#!/usr/bin/env python3
"""Generate deterministic Session input for demo.numeric.uncertainty."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import argparse,csv,math
from pathlib import Path

VALUES=[10.00,10.08,9.95,10.02,11.20]
SIGMA=[0.05,0.08,0.05,0.06,0.80]

def main() -> int:
    p=argparse.ArgumentParser();p.add_argument('--target-session',required=True);p.add_argument('--library-id');p.add_argument('--generator-id');a=p.parse_args()
    root=Path(a.target_session);raw=root/'raw';meta=root/'metadata';raw.mkdir(parents=True,exist_ok=True);meta.mkdir(parents=True,exist_ok=True)
    weights=[1.0/(s*s) for s in SIGMA]
    with (raw/'measurement_uncertainty_demo.csv').open('w',newline='',encoding='utf-8') as f:
        w=csv.writer(f);w.writerow(['measurement_id','value_V','sigma_V','weight_V_m2'])
        for i,(v,s,wt) in enumerate(zip(VALUES,SIGMA,weights),1):w.writerow([i,f'{v:.15g}',f'{s:.15g}',f'{wt:.15g}'])
    mean=sum(VALUES)/len(VALUES)
    u_mean=math.sqrt(sum(s*s for s in SIGMA))/len(SIGMA)
    sw=sum(weights);weighted_mean=sum(w*v for w,v in zip(weights,VALUES))/sw
    weighted_se=1.0/math.sqrt(sw)
    eff=sw*sw/sum(w*w for w in weights)
    truth=f'''dataset_rows={len(VALUES)}\nvalue_unit=V\nsigma_unit=V\nweight_unit=V^-2\nweight_definition=explicit reference weights generated as 1/sigma^2; the demo plugin never performs this conversion\nexpected_ordinary_mean_V={mean:.17g}\nexpected_standard_uncertainty_of_mean_V={u_mean:.17g}\nexpected_inverse_variance_weighted_mean_V={weighted_mean:.17g}\nexpected_inverse_variance_estimate_standard_error_V={weighted_se:.17g}\nexpected_sum_weights_V_m2={sw:.17g}\nexpected_effective_sample_size={eff:.17g}\nnotes=ground_truth is for tests/human inspection only; demo plugin must not read it\n'''
    (meta/'ground_truth.txt').write_text(truth,encoding='utf-8')
    print('Generated deterministic measurement-uncertainty demonstration dataset.')
    return 0
if __name__=='__main__': raise SystemExit(main())
