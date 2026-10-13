#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""GX-TXT process/provenance adapter for the portable 3D inspector.

The portable/ directory is the CORE extraction candidate. This module is the
application adapter: command-line parsing, cancellable exact-byte preservation
and the data-only Tcl wire protocol. It never edits GX-TXT registry files.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "portable"))
from geometry_probe import Cancelled, GeometryError, Monitor, inspect_file  # noqa: E402

BLOCK = 4 * 1024 * 1024


def text(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def b64(value: Any) -> str:
    return base64.b64encode(text(value).encode("utf-8")).decode("ascii")


def emit(kind: str, *values: Any) -> None:
    print("\t".join([kind, *(b64(v) for v in values)]), flush=True)


def progress(current: int, total: int, stage: str) -> None:
    print(f"P\t{current}\t{total}\t{b64(stage)}", flush=True)


def preserve(raw: Path, destination: Path, cancel) -> str:
    """Copy a RAW snapshot exactly; no overwrite and no partial-file success."""
    before = raw.stat()
    monitor = Monitor(before.st_size, progress, cancel)
    digest = hashlib.sha256()
    owned = False
    try:
        with raw.open("rb") as source, destination.open("xb") as target:
            owned = True
            copied = 0
            while block := source.read(BLOCK):
                monitor.tick(copied, "copy")
                target.write(block)
                digest.update(block)
                copied += len(block)
            target.flush()
            os.fsync(target.fileno())
        after = raw.stat()
        if (before.st_size, before.st_mtime_ns, before.st_ino) != (after.st_size, after.st_mtime_ns, after.st_ino) or copied != before.st_size:
            raise GeometryError("RAW geometry changed during preservation.")
        # A separate read verifies the bytes written to the destination. CORE
        # independently computes and owns registry source/canonical SHA-256.
        check = hashlib.sha256()
        verified = 0
        with destination.open("rb") as target:
            while block := target.read(BLOCK):
                monitor.tick(verified, "verify")
                check.update(block)
                verified += len(block)
        if check.digest() != digest.digest():
            raise GeometryError("Preserved geometry failed byte-for-byte integrity verification.")
        monitor.tick(before.st_size, "verify", force=True)
        return digest.hexdigest()
    except BaseException:
        if owned:
            destination.unlink(missing_ok=True)
        raise


def main() -> int:
    print("GX3DIMPORT1", flush=True)
    parser = argparse.ArgumentParser(description="Inspect and preserve supported 3D sources.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--inspect", type=Path)
    mode.add_argument("--import-raw", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--dataset-id")
    parser.add_argument("--original-name")
    parser.add_argument("--cancel-file", type=Path)
    args = parser.parse_args()
    cancelled = lambda: args.cancel_file is not None and args.cancel_file.exists()
    destination = None
    owned = False
    try:
        source = args.inspect if args.inspect is not None else args.import_raw
        if cancelled():
            raise Cancelled("3D import cancelled.")
        result = inspect_file(source, deep=args.import_raw is not None,
                              progress=progress, cancel=cancelled)
        md, fmt = result["metadata"], result["format"]
        fields = {"format": result["format_id"], "contract": fmt["contract"],
                  "media_type": fmt["media_type"], "label": fmt["label"]}
        md["source.original_filename"] = args.original_name or source.name
        md["source.size_bytes"] = source.stat().st_size
        if args.import_raw is not None:
            if not args.dataset_id or not re.fullmatch(r"[A-Za-z0-9_.-]+", args.dataset_id):
                raise GeometryError("A framework-safe Dataset ID is required.")
            if args.output_dir is None or not args.output_dir.is_dir():
                raise GeometryError("The framework output directory does not exist.")
            relative = args.dataset_id + fmt["canonical_extension"]
            destination = args.output_dir / relative
            preserve(source, destination, cancelled)
            owned = True
            fields["path"] = relative
            md["geometry.source_bytes_preserved"] = True
            md["geometry.import_warnings_json"] = json.dumps(result["warnings"], ensure_ascii=True)
        for vtk_format in ("vtu", "vtp", "vti"):
            if f"{vtk_format}.arrays_json" in md:
                arrays = json.loads(md[f"{vtk_format}.arrays_json"])
                md[f"{vtk_format}.array_summary"] = "; ".join(
                    f"{a['association']}/{a['name'] or '(unnamed)'}: {a['components']} component(s)"
                    for a in arrays[:40])
        for key, value in fields.items():
            emit("F", key, value)
        for key, value in md.items():
            emit("M", key, value)
        for warning in result["warnings"]:
            emit("W", warning)
        if cancelled():
            raise Cancelled("3D import cancelled.")
        print("OK", flush=True)
        return 0
    except Exception as exc:
        if owned and destination is not None:
            destination.unlink(missing_ok=True)
        emit("E", f"{type(exc).__name__}: {exc}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
