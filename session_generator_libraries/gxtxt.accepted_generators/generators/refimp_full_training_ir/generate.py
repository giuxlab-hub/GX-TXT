#!/usr/bin/env python3
"""Copy validated, original measurement assets into a new GX-TXT Session."""
import argparse
import hashlib
import shutil
from pathlib import Path
from session_recipe import configure

def sha256(path):
    h = hashlib.sha256()
    with path.open('rb') as src:
        for block in iter(lambda: src.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--target-session', required=True)
    parser.add_argument('--library-id')
    parser.add_argument('--generator-id')
    args = parser.parse_args()
    root = Path(args.target_session)
    package = Path(__file__).resolve().parent
    manifest = []
    for line in (package / 'SHA256SUMS.txt').read_text(encoding='ascii').splitlines():
        expected, rel = line.split('  ', 1)
        if not rel.startswith('assets/'):
            continue
        source = package / rel
        if sha256(source) != expected:
            raise ValueError('package asset hash mismatch: ' + rel)
        manifest.append((expected, rel, source))
    for expected, rel, source in manifest:
        dest = root / 'raw' / rel.removeprefix('assets/')
        if dest.exists():
            raise FileExistsError(dest)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, dest)
        if sha256(dest) != expected:
            raise ValueError('generated asset hash mismatch: ' + rel)
    for name in ('FACULTY_GUIDE.md', 'RIGHTS.md'):
        dest = root / name
        if dest.exists():
            raise FileExistsError(dest)
        shutil.copyfile(package / name, dest)
    configure(root, 'refimp_full_training_ir', [dict(
        source='raw/refimp_pp_item13.csv', id='ir.refimp.item13',
        kind='spectrum.scientific',
        units={'wavenumber': 'cm^-1', 'relative_transmission_signal': '1'},
        roles={'wavenumber': 'independent', 'relative_transmission_signal': 'measured'},
    )], [dict(id='analysis.spectroscopy.ir', sources={'primary': 'ir.refimp.item13'},
             bindings={'spectral_x': 'wavenumber', 'spectral_y': 'relative_transmission_signal'},
             config={'intensity_representation': 'relative_transmission_signal',
                     'reference_library_ids': 'tum.refimp.ftir.2022',
                     'baseline_method': 'none', 'smoothing_method': 'none',
                     'derivative_order': '0', 'resample_step_cm1': '4',
                     'matching_method': 'cosine', 'fingerprint_min_cm1': '1300',
                     'fingerprint_max_cm1': '1800', 'fingerprint_weight': '0.35'})],
              'Measured RefIMP polypropylene FTIR identification')
    print(f'PASS faculty source generator: {len(manifest)} validated assets')

if __name__ == '__main__':
    main()
