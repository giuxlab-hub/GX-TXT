#!/usr/bin/env python3
"""Build ordinary GX-TXT analysis and Workbench plugin ZIPs around exact research scripts."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import sys
import tempfile
import subprocess
import os
import uuid
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


ID = re.compile(r"^[A-Za-z][A-Za-z0-9._-]*$")
KEY = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")
VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
API = re.compile(r"^[A-Za-z0-9_]+(?:@[0-9]+)?(?::[A-Za-z0-9._-]+)?(?:\+[A-Za-z0-9_|.-]+)?$")
PUBLIC_API = re.compile(r"^[A-Z][A-Z0-9_]*_v([1-9][0-9]*)$")
FIELD_TYPES = {"color", "double", "command", "dataset", "selection", "temporal_set", "number", "integer", "string", "text",
               "boolean", "choice", "file", "path", "unit", "model", "table"}
TABLE_COLUMN_TYPES = {"variable", "model", "choice", "integer", "number", "string", "text", "unit"}


def _declaration_parser():
    """Load the framework-owned static parser, never the researcher script."""
    parser_path = Path(__file__).resolve().parents[4] / "core/python/script_source_declaration_v1.py"
    spec = importlib.util.spec_from_file_location("gxtxt_script_source_declaration_v1", parser_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Analysis Sources parser is unavailable: {parser_path}")
    parser = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(parser)
    return parser


def declared_sources(source: Path) -> tuple[list[dict], str] | None:
    """Return ordinary Builder rows and a declaration fingerprint, if declared."""
    declaration = _declaration_parser().discover(source)
    if declaration is None:
        return None
    rows = [{"id": item["id"], "label": item["label"],
             "required": item["required"], "contracts": ";".join(item["contracts"]),
             "purpose": item["purpose"], "dataset_id": item["preferred_dataset"]}
            for item in declaration["sources"]]
    fingerprint = digest(json.dumps(declaration, ensure_ascii=False, sort_keys=True,
                                    separators=(",", ":")).encode("utf-8"))
    return rows, fingerprint


def _source_semantics(rows: list[dict]) -> list[tuple]:
    result = []
    for item in rows:
        contracts = item.get("contracts", "")
        if isinstance(contracts, list):
            contracts = ";".join(contracts)
        result.append((item.get("id"), bool(item.get("required", item.get("id") == "primary")),
                       tuple(part.strip() for part in str(contracts).replace(",", ";").split(";") if part.strip()),
                       item.get("dataset_id", "")))
    return result


def reconcile_sources(data: dict, source: Path) -> dict:
    """Resolve a project against its source declaration before descriptor output."""
    discovered = declared_sources(source)
    if discovered is None:
        if data.get("source_declaration_resolution"):
            raise ValueError("source_declaration_resolution is set, but this script has no declaration")
        return data
    rows, fingerprint = discovered
    manual = data.get("sources")
    resolution = data.get("source_declaration_resolution")
    if resolution is not None:
        if not isinstance(resolution, dict) or set(resolution) != {"choice", "declaration_sha256"}:
            raise ValueError("source_declaration_resolution needs choice and declaration_sha256")
        if resolution["choice"] not in {"script", "manual"}:
            raise ValueError("source_declaration_resolution choice must be script or manual")
        if resolution["declaration_sha256"] != fingerprint:
            raise ValueError("script Analysis Sources declaration changed; review the conflict again")
    if manual is not None and _source_semantics(manual) != _source_semantics(rows):
        if resolution is None:
            raise ValueError("Builder sources conflict with the script Analysis Sources declaration; "
                             "review and choose script or manual sources explicitly")
        if resolution["choice"] == "manual":
            return data
    data["sources"] = rows
    return data


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _provided_parser():
    """Load the one CORE in-memory extractor; never import researcher code."""
    path = Path(__file__).resolve().parents[4] / "core/python/script_api_exports.py"
    dependency_path = path.with_name("script_api_declarations.py")
    dependency = sys.modules.get("script_api_declarations")
    if dependency is not None and Path(getattr(dependency, "__file__", "")).resolve() != dependency_path:
        raise RuntimeError("CORE declaration module conflicts with an already-loaded module")
    if dependency is None:
        dependency_spec = importlib.util.spec_from_file_location("script_api_declarations", dependency_path)
        if dependency_spec is None or dependency_spec.loader is None:
            raise RuntimeError("CORE declaration owner is unavailable")
        dependency = importlib.util.module_from_spec(dependency_spec)
        dependency_spec.loader.exec_module(dependency)
        sys.modules["script_api_declarations"] = dependency
    spec = importlib.util.spec_from_file_location("gxtxt_script_provided_inventory", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("CORE provided API inventory is unavailable")
    owner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(owner)
    return owner


def _source_relative(value: str, suffix: str) -> str:
    value = single(value, "relative source")
    path = Path(value)
    if (path.is_absolute() or path.as_posix() != value or "\\" in value
            or not path.parts or any(not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.-]*", part)
                                     or part in {".", ".."} for part in path.parts)
            or path.suffix != suffix):
        raise ValueError("source entrypoint must be an admitted language-relative path")
    return value


def _provided_inventory(data: dict, files: list[tuple[Path, str, bytes]], entrypoint: str) -> dict:
    suffix = ".py" if data["language"] == "Python" else ".m"
    sources = {entrypoint: files[0][2]}
    for _, target, body in files[1:]:
        relative = target.removeprefix("bundle/")
        if Path(relative).suffix == suffix:
            sources[relative] = body
    return _provided_parser().discover_project_exports(data["language"], entrypoint, sources)


def _core_interpreter(interpreter=None, session=None):
    """Trusted tool host of existing public owners; no Registry parser/store."""
    import tkinter
    interpreter = interpreter or tkinter.Tcl()
    root = Path(__file__).resolve().parents[4]
    if not interpreter.call("info", "commands", "::GX::scriptRegistryDescribe"):
        interpreter.call("set", "argv0", "__gxtxt_script_builder_host__")
        interpreter.call("source", str(root / "gxtxt_pipeline.tcl"))
        interpreter.call("::GX::defaults")
        interpreter.call("::GX::configurationLoad")
        interpreter.call("::GX::loadModuleCatalog")
    if session is not None:
        if session:
            interpreter.call("::GX::scriptRegistryRoot", "session", session)
        interpreter.call("set", "::GX::currentSession", session)
    return interpreter


def _tcl_dict(interpreter, value) -> dict:
    # Tk may expose shared Tcl key objects through nested Python tuples after
    # their internal representation shimmered. Preserve their Tcl string form.
    interpreter.call("set", "::GX::ScriptBuilderDictionary", value)
    keys = interpreter.splitlist(interpreter.eval("dict keys $::GX::ScriptBuilderDictionary"))
    return {key: interpreter.call("dict", "get", value, key) for key in keys}


def _tcl_text(interpreter, value) -> str:
    interpreter.call("set", "::GX::ScriptBuilderTextValue", value)
    return interpreter.eval("format %s $::GX::ScriptBuilderTextValue")


def registry_source_snapshot(reference: str, session: str = "", expected: dict | None = None, host=None) -> dict:
    """Public Registry/Project snapshot; reference is not a chosen INI path."""
    if not re.fullmatch(r"(?:user|session):[A-Za-z][A-Za-z0-9_.-]*", reference):
        raise ValueError("choose an existing qualified User or Session Script/Project")
    host = host or _core_interpreter()
    raw = host.call("::GX::scriptRegistryDescribe", reference, session)
    metadata = _tcl_dict(host, raw)
    baseline = {"expected_"+key: _tcl_text(host,metadata[key]) for key in
                ("sha256", "revision", "record_sha256", "owner_context")}
    if expected is not None and expected != baseline:
        raise ValueError("Registered source/record/owner changed; reopen and review; the Builder draft is retained")
    suffix = ".py" if str(metadata["language"]) == "Python" else ".m"
    if str(metadata["kind"]) == "project":
        entrypoint = str(metadata["entrypoint"])
        codes = _tcl_dict(host, host.call("::GX::scriptRegistryProjectFiles", raw))
        root = Path(str(metadata["project_root"]))
        paths = {str(name): root / str(name) for name in codes}
    else:
        entrypoint = "source" + suffix
        chosen = _tcl_dict(host, host.call("::GX::scriptRegistryReadChosenSource", metadata["source_path"]))
        if str(chosen["sha256"]) != str(metadata["sha256"]):
            raise ValueError("Registered source changed while reading")
        codes = {entrypoint: chosen["source"]}
        paths = {entrypoint: Path(str(metadata["source_path"]))}
    # Ask the public owner to enforce its complete expected identity again.
    options = host.call("dict", "create", *[part for item in baseline.items() for part in item])
    host.call("::GX::scriptRegistryProvidedApiInventory", reference, options, session)
    for relative, code in codes.items():
        if paths[relative].read_bytes() != _tcl_text(host,code).encode("utf-8"):
            raise ValueError("Public admitted source bytes changed before Builder intake")
    return {"reference": reference, "session": session, "baseline": baseline,
            "metadata": metadata, "entrypoint": entrypoint, "paths": paths}


def source_inspection(data: dict, anchor: Path) -> dict:
    """Bounded saved-file inspection in the existing managed auxiliary worker."""
    language = data.get("language")
    if language not in {"Python", "Octave"}:
        raise ValueError("Choose Python or GNU Octave")
    suffix = ".py" if language == "Python" else ".m"
    source = resolve_input(anchor, single(data.get("source", ""), "source"))
    if not source.is_file() or source.suffix != suffix:
        raise ValueError("Choose an existing saved language source file first")
    entry = data.get("source_entrypoint", source.name)
    try:
        entry = _source_relative(entry, suffix)
    except ValueError:
        if "source_entrypoint" in data:
            raise
        entry = "main" + suffix
    selected = [(source, entry)]
    seen = {entry.casefold()}
    for item in data.get("bundle", []):
        path = resolve_input(anchor, single(item.get("source", ""), "bundle source"))
        relative = single(item.get("target", path.name), "bundle target")
        parts = Path(relative).parts
        if (Path(relative).is_absolute() or "\\" in relative or not parts or
                any(part in {".", ".."} for part in parts) or relative.casefold() in seen):
            raise ValueError("Unsafe or duplicate source roster target")
        if not path.is_file():
            raise ValueError("A source roster file is unavailable")
        seen.add(relative.casefold());selected.append((path, relative))
    if len(selected) > 256:
        raise ValueError("At most256 source roster entries can be inspected")
    if data.get("registry_source"):
        binding = data["registry_source"]
        snapshot = registry_source_snapshot(binding["reference"], binding["session"], binding["baseline"])
        if (entry != snapshot["entrypoint"] or set(relative for _, relative in selected) != set(snapshot["paths"]) or
                any(path.resolve() != snapshot["paths"][relative].resolve() for path, relative in selected)):
            raise ValueError("Registered project roster changed; refresh through the public source owner")
    records = [];files = [];total = 0
    for path, relative in selected:
        before = path.stat()
        code = Path(relative).suffix == suffix
        raw = b""
        if code:
            total += before.st_size
            if before.st_size > 4194304 or total > 16777216:
                raise ValueError("Static source inventory is bounded to4MiB/file and16MiB/project")
            raw = path.read_bytes()
        after = path.stat()
        identity = lambda stat: [stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns]
        if identity(before) != identity(after):
            raise ValueError("Source file changed during inspection")
        records.append(dict(relative=relative, source=str(path), bytes=before.st_size,
                            sha256=digest(raw) if code else "asset: checksummed at Build",
                            role="entrypoint" if not records else "source" if code else "asset",
                            stat_identity=identity(after)))
        files.append((path, "bundle/"+relative, raw))
    inventory = _provided_inventory(data, files, entry)
    return dict(schema="gxtxt.builder_source_inspection.v1", entrypoint=entry, files=records,
                inventory=inventory, source_scope="registered_snapshot" if data.get("registry_source") else "saved_file_snapshot",
                execution_authority="none")


def managed_request(payload: dict) -> dict:
    """Fixed GUI auxiliary operations through the existing CORE Job owner."""
    operation = payload.get("operation")
    if operation == "inspect_source" and set(payload) == {"operation", "project", "anchor"}:
        return source_inspection(payload["project"], Path(payload["anchor"]))
    if operation == "registry_list" and set(payload) == {"operation", "session"}:
        host = _core_interpreter()
        records = host.splitlist(host.call("::GX::scriptRegistryList", "all", payload["session"]))
        rows = []
        for raw in records[:500]:
            item = _tcl_dict(host, raw)
            rows.append({key: _tcl_text(host,item[key]) for key in ("scope", "id", "name", "kind", "language", "revision")})
        return dict(rows=rows, truncated=len(records)>500)
    if operation == "registry_snapshot" and set(payload) == {"operation", "reference", "session"}:
        host = _core_interpreter()
        snapshot = registry_source_snapshot(payload["reference"], payload["session"], host=host)
        return dict(reference=snapshot["reference"], session=snapshot["session"], baseline=snapshot["baseline"],
                    entrypoint=snapshot["entrypoint"], paths={key: str(value) for key,value in snapshot["paths"].items()},
                    metadata={key: _tcl_text(host,snapshot["metadata"].get(key, "")) for key in ("id", "name", "description", "version", "language", "kind", "explicit_apis")})
    if operation in {"validate", "build"} and set(payload) == {"operation", "project_path", "project_sha256", "output", "inventory_sha256"}:
        project = Path(payload["project_path"])
        if digest(project.read_bytes()) != payload["project_sha256"]:
            raise ValueError("Saved Builder project changed before admission")
        data, files = validate(project)
        if digest(project.read_bytes()) != payload["project_sha256"]:
            raise ValueError("Saved Builder project changed during validation")
        manifest_sha = digest(provided_manifest_bytes(data))
        if payload["inventory_sha256"] and payload["inventory_sha256"] != manifest_sha:
            raise ValueError("Saved source API inventory changed since review; refresh and validate before Build")
        result = dict(status="VALIDATED", module_id=data["id"], version=data["version"], language=data["language"],
                      source_sha256=digest(files[0][2]), inventory_sha256=manifest_sha)
        if operation == "build":
            package, sha = _build_validated(data, files, Path(payload["output"]))
            result.update(status="BUILT", package=str(package), sha256=sha)
        return result
    raise ValueError("Unknown fixed Builder auxiliary request")


def single(value: object, label: str) -> str:
    result = str(value)
    if any(c in result for c in "\r\n\x00"):
        raise ValueError(f"{label} must be one line")
    return result


def resolve_input(project: Path, value: str) -> Path:
    path = Path(value)
    return (path if path.is_absolute() else project.parent / path).resolve()


def validate(project_path: Path) -> tuple[dict, list[tuple[Path, str, bytes]]]:
    project_path = project_path.resolve()
    data = json.loads(project_path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or data.get("schema_version") != 1:
        raise ValueError("Builder project requires schema_version 1")
    module_id = single(data.get("id", ""), "module ID")
    if not ID.fullmatch(module_id):
        raise ValueError("module ID must start with a letter and use letters, digits, dot, underscore or hyphen")
    version = single(data.get("version", ""), "version")
    if not VERSION.fullmatch(version):
        raise ValueError("version must be major.minor.patch")
    for key in ("name", "description", "group", "license", "profile"):
        if not single(data.get(key, ""), key):
            raise ValueError(f"{key} is required")
    if data["profile"] not in ("A", "B", "W"):
        raise ValueError("profile must be A, B or W (Workbench extension)")
    if data["profile"] == "W":
        validate_workbench_extension(data)
    language = single(data.get("language", ""), "language")
    if language not in ("Octave", "Python"):
        raise ValueError("language must be Octave or Python")
    suffix = ".m" if language == "Octave" else ".py"
    source_value = single(data.get("source", ""), "source")
    source = resolve_input(project_path, source_value)
    if not source.is_file() or source.suffix != suffix:
        raise ValueError(f"authoritative source must be an existing {suffix} file")
    if source.is_symlink():
        raise ValueError("source symlinks are not supported")
    data = reconcile_sources(data, source)
    data.setdefault("sources", [] if data["profile"] == "W" else [{"id": "primary", "required": True}])
    original_entrypoint = data.get("source_entrypoint", source.name)
    try:
        original_entrypoint = _source_relative(original_entrypoint, suffix)
    except ValueError:
        if "source_entrypoint" in data:
            raise
        # Ordinary legacy files may have names outside Project's source grammar;
        # their existing actual packaged entrypoint remains main.py/main.m.
        original_entrypoint = "main" + suffix
    files = [(source, "bundle/main" + suffix, source.read_bytes())]
    seen_names = {files[0][1].casefold()}
    for item in data.get("bundle", []):
        if not isinstance(item, dict):
            raise ValueError("bundle entries must be objects")
        path = resolve_input(project_path, single(item.get("source", ""), "bundle source"))
        rel = single(item.get("target", path.name), "bundle target")
        parts = Path(rel).parts
        if not parts or Path(rel).is_absolute() or any(p in (".", "..") for p in parts) or "\\" in rel:
            raise ValueError(f"unsafe bundle target: {rel}")
        if rel.casefold() in seen_names or rel.casefold() == ("main" + suffix).casefold():
            raise ValueError(f"duplicate bundle target: {rel}")
        if not path.is_file() or path.is_symlink():
            raise ValueError(f"bundle source is unavailable: {path}")
        if path.suffix in (".m", ".py") and path.suffix != suffix:
            raise ValueError("helper language must match the main script")
        seen_names.add(rel.casefold())
        files.append((path, "bundle/" + rel, path.read_bytes()))
    if any(rel.casefold() == ("bundle/" + original_entrypoint).casefold()
           for _, rel, _ in files[1:]):
        if "source_entrypoint" in data:
            raise ValueError("entrypoint collides with another admitted project file")
        original_entrypoint = "main" + suffix
    inventory = _provided_inventory(data, files, original_entrypoint)
    if inventory["provided"] and not inventory["valid"]:
        reasons = "; ".join(item["message"] for item in inventory["diagnostics"] if item["severity"] == "error")
        raise ValueError("Source-declared provided APIs are invalid; no partial operations published: " + reasons)
    data["_provided_inventory"] = inventory
    data["_provided_entrypoint"] = original_entrypoint
    if inventory["provided"] or "source_entrypoint" in data:
        files[0] = (source, "bundle/" + original_entrypoint, files[0][2])
    binding = data.get("registry_source")
    if binding is not None:
        if not isinstance(binding, dict) or set(binding) != {"reference", "session", "baseline"}:
            raise ValueError("registry_source requires reference, session and complete public baseline")
        snapshot = registry_source_snapshot(binding["reference"], binding["session"], binding["baseline"])
        actual_paths = {original_entrypoint: source, **{rel.removeprefix("bundle/"): path for path, rel, _ in files[1:]}}
        if (snapshot["entrypoint"] != original_entrypoint or set(actual_paths) != set(snapshot["paths"])
                or any(actual_paths[name].resolve() != snapshot["paths"][name].resolve() for name in actual_paths)):
            raise ValueError("Builder source roster differs from registered Project; save/review through the existing source Workspace first")
    source_ids = set()
    for item in data.get("sources", [{"id": "primary", "required": True}]):
        if not isinstance(item, dict):
            raise ValueError("Analysis Source entries must be objects")
        sid = single(item.get("id", ""), "source ID")
        if not KEY.fullmatch(sid) or sid in source_ids:
            raise ValueError(f"invalid or duplicate Analysis Source ID: {sid}")
        source_ids.add(sid)
        if type(item.get("required", sid == "primary")) is not bool:
            raise ValueError(f"source {sid} required must be a JSON boolean")
        contracts = single(item.get("contracts", ""), "source contract")
        if contracts and any(not ID.fullmatch(part.strip()) for part in contracts.replace(",", ";").split(";")):
            raise ValueError(f"source {sid} has an invalid Dataset contract")
        for key in ("label", "purpose", "dataset_id"):
            if key in item:
                single(item[key], f"source {sid} {key}")
    if data["profile"] != "W" and "primary" not in source_ids:
        raise ValueError("sources must include primary")
    if data["profile"] != "W" and not next(item for item in data["sources"] if item["id"] == "primary").get("required", True):
        raise ValueError("primary Analysis Source must be required")
    field_ids = set()
    for item in data.get("fields", []):
        fid = single(item.get("id", ""), "field ID")
        kind = single(item.get("type", ""), "field type")
        if not KEY.fullmatch(fid) or fid in field_ids or fid in {"script_file", "required_apis"}:
            raise ValueError(f"invalid or duplicate field ID: {fid}")
        if kind not in FIELD_TYPES:
            raise ValueError(f"unsupported Standard Module field type: {kind}")
        for key in ("label", "default", "values", "extensions", "path_kind", "dialog_title"):
            if key in item:
                single(item[key], f"field {fid} {key}")
        if kind == "choice" and not item.get("values"):
            raise ValueError(f"choice field {fid} needs values")
        if kind == "table":
            columns = item.get("columns")
            if not isinstance(columns, list) or not columns:
                raise ValueError(f"table field {fid} needs a nonempty columns list")
            column_ids = set()
            for column in columns:
                if not isinstance(column, dict):
                    raise ValueError(f"table field {fid} columns must be objects")
                cid = single(column.get("id", ""), "table column ID")
                ctype = single(column.get("type", "string"), "table column type")
                if not KEY.fullmatch(cid) or cid in column_ids or ctype not in TABLE_COLUMN_TYPES:
                    raise ValueError(f"table field {fid} has an invalid or duplicate column {cid}")
                if ctype == "choice" and not column.get("values"):
                    raise ValueError(f"table field {fid} choice column {cid} needs values")
                column_ids.add(cid)
            for bound in ("min_rows", "max_rows"):
                if bound in item and (not isinstance(item[bound], int) or item[bound] < 0):
                    raise ValueError(f"table field {fid} {bound} must be a nonnegative integer")
            if item.get("max_rows", 10**9) < item.get("min_rows", 0):
                raise ValueError(f"table field {fid} max_rows is below min_rows")
        field_ids.add(fid)
    bind_ids = set()
    for item in data.get("bindings", []):
        bid = single(item.get("id", ""), "binding ID")
        if not KEY.fullmatch(bid) or bid in bind_ids or bid in field_ids:
            raise ValueError(f"invalid or duplicate variable binding: {bid}")
        bind_ids.add(bid)
    for requirement in data.get("required_apis", []):
        if not API.fullmatch(single(requirement, "API requirement")):
            raise ValueError(f"invalid required API declaration: {requirement}")
    exposure = data.get("public_api")
    if exposure and any(api["id"] == exposure.get("id") for api in inventory["provided"]):
        raise ValueError("Legacy manual public_api collides with a source-declared API; explicitly keep one declaration")
    if exposure is not None:
        if not isinstance(exposure, dict):
            raise ValueError("public_api must be an object")
        match = PUBLIC_API.fullmatch(single(exposure.get("id", ""), "public API ID"))
        if not match or int(match.group(1)) != exposure.get("version"):
            raise ValueError("public API ID suffix and positive version must agree")
        if not exposure.get("operations"):
            raise ValueError("public API exposure needs at least one operation")
        operation_ids = set()
        for operation in exposure["operations"]:
            op_id = single(operation.get("id", ""), "operation ID")
            if not KEY.fullmatch(op_id) or op_id in operation_ids:
                raise ValueError(f"invalid or duplicate public operation: {op_id}")
            operation_ids.add(op_id)
            if not operation.get("summary") or not operation.get("result_contract"):
                raise ValueError(f"public operation {op_id} needs summary and result_contract")
            if operation.get("read_only", False):
                raise ValueError(f"script-backed analysis operation {op_id} mutates Session state")
            argument_ids = set()
            optional_seen = False
            for argument in operation.get("arguments", []):
                arg_id = single(argument.get("name", ""), "argument name")
                if not KEY.fullmatch(arg_id) or arg_id in argument_ids:
                    raise ValueError(f"invalid or duplicate argument: {arg_id}")
                argument_ids.add(arg_id)
                if not argument.get("required", True):
                    optional_seen = True
                elif optional_seen:
                    raise ValueError(f"public operation {op_id} places a required argument after an optional argument")
                target = single(argument.get("target", ""), "argument target")
                if target.startswith("config."):
                    valid = target[7:] in field_ids
                elif target.startswith("binding."):
                    valid = target[8:] in bind_ids
                elif target.startswith("source."):
                    valid = target[7:] in source_ids
                else:
                    valid = False
                if not valid:
                    raise ValueError(f"argument {arg_id} has unknown target {target}")
                single(argument.get("kind", "string"), "argument kind")
                single(argument.get("options", ""), "argument options")
    if data["profile"] == "B" and not data.get("scientific_method"):
        raise ValueError("Profile B requires scientific_method documentation")
    # Older schema_version=1 projects acquire only an explicit safe empty policy.
    # Preserve every other project field; scientific source bytes stay unchanged.
    data.setdefault("duplication_policy", {"experiment_duplication.api_version": 1})
    validate_duplication_policy(data, files)
    return data, files


def policy_sections(data: dict) -> list[str]:
    policy = data.get("duplication_policy", {"experiment_duplication.api_version": 1})
    if not isinstance(policy, dict):
        raise ValueError("duplication_policy must be a flat public module.ini dictionary")
    sections = {}
    for key, value in policy.items():
        if not isinstance(key, str) or not re.fullmatch(
                r"(?:experiment_duplication|duplication_document\.[A-Za-z_][A-Za-z0-9_-]*)\.[A-Za-z_][A-Za-z0-9_]*", key):
            raise ValueError(f"Not a public duplication policy key: {key}")
        if not isinstance(value, (str, int, bool, list)) or (isinstance(value, list) and
                any(not isinstance(item, str) for item in value)):
            raise ValueError(f"Policy value must be an INI scalar or string list: {key}")
        section, name = key.rsplit(".", 1)
        sections.setdefault(section, {})[name] = value
    return [ini_section(section, values) for section, values in sections.items()]


def validate_duplication_policy(data: dict, files: list) -> None:
    # Reuse the installed CORE's public validator and INI parser. No parallel
    # scientific classifier, provider callbacks or exact framework version pin.
    import tkinter
    framework = Path(__file__).resolve().parents[4]
    interp = tkinter.Tcl()
    interp.call("set", "argv0", "__builder_policy_validation__")
    interp.call("source", str(framework / "gxtxt_pipeline.tcl"))
    info = interp.call("::GX::experimentDuplicationPolicyInfo")
    if str(interp.call("dict", "get", info, "api_version")) != "1":
        raise ValueError("Experiment Duplication Policy API v1 is unavailable")
    with tempfile.TemporaryDirectory(prefix="gxtxt-builder-policy-") as folder:
        path = Path(folder) / "module.ini"
        path.write_text(descriptor(data, files), encoding="utf-8")
        result = interp.call("::GX::experimentDuplicationPolicyValidate",
                             interp.call("::GX::parseIni", str(path)))
    if not int(interp.call("dict", "get", result, "valid")):
        errors = interp.call("dict", "get", result, "errors")
        raise ValueError(f"Invalid Experiment Duplication Policy: {errors}")


def ini_section(name: str, values: dict) -> str:
    lines = [f"[{name}]"]
    for key, value in values.items():
        if isinstance(value, bool):
            value = int(value)
        elif isinstance(value, list):
            value = ";".join(map(str, value))
        lines.append(f"{key}={single(value, name + '.' + key)}")
    return "\n".join(lines) + "\n"


def workbench_ids(data):
    stem = re.sub(r"[^A-Za-z0-9_]", "_", data['id'])
    return 'WORKBENCH_SCRIPT_' + stem.upper() + '_API_v1', '::GX::GeneratedWorkbench_' + stem


def validate_workbench_extension(data):
    spec = data.get('workbench_extension')
    if not isinstance(spec, dict):
        raise ValueError('Workbench profile needs workbench_extension descriptor')
    if set(spec) - {'action_id','name','category','workbenches','selection_kinds','mutates'}:
        raise ValueError('Unknown Workbench extension descriptor field')
    if not KEY.fullmatch(single(spec.get('action_id',''), 'action ID')):
        raise ValueError('Workbench extension requires a stable action_id')
    categories = {'exporter','importer','tool','operation','measurement','geometry_generator','transform','validator','repair','analysis','utility'}
    if spec.get('category') not in categories:
        raise ValueError('Unknown Workbench action category')
    if not isinstance(spec.get('workbenches'),list) or not spec['workbenches'] or any(not ID.fullmatch(w) for w in spec['workbenches']):
        raise ValueError('Declare compatible Workbench IDs')
    if type(spec.get('mutates')) is not bool:
        raise ValueError('Workbench mutates must be a JSON boolean')
    if not isinstance(spec.get('selection_kinds',[]),list) or any(not KEY.fullmatch(k) for k in spec.get('selection_kinds',[])):
        raise ValueError('Declare valid selection kinds')
    if data.get('public_api'):
        raise ValueError('Workbench profile generates its own extension public API registration')
    if data.get('sources') or data.get('bindings'):
        raise ValueError('Workbench profile receives logical context; remove Analysis source/binding declarations')
    data.setdefault('required_apis',[])
    requirement = 'WORKBENCH_EXTENSION_API_v1@1:workbench_extension'
    if requirement not in data['required_apis']:
        data['required_apis'].append(requirement)


def workbench_descriptor(data, provided_ids=()):
    spec = data['workbench_extension']; api, namespace = workbench_ids(data)
    action = spec['action_id']; fields = data.get('fields',[])
    if api in provided_ids:
        raise ValueError('Source-declared API collides with the generated Workbench API')
    blocks = [ini_section('public_apis', {'ids':[api, *provided_ids]}),
              ini_section('public_api.'+api, {'api_version':1,'name':data['name'],'entrypoint':'api/workbench_api.tcl','namespace':namespace,'documentation':'api/WORKBENCH_API.md'}),
              ini_section('extensions', {'api_version':1,'ids':action}),
              ini_section('extension.'+action, {'name':spec.get('name',data['name']),'category':spec['category'],'workbenches':spec['workbenches'],'selection_kinds':spec.get('selection_kinds',[]),'mutates':spec['mutates'],'public_api':api,'command':namespace+'::invoke','parameters':[f['id'] for f in fields],'required_apis':['WORKBENCH_EXTENSION_API_v1']})]
    for field in fields:
        if field['type'] == 'table':
            raise ValueError('Workbench action parameters currently require scalar shared UI fields')
        values = {k:v for k,v in field.items() if k in {'type','label','default','required','min','max','values','alpha','allow_inherit'}}
        blocks.append(ini_section('extension.'+action+'.parameter.'+field['id'],values))
    return blocks


def workbench_api_files(data):
    api, namespace = workbench_ids(data); action=data['workbench_extension']['action_id']
    entry = (f'# Normal Workbench Extension API registration for {api}.\n'
             f'namespace eval {namespace} {{}}\n'
             f'proc {namespace}::invoke {{context}} {{\n'
             f'    return [::GX::workbenchExtensionScriptInvoke {{{data["id"]}}} {{{action}}} $context]\n'
             '}\n')
    docs = f"# {data['name']}\n\nPublic API: `{api}`. Workbench action: `{action}`.\n\nThe unchanged authoritative {data['language']} script runs through the shared CORE executor. It calls `WORKBENCH_EXTENSION_API_v1.script_context` and `return_result` with a bounded structured operation proposal. The Workbench owns validation, one transaction, Undo and rollback. No native handles or private Session paths enter the action context. Script/bundle hashes, parameters, plugin version and execution identity are recorded in provenance.\n"
    return {'api/workbench_api.tcl':entry.encode(), 'api/WORKBENCH_API.md':docs.encode()}


def descriptor(data: dict, files: list[tuple[Path, str, bytes]]) -> str:
    sources = data.get("sources", [{"id": "primary", "required": True}])
    fields = data.get("fields", [])
    bindings = data.get("bindings", [])
    apis = data.get("required_apis", [])
    blocks = ["; GX-TXT Standard Module API v1; generated by Script Module Builder 1.2.0\n",
              ini_section("meta", {"api_version": 1, "id": data["id"], "kind": "tool" if data["profile"] == "W" else "analysis",
                                   "group": data["group"], "name": data["name"], "version": data["version"],
                                   "selectable": 1, "default_enabled": 0, "core": 0, "runner": "script_module",
                                   "order": 797, "summary": data["description"],
                                   "description": data["description"]}),
              ini_section("inputs", {"contracts": data.get("input_contracts", "")}),
              ini_section("analysis_sources", {"api_version": 1, "ids": [s["id"] for s in sources], "dynamic": 0})]
    for source in sources:
        blocks.append(ini_section("analysis_source." + source["id"], {
            "required": source.get("required", source["id"] == "primary"), "contracts": source.get("contracts", ""),
            "dataset_id": source.get("dataset_id", "")}))
    blocks.append(ini_section("bindings", {"roles": [b["id"] for b in bindings]}))
    for binding in bindings:
        blocks.append(ini_section("binding." + binding["id"], {"label": binding.get("label", binding["id"]),
            "required": binding.get("required", True), "semantic_role": binding.get("semantic_role", "")}))
    outputs = data.get("outputs", {})
    blocks.append(ini_section("outputs", {"files": outputs.get("files", []), "datasets": outputs.get("datasets", [])}))
    blocks.append(ini_section("config", {"fields": [f["id"] for f in fields]}))
    for field in fields:
        values = {"type": field["type"], "label": field.get("label", field["id"]),
                  "default": field.get("default", ""), "required": field.get("required", False)}
        for key in ("values", "must_exist", "extensions", "path_kind", "dialog_title", "alpha", "allow_inherit", "persistent_default", "min", "max"):
            if key in field:
                values[key] = field[key]
        if field["type"] == "table":
            values.update({"dynamic": 1, "columns": [c["id"] for c in field["columns"]],
                           "min_rows": field.get("min_rows", 0)})
            if "max_rows" in field:
                values["max_rows"] = field["max_rows"]
        blocks.append(ini_section("config." + field["id"], values))
        if field["type"] == "table":
            for column in field["columns"]:
                values = {"type": column.get("type", "string"),
                          "label": column.get("label", column["id"]),
                          "required": column.get("required", False)}
                for key in ("default", "values", "source", "source_role", "kinds"):
                    if key in column:
                        values[key] = column[key]
                blocks.append(ini_section("config." + field["id"] + "." + column["id"], values))
    script_fields = {"api_version": 1, "language": data["language"],
        "main": files[0][1], "sha256": digest(files[0][2]), "profile": data["profile"],
        "required_apis": apis + (["SCRIPT_EXECUTION_API_v1@1+provided_function_jobs_v1|provided_bridge_control_arrays_v1"] if data["_provided_inventory"]["provided"] else []), "bundle_inventory": "bundle/SHA256SUMS"}
    inventory = data["_provided_inventory"]
    if inventory["provided"]:
        script_fields.update(provided_manifest="api/provided_operations.json",
                             provided_manifest_sha256=digest(provided_manifest_bytes(data)),
                             provided_entrypoint=data["_provided_entrypoint"])
    blocks.append(ini_section("script", script_fields))
    exposure = data.get("public_api")
    if (exposure or inventory["provided"]) and data["profile"] != "W":
        ids = ([exposure["id"]] if exposure else []) + [api["id"] for api in inventory["provided"]]
        blocks.append(ini_section("public_apis", {"ids": ids}))
    if exposure:
        namespace = "::GX::GeneratedScriptAPI_" + re.sub(r"[^A-Za-z0-9_]", "_", data["id"])
        blocks.append(ini_section("public_api." + exposure["id"], {
            "api_version": exposure["version"], "name": exposure.get("name", exposure["id"]),
            "entrypoint": "api/public_api.tcl", "namespace": namespace,
            "capabilities": exposure.get("capabilities", []), "documentation": "api/PUBLIC_API.md"}))
        blocks.append(ini_section("public_api_operations", {"ids": [op["id"] for op in exposure["operations"]]}))
        for operation in exposure["operations"]:
            op_id = operation["id"]
            blocks.append(ini_section("public_api_operation." + op_id, {
                "api_id": exposure["id"], "summary": operation["summary"],
                "result_contract": operation["result_contract"],
                "unit_behavior": operation.get("unit_behavior", "none"),
                "read_only": 0, "script_bridge": operation.get("script_bridge", False),
                "argument_ids": [argument["name"] for argument in operation.get("arguments", [])]}))
            for argument in operation.get("arguments", []):
                blocks.append(ini_section("public_api_argument." + op_id + "." + argument["name"], {
                    "kind": argument.get("kind", "string"), "required": argument.get("required", True),
                    "options": argument.get("options", ""), "target": argument["target"]}))
    for api in inventory["provided"]:
        namespace = provided_namespace(data["id"], api["id"])
        blocks.append(ini_section("public_api." + api["id"], {
            "api_version": api["version"], "name": api["name"], "operations": api["operations"],
            "entrypoint": "api/provided_api.tcl", "namespace": namespace,
            "documentation": "api/PROVIDED_API.md"}))
    blocks.append(ini_section("documentation", {"api_version": 1, "guide": "MANUAL.md",
        "changelog": "CHANGELOG.md", "examples": files[0][1]}))
    if data["profile"] == "W":
        blocks.extend(workbench_descriptor(data, [api["id"] for api in inventory["provided"]]))
    blocks.extend(policy_sections(data))
    return "\n".join(blocks)


def manual(data: dict, files: list[tuple[Path, str, bytes]]) -> str:
    lines = [f"# {data['name']}", "", data["description"], "", f"- Module ID: `{data['id']}`",
             f"- Version: `{data['version']}`", f"- Language: {data['language']}",
             f"- Profile: {data['profile']}", f"- License: {data['license']}",
             f"- Authoritative source SHA-256: `{digest(files[0][2])}`", "",
             "## Inputs", ""]
    for source in data.get("sources", [{"id": "primary", "required": True}]):
        lines.append(f"- Analysis Source `{source['id']}`: {'required' if source.get('required', True) else 'optional'}; contract `{source.get('contracts', '')}`")
    for binding in data.get("bindings", []):
        lines.append(f"- Variable `{binding['id']}`: {binding.get('label', binding['id'])}")
    lines.extend(["", "## Configuration", ""])
    for field in data.get("fields", []):
        lines.append(f"- `{field['id']}` ({field['type']}): {field.get('label', field['id'])}")
        if field["type"] == "table":
            lines.append("  Columns: " + ", ".join(f"`{c['id']}` ({c.get('type', 'string')})" for c in field["columns"]))
    lines.extend(["", "## Experiment duplication", "",
        "CORE owns Duplicate Experiment. Datasets, Workspaces, graphs, observations,",
        "scientific bindings, outputs and caches are excluded; modules start disabled.",
        "Unlisted settings reset to clean defaults. Only explicitly declared independent",
        "preparation is eligible; ownership and dependency validation still apply.",
        "The minimal policy copies no custom settings. Reconfigure fresh inputs before Run.",
        "No duplication code is injected into the research script.", "", "```ini",
        *policy_sections(data), "```", "", "## Required public APIs", ""])
    lines.extend([f"- `{item}`" for item in data.get("required_apis", [])] or ["None declared."])
    lines.extend(["", "## Expected outputs", ""])
    outputs = data.get("outputs", {})
    for name in outputs.get("datasets", []):
        lines.append(f"- Dataset `{name}`")
    for name in outputs.get("files", []):
        lines.append(f"- File `{name}`")
    lines.extend(["", "## Install and run", "", "Install the ZIP with Plugins → Install plugin. Enable the module in Modules,",
        ("choose its compatible Workbench Extensions action and configure the shared fields." if data["profile"] == "W" else "select its Dataset and variable inputs in Analysis, set its configuration, then Run."), "",
        "The original source bytes are unchanged. Each execution records the script SHA-256,",
        "module version, language and required APIs in Session provenance.", "",
        "Configuration is available through `gxtxt_context().parameters` in Python or",
        ("the Workbench action context from WORKBENCH_EXTENSION_API_v1.script_context in Octave or Python." if data["profile"] == "W" else "`gxtxt_context().parameters` in Octave; Dataset sources are in `.inputs`."), ""])
    if data["profile"] == "W":
        lines.extend(["## Workbench workflow", "", "Enable the installed module in Modules, then choose its action in the compatible Workbench Extensions dialog. Declarative parameters use shared UI fields. The unchanged script reads logical context and returns structured operations through WORKBENCH_EXTENSION_API_v1; the host commits one Undo transaction or rolls back.", ""])
    if data.get("documentation"):
        lines.extend(["## Researcher notes", "", str(data["documentation"]), ""])
    if data.get("scientific_method"):
        lines.extend(["## Scientific method", "", str(data["scientific_method"]), ""])
    if data.get("public_api"):
        lines.extend(["## Public API", "", f"`{data['public_api']['id']}` version {data['public_api']['version']} is provided by this module.",
            "Operations invoke the same authoritative script with structured arguments mapped to declared inputs and fields.", ""])
        for op in data["public_api"]["operations"]:
            lines.append(f"- `{op['id']}`: {op['summary']} ({op['result_contract']})")
        lines.append("")
    return "\n".join(lines)


def public_api_files(data: dict) -> dict[str, bytes]:
    exposure = data.get("public_api")
    if not exposure:
        return {}
    namespace = "::GX::GeneratedScriptAPI_" + re.sub(r"[^A-Za-z0-9_]", "_", data["id"])
    entry = (f"# Generated normal GX-TXT public API registration for {exposure['id']}.\n"
             f"namespace eval {namespace} {{}}\n"
             f"proc {namespace}::invoke {{operation arguments}} {{\n"
             f"    return [::GX::scriptModuleApiInvoke {{{data['id']}}} {{{exposure['id']}}} $operation $arguments]\n"
             "}\n")
    docs = [f"# {exposure.get('name', exposure['id'])}", "", f"API ID: `{exposure['id']}`. Provider: `{data['id']}`.", "",
            "Each operation is mutating and runs the authoritative script through shared GX-TXT execution.", ""]
    script_ops = {}
    for operation in exposure["operations"]:
        docs.extend([f"## {operation['id']}", "", operation["summary"], "", f"Result: {operation['result_contract']}.", ""])
        for argument in operation.get("arguments", []):
            docs.append(f"- `{argument['name']}` ({argument.get('kind', 'string')}): maps to `{argument['target']}`")
        docs.append("")
        if operation.get("script_bridge", False):
            script_ops[operation["id"]] = {
                "name": operation["id"], "summary": operation["summary"],
                "arguments": [{"name": a["name"], "kind": a.get("kind", "string"),
                               "required": a.get("required", True), "options": a.get("options", "")}
                              for a in operation.get("arguments", [])],
                "result_contract": operation["result_contract"],
                "argument_convention": ", ".join(a["name"] for a in operation.get("arguments", [])) or "no arguments",
                "result_convention": operation["result_contract"],
            }
    result = {"api/public_api.tcl": entry.encode(), "api/PUBLIC_API.md": "\n".join(docs).encode()}
    if script_ops:
        registration = {"api_id": exposure["id"], "api_version": exposure["version"],
            "provider_kind": "module", "provider_id": data["id"],
            "documentation_ref": "api/PUBLIC_API.md", "operations": script_ops}
        binding = ("\"\"\"Provider-owned Script Bridge binding generated by Module Builder.\"\"\"\n"
                   "from gxtxt_script_bridge_server import BridgeError\n\n"
                   f"REGISTRATION = {registration!r}\n\n"
                   "def invoke(host, operation, args):\n"
                   "    spec = REGISTRATION['operations'].get(operation)\n"
                   "    if spec is None:\n"
                   "        raise BridgeError('GXTXT:ScriptBridge:InvalidArguments', 'unknown public operation')\n"
                   "    minimum = sum(bool(field['required']) for field in spec['arguments'])\n"
                   "    if len(args) < minimum or len(args) > len(spec['arguments']):\n"
                   "        raise BridgeError('GXTXT:ScriptBridge:InvalidArguments', 'invalid public operation or argument count')\n"
                   "    values = {field['name']: value for field, value in zip(spec['arguments'], args)}\n"
                   "    module_id = REGISTRATION['provider_id']\n"
                   "    api_id = REGISTRATION['api_id']\n"
                   "    host.call('::GX::modulePublicApiActivate', module_id, api_id)\n"
                   "    result = host.call('::GX::scriptModuleApiInvoke', module_id, api_id, operation, values)\n"
                   "    return host.as_dict(result)\n")
        result["api/script_bridge_binding.py"] = binding.encode()
    return result


def provided_namespace(module_id: str, api_id: str) -> str:
    return "::GX::ProvidedScriptAPI_" + re.sub(r"[^A-Za-z0-9_]", "_", module_id) + "_" + digest(module_id.encode())[:12] + "_" + api_id


def provided_manifest_bytes(data: dict) -> bytes:
    return (json.dumps(data["_provided_inventory"], ensure_ascii=False, sort_keys=True,
                       separators=(",", ":"), allow_nan=False) + "\n").encode("utf-8")


def provided_api_files(data: dict, legacy: dict[str, bytes]) -> dict[str, bytes]:
    inventory = data["_provided_inventory"]
    if not inventory["provided"]:
        # Diagnostic only: no script.provided_manifest pointer and no authority.
        return {"api/provided_inventory_diagnostic.json": provided_manifest_bytes(data)}
    entries = ["# Source-derived registration; execution remains with existing CORE managed Jobs."]
    registrations = []
    docs = ["# Source-declared provided APIs", "", "Exact source/operation manifests are revalidated by CORE before managed function invocation.",
            "Static extraction alone grants no execution, Registry write or consumed API authority.", ""]
    for api in inventory["provided"]:
        namespace = provided_namespace(data["id"], api["id"])
        entries.extend([f"namespace eval {namespace} {{}}",
                        f"proc {namespace}::invoke {{operation arguments}} {{",
                        f"    return [::GX::scriptModuleApiInvoke {{{data['id']}}} {{{api['id']}}} $operation $arguments]", "}"])
        operations = {}
        docs.extend([f"## {api['id']} version{api['version']}", "", api["name"], ""])
        for op in inventory["operations"]:
            if op["api_id"] != api["id"]:
                continue
            operations[op["id"]] = dict(op, name=op["id"], argument_convention="ordered declared typed arguments",
                                        result_convention=op["result_contract"])
            impl = op["implementation"]
            docs.extend([f"### {op['id']}", "", op["summary"], "",
                         f"Implementation: `{impl['file']}:{impl['function']}` line{impl['line']}, SHA-256 `{impl['sha256']}`.",
                         f"Read only: `{op['read_only']}`. Unit behavior: {op['unit_behavior']}", "", "```json",
                         json.dumps({key: op[key] for key in ("arguments", "result", "effects", "capabilities", "required_apis")},
                                    ensure_ascii=False, indent=2, allow_nan=False), "```", ""])
        registrations.append(dict(api_id=api["id"], api_version=api["version"], provider_kind="module",
                                  provider_id=data["id"], documentation_ref="api/PROVIDED_API.md", operations=operations))
    binding_path = "api/script_bridge_binding.py"
    legacy_body = legacy.get(binding_path, b"").decode("utf-8")
    prefix = legacy_body + "\n" if legacy_body else "from gxtxt_script_bridge_server import BridgeError\n"
    binding = prefix + "import json\n" + f"PROVIDED_REGISTRATIONS = {registrations!r}\n"
    binding += "REGISTRATIONS = " + ("[REGISTRATION] + " if legacy_body else "") + "PROVIDED_REGISTRATIONS\n\n"
    binding += ("def invoke_api(host, api_id, operation, args):\n"
                "    registration = next((row for row in PROVIDED_REGISTRATIONS if row['api_id'] == api_id), None)\n"
                "    if registration is None:\n")
    binding += ("        return invoke(host, operation, args)\n" if legacy_body else
                "        raise BridgeError('GXTXT:ScriptBridge:UnknownAPI', 'unknown provided API')\n")
    binding += ("    spec = registration['operations'].get(operation)\n"
                "    if spec is None:\n"
                "        raise BridgeError('GXTXT:ScriptBridge:UnknownOperation', 'unknown provided operation')\n"
                "    minimum = sum(field['required'] for field in spec['arguments'])\n"
                "    if not minimum <= len(args) <= len(spec['arguments']):\n"
                "        raise BridgeError('GXTXT:ScriptBridge:InvalidArguments', 'provided argument count mismatch')\n"
                "    host.require([{'api_id': 'SCRIPT_EXECUTION_API_v1', 'api_version': 1, 'capabilities': ['provided_function_jobs_v1', 'provided_bridge_control_arrays_v1']}])\n"
                "    from gxtxt_script_provided_runtime import bridge_arguments_json\n"
                "    values = {field['name']: value for field, value in zip(spec['arguments'], args)}\n"
                "    try:\n"
                "        payload = bridge_arguments_json(values, spec)\n"
                "    except (ValueError, TypeError) as error:\n"
                "        raise BridgeError('GXTXT:ScriptBridge:InvalidArguments', str(error)) from error\n"
                "    host.call('::GX::modulePublicApiActivate', registration['provider_id'], api_id)\n"
                "    result = host.call('::GX::scriptModuleProvidedApiInvokeJson', registration['provider_id'], api_id, operation, payload)\n"
                "    return json.loads(result)\n")
    return {"api/provided_operations.json": provided_manifest_bytes(data),
            "api/provided_api.tcl": ("\n".join(entries) + "\n").encode("utf-8"),
            "api/PROVIDED_API.md": ("\n".join(docs) + "\n").encode("utf-8"),
            binding_path: binding.encode("utf-8")}


def module_package_payload(payload: dict[str, bytes]) -> dict[str, bytes]:
    """Normalize conventional root checksums without self/cross-manifest cycles.

    Existing legacy packages may carry both spellings. They have identical
    coverage of every other member; keep that convention and refresh both.
    New Builder packages continue to receive SHA256SUMS.txt only.
    """
    dual = 'SHA256SUMS' in payload
    result = {name: raw for name, raw in payload.items() if name not in {'SHA256SUMS', 'SHA256SUMS.txt'}}
    manifest = ''.join(f'{digest(result[name])}  {name}\n' for name in sorted(result)).encode()
    result['SHA256SUMS.txt'] = manifest
    if dual:
        result['SHA256SUMS'] = manifest
    return result


def write_module_zip(payload: dict[str, bytes], module_id: str, version: str, output: Path, *, file_modes: dict[str, int] | None = None) -> tuple[Path, str]:
    """Shared deterministic standard-package writer for every Builder profile."""
    output = output.resolve(); output.mkdir(parents=True, exist_ok=True)
    zip_path = output / f"{module_id}_{version}.zip"
    checksum_path = zip_path.with_suffix('.zip.sha256')
    if os.path.lexists(zip_path) or os.path.lexists(checksum_path):
        raise FileExistsError(f'refusing to overwrite {zip_path}')
    payload = dict(payload)
    if file_modes is not None:
        if not isinstance(file_modes, dict):
            raise ValueError('Package modes require a member-to-permissions mapping')
        for name, mode in file_modes.items():
            if (not isinstance(name, str) or name in {'', '.'} or name not in payload or '\\' in name
                    or Path(name).as_posix() != name or name.startswith('/')
                    or '..' in Path(name).parts or type(mode) is not int
                    or mode < 0 or mode > 0o777):
                raise ValueError('Package modes must name existing normalized regular members with nonprivileged permissions')
    payload = module_package_payload(payload)
    with tempfile.NamedTemporaryFile(dir=output, prefix='.viewer-package-', delete=False) as temporary_file:
        temporary = Path(temporary_file.name)
    temporary_checksum = None
    try:
        with ZipFile(temporary, 'w', compression=ZIP_DEFLATED, compresslevel=9) as archive:
            for name in sorted(payload):
                if name.startswith('/') or '..' in Path(name).parts:
                    raise ValueError('Invalid module asset path')
                info = ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
                mode = (file_modes or {}).get(name, 0o644)
                if type(mode) is not int or mode < 0 or mode > 0o777:
                    raise ValueError('Package modes must be ordinary nonprivileged permission bits')
                info.compress_type = ZIP_DEFLATED; info.external_attr = (0o100000 | mode) << 16
                archive.writestr(info, payload[name], compress_type=ZIP_DEFLATED, compresslevel=9)
        with temporary.open('rb') as stream:
            os.fsync(stream.fileno())
        zip_sha = digest(temporary.read_bytes())
        checksum_name = output / ('.viewer-checksum-' + uuid.uuid4().hex)
        # Match the old sidecar's ordinary create/umask permissions, but finish
        # and flush it privately before exclusive publication. O_EXCL means a
        # coincident temporary name is never adopted or cleaned as ours.
        fd = os.open(checksum_name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o666)
        temporary_checksum = checksum_name
        with os.fdopen(fd, 'wb') as stream:
            stream.write(f'{zip_sha}  {zip_path.name}\n'.encode('utf-8'))
            stream.flush(); os.fsync(stream.fileno())
        # Each complete member is published without replacement. These two
        # links are deliberately not a crash-atomic pair/rollback transaction.
        os.link(temporary, zip_path)
        try:
            os.link(temporary_checksum, checksum_path)
        except OSError as error:
            message = f'ZIP retained at {zip_path}; checksum publication failed at {checksum_path}; inspect this partial outcome before any retry'
            if isinstance(error, FileExistsError):
                raise FileExistsError(error.errno, message, str(checksum_path)) from error
            raise OSError(error.errno, message, str(checksum_path)) from error
    finally:
        temporary.unlink(missing_ok=True)
        if temporary_checksum is not None:
            temporary_checksum.unlink(missing_ok=True)
    return zip_path, zip_sha


def build_viewer(project_path: Path, source_directory: Path, output: Path) -> tuple[Path, str]:
    """Viewer profile: CORE validates layout; this owner packages ordinary modules.

    Generated assets may change. Existing handwritten handlers are never replaced.
    No GUI constructors or scientific implementation are generated here.
    """
    import tkinter
    framework = Path(__file__).resolve().parents[4]
    with tempfile.TemporaryDirectory(prefix='gxtxt-viewer-schema-') as scratch:
        environment = dict(os.environ)
        for name in ('XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_CACHE_HOME', 'XDG_STATE_HOME',
                     'GXTXT_INSTALLATION_ROOT', 'GXTXT_RESOURCE_ROOT', 'GXTXT_RESOURCE_STORAGE', 'GXTXT_JOB_ROOT'):
            environment[name] = str(Path(scratch) / name)
        validated = subprocess.check_output(
            ['tclsh', str(framework / 'core/tcl/viewer_design_validate.tcl'),
             str(framework), str(project_path.resolve()), 'describe'], text=True, timeout=30, env=environment)
    interpreter = tkinter.Tcl()
    def dictionary(value):
        words = interpreter.splitlist(value)
        if len(words) % 2: raise ValueError('Invalid inert Viewer dictionary')
        return dict(zip(words[::2], words[1::2]))
    response = dictionary(validated)
    validated = response['design']
    capabilities = {key: dictionary(value) for key, value in dictionary(response['capabilities']).items()}
    design = dictionary(validated)
    if design.get('target') == 'preview' and dictionary(design.get('preview', '')).get('runtime') == 'managed_cpp':
        # A managed native target must never fall through to the Tcl template.
        core_python = str(framework / 'core/python')
        if core_python not in sys.path:sys.path.insert(0, core_python)
        from gxtxt_preview_generation_v1 import generate
        return generate(validated, source_directory, output)
    module_id, provider, version = design['module_id'], design['provider_id'], design['version']
    title = single(design['title'], 'Viewer title')
    target = output.resolve() / f'{module_id}_{version}.zip'
    if target.exists() or target.with_suffix('.zip.sha256').exists():
        raise FileExistsError(f'refusing to overwrite {target}')
    components = [dictionary(c) for c in interpreter.splitlist(design['components'])]
    contracts = {key: dictionary(value) for key, value in dictionary(design['handlers']).items()}
    for contract in contracts.values(): contract['arguments'] = list(interpreter.splitlist(contract['arguments']))
    source_directory = source_directory.resolve()
    if source_directory.is_relative_to(framework / 'plugins'):
        raise ValueError('Generate into a separate source project, preserving installed modules')
    source_directory.mkdir(parents=True, exist_ok=True)
    slug = module_id.replace('.', '_'); namespace = '::GX::Generated_' + slug
    backend = slug + '_gui'; workspace = slug + '_' + provider + '_interface_state'
    api = r'''# Generated interface connector. Edit handlers.tcl for science.
# SPDX-License-Identifier: GPL-3.0-or-later
if {![llength [info commands ::GX::viewerGuiDesignCompose]]} {error {This Viewer requires the public CORE Viewer design capability.}}
namespace eval @NS@ {variable root [file dirname [file dirname [info script]]]}
namespace eval @NS@::Handlers {}
if {![info exists @NS@::handlersLoaded]} {
    source [file join [set @NS@::root] generated handler_defaults.tcl]
    source [file join [set @NS@::root] handlers.tcl]
    set @NS@::handlersLoaded 1
}
foreach {api version} [dict get [::GX::viewerGuiDesignRead [file join [set @NS@::root] gui design.tcldict]] requirements] {::GX::workbenchExtensionRequireApi $api}
proc @NS@::design {} {return [::GX::viewerGuiDesignRead [file join [set @NS@::root] gui design.tcldict]]}
proc @NS@::handlers {} {
    set result {}
    dict for {id contract} [dict get [design] handlers] {dict set result $id [dict create command [list @NS@::Handlers::$id] enabled [list @NS@::Handlers::enabled]]}
    return $result
}
proc @NS@::open {{context {}}} {
    set window .@SLUG@
    if {[winfo exists $window]} {
        set id [::GX::datasetPublicationV2DictDefault $context workspace_id {}]
        if {$id eq {}} {raise $window;return $window}
        if {[dict exists $::GX::SessionWorkspace::adapters $window] && ![::GX::sessionWorkspaceHostPrepare [dict get $::GX::SessionWorkspace::adapters $window] opening]} {return $window}
        destroy $window
    }
    ::GX::viewerGuiDesignCompose [design] $window @MODULE@ @PROVIDER@ runtime [handlers] $context
    return $window
}
proc @NS@::workspaceOpen {context} {return [::GX::viewerGuiDesignWorkspaceOpen @MODULE@ @PROVIDER@ [design] runtime [handlers] $context]}
proc @NS@::dispatch {operation scene} {return [open [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
::GX::viewerBackendRegister @BACKEND@ @NS@::dispatch
'''
    for key, value in {'@NS@': namespace, '@SLUG@': slug, '@MODULE@': module_id,
                       '@PROVIDER@': provider, '@BACKEND@': backend}.items():
        api = api.replace(key, value)
    descriptor_text = ini_section('meta', dict(api_version=1, id=module_id, kind='viewer',
        group='Viewers', name=title, version=version, selectable=1, default_enabled=1,
        core=0, runner='service', order=900, depends='plot.dataset' if any(c['type']=='plot' for c in components) else '',
        description='Declarative Viewer interface using public CORE owners.'))
    descriptor_text += ini_section('viewers', dict(api_version=1, ids=provider))
    descriptor_text += ini_section('viewer.' + provider, dict(name=title, backend=backend,
        activation_api='GENERATED_VIEWER_API_v1', gui_design='gui/design.tcldict', gui_handler_command=namespace+'::handlers',
        capabilities='declarative_gui;viewer_commands;gui_roundtrip', semantic_group='development',
        group_title='Designed Viewers', short_title=title))
    descriptor_text += ini_section('public_apis', dict(ids='GENERATED_VIEWER_API_v1'))
    descriptor_text += ini_section('public_api.GENERATED_VIEWER_API_v1', dict(api_version=1,
        name='Generated Viewer connector', entrypoint='api/viewer.tcl', namespace=namespace,
        capabilities='viewer_backend;viewer_gui_manifest'))
    descriptor_text += ini_section('documentation', dict(api_version=1, guide='MANUAL.md',
        api_refs=';'.join(sorted(set(dictionary(design['requirements'])) | {'SCRIPT_JOB_API_v1'}))))
    if any(c['type'] == 'workspace' for c in components):
        descriptor_text += ini_section('workspaces', dict(api_version=1, ids=workspace))
        descriptor_text += ini_section('workspace.' + workspace, dict(entrypoint='api/viewer.tcl',
            viewer_provider=provider,
            type='Designed Viewer state', schema='gxtxt.viewer_interface_state.v1', version=1,
            accepted_versions=1, validate='::GX::viewerGuiDesignStateValidate', open=namespace+'::workspaceOpen',
            native_contract='NATIVE_WORKSPACE_API_v1', encode='::GX::viewerGuiWorkspaceEncode', decode='::GX::viewerGuiWorkspaceDecode',
            native_required_fields='schema text values object bindings object choices object visibility object domain_state object design object'))
    defaults = '# Generated unbound defaults; handwritten handlers override these.\n'
    defaults += f'proc {namespace}::Handlers::enabled {{window action}} {{return 1}}\n'
    for action in sorted(contracts):
        defaults += f'proc {namespace}::Handlers::{action} {{window action}} {{return {{status not_connected}}}}\n'
    generated = {
        'generated/handler_defaults.tcl': defaults.encode(),
        'gui/design.tcldict': validated.strip().encode('utf-8') + b'\n',
        'api/viewer.tcl': api.encode('utf-8'),
        'module.ini': descriptor_text.encode('utf-8'),
        'plugin-package.ini': ini_section('package', dict(api_version=1, id=module_id,
            name=title, version=version, type='module', framework_min='0.9.8.10-dev-111' if any(c['type']=='api_catalog' for c in components) else '0.9.8.10-dev-108' if design.get('icons') or any({'component_visibility','visibility_commands','scientific_provider','numeric_dataset','plot_dataset'}.intersection(dictionary(c['properties'])) for c in components) or any(dictionary(c['properties']).get('diagram_catalog') for c in components if c['type']=='native2d') else ('0.9.8.10-dev-107' if 'NATIVE_3D_GUI_HOST_API_v2' in dictionary(design['requirements']) else '0.9.8.10-dev-104'), framework_max='')).encode(),
        'API_CONTRACTS.json': (json.dumps(dict(schema='gxtxt.viewer_handler_contracts.v1',
            module_id=module_id, provider_id=provider, handlers=contracts,
            api_requirements={key: int(value) for key, value in dictionary(design['requirements']).items()},
            component_owners={c['id']: dict(type=c['type'], parent=c['parent'],
                api_id=capabilities[c['type']]['api_id'], api_version=int(capabilities[c['type']]['api_version']),
                owner=capabilities[c['type']]['owner'], manifest='gui/design.tcldict#'+c['id']) for c in components}),
            indent=2, sort_keys=True) + '\n').encode(),
        'MANUAL.md': (f'# {title}\n\nThis Viewer is composed by the public CORE Viewer GUI Host.\n'
            'Unbound actions report not_connected and do not start scientific Jobs.\n'
            'Help displays this installed module’s manual and metadata.\n\n'
            '## Developer handlers\n\nEdit handlers.tcl. Each declared handler receives (window, action).\n'
            'Read component values with ::GX::viewerGuiDesignValues. Use the public\n'
            'Source/Plot setters, Script Job and Dataset publication services for domain work.\n'
            'Keep scientific operations inside explicit handlers, never at file top level.\n'
            'Regeneration preserves handlers.tcl byte for byte.\n').encode('utf-8'),
        'LICENSE': b'Generated interface assets: GPL-3.0-or-later.\nHandwritten handlers retain their own notices.\n',
    }
    if design.get('target', 'viewer') == 'preview':
        # This target uses the same validated design and packaging owner. The
        # public Preview host, rather than a generated Viewer shell, owns GUI
        # lifetime, Dataset/Session identity, callback admission and disposal.
        options = dictionary(design['preview'])
        preview_namespace = namespace
        api = r'''# Generated Dataset Preview connector; no standalone Viewer host.
# SPDX-License-Identifier: GPL-3.0-or-later
if {![llength [info commands ::GX::viewerGuiDesignPreviewMount]]} {error {This module requires the public Builder Preview Module target capability}}
namespace eval @NS@ {variable root [file dirname [file dirname [info script]]]}
namespace eval @NS@::Handlers {}
source [file join [set @NS@::root] generated handler_defaults.tcl]
source [file join [set @NS@::root] handlers.tcl]
proc @NS@::design {} {return [::GX::viewerGuiDesignRead [file join [set @NS@::root] gui design.tcldict]]}
proc @NS@::preview {context} {
    return [dict create tabs [list [dict create id controls label [dict get [design] title] kind gui role complementary]]]
}
proc @NS@::guiMount {host context} {
    set d [design]
    ::GX::viewerGuiDesignPreviewMount $d $host [list @NS@::dispatchControl]
    foreach c [dict get $d components] {
        if {[dict get $c type] ne {action}} continue
        set contract [dict get $d handlers [dict get $c properties action]]
        if {[dict exists $contract available] && ![dict get $contract available]} {::GX::datasetPreviewGuiControlState $host [dict get $c id] {enabled 0}}
    }
}
proc @NS@::dispatchControl {host event} {
    # Resolve only declared bindings; the public dispatcher checks the actual
    # current host/source/activation before this callback can run.
    set d [design];set id [dict get $event control_id]
    foreach c [dict get $d components] {
        if {[dict get $c id] ne $id} continue
        set p [dict get $c properties]
        if {[dict exists $p preview_operation]} {return [::GX::datasetPreviewGuiView $host [dict get $p preview_operation]]}
        set key [expr {[dict get $event event] eq {invoke} ? {action} : {change_action}}]
        if {![dict exists $p $key]} return
        set action [dict get $p $key]
        set contract [dict get $d handlers $action]
        if {[dict exists $contract available] && ![dict get $contract available]} {error {This Preview action is unavailable}}
        return [@NS@::Handlers::$action $host $event]
    }
}
proc @NS@::guiDispose {host context reason} {
    # CORE retires controls/panels/subscriptions. Author cleanup receives the
    # expired identity only; it cannot reuse this host after source switching.
    if {[llength [info commands @NS@::Handlers::dispose]]} {@NS@::Handlers::dispose $context $reason}
}
'''.replace('@NS@', preview_namespace)
        descriptor_text = ini_section('meta', dict(api_version=1, id=module_id,
            kind='preview', group='Preview', name=title, version=version,
            selectable=1, default_enabled=1, core=0, runner='service', order=900,
            depends='', description='Builder-authored controls inside Dataset Preview.'))
        declaration = dict(profile='presentation', api_version=1,
            dataset_contracts=';'.join(interpreter.splitlist(options['dataset_contracts'])),
            gui_public_api='PREVIEW_COMPONENT_GUI_API_v1', gui_api_version=1,
            view_role='complementary')
        for key, value in options.items():
            if key not in {'dataset_contracts', 'view_role'}:
                declaration[key] = value if key in {'match_metadata', 'match_provenance'} else ';'.join(interpreter.splitlist(value))
        descriptor_text += ini_section('preview_provider', declaration)
        descriptor_text += ini_section('public_apis', dict(ids='PREVIEW_COMPONENT_GUI_API_v1'))
        descriptor_text += ini_section('public_api.PREVIEW_COMPONENT_GUI_API_v1', dict(
            api_version=1, name='Generated Preview controls', entrypoint='api/preview.tcl',
            namespace=preview_namespace, capabilities='preview_tabs;preview_gui'))
        descriptor_text += ini_section('documentation', dict(api_version=1, guide='MANUAL.md',
            api_refs='PREVIEW_DESCRIPTOR_API_v1;PREVIEW_COMPONENT_GUI_API_v1;VIEWER_GUI_HOST_API_v1;UI_FIELD_API_v1'))
        generated.pop('api/viewer.tcl')
        generated['api/preview.tcl'] = api.encode('utf-8')
        generated['module.ini'] = descriptor_text.encode('utf-8')
        generated['plugin-package.ini'] = ini_section('package', dict(api_version=1,
            id=module_id, name=title, version=version, type='module',
            framework_min='0.9.8.10-dev-111', framework_max='')).encode()
        defaults = '# Generated defaults; handwritten Preview handlers override these.\n'
        for action in sorted(contracts):
            defaults += f'proc {namespace}::Handlers::{action} {{host event}} {{error {{Preview action is not connected to an authorized handler}}}}\n'
        generated['generated/handler_defaults.tcl'] = defaults.encode()
        generated['MANUAL.md'] = (f'# {title}\n\n'
            'Enable this module in Module/Plugin Manager. Open a compatible Dataset in\n'
            'Dataset Preview and select its controls tab alongside the standard display.\n'
            'Dataset and Session changes retire the old pane and callbacks. Disabling,\n'
            'updating or closing the module disposes its controls and viewport panels.\n\n'
            '## Authoring and callbacks\n\n'
            'Open gui/design.tcldict in Viewer Interface Builder with the Preview Module\n'
            'target. The Builder display is a layout simulation; test the installed\n'
            'package inside Dataset Preview for actual Dataset and viewport behavior.\n'
            'Edit handlers.tcl; regeneration preserves its exact bytes. Preview handlers\n'
            'receive (host, event). Inspect datasetPreviewGuiContext and use the public\n'
            'datasetPreviewGuiControlGet/Set/Configure/State operations for controls.\n'
            'Bound fit/zoom actions use the existing Plot controller. Other unconnected\n'
            'actions report an error. Explicit user actions may call authorized services;\n'
            'mount and disposal do not run science or publish Datasets. Optional\n'
            'Handlers::dispose(context, reason) releases author-owned timers/resources.\n'
            'The expired host cannot be reused during disposal.\n\n'
            'Compatibility uses the declared Dataset contracts and optional metadata\n'
            'filters. A viewport panel requires an available public Plot viewport;\n'
            'unsupported sources report that limitation while retaining standard Preview.\n'
            'Native Viewer surfaces, Workspace/History and menu hosts have no Preview\n'
            'component admission. Use supported UI Field containers and actions.\n').encode()
        contract_record = json.loads(generated['API_CONTRACTS.json'])
        contract_record['target'] = 'preview'
        for contract in contract_record['handlers'].values():
            contract['arguments'] = ['host', 'event']
        generated['API_CONTRACTS.json'] = (json.dumps(contract_record, indent=2, sort_keys=True)+'\n').encode()
    if 'NATIVE_3D_GUI_HOST_API_v2' in dictionary(design['requirements']):
        generated['MANUAL.md'] += ('''\n## Embedded Native3D viewport\n\nThis design requires the public `NATIVE_3D_GUI_HOST_API_v2` contract, version 2,\nprovided by CORE. The generated connector declares that capability;\nit does not depend on an exact unrelated Analysis or Viewer module release.\n\nOpen this installed Viewer from the standard Viewers catalogue. Its `native3d`\ncomponent is a child of the Viewer, with an independent scene, camera and worker.\nDrag the viewport with the left pointer button to orbit. Shift-drag pans. The\nmouse wheel zooms. Use the native Fit, Reset, Front and Top controls to recover\na useful view. Arrow keys orbit; F fits and R restores the isometric view when\nthe viewport has keyboard focus. The orientation cube is a rendered orientation\nindicator; direct cube-face clicking is not an exposed interaction contract.\n\nA short pointer click performs actual native geometry hit testing. Selection\nreceipts identify the layer and native world/local hit; no scientific edit or\nDataset publication follows from selection. Resize or hide/show a containing tab\nwithout transferring the camera to another Viewer. Closing this Viewer releases\nonly its own worker and callbacks.\n\n### Presentation properties\n\nBuilder exposes bounded width/height, perspective or orthographic projection,\ncamera position/target/up, world axes and orientation-indicator visibility.\nApply these in the normal property inspector, then Save/Open the design. These\nare presentation settings, not scientific coordinate calibration.\n\n### Explicit demonstration and scientific bindings\n\nA component with `demo=1` renders a deterministic RAM cube and axes. This is\nexplicitly synthetic, display-only content, with no Session, Dataset or files.\nA component without that flag starts empty until an authorized handler explicitly\nbinds a source through the public CORE host. Gallery and Runtime Test are distinct\nmodes; an ordinary unconnected scientific action remains `not_connected`.\n\nFor real data, obtain the opaque viewport handle from the public Viewer host\nand call `native3DViewportBind` with `kind scientific`, the registered module\nand provider. CORE resolves the current Dataset identity, units and Session\nrevision through its public provider and Dataset owners. No raw user-file path\nor private renderer state is accepted by this binding. Stale scientific identity\nblocks interaction until an explicit valid rebind. `native3DViewportUnbind`\nreturns the component to its empty state.\n\nThe full contract is in the installed public API guide\n`NATIVE_3D_GUI_HOST_API_v2`: create/configure/bind/unbind/update, navigation and\ncamera, command/pick, subscribe/unsubscribe, inspect and release. Native rendering\nerrors are reported visibly; rebind only after correcting the source or runtime\nproblem. This guide does not claim unsupported mesh editing or scientific output.\n''').encode('utf-8')
    # Existing standard packaging owner includes exact project-owned resources.
    sys.path.insert(0,str(framework/'core/python'))
    from gxtxt_viewer_icons import package_resources
    generated.update(package_resources(design.get('icons','')))
    handlers = source_directory / 'handlers.tcl'
    if handlers.is_symlink(): raise ValueError('A handwritten handler source must be an ordinary file')
    if handlers.exists() and handlers.stat().st_size > 8 * 1024 * 1024:
        raise ValueError('Handwritten handlers exceed the 8 MiB source bound')
    if not handlers.exists():
        body = '# Handwritten scientific hooks; preserved on regeneration.\n'
        body += f'namespace eval {namespace}::Handlers {{}}\n'
        for action in sorted(contracts):
            if design.get('target', 'viewer') == 'preview':
                body += f'proc {namespace}::Handlers::{action} {{host event}} {{\n    error {{Preview action is not connected to an authorized handler}}\n}}\n'
            else:
                body += f'proc {namespace}::Handlers::{action} {{window action}} {{\n    return {{status not_connected}}\n}}\n'
        handlers.write_text(body, encoding='utf-8')
    preserved = digest(handlers.read_bytes()); changes = []
    for name, body in generated.items():
        path = source_directory / name
        if path.is_symlink(): raise ValueError('Generated assets cannot be symbolic links')
        old = digest(path.read_bytes()) if path.exists() else None
        path.parent.mkdir(parents=True, exist_ok=True)
        if old != digest(body):
            with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as temp:
                temp.write(body); temporary = Path(temp.name)
            temporary.replace(path)
            changes.append(dict(path=name, before=old, after=digest(body)))
    if digest(handlers.read_bytes()) != preserved: raise RuntimeError('Handwritten handlers changed')
    payload = {name: (source_directory / name).read_bytes() for name in generated}
    payload['handlers.tcl'] = handlers.read_bytes()
    report = dict(schema='gxtxt.viewer_generation.v1', generated_changes=changes,
        handwritten_handlers_sha256=preserved, handwritten_handlers_overwritten=False,
        gui_owner='VIEWER_GUI_HOST_API_v1', source_directory=str(source_directory))
    (source_directory / 'generation-report.json').write_text(json.dumps(report, indent=2) + '\n')
    return write_module_zip(payload, module_id, version, output)


def build(project_path: Path, output: Path) -> tuple[Path, str]:
    data, source_files = validate(project_path)
    return _build_validated(data, source_files, output)


def _build_validated(data: dict, source_files: list[tuple[Path, str, bytes]], output: Path) -> tuple[Path, str]:
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    zip_path = output / f"{data['id']}_{data['version']}.zip"
    if zip_path.exists() or zip_path.with_suffix(".zip.sha256").exists():
        raise FileExistsError(f"refusing to overwrite {zip_path}")
    payload = {rel: body for _, rel, body in source_files}
    payload["bundle/SHA256SUMS"] = "".join(f"{digest(body)}  {rel.removeprefix('bundle/')}\n"
        for _, rel, body in source_files).encode("utf-8")
    payload["module.ini"] = descriptor(data, source_files).encode("utf-8")
    payload["plugin-package.ini"] = ini_section("package", {"api_version": 1, "id": data["id"],
        "name": data["name"], "version": data["version"], "type": "module",
        "framework_min": "0.9.8.10", "framework_max": ""}).encode("utf-8")
    payload["MANUAL.md"] = manual(data, source_files).encode("utf-8")
    payload["CHANGELOG.md"] = f"# Changelog\n\n## {data['version']}\n\nInitial Script Module Builder package.\n".encode()
    payload["LICENSE"] = (data["license"] + "\n").encode("utf-8")
    legacy_api_payload = public_api_files(data)
    payload.update(legacy_api_payload)
    payload.update(provided_api_files(data, legacy_api_payload))
    if data["profile"] == "W":
        payload.update(workbench_api_files(data))
    portable = dict(data)
    portable.pop("_provided_inventory", None)
    portable.pop("_provided_entrypoint", None)
    binding = portable.pop("registry_source", None)
    if binding:
        portable["source_registry_lineage"] = {"reference": binding["reference"],
                                              "sha256": binding["baseline"]["expected_sha256"],
                                              "record_sha256": binding["baseline"]["expected_record_sha256"]}
    portable["source"] = source_files[0][1]
    portable["bundle"] = [{"source": rel, "target": rel.removeprefix("bundle/")} for _, rel, _ in source_files[1:]]
    portable["source_sha256"] = digest(source_files[0][2])
    payload["builder-project.json"] = (json.dumps(portable, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
    payload["SHA256SUMS.txt"] = "".join(f"{digest(payload[name])}  {name}\n" for name in sorted(payload)).encode()
    return write_module_zip(payload, data['id'], data['version'], output)


def gui(*, on_ready=None, session="") -> None:
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk
    import tkinter.font as tkfont

    root = tk.Tk()
    host = _core_interpreter(root.tk, session=session)
    # Apply the same persisted CORE appearance owner used by the main GUI
    # before constructing widgets; loading Configuration alone is insufficient.
    host.call("::GX::uiAppearanceInitialize")
    root.title("GX-TXT Script Module Builder")
    root.geometry(f"{min(1080, max(720, root.winfo_screenwidth() - 40))}x"
                  f"{min(850, max(560, root.winfo_screenheight() - 80))}")
    project_file = tk.StringVar()
    output_dir = tk.StringVar()
    status = tk.StringVar(value="Choose a Builder project, or create one from a script.")
    for row, (label, variable, chooser) in enumerate((("Project JSON", project_file, filedialog.askopenfilename),
                                                      ("Package output", output_dir, filedialog.askdirectory))):
        ttk.Label(root, text=label).grid(row=row, column=0, sticky="w", padx=8, pady=6)
        ttk.Entry(root, textvariable=variable).grid(row=row, column=1, sticky="ew", padx=8)
        ttk.Button(root, text="Browse…", command=lambda v=variable, c=chooser: v.set(c() or v.get())).grid(row=row, column=2)
    workspace = ttk.Notebook(root)
    workspace.grid(row=2, column=0, columnspan=3, sticky="nsew", padx=8, pady=8)
    editor_frame = ttk.Frame(workspace);workspace.add(editor_frame, text="Project JSON")
    editor = tk.Text(editor_frame, wrap="none", undo=True)
    editor_y = ttk.Scrollbar(editor_frame, orient="vertical", command=editor.yview)
    editor_x = ttk.Scrollbar(editor_frame, orient="horizontal", command=editor.xview)
    editor.configure(yscrollcommand=editor_y.set, xscrollcommand=editor_x.set)
    editor_x.pack(side="bottom", fill="x");editor_y.pack(side="right", fill="y");editor.pack(fill="both", expand=True)
    source_frame = ttk.LabelFrame(workspace, text="Analysis Sources discovered from the script")
    workspace.add(source_frame, text="Analysis inputs")
    source_table = ttk.Treeview(source_frame, columns=("id", "required", "contracts", "label", "purpose"),
                                show="headings", height=4)
    for key, title, width in (("id", "Source ID", 120), ("required", "Required", 75),
                              ("contracts", "Accepted Dataset contracts", 245),
                              ("label", "Visible label", 180), ("purpose", "Purpose", 260)):
        source_table.heading(key, text=title)
        source_table.column(key, width=width, stretch=False)
    source_table.pack(fill="x", padx=4, pady=3)
    source_x = ttk.Scrollbar(source_frame, orient="horizontal", command=source_table.xview)
    source_table.configure(xscrollcommand=source_x.set);source_x.pack(fill="x", padx=4)
    source_status = tk.StringVar(value="Choose a script to inspect its declared sources.")
    ttk.Label(source_frame, textvariable=source_status, wraplength=1040).pack(anchor="w", padx=5, pady=3)
    root.grid_columnconfigure(1, weight=1)
    root.grid_rowconfigure(2, weight=1)
    files_page = ttk.Frame(workspace);workspace.add(files_page, text="Source files")
    ttk.Label(files_page, text="Registered projects are edited in the existing language source Workspace. This roster packages their exact saved files.",
              wraplength=920).pack(fill="x", padx=6, pady=6)
    file_box = ttk.Frame(files_page);file_box.pack(fill="both", expand=True)
    file_table = ttk.Treeview(file_box, columns=("relative", "role", "bytes", "sha256"), show="headings", selectmode="browse")
    for key,label,width in (("relative","Project-relative file",280),("role","Role",120),("bytes","Bytes",90),("sha256","Saved source SHA-256",480)):
        file_table.heading(key,text=label,anchor="w");file_table.column(key,width=width,minwidth=80,stretch=False)
    file_y=ttk.Scrollbar(file_box,command=file_table.yview);file_x=ttk.Scrollbar(file_box,orient="horizontal",command=file_table.xview)
    file_table.configure(yscrollcommand=file_y.set,xscrollcommand=file_x.set)
    file_y.pack(side="right",fill="y");file_x.pack(side="bottom",fill="x");file_table.pack(fill="both",expand=True)
    api_page=ttk.Frame(workspace);workspace.add(api_page,text="Public APIs")
    api_notice=tk.StringVar(value="Source declarations are static. No script is imported or executed; consumed requirements remain separate.")
    ttk.Label(api_page,textvariable=api_notice,wraplength=920).pack(fill="x",padx=6,pady=6)
    api_book=ttk.Notebook(api_page);api_book.pack(fill="both",expand=True)
    api_list=ttk.Frame(api_book);api_details=ttk.Frame(api_book)
    api_book.add(api_list,text="Operations / requirements");api_book.add(api_details,text="Operation details")
    api_table=ttk.Treeview(api_list,columns=("source","status"),show="tree headings",selectmode="browse")
    api_table.heading("#0",text="API / operation",anchor="w");api_table.column("#0",width=330,minwidth=160)
    for key,label,width in (("source","Source / line",360),("status","Qualification",230)):
        api_table.heading(key,text=label,anchor="w");api_table.column(key,width=width,minwidth=120)
    api_y=ttk.Scrollbar(api_list,command=api_table.yview);api_x=ttk.Scrollbar(api_list,orient="horizontal",command=api_table.xview)
    api_table.configure(yscrollcommand=api_y.set,xscrollcommand=api_x.set)
    api_y.pack(side="right",fill="y");api_x.pack(side="bottom",fill="x");api_table.pack(fill="both",expand=True)
    state={"request":None,"inspection":None,"api_rows":{},"file_rows":{},"baseline":"","closed":False}

    def core_host():
        nonlocal host
        if host is None:
            host=_core_interpreter(root.tk,session=session)
        return host

    def tree_geometry(tree):
        if not tree.winfo_ismapped() or tree.winfo_height()<24:return
        signature=(tree.winfo_id(),str(root.tk.call("ttk::style","theme","use")),str(tkfont.nametofont("TkDefaultFont").actual()))
        if getattr(tree,"_source_style_signature",None)==signature:return
        tree._source_style_signature=signature
        core_host().call("::GX::_uiFieldTreeFontRows",str(tree),"GXScriptBuilder.Treeview")
        core_host().call("::GX::uiFieldInspectionColumnsFit",str(tree),core_host().call("dict","create","recursive",int(tree is api_table)))

    for tree in (file_table,api_table,source_table):
        tree.bind("<Map>",lambda event,t=tree:tree_geometry(t),add=True)
        tree.bind("<<ThemeChanged>>",lambda event,t=tree:tree_geometry(t),add=True)
        tree.bind("<Configure>",lambda event,t=tree:tree_geometry(t),add=True)

    core_host()
    detail_path=str(api_details)+".source"
    detail_widget=host.call("::GX::sourceSurfaceCreate",detail_path,host.call("dict","create","mode","read_only","language","javascript","find_bar",0))
    host.call("pack",detail_path,"-fill","both","-expand",1)

    def show_detail(text):
        host.call("::GX::sourceSurfaceSet",detail_widget,text)

    def cancel_request():
        if state["request"]:
            host.call("::GX::scriptJobRequestCancel",state["request"],"user_cancelled")
            status.set("Cancelling the owned Builder inspection request…")

    def auxiliary(payload,done,guard=None):
        if state["request"]:
            status.set("Wait for the current request or its owned cancellation cleanup.");return
        callback_name=None
        def completed(raw):
            try:
                if state["closed"] or not root.winfo_exists():return
                state["request"]=None
                response=_tcl_dict(host,raw)
                if not int(response["ok"]):raise ValueError(str(response.get("error","Inspection failed")))
                if guard is not None and guard!=digest(editor.get("1.0","end-1c").encode("utf-8")):
                    status.set("Builder draft changed during inspection; the old result was discarded.");return
                state["last_receipt"]=json.loads(str(response["result_json"]))
                status.set("Inspection complete; no researcher source was executed.")
                done(state["last_receipt"])
            except Exception as error:
                if not state["closed"]:status.set(str(error))
            finally:
                if callback_name:
                    try:root.deletecommand(callback_name)
                    except tk.TclError:pass
        payload=dict(payload)
        root_path=Path(__file__).resolve().parents[4]
        code_names=("plugins/modules/tool.script_module_builder/runtime/builder.py","core/python/script_api_exports.py","core/python/script_api_declarations.py","core/python/script_project.py","core/tcl/script_provided_api_v1.tcl","core/tcl/script_execution_api_v1.tcl","core/tcl/script_project_v1.tcl")
        payload["code_pins"]={name:digest((root_path/name).read_bytes()) for name in code_names}
        callback_name=root.register(completed)
        command=host.call("list","setsid",sys.executable,"-B",str(Path(__file__).resolve()),"managed-request")
        options=host.call("dict","create","timeout_ms",30000,"max_bytes",4194304,"process_group",1,"ui_lifetime",1,"label","Script Builder source inspection")
        state["request"]=host.call("::GX::scriptJobAsync",command,json.dumps(payload,ensure_ascii=False,separators=(",",":")),host.call("list",callback_name),options)
        status.set("Managed Builder request running asynchronously; no researcher source execution.")

    def current_project():
        value = json.loads(editor.get("1.0", "end"))
        if not isinstance(value, dict):
            raise ValueError("Project must be a JSON object")
        return value

    def show_project(value):
        state["inspection"]=None
        editor.delete("1.0", "end")
        editor.insert("end", json.dumps(value, ensure_ascii=False, indent=2) + "\n")
        refresh_sources()

    def source_from_project(value):
        anchor = Path(project_file.get()) if project_file.get() else Path.cwd() / "unsaved-builder-project.json"
        return resolve_input(anchor, single(value.get("source", ""), "source"))

    def refresh_sources():
        source_table.delete(*source_table.get_children())
        try:
            data = current_project()
            discovered = declared_sources(source_from_project(data))
            if discovered is None:
                source_status.set("This script has no Analysis Sources declaration. Project sources remain editable.")
                return
            rows, fingerprint = discovered
            for row in rows:
                source_table.insert("", "end", values=(row["id"], "Yes" if row["required"] else "No",
                    row["contracts"], row["label"], row["purpose"]))
            configured = data.get("sources")
            if configured is None or _source_semantics(configured) == _source_semantics(rows):
                source_status.set(f"{len(rows)} source declarations found; project sources agree with the script.")
            else:
                resolution = data.get("source_declaration_resolution", {})
                if resolution.get("declaration_sha256") != fingerprint:
                    source_status.set("CONFLICT: Project sources differ from this script. Choose script or manual sources below before validation.")
                else:
                    source_status.set(f"Conflict reviewed: {resolution.get('choice', 'unknown')} sources selected for this exact declaration.")
        except Exception as exc:
            source_status.set(f"Source discovery: {exc}")

    def inspection_ready(result):
        if result.get("schema")!="gxtxt.builder_source_inspection.v1" or result.get("execution_authority")!="none":
            raise ValueError("Unexpected source inventory receipt")
        for row in result["files"]:
            stat=Path(row["source"]).stat()
            if [stat.st_dev,stat.st_ino,stat.st_size,stat.st_mtime_ns,stat.st_ctime_ns]!=row["stat_identity"]:
                raise ValueError("Saved source changed during inspection; refresh before reviewing")
        state["inspection"]=result;state["file_rows"]={};state["api_rows"]={}
        file_table.delete(*file_table.get_children());api_table.delete(*api_table.get_children())
        for index,row in enumerate(result["files"]):
            key=f"file{index}";state["file_rows"][key]=row
            file_table.insert("","end",iid=key,values=(row["relative"],row["role"],row["bytes"],row["sha256"]))
        host.call("::GX::uiFieldInspectionColumnsFit",str(file_table))
        inventory=result["inventory"]
        for key,label in (("provided","PROVIDED"),("consumed","CONSUMED"),("diagnostics","Diagnostics")):
            api_table.insert("","end",iid=key,text=label,open=True)
        for index,api in enumerate(inventory["provided"]):
            parent=f"api{index}";api_table.insert("provided","end",iid=parent,text=api["id"],values=("",f"version{api['version']} · static"),open=True)
            for number,operation in enumerate(inventory["operations"]):
                if operation["api_id"]!=api["id"]:continue
                key=f"operation{number}";impl=operation["implementation"];state["api_rows"][key]=operation
                api_table.insert(parent,"end",iid=key,text=operation["id"],values=(f"{impl['file']}:{impl.get('line',0)}",f"read_only={operation['read_only']}" if 'sha256' in impl else "UNBOUND"))
        for requirement in inventory["consumed"]:api_table.insert("consumed","end",text=requirement,values=("","requirement; no grant"))
        for diagnostic in inventory["diagnostics"]:api_table.insert("diagnostics","end",text=diagnostic["code"],values=(f"{diagnostic['file']}:{diagnostic['line']}",diagnostic["message"]))
        host.call("::GX::uiFieldInspectionColumnsFit",str(api_table),host.call("dict","create","recursive",1))
        api_notice.set(f"{result['source_scope']} · {len(result['files'])} files · {len(inventory['operations'])} provided operations · valid={inventory['valid']} · no execution")
        show_detail("Select a PROVIDED operation for its exact source/function, typed arguments/result, units and effects.\n\nDeclaration SHA: "+inventory["declaration_sha256"])
        status.set("Source snapshot inspected. Build revalidates the saved source closure; nothing was executed.")

    def refresh_inventory():
        try:
            data=current_project()
            anchor=Path(project_file.get()).resolve() if project_file.get() else Path.cwd()/"unsaved-builder-project.json"
            auxiliary(dict(operation="inspect_source",project=data,anchor=str(anchor)),inspection_ready,
                      digest(editor.get("1.0","end-1c").encode("utf-8")))
        except Exception as error:status.set(str(error))

    def operation_details(event=None):
        selected=api_table.selection()
        if len(selected)==1 and selected[0] in state["api_rows"]:
            show_detail(json.dumps(state["api_rows"][selected[0]],ensure_ascii=False,indent=2,allow_nan=False))

    def source_workspace(relative=None,operation=None):
        try:
            data=current_project();binding=data.get("registry_source")
            if not binding:
                raise ValueError("Save first in the existing Python/Octave source Workspace, then choose New from registered. No Registry identity is inferred from a file path.")
            snapshot=registry_source_snapshot(binding["reference"],binding["session"],binding["baseline"],host=core_host())
            language=str(snapshot["metadata"]["language"]);low=language.lower();namespace=f"::GX::{language}ScriptEditorUI"
            host.call("::GX::modulePublicApiActivate",f"analysis.{low}_script",language.upper()+"_SCRIPT_EDITOR_API_v1")
            host.call(f"::GX::{language}ScriptEditor::_ensureUi");host.call(namespace+"::open")
            host.call(namespace+"::_loadDocument",binding["reference"])
            tabs=host.call("set",namespace+"::ui(tabs)")
            identity=_tcl_dict(host,host.call("::GX::scriptSourceTabsIdentity",tabs))
            if str(identity["reference"])!=binding["reference"]:raise ValueError("Source Workspace retained a different draft; review it before opening this source")
            if relative:
                document=host.call("::GX::scriptSourceTabsCurrent",tabs)
                host.call("::GX::scriptSourceTabsOpen",tabs,binding["reference"],document,relative)
            if operation:
                impl=operation["implementation"]
                if "sha256" not in impl or "line" not in impl:raise ValueError("Implementation is unbound; repair the source declaration")
                widget=host.call("set",namespace+"::ui(text)")
                if digest(_tcl_text(host,host.call("::GX::sourceSurfaceGet",widget)).encode("utf-8"))!=impl["sha256"]:
                    raise ValueError("Current source buffer differs from the saved declaration; its draft is retained")
                host.call(widget,"mark","set","insert",f"{impl['line']}.0");host.call(widget,"see",f"{impl['line']}.0");host.call("focus",widget)
            status.set("Existing source Workspace opened. Edit/Save All there, then Sources → Refresh saved project here.")
        except Exception as error:status.set(str(error))

    def open_implementation(event=None):
        selected=api_table.selection()
        if len(selected)==1 and selected[0] in state["api_rows"]:
            operation=state["api_rows"][selected[0]];source_workspace(operation["implementation"]["file"],operation)

    def open_roster_source(event=None):
        selected=file_table.selection()
        if len(selected)==1 and selected[0] in state["file_rows"]:
            source_workspace(state["file_rows"][selected[0]]["relative"])

    api_table.bind("<<TreeviewSelect>>",operation_details)
    api_table.bind("<Double-1>",open_implementation);api_table.bind("<Return>",open_implementation)
    file_table.bind("<Double-1>",open_roster_source);file_table.bind("<Return>",open_roster_source)

    def use_snapshot(snapshot,preserve=False):
        data=current_project() if preserve else {}
        metadata=snapshot["metadata"];language=metadata["language"]
        if preserve:
            prior=data["registry_source"]
            if language!=data["language"] or snapshot["baseline"]["expected_owner_context"]!=prior["baseline"]["expected_owner_context"]:
                raise ValueError("Source language/authority changed; choose the intended registered source again")
        else:
            data=dict(schema_version=1,id="research."+metadata["id"],name=metadata["name"],description=metadata.get("description") or "Research analysis",
                      version=metadata.get("version") or "1.0.0",group="Research",license="GPL-3.0-or-later",profile="A",language=language,
                      sources=[dict(id="primary",required=True)],bindings=[],fields=[],required_apis=list(host.splitlist(metadata.get("explicit_apis",""))),
                      outputs=dict(datasets=[],files=[]),documentation="")
            project_file.set("")
        entry=snapshot["entrypoint"];data["source"]=snapshot["paths"][entry];data["source_entrypoint"]=entry
        data["bundle"]=[dict(source=path,target=relative) for relative,path in sorted(snapshot["paths"].items()) if relative!=entry]
        data["registry_source"]={key:snapshot[key] for key in ("reference","session","baseline")}
        show_project(data);workspace.select(files_page);refresh_inventory()

    def refresh_registered():
        try:
            data=current_project();binding=data.get("registry_source")
            if not binding:refresh_inventory();return
            auxiliary(dict(operation="registry_snapshot",reference=binding["reference"],session=binding["session"]),
                      lambda snapshot:use_snapshot(snapshot,True),digest(editor.get("1.0","end-1c").encode("utf-8")))
        except Exception as error:status.set(str(error))

    def add_bundle_file():
        try:
            data=current_project()
            if data.get("registry_source"):source_workspace();return
            path=filedialog.askopenfilename(title="Choose an explicit bundle/source file")
            if not path:return
            answer=form("Bundled source/file",[("target","Project-relative target",Path(path).name,None)])
            if answer:
                data.setdefault("bundle",[]).append(dict(source=path,target=answer["target"]));show_project(data);refresh_inventory();workspace.select(files_page)
        except Exception as error:status.set(str(error))

    def remove_bundle_file():
        try:
            data=current_project()
            if data.get("registry_source"):source_workspace();return
            selected=file_table.selection()
            if len(selected)!=1 or selected[0] not in state["file_rows"]:return
            row=state["file_rows"][selected[0]]
            if row["role"]=="entrypoint":raise ValueError("Choose a different entrypoint before removing it from the Builder roster")
            data["bundle"]=[item for item in data.get("bundle",[]) if item.get("target",Path(item["source"]).name)!=row["relative"]]
            show_project(data);refresh_inventory()
        except Exception as error:status.set(str(error))

    def rename_bundle_file():
        try:
            data=current_project()
            if data.get("registry_source"):source_workspace();return
            selected=file_table.selection()
            if len(selected)!=1 or selected[0] not in state["file_rows"]:return
            row=state["file_rows"][selected[0]]
            answer=form("Rename package-relative file",[("target","New relative target",row["relative"],None)])
            if not answer:return
            target=answer["target"];parts=Path(target).parts
            if not parts or Path(target).is_absolute() or "\\" in target or any(part in {".",".."} for part in parts):raise ValueError("Choose a safe project-relative target")
            if any(item["relative"].casefold()==target.casefold() and item["relative"]!=row["relative"] for item in state["file_rows"].values()):raise ValueError("A roster target already exists")
            if row["role"]=="entrypoint":
                _source_relative(target,".py" if data["language"]=="Python" else ".m");data["source_entrypoint"]=target
            else:
                for item in data.get("bundle",[]):
                    if item.get("target",Path(item["source"]).name)==row["relative"]:item["target"]=target
            show_project(data);refresh_inventory()
        except Exception as error:status.set(str(error))

    def choose_entrypoint():
        try:
            data=current_project()
            if data.get("registry_source"):source_workspace();return
            selected=file_table.selection()
            if len(selected)!=1 or selected[0] not in state["file_rows"]:return
            row=state["file_rows"][selected[0]];suffix=".py" if data["language"]=="Python" else ".m"
            _source_relative(row["relative"],suffix)
            old=dict(source=data["source"],target=data.get("source_entrypoint",Path(data["source"]).name))
            data["source"]=row["source"];data["source_entrypoint"]=row["relative"]
            data["bundle"]=[item for item in data.get("bundle",[]) if item.get("target",Path(item["source"]).name)!=row["relative"]]
            if old["source"]!=row["source"]:data["bundle"].append(old)
            show_project(data);refresh_inventory()
        except Exception as error:status.set(str(error))

    def resolve_declaration(choice):
        try:
            data = current_project()
            discovered = declared_sources(source_from_project(data))
            if discovered is None:
                raise ValueError("The selected script has no Analysis Sources declaration")
            rows, fingerprint = discovered
            if choice == "manual" and not messagebox.askyesno("Analysis Source conflict",
                    "Keep the project's manual source settings even though they differ from the script declaration? "
                    "This choice is recorded for this exact declaration and must be reviewed again if it changes."):
                return
            if choice == "script":
                data["sources"] = rows
            data["source_declaration_resolution"] = {"choice": choice, "declaration_sha256": fingerprint}
            show_project(data)
            status.set(f"Reviewed script Analysis Sources: {choice} settings selected.")
        except Exception as exc:
            messagebox.showerror("Module Builder", str(exc))

    def form(title, fields):
        dialog = tk.Toplevel(root)
        dialog.title(title)
        dialog.transient(root)
        dialog.grab_set()
        values = {}
        variables = {}
        for row, (key, label, default, choices) in enumerate(fields):
            ttk.Label(dialog, text=label).grid(row=row, column=0, sticky="w", padx=8, pady=4)
            variable = tk.StringVar(value=str(default))
            variables[key] = variable
            if choices:
                widget = ttk.Combobox(dialog, textvariable=variable, values=choices, state="readonly", width=44)
            else:
                widget = ttk.Entry(dialog, textvariable=variable, width=48)
            widget.grid(row=row, column=1, sticky="ew", padx=8, pady=4)
        dialog.grid_columnconfigure(1, weight=1)

        def accept():
            values.update({key: variable.get() for key, variable in variables.items()})
            dialog.destroy()

        ttk.Button(dialog, text="Apply", command=accept).grid(row=len(fields), column=1, sticky="e", padx=8, pady=8)
        dialog.bind("<Escape>", lambda event: dialog.destroy())
        root.wait_window(dialog)
        return values or None

    def edit_details():
        try:
            data = current_project()
            keys = ("id", "name", "description", "version", "group", "license", "profile", "language")
            fields = [(key, key.replace("_", " ").title(), data.get(key, ""),
                       ("A", "B", "W") if key == "profile" else (("Octave", "Python") if key == "language" else None))
                      for key in keys]
            answer = form("Module details", fields)
            if answer:
                data.update(answer)
                show_project(data)
        except Exception as exc:
            messagebox.showerror("Module Builder", str(exc))

    def add_source():
        try:
            data = current_project()
            answer = form("Analysis Source", [("id", "Source ID", "secondary", None),
                ("required", "Required", "0", ("0", "1")), ("contracts", "Dataset contracts", "", None)])
            if answer:
                data.setdefault("sources", []).append({"id": answer["id"], "required": answer["required"] == "1",
                    "contracts": answer["contracts"]})
                show_project(data)
        except Exception as exc:
            messagebox.showerror("Module Builder", str(exc))

    def add_binding():
        try:
            data = current_project()
            answer = form("Variable selector", [("id", "Binding ID", "signal", None),
                ("label", "Visible label", "Signal variable", None),
                ("required", "Required", "1", ("0", "1")),
                ("semantic_role", "Semantic role (optional)", "", None)])
            if answer:
                data.setdefault("bindings", []).append({"id": answer["id"], "label": answer["label"],
                    "required": answer["required"] == "1", "semantic_role": answer["semantic_role"]})
                show_project(data)
        except Exception as exc:
            messagebox.showerror("Module Builder", str(exc))

    def add_field():
        try:
            data = current_project()
            answer = form("Configuration field", [("id", "Field ID", "parameter", None),
                ("type", "Standard Module field type", "number", tuple(sorted(FIELD_TYPES))),
                ("label", "Visible label", "Parameter", None),
                ("default", "Default value", "", None),
                ("required", "Required", "0", ("0", "1")),
                ("values", "Choice values separated by semicolons", "", None),
                ("columns", "Table columns (semicolon list; edit types in JSON)", "", None)])
            if answer:
                field = {"id": answer["id"], "type": answer["type"],
                    "label": answer["label"], "default": answer["default"],
                    "required": answer["required"] == "1", "values": answer["values"]}
                if answer["type"] == "table":
                    field["columns"] = [{"id": c.strip(), "type": "string"}
                                        for c in answer["columns"].split(";") if c.strip()]
                data.setdefault("fields", []).append(field)
                show_project(data)
        except Exception as exc:
            messagebox.showerror("Module Builder", str(exc))

    def add_api():
        try:
            data = current_project()
            answer = form("Required public API", [("requirement", "API requirement", "", None)])
            if answer:
                data.setdefault("required_apis", []).append(answer["requirement"])
                show_project(data)
        except Exception as exc:
            messagebox.showerror("Module Builder", str(exc))

    def edit_outputs():
        try:
            data = current_project()
            outputs = data.setdefault("outputs", {"datasets": [], "files": []})
            answer = form("Outputs and documentation", [
                ("datasets", "Output Dataset IDs (semicolon list)", ";".join(outputs.get("datasets", [])), None),
                ("files", "Output files (semicolon list)", ";".join(outputs.get("files", [])), None),
                ("documentation", "Researcher notes", data.get("documentation", ""), None)])
            if answer:
                outputs["datasets"] = [x.strip() for x in answer["datasets"].split(";") if x.strip()]
                outputs["files"] = [x.strip() for x in answer["files"].split(";") if x.strip()]
                data["documentation"] = answer["documentation"]
                show_project(data)
        except Exception as exc:
            messagebox.showerror("Module Builder", str(exc))

    def open_project():
        try:
            p = Path(project_file.get())
            editor.delete("1.0", "end")
            editor.insert("end", p.read_text(encoding="utf-8"))
            refresh_sources()
            state["baseline"]=editor.get("1.0","end-1c");state["inspection"]=None
            status.set(f"Opened {p}")
        except Exception as exc:
            messagebox.showerror("Module Builder", str(exc))

    def create_project():
        source = filedialog.askopenfilename(filetypes=[("Research scripts", "*.m *.py")])
        if not source:
            return
        path = Path(source)
        template = {"schema_version": 1, "id": "research." + re.sub(r"[^A-Za-z0-9_]", "_", path.stem),
            "name": path.stem.replace("_", " ").title(), "description": "Research analysis",
            "version": "1.0.0", "group": "Research", "license": "GPL-3.0-or-later", "profile": "A",
            "language": "Python" if path.suffix == ".py" else "Octave", "source": source,
            "sources": [{"id": "primary", "required": True}], "bindings": [], "fields": [],
            "required_apis": [], "outputs": {"datasets": [], "files": []}, "documentation": ""}
        discovered = declared_sources(path)
        if discovered is not None:
            template["sources"] = discovered[0]
        project_file.set("")
        show_project(template)
        status.set(f"Discovered {len(template['sources'])} Analysis Sources from the script. Review, then save and validate.")

    def create_registered_project():
        if not leave_project():return
        dialog=tk.Toplevel(root);dialog.title("Choose registered Script or Project")
        dialog.geometry("820x440");dialog.transient(root)
        dialog.columnconfigure(0,weight=1);dialog.rowconfigure(1,weight=1)
        note=tk.StringVar(value="Reading the existing public User/Session Registry…")
        heading=ttk.Label(dialog,textvariable=note,wraplength=760)
        heading.grid(row=0,column=0,sticky="ew",padx=8,pady=8)
        heading.bind("<Configure>",lambda event:heading.configure(wraplength=max(100,event.width)))
        table=ttk.Frame(dialog);table.grid(row=1,column=0,sticky="nsew",padx=8)
        table.columnconfigure(0,weight=1);table.rowconfigure(0,weight=1)
        rows=ttk.Treeview(table,columns=("language","kind","name"),show="tree headings",selectmode="browse")
        rows.heading("#0",text="Qualified reference")
        for key in ("language","kind","name"):rows.heading(key,text=key.title())
        scroll=ttk.Scrollbar(table,command=rows.yview)
        horizontal=ttk.Scrollbar(table,orient="horizontal",command=rows.xview)
        rows.configure(yscrollcommand=scroll.set,xscrollcommand=horizontal.set)
        rows.grid(row=0,column=0,sticky="nsew");scroll.grid(row=0,column=1,sticky="ns");horizontal.grid(row=1,column=0,sticky="ew")
        selected=tk.StringVar();ttk.Entry(dialog,textvariable=selected).grid(row=2,column=0,sticky="ew",padx=8,pady=6)
        def choose(event=None):
            reference=selected.get()
            if not reference:return
            dialog.destroy()
            auxiliary(dict(operation="registry_snapshot",reference=reference,session=session),use_snapshot)
        def listed(result):
            if not dialog.winfo_exists():return
            for record in result["rows"]:
                reference=record["scope"]+":"+record["id"]
                rows.insert("","end",iid=reference,text=reference,values=(record["language"],record["kind"],record["name"]))
            note.set("Choose an existing source. "+("First500 records shown; enter an exact qualified reference for another." if result["truncated"] else "No script is executed."))
            tree_geometry(rows)
        rows.bind("<<TreeviewSelect>>",lambda event:selected.set(rows.selection()[0]) if rows.selection() else None)
        rows.bind("<Return>",choose);rows.bind("<Double-1>",choose)
        footer=ttk.Frame(dialog);footer.grid(row=3,column=0,sticky="ew",padx=8,pady=6)
        ttk.Button(footer,text="Choose",command=choose).pack(side="left")
        ttk.Button(footer,text="Cancel",command=dialog.destroy).pack(side="right")
        dialog.bind("<Escape>",lambda event:dialog.destroy())
        auxiliary(dict(operation="registry_list",session=session),listed)

    def workbench_profile():
        try:
            data = current_project()
            spec = data.get('workbench_extension',{})
            answer = form('Workbench extension profile', [
                ('action_id','Action ID',spec.get('action_id','transform'),None),
                ('category','Category',spec.get('category','transform'),['transform','geometry_generator','measurement','operation','validator','analysis','utility']),
                ('workbenches','Compatible Workbenches (semicolon list)',';'.join(spec.get('workbenches',['viewer.curve_workbench'])),None),
                ('selection_kinds','Selection kinds (semicolon list)',';'.join(spec.get('selection_kinds',['curve'])),None),
                ('mutates','Mutates geometry',str(int(spec.get('mutates',True))),['1','0'])])
            if answer:
                data['profile']='W';data['sources']=[];data['bindings']=[]
                data['workbench_extension']={'action_id':answer['action_id'],'category':answer['category'],'workbenches':[x.strip() for x in answer['workbenches'].split(';') if x.strip()],'selection_kinds':[x.strip() for x in answer['selection_kinds'].split(';') if x.strip()],'mutates':answer['mutates']=='1'}
                validate_workbench_extension(data);show_project(data)
                status.set('Workbench extension profile: logical context, shared parameters and one host transaction.')
        except Exception as exc:
            messagebox.showerror('Module Builder',str(exc))

    def edit_duplication_policy():
        try:
            data = current_project()
            dialog = tk.Toplevel(root)
            dialog.title("Experiment Duplication Policy")
            dialog.transient(root)
            ttk.Label(dialog, text="Optional flat public module.ini keys. Unlisted settings reset.\n"
                      "Datasets, Workspaces, graphs and scientific bindings are always excluded.",
                      wraplength=680).pack(padx=12, pady=10)
            text = tk.Text(dialog, width=86, height=16, undo=True)
            text.pack(fill="both", expand=True, padx=12)
            text.insert("1.0", json.dumps(data.get("duplication_policy",
                        {"experiment_duplication.api_version": 1}), indent=2))
            result = tk.StringVar(value="Validate uses the installed public CORE contract.")
            ttk.Label(dialog, textvariable=result, wraplength=680).pack(padx=12, pady=8)
            def check_policy(apply=False):
                try:
                    proposed = dict(data, duplication_policy=json.loads(text.get("1.0", "end")))
                    # Descriptor validation needs identities/types, not research execution.
                    validate_duplication_policy(proposed, [(Path("source"), "bundle/main", b"")])
                    result.set("Valid optional policy; global exclusions and ownership still apply.")
                    if apply:
                        show_project(proposed)
                        dialog.destroy()
                except Exception as exc:
                    result.set(str(exc))
            bar = ttk.Frame(dialog)
            bar.pack(pady=10)
            for label, command in (("Validate policy", check_policy),
                                   ("Apply", lambda: check_policy(True)), ("Cancel", dialog.destroy)):
                ttk.Button(bar, text=label, command=command).pack(side="left", padx=4)
            dialog.grab_set()
            text.focus_set()
        except Exception as exc:
            messagebox.showerror("Module Builder", str(exc))

    def save_project():
        try:
            target = project_file.get() or filedialog.asksaveasfilename(defaultextension=".json")
            if not target:return False
            current_project()
            text=editor.get("1.0","end-1c")
            Path(target).write_text(text,encoding="utf-8")
            project_file.set(target);state["baseline"]=text
            status.set(f"Saved {target}");return True
        except Exception as error:
            messagebox.showerror("Module Builder",str(error));return False

    def leave_project():
        if state["request"]:
            status.set("Cancel the current request and wait for its cleanup first.");return False
        if editor.get("1.0","end-1c") == state["baseline"]:return True
        answer=messagebox.askyesnocancel("Builder draft","Save the current Builder project before leaving?")
        return False if answer is None else save_project() if answer else True

    def close():
        if not leave_project():return
        # The shared source Workspace owns its own dirty/Notes review.
        for language in ("Python","Octave"):
            owner=f"::GX::{language}ScriptEditorUI"
            if host.call("info","commands",owner+"::_close"):
                host.call(owner+"::_close")
                if host.call("info","exists",owner+"::ui(window)"):
                    window=host.call("set",owner+"::ui(window)")
                    if host.call("winfo","exists",window):return
        state["closed"]=True;root.destroy()

    def action(make_package):
        if state["request"] or not save_project():return
        if make_package and not output_dir.get():
            status.set("Choose a package output directory first.");return
        project=Path(project_file.get()).resolve()
        reviewed=state["inspection"]
        expected=digest((json.dumps(reviewed["inventory"],ensure_ascii=False,sort_keys=True,separators=(",",":"),allow_nan=False)+"\n").encode()) if reviewed else ""
        payload=dict(operation="build" if make_package else "validate",project_path=str(project),
                     project_sha256=digest(project.read_bytes()),output=output_dir.get(),inventory_sha256=expected)
        def completed(result):
            status.set(("Built "+result["package"]+" · SHA256 "+result["sha256"]) if make_package else
                       "Validated exact saved source · inventory SHA256 "+result["inventory_sha256"])
        auxiliary(payload,completed,digest(editor.get("1.0","end-1c").encode()))

    menus=tk.Menu(root,tearoff=False);root.configure(menu=menus)
    def menu(label,items):
        child=tk.Menu(menus,tearoff=False);menus.add_cascade(label=label,menu=child)
        for title,command in items:child.add_command(label=title,command=command)
        return child
    menu("File",[("New from script…",lambda:create_project() if leave_project() else None),
                 ("New from registered Script / Project…",create_registered_project),
                 ("Open Builder project",lambda:open_project() if leave_project() else None),
                 ("Save",save_project),("Close",close)])
    menu("Project",[("Details…",edit_details),("Add Analysis Source…",add_source),("Add variable…",add_binding),
                    ("Add field…",add_field),("Require API…",add_api),("Outputs & notes…",edit_outputs),
                    ("Workbench extension…",workbench_profile),("Duplication policy…",edit_duplication_policy)])
    menu("Sources",[("Refresh saved project / inventory",refresh_registered),("Open source Workspace",source_workspace),
                    ("Open selected source",open_roster_source),("Add bundle file…",add_bundle_file),
                    ("Remove selected bundle file",remove_bundle_file),("Rename package-relative file…",rename_bundle_file),("Use selected entrypoint",choose_entrypoint),
                    ("Review Analysis inputs",refresh_sources),("Use script declaration",lambda:resolve_declaration("script")),
                    ("Keep manual Analysis inputs",lambda:resolve_declaration("manual"))])
    menu("Public APIs",[("Refresh static inventory",refresh_inventory),("Operation details",lambda:(operation_details(),api_book.select(api_details))),
                       ("Open implementation",open_implementation)])
    menu("Run",[("Validate",lambda:action(False)),("Build ZIP",lambda:action(True)),("Cancel current request",cancel_request)])
    def request_details():
        show_detail(json.dumps(dict(status=status.get(),receipt=state.get("last_receipt")),ensure_ascii=False,indent=2,allow_nan=False))
        workspace.select(api_page);api_book.select(api_details)
    menu("Help",[("Builder manual",lambda:host.call("::GX::documentationBrowserManualShow","tool.script_module_builder")),
                 ("Last request details / full diagnostic",request_details)])
    status_summary=tk.StringVar()
    status_label=ttk.Label(root,textvariable=status_summary)
    def status_layout(*args):
        value=" ".join(status.get().split())
        available=max(180,root.winfo_width()-32)
        face=tkfont.nametofont("TkDefaultFont")
        if face.measure(value)>available:
            suffix="… (Help → request details)"
            while value and face.measure(value+suffix)>available:value=value[:-1]
            value+=suffix
        status_summary.set(value)
    status.trace_add("write",status_layout)
    status_label.grid(row=3,column=0,columnspan=3,sticky="ew",padx=8,pady=8)
    status_label.bind("<Configure>",status_layout)
    status_layout()
    workspace.bind("<<NotebookTabChanged>>",lambda event:refresh_inventory() if workspace.select() in (str(files_page),str(api_page)) and editor.get("1.0","end-1c").strip() and not state["request"] and not state["inspection"] else None)
    root.bind("<Control-s>",lambda event:(save_project(),"break")[-1])
    root.protocol("WM_DELETE_WINDOW",close)
    root._gxtxt_builder=dict(editor=editor,workspace=workspace,files=file_table,apis=api_table,details=detail_widget,
                            state=state,status=status,project_file=project_file,output_dir=output_dir,
                            show_project=show_project,refresh_inventory=refresh_inventory,refresh_registered=refresh_registered,
                            use_snapshot=use_snapshot,action=action,source_workspace=source_workspace,menus=menus)
    if on_ready is not None:
        root.after(0, lambda: on_ready(root))
    root.mainloop()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("validate", "build"):
        command = sub.add_parser(name)
        command.add_argument("project", type=Path)
        if name == "build":
            command.add_argument("output", type=Path)
    graphical = sub.add_parser("gui")
    graphical.add_argument("--session", default="", help="Actual captured host Session for public source selection; no Session is created")
    sub.add_parser("managed-request", help=argparse.SUPPRESS)
    viewer = sub.add_parser('viewer-build', help='Package a CORE-validated Viewer design')
    viewer.add_argument('project', type=Path)
    viewer.add_argument('source_directory', type=Path)
    viewer.add_argument('output', type=Path)
    args = parser.parse_args()
    if args.command == "managed-request":
        _provided_parser()  # Loads the existing CORE inert Tcl-data serializer.
        serializer = sys.modules["script_api_declarations"].tcl
        try:
            raw = sys.stdin.read(2097153)
            if len(raw.encode("utf-8")) > 2097152:
                raise ValueError("Builder auxiliary metadata request exceeds2MiB")
            payload=json.loads(raw)
            pins=payload.pop("code_pins",None)
            names=("plugins/modules/tool.script_module_builder/runtime/builder.py","core/python/script_api_exports.py","core/python/script_api_declarations.py","core/python/script_project.py","core/tcl/script_provided_api_v1.tcl","core/tcl/script_execution_api_v1.tcl","core/tcl/script_project_v1.tcl")
            core_root=Path(__file__).resolve().parents[4]
            def code_check():
                if not isinstance(pins,dict) or set(pins)!=set(names) or any(digest((core_root/name).read_bytes())!=sha for name,sha in pins.items()):
                    raise ValueError("Trusted Builder source owner changed during the request; retry after review")
            code_check()
            response = managed_request(payload)
            code_check()
            print(serializer(dict(ok=True, result_json=json.dumps(response, ensure_ascii=False, separators=(",", ":"), allow_nan=False))))
        except Exception as error:
            print(serializer(dict(ok=False, error=str(error))))
        return 0
    try:
        if args.command == "gui":
            gui(session=args.session)
        elif args.command == 'viewer-build':
            path, sha = build_viewer(args.project, args.source_directory, args.output)
            print(f'BUILT {path} SHA-256 {sha}')
        elif args.command == "validate":
            data, files = validate(args.project)
            print(f"VALID {data['id']} {data['language']} SHA-256 {digest(files[0][2])}")
        else:
            path, sha = build(args.project, args.output)
            print(f"BUILT {path} SHA-256 {sha}")
    except Exception as exc:
        print(f"Module Builder: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
