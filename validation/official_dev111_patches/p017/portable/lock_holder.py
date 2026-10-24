# SPDX-License-Identifier: GPL-3.0-or-later
"""Controlled lock-only foreign writer fixture; data publication has not started."""
import fcntl
import sys
with open(sys.argv[1], 'x+b') as lock:
    fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
    print('LOCKED', flush=True)
    sys.stdin.readline()
