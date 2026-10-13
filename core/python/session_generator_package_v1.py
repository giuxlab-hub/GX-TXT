#!/usr/bin/env python3
# GX-TXT Session Generator package helper
# SPDX-License-Identifier: GPL-3.0-or-later
"""Create portable Session Generator ZIP packages without shell interpolation."""

from __future__ import annotations

import os
import sys
import zipfile
from pathlib import Path


def safe_tree(root: Path) -> list[Path]:
    root = root.resolve()
    files: list[Path] = []
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"symbolic links are not allowed in Session Generator packages: {path}")
        resolved = path.resolve()
        if root != resolved and root not in resolved.parents:
            raise ValueError(f"package path escapes source root: {path}")
        if path.is_file():
            files.append(path)
    return files


def pack(source: Path, output: Path) -> None:
    source = source.resolve()
    if not source.is_dir():
        raise ValueError(f"source directory does not exist: {source}")
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    temp = output.with_name(output.name + f".tmp-{os.getpid()}")
    if temp.exists():
        temp.unlink()
    try:
        with zipfile.ZipFile(temp, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for path in safe_tree(source):
                rel = path.relative_to(source).as_posix()
                archive.write(path, rel)
        os.replace(temp, output)
    finally:
        if temp.exists():
            temp.unlink()


def main() -> int:
    if len(sys.argv) != 4 or sys.argv[1] != "pack":
        print("usage: session_generator_package_v1.py pack SOURCE OUTPUT.zip", file=sys.stderr)
        return 2
    try:
        pack(Path(sys.argv[2]), Path(sys.argv[3]))
    except Exception as exc:
        print(f"Session Generator package error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
