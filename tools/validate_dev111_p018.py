#!/usr/bin/env python3
"""Read-only GX-TXT dev111-r3 P018 public source/package verification.

Does NOT run native software, open user Sessions, or certify GUI operation.
"""
from __future__ import annotations
import argparse,hashlib,json,pathlib,re,shutil,subprocess,sys,zipfile
ROOT=pathlib.Path(__file__).resolve().parent.parent
MANIFEST=ROOT/'patch-manifest-dev111-p018.json'
EXPECTED='1b7c3b4cf0ecf73303b2a7cf9346f42d6cd8f42c'
P017='b6c0770286698c0c25eaa4b42baabe0b09169415'
def sha(b:bytes)->str:return hashlib.sha256(b).hexdigest()
def need(value:bool,msg:str)->None:
 if not value:raise ValueError(msg)
def relpath(name:str)->pathlib.Path:
 p=pathlib.PurePosixPath(name)
 need(bool(name) and name==p.as_posix() and not p.is_absolute() and '..' not in p.parts and '\\' not in name and not re.match(r'^[A-Za-z]:',name),'Unsafe source path '+name)
 return pathlib.Path(*p.parts)
def inventory()->dict:
 data=json.loads(MANIFEST.read_text('utf8'))
 need(data['schema']=='gxtxt.patch-validation-p018/1','Wrong validator schema')
 need(data['framework']=='0.9.8.10-dev-111' and data['revision']=='r3','Wrong release')
 need(data['newP018Commit']==EXPECTED and data['priorP017Commit']==P017,'Unexpected P017/P018 commit')
 need(data['publishedFrameworkFiles']==26 and data['excludedInternalFiles']==202,'Incorrect public source scope')
 need(len(data['files'])==26 and len(data['originalSourceOnlyFixtures'])==13,'Incomplete P018 tests or framework content')
 need(data['predecessorPatch']==17 and data['tag']=='v0.9.8.10-dev-111-p018','Wrong patch ordering')
 normal=set(data['normalizationPaths'])
 need(normal=={'docs/api/DATASET_TRANSFORM_API_v1.md','plugins/modules/viewer.curve_workbench/SHA256SUMS','plugins/modules/viewer.curve_workbench/SHA256SUMS.txt'},'Unexpected author-source normalization')
 need(data['newlyExecutedRuntimeTests'] is False,'Cannot claim a runtime test')
 seen=set()
 for item in data['originalSourceOnlyFixtures']:
  file=item['path'];p=ROOT/relpath(file)
  need(file.startswith('validation/official_dev111_patches/p018/') and file not in seen,'Unrecognized test source path '+file)
  seen.add(file)
  need(p.is_file() and not p.is_symlink() and p.resolve().is_relative_to(ROOT),'Missing test source '+file)
  b=p.read_bytes()
  need(len(b)==item['bytes'] and sha(b)==item['sha256'],'Changed owner test source '+file)
  need(item['execution']=='ORIGINAL_SOURCE_ONLY_NOT_RERUN','Incorrect test source execution classification')
 for r in data['files']:
  relpath(r['path'])
  need(len(r['publicAfterSha256'])==64 and len(r['authorAfterSha256'])==64,'Invalid file SHA '+r['path'])
  if r['path'] not in normal:
   need(r['sourceExact'] and r['publicAfterSha256']==r['authorAfterSha256'],'Scientific functional source does not match author '+r['path'])
  else:need(not r['sourceExact'],'Expected public-source normalization missing')
 return data
def git(repo:pathlib.Path,*cmd,allow_missing=False)->bytes|None:
 p=subprocess.run(['git','-C',str(repo),*cmd],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 if p.returncode and allow_missing:return None
 need(p.returncode==0,'Git '+repr(cmd)+' '+p.stderr.decode(errors='replace')[:200])
 return p.stdout
def check_repo(data:dict,repo:pathlib.Path)->dict:
 repo=repo.resolve(strict=True)
 need((repo/'.git').exists() and shutil.which('git') is not None,'Git repository with tags required')
 commit=git(repo,'rev-parse','v0.9.8.10-dev-111-p018^{}').decode().strip()
 parent=git(repo,'rev-parse',EXPECTED+'^').decode().strip()
 need(commit==EXPECTED and parent==P017,'Unexpected cumulative Git tag/parent')
 path=repo/relpath(data['publicArchivePath'])
 need(path.is_file() and sha(path.read_bytes())==data['publicArchiveSha256'],'Public patch ZIP differs')
 file_checks=0
 with zipfile.ZipFile(path) as z:
  names=z.namelist()
  need(len(names)==len(set(names)) and all(relpath(n) for n in names),'Untrusted ZIP archive path')
  need(z.testzip() is None,'Corrupted public ZIP')
  for item in data['files']:
   name=item['path']
   old=git(repo,'show',P017+':'+name,allow_missing=True)
   new=git(repo,'show',EXPECTED+':'+name,allow_missing=True)
   previous=sha(old) if old is not None else None
   need(previous==item['publicBeforeSha256'],'P017 public preimage changed '+name)
   need(new is not None and sha(new)==item['publicAfterSha256'],'P018 source content changed '+name)
   need(z.read(name)==new,'P018 ZIP and committed source differ '+name)
   file_checks+=1
 # Native engines from P017 are authoritative and untouched by P018.
 for rel in ['core/native2d/bin/gx2dtcl.so','core/history/libgxtxt_history.so','core/native2d/gx2d_cad_controller_v1.cpp']:
  prior=git(repo,'show',P017+':'+rel)
  current=git(repo,'show',EXPECTED+':'+rel)
  need(prior==current and len(prior)>4096,'P018 altered native C/C++ engine '+rel)
 for rel,tokens in {
  'core/tcl/native2d_cad_canvas_v1.tcl':['oo::class create ::GX::Native2DCadCanvas::Host','method activate {ids}','method event {phase args}','method cancel','method finish'],
  'plugins/modules/viewer.curve_workbench/api/curve_workbench_cad_canvas.tcl':['proc ::GX::CurveWorkbench::_cadCanvas','_cadCanvasAdmit','_cadCanvasCommitted'],
  'core/tcl/dataset_transform_responsive_v1.tcl':['datasetTransformPlanResponsive'],
  'docs/api/NATIVE2D_CAD_CANVAS_HOST_v1.md':['native2DCadCanvasCreate','native2DCadCanvasAttach']
 }.items():
  b=git(repo,'show',EXPECTED+':'+rel,allow_missing=True)
  need(b is not None,'Missing new CORE CAD host API '+rel)
  txt=b.decode('utf8')
  for token in tokens:need(token in txt,'Public CAD/Transform API missing '+token)
 return {'status':'P018_ORDERED_SOURCE_AND_ARCHIVE_SHA_PASS','frameworkFiles':file_checks,'unchangedNativeCORE':3,'runtimeExecuted':False}
def check_final(data:dict,folder:pathlib.Path)->dict:
 folder=folder.resolve(strict=True)
 need((folder/'VERSION.txt').read_text('utf8').strip()=='0.9.8.10-dev-111','Wrong target framework version')
 for item in data['files']:
  target=folder/relpath(item['path'])
  need(target.is_file() and not target.is_symlink() and sha(target.read_bytes())==item['publicAfterSha256'],'Cumulative installed source SHA mismatch '+item['path'])
 return {'status':'P018_FINAL_CUMULATIVE_SOURCE_SHA_PASS','frameworkFiles':len(data['files']),'runtimeExecuted':False}
def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--repository',type=pathlib.Path)
 p.add_argument('--installed-final',type=pathlib.Path)
 p.add_argument('--json',action='store_true')
 args=p.parse_args()
 try:
  data=inventory()
  result={'status':'P018_SOURCE_ONLY_FIXTURES_SHA_PASS','originalSourceScripts':len(data['originalSourceOnlyFixtures'])}
  if args.repository:result['git']=check_repo(data,args.repository)
  if args.installed_final:result['installed']=check_final(data,args.installed_final)
  if args.json:print(json.dumps(result,indent=2))
  else:
   print('PASS: '+result['status'])
   if args.repository:print('PASS: '+result['git']['status'])
   if args.installed_final:print('PASS: '+result['installed']['status'])
   print('No native GUI runtime execution is inferred from source-only checks.')
  return 0
 except (KeyError,ValueError,OSError,zipfile.BadZipFile,UnicodeDecodeError) as err:
  print('VALIDATION ERROR: '+str(err),file=sys.stderr);return 2
if __name__=='__main__':sys.exit(main())
