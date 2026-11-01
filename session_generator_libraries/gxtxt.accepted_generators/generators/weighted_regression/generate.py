#!/usr/bin/env python3
"""Generate deterministic weighted-regression inputs for demo.numeric.regression."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import argparse,csv,random
from pathlib import Path

LINEAR_SEED=1975
POLY_SEED=1976

def write_linear(root: Path) -> None:
    rng=random.Random(LINEAR_SEED)
    path=root/'raw'/'weighted_linear_regression.csv'
    with path.open('w',newline='',encoding='utf-8') as f:
        w=csv.writer(f);w.writerow(['x','y','reference_y','sigma_y','weight_inv_variance'])
        for i in range(41):
            x=0.5*i
            reference=2.5*x+1.2
            sigma=0.08+0.012*x
            measured=reference+rng.gauss(0.0,sigma)
            weight=1.0/(sigma*sigma)
            w.writerow([f'{x:.8g}',f'{measured:.12g}',f'{reference:.12g}',f'{sigma:.12g}',f'{weight:.12g}'])
    text='''regression.model=linear\nregression.truth.degree=1\nregression.truth.coefficients=2.5;1.2\nregression.truth.slope=2.5\nregression.truth.intercept=1.2\nregression.noise=heteroscedastic_gaussian\nregression.seed=1975\nregression.sigma_variable=sigma_y\nregression.weight_variable=weight_inv_variance\nregression.weight_semantics=inverse_variance\nregression.reference_variable=reference_y\nregression.columns=x;y;reference_y;sigma_y;weight_inv_variance\n'''
    (root/'metadata'/'ground_truth_linear.txt').write_text(text,encoding='utf-8')

def write_poly(root: Path) -> None:
    rng=random.Random(POLY_SEED)
    path=root/'raw'/'weighted_polynomial_fitting.csv'
    with path.open('w',newline='',encoding='utf-8') as f:
        w=csv.writer(f);w.writerow(['x','y','reference_y','sigma_y','weight_inv_variance'])
        for i in range(61):
            x=-3.0+0.1*i
            reference=0.5*x**3-2.0*x**2+1.5*x+3.0
            sigma=0.06+0.035*abs(x)
            measured=reference+rng.gauss(0.0,sigma)
            weight=1.0/(sigma*sigma)
            w.writerow([f'{x:.8g}',f'{measured:.12g}',f'{reference:.12g}',f'{sigma:.12g}',f'{weight:.12g}'])
    text='''regression.model=polynomial\nregression.truth.degree=3\nregression.truth.coefficients=0.5;-2;1.5;3\nregression.noise=heteroscedastic_gaussian\nregression.seed=1976\nregression.sigma_variable=sigma_y\nregression.weight_variable=weight_inv_variance\nregression.weight_semantics=inverse_variance\nregression.reference_variable=reference_y\nregression.columns=x;y;reference_y;sigma_y;weight_inv_variance\n'''
    (root/'metadata'/'ground_truth_polynomial.txt').write_text(text,encoding='utf-8')

def main() -> int:
    p=argparse.ArgumentParser();p.add_argument('--target-session',required=True);p.add_argument('--library-id');p.add_argument('--generator-id');a=p.parse_args()
    root=Path(a.target_session);(root/'raw').mkdir(parents=True,exist_ok=True);(root/'metadata').mkdir(parents=True,exist_ok=True)
    write_linear(root);write_poly(root)
    print('Generated deterministic weighted linear and polynomial regression datasets.')
    return 0
if __name__=='__main__': raise SystemExit(main())
