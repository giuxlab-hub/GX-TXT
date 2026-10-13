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
    sample_names = ['3.1', '4.1', '5.1', '6.1', '7.1', '8', '9', '10', '11', '12']
    datasets = [dict(source=f'raw/manchester_uvvis_2022/{name}.Sample.Raw.csv',
                     id=f'uvvis.sample.{name.replace(".", "_")}', kind='spectrum.scientific',
                     units={'nm': 'nm', 'A': '1'},
                     roles={'nm': 'independent', 'A': 'measured'},
                     variable_ids={'nm': 'spectral_x', 'A': 'spectral_y'},
                     provenance={'spectrum_kind': 'UV_VIS', 'y_representation': 'absorbance'})
                for name in sample_names]
    datasets.append(dict(
        source='raw/manchester_uvvis_2022/100% or 0 Absorbance Baseline.Correction.Raw.csv',
        id='uvvis.blank', kind='spectrum.scientific', units={'nm': 'nm', 'A': '1'},
        roles={'nm': 'independent', 'A': 'measured'},
        variable_ids={'nm': 'spectral_x', 'A': 'spectral_y'},
        provenance={'spectrum_kind': 'UV_VIS', 'y_representation': 'absorbance'}))
    configure(root, 'manchester_uvvis_faculty', datasets, [
        dict(id='analysis.spectroscopy.uvvis_exploration',
             sources={'primary': 'uvvis.sample.7_1', 'blank': 'uvvis.blank'},
             config={'workflow': 'single_spectrum', 'selected_wavelength_nm': '322',
                     'blank_correction': 'none', 'baseline_method': 'none',
                     'smoothing_method': 'none', 'normalization': 'none'}),
    ], 'Measured Manchester UV/Vis spectrum exploration')
    print(f'PASS faculty source generator: {len(manifest)} validated assets')

if __name__ == '__main__':
    main()
