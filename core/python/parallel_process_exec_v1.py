#!/usr/bin/env python3
# GX-TXT Parallel Execution API v1 safe argv launcher
# SPDX-License-Identifier: GPL-3.0-or-later
"""Execute one CORE Parallel process request without shell interpolation."""

from __future__ import annotations

import base64
import os
import subprocess
import sys
from pathlib import Path


def decode_field(value: str) -> str:
    return base64.b64decode(value.encode("ascii"), validate=True).decode("utf-8")


def load_request(path: Path) -> tuple[list[str], dict[str, str], bool]:
    lines = path.read_text(encoding="ascii").splitlines()
    if not lines or lines[0] != "GXTXT_PARALLEL_EXEC_V1":
        raise ValueError("invalid Parallel Execution process request header")
    argv: list[str] = []
    env: dict[str, str] = {}
    process_group = False
    for line in lines[1:]:
        if not line:
            continue
        parts = line.split("\t")
        tag = parts[0]
        if tag == "ARG" and len(parts) == 2:
            argv.append(decode_field(parts[1]))
        elif tag == "ENV" and len(parts) == 3:
            env[decode_field(parts[1])] = decode_field(parts[2])
        elif tag == "GROUP" and len(parts) == 2:
            process_group = parts[1] == "1"
        else:
            raise ValueError(f"invalid Parallel Execution process request record: {tag}")
    if not argv:
        raise ValueError("Parallel Execution process request contains no argv")
    if any("\x00" in arg for arg in argv):
        raise ValueError("process argv contains NUL")
    return argv, env, process_group


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: parallel_process_exec_v1.py REQUEST", file=sys.stderr)
        return 2
    request = Path(sys.argv[1])
    try:
        argv, additions, process_group = load_request(request)
        env = os.environ.copy()
        env.update(additions)
        if process_group and hasattr(os, "setsid"):
            os.setsid()
        if os.name == "nt":
            # The MSYS2 UCRT Python execvpe path can crash in ucrtbase when
            # many independent Windows workers start together. A child
            # process keeps argv/env exact and inherits our captured streams.
            return subprocess.run(argv, env=env, check=False).returncode
        os.execvpe(argv[0], argv, env)
    except Exception as exc:  # launcher diagnostics belong on stderr
        print(f"GX-TXT Parallel process launcher error: {exc}", file=sys.stderr)
        return 126
    return 126


if __name__ == "__main__":
    raise SystemExit(main())
