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
    return registry_snapshot(root)[0]


def registry_snapshot(root):
    path = root / "registry.json"
    if not path.is_file():
        return {"schema": 1, "libraries": {}}, digest(b'')
    raw=path.read_bytes()
    value = json.loads(raw.decode('utf-8'))
    if value.get("schema") != 1 or not isinstance(value.get("libraries"), dict):
        fail("scientific library registry schema is invalid")
    return value, digest(raw)


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


CAPABILITY_NAMES = (
    'list_entries', 'entry_info', 'search_entries', 'read_entry', 'add_entry',
    'remove_entry', 'export_entry', 'verify', 'mutable', 'read_only', 'remote',
    'external', 'offline_available', 'authentication_required', 'library_viewer',
    'entry_viewer',
)


def provider_capabilities(provider, record=None):
    """Additive Step-2 declaration, preserving legacy managed-provider hooks.

    Status hooks describe known state; discovery does not probe a remote server
    or infer protocol, authentication, scientific meaning or permission.
    """
    module = provider['module']
    declared = getattr(module, 'LIBRARY_CAPABILITIES', {})
    if not isinstance(declared, dict):
        fail('provider LIBRARY_CAPABILITIES must be a dictionary')
    modes = declared.get('modes', ('managed',))
    if not isinstance(modes, (list, tuple)) or not modes or set(modes)-{'managed', 'external', 'remote'}:
        fail('provider capability modes must be managed/external/remote')
    extras = declared.get('extra_actions', {})
    if not isinstance(extras, dict) or len(extras)>32:
        fail('provider extra_actions must be a dictionary with at most 32 actions')
    unknown = set(declared)-set(CAPABILITY_NAMES)-{'modes', 'extra_actions'}
    if unknown:
        fail('unknown provider capability: '+', '.join(sorted(unknown)))
    out = dict(capability_schema='gxtxt.library_capabilities.v1',
               library_type=provider['library_type'], provider_id=provider['provider_id'],
               provider_version=provider['provider_version'], supported_modes=' '.join(modes),
               script_exposure='host_module_only; Script Bridge belongs to progression Step4')
    out['declaration_source']='provider_declaration' if declared else 'legacy_managed_contract'
    defaults = dict(list_entries=True, verify=callable(getattr(module, 'validate', None)),
                    read_only=True, offline_available=True,
                    library_viewer=bool(provider['library_viewer_module']),
                    entry_viewer=bool(provider['entry_viewer_module']),
                    external='external' in modes, remote='remote' in modes)
    for name in CAPABILITY_NAMES:
        value=declared.get(name, defaults.get(name, False))
        if type(value) is not bool:
            fail('provider capability '+name+' must be boolean')
        out['capability.'+name]=int(value)
    for action, spec in extras.items():
        safe_id(action)
        if action in {'open', 'entry_open', 'verify', 'install', 'update', 'remove', 'unregister', 'inspect', 'refresh'}:
            fail('provider extra action shadows a CORE library action')
        if not isinstance(spec, dict) or set(spec)-{'label', 'modes', 'requires_available', 'requires_authentication'}:
            fail('invalid provider extra action declaration')
        action_modes=spec.get('modes', modes)
        if not isinstance(action_modes, (list, tuple)) or not action_modes or set(action_modes)-set(modes):
            fail('extra action modes must be a subset of provider modes')
        label=spec.get('label', action)
        if not isinstance(label, str) or not 1<=len(label)<=160 or '\n' in label:
            fail('extra action label must be a bounded single line')
        out['extra.'+action+'.label']=label
        out['extra.'+action+'.modes']=' '.join(action_modes)
        for field in ('requires_available', 'requires_authentication'):
            value=spec.get(field, True)
            if type(value) is not bool:fail('extra action conditions must be boolean')
            out['extra.'+action+'.'+field]=int(value)
    out['extra_actions']=' '.join(extras)
    schema=provider['registration_schema']
    if not isinstance(schema,dict):fail('Provider registration schema must be a dictionary')
    for mode in ('external','remote'):
        specification=schema.get(mode,{})
        if not isinstance(specification,dict):fail('Provider registration mode schema must be a dictionary')
        for kind in ('required','optional'):
            fields=specification.get(kind,())
            if not isinstance(fields,(list,tuple)) or len(fields)>32 or any(not isinstance(name,str) or not SAFE.fullmatch(name) for name in fields):fail('Provider registration field schema is invalid')
            out[f'registration.{mode}.{kind}']=' '.join(fields)
    if record is None:
        return out
    info=public_info(record)
    status={key:info[key] for key in ('availability', 'read_only', 'authentication_required', 'authentication_status', 'entry_count') if key in info}
    if declared.get('authentication_required',False):
        status.update(authentication_required='1', authentication_status='unknown')
    # Step1 external/remote entry_count/auth defaults are registration metadata,
    # not a live provider observation. Report the distinction explicitly.
    out['status_source']='registration_metadata_not_probed'
    if record.get('mode', 'managed')!='managed':
        status['entry_count']='unknown'
        status.update(authentication_required=str(int(declared['authentication_required'])) if 'authentication_required' in declared else 'unknown', authentication_status='unknown')
    status_hook=getattr(module, 'library_status', None)
    if status_hook is not None:
        if not callable(status_hook):fail('library_status must be callable')
        observed=status_hook(dict(record), FRAMEWORK)
        if not isinstance(observed, dict) or set(observed)-{'availability', 'read_only', 'authentication_required', 'authentication_status', 'entry_count', 'reason'}:
            fail('library_status returned an invalid normalized status')
        status.update(observed);out['status_source']='provider_status'
    if status['availability'] not in {'available', 'unavailable', 'unknown', 'temporarily_unavailable'}:
        fail('invalid normalized library availability')
    for key in ('read_only', 'authentication_required'):
        if type(status[key]) is bool:status[key]=int(status[key])
        if str(status[key]) not in {'0','1','unknown'}:fail('invalid normalized '+key)
    if str(record.get('read_only','1'))=='1':status['read_only']='1'
    if status.get('entry_count','unknown')!='unknown' and (not str(status['entry_count']).isdigit()):
        fail('invalid normalized entry count')
    for key, value in status.items():out['status.'+key]=str(value)
    mode=info['mode'];supported=mode in modes
    out['mode']=mode;out['registry_state']=record.get('state','unknown')
    available=supported and status['availability']=='available'
    auth_ready=str(status['authentication_required'])=='0' or status['authentication_status'] in {'not_required', 'unlocked', 'authenticated'}
    active=record.get('state')=='installed'
    ready=active and available and auth_ready
    can_library=bool(out['capability.library_viewer']) and bool(provider['library_viewer_module'])
    can_entry=bool(out['capability.entry_viewer']) and bool(provider['entry_viewer_module'])
    actions=dict(inspect=active, refresh=True, update=active and mode=='managed',
                 remove=active and mode=='managed', unregister=active and mode in {'external','remote'},
                 verify=ready and mode=='managed' and bool(out['capability.verify']),
                 list_entries=ready and mode=='managed' and bool(out['capability.list_entries']),
                 open=ready and (can_library or (can_entry and mode=='managed' and int(record.get('entry_count',0))>0)),
                 entry_open=ready and (can_entry or can_library) and mode=='managed')
    reason=('Library was removed' if not active else 'Provider does not support this storage mode' if not supported else
            'Library availability is '+str(status['availability']) if not available else
            'Authentication state is '+str(status['authentication_status']) if not auth_ready else '')
    for action, enabled in actions.items():
        out['action.'+action]=int(enabled)
        out['reason.'+action]='' if enabled else reason or 'Capability or owned hook is unavailable'
    for action, spec in extras.items():
        enabled=active and supported and mode in spec.get('modes', modes) and callable(getattr(module, 'library_action', None))
        if spec.get('requires_available', True):enabled=enabled and available
        if spec.get('requires_authentication', True):enabled=enabled and auth_ready
        out['action.'+action]=int(enabled)
        out['reason.'+action]='' if enabled else reason or 'Provider action is not available in this mode'
    return out


def library_capabilities(library_id):
    registry, fingerprint=registry_snapshot(managed_root())
    record=registry['libraries'].get(safe_id(library_id))
    if not record:fail('unknown scientific library '+library_id)
    try:
        provider=select_provider(record['library_type'], record['provider_id'])
    except ValueError as exc:
        # Inspection of an actual registered resource remains possible when its
        # provider was uninstalled. A retained tombstone is still inactive:
        # provider absence must not revive its inspection/unregistration actions.
        mode=record.get('mode', 'managed')
        active=record.get('state')=='installed'
        unregister=active and mode in {'external','remote'}
        return dict(library_id=library_id, registry_sha256=fingerprint, capability_schema='gxtxt.library_capabilities.v1',
                    provider_id=record['provider_id'], mode=mode, registry_state=record.get('state','unknown'),
                    **{'status.availability':'unavailable', 'status.reason':str(exc),
                    'status_source':'provider_unavailable', 'action.inspect':int(active), 'action.refresh':1,
                    'action.unregister':int(unregister), 'reason.inspect':'' if active else 'Library was removed',
                    'reason.refresh':'', 'reason.unregister':'' if unregister else
                    ('Library was removed' if not active else 'Unregister is available only for external or remote libraries'),
                    'extra_actions':''})
    return dict(provider_capabilities(provider, record), library_id=library_id, registry_sha256=fingerprint)


def library_extra_action(library_id, action, parameters):
    record=require_installed(load_registry(managed_root()), library_id)
    provider=select_provider(record['library_type'], record['provider_id'])
    caps=provider_capabilities(provider, record)
    if action not in caps['extra_actions'].split() or not caps.get('action.'+action):
        fail(caps.get('reason.'+action, 'Unsupported library action'))
    if len(parameters)>32 or any(not SAFE.fullmatch(key) or len(value)>4096 for key,value in parameters.items()):
        fail('Provider action parameters exceed the normalized bounds')
    result=provider['module'].library_action(dict(record), action, parameters, FRAMEWORK)
    if not isinstance(result, dict) or len(result)>128 or any(not isinstance(key,str) or not isinstance(value,(str,int,float,bool)) for key,value in result.items()):
        fail('Provider action must return a bounded scalar information record')
    if len(json.dumps(result))>131072:fail('Provider action information exceeds 128 KiB')
    return dict(result, library_id=library_id, action=action, provider_id=provider['provider_id'])


def library_catalog_page(mode, query, offset, limit):
    if mode not in {'all','managed','external','remote'} or not 0<=offset or not 1<=limit<=200 or len(query)>1024:
        fail('Library catalog requires mode, bounded filter and offset/limit (1-200)')
    registry, fingerprint=registry_snapshot(managed_root())
    rows=[];needle=query.casefold().strip()
    for identifier, record in sorted(registry['libraries'].items()):
        if record.get('state')!='installed' or (mode!='all' and record.get('mode','managed')!=mode):continue
        searchable=' '.join(str(record.get(key,'')) for key in ('library_id','display_name','library_type','origin','provider_id'))
        if needle and needle not in searchable.casefold():continue
        rows.append(record)
    out=dict(schema='gxtxt.library_catalog_page.v1',registry_sha256=fingerprint,
             total=len(rows),offset=offset,limit=limit,mode=mode,query=query)
    selected=rows[offset:offset+limit];out['count']=len(selected)
    for index, record in enumerate(selected):
        info=public_info(record)
        if len(json.dumps(info))>131072:fail('Library public record exceeds the 128 KiB catalog inspection bound')
        for key,value in info.items():out[f'row.{index}.{key}']=value
    return out


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
    elif action == 'provider_capabilities' and len(args)==1:
        emit_info(provider_capabilities(select_provider(args[0])))
    elif action == 'library_capabilities' and len(args)==1:
        emit_info(library_capabilities(args[0]))
    elif action == 'library_action' and len(args)>=2 and len(args)%2==0:
        emit_info(library_extra_action(args[0],args[1],dict(zip(args[2::2],args[3::2]))))
    elif action == 'catalog_page' and len(args)==4:
        emit_info(library_catalog_page(args[0],args[1],int(args[2]),int(args[3])))
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
        if sys.argv[1:]==['--request']:
            # Same public manager, same F/L wire; the common Script Job owner
            # supplies asynchronous lifetime/cancellation for GUI consumers.
            import tkinter
            from gxtxt_job_supervisor import tcl_result, request_process_group
            request_process_group()
            interpreter=tkinter.Tcl();parts=interpreter.splitlist(sys.stdin.read(1048576))
            if len(parts)!=6:fail('Library request requires operation, arguments and current provider descriptors')
            request=dict(zip(parts[::2],parts[1::2]))
            if set(request)!={'operation','arguments','provider_descriptors'}:fail('Invalid Library request fields')
            os.environ['GXTXT_LIBRARY_PROVIDER_DESCRIPTORS']=os.pathsep.join(interpreter.splitlist(request['provider_descriptors']))
            allowed={'catalog_page','library_capabilities','provider_capabilities','library_action','info','entries','verify','install','update','remove','register','unregister','provider','types','open'}
            if request['operation'] not in allowed:fail('Unsupported asynchronous Library operation')
            try:
                captured=io.StringIO()
                with contextlib.redirect_stdout(captured):main([request['operation'],*interpreter.splitlist(request['arguments'])])
                print(tcl_result(dict(ok=1,result=dict(wire=captured.getvalue()))))
            except Exception as exc:
                print(tcl_result(dict(ok=0,error=str(exc),category='scientific_library_manager')))
                raise SystemExit(1)
        else:
            main(sys.argv[1:])
    except (ValueError, OSError, KeyError, zipfile.BadZipFile) as exc:
        print(f"GX-TXT Scientific Library Manager: {exc}", file=sys.stderr)
        raise SystemExit(1)
