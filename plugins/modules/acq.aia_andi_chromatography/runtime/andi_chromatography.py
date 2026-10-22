#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Read AIA/ANDI-CHROM NetCDF classic data with Python stdlib only.

This intentionally supports chromatography (ASTM E1947 style) rather than
ANDI mass-spectrometry spectral datasets. No scientific data is inferred.
"""
import argparse
import base64
import csv
from itertools import islice
import math
import os
from pathlib import Path
import struct
import sys

MAX_FILE_BYTES = 512 * 1024 * 1024
MAX_META_BYTES = 1 * 1024 * 1024
MAX_DIMS = 512
MAX_VARS = 4096
TYPE_INFO = {1: ('b', 1), 2: (None, 1), 3: ('h', 2), 4: ('i', 4), 5: ('f', 4), 6: ('d', 8)}
NAME_MAX = 512


class AndiError(ValueError):
    pass


def _prod(seq):
    n = 1
    for v in seq:
        n *= v
    return n


def _unpack(raw, code):
    _, width = TYPE_INFO[code]
    if len(raw) % width:
        raise AndiError('Misaligned numeric payload')
    return [v[0] for v in struct.iter_unpack('>' + TYPE_INFO[code][0], raw)]


def _clean(value):
    if isinstance(value, bytes):
        return value.decode('utf-8', errors='replace').strip(' \x00\t\r\n')
    if isinstance(value, list):
        return ' '.join(map(str, value[:32]))
    return str(value)


class NetCDFClassic:
    def __init__(self, path):
        self.path = Path(path)
        if not self.path.is_file():
            raise AndiError('Source file does not exist')
        self.size = self.path.stat().st_size
        if not 32 <= self.size <= MAX_FILE_BYTES:
            raise AndiError('NetCDF source is empty, truncated or exceeds the safety limit')
        self.f = open(self.path, 'rb')
        self.dimensions = []
        self.attributes = {}
        self.variables = {}
        self.record_stride = 0
        try:
            self._header()
        except Exception:
            self.f.close()
            raise

    def close(self):
        self.f.close()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()

    def _read(self, n):
        if n < 0 or n > MAX_FILE_BYTES or self.f.tell() + n > self.size:
            raise AndiError('NetCDF offset/length exceeds file bounds')
        d = self.f.read(n)
        if len(d) != n:
            raise AndiError('Truncated NetCDF file')
        return d

    def _u32(self):
        return struct.unpack('>I', self._read(4))[0]

    def _u64(self):
        return struct.unpack('>Q', self._read(8))[0]

    def _nstring(self):
        n = self._u32()
        if n > NAME_MAX:
            raise AndiError('NetCDF name exceeds length limit')
        b = self._read(n)
        self._read((-n) % 4)
        try:
            return b.decode('utf-8')
        except UnicodeDecodeError as e:
            raise AndiError('Invalid NetCDF UTF-8 name') from e

    def _list_header(self, kind, maxcount):
        t = self._u32()
        count = self._u32()
        if t == 0 and count == 0:
            return 0
        if t != kind or count > maxcount:
            raise AndiError('Malformed NetCDF header list')
        return count

    def _attrs(self):
        count = self._list_header(12, MAX_VARS)
        res = {}
        for _ in range(count):
            name = self._nstring()
            tp = self._u32()
            n = self._u32()
            if name in res or tp not in TYPE_INFO:
                raise AndiError('Duplicate/unknown NetCDF attribute')
            width = TYPE_INFO[tp][1]
            total = n * width
            if total > MAX_META_BYTES:
                raise AndiError('NetCDF metadata field exceeds limit')
            raw = self._read(total)
            self._read((-total) % 4)
            if tp == 2:
                res[name] = raw
            else:
                values = _unpack(raw, tp)
                res[name] = values[0] if n == 1 else values
        return res

    def _header(self):
        magic = self._read(4)
        if magic not in (b'CDF\x01', b'CDF\x02'):
            if magic == b'CDF\x05':
                raise AndiError('NetCDF CDF-5 unsupported; this reader handles CDF-1/CDF-2')
            if magic == b'\x89HDF':
                raise AndiError('NetCDF-4/HDF5 source unsupported by classic NetCDF reader')
            raise AndiError('Not a NetCDF classic CDF-1/CDF-2 file')
        self.format = 'netcdf_classic' if magic[-1] == 1 else 'netcdf_64bit_offset'
        self.numrecs = self._u32()
        if self.numrecs == 0xffffffff:
            raise AndiError('Streaming/unfinalized NetCDF records are unsupported')
        for _ in range(self._list_header(10, MAX_DIMS)):
            name = self._nstring()
            size = self._u32()
            if any(n == name for n, _ in self.dimensions):
                raise AndiError('Duplicate NetCDF dimension')
            self.dimensions.append((name, size))
        unlimited = [i for i, (_, size) in enumerate(self.dimensions) if size == 0]
        if len(unlimited) > 1 or (unlimited and unlimited[0] != 0):
            raise AndiError('Invalid NetCDF unlimited dimension')
        self.attributes = self._attrs()
        for _ in range(self._list_header(11, MAX_VARS)):
            name = self._nstring()
            ndims = self._u32()
            if ndims > len(self.dimensions):
                raise AndiError('Invalid NetCDF variable dimension count')
            dimids = [self._u32() for _ in range(ndims)]
            if any(i >= len(self.dimensions) for i in dimids):
                raise AndiError('Invalid NetCDF dimension reference')
            attrs = self._attrs()
            tp = self._u32()
            vsize = self._u32()
            begin = self._u64() if self.format == 'netcdf_64bit_offset' else self._u32()
            if name in self.variables or tp not in TYPE_INFO:
                raise AndiError('Duplicate NetCDF variable or unsupported dtype')
            isrecord = bool(dimids and self.dimensions[dimids[0]][1] == 0)
            if 0 in [self.dimensions[i][1] for i in dimids[1:]]:
                raise AndiError('Unlimited NetCDF dimension must be first')
            shape = [self.numrecs if self.dimensions[i][1] == 0 else self.dimensions[i][1] for i in dimids]
            required = _prod(shape) * TYPE_INFO[tp][1]
            if required > MAX_FILE_BYTES:
                raise AndiError('Variable exceeds supported size')
            if not isrecord and begin + required > self.size:
                raise AndiError(f'Variable {name!r} exceeds file bounds')
            self.variables[name] = {'type': tp, 'shape': shape, 'dimids': dimids, 'attrs': attrs,
                                    'begin': begin, 'vsize': vsize, 'record': isrecord}
        header_end = self.f.tell()
        self.record_stride = sum(v['vsize'] for v in self.variables.values() if v['record'])
        for name, v in self.variables.items():
            if _prod(v['shape']) and v['begin'] < header_end:
                raise AndiError(f'Variable {name!r} overlaps NetCDF header')
            if v['record'] and self.numrecs:
                count_per = _prod(v['shape'][1:])
                width = TYPE_INFO[v['type']][1]
                if count_per * width > v['vsize']:
                    raise AndiError('Record variable exceeds stride allocation')
                end = v['begin'] + (self.numrecs - 1) * self.record_stride + count_per * width
                if end > self.size:
                    raise AndiError(f'Record variable {name!r} exceeds file bounds')

    def read_var(self, name, first=None, count=None):
        if name not in self.variables:
            raise AndiError(f'Missing NetCDF variable: {name}')
        v = self.variables[name]
        tp = v['type']
        total = _prod(v['shape'])
        if first is None:
            first = 0
        if count is None:
            count = total - first
        if first < 0 or count < 0 or first + count > total:
            raise AndiError('NetCDF variable read outside declared bounds')
        width = TYPE_INFO[tp][1]
        if v['record']:
            per = _prod(v['shape'][1:])
            chunks = []
            at = first
            remaining = count
            while remaining:
                rec, inner = divmod(at, per)
                take = min(remaining, per - inner)
                self.f.seek(v['begin'] + rec * self.record_stride + inner * width)
                chunks.append(self._read(take * width))
                at += take
                remaining -= take
            raw = b''.join(chunks)
        else:
            self.f.seek(v['begin'] + first * width)
            raw = self._read(count * width)
        if tp == 2:
            return raw
        return _unpack(raw, tp)


def _scalar(nc, name, default=None):
    if name not in nc.variables:
        return default
    v = nc.variables[name]
    if _prod(v['shape']) != 1 or v['type'] == 2:
        raise AndiError(f'Expected numeric scalar: {name}')
    value = nc.read_var(name)[0]
    if not math.isfinite(value):
        raise AndiError(f'Invalid nonfinite numeric scalar: {name}')
    return float(value)


def _time_scale(unit):
    u = unit.strip().lower().replace('.', '')
    if u in ('s', 'sec', 'secs', 'second', 'seconds'):
        return 1.
    if u in ('ms', 'msec', 'millisecond', 'milliseconds'):
        return .001
    if u in ('min', 'mins', 'minute', 'minutes', 'm'):
        return 60.
    if u in ('h', 'hr', 'hrs', 'hour', 'hours'):
        return 3600.
    raise AndiError(f'Unsupported retention_unit {unit!r}; refusing an ambiguous time scale')


def _finite_time(value):
    if not math.isfinite(value):
        raise AndiError('Computed retention time is nonfinite')
    return value


def _text_table(nc, name, length):
    v = nc.variables[name]
    if v['type'] != 2 or len(v['shape']) != 2 or v['shape'][0] != length:
        raise AndiError(f'Unexpected AIA character table layout: {name}')
    width = v['shape'][1]
    raw = nc.read_var(name)
    return [_clean(raw[i * width: (i + 1) * width]) for i in range(length)]


def _num_array(nc, name, length):
    v = nc.variables[name]
    if v['type'] == 2 or len(v['shape']) != 1 or v['shape'][0] != length:
        raise AndiError(f'Unexpected AIA numeric vector layout: {name}')
    vals = nc.read_var(name)
    if any(not math.isfinite(float(x)) or abs(float(x)) > 1e35 for x in vals):
        raise AndiError(f'Nonfinite / fill value in {name}: cannot safely import')
    return vals


class Chromatography:
    def __init__(self, nc):
        self.nc = nc
        if 'ordinate_values' not in nc.variables:
            if 'mass_values' in nc.variables or 'scan_acquisition_time' in nc.variables:
                raise AndiError('ANDI-MS spectral file, not ANDI-CHROM chromatogram; unsupported')
            raise AndiError('Not AIA/ANDI chromatography: ordinate_values is missing')
        v = nc.variables['ordinate_values']
        if v['type'] == 2 or len(v['shape']) != 1 or v['shape'][0] < 2:
            raise AndiError('AIA ordinate_values must be a numeric 1D vector of at least 2 values')
        self.n = v['shape'][0]
        self.flag = _clean(v['attrs'].get('uniform_sampling_flag', b'')).upper()
        self.time_unit = _clean(nc.attributes.get('retention_unit', b''))
        self.factor = _time_scale(self.time_unit)
        self.detector_unit = _clean(nc.attributes.get('detector_unit', b''))
        self.interval = _scalar(nc, 'actual_sampling_interval')
        self.delay = _scalar(nc, 'actual_delay_time')
        self.duration = _scalar(nc, 'actual_run_time_length')
        self.warnings = []
        if self.flag not in ('Y', 'N'):
            raise AndiError('AIA uniform_sampling_flag must be Y or N')
        if self.flag == 'Y':
            if self.interval is None or not math.isfinite(self.interval) or self.interval <= 0:
                raise AndiError('AIA uniform sampling requires positive actual_sampling_interval')
            if self.delay is None:
                raise AndiError('AIA uniform sampling requires an explicit actual_delay_time')
            self.time_basis = 'uniform_interval'
            if self.duration is not None and abs(self.duration - (self.n - 1) * self.interval) > max(2 * self.interval, .001):
                self.warnings.append('Run-time length differs from (N-1)*sampling interval; source timing values preserved without correction.')
        else:
            if 'raw_data_retention' not in nc.variables:
                raise AndiError('Nonuniform sampling requires raw_data_retention array')
            vret = nc.variables['raw_data_retention']
            if len(vret['shape']) != 1 or vret['shape'][0] != self.n or vret['type'] == 2:
                raise AndiError('Invalid nonuniform raw_data_retention shape')
            self.time_basis = 'explicit_retention'
        self.peak_count = nc.dimensions[[name for name, _ in nc.dimensions].index('peak_number')][1] if 'peak_number' in dict(nc.dimensions) else 0
        # An empty or absent peak table is a normal acquisition, not a failure.
        if 'peak_retention_time' not in nc.variables:
            self.peak_count = 0
        elif self.peak_count < 1:
            self.peak_count = nc.variables['peak_retention_time']['shape'][0]
        self.metadata = {
            'chromatography.format': 'aia_andi_chrom',
            'chromatography.netcdf_variant': nc.format,
            'chromatography.sample_count': str(self.n),
            'chromatography.uniform_sampling': self.flag,
            'chromatography.time_basis': self.time_basis,
            'chromatography.retention_unit_original': self.time_unit,
            'chromatography.detector_unit': self.detector_unit,
            'chromatography.peak_count': str(self.peak_count),
        }
        if self.interval is not None:
            self.metadata['chromatography.sampling_interval_native'] = repr(self.interval)
        if self.delay is not None:
            self.metadata['chromatography.delay_native'] = repr(self.delay)
        if self.duration is not None:
            self.metadata['chromatography.run_length_native'] = repr(self.duration)
        for original, target in {
            'detector_name': 'instrument.detector',
            'dataset_date_time_stamp': 'experimental.dataset_timestamp',
            'injection_date_time_stamp': 'experimental.injection_timestamp',
            'experiment_title': 'experimental.title',
            'sample_id': 'experimental.sample_id',
            'sample_name': 'experimental.sample_name',
            'sample_type': 'experimental.sample_type',
            'operator_name': 'experimental.operator',
            'company_method_name': 'experimental.method',
            'aia_template_revision': 'chromatography.aia_template_revision',
            'netcdf_revision': 'chromatography.netcdf_revision',
            'peak_amount_unit': 'chromatography.peak_amount_unit',
            'source_file_reference': 'chromatography.vendor_source_reference',
        }.items():
            if original in nc.attributes:
                self.metadata[target] = _clean(nc.attributes[original])[:2000]

    def time_values(self):
        if self.time_basis == 'uniform_interval':
            xs = (self.delay + i * self.interval for i in range(self.n))
        else:
            xs = _num_array(self.nc, 'raw_data_retention', self.n)
        last_native = last_seconds = -math.inf
        for x in xs:
            if self.time_basis == 'explicit_retention' and x <= last_native:
                raise AndiError('Nonuniform retention axis must be strictly increasing')
            last_native = x
            seconds = _finite_time(x * self.factor)
            if seconds <= last_seconds:
                raise AndiError('Computed retention axis must be strictly increasing; source precision cannot be preserved')
            last_seconds = seconds
            yield seconds

    def signal(self):
        return _num_array(self.nc, 'ordinate_values', self.n)

    def peaks(self):
        if not self.peak_count:
            return [], []
        n = self.peak_count
        x = _num_array(self.nc, 'peak_retention_time', n)
        columns = [
            ('peak_number', '1', 'int32', 'index', 'Peak number'),
            ('peak_retention_s', 's', 'float64', 'time', 'Peak retention time (s)'),
            ('peak_retention_min', 'min', 'float64', 'time', 'Peak retention time (min)'),
        ]
        data = [[i + 1, val * self.factor, val * self.factor / 60.] for i, val in enumerate(x)]
        options = [
            ('peak_name', '', 'string', 'label', 'Peak name', 1.),
            ('peak_start_time', 's', 'float64', 'time', 'Peak start (s)', self.factor),
            ('peak_end_time', 's', 'float64', 'time', 'Peak end (s)', self.factor),
            ('peak_area', '', 'float64', 'measured', 'Peak area (native)', 1.),
            ('peak_width', '', 'float64', 'measured', 'Peak width (native)', 1.),
            ('peak_area_percent', '', 'float64', 'measured', 'Peak area (%)', 1.),
            ('peak_height_percent', '', 'float64', 'measured', 'Peak height (%)', 1.),
            ('peak_height', self.detector_unit, 'float64', 'measured', 'Peak height', 1.),
            ('peak_amount', _clean(self.nc.attributes.get('peak_amount_unit', b'')), 'float64', 'measured', 'Peak amount', 1.),
            ('baseline_start_time', 's', 'float64', 'time', 'Baseline start (s)', self.factor),
            ('baseline_stop_time', 's', 'float64', 'time', 'Baseline stop (s)', self.factor),
            ('baseline_start_value', self.detector_unit, 'float64', 'measured', 'Baseline start value', 1.),
            ('baseline_stop_value', self.detector_unit, 'float64', 'measured', 'Baseline stop value', 1.),
        ]
        for name, unit, dtype, role, label, scale in options:
            if name not in self.nc.variables:
                continue
            try:
                values = (_text_table(self.nc, name, n) if dtype == 'string'
                          else _num_array(self.nc, name, n))
            except AndiError as e:
                self.warnings.append(f'Skipped optional peak field {name}: {e}')
                continue
            cname = name
            if name in ('peak_start_time', 'peak_end_time', 'baseline_start_time', 'baseline_stop_time'):
                cname = name.replace('_time', '_s')
            columns.append((cname, unit, dtype, role, label))
            for row, val in zip(data, values):
                row.append(val * scale if dtype != 'string' else val)
        return columns, data


def _b64(value):
    return base64.b64encode(str(value).encode('utf-8')).decode('ascii')


def _format_num(value):
    if isinstance(value, int):
        return str(value)
    return format(float(value), '.17g')


def _write_csv(path, columns, rows):
    # Only this helper writes the requested canonical payload; GX-TXT owns
    # all Dataset Registry and RAW resources.
    path = Path(path)
    if not path.parent.is_dir():
        raise AndiError('GX-TXT output directory does not exist')
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow([c[0] for c in columns])
        for row in rows:
            w.writerow([_format_num(val) if isinstance(val, (int, float)) else val for val in row])


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--input', required=True)
    p.add_argument('--mode', choices=('inspect', 'import'), required=True)
    p.add_argument('--trace-path')
    p.add_argument('--peaks-path')
    args = p.parse_args()
    if args.mode == 'import' and (not args.trace_path or not args.peaks_path):
        raise AndiError('Import mode requires two GX-TXT output paths')
    with NetCDFClassic(args.input) as nc:
        chrom = Chromatography(nc)
        trace_columns = [('time_s', 's', 'float64', 'time', 'Elapsed/retention time (s)'),
                         ('time_min', 'min', 'float64', 'time', 'Elapsed/retention time (min)'),
                         ('signal_value', chrom.detector_unit, 'float64', 'measured', 'Detector signal')]
        signal = chrom.signal() if args.mode == 'import' else nc.read_var('ordinate_values', 0, min(8, chrom.n))
        # Validate full timing axis in import; in preview uniform grid is directly computable.
        times = list(chrom.time_values()) if args.mode == 'import' else None
        peak_columns, peaks = chrom.peaks()
        if args.mode == 'import':
            if len(times) != len(signal):
                raise AndiError('Trace/time lengths differ')
            _write_csv(args.trace_path, trace_columns, ([t, t / 60., y] for t, y in zip(times, signal)))
            if peaks:
                _write_csv(args.peaks_path, peak_columns, peaks)
        print('GXANDI1')
        chrom.metadata['source.original_filename'] = os.path.basename(args.input)
        for key, val in chrom.metadata.items():
            print('M\t' + _b64(key) + '\t' + _b64(val))
        for warning in chrom.warnings:
            print('W\t' + _b64(warning))
        for kind, cols in [('T', trace_columns), ('K', peak_columns if peaks else [])]:
            for index, (name, unit, dtype, role, label) in enumerate(cols, 1):
                print('C\t' + kind + '\t' + str(index) + '\t' + '\t'.join(map(_b64, (name, unit, dtype, role, label))))
        if args.mode == 'inspect':
            # A preview can be deliberately small and need not allocate full trace.
            tiny = list(islice(chrom.time_values(), len(signal)))
            for x, y in zip(tiny, signal):
                print('P\t' + _b64(_format_num(x / 60.)) + '\t' + _b64(_format_num(y)))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (AndiError, OSError, struct.error, OverflowError, IndexError, KeyError) as exc:
        print('AIA/ANDI import: ' + str(exc), file=sys.stderr)
        sys.exit(2)
