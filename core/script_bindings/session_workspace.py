"""Session-owned workspaces and UTF-8 notes; no script supplies a host path."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError

_COMMANDS = {
    "available_name": ("::GX::sessionWorkspaceAvailableName", ["preferred"]),
    "resource_copy_tree": ("::GX::sessionWorkspaceResourceCopyTreeUtf8", ["workspace_id", "payload_utf8"]),
    "list": ("::GX::sessionWorkspaceList", []),
    "get": ("::GX::sessionWorkspaceGet", ["workspace_id"]),
    "create": ("::GX::sessionWorkspaceCreate", ["provider_id", "name", "payload_utf8"]),
    "update": ("::GX::sessionWorkspaceUpdate", ["workspace_id", "payload_utf8"]),
    "rename": ("::GX::sessionWorkspaceRename", ["workspace_id", "name"]),
    "delete": ("::GX::sessionWorkspaceDelete", ["workspace_id"]),
    "validate": ("::GX::sessionWorkspaceValidate", ["workspace_id"]),
    "note_read": ("::GX::noteDocumentRead", ["workspace_id"]),
    "note_write": ("::GX::noteDocumentWrite", ["workspace_id", "text"]),
    "preview_set": ("::GX::sessionWorkspacePreviewSet", ["workspace_id", "resource"]),
    "export": ("::GX::sessionWorkspaceExport", ["workspace_id"]),
    "import": ("::GX::sessionWorkspaceImport", ["resource", "name"]),
}
REGISTRATION = {
    "api_id": "SESSION_WORKSPACE_API_v1", "api_version": 1,
    "provider_kind": "core", "provider_id": "session_workspace",
    "documentation_ref": "docs/api/SESSION_WORKSPACE_API_v1.md",
    "operations": {name: {"name": name, "summary": "Managed Session workspace: " + name,
                           "arguments": [{"name": argument, "kind": "public value", "required": True} for argument in arguments],
                           "argument_convention": ", ".join(arguments),
                           "result_contract": "workspace/resource receipt or serialized provider UTF-8 payload",
                           "result_convention": "managed receipt"}
                   for name, (_, arguments) in _COMMANDS.items()},
}


def receipt(host, raw):
    result = host.as_dict(raw)
    for key, value in list(result.items()):
        if key in {"revision", "size_bytes", "resource_count"}:
            result[key] = int(value)
        elif key == "valid":
            result[key] = bool(int(value))
        elif key in {"preview", "note", "metadata"}:
            result[key] = receipt(host, value) if str(value) else {}
        elif key == "payload":
            result["payload_utf8"] = str(value)
            del result[key]
    return result


def invoke(host, operation, args):
    if operation not in _COMMANDS or len(args) != len(_COMMANDS[operation][1]):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Invalid Workspace arguments")
    command, _ = _COMMANDS[operation]
    raw = host.call(command, *args)
    if operation == "available_name":
        return str(raw)
    if operation == "resource_copy_tree":
        return bytes(raw).decode("utf-8")
    if operation == "list":
        return [receipt(host, item) for item in host.as_list(raw)]
    if operation == "delete":
        return bool(int(raw))
    return receipt(host, raw)
