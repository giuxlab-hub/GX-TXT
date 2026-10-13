"""Public bounded Dataset Preview binding, shared by both Bridge languages."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError
REGISTRATION = {
    "api_id": "DATASET_PREVIEW_API_v1", "api_version": 1,
    "provider_kind": "core", "provider_id": "dataset_preview",
    "documentation_ref": "docs/api/DATASET_PREVIEW_API_v1.md",
    "operations": {
        "page": {"name": "page", "summary": "Read a bounded backend-neutral preview page",
                 "argument_convention": "dataset_id, options", "result_convention": "page struct",
                 "arguments": [{"name": "dataset_id", "kind": "Dataset ID", "required": True},
                               {"name": "options", "kind": "struct", "required": True}],
                 "result_contract": "page struct with source_rows, columns, rows, bounds"}
    }
}
def invoke(host, operation, args):
    if operation != "page" or len(args) != 2 or not isinstance(args[1], dict):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "page requires Dataset ID and options struct")
    raw = host.as_dict(host.call("::GX::datasetPreviewPage", host.session, *args))
    if not int(raw["available"]):
        return {"available": False, "reason": str(raw["reason"])}
    result = {key: str(value) for key, value in raw.items() if key not in ("rows", "columns", "source_rows")}
    for key in ("row_count", "start", "count", "page_size", "total_variable_count", "selected_variable_count"):
        result[key] = int(raw[key])
    for key in ("available", "has_previous", "has_next"):
        result[key] = bool(int(raw[key]))
    result["columns"] = [host.as_dict(item) for item in host.as_list(raw["columns"])]
    result["rows"] = [host.as_list(item) for item in host.as_list(raw["rows"])]
    result["source_rows"] = [int(value) for value in host.as_list(raw["source_rows"])]
    return result
