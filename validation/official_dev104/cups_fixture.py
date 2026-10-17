#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Private CUPS executables: never forwards a command to any real printer."""
from pathlib import Path
import json, os, signal, subprocess, sys, time
root=Path(os.environ['GXTXT_CUPS_FIXTURE_ROOT']).resolve()
if '_private_dev104' not in root.parts or not (root/'.private-cups-fixture').is_file():
    raise RuntimeError('Explicit private CUPS fixture required')
tool=Path(sys.argv[0]).name;args=sys.argv[1:]
mode=(root/'mode').read_text().strip()
def log(**fields):
    with (root/'calls.jsonl').open('a') as stream:
        stream.write(json.dumps(dict(tool=tool,args=args,pid=os.getpid(),ppid=os.getppid(),group=os.getpgrp(),mode=mode,**fields))+'\n')
log(event='start')
if mode in ('hang_discovery','hang_options') and ((tool=='lpstat' and args==['-e']) if mode=='hang_discovery' else tool=='lpoptions'):
    child=subprocess.Popen([sys.executable,'-c','import signal,time;signal.signal(signal.SIGTERM,signal.SIG_IGN);time.sleep(60)'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    log(event='stubborn_descendant',child=child.pid)
    signal.signal(signal.SIGTERM,signal.SIG_IGN);time.sleep(60)
if mode=='authorization': print('Forbidden: not authorized',flush=True);sys.exit(1)
if mode=='offline': print('Unable to connect to server: Connection refused',flush=True);sys.exit(1)
if mode=='flood': sys.stdout.write('x'*2097152);sys.stdout.flush();time.sleep(60)
if tool=='lpstat':
    if args==['-e']:
        if mode!='no_printers': print('QueueA\nQueueB')
    elif args==['-d']: print('system default destination: QueueA')
    elif args[:1]==['-p']: print(f'printer {args[1]} is idle. enabled since private fixture creation')
    elif args[:1]==['-W']:
        if args[1]=='not-completed' and (root/'accepted').exists(): print('QueueA-104 private 1024 fixture')
    else: raise ValueError('Unexpected lpstat arguments')
elif tool=='lpoptions':
    if args!=['-p',args[1],'-l']: raise ValueError('Only read-only option discovery is permitted')
    if mode=='late_a' and args[1]=='QueueA': time.sleep(4)
    print('PageSize/Media: *A4 Letter' if args[1]=='QueueA' else 'PageSize/Media: *Letter')
    if args[1]=='QueueA':
        print('Duplex/Two-sided: *None DuplexNoTumble DuplexTumble\nColorModel/Color: *Gray RGB\nResolution/Resolution: *300dpi 600dpi\nInputSlot/Tray: *Auto Tray1')
elif tool=='lp':
    (root/'accepted').write_text(json.dumps(args));print('request id is QueueA-104 (1 file(s))')
elif tool=='cancel':
    (root/'cancelled').write_text(json.dumps(args))
else: raise ValueError('Unknown private CUPS executable')
