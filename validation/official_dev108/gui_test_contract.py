# SPDX-License-Identifier: GPL-3.0-or-later
"""Primary review of bounded GUI author tooling; not separate-author evidence."""
from pathlib import Path
import json
import subprocess
import sys
import time
import tkinter

W = Path(__file__).resolve().parents[2]
C = W / '_work_gxtxt_dev108'
project = W / '_private_dev108/spice_project'
out = Path(sys.argv[1]).resolve()
assert out.is_relative_to(W / '_private_dev108') and not out.exists()
out.mkdir()
T = tkinter.Tcl()

def dictionary(value):
    words = T.splitlist(value)
    return dict(zip(words[::2], words[1::2]))

cases = []
def call(payload, denied=False):
    run = subprocess.run(['/usr/bin/python3', '-I', '-B', str(C / 'core/python/gxtxt_viewer_development.py'), 'gui_test', str(project)], input=json.dumps(payload), text=True, capture_output=True, timeout=40)
    response = json.loads(run.stdout)
    cases.append(dict(request=payload, response=response, returncode=run.returncode, stderr=run.stderr))
    (out / 'cases.json').write_text(json.dumps(cases, indent=2) + '\n')
    assert response['ok'] != denied, response
    if denied:
        assert run.returncode != 0
        return response
    assert run.returncode == 0
    return dictionary(response['result']['gui_receipt']['result'])

def wait():
    deadline = time.monotonic() + 80
    while time.monotonic() < deadline:
        result = call(dict(operation='status'))
        if result['busy'] == '0' and result['status'] not in {'VALIDATING', 'RUNNING'}:
            assert result['status'] == 'COMPLETED', result
            return result
        time.sleep(.3)
    raise AssertionError('Actual GUI compiled event timed out')

call(dict(operation='eval', source='destroy .'), denied=True)
call(dict(operation='open', module='viewer.other'), denied=True)
call(dict(operation='key', component='graphics', key='alt+F4'), denied=True)
call(dict(operation='open'))
wait()
call(dict(operation='click', component='not_declared'), denied=True)
call(dict(operation='click', component='graphics'), denied=True)
call(dict(operation='pointer', component='graphics', x=999999, y=999999, phase='click'), denied=True)
call(dict(operation='text', component='readout', value='forged'), denied=True)
call(dict(operation='click', component='advance'))
observed = wait()
domain = dictionary(observed['domain_state'])
native = dictionary(domain['restricted_cpp'])
state = dictionary(native['state'])
assert state['counter'] == '1' and float(T.splitlist(state['values'])[0]) == 1.0
call(dict(operation='click', component='tool_resistor'))
wait()
call(dict(operation='pointer', component='graphics', x=40, y=50, phase='click'))
captured = call(dict(operation='capture'))
diagram = dictionary(dictionary(captured['bindings'])['graphics'])
payload = dictionary(diagram['payload'])
assert len(dictionary(payload['components'])) == 1, payload
path = Path(captured['screenshot'])
assert path.is_relative_to(project / 'derived/gui-test') and path.read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
call(dict(operation='close'))
call(dict(operation='capture'), denied=True)
(out / 'result.json').write_text(json.dumps(dict(result='PASS_SCOPE_ONLY', cases=len(cases), capture=str(path), source_snapshot=dictionary(captured['source_snapshot']), separate_author_gui='NOT_TESTED_BY_THIS_SCRIPT'), indent=2) + '\n')
print('PASS bounded GUI transport, actual compiled Numeric action/native placement and denials')
