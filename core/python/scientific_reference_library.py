#!/usr/bin/env python3
"""GX-TXT CORE Scientific Reference Library storage helper (SQLite v1).

CLI wire format is intentionally simple: F/M/P tab-separated UTF-8-base64
key/value records and D tab-separated finite decimal X/Y records. It is not
exposed to plugins; the public Tcl API owns validation and this helper.
"""
from __future__ import annotations

import base64
import contextlib
import datetime as dt
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sqlite3
import struct
import sys
import tempfile
import zipfile

SAFE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
SCHEMA = 1


def fail(message: str) -> None:
    raise ValueError(message)


def safe_id(value: str) -> str:
    if not SAFE.fullmatch(value) or value in {".", ".."}:
        fail(f"invalid identifier: {value!r}")
    return value


def library_path(root: str, library_id: str) -> Path:
    return Path(root).resolve() / (safe_id(library_id) + ".gxsrl")


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def b64(text: str) -> str:
    return base64.b64encode(text.encode("utf-8")).decode("ascii")


def unb64(text: str) -> str:
    return base64.b64decode(text.encode("ascii"), validate=True).decode("utf-8")


def read_wire(path: str):
    fields, metadata, provenance, data = {}, {}, {}, []
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        parts = line.split("\t")
        if parts[0] == "D":
            if len(parts) != 3:
                fail("invalid numerical wire row")
            x, y = float(parts[1]), float(parts[2])
            if not math.isfinite(x) or not math.isfinite(y):
                fail("non-finite numerical wire row")
            data.append((x, y))
        elif parts[0] in {"F", "M", "P"}:
            if len(parts) != 3:
                fail("invalid metadata wire row")
            target = {"F": fields, "M": metadata, "P": provenance}[parts[0]]
            target[unb64(parts[1])] = unb64(parts[2])
        else:
            fail("unknown wire record")
    return fields, metadata, provenance, data


def write_wire(fields, metadata=None, provenance=None, data=None) -> None:
    for prefix, mapping in (("F", fields), ("M", metadata or {}), ("P", provenance or {})):
        for key, value in sorted(mapping.items()):
            print(f"{prefix}\t{b64(str(key))}\t{b64(str(value))}")
    for x, y in data or []:
        print(f"D\t{x:.17g}\t{y:.17g}")


@contextlib.contextmanager
def connect_existing(path: Path):
    if not path.is_file():
        fail(f"reference library does not exist: {path}")
    con = sqlite3.connect(f"file:{path}?mode=rw", uri=True)
    con.row_factory = sqlite3.Row
    if con.execute("PRAGMA user_version").fetchone()[0] != SCHEMA:
        con.close()
        fail("unsupported GX-TXT reference library schema")
    try:
        with con:
            yield con
    finally:
        con.close()


def init_schema(con: sqlite3.Connection) -> None:
    con.executescript("""
        PRAGMA foreign_keys=ON;
        PRAGMA user_version=1;
        CREATE TABLE library_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE entities (
            entity_id TEXT PRIMARY KEY,
            metadata_json TEXT NOT NULL
        );
        CREATE TABLE spectra (
            spectrum_id TEXT PRIMARY KEY,
            entity_id TEXT REFERENCES entities(entity_id),
            fields_json TEXT NOT NULL,
            metadata_json TEXT NOT NULL,
            provenance_json TEXT NOT NULL,
            spectrum_hash TEXT NOT NULL,
            payload_hash TEXT NOT NULL,
            sample_count INTEGER NOT NULL,
            x_min REAL NOT NULL,
            x_max REAL NOT NULL,
            x_ordering TEXT NOT NULL,
            x_payload BLOB NOT NULL,
            y_payload BLOB NOT NULL
        );
        CREATE INDEX spectra_entity ON spectra(entity_id);
        CREATE INDEX spectra_hash ON spectra(spectrum_hash);
    """)


def meta(con: sqlite3.Connection) -> dict[str, str]:
    return dict(con.execute("SELECT key,value FROM library_meta"))


def set_meta(con: sqlite3.Connection, values: dict[str, str]) -> None:
    con.executemany(
        "INSERT INTO library_meta(key,value) VALUES (?,?) "
        "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        values.items(),
    )


def content_hash(con: sqlite3.Connection) -> str:
    h = hashlib.sha256()
    for row in con.execute("SELECT entity_id,metadata_json FROM entities ORDER BY entity_id"):
        h.update(json.dumps(tuple(row), separators=(",", ":")).encode("utf-8"))
        h.update(b"\n")
    for row in con.execute(
        "SELECT spectrum_id,entity_id,spectrum_hash,payload_hash,fields_json,"
        "metadata_json,provenance_json FROM spectra ORDER BY spectrum_id"
    ):
        h.update(json.dumps(tuple(row), separators=(",", ":")).encode("utf-8"))
        h.update(b"\n")
    return h.hexdigest()


def refresh_hash(con: sqlite3.Connection) -> None:
    set_meta(con, {"content_hash": content_hash(con), "updated_at": now()})


def create(root: str, info_file: str) -> None:
    fields, _, _, _ = read_wire(info_file)
    library_id = safe_id(fields.get("library_id", ""))
    if not fields.get("name") or not fields.get("version"):
        fail("library name and version are required")
    path = library_path(root, library_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        fail("reference library already exists")
    fd, temp = tempfile.mkstemp(prefix=".gxsrl-", suffix=".tmp", dir=path.parent)
    os.close(fd)
    try:
        with sqlite3.connect(temp) as con:
            init_schema(con)
            fields.setdefault("owner", "user")
            fields.setdefault("source", "")
            fields.setdefault("source_version", "")
            fields.setdefault("retrieval_date", "")
            fields.setdefault("license", "")
            fields.setdefault("rights", "")
            fields.setdefault("citation", "")
            fields["format"] = "GX-TXT Scientific Reference Library"
            fields["format_version"] = "1"
            fields["created_at"] = now()
            fields["updated_at"] = fields["created_at"]
            set_meta(con, fields)
            refresh_hash(con)
        os.link(temp, path)
    finally:
        Path(temp).unlink(missing_ok=True)
    print(library_id)


def list_libraries(root: str) -> None:
    directory = Path(root)
    if not directory.is_dir():
        return
    for path in sorted(directory.glob("*.gxsrl")):
        try:
            with connect_existing(path) as con:
                info = meta(con)
                if info.get("library_id") == path.stem:
                    print(path.stem)
        except (sqlite3.Error, ValueError):
            continue


def info(root: str, library_id: str) -> None:
    with connect_existing(library_path(root, library_id)) as con:
        write_wire(meta(con))


def upsert_entity(root: str, library_id: str, entity_id: str, info_file: str) -> None:
    entity_id = safe_id(entity_id)
    fields, metadata, _, _ = read_wire(info_file)
    payload = {**fields, **metadata}
    payload["entity_id"] = entity_id
    with connect_existing(library_path(root, library_id)) as con:
        con.execute("PRAGMA foreign_keys=ON")
        con.execute(
            "INSERT INTO entities(entity_id,metadata_json) VALUES (?,?) "
            "ON CONFLICT(entity_id) DO UPDATE SET metadata_json=excluded.metadata_json",
            (entity_id, json.dumps(payload, sort_keys=True, ensure_ascii=False)),
        )
        refresh_hash(con)
    print(entity_id)


def prepared_spectrum(spec_file: str):
    fields, metadata, provenance, data = read_wire(spec_file)
    spectrum_id = safe_id(fields.get("spectrum_id", ""))
    entity_id = fields.get("entity_id", "")
    if entity_id:
        safe_id(entity_id)
    if len(data) < 2 or int(fields.get("sample_count", "-1")) != len(data):
        fail("spectrum sample count mismatch")
    x = [pair[0] for pair in data]
    y = [pair[1] for pair in data]
    direction = 1 if x[1] > x[0] else -1
    if any((x[i] - x[i - 1]) * direction <= 0 for i in range(1, len(x))):
        fail("spectrum X is not strictly monotonic")
    if fields.get("x_ordering") != ("ascending" if direction == 1 else "descending"):
        fail("spectrum ordering mismatch")
    x_blob = struct.pack("<" + "d" * len(x), *x)
    y_blob = struct.pack("<" + "d" * len(y), *y)
    payload_hash = hashlib.sha256(x_blob + y_blob).hexdigest()
    spectrum_hash = fields.get("spectrum_hash", "")
    if not re.fullmatch(r"[0-9a-f]{64}", spectrum_hash):
        fail("invalid scientific spectrum hash")
    return spectrum_id, entity_id, fields, metadata, provenance, spectrum_hash, payload_hash, x_blob, y_blob, x, y


def add_spectrum(root: str, library_id: str, spec_file: str) -> None:
    (spectrum_id, entity_id, fields, metadata, provenance, spectrum_hash,
     payload_hash, x_blob, y_blob, x, y) = prepared_spectrum(spec_file)
    with connect_existing(library_path(root, library_id)) as con:
        con.execute("PRAGMA foreign_keys=ON")
        if entity_id and not con.execute("SELECT 1 FROM entities WHERE entity_id=?", (entity_id,)).fetchone():
            fail("reference entity does not exist")
        con.execute(
            "INSERT INTO spectra(spectrum_id,entity_id,fields_json,metadata_json,"
            "provenance_json,spectrum_hash,payload_hash,sample_count,x_min,x_max,"
            "x_ordering,x_payload,y_payload) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (spectrum_id, entity_id or None,
             json.dumps(fields, sort_keys=True, ensure_ascii=False),
             json.dumps(metadata, sort_keys=True, ensure_ascii=False),
             json.dumps(provenance, sort_keys=True, ensure_ascii=False),
             spectrum_hash, payload_hash, len(x), min(x), max(x),
             fields["x_ordering"], x_blob, y_blob),
        )
        refresh_hash(con)
    print(spectrum_id)


def _fork_version(root: str, source_id: str, new_id: str, version: str, change=None) -> dict[str, str]:
    source = library_path(root, source_id)
    original = validate_file(source, safe_id(source_id))
    new_id = safe_id(new_id)
    if not version.strip() or source_id == new_id:
        fail("fork requires a distinct library ID and a nonempty new version")
    destination = library_path(root, new_id)
    if destination.exists():
        fail("new version already exists")
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=".gxsrl-version-", suffix=".tmp", dir=destination.parent)
    os.close(fd)
    try:
        with sqlite3.connect(source) as previous, sqlite3.connect(temp) as upcoming:
            previous.backup(upcoming)
        with connect_existing(Path(temp)) as con:
            set_meta(con, {"library_id": new_id, "version": version, "owner": "user",
                           "forked_from_library_id": source_id,
                           "forked_from_version": original["version"],
                           "forked_from_content_hash": original["content_hash"],
                           "created_at": now()})
            if change is not None:
                change(con)
            refresh_hash(con)
        checked = validate_file(Path(temp), new_id)
        os.link(temp, destination)
        return checked
    finally:
        Path(temp).unlink(missing_ok=True)


def fork_version(root: str, source_id: str, new_id: str, version: str) -> None:
    _fork_version(root, source_id, new_id, version)
    print(new_id)


def update_reference(root: str, source_id: str, new_id: str, version: str, spec_file: str) -> None:
    (spectrum_id, entity_id, fields, metadata, provenance, spectrum_hash,
     payload_hash, x_blob, y_blob, x, y) = prepared_spectrum(spec_file)

    def change(con):
        con.execute("PRAGMA foreign_keys=ON")
        if not con.execute("SELECT 1 FROM spectra WHERE spectrum_id=?", (spectrum_id,)).fetchone():
            fail("reference spectrum to update does not exist")
        if entity_id and not con.execute("SELECT 1 FROM entities WHERE entity_id=?", (entity_id,)).fetchone():
            fail("replacement reference entity does not exist")
        con.execute(
            "UPDATE spectra SET entity_id=?,fields_json=?,metadata_json=?,provenance_json=?,"
            "spectrum_hash=?,payload_hash=?,sample_count=?,x_min=?,x_max=?,x_ordering=?,"
            "x_payload=?,y_payload=? WHERE spectrum_id=?",
            (entity_id or None, json.dumps(fields, sort_keys=True, ensure_ascii=False),
             json.dumps(metadata, sort_keys=True, ensure_ascii=False),
             json.dumps(provenance, sort_keys=True, ensure_ascii=False),
             spectrum_hash, payload_hash, len(x), min(x), max(x), fields["x_ordering"],
             x_blob, y_blob, spectrum_id),
        )

    _fork_version(root, source_id, new_id, version, change)
    print(new_id)


def remove_user_reference(root: str, source_id: str, new_id: str, version: str, spectrum_id: str) -> None:
    source_info = validate_file(library_path(root, source_id), safe_id(source_id))
    if source_info.get("owner") != "user":
        fail("only user-owned references may be removed")
    spectrum_id = safe_id(spectrum_id)

    def change(con):
        deleted = con.execute("DELETE FROM spectra WHERE spectrum_id=?", (spectrum_id,))
        if deleted.rowcount != 1:
            fail("reference spectrum to remove does not exist")

    _fork_version(root, source_id, new_id, version, change)
    print(new_id)


def update_library(root: str, source_id: str, new_id: str, version: str, info_file: str) -> None:
    fields, _, _, data = read_wire(info_file)
    if data:
        fail("library metadata update may not include numerical rows")
    allowed = {"name", "license", "rights", "citation", "description", "source", "source_version"}
    if not fields or set(fields) - allowed:
        fail("library metadata update contains no supported fields or attempts to change identity")

    def change(con):
        set_meta(con, fields)

    _fork_version(root, source_id, new_id, version, change)
    print(new_id)


def remove_library(root: str, library_id: str) -> None:
    library_id = safe_id(library_id)
    source = library_path(root, library_id)
    info = validate_file(source, library_id)
    if info.get("owner") != "user":
        fail("only user-owned libraries may be removed")
    removed = Path(root).resolve() / "removed"
    removed.mkdir(parents=True, exist_ok=True)
    destination = removed / f"{library_id}.{dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')}.{info['content_hash'][:12]}.gxsrl"
    if destination.exists():
        fail("recovery target already exists")
    source.rename(destination)
    print(str(destination))


def entities(root: str, library_id: str) -> None:
    with connect_existing(library_path(root, library_id)) as con:
        for row in con.execute("SELECT entity_id FROM entities ORDER BY entity_id"):
            print(row[0])


def entity(root: str, library_id: str, entity_id: str) -> None:
    with connect_existing(library_path(root, library_id)) as con:
        row = con.execute("SELECT metadata_json FROM entities WHERE entity_id=?", (safe_id(entity_id),)).fetchone()
        if row is None:
            fail("reference entity not found")
        write_wire(json.loads(row[0]))


def spectra(root: str, library_id: str, entity_id: str = "") -> None:
    with connect_existing(library_path(root, library_id)) as con:
        if entity_id:
            rows = con.execute("SELECT spectrum_id FROM spectra WHERE entity_id=? ORDER BY spectrum_id", (safe_id(entity_id),))
        else:
            rows = con.execute("SELECT spectrum_id FROM spectra ORDER BY spectrum_id")
        for row in rows:
            print(row[0])


def spectrum(root: str, library_id: str, spectrum_id: str, include_data: bool) -> None:
    with connect_existing(library_path(root, library_id)) as con:
        row = con.execute("SELECT * FROM spectra WHERE spectrum_id=?", (safe_id(spectrum_id),)).fetchone()
        if row is None:
            fail("reference spectrum not found")
        fields = json.loads(row["fields_json"])
        fields["entity_id"] = row["entity_id"] or ""
        pairs = None
        if include_data:
            n = row["sample_count"]
            x = struct.unpack("<" + "d" * n, row["x_payload"])
            y = struct.unpack("<" + "d" * n, row["y_payload"])
            pairs = zip(x, y)
        write_wire(fields, json.loads(row["metadata_json"]), json.loads(row["provenance_json"]), pairs)


def search(root: str, library_id: str, query: str) -> None:
    q = f"%{query.lower()}%"
    with connect_existing(library_path(root, library_id)) as con:
        rows = con.execute(
            "SELECT s.spectrum_id FROM spectra s LEFT JOIN entities e ON s.entity_id=e.entity_id "
            "WHERE lower(s.spectrum_id) LIKE ? OR lower(s.fields_json) LIKE ? "
            "OR lower(s.metadata_json) LIKE ? OR lower(coalesce(e.metadata_json,'')) LIKE ? "
            "ORDER BY s.spectrum_id", (q, q, q, q),
        )
        for row in rows:
            print(row[0])


def validate_file(path: Path, expected_id: str | None = None) -> dict[str, str]:
    with connect_existing(path) as con:
        result = con.execute("PRAGMA integrity_check").fetchone()[0]
        if result != "ok":
            fail(f"SQLite integrity check failed: {result}")
        info = meta(con)
        if info.get("library_id") != (expected_id or path.stem):
            fail("library ID does not match filename")
        if info.get("content_hash") != content_hash(con):
            fail("library content hash mismatch")
        for row in con.execute("SELECT * FROM spectra"):
            n = row["sample_count"]
            xb, yb = row["x_payload"], row["y_payload"]
            if len(xb) != 8 * n or len(yb) != 8 * n:
                fail(f"spectrum payload length mismatch: {row['spectrum_id']}")
            if hashlib.sha256(xb + yb).hexdigest() != row["payload_hash"]:
                fail(f"spectrum payload hash mismatch: {row['spectrum_id']}")
        return info


def validate(root: str, library_id: str) -> None:
    info = validate_file(library_path(root, library_id))
    write_wire(info)


def export(root: str, library_id: str, target: str) -> None:
    source = library_path(root, library_id)
    info = validate_file(source)
    destination = Path(target).resolve()
    if destination.exists():
        fail("export target already exists")
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=".gxsrl-export-", suffix=".zip", dir=destination.parent)
    os.close(fd)
    try:
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        with zipfile.ZipFile(temp, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.write(source, "library.gxsrl")
            archive.writestr("SHA256SUMS.txt", f"{digest}  library.gxsrl\n")
            archive.writestr("LIBRARY.txt", f"GX-TXT Scientific Reference Library v1\n"
                             f"library_id={library_id}\nversion={info['version']}\n")
        os.link(temp, destination)
    finally:
        Path(temp).unlink(missing_ok=True)
    print(str(destination))


def import_package(root: str, package: str) -> None:
    with zipfile.ZipFile(package) as archive:
        if sorted(archive.namelist()) != ["LIBRARY.txt", "SHA256SUMS.txt", "library.gxsrl"]:
            fail("invalid or unsafe reference library package entries")
        data = archive.read("library.gxsrl")
        manifest = archive.read("SHA256SUMS.txt").decode("utf-8").strip()
        if manifest != f"{hashlib.sha256(data).hexdigest()}  library.gxsrl":
            fail("reference library package checksum mismatch")
    directory = Path(root).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=".gxsrl-import-", suffix=".tmp", dir=directory)
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(data)
        # The format ID comes from validated metadata, never a package path.
        with sqlite3.connect(temp) as con:
            info = meta(con)
        library_id = safe_id(info.get("library_id", ""))
        candidate = directory / (library_id + ".gxsrl")
        validate_file(Path(temp), library_id)
        os.link(temp, candidate)
    finally:
        if temp:
            Path(temp).unlink(missing_ok=True)
    print(library_id)


def main(argv: list[str]) -> None:
    if not argv:
        fail("missing command")
    command, *args = argv
    commands = {
        "create": create, "list": list_libraries, "info": info,
        "upsert-entity": upsert_entity, "add-spectrum": add_spectrum,
        "fork-version": fork_version, "update-reference": update_reference,
        "remove-user-reference": remove_user_reference, "update-library": update_library,
        "remove-library": remove_library,
        "entities": entities, "entity": entity, "spectra": spectra,
        "spectrum": lambda root, lid, sid: spectrum(root, lid, sid, True),
        "spectrum-info": lambda root, lid, sid: spectrum(root, lid, sid, False),
        "search": search, "validate": validate, "export": export,
        "import": import_package,
    }
    if command not in commands:
        fail(f"unknown command: {command}")
    commands[command](*args)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (ValueError, OSError, sqlite3.Error, zipfile.BadZipFile) as exc:
        print(f"GX-TXT reference library: {exc}", file=sys.stderr)
        raise SystemExit(1)
