"""Bulk-path regression tests; original chromatograms are optional runtime fixtures.
SPDX-License-Identifier: GPL-3.0-or-later
"""
from __future__ import annotations
import contextlib
import hashlib
import importlib.util
import io
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

HELPER = Path(__file__).resolve().parents[1] / 'runtime' / 'chw_inspect.py'
sp = importlib.util.spec_from_file_location('chw_bulk', HELPER)
chw = importlib.util.module_from_spec(sp)
sp.loader.exec_module(chw)
SAMPLE = Path(os.environ['CHW_SAMPLE_PATH']) if os.environ.get('CHW_SAMPLE_PATH') else None


class BulkRegression(unittest.TestCase):
    def setUp(self):
        if SAMPLE is None or not SAMPLE.is_file():
            self.skipTest('Set CHW_SAMPLE_PATH to enable original-RAW regression')

    def test_single_decode_and_single_read(self):
        original_decode = chw.decode_trace
        calls = []

        def counted(*args):
            calls.append(1)
            return original_decode(*args)

        with tempfile.TemporaryDirectory() as d:
            dest = Path(d) / 'trace.csv'
            with patch.object(chw, 'decode_trace', side_effect=counted), patch.object(
                sys, 'argv', ['chw_inspect.py', '--input', str(SAMPLE), '--output', 'protocol',
                             '--csv-output', str(dest)]
            ), contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(chw.main(), 0)
            self.assertEqual(len(calls), 1)
            self.assertIn('GXCHW1', output.getvalue())
            with dest.open() as handle:
                rows = sum(1 for _ in handle) - 1
            self.assertEqual(rows, int(chw.analyze_file(SAMPLE)['metadata']['chromatography.declared_sample_count']))

    def test_new_output_identical_to_old_round_trip(self):
        data = SAMPLE.read_bytes()
        reference = chw.analyze(data, SAMPLE.name)
        sections = chw.parse_sections(data)
        o, size = sections['S']
        t, ts = sections['T']
        import struct
        n = chw.u32(data, o+46)
        interval = struct.unpack_from('<f', data, o+68)[0]
        scale = struct.unpack_from('<f', data, o+18)[0]
        old_samples, old_stats = chw.decode_trace(data[t:t+ts], n)
        with tempfile.TemporaryDirectory() as d:
            previous = Path(d)/'previous.csv'
            changed = Path(d)/'changed.csv'
            chw.write_signal_csv(previous, old_samples, interval, scale)
            payload = []
            current = chw.analyze(data, SAMPLE.name, decoded_values=payload)
            chw.write_signal_csv(changed, payload,
                                 float(current['metadata']['chromatography.sample_interval_s']),
                                 float(current['metadata']['chromatography.adc_step_raw_float32']))
            self.assertEqual(previous.read_bytes(), changed.read_bytes())
            self.assertEqual(reference, current)
            self.assertEqual(payload, old_samples)
            self.assertEqual(hashlib.sha256(data).hexdigest(),
                             hashlib.sha256(SAMPLE.read_bytes()).hexdigest())

    def test_preexisting_output_never_overwritten_or_removed(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'signal.csv'
            path.write_bytes(b'BEFORE')
            with (patch.object(sys, 'argv', ['chw_inspect.py', '--input', str(SAMPLE),
                                            '--output', 'protocol', '--csv-output', str(path)]),
                  contextlib.redirect_stderr(io.StringIO())):
                self.assertEqual(chw.main(), 2)
            self.assertEqual(path.read_bytes(), b'BEFORE')

if __name__ == '__main__':
    unittest.main()
