#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Normal GUI entrypoint; only data/profile isolation differs from the desktop."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
p=argparse.ArgumentParser();p.add_argument('framework',type=Path);p.add_argument('output',type=Path);p.add_argument('--fixture',type=Path,required=True);p.add_argument('--environment-pid',type=int);a=p.parse_args()
root=a.framework.resolve();out=a.output.resolve();out.mkdir(exist_ok=False)
if a.environment_pid:pid=a.environment_pid
else:
 candidates=[x for x in Path('/proc').iterdir() if x.name.isdigit() and x.stat().st_uid==os.getuid() and (x/'comm').exists() and (x/'comm').read_text().strip()=='xfce4-session']
 assert len(candidates)==1,candidates
 pid=int(candidates[0].name)
proc=Path('/proc')/str(pid);assert proc.stat().st_uid==os.getuid()
env={}
for row in (proc/'environ').read_bytes().split(b'\0'):
 if b'=' in row:
  k,v=row.split(b'=',1);env[os.fsdecode(k)]=os.fsdecode(v)
# A terminal snapshot may point remotely: this task's primary environment is
# the actual desktop. Require its existing DISPLAY instead of overriding it.
assert env.get('DISPLAY') in [':0',':0.0'],env.get('DISPLAY')
profile=a.fixture.resolve();assert (profile/'FIXTURE.tcldict').is_file()
for k,d in {'HOME':'home','XDG_CONFIG_HOME':'config','XDG_DATA_HOME':'data','XDG_CACHE_HOME':'cache','XDG_STATE_HOME':'state','GXTXT_INSTALLATION_ROOT':'installation','GXTXT_RESOURCE_ROOT':'resources','GXTXT_RESOURCE_STORAGE':'buffers','GXTXT_JOB_ROOT':'jobs','TMPDIR':'tmp'}.items():env[k]=str(profile/d)
cmd=['wish','gxtxt_pipeline.tcl']
with (out/'stdout.log').open('wb') as stdout,(out/'stderr.log').open('wb') as stderr:
 child=subprocess.Popen(cmd,cwd=root,env=env,stdin=subprocess.DEVNULL,stdout=stdout,stderr=stderr,start_new_session=True)
whitelist={k:v for k,v in env.items() if k in ['DISPLAY','XAUTHORITY','XDG_SESSION_TYPE','LD_LIBRARY_PATH','LD_PRELOAD','LIBGL_ALWAYS_INDIRECT','LIBGL_ALWAYS_SOFTWARE','MESA_LOADER_DRIVER_OVERRIDE','GALLIUM_DRIVER','__GLX_VENDOR_LIBRARY_NAME'] or k.startswith('__GLX_FORCE_VENDOR_LIBRARY_')}
result=dict(command=cmd,cwd=str(root),source_commit=subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip(),entrypoint_sha256=hashlib.sha256((root/'gxtxt_pipeline.tcl').read_bytes()).hexdigest(),desktop_environment_pid=pid,graphics_environment=whitelist,graphics_overrides_added=False,private_profile=str(profile),pid=child.pid,start_time=(Path('/proc')/str(child.pid)/'stat').read_text().split()[21])
(out/'LAUNCH.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
