# SPDX-License-Identifier: GPL-3.0-or-later
"""Only directly launched private request/process-group cancellation fixtures."""
import json, os, signal, subprocess, sys, time
from pathlib import Path
os.setsid()
mode, receipt = sys.argv[1:]
sys.stdin.read()
if mode == 'ok':
    print('ok 1 result {ready 1}', flush=True)
elif mode == 'flood':
    while True:
        print('x' * 65536, flush=True)
else:
    child = subprocess.Popen([sys.executable, '-c', 'import signal,time;signal.signal(signal.SIGTERM,signal.SIG_IGN);time.sleep(60)'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    Path(receipt).write_text(json.dumps(dict(parent=os.getpid(), child=child.pid, group=os.getpgrp())))
    if mode == 'stubborn': signal.signal(signal.SIGTERM, signal.SIG_IGN)
    time.sleep(60)
