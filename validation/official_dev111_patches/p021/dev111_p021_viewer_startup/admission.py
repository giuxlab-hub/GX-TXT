# SPDX-License-Identifier: GPL-3.0-or-later
import pathlib, sys, os, json, shutil, importlib.util, hashlib
framework=pathlib.Path(sys.argv[1]).resolve(); output=pathlib.Path(sys.argv[2]).resolve()
if output.exists(): raise RuntimeError('Fresh output required')
output.mkdir(parents=True,mode=0o700)
for key,name in {'XDG_CONFIG_HOME':'config','XDG_DATA_HOME':'data','XDG_CACHE_HOME':'cache','XDG_STATE_HOME':'state','GXTXT_INSTALLATION_ROOT':'installation','GXTXT_RESOURCE_ROOT':'resources','GXTXT_RESOURCE_STORAGE':'buffers','GXTXT_JOB_ROOT':'jobs','TMPDIR':'tmp'}.items():
 p=output/name;p.mkdir(mode=0o700);os.environ[key]=str(p)
spec=importlib.util.spec_from_file_location('development',framework/'core/python/gxtxt_viewer_development.py');api=importlib.util.module_from_spec(spec);spec.loader.exec_module(api)
source=framework/'plugins/modules/viewer.dev107_restricted_native3d'
results=[]
def fixture(name):
 root=output/name;shutil.copytree(source,root);return root
def run(name, mutate=None, expected=None):
 root=fixture(name); receipt=root/'review/build.json';pre=receipt.read_bytes()
 if mutate: mutate(root)
 before=receipt.read_bytes()
 try:
  result=api.installed_inspect(root,output/('work-'+name))
  if expected: raise AssertionError('Expected '+expected)
  assert receipt.read_bytes()==before
  results.append(dict(test=name,status='PASS',contract=result['workspace_callback_contract_sha256'],receipt_unchanged=True,runtime_compilation=result['runtime_compilation']))
  return result
 except api.DevelopmentError as e:
  if e.code!=expected: raise
  results.append(dict(test=name,status='PASS',expected_error=expected,observed=str(e)))
def receipt_set(root,value):
 p=root/'review/build.json';v=json.loads(p.read_text());v['validation']['workspace_callback_contract_sha256']=value;p.write_text(json.dumps(v))
def append(root,rel):
 with (root/rel).open('ab') as f:f.write(b'\n')
legacy=run('legacy-normalized')
assert len(legacy['workspace_callback_contract_sha256'])==64
kept='0'*64
report=run('existing-contract-preserved',lambda root:receipt_set(root,kept))
assert report['workspace_callback_contract_sha256']==kept
run('source-mismatch',lambda root:append(root,'source/handlers.cpp'),'BINARY_SOURCE_MISMATCH')
run('interface-mismatch',lambda root:append(root,'gui/design.tcldict'),'BINARY_SOURCE_MISMATCH')
run('binary-mismatch',lambda root:append(root,'native/viewer.so'),'BINARY_INCOMPATIBLE')
(output/'RESULT.json').write_text(json.dumps({'framework':str(framework),'backend_sha256':hashlib.sha256((framework/'core/python/gxtxt_viewer_development.py').read_bytes()).hexdigest(),'results':results},indent=2)+'\n')
print(json.dumps(results,indent=2))
