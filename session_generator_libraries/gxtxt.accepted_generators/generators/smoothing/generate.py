#!/usr/bin/env python3
"""Generate the deterministic Session input for demo.numeric.smoothing."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import argparse
import csv
import math
import random
from pathlib import Path

SEED = 1974
NOISE_SIGMA_V = 0.11
SAMPLES = 501
X_START_S = 0.0
X_STEP_S = 0.02
SPIKES = {122: 0.65, 308: -0.70, 431: 0.55}


def reference_signal(x: float) -> float:
    return (
        0.35 * math.sin(2.0 * math.pi * 0.22 * x)
        + 0.18 * math.cos(2.0 * math.pi * 0.55 * x)
        + 0.04 * x
        + 1.10 * math.exp(-0.5 * ((x - 3.10) / 0.22) ** 2)
        - 0.75 * math.exp(-0.5 * ((x - 7.00) / 0.35) ** 2)
        + 0.45 * math.exp(-0.5 * ((x - 5.25) / 0.60) ** 2)
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-session", required=True)
    parser.add_argument("--library-id")
    parser.add_argument("--generator-id")
    args = parser.parse_args()

    root = Path(args.target_session)
    raw_dir = root / "raw"
    metadata_dir = root / "metadata"
    raw_dir.mkdir(parents=True, exist_ok=True)
    metadata_dir.mkdir(parents=True, exist_ok=True)

    rng = random.Random(SEED)
    csv_path = raw_dir / "smoothing_demo.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["time_s", "reference_V", "measured_V"])
        for i in range(SAMPLES):
            x = X_START_S + i * X_STEP_S
            reference = reference_signal(x)
            measured = reference + rng.gauss(0.0, NOISE_SIGMA_V) + SPIKES.get(i, 0.0)
            writer.writerow([f"{x:.8g}", f"{reference:.12g}", f"{measured:.12g}"])

    ground_truth = """reference_signal=0.35*sin(2*pi*0.22*x)+0.18*cos(2*pi*0.55*x)+0.04*x+1.10*exp(-0.5*((x-3.10)/0.22)^2)-0.75*exp(-0.5*((x-7.00)/0.35)^2)+0.45*exp(-0.5*((x-5.25)/0.60)^2)
sampling=uniform
x_start_s=0
x_stop_s=10
x_step_s=0.02
samples=501
noise=Gaussian sigma 0.11 V
seed=1974
spike_122_V=0.65
spike_308_V=-0.70
spike_431_V=0.55
columns=time_s;reference_V;measured_V
units=s;V;V
"""
    (metadata_dir / "ground_truth.txt").write_text(ground_truth, encoding="utf-8")
    print("Generated deterministic smoothing demonstration dataset.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
