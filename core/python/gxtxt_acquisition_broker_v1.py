# SPDX-License-Identifier: GPL-3.0-or-later
"""Trusted native Acquisition orchestration under the existing managed Job.

This is an implementation unit, not an authored JSON grant or a second job or
publication engine. CORE admission constructs source/output owners and supplies
live authority callbacks. The fixed target worker gets no source FD or path.
"""
from __future__ import annotations

import base64
import json
import os
from pathlib import Path
import re
import select
import subprocess
import sys
import time


class AcquisitionBrokerError(ValueError):
    pass


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise AcquisitionBrokerError('Duplicate native protocol key')
        result[key] = value
    return result


class AcquisitionNativeBroker:
    """One already-admitted producer/profile invocation, owned by CORE.

    The caller's live check and source/output owners must bind the actual module
    closure, selected profile, request, lease and Session incarnation. This unit
    cannot infer or grant these from a plugin's claimed identity. Helper calls
    require an explicit CORE implementation; absent capability refuses.
    """

    FRAME_BYTES = 262144

    def __init__(self, scope, source_owner, output_owner, validate_scope, *,
                 admitted_operations, progress=None, helper=None, spectrum_validator=None, timeout_seconds=3600):
        if not callable(validate_scope):
            raise AcquisitionBrokerError('Live CORE authority validator required')
        self.scope = json.loads(json.dumps(scope, allow_nan=False))
        if not isinstance(self.scope, dict) or not isinstance(self.scope.get('request_id'), str) or not re.fullmatch('[0-9a-f]{64}', self.scope['request_id']):
            raise AcquisitionBrokerError('Native channel requires an opaque256-bit CORE request identity')
        if getattr(source_owner, '_scope', None) != self.scope or (output_owner is not None and getattr(output_owner, '_scope', None) != self.scope):
            raise AcquisitionBrokerError('Native source/output scopes must match the admitted request exactly')
        if (self.scope.get('phase') in {'test', 'import'}) != (output_owner is not None):
            raise AcquisitionBrokerError('Numeric output authority must match the actual request phase')
        self.sources = source_owner
        self.outputs = output_owner
        self.validate_scope = validate_scope
        self.progress = progress
        self.helper = helper
        self.spectrum_validator = spectrum_validator
        allowed = {'source_info', 'source_read', 'cancelled', 'progress',
                   'prepare_output', 'output_write', 'output_finish', 'helper_call',
                   'scientific_spectrum_parse', 'scientific_spectrum_read'}
        if not isinstance(admitted_operations, (list, tuple, set, frozenset)) or not admitted_operations or any(not isinstance(op, str) or op not in allowed for op in admitted_operations):
            raise AcquisitionBrokerError('Explicit finite CORE-admitted profile operations required')
        self._operations = frozenset(admitted_operations)
        if type(timeout_seconds) not in {int, float} or not 0 < timeout_seconds <= 3600:
            raise AcquisitionBrokerError('Bounded Acquisition deadline required')
        self.timeout = timeout_seconds
        self._used = False
        self._sequence = 0
        self._process = None
        self._read_buffer = bytearray()
        self._stderr = bytearray()
        self._spectra = None

    def _check(self):
        if self.validate_scope(json.loads(json.dumps(self.scope))) is False:
            raise AcquisitionBrokerError('Acquisition admission or lifetime was revoked')

    def _send(self, message):
        wire = json.dumps(message, allow_nan=False, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
        if len(wire) + 1 > self.FRAME_BYTES:
            raise AcquisitionBrokerError('Native control frame exceeds its bound')
        pending = memoryview(wire + b'\n')
        while pending:
            self._check()
            remaining = self._deadline - time.monotonic()
            if remaining <= 0:
                raise AcquisitionBrokerError('Native Acquisition write deadline expired')
            _, writable, _ = select.select([], [self._process.stdin], [], min(0.1, remaining))
            if not writable:
                continue
            try:
                count = os.write(self._process.stdin.fileno(), pending)
            except BlockingIOError:
                continue
            if count <= 0:
                raise AcquisitionBrokerError('Native control write failed')
            pending = pending[count:]

    def _receive(self, deadline):
        # Nonblocking byte framing avoids readline waiting forever on a partial
        # authored/crashed output. Job cancellation remains the outer owner.
        while True:
            self._check()
            if b'\n' in self._read_buffer:
                line, remainder = self._read_buffer.split(b'\n', 1)
                self._read_buffer = bytearray(remainder)
                try:
                    result = json.loads(line.decode('utf-8'), object_pairs_hook=_unique_object,
                        parse_constant=lambda _: (_ for _ in ()).throw(AcquisitionBrokerError('Nonfinite protocol value')))
                except (ValueError, UnicodeError):
                    raise AcquisitionBrokerError('Invalid native control frame') from None
                if not isinstance(result, dict):
                    raise AcquisitionBrokerError('Native protocol requires object frames')
                return result
            if len(self._read_buffer) >= self.FRAME_BYTES:
                raise AcquisitionBrokerError('Native control frame exceeds its bound')
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AcquisitionBrokerError('Native Acquisition deadline expired')
            readable, _, _ = select.select([self._process.stdout, self._process.stderr], [], [], min(0.1, remaining))
            for stream in readable:
                chunk = os.read(stream.fileno(), min(65536, self.FRAME_BYTES - len(self._read_buffer)))
                if stream is self._process.stderr:
                    if hasattr(self, '_stderr_limit'):
                        self._stderr_seen += len(chunk)
                        if self._stderr_seen > self._stderr_limit:
                            raise AcquisitionBrokerError('Helper raw diagnostics exceed their bound')
                    self._stderr.extend(chunk)
                    del self._stderr[:-8192]
                elif not chunk:
                    raise AcquisitionBrokerError('Native worker ended before a complete response')
                else:
                    self._read_buffer.extend(chunk)

    def _identity(self, message, kind):
        if message.get('kind') != kind or message.get('request_id') != self.scope['request_id']:
            raise AcquisitionBrokerError('Native response request/channel identity differs')

    def _call(self, operation, args):
        self._check()
        if not isinstance(operation, str) or operation not in self._operations:
            raise AcquisitionBrokerError('Native capability was not admitted for this producer/profile')
        if not isinstance(args, dict):
            raise AcquisitionBrokerError('Native host arguments must be a bounded object')
        if operation == 'source_info':
            if set(args) != {'source_index'} or type(args['source_index']) is not int:
                raise AcquisitionBrokerError('Exact source index required')
            rows = self.sources.descriptors()
            if not 0 <= args['source_index'] < len(rows):
                raise AcquisitionBrokerError('Source is outside the request')
            return rows[args['source_index']]
        if operation == 'source_read':
            if set(args) != {'source_index', 'offset', 'count'}:
                raise AcquisitionBrokerError('Exact bounded source slice required')
            result = self.sources.read(**args)
            result['bytes_base64'] = base64.b64encode(result.pop('data')).decode('ascii')
            return result
        if operation in {'scientific_spectrum_parse', 'scientific_spectrum_read'}:
            if self._spectra is None:
                from gxtxt_acquisition_spectrum_v1 import AcquisitionSpectrumPages
                self._spectra = AcquisitionSpectrumPages(self.sources, self._check, self.spectrum_validator)
            return (self._spectra.parse if operation == 'scientific_spectrum_parse'
                    else self._spectra.read)(args)
        if operation == 'cancelled':
            if args:
                raise AcquisitionBrokerError('Cancellation query takes no authority arguments')
            return dict(cancelled=False)
        if operation == 'progress':
            if set(args) not in ({'phase', 'message'}, {'phase', 'message', 'current', 'total'}):
                raise AcquisitionBrokerError('Exact bounded progress fields required')
            if not isinstance(args['phase'], str) or not 1 <= len(args['phase']) <= 32 or not isinstance(args['message'], str) or len(args['message'].encode('utf-8')) > 1024:
                raise AcquisitionBrokerError('Progress labels exceed their bound')
            if 'current' in args and (type(args['current']) is not int or type(args['total']) is not int or not 0 <= args['current'] <= args['total'] <= (1 << 63) - 1):
                raise AcquisitionBrokerError('Progress counts must be finite bounded integers')
            if self.progress is not None:
                self.progress(dict(args))
            return dict(acknowledged=True)
        if operation in {'prepare_output', 'output_write', 'output_finish'}:
            if self.scope['phase'] not in {'test', 'import'} or self.outputs is None:
                raise AcquisitionBrokerError('Inspection has no numeric output authority')
            return {'prepare_output': self.outputs.prepare,
                    'output_write': self.outputs.authorize_write,
                    'output_finish': self.outputs.finish}[operation](args)
        if operation == 'helper_call':
            if set(args) != {'helper_id', 'args'} or not isinstance(args['helper_id'], str) or not 1 <= len(args['helper_id']) <= 128:
                raise AcquisitionBrokerError('Declared helper identity and typed arguments required')
            if self.helper is None:
                raise AcquisitionBrokerError('Managed helper capability is unavailable')
            return self.helper(args['helper_id'], args['args'])
        raise AcquisitionBrokerError('Native host capability is unavailable')

    def run(self, trusted_runtime, config, mapping, limits):
        if self._used:
            raise AcquisitionBrokerError('Native request cannot be replayed')
        self._used = True
        try:
            return self._run(trusted_runtime, config, mapping, limits)
        finally:
            if self._spectra is not None:
                self._spectra.close()
            self.sources.close()
            if self.outputs is not None:
                self.outputs.close()

    def _run(self, trusted_runtime, config, mapping, limits):
        self._check()
        entry = Path(__file__).resolve().with_name('gxtxt_acquisition_native_worker_v1.py')
        if not entry.is_file() or entry.is_symlink():
            raise AcquisitionBrokerError('Admitted native Acquisition worker is unavailable')
        deadline = time.monotonic() + self.timeout
        self._deadline = deadline
        self._process = subprocess.Popen([sys.executable, '-I', '-B', str(entry)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            close_fds=True, bufsize=0, cwd='/', env={
                'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8', 'LC_ALL': 'C.UTF-8'})
        os.set_blocking(self._process.stdin.fileno(), False)
        complete = None
        try:
            self._send(dict(schema='gxtxt.native_acquisition_request.v1', kind='hello',
                request_id=self.scope['request_id'], phase=self.scope['phase'],
                qualified_profile=self.scope['qualified_profile'],
                module_snapshot=self.scope['module_snapshot'],
                source_descriptors=self.sources.descriptors(), config=config, mapping=mapping,
                limits=limits, _trusted_runtime=trusted_runtime))
            ready = self._receive(deadline)
            if ready.get('kind') == 'complete' and ready.get('status') == 'failed' and ready.get('request_id') == self.scope['request_id']:
                diagnostics = ready.get('diagnostics', [])
                detail = '; '.join(value[:2048] for value in diagnostics[:2] if isinstance(value, str)) if isinstance(diagnostics, list) else ''
                raise AcquisitionBrokerError('Native worker admission failed: ' + detail)
            self._identity(ready, 'ready')
            if ready.get('binary_sha256') != trusted_runtime['binary_sha256'] or ready.get('sdk_sha256') != trusted_runtime['sdk_sha256'] or ready.get('worker_pid') != self._process.pid or not isinstance(ready.get('guard_receipt'), dict) or not ready['guard_receipt']:
                raise AcquisitionBrokerError('Native guarded admission receipt differs')
            guard = ready['guard_receipt']
            process_policy = guard.get('process_policy')
            expected_process = dict(enforced=True, fork='EPERM', vfork='EPERM',
                process_clone='EPERM', clone3='ENOSYS', exec='EPERM', threads='CLONE_THREAD_ONLY')
            if guard.get('schema') != 'gxtxt.native_acquisition_read_policy.v1' or guard.get('active') is not True or guard.get('before_authored_load') is not True or guard.get('source_paths_or_fds_admitted') is not False or guard.get('execute_allowed') is not False or not isinstance(process_policy, dict) or any(process_policy.get(key) != value for key, value in expected_process.items()) or process_policy.get('enforced') is not True or ready.get('factory_identity') != 'gxtxt_acquisition_invoke_v1':
                raise AcquisitionBrokerError('Native source/process confinement was not enforced before authored loading')
            self._check()
            self._send(dict(kind='invoke', request_id=self.scope['request_id'],
                phase=self.scope['phase'], qualified_profile=self.scope['qualified_profile']))
            while True:
                message = self._receive(deadline)
                if message.get('kind') == 'complete':
                    self._identity(message, 'complete')
                    if message.get('phase') != self.scope['phase'] or message.get('qualified_profile') != self.scope['qualified_profile']:
                        raise AcquisitionBrokerError('Native invocation did not complete with its admitted identity')
                    if message.get('status') == 'failed' and message.get('result') is None:
                        diagnostics = message.get('diagnostics', [])
                        detail = '; '.join(' '.join(value.replace('\0', '').split())[:2048] for value in diagnostics[:2] if isinstance(value, str)) if isinstance(diagnostics, list) else ''
                        raise AcquisitionBrokerError('Native producer refused the request' + (': ' + detail if detail else ''))
                    if message.get('status') != 'completed':
                        raise AcquisitionBrokerError('Native invocation did not complete with its admitted identity')
                    complete = message
                    break
                self._identity(message, 'host_call')
                if set(message) != {'kind', 'request_id', 'sequence', 'operation', 'args'} or type(message['sequence']) is not int or message['sequence'] != self._sequence + 1 or message['sequence'] > 262144:
                    raise AcquisitionBrokerError('Native exchange sequence or shape differs')
                self._sequence = message['sequence']
                try:
                    result = self._call(message['operation'], message['args'])
                except Exception:
                    self._send(dict(kind='host_reply', request_id=self.scope['request_id'],
                        sequence=self._sequence, status='refused', result=None,
                        error='CORE refused the requested capability'))
                    raise
                self._send(dict(kind='host_reply', request_id=self.scope['request_id'],
                    sequence=self._sequence, status='ok', result=result, error=''))
            self._process.stdin.close()
            # Success requires voluntary normal exit; completion alone does not
            # authorize publication while an actor can still mutate its buffers.
            try:
                exit_code = self._process.wait(timeout=min(5, max(0.01, deadline - time.monotonic())))
            except subprocess.TimeoutExpired:
                raise AcquisitionBrokerError('Completed native actor failed to exit') from None
            if exit_code != 0:
                raise AcquisitionBrokerError('Native actor did not exit normally')
            self._check()
            result = complete.get('result')
            if not isinstance(result, dict):
                raise AcquisitionBrokerError('Native completion requires a bounded result object')
            if self.outputs is not None:
                references = result.get('prepared_outputs')
                if not isinstance(references, list) or any(not isinstance(ref, dict) or set(ref) != {'output_id'} or not isinstance(ref['output_id'], str) for ref in references):
                    raise AcquisitionBrokerError('Exact prepared output references required')
                ids = [ref['output_id'] for ref in references]
                if len(ids) != len(set(ids)) or set(ids) != set(self.outputs.finished_output_ids()):
                    raise AcquisitionBrokerError('Native completion output references differ')
            elif 'prepared_outputs' in result or 'dataset_group' in result:
                raise AcquisitionBrokerError('Inspection cannot return publication references')
            descriptors = self.sources.finalize()
            plans = self.outputs.seal(actor_reaped=True) if self.outputs is not None else []
            self._check()
            return dict(result=result, prepared_publications=plans,
                source_descriptors=descriptors, admission=ready,
                host_calls=self._sequence, actor_reaped=True)
        finally:
            if self._process.poll() is None:
                self._process.kill()
            self._process.wait(timeout=5)
            for stream in (self._process.stdin, self._process.stdout, self._process.stderr):
                if not stream.closed:
                    stream.close()
            self.sources.close()
            if self.outputs is not None:
                self.outputs.close()
