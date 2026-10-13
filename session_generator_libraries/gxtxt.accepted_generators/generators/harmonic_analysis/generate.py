#!/usr/bin/env python3
"""Generate the deterministic GX-TXT Harmonic Analysis teaching dataset."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import argparse
import csv
import math
from pathlib import Path

FS_HZ = 4096.0
SAMPLES = 4096
DURATION_S = SAMPLES / FS_HZ
DC_V = 0.20
F0_HZ = 100.0
HARMONICS = {
    1: 1.000,
    2: 0.100,
    3: 0.050,
    4: 0.020,
    5: 0.010,
}
PHASE_RAD = {
    1: 0.0,
    2: 0.30,
    3: -0.45,
    4: 0.70,
    5: -0.20,
}

def component(t: float, order: int) -> float:
    return HARMONICS[order] * math.sin(2.0 * math.pi * (order * F0_HZ) * t + PHASE_RAD[order])

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-session", required=True)
    parser.add_argument("--library-id")
    parser.add_argument("--generator-id")
    args = parser.parse_args()
    root = Path(args.target_session)
    raw = root / "raw"
    metadata = root / "metadata"
    raw.mkdir(parents=True, exist_ok=True)
    metadata.mkdir(parents=True, exist_ok=True)

    csv_path = raw / "harmonic_analysis_demo.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["time_s", "fundamental_only_V", "distorted_V"])
        for i in range(SAMPLES):
            t = i / FS_HZ
            fundamental = DC_V + component(t, 1)
            distorted = DC_V + sum(component(t, order) for order in sorted(HARMONICS))
            writer.writerow([f"{t:.12g}", f"{fundamental:.12g}", f"{distorted:.12g}"])

    thd_ratio = math.sqrt(sum(HARMONICS[k] ** 2 for k in HARMONICS if k >= 2)) / HARMONICS[1]
    lines = [
        "dataset=harmonic_analysis_demo.csv",
        "sampling=uniform",
        f"sample_rate_hz={FS_HZ:.12g}",
        f"duration_s={DURATION_S:.12g}",
        f"samples={SAMPLES}",
        "frequency_resolution_hz=1",
        "columns=time_s;fundamental_only_V;distorted_V",
        "units=s;V;V",
        f"dc_offset_V={DC_V:.12g}",
        f"fundamental_frequency_hz={F0_HZ:.12g}",
    ]
    for order in sorted(HARMONICS):
        amp = HARMONICS[order]
        dbc = 20.0 * math.log10(amp / HARMONICS[1])
        pct = 100.0 * amp / HARMONICS[1]
        lines.extend([
            f"harmonic_{order}_frequency_hz={order * F0_HZ:.12g}",
            f"harmonic_{order}_amplitude_V={amp:.12g}",
            f"harmonic_{order}_dbc={dbc:.12g}",
            f"harmonic_{order}_percent={pct:.12g}",
        ])
    lines.extend([
        f"thd_ratio={thd_ratio:.17g}",
        f"thd_percent={100.0 * thd_ratio:.17g}",
        f"thd_db={20.0 * math.log10(thd_ratio):.17g}",
        "recommended_fft_analysis_mode=full_record",
        "recommended_fft_window=rectangular",
        "recommended_fft_detrend=mean",
        "recommended_fundamental_mode=auto_peak",
        "recommended_max_harmonic=5",
        "recommended_search_half_width_bins=0",
    ])
    (metadata / "harmonic_analysis_ground_truth.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")

    guide = """# Harmonic Analysis student exercise

This Session Generator creates a deterministic coherent waveform for `analysis.fft_spectrum` followed by `analysis.harmonic_analysis`.

## Known waveform

- Sampling rate: 4096 Hz
- Samples: 4096 (exactly 1 second)
- FFT-bin spacing for the full record: 1 Hz
- DC offset: 0.20 V
- H1: 100 Hz, 1.000 V peak
- H2: 200 Hz, 0.100 V peak (-20.000 dBc)
- H3: 300 Hz, 0.050 V peak (about -26.021 dBc)
- H4: 400 Hz, 0.020 V peak (about -33.979 dBc)
- H5: 500 Hz, 0.010 V peak (-40.000 dBc)
- Analytical THD: about 11.401754 % or -18.860566 dB

The harmonic phases are intentionally different; THD depends on harmonic amplitudes, not on their phase relative to H1.

## GX-TXT workflow

1. Import `raw/harmonic_analysis_demo.csv` through the normal CSV acquisition path.
2. In **Variables**, set `time_s` as the independent elapsed-time coordinate with unit `s`. Set `fundamental_only_V` and `distorted_V` as measured variables with unit `V`.
3. Enable **FFT Spectrum & Error Analysis** and bind:
   - Independent -> `time_s`
   - Signal -> `distorted_V`
4. Use these settings for the exact reference exercise:
   - Analysis mode: `full_record`
   - FFT window: `rectangular`
   - Detrend: `mean`
   - Fundamental frequency: `auto_peak`
5. Run the FFT module. The resulting `spectrum.table` should contain coherent spectral lines at 100, 200, 300, 400 and 500 Hz.
6. Enable **Harmonic Analysis** and select that FFT `spectrum.table` as its Analysis Source.
7. Bind:
   - Frequency -> `frequency`
   - Amplitude spectrum -> `amplitude`
8. Recommended Harmonic Analysis settings:
   - Fundamental detection: `auto_peak`
   - Highest harmonic order: `5`
   - Local harmonic search half-width: `0` bins
9. Run the module and compare the published harmonic Dataset and report against `metadata/harmonic_analysis_ground_truth.txt`.
10. Create graph variants for dBc, percent of fundamental, and linear amplitude. These variants use the scientific render cache and do not rerun the harmonic calculation.
11. Repeat the workflow with `fundamental_only_V`. The harmonic amplitudes should collapse to numerical roundoff and THD should approach zero.

## Questions for students

- Why does one second at 4096 samples/s produce exactly 1 Hz FFT-bin spacing?
- Why are all five spectral components coherent with this record?
- Why does mean detrending remove the 0.20 V DC offset without changing the harmonic frequencies?
- Derive THD from H2 through H5 and compare it with the reported value.
- Why is dBc a relative amplitude measure while THD combines harmonic amplitudes by root-sum-square?
- What changes when the record is no longer coherent or when a non-rectangular FFT window is used?
"""
    (root / "STUDENT_GUIDE.md").write_text(guide, encoding="utf-8")
    print(f"Generated {SAMPLES} deterministic harmonic-analysis samples in {csv_path}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
