#!/usr/bin/env python3
"""Generic CORE registry and managed lifecycle for scientific libraries."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import base64
import configparser
import contextlib
import datetime as dt
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import zipfile

if os.name == "nt":
    import msvcrt
else:
    import fcntl


FRAMEWORK = Path(__file__).resolve().parents[2]
SAFE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
VERSION = re.compile(r"^[0-9]+(?:\.[0-9]+){1,3}$")
PACKAGE_FILES = {"library.ini", "SHA256SUMS.txt", "payload/library.gxsrl"}


def fail(message):
    raise ValueError(message)


def safe_id(value):
    if not SAFE.fullmatch(value) or value in (".", ".."):
        fail(f"invalid scientific library identifier: {value!r}")
    return value


def managed_root():
    configured = os.environ.get("GXTXT_SCIENTIFIC_LIBRARY_ROOT")
    if configured:
        return Path(configured).expanduser().resolve()
    data = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(data).resolve() / "gxtxt_pipeline" / "scientific_libraries"


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def load_registry(root):
    path = root / "registry.json"
    if not path.is_file():
        return {"schema": 1, "libraries": {}}
    value = json.loads(path.read_text(encoding="utf-8"))
    if value.get("schema") != 1 or not isinstance(value.get("libraries"), dict):
        fail("scientific library registry schema is invalid")
    return value


def save_registry(root, value):
    root.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".registry-", suffix=".json", dir=root)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(value, stream, ensure_ascii=False, sort_keys=True, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, root / "registry.json")
    finally:
        Path(temporary).unlink(missing_ok=True)


@contextlib.contextmanager
def locked(root):
    root.mkdir(parents=True, exist_ok=True)
    with (root / ".registry.lock").open("a+b") as stream:
        if os.name == "nt":
            # msvcrt locks a byte range at the current file position. Keep a
            # permanent byte so concurrent installers serialize on Windows.
            stream.seek(0, os.SEEK_END)
            if stream.tell() == 0:
                stream.write(b"\0")
                stream.flush()
            stream.seek(0)
            msvcrt.locking(stream.fileno(), msvcrt.LK_LOCK, 1)
            try:
                yield
            finally:
                stream.seek(0)
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            fcntl.flock(stream, fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(stream, fcntl.LOCK_UN)


def provider_descriptors():
    # The Tcl host supplies its loaded module catalog, which includes installed
    # provider plugins. An explicit empty catalog means no providers are loaded.
    supplied = os.environ.get("GXTXT_LIBRARY_PROVIDER_DESCRIPTORS")
    if supplied is not None:
        return sorted(Path(item) for item in supplied.split(os.pathsep) if item)
    # Retain direct helper invocation for legacy CLI consumers.
    return sorted((FRAMEWORK / "plugins" / "modules").glob("*/module.ini"))


def providers():
    found = {}
    for descriptor_path in provider_descriptors():
        parser = configparser.ConfigParser(interpolation=None, strict=False)
        parser.read(descriptor_path, encoding="utf-8")
        if not parser.has_section("library_type_provider"):
            continue
        module_id = parser.get("meta", "id", fallback="")
        if module_id != descriptor_path.parent.name:
            fail(f"library provider module ID mismatch: {descriptor_path}")
        library_type = safe_id(parser.get("library_type_provider", "library_type"))
        entrypoint = parser.get("library_type_provider", "entrypoint")
        relative = Path(entrypoint)
        if relative.is_absolute() or ".." in relative.parts or relative.suffix != ".py":
            fail(f"unsafe scientific library provider entrypoint: {entrypoint}")
        source = descriptor_path.parent / relative
        if not source.is_file():
            fail(f"scientific library provider entrypoint is missing: {source}")
        if library_type in found:
            fail(f"multiple scientific library providers registered for {library_type}")
        spec = importlib.util.spec_from_file_location(f"gxtxt_library_provider_{len(found)}", source)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        if module.LIBRARY_TYPE != library_type:
            fail(f"provider implementation type mismatch: {module_id}")
        viewer_module = parser.get("library_type_provider", "entry_viewer_module", fallback="").strip()
        viewer_id = parser.get("library_type_provider", "entry_viewer_id", fallback="").strip()
        library_viewer_module = parser.get("library_type_provider", "library_viewer_module", fallback="").strip()
        library_viewer_id = parser.get("library_type_provider", "library_viewer_id", fallback="").strip()
        if bool(viewer_module) != bool(viewer_id):
            fail(f"scientific library provider {module_id} must declare both entry viewer fields")
        if bool(library_viewer_module) != bool(library_viewer_id):
            fail(f"scientific library provider {module_id} must declare both library viewer fields")
        if viewer_module:
            safe_id(viewer_module)
            safe_id(viewer_id)
        if library_viewer_module:
            safe_id(library_viewer_module)
            safe_id(library_viewer_id)
        found[library_type] = {"library_type": library_type, "provider_id": module_id,
                               "provider_version": parser.get("meta", "version"),
                               "module": module,
                               "registration_schema": getattr(module, "REGISTRATION_SCHEMA", {}),
                               "entry_viewer_module": viewer_module,
                               "entry_viewer_id": viewer_id,
                               "library_viewer_module": library_viewer_module,
                               "library_viewer_id": library_viewer_id}
    return found


def read_package(path):
    package_path = Path(path).resolve()
    if not package_path.is_file():
        fail(f"scientific library package is missing: {package_path}")
    with zipfile.ZipFile(package_path) as archive:
        infos = archive.infolist()
        names = [item.filename for item in infos]
        if len(names) != len(PACKAGE_FILES) or set(names) != PACKAGE_FILES:
            fail("scientific library package has missing, extra or unsafe paths")
        for item in infos:
            if item.is_dir() or (item.external_attr >> 16) & 0o170000 == 0o120000:
                fail("scientific library package contains a link or directory")
            if item.file_size > 500_000_000:
                fail("scientific library package payload exceeds the supported limit")
        descriptor = archive.read("library.ini")
        checksums = archive.read("SHA256SUMS.txt").decode("utf-8")
        payload = archive.read("payload/library.gxsrl")
    if checksums.strip() != f"{digest(payload)}  payload/library.gxsrl":
        fail("scientific library package checksum mismatch")
    parser = configparser.ConfigParser(interpolation=None, strict=True)
    parser.read_file(io.StringIO(descriptor.decode("utf-8")))
    if not parser.has_section("library"):
        fail("scientific library package manifest is missing [library]")
    manifest = dict(parser.items("library"))
    required = ("library_id", "library_type", "version", "provider_id", "format_version",
                "display_name", "description", "license", "origin")
    for key in required:
        if not manifest.get(key):
            fail(f"scientific library package manifest is missing {key}")
    for key in ("library_id", "library_type", "provider_id"):
        safe_id(manifest[key])
    if not VERSION.fullmatch(manifest["version"]):
        fail("scientific library package version is invalid")
    manifest["package_sha256"] = digest(package_path.read_bytes())
    manifest["payload_sha256"] = digest(payload)
    return manifest, payload


def storage_path(root, record):
    reference = Path(record["storage_ref"])
    if reference.is_absolute() or ".." in reference.parts:
        fail("scientific library registry storage reference is unsafe")
    path = (root / reference).resolve()
    if not path.is_relative_to(root.resolve()):
        fail("scientific library registry storage escaped managed root")
    return path


def public_info(record):
    info = {key: value for key, value in record.items()
            if key not in ("storage_ref", "package_ref", "entry_ids")}
    if record.get("state") == "installed" and record.get("storage_ref"):
        info["managed_storage_location"] = str(storage_path(managed_root(), record))
    # Historic schema-1 records remain valid without a registry migration.
    info.setdefault("mode", "managed")
    info.setdefault("availability", "available" if record.get("state") == "installed" else "unavailable")
    info.setdefault("rights", "")
    info.setdefault("read_only", "1")
    info.setdefault("authentication_required", "0")
    info.setdefault("authentication_status", "not_required")
    info["provider_config"] = json.dumps(record.get("provider_config", {}), sort_keys=True)
    return info


def require_managed(record, operation):
    if record.get("mode", "managed") != "managed":
        fail(f"{operation} is available only for managed libraries")
    return record


def register(fields):
    allowed = {"library_id", "library_type", "display_name", "mode", "version",
               "origin", "license", "rights", "read_only", "availability", "description"}
    unknown = set(fields) - allowed - {key for key in fields if key.startswith("config.")}
    if unknown:
        fail(f"unknown library registration fields: {', '.join(sorted(unknown))}")
    library_id = safe_id(fields.get("library_id", ""))
    library_type = safe_id(fields.get("library_type", ""))
    mode = fields.get("mode")
    if mode not in ("external", "remote"):
        fail("registerLibrary requires mode external or remote")
    if not fields.get("display_name"):
        fail("library registration requires display_name")
    provider = select_provider(library_type)
    configuration = {}
    for key, value in fields.items():
        if not key.startswith("config."):
            continue
        name = safe_id(key[7:])
        if re.search(r"secret|password|token|api[_-]?key|credential", name, re.I):
            fail("secrets are not allowed in provider registration configuration")
        configuration[name] = value
    schema = provider["registration_schema"]
    if not isinstance(schema, dict):
        fail("provider registration schema must be a dictionary")
    mode_schema = schema.get(mode, {})
    if not isinstance(mode_schema, dict):
        fail("provider registration mode schema must be a dictionary")
    required = set(mode_schema.get("required", ()))
    optional = set(mode_schema.get("optional", ()))
    if any(not SAFE.fullmatch(key) for key in required | optional):
        fail("provider registration schema contains an invalid field")
    if required - set(configuration):
        fail(f"provider registration requires: {', '.join(sorted(required - set(configuration)))}")
    if mode_schema and set(configuration) - required - optional:
        fail("provider registration contains undeclared configuration fields")
    validate = getattr(provider["module"], "validate_registration", None)
    if validate is not None:
        validate(mode, configuration)
    root = managed_root()
    with locked(root):
        registry = load_registry(root)
        previous = registry["libraries"].get(library_id)
        if previous:
            fail(f"scientific library ID {library_id} already has a registry record")
        record = {"library_id": library_id, "library_type": library_type,
                  "display_name": fields["display_name"], "mode": mode,
                  "provider_id": provider["provider_id"],
                  "provider_version": provider["provider_version"],
                  "version": fields.get("version", ""), "state": "installed",
                  "availability": fields.get("availability", "unknown"),
                  "origin": fields.get("origin", ""), "license": fields.get("license", ""),
                  "rights": fields.get("rights", ""), "description": fields.get("description", ""),
                  "read_only": fields.get("read_only", "1"),
                  "authentication_required": "0", "authentication_status": "not_required",
                  "provider_config": configuration, "entry_count": 0,
                  "installed_at": now(), "updated_at": now()}
        if record["read_only"] not in ("0", "1"):
            fail("read_only must be 0 or 1")
        registry["libraries"][library_id] = record
        save_registry(root, registry)
    return public_info(record)


def unregister(library_id):
    root = managed_root()
    with locked(root):
        registry = load_registry(root)
        record = require_installed(registry, library_id)
        if record.get("mode", "managed") == "managed":
            fail("managed libraries use removeLibrary")
        tombstone = dict(record, state="removed", availability="unavailable", removed_at=now())
        registry["libraries"][library_id] = tombstone
        save_registry(root, registry)
    return public_info(tombstone)


def require_installed(registry, library_id):
    safe_id(library_id)
    record = registry["libraries"].get(library_id)
    if not record:
        fail(f"scientific library {library_id} is not installed")
    if record["state"] != "installed":
        fail(f"scientific library {library_id} was removed; saved references are stale")
    return record


def select_provider(library_type, provider_id=None):
    provider = providers().get(library_type)
    if not provider:
        fail(f"no Library Type Provider is installed for {library_type}")
    if provider_id and provider["provider_id"] != provider_id:
        fail(f"scientific library requires provider {provider_id}, but {provider['provider_id']} is installed")
    return provider


def install_or_update(command, package_path, expected_id=None):
    root = managed_root()
    manifest, payload = read_package(package_path)
    provider = select_provider(manifest["library_type"], manifest["provider_id"])
    library_id = manifest["library_id"]
    if expected_id is not None and library_id != safe_id(expected_id):
        fail(f"scientific library update package ID {library_id} does not match {expected_id}")
    with locked(root):
        registry = load_registry(root)
        previous = registry["libraries"].get(library_id)
        if command == "install" and previous and previous["state"] == "installed":
            fail(f"scientific library {library_id} is already installed")
        if command == "update":
            previous = require_managed(require_installed(registry, library_id), "updateLibrary")
            if previous["library_type"] != manifest["library_type"] or previous["provider_id"] != manifest["provider_id"]:
                fail("scientific library update changes its provider or library type")
            old_version = tuple(int(v) for v in previous["version"].split("."))
            new_version = tuple(int(v) for v in manifest["version"].split("."))
            if new_version <= old_version:
                fail("scientific library update version must increase")
        with tempfile.TemporaryDirectory(prefix=".install-", dir=root) as temporary:
            staged = Path(temporary) / "library.gxsrl"
            staged.write_bytes(payload)
            domain = provider["module"].validate(staged, manifest, FRAMEWORK)
            entry_ids = domain.get("entry_ids")
            if not isinstance(entry_ids, list) or not entry_ids:
                fail("Library Type Provider returned no stable entries")
            if command == "update" and not set(previous["entry_ids"]).issubset(entry_ids):
                fail("scientific library update removes stable entry IDs")
            version_root = root / "payloads" / library_id / manifest["version"]
            if version_root.exists():
                fail("managed scientific library version already exists")
            version_root.mkdir(parents=True)
            target = version_root / "library.gxsrl"
            package_copy = version_root / "package.zip"
            try:
                os.replace(staged, target)
                shutil.copyfile(package_path, package_copy)
                record = {
                    "library_id": library_id, "library_type": manifest["library_type"],
                    "version": manifest["version"], "provider_id": provider["provider_id"],
                    "provider_version": provider["provider_version"], "state": "installed",
                    "mode": "managed", "availability": "available", "read_only": "1",
                    "rights": "", "authentication_required": "0",
                    "authentication_status": "not_required", "provider_config": {},
                    "origin": manifest["origin"], "display_name": manifest["display_name"],
                    "description": manifest["description"], "license": manifest["license"],
                    "format_version": manifest["format_version"],
                    "package_sha256": manifest["package_sha256"],
                    "payload_sha256": manifest["payload_sha256"],
                    "installed_at": previous.get("installed_at", now()) if previous else now(),
                    "updated_at": now(), "storage_ref": str(target.relative_to(root)),
                    "package_ref": str(package_copy.relative_to(root)),
                    "entry_count": len(entry_ids), "entry_ids": entry_ids,
                }
                old_target = storage_path(root, previous) if previous and previous["state"] == "installed" else None
                provider["module"].activate(target, old_target, library_id)
                registry["libraries"][library_id] = record
                try:
                    save_registry(root, registry)
                except Exception:
                    provider["module"].rollback_activate(old_target, library_id)
                    raise
            except Exception:
                shutil.rmtree(version_root, ignore_errors=True)
                raise
        return public_info(record)


def remove(library_id):
    root = managed_root()
    with locked(root):
        registry = load_registry(root)
        record = require_managed(require_installed(registry, library_id), "removeLibrary")
        provider = select_provider(record["library_type"], record["provider_id"])
        target = storage_path(root, record)
        provider["module"].deactivate(target, library_id)
        tombstone = dict(record, state="removed", removed_at=now(), storage_ref="", package_ref="")
        registry["libraries"][library_id] = tombstone
        try:
            save_registry(root, registry)
        except Exception:
            provider["module"].activate(target, None, library_id)
            raise
        directory = root / "payloads" / library_id
        if directory.is_dir() and directory.resolve().is_relative_to((root / "payloads").resolve()):
            shutil.rmtree(directory)
        return public_info(tombstone)


def verify(library_id):
    root = managed_root()
    record = require_managed(require_installed(load_registry(root), library_id), "verifyLibrary")
    payload = storage_path(root, record)
    package = storage_path(root, dict(storage_ref=record["package_ref"]))
    if digest(payload.read_bytes()) != record["payload_sha256"]:
        fail("installed scientific library payload checksum mismatch")
    if digest(package.read_bytes()) != record["package_sha256"]:
        fail("installed scientific library package checksum mismatch")
    provider = select_provider(record["library_type"], record["provider_id"])
    checked = provider["module"].validate(payload, record, FRAMEWORK)
    if checked["entry_ids"] != record["entry_ids"]:
        fail("installed scientific library entry index changed")
    return dict(public_info(record), verified_at=now())


def b64(value):
    return base64.b64encode(str(value).encode("utf-8")).decode("ascii")


def emit_info(info):
    for key, value in info.items():
        print(f"F\t{b64(key)}\t{b64(value)}")


def emit_list(values):
    for value in values:
        print(f"L\t{b64(value)}")


def main(argv):
    if not argv:
        fail("missing Scientific Library Manager operation")
    action, *args = argv
    root = managed_root()
    if action == "types" and not args:
        emit_list(providers().keys())
    elif action == "root" and not args:
        print(root)
    elif action == "provider" and len(args) == 1:
        p = select_provider(args[0])
        emit_info({key: value for key, value in p.items() if key not in ("module", "registration_schema")})
    elif action == "list" and not args:
        emit_list(sorted(library_id for library_id, record in load_registry(root)["libraries"].items()
                         if record["state"] == "installed" and record.get("mode", "managed") == "managed"))
    elif action == "registered" and not args:
        emit_list(sorted(library_id for library_id, record in load_registry(root)["libraries"].items()
                         if record["state"] == "installed"))
    elif action == "info" and len(args) == 1:
        record = load_registry(root)["libraries"].get(safe_id(args[0]))
        if not record:
            fail(f"unknown scientific library {args[0]}")
        emit_info(public_info(record))
    elif action == "compatible" and len(args) == 1:
        safe_id(args[0])
        emit_list(sorted(library_id for library_id, record in load_registry(root)["libraries"].items()
                         if record["state"] == "installed" and record["library_type"] == args[0]))
    elif action == "install" and len(args) == 1:
        emit_info(install_or_update(action, args[0]))
    elif action == "register" and len(args) >= 2 and len(args) % 2 == 0:
        emit_info(register(dict(zip(args[::2], args[1::2]))))
    elif action == "unregister" and len(args) == 1:
        emit_info(unregister(args[0]))
    elif action == "update" and len(args) == 2:
        emit_info(install_or_update(action, args[1], args[0]))
    elif action == "remove" and len(args) == 1:
        emit_info(remove(args[0]))
    elif action == "verify" and len(args) == 1:
        emit_info(verify(args[0]))
    elif action == "open" and len(args) == 1:
        record = require_installed(load_registry(root), args[0])
        emit_info({"library_id": record["library_id"], "library_type": record["library_type"],
                   "version": record["version"], "provider_id": record["provider_id"]})
    elif action == "entries" and len(args) == 1:
        record = require_managed(require_installed(load_registry(root), args[0]), "listLibraryEntries")
        emit_list(record["entry_ids"])
    elif action == "spectrum" and len(args) == 2:
        record = require_managed(require_installed(load_registry(root), args[0]), "readLibrarySpectrum")
        if args[1] not in record["entry_ids"]:
            fail(f"scientific library {args[0]} has no entry {args[1]}")
        provider = select_provider(record["library_type"], record["provider_id"])
        spectrum = provider["module"].read_spectrum(storage_path(root, record), args[1])
        fields = {key: value for key, value in spectrum.items() if key not in ("x", "y", "metadata", "provenance")}
        emit_info(fields)
        for key, value in spectrum.get("metadata", {}).items():
            print(f"M\t{b64(key)}\t{b64(value)}")
        for key, value in spectrum.get("provenance", {}).items():
            print(f"P\t{b64(key)}\t{b64(value)}")
        for x, y in zip(spectrum["x"], spectrum["y"]):
            print(f"D\t{x:.17g}\t{y:.17g}")
    else:
        fail(f"unknown or invalid Scientific Library Manager operation: {action}")


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (ValueError, OSError, KeyError, zipfile.BadZipFile) as exc:
        print(f"GX-TXT Scientific Library Manager: {exc}", file=sys.stderr)
        raise SystemExit(1)
