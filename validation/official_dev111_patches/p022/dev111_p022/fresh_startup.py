#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""P022 fresh-unpacking public API startup; headless, not GUI acceptance."""
from pathlib import Path
import argparse, os, subprocess, sys, tkinter
sys.dont_write_bytecode = True
sys.path.insert(0,str(Path(__file__).resolve().parent))
from release_common import GuardError,require,fresh_scratch,write_json,sha


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('framework',type=Path);parser.add_argument('new_output',type=Path)
    args=parser.parse_args();root=args.framework.resolve();out=fresh_scratch(args.new_output);out.mkdir(mode=0o700)
    env=os.environ.copy()
    for key,relative in [('HOME','home'),('TMPDIR','tmp'),('GXTXT_JOB_ROOT','jobs')]:
        path=out/relative;path.mkdir();env[key]=str(path)
    for kind in ('CONFIG','DATA','CACHE','STATE'):
        env['XDG_'+kind+'_HOME']=str(out/kind.lower())
    env['PYTHONDONTWRITEBYTECODE']='1'
    command=['/usr/bin/tclsh',str(root/'core/tcl/viewer_development_request.tcl'),str(root),'api_catalog']
    result=subprocess.run(command,env=env,capture_output=True,timeout=60)
    (out/'stdout.tcldict').write_bytes(result.stdout);(out/'stderr.log').write_bytes(result.stderr)
    require(result.returncode==0,'Public CORE startup failed; inspect retained stderr')
    interpreter=tkinter.Tcl();words=interpreter.splitlist(result.stdout.decode('utf-8'))
    outer=dict(zip(words[::2],words[1::2]));require(outer.get('ok')=='1','Public catalog rejected request')
    words=interpreter.splitlist(outer['result']);catalog=dict(zip(words[::2],words[1::2]))
    required=('NATIVE2D_API_v1','NATIVE2D_VIEWPORT_HOST_v1','NATIVE2D_SPRITE_SCENE_API_v1',
              'NATIVE_2D_GEOMETRY_API_v1','NATIVE_3D_GEOMETRY_API_v1','NATIVE_3D_GUI_HOST_API_v1',
              'NATIVE_3D_GUI_HOST_API_v2','GUI_UPDATE_SCHEDULER_API_v1','STDERR_DIAGNOSTICS_API_v1')
    require(set(required)<=set(catalog),'Required cumulative public APIs not discoverable')
    write_json(out/'RESULT.json',dict(status='PASS',scope='headless public startup, not real GUI',command=command,
               exit_code=result.returncode,required_public_apis=list(required),catalog_entries=len(catalog),
               entrypoint_sha256=sha(root/'core/tcl/viewer_development_request.tcl'),
               stdout_sha256=sha(out/'stdout.tcldict'),stderr_sha256=sha(out/'stderr.log'),
               isolated_home=str(out/'home'),installed=False,user_data_changed=False))
    print('PASS public P022 startup;',len(catalog),'API entries; no GUI acceptance claim')

if __name__=='__main__':
    try:main()
    except(GuardError,OSError,ValueError,KeyError,subprocess.SubprocessError)as error:raise SystemExit('FAIL: '+str(error))
