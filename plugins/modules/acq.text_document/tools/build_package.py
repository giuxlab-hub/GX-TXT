#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build a normal GX-TXT Plugin Install API ZIP, without installer scripts."""
from pathlib import Path
import argparse
import hashlib
import zipfile


def build(destination: Path) -> None:
    root = Path(__file__).resolve().parents[1]
    paths = sorted(p for p in root.rglob('*') if p.is_file() and '__pycache__' not in p.parts
                   and p.suffix not in {'.pyc','.zip'} and p.name != 'SHA256SUMS.txt')
    if destination.resolve().is_relative_to(root):
        raise ValueError('Choose a ZIP output path outside the plugin source directory.')
    (root/'SHA256SUMS.txt').write_text(''.join(
        f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(root).as_posix()}\n' for p in paths),encoding='utf-8')
    paths.append(root/'SHA256SUMS.txt')
    destination.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(destination,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
        for path in sorted(paths):
            info=zipfile.ZipInfo(path.relative_to(root).as_posix(),date_time=(2026,9,28,0,0,0))
            info.external_attr=0o100644 << 16
            info.compress_type=zipfile.ZIP_DEFLATED
            archive.writestr(info,path.read_bytes())
    digest=hashlib.sha256(destination.read_bytes()).hexdigest()
    destination.with_name(destination.name+'.sha256').write_text(f'{digest}  {destination.name}\n',encoding='ascii')
    print(destination)
    print(f'{destination.stat().st_size} bytes; SHA-256 {digest}')


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',type=Path)
    build(parser.parse_args().output)
