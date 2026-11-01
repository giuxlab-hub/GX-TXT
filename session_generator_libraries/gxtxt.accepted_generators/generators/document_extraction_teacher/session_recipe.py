"""Build a self-contained GX-TXT Session from generator-owned source definitions.

This module uses only Python's standard library. Generation does not import or
require the installed scientific Analysis modules; those run after Session open.
"""

from __future__ import annotations

import csv
import hashlib
import shutil
from pathlib import Path


def _sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _write_ini(path: Path, sections: list[tuple[str, list[tuple[str, str]]]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        for section, values in sections:
            stream.write(f"[{section}]\n")
            for key, value in values:
                value = str(value).replace("\n", " ").replace("\r", " ")
                stream.write(f"{key}={value}\n")
            stream.write("\n")


def _table(root: Path, recipe: dict, generator_id: str) -> tuple[str, list[tuple[str, str]]]:
    source_rel = recipe["source"]
    source = root / source_rel
    if not source.is_file():
        raise ValueError(f"Missing generator source {source_rel}")
    with source.open(newline="", encoding="utf-8-sig") as stream:
        reader = csv.reader(stream)
        columns = [item.strip() for item in next(reader)]
        if not columns or len(set(columns)) != len(columns):
            raise ValueError(f"Invalid column names in {source_rel}")
        samples = []
        rows = 0
        for row in reader:
            if len(row) != len(columns):
                raise ValueError(f"Ragged table at row {rows + 2} in {source_rel}")
            if rows < 100:
                samples.append(row)
            rows += 1
    if rows == 0:
        raise ValueError(f"Empty table {source_rel}")
    dataset_id = recipe["id"]
    relative = f"datasets/{dataset_id}.csv"
    canonical = root / relative
    canonical.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, canonical)
    digest = _sha(source)
    if _sha(canonical) != digest:
        raise ValueError(f"Canonical source copy differs for {dataset_id}")
    units = recipe.get("units", {})
    roles = recipe.get("roles", {})
    variable_ids = recipe.get("variable_ids", {})
    kinds = []
    for index, _ in enumerate(columns):
        try:
            for row in samples:
                if row[index].strip():
                    float(row[index])
            kinds.append("number")
        except ValueError:
            kinds.append("text")
    coordinate = next((columns[i] for i, kind in enumerate(kinds) if kind == "number"), "")
    fields = [
        ("id", dataset_id), ("kind", recipe.get("kind", "table.generic")),
        ("contract", recipe.get("kind", "table.generic")), ("format", "csv"),
        ("storage_kind", "text"), ("media_type", "text/csv"),
        ("path", relative), ("columns", ";".join(columns)),
        ("variables", ";".join(variable_ids.get(name, name) for name in columns)),
        ("units", ";".join(units.get(name, "") for name in columns)),
        ("semantic_roles", ";".join(roles.get(name, "independent" if name == coordinate else "measured") for name in columns)),
        ("source_module", f"session_generator.{generator_id}"),
        ("source_raw", source_rel), ("source_sha256", digest),
        ("canonical_sha256", digest), ("sha256", digest),
        ("row_count", str(rows)), ("sample_count", str(rows)),
        ("var_count", str(len(columns))), ("variable_schema_api_version", "3"),
        ("canonical_access_api_version", "2"), ("canonical_delimiter", "comma"),
        ("source_delimiter", "comma"),
    ]
    if recipe.get("provenance"):
        fields.append(("provenance", " ".join(
            item for pair in recipe["provenance"].items() for item in pair)))
    for index, name in enumerate(columns, 1):
        kind = kinds[index - 1]
        role = roles.get(name, "independent" if name == coordinate else "measured")
        fields.extend((f"var{index}_{key}", value) for key, value in [
            ("variable_id", variable_ids.get(name, f"v{index:04d}")), ("enabled", "1"),
            ("source_column", str(index)), ("canonical_position", str(index)),
            ("original_header", name), ("canonical", name),
            ("unit", units.get(name, "")), ("semantic_role", role),
            ("semantic_source", "generator"), ("semantic_reason", "Source-owned Session recipe"),
            ("value_kind", kind), ("dtype", "float64" if kind == "number" else "string"),
            ("rank", "1"), ("shape", str(rows)), ("dimension_ids", "row"),
            ("coordinate_variable_ids", "" if name == coordinate else variable_ids.get(coordinate, coordinate)),
            ("coordinate_role", "coordinate" if name == coordinate else "data"),
            ("axis_kind", "explicit" if name == coordinate else "none"),
            ("axis_origin", ""), ("axis_step", ""), ("axis_count", ""),
            ("component_ids", ""), ("group_id", generator_id),
        ])
    return dataset_id, fields


def _binary(root: Path, recipe: dict, generator_id: str) -> tuple[str, list[tuple[str, str]]]:
    source_rel = recipe["source"]
    source = root / source_rel
    if not source.is_file():
        raise ValueError(f"Missing generator source {source_rel}")
    dataset_id = recipe["id"]
    suffix = source.suffix.lower()
    relative = f"datasets/{dataset_id}{suffix}"
    canonical = root / relative
    canonical.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, canonical)
    digest = _sha(source)
    if _sha(canonical) != digest:
        raise ValueError(f"Canonical source copy differs for {dataset_id}")
    fields = [
        ("id", dataset_id), ("kind", recipe["kind"]), ("contract", recipe["kind"]),
        ("format", recipe.get("format", suffix.lstrip("."))), ("storage_kind", "binary"),
        ("media_type", recipe["media_type"]), ("path", relative),
        ("columns", ""), ("variables", ""), ("units", ""),
        ("semantic_roles", ""), ("var_count", "0"),
        ("variable_schema_api_version", "2"),
        ("source_module", f"session_generator.{generator_id}"),
        ("source_raw", source_rel), ("source_sha256", digest),
        ("canonical_sha256", digest), ("sha256", digest),
    ]
    return dataset_id, fields


def configure(root: Path, generator_id: str, datasets: list[dict], modules: list[dict],
              experiment: str, extra_manifest: list[tuple[str, list[tuple[str, str]]]] | None = None) -> None:
    """Write canonical Dataset registry and intentional runnable Manifest.

    ``datasets`` refer to source files already created in ``root/raw``. Each
    module may declare ``sources`` (role -> Dataset ID), ``bindings`` (role ->
    column name), and ``config``. A module can be enabled but left out of the
    automatic Analysis run by setting ``run=False``.
    """
    registry = [("registry", [("api_version", "1"), ("access_api_version", "2"),
                               ("inspection_api_version", "1"), ("session_mode", "analysis_only"),
                               ("count", str(len(datasets)))])]
    ids = set()
    for recipe in datasets:
        dataset_id, fields = (_binary(root, recipe, generator_id) if recipe.get("binary")
                              else _table(root, recipe, generator_id))
        if dataset_id in ids:
            raise ValueError(f"Duplicate Dataset ID {dataset_id}")
        ids.add(dataset_id)
        registry.append((f"dataset.{dataset_id}", fields))
    _write_ini(root / "metadata/datasets.ini", registry)

    enabled = [module["id"] for module in modules]
    run = [module["id"] for module in modules if module.get("run", True)]
    manifest = [
        ("pipeline", [("format", "2"), ("module_api_version", "1")]),
        ("session", [("mode", "analysis_only")]),
        ("experiment", [("name", experiment)]),
        ("module_state", [("enabled", ",".join(enabled)), ("run", ",".join(run))]),
        ("analysis_source_map_api", [("version", "1")]),
        ("dataset_variable_schema_api", [("version", "3")]),
    ]
    for module in modules:
        module_id = module["id"]
        config = module.get("config", {})
        if config:
            manifest.append((f"module_config.{module_id}", list(config.items())))
        bindings = module.get("bindings", {})
        if bindings:
            manifest.append((f"module_binding.{module_id}",
                             [(role, f"primary.{column}") for role, column in bindings.items()]))
        sources = module.get("sources", {})
        if sources:
            for source_id in sources.values():
                if source_id not in ids and not module.get("allow_derived_source"):
                    raise ValueError(f"{module_id} references missing Dataset {source_id}")
            manifest.append((f"module_analysis_sources.{module_id}",
                             [("ids", ";".join(sources))]))
            for role, dataset_id in sources.items():
                manifest.append((f"module_analysis_source.{module_id}.{role}",
                                 [("dataset_id", dataset_id)]))
        (root / "analysis" / module_id).mkdir(parents=True, exist_ok=True)
    manifest.extend(extra_manifest or [])
    _write_ini(root / "metadata/manifest.ini", manifest)
