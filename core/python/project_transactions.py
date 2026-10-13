# SPDX-License-Identifier: GPL-3.0-or-later
"""Host Project/Session organization transaction recovery, never scientific serialization."""
import sys,os,json,hashlib,base64
from pathlib import Path

def syncdir(p):
 if os.name!='nt':
  f=os.open(p,os.O_RDONLY)
  try:os.fsync(f)
  finally:os.close(f)
def atomic(path,data):
 path.parent.mkdir(parents=True,exist_ok=True);tmp=path.with_name(path.name+'.txn-'+str(os.getpid()))
 with tmp.open('wb') as f:f.write(data);f.flush();os.fsync(f.fileno())
 os.replace(tmp,path);syncdir(path.parent)
def envelope(d):
 raw=json.dumps(d,sort_keys=True).encode();return json.dumps(dict(data=d,sha256=hashlib.sha256(raw).hexdigest()),sort_keys=True).encode()
def load(path):
 e=json.loads(path.read_text());d=e['data'];assert e['sha256']==hashlib.sha256(json.dumps(d,sort_keys=True).encode()).hexdigest();return d
def alive(pid):
 try:os.kill(pid,0);return True
 except ProcessLookupError:return False
 except PermissionError:return True
def restore(path,d):
 for source,target in reversed(d['moves']):
  a,b=Path(source),Path(target)
  if b.exists():
   if a.exists():raise RuntimeError('Both original and recovery Session paths exist; inspect transaction '+str(path))
   os.replace(b,a);syncdir(a.parent)
 for p,content in d['files'].items():
  p=Path(p)
  if content is None:
   if p.exists():p.unlink();syncdir(p.parent)
  else:atomic(p,base64.b64decode(content))
 path.unlink();syncdir(path.parent)
def main():
 action=sys.argv[1];p=Path(sys.argv[2]);owner=int(sys.argv[3]);args=sys.argv[4:];p.parent.mkdir(parents=True,exist_ok=True)
 if action=='recover':
  if not p.exists():return 'healthy'
  d=load(p)
  if alive(d['owner']):return 'active transaction; read-only startup'
  restore(p,d);return 'recovered interrupted organization transaction'
 if action=='begin':
  files=args;moves=[]
  if '--move' in args:
   i=args.index('--move');files=args[:i];pairs=args[i+1:];assert len(pairs)%2==0;moves=list(zip(pairs[::2],pairs[1::2]))
  # Exclusive journal creation is the organization writer lock.
  f=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
  try:
   d=dict(owner=owner,files={str(Path(n).resolve()):base64.b64encode(Path(n).read_bytes()).decode() if Path(n).exists() else None for n in files},moves=moves)
   with os.fdopen(f,'wb') as stream:stream.write(envelope(d));stream.flush();os.fsync(stream.fileno())
   syncdir(p.parent)
  except BaseException:
   p.unlink(missing_ok=True);raise
  return 'started'
 d=load(p)
 if d['owner']!=owner:raise RuntimeError('Project transaction belongs to another process')
 if action=='rollback':restore(p,d);return 'rolled back'
 if action=='commit':p.unlink();syncdir(p.parent);return 'committed'
 raise RuntimeError('Unknown organization transaction operation')
if __name__=='__main__':
 try:print(main())
 except Exception as e:print('Project transaction error: '+str(e),file=sys.stderr);sys.exit(1)
