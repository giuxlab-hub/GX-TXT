"""Bounded non-executable source-owner authoring attachments.

The existing Registry/C++ owner holds its lock and checks its metadata revision
before calling prepare/import_payload. This helper writes immutable snapshots
only; the owner alone commits the returned pointer in its existing metadata.
No CLI, source execution, Dataset links, Registry or metadata writer lives here.

read returns {pointer, manifest, notes, blobs}; notes maps stable file keys to
text and blobs maps content SHA to bounded PNG bytes. The v1 format remains
exact for plain notes; only image-bearing revisions use the v2 schema.
file_note returns the active source's text or None for an uncreated note.
export_payload returns manifest.json plus declared notes/KEY.md and blobs/SHA.png;
the existing portable owner chooses its package prefix. import_payload requires
the imported source descriptors to match and creates fresh owner/file keys.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import copy
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import uuid
import source_asset_codec_v1 as assets

SCHEMA = "gxtxt.source_authoring.v1"
SCHEMA_V2 = "gxtxt.source_authoring.v2"
MAX_FILES = 256
MAX_NOTES = 256
MAX_NOTE_BYTES = 4 * 1024 * 1024
MAX_TOTAL_BYTES = 16 * 1024 * 1024
MAX_MANIFEST_BYTES = 1024 * 1024
FILE_MODE = 0o444
DIR_MODE = 0o700
_HEX32 = re.compile(r"[0-9a-f]{32}\Z")
_HEX64 = re.compile(r"[0-9a-f]{64}\Z")
_EXTENSIONS = {"python": {".py"}, "octave": {".m"},
               "cpp": {".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx"}}


class AuthoringError(ValueError):
    """The source owner must preserve its old metadata/pointer on this error."""


def _require(test, message):
    if not test:
        raise AuthoringError(message)


def _sha(value):
    return hashlib.sha256(value).hexdigest()


def _json(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True,
                       separators=(",", ":")) + "\n").encode("utf-8")


def _relative(value):
    _require(isinstance(value, str) and 0 < len(value) <= 240
             and "\\" not in value and ":" not in value
             and not any(ord(c) < 32 for c in value), "Invalid source-relative path")
    path = PurePosixPath(value)
    _require(not path.is_absolute() and path.as_posix() == value
             and all(re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.-]*", p)
                     and p not in {".", ".."} for p in path.parts),
             "Source path must be a normalized portable relative identifier")
    return value


def _language(value):
    _require(isinstance(value, str), "Source language must be text")
    aliases = {"Python": "python", "Octave": "octave", "C++": "cpp", "c++": "cpp"}
    value = aliases.get(value, value)
    _require(value in _EXTENSIONS, "Unsupported source language")
    return value


def _source_files(values):
    _require(isinstance(values, dict) and 1 <= len(values) <= MAX_FILES,
             "Source descriptors require1..256 files")
    result = {}; prefixes = {}
    for relative, descriptor in sorted(values.items()):
        _relative(relative)
        _require(isinstance(descriptor, dict)
                 and set(descriptor) == {"language", "source_sha256"},
                 "Source descriptor requires language and source_sha256 only")
        language = _language(descriptor["language"])
        _require(PurePosixPath(relative).suffix in _EXTENSIONS[language],
                 "Authoring source is not a declared language source/header")
        _require(isinstance(descriptor["source_sha256"], str)
                 and _HEX64.fullmatch(descriptor["source_sha256"]), "Invalid source SHA256")
        parts = PurePosixPath(relative).parts
        for index in range(1, len(parts) + 1):
            prefix = "/".join(parts[:index]); folded = prefix.casefold()
            _require(folded not in prefixes or prefixes[folded] == prefix,
                     "Case-colliding source path/directory")
            prefixes[folded] = prefix
        result[relative] = {"language": language, "source_sha256": descriptor["source_sha256"]}
    _require(all(not any(str(parent) in result for parent in PurePosixPath(name).parents
                         if str(parent) != ".") for name in result), "Source file/directory collision")
    return result


def _root(root):
    root = Path(os.path.abspath(root))
    for path in [*reversed(root.parents), root]:
        _require(not path.is_symlink(), "Linked authoring root/ancestor")
    _require(root.is_dir(), "Existing source-owner root required")
    return root


def _directory(path):
    state = path.lstat()
    _require(stat.S_ISDIR(state.st_mode) and stat.S_IMODE(state.st_mode) == DIR_MODE,
             "Authoring directory must be ordinary mode0700")


def _file(path, maximum):
    state = path.lstat()
    _require(stat.S_ISREG(state.st_mode) and state.st_nlink == 1
             and stat.S_IMODE(state.st_mode) == FILE_MODE and state.st_size <= maximum,
             "Authoring member must be bounded unlinked regular mode0444")
    with path.open("rb") as stream:
        before = os.fstat(stream.fileno()); value = stream.read(maximum + 1); after = os.fstat(stream.fileno())
    keys = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns, s.st_nlink, s.st_mode)
    _require(keys(state) == keys(before) == keys(after) and len(value) <= maximum,
             "Authoring member changed while reading")
    return value


def _text(value):
    _require(isinstance(value, bytes) and len(value) <= MAX_NOTE_BYTES,
             "Markdown note exceeds4MiB")
    try:
        text = value.decode("utf-8", errors="strict")
    except UnicodeError as error:
        raise AuthoringError("Markdown note must be valid UTF-8") from error
    _require("\0" not in text, "Markdown note contains NUL")
    return text


def _pointer(pointer):
    _require(isinstance(pointer, dict) and set(pointer) == {"schema", "owner_key", "revision"}
             and pointer["schema"] in {SCHEMA, SCHEMA_V2} and isinstance(pointer["owner_key"], str)
             and _HEX32.fullmatch(pointer["owner_key"]) and isinstance(pointer["revision"], str)
             and _HEX64.fullmatch(pointer["revision"]), "Invalid source-authoring pointer")
    return dict(pointer)


def _origin(origin, file=False):
    fields = {"owner_key", "file_key", "relative"} if file else {"owner_key", "revision"}
    _require(isinstance(origin, dict) and set(origin) == fields
             and isinstance(origin["owner_key"], str) and _HEX32.fullmatch(origin["owner_key"]),
             "Invalid authoring origin lineage")
    if file:
        _require(isinstance(origin["file_key"], str) and _HEX32.fullmatch(origin["file_key"]), "Invalid origin file key")
        _relative(origin["relative"])
    else:
        _require(isinstance(origin["revision"], str) and _HEX64.fullmatch(origin["revision"]), "Invalid origin revision")


def _validated_payload(payload, pointer=None):
    _require(isinstance(payload, dict) and "manifest.json" in payload
             and 1 <= len(payload) <= MAX_NOTES + assets.MAX_ASSETS + 1
             and all(isinstance(n, str) and isinstance(v, bytes) for n, v in payload.items()),
             "Bounded exact authoring byte payload required")
    _require(sum(len(v) for v in payload.values()) <= MAX_TOTAL_BYTES + MAX_MANIFEST_BYTES,
             "Portable authoring payload exceeds aggregate byte bound")
    raw = payload["manifest.json"]
    _require(len(raw) <= MAX_MANIFEST_BYTES, "Authoring manifest exceeds bound")
    try:
        manifest = assets.loads(raw)
    except (UnicodeError, json.JSONDecodeError) as error:
        raise AuthoringError("Invalid authoring manifest JSON") from error
    _require(isinstance(manifest, dict) and set(manifest) in (
        {"schema", "owner_key", "files", "detached"},
        {"schema", "owner_key", "files", "detached", "origin"})
        and manifest["schema"] in {SCHEMA, SCHEMA_V2} and isinstance(manifest["owner_key"], str)
        and _HEX32.fullmatch(manifest["owner_key"]), "Unknown authoring manifest fields/identity")
    _require(_json(manifest) == raw, "Authoring manifest must use canonical exact JSON")
    actual_pointer = {"schema": manifest["schema"], "owner_key": manifest["owner_key"], "revision": _sha(raw)}
    if pointer is not None:
        _require(actual_pointer == _pointer(pointer), "Authoring pointer/manifest digest differs")
    if "origin" in manifest:
        _origin(manifest["origin"])
    _require(isinstance(manifest["files"], dict) and 1 <= len(manifest["files"]) <= MAX_FILES
             and isinstance(manifest["detached"], dict) and len(manifest["detached"]) <= MAX_NOTES,
             "Authoring file/detached inventory exceeds bound")
    descriptors = {}; seen = set(); expected = {"manifest.json"}; notes = {}; total = 0; blobs = {}
    for detached, records in ((False, manifest["files"]), (True, manifest["detached"])):
        for name, record in records.items():
            fields = {"file_key", "language", "source_sha256", "note"} | ({"relative"} if detached else set())
            admitted = [fields, fields | {"origin"}]
            if manifest['schema'] == SCHEMA_V2:
                admitted += [fields | {'assets'}, fields | {'assets','origin'}]
            _require(isinstance(record, dict) and set(record) in admitted,
                     "Unknown source-authoring record fields")
            key = record["file_key"]
            _require(isinstance(key, str) and _HEX32.fullmatch(key) and key not in seen,
                     "Invalid/duplicate stable authoring file key")
            seen.add(key)
            relative = record["relative"] if detached else name
            if detached:
                _require(name == key and record["note"] is not None, "Detached record must retain a declared note")
                _relative(relative)
                _require(_language(record["language"]) == record["language"]
                         and PurePosixPath(relative).suffix in _EXTENSIONS[record["language"]]
                         and isinstance(record["source_sha256"], str) and _HEX64.fullmatch(record["source_sha256"]),
                         "Invalid detached source descriptor")
            else:
                descriptors[relative] = {k: record[k] for k in ("language", "source_sha256")}
            if "origin" in record:
                _origin(record["origin"], True)
            note = record["note"]
            roster = record.get('assets', {})
            _require(isinstance(roster, dict) and len(roster) <= 32 and (not roster or note is not None), 'Assets require an existing note and at most32 images')
            for logical, descriptor in roster.items():
                _require(isinstance(descriptor, dict) and isinstance(descriptor.get('sha256'), str), 'Invalid asset identity')
                digest = descriptor['sha256']; leaf = 'blobs/' + digest + '.png'
                _require(leaf in payload, 'Missing declared PNG blob')
                assets.validate_asset(logical, descriptor, payload[leaf])
                expected.add(leaf); blobs[digest] = payload[leaf]
            if note is None:
                continue
            _require(isinstance(note, dict) and set(note) == {"sha256", "size", "mode"}
                     and isinstance(note["sha256"], str) and _HEX64.fullmatch(note["sha256"])
                     and type(note["size"]) is int and 0 <= note["size"] <= MAX_NOTE_BYTES
                     and note["mode"] == FILE_MODE, "Invalid note identity")
            leaf = "notes/" + key + ".md"; expected.add(leaf)
            _require(leaf in payload and len(payload[leaf]) == note["size"]
                     and _sha(payload[leaf]) == note["sha256"], "Declared Markdown note SHA/size differs")
            notes[key] = _text(payload[leaf]); total += len(payload[leaf])
    _require(_source_files(descriptors) == descriptors, "Noncanonical source language descriptor")
    _require((manifest['schema'] == SCHEMA_V2) == bool(blobs), 'Asset schema must be v2 exactly when assets exist')
    _require(set(payload) == expected and len(notes) <= MAX_NOTES and len(blobs) <= assets.MAX_ASSETS
             and total + sum(map(len, blobs.values())) <= MAX_TOTAL_BYTES,
             "Extra/missing authoring members or total note bound exceeded")
    return {"pointer": actual_pointer, "manifest": manifest, "notes": notes, 'blobs': blobs}


def read(root, pointer):
    """Read only the exact pointed closure; a missing pointer creates nothing."""
    root = _root(root)
    if pointer is None or pointer == {}:
        return {"pointer": None, "manifest": None, "notes": {}, 'blobs': {}}
    pointer = _pointer(pointer)
    revision = root / "authoring" / "revisions" / pointer["revision"]
    for path in (root / "authoring", root / "authoring/revisions", revision):
        _directory(path)
    _require({p.name for p in revision.iterdir()} <= {"manifest.json", "notes", "blobs"}, "Unexpected authoring revision member")
    payload = {"manifest.json": _file(revision / "manifest.json", MAX_MANIFEST_BYTES)}
    note_root = revision / "notes"
    if note_root.exists() or note_root.is_symlink():
        _directory(note_root)
        members = list(note_root.iterdir())
        _require(len(members) <= MAX_NOTES, "Authoring note count exceeds bound")
        total = 0
        for path in members:
            _require(re.fullmatch(r"[0-9a-f]{32}\.md", path.name), "Unadmitted authoring note member")
            total += path.lstat().st_size
            _require(total <= MAX_TOTAL_BYTES, "Authoring note total exceeds16MiB")
            payload["notes/" + path.name] = _file(path, MAX_NOTE_BYTES)
    blob_root = revision / 'blobs'
    if blob_root.exists() or blob_root.is_symlink():
        _directory(blob_root)
        members = list(blob_root.iterdir())
        _require(0 < len(members) <= assets.MAX_ASSETS, 'PNG blob directory must declare bounded nonempty content')
        total = sum(len(v) for k, v in payload.items() if k != 'manifest.json')
        for path in members:
            _require(re.fullmatch(r'[0-9a-f]{64}\.png', path.name), 'Unadmitted PNG member')
            total += path.lstat().st_size
            _require(total <= MAX_TOTAL_BYTES, 'Notes plus PNG assets exceed16MiB')
            payload['blobs/' + path.name] = _file(path, assets.MAX_IMAGE)
    return _validated_payload(payload, pointer)


def file_note(root, pointer, relative):
    """Return one active file's note, without restoring a detached same-name note."""
    relative = _relative(relative); state = read(root, pointer)
    if state["manifest"] is None:
        return None
    _require(relative in state["manifest"]["files"], "Source file is not active in this authoring revision")
    key = state["manifest"]["files"][relative]["file_key"]
    return state["notes"].get(key)


def _payload(manifest, notes, blobs=None):
    payload = {"manifest.json": _json(manifest)}
    for key, value in notes.items():
        payload["notes/" + key + ".md"] = value.encode("utf-8")
    for key, value in (blobs or {}).items():
        payload['blobs/' + key + '.png'] = value
    _validated_payload(payload)
    return payload


def _store(root, payload):
    state = _validated_payload(payload); root = _root(root)
    for path in (root / "authoring", root / "authoring/revisions"):
        try:
            path.mkdir(mode=DIR_MODE)
        except FileExistsError:
            pass
        _directory(path)
    target = root / "authoring/revisions" / state["pointer"]["revision"]
    if target.exists() or target.is_symlink():
        _require(read(root, state["pointer"]) == state, "Existing immutable authoring revision differs")
        return state["pointer"]
    # The enclosing owner lock serializes publication. Exclusive reservation and
    # exclusive member creation never replace an unknown revision. The caller
    # commits no pointer until this complete snapshot passes strict readback.
    target.mkdir(mode=DIR_MODE)
    for directory in ('notes', 'blobs'):
        if any(name.startswith(directory + '/') for name in payload):
            (target / directory).mkdir(mode=DIR_MODE)
    for name, value in sorted(payload.items()):
        with (target / name).open("xb") as stream:
            stream.write(value); stream.flush(); os.fchmod(stream.fileno(), FILE_MODE); os.fsync(stream.fileno())
    for path in (target / "notes", target / 'blobs', target, target.parent, target.parent.parent):
        if path.is_dir():
            fd = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
            try:
                os.fsync(fd)
            finally:
                os.close(fd)
    _require(read(root, state["pointer"]) == state, "New authoring snapshot readback differs")
    return state["pointer"]


def prepare(root, pointer, source_files, updates=None, renames=None, asset_updates=None):
    """Prepare a snapshot under the caller's existing owner lock/CAS boundary."""
    source_files = _source_files(source_files); previous = read(root, pointer)
    updates = {} if updates is None else updates; renames = {} if renames is None else renames
    _require(isinstance(updates, dict) and isinstance(renames, dict), "Updates/renames must be dictionaries")
    asset_updates = {} if asset_updates is None else asset_updates
    _require(isinstance(asset_updates, dict), 'Asset updates must be a dictionary')
    old = previous["manifest"]
    manifest = copy.deepcopy(old) if old is not None else {
        "schema": SCHEMA, "owner_key": uuid.uuid4().hex, "files": {}, "detached": {}}
    files = manifest["files"]; notes = dict(previous["notes"]); blobs = dict(previous['blobs'])
    _require(len(set(renames.values())) == len(renames), "Rename destinations must be unique")
    for old_name, new_name in renames.items():
        _relative(old_name); _relative(new_name)
        _require(old_name in files and old_name not in source_files and new_name in source_files
                 and new_name not in files, "Rename requires an existing removed source and absent new destination")
    moved = {new_name: files[old_name] for old_name, new_name in renames.items()}
    for name, record in files.items():
        if name not in source_files and name not in renames and record["note"] is not None:
            manifest["detached"][record["file_key"]] = {**record, "relative": name}
    manifest["files"] = {}
    for name, descriptor in source_files.items():
        record = copy.deepcopy(moved.get(name, files.get(name)))
        if record is None:
            record = {"file_key": uuid.uuid4().hex, "note": None}
        record.update(descriptor); manifest["files"][name] = record
    for name, text in updates.items():
        _relative(name)
        _require(name in manifest["files"] and isinstance(text, str), "Note update requires an active source and UTF-8 text")
        try:
            raw = text.encode("utf-8", errors="strict")
        except UnicodeError as error:
            raise AuthoringError("Note text is not valid UTF-8") from error
        _text(raw); key = manifest["files"][name]["file_key"]
        notes[key] = text
        manifest["files"][name]["note"] = {"sha256": _sha(raw), "size": len(raw), "mode": FILE_MODE}
    for name, plan in asset_updates.items():
        _require(name in manifest['files'] and manifest['files'][name]['note'] is not None
                 and isinstance(plan, dict) and set(plan) == {'assets','blobs'}, 'Asset update requires active note and exact validated plan')
        plan = assets.validate_index(_json({'schema': assets.INDEX_SCHEMA, 'assets': plan['assets']}), plan['blobs'])
        manifest['files'][name]['assets'] = copy.deepcopy(plan['assets']); blobs.update(plan['blobs'])
    kept = {r["file_key"] for r in [*manifest["files"].values(), *manifest["detached"].values()] if r["note"] is not None}
    notes = {key: text for key, text in notes.items() if key in kept}
    wanted = set()
    for record in [*manifest['files'].values(), *manifest['detached'].values()]:
        if not record.get('assets'):
            record.pop('assets', None)
        else:
            wanted.update(row['sha256'] for row in record['assets'].values())
    blobs = {key: value for key, value in blobs.items() if key in wanted}
    manifest['schema'] = SCHEMA_V2 if blobs else SCHEMA
    return _store(root, _payload(manifest, notes, blobs))


def export_payload(root, pointer):
    """Return an exact declared portable closure, never a directory-wide copy."""
    state = read(root, pointer)
    if state["manifest"] is None:
        return {}
    return _payload(state["manifest"], state["notes"], state['blobs'])


def import_payload(root, payload, source_files):
    """Import exact notes with fresh instance/file keys and immediate lineage."""
    source_files = _source_files(source_files); imported = _validated_payload(payload)
    manifest = copy.deepcopy(imported["manifest"]); original_owner = manifest["owner_key"]
    expected = {name: {k: record[k] for k in ("language", "source_sha256")}
                for name, record in manifest["files"].items()}
    _require(expected == source_files, "Imported authoring sources differ from the owning source package")
    manifest["origin"] = {"owner_key": original_owner, "revision": imported["pointer"]["revision"]}
    manifest["owner_key"] = uuid.uuid4().hex; notes = {}; detached = {}
    for is_detached, records in ((False, manifest["files"]), (True, manifest["detached"])):
        for name, record in records.items():
            old_key = record["file_key"]; new_key = uuid.uuid4().hex
            relative = record["relative"] if is_detached else name
            record["origin"] = {"owner_key": original_owner, "file_key": old_key, "relative": relative}
            record["file_key"] = new_key
            if old_key in imported["notes"]:
                notes[new_key] = imported["notes"][old_key]
            if is_detached:
                detached[new_key] = record
    manifest["detached"] = detached
    return _store(root, _payload(manifest, notes, imported['blobs']))
