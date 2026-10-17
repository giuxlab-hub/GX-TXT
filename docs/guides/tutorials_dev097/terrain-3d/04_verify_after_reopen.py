# GX-TXT Python Script Workspace test: verify fitted terrain state after Session reopen.
# SPDX-License-Identifier: GPL-3.0-or-later

from gxtxt import gxtxt_context, gxtxt_api_require, gxtxt_api_call


ctx = gxtxt_context()
gxtxt_api_require([
    "CANONICAL_DATASET_API_v2@2",
    "DATASET_METADATA_API_v1@1",
    "PLOT_MODULE_API_v1@1",
    "PLOT_DATASET_API_v3@3:plot.dataset+plotspec",
    "INTERACTIVE_DOCUMENT_API_v1@1",
])

primary = ctx.get("inputs", {}).get("primary")
if not isinstance(primary, dict) or not primary.get("dataset_id"):
    raise RuntimeError("TERRAIN_VERIFY: select tutorial.terrain_surface_fit as Analysis Source 'primary'")

dataset_id = str(primary["dataset_id"])
metadata = gxtxt_api_call("DATASET_METADATA_API_v1", "read", [dataset_id])

required_keys = (
    "processing.kind",
    "processing.source_dataset_id",
    "fit.model",
    "fit.degree",
    "fit.rmse_m",
    "fit.r2",
    "schema.x_variable_id",
    "schema.y_variable_id",
    "schema.z_variable_id",
    "presentation.surface_plot_type",
    "presentation.mesh_plot_type",
)
missing = [key for key in required_keys if not str(metadata.get(key, "")).strip()]
if missing:
    raise RuntimeError(
        "TERRAIN_VERIFY: derived Dataset Metadata did not survive reopen: "
        + ", ".join(missing)
    )

dataset_description = gxtxt_api_call("CANONICAL_DATASET_API_v2", "describe", [dataset_id])
variant_ids = gxtxt_api_call(
    "PLOT_MODULE_API_v1",
    "variant_ids",
    ["plot.dataset", "plot.dataset.xyz"],
)

plot_types = {}
for variant_id in variant_ids:
    ref = gxtxt_api_call(
        "PLOT_DATASET_API_v3",
        "open_plot",
        ["plot.dataset.xyz", str(variant_id)],
    )
    state = gxtxt_api_call("PLOT_DATASET_API_v3", "read_plot", [ref])
    config = state.get("config", {}) if isinstance(state, dict) else {}
    plot_types[str(variant_id)] = str(config.get("plot_type", ""))

representations = gxtxt_api_call(
    "PLOT_DATASET_API_v3",
    "interactive_representations",
    [],
)
documents = gxtxt_api_call("INTERACTIVE_DOCUMENT_API_v1", "list", [])

if not variant_ids:
    raise RuntimeError("TERRAIN_VERIFY: no persistent plot.dataset.xyz Variants survived reopen")
if not representations:
    raise RuntimeError("TERRAIN_VERIFY: no persistent Plot Dataset interactive representations survived reopen")
if not documents:
    raise RuntimeError("TERRAIN_VERIFY: no Interactive Documents survived reopen")

print(
    "PASS TERRAIN_PERSISTENCE_VERIFY "
    f"dataset={dataset_id} rows={int(dataset_description['row_count'])} "
    f"metadata_keys={len(metadata)} xyz_variants={len(variant_ids)} "
    f"plot_types={plot_types} interactive_representations={len(representations)} "
    f"interactive_documents={len(documents)}"
)
