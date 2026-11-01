#!/usr/bin/env python3
"""Generate the deterministic GX-TXT Cepstrum Analysis teaching dataset."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import argparse
import csv
import math
from pathlib import Path

FS_HZ = 4096.0
SAMPLES = 4096
F0_HZ = 128.0
DC_V = 0.15
HARMONIC_COUNT = 12

def amplitude(order: int) -> float:
    return 1.0 / order

def phase(order: int) -> float:
    return 0.17 * order

def sample(t: float) -> float:
    return DC_V + sum(
        amplitude(k) * math.sin(2.0 * math.pi * (k * F0_HZ) * t + phase(k))
        for k in range(1, HARMONIC_COUNT + 1)
    )

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

    csv_path = raw / "cepstrum_analysis_demo.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["time_s", "harmonic_series_V"])
        for i in range(SAMPLES):
            t = i / FS_HZ
            writer.writerow([f"{t:.12g}", f"{sample(t):.12g}"])

    period_s = 1.0 / F0_HZ
    lines = [
        "dataset=cepstrum_analysis_demo.csv",
        "sampling=uniform",
        f"sample_rate_hz={FS_HZ:.12g}",
        f"samples={SAMPLES}",
        f"duration_s={SAMPLES / FS_HZ:.12g}",
        f"fundamental_frequency_hz={F0_HZ:.12g}",
        f"fundamental_period_s={period_s:.17g}",
        f"fundamental_period_samples={FS_HZ / F0_HZ:.12g}",
        f"dc_offset_V={DC_V:.12g}",
        f"harmonic_count={HARMONIC_COUNT}",
        "harmonic_amplitude_rule=1/order",
        "recommended_window=rectangular",
        "recommended_detrend=mean",
        "recommended_log_floor_db=-240",
        "recommended_min_frequency_hz=80",
        "recommended_max_frequency_hz=200",
    ]
    (metadata / "cepstrum_ground_truth.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")

    guide = """# Cepstrum Analysis student exercise

This Session Generator creates a deterministic 1-second harmonic series for `analysis.cepstrum`.

## Known waveform

- Sampling rate: 4096 Hz
- Samples: 4096
- Duration: 1 s
- Fundamental: 128 Hz
- Fundamental period: 7.8125 ms
- Fundamental period in samples: exactly 32
- Harmonics: H1 through H12
- Harmonic peak amplitude rule: `1 / harmonic_order`
- DC offset: 0.15 V

The phases vary with harmonic order. The regular 128 Hz harmonic spacing is the feature the cepstrum should reveal.

## GX-TXT workflow

1. Import `raw/cepstrum_analysis_demo.csv` through the normal CSV acquisition workflow.
2. In **Variables**, set `time_s` as the independent elapsed-time variable with unit `s`, and `harmonic_series_V` as a measured variable with unit `V`.
3. Enable **Cepstrum Analysis**.
4. Bind:
   - Independent time coordinate -> `time_s`
   - Signal variable / channel -> `harmonic_series_V`
5. Use the reference settings:
   - Analysis window: `rectangular`
   - Detrend: `mean`
   - Log-magnitude floor: `-240 dB`
   - Minimum fundamental search frequency: `80 Hz`
   - Maximum fundamental search frequency: `200 Hz`
6. Run the module.
7. Compare the reported dominant quefrency with `0.0078125 s`.
8. Compare the equivalent frequency with `128 Hz`.
9. Inspect the published `quefrency_s` / `real_cepstrum` Dataset and the graph.
10. Create a graph variant with a narrower X range around the first few milliseconds and rerender it without rerunning the cepstral calculation.

## Questions for students

- Why does a 128 Hz harmonic spacing correspond to 7.8125 ms of quefrency?
- Why is the horizontal axis called quefrency rather than frequency?
- What does taking the logarithm of spectral magnitude accomplish conceptually?
- Why can cepstral peaks also appear at multiples of the fundamental period?
- Why does the configured frequency search interval matter when selecting the reported peak?
- What happens to the zero-quefrency term when the signal is multiplied by a constant amplitude factor?
"""
    (root / "STUDENT_GUIDE.md").write_text(guide, encoding="utf-8")
    print(f"Generated {SAMPLES} deterministic cepstrum-analysis samples in {csv_path}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
