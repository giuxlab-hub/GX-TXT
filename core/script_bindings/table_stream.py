"""Provider-owned bounded Table Stream v3 Script Bridge binding."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError, NumericArray

REGISTRATION = {
    "api_id": "TABLE_STREAM_API_v3", "api_version": 3,
    "provider_kind": "core", "provider_id": "table_stream",
    "documentation_ref": "docs/api/TABLE_STREAM_API_v3.md",
    "operations": {
        "open_dataset": {"name": "open_dataset", "summary": "Open bounded canonical table stream", "arguments": [{"name": "dataset_id", "kind": "string", "required": True}, {"name": "variable_ids", "kind": "cell of strings", "required": True}, {"name": "chunk_rows", "kind": "integer", "required": True}, {"name": "options", "kind": "struct", "required": False}], "result_contract": "opaque stream token"},
        "metadata": {"name": "metadata", "summary": "Read selected stable Schema v3 variables", "argument_convention": "stream token", "result_convention": "metadata struct"},
        "next": {"name": "next", "summary": "Read the next bounded chunk", "argument_convention": "stream token", "result_convention": "chunk struct with typed values"},
        "diagnostics": {"name": "diagnostics", "summary": "Read stream diagnostics", "argument_convention": "stream token", "result_convention": "diagnostics struct"},
        "close": {"name": "close", "summary": "Close a stream", "argument_convention": "stream token", "result_convention": "logical"},
    },
}
for _op in REGISTRATION["operations"].values():
    _op.setdefault("arguments", [{"name": "stream", "kind": "opaque token", "required": True}])
    _op.setdefault("result_contract", _op.get("result_convention", ""))
    _op.setdefault("argument_convention", ", ".join(a["name"] for a in _op["arguments"]))
    _op.setdefault("result_convention", _op["result_contract"])


def _streams(host):
    return host.handles.setdefault("table_stream", set())


def _token(host, args):
    if len(args) != 1 or args[0] not in _streams(host):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "unknown or closed Table Stream token")
    return args[0]


def invoke(host, operation, args):
    if operation == "open_dataset":
        if len(args) not in (3, 4) or not isinstance(args[0], str) or not isinstance(args[1], list):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "open_dataset requires Dataset ID, variable IDs and chunk rows")
        options = dict(args[3]) if len(args) == 4 and isinstance(args[3], dict) else {}
        options["numeric_transport"] = "values"
        token = str(host.call("::GX::tableStreamOpenDataset", host.session, args[0], args[1], int(args[2]), options))
        _streams(host).add(token)
        return token
    token = _token(host, args)
    if operation == "metadata":
        raw = host.as_dict(host.call("::GX::tableStreamMetadata", token))
        raw["variables"] = [host.as_dict(item) for item in host.as_list(raw["variables"])]
        raw["selected_variable_ids"] = host.as_list(raw["selected_variable_ids"])
        return raw
    if operation == "next":
        raw = host.as_dict(host.call("::GX::tableStreamNext", token))
        values = host.as_dict(raw["values"])
        columns = [host.as_dict(item) for item in host.as_list(raw["columns"])]
        for column in columns:
            variable_id = column["variable_id"]
            entries = host.as_list(values[variable_id])
            typed = [str(v) for v in entries] if column["dtype"] == "string" else NumericArray(entries)
            values[variable_id] = typed
            column["values"] = typed
        raw["values"] = values
        raw["columns"] = columns
        raw["selected_variable_ids"] = host.as_list(raw["selected_variable_ids"])
        return raw
    if operation == "diagnostics":
        raw = host.as_dict(host.call("::GX::tableStreamDiagnostics", token))
        raw.pop("provider", None)
        return raw
    if operation == "close":
        source_state = host.handles.get("curve_source", {})
        owner = source_state.get("streams", {}).get(token)
        if owner is not None:
            host.call("::GX::curveSourceCloseStream", owner, token)
            del source_state["streams"][token]
            _streams(host).remove(token)
            return True
        host.call("::GX::tableStreamClose", token)
        _streams(host).remove(token)
        return True
    raise BridgeError("GXTXT:ScriptBridge:UnknownOperation", f"TABLE_STREAM_API_v3/{operation} is unavailable")


def cleanup(host):
    for token in list(_streams(host)):
        try:
            host.call("::GX::tableStreamClose", token)
        finally:
            _streams(host).discard(token)
