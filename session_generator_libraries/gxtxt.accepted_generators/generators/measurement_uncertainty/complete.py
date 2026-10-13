#!/usr/bin/env python3
"""Generate source data and a complete ordinary GX-TXT Session."""
from __future__ import annotations
import argparse
from pathlib import Path
from generate import main as generate_source
from session_recipe import configure

DATASETS = [{'csv': 'measurement_uncertainty_demo.csv',
  'id': 'uncertainty.source',
  'contract': 'table.generic',
  'units': {'value_V': 'V', 'sigma_V': 'V', 'weight_V_m2': 'V^-2'},
  'roles': {'measurement_id': 'independent',
            'value_V': 'measured',
            'sigma_V': 'uncertainty',
            'weight_V_m2': 'weight'},
  'missing_as_nan': False}]
ANALYSES = [{'module': 'demo.numeric.uncertainty',
  'source': 'uncertainty.source',
  'bindings': {'value': 'value_V', 'aux': 'sigma_V'},
  'config': {'input_interpretation': 'standard_uncertainty', 'nonfinite_policy': 'omit'},
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
    configure(Path(args.target_session), "measurement_uncertainty", DATASETS, ANALYSES, TEMPORAL_SETS)
    return result

if __name__ == "__main__":
    raise SystemExit(main())
