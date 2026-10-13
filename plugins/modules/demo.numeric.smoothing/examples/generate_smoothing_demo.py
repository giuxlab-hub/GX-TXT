#!/usr/bin/env python3
"""Generate the deterministic dataset used by demo.numeric.smoothing."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
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
    """Smooth sensor-like reference with broad and narrow features."""
    return (
        0.35 * math.sin(2.0 * math.pi * 0.22 * x)
        + 0.18 * math.cos(2.0 * math.pi * 0.55 * x)
        + 0.04 * x
        + 1.10 * math.exp(-0.5 * ((x - 3.10) / 0.22) ** 2)
        - 0.75 * math.exp(-0.5 * ((x - 7.00) / 0.35) ** 2)
        + 0.45 * math.exp(-0.5 * ((x - 5.25) / 0.60) ** 2)
    )


def generate(path: Path) -> None:
    rng = random.Random(SEED)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["time_s", "reference_V", "measured_V"])
        for i in range(SAMPLES):
            x = X_START_S + i * X_STEP_S
            reference = reference_signal(x)
            measured = reference + rng.gauss(0.0, NOISE_SIGMA_V) + SPIKES.get(i, 0.0)
            writer.writerow([f"{x:.8g}", f"{reference:.12g}", f"{measured:.12g}"])


if __name__ == "__main__":
    generate(Path(__file__).with_name("smoothing_demo.csv"))
    print("Generated deterministic smoothing demonstration dataset.")
