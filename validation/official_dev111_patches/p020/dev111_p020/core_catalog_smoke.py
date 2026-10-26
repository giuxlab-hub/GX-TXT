#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
import os,pathlib,subprocess,sys,json,tkinter
root=pathlib.Path(sys.argv[1]).resolve(); out=pathlib.Path(sys.argv[2]).resolve();out.mkdir(exist_ok=False,parents=True)
env=os.environ.copy()
for kind in ['CONFIG','DATA','CACHE','STATE']:env['XDG_'+kind+'_HOME']=str(out/kind.lower())
env['GXTXT_JOB_ROOT']=str(out/'jobs')
r=subprocess.run(['/usr/bin/tclsh',str(root/'core/tcl/viewer_development_request.tcl'),str(root),'api_catalog'],env=env,capture_output=True,timeout=60)
(out/'stdout.tcldict').write_bytes(r.stdout);(out/'stderr.log').write_bytes(r.stderr)
print('exit',r.returncode)
print(r.stderr.decode(errors='replace')[-2500:])
if r.returncode:raise SystemExit(r.returncode)
t=tkinter.Tcl();words=t.splitlist(r.stdout.decode());d=dict(zip(words[::2],words[1::2]));assert d['ok']=='1',d
print('PASS CORE load and public API catalog')
