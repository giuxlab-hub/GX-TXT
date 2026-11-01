#!/usr/bin/env python3
"""Generate the deterministic GX-TXT Welch PSD teaching dataset."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import argparse
import csv
import math
from pathlib import Path

FS_HZ = 1024.0
DURATION_S = 32.0
SAMPLES = int(FS_HZ * DURATION_S)
F1_HZ = 50.0
A1_V = 0.8
F2_HZ = 123.0
A2_V = 0.35
NOISE_SIGMA_V = 0.20
SEED = 1974
_PM_M = 2147483647
_PM_A = 16807

class DeterministicNormal:
    def __init__(self, seed: int):
        if not (0 < seed < _PM_M):
            raise ValueError("seed out of Park-Miller range")
        self.state = seed
        self.spare = None
    def uniform(self) -> float:
        self.state = (self.state * _PM_A) % _PM_M
        return self.state / _PM_M
    def normal(self) -> float:
        if self.spare is not None:
            z = self.spare
            self.spare = None
            return z
        u1 = max(self.uniform(), 1e-15)
        u2 = self.uniform()
        r = math.sqrt(-2.0 * math.log(u1))
        a = 2.0 * math.pi * u2
        self.spare = r * math.sin(a)
        return r * math.cos(a)

def clean_signal(t: float) -> float:
    return A1_V * math.sin(2.0 * math.pi * F1_HZ * t) + A2_V * math.sin(2.0 * math.pi * F2_HZ * t)

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

    rng = DeterministicNormal(SEED)
    noises = []
    csv_path = raw / "welch_psd_demo.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["time_s", "clean_V", "measured_V"])
        for i in range(SAMPLES):
            t = i / FS_HZ
            clean = clean_signal(t)
            noise = NOISE_SIGMA_V * rng.normal()
            noises.append(noise)
            writer.writerow([f"{t:.12g}", f"{clean:.12g}", f"{(clean + noise):.12g}"])

    noise_mean = sum(noises) / len(noises)
    noise_power = sum(v*v for v in noises) / len(noises)
    ideal_floor = 2.0 * (NOISE_SIGMA_V ** 2) / FS_HZ
    total_expected_power = (A1_V ** 2)/2.0 + (A2_V ** 2)/2.0 + NOISE_SIGMA_V ** 2
    truth = f"""dataset=welch_psd_demo.csv
sampling=uniform
sample_rate_hz={FS_HZ:.12g}
duration_s={DURATION_S:.12g}
samples={SAMPLES}
columns=time_s;clean_V;measured_V
units=s;V;V
model=0.8*sin(2*pi*50*t)+0.35*sin(2*pi*123*t)+deterministic_white_gaussian_noise
frequency_1_hz={F1_HZ:.12g}
amplitude_1_V={A1_V:.12g}
tone_1_power_V2={(A1_V**2/2):.12g}
frequency_2_hz={F2_HZ:.12g}
amplitude_2_V={A2_V:.12g}
tone_2_power_V2={(A2_V**2/2):.12g}
noise_sigma_V={NOISE_SIGMA_V:.12g}
noise_seed={SEED}
noise_generator=Park-Miller 16807 uniform + Box-Muller normal
realized_noise_mean_V={noise_mean:.17g}
realized_noise_mean_square_V2={noise_power:.17g}
ideal_one_sided_white_noise_psd_V2_per_Hz={ideal_floor:.17g}
expected_total_mean_square_V2={total_expected_power:.17g}
recommended_temporal_basis=samples
recommended_window_size_samples=2048
recommended_step_samples=1024
recommended_partial_policy=drop
recommended_overlap_percent=50
recommended_resolved_windows=31
recommended_fft_window=hann
recommended_detrend=mean
recommended_nfft=auto
recommended_frequency_resolution_hz=0.5
"""
    (metadata / "welch_psd_ground_truth.txt").write_text(truth, encoding="utf-8")
    guide = """# Welch PSD student exercise

This Session Generator creates a deterministic noisy two-tone signal for `analysis.welch_spectrum`.

## Expected signal

- Sampling rate: 1024 Hz
- Duration: 32 s
- Tone 1: 50 Hz, 0.8 V peak
- Tone 2: 123 Hz, 0.35 V peak
- Added white Gaussian noise: sigma = 0.20 V, deterministic seed 1974

## GX-TXT workflow

1. Import `raw/welch_psd_demo.csv` through the normal CSV acquisition path.
2. In **Variables**, make sure `time_s` is the independent elapsed-time coordinate with unit `s`. `clean_V` and `measured_V` are measured variables with unit `V`.
3. Open **Variables -> Temporal Sets...** and create a Window Set:
   - Basis: `Samples`
   - Window size: `2048`
   - Step: `1024`
   - Partial window: `Drop`
   - Parent: `All dataset`
   This is 50% overlap and resolves to 31 windows.
4. Enable **Welch PSD & Averaged Spectrum**.
5. Bind Time to `time_s` and Signal to `measured_V`.
6. Select the Window Set created above.
7. Recommended analysis settings:
   - FFT weighting window: `hann`
   - Detrend: `mean`
   - NFFT mode: `auto`
   - Workers: `auto`
8. Run the module. With NFFT=2048, the expected frequency spacing is 0.5 Hz.
9. The spectrum should show strong peaks at 50 Hz and 123 Hz. The PSD away from the tones should approach the known white-noise floor statistically.
10. Create Graph Provider variants to compare `PSD dB`, `PSD linear`, `ASD`, and `Mean amplitude` without recalculating the analysis.

## Questions for students

- Why does 2048/1024 correspond to 50% overlap?
- Why does the 2048-point FFT at 1024 Hz have 0.5 Hz bin spacing?
- Why is a PSD useful for comparing noise levels across different segment lengths?
- Compare the integrated PSD with the expected total mean-square value in `metadata/welch_psd_ground_truth.txt`.
- Compare the noisy signal result with `clean_V` using the same Temporal Set.
"""
    (root / "STUDENT_GUIDE.md").write_text(guide, encoding="utf-8")
    print(f"Generated {SAMPLES} deterministic Welch PSD samples in {csv_path}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
