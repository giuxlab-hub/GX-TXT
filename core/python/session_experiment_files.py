"""Private CORE Session creation ownership, without scientific/Project writes.

CLI arguments after the operation are base64 UTF-8 to avoid Tcl exec redirection
syntax. Responses are inert Tcl dictionaries. Cleanup never recurses or removes
a promoted final Session. The outside marker is transient ownership, not a store.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
import base64
import contextlib
import ctypes
import errno
import json
import os
from pathlib import Path
import stat
import sys
import uuid

SCHEMA = 'gxtxt.session_creation.v1'
PREFIX = '.gxtxt-create-'
MARKER = 'creation.json'
LOCK = '.owner.lock'
IMMUTABLE = ('schema', 'nonce', 'root', 'root_identity', 'stage_parent', 'parent_identity',
             'lock_identity', 'stage', 'stage_name', 'target', 'owner_pid', 'owner_identity')


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def identity(path):
    value = path.lstat()
    require(stat.S_ISDIR(value.st_mode) and not path.is_symlink(), 'Not a real directory: ' + str(path))
    return [value.st_dev, value.st_ino]


def real_directory(path):
    path = Path(path)
    require(path.is_absolute() and path == path.resolve(strict=True), 'Real absolute directory required: ' + str(path))
    identity(path)
    return path


def process_identity(pid):
    if sys.platform.startswith('linux'):
        try:
            text = Path(f'/proc/{pid}/stat').read_text()
            fields = text[text.rfind(')') + 2:].split()
            if fields[0] == 'Z':
                return None
            return [Path('/proc/sys/kernel/random/boot_id').read_text().strip(), fields[19]]
        except (OSError, ValueError, IndexError):
            return None
    if os.name == 'nt':
        from ctypes import wintypes
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        kernel.OpenProcess.restype = wintypes.HANDLE
        kernel.GetProcessTimes.argtypes = [wintypes.HANDLE, *([ctypes.POINTER(wintypes.FILETIME)] * 4)]
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        handle = kernel.OpenProcess(0x1000, False, pid)
        if not handle:
            return None
        try:
            values = [wintypes.FILETIME() for _ in range(4)]
            if not kernel.GetProcessTimes(handle, *(ctypes.byref(v) for v in values)):
                return None
            return ['windows', (values[0].dwHighDateTime << 32) | values[0].dwLowDateTime]
        finally:
            kernel.CloseHandle(handle)
    raise RuntimeError('No Session creation process identity adapter on this platform')


def sync_directory(path):
    if os.name != 'nt':
        fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)


def encoded(value):
    return base64.urlsafe_b64encode(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).decode()


def decoded(token):
    require(isinstance(token, str) and len(token) <= 32768, 'Invalid creation token size')
    return json.loads(base64.b64decode(token, altchars=b'-_', validate=True))


def write_marker(record, initial=False):
    parent = Path(record['stage_parent'])
    marker = parent / MARKER
    temporary = parent / ('.creation-write-' + uuid.uuid4().hex)
    destination = marker if initial else temporary
    descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'wb') as stream:
        stream.write(json.dumps(record, sort_keys=True, separators=(',', ':')).encode())
        stream.flush(); os.fsync(stream.fileno())
    if not initial:
        # Replace only our private marker, never a Session directory.
        os.replace(temporary, marker)
    sync_directory(parent)


def read_marker(parent):
    descriptor = os.open(parent / MARKER, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
    with os.fdopen(descriptor, 'rb') as stream:
        value = os.fstat(stream.fileno())
        require(stat.S_ISREG(value.st_mode) and value.st_nlink == 1 and value.st_size <= 32768,
                'Invalid creation marker')
        return json.loads(stream.read(32769))


def validate(record):
    require(record.get('schema') == SCHEMA and len(record.get('nonce', '')) == 32, 'Invalid creation record')
    root = real_directory(record['root'])
    parent = real_directory(record['stage_parent'])
    require(parent.parent == root and parent.name == PREFIX + record['nonce'] and
            identity(root) == record['root_identity'] and identity(parent) == record['parent_identity'],
            'Creation parent/root ownership changed; retain all paths')
    if os.name != 'nt':
        require(stat.S_IMODE(parent.stat().st_mode) == 0o700 and parent.stat().st_uid == os.getuid(),
                'Creation parent is no longer private')
    name = record['stage_name']
    require(name not in ('', '.', '..') and Path(name).name == name and
            not any(c in name for c in '/\\\x00\r\n'), 'Invalid creation name')
    require(Path(record['stage']) == parent / name and Path(record['target']) == root / name,
            'Creation paths disagree')
    return root, parent


@contextlib.contextmanager
def locked(token):
    expected = decoded(token)
    _, parent = validate(expected)
    fd = os.open(parent / LOCK, os.O_RDWR | getattr(os, 'O_NOFOLLOW', 0))
    acquired = False
    try:
        value = os.fstat(fd)
        require(stat.S_ISREG(value.st_mode) and [value.st_dev, value.st_ino] == expected['lock_identity'],
                'Creation lock ownership changed')
        if os.name == 'nt':
            import msvcrt
            msvcrt.locking(fd, msvcrt.LK_LOCK, 1)
        else:
            import fcntl
            fcntl.flock(fd, fcntl.LOCK_EX)
        acquired = True
        record = read_marker(parent)
        require(all(record.get(key) == expected.get(key) for key in IMMUTABLE), 'Creation marker changed')
        if expected.get('stage_identity') is not None:
            require(record.get('stage_identity') == expected['stage_identity'], 'Claimed stage identity changed')
        validate(record)
        yield record
    finally:
        if os.name == 'nt' and acquired:
            import msvcrt
            os.lseek(fd, 0, os.SEEK_SET)
            msvcrt.locking(fd, msvcrt.LK_UNLCK, 1)
        os.close(fd)


def result(record, **extra):
    return dict(schema=SCHEMA, state=record['state'], claim=encoded(record), root=record['root'],
                target=record['target'], stage_parent=record['stage_parent'], stage=record['stage'],
                stage_name=record['stage_name'], owner_alive=process_identity(record['owner_pid']) == record['owner_identity'], **extra)


def reserve(root_s, name, owner_s):
    root = real_directory(root_s)
    require(name not in ('', '.', '..') and Path(name).name == name and
            not any(c in name for c in '/\\\x00\r\n'), 'Expected one safe Session name')
    target = root / name
    require(not os.path.lexists(target), 'New Session destination already exists: ' + str(target))
    owner = int(owner_s)
    lease = process_identity(owner)
    require(owner > 0 and lease is not None, 'Live creation owner required')
    nonce = uuid.uuid4().hex
    parent = root / (PREFIX + nonce)
    parent.mkdir(mode=0o700); parent.chmod(0o700)
    descriptor = os.open(parent / LOCK, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'wb') as stream:
        stream.write(b'0'); stream.flush(); os.fsync(stream.fileno())
    value = (parent / LOCK).stat()
    record = dict(schema=SCHEMA, nonce=nonce, root=str(root), root_identity=identity(root),
                  stage_parent=str(parent), parent_identity=identity(parent), lock_identity=[value.st_dev, value.st_ino],
                  stage=str(parent / name), stage_name=name, target=str(target), owner_pid=owner,
                  owner_identity=lease, stage_identity=None, state='reserved')
    write_marker(record, initial=True); sync_directory(root)
    return result(record)


def claim(token, actual):
    with locked(token) as record:
        require(record['state'] in {'reserved', 'claimed'}, 'Creation is not pending')
        require(process_identity(record['owner_pid']) == record['owner_identity'], 'Creation owner is no longer active')
        stage = real_directory(actual)
        require(str(stage) == record['stage'], 'makeSession selected another path; retain it')
        current = identity(stage)
        require(record['stage_identity'] in (None, current), 'Creation stage ownership changed')
        record['stage_identity'] = current; record['state'] = 'claimed'
        write_marker(record)
        return result(record)


def probe(session_s):
    session = Path(session_s)
    require(session.is_absolute(), 'Absolute Session probe required')
    parent = session.parent
    if not parent.name.startswith(PREFIX):
        return dict(schema=SCHEMA, pending=False, state='ordinary')
    # Missing/corrupt creation ownership never authorizes ordinary registration.
    record = read_marker(real_directory(parent))
    with locked(encoded(record)) as record:
        require(str(session) == record['stage'], 'Session is not the reserved staging child')
        current = identity(real_directory(session))
        require(record['stage_identity'] in (None, current), 'Pending Session identity changed')
        return result(record, pending=True)


def no_replace(stage, target, record):
    if sys.platform.startswith('linux'):
        libc = ctypes.CDLL(None, use_errno=True)
        rename = getattr(libc, 'renameat2', None)
        require(rename is not None, 'Kernel no-replace adapter unavailable; stage retained')
        rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
        rename.restype = ctypes.c_int
        root_fd = os.open(target.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        parent_fd = os.open(stage.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            a, b = os.fstat(root_fd), os.fstat(parent_fd)
            require([a.st_dev, a.st_ino] == record['root_identity'] and
                    [b.st_dev, b.st_ino] == record['parent_identity'], 'Promotion parent changed')
            if rename(parent_fd, os.fsencode(stage.name), root_fd, os.fsencode(target.name), 1):
                code = ctypes.get_errno()
                if code in {errno.ENOSYS, errno.EINVAL, errno.EOPNOTSUPP}:
                    raise RuntimeError('Filesystem/kernel lacks no-replace; stage retained')
                raise OSError(code, os.strerror(code), str(target))
        finally:
            os.close(parent_fd); os.close(root_fd)
    elif os.name == 'nt':
        os.rename(stage, target)  # Windows refuses an existing destination.
    else:
        raise RuntimeError('No supported no-replace Session promotion on this platform')


def cleanup_metadata(record):
    _, parent = validate(record)
    require(read_marker(parent) == record, 'Changed marker retained')
    value = (parent / LOCK).lstat()
    require([value.st_dev, value.st_ino] == record['lock_identity'] and stat.S_ISREG(value.st_mode),
            'Changed lock retained')
    (parent / MARKER).unlink(); (parent / LOCK).unlink(); sync_directory(parent)
    try:
        parent.rmdir(); sync_directory(parent.parent)
        return ''
    except OSError:
        return str(parent)  # Unknown extra entries are preserved, never traversed.


def promote(token):
    with locked(token) as record:
        expected = decoded(token)
        require(record['state'] == 'claimed' and expected.get('stage_identity') == record['stage_identity'],
                'Positive claimed stage required for promotion')
        require(process_identity(record['owner_pid']) == record['owner_identity'], 'Creation owner is no longer active')
        stage, target = Path(record['stage']), Path(record['target'])
        require(identity(real_directory(stage)) == record['stage_identity'], 'Stage replaced; retain all paths')
        no_replace(stage, target, record)
        sync_directory(stage.parent); sync_directory(target.parent)
        require(identity(target) == record['stage_identity'], 'Promoted target changed; retain all paths')
        record['state'] = 'promoted'; write_marker(record)
    retained = cleanup_metadata(record)
    return result(record, pending=False, retained_metadata=retained)


def inspect(token):
    record = decoded(token)
    target = Path(record['target'])
    # Observation only after the outside marker is deliberately gone.
    if record.get('stage_identity') and not Path(record['stage']).exists() and target.exists():
        if identity(real_directory(target)) == record['stage_identity']:
            record['state'] = 'promoted'
            return result(record, pending=False)
        raise RuntimeError('Final target identity differs; retain all paths')
    with locked(token) as record:
        return result(record, pending=True)


def abort(token):
    observed = inspect(token)
    if observed['state'] == 'promoted':
        return dict(observed, state='promoted_retained', diagnostic='Committed valid target is never removed')
    with locked(token) as record:
        stage = Path(record['stage'])
        if stage.exists() or stage.is_symlink():
            require(record['stage_identity'] is not None and identity(real_directory(stage)) == record['stage_identity'],
                    'Unproven/replaced stage retained; no deletion authorized')
            try:
                stage.rmdir()  # Never recurse into producer output or a foreign canary.
            except OSError:
                record['state'] = 'aborted_retained'; write_marker(record)
                return result(record, pending=True, diagnostic='Nonempty failed stage preserved')
        record['state'] = 'aborted_empty'; write_marker(record)
    retained = cleanup_metadata(record)
    return result(record, pending=False, retained_metadata=retained)


def tcl_word(value):
    text = str(value)
    if not text:
        return '{}'
    return ''.join({' ': '\\ ', '\t': '\\t', '\n': '\\n', '\r': '\\r', '\\': '\\\\'}.get(
        c, '\\' + c if c in '{}[]$;"' else c) for c in text)


def tcl_dict(record):
    return ' '.join(tcl_word(key) + ' ' + tcl_word('1' if value is True else '0' if value is False
                                               else '' if value is None else value)
                    for key, value in record.items())


def main():
    operation, *raw = sys.argv[1:]
    arguments = [base64.b64decode(value, validate=True).decode('utf-8') for value in raw]
    functions = dict(reserve=reserve, claim=claim, probe=probe, promote=promote, abort=abort, inspect=inspect)
    require(operation in functions, 'Unknown private creation operation')
    print(tcl_dict(functions[operation](*arguments)))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Session creation owner error: ' + str(error) + '; preserve retained paths', file=sys.stderr)
        sys.exit(1)
