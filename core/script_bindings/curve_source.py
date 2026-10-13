"""Execution-scoped exact curve sources and bounded Native2D display proxies."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError, NumericArray

_ARGS = {
    "api_info": [], "open": ["request"], "describe": ["source"], "validate_snapshot": ["descriptor"],
    "display": ["source"], "page": ["source", "start", "count"],
    "locate_rows": ["source", "source_rows"],
    "open_stream": ["source", "variable_ids", "chunk_rows", "options"],
    "close_stream": ["source", "stream"], "close": ["source"],
}
REGISTRATION = {
    "api_id": "CURVE_SOURCE_API_v1", "api_version": 1,
    "provider_kind": "core", "provider_id": "curve_source",
    "documentation_ref": "docs/api/CURVE_SOURCE_API_v1.md",
    "operations": {
        name: {"name": name, "summary": "Backend-neutral curve source: " + name,
               "arguments": [{"name": arg, "kind": "opaque token" if arg in ("source", "stream") else "public value", "required": True} for arg in args],
               "argument_convention": ", ".join(args), "result_contract": "exact source descriptor or bounded typed result",
               "result_convention": "source token, public metadata or typed data"}
        for name, args in _ARGS.items()
    },
}


def _state(host):
    return host.handles.setdefault("curve_source", {"sources": set(), "streams": {}})


def _matrix(host, value):
    rows = [host.as_list(row) for row in host.as_list(value)]
    return NumericArray([float(row[column]) for column in range(2) for row in rows], [len(rows), 2])


def _close_stream(host, source, stream):
    state = _state(host)
    if state["streams"].get(stream) != source:
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Stream is not owned by this Curve Source")
    host.call("::GX::curveSourceCloseStream", source, stream)
    del state["streams"][stream]
    host.handles.setdefault("table_stream", set()).discard(stream)


def invoke(host, operation, args):
    if operation not in _ARGS or len(args) != len(_ARGS[operation]):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Invalid Curve Source arguments")
    state = _state(host)
    if operation == "api_info":
        result = host.as_dict(host.call("::GX::curveSourceApiInfo"))
        result["operations"] = host.as_list(result["operations"])
        return result
    if operation == "validate_snapshot":
        if not isinstance(args[0],dict):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments","Curve Source snapshot must be a struct")
        result=host.as_dict(host.call("::GX::curveSourceValidateSnapshot",host.session,args[0]))
        result["valid"]=str(result["valid"])=="1"
        for key in ("missing_dataset_ids","stale_dataset_ids","reasons"):
            result[key]=host.as_list(result[key])
        result["source_identities"]=[host.as_dict(item) for item in host.as_list(result["source_identities"])]
        return result
    if operation == "open":
        if not isinstance(args[0], dict):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Curve Source request must be a struct")
        token = str(host.call("::GX::curveSourceOpen", host.session, args[0]))
        state["sources"].add(token)
        return token
    token = args[0]
    if not isinstance(token, str) or token not in state["sources"]:
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Unknown/closed Curve Source in this execution")
    if operation == "describe":
        result = host.as_dict(host.call("::GX::curveSourceDescribe", token))
        result["request"] = host.as_dict(result["request"])
        if "filters" in result["request"]:
            result["request"]["filters"] = [host.as_dict(item) for item in host.as_list(result["request"]["filters"])]
        result["variables"] = [host.as_dict(item) for item in host.as_list(result["variables"])]
        result["source_identities"] = [host.as_dict(item) for item in host.as_list(result["source_identities"])]
        result["row_count"] = int(result["row_count"])
        result["display_budget"] = int(result["display_budget"])
        result["display_is_scientific_data"] = False
        return result
    if operation == "locate_rows":
        result = host.as_dict(host.call("::GX::curveSourceLocateRows", *args))
        for key in ("source_rows", "positions"):
            result[key] = [int(value) for value in host.as_list(result[key])]
        return result
    if operation in ("display", "page"):
        result = host.as_dict(host.call("::GX::curveSource" + operation.title(), *args))
        result["source_rows"] = [int(row) for row in host.as_list(result["source_rows"])]
        for key in ("row_count", "display_rows", "finite_rows", "start", "count"):
            if key in result: result[key] = int(result[key])
        if operation == "display":
            result["breaks"] = [int(item) for item in host.as_list(result["breaks"])]
            result["points"] = _matrix(host, result["points"])
            result["full_bounds"] = NumericArray(host.as_list(result["full_bounds"]))
            result["diagnostics"] = host.as_dict(result["diagnostics"])
            result["reduced"] = bool(int(result["reduced"]))
            result["display_is_scientific_data"] = False
        else:
            result["rows"] = _matrix(host, result["rows"])
            result["columns"] = [host.as_dict(item) for item in host.as_list(result["columns"])]
        return result
    if operation == "open_stream":
        # The shared script Table Stream binding owns numeric-array encoding;
        # native display ingestion independently uses Canonical binary columns.
        options = dict(args[3])
        options["numeric_transport"] = "values"
        stream = str(host.call("::GX::curveSourceOpenStream", token, args[1], args[2], options))
        state["streams"][stream] = token
        host.handles.setdefault("table_stream", set()).add(stream)
        return stream
    if operation == "close_stream":
        _close_stream(host, token, args[1])
        return True
    if operation == "close":
        for stream, owner in list(state["streams"].items()):
            if owner == token: _close_stream(host, token, stream)
        host.call("::GX::curveSourceClose", token)
        state["sources"].remove(token)
        return True


def cleanup(host):
    for token in list(_state(host)["sources"]):
        invoke(host, "close", [token])
