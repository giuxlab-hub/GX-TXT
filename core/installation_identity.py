# SPDX-License-Identifier: GPL-3.0-or-later
"""Host-only durable installation identity. No preference or Session authority."""
import os,sys,json,uuid,hashlib,time
from pathlib import Path
from contextlib import contextmanager
@contextmanager
def locked(root):
 root.mkdir(parents=True,exist_ok=True)
 with (root/'ledger.lock').open('a+b') as f:
  if os.name=='nt':
   import msvcrt
   f.seek(0);f.write(b'0');f.flush();f.seek(0);msvcrt.locking(f.fileno(),msvcrt.LK_LOCK,1)
  else:
   import fcntl
   fcntl.flock(f,fcntl.LOCK_EX)
  try:yield
  finally:
   if os.name=='nt':f.seek(0);msvcrt.locking(f.fileno(),msvcrt.LK_UNLCK,1)
   else:fcntl.flock(f,fcntl.LOCK_UN)
def canonical(d):return json.dumps(d,sort_keys=True,separators=(',',':')).encode()
def valid(p):
 e=json.loads(p.read_text());d=e['ledger'];assert e['sha256']==hashlib.sha256(canonical(d)).hexdigest()
 assert d['version']==1 and isinstance(d['history'],list) and d['history']
 seen=set()
 for i,r in enumerate(d['history']):
  assert str(uuid.UUID(r['id']))==r['id'] and r['order']==i+1 and r['id'] not in seen
  assert isinstance(r['reason'],str) and isinstance(r['date'],str)
  assert r['previous']==('' if i==0 else d['history'][i-1]['id']);seen.add(r['id'])
 assert d['current']==d['history'][-1]['id'];return d
def syncdir(p):
 if os.name!='nt':
  f=os.open(p,os.O_RDONLY)
  try:os.fsync(f)
  finally:os.close(f)
def write(p,d):
 e={'ledger':d,'sha256':hashlib.sha256(canonical(d)).hexdigest()};temp=p.with_name(p.name+'.tmp')
 with temp.open('wb') as f:f.write(canonical(e));f.flush();os.fsync(f.fileno())
 os.replace(temp,p);syncdir(p.parent)
def extends(a,b):return len(a['history'])>=len(b['history']) and a['history'][:len(b['history'])]==b['history']
def read(root):
 paths=[root/'ledger.json',root/'ledger.pending',root/'ledger.backup'];found=[];bad=[]
 for p in paths:
  if p.exists():
   try:found.append((p,valid(p)))
   except Exception:bad.append(p)
 if not found:
  if bad:raise RuntimeError('Invalid installation identity; no valid recovery ledger. Preserve files and restore a verified backup.')
  # Temp indicates interrupted first issuance, never claim healthy absence.
  if list(root.glob('ledger*.tmp')):raise RuntimeError('Interrupted initial identity write; inspect retained temporary ledger before recovery.')
  return None,'new'
 best=max(found,key=lambda x:len(x[1]['history']))[1]
 if any(not extends(best,d) for p,d in found):raise RuntimeError('Conflicting installation identity histories; automatic continuity recovery refused.')
 diagnostic='healthy'
 if bad or not paths[0].exists() or valid(paths[0])!=best or paths[1].exists() or not paths[2].exists() or valid(paths[2])!=best:
  for p in bad:os.replace(p,p.with_name(p.name+'.corrupt.'+str(time.time_ns())))
  write(paths[0],best);write(paths[2],best);diagnostic='recovered verified history'
 if paths[1].exists():paths[1].unlink();syncdir(root)
 return best,diagnostic
def event(previous,order,reason):return dict(id=str(uuid.uuid4()),previous=previous,order=order,date=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),reason=reason)
def operation(root,action,reason=''):
 with locked(root):
  d,status=read(root)
  if d is None:
   r=event('',1,'initial CORE startup');d=dict(version=1,current=r['id'],history=[r]);write(root/'ledger.pending',d);write(root/'ledger.json',d);write(root/'ledger.backup',d);(root/'ledger.pending').unlink();syncdir(root)
  if action=='rotate':
   if not reason.strip():raise RuntimeError('Rotation requires a reason.')
   write(root/'ledger.backup',d)
   r=event(d['current'],len(d['history'])+1,reason);d=dict(version=1,current=r['id'],history=d['history']+[r])
   write(root/'ledger.pending',d);write(root/'ledger.json',d);write(root/'ledger.backup',d);(root/'ledger.pending').unlink();syncdir(root);status='rotated'
  elif action!='read':raise RuntimeError('Unknown identity host operation')
  return dict(api_id='INSTALLATION_IDENTITY_API_v1',version=1,current=d['current'],history=d['history'],authority=str(root),diagnostic=status)
def tcl(s):
 if isinstance(s,dict):return ' '.join(tcl(k)+' '+tcl(v) for k,v in s.items())
 if isinstance(s,list):return ' '.join(tcl(v) if not isinstance(v,dict) else '{'+tcl(v)+'}' for v in s)
 s=str(s)
 return '{'+s+'}' if not any(c in s for c in '{}\\') else ''.join('\\'+c if c in ' {}[]$;\\\n\r\t"' else c for c in s)
def output(d):
 # Every nested value is a single list element; braces only enclose already escaped Tcl lists.
 return ' '.join(tcl(k)+' '+('{'+tcl(v)+'}' if isinstance(v,(dict,list)) else tcl(v)) for k,v in d.items())
if __name__=='__main__':
 try:print(output(operation(Path(sys.argv[1]),sys.argv[2],sys.argv[3] if len(sys.argv)>3 else '')))
 except Exception as e:print('Installation identity error: '+str(e),file=sys.stderr);sys.exit(1)
