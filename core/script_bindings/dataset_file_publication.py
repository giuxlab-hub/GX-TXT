"""Script-owned output file publication through the public CORE transaction."""
# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
from gxtxt_script_bridge_server import BridgeError

REGISTRATION = {
    "api_id": "DATASET_FILE_PUBLICATION_API_v1", "api_version": 1,
    "provider_kind": "core", "provider_id": "dataset_file_publication",
    "documentation_ref": "docs/api/DATASET_FILE_PUBLICATION_API_v1.md",
    "operations": {
        "authorize_edit": {"name":"authorize_edit","summary":"Authorize one editor for one owned file Dataset revision",
            "arguments":[{"name":"request","kind":"struct","required":True}],
            "argument_convention":"request struct", "result_contract":"scoped revision receipt", "result_convention":"struct"},
        "publish": {"name": "publish", "summary": "Publish a completed script output file as a Canonical Dataset",
                    "arguments": [{"name": "request", "kind": "file publication struct", "required": True}],
                    "result_contract": "Dataset identity and SHA-256 struct",
                    "argument_convention": "request struct", "result_convention": "Dataset identity and SHA-256 struct"},
        "publish_auto": {"name": "publish_auto", "summary": "Publish a completed output file with safe format defaults",
                    "arguments": [{"name": "request", "kind": "file publication struct", "required": True}],
                    "result_contract": "Dataset identity and SHA-256 struct",
                    "argument_convention": "request struct", "result_convention": "Dataset identity and SHA-256 struct"},
    },
}


def invoke(host, operation, args):
    if operation=="authorize_edit":
        if len(args)!=1 or not isinstance(args[0],dict):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments","authorize_edit requires one request")
        context=host.as_dict(host.call("::GX::_datasetPrivateModuleContext",host.module_id))
        return host.as_dict(host.call("::GX::datasetFileEditAuthorize",context["capability"],host.session,args[0]["dataset_id"],args[0]["editor_module"]))
    if operation not in {"publish", "publish_auto"} or len(args) != 1 or not isinstance(args[0], dict):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "publish/publish_auto requires one file publication struct")
    request = dict(args[0])
    output = host.config.get("runtime", "output_dir", fallback="")
    if not output:
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "script output directory is unavailable")
    allowed = Path(output).resolve()
    source = Path(request.get("source_file", "")).resolve()
    if not source.is_file() or not source.is_relative_to(allowed):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "publication source must be a completed file in the script output directory")
    request["source_file"] = str(source)
    command = "::GX::datasetFilePublicationPublishAuto" if operation == "publish_auto" else "::GX::datasetFilePublicationPublish"
    result = host.as_dict(host.call(command, host.session, host.module_id, request))
    result.pop("path", None)
    return host.record_publications(result)
