# SPDX-License-Identifier: GPL-3.0-or-later
"""Portable, read-only 3D file inspection; Python standard library only.

CORE EXTRACTION CANDIDATE: this file and formats.json have no GX-TXT, Tcl,
GUI, Dataset Registry, viewer or installation dependencies. Move them together
and keep inspect_file()'s result contract. The GX-TXT adapter lives in runtime/.

This is an import/container inspector, NOT a replacement for VTK or OCCT.
STL/OBJ geometry records can be checked without tessellation. STEP checks its
exchange-file envelope/header only. VTU/VTP/VTI check XML and array declarations,
not array values, compressed blocks or mesh topology. Each result records the
actual validation level; downstream readers remain responsible for decoding.
"""
from __future__ import annotations

import json
import math
import mmap
import re
import struct
import time
from pathlib import Path
from typing import Any, Callable, Iterator
from xml.parsers import expat

CATALOG_PATH = Path(__file__).with_name("formats.json")
CHUNK = 1024 * 1024
MAX_RECORD = 16 * CHUNK
MAX_ARRAY_METADATA = 4096
Progress = Callable[[int, int, str], None]


class GeometryError(ValueError):
    """A source is unsupported, incomplete, or inconsistent at the checked level."""


class Cancelled(GeometryError):
    """A caller cancelled inspection or copying."""


def catalog() -> dict[str, dict[str, Any]]:
    """Return the extractable format catalogue without registering anything."""
    data = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1:
        raise GeometryError("Unsupported geometry format catalogue version.")
    return {item["id"]: item for item in data["formats"]}


class Monitor:
    def __init__(self, size: int, progress: Progress | None, cancel: Callable[[], bool] | None):
        self.size, self.progress, self.cancel = size, progress, cancel
        self.last = 0.0

    def tick(self, position: int, stage: str = "inspect", force: bool = False) -> None:
        now = time.monotonic()
        if force or now - self.last >= 0.1:
            if self.cancel and self.cancel():
                raise Cancelled("3D import cancelled.")
            if self.progress:
                self.progress(position, self.size, stage)
            self.last = now


def _finite(values: list[str] | tuple[float, ...], where: str) -> list[float]:
    try:
        result = [float(v) for v in values]
    except (ValueError, OverflowError) as exc:
        raise GeometryError(f"Invalid numeric value in {where}.") from exc
    if not all(math.isfinite(v) for v in result):
        raise GeometryError(f"Non-finite coordinate or normal in {where}.")
    return result


def _bounds_add(bounds: list[float], xyz: list[float]) -> None:
    for i in range(3):
        bounds[2 * i] = min(bounds[2 * i], xyz[i])
        bounds[2 * i + 1] = max(bounds[2 * i + 1], xyz[i])


def _bounds_metadata(bounds: list[float]) -> dict[str, Any]:
    if not all(math.isfinite(x) for x in bounds):
        return {}
    return {f"geometry.bounds_{axis}_{end}": bounds[2 * i + j]
            for i, axis in enumerate("xyz") for j, end in enumerate(("min", "max"))}


def _lines(path: Path, monitor: Monitor) -> Iterator[tuple[int, str, int]]:
    """Bounded binary line reader; numeric syntax is ASCII, names remain intact.

    Latin-1 is used only as a reversible inspection view of opaque source bytes.
    It never rewrites a source. Known UTF-8 BOMs are ignored for inspection.
    """
    with path.open("rb") as stream:
        line_number, position = 0, 0
        while True:
            raw = stream.readline(MAX_RECORD + 1)
            if not raw:
                break
            line_number += 1
            position += len(raw)
            if len(raw) > MAX_RECORD:
                raise GeometryError(f"Source record exceeds the {MAX_RECORD}-byte inspection limit.")
            if line_number == 1:
                raw = raw.removeprefix(b"\xef\xbb\xbf")
            if b"\x00" in raw:
                raise GeometryError(f"Unexpected NUL byte in text geometry at line {line_number}.")
            monitor.tick(position)
            yield line_number, raw.decode("latin-1").strip(), position


def _stl(path: Path, head: bytes, size: int, deep: bool, monitor: Monitor) -> tuple[dict, list]:
    bounds = [math.inf, -math.inf] * 3
    count = struct.unpack_from("<I", head, 80)[0] if len(head) >= 84 else 0
    if len(head) >= 84 and size == 84 + 50 * count:
        if not count:
            raise GeometryError("Binary STL contains no triangles.")
        if deep:
            with path.open("rb") as stream:
                stream.seek(84)
                for start in range(0, count, 4096):
                    number = min(4096, count - start)
                    data = stream.read(50 * number)
                    if len(data) != 50 * number:
                        raise GeometryError("Binary STL is truncated.")
                    for rec in struct.iter_unpack("<12fH", data):
                        coords = _finite(rec[:12], "binary STL record")
                        for i in (3, 6, 9):
                            _bounds_add(bounds, coords[i:i + 3])
                    monitor.tick(stream.tell())
        result = {"geometry.encoding": "binary_little_endian",
                  "geometry.triangle_count": count,
                  "geometry.validation_level": "triangle_records" if deep else "binary_record_layout"}
        if deep:
            result.update(_bounds_metadata(bounds))
        return result, []
    # Binary STL may start with 'solid'; the exact binary record layout above
    # always wins. A 'solid' prefix alone is never accepted as a valid STL.
    if not head.removeprefix(b"\xef\xbb\xbf").lstrip().lower().startswith(b"solid"):
        raise GeometryError("STL has neither an ASCII solid nor a consistent binary record length.")
    state, vertices, triangles, solids, closed = "solid", 0, 0, 0, 0
    for line_number, line, position in _lines(path, monitor):
        if not line:
            continue
        words = line.split()
        token = words[0].lower()
        where = f"ASCII STL line {line_number}"
        if state == "solid" and token == "solid":
            solids += 1
            state = "facet"
        elif state == "facet" and token == "endsolid":
            closed += 1
            state = "solid"
        elif state == "facet" and token == "facet" and len(words) == 5 and words[1].lower() == "normal":
            _finite(words[2:], where)
            state = "outer"
        elif state == "outer" and [w.lower() for w in words] == ["outer", "loop"]:
            state, vertices = "vertices", 0
        elif state == "vertices" and token == "vertex" and len(words) == 4:
            _bounds_add(bounds, _finite(words[1:], where))
            vertices += 1
            if vertices == 3:
                state = "endloop"
        elif state == "endloop" and words == ["endloop"]:
            state = "endfacet"
        elif state == "endfacet" and words == ["endfacet"]:
            state = "facet"
            triangles += 1
            if not deep:
                with path.open("rb") as stream:
                    stream.seek(max(0, size - CHUNK))
                    tail = stream.read()
                if not re.search(rb"(?:^|[\r\n])\s*endsolid(?:\s[^\r\n]*)?\s*$", tail, re.I):
                    raise GeometryError("ASCII STL closing endsolid record is missing.")
                return {"geometry.encoding": "ascii", "geometry.validation_level": "first_triangle_and_terminator",
                        "geometry.counts_scope": "not_scanned"}, []
        else:
            raise GeometryError(f"Unexpected record in {where}; expected {state}.")
    if state != "solid" or solids != closed or not triangles:
        raise GeometryError("ASCII STL is incomplete or contains no triangles.")
    result = {"geometry.encoding": "ascii", "geometry.triangle_count": triangles,
              "geometry.solid_count": solids, "geometry.validation_level": "triangle_records"}
    result.update(_bounds_metadata(bounds))
    return result, []


def _obj(path: Path, deep: bool, monitor: Monitor) -> tuple[dict, list]:
    counts = {"v": 0, "vt": 0, "vn": 0, "f": 0, "l": 0, "p": 0}
    max_positive = {"v": 0, "vt": 0, "vn": 0}
    bounds = [math.inf, -math.inf] * 3
    materials, unknown, warning = [], set(), []
    pending, scanned_all, weighted = "", True, False
    objects, groups, triangles = 0, 0, 0
    known = {"o", "g", "s", "usemtl", "mtllib", "vp"}
    for line_number, line, position in _lines(path, monitor):
        line = line.split("#", 1)[0].rstrip()
        if not line:
            continue
        pending += line[:-1] + " " if line.endswith("\\") else line
        if len(pending) > MAX_RECORD:
            raise GeometryError("OBJ logical record is too long.")
        if line.endswith("\\"):
            continue
        words, pending = pending.split(), ""
        token, args = words[0], words[1:]
        where = f"OBJ line {line_number}"
        if token in {"v", "vt", "vn"}:
            minimum = 3 if token in {"v", "vn"} else 1
            if len(args) < minimum or (token == "vn" and len(args) != 3):
                raise GeometryError(f"Incomplete {token} record at {where}.")
            numbers = _finite(args, where)
            counts[token] += 1
            if token == "v":
                _bounds_add(bounds, numbers[:3])
                weighted |= len(numbers) == 4 and numbers[3] != 1.0
        elif token in {"f", "l", "p"}:
            if len(args) < {"f": 3, "l": 2, "p": 1}[token]:
                raise GeometryError(f"Not enough indices at {where}.")
            for item in args:
                parts = item.split("/")
                if len(parts) > 3 or not parts[0]:
                    raise GeometryError(f"Malformed OBJ index at {where}.")
                for kind, text in zip(("v", "vt", "vn"), parts):
                    if not text:
                        continue
                    if not re.fullmatch(r"[+-]?\d+", text):
                        raise GeometryError(f"Non-integer OBJ index at {where}.")
                    index = int(text)
                    if index == 0 or (index < 0 and -index > counts[kind]):
                        raise GeometryError(f"Invalid zero/relative OBJ index at {where}.")
                    max_positive[kind] = max(max_positive[kind], index)
            counts[token] += 1
            if token == "f":
                triangles += len(args) - 2
        elif token == "mtllib":
            # Do not dereference paths: the requested object is a single source.
            # Record dependencies and make missing portability of appearance
            # explicit; the native mesh reader uses the geometry, not an importer
            # side channel that fetches arbitrary files.
            if len(materials) < 128:
                materials.append(" ".join(args))
        elif token == "o":
            objects += 1
        elif token == "g":
            groups += 1
        elif token not in known:
            if len(unknown) < 64:
                unknown.add(token)
        if not deep and position >= CHUNK and counts["v"]:
            scanned_all = False
            break
    if pending:
        raise GeometryError("OBJ ends with an unfinished line continuation.")
    if not counts["v"] or not any(counts[t] for t in ("f", "l", "p")) and scanned_all:
        raise GeometryError("OBJ needs vertices and at least one face, line or point element.")
    if scanned_all:
        for kind in max_positive:
            if max_positive[kind] > counts[kind]:
                raise GeometryError(f"OBJ {kind} index exceeds the number of available records.")
    result: dict[str, Any] = {"geometry.encoding": "text",
                             "geometry.validation_level": "geometry_records_and_indices" if scanned_all else "prefix_records",
                             "geometry.counts_scope": "complete" if scanned_all else "prefix"}
    suffix = "count" if scanned_all else "records_in_preview"
    for key, label in (("v", "vertex"), ("vt", "texture_coordinate"), ("vn", "normal"),
                       ("f", "face"), ("l", "polyline"), ("p", "point_element")):
        result[f"geometry.{label}_{suffix}"] = counts[key]
    if scanned_all:
        result.update({"obj.object_count": objects, "obj.group_count": groups,
                       "obj.polygon_fan_triangle_count": triangles})
        # These are source XYZ coordinates, not a tessellation of rational geometry.
        if not weighted:
            result.update(_bounds_metadata(bounds))
    if weighted:
        warning.append("OBJ homogeneous vertex weights are preserved; Cartesian bounds are not inferred.")
    if materials:
        result["obj.material_library_references"] = json.dumps(materials, ensure_ascii=True)
        warning.append("OBJ material libraries/textures are referenced but are not copied or loaded. Geometry bytes are preserved; appearance is not made portable.")
    if unknown:
        result["obj.uninterpreted_record_types"] = json.dumps(sorted(unknown))
        warning.append("Additional OBJ record types are preserved but not interpreted by the mesh inspector.")
    return result, warning


def _strip_step_comments(text: bytes) -> bytes:
    """Remove block comments, not comment-like text inside STEP strings."""
    return re.sub(rb"'(?:[^']|'')*'|/\*.*?\*/", lambda m: b" " if m[0].startswith(b"/*") else m[0], text, flags=re.S)


def _step(path: Path, size: int, monitor: Monitor) -> tuple[dict, list]:
    # CAD semantics belong to OCCT. A bounded envelope/header check is deliberate;
    # do not relabel it as STEP entity, topology, assembly or tessellation validation.
    with path.open("rb") as stream:
        head = stream.read(2 * CHUNK).removeprefix(b"\xef\xbb\xbf")
        stream.seek(max(0, size - CHUNK))
        tail = stream.read()
    head, tail = _strip_step_comments(head).strip(), _strip_step_comments(tail).strip()
    if not head.startswith(b"ISO-10303-21;") or not tail.endswith(b"END-ISO-10303-21;"):
        raise GeometryError("STEP exchange-file opening/closing signature is missing.")
    header = re.search(rb"\bHEADER\s*;(.*?)\bENDSEC\s*;", head, re.S)
    if not header:
        raise GeometryError("STEP HEADER section is missing or exceeds the 2 MiB inspection limit.")
    for item in (b"FILE_DESCRIPTION", b"FILE_NAME", b"FILE_SCHEMA"):
        if not re.search(rb"\b" + item + rb"\s*\(", header[1]):
            raise GeometryError(f"STEP HEADER is missing {item.decode('ascii')}.")
    if not re.search(rb"\bDATA(?:\s*\([^;]*\))?\s*;", head[header.end():]):
        raise GeometryError("STEP DATA section was not found after HEADER.")
    if not re.search(rb"\bENDSEC\s*;\s*END-ISO-10303-21;\s*$", tail):
        raise GeometryError("STEP DATA closing ENDSEC is missing.")
    schema = re.search(rb"FILE_SCHEMA\s*\((.*?)\)\s*;", header[1], re.S)
    names = re.findall(rb"'((?:[^']|'')*)'", schema[1]) if schema else []
    result = {"geometry.encoding": "iso_10303_21_text", "geometry.validation_level": "exchange_envelope_and_header",
              "step.schemas": json.dumps([n.decode("latin-1").replace("''", "'") for n in names]),
              "step.geometry_decoded": False, "geometry.units_status": "embedded_units_preserved_not_interpreted"}
    monitor.tick(size, force=True)
    return result, ["STEP entities, assemblies and embedded units are preserved without CAD decoding or tessellation."]


class _AppendedStart(Exception):
    pass


def _vtu(path: Path, size: int, monitor: Monitor) -> tuple[dict, list]:
    """Inspect XML declarations without materializing scientific arrays.

    Raw AppendedData is explicitly not XML. Expat is stopped at its opening
    element; binary bytes are never sent to an XML or text decoder. Only the
    closing XML envelope and raw offset bounds are checked thereafter.
    """
    parser = expat.ParserCreate()
    stack: list[str] = []
    pieces: list[dict[str, Any]] = []
    arrays: list[dict[str, Any]] = []
    root: dict[str, str] = {}
    appended: dict[str, Any] = {}
    formats: set[str] = set()
    offsets: list[int] = []
    omitted = 0
    grid_count = 0
    current: dict[str, Any] | None = None
    numeric_types = {f"{prefix}{bits}" for prefix in ("Int", "UInt") for bits in (8, 16, 32, 64)} | {"Float32", "Float64"}

    def integer(value: str | None, label: str) -> int:
        if value is None or not re.fullmatch(r"\d+", value):
            raise GeometryError(f"VTU {label} must be a nonnegative integer.")
        return int(value)

    def reject(*args: Any) -> None:
        raise GeometryError("VTU DTDs and entity declarations are not supported; external resources are never fetched.")

    def start(name: str, attrs: dict[str, str]) -> None:
        nonlocal current, omitted, grid_count
        parent = stack[-1] if stack else ""
        if not stack:
            if root or name != "VTKFile" or attrs.get("type") != "UnstructuredGrid":
                raise GeometryError("Only a VTKFile of type UnstructuredGrid is supported as VTU.")
            root.update(attrs)
            if attrs.get("byte_order", "LittleEndian") not in {"LittleEndian", "BigEndian"}:
                raise GeometryError("Unsupported VTU byte_order.")
            if attrs.get("header_type", "UInt32") not in {"UInt32", "UInt64"}:
                raise GeometryError("Unsupported VTU header_type.")
        elif name == "UnstructuredGrid":
            if parent != "VTKFile" or grid_count:
                raise GeometryError("VTU must contain one UnstructuredGrid element.")
            grid_count += 1
        elif name == "Piece":
            if parent != "UnstructuredGrid" or current is not None:
                raise GeometryError("Invalid VTU Piece nesting.")
            current = {"points": integer(attrs.get("NumberOfPoints"), "NumberOfPoints"),
                       "cells": integer(attrs.get("NumberOfCells"), "NumberOfCells"),
                       "point_arrays": 0, "cell_arrays": set(), "index": len(pieces)}
        elif name == "DataArray":
            components = integer(attrs.get("NumberOfComponents", "1"), "NumberOfComponents")
            if not components or attrs.get("type") not in numeric_types:
                raise GeometryError("Invalid VTU DataArray type or component count.")
            storage = attrs.get("format", "ascii").lower()
            if storage not in {"ascii", "binary", "appended"}:
                raise GeometryError(f"Unsupported VTU DataArray encoding: {storage}.")
            formats.add(storage)
            if storage == "appended":
                offsets.append(integer(attrs.get("offset"), "appended array offset"))
            if parent == "Points" and current is not None:
                if components != 3:
                    raise GeometryError("VTU point coordinates must have three components.")
                current["point_arrays"] += 1
            if parent == "Cells" and current is not None:
                current["cell_arrays"].add(attrs.get("Name", ""))
            if len(arrays) < MAX_ARRAY_METADATA:
                item: dict[str, Any] = {"name": attrs.get("Name", ""), "association": parent,
                                        "components": components, "type": attrs["type"], "format": storage,
                                        "piece": current["index"] if current else None}
                for key in ("RangeMin", "RangeMax", "Units", "offset", "NumberOfTuples"):
                    if key in attrs:
                        item[key] = attrs[key]
                arrays.append(item)
            else:
                omitted += 1
        elif name == "AppendedData":
            if parent != "VTKFile" or not grid_count or current is not None:
                raise GeometryError("VTU AppendedData must follow its complete grid declaration.")
            encoding = attrs.get("encoding", "base64")
            if encoding not in {"raw", "base64"}:
                raise GeometryError("Unknown VTU AppendedData encoding.")
            appended.update(start=parser.CurrentByteIndex, encoding=encoding)
            raise _AppendedStart()
        stack.append(name)
        if len(stack) > 64:
            raise GeometryError("VTU nesting exceeds the inspection limit.")

    def end(name: str) -> None:
        nonlocal current
        if name == "Piece":
            if current is None:
                raise GeometryError("Invalid VTU Piece closure.")
            if current["points"] and current["point_arrays"] != 1:
                raise GeometryError("VTU Piece needs exactly one point coordinate DataArray.")
            if current["cells"] and not {"connectivity", "offsets", "types"}.issubset(current["cell_arrays"]):
                raise GeometryError("VTU Cells is missing connectivity, offsets or types.")
            pieces.append(current)
            current = None
        stack.pop()

    parser.StartElementHandler, parser.EndElementHandler = start, end
    parser.StartDoctypeDeclHandler = reject
    parser.EntityDeclHandler = reject
    parser.ExternalEntityRefHandler = reject
    parser.SetParamEntityParsing(expat.XML_PARAM_ENTITY_PARSING_NEVER)
    with path.open("rb") as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as data:
        try:
            for position in range(0, size, CHUNK):
                parser.Parse(data[position:position + CHUNK], False)
                monitor.tick(min(size, position + CHUNK))
            parser.Parse(b"", True)
        except _AppendedStart:
            begin = data.find(b">", appended["start"])
            close = data.rfind(b"</AppendedData>")
            if begin < 0 or close <= begin:
                raise GeometryError("VTU AppendedData is truncated.")
            marker = begin + 1
            while marker < close and data[marker] in b" \r\n\t":
                marker += 1
            if marker >= close or data[marker] != ord("_"):
                raise GeometryError("VTU AppendedData must begin with an underscore separator.")
            payload_bytes = close - marker - 1
            if offsets and payload_bytes == 0:
                raise GeometryError("VTU appended arrays have no payload.")
            if appended["encoding"] == "raw" and offsets and max(offsets) >= payload_bytes:
                raise GeometryError("VTU raw appended offset is outside the payload.")
            # Parsing this synthetic envelope validates the real trailing XML
            # while excluding arbitrary raw binary bytes from XML processing.
            tail_parser = expat.ParserCreate()
            tail_parser.StartDoctypeDeclHandler = reject
            tail_parser.EntityDeclHandler = reject
            tail_parser.ExternalEntityRefHandler = reject
            tail_parser.Parse(b"<VTKFile><AppendedData>" + data[close:], True)
            appended["payload_bytes"] = payload_bytes
        except expat.ExpatError as exc:
            raise GeometryError(f"Malformed VTU XML: {exc}.") from exc
    if grid_count != 1 or not pieces:
        raise GeometryError("VTU contains no UnstructuredGrid Piece.")
    if offsets and not appended:
        raise GeometryError("VTU declares appended arrays without AppendedData.")
    result = {"geometry.encoding": "vtk_xml", "geometry.validation_level": "xml_structure_and_array_declarations",
              "geometry.vertex_count": sum(p["points"] for p in pieces),
              "geometry.cell_count": sum(p["cells"] for p in pieces),
              "vtu.piece_count": len(pieces), "vtu.data_type": "UnstructuredGrid",
              "vtu.byte_order": root.get("byte_order", "LittleEndian"),
              "vtu.header_type": root.get("header_type", "UInt32"),
              "vtu.compressor": root.get("compressor", "none"),
              "vtu.array_encodings": ";".join(sorted(formats)),
              "vtu.arrays_json": json.dumps(arrays, ensure_ascii=True, separators=(",", ":")),
              "vtu.array_metadata_omitted": omitted, "vtu.payload_decoded": False}
    if appended:
        result["vtu.appended_encoding"] = appended["encoding"]
        result["vtu.appended_payload_bytes"] = appended["payload_bytes"]
    warning = ["VTU array values, connectivity and compressed blocks are preserved without decoding. Native 3D opens VTU through Add Session VTU, not Open model."]
    if omitted:
        warning.append(f"Metadata lists the first {MAX_ARRAY_METADATA} arrays; all source arrays are preserved.")
    return result, warning


def _vtk_poly_image(path: Path, size: int, monitor: Monitor, fmt: str) -> tuple[dict, list]:
    """Inspect VTP polydata or VTI regular 3-D image declarations, not array values.

    The VTK reader remains the authority for compressed payload decoding,
    connectivity and isosurface extraction. Raw appended bytes are never fed
    to XML parsing; this follows the same bounded envelope policy as VTU.
    """
    label = fmt.upper()
    grid = "PolyData" if fmt == "vtp" else "ImageData"
    parser = expat.ParserCreate()
    stack: list[str] = []
    root: dict[str, str] = {}
    image: dict[str, str] = {}
    pieces: list[dict[str, Any]] = []
    arrays: list[dict[str, Any]] = []
    formats: set[str] = set()
    offsets: list[int] = []
    appended: dict[str, Any] = {}
    current: dict[str, Any] | None = None
    grid_count = 0
    omitted = 0
    numeric_types = {f"{prefix}{bits}" for prefix in ("Int", "UInt") for bits in (8, 16, 32, 64)} | {"Float32", "Float64"}

    def integer(value: str | None, name: str) -> int:
        if value is None or not re.fullmatch(r"\d+", value):
            raise GeometryError(f"{label} {name} must be a nonnegative integer.")
        return int(value)

    def extent(value: str | None) -> tuple[int, int, int, int, int, int]:
        if value is None or not re.fullmatch(r"\s*-?\d+(\s+-?\d+){5}\s*", value):
            raise GeometryError(f"{label} requires a six-integer extent.")
        parts = tuple(int(x) for x in value.split())
        if any(parts[2*i+1] < parts[2*i] for i in range(3)):
            raise GeometryError(f"{label} extent bounds are reversed.")
        return parts

    def reject(*args: Any) -> None:
        raise GeometryError(f"{label} DTDs and entity declarations are not supported.")

    def start(name: str, attrs: dict[str, str]) -> None:
        nonlocal current, grid_count, omitted
        parent = stack[-1] if stack else ""
        if not stack:
            if root or name != "VTKFile" or attrs.get("type") != grid:
                raise GeometryError(f"{label} requires a VTKFile of type {grid}.")
            root.update(attrs)
            if attrs.get("byte_order", "LittleEndian") not in {"LittleEndian", "BigEndian"} or \
                attrs.get("header_type", "UInt32") not in {"UInt32", "UInt64"}:
                raise GeometryError(f"Unsupported {label} byte or header order.")
        elif name == grid:
            if parent != "VTKFile" or grid_count:
                raise GeometryError(f"{label} requires one {grid} declaration.")
            grid_count += 1
            if fmt == "vti":
                image.update(attrs)
                extent(attrs.get("WholeExtent"))
                for key in ("Origin", "Spacing"):
                    values = attrs.get(key, "").split()
                    if len(values) != 3:
                        raise GeometryError(f"VTI {key} needs three values.")
                    numbers = _finite(values, f"VTI {key}")
                    if key == "Spacing" and any(v == 0 for v in numbers):
                        raise GeometryError("VTI spacing must be nonzero.")
        elif name == "Piece":
            if parent != grid or current is not None:
                raise GeometryError(f"Invalid {label} Piece nesting.")
            if fmt == "vtp":
                counts = {key: integer(attrs.get("NumberOf" + key), key)
                          for key in ("Points", "Verts", "Lines", "Strips", "Polys")}
                current = {"points": counts["Points"], "cells": sum(counts[k] for k in ("Verts", "Lines", "Strips", "Polys")),
                           "counts": counts, "point_arrays": 0, "topology": {}, "index": len(pieces)}
            else:
                bounds = extent(attrs.get("Extent"))
                dims = [bounds[2*i+1] - bounds[2*i] + 1 for i in range(3)]
                if any(n < 2 for n in dims):
                    raise GeometryError("VTI scalar field must have three nondegenerate axes.")
                current = {"points": math.prod(dims), "cells": math.prod(n-1 for n in dims),
                           "extent": bounds, "index": len(pieces), "data_arrays": 0}
        elif name == "DataArray":
            components = integer(attrs.get("NumberOfComponents", "1"), "component count")
            if not components or attrs.get("type") not in numeric_types:
                raise GeometryError(f"Invalid {label} DataArray type or component count.")
            storage = attrs.get("format", "ascii").lower()
            if storage not in {"ascii", "binary", "appended"}:
                raise GeometryError(f"Unsupported {label} DataArray encoding.")
            formats.add(storage)
            if storage == "appended":
                offsets.append(integer(attrs.get("offset"), "appended offset"))
            if current is not None:
                if fmt == "vtp" and parent == "Points":
                    if components != 3:
                        raise GeometryError("VTP point coordinates need three components.")
                    current["point_arrays"] += 1
                elif fmt == "vtp" and parent in {"Verts", "Lines", "Strips", "Polys"}:
                    current["topology"].setdefault(parent, set()).add(attrs.get("Name", ""))
                elif fmt == "vti" and parent in {"PointData", "CellData"}:
                    current["data_arrays"] += 1
            if len(arrays) < MAX_ARRAY_METADATA:
                item: dict[str, Any] = {"name": attrs.get("Name", ""), "association": parent,
                                        "components": components, "type": attrs["type"], "format": storage,
                                        "piece": current["index"] if current else None}
                for key in ("RangeMin", "RangeMax", "Units", "offset", "NumberOfTuples"):
                    if key in attrs:
                        item[key] = attrs[key]
                arrays.append(item)
            else:
                omitted += 1
        elif name == "AppendedData":
            if parent != "VTKFile" or not grid_count or current is not None:
                raise GeometryError(f"{label} AppendedData must follow the grid.")
            encoding = attrs.get("encoding", "base64")
            if encoding not in {"raw", "base64"}:
                raise GeometryError(f"Unknown {label} AppendedData encoding.")
            appended.update(start=parser.CurrentByteIndex, encoding=encoding)
            raise _AppendedStart()
        stack.append(name)
        if len(stack) > 64:
            raise GeometryError(f"{label} nesting exceeds the inspection limit.")

    def end(name: str) -> None:
        nonlocal current
        if name == "Piece":
            if current is None:
                raise GeometryError(f"Invalid {label} Piece closure.")
            if fmt == "vtp":
                if current["points"] and current["point_arrays"] != 1:
                    raise GeometryError("VTP Piece needs one coordinate DataArray.")
                for kind in ("Verts", "Lines", "Strips", "Polys"):
                    if current["counts"][kind] and not {"connectivity", "offsets"}.issubset(current["topology"].get(kind, set())):
                        raise GeometryError(f"VTP {kind} is missing connectivity or offsets.")
            elif current["data_arrays"] < 1:
                raise GeometryError("VTI Piece contains no scientific arrays.")
            pieces.append(current)
            current = None
        stack.pop()

    parser.StartElementHandler, parser.EndElementHandler = start, end
    parser.StartDoctypeDeclHandler = reject
    parser.EntityDeclHandler = reject
    parser.ExternalEntityRefHandler = reject
    parser.SetParamEntityParsing(expat.XML_PARAM_ENTITY_PARSING_NEVER)
    with path.open("rb") as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as data:
        try:
            for position in range(0, size, CHUNK):
                parser.Parse(data[position:position + CHUNK], False)
                monitor.tick(min(size, position + CHUNK))
            parser.Parse(b"", True)
        except _AppendedStart:
            begin = data.find(b">", appended["start"])
            close = data.rfind(b"</AppendedData>")
            if begin < 0 or close <= begin:
                raise GeometryError(f"{label} AppendedData is truncated.")
            marker = begin + 1
            while marker < close and data[marker] in b" \r\n\t":
                marker += 1
            if marker >= close or data[marker] != ord("_"):
                raise GeometryError(f"{label} AppendedData needs an underscore separator.")
            payload_bytes = close - marker - 1
            if offsets and (payload_bytes == 0 or (appended["encoding"] == "raw" and max(offsets) >= payload_bytes)):
                raise GeometryError(f"{label} appended array offset is outside the payload.")
            tail_parser = expat.ParserCreate()
            tail_parser.StartDoctypeDeclHandler = reject
            tail_parser.EntityDeclHandler = reject
            tail_parser.ExternalEntityRefHandler = reject
            tail_parser.Parse(b"<VTKFile><AppendedData>" + data[close:], True)
            appended["payload_bytes"] = payload_bytes
        except expat.ExpatError as exc:
            raise GeometryError(f"Malformed {label} XML: {exc}.") from exc
    if grid_count != 1 or not pieces or sum(p["points"] for p in pieces) < 1:
        raise GeometryError(f"{label} contains no displayable grid Piece.")
    if fmt == "vtp" and sum(p["cells"] for p in pieces) < 1:
        raise GeometryError("VTP contains no displayable cells.")
    if offsets and not appended:
        raise GeometryError(f"{label} declares appended arrays without AppendedData.")
    result = {"geometry.encoding": "vtk_xml", "geometry.validation_level": "xml_structure_and_array_declarations",
              "geometry.vertex_count": sum(p["points"] for p in pieces),
              "geometry.cell_count": sum(p["cells"] for p in pieces),
              f"{fmt}.piece_count": len(pieces), f"{fmt}.data_type": grid,
              f"{fmt}.byte_order": root.get("byte_order", "LittleEndian"),
              f"{fmt}.header_type": root.get("header_type", "UInt32"),
              f"{fmt}.compressor": root.get("compressor", "none"),
              f"{fmt}.array_encodings": ";".join(sorted(formats)),
              f"{fmt}.arrays_json": json.dumps(arrays, ensure_ascii=True, separators=(",", ":")),
              f"{fmt}.array_metadata_omitted": omitted, f"{fmt}.payload_decoded": False}
    if fmt == "vti":
        for key in ("Origin", "Spacing", "WholeExtent"):
            result[f"vti.{key.lower()}"] = image[key]
    if appended:
        result[f"{fmt}.appended_encoding"] = appended["encoding"]
        result[f"{fmt}.appended_payload_bytes"] = appended["payload_bytes"]
    warning = [f"{label} array values, connectivity and compressed blocks are preserved without decoding; the native VTK reader validates them during rendering."]
    if omitted:
        warning.append(f"Metadata lists only the first {MAX_ARRAY_METADATA} arrays; source arrays are preserved.")
    return result, warning


def inspect_file(path: str | Path, *, deep: bool = False, progress: Progress | None = None,
                 cancel: Callable[[], bool] | None = None) -> dict[str, Any]:
    """Return format_id, format, metadata and warnings; never write to the source.

    deep=True fully checks STL/OBJ records. STEP and VTK XML deliberately retain the
    envelope/declaration scope described above. No coordinate conversion, mesh
    repair, triangulation, resampling, scientific computation or rendering occurs.
    """
    path = Path(path)
    if not path.is_file():
        raise GeometryError("3D source is not a regular file.")
    before = path.stat()
    if before.st_size <= 0:
        raise GeometryError("3D source is empty.")
    with path.open("rb") as stream:
        head = stream.read(CHUNK)
    lead = head.removeprefix(b"\xef\xbb\xbf").lstrip()
    entries = catalog()
    monitor = Monitor(before.st_size, progress, cancel)
    monitor.tick(0, force=True)
    binary_count = struct.unpack_from("<I", head, 80)[0] if len(head) >= 84 else None
    if binary_count is not None and before.st_size == 84 + 50 * binary_count:
        fmt = "stl"
    elif lead.lower().startswith(b"solid"):
        fmt = "stl"
    elif _strip_step_comments(lead).lstrip().startswith(b"ISO-10303-21;"):
        fmt = "step"
    elif re.search(rb"<VTKFile\b", lead):
        match = re.search(rb"<VTKFile\b[^>]*\btype\s*=\s*([\"'])([^\"']+)\1", lead)
        vtk_types = {b"UnstructuredGrid": "vtu", b"PolyData": "vtp", b"ImageData": "vti"}
        fmt = vtk_types.get(match.group(2) if match else b"")
        if fmt is None:
            raise GeometryError("Unsupported VTK XML data type; only VTU, VTP and VTI are imported.")
        if path.suffix.lower() != "." + fmt:
            raise GeometryError("VTK XML file extension disagrees with its declared data type.")
    elif re.search(rb"(?m)^\s*v\s+[-+.0-9]", lead) or path.suffix.lower() == ".obj":
        fmt = "obj"
    else:
        raise GeometryError("Unrecognized 3D content. Supported sources: STL, OBJ, STEP/STP, VTU, VTP and VTI.")
    if fmt == "stl":
        metadata, warnings = _stl(path, head, before.st_size, deep, monitor)
    elif fmt == "obj":
        metadata, warnings = _obj(path, deep, monitor)
    elif fmt == "step":
        metadata, warnings = _step(path, before.st_size, monitor)
    elif fmt == "vtu":
        metadata, warnings = _vtu(path, before.st_size, monitor)
    else:
        metadata, warnings = _vtk_poly_image(path, before.st_size, monitor, fmt)
    after = path.stat()
    if (before.st_size, before.st_mtime_ns, before.st_ino) != (after.st_size, after.st_mtime_ns, after.st_ino):
        raise GeometryError("3D source changed while it was being inspected.")
    metadata.update({"geometry.format": fmt, "geometry.media_type": entries[fmt]["media_type"],
                     "geometry.source_size_bytes": before.st_size, "geometry.coordinates_transformed": False,
                     "geometry.inspector_version": "1.1.0", "geometry.viewer_use": entries[fmt]["viewer_use"]})
    metadata.setdefault("geometry.units_status", "not_assigned_by_importer")
    if path.suffix.lower() not in entries[fmt]["extensions"]:
        warnings.append(f"Filename extension {path.suffix or '(none)'} does not match detected {fmt.upper()} content; the canonical extension will be {entries[fmt]['canonical_extension']}.")
    monitor.tick(before.st_size, force=True)
    return {"format_id": fmt, "format": entries[fmt], "metadata": metadata, "warnings": warnings}
