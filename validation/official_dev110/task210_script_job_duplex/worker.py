#!/usr/bin/env python3
"""Inert real-pipe fixture; launched only by the actual ScriptJob owner."""
import signal
import sys
import time

mode = sys.argv[1]
if mode == "one-shot":
    print("ok 1 result legacy", flush=True)
elif mode in {"idle", "sink"}:
    if mode == "sink":
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
    print("ready", flush=True)
    time.sleep(30)
elif mode in {"echo", "ready"}:
    if mode == "ready":
        print("ready", flush=True)
    for raw in sys.stdin.buffer:
        frame = raw[:-1] if raw.endswith(b"\n") else raw
        if frame == b"!burst3":
            sys.stdout.buffer.write(b"first\n\nthird\n")
        elif frame == b"!burst17":
            sys.stdout.buffer.write(b"x\n" * 17)
        elif frame == b"!long":
            sys.stdout.buffer.write(b"123456789\n")
        elif frame == b"!partial":
            sys.stdout.buffer.write(b"123456789")
        elif frame == b"!exit":
            sys.stdout.buffer.write(b"last\n")
            sys.stdout.buffer.flush()
            break
        else:
            sys.stdout.buffer.write(frame + b"\n")
        sys.stdout.buffer.flush()
else:
    raise SystemExit("Unknown fixture mode")
