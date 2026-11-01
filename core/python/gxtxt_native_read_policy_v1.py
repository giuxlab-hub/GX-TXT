# SPDX-License-Identifier: GPL-3.0-or-later
"""Additive native Acquisition filesystem guard, before authored code loading.

Called only by the fixed trusted target worker. Inputs are admitted CORE binary,
runtime dependency roles and an optional CORE-owned typed buffer directory.
No selected-source FD/path is admitted. Existing Viewer/project grants are not
changed. This is not an account-wide or network confinement claim.
"""
from __future__ import annotations
import ctypes
import errno
import fcntl
import hashlib
import os
from pathlib import Path
import platform
import stat

class NativeReadPolicyError(RuntimeError):
    pass

class _Ruleset(ctypes.Structure):
    _fields_ = [('handled_access_fs', ctypes.c_uint64)]

class _PathRule(ctypes.Structure):
    _pack_ = 1
    _fields_ = [('allowed_access', ctypes.c_uint64), ('parent_fd', ctypes.c_int32)]

class _Filter(ctypes.Structure):
    _fields_ = [('code',ctypes.c_ushort),('jt',ctypes.c_ubyte),('jf',ctypes.c_ubyte),('k',ctypes.c_uint)]

class _Program(ctypes.Structure):
    _fields_ = [('len',ctypes.c_ushort),('filter',ctypes.POINTER(_Filter))]

READ_FILE = 1 << 2
WRITE_FILE = 1 << 1
TRUNCATE = 1 << 14

def _deny_process_descendants(libc):
    """New target only: inherited write FDs cannot outlive the worker process.

    Ordinary pthreads remain in the same process; clone3 must fall back to clone
    because classic seccomp cannot safely dereference its authored flags pointer.
    No old Viewer language/runtime policy is changed.
    """
    if platform.machine()=='x86_64':arch=0xc000003e;clone=56;denied=(57,58,59,322)
    elif platform.machine()=='aarch64':arch=0xc00000b7;clone=220;denied=(221,281)
    else:raise NativeReadPolicyError('Unsupported native process syscall ABI')
    allow=0x7fff0000;refuse=0x00050000|errno.EPERM
    instructions=[(0x20,0,0,4),(0x15,1,0,arch),(0x06,0,0,0x80000000),
                  (0x20,0,0,0),(0x35,0,1,0x40000000),(0x06,0,0,refuse),
                  (0x15,0,1,435),(0x06,0,0,0x00050000|errno.ENOSYS)]
    for number in denied:instructions.extend([(0x15,0,1,number),(0x06,0,0,refuse)])
    instructions.extend([(0x15,0,3,clone),(0x20,0,0,16),(0x45,1,0,0x10000),(0x06,0,0,refuse),(0x06,0,0,allow)])
    filters=(_Filter*len(instructions))(*(_Filter(*row) for row in instructions));program=_Program(len(filters),filters)
    if libc.prctl(22,2,ctypes.byref(program),0,0):
        raise OSError(ctypes.get_errno(),'Cannot enforce native process-creation restriction')
    return dict(mechanism='Linux seccomp-BPF',enforced=True,fork='EPERM',vfork='EPERM',
                process_clone='EPERM',clone3='ENOSYS',exec='EPERM',threads='CLONE_THREAD_ONLY',
                foreign_syscall_abi=False,scope='new Acquisition target only')


def _ordinary(record, *, system=False):
    if not isinstance(record, dict) or set(record) != {'path', 'sha256'}:
        raise NativeReadPolicyError('An exact admitted file/digest role is required')
    path = Path(record['path'])
    if not path.is_absolute() or path.resolve(strict=True) != path or any(p.is_symlink() for p in [path, *path.parents]):
        raise NativeReadPolicyError('Native read policy refuses linked/noncanonical files')
    info = path.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_mode & 0o022:
        raise NativeReadPolicyError('Native read policy requires ordinary non-writable admitted files')
    if system and info.st_uid != 0:
        raise NativeReadPolicyError('Runtime dependency must be a reviewed system-owned file')
    if not system and info.st_nlink != 1:
        raise NativeReadPolicyError('Admitted native binary must not be hardlinked')
    expected = record['sha256']
    if not isinstance(expected, str) or len(expected) != 64 or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise NativeReadPolicyError('Admitted file changed before native confinement')
    return path


def _close_unrelated(protocol_fds):
    keep = {0, 1, 2, *protocol_fds}
    if any(type(fd) is not int or not 0 <= fd <= 1024 for fd in keep):
        raise NativeReadPolicyError('Invalid trusted protocol descriptor set')
    for fd in keep:
        try:
            info = os.fstat(fd)
            mode = fcntl.fcntl(fd, fcntl.F_GETFL) & os.O_ACCMODE
        except OSError as error:
            raise NativeReadPolicyError('Trusted protocol descriptor is unavailable') from error
        if fd in {1, 2}:
            if mode != os.O_WRONLY:
                raise NativeReadPolicyError('Native diagnostics must be write-only descriptors')
        elif not (stat.S_ISFIFO(info.st_mode) or stat.S_ISSOCK(info.st_mode)):
            raise NativeReadPolicyError('Native input/protocol must not be an inherited source file')
    closed = []
    for name in os.listdir('/proc/self/fd'):
        if not name.isdecimal():
            continue
        fd = int(name)
        if fd not in keep:
            try:
                os.close(fd)
                closed.append(fd)
            except OSError:
                pass
    return closed


def activate_native_read_policy(binary, reviewed_runtime_files, *,
                                buffer_root=None, protocol_fds=()):
    """Irreversible target-only Landlock policy; no permissive fallback.

    Source authority remains in a different CORE broker process. The only write
    exception is WRITE_FILE/TRUNCATE under an existing private buffer directory;
    the actor cannot read/list/create/unlink/rename/execute there. Parent creates
    buffers, validates them after actor reaping and owns publication.
    """
    if platform.system() != 'Linux' or platform.machine() not in {'x86_64', 'aarch64'}:
        raise NativeReadPolicyError('Native Acquisition requires supported Linux read enforcement')
    if not isinstance(reviewed_runtime_files, list) or not 1 <= len(reviewed_runtime_files) <= 128:
        raise NativeReadPolicyError('A bounded reviewed runtime closure is required')
    admitted = [_ordinary(binary)]
    admitted.extend(_ordinary(record, system=True) for record in reviewed_runtime_files)
    if len(set(admitted)) != len(admitted):
        raise NativeReadPolicyError('Native runtime closure contains duplicate file roles')
    buffer = None
    if buffer_root is not None:
        buffer = Path(buffer_root)
        if not buffer.is_absolute() or buffer.resolve(strict=True) != buffer or any(p.is_symlink() for p in [buffer, *buffer.parents]):
            raise NativeReadPolicyError('Typed buffer root must be a canonical CORE-owned directory')
        info = buffer.stat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise NativeReadPolicyError('Typed buffer root must be private to its CORE owner')
    closed = _close_unrelated(protocol_fds)
    libc = ctypes.CDLL(None, use_errno=True)
    libc.syscall.restype = ctypes.c_long
    abi = libc.syscall(444, ctypes.c_void_p(), ctypes.c_size_t(0), ctypes.c_uint(1))
    if abi < 3:
        raise NativeReadPolicyError('Native Acquisition requires Landlock ABI >=3 with truncate control')
    handled = (1 << 15) - 1
    if abi >= 5:
        handled |= 1 << 15
    ruleset = _Ruleset(handled)
    descriptor = libc.syscall(444, ctypes.byref(ruleset), ctypes.sizeof(ruleset), 0)
    if descriptor < 0:
        raise OSError(ctypes.get_errno(), 'Cannot create native read ruleset')
    def add(path, rights):
        fd = os.open(path, os.O_PATH | os.O_CLOEXEC)
        try:
            rule = _PathRule(rights, fd)
            if libc.syscall(445, descriptor, 1, ctypes.byref(rule), 0):
                raise OSError(ctypes.get_errno(), 'Cannot admit exact native dependency role')
        finally:
            os.close(fd)
    try:
        for path in admitted:
            add(path, READ_FILE)
        if buffer is not None:
            add(buffer, WRITE_FILE | TRUNCATE)
        if libc.prctl(38, 1, 0, 0, 0):
            raise OSError(ctypes.get_errno(), 'Cannot enable no_new_privs for native actor')
        if libc.syscall(446, descriptor, 0):
            raise OSError(ctypes.get_errno(), 'Cannot enforce native read ruleset')
        descendants=_deny_process_descendants(libc)
    finally:
        os.close(descriptor)
    return {'schema': 'gxtxt.native_acquisition_read_policy.v1', 'active': True,
            'mechanism': 'Linux Landlock', 'abi': abi, 'required_before_authored_load': True,
            'read_files': [str(path) for path in admitted],
            'buffer_write_root': str(buffer) if buffer is not None else None,
            'buffer_rights': ['WRITE_FILE', 'TRUNCATE'] if buffer is not None else [],
            'execute_allowed': False, 'closed_unrelated_fds': closed,
            'source_paths_or_fds_admitted': False,
            'process_policy': descendants,
            'limits': 'Filesystem scope only; no account/network hostile-code isolation claim'}
