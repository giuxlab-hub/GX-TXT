"""Read-only original inspection and quiescent P019 private Session snapshot."""
from pathlib import Path
from datetime import datetime,timezone
import configparser,hashlib,importlib.util,json,os,shutil,stat,sys,time,traceback
sys.dont_write_bytecode=True
framework,source,out=map(lambda p:Path(p).resolve(),sys.argv[1:])
if out.exists():raise SystemExit('Refusing existing private output')
if not source.is_dir() or not (source/'metadata/manifest.ini').is_file():raise SystemExit('Invalid source Session')
out.mkdir(mode=0o700,parents=True)
private=out/'snapshot'/source.name
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def now():return datetime.now(timezone.utc).isoformat()
def save(name,data):
 p=out/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(data,indent=2,sort_keys=True)+'\n')
def parse(path):
 c=configparser.ConfigParser(interpolation=None,strict=False);c.optionxform=str;c.read(path,encoding='utf-8');return c
def inventory(root):
 files={};dirs={}
 for directory,subdirs,names in os.walk(root,followlinks=False):
  d=Path(directory);ds=d.lstat()
  if not stat.S_ISDIR(ds.st_mode):raise ValueError('Non-directory source component')
  dirs[str(d.relative_to(root))]={'mode':stat.S_IMODE(ds.st_mode),'dev':ds.st_dev,'ino':ds.st_ino,'mtime_ns':ds.st_mtime_ns,'ctime_ns':ds.st_ctime_ns}
  for n in subdirs:
   p=d/n
   if p.is_symlink():raise ValueError('Session symlink directory requires separate approved dependency handling')
  for n in names:
   p=d/n;s=p.lstat()
   if not stat.S_ISREG(s.st_mode):raise ValueError('Session nonregular file requires separate approved dependency handling')
   digest=sha(p);after=p.stat()
   if (s.st_dev,s.st_ino,s.st_size,s.st_mtime_ns,s.st_ctime_ns)!=(after.st_dev,after.st_ino,after.st_size,after.st_mtime_ns,after.st_ctime_ns):raise ValueError('Source changed while hashing')
   files[str(p.relative_to(root))]={'sha256':digest,'bytes':s.st_size,'mode':stat.S_IMODE(s.st_mode),'dev':s.st_dev,'ino':s.st_ino,'mtime_ns':s.st_mtime_ns,'ctime_ns':s.st_ctime_ns}
 return {'files':files,'directories':dirs}
def processes():
 refs=[];candidates=[]
 for p in Path('/proc').iterdir():
  if not p.name.isdigit() or int(p.name)==os.getpid():continue
  try:
   if p.stat().st_uid!=os.getuid():continue
   comm=(p/'comm').read_text().strip()
   if any(x in comm.lower() for x in ['tclsh','wish','gxtxt']):candidates.append({'pid':int(p.name),'comm':comm})
   for fd in (p/'fd').iterdir():
    try:
     target=os.readlink(fd)
     if target==str(source) or target.startswith(str(source)+'/'):
      info=(p/'fdinfo'/fd.name).read_text();flags=int(next(line.split()[1] for line in info.splitlines() if line.startswith('flags:')),8)
      refs.append({'pid':int(p.name),'comm':comm,'fd':int(fd.name),'path':target,'writable':bool(flags&3),'flags':oct(flags)})
    except (OSError,StopIteration):pass
  except OSError:pass
 return {'references':refs,'possible_gui_processes':candidates,'excluded_own_read_lock_process':os.getpid()}
record={'started_utc':now(),'source':str(source),'framework':str(framework),'private_snapshot':str(private),'original_mutating_api_called':False,'original_gui_opened':False,'status':'IN_PROGRESS'}
save('inspection.json',record)
try:
 history_file=framework/'core/python/scientific_history_portable_copy.py'
 spec=importlib.util.spec_from_file_location('p019_history_read_only',history_file);history=importlib.util.module_from_spec(spec);spec.loader.exec_module(history)
 record['history_lock_helper_sha256']=sha(history_file)
 with history.history_read_locks(source) as families:
  record['history_read_locked_families']=[str(p.relative_to(source)) for p in families]
  first=inventory(source);save('source-inventory-before.json',first)
  observed=processes();save('process-observation-before.json',observed)
  if any(r['writable'] for r in observed['references']):raise ValueError('Source Session has observed open writable descriptors')
  time.sleep(2)
  quiet=inventory(source);save('source-inventory-quiet.json',quiet)
  if first!=quiet:raise ValueError('Source mutated during quiescence observation')
  private.parent.mkdir()
  shutil.copytree(source,private,symlinks=True,copy_function=shutil.copy2)
  copied=inventory(private);save('snapshot-inventory.json',copied)
  for rel,b in first['files'].items():
   a=copied['files'].get(rel)
   if a is None or any(a[k]!=b[k] for k in ['sha256','bytes','mode','mtime_ns']):raise ValueError('Snapshot byte/mode/time mismatch')
   if (a['dev'],a['ino'])==(b['dev'],b['ino']):raise ValueError('Snapshot shares source inode')
  if set(copied['files'])!=set(first['files']) or set(copied['directories'])!=set(first['directories']):raise ValueError('Snapshot inventory mismatch')
  for rel,b in first['directories'].items():
   if copied['directories'][rel]['mode']!=b['mode']:raise ValueError('Snapshot directory mode mismatch')
  after=inventory(source);save('source-inventory-after-copy.json',after)
  observed_after=processes();save('process-observation-after.json',observed_after)
  if any(r['writable'] for r in observed_after['references']):raise ValueError('Source writer appeared during snapshot')
  time.sleep(2)
  final=inventory(source);save('source-inventory-final.json',final)
  if first!=after or first!=final:raise ValueError('Original source inventory/stat/content changed across snapshot')
  c=parse(private/'metadata/interactive_documents.ini');found=None
  for section in c.sections():
   if c[section].get('id')=='idoc_0004':found=dict(c[section]);break
  if found is None:raise ValueError('Requested Document is absent')
  if found.get('module_id')!='viewer.curve_workbench' or found.get('provider_id')!='curve_workbench' or found.get('format')!='gxtxt.curve_workbench.workspace' or found.get('format_version')!='2.0':raise ValueError('Requested Document owner/format mismatch')
  payload=private/'metadata/interactive_documents'/found['storage_name']
  if sha(payload)!=found['sha256']:raise ValueError('Document hash mismatch')
  # Tcl list/dict parsing only, not Tcl evaluation or application activation.
  import tkinter
  interp=tkinter.Tcl();data=payload.read_text();keys=interp.splitlist(interp.call('dict','keys',data))
  name=None
  for k in ['name','workspace_name','title']:
   if k in keys:
    value=interp.call('dict','get',data,k)
    if value=='produrre_di_bug':name=value
  # Persist only keys here; exact payload is preserved in private snapshot.
  record['document_payload_keys']=list(keys)
  record['requested_document']=found;record['document_bytes']=payload.stat().st_size;record['workspace_name_verified']=name=='produrre_di_bug'
  project=source.parent.parent/'project.ini'
  if project.is_file():
   target=out/'project-context/project.ini';target.parent.mkdir();shutil.copy2(project,target);record['project_context_sha256']=sha(project)
  record['status']='CONSISTENT_PRIVATE_FILESYSTEM_SNAPSHOT'
  record['safe_for_original_access']='READ_ONLY_ONLY'
  record['private_activation_requires']='Existing public CORE portable import/rescope on PRIVATE COPY ONLY before GUI; raw snapshot preserves original native History scope.'
  record['file_count']=len(first['files']);record['total_bytes']=sum(r['bytes'] for r in first['files'].values())
  record['quiescence_evidence']='All native History shared locks acquired; no writable source descriptors observed before/after; full source names/stat/hash inventory unchanged across quiet interval/copy/final interval; copied bytes/modes/mtime match, no shared file inodes.'
  record['live_application_limit']='No observed source writer is not proof that every GUI is closed; snapshot captures persisted state only, not unsaved RAM in a potentially idle application.'
 record['finished_utc']=now();save('inspection.json',record)
 print(json.dumps({k:record[k] for k in ['status','private_snapshot','file_count','total_bytes','document_bytes','workspace_name_verified']},indent=2))
except BaseException as e:
 record['status']='NOT_FOR_TEST_USE';record['failure']=str(e);record['finished_utc']=now();save('inspection.json',record);(out/'failure.txt').write_text(traceback.format_exc());raise
