#!/usr/bin/env python3
"""Generate a deterministic linear PSD for fractional-octave teaching."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import argparse, csv
from pathlib import Path
FMAX=4096
DF=1.0
NOISE_PSD=1.0e-6
TONES={125:0.25,500:0.09,2000:0.04}
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--target-session',required=True);ap.add_argument('--library-id');ap.add_argument('--generator-id');a=ap.parse_args()
    root=Path(a.target_session);raw=root/'raw';meta=root/'metadata';raw.mkdir(parents=True,exist_ok=True);meta.mkdir(parents=True,exist_ok=True)
    path=raw/'fractional_octave_psd.csv'
    with path.open('w',newline='',encoding='utf-8') as h:
        w=csv.writer(h);w.writerow(['frequency_Hz','psd_V2_per_Hz'])
        for f in range(FMAX+1):
            p=NOISE_PSD+TONES.get(f,0.0)/DF
            w.writerow([f'{float(f):.12g}',f'{p:.17g}'])
    total_noise=NOISE_PSD*(FMAX+0.5)
    truth=(
        'dataset=fractional_octave_psd.csv\n'
        f'frequency_spacing_hz={DF}\nfrequency_min_hz=0\nfrequency_max_hz={FMAX}\n'
        'source_cell_support_hz=0..4096.5\n'
        f'background_psd_V2_per_Hz={NOISE_PSD:.17g}\n'
        'line_125_Hz_power_V2=0.25\nline_500_Hz_power_V2=0.09\nline_2000_Hz_power_V2=0.04\n'
        'expected_total_line_power_V2=0.38\n'
        f'expected_background_power_over_source_support_V2={total_noise:.17g}\n'
        'model=constant_linear_PSD_plus_single_bin_line_powers\n'
        'recommended_bands_per_octave=3\nrecommended_range_mode=auto\nrecommended_reference_rms_V=1\n'
    )
    (meta/'fractional_octave_ground_truth.txt').write_text(truth,encoding='utf-8')
    guide='''# Fractional-Octave PSD student exercise

This generator creates a **linear PSD**, not a time waveform. It tests `analysis.fractional_octave_spectrum` directly.

## Known spectrum

- Frequency grid: 0 ... 4096 Hz, 1 Hz spacing
- White background: 1e-6 V^2/Hz
- Added line power: 0.25 V^2 at 125 Hz
- Added line power: 0.09 V^2 at 500 Hz
- Added line power: 0.04 V^2 at 2000 Hz

## GX-TXT workflow

1. Import `raw/fractional_octave_psd.csv`.
2. Set `frequency_Hz` as independent, unit `Hz`.
3. Set `psd_V2_per_Hz` as measured, unit `V^2/Hz`.
4. Enable **Fractional-Octave Band Analysis**.
5. Bind Frequency and Linear PSD.
6. Select `3` bands per octave, `Auto` range, RMS reference `1`.
7. Run. The strongest excess-power bands contain 125, 500 and 2000 Hz.
8. Create Graph Provider variants for Band level, Band RMS and Band power without recalculation.
9. Repeat with `1` band per octave and compare the coarser grouping.

## Questions

- Why must band integration use linear PSD rather than dB values?
- Why do wider octave bands collect more white-noise power when the PSD floor is flat?
- Why does 1/3-octave analysis separate features better than 1/1-octave analysis?
- Compare a tone-containing band power with the known line power plus the white-noise contribution over that band width.
'''
    (root/'STUDENT_GUIDE.md').write_text(guide,encoding='utf-8')
    print(f'Generated {FMAX+1} PSD bins in {path}')
    return 0
if __name__=='__main__': raise SystemExit(main())
