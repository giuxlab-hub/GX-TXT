#!/usr/bin/env python3
"""Generate source data and a complete ordinary GX-TXT Session."""
from __future__ import annotations
import argparse
from pathlib import Path
from generate import main as generate_source
from session_recipe import configure

DATASETS = [{'csv': 'statistics_demo.csv',
  'id': 'statistics.source',
  'contract': 'table.generic',
  'units': {'value_V': 'V'},
  'roles': {'sample': 'independent', 'value_V': 'measured', 'weight': 'weight'},
  'missing_as_nan': True}]
ANALYSES = [{'module': 'demo.numeric.statistics',
  'source': 'statistics.source',
  'bindings': {'value': 'value_V', 'weight': 'weight'},
  'config': {'mode': 'weighted', 'nonfinite_policy': 'omit'},
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
    configure(Path(args.target_session), "statistics", DATASETS, ANALYSES, TEMPORAL_SETS)
    return result

if __name__ == "__main__":
    raise SystemExit(main())
