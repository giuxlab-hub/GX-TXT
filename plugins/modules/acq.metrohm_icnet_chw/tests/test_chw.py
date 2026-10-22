"""Format-level tests. Optional real fixture: CHW_SAMPLE_PATH=/path/file.CHW.
SPDX-License-Identifier: GPL-3.0-or-later
"""
from __future__ import annotations
import importlib.util
import os
import struct
import tempfile
import unittest
from pathlib import Path

HELPER = Path(__file__).resolve().parents[1] / 'runtime' / 'chw_inspect.py'
spec = importlib.util.spec_from_file_location('chw_inspect', HELPER)
chw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(chw)
FIXTURE = os.getenv('CHW_SAMPLE_PATH', '')


def pack_trace(start: int, runs: list[tuple[int, list[int]]]):
    samples = [start]
    chunks = []
    for mode, changes in runs:
        chunks.append(struct.pack('<H', len(changes) * 16 + mode))
        for delta in changes:
            if mode == 0:
                assert delta == 0
            else:
                width = {3: 1, 4: 2, 5: 4}[mode]
                chunks.append(int(delta).to_bytes(width, 'little', signed=True))
            samples.append(samples[-1] + delta)
    return struct.pack('<IIi', len(samples) * 4, len(runs), start) + b''.join(chunks), samples


class CHWTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = Path(FIXTURE).read_bytes() if FIXTURE and Path(FIXTURE).is_file() else None

    def test_codec_roundtrip_all_modes(self):
        data, expected = pack_trace(1000, [(3, [12, -13, 0]), (4, [1000, -300]),
                                           (0, [0, 0, 0, 0]), (5, [100000, -200001]),
                                           (3, [127, -128])])
        got, stat = chw.decode_trace(data, len(expected))
        self.assertEqual(got, expected)
        self.assertEqual(stat['block_count'], 5)
        self.assertEqual(stat['mode_counts'], {0: 1, 3: 2, 4: 1, 5: 1})

    def test_invalid_modes_rejected(self):
        data, values = pack_trace(50, [(3, [3])])
        bad = data[:12] + struct.pack('<H', 1 * 16 + 2) + data[14:]
        with self.assertRaises(chw.CHWError):
            chw.decode_trace(bad, len(values))

    def test_extra_data_rejected(self):
        data, values = pack_trace(50, [(3, [3])])
        with self.assertRaises(chw.CHWError):
            chw.decode_trace(data + b'X', len(values))

    def test_missing_blocks_rejected(self):
        data, values = pack_trace(50, [(3, [3])])
        bad = data[:4] + struct.pack('<I', 2) + data[8:]
        with self.assertRaises(chw.CHWError):
            chw.decode_trace(bad, len(values))

    def test_fabricated_sample_overflow_rejected(self):
        data, values = pack_trace(2**31 - 1, [(3, [1])])
        with self.assertRaises(chw.CHWError):
            chw.decode_trace(data, len(values))

    def test_output_never_overwrites(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / 'trace.csv'
            chw.write_signal_csv(out, [100, 101, 102], 0.1, 1e-5)
            body = out.read_text()
            self.assertEqual(len(body.splitlines()), 4)
            self.assertIn('time_s,time_min,signal_value,adc_count', body)
            self.assertIn('0.1,0.00166666666666667,0.00101,101', body)
            with self.assertRaises(chw.CHWError):
                chw.write_signal_csv(out, [999], .1, 1e-5)
            self.assertEqual(out.read_text(), body)

    def test_short_file_rejected(self):
        with self.assertRaises(chw.CHWError):
            chw.analyze(b'not Metrohm')

    def _fixture(self):
        if self.data is None:
            self.skipTest('Optional original file: CHW_SAMPLE_PATH')
        return chw.analyze(self.data, Path(FIXTURE).name)

    def test_real_file_numeric_trace(self):
        info = self._fixture()
        md = info['metadata']
        self.assertEqual(md['chromatography.signal_decode_status'], 'decoded_integer_exact')
        self.assertEqual(info['signal']['count'], int(md['chromatography.declared_sample_count']))
        self.assertEqual(sum(x['length'] for x in info['sections'].values()) + 298, len(self.data))
        self.assertGreater(int(md['chromatography.trace_block_count']), 1)

    def test_real_file_identity_not_extension(self):
        self._fixture()
        info = chw.analyze(self.data, 'chromatogram.bin')
        self.assertEqual(info['metadata']['chromatography.format'], 'metrohm.icnet.chw')

    def test_real_file_section_magic_and_truncation(self):
        self._fixture()
        bad = bytearray(self.data)
        bad[0] ^= 0xff
        with self.assertRaises(chw.CHWError):
            chw.analyze(bytes(bad))
        with self.assertRaises(chw.CHWError):
            chw.analyze(self.data[:-2])

    def test_real_file_sample_count_corruption(self):
        self._fixture()
        bad = bytearray(self.data)
        off = chw.parse_sections(bad)['S'][0]
        struct.pack_into('<I', bad, off + 46, 99)
        with self.assertRaises(chw.CHWError):
            chw.analyze(bytes(bad))

    def test_real_file_peak_corruption_rejected(self):
        self._fixture()
        bad = bytearray(self.data)
        off = chw.parse_sections(bad)['D'][0]
        struct.pack_into('<I', bad, off + 32 + 4, 0xFFFFFFFF)
        result = chw.analyze(bytes(bad))
        self.assertFalse(result['peaks'])
        self.assertTrue(any('inconsistent' in w for w in result['warnings']))


if __name__ == '__main__':
    unittest.main()
