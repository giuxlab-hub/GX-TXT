# GX-TXT Python Script Workspace test: fitted terrain -> native static 3D surface.
# SPDX-License-Identifier: GPL-3.0-or-later

from gxtxt import gxtxt_context, gxtxt_api_require, gxtxt_api_call


def required(metadata, key):
    value = str(metadata.get(key, "")).strip()
    if not value:
        raise RuntimeError(f"TERRAIN_SURFACE: required Dataset Metadata key is missing: {key}")
    return value


ctx = gxtxt_context()
gxtxt_api_require([
    "CANONICAL_DATASET_API_v2@2",
    "DATASET_VARIABLE_SCHEMA_API_v3@3",
    "DATASET_METADATA_API_v1@1",
    "PLOT_DATASET_API_v3@3:plot.dataset+plotspec",
    "SESSION_PERSISTENCE_API_v1@1",
])

primary = ctx.get("inputs", {}).get("primary")
if not isinstance(primary, dict) or not primary.get("dataset_id"):
    raise RuntimeError("TERRAIN_SURFACE: select tutorial.terrain_surface_fit as Analysis Source 'primary'")

dataset_id = str(primary["dataset_id"])
metadata = gxtxt_api_call("DATASET_METADATA_API_v1", "read", [dataset_id])

if required(metadata, "processing.kind") != "surface_fit":
    raise RuntimeError("TERRAIN_SURFACE: primary Dataset is not the fitted terrain output")

x_id = required(metadata, "schema.x_variable_id")
y_id = required(metadata, "schema.y_variable_id")
z_id = required(metadata, "schema.z_variable_id")
x_unit = required(metadata, "terrain.x_unit")
y_unit = required(metadata, "terrain.y_unit")
z_unit = required(metadata, "terrain.z_unit")
plot_type = required(metadata, "presentation.surface_plot_type")

if plot_type != "surface":
    raise RuntimeError(
        f"TERRAIN_SURFACE: metadata presentation.surface_plot_type must be 'surface', got {plot_type!r}"
    )

# Verify that the metadata-carried stable IDs still exist in the canonical schema.
for variable_id in (x_id, y_id, z_id):
    gxtxt_api_call("DATASET_VARIABLE_SCHEMA_API_v3", "get", [dataset_id, variable_id])

description = gxtxt_api_call("CANONICAL_DATASET_API_v2", "describe", [dataset_id])
if int(description["row_count"]) < 4:
    raise RuntimeError("TERRAIN_SURFACE: fitted Dataset is empty or too small")

spec = {
    "schema": "PLOT_DATASET_PLOTSPEC_v2",
    "graph_type": "cartesian_3d",
    "graph_id": "plot.dataset.xyz",
    "dataset_id": dataset_id,
    "x_variable_id": x_id,
    "y_variable_id": y_id,
    "z_variable_id": z_id,
    "title": "Python fitted synthetic terrain",
    "config": {
        "plot_type": plot_type,
        "reduction_mode": "none",
        "x_label": f"X [{x_unit}]",
        "y_label": f"Y [{y_unit}]",
        "z_label": f"Elevation [{z_unit}]",
    },
}

if not gxtxt_api_call("PLOT_DATASET_API_v3", "validate_spec", [spec]):
    raise RuntimeError("TERRAIN_SURFACE: PlotSpec validation returned false")

plot_ref = gxtxt_api_call(
    "PLOT_DATASET_API_v3",
    "create_plot",
    [spec, "variant"],
)

render_result = gxtxt_api_call("PLOT_DATASET_API_v3", "render", [plot_ref])
artifacts = gxtxt_api_call("PLOT_DATASET_API_v3", "artifacts", [plot_ref])
gxtxt_api_call("SESSION_PERSISTENCE_API_v1", "commit", [])

print(
    "PASS TERRAIN_SURFACE_V3 "
    f"dataset={dataset_id} module={plot_ref['module_id']} "
    f"graph={plot_ref['graph_id']} variant={plot_ref['variant_id']} "
    f"artifact={artifacts.get('graph_artifact', '')}"
)
