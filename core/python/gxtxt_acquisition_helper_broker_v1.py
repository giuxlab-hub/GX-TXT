# SPDX-License-Identifier: GPL-3.0-or-later
"""Private CORE helper dispatcher under an already admitted Acquisition Job.

No SourceGrant, output owner, scheduler or publication interface exists here.
The caller supplies the actual pinned project roster and live authority check.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import secrets
import select
import stat
import subprocess
import sys
import time

from gxtxt_acquisition_broker_v1 import AcquisitionNativeBroker, AcquisitionBrokerError
from gxtxt_acquisition_native_worker_v1 import decode, wire
from gxtxt_acquisition_helper_worker_v1 import ordinary
import gxtxt_acquisition_project_v1 as project_model

ROOT = Path(__file__).resolve().parents[2]


class AcquisitionHelperBroker(AcquisitionNativeBroker):
    """One request's finite helper budget; every call creates/reaps one actor."""
    MAX_CALLS = 32
    METADATA_BYTES = 1048576
    TOTAL_SECONDS = 30

    def __init__(self, scope, source_root, helpers, source_files, validate_scope, *,
                 admitted_operations, runtime_pins):
        if not callable(validate_scope): raise AcquisitionBrokerError('Live CORE helper validator required')
        self.scope = decode(wire(scope))
        self.validate_scope = validate_scope
        self._operations = frozenset(admitted_operations)
        self.root = Path(source_root).resolve(strict=True)
        self.pins = dict(runtime_pins)
        self.helpers = {}
        if not isinstance(helpers, list) or len(helpers) > 32:
            raise AcquisitionBrokerError('Bounded actual registered helper roster required')
        for helper in helpers:
            project_model.helper_validate(helper)
            if helper['id'] in self.helpers or helper['path'] not in source_files:
                raise AcquisitionBrokerError('Helper roster differs from actual source closure')
            path = self.root/helper['path']
            digest = hashlib.sha256(source_files[helper['path']]).hexdigest()
            if self.pins.get(str(path)) != digest:
                raise AcquisitionBrokerError('Helper source lacks its actual admitted closure pin')
            self.helpers[helper['id']] = dict(helper, source_sha256=digest, source_path=str(path))
        self.calls = 0; self.bytes = 0; self.elapsed = 0.0; self.receipts = []
        self._process = None
        self._check()

    def _budget(self, amount):
        self.bytes += amount
        if self.bytes > self.METADATA_BYTES:
            raise AcquisitionBrokerError('Cumulative helper metadata exceeds 1 MiB')

    def _pin(self, path):
        path = Path(path)
        value = self.pins.get(str(path))
        if value is None or hashlib.sha256(ordinary(path,16777216,preloaded_core=True)).hexdigest() != value:
            raise AcquisitionBrokerError('CORE helper factory/runtime pin changed')
        return dict(path=str(path), sha256=value)

    def _factory(self, language):
        result = dict(protocol=1,
            worker=self._pin(ROOT/'core/python/gxtxt_acquisition_helper_worker_v1.py'),
            protocol_owner=self._pin(ROOT/'core/python/gxtxt_acquisition_native_worker_v1.py'),
            read_policy=self._pin(ROOT/'core/python/gxtxt_native_read_policy_v1.py'))
        if language == 'Tcl':
            result.update(tcl_worker=self._pin(ROOT/'core/tcl/acquisition_helper_worker_v1.tcl'),
                codec_adapter=self._pin(ROOT/'core/tcl/native_workspace_api_v1.tcl'),
                preloaded_core_codec=self._pin(ROOT/'core/workspace/libgxtxt_workspace.so'))
        return result

    def _ready(self, ready, helper, call_id, factory):
        if set(ready) != {'kind','request_id','helper_call_id','helper_id','source_sha256','worker_pid','factory_identity','guard_receipt'} or ready['kind'] != 'ready' or ready['request_id'] != self.scope['request_id'] or ready['helper_call_id'] != call_id or ready['helper_id'] != helper['id'] or ready['source_sha256'] != helper['source_sha256'] or type(ready['worker_pid']) is not int or ready['worker_pid'] != self._process.pid:
            raise AcquisitionBrokerError('Helper ready identity differs from the actual actor')
        actual = dict(ready['factory_identity'])
        if helper['language'] == 'Tcl':
            version = actual.pop('tcl_version', None)
            if not isinstance(version, str) or not version.startswith('8.6.'):
                raise AcquisitionBrokerError('Helper Tcl runtime version is unsupported')
        if actual != factory: raise AcquisitionBrokerError('Helper factory closure differs from actual CORE pins')
        guard = ready['guard_receipt']; policy = guard.get('process_policy', {})
        process = dict(enforced=True,fork='EPERM',vfork='EPERM',process_clone='EPERM',clone3='ENOSYS',exec='EPERM',threads='CLONE_THREAD_ONLY')
        if guard.get('schema') != 'gxtxt.native_acquisition_read_policy.v1' or guard.get('active') is not True or guard.get('before_authored_load') is not True or guard.get('required_before_authored_load') is not True or guard.get('source_paths_or_fds_admitted') is not False or guard.get('execute_allowed') is not False or guard.get('buffer_write_root') is not None or guard.get('buffer_rights') != [] or any(policy.get(k) != v for k,v in process.items()):
            raise AcquisitionBrokerError('Helper filesystem/process guard was not enforced before authored execution')
        reads = guard.get('read_files')
        if not isinstance(reads, list) or not 2 <= len(reads) <= 129 or len(reads) != len(set(reads)) or helper['source_path'] not in reads:
            raise AcquisitionBrokerError('Helper read roles differ')
        for name in reads:
            if name == helper['source_path']: continue
            path = Path(name); info = path.stat(follow_symlinks=False)
            if not path.is_absolute() or path.resolve(strict=True) != path or not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
                raise AcquisitionBrokerError('Helper read grant exceeds its reviewed system dependencies')

    def _reap_completed(self):
        self._process.stdin.close()
        if self._read_buffer:
            raise AcquisitionBrokerError('Helper emitted extra protocol data')
        streams = [self._process.stdout, self._process.stderr]
        while streams:
            self._check()
            remaining = self._deadline-time.monotonic()
            if remaining <= 0: raise AcquisitionBrokerError('Completed helper did not drain/exit within its deadline')
            readable,_,_ = select.select(streams, [], [], min(.05,remaining))
            for stream in readable:
                chunk = os.read(stream.fileno(), 8192)
                if not chunk: streams.remove(stream); continue
                if stream is self._process.stdout:
                    raise AcquisitionBrokerError('Helper emitted extra protocol data after completion')
                self._stderr_seen += len(chunk)
                if self._stderr_seen > self._stderr_limit:
                    raise AcquisitionBrokerError('Helper raw diagnostics exceed 8 KiB')
                self._stderr.extend(chunk)
        if self._process.wait(timeout=max(.01,self._deadline-time.monotonic())) != 0:
            raise AcquisitionBrokerError('Helper did not exit normally')

    def __call__(self, helper_id, args):
        self._check()
        if 'helper_call' not in self._operations:
            raise AcquisitionBrokerError('Managed helper capability was not admitted')
        if not isinstance(helper_id, str) or helper_id not in self.helpers:
            raise AcquisitionBrokerError('Helper is outside the actual registered producer roster')
        self.calls += 1
        if self.calls > self.MAX_CALLS or self.elapsed >= self.TOTAL_SECONDS:
            raise AcquisitionBrokerError('Cumulative helper call/time budget exceeded')
        encoded = wire(args,196609); decode(encoded); self._budget(len(encoded))
        helper = self.helpers[helper_id]
        path = Path(helper['source_path'])
        if hashlib.sha256(project_model.ordinary_read(self.root,helper['path'])).hexdigest() != helper['source_sha256']:
            raise AcquisitionBrokerError('Registered helper source was revoked or changed')
        factory = self._factory(helper['language'])
        call_id = secrets.token_hex(32)
        self._read_buffer = bytearray(); self._stderr = bytearray()
        self._stderr_seen = 0; self._stderr_limit = 8192
        started = time.monotonic()
        self._deadline = started+min(6, self.TOTAL_SECONDS-self.elapsed)
        self._process = subprocess.Popen([sys.executable,'-I','-B',factory['worker']['path']],
            stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
            close_fds=True,bufsize=0,cwd='/',env={'PATH':'/usr/bin:/bin','LANG':'C.UTF-8','LC_ALL':'C.UTF-8'})
        try:
            os.set_blocking(self._process.stdin.fileno(), False)
            self._send(dict(schema='gxtxt.acquisition_helper_request.v1',kind='hello',
                request_id=self.scope['request_id'],helper_call_id=call_id,phase=self.scope['phase'],
                qualified_profile=self.scope['qualified_profile'],module_snapshot=self.scope['module_snapshot'],
                helper={key:helper[key] for key in ('id','language','entrypoint','source_sha256')},
                args=args,_trusted_runtime={'source_path':helper['source_path']}))
            ready = self._receive(self._deadline)
            self._ready(ready,helper,call_id,factory)
            self._check()
            self._send(dict(kind='invoke',request_id=self.scope['request_id'],helper_call_id=call_id))
            complete = self._receive(self._deadline)
            if set(complete) != {'kind','request_id','helper_call_id','status','result','diagnostics'} or complete['kind'] != 'complete' or complete['request_id'] != self.scope['request_id'] or complete['helper_call_id'] != call_id or complete['status'] != 'completed':
                raise AcquisitionBrokerError('Managed helper failed or returned a stale completion')
            diagnostic = complete['diagnostics']
            if not isinstance(diagnostic, str) or len(diagnostic.encode('utf-8')) > 8192:
                raise AcquisitionBrokerError('Helper diagnostic result exceeds 8 KiB')
            result = decode(wire(complete['result'],196609))
            self._budget(len(wire(result))+len(diagnostic.encode('utf-8')))
            self._reap_completed()
            self._budget(self._stderr_seen)
            self._check()
            if hashlib.sha256(project_model.ordinary_read(self.root,helper['path'])).hexdigest() != helper['source_sha256']:
                raise AcquisitionBrokerError('Registered helper source changed before handoff')
            if self._factory(helper['language']) != factory:
                raise AcquisitionBrokerError('Helper factory changed before handoff')
            self.receipts.append(dict(helper_id=helper_id,helper_call_id=call_id,
                source_sha256=helper['source_sha256'],worker_pid=ready['worker_pid'],actor_reaped=True,
                language=helper['language'],diagnostics=diagnostic,raw_diagnostics=self._stderr.decode('utf-8',errors='replace')))
            return result
        finally:
            self.elapsed += time.monotonic()-started
            if self._process.poll() is None: self._process.kill()
            self._process.wait(timeout=5)
            for stream in (self._process.stdin,self._process.stdout,self._process.stderr):
                if not stream.closed: stream.close()
