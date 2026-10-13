"""Generic workspace note source; the graphical GX-Markup editor is host-only."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError

REGISTRATION = {
    "api_id": "NOTE_DOCUMENT_API_v1", "api_version": 1,
    "provider_kind": "core", "provider_id": "note_document",
    "documentation_ref": "docs/api/NOTE_DOCUMENT_API_v1.md",
    "operations": {name: {"name": name, "summary": "Managed UTF-8 note " + name,
                           "arguments": [{"name": arg, "kind": "string", "required": True} for arg in args],
                           "result_contract": "note source receipt", "result_convention": "workspace ID, text, format",
                           "argument_convention": ", ".join(args)}
                   for name, args in {"read": ["workspace_id"], "write": ["workspace_id", "text"]}.items()},
}


def invoke(host, operation, args):
    if operation not in {"read", "write"} or len(args) != (1 if operation == "read" else 2):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Invalid note arguments")
    return host.as_dict(host.call("::GX::noteDocumentRead" if operation == "read" else "::GX::noteDocumentWrite", *args))
