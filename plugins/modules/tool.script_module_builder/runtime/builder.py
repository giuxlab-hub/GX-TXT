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


def workbench_descriptor(data):
    spec = data['workbench_extension']; api, namespace = workbench_ids(data)
    action = spec['action_id']; fields = data.get('fields',[])
    blocks = [ini_section('public_apis', {'ids':api}),
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
    blocks.append(ini_section("script", {"api_version": 1, "language": data["language"],
        "main": files[0][1], "sha256": digest(files[0][2]), "profile": data["profile"],
        "required_apis": apis, "bundle_inventory": "bundle/SHA256SUMS"}))
    exposure = data.get("public_api")
    if exposure:
        namespace = "::GX::GeneratedScriptAPI_" + re.sub(r"[^A-Za-z0-9_]", "_", data["id"])
        blocks.append(ini_section("public_apis", {"ids": exposure["id"]}))
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
    blocks.append(ini_section("documentation", {"api_version": 1, "guide": "MANUAL.md",
        "changelog": "CHANGELOG.md", "examples": files[0][1]}))
    if data["profile"] == "W":
        blocks.extend(workbench_descriptor(data))
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


def write_module_zip(payload: dict[str, bytes], module_id: str, version: str, output: Path) -> tuple[Path, str]:
    """Shared deterministic standard-package writer for every Builder profile."""
    output = output.resolve(); output.mkdir(parents=True, exist_ok=True)
    zip_path = output / f"{module_id}_{version}.zip"
    if zip_path.exists() or zip_path.with_suffix('.zip.sha256').exists():
        raise FileExistsError(f'refusing to overwrite {zip_path}')
    payload = dict(payload)
    payload.pop('SHA256SUMS.txt', None)
    payload['SHA256SUMS.txt'] = ''.join(f'{digest(payload[name])}  {name}\n' for name in sorted(payload)).encode()
    with tempfile.NamedTemporaryFile(dir=output, prefix='.viewer-package-', delete=False) as temporary_file:
        temporary = Path(temporary_file.name)
    try:
        with ZipFile(temporary, 'w', compression=ZIP_DEFLATED, compresslevel=9) as archive:
            for name in sorted(payload):
                if name.startswith('/') or '..' in Path(name).parts:
                    raise ValueError('Invalid module asset path')
                info = ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
                info.compress_type = ZIP_DEFLATED; info.external_attr = 0o100644 << 16
                archive.writestr(info, payload[name], compress_type=ZIP_DEFLATED, compresslevel=9)
        # No partial package is installable; link promotion also refuses races.
        os.link(temporary, zip_path)
    finally:
        temporary.unlink(missing_ok=True)
    zip_sha = digest(zip_path.read_bytes())
    zip_path.with_suffix('.zip.sha256').write_text(f'{zip_sha}  {zip_path.name}\n', encoding='utf-8')
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
            accepted_versions=1, validate='::GX::viewerGuiDesignStateValidate', open=namespace+'::workspaceOpen'))
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
            name=title, version=version, type='module', framework_min='0.9.8.10-dev-107' if 'NATIVE_3D_GUI_HOST_API_v2' in dictionary(design['requirements']) else '0.9.8.10-dev-104', framework_max='')).encode(),
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
    if 'NATIVE_3D_GUI_HOST_API_v2' in dictionary(design['requirements']):
        generated['MANUAL.md'] += ('''\n## Embedded Native3D viewport\n\nThis design requires the public `NATIVE_3D_GUI_HOST_API_v2` contract, version 2,\nprovided by CORE in GX-TXT dev107. The generated connector declares that capability;\nit does not depend on an exact unrelated Analysis or Viewer module release.\n\nOpen this installed Viewer from the standard Viewers catalogue. Its `native3d`\ncomponent is a child of the Viewer, with an independent scene, camera and worker.\nDrag the viewport with the left pointer button to orbit. Shift-drag pans. The\nmouse wheel zooms. Use the native Fit, Reset, Front and Top controls to recover\na useful view. Arrow keys orbit; F fits and R restores the isometric view when\nthe viewport has keyboard focus. The orientation cube is a rendered orientation\nindicator; direct cube-face clicking is not an exposed interaction contract.\n\nA short pointer click performs actual native geometry hit testing. Selection\nreceipts identify the layer and native world/local hit; no scientific edit or\nDataset publication follows from selection. Resize or hide/show a containing tab\nwithout transferring the camera to another Viewer. Closing this Viewer releases\nonly its own worker and callbacks.\n\n### Presentation properties\n\nBuilder exposes bounded width/height, perspective or orthographic projection,\ncamera position/target/up, world axes and orientation-indicator visibility.\nApply these in the normal property inspector, then Save/Open the design. These\nare presentation settings, not scientific coordinate calibration.\n\n### Explicit demonstration and scientific bindings\n\nA component with `demo=1` renders a deterministic RAM cube and axes. This is\nexplicitly synthetic, display-only content, with no Session, Dataset or files.\nA component without that flag starts empty until an authorized handler explicitly\nbinds a source through the public CORE host. Gallery and Runtime Test are distinct\nmodes; an ordinary unconnected scientific action remains `not_connected`.\n\nFor real data, obtain the opaque viewport handle from the public Viewer host\nand call `native3DViewportBind` with `kind scientific`, the registered module\nand provider. CORE resolves the current Dataset identity, units and Session\nrevision through its public provider and Dataset owners. No raw user-file path\nor private renderer state is accepted by this binding. Stale scientific identity\nblocks interaction until an explicit valid rebind. `native3DViewportUnbind`\nreturns the component to its empty state.\n\nThe full contract is in the installed public API guide\n`NATIVE_3D_GUI_HOST_API_v2`: create/configure/bind/unbind/update, navigation and\ncamera, command/pick, subscribe/unsubscribe, inspect and release. Native rendering\nerrors are reported visibly; rebind only after correcting the source or runtime\nproblem. This guide does not claim unsupported mesh editing or scientific output.\n''').encode('utf-8')
    handlers = source_directory / 'handlers.tcl'
    if handlers.is_symlink(): raise ValueError('A handwritten handler source must be an ordinary file')
    if handlers.exists() and handlers.stat().st_size > 8 * 1024 * 1024:
        raise ValueError('Handwritten handlers exceed the 8 MiB source bound')
    if not handlers.exists():
        body = '# Handwritten scientific hooks; preserved on regeneration.\n'
        body += f'namespace eval {namespace}::Handlers {{}}\n'
        for action in sorted(contracts):
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
    payload.update(public_api_files(data))
    if data["profile"] == "W":
        payload.update(workbench_api_files(data))
    portable = dict(data)
    portable["source"] = source_files[0][1]
    portable["bundle"] = [{"source": rel, "target": rel.removeprefix("bundle/")} for _, rel, _ in source_files[1:]]
    portable["source_sha256"] = digest(source_files[0][2])
    payload["builder-project.json"] = (json.dumps(portable, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
    payload["SHA256SUMS.txt"] = "".join(f"{digest(payload[name])}  {name}\n" for name in sorted(payload)).encode()
    return write_module_zip(payload, data['id'], data['version'], output)


def gui(*, on_ready=None) -> None:
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk
    import configparser

    root = tk.Tk()
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
    editor_frame = ttk.Frame(root)
    editor_frame.grid(row=2, column=0, columnspan=3, sticky="nsew", padx=8, pady=8)
    editor = tk.Text(editor_frame, wrap="none", undo=True)
    editor_y = ttk.Scrollbar(editor_frame, orient="vertical", command=editor.yview)
    editor_x = ttk.Scrollbar(editor_frame, orient="horizontal", command=editor.xview)
    editor.configure(yscrollcommand=editor_y.set, xscrollcommand=editor_x.set)
    editor_x.pack(side="bottom", fill="x");editor_y.pack(side="right", fill="y");editor.pack(fill="both", expand=True)
    source_frame = ttk.LabelFrame(root, text="Analysis Sources discovered from the script")
    source_frame.grid(row=3, column=0, columnspan=3, sticky="ew", padx=8, pady=4)
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

    def current_project():
        value = json.loads(editor.get("1.0", "end"))
        if not isinstance(value, dict):
            raise ValueError("Project must be a JSON object")
        return value

    def show_project(value):
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
        registry = filedialog.askopenfilename(title="Choose a registered script.ini",
                                               filetypes=[("GX-TXT registered script", "script.ini")])
        if not registry:
            return
        try:
            config = configparser.ConfigParser(interpolation=None)
            config.read(registry, encoding="utf-8")
            record = config["script"]
            language = record.get("language", "")
            if language not in ("Python", "Octave"):
                raise ValueError("Registered script language must be Python or Octave")
            suffix = ".py" if language == "Python" else ".m"
            source = Path(registry).parent / ("source" + suffix)
            if not source.is_file():
                raise ValueError(f"Registered source is missing: {source}")
            template = {"schema_version": 1, "id": "research." + record["id"],
                "name": record.get("name", record["id"]), "description": record.get("description", "Research analysis"),
                "version": record.get("version", "1.0.0"), "group": "Research", "license": "GPL-3.0-or-later",
                "profile": "A", "language": language, "source": str(source),
                "sources": [{"id": "primary", "required": True}], "bindings": [], "fields": [],
                "required_apis": [item for item in record.get("required_apis", "").split(";") if item],
                "outputs": {"datasets": [], "files": []}, "documentation": ""}
            discovered = declared_sources(source)
            if discovered is not None:
                template["sources"] = discovered[0]
            project_file.set("")
            show_project(template)
            status.set(f"Imported registered {language} script {record['id']}; "
                       f"{len(template['sources'])} Analysis Sources; source SHA-256 {digest(source.read_bytes())}")
        except Exception as exc:
            messagebox.showerror("Module Builder", str(exc))

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
            if not target:
                return
            json.loads(editor.get("1.0", "end"))
            Path(target).write_text(editor.get("1.0", "end"), encoding="utf-8")
            project_file.set(target)
            status.set(f"Saved {target}")
        except Exception as exc:
            messagebox.showerror("Module Builder", str(exc))

    def action(make_package: bool):
        try:
            save_project()
            if not project_file.get():
                return
            data, files = validate(Path(project_file.get()))
            status.set(f"Valid {data['language']} module; source SHA-256 {digest(files[0][2])}")
            if make_package:
                if not output_dir.get():
                    raise ValueError("Choose an output directory")
                archive, sha = build(Path(project_file.get()), Path(output_dir.get()))
                status.set(f"Built {archive}; SHA-256 {sha}")
        except Exception as exc:
            messagebox.showerror("Module Builder", str(exc))

    def flow_actions(bar, width):
        children=bar.winfo_children()
        widths=tuple(child.winfo_reqwidth()+6 for child in children)
        height=max((child.winfo_reqheight()+4 for child in children),default=1)
        signature=(width,widths,height)
        if getattr(bar,'_flow_signature',None)==signature:return
        bar._flow_signature=signature
        row=used=0
        for child,needed in zip(children,widths):
            if used and used+needed>max(200,width):row+=1;used=0
            child.place(x=used+3,y=row*height+2,width=needed-6,height=height-4)
            used+=needed
        bar.configure(height=(row+1)*height)

    for row, buttons in enumerate((
        (("New from script…", create_project), ("New from registered…", create_registered_project),
         ("Open", open_project), ("Details…", edit_details), ("Add source…", add_source),
         ("Add variable…", add_binding), ("Workbench extension…", workbench_profile)),
        (("Add field…", add_field), ("Require API…", add_api), ("Outputs & notes…", edit_outputs),
         ("Duplication policy…", edit_duplication_policy),
         ("Save", save_project), ("Validate", lambda: action(False)),
         ("Build ZIP", lambda: action(True))),
        (("Review script sources", refresh_sources),
         ("Use script declaration", lambda: resolve_declaration("script")),
         ("Keep manual source settings", lambda: resolve_declaration("manual"))),
    ), start=4):
        bar = ttk.Frame(root)
        bar.grid(row=row, column=0, columnspan=3, sticky="ew", padx=8, pady=2)
        for label, command in buttons:
            ttk.Button(bar, text=label, command=command)
        bar.bind("<Configure>",lambda event,b=bar:flow_actions(b,event.width))
        flow_actions(bar,min(1080,root.winfo_screenwidth()-40)-16)
    status_label=ttk.Label(root, textvariable=status, wraplength=1040)
    status_label.grid(row=7, column=0, columnspan=3, sticky="ew", padx=8, pady=8)
    status_label.bind("<Configure>",lambda event:status_label.configure(wraplength=max(100,event.width-16)))
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
    sub.add_parser("gui")
    viewer = sub.add_parser('viewer-build', help='Package a CORE-validated Viewer design')
    viewer.add_argument('project', type=Path)
    viewer.add_argument('source_directory', type=Path)
    viewer.add_argument('output', type=Path)
    args = parser.parse_args()
    try:
        if args.command == "gui":
            gui()
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
