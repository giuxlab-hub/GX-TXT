#!/usr/bin/env python3
"""Decode Metrohm IC Net 2.x CHW conductivity chromatograms.

Format inferred by cross-validation with seven instrument-produced AIA/ANDI
NetCDF and three text exports. Unsupported variants fail explicitly.
SPDX-License-Identifier: GPL-3.0-or-later
"""
from __future__ import annotations

import argparse
import base64
import csv
import math
import json
import re
import struct
import sys
from pathlib import Path

MAX_SIZE = 128 * 1024 * 1024
MAX_SAMPLES = 2_000_000
MAX_SECTIONS = 12
SIGNATURE = b"\xff\x26"
SECTION_SIZE = 16
TABLE_START = 8


class CHWError(ValueError):
    pass


def u32(data: bytes, pos: int) -> int:
    if pos < 0 or pos + 4 > len(data):
        raise CHWError("Truncated 32-bit field")
    return struct.unpack_from("<I", data, pos)[0]


def clean_text(data: bytes) -> str:
    return data.decode("cp1252", errors="replace").strip("\x00 \r\n\t")


def ascii_strings(data: bytes, min_length: int = 4) -> list[str]:
    return [clean_text(m.group()) for m in re.finditer(rb"[\x20-\x7e]{%d,}" % min_length, data)]


def parse_sections(data: bytes) -> dict[str, tuple[int, int]]:
    if len(data) < 298 or data[:2] != SIGNATURE:
        raise CHWError("Unrecognized or truncated Metrohm IC Net CHW header")
    sections: dict[str, tuple[int, int]] = {}
    entries = []
    for i in range(MAX_SECTIONS + 1):
        p = TABLE_START + SECTION_SIZE * i
        if p + 16 > 298:
            raise CHWError("Section directory exceeds header")
        section_code = struct.unpack_from("<H", data, p)[0]
        start, length, _ = struct.unpack_from("<III", data, p + 2)
        if section_code == 0:
            break
        if section_code != 12 and (section_code > 127 or chr(section_code) not in "ABCDEFGHIJKLMNOPQRSTUVWXYZ"):
            raise CHWError("Unrecognized CHW section code")
        name = "header12" if section_code == 12 else chr(section_code)
        if name in sections:
            raise CHWError("Duplicate CHW section code: " + name)
        if start == length == 0 and name == "Y":
            break
        if start < 298 or length <= 0 or start + length > len(data):
            raise CHWError("Invalid CHW section bounds: " + name)
        sections[name] = (start, length)
        entries.append((start, start + length, name))
    else:
        raise CHWError("No valid end of CHW directory")
    if not entries or not all(name in sections for name in ("S", "T")):
        raise CHWError("Required signal and trace sections are absent")
    entries.sort()
    for prev, curr in zip(entries, entries[1:]):
        if prev[1] > curr[0]:
            raise CHWError("Overlapping CHW sections: " + prev[2] + ", " + curr[2])
    if entries[-1][1] != len(data):
        raise CHWError("CHW section directory does not account for complete file")
    return sections


def decode_trace(trace: bytes, sample_count: int) -> tuple[list[int], dict]:
    """Decode CHW trace exactly as signed ADC integers (no float rounding)."""
    if len(trace) < 14 or u32(trace, 0) != 4 * sample_count:
        raise CHWError("CHW trace byte count disagrees with signal descriptor")
    expected_blocks = u32(trace, 4)
    if not (1 <= expected_blocks <= sample_count):
        raise CHWError("Invalid CHW trace block count")
    current = struct.unpack_from("<i", trace, 8)[0]
    points = [current]
    cursor = 12
    modes = {0: 0, 3: 0, 4: 0, 5: 0}
    for block in range(expected_blocks):
        if cursor + 2 > len(trace):
            raise CHWError("Truncated CHW run header")
        header = struct.unpack_from("<H", trace, cursor)[0]
        cursor += 2
        length = header >> 4
        mode = header & 15
        if length == 0 or mode not in modes:
            raise CHWError(f"Unsupported CHW compression block {block}: length={length}, mode={mode}")
        if len(points) + length > sample_count:
            raise CHWError("CHW run extends beyond declared sample count")
        width = {0: 0, 3: 1, 4: 2, 5: 4}[mode]
        if cursor + width * length > len(trace):
            raise CHWError("Truncated CHW compressed run")
        modes[mode] += 1
        if mode == 0:
            points.extend([current] * length)
        else:
            for _ in range(length):
                delta = int.from_bytes(trace[cursor:cursor + width], "little", signed=True)
                cursor += width
                current += delta
                if not (-2**31 <= current < 2**31):
                    raise CHWError("ADC cumulative value exceeds signed 32-bit range")
                points.append(current)
    if cursor != len(trace) or len(points) != sample_count:
        raise CHWError("CHW compressed trace has extra bytes or incomplete samples")
    return points, {"block_count": expected_blocks, "mode_counts": modes}


def write_signal_csv(path: Path, values: list[int], sample_interval: float, adc_step: float) -> None:
    """Write framework-owned canonical CSV; no edits to source or RAW."""
    if not path.parent.is_dir() or path.exists():
        raise CHWError("Canonical output directory must exist; target must not be overwritten")
    # Remove only an incomplete file that this invocation actually created.
    # An existing target is never overwritten or removed.
    created = False
    try:
        with path.open("x", newline="", encoding="utf-8") as handle:
            created = True
            writer = csv.writer(handle, lineterminator="\n")
            writer.writerow(["time_s", "time_min", "signal_value", "adc_count"])
            for index, adc in enumerate(values):
                sec = index * sample_interval
                writer.writerow([format(sec, ".15g"), format(sec / 60, ".15g"),
                                 format(adc * adc_step, ".15g"), adc])
    except BaseException:
        if created:
            path.unlink(missing_ok=True)
        raise


def analyze(data: bytes, filename: str = "", decoded_values: list[int] | None = None) -> dict:
    if len(data) > MAX_SIZE:
        raise CHWError("CHW file exceeds bounded inspection limit")
    sections = parse_sections(data)

    def sec(code: str) -> bytes:
        if code not in sections:
            return b""
        o, n = sections[code]
        return data[o:o+n]

    meta = sec("header12")
    paths = sec("H")
    source_hints = meta + b"\x00" + paths
    full_str = ascii_strings(source_hints, 4)
    model = next((s for s in full_str if re.fullmatch(r"\d{3}\s+[^\\/\x00]{1,50}IC", s)), "")
    soft = re.search(rb"IC Net\s+(\d+(?:\.\d+)?)", source_hints, re.I)
    method = next((s.rsplit('\\', 1)[-1] for s in full_str if s.lower().endswith(".mtw")), "")
    column = next((s for s in full_str if "METROSEP" in s.upper()), "")

    s = sec("S")
    if len(s) != 72:
        raise CHWError("Unvalidated signal descriptor variant (S section length is not 72)")
    channel = clean_text(s[:9].split(b"\x00", 1)[0])
    unit = clean_text(s[9:17].split(b"\x00", 1)[0])
    if not channel or not unit:
        raise CHWError("Invalid channel or unit label in signal descriptor")
    sample_count = u32(s, 46)
    dt = struct.unpack_from("<f", s, 68)[0]
    if not (0 < sample_count <= MAX_SAMPLES and 0 < dt < 3600):
        raise CHWError("Invalid acquisition count or sampling interval")
    # The signal descriptor stores the physical ADC step as LE float32 at S+18.
    # Read from the file: do not hardcode the 1e-5 step observed in fixtures.
    adc_step = struct.unpack_from("<f", s, 18)[0]
    if not (math.isfinite(adc_step) and adc_step > 0.0):
        raise CHWError("Unrecognized or invalid CHW ADC scale")
    trace = sec("T")
    values, coding = decode_trace(trace, sample_count)
    if decoded_values is not None:
        decoded_values.extend(values)
    warnings = [
        "CHW compression decoder validated on seven IC Net 2.3 conductivity files; other vendor versions and instruments require individual validation.",
        "Raw CHW integration labels may be absent even when the CDF exporter supplies names from the method.",
    ]

    peaks: list[dict] = []
    d = sec("D")
    # Observed fixture: 32-byte prefix, 32-byte records containing 3 LE uint32
    # point positions. This record layout is only a provisional interpretation.
    if d:
        if len(d) < 32 or (len(d) - 32) % 32:
            warnings.append("Unknown integration section record layout; peaks not decoded.")
        else:
            for j in range((len(d) - 32) // 32):
                start, apex, end = struct.unpack_from("<III", d, 32 + j * 32)
                if not (0 <= start <= apex <= end < sample_count):
                    peaks = []
                    warnings.append("Peak-point bounds are inconsistent; all peak records ignored.")
                    break
                peaks.append(dict(number=j+1, start_point=start, apex_point=apex,
                                  end_point=end, approx_retention_min=apex*dt/60))

    # Provenance for component assignment is explicit in the U audit log.
    log = sec("U").decode("cp1252", errors="replace")
    for peak in peaks:
        rx = rf"\t([^\t\r\n]{{1,80}})\t\tChromatogram\\Peaks\\# {peak['number']}\\component"
        m = re.search(rx, log)
        if m:
            peak["component"] = m.group(1).rsplit("\t", 1)[-1].strip()
        else:
            peak["component"] = ""
    # The sample time is audit-logged separately from the analysis timestamps.
    tm = re.search(r"(\d{2}:\d{2}:\d{2}(?:\.\d+)?)\t[^\x00\r\n]{0,50}Chromatogram\\Sample\\sample time", log)
    sample_time = tm.group(1) if tm else ""
    file_date = re.search(r"(20\d{2}-\d{2}-\d{2})", filename)

    metadata = {
        "source.original_filename": filename,
        "source.file_size_bytes": str(len(data)),
        "chromatography.format": "metrohm.icnet.chw",
        "chromatography.signal_decode_status": "decoded_integer_exact",
        "chromatography.adc_step_raw_float32": format(adc_step, ".17g"),
        "chromatography.trace_block_count": str(coding["block_count"]),
        "chromatography.trace_mode_counts": ";".join(f"{k}:{v}" for k,v in coding["mode_counts"].items()),
        "chromatography.declared_sample_count": str(sample_count),
        "chromatography.sample_interval_s": format(dt, ".17g"),
        "chromatography.trace_payload_bytes": str(len(trace)),
        "chromatography.unpacked_trace_bytes": str(u32(trace, 0)),
        "chromatography.integration_peak_count": str(len(peaks)),
        "chromatography.signal_channel": channel,
        "chromatography.signal_unit": unit,
        "chromatography.section_ids": ";".join(sections),
    }
    if soft:
        metadata["instrument.software"] = "IC Net " + soft.group(1).decode("ascii")
    if model:
        metadata["instrument.model"] = model
    if method:
        metadata["chromatography.method_filename"] = method
    if column:
        metadata["chromatography.column_description"] = column
    if sample_time:
        metadata["chromatography.sample_time_local"] = sample_time
    if file_date:
        metadata["chromatography.filename_date"] = file_date.group(1)
    return {"metadata": metadata, "warnings": warnings, "peaks": peaks,
            "signal": {"count": len(values), "first_adc": values[0], "last_adc": values[-1],
                       "minimum_adc": min(values), "maximum_adc": max(values),
                       "first_12_adc": values[:12]},
            "sections": {k: {"offset": o, "length": n} for k, (o, n) in sections.items()}}


def analyze_file(path: Path) -> dict:
    if not path.is_file():
        raise CHWError("Input path is not an existing file")
    if path.stat().st_size > MAX_SIZE:
        raise CHWError("CHW file exceeds bounded inspection limit")
    return analyze(path.read_bytes(), filename=path.name)


def protocol(results: dict) -> str:
    def b64(v: str) -> str:
        return base64.b64encode(v.encode("utf-8")).decode("ascii")
    output = ["GXCHW1"]
    for k, v in sorted(results["metadata"].items()):
        output.append("M\t" + b64(k) + "\t" + b64(v))
    for w in results["warnings"]:
        output.append("W\t" + b64(w))
    for p in results["peaks"]:
        output.append("P\t" + "\t".join([
            str(p["number"]), str(p["start_point"]), str(p["apex_point"]),
            str(p["end_point"]), format(p["approx_retention_min"], ".12g"),
            b64(p.get("component", ""))]))
    return "\n".join(output) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--input", type=Path, required=True)
    ap.add_argument("--output", choices=["json", "protocol"], default="json")
    ap.add_argument("--csv-output", type=Path, help="Write complete canonical signal CSV in framework-owned directory")
    args = ap.parse_args()
    try:
        # One file read and one trace decode supply both metadata and CSV output.
        if not args.input.is_file() or args.input.stat().st_size > MAX_SIZE:
            raise CHWError("Input source is absent or exceeds the CHW inspection limit")
        raw = args.input.read_bytes()
        decoded_values = [] if args.csv_output is not None else None
        info = analyze(raw, filename=args.input.name, decoded_values=decoded_values)
        if args.csv_output is not None:
            md = info["metadata"]
            write_signal_csv(args.csv_output, decoded_values,
                             float(md["chromatography.sample_interval_s"]),
                             float(md["chromatography.adc_step_raw_float32"]))
    except (CHWError, OSError) as exc:
        print("CHW inspection failed: " + str(exc), file=sys.stderr)
        return 2
    if args.output == "json":
        print(json.dumps(info, ensure_ascii=False, indent=2))
    else:
        sys.stdout.write(protocol(info))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
