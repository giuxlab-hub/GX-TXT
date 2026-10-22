# SPDX-License-Identifier: GPL-3.0-or-later
"""Dependency-free unit tests. Optional external tests use ANDI_FIXTURE_DIR."""
import importlib.util
import math
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'runtime' / 'andi_chromatography.py'
spec = importlib.util.spec_from_file_location('andi_chromatography', SRC)
andi = importlib.util.module_from_spec(spec)
spec.loader.exec_module(andi)


def u32(n):
    return struct.pack('>I', n)


def pad(raw):
    return raw + bytes((-len(raw)) % 4)


def name(value):
    return u32(len(value)) + pad(value.encode('ascii'))


def attrs(values):
    if not values:
        return u32(0) + u32(0)
    out = u32(12) + u32(len(values))
    for key, val in values.items():
        if isinstance(val, str):
            tp, size, data = 2, len(val.encode('ascii')), val.encode('ascii')
        elif isinstance(val, float):
            tp, size, data = 5, 1, struct.pack('>f', val)
        else:
            raise ValueError(val)
        out += name(key) + u32(tp) + u32(size) + pad(data)
    return out


def make_cdf(path, *, flag='Y', unit='s', nonuniform=False, version=1, invalid=False,
             interval=None, ordinate_begin=None, delay=None, retention=None):
    dims = [('point_number', 3), ('peak_number', 1), ('name_width', 8)]
    dim = u32(10) + u32(len(dims)) + b''.join(name(k) + u32(v) for k, v in dims)
    ga = attrs({'retention_unit': unit, 'detector_unit': 'uS/cm', 'detector_name': 'Generic IC'})
    vars_ = [
        ('actual_delay_time', [], 5 if delay is None else 6,
         struct.pack('>f', 0.) if delay is None else struct.pack('>d', delay), {}),
        ('actual_run_time_length', [], 5, struct.pack('>f', 2.), {}),
        ('actual_sampling_interval', [], 5 if interval is None else 6,
         struct.pack('>f', 1.) if interval is None else struct.pack('>d', interval), {}),
        ('ordinate_values', [0], 5, struct.pack('>fff', 2., (float('nan') if invalid else 3.), 4.), {'uniform_sampling_flag': flag}),
        ('peak_retention_time', [1], 5, struct.pack('>f', 1.), {}),
        ('peak_name', [1, 2], 2, b'F\x00\x00\x00\x00\x00\x00\x00', {}),
        ('peak_area', [1], 5, struct.pack('>f', 6.), {}),
    ]
    if nonuniform:
        vars_.append(('raw_data_retention', [0], 5 if retention is None else 6,
                      struct.pack('>fff', .5, .9, 1.7) if retention is None
                      else struct.pack('>ddd', *retention), {}))
    header = b'CDF' + bytes([version]) + u32(0) + dim + ga
    def var_header(offsets):
        out = u32(11) + u32(len(vars_))
        for (nam, ids, tp, data, at), offset in zip(vars_, offsets):
            out += name(nam) + u32(len(ids)) + b''.join(u32(x) for x in ids) + attrs(at) + u32(tp) + u32(len(pad(data)))
            if nam == 'ordinate_values' and ordinate_begin is not None:
                offset = ordinate_begin
            out += struct.pack('>Q' if version == 2 else '>I', offset)
        return out
    empty = var_header([0] * len(vars_))
    offset = len(header) + len(empty)
    offsets = []
    for _name, _ids, _type, data, _attrs in vars_:
        offsets.append(offset)
        offset += len(pad(data))
    content = header + var_header(offsets) + b''.join(pad(data) for _, _, _, data, _ in vars_)
    path.write_bytes(content)
    return path


class ReaderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_uniform_cdf1(self):
        f = make_cdf(self.root / 'uniform.cdf')
        with andi.NetCDFClassic(f) as nc:
            c = andi.Chromatography(nc)
            self.assertEqual(c.n, 3)
            self.assertEqual(list(c.time_values()), [0., 1., 2.])
            self.assertEqual(c.signal(), [2., 3., 4.])
            columns, rows = c.peaks()
            self.assertEqual([x[0] for x in columns], ['peak_number', 'peak_retention_s', 'peak_retention_min', 'peak_name', 'peak_area'])
            self.assertEqual(rows[0][3], 'F')

    def test_cdf2(self):
        f = make_cdf(self.root / 'CDF2.cdf', version=2)
        with andi.NetCDFClassic(f) as nc:
            self.assertEqual(nc.format, 'netcdf_64bit_offset')
            self.assertEqual(andi.Chromatography(nc).signal(), [2., 3., 4.])

    def test_nonuniform(self):
        f = make_cdf(self.root / 'variable.cdf', flag='N', nonuniform=True)
        with andi.NetCDFClassic(f) as nc:
            c = andi.Chromatography(nc)
            x = list(c.time_values())
            self.assertAlmostEqual(x[0], .5)
            self.assertAlmostEqual(x[1], .9, places=6)
            self.assertAlmostEqual(x[2], 1.7, places=6)

    def test_unsupported_time_units(self):
        f = make_cdf(self.root / 'badunits.cdf', unit='widgets')
        with andi.NetCDFClassic(f) as nc:
            with self.assertRaisesRegex(andi.AndiError, 'Unsupported retention_unit'):
                andi.Chromatography(nc)

    def test_missing_retention_for_nonuniform(self):
        f = make_cdf(self.root / 'wrong.cdf', flag='N')
        with andi.NetCDFClassic(f) as nc:
            with self.assertRaisesRegex(andi.AndiError, 'raw_data_retention'):
                andi.Chromatography(nc)

    def test_corruption_and_hdf(self):
        f = self.root / 'corrupt.cdf'
        f.write_bytes(b'CDF\x01' + b'\x00' * 48)
        with andi.NetCDFClassic(f) as nc:
            with self.assertRaises(andi.AndiError):
                andi.Chromatography(nc)
        f.write_bytes(b'\x89HDF\r\n\x1a\n' + bytes(100))
        with self.assertRaisesRegex(andi.AndiError, 'NetCDF-4'):
            with andi.NetCDFClassic(f):
                pass

    def test_nonfinite_signal(self):
        f = make_cdf(self.root / 'nan.cdf', invalid=True)
        with andi.NetCDFClassic(f) as nc:
            c = andi.Chromatography(nc)
            with self.assertRaisesRegex(andi.AndiError, 'Nonfinite'):
                c.signal()

    def test_cli_import_csv(self):
        f = make_cdf(self.root / 'ok.cdf')
        trace = self.root / 'trace.csv'
        peaks = self.root / 'peaks.csv'
        run = subprocess.run([sys.executable, str(SRC), '--mode', 'import', '--input', str(f),
                             '--trace-path', str(trace), '--peaks-path', str(peaks)],
                             capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn('GXANDI1', run.stdout)
        self.assertEqual(trace.read_text().splitlines()[0], 'time_s,time_min,signal_value')
        self.assertEqual(len(trace.read_text().splitlines()), 4)
        self.assertEqual(len(peaks.read_text().splitlines()), 2)

    def test_computed_time_overflow(self):
        for version in (1, 2):
            with self.subTest(version=version):
                f = make_cdf(self.root / f'overflow{version}.cdf',
                             version=version, interval=1e308)
                with andi.NetCDFClassic(f) as nc:
                    c = andi.Chromatography(nc)
                    with self.assertRaisesRegex(andi.AndiError, 'Computed retention time is nonfinite'):
                        list(c.time_values())
                for mode in ('inspect', 'import'):
                    with self.subTest(mode=mode):
                        trace = self.root / f'overflow{version}.{mode}.trace.csv'
                        peaks = self.root / f'overflow{version}.{mode}.peaks.csv'
                        argv = [sys.executable, str(SRC), '--mode', mode, '--input', str(f)]
                        if mode == 'import':
                            argv += ['--trace-path', str(trace), '--peaks-path', str(peaks)]
                        run = subprocess.run(argv, capture_output=True, text=True)
                        self.assertEqual(run.returncode, 2, run.stderr)
                        self.assertIn('Computed retention time is nonfinite', run.stderr)
                        self.assertFalse(trace.exists())
                        self.assertFalse(peaks.exists())

    def test_variable_payload_overlaps_header(self):
        for version in (1, 2):
            with self.subTest(version=version):
                f = make_cdf(self.root / f'header_overlap{version}.cdf',
                             version=version, ordinate_begin=0)
                with self.assertRaisesRegex(andi.AndiError, 'overlaps NetCDF header'):
                    with andi.NetCDFClassic(f):
                        pass
                trace = self.root / f'header_overlap{version}.trace.csv'
                peaks = self.root / f'header_overlap{version}.peaks.csv'
                run = subprocess.run([sys.executable, str(SRC), '--mode', 'import',
                                      '--input', str(f), '--trace-path', str(trace),
                                      '--peaks-path', str(peaks)], capture_output=True, text=True)
                self.assertEqual(run.returncode, 2, run.stderr)
                self.assertIn('overlaps NetCDF header', run.stderr)
                self.assertFalse(trace.exists())
                self.assertFalse(peaks.exists())

    def test_uniform_axis_precision_collapse(self):
        for version in (1, 2):
            with self.subTest(version=version):
                f = make_cdf(self.root / f'uniform_collapse{version}.cdf',
                             version=version, delay=1e16, interval=1.)
                self._assert_axis_precision_rejected(f)
                valid = make_cdf(self.root / f'negative_uniform{version}.cdf',
                                 version=version, delay=-2., interval=1.)
                with andi.NetCDFClassic(valid) as nc:
                    self.assertEqual(list(andi.Chromatography(nc).time_values()), [-2., -1., 0.])

    def test_nonuniform_axis_conversion_collapse(self):
        tiny = math.ulp(0.)
        for version in (1, 2):
            with self.subTest(version=version):
                f = make_cdf(self.root / f'nonuniform_collapse{version}.cdf',
                             version=version, flag='N', unit='ms', nonuniform=True,
                             retention=[tiny, 2 * tiny, 3 * tiny])
                self._assert_axis_precision_rejected(f)
                valid = make_cdf(self.root / f'negative_nonuniform{version}.cdf',
                                 version=version, flag='N', unit='ms', nonuniform=True,
                                 retention=[-2., -.5, 0.])
                with andi.NetCDFClassic(valid) as nc:
                    self.assertEqual(list(andi.Chromatography(nc).time_values()), [-.002, -.0005, 0.])

    def _assert_axis_precision_rejected(self, path):
        message = 'Computed retention axis must be strictly increasing'
        with andi.NetCDFClassic(path) as nc:
            with self.assertRaisesRegex(andi.AndiError, message):
                list(andi.Chromatography(nc).time_values())
        for mode in ('inspect', 'import'):
            with self.subTest(mode=mode):
                trace = self.root / f'{path.stem}.{mode}.trace.csv'
                peaks = self.root / f'{path.stem}.{mode}.peaks.csv'
                argv = [sys.executable, str(SRC), '--mode', mode, '--input', str(path)]
                if mode == 'import':
                    argv += ['--trace-path', str(trace), '--peaks-path', str(peaks)]
                run = subprocess.run(argv, capture_output=True, text=True)
                self.assertEqual(run.returncode, 2, run.stderr)
                self.assertIn(message, run.stderr)
                self.assertFalse(trace.exists())
                self.assertFalse(peaks.exists())

    def test_real_samples_if_supplied(self):
        root = os.environ.get('ANDI_FIXTURE_DIR')
        if not root:
            self.skipTest('Supply ANDI_FIXTURE_DIR to validate real CDF files')
        files = sorted(Path(root).glob('*.cdf'))
        self.assertGreater(len(files), 0)
        for f in files:
            with self.subTest(file=f.name), andi.NetCDFClassic(f) as nc:
                c = andi.Chromatography(nc)
                self.assertEqual(len(c.signal()), c.n)
                self.assertEqual(len(list(c.time_values())), c.n)
                self.assertGreaterEqual(len(c.peaks()[1]), 0)


if __name__ == '__main__':
    unittest.main()
