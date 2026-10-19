# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
import hashlib,json,subprocess,tkinter
w=Path(__file__).resolve().parents[2];framework=w/'_work_gxtxt_dev108';base=w/'_private_dev108';t=tkinter.Tcl();receipts=[]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def td(raw):
 parts=t.splitlist(raw);return dict(zip(parts[::2],parts[1::2]))
def call(project,op,payload=None,args=(),ok=True):
 r=subprocess.run(['/usr/bin/python3','-I','-B',str(framework/'core/python/gxtxt_viewer_development.py'),op,str(project),*args],input=None if payload is None else json.dumps(payload),text=True,capture_output=True,timeout=90)
 ans=json.loads(r.stdout);assert bool(ans['ok'])==ok,ans
 receipts.append({'project':str(project),'operation':op,'request':payload,'ok':ans['ok'],'response_bytes':len(r.stdout.encode()),'code':ans.get('code'),'error':ans.get('error')})
 return ans.get('result')
def prepare(name,kind):
 out=base/name;assert not out.exists();out.mkdir();p=out/'project'
 call(p,'init',args=('--module-id','viewer.builder_history_qa'))
 r=subprocess.run(['tclsh',str(Path(__file__).with_name('builder_history_fixture.tcl')),str(framework),str(p),kind],capture_output=True,text=True,timeout=60)
 assert r.returncode==0,r.stderr
 return out,p,td(r.stdout)
out,p,fixture=prepare('builder-history-contract01','history')
design=p/'design.gxtxt-viewer';history=p/'derived/builder-model.tcldict'
assert history.stat().st_size>4194304 and fixture['past']=='50'
before=(sha(design),sha(history));inspected=call(p,'builder',{'operation':'inspect','arguments':[]})
assert before==(sha(design),sha(history))
changed=call(p,'builder',{'operation':'metadata','arguments':['title','Accepted after large history']});accepted=sha(design)
assert td(history.read_text())['revision']=='51' and len(t.splitlist(td(history.read_text())['past']))==50
call(p,'builder',{'operation':'undo','arguments':[]});assert sha(design)==before[0]
call(p,'builder',{'operation':'redo','arguments':[]});assert sha(design)==accepted
preimages=(design.read_bytes(),history.read_bytes());derived=p/'derived';derived.chmod(0o500)
try:call(p,'builder',{'operation':'metadata','arguments':['title','Must rollback on history write failure']},ok=False)
finally:derived.chmod(0o700)
assert (design.read_bytes(),history.read_bytes())==preimages
r=subprocess.run(['tclsh',str(Path(__file__).with_name('builder_history_fixture.tcl')),str(framework),str(p),'invalid'],capture_output=True,text=True,timeout=60);assert r.returncode==0,r.stderr
invalid=(design.read_bytes(),history.read_bytes());call(p,'builder',{'operation':'inspect','arguments':[]},ok=False);assert invalid==(design.read_bytes(),history.read_bytes())
large,lp,largefixture=prepare('builder-history-response01','response')
large_result=call(lp,'builder',{'operation':'inspect','arguments':[]})
assert len(large_result['builder']['design'].encode())<=4194304
# Tcl's raw response contains capabilities/quoting as well as the valid design.
raw=subprocess.run(['tclsh',str(framework/'core/tcl/viewer_development_request.tcl'),str(framework),'builder_edit',str(lp/'design.gxtxt-viewer'),'operation inspect arguments {}'],capture_output=True,timeout=60)
assert raw.returncode==0 and len(raw.stdout)>4194304,(raw.returncode,len(raw.stdout),raw.stderr[-500:])
result={'status':'PASS_REAL_LARGE_HISTORY_UNDO_REDO_ROLLBACK_AND_RESPONSE','history_fixture':fixture,'large_response_fixture':largefixture,'actual_raw_core_response_bytes':len(raw.stdout),'retained_steps':50,'ordinary_error_preimages_exact':True,'crash_atomicity_claimed':False,'receipts':receipts}
(out/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(out/'result.json')
