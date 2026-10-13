#!/usr/bin/env python3
"""Read-only CORE GXSRL fast ranking for the IR module's simple preprocessing path."""
from __future__ import annotations

import argparse
import json
import math
import sqlite3
import sys
from pathlib import Path

import numpy as np


def finite_float(value: str) -> float:
    number = float(value)
    if not math.isfinite(number):
        raise ValueError('non-finite matching option')
    return number


def vector(payload: bytes) -> np.ndarray:
    if len(payload) % 8:
        raise ValueError('invalid GXSRL numeric payload')
    return np.frombuffer(payload, dtype='<f8')


def process(x: np.ndarray, y: np.ndarray, representation: str, y_unit: str,
            low: float, high: float, normalization: str) -> tuple[np.ndarray, np.ndarray]:
    if len(x) != len(y) or len(x) < 8 or not np.isfinite(x).all() or not np.isfinite(y).all():
        raise ValueError('invalid reference samples')
    if x[0] > x[-1]:
        x = x[::-1]
        y = y[::-1]
    if not np.all(np.diff(x) > 0):
        raise ValueError('reference X is not strictly monotonic')
    if representation == 'transmittance':
        representation = 'transmittance_percent' if y_unit == '%' else 'transmittance_fraction'
    if representation in ('relative_transmission_signal', 'transmission_signal'):
        y = np.max(y) - y
    elif representation == 'absorbance':
        y = y.copy()
    elif representation == 'absorption_index':
        if np.any(y < 0):
            raise ValueError('negative absorption index')
        y = y.copy()
    elif representation == 'transmittance_fraction':
        if np.any(y <= 0) or np.any(y > 1):
            raise ValueError('invalid transmittance fraction')
        y = -np.log10(y)
    elif representation == 'transmittance_percent':
        if np.any(y <= 0) or np.any(y > 100):
            raise ValueError('invalid transmittance percent')
        y = -np.log10(y / 100)
    else:
        raise ValueError('unsupported reference ordinate')
    chosen = (x >= low) & (x <= high)
    x = x[chosen]
    y = y[chosen]
    if len(x) < 8:
        raise ValueError('reference has insufficient selected points')
    if normalization == 'mean_center_unit_vector':
        y = y - np.mean(y)
    elif normalization != 'unit_vector':
        raise ValueError('unsupported normalization')
    length = np.linalg.norm(y)
    if length <= 0:
        raise ValueError('zero-variation reference')
    return x, y / length


def score(a: np.ndarray, b: np.ndarray, method: str) -> float:
    if method == 'pearson':
        a = a - np.mean(a)
        b = b - np.mean(b)
    aa = float(np.dot(a, a))
    bb = float(np.dot(b, b))
    if aa <= 0 or bb <= 0:
        return -1.0
    cosine = float(np.dot(a, b) / math.sqrt(aa * bb))
    if method in ('cosine', 'pearson'):
        return cosine
    if method == 'spectral_angle':
        return 1.0 - math.acos(max(-1.0, min(1.0, cosine))) / math.pi
    if method == 'normalized_residual':
        residual = float(np.dot(a - b, a - b))
        return 1.0 / (1.0 + math.sqrt(residual / aa))
    raise ValueError('unsupported score method')


def run(args: argparse.Namespace) -> tuple[int, int, list[tuple[float, str, float, float]]]:
    experimental = np.loadtxt(args.experimental, delimiter='\t', dtype=np.float64, ndmin=2)
    if experimental.shape[1] != 2:
        raise ValueError('experimental table needs exactly X and Y')
    ex = experimental[:, 0]
    ey = experimental[:, 1]
    if len(ex) < 8 or not np.all(np.diff(ex) > 0) or not np.isfinite(ex).all() or not np.isfinite(ey).all():
        raise ValueError('processed experimental spectrum is invalid')
    connection = sqlite3.connect(f'file:{args.library.resolve()}?mode=ro', uri=True)
    connection.execute('pragma query_only=ON')
    total = 0
    skipped = 0
    results: list[tuple[float, str, float, float]] = []
    query = 'select spectrum_id, fields_json, x_payload, y_payload from spectra order by spectrum_id'
    for sid, field_text, xb, yb in connection.execute(query):
        total += 1
        fields = json.loads(field_text)
        if fields.get('spectrum_kind') != 'IR' or fields.get('x_unit') != 'cm^-1':
            skipped += 1
            continue
        representation = fields.get('y_representation', '')
        if (args.experimental_representation == 'absorption_index') != (representation == 'absorption_index'):
            skipped += 1
            continue
        try:
            rx, ry = process(vector(xb), vector(yb), representation, fields.get('y_unit', ''),
                             args.range_min, args.range_max, args.normalization)
            low = max(ex[0], rx[0])
            high = min(ex[-1], rx[-1])
            n = math.floor((high - low) / args.step) + 1
            if n < 16 or n > 20000:
                raise ValueError('common grid invalid')
            target = low + args.step * np.arange(n)
            a = np.interp(target, ex, ey)
            b = np.interp(target, rx, ry)
            full = score(a, b, args.method)
            fingerprint = (target >= args.fingerprint_min) & (target <= args.fingerprint_max)
            fp = score(a[fingerprint], b[fingerprint], args.method) if fingerprint.sum() >= 16 else full
            combined = (1 - args.fingerprint_weight) * full + args.fingerprint_weight * fp
            if not math.isfinite(combined):
                raise ValueError('non-finite score')
            results.append((combined, sid, full, fp))
        except (ValueError, KeyError, OverflowError):
            skipped += 1
    results.sort(key=lambda item: (-item[0], item[1]))
    return total, skipped, results[:args.limit]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--library', type=Path, required=True)
    parser.add_argument('--experimental', type=Path, required=True)
    parser.add_argument('--experimental-representation', required=True)
    parser.add_argument('--range-min', type=finite_float, required=True)
    parser.add_argument('--range-max', type=finite_float, required=True)
    parser.add_argument('--normalization', required=True, choices=('unit_vector', 'mean_center_unit_vector'))
    parser.add_argument('--step', type=finite_float, required=True)
    parser.add_argument('--method', required=True, choices=('cosine', 'pearson', 'spectral_angle', 'normalized_residual'))
    parser.add_argument('--fingerprint-min', type=finite_float, required=True)
    parser.add_argument('--fingerprint-max', type=finite_float, required=True)
    parser.add_argument('--fingerprint-weight', type=finite_float, required=True)
    parser.add_argument('--limit', type=int, required=True)
    args = parser.parse_args()
    if args.range_max <= args.range_min or args.step <= 0 or args.fingerprint_max <= args.fingerprint_min or not 0 <= args.fingerprint_weight <= 1 or args.limit < 1:
        raise ValueError('invalid ranking range/weight/limit')
    total, skipped, candidates = run(args)
    print(f'SUMMARY\t{total}\t{skipped}')
    for combined, sid, full, fingerprint in candidates:
        print(f'CANDIDATE\t{sid}\t{combined:.17g}\t{full:.17g}\t{fingerprint:.17g}')


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(f'CORE bulk rank error: {exc}', file=sys.stderr)
        raise SystemExit(1)
