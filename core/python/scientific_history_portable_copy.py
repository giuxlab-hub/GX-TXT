# SPDX-License-Identifier: GPL-3.0-or-later
"""CORE native-History snapshot locks; serialization remains the C++ engine's."""
from __future__ import annotations
import argparse
from contextlib import contextmanager
from pathlib import Path
import re
import shutil
import stat
try:
    import fcntl
except ImportError:
    fcntl = None

BOUND = re.compile(r"idoc_[0-9]{4,}(?:\.[A-Za-z][A-Za-z0-9_]{0,63})?\.gxh")
DRAFT = re.compile(r"[0-9]+-[0-9]+-[0-9]+\.gxh")


def families(session: Path, documents: list[str] | None = None):
    root = session / 'metadata' / 'history'
    if not root.exists():
        return []
    if root.is_symlink() or not root.is_dir():
        raise ValueError('Native History root must be a real directory')
    selected = None if documents is None else set(documents)
    found = set()
    for directory in [root] + ([root / 'drafts'] if selected is None else []):
        if not directory.exists():
            continue
        if directory.is_symlink() or not directory.is_dir():
            raise ValueError('Native History family directory is unsafe')
        for entry in directory.iterdir():
            name = entry.name
            if name.endswith('.gxh.checkpoint'):
                name = name[:-11]
            elif name.endswith('.gxh.lock'):
                # Native open takes its owner lock before its background
                # worker publishes the first checkpoint. A lock-only active
                # family must still block an external snapshot.
                name = name[:-5]
            elif not name.endswith('.gxh'):
                continue
            match = DRAFT.fullmatch(name) if directory.name == 'drafts' else BOUND.fullmatch(name)
            if not match:
                raise ValueError(f'Invalid native History family: {entry}')
            if selected is not None and name.split('.')[0] not in selected:
                continue
            found.add(directory / name)
    return sorted(found)


@contextmanager
def history_read_locks(session: Path, owned=(), documents=None):
    """Known active writers were drained by this blocked interpreter's caller."""
    active = {str(Path(path).resolve()) for path in owned}
    locks = []
    paths = families(session, documents)
    try:
        for path in paths:
            for member in (path, Path(str(path) + '.checkpoint')):
                if member.exists() and (member.is_symlink() or not stat.S_ISREG(member.lstat().st_mode)):
                    raise ValueError(f'Unsafe native History member: {member}')
            lock = Path(str(path) + '.lock')
            if lock.is_symlink() or not lock.is_file():
                raise ValueError(f'Native History requires its regular owner lock: {path}')
            if str(path.resolve()) in active:
                continue
            if fcntl is None:
                raise RuntimeError('Native History transport requires operating-system file locks')
            stream = lock.open('rb')
            try:
                fcntl.flock(stream.fileno(), fcntl.LOCK_SH | fcntl.LOCK_NB)
            except BlockingIOError:
                stream.close()
                raise ValueError(f'Native History has a foreign active writer; finish/close it before transport: {path}') from None
            locks.append(stream)
        yield paths
    finally:
        for stream in reversed(locks):
            stream.close()


def copy_families(source: Path, destination: Path, documents=None, owned=()):
    if destination.exists():
        raise ValueError('History snapshot copy requires a fresh directory')
    with history_read_locks(source, owned, documents) as paths:
        destination.mkdir(parents=True, mode=0o700)
        for path in paths:
            for member in (path, Path(str(path) + '.checkpoint')):
                if member.exists():
                    relative = member.relative_to(source)
                    target = destination / relative
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(member, target)
    return len(paths)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--document', action='append', default=None)
    parser.add_argument('--owned', action='append', default=[])
    args = parser.parse_args()
    print(copy_families(args.source.resolve(), args.destination.resolve(), args.document, args.owned))

if __name__ == '__main__':
    main()
