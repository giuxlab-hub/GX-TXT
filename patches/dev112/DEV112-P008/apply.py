#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Exact cumulative DEV112.r2/post-P005/P006r5 -> P008; default pure read-only check."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tempfile
import zipfile
import zlib

PATCH = 'DEV112-P008'
NOTES = 'patch_notes/' + PATCH
MANIFEST_SHA256 = 'cb2449c05c2fd64577b994f795a177cb9221a457b7fedd9c9d129ea59a09033c'
MODES = {0o644, 0o664, 0o755}
MAX_MEMBER = 64 * 1024 * 1024
MAX_ARCHIVE = 256 * 1024 * 1024
MAX_TOTAL = 512 * 1024 * 1024
ROUTES = {'r2', 'post-p005', 'post-p006-r5', 'post-p007'}
NOTE_FILES = {'INSTALLAZIONE.md', 'FILES.json', 'apply.py', 'README.md', 'CHANGELOG.md', 'OWNER_HANDOFF.md', 'VALIDATION.json', 'CORE_REUSE_AND_GAP_AUDIT.md', 'API_CONTRACTS.md'}
INPUTS = {
'r2': '8fda1fd6e485d9d917adfb08d64991c2403f8faf19ed10f4770565d8afcdbaa0',
'P001': 'b73fd26aaf6e8d3950de355988640bce0c6f0180e0ccc18aa5a19962e8f68d4b',
'P002': '022d5af77a5660a87a48193293240de9cffb9ecb6d5f421f5fc0dd4fbd54aaa6',
'P003': '135761937e22f22582763dba927c22e844d81cec0e6f4e90f6382b1adfe8af81',
'P004': 'd0ec6476778f3e4d2fdc781427bbfcb71dcfc1374cae31b5c609d333adf37b44',
'P005': '55358070dc710ae4b1d7384edeef03f4a47627e4f790484d102a5a360e2e38b9',
'P006-r5': 'd62ff22bd824e1dcdfaece27243ae958a5d20d1ec624d0b33d45be79fc2a7ed6',
'P007': 'db4b7457edebc3a01bae244e1bc01db7a785d7348b9d808fb000b7a2d20131b3',
}
ROUTE_PINS = {'r2': 'd385ab67405dedbe0747d6de6bc97c9ff267313041391c355d7020da8a195c3d', 'post-p005': 'c4f988dee0f95b14b773fd67064fa09a80073a07a1a34e25d381273387b63a80', 'post-p006-r5': '1471c154455c18c18c7f71a1dd751c1d946e1235ceecc25e23008bfb7360c11c', 'post-p007': '514e9dd7778b8eb2fc34d60ea0ec4cb544786f430d9e308d0620171e8cac90ed'}

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
    require(relative in {'gxtxt_pipeline.tcl', 'PATCH_LEVEL.txt', 'GX-TXT_REMAINING_WORK_TODO.md', 'GX-TXT_REMAINING_WORK_TODO.md.sha256'} or
            relative in {'SCRIPT_CATALOG.md', 'SCRIPT_CATALOG.md.sha256', 'README.md', 'CHANGELOG.md',
                        'validation/dev112_p008_gui_followup/AUTHOR_RESULTS.md',
                        'validation/dev112_p008_gui_followup/SCRIPT_CATALOG.md',
                        'validation/dev112_p008_gui_followup/check.py',
                        'validation/dev112_p008_bis_main/SCRIPT_CATALOG.md',
                        'validation/dev112_p008_bis_main/check.py',
                        'validation/dev112_p008_gui_supplement/AUTHOR_RESULTS.md',
                        'validation/dev112_p008_gui_supplement/SCRIPT_CATALOG.md',
                        'validation/dev112_p008_gui_supplement/check.py',
                        'validation/dev112_p008_runtime/AUTHOR_RESULTS.md',
                        'validation/dev112_p008_runtime/SCRIPT_CATALOG.md',
                        'validation/dev112_p008_runtime/check.py',
                        'validation/dev112_p008_runtime/guards.py',
                        'validation/dev112_p008_runtime/setup_baseline.py',
                        'validation/dev112_p008_main/check.py',
                        'validation/dev112_p008_main/SCRIPT_CATALOG.md',
                        'validation/dev112_p008_graphics/check.py',
                        'validation/dev112_p008_graphics/SCRIPT_CATALOG.md',
                        'validation/dev112_p008_graphics/HANDOFF.md',
                        'validation/dev112_p008_graphics/WORK_STATE.md',
                        'validation/dev112_p008_gui/SCRIPT_CATALOG.md',
                        'validation/dev112_p008_gui/AUTHOR_RESULTS.md',
                        'validation/dev112_p008_gui/check.py',
                        'validation/dev112_p007_preview/SCRIPT_CATALOG.md',
                        'validation/dev112_p007_preview/presentation_guards.tcl',
                        'validation/dev112_p007_preview/PERFORMANCE_LIMITS.md',
                        'validation/dev112_p007_preview/AUTHOR_RESULTS.md',
                        'validation/dev112_p007_preview/cache_upgrade.tcl',
                        'validation/dev112_p007_preview/companion_stages.tcl',
                        'validation/dev112_p007_preview/gui.tcl',
                        'validation/dev112_p007_preview/profile_gui.tcl',
                        'validation/dev112_p007_preview/fixture.tcl',
                        'validation/dev112_p007_preview/run.py',
                        'validation/dev112_p007_preview/quality_fixture.py',
                        'validation/dev112_p007_preview/metadata.tcl',
                        'validation/dev112_p007_preview/HANDOFF.md',
                        'validation/dev112_p007_identity/SCRIPT_CATALOG.md',
                        'validation/dev112_p007_identity/check.py',
                        'validation/dev112_p007_library_jobs/SCRIPT_CATALOG.md',
                        'validation/dev112_p007_library_jobs/HANDOFF.md',
                        'validation/dev112_p007_library_jobs/check.py',
                        'validation/dev112_p007_library_jobs/hash_check.py',
                        'validation/dev112_p007_library_jobs/read_integrity.py',
                        'validation/dev112_p006_font_units/SCRIPT_CATALOG.md',
                        'validation/dev112_p006_font_units/run.py',
                        'validation/dev112_p006_working_values01/SCRIPT_CATALOG.md',
                        'validation/dev112_p006_working_values01/check.py',
                        'validation/dev112_p006_working_values01/consumer.py',
                        'validation/dev112_p006_working_values01/consumer.m',
                        'validation/dev112_p006_working_values01/design_cases.py',
                        'distribution/packages/viewer.orion_sii_canvas_1.0.7.zip',
                        'distribution/packages/viewer.orion_sii_canvas_1.0.7.zip.sha256'} or
            (len(parts) >= 2 and parts[0] in {'app', 'core', 'docs', 'examples', 'services', 'tools'}) or
            (len(parts) >= 4 and parts[:2] == ['plugins', 'modules']),
            'Out-of-scope product path: ' + relative)
    require(not any(p in {'.git', '__pycache__', 'Sessions', 'session_generators', 'releases'} for p in parts),
            'Forbidden product subtree: ' + relative)


def validate_inventory(inventory, label):
    require(type(inventory) is dict and 5000 <= len(inventory) <= 16384,
            'Incomplete/oversized inventory: ' + label)
    for path, value in inventory.items():
        safe_relative(path)
        expected_identity(value, label + ':' + path)


def validate_manifest(manifest):
    require(type(manifest) is dict and set(manifest) ==
            {'schema', 'patch', 'inputs', 'routes', 'postimage', 'payload'}, 'Malformed manifest fields')
    require(manifest['schema'] == 'gxtxt.dev112.cumulative.v1' and manifest['patch'] == PATCH,
            'Wrong cumulative schema/patch')
    require(manifest['inputs'] == INPUTS and type(manifest['routes']) is dict and
            set(manifest['routes']) == ROUTES, 'Wrong input/route identities')
    post = manifest['postimage']
    validate_inventory(post, 'postimage')
    all_paths = set(post)
    expected_payload = set()
    for route, before in manifest['routes'].items():
        validate_inventory(before, route)
        require(digest(canonical(before)) == ROUTE_PINS[route], 'Route inventory pin mismatch: ' + route)
        require(set(before).issubset(post), 'Published-file deletion is not admitted')
        all_paths.update(before)
        expected_payload.update(p for p in post if post[p] != before.get(p))
    require(type(manifest['payload']) is list and len(manifest['payload']) == len(set(manifest['payload'])) and
            set(manifest['payload']) == expected_payload, 'Missing/duplicate/unneeded net payload')
    for path in expected_payload:
        product_path(path)
    for path in all_paths:
        parts = path.split('/')
        require(not any('/'.join(parts[:n]) in all_paths for n in range(1, len(parts))),
                'File/directory namespace collision: ' + path)
    marker = b'008\n'
    require(post['PATCH_LEVEL.txt'] == {'sha256': digest(marker), 'size': len(marker), 'mode': 0o644},
            'Final patch marker must be exact 008 newline mode0644')
    require(all(before['VERSION.txt'] == post['VERSION.txt'] for before in manifest['routes'].values()),
            'Underlying compatibility VERSION.txt must remain unchanged')
    return manifest['routes'], post, expected_payload


def archive_read(archive):
    info = regular_info(archive)
    require(info is not None and info.st_size <= MAX_ARCHIVE, 'Archive missing or exceeds bound')
    sidecar = Path(str(archive) + '.sha256')
    info = regular_info(sidecar)
    require(info is not None and info.st_size <= 4096, 'Missing/oversized archive checksum')
    fields = sidecar.read_text(encoding='ascii').strip().split()
    require(len(fields) in {1, 2} and re.fullmatch('[0-9a-f]{64}', fields[0]), 'Malformed archive checksum')
    if len(fields) == 2:
        require(fields[1].lstrip('*') == archive.name, 'Checksum names another archive')
    archive_bytes = archive.read_bytes()
    require(digest(archive_bytes) == fields[0], 'Archive SHA256 differs from adjacent sidecar')
    with zipfile.ZipFile(io.BytesIO(archive_bytes)) as zipped:
        infos = zipped.infolist()
        names = [item.filename for item in infos]
        require(0 < len(names) <= 32768 and len(names) == len(set(names)) and not zipped.comment,
                'Malformed/duplicate archive entries')
        total = 0
        modes = {}
        for item in infos:
            safe_relative(item.filename)
            mode = item.external_attr >> 16
            require(item.orig_filename == item.filename and not item.is_dir() and item.create_system == 3 and
                    stat.S_IFMT(mode) == stat.S_IFREG and stat.S_IMODE(mode) in MODES and
                    not item.extra and not item.comment and not (item.flag_bits & 1) and
                    item.compress_type in {zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED} and
                    0 <= item.file_size <= MAX_MEMBER, 'Invalid archive member metadata: ' + item.filename)
            total += item.file_size
            require(total <= MAX_TOTAL, 'Archive uncompressed size exceeds bound')
            modes[item.filename] = stat.S_IMODE(mode)
        name = NOTES + '/FILES.json'
        require(name in names and zipped.getinfo(name).file_size <= 8 * 1024 * 1024, 'Missing/oversized manifest')
        raw = zipped.read(name)
        require(digest(raw) == MANIFEST_SHA256, 'Manifest differs from installer-bound SHA256')
        manifest = parse_json(raw)
        routes, post, payload = validate_manifest(manifest)
        expected = {p: post[p] for p in payload}
        for route, before in routes.items():
            for path in payload:
                if path in before and before[path] != post[path]:
                    expected[NOTES + '/preimages/' + route + '/' + path] = before[path]
        note_names = {NOTES + '/' + n for n in NOTE_FILES}
        require(set(expected).issubset(names) and set(names).issubset(set(expected) | note_names),
                'Missing or undeclared payload/preimage/note')
        require(NOTES + '/apply.py' in names and NOTES + '/README.md' in names, 'Missing installer/instructions')
        data = {}
        for name in names:
            blob = zipped.read(name)  # All CRC/decompression checks precede framework writes.
            if name in expected:
                value = expected[name]
                require(len(blob) == value['size'] and digest(blob) == value['sha256'] and
                        modes[name] == value['mode'], 'Bad member bytes/mode: ' + name)
                data[name] = blob
            else:
                require(modes[name] == (0o755 if name.endswith('/apply.py') else 0o644), 'Bad note mode: ' + name)
                if name.endswith('.json'):
                    parse_json(blob)
                else:
                    blob.decode('utf-8')
        require(b"MANIFEST_SHA256 = '" + MANIFEST_SHA256.encode() + b"'" in zipped.read(NOTES + '/apply.py'),
                'Embedded installer does not bind this manifest')
    return routes, post, payload, data, fields[0]


def guard_source_inventory(root, post):
    # Known shipped source trees are exact; unrelated user data outside them is untouched.
    source_trees = {p.split('/')[0] for p in post if '/' in p}
    directories = set()
    for path in post:
        parts = path.split('/')
        directories.update('/'.join(parts[:n]) for n in range(1, len(parts)))
    for entry in root.iterdir():
        if entry.name not in source_trees and entry.name not in post:
            require(entry.suffix.lower() not in {'.tcl', '.py', '.so', '.dll', '.sh', '.exe'},
                    'Undeclared root source/executable file: ' + entry.name)
            info = entry.lstat()
            require(not (stat.S_ISREG(info.st_mode) and info.st_mode & 0o111),
                    'Undeclared root executable file: ' + entry.name)
    for top in sorted(source_trees):
        path = root / top
        if not path.exists():
            continue  # Missing required files are rejected by the complete inventory below.
        require(stat.S_ISDIR(path.lstat().st_mode), 'Non-directory/symlink source tree: ' + top)
        for parent, dirs, files in os.walk(path, followlinks=False):
            for name in dirs:
                candidate = Path(parent) / name
                relative = candidate.relative_to(root).as_posix()
                require(relative in directories and stat.S_ISDIR(candidate.lstat().st_mode),
                        'Undeclared/symlink/non-directory source directory: ' + relative)
            for name in files:
                relative = (Path(parent) / name).relative_to(root).as_posix()
                require(relative in post, 'Undeclared source file: ' + relative)


def admitted_state(root, routes, post):
    guard_source_inventory(root, post)
    observed = {path: identity(member(root, path)) for path in sorted(post)}
    matches = []
    for name, expected in [*routes.items(), ('postimage', post)]:
        if all(observed[p] == expected.get(p) for p in post):
            matches.append(name)
    require(len(matches) == 1, 'Unknown/modified/incomplete/mixed framework inventory; no writes')
    return matches[0], observed


def fsync_parent(path):
    descriptor = os.open(path.parent, os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0))
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def replace(root, relative, data, mode):
    path = member(root, relative)
    path.parent.mkdir(parents=True, exist_ok=True)
    member(root, relative)
    descriptor, temporary = tempfile.mkstemp(prefix='.p008-', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'wb') as stream:
            os.fchmod(stream.fileno(), mode)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        fsync_parent(path)
    finally:
        if os.path.lexists(temporary):
            os.unlink(temporary)


def external_receipt_path(raw, root, existing):
    require(raw is not None, 'A retained external --receipt is required for this operation')
    path = Path(os.path.abspath(raw))
    require(not path.is_relative_to(root) and not root.is_relative_to(path),
            'Apply receipt must be outside the framework and not its ancestor')
    for parent in [*reversed(path.parents), path.parent]:
        info = parent.lstat()
        require(stat.S_ISDIR(info.st_mode), 'Receipt ancestor must be a real directory: ' + str(parent))
    if existing:
        info = regular_info(path)
        require(info is not None and info.st_size <= 8 * 1024 * 1024, 'Missing/oversized external apply receipt')
    else:
        require(not os.path.lexists(path), 'Apply receipt path must be new; preserve the prior receipt')
    return path


def persist_apply_receipt(path, record, previous_sha=None):
    raw = canonical(record) + b'\n'
    require(len(raw) <= 8 * 1024 * 1024, 'External apply receipt exceeds its bound')
    if previous_sha is None:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0), 0o600)
        with os.fdopen(descriptor, 'wb') as output:
            output.write(raw)
            output.flush()
            os.fsync(output.fileno())
        fsync_parent(path)
    else:
        require(identity(path)['sha256'] == previous_sha, 'External apply receipt changed during installation')
        descriptor, temporary = tempfile.mkstemp(prefix='.p008-receipt-', dir=path.parent)
        try:
            with os.fdopen(descriptor, 'wb') as output:
                os.fchmod(output.fileno(), 0o600)
                output.write(raw)
                output.flush()
                os.fsync(output.fileno())
            require(identity(path)['sha256'] == previous_sha, 'External apply receipt changed before update')
            os.replace(temporary, path)
            fsync_parent(path)
        finally:
            if os.path.lexists(temporary):
                os.unlink(temporary)
    actual = identity(path)
    require(actual['sha256'] == digest(raw) and actual['size'] == len(raw) and actual['mode'] == 0o600,
            'External apply receipt write verification failed')
    return actual['sha256']


def installation_instance(root):
    info = regular_info(member(root, 'PATCH_LEVEL.txt'))
    require(info is not None, 'Canonical installation marker is missing')
    return {'device': info.st_dev, 'inode': info.st_ino,
            'mtime_ns': info.st_mtime_ns, 'ctime_ns': info.st_ctime_ns}


def read_apply_receipt(arguments, root, routes, post, archive_sha):
    require(type(arguments.receipt_sha256) is str and re.fullmatch('[0-9a-f]{64}', arguments.receipt_sha256),
            'Rollback/receipt validation requires independently retained --receipt-sha256')
    path = external_receipt_path(arguments.receipt, root, True)
    before = identity(path)
    require(before['sha256'] == arguments.receipt_sha256, 'External apply receipt differs from retained SHA256')
    descriptor = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0) | getattr(os, 'O_NONBLOCK', 0))
    with os.fdopen(descriptor, 'rb') as stream:
        raw = stream.read(8 * 1024 * 1024 + 1)
    require(len(raw) <= 8 * 1024 * 1024 and digest(raw) == arguments.receipt_sha256 and identity(path) == before,
            'External apply receipt changed while reading')
    record = parse_json(raw)
    require(type(record) is dict and set(record) == {'schema', 'patch', 'framework_root', 'route',
            'archive_sha256', 'manifest_sha256', 'before_inventory_sha256', 'after_inventory_sha256',
            'status', 'completed_files', 'total_files', 'error', 'installation_instance'}, 'Malformed external apply receipt fields')
    require(record['schema'] == 'gxtxt.dev112.external_apply_receipt.v1' and record['patch'] == PATCH,
            'Wrong external apply receipt schema/patch')
    route = record['route']
    require(type(route) is str and route in ROUTES, 'Invalid receipt route')
    require(arguments.route is None or arguments.route == route, 'Rollback route differs from retained successful apply origin')
    require(record['framework_root'] == str(root), 'External apply receipt belongs to another framework root')
    require(record['archive_sha256'] == archive_sha and record['manifest_sha256'] == MANIFEST_SHA256,
            'External apply receipt archive/manifest mismatch')
    require(record['before_inventory_sha256'] == digest(canonical(routes[route])) and
            record['after_inventory_sha256'] == digest(canonical(post)), 'External apply receipt inventory mismatch')
    total = sum(post[p] != routes[route].get(p) for p in post)
    require(record['status'] == 'COMPLETE' and record['error'] is None and
            type(record['completed_files']) is int and type(record['total_files']) is int and
            record['completed_files'] == total and record['total_files'] == total,
            'External apply receipt is not a completed successful installation')
    instance = record['installation_instance']
    require(type(instance) is dict and set(instance) == {'device', 'inode', 'mtime_ns', 'ctime_ns'} and
            all(type(value) is int for value in instance.values()), 'Malformed receipt installation instance')
    if identity(member(root, 'PATCH_LEVEL.txt')) == post['PATCH_LEVEL.txt']:
        require(instance == installation_instance(root), 'External apply receipt belongs to another installation instance')
    return path, record, before['sha256']


def run(arguments):
    root = Path(os.path.abspath(arguments.framework))
    for parent in [*reversed(root.parents), root]:
        info = parent.lstat()
        require(stat.S_ISDIR(info.st_mode), 'Linked/nondirectory framework ancestor: ' + str(parent))
    routes, post, payload, data, archive_sha = archive_read(Path(os.path.abspath(arguments.archive)))
    state, observed = admitted_state(root, routes, post)
    operation = 'rollback' if arguments.rollback else 'apply' if arguments.apply else 'check'
    receipt = {'patch': PATCH, 'operation': operation, 'framework_root': str(root),
               'archive_sha256': archive_sha, 'manifest_sha256': MANIFEST_SHA256,
               'initial_state': state, 'writes': [], 'activation': 'NONE'}
    if operation == 'check':
        if arguments.route:
            require(state in {arguments.route, 'postimage'}, 'Selected route does not match exact source')
        if arguments.receipt is not None or arguments.receipt_sha256 is not None:
            path, retained, retained_sha = read_apply_receipt(arguments, root, routes, post, archive_sha)
            receipt.update(external_receipt=str(path), external_receipt_sha256=retained_sha,
                           route=retained['route'], rollback_origin_verified=True)
        else:
            receipt['rollback_origin_verified'] = False
        receipt.update(result='PASS', final_state=state, read_only=True)
        print(json.dumps(receipt, sort_keys=True))
        return
    require(arguments.stopped and arguments.owner_authorized,
            'Writes require --owner-authorized and --stopped acknowledgements; no authorization/process detection')
    if operation == 'rollback':
        require(arguments.route in ROUTES, 'Rollback requires explicit --route r2, post-p005, post-p006-r5 or post-p007')
        require(state in {'postimage', arguments.route}, 'Rollback route differs from current original state')
        receipt_path, retained, retained_sha = read_apply_receipt(arguments, root, routes, post, archive_sha)
        route = retained['route']
        target_state = route
        receipt.update(external_receipt=str(receipt_path), external_receipt_sha256=retained_sha,
                       rollback_origin_verified=True)
    else:
        if state == 'postimage':
            if arguments.receipt is not None or arguments.receipt_sha256 is not None or arguments.route is not None:
                receipt_path, retained, retained_sha = read_apply_receipt(arguments, root, routes, post, archive_sha)
                receipt.update(external_receipt=str(receipt_path), external_receipt_sha256=retained_sha,
                               route=retained['route'], rollback_origin_verified=True)
            else:
                receipt['rollback_origin_verified'] = False
            receipt.update(result='PASS', final_state=state, coherent_noop=True)
            print(json.dumps(receipt, sort_keys=True))
            return
        route = state
        require(arguments.route is None or arguments.route == route, 'Selected route differs from exact source')
        require(arguments.receipt_sha256 is None, 'New apply creates its receipt SHA; do not supply --receipt-sha256')
        receipt_path = external_receipt_path(arguments.receipt, root, False)
        target_state = 'postimage'
    receipt['route'] = route
    if state == target_state:
        receipt.update(result='PASS', final_state=state, coherent_noop=True)
        print(json.dumps(receipt, sort_keys=True))
        return
    before = routes[route]
    second_state, second_observed = admitted_state(root, routes, post)
    require(second_state == state and second_observed == observed, 'Guarded files changed during full preflight')
    changes = [p for p in payload if before.get(p) != post[p]]
    changes.sort(key=lambda p: (p == 'PATCH_LEVEL.txt', p))
    progress = None
    if operation == 'apply':
        progress = {'schema': 'gxtxt.dev112.external_apply_receipt.v1', 'patch': PATCH,
                    'framework_root': str(root), 'route': route, 'archive_sha256': archive_sha,
                    'manifest_sha256': MANIFEST_SHA256, 'before_inventory_sha256': digest(canonical(before)),
                    'after_inventory_sha256': digest(canonical(post)), 'status': 'IN_PROGRESS',
                    'completed_files': 0, 'total_files': len(changes), 'error': None, 'installation_instance': None}
        progress_sha = persist_apply_receipt(receipt_path, progress)
        receipt['external_receipt'] = str(receipt_path)
    try:
        for relative in changes:
            path = member(root, relative)
            require(identity(path) == observed[relative], 'Target changed after preflight: ' + relative)
            target = before.get(relative) if operation == 'rollback' else post[relative]
            if target is None:
                path.unlink()
                fsync_parent(path)
            else:
                name = NOTES + '/preimages/' + route + '/' + relative if operation == 'rollback' else relative
                replace(root, relative, data[name], target['mode'])
            require(identity(member(root, relative)) == target, 'Written target verification failed: ' + relative)
            receipt['writes'].append({'path': relative, 'before': observed[relative], 'after': target})
            if progress is not None:
                progress['completed_files'] += 1
                progress_sha = persist_apply_receipt(receipt_path, progress, progress_sha)
        final_state, final_observed = admitted_state(root, routes, post)
        require(final_state == target_state, 'Final complete inventory verification failed')
        if progress is not None:
            progress['installation_instance'] = installation_instance(root)
            progress['status'] = 'COMPLETE'
            progress_sha = persist_apply_receipt(receipt_path, progress, progress_sha)
            receipt.update(external_receipt_sha256=progress_sha, rollback_origin_verified=True)
        receipt.update(result='PASS', final_state=final_state,
                       final_inventory_sha256=digest(canonical({p: v for p, v in final_observed.items() if v is not None})))
        print(json.dumps(receipt, sort_keys=True))
    except BaseException as error:
        if progress is not None:
            progress['status'] = 'FAILED'
            progress['error'] = type(error).__name__ + ': ' + str(error)
            try:
                receipt['external_receipt_sha256'] = persist_apply_receipt(receipt_path, progress, progress_sha)
            except BaseException as receipt_error:
                receipt['external_receipt_error'] = str(receipt_error)
        receipt.update(result='INTERRUPTED_OR_FAILED', error=str(error),
                       recovery='No automatic continuation; preserve external receipt, stdout audit and original files for owner-controlled restoration')
        print(json.dumps(receipt, sort_keys=True))
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('framework')
    parser.add_argument('archive')
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--check', action='store_true')
    group.add_argument('--apply', action='store_true')
    group.add_argument('--rollback', action='store_true')
    parser.add_argument('--route', choices=sorted(ROUTES))
    parser.add_argument('--receipt', help='External retained apply receipt; new for apply, completed for rollback')
    parser.add_argument('--receipt-sha256', help='Exact receipt SHA retained independently from successful apply stdout')
    parser.add_argument('--stopped', action='store_true', help='Acknowledgement only; does not detect or stop processes')
    parser.add_argument('--owner-authorized', action='store_true', help='Operator confirms authorization; never grants it')
    arguments = parser.parse_args()
    try:
        run(arguments)
    except (OSError, ValueError, KeyError, TypeError, UnicodeError, RuntimeError,
            zipfile.BadZipFile, zipfile.LargeZipFile, zlib.error, EOFError) as error:
        raise SystemExit('REFUSED: ' + str(error))


if __name__ == '__main__':
    main()
