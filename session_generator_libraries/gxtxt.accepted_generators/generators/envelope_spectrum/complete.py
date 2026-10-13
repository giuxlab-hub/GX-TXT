#!/usr/bin/env python3
"""Generate source data and a complete ordinary GX-TXT Session."""
from __future__ import annotations
import argparse
from pathlib import Path
from generate import main as generate_source
from session_recipe import configure

DATASETS = [{'csv': 'envelope_spectrum_demo.csv',
  'id': 'envelope.source',
  'contract': 'timeseries.table',
  'units': {'time_s': 's', 'envelope_truth_V': 'V', 'clean_V': 'V', 'measured_V': 'V'},
  'roles': {'time_s': 'independent',
            'envelope_truth_V': 'reference',
            'clean_V': 'reference',
            'measured_V': 'measured'},
  'missing_as_nan': False}]
ANALYSES = [{'module': 'analysis.envelope_spectrum',
  'source': 'envelope.source',
  'bindings': {'time': 'time_s', 'signal': 'measured_V'},
  'config': {'input_detrend': 'mean',
             'demodulation_filter': 'ideal_fft_bandpass',
             'band_low_hz': '1500',
             'band_high_hz': '2600',
             'envelope_dc': 'remove_mean',
             'window': 'hann',
             'nfft_mode': 'auto',
             'nfft': '65536'},
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
    configure(Path(args.target_session), "envelope_spectrum", DATASETS, ANALYSES, TEMPORAL_SETS)
    return result

if __name__ == "__main__":
    raise SystemExit(main())
