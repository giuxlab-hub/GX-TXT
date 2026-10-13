#!/usr/bin/env python3
"""Generate source data and a complete ordinary GX-TXT Session."""
from __future__ import annotations
import argparse
from pathlib import Path
from generate import main as generate_source
from session_recipe import configure

DATASETS = [{'csv': 'peak_detection_demo.csv',
  'id': 'peaks.source',
  'contract': 'table.generic',
  'units': {'x_s': 's', 'signal_V': 'V'},
  'roles': {'sample': 'sample_index', 'x_s': 'independent', 'signal_V': 'measured'},
  'missing_as_nan': False,
  'coordinate': 'x_s'}]
ANALYSES = [{'module': 'demo.numeric.peaks',
  'source': 'peaks.source',
  'bindings': {'x': 'x_s', 'signal': 'signal_V'},
  'config': {'min_height': '0.5',
             'min_prominence': '0.5',
             'min_distance': '8',
             'distance_mode': 'x',
             'relative_height': '0.5'},
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
    configure(Path(args.target_session), "peak_detection", DATASETS, ANALYSES, TEMPORAL_SETS)
    return result

if __name__ == "__main__":
    raise SystemExit(main())
