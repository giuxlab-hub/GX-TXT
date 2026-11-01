#!/usr/bin/env python3
"""P024 immutable file transport; scientific graphs belong to the native capsule."""
# SPDX-License-Identifier: GPL-3.0-or-later
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import tempfile
import zipfile

RESOURCE = re.compile(r"resources/(idoc_[0-9]{4,32})/([a-f0-9]{64})\.blob\Z")
MAX_BYTES = 2 * 1024**3


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def regular(path):
    for parent in (path, *path.parents):
        if parent.is_symlink():
            raise ValueError('Native package path contains a symlink')
    if not path.is_file():
        raise ValueError('Native package file is unavailable')


def members(stage):
    result = {}
    total = 0
    for path in sorted(stage.rglob('*')):
        if path.is_dir() and not path.is_symlink():
            continue
        regular(path)
        rel = path.relative_to(stage).as_posix()
        if rel != 'workspace.native' and not RESOURCE.fullmatch(rel):
            raise ValueError('Unknown native package member')
        size = path.stat().st_size
        total += size
        if total > MAX_BYTES or len(result) >= 10000:
            raise ValueError('Native package exceeds file/byte bound')
        sha = digest(path)
        match = RESOURCE.fullmatch(rel)
        if match and sha != match[2]:
            raise ValueError('Native package blob digest differs')
        result[rel] = {'size': size, 'sha256': sha}
    if 'workspace.native' not in result:
        raise ValueError('Native Workspace capsule missing')
    return result


def export(stage, archive):
    files = members(stage)
    manifest = {'format': 'GXTXT_NATIVE_WORKSPACE_PACKAGE_v1', 'files': files}
    with zipfile.ZipFile(archive, 'x', compression=zipfile.ZIP_STORED) as z:
        z.writestr('manifest.json', json.dumps(manifest, sort_keys=True).encode())
        for rel in files:
            z.write(stage / rel, rel)


def extract(archive, stage):
    if stage.exists():
        raise ValueError('Native package staging directory must be new')
    with zipfile.ZipFile(archive) as z:
        infos = z.infolist()
        names = [i.filename for i in infos]
        if len(names) != len(set(names)) or len(names) > 10001:
            raise ValueError('Duplicate/excessive native package members')
        if 'manifest.json' not in names or z.getinfo('manifest.json').file_size > 2097152:
            raise ValueError('Native manifest is missing/too large; obsolete Tcl packages are unsupported')
        manifest = json.loads(z.read('manifest.json'))
        if manifest.get('format') != 'GXTXT_NATIVE_WORKSPACE_PACKAGE_v1':
            raise ValueError('Unsupported native Workspace package')
        files = manifest['files']
        if set(names) != set(files) | {'manifest.json'} or 'workspace.native' not in files:
            raise ValueError('Native manifest member set differs')
        total = 0
        for info in infos:
            if info.filename == 'manifest.json':
                continue
            if info.filename != 'workspace.native' and not RESOURCE.fullmatch(info.filename):
                raise ValueError('Unsafe native package path')
            mode = info.external_attr >> 16
            if stat.S_IFMT(mode) not in (0, stat.S_IFREG) or info.flag_bits & 1:
                raise ValueError('Native package requires unencrypted regular files')
            total += info.file_size
            if total > MAX_BYTES or info.file_size != files[info.filename]['size']:
                raise ValueError('Native package declared size differs')
        stage.mkdir(mode=0o700)
        for info in infos:
            if info.filename == 'manifest.json':
                continue
            target = stage / info.filename
            target.parent.mkdir(parents=True, exist_ok=True)
            with z.open(info) as src, target.open('xb') as dst:
                shutil.copyfileobj(src, dst, 1024 * 1024)
            if digest(target) != files[info.filename]['sha256']:
                raise ValueError('Native package member digest differs')
        if members(stage) != files:
            raise ValueError('Native package verified manifest differs')


def adopt(stage, session, plan):
    # The Tcl host verified every native resource owner/generation before this
    # immutable byte step. A plan contains ONLY capsule-declared resource paths.
    requested = plan.read_text(encoding='utf-8').splitlines()
    packaged = set(members(stage)) - {'workspace.native'}
    if set(requested) != packaged or len(requested) != len(packaged):
        raise ValueError('Capsule resource inventory differs from package')
    for rel in requested:
        match = RESOURCE.fullmatch(rel)
        if not match:
            raise ValueError('Invalid native resource plan')
        source = stage / rel
        target = session / 'metadata' / 'interactive_document_resources' / match[1] / (match[2] + '.blob')
        for parent in (target, *target.parents):
            if parent.is_symlink():
                raise ValueError('Imported resource destination contains a symlink')
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            regular(target)
            if target.stat().st_size != source.stat().st_size or digest(target) != match[2]:
                raise ValueError('Imported resource collides with existing immutable bytes')
            continue
        # Exclusive creation never replaces existing scientific data. Native
        # commit independently verifies and fsyncs bytes/directories afterward.
        # Complete and fsync a private temporary before exclusively publishing
        # its immutable name. Interrupted copying can never leave a truncated
        # content-addressed .blob that blocks a later healthy import.
        fd, temporary_name = tempfile.mkstemp(prefix='.native-import-', dir=target.parent)
        temporary = Path(temporary_name)
        try:
            with os.fdopen(fd, 'wb') as dst, source.open('rb') as src:
                shutil.copyfileobj(src, dst, 1024 * 1024)
                dst.flush()
                os.fsync(dst.fileno())
            try:
                os.link(temporary, target, follow_symlinks=False)
            except FileExistsError:
                regular(target)
                if target.stat().st_size != source.stat().st_size or digest(target) != match[2]:
                    raise ValueError('Concurrent imported resource collision') from None
        finally:
            temporary.unlink(missing_ok=True)



if __name__ == '__main__':
    try:
        operation, *args = sys.argv[1:]
        if operation == 'export' and len(args) == 2:
            export(*map(Path, args))
        elif operation == 'extract' and len(args) == 2:
            extract(*map(Path, args))
        elif operation == 'adopt' and len(args) == 3:
            adopt(*map(Path, args))
        else:
            raise ValueError('Usage: native_workspace_portable_v1.py export|extract|adopt ...')
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
