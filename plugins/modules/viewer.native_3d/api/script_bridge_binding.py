"""Read-only Native 3D public identity binding for researcher scripts."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError

REGISTRATION = {
    "api_id": "NATIVE_3D_VIEWER_API_v1", "api_version": 1,
    "provider_kind": "module", "provider_id": "viewer.native_3d",
    "documentation_ref": "plugins/modules/viewer.native_3d/NATIVE_3D_VIEWER_API_v1.md",
    "operations": {
        "source_identity": {
            "name": "source_identity",
            "summary": "Verify current public Viewer scene source identities without exposing paths",
            "arguments": [], "result_contract": "verified scene and layer identity struct",
            "argument_convention": "no arguments", "result_convention": "verified scene and layer identity struct",
        },
    },
}


def invoke(host, operation, args):
    if operation != "source_identity" or args:
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "source_identity takes no arguments")
    host.call("::GX::modulePublicApiActivate", "viewer.native_3d", "NATIVE_3D_VIEWER_API_v1")
    scene = host.as_dict(host.call("::GX::Native3D::verifySourceIdentity"))
    layers = host.as_dict(scene["layers"])
    safe_layers = {}
    for layer_id, value in layers.items():
        layer = host.as_dict(value)
        safe_layers[layer_id] = {key: layer.get(key, "") for key in
                                 ("kind", "source_mode", "dataset_id", "sha256",
                                  "source_dataset_id", "source_dataset_sha256")}
    return {"provider_id": "viewer.native_3d", "viewer_id": "native_3d",
            "source_verified": True, "layers": safe_layers}
