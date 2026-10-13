"""Bounded data transport to the existing Session Document resource writer."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError

_OPERATIONS = {"write": ("::GX::managedResourceWriteBase64", ["document_id", "metadata", "bytes_base64"]),
               "read": ("::GX::managedResourceReadBase64", ["resource", "start", "count"]),
               "info": ("::GX::interactiveDocumentResourceInfo", ["resource"])}
REGISTRATION = {
    "api_id": "MANAGED_RESOURCE_API_v1", "api_version": 1,
    "provider_kind": "core", "provider_id": "managed_resource",
    "documentation_ref": "docs/api/MANAGED_RESOURCE_API_v1.md",
    "operations": {name: {"name": name, "summary": "Bounded managed resource " + name,
                           "arguments": [{"name": arg, "kind": "public value", "required": True} for arg in args],
                           "result_contract": "managed resource receipt or bounded base64 data",
                           "argument_convention": ", ".join(args), "result_convention": "bounded public value"}
                   for name, (_, args) in _OPERATIONS.items()},
}


def invoke(host, operation, args):
    if operation not in _OPERATIONS or len(args) != len(_OPERATIONS[operation][1]):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Invalid managed resource arguments")
    if operation == "write" and (not isinstance(args[1], dict) or not isinstance(args[2], str)):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Resource write needs metadata and base64 text")
    raw = host.call(_OPERATIONS[operation][0], *args)
    if operation == "read":
        return raw.decode("ascii") if isinstance(raw, bytes) else str(raw)
    result = host.as_dict(raw)
    result["size_bytes"] = int(result["size_bytes"])
    result["metadata"] = host.as_dict(result["metadata"])
    return result
