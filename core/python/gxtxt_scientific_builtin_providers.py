"""Small registered ngspice RC provider and explicitly enabled verification fixture."""
# SPDX-License-Identifier: GPL-3.0-or-later
import hashlib
import json
import math
import os
import re
import shutil
import time


def run(context):
    if context.request['provider_id']=='core.ngspice.rc_transient':
        rc(context)
    else:
        fixture(context)


def rc(context):
    raw=context.inputs.get('netlist')
    if raw is None: raise ValueError('RC transient requires the managed netlist resource')
    text=raw.decode('utf-8')
    lines=[line.strip() for line in text.splitlines() if line.strip()]
    # This intentionally bounded provider accepts the documented RC model only.
    # Arbitrary .control/.include/shell commands never reach the interpreter.
    expected=['GX-TXT managed RC transient','V1 input 0 PULSE(0 1 0 1n 1n 10m 20m)',
              'R1 input output 1000','C1 output 0 1u IC=0','.end']
    if lines!=expected: raise ValueError('Netlist is outside the registered RC scientific contract')
    step=context.parameters['step_seconds'];stop=context.parameters['stop_seconds']
    control=f'.control\nset wr_singlescale\nset wr_vecnames\ntran {step:.17g} {stop:.17g} uic\nwrdata waveform.txt v(output)\nquit\n.endc\n.end\n'
    (context.scratch/'model.cir').write_text('\n'.join(lines[:-1])+'\n'+control)
    version=context.run('spice',['--version'])
    context.run('spice',['-b','model.cir'])
    source=context.scratch/'waveform.txt'
    rows=[]
    for line in source.read_text().splitlines()[1:]:
        values=[float(v) for v in line.split()]
        if len(values)!=2 or not all(math.isfinite(v) for v in values): raise ValueError('Invalid ngspice waveform record')
        rows.append(values)
    if not rows or any(b[0]<=a[0] for a,b in zip(rows,rows[1:])): raise ValueError('ngspice time is not strictly increasing')
    target=context.output/'waveform.csv'
    with target.open('w') as stream:
        stream.write('time,voltage\n')
        for t,v in rows:stream.write(f'{t:.17g},{v:.17g}\n')
    context.publish_output('waveform.csv','waveform','csv',[
        {'id':'time','dtype':'float64','unit':'s'},{'id':'voltage','dtype':'float64','unit':'V'}])
    context.summary({'validation':'validated_structure','rows':len(rows),'tau_seconds':.001,
        'source_sha256':hashlib.sha256(raw).hexdigest(),'solver_version':version['stdout'][:4096]})


def fixture(context):
    p=context.parameters
    started=time.monotonic();value=p['seed']
    while time.monotonic()-started<p['seconds']:
        for unused in range(20000):value=(value*1664525+1013904223)&0xffffffff
    result=p['seed']
    for unused in range(p['rounds']):result=(result*1664525+1013904223)&0xffffffff
    if p['fail']:raise RuntimeError('Requested bounded nonzero-exit fixture')
    path=context.output/'result.json'
    path.write_text(json.dumps({'seed':p['seed'],'rounds':p['rounds'],'checksum':result,'pid':os.getpid(),
        'started':started,'finished':time.monotonic(),'job_id':os.environ.get('GXTXT_JOB_ID','')}))
    context.publish_output('result.json','checksum','json')
    if p['live']:
        path=context.output/'live.csv';path.write_text('time,value\n0,0\n')
        context.publish_output('live.csv','samples','csv',[{'id':'time','dtype':'float64','unit':'s'},
            {'id':'value','dtype':'float64','unit':'V'}],live=True)
        for number in range(1,8):
            with path.open('a') as stream:stream.write(f'{number},{number*2}\n')
            print(f'live UTF-8 sample {number}: \u03b1',flush=True);time.sleep(.3)
        path.write_text('time,value\n0,10\n1,')
        print('live truncation and incomplete record',flush=True);time.sleep(.5)
        with path.open('a') as stream:stream.write('12\n')
        time.sleep(.5)
    context.summary({'validation':'validated_structure','checksum':result})
