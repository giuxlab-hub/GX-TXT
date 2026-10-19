# SPDX-License-Identifier: GPL-3.0-or-later
"""Synthetic verifier fixtures for resource validation, NOT native GUI evidence."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
from unittest.mock import patch
import zipfile

workspace = Path(__file__).resolve().parents[2]
project = Path(sys.argv[1]).resolve()
assert project.parent == workspace/'_private_dev108' and project.name.startswith('manual-asset-contract') and not project.exists()
core = workspace/'_work_gxtxt_dev108/core/python'
sys.path.insert(0, str(core))
from gxtxt_viewer_development import DevelopmentError, dictionary, digest
from gxtxt_viewer_manual_assets import manual_asset, resources
from gxtxt_job_supervisor import tcl_result

def cli(operation, *args, text=None, accepted=True):
    run = subprocess.run(['/usr/bin/python3', '-I', '-B', str(core/'gxtxt_viewer_development.py'), operation, str(project), *args], input=text, text=True, capture_output=True, timeout=120)
    value = json.loads(run.stdout)
    assert (run.returncode == 0) == accepted, value
    return value.get('result', value)

cli('init', '--module-id', 'viewer.manual_asset_contract')
folder = project/'derived/gui-test'
folder.mkdir()
capture_id = '1'*32
source = workspace/'_private_dev108/gui_icons_states02/icon_runtime_normal.png'
image = source.read_bytes()
target = folder/('capture-'+capture_id+'.png')
target.write_bytes(image)
snapshot = {key:digest((project/name).read_bytes()) for name,key in [('handlers.cpp','source_sha256'),('design.gxtxt-viewer','design_sha256'),('project.json','project_sha256')]}
captured = dict(operation='capture', source_snapshot=snapshot, screenshot=str(target), screenshot_sha256=digest(image), session='SYNTHETIC_VERIFIER_FIXTURE_NOT_GUI_EVIDENCE', geometry='fixture')
response_path = folder/('response-'+capture_id+'.tcldict')
def receipt():
    response_path.write_text(tcl_result(dict(ok=1, request_id=capture_id, result=captured)))
receipt()
request = dict(operation='add',asset_id='native-example',capture_id=capture_id)
observations = []
def deny(label, fn):
    try: fn()
    except Exception as error: observations.append(dict(case=label, denied=True, error=str(error)))
    else: raise AssertionError('Accepted '+label)
    assert not (project/'manual-assets.json').exists(), label

for label, change in [('path_id',dict(asset_id='../escape')), ('unknown_field',dict(path=str(target))), ('bad_capture',dict(capture_id='outside'))]:
    deny(label,lambda change=change: manual_asset(project, dict(request,**change)))
def verifier(project_arg, payload):
    assert project_arg == project and payload == dict(operation='capture_verify',capture_id=capture_id)
    return dict(gui_receipt=dict(result=tcl_result(dict(captured,operation='capture_verify'))))
with patch('gxtxt_viewer_gui_test.gui_test', side_effect=DevelopmentError('Capture was not issued by this live source-bound GUI attachment')):
    deny('fabricated_complete_project_receipt', lambda:manual_asset(project,request))
with patch('gxtxt_viewer_gui_test.gui_test', side_effect=verifier):
    captured['screenshot_sha256']='0'*64;receipt()
    deny('wrong_sha',lambda:manual_asset(project,request))
    captured['screenshot_sha256']=digest(image);receipt()
    target.write_bytes(b'not a PNG')
    deny('wrong_codec',lambda:manual_asset(project,request))
    target.unlink();target.symlink_to(source)
    deny('symlink',lambda:manual_asset(project,request))
    target.unlink();target.write_bytes(image)
    original=dict(captured['source_snapshot']);captured['source_snapshot']=dict(original,source_sha256='0'*64);receipt()
    deny('stale_source',lambda:manual_asset(project,request))
    captured['source_snapshot']=original;receipt()
    saved=manual_asset(project,request)
assert saved['installed_path']=='images/native-example.png'
assert manual_asset(project,dict(operation='list'))['inventory']['assets']['native-example']['sha256']==digest(image)
cli('save','--file','MANUAL.md',text='# Native image resource fixture\n\n![Resource fixture](images/native-example.png)\n')
candidate=cli('export')
with zipfile.ZipFile(candidate['package']) as package:
    assert package.read('images/native-example.png')==image
    provenance=json.loads(package.read('review/manual-assets.json'))
    assert provenance['assets']['native-example']['session']=='SYNTHETIC_VERIFIER_FIXTURE_NOT_GUI_EVIDENCE'
    assert package.read('source/manual-assets/'+digest(image)+'.png')==image
cli('save','--file','MANUAL.md',text='![Broken](images/missing.png)\n')
cli('export',accepted=False)
manual_asset(project,dict(operation='remove',asset_id='native-example'))
assert resources(project)[0]=={}
(project/'derived/manual-asset-contract.json').write_text(json.dumps(dict(result='PASS_RESOURCE_CONTRACT_ONLY',synthetic_verifier_fixture=True,genuine_GUI_acceptance='separate mandatory test',observations=observations,candidate=candidate),indent=2)+'\n')
print('PASS synthetic manual resource contract and normal export; no native GUI claim')
