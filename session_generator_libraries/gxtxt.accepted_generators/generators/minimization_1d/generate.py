#!/usr/bin/env python3
"""Generate deterministic Session input for demo.numeric.minimization."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import argparse, csv
from pathlib import Path

START = -3.0
STOP = 5.0
STEP = 0.05
X_MIN = 1.75
Y_MIN = 2.0

def f(x: float) -> float:
    return (x - X_MIN) ** 2 + Y_MIN

def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument('--target-session', required=True)
    p.add_argument('--library-id')
    p.add_argument('--generator-id')
    a = p.parse_args()
    root = Path(a.target_session)
    raw = root / 'raw'
    meta = root / 'metadata'
    raw.mkdir(parents=True, exist_ok=True)
    meta.mkdir(parents=True, exist_ok=True)

    count = int(round((STOP - START) / STEP)) + 1
    with (raw / 'minimization_1d.csv').open('w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh)
        w.writerow(['x', 'f'])
        for i in range(count):
            x = START + i * STEP
            y = f(x)
            w.writerow([f'{x:.15g}', f'{y:.15g}'])

    truth = f'''expression=(x - 1.75)^2 + 2\nrange_start={START:.17g}\nrange_stop={STOP:.17g}\ngrid_step={STEP:.17g}\nrow_count={count}\nx_unit=1\nf_unit=1\nexpected_minimum_x={X_MIN:.17g}\nexpected_minimum_y={Y_MIN:.17g}\nrecommended_bounds={START:.17g},{STOP:.17g}\nnotes=ground_truth is for tests and human inspection only; demo plugin must not read it\n'''
    (meta / 'ground_truth.txt').write_text(truth, encoding='utf-8')
    print('Generated deterministic one-dimensional minimization demonstration dataset.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
