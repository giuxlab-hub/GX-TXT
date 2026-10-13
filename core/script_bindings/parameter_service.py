"""Safe Session/Workspace parameter reads through the portable CORE evaluator."""
from gxtxt_script_bridge_server import BridgeError
_COMMANDS = {
    "session_list": ("::GX::parameterSessionList", []),
    "session_evaluate": ("::GX::parameterSessionEvaluate", ["expression"]),
    "workspace_list": ("::GX::parameterWorkspaceRead", ["workspace_id"]),
    "workspace_evaluate": ("::GX::parameterWorkspaceRead", ["workspace_id", "expression"]),
}
REGISTRATION = {
    "api_id": "CORE_PARAMETER_SERVICE_v1", "api_version": 1,
    "provider_kind": "core", "provider_id": "parameter_service",
    "documentation_ref": "docs/api/CORE_PARAMETER_SERVICE_v1.md",
    "operations": {name: {"name": name, "summary": "Read/evaluate parameters: " + name,
        "arguments": [{"name": arg, "kind": "string", "required": True} for arg in args],
        "argument_convention": ", ".join(args), "result_contract": "evaluated numeric value or parameter records",
        "result_convention": "read-only"} for name, (_, args) in _COMMANDS.items()},
}
def invoke(host, operation, args):
    if operation not in _COMMANDS or len(args) != len(_COMMANDS[operation][1]):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Parameter Bridge is read/evaluate only")
    raw = host.call(_COMMANDS[operation][0], *args)
    if operation.endswith("evaluate"):
        return float(raw)
    result = {}
    for name, value in host.as_dict(raw).items():
        record = host.as_dict(value)
        record["value"] = float(record["value"])
        record["dependencies"] = list(dict.fromkeys(map(str, host.as_list(record["dependencies"]))))
        result[name] = record
    return result
