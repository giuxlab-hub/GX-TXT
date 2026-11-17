#!/usr/bin/env python3
"""Standalone manifest-bound atomic source transactions. No framework import."""
import argparse
import ctypes
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import signal
import stat
import sys
import time
import uuid

SCHEMA = 'gxtxt.atomic_source_transaction.v1'
MAX_JSON = 32 * 1024 * 1024
RENAME_EXCHANGE = 2
AT_FDCWD = -100


class Refusal(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise Refusal(message)


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def identity(path):
    s = path.lstat()
    return [s.st_dev, s.st_ino]


def fsync_dir(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def walk_error(error):
    raise error


def remove_disposable_tree(stage, live):
    # Only proven staging/retired roots reach this helper. Directory chmod is
    # limited to disposable inodes; shared regular files are never modified.
    protected = {tuple(identity(live))}
    for base, directories, files in os.walk(live, followlinks=False, onerror=walk_error):
        for name in directories:
            protected.add(tuple(identity(Path(base) / name)))
    for base, directories, files in os.walk(stage, followlinks=False, onerror=walk_error):
        base = Path(base)
        require(tuple(identity(base)) not in protected, 'Cleanup found a live original directory; no chmod/delete is permitted')
        os.chmod(base, stat.S_IMODE(base.stat().st_mode) | 0o700)
        for name in directories:
            p = base / name
            require(not p.is_symlink() and tuple(identity(p)) not in protected,
                    'Cleanup found a linked/live directory; retain both trees')
            os.chmod(p, stat.S_IMODE(p.stat().st_mode) | 0o700)
    shutil.rmtree(stage)
    fsync_dir(stage.parent)


def atomic_json(path, value):
    data = (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()
    require(len(data) <= MAX_JSON, 'Transaction metadata exceeds the supported 32 MiB bound')
    temporary = path.with_name(path.name + '.' + uuid.uuid4().hex + '.new')
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        fsync_dir(path.parent)
    finally:
        temporary.unlink(missing_ok=True)


def load_json(path):
    s = path.lstat()
    require(stat.S_ISREG(s.st_mode) and s.st_nlink == 1 and s.st_size <= MAX_JSON,
            'JSON metadata must be a bounded unlinked regular file: ' + str(path))
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, 'Duplicate JSON key: ' + key)
            result[key] = value
        return result
    return json.loads(path.read_bytes(), object_pairs_hook=unique)


def relative(name):
    require(isinstance(name, str) and name and '\\' not in name and not any(ord(c) < 32 for c in name),
            'Invalid relative source path')
    p = PurePosixPath(name)
    require(not p.is_absolute() and all(x not in ('', '.', '..') for x in p.parts)
            and p.as_posix() == name, 'Noncanonical relative source path: ' + name)
    return name


def exchange(left, right):
    libc = ctypes.CDLL(None, use_errno=True)
    function = getattr(libc, 'renameat2', None)
    require(function is not None, 'Linux renameat2(RENAME_EXCHANGE) is unavailable; no fallback is permitted')
    function.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    function.restype = ctypes.c_int
    if function(AT_FDCWD, os.fsencode(left), AT_FDCWD, os.fsencode(right), RENAME_EXCHANGE):
        code = ctypes.get_errno()
        raise Refusal('Atomic directory exchange failed: ' + os.strerror(code))


def safe_path(path):
    absolute = Path(os.path.abspath(path))
    require(not any(ord(c) < 32 for c in str(absolute)), 'Control characters in installation paths are unsupported')
    require(absolute.resolve() == absolute, 'Symlink or noncanonical installation path refused: ' + str(absolute))
    current = Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current /= part
        require(not current.is_symlink(), 'Symlink path component refused: ' + str(current))
    return absolute


def mounted_identities():
    result = {}
    for line in Path('/proc/self/mountinfo').read_text().splitlines():
        fields = line.split()
        name = re.sub(r'\\([0-7]{3})', lambda m: chr(int(m[1], 8)), fields[4])
        try:
            p = Path(name)
            result[str(p)] = identity(p)
        except OSError:
            continue
    return result


def process_check(target):
    # Advisory observation complements the mandatory operator-held stopped
    # boundary; it cannot prevent a concurrent launcher after this observation.
    active = []
    unavailable_maps = []
    prefix = str(target) + '/'
    ancestors = set()
    parent = os.getppid()
    while parent > 1 and parent not in ancestors:
        ancestors.add(parent)
        try:
            status = Path('/proc', str(parent), 'status').read_text()
            parent = int(re.search(r'^PPid:\s+(\d+)', status, re.M)[1])
        except (OSError, TypeError):
            break
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        try:
            if proc.stat().st_uid != os.getuid():
                continue
            args = (proc / 'cmdline').read_bytes().split(b'\0')
            paths = []
            for name in ('cwd', 'exe'):
                try:
                    paths.append(os.readlink(proc / name))
                except OSError:
                    pass
            if int(proc.name) not in ancestors:
                paths.extend(os.fsdecode(arg) for arg in args[1:])
            used = any(p == str(target) or p.startswith(prefix) for p in paths)
            if not used:
                try:
                    used = any((' ' + prefix) in row for row in (proc / 'maps').read_text().splitlines())
                except PermissionError:
                    # Linux ptrace policy can hide maps of unrelated same-UID
                    # processes. Record the observation limit; the operator's
                    # exclusive stopped-target boundary remains mandatory.
                    unavailable_maps.append(int(proc.name))
            if used:
                active.append(int(proc.name))
        except (FileNotFoundError, ProcessLookupError):
            continue
        except PermissionError:
            raise Refusal('Cannot inspect an owned process; establish a stopped target before retrying')
    require(not active, 'Target use detected in process IDs: ' + ', '.join(map(str, active)))
    return {'detected_target_processes': active, 'unavailable_process_maps': unavailable_maps,
            'scope': 'Best-effort process observation, not a universal concurrent-launch lock'}


class Package:
    def __init__(self, directory):
        self.directory = safe_path(directory)
        hashes = load_json(self.directory / 'PACKAGE_FILES.json')
        for name, expected in hashes.items():
            p = self.directory / relative(name)
            s = p.lstat()
            require(stat.S_ISREG(s.st_mode) and s.st_nlink == 1, 'Linked/nonregular package file: ' + name)
            require(sha(p) == expected, 'Package file checksum mismatch: ' + name)
        self.manifest = load_json(self.directory / 'MANIFEST.json')
        self.manifest_sha = sha(self.directory / 'MANIFEST.json')
        self.baseline = load_json(self.directory / 'BASELINE_FILES.json')
        self.postimage = load_json(self.directory / 'SOURCE_FILES.json')
        require(self.manifest['schema'] == 'gxtxt.p011bis.atomic_package.v1', 'Unsupported package manifest schema')
        require(self.manifest['installer_sha256'] == sha(Path(__file__).resolve()),
                'The source transaction manifest does not bind this exact installer')
        require(sha(self.directory / 'BASELINE_FILES.json') ==
                '8d39dbf9e98cfe7e9d25a36c527e923efa656147b9d1d7aac35f9b2f01bf1ec9'
                and self.manifest['baseline_source_archive_sha256'] ==
                'b8f083d2f9186ddabc8bc0b5561e191dc8233f18d361c22ef61a94c011ce2475',
                'This cumulative package requires the exact accepted P011 source inventory, not a release label')
        for base, directories, files in os.walk(self.directory, followlinks=False, onerror=walk_error):
            for name in directories + files:
                entry = Path(base) / name
                require(not entry.is_symlink() and (entry.is_file() or entry.is_dir()),
                        'Symlink/special package entry refused: ' + str(entry))
        require(self.manifest['baseline_inventory_sha256'] == sha(self.directory / 'BASELINE_FILES.json')
                and self.manifest['source_inventory_sha256'] == sha(self.directory / 'SOURCE_FILES.json'),
                'Source inventory is not manifest-bound')
        for table in (self.baseline, self.postimage):
            for name, record in table.items():
                relative(name)
                require(set(record) == {'sha256', 'size', 'mode'}, 'Invalid source inventory record: ' + name)
                require(isinstance(record['mode'], int) and 0 <= record['mode'] <= 0o777,
                        'Unsupported source permissions: ' + name)
                require(isinstance(record['size'], int) and record['size'] >= 0
                        and re.fullmatch('[a-f0-9]{64}', record['sha256']), 'Invalid source identity: ' + name)
        self.changed = {name for name in self.baseline.keys() | self.postimage.keys()
                        if self.baseline.get(name) != self.postimage.get(name)}
        require(self.baseline.keys() <= self.postimage.keys(), 'Cumulative correction does not support baseline source deletion')
        expected_files = {'apply.py', 'MANIFEST.json', 'BASELINE_FILES.json', 'SOURCE_FILES.json'}
        for name in self.changed:
            for folder, table in (('payload', self.postimage), ('preimages', self.baseline)):
                if name not in table:
                    continue
                p = self.directory / folder / name
                require(sha(p) == table[name]['sha256'] and p.stat().st_size == table[name]['size'],
                        'Payload/preimage mismatch: ' + name)
                expected_files.add(folder + '/' + name)
        require(expected_files <= hashes.keys(), 'Package hash inventory omits required artifacts')
        require('GXTXT_SOURCE_TRANSACTION_STARTUP_GUARD_V1' in
                (self.directory / 'payload/gxtxt_pipeline.tcl').read_text(), 'Corrected source lacks its early transaction guard')
        require(hashes['apply.py'] == sha(Path(__file__).resolve()), 'Installer does not match the package-bound installer')

    def verify_source(self, target, table, allow_links=False):
        for name, record in table.items():
            path = target / name
            s = path.lstat()
            require(stat.S_ISREG(s.st_mode) and (allow_links or s.st_nlink == 1),
                    'Nonregular or linked source refused: ' + name)
            require(s.st_uid == os.getuid(), 'Source owner mismatch: ' + name)
            require(s.st_size == record['size'] and stat.S_IMODE(s.st_mode) == record['mode']
                    and sha(path) == record['sha256'], 'Source byte/size/mode drift: ' + name)


def tree_snapshot(target, managed, allow_links=False):
    entries = {}
    directory_paths = set()
    for name in managed:
        parent = PurePosixPath(name).parent
        while parent != PurePosixPath('.'):
            directory_paths.add(parent.as_posix())
            parent = parent.parent
    original = target.stat()
    mounts = mounted_identities()
    roots = []
    for base, dirs, files in os.walk(target, followlinks=False, onerror=walk_error):
        base = Path(base)
        for name in sorted(dirs + files):
            p = base / name
            rel = p.relative_to(target).as_posix()
            relative(rel)
            s = p.lstat()
            require(s.st_dev == original.st_dev, 'Cross-device target entry refused: ' + rel)
            require(s.st_uid == original.st_uid and s.st_gid == original.st_gid,
                    'Mixed target ownership refused: ' + rel)
            require(stat.S_ISREG(s.st_mode) or stat.S_ISDIR(s.st_mode),
                    'Symlink or special target entry refused: ' + rel)
            require(allow_links or not stat.S_ISREG(s.st_mode) or s.st_nlink == 1,
                    'Hardlinked target entry refused: ' + rel)
            ident = [s.st_dev, s.st_ino]
            if stat.S_ISDIR(s.st_mode):
                require(ident not in mounts.values(), 'Mounted target directory or bind alias refused: ' + rel)
                require(s.st_mode & 0o500 == 0o500, 'Unreadable/unsearchable target directory refused: ' + rel)
                if rel in directory_paths:
                    require(s.st_mode & 0o700 == 0o700, 'Managed directory needs owner read/write/search for subtree exchange: ' + rel)
                    require(not os.listxattr(p, follow_symlinks=False), 'Managed directory extended metadata is unsupported: ' + rel)
                if rel not in directory_paths and not any(rel.startswith(r + '/') for r in roots):
                    roots.append(rel)
            elif rel in managed:
                require(not os.listxattr(p, follow_symlinks=False), 'Managed source extended metadata is unsupported: ' + rel)
            entries[rel] = {'id': ident, 'mode': stat.S_IMODE(s.st_mode),
                            'kind': 'directory' if stat.S_ISDIR(s.st_mode) else 'file'}
            if stat.S_ISREG(s.st_mode):
                entries[rel].update(size=s.st_size, mtime_ns=s.st_mtime_ns)
        require(len(entries) <= 200000, 'Target exceeds supported transaction entry bound (200000)')
    return entries, sorted(roots)


def unmanaged_snapshot(entries, managed):
    # Managed parent directories are replaced by staging. Every other directory
    # and all unknown files retain their original identity.
    parents = {str(PurePosixPath(n).parent) for n in managed}
    parents |= {str(p) for n in managed for p in PurePosixPath(n).parents if str(p) != '.'}
    return {name: value for name, value in entries.items() if name not in managed and name not in parents}


def clone_stage(target, stage, fault=lambda point: None):
    require(stage.is_dir() and not any(stage.iterdir()), 'Staging requires its proven empty owned directory')
    count = 0
    for base, dirs, files in os.walk(target, followlinks=False, onerror=walk_error):
        base = Path(base)
        output = stage / base.relative_to(target)
        for name in dirs:
            (output / name).mkdir(mode=0o700)
            os.chown(output / name, -1, target.stat().st_gid, follow_symlinks=False)
        for name in files:
            os.link(base / name, output / name, follow_symlinks=False)
            count += 1
            if count == 1:
                fault('mid_clone')


def stage_directory_metadata(target, stage):
    # Populate writable new directories first, then restore original directory
    # modes, including read-only parents. No original directory is changed.
    for base, dirs, files in os.walk(stage, topdown=False, onerror=walk_error):
        output = Path(base)
        original = target / output.relative_to(stage)
        os.chown(output, -1, target.stat().st_gid, follow_symlinks=False)
        os.chmod(output, stat.S_IMODE(original.stat().st_mode) if original.exists() else 0o755)
        fsync_dir(output)


def overlay(package, stage, direction, fault=lambda point: None):
    desired = package.postimage if direction == 'apply' else package.baseline
    folder = 'payload' if direction == 'apply' else 'preimages'
    for index, name in enumerate(sorted(package.changed)):
        path = stage / name
        if path.exists():
            require(path.is_file() and not path.is_symlink(), 'Owned stage entry is not a regular file: ' + name)
            path.unlink()  # Removes a staging link only; original inode is intact.
        if name not in desired:
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        data = (package.directory / folder / name).read_bytes()
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'wb') as stream:
            middle = len(data) // 2
            stream.write(data[:middle])
            fault('during_payload_write')
            stream.write(data[middle:])
            stream.flush()
            os.fchown(stream.fileno(), -1, stage.stat().st_gid)
            os.fchmod(stream.fileno(), desired[name]['mode'])
            os.fsync(stream.fileno())
        if index == 0:
            fault('mid_overlay')
    if direction == 'rollback':
        before_parents = {p for name in package.baseline for p in PurePosixPath(name).parents if str(p) != '.'}
        after_parents = {p for name in package.postimage for p in PurePosixPath(name).parents if str(p) != '.'}
        for name in sorted(after_parents - before_parents, key=lambda p: len(p.parts), reverse=True):
            path = stage / name
            # Only new source-owned parent directories, and only when empty.
            # Unknown files and directories created after apply are retained.
            if path.is_dir() and not any(path.iterdir()):
                path.rmdir()
    for base, dirs, files in os.walk(stage, topdown=False, onerror=walk_error):
        fsync_dir(Path(base))


class Transaction:
    def __init__(self, package, target, args):
        self.package = package
        self.target = safe_path(target)
        require(self.target.is_dir() and self.target.parent != self.target, 'Target must be an existing installation directory')
        require(self.target.stat().st_uid == os.getuid(), 'Run as the existing target owner; ownership changes are unsupported')
        require(self.target.stat().st_gid in set(os.getgroups()) | {os.getegid()},
                'Target group is outside installer group membership; cannot preserve new directory/file groups')
        require(self.target.stat().st_mode & 0o700 == 0o700 and not os.listxattr(self.target, follow_symlinks=False),
                'Target root requires owner read/write/search permissions and no unsupported extended metadata')
        require(self.target.stat().st_dev == self.target.parent.stat().st_dev, 'Target and its parent must share a filesystem')
        mounts = mounted_identities()
        require(identity(self.target) not in mounts.values(), 'Mounted target or bind alias cannot be atomically replaced')
        self.external = self.target.parent / ('.' + self.target.name + '.gxtxt-source-transactions')
        if self.external.exists():
            require(not self.external.is_symlink() and self.external.is_dir()
                    and self.external.stat().st_uid == os.getuid(), 'Unsafe external transaction directory')
        else:
            self.external.mkdir(mode=0o700)
            fsync_dir(self.external.parent)
        require(stat.S_IMODE(self.external.stat().st_mode) == 0o700, 'External transaction directory must have mode 0700')
        self.pending = self.external / 'pending.json'
        self.args = args
        self.lock_fd = os.open(self.external / 'lock', os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
        lock_stat = os.fstat(self.lock_fd)
        require(stat.S_ISREG(lock_stat.st_mode) and lock_stat.st_uid == os.getuid()
                and lock_stat.st_nlink == 1, 'Nonregular, foreign or linked transaction lock refused')
        try:
            fcntl.flock(self.lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise Refusal('Another source transaction holds this target')

    def fault(self, point):
        if self.args.fault_point == point:
            require(self.args.test_faults and str(self.target).startswith('/srv/gxtxt/agents/scratch/'),
                    'Fault injection is allowed only on explicitly selected scratch targets')
            os.kill(os.getpid(), signal.SIGKILL)

    def stopped(self):
        require(self.args.stopped_target, 'Mutation/recovery requires --stopped-target and no concurrent launch for the whole transaction')
        self.process_observation = process_check(self.target)

    def probe(self):
        left = self.external / ('exchange-probe-a-' + uuid.uuid4().hex)
        right = self.external / ('exchange-probe-b-' + uuid.uuid4().hex)
        left.mkdir(); right.mkdir()
        a, b = identity(left), identity(right)
        try:
            exchange(left, right)
            fsync_dir(self.external)
            require(identity(left) == b and identity(right) == a, 'Filesystem did not provide an actual atomic exchange')
        finally:
            left.rmdir(); right.rmdir()
            fsync_dir(self.external)

    def read_pending(self):
        journal = load_json(self.pending)
        require(journal.get('schema') == SCHEMA and journal.get('target') == str(self.target)
                and journal.get('manifest_sha256') == self.package.manifest_sha,
                'Foreign/malformed pending transaction; keep both trees and use its exact matching package')
        require(journal['parent_id'] == identity(self.target.parent), 'Transaction parent identity changed')
        require(re.fullmatch('[a-f0-9]{32}', journal['id']), 'Invalid transaction identity')
        stage = self.target.parent / ('.' + self.target.name + '.gxtxt-stage-' + journal['id'])
        require(journal['stage'] == str(stage) and not stage.is_symlink(), 'Foreign stage path')
        for row in journal['subtrees']:
            relative(row['path'])
            require(row['path'] in journal['unmanaged']
                    and journal['unmanaged'][row['path']]['kind'] == 'directory'
                    and journal['unmanaged'][row['path']]['id'] == row['original_id'],
                    'Subtree recovery identity is not bound to original unmanaged metadata')
        require(journal['direction'] in ('apply', 'rollback')
                and journal['package_identity'] == self.package.manifest['package_identity'],
                'Foreign transaction direction/package identity')
        before_sha = self.package.manifest['baseline_inventory_sha256' if journal['direction'] == 'apply' else 'source_inventory_sha256']
        after_sha = self.package.manifest['source_inventory_sha256' if journal['direction'] == 'apply' else 'baseline_inventory_sha256']
        require(journal['before_inventory_sha256'] == before_sha and journal['after_inventory_sha256'] == after_sha,
                'Transaction source inventories differ from the matching package')
        return journal, stage

    def checkpoint(self, journal, phase):
        journal['phase'] = phase
        atomic_json(self.pending, journal)

    def finish(self, journal, stage):
        desired = self.package.postimage if journal['direction'] == 'apply' else self.package.baseline
        self.package.verify_source(self.target, desired, allow_links=True)
        if journal['direction'] == 'rollback':
            require(not any((self.target / n).exists() for n in self.package.postimage.keys() - self.package.baseline.keys()),
                    'Introduced source remains after rollback')
        current, roots = tree_snapshot(self.target, desired, allow_links=True)
        actual = unmanaged_snapshot(current, desired)
        # Empty directories introduced only for postimage source may remain on
        # rollback; they contain no user data and have no required old identity.
        expected = journal['unmanaged']
        require(all(actual.get(name) == record for name, record in expected.items()),
                'Unmanaged content/identity changed; pending recovery remains protected')
        source_parents = {str(p) for n in self.package.postimage for p in PurePosixPath(n).parents if str(p) != '.'}
        for name, record in actual.items():
            require(name in expected or (record['kind'] == 'directory' and name in source_parents),
                    'Unexpected unmanaged content appeared during the stopped transaction: ' + name)
        outcome = 'APPLIED' if journal['direction'] == 'apply' else 'ROLLED_BACK'
        receipt = dict(journal, phase=outcome, target_id=identity(self.target), completed_utc=time.time(),
                       guarantee='Atomic source directory exchange plus completed original unmanaged directory identity recovery',
                       operational_boundary='Stopped target with no concurrent launch throughout; no launcher or service activation')
        self.fault(journal['direction'] + '.before_receipt')
        receipt_path = self.external / (journal['id'] + '.receipt.json')
        atomic_json(receipt_path, receipt)
        atomic_json(self.external / 'latest.json', receipt)
        self.fault(journal['direction'] + '.after_receipt')
        self.pending.unlink()
        fsync_dir(self.external)
        self.fault(journal['direction'] + '.after_pending_removed')
        # Both original data and full source have been verified in the live
        # root. The retired tree holds only disposable clones/source links.
        self.cleanup(receipt)
        self.package.verify_source(self.target, desired)
        return {'status': outcome, 'receipt': str(receipt_path), 'target_id': identity(self.target)}

    def cleanup(self, receipt):
        require(receipt.get('schema') == SCHEMA and receipt.get('target') == str(self.target)
                and receipt.get('manifest_sha256') == self.package.manifest_sha
                and receipt.get('target_id') == identity(self.target)
                and re.fullmatch('[a-f0-9]{32}', receipt.get('id', '')),
                'Completed receipt does not own this installation')
        stage = self.target.parent / ('.' + self.target.name + '.gxtxt-stage-' + receipt['id'])
        require(receipt.get('stage') == str(stage) and not stage.is_symlink(), 'Foreign completed stage path')
        if stage.exists():
            require(not stage.is_symlink() and identity(stage) == receipt['before_root_id'],
                    'Retired tree identity changed; retain it for inspection')
            for row in receipt['subtrees']:
                relative(row['path'])
                require(identity(self.target / row['path']) == row['original_id']
                        and identity(stage / row['path']) == row['clone_id'],
                        'Original unmanaged ownership is not proven; retain retired tree')
            remove_disposable_tree(stage, self.target)
        intent = self.external / (receipt['id'] + '.staging.json')
        intent.unlink(missing_ok=True)
        fsync_dir(self.external)

    def recover_staging(self):
        cleaned = []
        for intent_path in sorted(self.external.glob('*.staging.json')):
            intent = load_json(intent_path)
            require(intent.get('schema') == SCHEMA + '.staging'
                    and intent.get('manifest_sha256') == self.package.manifest_sha
                    and intent.get('target') == str(self.target)
                    and intent.get('parent_id') == identity(self.target.parent)
                    and re.fullmatch('[a-f0-9]{32}', intent.get('id', '')),
                    'Foreign staging intent; retain it and use the matching package')
            require(intent_path.name == intent['id'] + '.staging.json'
                    and intent['before_root_id'] == identity(self.target),
                    'Staging intent does not own the live original root')
            stage = self.target.parent / ('.' + self.target.name + '.gxtxt-stage-' + intent['id'])
            require(intent['stage'] == str(stage) and not stage.is_symlink(), 'Foreign staging path')
            table = self.package.baseline if intent['direction'] == 'apply' else self.package.postimage
            self.package.verify_source(self.target, table, allow_links=True)
            current, roots = tree_snapshot(self.target, table, allow_links=True)
            require(current == intent['entries'] and roots == intent['roots'],
                    'Live target changed after staging interruption; retain clone for inspection')
            if stage.exists():
                require(identity(stage) == intent['stage_id'], 'Foreign stage identity; no cleanup performed')
                original_dirs = {tuple(row['id']) for row in current.values() if row['kind'] == 'directory'}
                allowed_source = self.package.baseline.keys() | self.package.postimage.keys()
                allowed_directories = {str(p) for n in allowed_source for p in PurePosixPath(n).parents if str(p) != '.'}
                allowed_directories |= {n for n, row in current.items() if row['kind'] == 'directory'}
                for base, directories, files in os.walk(stage, followlinks=False, onerror=walk_error):
                    for name in directories + files:
                        path = Path(base) / name
                        name = path.relative_to(stage).as_posix()
                        s = path.lstat()
                        require(s.st_dev == self.target.stat().st_dev and s.st_uid == os.getuid(),
                                'Foreign staging entry ownership/device: ' + name)
                        if stat.S_ISDIR(s.st_mode):
                            require(name in allowed_directories and (s.st_dev, s.st_ino) not in original_dirs,
                                    'Original or foreign directory found in staging: ' + name)
                        else:
                            require(stat.S_ISREG(s.st_mode), 'Linked/special staging entry: ' + name)
                            require(name in allowed_source or (name in current and current[name]['kind'] == 'file'
                                    and identity(path) == current[name]['id']),
                                    'Foreign unmanaged staging file; retain it: ' + name)
                remove_disposable_tree(stage, self.target)
            intent_path.unlink()
            fsync_dir(self.external)
            self.package.verify_source(self.target, table)
            cleaned.append(intent['id'])
        return cleaned

    def move_subtrees(self, journal, stage, original_in_target):
        for index, row in enumerate(journal['subtrees']):
            live = self.target / row['path']
            other = stage / row['path']
            original = row['original_id']; clone = row['clone_id']
            expected = (original, clone) if original_in_target else (clone, original)
            ids = (identity(live), identity(other))
            if ids == expected:
                fsync_dir(live.parent); fsync_dir(other.parent)
                continue
            require(ids == expected[::-1], 'Foreign/missing unmanaged subtree identity: ' + row['path'])
            self.fault(journal['direction'] + '.before_subtree_' + str(index))
            exchange(live, other)
            self.fault(journal['direction'] + '.after_subtree_exchange_' + str(index))
            fsync_dir(live.parent); fsync_dir(other.parent)
            self.checkpoint(journal, 'SUBTREE_' + str(index))

    def resume(self, journal, stage):
        root_ids = (identity(self.target), identity(stage))
        before, after = journal['before_root_id'], journal['after_root_id']
        require(root_ids in ((before, after), (after, before)), 'Foreign/missing root identity; recovery refuses without mutations')
        old_table = self.package.baseline if journal['direction'] == 'apply' else self.package.postimage
        new_table = self.package.postimage if journal['direction'] == 'apply' else self.package.baseline
        self.package.verify_source(self.target, old_table if root_ids[0] == before else new_table, allow_links=True)
        self.package.verify_source(stage, new_table if root_ids[0] == before else old_table, allow_links=True)
        fsync_dir(self.target.parent)
        if journal['direction'] == 'apply':
            if root_ids == (before, after):
                # The unmodified baseline has no startup guard. Never proceed
                # with a pre-cutover apply merely because an old marker exists.
                self.package.verify_source(self.target, self.package.baseline, allow_links=True)
                require(all(identity(self.target / r['path']) == r['original_id'] for r in journal['subtrees']),
                        'Unexpected pre-cutover original directory ownership')
                receipt = dict(journal, phase='CANCELLED_BEFORE_CUTOVER', completed_utc=time.time())
                atomic_json(self.external / (journal['id'] + '.receipt.json'), receipt)
                self.fault('apply.cancel_before_pending_removed')
                self.pending.unlink(); fsync_dir(self.external)
                self.fault('apply.cancel_after_pending_removed')
                remove_disposable_tree(stage, self.target)
                (self.external / (journal['id'] + '.staging.json')).unlink(missing_ok=True)
                fsync_dir(self.external)
                self.package.verify_source(self.target, self.package.baseline)
                return {'status': 'CANCELLED_BEFORE_CUTOVER', 'retry': 'Run a fresh stopped-target apply'}
            self.move_subtrees(journal, stage, original_in_target=True)
        else:
            if root_ids == (before, after):
                self.move_subtrees(journal, stage, original_in_target=False)
                self.fault('rollback.before_root_exchange')
                exchange(self.target, stage)
                self.fault('rollback.after_root_exchange')
                fsync_dir(self.target.parent)
                self.checkpoint(journal, 'ROOT_EXCHANGED')
        return self.finish(journal, stage)

    def recover(self):
        self.stopped()
        if self.pending.exists() or self.pending.is_symlink():
            journal, stage = self.read_pending()
            return self.resume(journal, stage)
        latest = self.external / 'latest.json'
        if latest.exists():
            receipt = load_json(latest)
            if receipt.get('target_id') == identity(self.target) and receipt.get('manifest_sha256') == self.package.manifest_sha:
                self.cleanup(receipt)
        cleaned = self.recover_staging()
        return {'status': 'NO_PENDING_TRANSACTION', 'recovered_staging': cleaned,
                'retired_stage_cleanup': 'complete if matching receipt exists'}

    def run(self, direction):
        require(not self.pending.exists() and not self.pending.is_symlink(), 'Pending transaction exists; run recover with the matching package')
        self.stopped()
        require(not list(self.external.glob('*.staging.json')), 'Interrupted staging exists; run recover before retrying')
        before = self.package.baseline if direction == 'apply' else self.package.postimage
        after = self.package.postimage if direction == 'apply' else self.package.baseline
        if direction == 'apply':
            try:
                self.package.verify_source(self.target, self.package.postimage)
                receipt = load_json(self.external / 'latest.json')
                require(receipt.get('phase') == 'APPLIED' and receipt.get('manifest_sha256') == self.package.manifest_sha
                        and receipt.get('target_id') == identity(self.target), 'Postimage has no matching external apply receipt')
                return {'status': 'NOOP_ALREADY_APPLIED', 'receipt': str(self.external / 'latest.json')}
            except (FileNotFoundError, Refusal):
                pass
        else:
            receipt = load_json(self.external / 'latest.json')
            if receipt.get('phase') == 'ROLLED_BACK' and receipt.get('manifest_sha256') == self.package.manifest_sha and receipt.get('target_id') == identity(self.target):
                self.package.verify_source(self.target, self.package.baseline)
                return {'status': 'NOOP_ALREADY_ROLLED_BACK'}
            require(receipt.get('phase') == 'APPLIED' and receipt.get('manifest_sha256') == self.package.manifest_sha
                    and receipt.get('target') == str(self.target) and receipt.get('target_id') == identity(self.target),
                    'Rollback requires the matching successful external apply receipt and installation identity')
        self.package.verify_source(self.target, before)
        if direction == 'apply':
            require(not any((self.target / n).exists() for n in self.package.postimage.keys() - self.package.baseline.keys()),
                    'An introduced source path already contains unmanaged data')
        entries, roots = tree_snapshot(self.target, before)
        if direction == 'apply':
            for name in self.package.postimage.keys() - self.package.baseline.keys():
                require(not any(name == r or name.startswith(r + '/') for r in roots),
                        'Introduced source overlaps an original unmanaged directory: ' + name)
        self.probe()
        ident = uuid.uuid4().hex
        stage = self.target.parent / ('.' + self.target.name + '.gxtxt-stage-' + ident)
        intent_path = self.external / (ident + '.staging.json')
        prepared = False
        try:
            stage.mkdir(mode=0o700)
            os.chown(stage, -1, self.target.stat().st_gid, follow_symlinks=False)
            intent = {'schema': SCHEMA + '.staging', 'id': ident, 'direction': direction,
                      'target': str(self.target), 'stage': str(stage), 'parent_id': identity(self.target.parent),
                      'before_root_id': identity(self.target), 'stage_id': identity(stage),
                      'manifest_sha256': self.package.manifest_sha, 'entries': entries, 'roots': roots}
            atomic_json(intent_path, intent)
            self.fault(direction + '.after_staging_intent')
            clone_stage(self.target, stage, lambda point: self.fault(direction + '.' + point))
            overlay(self.package, stage, direction, lambda point: self.fault(direction + '.' + point))
            stage_directory_metadata(self.target, stage)
            self.fault(direction + '.after_staging')
            self.package.verify_source(stage, after, allow_links=True)
            reread, reread_roots = tree_snapshot(self.target, before, allow_links=True)
            require(entries == reread and roots == reread_roots, 'Target changed while staging; no cutover performed')
            self.stopped()
            journal = {'schema': SCHEMA, 'id': ident, 'direction': direction, 'phase': 'PREPARED',
                       'target': str(self.target), 'stage': str(stage), 'parent_id': identity(self.target.parent),
                       'before_root_id': identity(self.target), 'after_root_id': identity(stage),
                       'manifest_sha256': self.package.manifest_sha,
                       'package_identity': self.package.manifest['package_identity'],
                       'before_inventory_sha256': self.package.manifest['baseline_inventory_sha256' if direction == 'apply' else 'source_inventory_sha256'],
                       'after_inventory_sha256': self.package.manifest['source_inventory_sha256' if direction == 'apply' else 'baseline_inventory_sha256'],
                       'unmanaged': unmanaged_snapshot(entries, before),
                       'process_observation': self.process_observation,
                       'subtrees': [{'path': name, 'original_id': identity(self.target / name),
                                     'clone_id': identity(stage / name)} for name in roots],
                       'prepared_utc': time.time()}
            atomic_json(self.pending, journal)
            prepared = True
            self.fault(direction + '.after_prepared')
            if direction == 'apply':
                self.fault('apply.before_root_exchange')
                exchange(self.target, stage)
                self.fault('apply.after_root_exchange')
                fsync_dir(self.target.parent)
                self.checkpoint(journal, 'ROOT_EXCHANGED')
            return self.resume(journal, stage)
        except BaseException:
            if not prepared and not self.pending.exists() and not self.pending.is_symlink() and stage.exists():
                remove_disposable_tree(stage, self.target)
                intent_path.unlink(missing_ok=True); fsync_dir(self.external)
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('check', 'apply', 'rollback', 'recover', 'status'))
    parser.add_argument('target')
    parser.add_argument('--stopped-target', action='store_true', help='Operator maintains no running target or concurrent launch throughout mutation/recovery')
    parser.add_argument('--test-faults', action='store_true', help='Allow explicit SIGKILL fault injection on allocated scratch targets only')
    parser.add_argument('--fault-point', default='')
    args = parser.parse_args()
    require(not args.fault_point or args.test_faults, 'Fault point requires explicit --test-faults')
    package = Package(Path(__file__).resolve().parent)
    transaction = Transaction(package, args.target, args)
    if args.operation == 'status':
        if transaction.pending.exists() or transaction.pending.is_symlink():
            journal, stage = transaction.read_pending()
            result = {'status': 'PENDING_RECOVERY', 'direction': journal['direction'], 'phase': journal['phase'],
                      'root_ids': [identity(transaction.target), identity(stage)], 'journal': str(transaction.pending)}
        else:
            result = {'status': 'NO_PENDING_TRANSACTION', 'latest': str(transaction.external / 'latest.json')}
    elif args.operation == 'recover':
        result = transaction.recover()
    elif args.operation == 'check':
        require(not transaction.pending.exists() and not transaction.pending.is_symlink(), 'Pending transaction requires recovery')
        package.verify_source(transaction.target, package.baseline)
        for name in package.postimage.keys() - package.baseline.keys():
            require(not (transaction.target / name).exists(), 'Introduced source collides with unmanaged data: ' + name)
        entries, roots = tree_snapshot(transaction.target, package.baseline)
        transaction.probe()
        result = {'status': 'EXACT_BASELINE_READY', 'source_files': len(package.baseline),
                  'unmanaged_directory_roots': len(roots), 'mutation': False,
                  'operational_requirement': 'Stopped target and no concurrent launch throughout apply/rollback/recovery'}
    else:
        result = transaction.run(args.operation)
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (Refusal, OSError, ValueError, KeyError) as error:
        print(json.dumps({'status': 'REFUSED_OR_PENDING_RECOVERY', 'error': str(error),
                          'action': 'Keep target stopped. If pending.json exists, retain both trees and use this exact package recover command.'}), file=sys.stderr)
        sys.exit(2)
