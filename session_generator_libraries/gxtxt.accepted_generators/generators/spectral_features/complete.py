#!/usr/bin/env python3
"""Generate source data and a complete ordinary GX-TXT Session."""
from __future__ import annotations
import argparse
from pathlib import Path
from generate import main as generate_source
from session_recipe import configure

DATASETS = [{'csv': 'spectral_features_demo.csv',
  'id': 'spectral_features.source',
  'contract': 'timeseries.table',
  'units': {'time_s': 's', 'signal_V': 'V'},
  'roles': {'time_s': 'independent', 'signal_V': 'measured'},
  'missing_as_nan': False}]
ANALYSES = [{'module': 'analysis.fft_spectrum',
  'source': 'spectral_features.source',
  'bindings': {'independent': 'time_s', 'signal': 'signal_V'},
  'config': {'analysis_mode': 'full_record', 'window': 'rectangular', 'detrend': 'mean'},
  'derived_source': False,
  'initial_run': True},
 {'module': 'analysis.spectral_features',
  'source': 'spectral_features.source.spectrum',
  'bindings': {'frequency': 'frequency', 'value': 'amplitude'},
  'config': {'input_semantics': 'amplitude',
             'exclude_dc': 'yes',
             'output_dataset_id': 'spectral_features.summary'},
  'derived_source': True,
  'initial_run': False}]
TEMPORAL_SETS = []

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-session", required=True)
    parser.add_argument("--library-id")
    parser.add_argument("--generator-id")
    args = parser.parse_args()
    result = generate_source()
    configure(Path(args.target_session), "spectral_features", DATASETS, ANALYSES, TEMPORAL_SETS)
    return result

if __name__ == "__main__":
    raise SystemExit(main())
