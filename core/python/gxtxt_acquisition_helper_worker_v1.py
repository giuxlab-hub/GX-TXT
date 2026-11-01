# SPDX-License-Identifier: GPL-3.0-or-later
"""Fixed subordinate helper actor. CORE owns registration, leases and reap.

One process, one helper call; no host calls, RAW descriptors or output buffers.
The kernel policy is a filesystem/process boundary, not a Python language,
account or network sandbox. Tcl additionally uses a bounded safe interpreter.
"""
from __future__ import annotations
import base64
import builtins
import ctypes
import hashlib
import json
import math
import os
from pathlib import Path
import re
import resource
import signal
import stat
import struct
import sys
import types

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gxtxt_acquisition_native_worker_v1 import Worker, WorkerError, decode, wire, sha
from gxtxt_native_read_policy_v1 import activate_native_read_policy

ROOT = Path(__file__).resolve().parents[2]
TCL_WORKER = ROOT/'core/tcl/acquisition_helper_worker_v1.tcl'
CODEC_ADAPTER = ROOT/'core/tcl/native_workspace_api_v1.tcl'
CODEC = ROOT/'core/workspace/libgxtxt_workspace.so'
SCHEMA = 'gxtxt.acquisition_helper_request.v1'
MODULES = {m.__name__: m for m in (math, re, struct, json, base64)}


def ordinary(path, maximum=65536, *, preloaded_core=False):
    path = Path(path)
    if not path.is_absolute() or path.resolve(strict=True) != path or any(p.is_symlink() for p in [path, *path.parents]):
        raise WorkerError('Helper source must be an admitted canonical ordinary file')
    fd = os.open(path, os.O_RDONLY|os.O_CLOEXEC|os.O_NOFOLLOW|os.O_NONBLOCK)
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or (before.st_mode & 0o022 and not preloaded_core) or before.st_size > maximum:
            raise WorkerError('Helper source exceeds its ordinary file grant')
        data = bytearray()
        while len(data) <= maximum:
            chunk = os.read(fd, min(65536, maximum+1-len(data)))
            if not chunk: break
            data.extend(chunk)
        after = os.fstat(fd); current = os.stat(path, follow_symlinks=False)
        fields = lambda s: (s.st_dev, s.st_ino, s.st_mode, s.st_nlink, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
        if len(data) > maximum or fields(before) != fields(after) or fields(after) != fields(current):
            raise WorkerError('Helper source changed during admission')
        return bytes(data)
    finally:
        os.close(fd)


def identity(path, *, preloaded_core=False):
    return dict(path=str(path), sha256=hashlib.sha256(ordinary(path, 16777216, preloaded_core=preloaded_core)).hexdigest())


def runtime_closure(preloaded):
    # The CORE codec is verified/preloaded separately. It is not misrepresented
    # as a root-owned system dependency or granted filesystem read rights.
    paths = set()
    for line in Path('/proc/self/maps').read_text().splitlines():
        parts = line.split(None, 5)
        if len(parts) == 6 and parts[5].startswith('/'):
            if parts[5].endswith(' (deleted)'): raise WorkerError('Mapped helper runtime was removed')
            path = Path(parts[5]).resolve(strict=True)
            if path not in preloaded: paths.add(path)
    result = []
    for path in sorted(paths):
        info = path.stat()
        if info.st_uid != 0 or info.st_mode & 0o022 or not stat.S_ISREG(info.st_mode):
            raise WorkerError('Helper dependency is not a reviewed system runtime')
        result.append(dict(path=str(path), sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    return result


class HelperWorker(Worker):
    def __init__(self):
        super().__init__()
        self.diagnostics = ''; self.context = None

    def diagnostic(self, *args):
        # Tcl puts accepts only inert diagnostic text, never a channel handle.
        if len(args) == 2 and args[0] == '-nonewline': text = str(args[1])
        elif len(args) == 1: text = str(args[0])+'\n'
        else: raise WorkerError('Helper diagnostic puts accepts text only')
        self.write(text)
        return ''

    def write(self, text):
        if not isinstance(text, str): raise WorkerError('Helper diagnostics require text')
        available = 8192-len(self.diagnostics.encode('utf-8'))
        if len(text.encode('utf-8')) > available: raise WorkerError('Helper diagnostics exceed 8 KiB')
        self.diagnostics += text
        return len(text)

    def flush(self): pass

    def bootstrap(self, hello):
        if not isinstance(hello, dict) or set(hello) != {'schema','kind','request_id','helper_call_id','phase','qualified_profile','module_snapshot','helper','args','_trusted_runtime'} or hello['schema'] != SCHEMA or hello['kind'] != 'hello':
            raise WorkerError('Exact helper hello schema required')
        sha(hello['request_id']); sha(hello['helper_call_id'])
        if hello['phase'] not in {'recognize','inspect','test','import'} or not isinstance(hello['qualified_profile'], str) or not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', hello['qualified_profile']):
            raise WorkerError('Helper requires an admitted phase/profile')
        decode(wire(hello['module_snapshot'], 65536)); decode(wire(hello['args'], 196609))
        if not isinstance(hello['module_snapshot'], dict): raise WorkerError('Helper module snapshot must be an object')
        helper = hello['helper']; runtime = hello['_trusted_runtime']
        if not isinstance(helper, dict) or set(helper) != {'id','language','entrypoint','source_sha256'} or not isinstance(helper['id'],str) or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_.-]{0,127}',helper['id']):
            raise WorkerError('Exact registered helper identity required')
        sha(helper['source_sha256'])
        pattern = r'[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*' if helper['language'] == 'Python' else r'(?:::)?[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*'
        if helper['language'] not in {'Python','Tcl'} or not isinstance(helper['entrypoint'], str) or len(helper['entrypoint']) > 192 or not re.fullmatch(pattern, helper['entrypoint']) or any(part.startswith('__') for part in helper['entrypoint'].replace('::','.').split('.')):
            raise WorkerError('Helper requires a finite registered function/proc name')
        if not isinstance(runtime, dict) or set(runtime) != {'source_path'}: raise WorkerError('Exact trusted helper source role required')
        raw = ordinary(runtime['source_path'])
        if hashlib.sha256(raw).hexdigest() != helper['source_sha256']: raise WorkerError('Registered helper source SHA differs')
        self.source = raw.decode('utf-8-sig', errors='strict')
        if '\0' in self.source: raise WorkerError('Helper source contains NUL')
        self.hello = hello
        factory = {'worker': identity(Path(__file__).resolve(), preloaded_core=True), 'protocol': 1,
                   'protocol_owner': identity(ROOT/'core/python/gxtxt_acquisition_native_worker_v1.py', preloaded_core=True),
                   'read_policy': identity(ROOT/'core/python/gxtxt_native_read_policy_v1.py', preloaded_core=True)}
        preloaded = set()
        if helper['language'] == 'Tcl':
            import tkinter
            factory.update(tcl_worker=identity(TCL_WORKER, preloaded_core=True), codec_adapter=identity(CODEC_ADAPTER, preloaded_core=True), preloaded_core_codec=identity(CODEC, preloaded_core=True))
            master = tkinter.Tcl()
            master.eval('namespace eval ::GX {}')
            master.setvar('::GX::scriptDir', str(ROOT))
            master.eval(ordinary(CODEC_ADAPTER, preloaded_core=True).decode('utf-8'))
            # Existing CORE distributions can carry group-writable executable
            # mode; this is an exact pinned trusted preload, not a system read
            # role. Load the opened inode, then recheck the normal path/hash.
            codec_fd = os.open(CODEC, os.O_RDONLY|os.O_CLOEXEC|os.O_NOFOLLOW|os.O_NONBLOCK)
            try:
                master.call('load', '/proc/self/fd/'+str(codec_fd), 'Gxtxt_workspace')
            finally:
                os.close(codec_fd)
            if identity(CODEC, preloaded_core=True) != factory['preloaded_core_codec']:
                raise WorkerError('Trusted preloaded CORE codec changed')
            master.call('::GX::nativeWorkspaceJsonDecode', '{}')
            master.eval(ordinary(TCL_WORKER, preloaded_core=True).decode('utf-8'))
            master.createcommand('::GX::AcquisitionHelper::diagnostic', self.diagnostic)
            child = master.call('::GX::AcquisitionHelper::prepare')
            self.context = (master, child)
            factory['tcl_version'] = master.call('info', 'patchlevel')
            preloaded.add(CODEC.resolve(strict=True))
        else:
            self.code = compile(self.source, '<gxtxt-registered-helper>', 'exec', dont_inherit=True)
        closure = runtime_closure(preloaded)
        resource.setrlimit(resource.RLIMIT_CPU, (2,2))
        resource.setrlimit(resource.RLIMIT_AS, (268435456,268435456))
        resource.setrlimit(resource.RLIMIT_CORE, (0,0))
        resource.setrlimit(resource.RLIMIT_FSIZE, (0,0))
        signal.alarm(5)
        # Original stdout is a private protocol pipe; authored stdout is a
        # separate diagnostics stream drained/capped by the CORE supervisor.
        self.channel = os.dup(1); os.set_inheritable(self.channel, False)
        os.dup2(2, 1)
        sys.stdout = self; sys.stderr = self
        guard = activate_native_read_policy(dict(path=runtime['source_path'], sha256=helper['source_sha256']), closure, protocol_fds=(self.channel,))
        guard['before_authored_load'] = True
        if not guard['process_policy']['enforced'] or guard['buffer_write_root'] is not None:
            raise WorkerError('Helper enforcement is unavailable')
        return dict(kind='ready', request_id=hello['request_id'], helper_call_id=hello['helper_call_id'], helper_id=helper['id'], source_sha256=helper['source_sha256'], worker_pid=os.getpid(), factory_identity=factory, guard_receipt=guard)

    def invoke(self):
        hello = self.hello; helper = hello['helper']; entry = helper['entrypoint']
        if helper['language'] == 'Tcl':
            master, child = self.context
            encoded = master.call('::GX::AcquisitionHelper::invoke', child, self.source, entry, wire(hello['args'],196609).decode('utf-8'))
            return decode(str(encoded).encode('utf-8'))
        def admitted_import(name, globals=None, locals=None, fromlist=(), level=0):
            if level or name not in MODULES: raise WorkerError('Helper import is not in the preloaded metadata runtime')
            return MODULES[name]
        # Convenience builtins are not a Python hostile-code isolation claim;
        # kernel read/process enforcement remains active even through reflection.
        namespace = {'__builtins__': dict(vars(builtins), __import__=admitted_import), '__name__': 'gxtxt_registered_helper'}
        exec(self.code, namespace, namespace)
        value = namespace
        for part in entry.split('.'):
            value = value.get(part) if isinstance(value,dict) else getattr(value,part,None)
        if not isinstance(value, types.FunctionType) or value.__code__.co_filename != '<gxtxt-registered-helper>' or value.__code__.co_argcount != 1 or value.__code__.co_kwonlyargcount or value.__code__.co_flags & 12:
            raise WorkerError('Registered helper must be an authored Python function')
        return decode(wire(value(hello['args']),196609))

    def run(self):
        hello = self.receive(); ready = self.bootstrap(hello); self.send(ready)
        if self.receive() != dict(kind='invoke', request_id=hello['request_id'], helper_call_id=hello['helper_call_id']):
            raise WorkerError('Helper invoke differs from admitted channel')
        result = self.invoke()
        self.send(dict(kind='complete', request_id=hello['request_id'], helper_call_id=hello['helper_call_id'], status='completed', result=result, diagnostics=self.diagnostics))


def main():
    worker = HelperWorker()
    try:
        worker.run()
        return 0
    except BaseException as error:
        # Error text is bounded; no traceback/source paths become authored data.
        receipt = dict(kind='complete', status='failed', result=None, diagnostics=str(error).encode('utf-8')[:8192].decode('utf-8',errors='replace'))
        if worker.hello:
            receipt.update(request_id=worker.hello['request_id'], helper_call_id=worker.hello['helper_call_id'])
        try: worker.send(receipt)
        except BaseException: pass
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
