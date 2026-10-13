#!/usr/bin/env python3
"""Generate source data and a complete ordinary GX-TXT Session."""
from __future__ import annotations
import argparse
from pathlib import Path
from generate import main as generate_source
from session_recipe import configure

DATASETS = [{'csv': 'welch_psd_demo.csv',
  'id': 'welch.source',
  'contract': 'timeseries.table',
  'units': {'time_s': 's', 'clean_V': 'V', 'measured_V': 'V'},
  'roles': {'time_s': 'independent', 'clean_V': 'reference', 'measured_V': 'measured'},
  'missing_as_nan': False}]
ANALYSES = [{'module': 'analysis.welch_spectrum',
  'source': 'welch.source',
  'bindings': {'time': 'time_s', 'signal': 'measured_V'},
  'config': {'run_mode': 'recalculate',
             'temporal_set': 'tset_001',
             'window': 'hann',
             'detrend': 'mean',
             'nfft_mode': 'auto',
             'workers': 'serial'},
  'derived_source': False,
  'initial_run': True}]
TEMPORAL_SETS = [{'id': 'tset_001',
  'api_version': '1',
  'type': 'window_set',
  'source_dataset_id': 'welch.source',
  'temporal_variable_id': 'v0001',
  'temporal_variable': 'time_s',
  'temporal_unit': 's',
  'parent_selection_id': '',
  'boundary_policy': 'start_inclusive_end_exclusive',
  'generator_basis': 'samples',
  'window_size': '2048',
  'step': '1024',
  'duration_unit': '',
  'partial_policy': 'drop',
  'label': '2048 samples with 50 percent overlap',
  'created_at': '2026-10-01T00:00:00+0000',
  'updated_at': '2026-10-01T00:00:00+0000'}]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-session", required=True)
    parser.add_argument("--library-id")
    parser.add_argument("--generator-id")
    args = parser.parse_args()
    result = generate_source()
    configure(Path(args.target_session), "welch_psd", DATASETS, ANALYSES, TEMPORAL_SETS)
    return result

if __name__ == "__main__":
    raise SystemExit(main())
