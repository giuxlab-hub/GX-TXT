# GX-TXT Python Script Workspace test: fitted terrain -> static mesh -> persistent Native 3D scene.
# SPDX-License-Identifier: GPL-3.0-or-later

from gxtxt import gxtxt_context, gxtxt_api_require, gxtxt_api_call


def required(metadata, key):
    value = str(metadata.get(key, "")).strip()
    if not value:
        raise RuntimeError(f"TERRAIN_MESH: required Dataset Metadata key is missing: {key}")
    return value


ctx = gxtxt_context()
gxtxt_api_require([
    "CANONICAL_DATASET_API_v2@2",
    "DATASET_VARIABLE_SCHEMA_API_v3@3",
    "DATASET_METADATA_API_v1@1",
    "PLOT_DATASET_API_v3@3:plot.dataset+plotspec",
    "INTERACTIVE_DOCUMENT_API_v1@1",
    "NATIVE_3D_VIEWER_API_v1@1",
    "SESSION_PERSISTENCE_API_v1@1",
])

primary = ctx.get("inputs", {}).get("primary")
if not isinstance(primary, dict) or not primary.get("dataset_id"):
    raise RuntimeError("TERRAIN_MESH: select tutorial.terrain_surface_fit as Analysis Source 'primary'")

dataset_id = str(primary["dataset_id"])
metadata = gxtxt_api_call("DATASET_METADATA_API_v1", "read", [dataset_id])

if required(metadata, "processing.kind") != "surface_fit":
    raise RuntimeError("TERRAIN_MESH: primary Dataset is not the fitted terrain output")

x_id = required(metadata, "schema.x_variable_id")
y_id = required(metadata, "schema.y_variable_id")
z_id = required(metadata, "schema.z_variable_id")
x_unit = required(metadata, "terrain.x_unit")
y_unit = required(metadata, "terrain.y_unit")
z_unit = required(metadata, "terrain.z_unit")
plot_type = required(metadata, "presentation.mesh_plot_type")

if plot_type != "mesh":
    raise RuntimeError(
        f"TERRAIN_MESH: metadata presentation.mesh_plot_type must be 'mesh', got {plot_type!r}"
    )

for variable_id in (x_id, y_id, z_id):
    gxtxt_api_call("DATASET_VARIABLE_SCHEMA_API_v3", "get", [dataset_id, variable_id])

spec = {
    "schema": "PLOT_DATASET_PLOTSPEC_v2",
    "graph_type": "cartesian_3d",
    "graph_id": "plot.dataset.xyz",
    "dataset_id": dataset_id,
    "x_variable_id": x_id,
    "y_variable_id": y_id,
    "z_variable_id": z_id,
    "title": "Python fitted terrain mesh",
    "config": {
        "plot_type": plot_type,
        "reduction_mode": "none",
        "x_label": f"X [{x_unit}]",
        "y_label": f"Y [{y_unit}]",
        "z_label": f"Elevation [{z_unit}]",
    },
}

if not gxtxt_api_call("PLOT_DATASET_API_v3", "validate_spec", [spec]):
    raise RuntimeError("TERRAIN_MESH: PlotSpec validation returned false")

mesh_ref = gxtxt_api_call(
    "PLOT_DATASET_API_v3",
    "create_plot",
    [spec, "variant"],
)

gxtxt_api_call("PLOT_DATASET_API_v3", "render", [mesh_ref])
artifacts = gxtxt_api_call("PLOT_DATASET_API_v3", "artifacts", [mesh_ref])

scene = gxtxt_api_call("PLOT_DATASET_API_v3", "build_scene", [mesh_ref])
representation_id = str(scene["representation_id"])

status = gxtxt_api_call(
    "PLOT_DATASET_API_v3",
    "interactive_status",
    [representation_id],
)
if str(status) != "SYNCED":
    raise RuntimeError(
        f"TERRAIN_MESH: new interactive representation is not SYNCED: {status!r}"
    )

representations = gxtxt_api_call(
    "PLOT_DATASET_API_v3",
    "interactive_representations",
    [],
)
if not any(str(item.get("id", "")) == representation_id for item in representations):
    raise RuntimeError("TERRAIN_MESH: representation is missing from Plot Dataset interactive registry")

documents = gxtxt_api_call("INTERACTIVE_DOCUMENT_API_v1", "list", [])
if not any(str(item.get("id", "")) == representation_id for item in documents):
    raise RuntimeError("TERRAIN_MESH: representation is missing from Interactive Document registry")

viewer_identity = gxtxt_api_call("NATIVE_3D_VIEWER_API_v1", "source_identity", [])
layers = viewer_identity.get("layers", {})
if not layers:
    raise RuntimeError("TERRAIN_MESH: Native 3D scene contains no scientific layers")

matching_layers = 0
for layer in layers.values():
    if str(layer.get("source_dataset_id", "")) == dataset_id:
        matching_layers += 1
if matching_layers < 1:
    raise RuntimeError(
        "TERRAIN_MESH: Native 3D scene layers do not retain the fitted Dataset identity"
    )

gxtxt_api_call("SESSION_PERSISTENCE_API_v1", "commit", [])

print(
    "PASS TERRAIN_MESH_SCENE_V3 "
    f"dataset={dataset_id} graph={mesh_ref['graph_id']} "
    f"variant={mesh_ref['variant_id']} representation={representation_id} "
    f"status={status} layers={len(layers)} matching_source_layers={matching_layers} "
    f"artifact={artifacts.get('graph_artifact', '')}"
)
