#!/usr/bin/env python3
"""Independent generator: public Session/bootstrap plus registered API producer."""
# SPDX-License-Identifier: GPL-3.0-or-later
import argparse
import os
from pathlib import Path
import shutil
import subprocess

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--target-session',required=True)
    parser.add_argument('--library-id')
    parser.add_argument('--generator-id')
    parser.add_argument('--framework',default=os.environ.get('GXTXT_FRAMEWORK_ROOT',''))
    args=parser.parse_args()
    if not args.framework:
        parser.error('The public host must provide GXTXT_FRAMEWORK_ROOT, or supply --framework explicitly')
    framework=Path(args.framework).resolve();target=Path(args.target_session).resolve()
    if not (framework/'gxtxt_pipeline.tcl').is_file() or not target.is_dir():
        raise ValueError('A real framework API bootstrap and fresh target Session are required')
    here=Path(__file__).resolve().parent
    subprocess.run(['tclsh',str(here/'public_producer.tcl'),str(framework),str(target),str(here/'worksheet_session.py')],check=True)
    guide=target/'STUDENT_GUIDE.md'
    if guide.exists():raise FileExistsError('Refusing to overwrite an existing Session guide')
    shutil.copyfile(here/'STUDENT_GUIDE.md',guide)
    print('Generated scientific Workspace, canonical sources, exact formula lineage and native charts through public APIs',flush=True)

if __name__=='__main__':main()
