# SPDX-License-Identifier: GPL-3.0-or-later
"""Private CORE managed-request adapter. Never an authored grant interface.

The Tcl admission owner sends a single reviewed bootstrap on its owned pipe.
Only small preflight/lifetime/progress messages return to that owner; selected
source slices and typed scientific bytes stay in the existing native broker.
"""
from __future__ import annotations
import base64
import hashlib
import json
import os
from pathlib import Path
import signal
import stat
import sys
import time
import tkinter

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gxtxt_acquisition_broker_v1 import AcquisitionNativeBroker, _unique_object
from gxtxt_acquisition_source_v1 import AcquisitionSourceGrant
from gxtxt_acquisition_output_v1 import AcquisitionOutputBuffers
from gxtxt_job_supervisor import request_process_group, tcl_result
import gxtxt_acquisition_project_v1 as project_model

MAX_FRAME = 1048576


def receive():
    raw = sys.stdin.buffer.readline(MAX_FRAME + 1)
    if not raw.endswith(b'\n') or len(raw) > MAX_FRAME:
        raise ValueError('CORE control channel ended or exceeded its bound')
    return json.loads(raw.decode('utf-8'), object_pairs_hook=_unique_object,
        parse_constant=lambda _: (_ for _ in ()).throw(ValueError('Nonfinite control value')))


def send(value):
    raw = tcl_result(value).encode('utf-8')
    if len(raw) > MAX_FRAME:
        raise ValueError('CORE result exceeds its control bound')
    print(base64.b64encode(raw).decode('ascii'), flush=True)


class CoreRequest:
    def __init__(self, envelope):
        if not isinstance(envelope, dict) or set(envelope) != {
            'schema', 'scope', 'sources', 'runtime', 'config', 'mapping', 'limits',
            'admitted_operations', 'pins', 'lease'} or envelope['schema'] != 'gxtxt.core_acquisition_bootstrap.v1':
            raise ValueError('Exact private CORE bootstrap required')
        self.data = envelope
        self.sequence = 0
        self.next_core_check = 0
        self.tcl = tkinter.Tcl()
        self.identities = {}
        if not isinstance(envelope['pins'], dict) or not 8 <= len(envelope['pins']) <= 160:
            raise ValueError('Reviewed package/runtime closure required')
        for name, digest in envelope['pins'].items():
            path = Path(name)
            if not path.is_absolute() or path.resolve(strict=True) != path:
                raise ValueError('Reviewed closure requires exact ordinary absolute files')
            info = path.stat(follow_symlinks=False)
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                raise ValueError('Reviewed package/runtime closure changed')
            self.identities[name] = self.identity(info)
        source = Path(envelope['runtime']['library']).parent.parent / 'source'
        meta, raw, files = project_model.state(source)
        description = project_model.description(meta, raw, files)
        snapshot = envelope['scope']['module_snapshot']
        if meta['module_id'] != envelope['scope']['module_id'] or description['project_sha256'] != snapshot['project_sha256'] or description['source_tree_sha256'] != snapshot['source_tree_sha256']:
            raise ValueError('Native source closure no longer matches CORE admission')
        profile_id = envelope['scope']['qualified_profile'].removeprefix(meta['module_id'] + '/')
        profile = next((row for row in meta['formats'] if row['id'] == profile_id), None)
        if profile is None or description['profile_sha256'][profile_id] != snapshot['profile_sha256'] or envelope['config'].get('format_profile') != profile_id:
            raise ValueError('Native profile/configuration identity differs')
        granted = set(next((row['operations'] for row in profile['capabilities'] if row['api_id'] == 'ACQUISITION_HANDLER_PLUGIN_API_v1' and str(row['version']) == '1'), []))
        module_granted = set(next((row['operations'] for row in meta['capabilities'] if row['api_id'] == 'ACQUISITION_HANDLER_PLUGIN_API_v1' and str(row['version']) == '1'), []))
        if not set(envelope['admitted_operations']).issubset(granted & module_granted):
            raise ValueError('Native capabilities exceed the actual producer/profile declarations')
        if hasattr(project_model, 'typed_config_payload'):
            envelope['config'] = project_model.typed_config_payload(meta, envelope['config'])
        self.source_root = source
        self.metadata = meta
        self.source_files = files
        self.live(envelope['scope'])

    @staticmethod
    def identity(info):
        return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns

    def rpc(self, operation, payload=None):
        self.sequence += 1
        send(dict(kind='core_call', sequence=self.sequence, operation=operation,
            payload_json=json.dumps(payload, ensure_ascii=False, allow_nan=False, separators=(',', ':'))))
        reply = receive()
        if not isinstance(reply, dict) or set(reply) != {'sequence', 'ok', 'result'} or reply['sequence'] != self.sequence or reply['ok'] is not True:
            raise ValueError('CORE refused or retired this request')
        return reply['result']

    def live(self, scope):
        if scope != self.data['scope']:
            raise ValueError('CORE scope changed')
        for name, expected in self.identities.items():
            info = os.stat(name, follow_symlinks=False)
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or self.identity(info) != expected:
                raise ValueError('Producer/runtime closure changed during invocation')
        lease = self.data['lease']
        if lease:
            path = Path(lease['path'])
            info = path.stat(follow_symlinks=False)
            if not stat.S_ISREG(info.st_mode) or info.st_size > 65536:
                raise ValueError('Acquisition lease is unavailable')
            fields = self.tcl.splitlist(path.read_text(encoding='utf-8'))
            if len(fields) % 2:
                raise ValueError('Invalid lease data')
            control = dict(zip(fields[::2], fields[1::2]))
            if control.get('cancelled') != '0' or control.get('session_token') != lease['session_token']:
                raise ValueError('Acquisition cancelled or Session changed')
        now = time.monotonic()
        if now >= self.next_core_check:
            if self.rpc('live') is not True:
                raise ValueError('CORE lifetime ended')
            self.next_core_check = now + 0.25
        return True

    def definition(self, declaration):
        return self.rpc('preflight', declaration) is True

    def helper_live(self, scope):
        self.live(scope)
        # A helper handoff must not reuse the native bulk-read RPC throttle.
        # Recheck the actual Tcl owner before invoke, while waiting and after reap.
        if self.rpc('live') is not True:
            raise ValueError('CORE helper lifetime ended')
        return True

    def progress(self, event):
        if self.rpc('progress', event) is not True:
            raise ValueError('CORE progress owner ended')

    def spectrum_validate(self, request):
        self.live(self.data['scope'])
        value = self.rpc('scientific_spectrum_validate', request)
        self.live(self.data['scope'])
        return value

    def finish(self):
        self.live(self.data['scope'])
        # Stat checks are fast revocation checks, never cryptographic evidence.
        for name, digest in self.data['pins'].items():
            if hashlib.sha256(Path(name).read_bytes()).hexdigest() != digest:
                raise ValueError('Producer/runtime SHA changed during invocation')
        if self.rpc('live') is not True:
            raise ValueError('CORE lifetime ended before handoff')


def main():
    request_process_group()
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    source = output = None
    try:
        core = CoreRequest(receive())
        data = core.data
        source = AcquisitionSourceGrant(data['scope'], data['sources'], core.live)
        if data['scope']['phase'] in {'test', 'import'}:
            output = AcquisitionOutputBuffers(data['runtime']['buffer_root'], data['scope'], core.live, core.definition)
        # The output owner first admits an empty root. The fixed worker also
        # requires a CORE-created empty diagnostic file inside that same root.
        log = Path(data['runtime']['native_output_path'])
        if log.parent != Path(data['runtime']['buffer_root']):
            raise ValueError('Native diagnostics must remain in the owned buffer root')
        fd = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
        os.close(fd)
        helper = None
        if 'helper_call' in data['admitted_operations']:
            from gxtxt_acquisition_helper_broker_v1 import AcquisitionHelperBroker
            helper = AcquisitionHelperBroker(data['scope'],core.source_root,
                core.metadata['helpers'],core.source_files,core.helper_live,
                admitted_operations=data['admitted_operations'],runtime_pins=data['pins'])
        broker = AcquisitionNativeBroker(data['scope'], source, output, core.live,
            admitted_operations=data['admitted_operations'], progress=core.progress,helper=helper,
            spectrum_validator=core.spectrum_validate)
        result = broker.run(data['runtime'], data['config'], data['mapping'], data['limits'])
        core.finish()
        result['helper_receipts'] = helper.receipts if helper is not None else []
        result['native_result_json'] = json.dumps(result['result'], ensure_ascii=False, allow_nan=False, separators=(',', ':'))
        result['config_json'] = json.dumps(data['config'], ensure_ascii=False, allow_nan=False, separators=(',', ':'))
        result['config_sha256'] = hashlib.sha256(result['config_json'].encode('utf-8')).hexdigest()
        send(dict(kind='complete', ok=True, result=result))
        if receive() != {'done': True}:
            raise ValueError('CORE completion acknowledgement differs')
    except Exception as error:
        send(dict(kind='complete', ok=False, error=str(error)))
        # Keep the last frame owned until the parent consumes it. Its managed
        # timeout/cancellation owner also handles a vanished parent.
        try:
            receive()
        except Exception:
            pass
    finally:
        if source is not None:
            source.close()
        if output is not None:
            output.close()


if __name__ == '__main__':
    main()
