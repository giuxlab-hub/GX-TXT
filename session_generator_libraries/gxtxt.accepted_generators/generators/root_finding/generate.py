#!/usr/bin/env python3
"""Generate deterministic Session input for demo.numeric.root_finding."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import argparse, csv
from pathlib import Path

ROOTS = (-2.0, 0.5, 3.0)
START = -4.0
STOP = 4.0
STEP = 0.05

def f(x: float) -> float:
    return (x + 2.0) * (x - 0.5) * (x - 3.0)

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
    with (raw / 'root_finding.csv').open('w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh)
        w.writerow(['x', 'f'])
        for i in range(count):
            x = START + i * STEP
            y = f(x)
            if abs(y) < 1e-15:
                y = 0.0
            w.writerow([f'{x:.15g}', f'{y:.15g}'])

    truth = f'''expression=(x + 2) * (x - 0.5) * (x - 3)\nrange_start={START:.17g}\nrange_stop={STOP:.17g}\ngrid_step={STEP:.17g}\nrow_count={count}\nx_unit=1\nf_unit=1\nexpected_roots=-2;0.5;3\nrecommended_intervals=-3,-1;0,1;2,4\nnotes=ground_truth is for tests and human inspection only; demo plugin must not read it\n'''
    (meta / 'ground_truth.txt').write_text(truth, encoding='utf-8')
    print('Generated deterministic root-finding demonstration dataset.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
