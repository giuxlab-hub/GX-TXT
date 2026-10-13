"""Source-owned Session recipe for the cross-spectral transfer generator.

The recipe writes a canonical table and the public persisted Analysis bindings.
It uses only Python's standard library, so generation needs no Analysis plugin.
"""

from __future__ import annotations

import csv
import hashlib
import shutil
from pathlib import Path


def _ini(path: Path, sections):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        for section, values in sections:
            stream.write(f"[{section}]\n")
            for key, value in values:
                stream.write(f"{key}={value}\n")
            stream.write("\n")


def configure(root: Path, csv_name: str, dataset_id: str, module_id: str,
              roles: dict[str, str], bindings: dict[str, str], config: dict[str, str],
              units: dict[str, str] | None = None):
    units = units or {}
    source = root / "raw" / csv_name
    with source.open(newline="", encoding="utf-8") as stream:
        reader = csv.reader(stream)
        columns = next(reader)
        row_count = sum(1 for _ in reader)
    if not columns or row_count == 0 or set(bindings.values()) - set(columns):
        raise ValueError("Numerical example source columns or rows are missing")

    relative = f"datasets/{dataset_id}.csv"
    canonical = root / relative
    canonical.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, canonical)
    digest = hashlib.sha256(canonical.read_bytes()).hexdigest()
    fields = [
        ("id", dataset_id), ("kind", "table.generic"), ("contract", "table.generic"),
        ("format", "csv"), ("storage_kind", "text"), ("media_type", "text/csv"),
        ("path", relative), ("columns", ";".join(columns)),
        ("variables", ";".join(columns)), ("units", ";".join(units.get(name, "") for name in columns)),
        ("semantic_roles", ";".join(roles.get(name, "measured") for name in columns)),
        ("source_module", "session_generator.cross_spectral_transfer"),
        ("source_raw", f"raw/{csv_name}"), ("source_sha256", digest),
        ("canonical_sha256", digest), ("sha256", digest),
        ("row_count", str(row_count)), ("sample_count", str(row_count)),
        ("var_count", str(len(columns))), ("variable_schema_api_version", "3"),
        ("canonical_access_api_version", "2"), ("canonical_delimiter", "comma"),
        ("source_delimiter", "comma"),
    ]
    for index, name in enumerate(columns, 1):
        prefix = f"var{index}_"
        fields.extend((prefix + key, value) for key, value in [
            ("variable_id", f"v{index:04d}"), ("enabled", "1"),
            ("source_column", str(index)), ("canonical_position", str(index)),
            ("original_header", name), ("canonical", name), ("unit", units.get(name, "")),
            ("semantic_role", roles.get(name, "measured")),
            ("semantic_source", "generator"), ("semantic_reason", "Cross-spectral transfer source recipe"),
            ("value_kind", "number"), ("dtype", "float64"), ("rank", "1"),
            ("shape", str(row_count)), ("dimension_ids", "row"),
            ("coordinate_variable_ids", "" if index == 1 else columns[0]),
            ("coordinate_role", "coordinate" if index == 1 else "data"),
            ("axis_kind", "explicit" if index == 1 else "none"),
            ("axis_origin", ""), ("axis_step", ""), ("axis_count", ""),
            ("component_ids", ""), ("group_id", "numerical_example"),
        ])
    _ini(root / "metadata/datasets.ini", [
        ("registry", [("api_version", "1"), ("access_api_version", "2"),
                       ("inspection_api_version", "1"), ("session_mode", "analysis_only"),
                       ("count", "1")]),
        (f"dataset.{dataset_id}", fields),
    ])
    manifest = [
        ("pipeline", [("format", "2"), ("module_api_version", "1")]),
        ("session", [("mode", "analysis_only")]),
        ("experiment", [("name", f"Numerical example: {csv_name.removesuffix('.csv')}")]),
        ("module_state", [("enabled", module_id), ("run", module_id)]),
        (f"module_config.{module_id}", list(config.items())),
        (f"module_binding.{module_id}", [(role, f"primary.{column}") for role, column in bindings.items()]),
        ("analysis_source_map_api", [("version", "1")]),
        (f"module_analysis_sources.{module_id}", [("ids", "primary")]),
        (f"module_analysis_source.{module_id}.primary", [("dataset_id", dataset_id)]),
        ("dataset_variable_schema_api", [("version", "3")]),
    ]
    _ini(root / "metadata/manifest.ini", manifest)
    (root / "analysis" / module_id).mkdir(parents=True, exist_ok=True)
