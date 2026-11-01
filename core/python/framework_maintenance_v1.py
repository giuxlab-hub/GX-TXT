# SPDX-License-Identifier: GPL-3.0-or-later
"""Aggregate transport only; Project/Session Portable own scientific formats."""
import hashlib
import contextlib
import json
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile
import zipfile

import project_portable_v1 as project
import session_portable_v1 as session

FORMAT = "gxtxt.maintenance.backup.v1"
MANIFEST = "gxtxt-maintenance.json"
MAX_MANIFEST = 4 * 1024 * 1024


def read_json(path):
    path = Path(path)
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_MANIFEST:
        raise ValueError("Expected bounded regular maintenance JSON")
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("Duplicate maintenance JSON key")
            result[key] = value
        return result
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique)


def source_stamp(spec):
    """Verify whole-source stability; no writer permission or new serialization."""
    entries = []
    session_roots = [Path(p).resolve() for p in spec["sessions"]]
    excluded_roots = [Path(p).resolve() for p in spec.get("excluded_sessions", [])]
    for root in session_roots:
        directories, files, external = session.scan_session(root)
        entries.extend((str(root), "directory", str(path)) for path in directories)
        entries.extend((str(root), item.rel.as_posix(), item.sha256, item.size) for item in files)
        entries.extend((str(root), "external", p, kind) for p, kind in external)
        _, referenced = session.find_portable_acquisition_source(root, files)
        if referenced:
            path = Path(referenced).resolve(strict=True)
            before = path.stat()
            if not stat.S_ISREG(before.st_mode):
                raise ValueError("Referenced acquisition source is not a regular file")
            digest = session.sha256_file(path)
            after = path.stat()
            if file_identity(before) != file_identity(after):
                raise ValueError("Referenced acquisition source changed during inspection")
            entries.append((str(root), "external_acquisition", str(path), digest, after.st_size))
    for raw in spec["projects"]:
        root = Path(raw)
        if root.is_symlink() or not root.is_dir():
            raise ValueError("Project source is unavailable or linked")
        for path in sorted(root.rglob("*")):
            if any(path == child or child in path.parents for child in [*session_roots, *excluded_roots]):
                continue
            if path.is_symlink():
                raise ValueError("Project source contains a linked resource")
            if path.is_file():
                before = path.stat()
                digest = session.sha256_file(path)
                after = path.stat()
                if (before.st_ino, before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns):
                    raise ValueError("Project source changed during inspection")
                entries.append((str(root), path.relative_to(root).as_posix(), digest, after.st_size))
            elif path.is_dir():
                entries.append((str(root), "directory", path.relative_to(root).as_posix()))
    return hashlib.sha256(json.dumps(sorted(entries, key=lambda row: json.dumps(row, ensure_ascii=False)), ensure_ascii=False).encode()).hexdigest()


def file_identity(info):
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns


@contextlib.contextmanager
def snapshot_archive(raw):
    """Bind hash and validation/extraction to one stable regular-file snapshot."""
    path = Path(raw).absolute()
    flags = os.O_RDONLY | os.O_NONBLOCK | getattr(os, "O_NOFOLLOW", 0)
    with tempfile.TemporaryDirectory(prefix="gxtxt-maintenance-input-") as temporary:
        copy = Path(temporary) / "input.zip"
        with os.fdopen(os.open(path, flags), "rb") as incoming, copy.open("xb") as outgoing:
            before = os.fstat(incoming.fileno())
            if not stat.S_ISREG(before.st_mode) or before.st_size > 16 * 1024**4:
                raise ValueError("Backup input must be a regular archive within the transport bound")
            digest = hashlib.sha256()
            for block in iter(lambda: incoming.read(1024 * 1024), b""):
                digest.update(block)
                outgoing.write(block)
            after = os.fstat(incoming.fileno())
        if file_identity(before) != file_identity(after) or file_identity(after) != file_identity(path.lstat()):
            raise ValueError("Backup changed while taking a private inspection snapshot")
        yield copy, digest.hexdigest()


def validate(archive, extract=None):
    with tempfile.TemporaryDirectory(prefix="gxtxt-maintenance-check-") as temporary:
        staging = Path(temporary)
        with zipfile.ZipFile(archive) as source:
            members = {}
            for info in source.infolist():
                name = info.filename
                if name in members or session.zip_entry_is_symlink(info) or project.name(name) != name:
                    raise ValueError("Unsafe or duplicate maintenance package member")
                members[name] = info
            if not 1 <= len(members) <= 20002 or MANIFEST not in members or members[MANIFEST].file_size > MAX_MANIFEST:
                raise ValueError("Invalid maintenance package inventory")
            raw = staging / MANIFEST
            raw.write_bytes(source.read(MANIFEST))
            manifest = read_json(raw)
            if manifest.get("schema") != FORMAT or manifest.get("orphan_policy") not in ("include", "exclude"):
                raise ValueError("Unsupported backup schema or orphan policy")
            records = manifest["packages"]
            if len(records) > 20000 or set(members) != {MANIFEST, *(r["archive"] for r in records)}:
                raise ValueError("Backup manifest does not match its members")
            seen = set()
            for ordinal, record in enumerate(records):
                kind = record["kind"]
                if kind == "orphan_session" and manifest["orphan_policy"] != "include":
                    raise ValueError("Excluded unassociated Session is present in backup payload")
                if kind not in ("project", "orphan_session") or record["archive"] != f"packages/{ordinal}.zip":
                    raise ValueError("Invalid nested package identity")
                identity = (kind, record["source_id"])
                if not record["source_id"] or identity in seen:
                    raise ValueError("Duplicate source identity in backup")
                seen.add(identity)
                info = members[record["archive"]]
                if info.file_size != record["bytes"] or info.file_size > 16 * 1024**4:
                    raise ValueError("Nested package size differs or exceeds the transport bound")
                target = staging / record["archive"]
                target.parent.mkdir(exist_ok=True)
                digest = hashlib.sha256()
                with source.open(info) as incoming, target.open("xb") as outgoing:
                    for block in iter(lambda: incoming.read(1024 * 1024), b""):
                        digest.update(block)
                        outgoing.write(block)
                if digest.hexdigest() != record["sha256"]:
                    raise ValueError("Nested package checksum differs")
                if kind == "project":
                    nested = project.validate(target)
                    # The explicit orphan policy also applies to Sessions
                    # physically below Project resources, without duplicate
                    # raw copies escaping their Session Portable mappings.
                    known_orphans = [r["source_path"] for r in records if r["kind"] == "orphan_session"] if manifest["orphan_policy"] == "include" else [r["path"] for r in manifest.get("excluded_orphans", [])]
                    session_parent = Path(record["source_path"]) / "Sessions"
                    expected_omissions = sorted("Sessions/" + Path(p).name for p in known_orphans if Path(p).parent == session_parent)
                    if sorted(nested.get("excluded_unassociated_sessions", [])) != expected_omissions:
                        raise ValueError("Project resources disagree with the aggregate orphan policy")
                    if nested["source_project_id"] != record["source_id"]:
                        raise ValueError("Nested Project identity differs")
                    declared = {r["source_experiment_id"]: r for r in nested["sessions"]}
                    outer = record["sessions"]
                    if len(outer) != len(declared) or len({r["experiment_id"] for r in outer}) != len(outer) or set(declared) != {r["experiment_id"] for r in outer}:
                        raise ValueError("Backup Project/Session mapping differs")
                    with zipfile.ZipFile(target) as project_zip:
                        transfer_path = staging / "transfer-check.ini"
                        transfer_path.write_bytes(project_zip.read("source/transfer.ini"))
                        transfer = session.simple_ini(transfer_path)
                    if record["source_path"] != transfer["project"]["storage_path"] or record["name"] != transfer["project"]["name"]:
                        raise ValueError("Backup outer Project source differs from its owner package")
                    by_id = {r["experiment_id"]: r for key, r in transfer.items() if key.startswith("experiment.")}
                    for row in outer:
                        original = by_id[row["experiment_id"]]
                        if any(str(row.get(key, "")) != str(original.get(key, "")) for key in original):
                            raise ValueError("Backup associated Session metadata differs from the Portable owner")
                else:
                    session.validate_archive(target)
                    if len(record["sessions"]) != 1:
                        raise ValueError("An unassociated Session needs one exact source mapping")
                    row = record["sessions"][0]
                    with zipfile.ZipFile(target) as nested_zip:
                        manifest_path = staging / "orphan-check.ini"
                        manifest_path.write_bytes(nested_zip.read("session/metadata/manifest.ini"))
                        link = session.simple_ini(manifest_path).get("project_link", {})
                    if record["source_id"] != record["source_path"] or row["path"] != record["source_path"] or row["name"] != record["name"] or row.get("source_project_id", "") != link.get("project_id", "") or row.get("source_experiment_id", "") != link.get("experiment_id", ""):
                        raise ValueError("Backup unassociated Session identity differs from its owner package")
            # Check-only files are not part of the verified transport extraction.
            for name in ("transfer-check.ini", "orphan-check.ini"):
                (staging / name).unlink(missing_ok=True)
        if extract is not None:
            destination = Path(extract)
            if destination.exists():
                raise ValueError("Backup extraction destination exists")
            shutil.copytree(staging, destination)
        return manifest


def pack(spec_path, destination):
    spec = read_json(spec_path)
    destination = Path(destination)
    if destination.exists() or destination.is_symlink():
        raise ValueError("Backup destination already exists")
    stage = Path(spec_path).parent
    manifest = dict(spec)
    for ordinal, record in enumerate(manifest["packages"]):
        archive = stage / f"{ordinal}.zip"
        if archive.is_symlink() or not archive.is_file():
            raise ValueError("Nested package is unavailable")
        record.update(archive=f"packages/{ordinal}.zip", bytes=archive.stat().st_size, sha256=session.sha256_file(archive))
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, raw = tempfile.mkstemp(prefix=".gxtxt-maintenance-", dir=destination.parent)
    os.close(fd)
    temporary = Path(raw)
    try:
        with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as output:
            output.writestr(MANIFEST, json.dumps(manifest, sort_keys=True, ensure_ascii=False))
            for ordinal, record in enumerate(manifest["packages"]):
                output.write(stage / f"{ordinal}.zip", record["archive"])
        validate(temporary)
        digest = session.sha256_file(temporary)
        # Publication is exclusive even if another process wins after preview.
        os.link(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)
    return manifest, digest


def main():
    operation, *arguments = sys.argv[1:]
    if operation == "stamp":
        session.emit({"stamp": source_stamp(read_json(arguments[0]))})
        return
    if operation == "pack":
        manifest, digest = pack(*arguments)
        archive = Path(arguments[1])
    elif operation in ("validate", "extract"):
        archive = Path(arguments[0])
        with snapshot_archive(archive) as (snapshot, digest):
            manifest = validate(snapshot, arguments[1] if operation == "extract" else None)
    else:
        raise ValueError("Unknown maintenance transport operation")
    session.emit({"archive": str(archive), "sha256": digest,
                  "manifest_json": json.dumps(manifest, ensure_ascii=True, separators=(",", ":"))})


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("Maintenance transport failed: " + str(error), file=sys.stderr)
        sys.exit(1)
