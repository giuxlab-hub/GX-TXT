"""Python/Octave Script Bridge registration owned by Dataset Metadata API v1."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError

REGISTRATION = {
    "api_id": "DATASET_METADATA_API_v1", "api_version": 1,
    "provider_kind": "core", "provider_id": "dataset_metadata",
    "documentation_ref": "docs/api/DATASET_METADATA_API_v1.md",
    "operations": {
        "read": {"name": "read", "summary": "Read framework-managed Dataset metadata", "argument_convention": "dataset_id", "result_convention": "metadata struct"},
        "update": {"name": "update", "summary": "Update framework-managed Dataset metadata", "argument_convention": "dataset_id, updates struct", "result_convention": "metadata struct"},
        "unset": {"name": "unset", "summary": "Remove selected metadata keys", "argument_convention": "dataset_id, key cell", "result_convention": "metadata struct"},
    },
}
REGISTRATION["operations"]["parse_text"] = {
    "name": "parse_text", "summary": "Parse portable key=value metadata atomically",
    "argument_convention": "text", "result_convention": "validated metadata struct",
    "arguments": [{"name": "text", "kind": "UTF-8 string", "required": True}],
    "result_contract": "validated metadata struct",
}
for _name, _operation in REGISTRATION["operations"].items():
    if _name == "parse_text":
        continue
    _operation["arguments"] = [{"name": "dataset_id", "kind": "Dataset ID", "required": True}]
    if _name != "read":
        _operation["arguments"].append({"name": "updates" if _name == "update" else "keys",
                                        "kind": "metadata struct" if _name == "update" else "cell of strings",
                                        "required": True})
    _operation["result_contract"] = _operation["result_convention"]


for _name, _summary, _extra in (
    ("private_read", "Read all reserved Dataset metadata", None),
    ("private_update", "Update relative keys owned by this runtime module", ("updates", "metadata struct")),
    ("private_unset", "Unset relative keys owned by this runtime module", ("keys", "cell of strings")),
):
    _arguments = [{"name": "dataset_id", "kind": "Dataset ID", "required": True}]
    if _extra:
        _arguments.append({"name": _extra[0], "kind": _extra[1], "required": True})
    REGISTRATION["operations"][_name] = {
        "name": _name, "summary": _summary, "arguments": _arguments,
        "argument_convention": "dataset_id" + (", " + _extra[0] if _extra else ""),
        "result_convention": "private metadata struct", "result_contract": "private metadata struct",
    }
REGISTRATION["operations"]["private_owner"] = {
    "name": "private_owner", "summary": "Describe the trusted runtime module owner (no capability exposed)",
    "arguments": [], "argument_convention": "none", "result_convention": "owner struct",
    "result_contract": "module_id and owner_prefix",
}

def invoke(host, operation, args):
    if operation in ("update", "unset", "private_update", "private_unset") and args:
        host.call("::GX::_datasetNamespaceRequireModuleWrite", host.session, host.module_id, args[0])
    if operation == "private_owner" and not args:
        context = host.dataset_private_context()
        return {key: context[key] for key in ("module_id", "owner_prefix")}
    if operation == "private_read" and len(args) == 1:
        return host.as_dict(host.call("::GX::datasetPrivateMetadataRead", host.session, args[0]))
    if operation == "private_update" and len(args) == 2 and isinstance(args[1], dict):
        return host.as_dict(host.call("::GX::datasetPrivateMetadataUpdate", host.dataset_private_context()["capability"], host.session, args[0], args[1]))
    if operation == "private_unset" and len(args) == 2 and isinstance(args[1], list):
        return host.as_dict(host.call("::GX::datasetPrivateMetadataUnset", host.dataset_private_context()["capability"], host.session, args[0], args[1]))
    if operation == "parse_text" and len(args) == 1 and isinstance(args[0], str):
        return host.as_dict(host.call("::GX::datasetMetadataParseText", args[0]))
    if operation == "read" and len(args) == 1:
        return host.as_dict(host.call("::GX::datasetMetadataRead", host.session, args[0]))
    if operation == "update" and len(args) == 2 and isinstance(args[1], dict):
        return host.as_dict(host.call("::GX::datasetMetadataUpdate", host.session, args[0], args[1]))
    if operation == "unset" and len(args) == 2 and isinstance(args[1], list):
        return host.as_dict(host.call("::GX::datasetMetadataUnset", host.session, args[0], args[1]))
    raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"invalid {operation} arguments for DATASET_METADATA_API_v1")
