#!/usr/bin/env python3
"""Generate source data and a complete ordinary GX-TXT Session."""
from __future__ import annotations
import argparse
from pathlib import Path
from generate import main as generate_source
from session_recipe import configure

DATASETS = [{'csv': 'minimization_1d.csv',
  'id': 'minimization.source',
  'contract': 'table.generic',
  'units': {},
  'roles': {'x': 'independent', 'f': 'measured'},
  'missing_as_nan': False}]
ANALYSES = [{'module': 'demo.numeric.minimization',
  'source': 'minimization.source',
  'bindings': {'x': 'x', 'function': 'f'},
  'config': {'interpolation_method': 'pchip', 'lower_bound': '-3', 'upper_bound': '5'},
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
    configure(Path(args.target_session), "minimization_1d", DATASETS, ANALYSES, TEMPORAL_SETS)
    return result

if __name__ == "__main__":
    raise SystemExit(main())
