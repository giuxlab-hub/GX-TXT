#!/usr/bin/env python3
"""Generate source data and a complete ordinary GX-TXT Session."""
from __future__ import annotations
import argparse
from pathlib import Path
from generate import main as generate_source
from session_recipe import configure

DATASETS = [{'csv': 'harmonic_analysis_demo.csv',
  'id': 'harmonic.source',
  'contract': 'timeseries.table',
  'units': {'time_s': 's', 'fundamental_only_V': 'V', 'distorted_V': 'V'},
  'roles': {'time_s': 'independent',
            'fundamental_only_V': 'reference',
            'distorted_V': 'measured'},
  'missing_as_nan': False}]
ANALYSES = [{'module': 'analysis.fft_spectrum',
  'source': 'harmonic.source',
  'bindings': {'independent': 'time_s', 'signal': 'distorted_V'},
  'config': {'analysis_mode': 'full_record', 'window': 'rectangular', 'detrend': 'mean'},
  'derived_source': False,
  'initial_run': True},
 {'module': 'analysis.harmonic_analysis',
  'source': 'harmonic.source.spectrum',
  'bindings': {'frequency': 'frequency', 'amplitude': 'amplitude'},
  'config': {'fundamental_mode': 'auto_peak',
             'max_harmonic': '5',
             'output_dataset_id': 'harmonic_analysis.result'},
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
    configure(Path(args.target_session), "harmonic_analysis", DATASETS, ANALYSES, TEMPORAL_SETS)
    return result

if __name__ == "__main__":
    raise SystemExit(main())
