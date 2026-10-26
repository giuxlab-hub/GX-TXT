#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
import hashlib,json,subprocess,sys
root,out=map(lambda p:Path(p).resolve(),sys.argv[1:])
assert not out.exists() and out.is_relative_to('/srv/gxtxt/agents/scratch')
out.mkdir(parents=True)
common=['c++','-std=c++17','-O2','-fPIC','-shared','-Wall','-Wextra','-I/usr/include/tcl8.6']
commands=[common+['-I'+str(root/'core/native3d/include'),str(root/'core/native3d/gx3de_viewer_tcl.cpp'),'-L'+str(root/'core/native3d/lib'),'-lgx3de','-ltcl8.6','-Wl,-rpath,$ORIGIN/../lib','-o',str(out/'libgx3de_viewer_tcl.so')],common+['-Werror',str(root/'core/native3d/gx3de_projection_tcl_v1.cpp'),'-ltcl8.6','-o',str(out/'gx3de_projection_tcl_v1.so')]]
for i,command in enumerate(commands):
    r=subprocess.run(command,capture_output=True)
    (out/f'{i}.stdout').write_bytes(r.stdout);(out/f'{i}.stderr').write_bytes(r.stderr)
    if r.returncode:raise SystemExit(f'Build failed {i}: {r.stderr.decode(errors="replace")[-8000:]}')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
sources=['core/native3d/gx3de_viewer_tcl.cpp','core/native3d/gx3de_projection_tcl_v1.cpp','core/native3d/gx3de_projection_snapshot_v1.h','core/native3d/renderer_worker.tcl','core/native3d/CMakeLists.txt']
engines={p.relative_to(root).as_posix():sha(p) for p in(root/'core/native3d/lib').rglob('*') if p.is_file()}
receipt=dict(commands=commands,sources={p:sha(root/p) for p in sources},protected_engine_binaries=engines,binaries={p.name:sha(p) for p in out.glob('*.so')})
(out/'BUILD.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt['binaries'],indent=2))
