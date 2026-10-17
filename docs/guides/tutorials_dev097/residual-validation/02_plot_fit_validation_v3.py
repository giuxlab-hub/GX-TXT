# GX-TXT Python Script Workspace tutorial:
# plot the terrain fit validation Datasets through PLOT_DATASET_API_v3.
#
# SPDX-License-Identifier: GPL-3.0-or-later

from gxtxt import gxtxt_context, gxtxt_api_require, gxtxt_api_call


def required(metadata, key, prefix="TERRAIN_VALIDATE_PLOT"):
    value = str(metadata.get(key, "")).strip()
    if not value:
        raise RuntimeError(f"{prefix}: required Dataset Metadata key is missing: {key}")
    return value


ctx = gxtxt_context()

gxtxt_api_require([
    "DATASET_VARIABLE_SCHEMA_API_v3@3",
    "DATASET_METADATA_API_v1@1",
    "PLOT_DATASET_API_v3@3:plot.dataset+plotspec",
    "SESSION_PERSISTENCE_API_v1@1",
])

inputs = ctx.get("inputs", {})
residual_source = inputs.get("primary")
summary_source = inputs.get("summary")

if not isinstance(residual_source, dict) or not residual_source.get("dataset_id"):
    raise RuntimeError(
        "TERRAIN_VALIDATE_PLOT: bind tutorial.terrain_fit_residuals to Analysis Source 'primary'"
    )
if not isinstance(summary_source, dict) or not summary_source.get("dataset_id"):
    raise RuntimeError(
        "TERRAIN_VALIDATE_PLOT: bind tutorial.terrain_fit_profile_statistics to Analysis Source 'summary'"
    )

residual_dataset_id = str(residual_source["dataset_id"])
summary_dataset_id = str(summary_source["dataset_id"])

residual_metadata = gxtxt_api_call(
    "DATASET_METADATA_API_v1", "read", [residual_dataset_id]
)
summary_metadata = gxtxt_api_call(
    "DATASET_METADATA_API_v1", "read", [summary_dataset_id]
)

if required(residual_metadata, "validation.kind") != "fit_residual_analysis":
    raise RuntimeError("TERRAIN_VALIDATE_PLOT: primary Dataset is not a residual analysis output")
if required(summary_metadata, "validation.kind") != "fit_residual_profile_statistics":
    raise RuntimeError("TERRAIN_VALIDATE_PLOT: summary Dataset is not a profile-statistics output")

x_id = required(residual_metadata, "schema.x_variable_id")
family_id = required(residual_metadata, "schema.family_variable_id")
observed_id = required(residual_metadata, "schema.observed_variable_id")
fitted_id = required(residual_metadata, "schema.fitted_variable_id")
residual_id = required(residual_metadata, "schema.residual_variable_id")

profile_y_id = required(summary_metadata, "schema.profile_y_variable_id")
rmse_id = required(summary_metadata, "schema.rmse_variable_id")

# Fail early if metadata-carried IDs no longer exist.
for variable_id in (x_id, family_id, observed_id, fitted_id, residual_id):
    gxtxt_api_call(
        "DATASET_VARIABLE_SCHEMA_API_v3", "get",
        [residual_dataset_id, variable_id],
    )
for variable_id in (profile_y_id, rmse_id):
    gxtxt_api_call(
        "DATASET_VARIABLE_SCHEMA_API_v3", "get",
        [summary_dataset_id, variable_id],
    )

# -------------------------------------------------------------------------
# Plot 1: measured/fitted family overlay + residual family panel.
# -------------------------------------------------------------------------
spec = gxtxt_api_call(
    "PLOT_DATASET_API_v3",
    "new_spec",
    ["plot.dataset.xy", "Terrain fit validation"],
)

observed_series = {
    "id": "observed",
    "dataset_id": residual_dataset_id,
    "x_variable_id": x_id,
    "y_variable_id": observed_id,
    "family_variable_id": family_id,
    "family_label_prefix": "Observed profile ",
    "axis": "left",
    "kind": "scatter",
    "label": "Observed",
}

fitted_series = {
    "id": "fitted",
    "dataset_id": residual_dataset_id,
    "x_variable_id": x_id,
    "y_variable_id": fitted_id,
    "family_variable_id": family_id,
    "family_label_prefix": "Fitted profile ",
    "axis": "left",
    "kind": "line",
    "label": "Fitted",
}

residual_series = {
    "id": "residual",
    "dataset_id": residual_dataset_id,
    "x_variable_id": x_id,
    "y_variable_id": residual_id,
    "family_variable_id": family_id,
    "family_label_prefix": "Residual profile ",
    "axis": "left",
    "kind": "line_marker",
    "label": "Residual",
}

panel_fit = {
    "id": "main",
    "title": "Observed and fitted profiles",
    "axes": {
        "x": {"label": "X [m]"},
        "y_left": {"label": "Elevation [m]"},
    },
    "annotations": [],
    "series": [observed_series, fitted_series],
}

panel_residual = {
    "id": "residual",
    "title": "Fit residuals",
    "axes": {
        "x": {"label": "X [m]"},
        "y_left": {"label": "Residual [m]"},
    },
    "annotations": [
        {
            "type": "reference_line",
            "axis": "left",
            "value": 0.0,
            "label": "Zero residual",
            "line_style": "dashed",
        }
    ],
    "series": [residual_series],
}

spec["multi_panel"] = 1
spec["panels"] = [panel_fit, panel_residual]

if not gxtxt_api_call("PLOT_DATASET_API_v3", "validate_spec", [spec]):
    raise RuntimeError("TERRAIN_VALIDATE_PLOT: diagnostic PlotSpec validation returned false")

diagnostic_ref = gxtxt_api_call(
    "PLOT_DATASET_API_v3",
    "create_plot",
    [spec, "variant"],
)
gxtxt_api_call("PLOT_DATASET_API_v3", "render", [diagnostic_ref])
diagnostic_artifacts = gxtxt_api_call(
    "PLOT_DATASET_API_v3", "artifacts", [diagnostic_ref]
)

# -------------------------------------------------------------------------
# Plot 2: RMSE by profile Y position.
# -------------------------------------------------------------------------
summary_spec = gxtxt_api_call(
    "PLOT_DATASET_API_v3",
    "new_spec",
    ["plot.dataset.xy", "Terrain fit error by profile"],
)

rmse_series = {
    "id": "profile_rmse",
    "dataset_id": summary_dataset_id,
    "x_variable_id": profile_y_id,
    "y_variable_id": rmse_id,
    "axis": "left",
    "kind": "line_marker",
    "label": "RMSE",
}

summary_panel = {
    "id": "main",
    "title": "RMSE by terrain profile",
    "axes": {
        "x": {"label": "Profile Y position [m]"},
        "y_left": {"label": "RMSE [m]"},
    },
    "annotations": [],
    "series": [rmse_series],
}

summary_spec["panels"] = [summary_panel]

if not gxtxt_api_call("PLOT_DATASET_API_v3", "validate_spec", [summary_spec]):
    raise RuntimeError("TERRAIN_VALIDATE_PLOT: RMSE PlotSpec validation returned false")

summary_ref = gxtxt_api_call(
    "PLOT_DATASET_API_v3",
    "create_plot",
    [summary_spec, "variant"],
)
gxtxt_api_call("PLOT_DATASET_API_v3", "render", [summary_ref])
summary_artifacts = gxtxt_api_call(
    "PLOT_DATASET_API_v3", "artifacts", [summary_ref]
)

gxtxt_api_call("SESSION_PERSISTENCE_API_v1", "commit", [])

print(
    "PASS TERRAIN_VALIDATION_PLOTS "
    f"diagnostic_variant={diagnostic_ref['variant_id']} "
    f"diagnostic_artifact={diagnostic_artifacts.get('graph_artifact', '')} "
    f"summary_variant={summary_ref['variant_id']} "
    f"summary_artifact={summary_artifacts.get('graph_artifact', '')}"
)
