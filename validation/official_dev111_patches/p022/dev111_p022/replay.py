#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
import argparse,json,os,resource,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('framework',type=Path);p.add_argument('request',type=Path);p.add_argument('output',type=Path);p.add_argument('--desktop-pid',type=int,required=True);p.add_argument('--address-mib',type=int);p.add_argument('--gdb',action='store_true');p.add_argument('--bind-now',action='store_true');p.add_argument('--thread-bootstrap',action='store_true');p.add_argument('--pthread-preload',action='store_true');a=p.parse_args()
a.output.mkdir(exist_ok=False);env={}
for row in Path(f'/proc/{a.desktop_pid}/environ').read_bytes().split(b'\0'):
 if b'=' in row:
  k,v=row.split(b'=',1);env[os.fsdecode(k)]=os.fsdecode(v)
env['LIBGL_ALWAYS_INDIRECT']='0'
if a.bind_now:env['LD_BIND_NOW']='1'
if a.pthread_preload:env['LD_PRELOAD']='libpthread.so.0'
root=a.framework.resolve();cmd=['/usr/bin/tclsh',str(root/'core/native3d/renderer_worker.tcl'),str(root/'core/native3d/bin/libgx3de_viewer_tcl.so'),'readonly']
if a.thread_bootstrap:
 src=a.output.resolve()/'bootstrap.cpp';lib=a.output.resolve()/'bootstrap.so';wrapper=a.output.resolve()/'worker.tcl'
 src.write_text('#include <tcl.h>\n#include <thread>\nextern "C" int Gxp022bootstrap_Init(Tcl_Interp*) {std::thread([]{}).join();return TCL_OK;}\n')
 subprocess.run(['g++','-std=c++17','-shared','-fPIC','-pthread','-I/usr/include/tcl8.6',str(src),'-o',str(lib)],check=True)
 wrapper.write_text(f'load {{{lib}}} Gxp022bootstrap\nsource {{{root}/core/native3d/renderer_worker.tcl}}\n')
 cmd[1]=str(wrapper)
if a.address_mib:cmd=['prlimit',f'--as={a.address_mib*1048576}','--']+cmd
if a.gdb:cmd=['gdb','--batch','-ex','set disable-randomization off','-ex','run','-ex','thread apply all bt 8','--args']+cmd
try:
 r=subprocess.run(cmd,input=a.request.read_bytes(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,cwd=a.output.resolve(),timeout=45,preexec_fn=lambda:resource.setrlimit(resource.RLIMIT_CORE,(268435456,resource.RLIM_INFINITY)))
 (a.output/'STDOUT.log').write_bytes(r.stdout);(a.output/'STDERR.log').write_bytes(r.stderr)
 (a.output/'RESULT.json').write_text(json.dumps(dict(command=cmd,returncode=r.returncode),indent=2)+'\n');print(r.returncode)
except subprocess.TimeoutExpired as e:
 (a.output/'STDOUT.log').write_bytes(e.stdout or b'');(a.output/'STDERR.log').write_bytes(e.stderr or b'');raise
