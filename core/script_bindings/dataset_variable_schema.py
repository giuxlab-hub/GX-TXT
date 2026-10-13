"""Octave Script Bridge registration owned by Dataset Variable Schema API v3."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError

REGISTRATION = {
    "api_id": "DATASET_VARIABLE_SCHEMA_API_v3", "api_version": 3,
    "provider_kind": "core", "provider_id": "dataset_variable_schema",
    "documentation_ref": "docs/api/DATASET_VARIABLE_SCHEMA_API_v3.md",
    "operations": {
        "list": {"name": "list", "summary": "List stable Dataset variable descriptors", "argument_convention": "dataset_id", "result_convention": "cell of variable structs"},
        "get": {"name": "get", "summary": "Read one stable variable descriptor", "argument_convention": "dataset_id, variable_id", "result_convention": "variable struct"},
        "update": {"name": "update", "summary": "Atomically update mutable v2/v3 scientific Variable schema", "argument_convention": "dataset_id, changes struct keyed by Variable ID", "result_convention": "cell of variable structs"},
    },
}
REGISTRATION["operations"]["list"]["arguments"] = [{"name": "dataset_id", "kind": "Dataset ID", "required": True}]
REGISTRATION["operations"]["get"]["arguments"] = [{"name": "dataset_id", "kind": "Dataset ID", "required": True},
                                                     {"name": "variable_id", "kind": "stable Variable ID", "required": True}]
REGISTRATION["operations"]["update"]["arguments"] = [{"name": "dataset_id", "kind": "Dataset ID", "required": True},
                                                        {"name": "changes", "kind": "Variable ID to fields struct", "required": True}]
for _operation in REGISTRATION["operations"].values():
    _operation["result_contract"] = _operation["result_convention"]


def invoke(host, operation, args):
    if operation == "list" and len(args) == 1:
        return [host.as_dict(v) for v in host.as_list(host.call("::GX::datasetVariableSchemaV3", args[0]))]
    if operation == "get" and len(args) == 2:
        return host.as_dict(host.call("::GX::datasetVariableV3ById", args[0], args[1]))
    if operation == "update" and len(args) == 2 and isinstance(args[1], dict):
        host.call("::GX::_datasetNamespaceRequireModuleWrite", host.session, host.module_id, args[0])
        return [host.as_dict(v) for v in host.as_list(host.call("::GX::datasetVariableSchemaUpdateCombined", args[0], args[1]))]
    raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"{operation} requires a Dataset ID and optional variable ID")
