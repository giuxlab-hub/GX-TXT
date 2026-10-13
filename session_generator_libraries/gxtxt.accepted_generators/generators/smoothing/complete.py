#!/usr/bin/env python3
"""Generate source data and a complete ordinary GX-TXT Session."""
from __future__ import annotations
import argparse
from pathlib import Path
from generate import main as generate_source
from session_recipe import configure

DATASETS = [{'csv': 'smoothing_demo.csv',
  'id': 'smoothing.source',
  'contract': 'timeseries.table',
  'units': {'time_s': 's', 'reference_V': 'V', 'measured_V': 'V'},
  'roles': {'time_s': 'independent', 'reference_V': 'reference', 'measured_V': 'measured'},
  'missing_as_nan': False}]
ANALYSES = [{'module': 'demo.numeric.smoothing',
  'source': 'smoothing.source',
  'bindings': {'x': 'time_s', 'measured': 'measured_V', 'reference': 'reference_V'},
  'config': {},
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
    configure(Path(args.target_session), "smoothing", DATASETS, ANALYSES, TEMPORAL_SETS)
    return result

if __name__ == "__main__":
    raise SystemExit(main())
