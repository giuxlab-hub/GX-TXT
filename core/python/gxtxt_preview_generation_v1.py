# SPDX-License-Identifier: GPL-3.0-or-later
"""Builder adapter to the existing restricted C++ source/build/export owner."""
from pathlib import Path
import hashlib
import json
import os
import signal
import stat
import subprocess
import sys
import tempfile


def generate(design, source, output):
    from gxtxt_project_grant import check_project_root
    from gxtxt_viewer_development import FRAMEWORK, dictionary
    design = dictionary(design)
    source, output = Path(source).absolute(), Path(output).absolute()
    check_project_root(source, allow_missing=True)
    if not output.is_dir() or output.resolve(strict=True) != output:
        raise ValueError('Choose an existing ordinary output directory')
    for root in (FRAMEWORK, Path('/srv/gxtxt/main/script-ag'), Path('/srv/gxtxt/releases')):
        root = root.resolve()
        if any(path==root or path.is_relative_to(root) or root.is_relative_to(path) for path in (source,output)):
            raise ValueError('Generation refuses framework, live installation and release locations')
    target = output / (design['module_id'] + '_' + design['version'] + '.zip')
    sidecar = target.with_suffix('.zip.sha256')
    if any(path.exists() or path.is_symlink() for path in (target, sidecar)):
        raise FileExistsError('Refusing to overwrite an existing Preview delivery')
    # The compiler/project write grant is installed only in the existing
    # Development child. The controller can publish the exact resulting ZIP.
    command = [sys.executable, '-I', '-B', str(FRAMEWORK/'core/python/gxtxt_viewer_development.py'),
               'generate_preview', str(source)]
    request = dict(schema='gxtxt.preview_generation.v1', module_id=design['module_id'],
                   design=__import__('gxtxt_job_supervisor').tcl_result(design))
    # Values remain inert Tcl strings. No authored Tcl command is evaluated.
    child = None
    def retire():
        if child is None or child.poll() is not None:
            return
        try: os.killpg(child.pid, signal.SIGTERM)
        except ProcessLookupError: pass
        try: child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try: os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError: pass
            child.wait(timeout=3)
    def cancelled(signum, frame):
        retire()
        raise SystemExit(128+signum)
    handlers = {signum: signal.signal(signum, cancelled) for signum in (signal.SIGTERM, signal.SIGINT)}
    try:
        with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
            child = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=stdout, stderr=stderr,
                                     start_new_session=True, close_fds=True)
            child.communicate((json.dumps(request, ensure_ascii=False)+'\n').encode(), timeout=150)
            stdout.seek(0); stderr.seek(0)
            raw, diagnostic = stdout.read(1048577), stderr.read(8193)
        if len(raw)>1048576:
            raise ValueError('Native generation response exceeds its bound')
        response = json.loads(raw)
        if child.returncode or response.get('ok') is not True:
            raise ValueError(response.get('error', 'Restricted C++ Preview generation failed'))
        result = response['result']
        package = Path(result['package'])
        if package.resolve(strict=True)!=package or not package.is_relative_to(source/'candidates'):
            raise ValueError('Native candidate escapes its source project')
        fd = os.open(package, os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK|os.O_CLOEXEC)
        with os.fdopen(fd, 'rb') as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_nlink!=1 or info.st_size>33554432:
                raise ValueError('Native candidate is not an ordinary bounded package')
            payload = stream.read(33554433)
        sha = hashlib.sha256(payload).hexdigest()
        if sha!=result['sha256']:
            raise ValueError('Native candidate SHA differs')
        # Publish new files only. Never regenerate or repackage native members.
        with target.open('xb') as stream:
            stream.write(payload); stream.flush(); os.fsync(stream.fileno())
        with sidecar.open('x', encoding='ascii') as stream:
            stream.write(sha+'  '+target.name+'\n'); stream.flush(); os.fsync(stream.fileno())
        return target, sha
    finally:
        retire()
        for signum, handler in handlers.items():signal.signal(signum, handler)
