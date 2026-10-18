# SPDX-License-Identifier: GPL-3.0-or-later
"""Compare actual GUI-produced backend reports with fresh independent CLI calls."""
import hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
C=ROOT/'_work_gxtxt_dev107'
GUI=Path(sys.argv[1]).resolve();OUT=Path(sys.argv[2]).resolve()
assert GUI.is_relative_to(ROOT/'_private_dev107') and OUT.is_relative_to(ROOT/'_private_dev107')
OUT.mkdir(exist_ok=False,parents=True)
PROJECT=ROOT/'_private_dev107/development/native3d-project-01'
original=(PROJECT/'handlers.cpp').read_bytes();rows=[]
for stage,report in [('validate','validation.json'),('build','build.json'),('test','tests.json'),('export','candidate.json')]:
    run=subprocess.run(['/usr/bin/python3','-I','-B',str(C/'core/python/gxtxt_viewer_development.py'),stage,str(PROJECT)],capture_output=True,text=True,timeout=130)
    (OUT/(stage+'-console.json')).write_text(run.stdout)
    (OUT/(stage+'-stderr.txt')).write_text(run.stderr)
    assert run.returncode==0,(stage,run.stderr)
    before=(GUI/'gui_backend_reports'/report).read_bytes();after=(PROJECT/'derived'/report).read_bytes()
    assert before==after,(stage,'GUI and CLI backend report bytes differ')
    (OUT/report).write_bytes(after)
    rows.append(dict(stage=stage,status='PASS',report=report,sha256=hashlib.sha256(after).hexdigest(),exact_gui_cli_bytes=True))
assert (PROJECT/'handlers.cpp').read_bytes()==original
(OUT/'matrix.json').write_text(json.dumps(dict(status='PASS',cases=rows,source_sha256=hashlib.sha256(original).hexdigest(),same_project=str(PROJECT)),indent=2)+'\n')
print('PASS four exact GUI/CLI reports, deterministic compiled binary and candidate package; original source preserved')
