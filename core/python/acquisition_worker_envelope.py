#!/usr/bin/env python3
"""Bounded control envelope for the existing Acquisition managed-request owner.
No Dataset, Job or persistence authority is implemented here.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
import argparse,json,os,re,shutil,subprocess,sys,time,uuid
from pathlib import Path
from gxtxt_job_supervisor import request_process_group,tcl_result

def atomic(path,value):
    path=Path(path);temporary=path.with_name(path.name+'.'+uuid.uuid4().hex+'.tmp')
    try:
        with temporary.open('x',encoding='utf-8') as stream:stream.write(tcl_result(value))
        os.replace(temporary,path)
    finally:
        if temporary.exists():temporary.unlink()

def main():
    operation=sys.argv[1]
    parser=argparse.ArgumentParser();parser.add_argument('--framework');parser.add_argument('--request');parser.add_argument('--progress')
    if operation=='parser':parser.add_argument('command',nargs=argparse.REMAINDER)
    args=parser.parse_args(sys.argv[2:])
    if operation=='bootstrap':
        request_process_group()
        tcl=shutil.which('tclsh')
        if not tcl:raise ValueError('The existing local Tcl runtime is unavailable')
        worker=Path(args.framework).resolve()/'core/tcl/acquisition_managed_request.tcl'
        os.execv(tcl,[tcl,str(worker),str(Path(args.framework).resolve()),args.request])
    command=args.command
    if command and command[0]=='--':command=command[1:]
    if not command:raise ValueError('Missing Acquisition parser command')
    child=None;tail='';total=0;last=0
    try:
        child=subprocess.Popen(command,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        while True:
            raw=child.stdout.readline(65537)
            if not raw:break
            total+=len(raw)
            if len(raw)>65536 or total>1048576:raise ValueError('Acquisition parser exceeded its bounded diagnostic protocol')
            line=raw.decode('utf-8',errors='replace');tail=(tail+line)[-8192:]
            found=re.search(r'\[IMPORT\].*?rows=(\d+).*?progress=([0-9.]+)%',line)
            if found and args.progress:
                rows=int(found.group(1));percent=max(0,min(100,float(found.group(2))))
                atomic(args.progress,dict(rows=rows,current=percent,total=100,phase='parser',message=f'Parsing source: {rows} rows ({percent:.1f}%)'))
        rc=child.wait()
        if rc:raise ValueError(f'Acquisition parser exited with status {rc}: {tail}')
        print(tcl_result(dict(ok=True,result=dict(exit_code=rc,diagnostic_tail=tail))))
        return 0
    except BaseException as exc:
        if child is not None and child.poll() is None:
            child.terminate()
            try:child.wait(timeout=2)
            except subprocess.TimeoutExpired:child.kill();child.wait()
        print(tcl_result(dict(ok=False,error=str(exc)[-8192:])))
        return 0
if __name__=='__main__':raise SystemExit(main())
