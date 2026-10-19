"""Real GDB/MI native control fixture through the same admitted author toolchain."""
from pathlib import Path
import json,subprocess,time,sys,os,signal
W=Path(__file__).resolve().parents[2];C=W/'_work_gxtxt_dev108'
P=W/'_private_dev108/debug-contract';B=C/'core/python/gxtxt_viewer_development.py'
def cli(op,payload=None,*args):
    p=subprocess.run(['/usr/bin/python3','-I','-B',str(B),op,str(P),*args],input=payload,text=True,capture_output=True,timeout=90)
    value=json.loads(p.stdout)
    if p.returncode:raise RuntimeError(value)
    return value
cli('init',None,'--module-id','viewer.cpp_debug_fixture')
source='''// Genuine admitted scalar control fixture; no scientific calculation.
int increment(int value) {
    int next = value + 1;
    return next;
}
void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    int first = 2;
    int second = increment(first);
    state.counter = second;
    host.text(2, "Native C++ execution completed");
}
'''
cli('save',source)
process=subprocess.Popen(['/usr/bin/python3','-I','-B',str(B),'debug',str(P),'--breakpoints','[8,9]'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
receipts=[]
def wait_paused(after=0):
    deadline=time.monotonic()+90
    while time.monotonic()<deadline:
        path=P/'derived/debug/state.json'
        if path.exists():
            state=json.loads(path.read_text())
            if state['state']=='PAUSED' and state['sequence']>after and state['frames'] and state['locals']:
                return state
            if state['state'] in {'FAILED','TIMED_OUT','SOURCE_CHANGED'}:raise RuntimeError(state)
        if process.poll() is not None:raise RuntimeError(process.communicate())
        time.sleep(.05)
    raise TimeoutError('Actual paused C++ state not observed')
try:
    current=wait_paused();receipts.append({'case':'breakpoint','state':current})
    assert current['frame']['line']=='8',current
    for operation in ('into','over','out'):
        prior=current['sequence']
        cli('debug_control',json.dumps({'operation':operation,'source_sha256':current['source_sha256']}))
        # Require a new native stop, not just a locals refresh of the old pause.
        old_stops=len(current.get('stops',[]));deadline=time.monotonic()+20
        while True:
            current=wait_paused(prior)
            if len(current.get('stops',[]))>old_stops:break
            if time.monotonic()>deadline:raise TimeoutError(operation)
            time.sleep(.05)
        receipts.append({'case':operation,'state':current})
    assert any('increment' in r['state'].get('frame',{}).get('func','') for r in receipts if r['case']=='into')
    cli('debug_control',json.dumps({'operation':'continue','source_sha256':current['source_sha256']}))
    # Subsequent breakpoint at line9 is a real native stop; continue again.
    deadline=time.monotonic()+15
    while process.poll() is None and time.monotonic()<deadline:
        time.sleep(.05);current=json.loads((P/'derived/debug/state.json').read_text())
        if current['state']=='PAUSED' and not (P/'derived/debug/command.json').exists():
            cli('debug_control',json.dumps({'operation':'continue','source_sha256':current['source_sha256']}))
    stdout,stderr=process.communicate(timeout=15)
    report=json.loads(stdout);receipts.append({'case':'completed','result':report,'stderr':stderr})
    assert report['ok'] and report['result']['status']=='COMPLETED',report
    assert report['result']['debug']['native_result']['state']['counter']==3
finally:
    if process.poll() is None:
        os.killpg(process.pid,signal.SIGTERM)
        try:process.wait(timeout=5)
        except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait()
    (P/'debug-contract-receipts.json').write_text(json.dumps(receipts,indent=2)+'\n')
print(json.dumps({'status':'PASS_REAL_GDB_NESTED_CONTROL','cases':[r['case'] for r in receipts]}))
