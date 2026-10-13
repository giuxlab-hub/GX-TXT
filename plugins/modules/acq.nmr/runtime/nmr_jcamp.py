#!/usr/bin/env python3
"""Import one-dimensional Bruker JCAMP-DX NTUPLES NMR data.

The decoder supports AFFN, SQZ, DIF and DUP records. It rejects unsupported
multidimensional pages instead of silently flattening them.
"""
from __future__ import annotations

import argparse
import base64
import csv
import hashlib
import json
import math
import re
from pathlib import Path

import numpy as np

SQZ = {"@": 0, **{chr(ord("A") + i - 1): i for i in range(1, 10)},
       **{chr(ord("a") + i - 1): -i for i in range(1, 10)}}
DIF = {"%": 0, **{chr(ord("J") + i - 1): i for i in range(1, 10)},
       **{chr(ord("j") + i - 1): -i for i in range(1, 10)}}
DUP = {**{chr(ord("S") + i - 1): i for i in range(1, 9)}, "s": 9}
TOKEN = re.compile(r"([@A-Ia-i%J-Rj-rS-Zs]|[+-])([0-9.]*)")


def decode_line(line: str, previous: int | None) -> tuple[int, list[int], int]:
    match = re.match(r"\s*([+-]?\d+(?:\.\d+)?)(.*)", line)
    if not match:
        raise ValueError(f"Invalid JCAMP data record: {line[:70]}")
    x = int(float(match.group(1)))
    payload = match.group(2).strip().replace(",", " ")
    values: list[int] = []
    last_difference = None
    pos = 0
    for token in TOKEN.finditer(payload):
        if payload[pos:token.start()].strip():
            raise ValueError(f"Unsupported JCAMP numeric encoding near {payload[pos:token.start()]!r}")
        pos = token.end()
        marker, digits = token.groups()
        if marker in DUP:
            if last_difference is None or previous is None:
                raise ValueError("JCAMP DUP without preceding difference")
            count = int(str(DUP[marker]) + digits)
            if count > 1000000:
                raise ValueError("JCAMP duplicate run is too large")
            for _ in range(count - 1):
                previous += last_difference
                values.append(previous)
            continue
        if marker in SQZ:
            lead = SQZ[marker]
            value = int(("-" if lead < 0 else "") + str(abs(lead)) + digits)
            last_difference = None
        elif marker in DIF:
            if previous is None:
                raise ValueError("JCAMP DIF without preceding ordinate")
            lead = DIF[marker]
            difference = int(("-" if lead < 0 else "") + str(abs(lead)) + digits)
            value = previous + difference
            last_difference = difference
        else:
            value = int(marker + digits)
            last_difference = None
        values.append(value)
        previous = value
    if payload[pos:].strip():
        raise ValueError(f"Unsupported JCAMP data token: {payload[pos:]!r}")
    return x, values, previous if previous is not None else 0


def _header_and_pages(path: Path):
    text = path.read_bytes().decode("latin-1")
    header = {}
    pages = []
    current = None
    in_table = False
    for line in text.splitlines():
        if line.startswith("##"):
            in_table = False
            match = re.match(r"##([^=]+)=\s*(.*)", line)
            if not match:
                continue
            key, value = match.groups()
            key = key.strip().upper()
            if key == "DATA TABLE":
                current = []
                pages.append(current)
                in_table = True
            elif key not in header:
                header[key] = value.strip()
        elif in_table and current is not None and line.strip() and not line.lstrip().startswith("$$"):
            current.append(line.strip())
    if "NTUPLES" not in header or len(pages) != 2:
        raise ValueError("Only one-dimensional two-page NMR NTUPLES are supported")
    return header, pages


def _decode_page(lines: list[str], expected: int) -> np.ndarray:
    result = []
    previous = None
    reverse = None
    for line in lines:
        x, vals, previous = decode_line(line, previous)
        if reverse is None:
            reverse = x == expected - 1
            if not reverse and x != 0:
                raise ValueError(f"JCAMP first point index {x} is invalid")
        position = expected - 1 - x if reverse else x
        # Bruker records identify each 1-D point by integer index. A record's
        # final ordinate may be repeated as the next record's checkpoint.
        if position == len(result) - 1 and vals:
            vals = vals[1:]
        elif position != len(result):
            raise ValueError(f"JCAMP point-index discontinuity: {x} vs {len(result)}")
        result.extend(vals)
    if len(result) != expected:
        raise ValueError(f"JCAMP point count mismatch: {len(result)} vs {expected}")
    return np.asarray(result, dtype=np.float64)


def read_nmr(path: Path):
    header, pages = _header_and_pages(path)
    data_type = header.get("DATA TYPE", "").upper()
    if data_type not in ("NMR FID", "NMR SPECTRUM"):
        raise ValueError(f"Unsupported NMR data type: {data_type}")
    dimensions = [int(x.strip()) for x in header["VAR_DIM"].split(",")]
    if len(dimensions) != 3 or len(set(dimensions)) != 1:
        raise ValueError("The NMR importer requires a one-dimensional real/imaginary pair")
    factors = [float(x.strip()) for x in header["FACTOR"].split(",")]
    first = [float(x.strip()) for x in header["FIRST"].split(",")]
    last = [float(x.strip()) for x in header["LAST"].split(",")]
    real = _decode_page(pages[0], dimensions[0]) * factors[1]
    imag = _decode_page(pages[1], dimensions[0]) * factors[2]
    x = np.linspace(first[0], last[0], dimensions[0]);
    return header, x, real + 1j * imag


def processed_spectrum(header: dict, x: np.ndarray, signal: np.ndarray,
                       zero_fill: int = 4, line_broadening_hz: float = 2.0,
                       phase_deg: float = 0.0):
    kind = header["DATA TYPE"].upper()
    frequency_mhz = float(header[".OBSERVE FREQUENCY"])
    if kind == "NMR SPECTRUM":
        # Bruker processed frequency axis is relative to the spectrum's left
        # edge; OFFSET is its ppm position, while SF is the processed carrier.
        if "$OFFSET" not in header or "$SF" not in header:
            raise ValueError("Processed NMR spectrum lacks OFFSET/SF for ppm conversion")
        offset = float(header["$OFFSET"])
        ppm = offset - (x[0] - x) / float(header["$SF"])
        return ppm, signal.real, {"processing": "already_processed", "reference_offset_ppm": offset}
    dwell = x[1] - x[0]
    if dwell <= 0 or not math.isfinite(dwell):
        raise ValueError("FID dwell time is invalid")
    count = len(signal)
    size = int(2 ** math.ceil(math.log2(max(count, count * zero_fill))))
    window = np.exp(-math.pi * line_broadening_hz * x)
    transformed = np.fft.fftshift(np.fft.fft(signal * window, n=size))
    transformed *= np.exp(1j * math.radians(phase_deg))
    # Bruker O1 and BF1 identify the transmitter; the ppm shift from that
    # carrier is spectral offset in Hz divided by the observation frequency.
    o1 = float(header["$O1"])
    bf1 = float(header["$BF1"])
    ppm = o1 / bf1 + np.fft.fftshift(np.fft.fftfreq(size, d=dwell)) / frequency_mhz
    return ppm, transformed.real, {"processing": "fid_fft", "window": "exponential",
        "line_broadening_hz": line_broadening_hz, "zero_fill_factor": zero_fill,
        "fft_points": size, "phase_deg": phase_deg, "dwell_seconds": dwell,
        "carrier_hz": o1, "base_frequency_mhz": bf1}


def inspect(path: Path):
    header, pages = _header_and_pages(path)
    dimensions = [int(x.strip()) for x in header["VAR_DIM"].split(",")]
    return {"format": "jcamp-dx.nmr.ntuple", "data_type": header.get("DATA TYPE", ""),
            "nucleus": header.get(".OBSERVE NUCLEUS", ""),
            "observed_frequency_mhz": header.get(".OBSERVE FREQUENCY", ""),
            "solvent": header.get(".SOLVENT NAME", ""),
            "shift_reference": header.get(".SHIFT REFERENCE", ""),
            "source_phase0_deg": header.get("$PHC0", ""),
            "source_phase1_deg": header.get("$PHC1", ""),
            "source_line_broadening_hz": header.get("$LB", ""),
            "source_offset_ppm": header.get("$OFFSET", ""),
            "source_acquisition_date": header.get("LONG DATE", ""),
            "source_pulse_sequence": header.get(".PULSE SEQUENCE", ""),
            "source_averages": header.get(".AVERAGES", ""),
            "source_instrument": header.get("SPECTROMETER/DATA SYSTEM", ""),
            "title": header.get("TITLE", "").splitlines()[0],
            "sample_count": dimensions[0], "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def convert(path: Path, output: Path, **processing):
    header, x, signal = read_nmr(path)
    ppm, y, params = processed_spectrum(header, x, signal, **processing)
    if not np.all(np.isfinite(ppm)) or not np.all(np.isfinite(y)):
        raise ValueError("Non-finite NMR data")
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(["spectral_x", "spectral_y"])
        writer.writerows((f"{a:.12g}", f"{b:.12g}") for a,b in zip(ppm,y))
    return {**inspect(path), **params, "ppm_min": float(np.min(ppm)),
            "ppm_max": float(np.max(ppm)), "output_points": len(ppm),
            "output_sha256": hashlib.sha256(output.read_bytes()).hexdigest()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("inspect", "convert"))
    parser.add_argument("source", type=Path)
    parser.add_argument("output", nargs="?", type=Path)
    parser.add_argument("--zero-fill", type=int, default=4)
    parser.add_argument("--line-broadening-hz", type=float, default=2.0)
    parser.add_argument("--phase-deg", type=float, default=0.0)
    parser.add_argument("--kv", action="store_true", help="emit base64 key/value records for Tcl")
    args = parser.parse_args()
    if args.mode == "inspect":
        info = inspect(args.source)
    else:
        if args.output is None: parser.error("convert requires output")
        info = convert(args.source, args.output, zero_fill=args.zero_fill,
                       line_broadening_hz=args.line_broadening_hz, phase_deg=args.phase_deg)
    if args.kv:
        for key, value in sorted(info.items()):
            encoded = base64.b64encode(str(value).encode("utf-8")).decode("ascii")
            print(f"{key}\t{encoded}")
    else:
        print(json.dumps(info, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
