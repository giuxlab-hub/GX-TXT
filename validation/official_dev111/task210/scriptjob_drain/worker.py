#!/usr/bin/env python3
"""Non-scientific pipe fixture; only the actual ScriptJob owner launches it."""
import os
import select
import signal
import sys
import time

if len(sys.argv) != 2 or sys.argv[1] not in {
    "default", "resistant", "burst", "burst_short", "overlong_line",
    "overlong_tail", "nonduplex",
}:
    raise SystemExit("Expected one closed fixture mode")
mode = sys.argv[1]
signal.signal(signal.SIGTERM, signal.SIG_IGN if mode == "resistant" else signal.SIG_DFL)
deadline = time.monotonic() + 8.0


def command():
    """One bounded control line; no descendants or alternate process owner."""
    value = bytearray()
    while time.monotonic() < deadline:
        ready, _, _ = select.select([sys.stdin.buffer], [], [], min(0.05, max(0, deadline - time.monotonic())))
        if ready:
            byte = os.read(sys.stdin.fileno(), 1)
            if not byte:
                return bytes(value)
            value.extend(byte)
            if byte == b"\n":
                return bytes(value)
            if len(value) > 16:
                raise SystemExit("Fixture control line exceeded bound")
    raise SystemExit("Fixture control deadline expired")


def emit(value):
    """Nonblocking finite stdout writes respect the SAME eight-second bound."""
    data = value.encode("utf-8")
    offset = 0
    while offset < len(data) and time.monotonic() < deadline:
        _, ready, _ = select.select([], [sys.stdout.fileno()], [], min(0.05, max(0, deadline - time.monotonic())))
        if ready:
            try:
                offset += os.write(sys.stdout.fileno(), data[offset:offset + 4096])
            except BlockingIOError:
                pass
    if offset != len(data):
        raise SystemExit("Fixture output deadline expired")


if mode not in {"default", "resistant"}:
    os.set_blocking(sys.stdout.fileno(), False)
    if mode == "nonduplex":
        if command() != b"go\n":
            raise SystemExit("Expected bounded nonduplex payload")
        emit("ok 1 value nonduplex\n")
        raise SystemExit(0)
    emit(f"ready {os.getpid()} {mode}\n")
    if command() != b"go\n":
        raise SystemExit("Expected go after actual readiness")
    if mode == "burst":
        frames = []
        for index in range(48):
            if index in {1, 17, 31}:
                frames.append("")
            elif index == 9:
                frames.append("water:" + "水" * 1024)
            elif index == 25:
                frames.append("wave:" + "🌊" * 512)
            else:
                frames.append(f"frame-{index}:" + "é" * 1536)
        emit("\n".join(frames) + "\n")
    elif mode == "burst_short":
        emit("".join(f"short-{index}\n" for index in range(24)))
    elif mode == "overlong_line":
        emit("x" * 4097 + "\n")
    else:
        emit("x" * 4097)
    # Natural EOF is requested only by the paused-EOF case; every other case
    # leaves termination/cancellation to the actual existing ScriptJob owner.
    if command() != b"finish\n":
        raise SystemExit("Expected finish or actual owner cancellation")
    raise SystemExit(0)

print(f"ready {os.getpid()} {mode}", flush=True)
# No stdin read, network, scientific data or descendant creation. The natural
# bound is a last-resort fixture limit, never fabricated cancellation evidence.
while time.monotonic() < deadline:
    time.sleep(0.02)
print("fixture_bound_expired", flush=True)
raise SystemExit(3)
