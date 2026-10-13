#!/usr/bin/env python3
"""GX-TXT CORE generic CSV and JCAMP-DX spectrum parser.

Scientific semantics for CSV are mandatory caller choices. JCAMP semantics are
read from declared headers; unsupported encodings fail explicitly.
"""
from __future__ import annotations

import base64
import csv
import hashlib
import itertools
import math
from pathlib import Path
import re
import sys


def fail(message: str) -> None:
    raise ValueError(message)


def b64(value: str) -> str:
    return base64.b64encode(str(value).encode("utf-8")).decode("ascii")


def unb64(value: str) -> str:
    return base64.b64decode(value.encode("ascii"), validate=True).decode("utf-8")


def read_options(path: str):
    fields, metadata, provenance = {}, {}, {}
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        parts = line.split("\t")
        if len(parts) != 3 or parts[0] not in {"F", "M", "P"}:
            fail("invalid parser options wire file")
        {"F": fields, "M": metadata, "P": provenance}[parts[0]][unb64(parts[1])] = unb64(parts[2])
    return fields, metadata, provenance


def emit(fields, metadata, provenance, pairs):
    for prefix, mapping in (("F", fields), ("M", metadata), ("P", provenance)):
        for key, value in sorted(mapping.items()):
            print(f"{prefix}\t{b64(key)}\t{b64(value)}")
    for x, y in pairs:
        print(f"D\t{x:.17g}\t{y:.17g}")


def source_sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def finite_float(value: str, label: str) -> float:
    try:
        number = float(value)
    except ValueError:
        fail(f"{label} is not numeric: {value!r}")
    if not math.isfinite(number):
        fail(f"{label} is not finite: {value!r}")
    return number


def required(fields: dict, key: str) -> str:
    value = fields.get(key, "").strip()
    if not value:
        fail(f"{key} is required")
    return value


def make_base(path: Path, options: dict, source_format: str):
    fields = {
        key: required(options, key)
        for key in ("spectrum_id", "display_name", "spectrum_kind", "x_quantity",
                    "x_unit", "y_quantity", "y_representation", "y_unit")
    }
    fields["entity_id"] = options.get("entity_id", "")
    fields["source_identity"] = options.get("source_identity", str(path.resolve()))
    fields["source_hash"] = source_sha(path)
    provenance = {"source_format": source_format, "parser": "GX-TXT Scientific Spectrum Import v1",
                  "source_filename": path.name, "source_sha256": fields["source_hash"]}
    return fields, provenance


def column_index(value: str, headers: list[str], header: bool) -> int:
    if value.isdigit():
        index = int(value) - 1
    elif header:
        if value not in headers:
            fail(f"CSV column not found: {value}")
        index = headers.index(value)
    else:
        fail("CSV columns must be 1-based indices when header=0")
    if index < 0 or index >= len(headers):
        fail(f"CSV column outside available range: {value}")
    return index


def parse_csv(path: Path, options: dict, metadata: dict, provenance: dict):
    x_col = required(options, "x_column")
    y_col = required(options, "y_column")
    header = options.get("header", "1").lower() in {"1", "true", "yes"}
    delimiter = options.get("delimiter", "auto")
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        if delimiter == "auto":
            sample = stream.read(4096)
            stream.seek(0)
            try:
                delimiter = csv.Sniffer().sniff(sample, delimiters=",;\t").delimiter
            except csv.Error:
                fail("could not detect CSV delimiter; specify delimiter explicitly")
        elif delimiter == "tab":
            delimiter = "\t"
        if delimiter not in {",", ";", "\t"}:
            fail("CSV delimiter must be comma, semicolon or tab")
        reader = csv.reader(stream, delimiter=delimiter)
        try:
            first = next(reader)
        except StopIteration:
            fail("CSV file is empty")
        headers = first if header else [str(i) for i in range(1, len(first) + 1)]
        xi, yi = column_index(x_col, headers, header), column_index(y_col, headers, header)
        rows = reader if header else itertools.chain([first], reader)
        pairs = []
        for line_number, row in enumerate(rows, start=2 if header else 1):
            if not row or all(not cell.strip() for cell in row):
                continue
            if max(xi, yi) >= len(row):
                fail(f"CSV row {line_number} has too few columns")
            pairs.append((finite_float(row[xi].strip(), f"CSV X row {line_number}"),
                          finite_float(row[yi].strip(), f"CSV Y row {line_number}")))
    if len(pairs) < 2:
        fail("CSV spectrum needs at least two samples")
    fields, automatic = make_base(path, options, "CSV")
    metadata = {**metadata, "source_x_column": x_col, "source_y_column": y_col,
                "source_delimiter": "tab" if delimiter == "\t" else delimiter,
                "source_header": str(int(header))}
    return fields, metadata, {**automatic, **provenance}, pairs


def read_jcamp(path: Path):
    text = path.read_text(encoding="latin-1")
    headers: dict[str, str] = {}
    data_tag = ""
    data_lines = []
    collecting = False
    last_key = ""
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("##"):
            collecting = False
            if "=" not in line:
                continue
            key, value = line[2:].split("=", 1)
            key = key.strip().upper()
            value = value.strip()
            if key in {"XYDATA", "PEAK TABLE", "XYPOINTS"}:
                if data_tag:
                    fail("multi-block JCAMP files require explicit block selection")
                data_tag = key
                headers[key] = value
                collecting = True
            else:
                headers[key] = value
                last_key = key
            continue
        if collecting:
            if line and not line.startswith("$$"):
                data_lines.append(line)
        elif last_key and line and not line.startswith("$$"):
            headers[last_key] += "\n" + line
    if not data_tag or not data_lines:
        fail("JCAMP has no supported numerical data block")
    return headers, data_tag, data_lines


def jcamp_units(headers):
    x_raw = headers.get("XUNITS", "").upper().replace(" ", "")
    y_raw = headers.get("YUNITS", "").upper().replace(" ", "")
    x_map = {"1/CM": ("wavenumber", "cm^-1"), "CM-1": ("wavenumber", "cm^-1"),
             "NM": ("wavelength", "nm"), "EV": ("energy", "eV")}
    y_map = {"ABSORBANCE": ("absorbance", "absorbance", "1"),
             "ABSORPTIONINDEX": ("absorption_index", "absorption_index", "1"),
             "DISPERSIONINDEX": ("dispersion_index", "dispersion_index", "1"),
             "TRANSMITTANCE": ("transmittance", "transmittance", "1"),
             "%TRANSMITTANCE": ("transmittance", "transmittance", "%"),
             "%T": ("transmittance", "transmittance", "%"),
             "REFLECTANCE": ("reflectance", "reflectance", "1"),
             "INTENSITY": ("intensity", "raw_intensity", "counts")}
    if x_raw not in x_map:
        fail(f"unsupported JCAMP XUNITS {x_raw!r}; supply a controlled conversion")
    if y_raw not in y_map:
        fail(f"unsupported JCAMP YUNITS {y_raw!r}; supply a controlled conversion")
    return x_map[x_raw], y_map[y_raw]


def parse_jcamp(path: Path, options: dict, metadata: dict, provenance: dict):
    headers, data_tag, lines = read_jcamp(path)
    x_factor = finite_float(headers.get("XFACTOR", "1"), "JCAMP XFACTOR")
    y_factor = finite_float(headers.get("YFACTOR", "1"), "JCAMP YFACTOR")
    pairs = []
    packed_signed_affn = False
    if data_tag == "XYDATA":
        delta_raw = headers.get("DELTAX", "")
        if delta_raw:
            delta = finite_float(delta_raw, "JCAMP DELTAX") * x_factor
        else:
            first = finite_float(required(headers, "FIRSTX"), "JCAMP FIRSTX") * x_factor
            last = finite_float(required(headers, "LASTX"), "JCAMP LASTX") * x_factor
            n = int(required(headers, "NPOINTS"))
            delta = (last - first) / (n - 1)
        if delta == 0:
            fail("JCAMP DELTAX is zero")
        first_grid = (finite_float(headers["FIRSTX"], "JCAMP FIRSTX") * x_factor
                      if headers.get("FIRSTX") else None)
        for line in lines:
            tokens = line.replace(",", " ").split()
            if len(tokens) == 1:
                # Real OpenSpecy/PNNL example: X followed by signed AFFN values
                # without whitespace, e.g. 7498.99+1059714498+1066285291.
                # This is not JCAMP SQZ/DIF/DUP compression.
                packed = re.fullmatch(r"([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[Ee][+-]?\d+)?)"
                                      r"((?:[+-](?:\d+(?:\.\d*)?|\.\d+)(?:[Ee][+-]?\d+)?)+)",
                                      tokens[0])
                if packed is None:
                    fail("unsupported JCAMP XYDATA encoding; expected AFFN or signed packed AFFN")
                if first_grid is None:
                    fail("JCAMP signed-packed AFFN requires FIRSTX for its exact numerical grid")
                x0 = finite_float(packed.group(1), "JCAMP row X") * x_factor
                values = re.findall(r"[+-](?:\d+(?:\.\d*)?|\.\d+)(?:[Ee][+-]?\d+)?", packed.group(2))
                if "".join(values) != packed.group(2):
                    fail("unsupported JCAMP XYDATA signed encoding")
                expected_x = first_grid + len(pairs) * delta
                if abs(x0 - expected_x) > max(abs(delta) / 2, 0.02):
                    fail("JCAMP packed row X does not match declared grid")
                for token in values:
                    y = finite_float(token, "JCAMP signed AFFN Y") * y_factor
                    pairs.append((first_grid + len(pairs) * delta, y))
                packed_signed_affn = True
            elif len(tokens) >= 2:
                x0 = finite_float(tokens[0], "JCAMP row X") * x_factor
                for index, token in enumerate(tokens[1:]):
                    # Compressed SQZ/DIF/DUP records must not be misread as AFFN.
                    y = finite_float(token, "JCAMP AFFN Y") * y_factor
                    pairs.append((x0 + index * delta, y))
            else:
                fail("empty JCAMP XYDATA row")
    else:
        for line in lines:
            tokens = [t for t in re.split(r"[\s,;]+", line) if t]
            if len(tokens) % 2:
                fail("JCAMP XY pair row has an odd number of values")
            for i in range(0, len(tokens), 2):
                pairs.append((finite_float(tokens[i], "JCAMP X") * x_factor,
                              finite_float(tokens[i + 1], "JCAMP Y") * y_factor))
    if len(pairs) < 2:
        fail("JCAMP spectrum has fewer than two numerical samples")
    expected = headers.get("NPOINTS", "")
    if expected and len(pairs) != int(expected):
        fail(f"JCAMP NPOINTS mismatch: declared {expected}, parsed {len(pairs)}")
    (x_quantity, x_unit), (y_quantity, y_rep, y_unit) = jcamp_units(headers)
    data_type = headers.get("DATA TYPE", "").upper()
    if "INFRARED" in data_type:
        kind = "IR"
    elif "RAMAN" in data_type:
        kind = "Raman"
    elif "UV" in data_type or "VISIBLE" in data_type:
        kind = "UV_VIS"
    else:
        kind = options.get("spectrum_kind", "")
        if not kind:
            fail("JCAMP DATA TYPE is ambiguous; spectrum_kind is required")
    options = {**options, "display_name": options.get("display_name") or headers.get("TITLE", ""),
               "spectrum_kind": options.get("spectrum_kind") or kind,
               "x_quantity": options.get("x_quantity") or x_quantity,
               "x_unit": options.get("x_unit") or x_unit,
               "y_quantity": options.get("y_quantity") or y_quantity,
               "y_representation": options.get("y_representation") or y_rep,
               "y_unit": options.get("y_unit") or y_unit}
    fields, automatic = make_base(path, options, "JCAMP-DX")
    metadata = {**{f"jcamp.{key.lower().replace(' ', '_')}": value for key, value in headers.items()}, **metadata}
    metadata["jcamp.numeric_encoding"] = "signed_packed_affn" if packed_signed_affn else "affn"
    automatic["jcamp_data_tag"] = data_tag
    return fields, metadata, {**automatic, **provenance}, pairs


def main(argv):
    if len(argv) != 3:
        fail("usage: scientific_spectrum_import.py csv|jcamp SOURCE OPTIONS_WIRE")
    mode, source, wire = argv
    path = Path(source).resolve()
    if not path.is_file():
        fail(f"source spectrum does not exist: {path}")
    options, metadata, provenance = read_options(wire)
    if mode == "csv":
        result = parse_csv(path, options, metadata, provenance)
    elif mode == "jcamp":
        result = parse_jcamp(path, options, metadata, provenance)
    else:
        fail("source format must be csv or jcamp")
    emit(*result)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (ValueError, OSError, csv.Error) as exc:
        print(f"GX-TXT scientific spectrum import: {exc}", file=sys.stderr)
        raise SystemExit(1)
