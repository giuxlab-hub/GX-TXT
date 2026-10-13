#!/usr/bin/env python3
"""Generate source data and a complete ordinary GX-TXT Session."""
from __future__ import annotations
import argparse
from pathlib import Path
from generate import main as generate_source
from session_recipe import configure

DATASETS = [{'csv': 'cepstrum_analysis_demo.csv',
  'id': 'cepstrum.source',
  'contract': 'timeseries.table',
  'units': {'time_s': 's', 'harmonic_series_V': 'V'},
  'roles': {'time_s': 'independent', 'harmonic_series_V': 'measured'},
  'missing_as_nan': False}]
ANALYSES = [{'module': 'analysis.cepstrum',
  'source': 'cepstrum.source',
  'bindings': {'independent': 'time_s', 'signal': 'harmonic_series_V'},
  'config': {'window': 'rectangular',
             'detrend': 'mean',
             'log_floor_db': '-240',
             'min_frequency_hz': '80',
             'max_frequency_hz': '200',
             'output_dataset_id': 'cepstrum.result'},
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
    configure(Path(args.target_session), "cepstrum", DATASETS, ANALYSES, TEMPORAL_SETS)
    return result

if __name__ == "__main__":
    raise SystemExit(main())
