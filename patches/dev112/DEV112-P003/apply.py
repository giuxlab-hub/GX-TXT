#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Exact DEV112.r2 + P001 + corrected P002 -> P003 incremental overlay; default read-only check."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tempfile
import zipfile
import zlib

PATCH = 'DEV112-P003'
NOTES = 'patch_notes/' + PATCH
PREDECESSOR_COUNT = 5457
# SHA256 of UTF-8 json.dumps(P002_POSTIMAGE, sort_keys=True, separators=(',', ':')).
PREDECESSOR_DIGEST = '9ffdd681eb9499fafd574b8fe8bd76aaa1f489ab682c5f9173d90bbf0c52bc39'
MODES = {0o644, 0o664, 0o755}
MAX_MEMBER = 64 * 1024 * 1024
MAX_ARCHIVE = 256 * 1024 * 1024
MAX_TOTAL = 512 * 1024 * 1024
NOTE_FILES = {
    'FILES.json', 'apply.py', 'README.md', 'VALIDATION.json', 'CHANGELOG.md',
    'CORE_REUSE_AND_GAP_AUDIT.md', 'CANVAS_ARCHITECTURE_AND_API_CONTRACT.md',
    'OWNER_HANDOFF.md', 'EVIDENCE_INDEX.json', 'ORION_REFERENCE_RECONCILIATION.md',
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical(data):
    return json.dumps(data, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode('utf-8')


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'Duplicate JSON field: ' + key)
        result[key] = value
    return result


def parse_json(data):
    def bad_constant(value):
        raise ValueError('Nonfinite JSON constant: ' + value)
    return json.loads(data.decode('utf-8'), object_pairs_hook=unique_object,
                      parse_constant=bad_constant)


def safe_relative(name):
    require(isinstance(name, str) and 0 < len(name.encode('utf-8')) <= 1024,
            'Invalid relative path')
    parts = name.split('/')
    require(not PurePosixPath(name).is_absolute() and '\\' not in name and ':' not in name
            and all(p not in ('', '.', '..') and len(p.encode('utf-8')) <= 255 for p in parts)
            and not any(ord(c) < 32 or ord(c) == 127 for c in name),
            'Unsafe relative path: ' + repr(name))
    return parts


def regular_info(path):
    try:
        info = path.lstat()
    except FileNotFoundError:
        return None
    require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1,
            'Nonregular/symlink/hardlinked file: ' + str(path))
    return info


def member(root, relative):
    current = root
    parts = safe_relative(relative)
    for index, part in enumerate(parts):
        current = current / part
        try:
            info = current.lstat()
        except FileNotFoundError:
            continue
        require(not stat.S_ISLNK(info.st_mode), 'Symlink target/ancestor: ' + str(current))
        if index + 1 < len(parts):
            require(stat.S_ISDIR(info.st_mode), 'Nondirectory ancestor: ' + str(current))
    return current


def identity(path):
    info = regular_info(path)
    if info is None:
        return None
    require(info.st_size <= MAX_MEMBER, 'Guarded file exceeds size bound: ' + str(path))
    hasher = hashlib.sha256()
    # O_NOFOLLOW prevents a replaced final-component symlink being followed.
    fd = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
    with os.fdopen(fd, 'rb') as stream:
        opened = os.fstat(stream.fileno())
        require((opened.st_dev, opened.st_ino, opened.st_size, opened.st_mtime_ns,
                 opened.st_ctime_ns, opened.st_mode, opened.st_nlink) ==
                (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns,
                 info.st_ctime_ns, info.st_mode, info.st_nlink),
                'File changed before read: ' + str(path))
        for page in iter(lambda: stream.read(1024 * 1024), b''):
            hasher.update(page)
        after = os.fstat(stream.fileno())
        def stable(s):
            return (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns,
                    s.st_mode, s.st_nlink, s.st_uid, s.st_gid)
        require(stable(after) == stable(opened), 'File changed during read: ' + str(path))
    require(stable(path.lstat()) == stable(info), 'File changed after read: ' + str(path))
    return {'sha256': hasher.hexdigest(), 'size': info.st_size, 'mode': stat.S_IMODE(info.st_mode)}


def expected_identity(value, label):
    require(type(value) is dict and set(value) == {'sha256', 'size', 'mode'},
            'Malformed identity: ' + label)
    require(type(value['sha256']) is str and re.fullmatch('[0-9a-f]{64}', value['sha256']),
            'Malformed SHA256: ' + label)
    require(type(value['size']) is int and 0 <= value['size'] <= MAX_MEMBER,
            'Malformed size: ' + label)
    require(type(value['mode']) is int and value['mode'] in MODES,
            'Malformed/unsupported mode: ' + label)


def product_path(relative):
    parts = safe_relative(relative)
    require(relative == 'gxtxt_pipeline.tcl' or
            (len(parts) >= 2 and parts[0] in {'core', 'docs', 'examples'}),
            'Out-of-scope product path: ' + relative)
    require(not any(p in {'.git', '__pycache__', 'Sessions', 'external_plugins',
                          'session_generators', 'plugins', 'releases'} for p in parts),
            'Forbidden product subtree: ' + relative)


def validate_manifest(manifest):
    require(type(manifest) is dict and set(manifest) ==
            {'schema', 'patch', 'predecessor', 'predecessor_files', 'files'},
            'Malformed FILES.json fields')
    require(manifest['schema'] == 'gxtxt.dev112.incremental.v1' and
            manifest['patch'] == PATCH and manifest['predecessor'] == 'DEV112-P002',
            'Wrong incremental schema/patch/predecessor')
    baseline = manifest['predecessor_files']
    require(type(baseline) is dict and len(baseline) == PREDECESSOR_COUNT,
            'Incomplete predecessor file inventory')
    for path, value in baseline.items():
        safe_relative(path)
        expected_identity(value, path)
    require(digest(canonical(baseline)) == PREDECESSOR_DIGEST,
            'Predecessor inventory differs from exact corrected DEV112-P002')
    rows = manifest['files']
    require(type(rows) is list and 0 < len(rows) <= 4096, 'Malformed/empty patch files')
    deltas = {}
    for row in rows:
        require(type(row) is dict and set(row) == {'path', 'before', 'after'},
                'Malformed delta fields')
        path = row['path']
        product_path(path)
        require(path not in deltas, 'Duplicate product delta: ' + path)
        expected_identity(row['after'], path + ' postimage')
        if path in baseline:
            expected_identity(row['before'], path + ' preimage')
            require(row['before'] == baseline[path], 'Delta preimage differs from predecessor: ' + path)
        else:
            require(row['before'] is None, 'New file has a fabricated preimage: ' + path)
        require(row['before'] != row['after'], 'Unchanged file in incremental delta: ' + path)
        deltas[path] = row
    all_paths = set(baseline) | set(deltas)
    for path in all_paths:
        parts = path.split('/')
        require(not any('/'.join(parts[:n]) in all_paths for n in range(1, len(parts))),
                'File/directory namespace collision: ' + path)
    return baseline, deltas


def archive_read(archive):
    regular_info(archive)
    require(archive.is_file() and archive.stat().st_size <= MAX_ARCHIVE,
            'Archive missing or exceeds bound')
    sidecar = Path(str(archive) + '.sha256')
    info = regular_info(sidecar)
    require(info is not None and info.st_size <= 4096, 'Missing/oversized archive checksum')
    checksum = sidecar.read_text(encoding='ascii').strip()
    fields = checksum.split()
    require(len(fields) in {1, 2} and re.fullmatch('[0-9a-f]{64}', fields[0]),
            'Malformed archive checksum')
    if len(fields) == 2:
        require(fields[1].lstrip('*') == archive.name, 'Checksum names another archive')
    archive_bytes = archive.read_bytes()
    require(digest(archive_bytes) == fields[0], 'Archive SHA256 differs from adjacent sidecar')
    import io
    with zipfile.ZipFile(io.BytesIO(archive_bytes)) as zipped:
        infos = zipped.infolist()
        require(0 < len(infos) <= 16384 and not zipped.comment, 'Malformed archive metadata')
        names = [item.filename for item in infos]
        require(len(names) == len(set(names)), 'Duplicate archive entries')
        total = 0
        modes = {}
        for item in infos:
            safe_relative(item.filename)
            mode = item.external_attr >> 16
            require(item.orig_filename == item.filename and not item.is_dir() and item.create_system == 3 and
                    stat.S_IFMT(mode) == stat.S_IFREG and stat.S_IMODE(mode) in MODES and
                    not item.extra and not item.comment and not (item.flag_bits & 1) and
                    item.compress_type in {zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED} and
                    0 <= item.file_size <= MAX_MEMBER,
                    'Invalid archive member metadata: ' + item.filename)
            total += item.file_size
            require(total <= MAX_TOTAL, 'Archive uncompressed size exceeds bound')
            modes[item.filename] = stat.S_IMODE(mode)
        manifest_name = NOTES + '/FILES.json'
        require(manifest_name in names and zipped.getinfo(manifest_name).file_size <= 4 * 1024 * 1024,
                'Missing/oversized FILES.json')
        manifest = parse_json(zipped.read(manifest_name))
        baseline, deltas = validate_manifest(manifest)
        preimages = {NOTES + '/preimages/' + path for path, row in deltas.items() if row['before'] is not None}
        notes = {NOTES + '/' + name for name in NOTE_FILES}
        expected = set(deltas) | preimages
        require(expected.issubset(names) and set(names).issubset(expected | notes),
                'Missing or undeclared payload/preimage/notes')
        data = {}
        # Every member is read now: CRC/decompression/JSON/encoding failures precede writes.
        for name in names:
            blob = zipped.read(name)
            if name in deltas:
                target = deltas[name]['after']
            elif name in preimages:
                target = deltas[name[len(NOTES + '/preimages/'):]]['before']
            else:
                require(modes[name] == (0o755 if name.endswith('/apply.py') else 0o644),
                        'Wrong inert note mode: ' + name)
                if name.endswith('.json'):
                    parse_json(blob)
                elif name.endswith(('.md', '.py')):
                    blob.decode('utf-8')
                continue
            require(len(blob) == target['size'] and digest(blob) == target['sha256'] and
                    modes[name] == target['mode'], 'Bad payload/preimage bytes or mode: ' + name)
            data[name] = blob
    return baseline, deltas, data


def admitted_state(root, baseline, deltas):
    before = True
    after = True
    observed = {}
    for relative in sorted(set(baseline) | set(deltas)):
        actual = identity(member(root, relative))
        pre = baseline.get(relative)
        post = deltas[relative]['after'] if relative in deltas else pre
        before = before and actual == pre
        after = after and actual == post
        observed[relative] = actual
        require(actual == pre or actual == post, 'Altered guarded file/new-file collision: ' + relative)
    require(before or after, 'Mixed predecessor/postimage is refused; no writes')
    return ('predecessor' if before else 'postimage'), observed


def replace(root, relative, data, mode):
    path = member(root, relative)
    path.parent.mkdir(parents=True, exist_ok=True)
    member(root, relative)
    descriptor, temporary = tempfile.mkstemp(prefix='.p003-', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'wb') as stream:
            os.fchmod(stream.fileno(), mode)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.lexists(temporary):
            os.unlink(temporary)


def run(arguments):
    root = Path(os.path.abspath(arguments.framework))
    for parent in [*reversed(root.parents), root]:
        info = parent.lstat()
        require(stat.S_ISDIR(info.st_mode), 'Linked/nondirectory framework ancestor: ' + str(parent))
    baseline, deltas, data = archive_read(Path(os.path.abspath(arguments.archive)))
    state, observed = admitted_state(root, baseline, deltas)
    if not (arguments.apply or arguments.rollback):
        print('CHECK PASS; exact ' + state + '; no writes; ' + str(len(deltas)) + ' deltas')
        return
    require(arguments.stopped, 'Writes require --stopped acknowledgement; processes are not detected/stopped')
    destination = 'predecessor' if arguments.rollback else 'postimage'
    if state == destination:
        print(('ROLLBACK' if arguments.rollback else 'APPLY') + ' PASS; coherent no-op; no writes')
        return
    # Repeat the complete guarded admission before the first framework write.
    second_state, second_observed = admitted_state(root, baseline, deltas)
    require(second_state == state and second_observed == observed, 'Guarded files changed during preflight')
    for relative, row in sorted(deltas.items()):
        path = member(root, relative)
        require(identity(path) == observed[relative], 'Target changed after preflight: ' + relative)
        target = row['before'] if arguments.rollback else row['after']
        if target is None:
            path.unlink()
        else:
            name = NOTES + '/preimages/' + relative if arguments.rollback else relative
            replace(root, relative, data[name], target['mode'])
        require(identity(member(root, relative)) == target, 'Written target verification failed: ' + relative)
    final_state, _ = admitted_state(root, baseline, deltas)
    require(final_state == destination, 'Final complete inventory verification failed')
    print(('ROLLBACK' if arguments.rollback else 'APPLY') + ' PASS; exact ' + destination +
          '; no activation or running-process control performed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('framework')
    parser.add_argument('archive')
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--check', action='store_true')
    group.add_argument('--apply', action='store_true')
    group.add_argument('--rollback', action='store_true')
    parser.add_argument('--stopped', action='store_true',
                        help='Operator acknowledgement only; does not detect or stop processes')
    arguments = parser.parse_args()
    if (arguments.apply or arguments.rollback) and not arguments.stopped:
        parser.error('Writes require --stopped acknowledgement')
    try:
        run(arguments)
    except (OSError, ValueError, KeyError, TypeError, UnicodeError, RuntimeError,
            zipfile.BadZipFile, zipfile.LargeZipFile, zlib.error, EOFError) as error:
        raise SystemExit('REFUSED: ' + str(error))


if __name__ == '__main__':
    main()
