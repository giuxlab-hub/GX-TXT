"""CORE local guardian: validate launch and retain ownership until children stop."""
# SPDX-License-Identifier: GPL-3.0-or-later
import contextlib
import json
import os
from pathlib import Path
import signal
import selectors
import json
import subprocess
import sys
import time

from gxtxt_job_supervisor import enable_subreaper, process_identity, process_tree

# FUTURE WINDOWS PORTING REQUIREMENT (implementation intentionally deferred):
# This guardian belongs to the LOCAL supervisor's native Job Object, not Tk.
# GUI close leaves jobs running. The independent Windows supervisor/tray must
# reopen/focus GUI, inspect jobs, cancel selected/all (confirm all), and exit
# safely. Reuse common CORE jobs/resources/recovery; no mandatory Windows service
# or remote dispatch. Native Job Objects replace this Linux subreaper boundary.
stopping = False


def request_stop(signum, frame):
    global stopping
    stopping = True


def children():
    return {pid: info for pid, info in process_tree(os.getpid()).items()
            if pid != os.getpid() and info[6] != "Z"}


def signal_children(sig):
    for pid, info in children().items():
        if process_identity(pid) == info[2]:
            with contextlib.suppress(ProcessLookupError):
                os.kill(pid, sig)


def reap(exclude=()):
    # waitid observes without stealing Popen's exit status. Avoid a full /proc
    # walk every polling tick merely to reap adopted grandchildren.
    while True:
        try:info = os.waitid(os.P_ALL, 0, os.WEXITED | os.WNOHANG | os.WNOWAIT)
        except ChildProcessError:return
        if info is None or info.si_pid in exclude:return
        with contextlib.suppress(ChildProcessError):os.waitpid(info.si_pid, os.WNOHANG)


def drain():
    signal_children(signal.SIGTERM)
    started = time.monotonic()
    while children():
        if time.monotonic() - started > 1:
            signal_children(signal.SIGKILL)
        reap()
        # Stay alive with the resource lease if a child is in uninterruptible
        # kernel I/O. The supervisor must not recover/purge beneath that child.
        time.sleep(.05)
    reap()


def run_child(command, role='program'):
    """Drain genuine stdout/stderr separately, retaining legacy combined reads."""
    directory=Path(os.environ['GXTXT_CAPTURE_DIR'])
    child=subprocess.Popen(command,close_fds=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    selector=selectors.DefaultSelector()
    for stream,name in ((child.stdout,'stdout'),(child.stderr,'stderr')):
        os.set_blocking(stream.fileno(),False);selector.register(stream,selectors.EVENT_READ,name)
    stopped_at=None
    with (directory/'program.stdout').open('ab',buffering=0) as output, (directory/'program.stderr').open('ab',buffering=0) as errors, (directory/'diagnostic.log').open('ab',buffering=0) as diagnostics:
        while selector.get_map() or child.poll() is None:
            for key,_ in selector.select(.04):
                raw=os.read(key.fileobj.fileno(),65536)
                if not raw:selector.unregister(key.fileobj);key.fileobj.close();continue
                (diagnostics if role=='preflight' else output if key.data=='stdout' else errors).write(raw)
                sys.stdout.buffer.write(raw);sys.stdout.buffer.flush()
            if stopping:
                if stopped_at is None:signal_children(signal.SIGTERM);stopped_at=time.monotonic()
                elif time.monotonic()-stopped_at>1:signal_children(signal.SIGKILL)
            reap(exclude=(child.pid,))
    selector.close()
    return child.wait()


def main():
    runtime = sys.argv[1]
    permit = Path(os.environ["GXTXT_JOB_ROOT"]) / (os.environ["GXTXT_JOB_ID"] + ".permit")
    identity = process_identity(os.getpid())
    for attempt in range(200):
        if stopping:
            return 143
        if permit.is_file():
            data = json.loads(permit.read_text())
            if data["pid"] != os.getpid() or data["start"] != identity:
                raise RuntimeError("Invalid supervisor launch permit identity")
            scratch = Path(data["temp_dir"])
            st = scratch.lstat()
            if scratch.is_symlink() or not scratch.is_dir() or [st.st_dev, st.st_ino] != data["temp_identity"]:
                raise RuntimeError("Job temporary allocation identity changed")
            os.environ.update(data.get("environment", {}))
            os.environ["TMPDIR"] = str(scratch)
            os.environ["GXTXT_RESOURCE_LEASE"] = data["resource_id"]
            break
        if process_identity(os.environ["GXTXT_SUPERVISOR_PID"]) != os.environ["GXTXT_SUPERVISOR_START"]:
            return 2
        time.sleep(.05)
    else:
        raise RuntimeError("Supervisor launch permit timed out")
    try:
        rc = run_child([sys.executable, "-B", str(Path(__file__).with_name("script_api_preflight.py")), runtime], role="preflight")
        if rc or stopping:
            return rc or 143
        return run_child(sys.argv[2:])
    finally:
        drain()


if __name__ == "__main__":
    enable_subreaper()
    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    sys.exit(main())
