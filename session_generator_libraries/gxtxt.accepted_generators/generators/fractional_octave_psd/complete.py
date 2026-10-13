#!/usr/bin/env python3
"""Generate source data and a complete ordinary GX-TXT Session."""
from __future__ import annotations
import argparse
from pathlib import Path
from generate import main as generate_source
from session_recipe import configure

DATASETS = [{'csv': 'fractional_octave_psd.csv',
  'id': 'fractional_octave.source',
  'contract': 'spectrum.table',
  'units': {'frequency_Hz': 'Hz', 'psd_V2_per_Hz': 'V^2/Hz'},
  'roles': {'frequency_Hz': 'independent', 'psd_V2_per_Hz': 'measured'},
  'missing_as_nan': False}]
ANALYSES = [{'module': 'analysis.fractional_octave_spectrum',
  'source': 'fractional_octave.source',
  'bindings': {'frequency': 'frequency_Hz', 'psd': 'psd_V2_per_Hz'},
  'config': {'bands_per_octave': '3', 'range_mode': 'auto', 'reference_rms': '1'},
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
    configure(Path(args.target_session), "fractional_octave_psd", DATASETS, ANALYSES, TEMPORAL_SETS)
    return result

if __name__ == "__main__":
    raise SystemExit(main())
