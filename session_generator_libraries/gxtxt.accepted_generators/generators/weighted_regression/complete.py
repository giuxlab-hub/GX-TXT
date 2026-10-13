#!/usr/bin/env python3
"""Generate source data and a complete ordinary GX-TXT Session."""
from __future__ import annotations
import argparse
from pathlib import Path
from generate import main as generate_source
from session_recipe import configure

DATASETS = [{'csv': 'weighted_linear_regression.csv',
  'id': 'regression.linear',
  'contract': 'table.generic',
  'units': {'y': 'V', 'reference_y': 'V', 'sigma_y': 'V', 'weight_inv_variance': 'V^-2'},
  'roles': {'x': 'independent',
            'y': 'measured',
            'reference_y': 'reference',
            'sigma_y': 'uncertainty',
            'weight_inv_variance': 'weight'},
  'missing_as_nan': False},
 {'csv': 'weighted_polynomial_fitting.csv',
  'id': 'regression.polynomial',
  'contract': 'table.generic',
  'units': {'y': 'V', 'reference_y': 'V', 'sigma_y': 'V', 'weight_inv_variance': 'V^-2'},
  'roles': {'x': 'independent',
            'y': 'measured',
            'reference_y': 'reference',
            'sigma_y': 'uncertainty',
            'weight_inv_variance': 'weight'},
  'missing_as_nan': False}]
ANALYSES = [{'module': 'demo.numeric.regression',
  'source': 'regression.linear',
  'bindings': {'x': 'x',
               'measured': 'y',
               'reference': 'reference_y',
               'sigma': 'sigma_y',
               'weight': 'weight_inv_variance'},
  'config': {'fit_mode': 'linear', 'weight_semantics': 'inverse_variance'},
  'derived_source': False,
  'initial_run': True}]
TEMPORAL_SETS = []

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-session", required=True)
    parser.add_argument("--library-id")
    parser.add_argument("--generator-id")
    args = parser.parse_args()
    result = generate_source()
    configure(Path(args.target_session), "weighted_regression", DATASETS, ANALYSES, TEMPORAL_SETS)
    return result

if __name__ == "__main__":
    raise SystemExit(main())
