"""Python/Octave binding of the canonical Dataset organizational namespace API."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError

_FIELDS = {
    "get": [("dataset_id", "Dataset ID")],
    "list": [], "current_get": [],
    "module_default": [],
}
REGISTRATION = {
    "api_id": "DATASET_NAMESPACE_API_v1", "api_version": 1,
    "provider_kind": "core", "provider_id": "dataset_namespace",
    "documentation_ref": "docs/api/DATASET_NAMESPACE_API_v1.md",
    "operations": {name: {
        "name": name, "summary": "Organize canonical Datasets without changing their IDs",
        "arguments": [{"name": key, "kind": kind, "required": True} for key, kind in fields],
        "argument_convention": ", ".join(key for key, _ in fields) or "none",
        "result_convention": "namespace string or namespace cell", "result_contract": "namespace string or namespace cell",
    } for name, fields in _FIELDS.items()},
}

def invoke(host, operation, args):
    if operation not in _FIELDS or len(args) != len(_FIELDS[operation]) or any(not isinstance(arg, str) for arg in args):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"invalid {operation} namespace arguments")
    if operation == "get":
        return host.call("::GX::datasetNamespaceGet", host.session, *args)
    if operation == "list":
        return host.as_list(host.call("::GX::datasetNamespaceList", host.session))
    if operation == "current_get":
        return host.call("::GX::datasetNamespaceCurrentGet", host.session)
    return host.dataset_private_context()["dataset_namespace"]
