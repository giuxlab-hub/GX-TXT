#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build a normal Plugin Install API ZIP; never runs at installation time."""
from __future__ import annotations
import argparse
import hashlib
import json
import re
import zipfile
from pathlib import Path


def build(root: Path, output: Path) -> None:
    catalog = json.loads((root / 'portable/formats.json').read_text(encoding='utf-8'))
    descriptor = (root / 'module.ini').read_text(encoding='utf-8')
    blocks = []
    for item in catalog['formats']:
        blocks.append(f"[acquisition_format.geometry3d.{item['id']}]\n"
                      f"description={item['label']}\nmime={item['media_type']}\n"
                      f"extensions={';'.join('*'+e for e in item['extensions'])}\n"
                      f"canonical_formats={item['id']}\n")
    start = descriptor.index('[acquisition_format.geometry3d.')
    stop = descriptor.index('[documentation]', start)
    (root / 'module.ini').write_text(descriptor[:start] + '\n'.join(blocks) + '\n' + descriptor[stop:], encoding='utf-8')
    files = sorted(p for p in root.rglob('*') if p.is_file() and '__pycache__' not in p.parts
                   and p.suffix not in {'.pyc', '.zip'} and p.name != 'SHA256SUMS.txt')
    checksums = ''.join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(root).as_posix()}\n" for p in files)
    (root / 'SHA256SUMS.txt').write_text(checksums, encoding='utf-8')
    files.append(root / 'SHA256SUMS.txt')
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(files):
            info = zipfile.ZipInfo(path.relative_to(root).as_posix(), (2026, 9, 28, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, path.read_bytes())
    sha = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(output.suffix + '.sha256').write_text(f'{sha}  {output.name}\n', encoding='ascii')
    print(f'{output}\nSHA-256: {sha}\nSize: {output.stat().st_size} bytes')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    build(Path(__file__).resolve().parents[1], args.output.resolve())
