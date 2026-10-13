#!/usr/bin/env python3
"""Generate the deterministic Session input for demo.numeric.statistics."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import argparse,csv
from pathlib import Path
ROWS=[
(1,'-4','1'),(2,'-1','2'),(3,'0','1'),(4,'1','1'),(5,'2','3'),(6,'2','2'),(7,'3','1'),(8,'5','1'),(9,'8','2'),(10,'13','1'),
(11,'NA','1'),(12,'missing','1'),(13,'invalid','1'),(14,'21','0')]
def main():
    p=argparse.ArgumentParser();p.add_argument('--target-session',required=True);p.add_argument('--library-id');p.add_argument('--generator-id');a=p.parse_args()
    root=Path(a.target_session);raw=root/'raw';meta=root/'metadata';raw.mkdir(parents=True,exist_ok=True);meta.mkdir(parents=True,exist_ok=True)
    with (raw/'statistics_demo.csv').open('w',newline='',encoding='utf-8') as f:
        w=csv.writer(f);w.writerow(['sample','value_V','weight']);w.writerows(ROWS)
    truth="""dataset_rows=14\nfinite_value_count=11\nnonfinite_value_count=3\nfinite_values=-4;-1;0;1;2;2;3;5;8;13;21\ndescriptive_mean=4.545454545454545\ndescriptive_q25=0.5\ndescriptive_median=2\ndescriptive_q75=6.5\ndescriptive_variance_population=46.06611570247934\ndescriptive_variance_sample=50.67272727272727\nweighted_finite_pair_count=11\nweighted_positive_count=10\nweighted_zero_count=1\nweighted_mean=2.8\nweighted_q25=0\nweighted_median=2\nweighted_q75=5\nweighted_variance_population=16.82666666666666\nweighted_variance_unbiased=19.12121212121212\nquantile_definition=Hyndman-Fan type 7 linear interpolation\nweighted_quantile_definition=weighted empirical CDF inverse\nnotes=ground_truth is for tests/human inspection only; demo plugin must not read it\n"""
    (meta/'ground_truth.txt').write_text(truth,encoding='utf-8');print('Generated deterministic statistics demonstration dataset.');return 0
if __name__=='__main__': raise SystemExit(main())
