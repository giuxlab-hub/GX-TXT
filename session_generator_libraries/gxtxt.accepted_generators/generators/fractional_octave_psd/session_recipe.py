"""Package-owned canonical Dataset and Analysis recipe for numerical examples.

This file is copied into each independent generator package at build time.
Generation uses only the Python standard library and does not load Analysis plugins.
"""

from __future__ import annotations

import csv
import hashlib
import shutil
from pathlib import Path


def _write_ini(path: Path, sections: list[tuple[str, list[tuple[str, str]]]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        for name, items in sections:
            stream.write(f"[{name}]\n")
            for key, value in items:
                if any(ch in str(value) for ch in "\r\n"):
                    raise ValueError(f"INI value {name}.{key} is multiline")
                stream.write(f"{key}={value}\n")
            stream.write("\n")


def _dataset(root: Path, item: dict[str, object], generator_id: str) -> tuple[str, list[tuple[str, str]]]:
    name = str(item["csv"])
    dataset_id = str(item["id"])
    source = root / "raw" / name
    with source.open(newline="", encoding="utf-8") as stream:
        reader = csv.reader(stream)
        columns = next(reader)
        rows = sum(1 for _ in reader)
    if not rows or not columns or len(set(columns)) != len(columns):
        raise ValueError(f"Source {name} has missing rows or invalid columns")
    roles = item.get("roles", {})
    units = item.get("units", {})
    if not isinstance(roles, dict) or not isinstance(units, dict):
        raise TypeError("roles and units must be dictionaries")
    coordinate = str(item.get("coordinate", columns[0]))
    if coordinate not in columns:
        raise ValueError(f"Coordinate {coordinate} is absent from {name}")
    relative = f"datasets/{dataset_id}.csv"
    canonical = root / relative
    canonical.parent.mkdir(parents=True, exist_ok=True)
    if item.get("missing_as_nan", False):
        with source.open(newline="", encoding="utf-8") as read_stream, \
             canonical.open("w", newline="", encoding="utf-8") as write_stream:
            reader = csv.reader(read_stream)
            writer = csv.writer(write_stream)
            for row in reader:
                writer.writerow(["NaN" if value in {"NA", "missing", "invalid"} else value
                                 for value in row])
    else:
        shutil.copyfile(source, canonical)
    source_digest = hashlib.sha256(source.read_bytes()).hexdigest()
    digest = hashlib.sha256(canonical.read_bytes()).hexdigest()
    contract = str(item.get("contract", "table.generic"))
    fields = [
        ("id", dataset_id), ("kind", contract), ("contract", contract),
        ("format", "csv"), ("storage_kind", "text"), ("media_type", "text/csv"),
        ("path", relative), ("columns", ";".join(columns)),
        ("variables", ";".join(columns)), ("units", ";".join(str(units.get(c, "")) for c in columns)),
        ("semantic_roles", ";".join(str(roles.get(c, "measured")) for c in columns)),
        ("source_module", f"session_generator.{generator_id}"),
        ("source_raw", f"raw/{name}"), ("source_sha256", source_digest),
        ("canonical_sha256", digest), ("sha256", digest),
        ("row_count", str(rows)), ("sample_count", str(rows)),
        ("var_count", str(len(columns))), ("variable_schema_api_version", "3"),
        ("canonical_access_api_version", "2"), ("canonical_delimiter", "comma"),
        ("source_delimiter", "comma"),
    ]
    for index, column in enumerate(columns, 1):
        prefix = f"var{index}_"
        role = str(roles.get(column, "measured"))
        unit = str(units.get(column, ""))
        fields.extend((prefix + key, value) for key, value in [
            ("variable_id", f"v{index:04d}"), ("enabled", "1"),
            ("source_column", str(index)), ("canonical_position", str(index)),
            ("original_header", column), ("canonical", column), ("unit", unit),
            ("semantic_role", role), ("semantic_source", "generator"),
            ("semantic_reason", "Package-owned numerical example recipe"),
            ("value_kind", "number"), ("dtype", "float64"), ("rank", "1"),
            ("shape", str(rows)), ("dimension_ids", "row"),
            ("coordinate_variable_ids", "" if column == coordinate else coordinate),
            ("coordinate_role", "coordinate" if column == coordinate else "data"),
            ("axis_kind", "explicit" if column == coordinate else "none"),
            ("axis_origin", ""), ("axis_step", ""), ("axis_count", ""),
            ("component_ids", ""), ("group_id", generator_id),
        ])
    return f"dataset.{dataset_id}", fields


def configure(root: Path, generator_id: str, datasets: list[dict[str, object]],
              analyses: list[dict[str, object]], temporal_sets: list[dict[str, str]] | None = None) -> None:
    if not datasets or not analyses:
        raise ValueError("A runnable numerical Session needs sources and Analysis")
    ids = [str(d["id"]) for d in datasets]
    if len(set(ids)) != len(ids):
        raise ValueError("Duplicate canonical Dataset ID")
    dataset_sections = [("registry", [
        ("api_version", "1"), ("access_api_version", "2"),
        ("inspection_api_version", "1"), ("session_mode", "analysis_only"),
        ("count", str(len(datasets))),
    ])]
    dataset_sections.extend(_dataset(root, item, generator_id) for item in datasets)
    _write_ini(root / "metadata/datasets.ini", dataset_sections)
    modules = [str(item["module"]) for item in analyses]
    if len(set(modules)) != len(modules):
        raise ValueError("Duplicate Analysis module")
    initial_runs = [str(item["module"]) for item in analyses if item.get("initial_run", True)]
    sections = [
        ("pipeline", [("format", "2"), ("module_api_version", "1")]),
        ("session", [("mode", "analysis_only")]),
        ("experiment", [("name", f"Numerical example: {generator_id}")]),
        ("module_state", [("enabled", ",".join(modules)), ("run", ",".join(initial_runs))]),
        ("analysis_source_map_api", [("version", "1")]),
        ("dataset_variable_schema_api", [("version", "3")]),
    ]
    for item in analyses:
        module = str(item["module"])
        source = str(item["source"])
        if source not in ids and not item.get("derived_source", False):
            raise ValueError(f"Analysis {module} refers to unknown source {source}")
        bindings = item.get("bindings", {})
        config = item.get("config", {})
        if not isinstance(bindings, dict) or not isinstance(config, dict):
            raise TypeError("Analysis bindings and config must be dictionaries")
        sections.extend([
            (f"module_config.{module}", [(str(k), str(v)) for k, v in config.items()]),
            (f"module_binding.{module}", [(str(k), f"primary.{v}") for k, v in bindings.items()]),
            (f"module_analysis_sources.{module}", [("ids", "primary")]),
            (f"module_analysis_source.{module}.primary", [("dataset_id", source)]),
        ])
        (root / "analysis" / module).mkdir(parents=True, exist_ok=True)
    temporal_sets = temporal_sets or []
    if temporal_sets:
        sections.append(("temporal_set_api", [("version", "1"),
                                               ("ids", ";".join(v["id"] for v in temporal_sets))]))
        for item in temporal_sets:
            sections.append((f"temporal_set.{item['id']}", list(item.items())))
    _write_ini(root / "metadata/manifest.ini", sections)
