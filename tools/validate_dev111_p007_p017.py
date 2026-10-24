#!/usr/bin/env python3
"""GX-TXT dev111 P007-P017 independent source/package and native identity validation.

Read-only. No application start, no scientific Session creation, no GUI or native computation.
"""
from __future__ import annotations
import argparse,hashlib,json,os,pathlib,re,shutil,struct,subprocess,sys,zipfile
ROOT=pathlib.Path(__file__).resolve().parent.parent
MANIFEST=ROOT/'patch-manifest-dev111-p007-p017.json'
MAIN='4daf135e49378eff1f413310bc17cf32f1928c44'
PREV='5a586abb20b6a43dea72ef5958df5f0fdaddf09e'
LAST='b6c0770286698c0c25eaa4b42baabe0b09169415'
H=lambda b:hashlib.sha256(b).hexdigest()
def need(v,m):
 if not v:raise ValueError(m)
def safe(p):
 path=pathlib.PurePosixPath(p)
 need(p==path.as_posix() and not path.is_absolute() and '..' not in path.parts and '\\' not in p and not re.match(r'^[A-Za-z]:',p),'Unsafe relative path '+p)
 return pathlib.Path(*path.parts)
def load():
 m=json.loads(MANIFEST.read_text('utf8'))
 need(m['schema']=='gxtxt.patch-validation-extension/1' and m['officialMain']==MAIN,'Wrong scientific release source')
 need(m['framework']=='0.9.8.10-dev-111' and m['revision']=='r3','Wrong version-specific patch scope')
 need(m['priorP006Commit']==PREV and m['currentP017Commit']==LAST,'Patch chain incorrect')
 need(m['p017MilestoneStatus']=='ONE_OF_SEVERAL_MILESTONES_NOT_FINAL','P017 incorrectly called final milestone')
 patches=m['patches']
 need(len(patches)==11 and [x['patch'] for x in patches]==[f'P{n:03d}' for n in range(7,18)],'Incomplete patch tags')
 need(len(m['selectedPortableSourceTests'])==31,'Missing original P016/P017 source fixture')
 tested=set()
 for row in m['selectedPortableSourceTests']:
  rel=row['path'];safe(rel)
  need(rel.startswith('validation/official_dev111_patches/p016/') or rel.startswith('validation/official_dev111_patches/p017/'),'Unexpected source-only test path')
  need(rel not in tested,'Duplicate test source '+rel);tested.add(rel)
  p=ROOT/safe(rel)
  need(not p.is_symlink() and p.is_file() and p.resolve().is_relative_to(ROOT),'Missing portable original test source '+rel)
  raw=p.read_bytes()
  need(len(raw)==row['bytes'] and H(raw)==row['sha256'],'Unexpected original test file bytes '+rel)
  need(row['execution']=='ORIGINAL_SOURCE_ONLY_NOT_RERUN','Incorrect source-only execution classification')
  for token in ('/srv/gxtxt/','/home/giu/','GXTXT_SCRIPT_WORKSPACE_DEBUGGER_GUIDE_WP_dev107','BEGIN PRIVATE KEY'):
   need(token not in raw.decode('utf8'),'Excluded owner-private file reference '+rel)
 for n,p in enumerate(patches,7):
  need(p['tag']==f'v0.9.8.10-dev-111-p{n:03d}' and p['requiredPredecessor']==n-1,'Broken patch predecessor')
  need(len(p['commit'])==len(p['parent'])==40,'Invalid Git object ID '+p['tag'])
  need(re.fullmatch(r'[0-9a-f]{64}',p['publicArchiveSha256']) is not None,'Invalid ZIP hash')
  need(len(p['files'])==p['originalChangedFiles']-p['excludedPrivateFiles'],'Private source inventory mismatch')
  seen=set()
  for file in p['files']:
   rel=file['path'];safe(rel)
   need(rel not in seen,'Duplicate source path '+rel);seen.add(rel)
   for field in ['publicAfter','authorAfter']:
    need(re.fullmatch(r'[0-9a-f]{64}',file[field]) is not None,'Missing signed file SHA '+rel)
   for field in ['publicBefore','authorBefore']:
    v=file[field]
    need(v is None or re.fullmatch(r'[0-9a-f]{64}',v) is not None,'Invalid prerequisite hash '+rel)
   if not file['sourceExact']:
    need(rel.endswith(('/SHA256SUMS','/SHA256SUMS.txt')),'Executable or documentation unexpectedly changed from owner archive '+rel)
 return m
class Git:
 def __init__(self,p):
  self.root=p.resolve(strict=True)
  need((self.root/'.git').exists(),'Independent Git checkout required')
  need(shutil.which('git') is not None,'Git executable missing')
 def call(self,*args,allow_missing=False):
  p=subprocess.run(['git','-C',str(self.root),*args],stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=False)
  if p.returncode and allow_missing:return None
  need(p.returncode==0,'Git failed '+repr(args)+' '+p.stderr.decode(errors='replace')[:160])
  return p.stdout
 def rev(self,ref):return self.call('rev-parse',ref).decode().strip()
 def blob(self,commit,rel):safe(rel);return self.call('show',commit+':'+rel,allow_missing=True)
def elf64_x64(data):
 need(len(data)>=4096 and data[:4]==b'\x7fELF','Native object must be real ELF')
 need(data[4:6]==b'\x02\x01' and struct.unpack_from('<H',data,18)[0]==62,'Native shared library must be x86-64 ELF64')
 need(struct.unpack_from('<H',data,16)[0]==3,'Native module must be ELF shared object')
def native_check(g,m):
 last=m['patches'][-1]['commit']
 for path in ('core/history/libgxtxt_history.so','core/native2d/bin/gx2dtcl.so'):
  b=g.blob(last,path);need(b is not None,'Missing native binary '+path);elf64_x64(b)
 for path in (
  'core/history/history_engine.cpp','core/tcl/scientific_history_native.tcl',
  'core/tcl/scientific_recipe_history.tcl',
  'plugins/modules/viewer.curve_workbench/api/curve_workbench_history.tcl',
  'core/native2d/gx2d_sprite_scene_v1.cpp','core/native2d/gx2d_cad_controller_v1.cpp',
  'core/tcl/native2d_sprite_scene_v1.tcl',
 ):
  b=g.blob(last,path)
  need(b is not None and len(b)>200,'Missing cumulative History/Sprites/CAD scientific owner '+path)
 return 9
def check_git(m,folder):
 g=Git(folder)
 need(g.rev('v0.9.8.10-dev-111-p017^{}')==LAST,'Wrong final tag P017')
 totals=0;archived=0
 for row in m['patches']:
  commit=row['commit'];prior=row['parent'];n=row['patch']
  need(g.rev(row['tag']+'^{}')==commit and g.rev(commit+'^')==prior,'Broken P007–P017 tag/commit ancestry '+n)
  f=folder/safe(row['archivePath'])
  need(f.is_file() and not f.is_symlink() and len(f.read_bytes())==row['publicArchiveBytes'] and H(f.read_bytes())==row['publicArchiveSha256'],'Wrong package download/archive '+n)
  with zipfile.ZipFile(f) as z:
   names=z.namelist()
   need(z.testzip() is None and len(names)==len(set(names)) and all(safe(item) for item in names),'Unsafe ZIP source member '+n)
   for item in row['files']:
    rel=item['path'];old=g.blob(prior,rel);new=g.blob(commit,rel)
    oldsha=H(old) if old is not None else None
    need(oldsha==item['publicBefore'],'Changed original public preimage '+n+' '+rel)
    need(new is not None and H(new)==item['publicAfter'],'Published postimage wrong '+n+' '+rel)
    need(z.read(rel)==new,'ZIP source differs from committed tree '+n+' '+rel)
    if item['sourceExact']:need(H(new)==item['authorAfter'],'Runtime source diverged from owner '+n+' '+rel)
    totals+=1
   archived+=1
 checked=native_check(g,m)
 return {'status':'P007_P017_STATIC_CHAIN_PASS','patches':len(m['patches']),'sourceChecks':totals,'archives':archived,'nativeHistorySpriteCad':checked,'scientificGuiExecution':'NOT_PERFORMED'}
def check_final(m,root):
 root=root.resolve(strict=True)
 need((root/'VERSION.txt').read_text('utf8').strip()=='0.9.8.10-dev-111','Wrong installed source version')
 latest={}
 for p in m['patches']:
  for item in p['files']:latest[item['path']]=item['publicAfter']
 for name,expected in latest.items():
  p=root/safe(name)
  need(p.is_file() and not p.is_symlink() and H(p.read_bytes())==expected,'Cumulative installed path differs '+name)
 for file in ('core/history/libgxtxt_history.so','core/native2d/bin/gx2dtcl.so'):
  elf64_x64((root/safe(file)).read_bytes())
 return {'status':'P017_FINAL_CUMULATIVE_SOURCE_SHA_PASS','uniqueFileHashes':len(latest),'runtimeExecuted':False}
def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--repository',type=pathlib.Path)
 parser.add_argument('--installed-final',type=pathlib.Path)
 parser.add_argument('--json',action='store_true')
 args=parser.parse_args()
 try:
  data=load()
  result={'status':'P007_P017_ORIGINAL_SOURCE_FIXTURES_PASS','fixtures':len(data['selectedPortableSourceTests'])}
  if args.repository:result['repository']=check_git(data,args.repository)
  if args.installed_final:result['installed']=check_final(data,args.installed_final)
  if args.json:print(json.dumps(result,indent=2))
  else:
   print('PASS: '+result['status']+' ('+str(result['fixtures'])+' original P016/P017 test scripts)')
   if args.repository:print('PASS: '+result['repository']['status']+' ('+str(result['repository']['patches'])+' historical version-bound tags)')
   if args.installed_final:print('PASS: '+result['installed']['status'])
   print('No independent Linux GUI/native scientific test is executed by these static checks.')
  return 0
 except (ValueError,OSError,UnicodeError,zipfile.BadZipFile,KeyError) as e:
  print('VALIDATION ERROR: '+str(e),file=sys.stderr);return 2
if __name__=='__main__':sys.exit(main())
