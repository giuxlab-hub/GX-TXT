# SPDX-License-Identifier: GPL-3.0-or-later
"""Read-only local TeX inventory for the existing Configuration request owner."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
from gxtxt_job_supervisor import tcl_result


def probe(command):
    try:
        result=subprocess.run(command,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT,timeout=4)
        return dict(status='available' if result.returncode==0 else 'test failed',
                    text=result.stdout[:262144].decode('utf-8',errors='replace').strip(),exit_code=result.returncode)
    except (OSError,subprocess.TimeoutExpired) as exc:
        return dict(status='unavailable',text=str(exc),exit_code=-1)


def inventory(configured):
    entries=[];roots=[]
    for name in ['latexmk','pdflatex','xelatex','lualatex','kpsewhich','bibtex','biber']:
        executable=shutil.which(name)
        result=probe([executable,'--version']) if executable else dict(status='not detected',text='')
        entries.append(dict(name=name,kind='tool',version=result['text'].splitlines()[0] if result['text'] else '',location=executable or '',status=result['status']))
    configured_result=probe([configured,'--version']) if configured else dict(status='not configured',text='')
    entries.insert(0,dict(name='Configured LaTeX runtime',kind='configured tool',version=configured_result['text'].splitlines()[0] if configured_result['text'] else '',location=configured,status=configured_result['status']))
    kpse=shutil.which('kpsewhich')
    if kpse:
        for variable in ['TEXMFDIST','TEXMFLOCAL','TEXMFHOME']:
            result=probe([kpse,'-var-value='+variable]);root=result['text']
            entries.append(dict(name=variable,kind='search root',version='',location=root,status=result['status']))
            path=Path(root)
            if result['status']=='available' and path.is_absolute() and path.is_dir() and not path.is_symlink():roots.append(path)
    suffixes={'.sty':'package','.cls':'class','.bst':'bibliography style','.bib':'bibliography resource','.tfm':'font metrics','.otf':'font','.ttf':'font'}
    seen=set();truncated=False
    for root in roots:
        for directory,dirs,files in os.walk(root,followlinks=False):
            dirs[:]=sorted(d for d in dirs if not (Path(directory)/d).is_symlink())
            for name in sorted(files):
                path=Path(directory)/name
                if path.suffix.lower() not in suffixes or path.is_symlink() or str(path) in seen:continue
                if len(entries)>=20000:truncated=True;break
                seen.add(str(path))
                # A filename establishes installed resource presence, not a
                # guessed package version or successful document compilation.
                entries.append(dict(name=name,kind=suffixes[path.suffix.lower()],version='not advertised',location=str(path),status='installed resource'))
            if truncated:break
        if truncated:break
    return dict(entries=entries,total=len(entries),truncated=truncated,configured=configured,
                status=configured_result['status'],scope='Read-only filenames/native tool diagnostics; no installation, update or promise every TeX project compiles')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--configured',default='')
    args=parser.parse_args()
    # Existing managed-request group cancellation owns this probe and native
    # version/search children together. It is not a scientific Job.
    if os.getpgrp()!=os.getpid():
        os.setsid()
    try:print(tcl_result(dict(ok=True,result=inventory(args.configured))))
    except Exception as exc:print(tcl_result(dict(ok=False,error=str(exc))));raise SystemExit(1)
