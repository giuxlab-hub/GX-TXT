#!/usr/bin/env python3
"""Transactional adapter for the officially licensed TUM RefIMP training CSV."""
from __future__ import annotations

import csv
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import sqlite3
import struct
import sys
import tempfile
import zipfile

SOURCE_SHA256 = "569050ddf6cfed952fdaabe6e2020522b643510cf1e00cf27265f4cd3783711a"
LIBRARY_ID = "tum.refimp.ftir.training.2022"
SOURCE_URL = "https://mediatum.ub.tum.de/1656656"
LICENSE_URL = "https://creativecommons.org/licenses/by-sa/4.0/"
CITATION = "Weisser, Jana; Pohl, Teresa (2022), RefIMP transmission micro-FTIR dataset, TUM mediaTUM 1656656"
EXPECTED_COUNT = 9537
EXPECTED_POINTS = 637


def fail(message: str) -> None:
    raise ValueError(message)


def source_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")


def spectrum_hash(x: list[float], y: list[float]) -> str:
    header = ["IR", "wavenumber", "cm^-1", "relative_transmission_signal", "transmission_signal", "1"]
    stream = io.StringIO()
    for field in header:
        stream.write(field + "\n")
    for a, b in zip(x, y):
        stream.write(f"{a:.17g}\t{b:.17g}\n")
    return hashlib.sha256(stream.getvalue().encode("utf-8")).hexdigest()


def main(args: list[str]) -> None:
    if len(args) != 3:
        fail("usage: install_refimp_training.py FRAMEWORK_ROOT FTIR_MP_train_test_spectra.csv NEW_EXPORT_ZIP")
    framework, source, export = (Path(a).resolve() for a in args)
    if source.name != "FTIR_MP_train_test_spectra.csv" or not source.is_file():
        fail("official RefIMP training/test CSV required")
    if source_digest(source) != SOURCE_SHA256:
        fail("RefIMP training/test source SHA-256 mismatch")
    helper = framework / "core/python/scientific_reference_library.py"
    spec = importlib.util.spec_from_file_location("scientific_reference_library", helper)
    if spec is None or spec.loader is None:
        fail("GX-TXT CORE library helper missing")
    lib = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(lib)
    data_root = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share")))
    root = data_root / "gxtxt_pipeline/scientific_reference_libraries"
    destination = root / f"{LIBRARY_ID}.gxsrl"
    if destination.exists() or export.exists():
        fail("reference library or export already exists")
    root.mkdir(parents=True, exist_ok=True)
    export.parent.mkdir(parents=True, exist_ok=True)
    db_fd, db_name = tempfile.mkstemp(prefix=".refimp-training-", suffix=".tmp", dir=root)
    zip_fd, zip_name = tempfile.mkstemp(prefix=".refimp-training-", suffix=".zip", dir=export.parent)
    os.close(db_fd)
    os.close(zip_fd)
    db_temp, zip_temp = Path(db_name), Path(zip_name)
    linked_db = linked_zip = False
    try:
        with sqlite3.connect(db_temp) as con:
            lib.init_schema(con)
            con.execute("PRAGMA foreign_keys=ON")
            created = lib.now()
            lib.set_meta(con, {
                "library_id": LIBRARY_ID,
                "name": "RefIMP transmission micro-FTIR training/test spectra",
                "version": "2022-04-21",
                "owner": "Technical University of Munich",
                "source_identity": SOURCE_URL,
                "source_version": "2022-04-21",
                "retrieval_date": "2026-09-24",
                "license": "CC-BY-SA-4.0",
                "rights": LICENSE_URL,
                "citation": CITATION,
                "description": "9,537 labeled training/test traces; not independently validated chemical identifications. Ordinate is a relative transmission signal, not asserted absolute transmittance.",
                "format": "GX-TXT Scientific Reference Library",
                "format_version": "1",
                "created_at": created,
                "updated_at": created,
                "source_sha256": SOURCE_SHA256,
            })
            with source.open("r", encoding="utf-8-sig", newline="") as stream:
                reader = csv.reader(stream, delimiter=";")
                header = next(reader)
                if header[-1].strip() == "":
                    header.pop()
                if header[:3] != ["ItemID", "Class No", "Caption"] or len(header) != EXPECTED_POINTS + 3:
                    fail("unexpected RefIMP training CSV header")
                x = []
                for item in header[3:]:
                    match = re.fullmatch(r"\s*(\d+(?:\.\d+)?)\s*\[1/cm\]\s*", item)
                    if match is None:
                        fail(f"invalid spectral coordinate header: {item!r}")
                    x.append(float(match.group(1)))
                if any(x[i] >= x[i - 1] for i in range(1, len(x))):
                    fail("RefIMP training grid is not strictly descending")
                x_blob = struct.pack("<" + "d" * len(x), *x)
                seen_ids: set[str] = set()
                groups: dict[str, tuple[str, str]] = {}
                count = 0
                for line_number, row in enumerate(reader, start=2):
                    if not any(cell.strip() for cell in row):
                        continue
                    if row[-1].strip() == "" and len(row) == len(header) + 1:
                        row.pop()
                    if len(row) != len(header):
                        fail(f"line {line_number}: wrong column count")
                    item_id, class_no, caption = (cell.strip() for cell in row[:3])
                    if not item_id.isdigit() or item_id in seen_ids or not class_no.isdigit() or not caption:
                        fail(f"line {line_number}: invalid/duplicate identity or classification")
                    seen_ids.add(item_id)
                    entity_id = slug(caption)
                    if entity_id in groups and groups[entity_id] != (class_no, caption):
                        fail(f"line {line_number}: inconsistent class/caption mapping")
                    if entity_id not in groups:
                        con.execute("INSERT INTO entities(entity_id,metadata_json) VALUES (?,?)", (
                            entity_id, json.dumps({"entity_id": entity_id, "display_name": caption,
                                                   "class_no": class_no, "dataset_role": "training/test",
                                                   "source_identity": SOURCE_URL}, sort_keys=True),
                        ))
                    groups[entity_id] = (class_no, caption)
                    try:
                        y = [float(value) for value in row[3:]]
                    except ValueError as exc:
                        fail(f"line {line_number}: nonnumeric ordinate: {exc}")
                    if any(not (-float("inf") < value < float("inf")) for value in y):
                        fail(f"line {line_number}: nonfinite ordinate")
                    spectrum_id = f"refimp-train-{int(item_id):05d}"
                    y_blob = struct.pack("<" + "d" * len(y), *y)
                    fields = {
                        "spectrum_id": spectrum_id, "entity_id": entity_id,
                        "display_name": f"{caption} training/test spectrum {item_id}",
                        "spectrum_kind": "IR", "x_quantity": "wavenumber", "x_unit": "cm^-1",
                        "y_quantity": "relative_transmission_signal", "y_representation": "transmission_signal", "y_unit": "1",
                        "contract": "spectrum.scientific", "sample_count": str(len(x)),
                        "x_ordering": "descending", "x_min": str(x[-1]), "x_max": str(x[0]),
                        "source_identity": f"{SOURCE_URL}#FTIR_MP_train_test_spectra.csv:ItemID={item_id}",
                        "source_hash": SOURCE_SHA256,
                    }
                    scientific_hash = spectrum_hash(x, y)
                    fields["spectrum_hash"] = scientific_hash
                    metadata = {"class_no": class_no, "caption": caption, "technique": "transmission micro-FTIR",
                                "nominal_resolution": "8 cm^-1", "dataset_role": "training/test",
                                "ordinate_note": "relative signal; no asserted absolute transmittance scale"}
                    provenance = {"publisher": "Technical University of Munich", "source_url": SOURCE_URL,
                                  "license": "CC-BY-SA-4.0", "citation": CITATION,
                                  "source_filename": source.name, "source_sha256": SOURCE_SHA256,
                                  "source_item_id": item_id}
                    con.execute(
                        "INSERT INTO spectra(spectrum_id,entity_id,fields_json,metadata_json,provenance_json,"
                        "spectrum_hash,payload_hash,sample_count,x_min,x_max,x_ordering,x_payload,y_payload)"
                        " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
                        (spectrum_id, entity_id, json.dumps(fields, sort_keys=True, ensure_ascii=False),
                         json.dumps(metadata, sort_keys=True, ensure_ascii=False),
                         json.dumps(provenance, sort_keys=True, ensure_ascii=False), scientific_hash,
                         hashlib.sha256(x_blob + y_blob).hexdigest(), len(x), x[-1], x[0],
                         "descending", x_blob, y_blob),
                    )
                    count += 1
                if count != EXPECTED_COUNT:
                    fail(f"expected {EXPECTED_COUNT} spectra, found {count}")
                if len(groups) != 15:
                    fail(f"expected 15 classes, found {len(groups)}")
                lib.refresh_hash(con)
        info = lib.validate_file(db_temp, LIBRARY_ID)
        db_sha = source_digest(db_temp)
        with zipfile.ZipFile(zip_temp, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.write(db_temp, "library.gxsrl")
            archive.writestr("SHA256SUMS.txt", f"{db_sha}  library.gxsrl\n")
            archive.writestr("LIBRARY.txt", f"GX-TXT Scientific Reference Library v1\nlibrary_id={LIBRARY_ID}\nversion=2022-04-21\n")
        os.link(db_temp, destination)
        linked_db = True
        os.link(zip_temp, export)
        linked_zip = True
        print(f"PASS {LIBRARY_ID}: {count} spectra, {len(groups)} classes, {len(x)} points each, "
              f"content_hash={info['content_hash']}, export={export}")
    except Exception:
        if linked_zip:
            export.unlink()
        if linked_db:
            destination.unlink()
        raise
    finally:
        db_temp.unlink(missing_ok=True)
        zip_temp.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (OSError, ValueError, sqlite3.Error, csv.Error) as error:
        print(f"RefIMP adapter: {error}", file=sys.stderr)
        raise SystemExit(1)
