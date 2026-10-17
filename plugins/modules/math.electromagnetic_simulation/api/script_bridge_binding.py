"""Provider-owned public native EM scientific binding. GPL-3.0-or-later."""
from gxtxt_script_bridge_server import BridgeError

_SIGNATURES = {
    "api_info": ("apiInfo", []), "default_model": ("defaultModel", [("kind", "string", True)]),
    "validate_model": ("validate", [("model", "struct", True)]),
    "save_model": ("saveModel", [("model", "struct", True), ("document_id", "string", False), ("workspace_name", "string", False)]),
    "list_models": ("listModels", []), "load_model": ("loadModel", [("document_id", "string", True)]),
    "run_async": ("runAsync", [("model", "struct", True)]),
    "job_status": ("jobStatus", [("job_id", "string", True)]), "cancel": ("cancel", [("job_id", "string", True)]),
    "result_describe": ("resultDescribe", [("job_id", "string", True)]),
    "result_preview": ("resultPreview", [("job_id", "string", True), ("offset", "integer", False), ("count", "integer", False)]),
    "publish": ("publish", [("job_id", "string", True), ("dataset_id", "string", True)]),
    "field_describe": ("fieldDescribe", [("dataset_id", "string", True)]),
}
REGISTRATION = {"api_id": "ELECTROMAGNETIC_SIMULATION_API_v1", "api_version": 1,
                "provider_kind": "module", "provider_id": "math.electromagnetic_simulation",
                "documentation_ref": "plugins/modules/math.electromagnetic_simulation/README.md", "operations": {
                    name: {"name": name, "summary": "Public native electromagnetic " + name.replace("_", " "),
                           "arguments": [{"name": n, "kind": k, "required": r} for n, k, r in fields],
                           "result_contract": "Typed existing CORE/domain result; SI science and stable canonical identities"}
                    for name, (_, fields) in _SIGNATURES.items()}}


def invoke(host, operation, args):
    command, fields = _SIGNATURES[operation]
    if not sum(required for _, _, required in fields) <= len(args) <= len(fields):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Invalid electromagnetic operation arity")
    for value, (_, kind, _) in zip(args, fields):
        if kind == "struct" and not isinstance(value, dict) or kind == "string" and not isinstance(value, str) or kind == "integer" and (isinstance(value, bool) or not isinstance(value, (int, float)) or int(value) != value):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Invalid typed electromagnetic operand")
    host.call("::GX::modulePublicApiActivate", "math.electromagnetic_simulation", "ELECTROMAGNETIC_SIMULATION_API_v1")
    result = host.call("::GX::ElectromagneticSimulation::" + command, *args)
    if operation in ("save_model", "publish"):
        host.persist_manifest(operation)
    return host.normalize(result)
