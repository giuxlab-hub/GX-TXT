"""Scientific validation and access for independent NMR reference libraries."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import json
import contextlib
import os
from pathlib import Path
import sqlite3
import struct
import sys
import uuid

LIBRARY_TYPE = "spectroscopy.nmr.reference"


def _reference_root():
    data = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(data).resolve() / "gxtxt_pipeline" / "scientific_reference_libraries"


def _reference_path(library_id):
    return _reference_root() / f"{library_id}.gxsrl"


def _storage_helper(framework_root):
    sys.path.insert(0, str(framework_root / "core" / "python"))
    from scientific_reference_library import validate_file
    return validate_file


def validate(payload_path, manifest, framework_root):
    payload_path = Path(payload_path)
    if str(manifest.get("format_version")) != "1":
        raise ValueError("NMR provider requires Scientific Reference Library format 1")
    library_id = manifest["library_id"]
    information = _storage_helper(framework_root)(payload_path, library_id)
    if information.get("library_id") != library_id:
        raise ValueError("NMR reference library identity does not match the package")
    if not information.get("license") or not (information.get("source") or information.get("source_identity")):
        raise ValueError("NMR reference library lacks source or license metadata")
    with contextlib.closing(sqlite3.connect(f"file:{payload_path}?mode=ro", uri=True)) as connection:
        rows = connection.execute("SELECT spectrum_id,fields_json,metadata_json,sample_count FROM spectra ORDER BY spectrum_id").fetchall()
    if not rows:
        raise ValueError("NMR reference library contains no spectra")
    entry_ids = []
    for spectrum_id, fields_json, metadata_json, sample_count in rows:
        fields = json.loads(fields_json)
        if fields.get("spectrum_kind") != "NMR" or fields.get("contract") != "spectrum.scientific":
            raise ValueError(f"reference {spectrum_id} is not a scientific IR spectrum")
        if fields.get("x_quantity") != "chemical_shift" or fields.get("x_unit") != "ppm":
            raise ValueError(f"reference {spectrum_id} has invalid IR coordinates")
        if not fields.get("y_representation") or int(sample_count) < 8:
            raise ValueError(f"reference {spectrum_id} has invalid response semantics or sample count")
        if fields.get("spectrum_id") != spectrum_id:
            raise ValueError(f"reference {spectrum_id} has inconsistent stable identity")
        metadata = json.loads(metadata_json)
        if metadata.get("nucleus") not in ("^1H", "^13C") or metadata.get("dimensionality") != "1" or not metadata.get("frequency_mhz"):
            raise ValueError(f"reference {spectrum_id} lacks required 1-D NMR metadata")
        entry_ids.append(spectrum_id)
    return {"entry_ids": entry_ids, "entry_count": len(entry_ids)}


def _replace_link(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.parent / f".{target.name}.{uuid.uuid4().hex}.tmp"
    try:
        os.link(source, temporary)
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)


def activate(new_payload, old_payload, library_id):
    target = _reference_path(library_id)
    if target.exists():
        if old_payload is None or not target.samefile(old_payload):
            raise ValueError(f"NMR reference library {library_id} already exists outside managed installation")
    _replace_link(new_payload, target)


def rollback_activate(old_payload, library_id):
    target = _reference_path(library_id)
    if old_payload is None:
        target.unlink(missing_ok=True)
    else:
        _replace_link(old_payload, target)


def deactivate(managed_payload, library_id):
    target = _reference_path(library_id)
    if not target.is_file() or not target.samefile(managed_payload):
        raise ValueError(f"NMR reference library {library_id} is not the managed installation")
    target.unlink()


def read_spectrum(payload_path, spectrum_id):
    with contextlib.closing(sqlite3.connect(f"file:{payload_path}?mode=ro", uri=True)) as connection:
        connection.row_factory = sqlite3.Row
        row = connection.execute("SELECT * FROM spectra WHERE spectrum_id=?", (spectrum_id,)).fetchone()
        if row is None:
            raise ValueError(f"unknown NMR reference {spectrum_id}")
        count = row["sample_count"]
        x = struct.unpack("<" + "d" * count, row["x_payload"])
        y = struct.unpack("<" + "d" * count, row["y_payload"])
        result = json.loads(row["fields_json"])
        result["metadata"] = json.loads(row["metadata_json"])
        result["provenance"] = json.loads(row["provenance_json"])
        result["x"] = x
        result["y"] = y
        return result
