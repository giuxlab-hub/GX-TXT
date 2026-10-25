"""Existing public CORE portable transport over the P019 PRIVATE snapshot only."""
from pathlib import Path
from datetime import datetime,timezone
import configparser,hashlib,importlib.util,json,os,sys,tkinter,traceback
sys.dont_write_bytecode=True
framework,root=map(lambda p:Path(p).resolve(),sys.argv[1:])
info=json.loads((root/'inspection.json').read_text());raw=Path(info['private_snapshot']);source=Path(info['source'])
if info['status']!='CONSISTENT_PRIVATE_FILESYSTEM_SNAPSHOT':raise SystemExit('Unqualified raw snapshot')
transport=root/'transport'
if transport.exists():raise SystemExit('Fresh transport output required')
transport.mkdir(mode=0o700)
for key,sub in {'XDG_CONFIG_HOME':'config','XDG_DATA_HOME':'data','XDG_CACHE_HOME':'cache','XDG_STATE_HOME':'state','GXTXT_INSTALLATION_ROOT':'installation','GXTXT_RESOURCE_ROOT':'resources','GXTXT_RESOURCE_STORAGE':'buffers','GXTXT_JOB_ROOT':'jobs','TMPDIR':'tmp'}.items():
 p=transport/sub;p.mkdir();os.environ[key]=str(p)
os.environ['PYTHONDONTWRITEBYTECODE']='1';os.environ.pop('DISPLAY',None)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def save(name,data):p=transport/name;p.write_text(json.dumps(data,indent=2,sort_keys=True)+'\n')
def parse(path):c=configparser.ConfigParser(interpolation=None,strict=False);c.optionxform=str;c.read(path,encoding='utf-8');return c
def full_hashes(s):return {p.relative_to(s).as_posix():sha(p) for p in sorted(s.rglob('*')) if p.is_file() and not p.is_symlink()}
raw_before=full_hashes(raw);source_before=full_hashes(source)
expected=json.loads((root/'source-inventory-before.json').read_text())['files']
if source_before!={k:v['sha256'] for k,v in expected.items()}:raise SystemExit('Original changed since snapshot; preserve evidence and investigate before proceeding')
save('raw-before-hashes.json',raw_before)
module=framework/'core/python/session_portable_v1.py'
sys.path.insert(0,str(module.parent));spec=importlib.util.spec_from_file_location('p019_portable',module);portable=importlib.util.module_from_spec(spec);sys.modules[spec.name]=portable;spec.loader.exec_module(portable)
record={'started_utc':datetime.now(timezone.utc).isoformat(),'original_passed_to_export_or_import':False,'raw_snapshot':str(raw),'transport_helper_sha256':sha(module),'status':'IN_PROGRESS'}
save('transport-inspection.json',record)
try:
 d=info['requested_document'];payload=raw/'metadata/interactive_documents'/d['storage_name'];t=tkinter.Tcl();text=payload.read_text()
 name=t.call('dict','get',text,'workspace_metadata','name')
 if name!='produrre_di_bug' or sha(payload)!=d['sha256']:raise ValueError('Private Workspace identity mismatch')
 save('identity-confirmation.json',{'document_id':d['id'],'provider_id':d['provider_id'],'format':d['format'],'format_version':d['format_version'],'revision':d['revision'],'generation':d['generation'],'payload_sha256':sha(payload),'payload_bytes':payload.stat().st_size,'workspace_name':name,'workspace_name_path':'workspace_metadata.name','initial_top_level_name_probe':'No top-level name key; nested field verified without evaluating payload'})
 dirs,files,external=portable.scan_session(raw)
 acquisition_rel,unresolved=portable.find_portable_acquisition_source(raw,files)
 save('dependency-closure.json',{'module_dependencies':portable.discover_dependencies(raw,framework),'external_scan_dependencies':external,'acquisition_relative':acquisition_rel,'unresolved_acquisition':unresolved})
 if external or unresolved:raise ValueError('External source dependency requires review; no automatic outside-snapshot export access')
 dataset_config=parse(raw/'metadata/datasets.ini');datasets=[]
 for sec in dataset_config.sections():
  if not sec.startswith('dataset.'):continue
  row=dict(dataset_config[sec]);rel=row.get('path','');p=raw/rel
  if not rel or not p.resolve().is_relative_to(raw) or not p.is_file():raise ValueError('Dataset payload path is unresolved or outside private snapshot')
  datasets.append({'section':sec,'id':row.get('id'),'path':rel,'source_module':row.get('source_module',row.get('producer_module')),'sha256':sha(p),'bytes':p.stat().st_size})
 save('dataset-payload-closure.json',datasets)
 archive=transport/'private-session-snapshot.zip'
 version=(framework/'VERSION.txt').read_text().strip()
 exported=portable.export_session(raw,archive,framework,version)
 save('export-receipt.json',exported)
 manifest,members=portable.validate_archive(archive)
 # Existing importer may rescope native History only in this unpublished copy.
 work=transport/'working'/source.name;work.parent.mkdir()
 result=portable.import_session(archive,work)
 save('import-receipt.json',result)
 if full_hashes(raw)!=raw_before:raise ValueError('Raw private snapshot changed during transport')
 if full_hashes(source)!=source_before:raise ValueError('Original source changed during transport observation')
 c=parse(work/'metadata/interactive_documents.ini');target=None
 for sec in c.sections():
  if c[sec].get('id')=='idoc_0004':target=dict(c[sec]);break
 if target is None or target!=d:raise ValueError('Imported original Document registry identity changed')
 if sha(work/'metadata/interactive_documents'/d['storage_name'])!=d['sha256']:raise ValueError('Imported Document payload changed')
 for row in datasets:
  if sha(work/row['path'])!=row['sha256']:raise ValueError('Imported canonical Dataset payload changed')
 receipts=[]
 for p in (work/'metadata/history/transport_archives').rglob('*.receipt.tcldict'):
  data=p.read_text();keys=t.splitlist(t.call('dict','keys',data));small={key:t.call('dict','get',data,key) for key in ['family','source_accepted_revision','source_durable_revision','destination_durable_revision','torn_tail','policy','scientific_steps_changed','auxiliary_preserved'] if key in keys}
  receipts.append({'relative':p.relative_to(work).as_posix(),'sha256':sha(p),'receipt':small})
 record.update(status='READY_PRIVATE_TRANSPORTED_FIXTURE',working_session=str(work),archive_sha256=sha(archive),archive_bytes=archive.stat().st_size,original_unchanged=True,raw_snapshot_unchanged=True,document_identity_unchanged=True,dataset_payloads_unchanged=len(datasets),history_transport_receipts=receipts,workspace_name=name,finished_utc=datetime.now(timezone.utc).isoformat())
 save('transport-inspection.json',record);save('working-inventory-before-gui.json',full_hashes(work))
 print(json.dumps({k:record[k] for k in ['status','working_session','dataset_payloads_unchanged','document_identity_unchanged','original_unchanged','raw_snapshot_unchanged']},indent=2))
except BaseException as e:
 record.update(status='NOT_FOR_TEST_USE',error=str(e));save('transport-inspection.json',record);(transport/'failure.txt').write_text(traceback.format_exc());raise
