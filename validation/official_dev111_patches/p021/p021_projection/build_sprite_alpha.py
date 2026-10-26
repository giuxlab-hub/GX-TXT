#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build the existing Native2D adapter target in a new private directory."""
import hashlib, json, pathlib, subprocess, sys, time
root=pathlib.Path(sys.argv[1]).resolve(); out=pathlib.Path(sys.argv[2]).resolve()
if out.exists(): raise SystemExit('Fresh private output required')
out.mkdir(parents=True)
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
paths=[p for p in (root/'core/native2d').iterdir() if p.is_file() and p.suffix in ('.c','.cpp','.h','.inc','.txt')]
paths.append(root/'plugins/modules/math.numeric/api/c/gxtxt_numeric_reductions_v1.h')
pins={str(p.relative_to(root)):sha(p) for p in paths}
extra=[]
if len(sys.argv)>3: extra=['-DGXTXT_CAIRO_INCLUDE='+str(pathlib.Path(sys.argv[3]).resolve()),'-DGXTXT_CAIRO_LIBRARY=/usr/lib/x86_64-linux-gnu/libcairo.so.2']
commands=[['cmake','-S',str(root/'core/native2d'),'-B',str(out/'build'),'-DCMAKE_BUILD_TYPE=Release','-DBUILD_TESTING=OFF']+extra,['cmake','--build',str(out/'build'),'--target','gx2dtcl','--parallel','2']]
dependency_headers={}
if len(sys.argv)>3: dependency_headers={str(p):sha(p) for p in pathlib.Path(sys.argv[3]).resolve().glob('*.h')}
receipt={'dependency_headers':dependency_headers,'source_commit':subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip(),'sources':pins,'commands':[]}
for index,cmd in enumerate(commands):
    started=time.monotonic();r=subprocess.run(cmd,text=True,capture_output=True)
    (out/f'command-{index}.stdout').write_text(r.stdout);(out/f'command-{index}.stderr').write_text(r.stderr)
    receipt['commands'].append({'command':cmd,'seconds':time.monotonic()-started,'exit':r.returncode})
    (out/'BUILD.json').write_text(json.dumps(receipt,indent=2)+'\n')
    if r.returncode: raise SystemExit(r.returncode)
if any(sha(root/p)!=v for p,v in pins.items()): raise SystemExit('Source changed during build')
binary=out/'build/gx2dtcl.so';receipt['binary']={'path':str(binary),'sha256':sha(binary),'bytes':binary.stat().st_size}
receipt['compiler']=subprocess.check_output(['c++','--version'],text=True)
(out/'BUILD.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt['binary']))
