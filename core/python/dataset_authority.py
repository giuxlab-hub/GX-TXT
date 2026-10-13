#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Local Dataset authority lock and durable undo journal, owned by CORE Tcl.

This is not a Dataset registry. Existing INI/payload resources stay authoritative.
The protocol is private, bounded to canonical paths below one Session. Linux uses
kernel advisory locks; a future Windows adapter must supply equivalent LOCAL
process-crash lock release and durable replace/fsync semantics, not remote RPC.
"""
import base64
import fcntl
import json
import hashlib
import os
from pathlib import Path
import shutil
import sys
import uuid


def sync_dir(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def durable_json(path, value):
    temporary = path.with_suffix('.tmp')
    with temporary.open('w', encoding='utf-8') as stream:
        json.dump(value, stream, sort_keys=True)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)
    sync_dir(path.parent)


class Authority:
    def __init__(self, session):
        self.session = Path(session).resolve(strict=True)
        self.root = self.session / 'metadata' / '.dataset_transactions'
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        if self.root.is_symlink() or self.root.resolve().parent != self.session / 'metadata':
            raise ValueError('Invalid Dataset transaction directory')
        self.lock = os.open(self.root / 'authority.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        fcntl.flock(self.lock, fcntl.LOCK_EX)
        self.directory = None
        self.record = None
        for directory in sorted(self.root.glob('txn-*')):
            if directory.is_symlink() or not directory.is_dir():
                raise ValueError('Invalid Dataset recovery directory')
            journal = directory / 'journal.json'
            if not journal.exists():
                # No durable journal means no authoritative mutation was authorized.
                shutil.rmtree(directory)
                continue
            record = json.loads(journal.read_text(encoding='utf-8'))
            self.finish(directory, record, record['phase'] == 'committed')
        self.reconcile_staging()

    @staticmethod
    def process_identity(pid):
        try:
            text = Path('/proc/%d/stat' % int(pid)).read_text()
            state = text[text.rindex(')') + 2:].split()
            if state[0] == 'Z':
                return None
            return [int(pid), state[19], Path('/proc/sys/kernel/random/boot_id').read_text().strip()]
        except (OSError, ValueError, IndexError):
            return None

    def stage_record(self, path):
        return self.root / ('stage-' + hashlib.sha256(str(path).encode()).hexdigest() + '.json')

    def staging(self, argument, remove=False):
        parts = argument.split('\t')
        path = self.path(parts[0])
        if not path.name.startswith('.') or not path.name.endswith('.partial'):
            raise ValueError('Only CORE publication staging is managed here')
        record_path = self.stage_record(path)
        if remove:
            record_path.unlink(missing_ok=True)
            sync_dir(self.root)
            return
        owners = [self.process_identity(os.getppid())]
        if len(parts) > 1 and parts[1]:
            owners.append(self.process_identity(parts[1]))
        stat = path.stat() if path.exists() else None
        durable_json(record_path, {'path': str(path), 'owners': [v for v in owners if v],
                                 'identity': [stat.st_dev, stat.st_ino] if stat else None})

    def reconcile_staging(self):
        for record_path in self.root.glob('stage-*.json'):
            if record_path.is_symlink():
                raise ValueError('Invalid staging owner record')
            record = json.loads(record_path.read_text())
            if any(self.process_identity(identity[0]) == identity for identity in record['owners']):
                continue
            path = self.path(record['path'])
            if path.exists():
                stat = path.stat()
                # A changed/unknown inode is retained for explicit inspection.
                if [stat.st_dev, stat.st_ino] != record['identity']:
                    continue
                path.unlink()
                self.sync_parents(path.parent)
            record_path.unlink()
            sync_dir(self.root)

    def sync_parents(self, path):
        while path == self.session or self.session in path.parents:
            if path.is_dir():
                sync_dir(path)
            if path == self.session:
                break
            path = path.parent

    def path(self, raw):
        path = Path(raw)
        if not path.is_absolute():
            raise ValueError('Transaction path must be absolute')
        relative = path.relative_to(self.session)
        if '..' in relative.parts or not relative.parts or relative.parts[:2] == ('metadata', '.dataset_transactions'):
            raise ValueError('Transaction path escapes Dataset authority')
        current = self.session
        for part in relative.parts:
            current /= part
            if current.is_symlink():
                raise ValueError('Transaction paths cannot contain symlinks')
        if path.exists() and not path.is_file():
            raise ValueError('Transaction resource must be a regular file')
        return path

    def enlist(self, raw):
        path = self.path(raw)
        if self.directory is None:
            self.directory = self.root / ('txn-' + uuid.uuid4().hex)
            self.directory.mkdir(mode=0o700)
            sync_dir(self.root)
            self.record = {'version': 1, 'phase': 'pending', 'owner_pid': os.getppid(), 'files': []}
        if any(item['path'] == str(path) for item in self.record['files']):
            return
        item = {'path': str(path), 'present': path.exists(), 'backup': str(len(self.record['files'])) + '.before'}
        if item['present']:
            backup = self.directory / item['backup']
            shutil.copy2(path, backup)
            with backup.open('rb') as stream:
                os.fsync(stream.fileno())
        self.record['files'].append(item)
        durable_json(self.directory / 'journal.json', self.record)

    def finish(self, directory, record, committed):
        if not committed:
            for item in reversed(record['files']):
                path = self.path(item['path'])
                if item['present']:
                    backup = directory / item['backup']
                    if backup.parent != directory or not backup.is_file() or backup.is_symlink():
                        raise ValueError('Invalid Dataset recovery preimage')
                    path.parent.mkdir(parents=True, exist_ok=True)
                    temporary = path.with_name('.' + path.name + '.recover-' + directory.name)
                    shutil.copy2(backup, temporary)
                    with temporary.open('rb') as stream:
                        os.fsync(stream.fileno())
                    os.replace(temporary, path)
                else:
                    path.unlink(missing_ok=True)
                self.sync_parents(path.parent)
        shutil.rmtree(directory)
        sync_dir(self.root)

    def end(self, committed):
        if self.directory is None:
            return
        if committed:
            for item in self.record['files']:
                path = self.path(item['path'])
                if path.exists():
                    with path.open('rb') as stream:
                        os.fsync(stream.fileno())
                self.sync_parents(path.parent)
            committed_record = dict(self.record, phase='committed')
            durable_json(self.directory / 'journal.json', committed_record)
            self.record = committed_record
        durable_commit = self.record['phase'] == 'committed'
        try:
            self.finish(self.directory, self.record, durable_commit)
        except OSError:
            if not durable_commit:
                raise
            # Publication is already durable. A cleanup failure must NEVER
            # turn it into a rollback; the next opener retries owned cleanup.
        self.directory = None
        self.record = None


def main():
    authority = Authority(sys.argv[1])
    print('OK', flush=True)
    try:
        for line in sys.stdin:
            try:
                command, _, argument = line.rstrip('\n').partition('\t')
                if command == 'ENLIST':
                    authority.enlist(base64.b64decode(argument, validate=True).decode('utf-8'))
                elif command in ('STAGE', 'UNSTAGE'):
                    authority.staging(base64.b64decode(argument, validate=True).decode('utf-8'), command == 'UNSTAGE')
                elif command in ('COMMIT', 'ABORT'):
                    authority.end(command == 'COMMIT')
                elif command == 'QUIT':
                    break
                else:
                    raise ValueError('Unknown Dataset authority request')
                print('OK', flush=True)
            except Exception as error:
                print('ERROR\t' + base64.b64encode(str(error).encode()).decode(), flush=True)
    finally:
        authority.end(False)
        os.close(authority.lock)


if __name__ == '__main__':
    main()
