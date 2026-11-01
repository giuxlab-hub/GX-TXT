#!/usr/bin/env python3
"""Generate a teaching Session from the two user-supplied, hash-pinned PDFs."""
from __future__ import annotations

import argparse
import hashlib
import shutil
from pathlib import Path
from session_recipe import configure

FILES = {
    'middlebrook_loop_gain.pdf': '713f9111f6df7aa015c78159edf36143f441d55c83e37d0da3cc7f228c3f4f0d',
    'climate_tables.pdf': '64c11d080187f979152ab8d6fe64f32551120513c40688b882895d06723d92c4',
}


def hash_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--target-session', required=True)
    ap.add_argument('--library-id')
    ap.add_argument('--generator-id')
    args = ap.parse_args()
    root = Path(args.target_session)
    raw = root / 'raw'
    metadata = root / 'metadata'
    raw.mkdir(parents=True, exist_ok=True)
    metadata.mkdir(parents=True, exist_ok=True)
    lines = []
    for name, expected in FILES.items():
        source = Path(__file__).resolve().parent / 'assets' / name
        if hash_file(source) != expected:
            raise ValueError(f'bundled PDF hash mismatch: {name}')
        target = raw / name
        if target.exists():
            raise FileExistsError(target)
        shutil.copyfile(source, target)
        if hash_file(target) != expected:
            target.unlink(missing_ok=True)
            raise ValueError(f'generated PDF copy hash mismatch: {name}')
        lines.append(f'{expected}  raw/{name}')
    (metadata / 'source_hashes.sha256').write_text('\n'.join(lines) + '\n', encoding='ascii')
    guide = (Path(__file__).resolve().parent / 'TEACHER_GUIDE.md').read_text(encoding='utf-8')
    (root / 'TEACHER_GUIDE.md').write_text(guide, encoding='utf-8')
    configure(root, 'document_extraction_teacher', [
        dict(source='raw/middlebrook_loop_gain.pdf', id='document.middlebrook',
             binary=True, kind='document.pdf', format='pdf', media_type='application/pdf'),
        dict(source='raw/climate_tables.pdf', id='document.climate',
             binary=True, kind='document.pdf', format='pdf', media_type='application/pdf'),
    ], [], 'Measured source document extraction and OCR')
    print('PASS teacher document generator: both real PDFs copied and verified')


if __name__ == '__main__':
    main()
