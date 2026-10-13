"""Octave Script Bridge registration owned by plot.dataset / PLOT_DATASET_API_v2."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError


def _mapping(host, value):
    return host.as_dict(value)


def _plot_spec(host, value):
    spec = _mapping(host, value)
    if "plotspec" in spec:
        spec["plotspec"] = _plot_spec(host, spec["plotspec"])
    if "artifacts" in spec:
        spec["artifacts"] = _mapping(host, spec["artifacts"])
    if "series" in spec:
        spec["series"] = [_mapping(host, item) for item in host.tcl.splitlist(spec["series"])]
    for key in ("defaults", "output", "config"):
        if key in spec:
            spec[key] = _mapping(host, spec[key])
    if "style" in spec.get("defaults", {}):
        spec["defaults"]["style"] = _mapping(host, spec["defaults"]["style"])
    if "panels" in spec:
        panels = []
        for raw_panel in host.tcl.splitlist(spec["panels"]):
            panel = _mapping(host, raw_panel)
            if "axes" in panel:
                axes = _mapping(host, panel["axes"])
                panel["axes"] = {key: _mapping(host, axis) for key, axis in axes.items()}
            for key in ("series", "annotations"):
                if key in panel:
                    items = []
                    for raw_item in host.tcl.splitlist(panel[key]):
                        item = _mapping(host, raw_item)
                        if key == "series":
                            for nested in ("style", "x_error", "y_error", "band", "bar_bounds"):
                                if nested in item:
                                    item[nested] = _mapping(host, item[nested])
                        items.append(item)
                    panel[key] = items
            panels.append(panel)
        spec["panels"] = panels
    return spec

REGISTRATION = {
    "api_id": "PLOT_DATASET_API_v2", "api_version": 2,
    "provider_kind": "module", "provider_id": "plot.dataset",
    "documentation_ref": "docs/api/PLOT_DATASET_API_v2.md",
    "operations": {
        "api_info": {"name": "api_info", "summary": "Inspect the public Plot Dataset capability descriptor", "argument_convention": "no arguments", "result_convention": "descriptor struct"},
        "validate_spec": {"name": "validate_spec", "summary": "Validate a public PlotSpec v2", "argument_convention": "PlotSpec struct", "result_convention": "logical"},
        "create_plot": {"name": "create_plot", "summary": "Create a public Plot Dataset graph", "argument_convention": "PlotSpec struct, optional kind", "result_convention": "plot reference struct"},
        "read_plot": {"name": "read_plot", "summary": "Read a public Plot Dataset graph", "argument_convention": "Plot reference struct", "result_convention": "plot record struct"},
        "render": {"name": "render", "summary": "Render a public Plot Dataset graph", "argument_convention": "Plot reference struct", "result_convention": "render result"},
        "rerender": {"name": "rerender", "summary": "Rerender a public Plot Dataset graph", "argument_convention": "Plot reference struct", "result_convention": "render result"},
    },
}
_V2_ARGUMENTS = {
    "api_info": [], "validate_spec": [("spec", "PlotSpec v2 struct")],
    "create_plot": [("spec", "PlotSpec v2 struct"), ("kind", "base or variant")],
    "read_plot": [("plot_ref", "plot reference struct")],
    "render": [("plot_ref", "plot reference struct")],
    "rerender": [("plot_ref", "plot reference struct")],
}
for _name, _fields in _V2_ARGUMENTS.items():
    _operation = REGISTRATION["operations"][_name]
    _operation["arguments"] = [{"name": name, "kind": kind, "required": name != "kind"}
                               for name, kind in _fields]
    _operation["result_contract"] = _operation["result_convention"]

V3_REGISTRATION = {
    "api_id": "PLOT_DATASET_API_v3", "api_version": 3,
    "provider_kind": "module", "provider_id": "plot.dataset",
    "documentation_ref": "docs/api/PLOT_DATASET_API_v3.md",
    "operations": {
        "api_info": {"name": "api_info", "summary": "Inspect Plot Dataset v3 capabilities", "arguments": [], "result_contract": "descriptor struct"},
        "new_spec": {"name": "new_spec", "summary": "Create a public PlotSpec v2 template", "arguments": [{"name": "graph_id", "kind": "string", "required": True}, {"name": "title", "kind": "string", "required": True}], "result_contract": "PlotSpec v2 struct"},
        "validate_spec": {"name": "validate_spec", "summary": "Validate a public PlotSpec v2", "arguments": [{"name": "spec", "kind": "struct", "required": True}], "result_contract": "logical"},
        "create_plot": {"name": "create_plot", "summary": "Create a normal Plot Dataset plot or variant", "arguments": [{"name": "spec", "kind": "PlotSpec v2 struct", "required": True}, {"name": "kind", "kind": "base or variant", "required": True}, {"name": "source_variant", "kind": "string", "required": False}], "result_contract": "plot reference struct"},
        "upsert_plot": {"name": "upsert_plot", "summary": "Create or update a persistent plot owned by this script module", "arguments": [{"name": "provider_key", "kind": "string", "required": True}, {"name": "spec", "kind": "PlotSpec v2 struct", "required": True}], "result_contract": "plot reference struct"},
        "read_plot": {"name": "read_plot", "summary": "Read a persistent plot", "arguments": [{"name": "plot_ref", "kind": "struct", "required": True}], "result_contract": "plot record struct"},
        "render": {"name": "render", "summary": "Render a persistent plot", "arguments": [{"name": "plot_ref", "kind": "struct", "required": True}], "result_contract": "render result struct"},
        "artifacts": {"name": "artifacts", "summary": "Inspect plot artifacts", "arguments": [{"name": "plot_ref", "kind": "struct", "required": True}], "result_contract": "artifact struct"},
        "build_scene": {"name": "build_scene", "summary": "Build a persistent scientific 3D representation", "arguments": [{"name": "plot_ref", "kind": "struct", "required": True}], "result_contract": "representation struct"},
        "interactive_status": {"name": "interactive_status", "summary": "Inspect an interactive representation", "arguments": [{"name": "representation_id", "kind": "string", "required": True}], "result_contract": "status string"},
        "sync_interactive": {"name": "sync_interactive", "summary": "Synchronize a 3D representation explicitly", "arguments": [{"name": "representation_id", "kind": "string", "required": True}], "result_contract": "scene struct"},
    },
}
_V3_PUBLIC = {
    "rerender": ("rerender", [("plot_ref", "struct")], "render result struct"),
    "apply_spec": ("applySpec", [("plot_ref", "struct"), ("spec", "struct")], "plot record struct"),
    "load_spec": ("loadSpec", [("plot_ref", "struct"), ("derive_if_missing", "integer", False)], "PlotSpec struct"),
    "save_spec": ("saveSpec", [("plot_ref", "struct"), ("spec", "struct")], "integer 1"),
    "remove_spec": ("removeSpec", [("plot_ref", "struct")], "integer 0 or 1"),
    "open_plot": ("openPlot", [("graph_id", "string"), ("variant_id", "string", False)], "plot reference struct"),
    "delete_plot": ("deletePlot", [("plot_ref", "struct")], "integer 0 or 1"),
    "set_plot_enabled": ("setPlotEnabled", [("plot_ref", "struct"), ("state", "integer")], "integer 0 or 1"),
    "set_series_presentation": ("setSeriesPresentation", [("plot_ref", "struct"), ("series_id", "string"), ("fields", "struct")], "series struct"),
    "multi_panel_enabled": ("multiPanelEnabled", [("plot_ref", "struct")], "integer 0 or 1"),
    "set_multi_panel": ("setMultiPanel", [("plot_ref", "struct"), ("state", "integer")], "integer 0 or 1"),
    "panel_ids": ("panelIds", [("plot_ref", "struct")], "cell of panel IDs"),
    "panel_info": ("panelInfo", [("plot_ref", "struct"), ("panel_id", "string")], "panel struct"),
    "add_panel": ("addPanel", [("plot_ref", "struct"), ("panel_id", "string")], "PlotSpec struct"),
    "remove_panel": ("removePanel", [("plot_ref", "struct"), ("panel_id", "string")], "PlotSpec struct"),
    "move_panel": ("movePanel", [("plot_ref", "struct"), ("panel_id", "string"), ("delta", "integer")], "PlotSpec struct"),
    "set_panel_title": ("setPanelTitle", [("plot_ref", "struct"), ("panel_id", "string"), ("title", "string")], "panel struct"),
    "set_panel_axis": ("setPanelAxis", [("plot_ref", "struct"), ("panel_id", "string"), ("axis", "string"), ("fields", "struct")], "panel struct"),
    "set_series_panel": ("setSeriesPanel", [("plot_ref", "struct"), ("series_id", "string"), ("panel_id", "string")], "PlotSpec struct"),
    "interactive_sources": ("interactiveSources", [], "cell of plot references"),
    "interactive_source_info": ("interactiveSourceInfo", [("plot_ref", "struct")], "source struct"),
    "source_fingerprint": ("sourceFingerprint", [("plot_ref", "struct")], "fingerprint string"),
    "interactive_representations": ("interactiveRepresentations", [], "cell of representation structs"),
}
for _name, (_command, _fields, _result) in _V3_PUBLIC.items():
    V3_REGISTRATION["operations"][_name] = {
        "name": _name, "summary": f"Public Plot Dataset {_command}",
        "arguments": [{"name": f[0], "kind": f[1], "required": f[2] if len(f) > 2 else True} for f in _fields],
        "result_contract": _result,
    }
for _operation in V3_REGISTRATION["operations"].values():
    _operation["argument_convention"] = ", ".join(a["name"] for a in _operation["arguments"]) or "no arguments"
    _operation["result_convention"] = _operation["result_contract"]
REGISTRATIONS = [REGISTRATION, V3_REGISTRATION]


def invoke_api(host, api_id, operation, args):
    if api_id == "PLOT_DATASET_API_v2":
        return invoke(host, operation, args)
    host.call("::GX::modulePublicApiActivate", "plot.dataset", "PLOT_DATASET_API_v3")
    prefix = "::GX::PlotDatasetAPIv3::"
    if operation == "api_info" and not args:
        return host.as_dict(host.call(prefix + "apiInfo"))
    if operation == "new_spec" and len(args) == 2 and all(isinstance(x, str) for x in args):
        return _plot_spec(host, host.call(prefix + "newSpec", "-graph_id", args[0], "-title", args[1]))
    if operation == "validate_spec" and len(args) == 1 and isinstance(args[0], dict):
        result = host.call(prefix + "validateSpec", args[0])
        return bool(host.tcl.getboolean(result))
    if operation == "create_plot" and len(args) in (2, 3) and isinstance(args[0], dict) and args[1] in ("base", "variant") and (len(args) == 2 or isinstance(args[2], str)):
        ref = host.as_dict(host.call(prefix + "createPlotFromSpec", *args))
        host.persist_manifest("create_plot")
        return ref
    if operation == "upsert_plot" and len(args) == 2 and isinstance(args[0], str) and isinstance(args[1], dict):
        key = f"{host.module_id}:{args[0]}"
        ref = host.as_dict(host.call(prefix + "upsertPlotFromSpec", host.module_id, key, args[1]))
        host.persist_manifest("upsert_plot")
        return ref
    if operation == "read_plot" and len(args) == 1 and isinstance(args[0], dict):
        return _plot_spec(host, host.call(prefix + "readPlot", args[0]))
    if operation in ("render", "rerender", "artifacts", "build_scene") and len(args) == 1 and isinstance(args[0], dict):
        command = {"render": "render", "rerender": "rerender", "artifacts": "artifacts", "build_scene": "buildScene"}[operation]
        return host.normalize(host.call(prefix + command, args[0]))
    if operation in ("interactive_status", "sync_interactive") and len(args) == 1 and isinstance(args[0], str):
        command = {"interactive_status": "interactiveStatus", "sync_interactive": "syncInteractive"}[operation]
        return host.normalize(host.call(prefix + command, args[0]))
    if operation in _V3_PUBLIC:
        command, fields, _result = _V3_PUBLIC[operation]
        required = sum(f[2] if len(f) > 2 else True for f in fields)
        if required <= len(args) <= len(fields) and all(
            isinstance(value, dict) if field[1] == "struct" else
            isinstance(value, str) if field[1] == "string" else
            isinstance(value, (int, float)) and int(value) == value
            for value, field in zip(args, fields)):
            result = host.call(prefix + command, *args)
            if operation in {"save_spec", "remove_spec", "delete_plot", "set_plot_enabled", "multi_panel_enabled", "set_multi_panel"}:
                normalized = 1 if operation == "save_spec" else int(result)
            elif operation == "load_spec":
                normalized = _plot_spec(host, result)
            elif operation in {"panel_ids", "interactive_sources", "interactive_representations"}:
                normalized = [host.normalize(item) for item in host.as_list(result)]
            else:
                normalized = host.normalize(result)
            if operation in {"apply_spec", "delete_plot", "set_plot_enabled", "set_series_presentation"}:
                host.persist_manifest(operation)
            return normalized
    raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"invalid {operation} arguments for PLOT_DATASET_API_v3")


def invoke(host, operation, args):
    host.call("::GX::modulePublicApiActivate", "plot.dataset", "PLOT_DATASET_API_v2")
    prefix = "::GX::PlotDatasetAPIv2::"
    if operation == "api_info" and not args:
        return host.as_dict(host.call(prefix + "apiInfo"))
    if operation == "validate_spec" and len(args) == 1 and isinstance(args[0], dict):
        result = host.call(prefix + "validateSpec", args[0])
        return bool(host.tcl.getboolean(result))
    if operation == "create_plot" and len(args) in (1, 2) and isinstance(args[0], dict):
        return host.as_dict(host.call(prefix + "createPlotFromSpec", *args))
    if operation == "read_plot" and len(args) == 1 and isinstance(args[0], dict):
        return _plot_spec(host, host.call(prefix + "readPlot", args[0]))
    if operation in ("render", "rerender") and len(args) == 1 and isinstance(args[0], dict):
        result = host.call(prefix + operation, args[0])
        try:
            return host.as_dict(result)
        except BridgeError:
            return str(result)
    raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"invalid {operation} arguments for PLOT_DATASET_API_v2")
