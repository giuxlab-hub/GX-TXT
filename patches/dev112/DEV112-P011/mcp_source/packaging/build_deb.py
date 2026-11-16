#!/usr/bin/env python3
"""Build an offline adapter Debian package from verified pinned wheels."""
from pathlib import Path
import ast
import hashlib
import json
import os
import shutil
import subprocess
import sys
import zipfile

framework,wheels,output=map(lambda v:Path(v).resolve(),sys.argv[1:])
output.mkdir(parents=True,exist_ok=False)
source=framework/'integrations/mcp'
version=next(ast.literal_eval(node.value) for node in ast.parse((source/'gxtxt_mcp/__init__.py').read_text()).body if isinstance(node,ast.Assign) and any(isinstance(target,ast.Name) and target.id=='__version__' for target in node.targets))
lock=json.loads((source/'requirements.lock.json').read_text())
stage=output/'root';library=stage/'usr/lib/gxtxt-mcp-server'
library.mkdir(parents=True)
shutil.copytree(source/'gxtxt_mcp',library/'gxtxt_mcp',ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
shutil.copy2(source/'gxtxt-mcp',library/'gxtxt-mcp')
vendor=library/'vendor';vendor.mkdir()
notices=[]
for item in lock['wheels']:
    wheel=wheels/item['filename']
    if hashlib.sha256(wheel.read_bytes()).hexdigest()!=item['sha256']:raise SystemExit('Wheel checksum mismatch: '+wheel.name)
    with zipfile.ZipFile(wheel) as archive:
        for entry in archive.infolist():
            relative=Path(entry.filename)
            if relative.is_absolute() or '..' in relative.parts or (entry.external_attr>>16)&0o170000==0o120000:
                raise SystemExit('Unsafe wheel member')
            # Current lock wheels have no executable entrypoint requirement.
            if '.data' in relative.parts[0]:
                if len(relative.parts)>2 and relative.parts[1] in {'purelib','platlib'}:relative=Path(*relative.parts[2:])
                else:raise SystemExit('Unreviewed wheel installation scheme')
            target=vendor/relative
            if entry.is_dir():target.mkdir(parents=True,exist_ok=True);continue
            target.parent.mkdir(parents=True,exist_ok=True)
            if target.exists() and target.read_bytes()!=archive.read(entry):raise SystemExit('Wheel member collision')
            target.write_bytes(archive.read(entry));target.chmod(0o644)
    notices.append(f"{item['name']} {item['version']}: {item['license']}\nSHA256 {item['sha256']}\n")
binary=stage/'usr/bin';binary.mkdir(parents=True)
shutil.copy2(source/'gxtxt-mcp',binary/'gxtxt-mcp');(binary/'gxtxt-mcp').chmod(0o755)
documentation=stage/'usr/share/doc/gxtxt-mcp-server';documentation.mkdir(parents=True)
for name in ('requirements.lock','requirements.lock.json','README.md'):
    shutil.copy2(source/name,documentation/name)
(documentation/'copyright').write_text('GX-TXT MCP adapter: GPL-3.0-or-later. See /usr/share/common-licenses/GPL-3.\n\n'
    +'Third-party dependencies are isolated under /usr/lib/gxtxt-mcp-server/vendor.\n'
    +'Their original .dist-info license notices and METADATA are included there.\n\n'+'\n'.join(notices))
unit=stage/'usr/lib/systemd/user';unit.mkdir(parents=True)
shutil.copy2(source/'packaging/gxtxt-mcp.service',unit/'gxtxt-mcp.service')
control=stage/'DEBIAN';control.mkdir()
(control/'control').write_text(f'Package: gxtxt-mcp-server\nVersion: {version}-1\nArchitecture: amd64\n'
    'Maintainer: GX-TXT maintainers <maintainers@gxtxt.invalid>\nSection: science\nPriority: optional\n'
    'Depends: python3 (>= 3.13), python3 (<< 3.14), python3-tk, ca-certificates\n'
    'Description: Optional authenticated capability-negotiated local MCP adapter for GX-TXT\n'
    ' Uses an explicitly selected existing framework; no bundled scientific engine.\n'
    ' Disabled by default. No automatic clients, grants, service activation or tunnel.\n')
for path in stage.rglob('*'):
    if path.is_dir():path.chmod(0o755)
    else:path.chmod(0o755 if path in {binary/'gxtxt-mcp',library/'gxtxt-mcp'} else 0o644)
    os.utime(path,(1794528000,1794528000))
package=output/f'gxtxt-mcp-server_{version}-1_amd64.deb'
subprocess.run(['dpkg-deb','--root-owner-group','-Zxz','--build',str(stage),str(package)],check=True,
               env=dict(os.environ,SOURCE_DATE_EPOCH='1794528000'))
(output/'BUILD.json').write_text(json.dumps({'framework_version':(framework/'VERSION.txt').read_text().strip(),
    'patch':(framework/'PATCH_LEVEL.txt').read_text().strip(),'package':package.name,
    'sha256':hashlib.sha256(package.read_bytes()).hexdigest(),'dependencies':lock,'automatic_activation':False},indent=2)+'\n')
print(package)
