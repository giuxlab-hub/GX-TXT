"""Octave Script Bridge registration owned by Canonical Dataset API v2."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError, NumericArray

REGISTRATION = {
    "api_id": "CANONICAL_DATASET_API_v2", "api_version": 2,
    "provider_kind": "core", "provider_id": "canonical_dataset",
    "documentation_ref": "docs/api/CANONICAL_DATASET_API_v2.md",
    "operations": {
        "list": {"name": "list", "summary": "List Dataset IDs in the current Session", "argument_convention": "no arguments", "result_convention": "cell of Dataset IDs"},
        "describe": {"name": "describe", "summary": "Read Canonical Dataset metadata", "argument_convention": "dataset_id", "result_convention": "metadata struct"},
        "read_range": {"name": "read_range", "summary": "Read bounded stable-variable ranges", "argument_convention": "dataset_id, variable_id cell, zero-based start, count", "result_convention": "struct keyed by variable ID with typed values"},
    },
}
_ARGUMENTS = {
    "list": [],
    "describe": [("dataset_id", "Dataset ID")],
    "read_range": [("dataset_id", "Dataset ID"), ("variable_ids", "cell of stable Variable IDs"),
                   ("start", "zero-based integer"), ("count", "nonnegative integer")],
}
for _name, _fields in _ARGUMENTS.items():
    REGISTRATION["operations"][_name]["arguments"] = [
        {"name": name, "kind": kind, "required": True} for name, kind in _fields]
    REGISTRATION["operations"][_name]["result_contract"] = REGISTRATION["operations"][_name]["result_convention"]

for _name, _arguments in {
    "catalog_revision": [], "catalog_snapshot": [],
    "catalog_changed_since": [{"name": "revision", "kind": "nonnegative integer", "required": True}],
}.items():
    REGISTRATION["operations"][_name] = {
        "name": _name, "summary": "Observe the committed Session Dataset catalog",
        "argument_convention": "revision" if _arguments else "no arguments",
        "arguments": _arguments, "result_convention": "catalog result",
        "result_contract": "integer or bounded catalog struct",
    }


def invoke(host, operation, args):
    if operation in {"catalog_revision", "catalog_snapshot", "catalog_changed_since"}:
        if operation == "catalog_changed_since":
            if len(args) != 1 or not isinstance(args[0], (int, float)) or int(args[0]) != args[0] or args[0] < 0:
                raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "catalog_changed_since requires a nonnegative revision")
            return host.normalize(host.call("::GX::datasetCatalogChangedSince", int(args[0]), host.session))
        if args:
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "catalog query takes no arguments")
        if operation == "catalog_revision":
            return int(host.call("::GX::datasetCatalogRevision", host.session))
        return host.normalize(host.call("::GX::datasetCatalogSnapshot", host.session))
    if operation == "list":
        if args:
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "CANONICAL_DATASET_API_v2/list takes no arguments")
        return host.as_list(host.call("::GX::datasetRegistryIds"))
    if operation == "describe":
        if len(args) != 1:
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "describe requires dataset_id")
        handle = host.call("::GX::datasetAccessOpen", host.session, args[0])
        try:
            raw = host.as_dict(host.call("::GX::datasetAccessMetadata", handle))
            variables = [host.as_dict(v) for v in host.as_list(raw.pop("variables", ()))]
            raw["variables"] = variables
            raw["capabilities"] = host.as_list(raw.get("capabilities", ()))
            raw["groups"] = host.as_list(raw.get("groups", ()))
            return raw
        finally:
            host.call("::GX::datasetAccessClose", handle)
    if len(args) != 4 or not isinstance(args[1], list):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "read_range requires dataset_id, variable IDs, start, and count")
    dataset_id, ids, start, count = args
    if not isinstance(start, (int, float)) or not isinstance(count, (int, float)) or int(start) != start or int(count) != count:
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "read_range bounds must be integers")
    handle = host.call("::GX::datasetAccessOpen", host.session, dataset_id)
    try:
        raw = host.as_dict(host.call("::GX::datasetAccessReadRange", handle, ids, int(start), int(count)))
        result = {}
        for variable_id, block in raw.items():
            item = host.as_dict(block)
            dtype = str(item.get("dtype", "float64"))
            values = host.as_list(item.get("values", ()))
            if dtype == "string":
                item["values"] = [str(v) for v in values]
            else:
                item["values"] = NumericArray(values)
            result[variable_id] = item
        return result
    finally:
        host.call("::GX::datasetAccessClose", handle)
