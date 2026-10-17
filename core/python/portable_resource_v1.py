#!/usr/bin/env python3
"""Portable Dataset/Graph resource transport; no archive content is executed."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import argparse
import base64
import configparser
import hashlib
import io
import json
import mimetypes
import os
import re
import shutil
import stat
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

from session_portable_v1 import safe_rel_text, sha256_file, utc_timestamp, zip_entry_is_symlink
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "services" / "annotations"))
from plot_annotation_bridge import validate_document as validate_annotations

MANIFEST = "gxtxt-resource-package.json"
SCHEMA = "GXTXT_PORTABLE_RESOURCE_v1"
MAX_ENTRIES = 10000
MAX_UNCOMPRESSED = 4 * 1024**3
MAX_ENTRY = 2 * 1024**3
MAX_RATIO = 200
MAX_MANIFEST = 2 * 1024**2
ID = re.compile(r"^[A-Za-z0-9_.-]+$")
VARIABLE_ID = re.compile(r"^[A-Za-z][A-Za-z0-9_.-]*$")


def valid_id(value: object) -> bool:
    return isinstance(value, str) and value not in {".", ".."} and bool(ID.fullmatch(value))


def read_json_member(zf: zipfile.ZipFile, name: str, limit: int = 8 * 1024 * 1024) -> object:
    if zf.getinfo(name).file_size > limit:
        raise ValueError(f"JSON resource exceeds size limit: {name}")
    return json.loads(zf.read(name).decode("utf-8"))


def ini_sections(path: Path) -> dict[str, dict[str, str]]:
    if not path.is_file():
        return {}
    parsed = configparser.RawConfigParser(interpolation=None, strict=False)
    parsed.optionxform = str
    parsed.read(path, encoding="utf-8")
    return {s: dict(parsed.items(s)) for s in parsed.sections()}


def within(session: Path, relative: str) -> Path:
    safe_rel_text(PurePosixPath(relative))
    root = session.resolve()
    candidate = root
    for part in PurePosixPath(relative).parts:
        candidate = candidate / part
        if candidate.is_symlink():
            raise ValueError(f"symlink resource is not portable: {relative}")
    target = candidate.resolve()
    if root not in target.parents:
        raise ValueError(f"resource path leaves Session: {relative}")
    return target


def json_bytes(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def portable_presentation(payload: bytes, normalize: bool = False) -> bytes:
    parsed = configparser.RawConfigParser(interpolation=None, strict=False)
    parsed.optionxform = str
    parsed.read_string(payload.decode("utf-8"))
    if normalize:
        if not parsed.has_section("runtime"):
            parsed.add_section("runtime")
        parsed.set("runtime", "session", "private_session")
        parsed.set("runtime", "output_dir", ".")
    if parsed.get("runtime", "session", fallback="") != "private_session" or parsed.get("runtime", "output_dir", fallback="") != ".":
        raise ValueError("Graph scientific presentation has a nonportable runtime path")
    for section in parsed.sections():
        for key, value in list(parsed.items(section)):
            if re.fullmatch(r"GXTXT_(?:PLOT_.*_FILE|UNIT_REGISTRY_FILE)", key):
                if not normalize:
                    raise ValueError("Graph scientific presentation has a host file override")
                parsed.remove_option(section, key)
    variant = parsed.get("plot_variant", "variant_id", fallback="")
    if variant and not valid_id(variant):
        raise ValueError("Graph scientific presentation has an invalid Variant ID")
    output = io.StringIO()
    parsed.write(output, space_around_delimiters=False)
    return output.getvalue().encode("utf-8")


class Builder:
    def __init__(self, resource_type: str, version: str, session: Path, identity: dict):
        self.resource_type = resource_type
        self.version = version
        self.session = session
        self.identity = identity
        self.content: dict[str, bytes | Path] = {}
        self.roles: dict[str, str] = {}
        self.dependencies: list[dict] = []
        self.external_dependencies: list[dict] = []
        self.warnings: list[str] = []

    def add(self, path: str, role: str, payload: bytes | Path) -> None:
        safe_rel_text(PurePosixPath(path))
        if path == MANIFEST or path in self.content:
            raise ValueError(f"duplicate package entry: {path}")
        if isinstance(payload, Path) and (not payload.is_file() or payload.is_symlink()):
            raise ValueError(f"resource file is unavailable or symlinked: {payload}")
        self.content[path] = payload
        self.roles[path] = role

    def dataset(self, dataset_id: str, prefix: str = "dataset") -> dict:
        if not valid_id(dataset_id):
            raise ValueError("invalid Dataset ID")
        registry = ini_sections(self.session / "metadata" / "datasets.ini").get(f"dataset.{dataset_id}")
        if not registry:
            raise ValueError(f"Dataset is not registered: {dataset_id}")
        relative = registry.get("path", "")
        if not relative:
            raise ValueError("Dataset has no Canonical payload path")
        payload_override = None
        if registry.get('source_storage_policy') == 'reference' and registry.get('external_source_root'):
            from gxtxt_scientific_io import open_scoped, signature
            fd = open_scoped(registry['external_source_root'], registry['external_source_relative'])
            try:
                before = os.fstat(fd)
                if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_size > 64 * 1024**2:
                    raise ValueError('Reference portable snapshot requires an ordinary source of at most 64 MiB')
                parts = []
                while chunk := os.read(fd, 1024 * 1024): parts.append(chunk)
                payload_override = b''.join(parts)
                if signature(os.fstat(fd)) != signature(before):
                    raise ValueError('External reference changed during portable snapshot')
            finally: os.close(fd)
            source = Path(registry['external_source_relative'])
            actual = hashlib.sha256(payload_override).hexdigest()
        else:
            source = within(self.session, relative)
            if not source.is_file():
                raise ValueError("Canonical Dataset payload is missing")
            actual = sha256_file(source)
        expected = registry.get("canonical_sha256") or registry.get("sha256")
        if expected and expected.lower() != actual:
            raise ValueError("Canonical Dataset SHA-256 mismatch")
        portable = {k: v for k, v in registry.items() if k not in
                    {"path", "source_raw", "storage_locator", "materialized_path", "external_source_root", "external_source_relative"}}
        if payload_override is not None:
            portable["source_storage_policy"] = "copy"
            portable["reference_snapshot_sha256"] = actual
        elif registry.get("source_raw"):
            self.external_dependencies.append({"kind": "acquisition_raw", "dataset_id": dataset_id,
                                               "name": Path(registry["source_raw"]).name, "embedded": False})
        portable["id"] = dataset_id
        portable["canonical_sha256"] = actual
        portable["sha256"] = actual
        variables = []
        count = int(registry.get("var_count", "0"))
        if count < 0 or count > 100000:
            raise ValueError("invalid Variable count")
        for index in range(1, count + 1):
            marker = f"var{index}_"
            variable = {key[len(marker):]: val for key, val in registry.items() if key.startswith(marker)
                        and key != marker + "source_raw"}
            if not variable.get("variable_id"):
                raise ValueError("Dataset Variable schema has a missing stable ID")
            variables.append(variable)
        suffix = source.suffix or ".dat"
        self.add(f"{prefix}/payload/canonical{suffix}", "canonical_payload", source if payload_override is None else payload_override)
        self.add(f"{prefix}/registry.json", "dataset_registry", json_bytes(portable))
        self.add(f"{prefix}/schema.json", "variable_schema_v3", json_bytes(variables))
        metadata_rel = registry.get("structured_metadata_file") or f"metadata/datasets/{dataset_id}.ini"
        metadata_file = within(self.session, metadata_rel)
        if metadata_file.is_file():
            sections = ini_sections(metadata_file)
            if sections.get("dataset_metadata", {}).get("dataset_id") != dataset_id:
                raise ValueError("Dataset metadata identity mismatch")
            metadata = sections.get("metadata", {})
            self.add(f"{prefix}/metadata.json", "dataset_metadata", json_bytes(metadata))
        note_rel = f"notes/datasets/{dataset_id}.md"
        note = within(self.session, note_rel)
        if note.is_file():
            self.add(f"{prefix}/notes.md", "dataset_notes", note)
        snapshot_rel = registry.get("schema_source_snapshot", "")
        if snapshot_rel:
            snapshot = within(self.session, snapshot_rel)
            if not snapshot.is_file():
                raise ValueError("Dataset schema-source snapshot is missing")
            expected = registry.get("schema_source_snapshot_sha256", "")
            if expected and sha256_file(snapshot) != expected:
                raise ValueError("Dataset schema-source snapshot SHA-256 mismatch")
            self.add(f"{prefix}/schema_source/{snapshot.name}", "schema_source_snapshot", snapshot)
        return {"dataset_id": dataset_id, "contract": registry.get("contract", ""),
                "format": registry.get("format", ""), "storage_provider": registry.get("storage_provider", ""),
                "producer_module": registry.get("producer_module", registry.get("source_module", "")),
                "producer_version": registry.get("producer_version", ""), "canonical_sha256": actual}

    def finish(self, archive: Path) -> dict:
        if archive.exists():
            raise ValueError("archive already exists")
        files = []
        for path, payload in sorted(self.content.items()):
            if isinstance(payload, bytes):
                digest = hashlib.sha256(payload).hexdigest()
                size = len(payload)
            else:
                digest = sha256_file(payload)
                size = payload.stat().st_size
            files.append({"path": path, "role": self.roles[path], "size": size,
                          "sha256": digest, "media_type": mimetypes.guess_type(path)[0] or "application/octet-stream"})
        manifest = {"schema": SCHEMA, "schema_version": 1, "resource_type": self.resource_type,
                    "source_gxtxt_version": self.version, "created_at": utc_timestamp(),
                    "source_session_name": self.session.name, "resource_identity": self.identity,
                    "files": files, "dependencies": self.dependencies, "integrity_algorithm": "sha256",
                    "external_dependencies": self.external_dependencies,
                    "warnings": self.warnings, "unknown_fields": "ignore additive fields"}
        archive.parent.mkdir(parents=True, exist_ok=True)
        tmp = archive.with_name(archive.name + f".tmp-{os.getpid()}")
        try:
            with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6,
                                 allowZip64=True) as zf:
                zf.writestr(MANIFEST, json_bytes(manifest))
                for path, payload in sorted(self.content.items()):
                    if isinstance(payload, bytes):
                        zf.writestr(path, payload)
                    else:
                        zf.write(payload, path)
            inspect(tmp)
            os.replace(tmp, archive)
        finally:
            tmp.unlink(missing_ok=True)
        return {"archive": str(archive), "sha256": sha256_file(archive), "file_count": len(files),
                "resource_type": self.resource_type}


def read_state_tsv(path: Path) -> dict:
    state: dict[str, object] = {"axis": {}, "series": []}
    series: dict[int, dict] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        cells = raw.split("\t")
        if len(cells) != 2:
            raise ValueError("invalid graph state transport row")
        key, encoded = cells
        value = base64.b64decode(encoded, validate=True).decode("utf-8")
        if key.startswith("axis."):
            state["axis"][key[5:]] = value
        elif key.startswith("series."):
            _, number, field = key.split(".", 2)
            series.setdefault(int(number), {})[field] = value
        else:
            state[key] = value
    state["series"] = [series[i] for i in sorted(series)]
    return state


def export_graph(session: Path, artifact: Path, state_tsv: Path, note: str, metadata: str,
                 annotation: str, render_metadata: str, scientific: str, dependencies: str,
                 archive: Path, version: str) -> dict:
    session = session.resolve()
    artifact = artifact.resolve()
    if session not in artifact.parents or not artifact.is_file():
        raise ValueError("graph artifact is not a Session PNG")
    with artifact.open("rb") as fh:
        if fh.read(8) != b"\x89PNG\r\n\x1a\n":
            raise ValueError("graph artifact is not a PNG")
    state = read_state_tsv(state_tsv)
    identity = {k: state.get(k, "") for k in ("kind", "module_id", "graph_id", "variant_id", "clone_id")}
    builder = Builder("graph", version, session, identity)
    builder.add("graph/graph.png", "rendered_graph", artifact)
    builder.add("graph/graph-state.json", "graph_state", json_bytes(state))
    for source, name, role in ((note, "notes.md", "graph_notes"),
                               (metadata, "metadata.json", "graph_metadata"),
                               (annotation, "annotations.json", "graph_annotations"),
                               (render_metadata, "render-metadata.ini", "render_metadata")):
        if source:
            path = Path(source)
            if name == "metadata.json":
                data = ini_sections(path).get("metadata", {})
                builder.add("graph/metadata.json", role, json_bytes(data))
            else:
                builder.add("graph/" + name, role, path)
    if scientific:
        root = Path(scientific)
        native_source = (root / "native_v4_snapshot.tcldict").is_file()
        for source in sorted(root.rglob("*")):
            if source.is_symlink():
                raise ValueError("scientific snapshot contains a symlink")
            if source.is_dir():
                continue
            rel = source.relative_to(root).as_posix()
            if rel == "graph.png" or (native_source and rel in {".gxtxt_plotmeta/graph.ini", ".gxtxt_plotmeta/graph.xrange.ini"}):
                # Native scene geometry/axis sidecars are regenerated from the
                # complete canonical spec; they are not scientific source.
                continue
            payload = portable_presentation(source.read_bytes(), normalize=True) if rel == "presentation.ini" else source
            builder.add("graph/scientific/" + rel, "scientific_snapshot", payload)
        native = "graph/scientific/native_v4_snapshot.tcldict" in builder.content
        if not native and ("graph/scientific/snapshot.h5" not in builder.content or "graph/scientific/presentation.ini" not in builder.content):
            raise ValueError("scientific snapshot is incomplete")
    for dataset_id in [d for d in dependencies.split(";") if d]:
        prefix = "datasets/" + dataset_id
        detail = builder.dataset(dataset_id, prefix)
        builder.dependencies.append({"resource_type": "dataset", "dataset_id": dataset_id,
                                     "embedded": True, "prefix": prefix, "contract": detail["contract"]})
    builder.dependencies.sort(key=lambda x: x["dataset_id"])
    builder.warnings.append("Scientific snapshot is unavailable; rendered graph is preserved") if not scientific else None
    return builder.finish(archive)


def sha256_file_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def inspect(archive: Path) -> dict:
    if not archive.is_file():
        raise ValueError("resource archive does not exist")
    with zipfile.ZipFile(archive) as zf:
        infos = zf.infolist()
        if len(infos) > MAX_ENTRIES or not infos:
            raise ValueError("archive entry count exceeds limit")
        names = set()
        total = 0
        for item in infos:
            name = safe_rel_text(PurePosixPath(item.filename))
            if name != item.filename:
                raise ValueError(f"noncanonical archive path: {item.filename}")
            if item.is_dir() or zip_entry_is_symlink(item):
                raise ValueError(f"directory/symlink archive entry is forbidden: {name}")
            if name in names:
                raise ValueError(f"duplicate archive entry: {name}")
            names.add(name)
            if item.file_size > MAX_ENTRY:
                raise ValueError("archive member exceeds size limit")
            total += item.file_size
            if total > MAX_UNCOMPRESSED:
                raise ValueError("archive exceeds uncompressed size limit")
            if item.file_size > 1024 * 1024 and item.file_size / max(1, item.compress_size) > MAX_RATIO:
                raise ValueError("archive compression ratio exceeds limit")
        if MANIFEST not in names or zf.getinfo(MANIFEST).file_size > MAX_MANIFEST:
            raise ValueError("resource transport manifest is missing or oversized")
        manifest = read_json_member(zf, MANIFEST, MAX_MANIFEST)
        if manifest.get("schema") != SCHEMA or manifest.get("schema_version") != 1:
            raise ValueError("unsupported resource package schema")
        if manifest.get("resource_type") not in {"dataset", "graph", "workspace"}:
            raise ValueError("unknown resource package type")
        if manifest.get("integrity_algorithm") != "sha256":
            raise ValueError("unsupported integrity algorithm")
        declared = manifest.get("files")
        if not isinstance(declared, list) or len(declared) != len(infos) - 1:
            raise ValueError("package file declaration count mismatch")
        checked = set()
        for entry in declared:
            if not isinstance(entry, dict):
                raise ValueError("invalid package file declaration")
            name = safe_rel_text(PurePosixPath(entry.get("path", "")))
            if name != entry.get("path"):
                raise ValueError("noncanonical package file declaration")
            if name == MANIFEST or name in checked or name not in names:
                raise ValueError(f"undeclared or duplicate package file: {name}")
            checked.add(name)
            item = zf.getinfo(name)
            if entry.get("size") != item.file_size:
                raise ValueError(f"declared byte size mismatch: {name}")
            digest = hashlib.sha256()
            with zf.open(item) as reader:
                for chunk in iter(lambda: reader.read(1024 * 1024), b""):
                    digest.update(chunk)
            if entry.get("sha256") != digest.hexdigest():
                raise ValueError(f"SHA-256 mismatch: {name}")
        if checked != names - {MANIFEST}:
            raise ValueError("archive contains undeclared files")
        if manifest["resource_type"] == "dataset":
            validate_dataset_tree(zf, manifest, "dataset", manifest.get("resource_identity", {}).get("dataset_id"))
        elif manifest["resource_type"] == "graph":
            validate_graph_tree(zf, manifest)
        else:
            identity = read_json_member(zf, "workspace/identity.json", MAX_MANIFEST)
            if identity != manifest.get("resource_identity"):
                raise ValueError("workspace identity mismatch")
            required = {"workspace_id", "name", "provider_id", "module_id", "schema", "schema_version"}
            if not required <= identity.keys() or not all(isinstance(identity[key], str) for key in required):
                raise ValueError("invalid workspace provider metadata")
            if zf.getinfo("workspace/payload.utf8").file_size > 64 * 1024**2:
                raise ValueError("workspace payload exceeds limit")
            zf.read("workspace/payload.utf8").decode("utf-8")
            for name in checked:
                if name in {"workspace/identity.json", "workspace/payload.utf8", "workspace/notes.md"}:
                    continue
                if not re.fullmatch(r"workspace/blobs/[a-f0-9]{64}\.blob", name):
                    raise ValueError("unexpected workspace resource")
                if sha256_file_bytes(zf.read(name)) != Path(name).stem:
                    raise ValueError("workspace blob identity mismatch")
        return manifest


def validate_dataset_tree(zf: zipfile.ZipFile, manifest: dict, prefix: str, expected_id: str | None) -> dict:
    records = [f for f in manifest["files"] if f["path"].startswith(prefix + "/")]
    by_role: dict[str, list[str]] = {}
    for record in records:
        by_role.setdefault(record["role"], []).append(record["path"])
    if any(role not in {"canonical_payload", "dataset_registry", "variable_schema_v3", "dataset_metadata", "dataset_notes", "schema_source_snapshot"} for role in by_role):
        raise ValueError("Dataset package has an unsupported role")
    for role in ("canonical_payload", "dataset_registry", "variable_schema_v3"):
        if len(by_role.get(role, [])) != 1:
            raise ValueError(f"Dataset package requires one {role}")
    for role in ("dataset_metadata", "dataset_notes", "schema_source_snapshot"):
        if len(by_role.get(role, [])) > 1:
            raise ValueError(f"Dataset package has duplicate {role}")
    if by_role["dataset_registry"] != [prefix + "/registry.json"] or by_role["variable_schema_v3"] != [prefix + "/schema.json"]:
        raise ValueError("Dataset package has nonstandard authority paths")
    if len(by_role["canonical_payload"]) != 1 or not by_role["canonical_payload"][0].startswith(prefix + "/payload/"):
        raise ValueError("Dataset has a nonstandard payload path")
    for role, basename in (("dataset_metadata", "metadata.json"), ("dataset_notes", "notes.md")):
        if by_role.get(role) and by_role[role] != [prefix + "/" + basename]:
            raise ValueError("Dataset has a nonstandard resource path")
    if by_role.get("schema_source_snapshot") and not by_role["schema_source_snapshot"][0].startswith(prefix + "/schema_source/"):
        raise ValueError("Dataset has a nonstandard schema-source path")
    registry = read_json_member(zf, by_role["dataset_registry"][0])
    schema = read_json_member(zf, by_role["variable_schema_v3"][0], 32 * 1024 * 1024)
    if not isinstance(registry, dict) or not isinstance(schema, list):
        raise ValueError("Dataset registry/schema has invalid JSON structure")
    dataset_id = registry.get("id")
    if not valid_id(dataset_id) or dataset_id != expected_id:
        raise ValueError("Dataset identity mismatch")
    if any(not isinstance(k, str) or not isinstance(v, str) for k, v in registry.items()):
        raise ValueError("Dataset registry contains a non-text field")
    if any(not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", k) for k in registry):
        raise ValueError("Dataset registry contains an invalid field name")
    if any("\n" in v or "\r" in v for v in registry.values()):
        raise ValueError("Dataset registry contains a multiline field")
    if any(key in registry for key in ("path", "source_raw", "storage_locator", "external_source_root", "external_source_relative")):
        raise ValueError("Dataset registry contains a host-local path")
    count = int(registry.get("var_count", "-1"))
    if count < 0 or count > 100000 or len(schema) != count:
        raise ValueError("Variable schema count mismatch")
    seen_ids = set()
    for index, variable in enumerate(schema, 1):
        if not isinstance(variable, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in variable.items()):
            raise ValueError("Variable schema entry is not a string dictionary")
        variable_id = variable.get("variable_id", "")
        if not isinstance(variable_id, str) or not VARIABLE_ID.fullmatch(variable_id) or variable_id in seen_ids:
            raise ValueError("Variable schema has a missing/duplicate stable ID")
        seen_ids.add(variable_id)
        for key, value in variable.items():
            if "\n" in value or "\r" in value or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", key):
                raise ValueError("Variable schema has an invalid field")
            if registry.get(f"var{index}_{key}") != value:
                raise ValueError("Registry and Variable schema disagree")
    payload_path = by_role["canonical_payload"][0]
    payload_sha = next(f["sha256"] for f in records if f["path"] == payload_path)
    if registry.get("canonical_sha256", registry.get("sha256", "")) != payload_sha:
        raise ValueError("Canonical Dataset SHA-256 mismatch")
    if registry.get("storage_provider") == "hdf5" or registry.get("format") in {"hdf5", "h5"}:
        datasets = validate_hdf5_member(zf, payload_path)
        for index, variable in enumerate(schema, 1):
            locator = registry.get(f"var{index}_storage_locator", "")
            if variable.get("axis_kind") == "uniform" and not locator:
                continue
            if locator not in datasets:
                raise ValueError(f"HDF5 Variable locator is unavailable: {locator}")
            declared_shape = tuple(int(s) for s in variable.get("shape", "").split(";") if s)
            if declared_shape and declared_shape != datasets[locator]:
                raise ValueError(f"HDF5 Variable shape mismatch: {locator}")
    if by_role.get("dataset_metadata"):
        metadata = read_json_member(zf, by_role["dataset_metadata"][0])
        if not isinstance(metadata, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in metadata.items()):
            raise ValueError("Dataset metadata is not a string dictionary")
    if by_role.get("dataset_notes"):
        if zf.getinfo(by_role["dataset_notes"][0]).file_size > 16 * 1024 * 1024:
            raise ValueError("Dataset note exceeds size limit")
        zf.read(by_role["dataset_notes"][0]).decode("utf-8")
    if by_role.get("schema_source_snapshot"):
        path = by_role["schema_source_snapshot"][0]
        snapshot_sha = next(f["sha256"] for f in records if f["path"] == path)
        if registry.get("schema_source_snapshot_sha256") != snapshot_sha:
            raise ValueError("schema-source snapshot SHA-256 mismatch")
    elif registry.get("schema_source_snapshot"):
        raise ValueError("schema-source snapshot is missing")
    return {"registry": registry, "schema": schema, "roles": by_role}


def validate_hdf5_member(zf: zipfile.ZipFile, name: str) -> dict:
    """Inspect a staged HDF5 without reading data or following external links."""
    try:
        import h5py
    except ImportError as exc:
        raise ValueError("HDF5 resource validation requires h5py") from exc
    with tempfile.TemporaryDirectory(prefix="gxtxt-resource-hdf5-") as temp:
        path = Path(temp) / "payload.h5"
        with zf.open(name) as source, path.open("xb") as target:
            shutil.copyfileobj(source, target, 1024 * 1024)
        datasets = {}
        seen = set()
        with h5py.File(path, "r") as file:
            snapshot = name == "graph/scientific/snapshot.h5"
            if snapshot and set(file.keys()) != {"P"}:
                raise ValueError("Graph scientific snapshot must contain only prepared P data")
            def visit(group):
                address = h5py.h5o.get_info(group.id).addr
                if address in seen:
                    return
                seen.add(address)
                for key in group.keys():
                    link = group.get(key, getlink=True)
                    if isinstance(link, h5py.ExternalLink):
                        raise ValueError(f"HDF5 external link is not portable: {name}")
                    item = group.get(key)
                    if item is None:
                        raise ValueError(f"HDF5 dangling link is not portable: {name}")
                    if isinstance(item, h5py.Group):
                        visit(item)
                    elif isinstance(item, h5py.Dataset):
                        if snapshot and key == "type":
                            if item.size != 1 or item.dtype.kind not in {"S", "O", "U"}:
                                raise ValueError("Graph snapshot has invalid Octave data type metadata")
                            value = item[()]
                            if isinstance(value, bytes):
                                value = value.decode("ascii")
                            if not isinstance(value, str) or not re.fullmatch(r"scalar struct|struct|cell|sq_string|string|bool|scalar|matrix|complex scalar|complex matrix|(?:u?int(?:8|16|32|64)|float|double|bool) (?:scalar|matrix)|range", value):
                                raise ValueError("Graph snapshot contains an executable or unsupported Octave type")
                        if item.external:
                            raise ValueError(f"HDF5 external raw storage is not portable: {name}")
                        if item.is_virtual and any(source.file_name not in {".", b"."} for source in item.virtual_sources()):
                            raise ValueError(f"HDF5 external virtual source is not portable: {name}")
                        datasets[item.name] = item.shape
            visit(file)
        return datasets


def validate_native_graph_snapshot(zf: zipfile.ZipFile, paths: list[str], state: dict) -> None:
    """Parse inert Tcl lists and inspect complete canonical Dataset archives.

    Tcl's list parser performs no command, variable or expression evaluation.
    The interpreter has no Tk/display requirement. Snapshot content is never
    sourced and a nested Graph package cannot recurse into this validator.
    """
    import tkinter
    parser = tkinter.Tcl()

    def dictionary(value: str) -> dict:
        try:
            items = parser.splitlist(value)
        except tkinter.TclError as exc:
            raise ValueError("Native snapshot contains a malformed inert dictionary") from exc
        if len(items) % 2:
            raise ValueError("Native snapshot dictionary has an odd item count")
        result = dict(zip(items[::2], items[1::2]))
        if len(result) * 2 != len(items):
            raise ValueError("Native snapshot dictionary has duplicate fields")
        return result

    name = "graph/scientific/native_v4_snapshot.tcldict"
    if zf.getinfo(name).file_size > 16 * 1024**2:
        raise ValueError("Native snapshot manifest exceeds size limit")
    try:
        outer = parser.splitlist(zf.read(name).decode("utf-8"))
    except tkinter.TclError as exc:
        raise ValueError("Native snapshot contains a malformed inert list") from exc
    if len(outer) != 1:
        raise ValueError("Native snapshot requires one inert dictionary")
    snapshot = dictionary(outer[0])
    if snapshot.get("schema") != "GXTXT_NATIVE_PLOT_SNAPSHOT_v1" or snapshot.get("renderer_owner") != "PLOT_DATASET_API_v4":
        raise ValueError("Unsupported native scientific snapshot")
    if snapshot.get("graph_id") != state["graph_id"] or not valid_id(snapshot.get("graph_id")):
        raise ValueError("Native snapshot graph identity mismatch")
    spec = dictionary(snapshot.get("spec", ""))
    if spec.get("graph_id") != snapshot["graph_id"]:
        raise ValueError("Native snapshot specification identity mismatch")
    datasets = dictionary(snapshot.get("datasets", ""))
    dependencies = {}
    def require(dataset, variable):
        if not valid_id(dataset) or not VARIABLE_ID.fullmatch(variable):
            raise ValueError('Invalid native scientific Dataset/Variable dependency')
        dependencies.setdefault(dataset, set()).add(variable)
    if snapshot['graph_id'] == 'plot.dataset.xyz':
        series = [spec]
    else:
        series = [dictionary(item) for panel in parser.splitlist(spec.get('panels', ''))
                  for item in parser.splitlist(dictionary(panel).get('series', ''))]
    for item in series:
        dataset = item.get('dataset_id', '')
        for key, variable in item.items():
            if key.endswith('_variable_id') and variable: require(dataset, variable)
        for field in ('x_error', 'y_error', 'band', 'bar_bounds'):
            if item.get(field):
                for key, variable in dictionary(item[field]).items():
                    if (key.endswith('_variable_id') or key == 'variable_id') and variable: require(dataset, variable)
        if 'cell_field' in item:
            binding = dictionary(item['cell_field'])
            keys = {'schema','nodes_dataset_id','node_id_variable_id','x_variable_id','y_variable_id',
                    'cell_id_variable_id','node_variable_ids','scalar_variable_id'}
            if set(binding) != keys or binding['schema'] != 'GXTXT_CELL_FIELD_BINDING_v1':
                raise ValueError('Invalid native exact-cell binding schema')
            node_roles = parser.splitlist(binding['node_variable_ids'])
            if len(node_roles) != 3 or len(set(node_roles)) != 3:
                raise ValueError('Exact triangles require three distinct connectivity roles')
            for key in ('node_id_variable_id','x_variable_id','y_variable_id'):
                require(binding['nodes_dataset_id'], binding[key])
            for variable in [binding['cell_id_variable_id'],binding['scalar_variable_id'],*node_roles]:
                require(dataset, variable)
    if set(dependencies) != set(datasets):
        raise ValueError('Native snapshot Dataset set does not match its actual specification')
    expected = {name}
    total_nested = 0
    for dataset_id, raw in datasets.items():
        if not valid_id(dataset_id):
            raise ValueError("Native snapshot has an invalid Dataset identity")
        resource = dictionary(raw)
        relative = resource.get("archive", "")
        if relative != f"resources/{dataset_id}.zip":
            raise ValueError("Native snapshot has an unsafe Dataset archive path")
        member = "graph/scientific/" + relative
        expected.add(member)
        if member not in paths or not re.fullmatch(r"[0-9a-f]{64}", resource.get("sha256", "")):
            raise ValueError("Native snapshot Dataset declaration is incomplete")
        with tempfile.TemporaryDirectory(prefix="gxtxt-native-snapshot-") as temp:
            archive = Path(temp) / "dataset.zip"
            digest = hashlib.sha256()
            with zf.open(member) as source, archive.open("xb") as target:
                while chunk := source.read(1024 * 1024):
                    digest.update(chunk)
                    target.write(chunk)
            if digest.hexdigest() != resource["sha256"]:
                raise ValueError("Native snapshot canonical Dataset archive SHA-256 mismatch")
            with zipfile.ZipFile(archive) as nested:
                header = read_json_member(nested, MANIFEST, MAX_MANIFEST)
                if not isinstance(header, dict) or header.get("resource_type") != "dataset":
                    raise ValueError("Native snapshot permits canonical Dataset packages only")
                total_nested += sum(item.file_size for item in nested.infolist())
                if total_nested > MAX_UNCOMPRESSED:
                    raise ValueError("Native snapshot canonical content exceeds total size limit")
            info = inspect(archive)
            if info.get("resource_type") != "dataset" or info.get("resource_identity", {}).get("dataset_id") != dataset_id:
                raise ValueError("Native snapshot canonical Dataset identity mismatch")
            with zipfile.ZipFile(archive) as nested:
                schema = validate_dataset_tree(nested, info, 'dataset', dataset_id)['schema']
                available = {variable['variable_id'] for variable in schema}
                if not dependencies[dataset_id] <= available:
                    raise ValueError('Native snapshot is missing an actual scientific Variable dependency')

    if set(paths) != expected:
        raise ValueError("Native snapshot contains undeclared or unsupported files")


def validate_graph_tree(zf: zipfile.ZipFile, manifest: dict) -> None:
    roles: dict[str, list[str]] = {}
    for record in manifest["files"]:
        roles.setdefault(record["role"], []).append(record["path"])
    graph_roles = {"rendered_graph", "graph_state", "graph_notes", "graph_metadata", "graph_annotations", "render_metadata", "scientific_snapshot"}
    if any(role not in graph_roles | {"canonical_payload", "dataset_registry", "variable_schema_v3", "dataset_metadata", "dataset_notes", "schema_source_snapshot"} for role in roles):
        raise ValueError("Graph package has an unsupported role")
    for role, path in (("rendered_graph", "graph/graph.png"), ("graph_state", "graph/graph-state.json")):
        if roles.get(role) != [path]:
            raise ValueError(f"Graph package requires one {role}")
    with zf.open("graph/graph.png") as image:
        if image.read(8) != b"\x89PNG\r\n\x1a\n":
            raise ValueError("Graph package has an invalid PNG")
    state = read_json_member(zf, "graph/graph-state.json")
    if not isinstance(state, dict) or not isinstance(state.get("series"), list) or not isinstance(state.get("axis"), dict):
        raise ValueError("Graph state has invalid structure")
    for field in ("kind", "module_id", "graph_id", "variant_id", "clone_id", "source_module_version", "capture_mode", "use", "title"):
        if not isinstance(state.get(field), str) or "\n" in state[field] or "\r" in state[field]:
            raise ValueError(f"Graph state has an invalid {field}")
    if state["kind"] not in {"provider", "clone"} or state["capture_mode"] not in {"rendered", "scientific"} or state["use"] not in {"0", "1"}:
        raise ValueError("Graph state has invalid kind, capture mode or USE value")
    for field in ("module_id", "graph_id", "variant_id", "clone_id"):
        if state[field] and not valid_id(state[field]):
            raise ValueError(f"Graph state has an invalid identity: {field}")
    for field in ("kind", "module_id", "graph_id", "variant_id", "clone_id"):
        if state.get(field, "") != manifest.get("resource_identity", {}).get(field, ""):
            raise ValueError("Graph identity mismatch")
    for role in ("graph_notes", "graph_metadata", "graph_annotations", "render_metadata"):
        if len(roles.get(role, [])) > 1:
            raise ValueError(f"Graph has duplicate {role}")
    for role, basename in (("graph_notes", "notes.md"), ("graph_metadata", "metadata.json"),
                           ("graph_annotations", "annotations.json"), ("render_metadata", "render-metadata.ini")):
        if roles.get(role) and roles[role] != ["graph/" + basename]:
            raise ValueError(f"Graph has a nonstandard {role} path")
    if roles.get("graph_notes"):
        if zf.getinfo(roles["graph_notes"][0]).file_size > 16 * 1024 * 1024:
            raise ValueError("Graph note exceeds size limit")
        zf.read(roles["graph_notes"][0]).decode("utf-8")
    if roles.get("graph_metadata"):
        value = read_json_member(zf, roles["graph_metadata"][0])
        if not isinstance(value, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in value.items()):
            raise ValueError("Graph metadata is invalid")
    if roles.get("graph_annotations"):
        validate_annotations(read_json_member(zf, roles["graph_annotations"][0]))
    scientific_paths = roles.get("scientific_snapshot", [])
    if any(not name.startswith("graph/scientific/") for name in scientific_paths):
        raise ValueError("Graph scientific snapshot has a nonstandard path")
    native = "graph/scientific/native_v4_snapshot.tcldict" in scientific_paths
    if native:
        validate_native_graph_snapshot(zf, scientific_paths, state)
        metadata = read_json_member(zf, "graph/metadata.json") if roles.get("graph_metadata") else {}
        if metadata.get("renderer_owner") != "PLOT_DATASET_API_v4" or metadata.get("renderer_owner_api_version") != "1":
            raise ValueError("Native scientific snapshot requires matching Graph renderer ownership")
    for name in ([] if native else scientific_paths):
        relative = name[len("graph/scientific/"):]
        if relative not in {"snapshot.h5", "presentation.ini"} and not re.fullmatch(r"(?:\.gxtxt_plotmeta|private_session/metadata/plot\.dataset/plotspec_v2)/[A-Za-z0-9_.-]+\.ini", relative):
            raise ValueError("Graph snapshot contains an undeclared executable or unsupported resource")
    if scientific_paths and not native and ("graph/scientific/snapshot.h5" not in scientific_paths or
                             "graph/scientific/presentation.ini" not in scientific_paths):
        raise ValueError("Graph scientific snapshot is incomplete")
    for name in scientific_paths:
        if name.lower().endswith((".h5", ".hdf5")):
            validate_hdf5_member(zf, name)
    if "graph/scientific/presentation.ini" in scientific_paths:
        if zf.getinfo("graph/scientific/presentation.ini").file_size > MAX_MANIFEST:
            raise ValueError("Graph presentation INI exceeds size limit")
        portable_presentation(zf.read("graph/scientific/presentation.ini"))
    dependencies = manifest.get("dependencies", [])
    if not isinstance(dependencies, list):
        raise ValueError("Graph dependencies must be a list")
    seen_dependencies = set()
    for dep in dependencies:
        if not isinstance(dep, dict) or dep.get("resource_type") != "dataset" or not dep.get("embedded"):
            raise ValueError("Graph dependency declaration is invalid")
        dataset_id = dep.get("dataset_id", "")
        if not valid_id(dataset_id) or dataset_id in seen_dependencies or dep.get("prefix") != "datasets/" + dataset_id:
            raise ValueError("Graph Dataset dependency path is invalid")
        seen_dependencies.add(dataset_id)
        validate_dataset_tree(zf, manifest, dep["prefix"], dataset_id)
    for record in manifest["files"]:
        path, role = record["path"], record["role"]
        if path.startswith("graph/"):
            if role not in graph_roles:
                raise ValueError("Graph path has a Dataset role")
        elif not any(path.startswith("datasets/" + dataset_id + "/") for dataset_id in seen_dependencies):
            raise ValueError("Graph package has an undeclared Dataset dependency")


def extract(archive: Path, staging: Path) -> dict:
    manifest = inspect(archive)
    if staging.exists():
        raise ValueError("private staging path already exists")
    staging.mkdir(parents=True)
    try:
        with zipfile.ZipFile(archive) as zf:
            (staging / MANIFEST).write_bytes(zf.read(MANIFEST))
            for entry in manifest["files"]:
                name = entry["path"]
                target = staging / Path(name)
                target.parent.mkdir(parents=True, exist_ok=True)
                with zf.open(name) as source, target.open("xb") as dest:
                    shutil.copyfileobj(source, dest, 1024 * 1024)
                if target.stat().st_size != entry["size"] or sha256_file(target) != entry["sha256"]:
                    raise ValueError(f"staged resource integrity mismatch: {name}")
        return manifest
    except Exception:
        shutil.rmtree(staging)
        raise


def emit_fields(path: Path) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("field document must be a JSON object")
    for key, value in sorted(data.items()):
        if not isinstance(value, str):
            raise ValueError("field document contains a non-string value")
        encoded = base64.b64encode(value.encode("utf-8")).decode("ascii")
        print(f"{key}\t{encoded}")


def emit_schema(path: Path) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError("schema document must be a JSON array")
    for index, variable in enumerate(data, 1):
        if not isinstance(variable, dict):
            raise ValueError("schema entry must be a JSON object")
        for key, value in sorted(variable.items()):
            if not isinstance(value, str):
                raise ValueError("schema value must be text")
            encoded = base64.b64encode(value.encode("utf-8")).decode("ascii")
            print(f"{index}\t{key}\t{encoded}")


def emit_dependencies(path: Path) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data.get("dependencies"), list):
        raise ValueError("missing dependency list")
    for dep in data["dependencies"]:
        if dep.get("resource_type") == "dataset" and dep.get("embedded"):
            print(dep["dataset_id"])


def emit_graph_state(path: Path) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    for key, value in sorted(data.items()):
        if isinstance(value, str):
            print(f"{key}\t{base64.b64encode(value.encode('utf-8')).decode('ascii')}")


def result_lines(values: dict) -> None:
    for key, value in values.items():
        if isinstance(value, (str, int)):
            print(f"{key}={value}")


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="op", required=True)
    ds = sub.add_parser("export-dataset")
    for field in ("session", "dataset_id", "archive", "version"):
        ds.add_argument(field)
    graph = sub.add_parser("export-graph")
    for field in ("session", "artifact", "state_tsv", "note", "metadata", "annotation",
                  "render_metadata", "scientific", "dependencies", "archive", "version"):
        graph.add_argument(field)
    workspace = sub.add_parser("export-workspace")
    for field in ("session", "plan", "archive", "version"):
        workspace.add_argument(field)
    valid = sub.add_parser("inspect")
    valid.add_argument("archive")
    stage = sub.add_parser("extract")
    stage.add_argument("archive")
    stage.add_argument("staging")
    fields = sub.add_parser("emit-fields")
    fields.add_argument("path")
    schema = sub.add_parser("emit-schema")
    schema.add_argument("path")
    deps = sub.add_parser("emit-dependencies")
    deps.add_argument("path")
    state = sub.add_parser("emit-graph-state")
    state.add_argument("path")
    args = parser.parse_args()
    if args.op == "export-dataset":
        session = Path(args.session).resolve()
        builder = Builder("dataset", args.version, session, {"dataset_id": args.dataset_id})
        builder.identity.update(builder.dataset(args.dataset_id))
        result_lines(builder.finish(Path(args.archive).resolve()))
    elif args.op == "export-graph":
        result_lines(export_graph(Path(args.session), Path(args.artifact), Path(args.state_tsv),
                                  args.note, args.metadata, args.annotation, args.render_metadata,
                                  args.scientific, args.dependencies, Path(args.archive).resolve(), args.version))
    elif args.op == "export-workspace":
        session = Path(args.session).resolve()
        fields, blobs = {}, []
        for line in Path(args.plan).read_text(encoding="utf-8").splitlines():
            key, value = line.split("\t", 1)
            if key == "blob":
                sha, encoded_owner = value.split("\t", 1)
                resource_owner = base64.b64decode(encoded_owner, validate=True).decode("ascii")
                if not re.fullmatch(r"[a-f0-9]{64}", sha) or not re.fullmatch(r"idoc_[0-9]{4,}", resource_owner):
                    raise ValueError("invalid workspace blob identity")
                blobs.append((sha, resource_owner))
            else:
                fields[key] = base64.b64decode(value, validate=True).decode("utf-8")
        payload = fields.pop("payload")
        owner = fields["workspace_id"]
        if not re.fullmatch(r"idoc_[0-9]{4,}", owner):
            raise ValueError("invalid workspace owner")
        builder = Builder("workspace", args.version, session, fields)
        builder.add("workspace/identity.json", "workspace_identity", json_bytes(fields))
        builder.add("workspace/payload.utf8", "workspace_payload", payload.encode("utf-8"))
        for sha, resource_owner in blobs:
            builder.add(f"workspace/blobs/{sha}.blob", "owned_resource",
                        within(session, f"metadata/interactive_document_resources/{resource_owner}/{sha}.blob"))
        note = within(session, f"notes/workspaces/{owner}.md")
        if note.is_file():
            builder.add("workspace/notes.md", "workspace_note", note)
        result_lines(builder.finish(Path(args.archive)))
    elif args.op == "inspect":
        manifest = inspect(Path(args.archive))
        identity = manifest["resource_identity"]
        dependencies = manifest.get("dependencies", [])
        if manifest["resource_type"] == "dataset":
            with zipfile.ZipFile(args.archive) as zf:
                registry = validate_dataset_tree(zf, manifest, "dataset", identity.get("dataset_id"))["registry"]
            contract = registry.get("contract", "")
            provider = registry.get("storage_provider", "")
            capture_mode = ""
            variable_ids = ";".join(registry.get(f"var{i}_variable_id", "") for i in range(1, int(registry.get("var_count", "0")) + 1))
        elif manifest["resource_type"] == "workspace":
            contract = identity["schema"]
            provider = identity["provider_id"]
            capture_mode = "workspace"
            variable_ids = ""
        else:
            contract = "graph"
            provider = identity.get("module_id", "")
            with zipfile.ZipFile(args.archive) as zf:
                capture_mode = read_json_member(zf, "graph/graph-state.json").get("capture_mode", "rendered")
            variable_ids = ""
        role_hashes = {entry["role"]: entry["sha256"] for entry in manifest["files"]
                       if entry["path"].startswith("dataset/" if manifest["resource_type"] == "dataset" else "graph/")}
        result_lines({"resource_type": manifest["resource_type"],
                      "source_gxtxt_version": manifest["source_gxtxt_version"],
                      "source_session_name": manifest.get("source_session_name", ""),
                      "file_count": len(manifest["files"]), "total_bytes": sum(x["size"] for x in manifest["files"]),
                      "resource_identity": json.dumps(identity, ensure_ascii=False),
                      "dataset_id": identity.get("dataset_id", ""), "module_id": identity.get("module_id", ""),
                      "graph_id": identity.get("graph_id", ""), "variant_id": identity.get("variant_id", ""),
                      "clone_id": identity.get("clone_id", ""), "contract": contract, "provider": provider,
                      "capture_mode": capture_mode,
                      "dependency_ids": ";".join(x["dataset_id"] for x in dependencies),
                      "dependency_count": len(dependencies),
                      "variable_ids": variable_ids, "archive_sha256": sha256_file(Path(args.archive)),
                      **{role + "_sha256": digest for role, digest in role_hashes.items()},
                      "integrity": "verified"})
    elif args.op == "extract":
        manifest = extract(Path(args.archive), Path(args.staging))
        result_lines({"staging": args.staging, "resource_type": manifest["resource_type"],
                      "file_count": len(manifest["files"]), "integrity": "verified"})
    elif args.op == "emit-fields":
        emit_fields(Path(args.path))
    elif args.op == "emit-schema":
        emit_schema(Path(args.path))
    elif args.op == "emit-dependencies":
        emit_dependencies(Path(args.path))
    elif args.op == "emit-graph-state":
        emit_graph_state(Path(args.path))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, zipfile.BadZipFile, json.JSONDecodeError) as exc:
        print(f"Portable Resource error: {exc}", file=sys.stderr)
        sys.exit(1)
