#!/usr/bin/env python3
"""Generate the deterministic Session input for demo.numeric.peaks."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import argparse,csv,math
from pathlib import Path

def signal(x: float) -> float:
    baseline=0.15+0.0008*x
    p1=3.0*math.exp(-0.5*((x-20.0)/2.2)**2)
    p2=5.0*math.exp(-0.5*((x-50.0)/3.5)**2)
    p3=2.6*math.exp(-0.5*((x-78.0)/1.8)**2)
    return baseline+p1+p2+p3

def main() -> int:
    p=argparse.ArgumentParser();p.add_argument('--target-session',required=True);p.add_argument('--library-id');p.add_argument('--generator-id');a=p.parse_args()
    root=Path(a.target_session);raw=root/'raw';meta=root/'metadata';raw.mkdir(parents=True,exist_ok=True);meta.mkdir(parents=True,exist_ok=True)
    rows=[(i,float(i),signal(float(i))) for i in range(101)]
    with (raw/'peak_detection_demo.csv').open('w',newline='',encoding='utf-8') as f:
        w=csv.writer(f);w.writerow(['sample','x_s','signal_V']);w.writerows((i,f'{x:.12g}',f'{y:.15g}') for i,x,y in rows)
    truth="""dataset_rows=101
x_unit=s
signal_unit=V
expected_peak_count=3
expected_peak_x=20;50;78
recommended_min_height=0.5
recommended_min_prominence=0.5
recommended_min_distance=8
recommended_distance_mode=x
recommended_relative_height=0.5
notes=ground_truth is for tests/human inspection only; demo plugin must not read it
"""
    (meta/'ground_truth.txt').write_text(truth,encoding='utf-8')
    print('Generated deterministic peak-detection demonstration dataset.')
    return 0
if __name__=='__main__': raise SystemExit(main())
