# SPDX-License-Identifier: GPL-3.0-or-later
"""Irreversible Linux project-write tool grant for cooperative Viewer authors."""
from __future__ import annotations
import ctypes
import os
from pathlib import Path
import platform
import pwd
import stat

class Ruleset(ctypes.Structure):
    _fields_ = [('handled_access_fs', ctypes.c_uint64)]

class PathRule(ctypes.Structure):
    _pack_ = 1
    _fields_ = [('allowed_access', ctypes.c_uint64), ('parent_fd', ctypes.c_int32)]

def check_project_root(project: Path, allow_missing=False) -> Path:
    project = Path(project)
    missing = not project.exists()
    if not project.is_absolute() or project.is_symlink() or (not project.is_dir() and not (allow_missing and missing and project.parent.is_dir())):
        raise ValueError('Project-write grant requires an existing real absolute directory')
    resolved = project.resolve(strict=not missing)
    if resolved != project:
        raise ValueError('Project-write grant refuses symlinked ancestors')
    home = Path(pwd.getpwuid(os.getuid()).pw_dir)
    framework = Path(__file__).resolve().parents[2]
    protected = [framework, home/'script-ag', home/'ag-script',
                 home/'electronics-server/scripts/GXTXT',
                 home/'electronics-server/work-agent/restore-points',
                 home/'electronics-server/progetti_giux', Path('/usr'), Path('/etc'),
                 Path('/bin'), Path('/lib'), Path('/boot'), Path('/var')]
    for item in protected:
        item = item.resolve()
        if resolved == item or resolved.is_relative_to(item) or item.is_relative_to(resolved):
            raise ValueError('Project-write grant refuses a protected framework, installation, data, restore or system location')
    # No preexisting hardlink may give a project pathname write access to another inode owner.
    if missing: return resolved
    count = 0
    for directory, directories, files in os.walk(resolved, followlinks=False):
        for name in directories + files:
            count += 1
            if count > 10000: raise ValueError('Project exceeds the 10,000-entry grant audit bound')
            p = Path(directory)/name
            try:
                info = p.lstat()
            except FileNotFoundError:
                # Concurrent ordinary owner operations atomically rename their
                # temporary receipt files. A vanished entry grants no path.
                continue
            if stat.S_ISLNK(info.st_mode) or (stat.S_ISREG(info.st_mode) and info.st_nlink != 1):
                raise ValueError('Project-write grant refuses symlinks and hardlinked files')
            if not (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode)):
                raise ValueError('Project-write grant accepts ordinary files/directories only')
    return resolved

def enforce_project_write(project: Path) -> dict:
    """Fail closed; restrict this thread and all future descendants to project writes.

    Read access remains necessary for the fixed CORE SDK/compiler/runtime. This is
    a write grant, not a claim that Landlock covers all filesystem metadata calls.
    """
    project = check_project_root(project)
    if platform.system() != 'Linux' or platform.machine() not in {'x86_64', 'aarch64'}:
        raise RuntimeError('Project-write grant requires supported native Linux Landlock')
    libc = ctypes.CDLL(None, use_errno=True)
    libc.syscall.restype = ctypes.c_long
    abi = libc.syscall(444, ctypes.c_void_p(), ctypes.c_size_t(0), ctypes.c_uint(1))
    if abi < 3:
        raise RuntimeError('Project-write grant requires Landlock ABI >=3 including file truncation protection')
    # Write, remove, create and cross-directory refer/truncate rights are default-denied.
    handled = sum(1 << bit for bit in (1,4,5,6,7,8,9,10,11,12,13,14))
    if abi >= 5: handled |= 1 << 15  # Device ioctl is denied; projects contain no devices.
    allowed = sum(1 << bit for bit in (1,4,5,7,8,12,13,14))
    ruleset = Ruleset(handled)
    ruleset_fd = libc.syscall(444, ctypes.byref(ruleset), ctypes.sizeof(ruleset), 0)
    if ruleset_fd < 0: raise OSError(ctypes.get_errno(), 'Cannot create project-write ruleset')
    project_fd = os.open(project, os.O_PATH | os.O_CLOEXEC | os.O_DIRECTORY)
    try:
        rule = PathRule(allowed, project_fd)
        if libc.syscall(445, ruleset_fd, 1, ctypes.byref(rule), 0):
            raise OSError(ctypes.get_errno(), 'Cannot add project-write path rule')
        if libc.prctl(38, 1, 0, 0, 0):
            raise OSError(ctypes.get_errno(), 'Cannot set no_new_privs')
        if libc.syscall(446, ruleset_fd, 0):
            raise OSError(ctypes.get_errno(), 'Cannot enforce project-write ruleset')
    finally:
        os.close(project_fd);os.close(ruleset_fd)
    return {'mechanism':'Linux Landlock project-write tool grant', 'abi':abi,
            'project':str(project), 'write_scope':'project and descendants only',
            'read_scope':'existing Unix permissions', 'no_new_privs':True,
            'limits':'No general hostile-code or filesystem-metadata isolation claim; this grant applies to this process tree, not every shell of the account.'}
