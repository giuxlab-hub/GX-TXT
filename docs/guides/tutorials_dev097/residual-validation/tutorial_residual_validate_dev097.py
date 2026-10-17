# GX-TXT dev097 tutorial revision 1.1.0: public residual metrics and CORE meaning.
# Existing result Dataset/Variable IDs and observed-minus-predicted convention retained.
# GX-TXT Python Script Workspace tutorial:
# validate a fitted terrain Dataset against the original profile family
# using GX-TXT public numerical APIs for the scientific calculations.
#
# SPDX-License-Identifier: GPL-3.0-or-later

from gxtxt import gxtxt_context, gxtxt_api_require, gxtxt_api_call


RESIDUAL_DATASET_ID = "tutorial.terrain_fit_residuals"
PROFILE_STATS_DATASET_ID = "tutorial.terrain_fit_profile_statistics"


def required(metadata, key, prefix="TERRAIN_VALIDATE"):
    value = str(metadata.get(key, "")).strip()
    if not value:
        raise RuntimeError(f"{prefix}: required Dataset Metadata key is missing: {key}")
    return value


def flatten_numeric(value):
    """Transport helper only: convert a Bridge numeric vector to a Python list."""
    if hasattr(value, "reshape") and hasattr(value, "tolist"):
        return [float(v) for v in value.reshape(-1).tolist()]
    if isinstance(value, (list, tuple)):
        out = []
        for item in value:
            if isinstance(item, (list, tuple)):
                out.extend(flatten_numeric(item))
            else:
                out.append(float(item))
        return out
    return [float(value)]


def operand_vector(values):
    return {"kind": "vector", "value": [float(v) for v in values]}


def operand_scalar(value):
    return {"kind": "scalar", "value": float(value)}


def result_values(result):
    if "values" not in result:
        raise RuntimeError("TERRAIN_VALIDATE: NUMERIC_API_v1 result has no values field")
    return flatten_numeric(result["values"])


def result_scalar(result):
    values = result_values(result)
    if len(values) != 1:
        raise RuntimeError(
            f"TERRAIN_VALIDATE: expected one numerical result, got {len(values)}"
        )
    return float(values[0])


def numeric_unary(name, values):
    result = gxtxt_api_call(
        "NUMERIC_API_v1",
        "array_unary",
        [name, operand_vector(values)],
    )
    return result_values(result)


def numeric_unary_scalar(name, value):
    result = gxtxt_api_call(
        "NUMERIC_API_v1",
        "array_unary",
        [name, operand_scalar(value)],
    )
    return result_scalar(result)


def numeric_binary(name, left, right):
    result = gxtxt_api_call(
        "NUMERIC_API_v1",
        "array_binary",
        [name, operand_vector(left), operand_vector(right)],
    )
    return result_values(result)


def numeric_binary_vector_scalar(name, left, right_scalar):
    result = gxtxt_api_call(
        "NUMERIC_API_v1",
        "array_binary",
        [name, operand_vector(left), operand_scalar(right_scalar)],
    )
    return result_values(result)


def numeric_binary_scalar(name, left, right):
    result = gxtxt_api_call(
        "NUMERIC_API_v1",
        "array_binary",
        [name, operand_scalar(left), operand_scalar(right)],
    )
    return result_scalar(result)


def numeric_reduce(name, values):
    result = gxtxt_api_call(
        "NUMERIC_API_v1",
        "array_reduce",
        [name, operand_vector(values), {"axis": 0}],
    )
    return result_scalar(result)


def resolve_variable_id(schema, requested_name):
    requested = str(requested_name).strip()
    for item in schema:
        candidates = []
        for field in ("canonical", "label", "name", "variable_id"):
            value = item.get(field)
            if value is not None:
                candidates.append(str(value).strip())
        if requested in candidates:
            return str(item["variable_id"])
    raise RuntimeError(
        f"TERRAIN_VALIDATE: variable {requested!r} is not present in the canonical schema"
    )


def read_table(dataset_id, variable_ids, chunk_rows=512):
    token = gxtxt_api_call(
        "TABLE_STREAM_API_v3",
        "open_dataset",
        [dataset_id, list(variable_ids), int(chunk_rows),
         {"start": 0, "count": -1, "require_direct": False}],
    )
    columns = {variable_id: [] for variable_id in variable_ids}
    try:
        stream_metadata = gxtxt_api_call("TABLE_STREAM_API_v3", "metadata", [token])
        while True:
            chunk = gxtxt_api_call("TABLE_STREAM_API_v3", "next", [token])
            for variable_id in variable_ids:
                columns[variable_id].extend(
                    flatten_numeric(chunk["values"][variable_id])
                )
            eof = str(chunk.get("eof", "0")).strip().lower() in (
                "1", "true", "yes", "on"
            )
            if eof:
                break
        diagnostics = gxtxt_api_call("TABLE_STREAM_API_v3", "diagnostics", [token])
    finally:
        gxtxt_api_call("TABLE_STREAM_API_v3", "close", [token])

    lengths = {len(values) for values in columns.values()}
    if len(lengths) != 1:
        raise RuntimeError("TERRAIN_VALIDATE: Table Stream returned unaligned columns")
    return columns, stream_metadata, diagnostics


def xy_key(x, y):
    # Alignment key only. Scientific arithmetic is performed through NUMERIC_API_v1.
    return (round(float(x), 12), round(float(y), 12))


def compute_metrics(observed, predicted):
    """Public Numeric owns statistics; CORE interprets those same facts."""
    if len(observed) != len(predicted) or not observed:
        raise RuntimeError("TERRAIN_VALIDATE: observed/predicted vectors are incompatible")
    raw = gxtxt_api_call("NUMERIC_API_v1", "residual_metrics", [observed, predicted])
    # These pointwise arrays are published, not a second statistical estimator.
    residual = numeric_binary("subtract", observed, predicted)
    abs_residual = numeric_unary("abs", residual)
    residual_squared = numeric_unary("square", residual)
    bias_raw = gxtxt_api_call("NUMERIC_API_v1", "array_reduce", [
        "mean", operand_vector(residual), {"axis": 0},
    ])
    return {"count": int(raw["n"]), "residual": residual,
            "abs_residual": abs_residual, "residual_squared": residual_squared,
            "bias": result_scalar(bias_raw), "mae": float(raw["mae"]),
            "rmse": float(raw["rmse"]), "max_abs_error": float(raw["max_abs_error"]),
            "r2": float(raw["r2"]), "raw": raw, "bias_raw": bias_raw}


def publish_table(dataset_id, source_dataset_ids, source_variable_ids,
                  source_text, provenance, notes, variable_definitions,
                  variable_data):
    definition = {
        "dataset_id": dataset_id,
        "contract": "table.generic",
        "storage": "auto",
        "replace_owned": True,
        "producer_version": "1.1.0",
        "structured_metadata": validation_statistical_metadata,
        "source_dataset_ids": list(source_dataset_ids),
        "source_variable_ids": list(source_variable_ids),
        "source": source_text,
        "provenance": provenance,
        "notes": notes,
    }

    writer = gxtxt_api_call(
        "DATASET_PUBLICATION_API_v2", "begin", [definition]
    )
    try:
        gxtxt_api_call(
            "DATASET_PUBLICATION_API_v2",
            "declare_dimension",
            [writer, "row", 0, {"extendible": 1}],
        )

        for variable_id, unit, coordinate_role, semantic_role in variable_definitions:
            schema = {
                "dtype": "float64",
                "rank": 1,
                "dimension_ids": "row",
                "coordinate_role": coordinate_role,
                "semantic_role": semantic_role,
                "unit": unit,
            }
            gxtxt_api_call(
                "DATASET_PUBLICATION_API_v2",
                "declare_variable",
                [writer, variable_id, schema],
            )

        gxtxt_api_call(
            "DATASET_PUBLICATION_API_v2",
            "append",
            [writer, "row", variable_data],
        )

        result = gxtxt_api_call(
            "DATASET_PUBLICATION_API_v2", "finalize", [writer]
        )
        writer = None
        return result
    except Exception:
        if writer is not None:
            gxtxt_api_call("DATASET_PUBLICATION_API_v2", "abort", [writer])
        raise


ctx = gxtxt_context()

gxtxt_api_require([
    "TABLE_STREAM_API_v3@3",
    "DATASET_VARIABLE_SCHEMA_API_v3@3",
    "DATASET_METADATA_API_v1@1",
    "NUMERIC_API_v1@1:math.numeric",
    "STATISTICAL_RESULT_SEMANTICS_API_v1@1",
    "DATASET_PUBLICATION_API_v2@2",
    "SESSION_PERSISTENCE_API_v1@1",
])

inputs = ctx.get("inputs", {})
observed_source = inputs.get("primary")
model_source = inputs.get("model")

if not isinstance(observed_source, dict) or not observed_source.get("dataset_id"):
    raise RuntimeError(
        "TERRAIN_VALIDATE: bind the original terrain family Dataset to Analysis Source 'primary'"
    )
if not isinstance(model_source, dict) or not model_source.get("dataset_id"):
    raise RuntimeError(
        "TERRAIN_VALIDATE: bind the fitted surface Dataset to Analysis Source 'model'"
    )

observed_dataset_id = str(observed_source["dataset_id"])
model_dataset_id = str(model_source["dataset_id"])

observed_metadata = gxtxt_api_call(
    "DATASET_METADATA_API_v1", "read", [observed_dataset_id]
)
model_metadata = gxtxt_api_call(
    "DATASET_METADATA_API_v1", "read", [model_dataset_id]
)

# Metadata drive stable scientific bindings.
observed_schema = gxtxt_api_call(
    "DATASET_VARIABLE_SCHEMA_API_v3", "list", [observed_dataset_id]
)

observed_x_id = resolve_variable_id(
    observed_schema, required(observed_metadata, "binding.x")
)
observed_y_id = resolve_variable_id(
    observed_schema, required(observed_metadata, "binding.y")
)
observed_z_id = resolve_variable_id(
    observed_schema, required(observed_metadata, "binding.z")
)
observed_family_id = resolve_variable_id(
    observed_schema, required(observed_metadata, "binding.family")
)

model_x_id = required(model_metadata, "schema.x_variable_id")
model_y_id = required(model_metadata, "schema.y_variable_id")
model_z_id = required(model_metadata, "schema.z_variable_id")

if required(model_metadata, "processing.kind") != "surface_fit":
    raise RuntimeError("TERRAIN_VALIDATE: model Dataset is not a surface_fit output")

declared_source = required(model_metadata, "processing.source_dataset_id")
if declared_source != observed_dataset_id:
    raise RuntimeError(
        "TERRAIN_VALIDATE: fitted Dataset metadata identifies source "
        f"{declared_source!r}, but Analysis Source primary is {observed_dataset_id!r}"
    )

x_unit = required(model_metadata, "terrain.x_unit")
y_unit = required(model_metadata, "terrain.y_unit")
z_unit = required(model_metadata, "terrain.z_unit")

observed_columns, observed_stream_meta, observed_diag = read_table(
    observed_dataset_id,
    [observed_x_id, observed_y_id, observed_z_id, observed_family_id],
)
model_columns, model_stream_meta, model_diag = read_table(
    model_dataset_id,
    [model_x_id, model_y_id, model_z_id],
)

obs_x = observed_columns[observed_x_id]
obs_y = observed_columns[observed_y_id]
obs_z = observed_columns[observed_z_id]
obs_family = observed_columns[observed_family_id]

model_x = model_columns[model_x_id]
model_y = model_columns[model_y_id]
model_z = model_columns[model_z_id]

model_lookup = {}
for x, y, zfit in zip(model_x, model_y, model_z):
    key = xy_key(x, y)
    if key in model_lookup:
        raise RuntimeError(
            f"TERRAIN_VALIDATE: duplicate model-grid coordinate {key}"
        )
    model_lookup[key] = float(zfit)

matched_fit = []
for x, y in zip(obs_x, obs_y):
    key = xy_key(x, y)
    if key not in model_lookup:
        raise RuntimeError(
            f"TERRAIN_VALIDATE: observed coordinate {key} is absent from fitted grid"
        )
    matched_fit.append(model_lookup[key])

if len(matched_fit) != len(obs_z):
    raise RuntimeError("TERRAIN_VALIDATE: exact XY matching did not preserve row count")

global_metrics = compute_metrics(obs_z, matched_fit)

# Validate the metadata chain: the RMSE and R2 written by the fit stage should
# agree with recomputation from the two persistent Datasets.
metadata_rmse = float(required(model_metadata, "fit.rmse_m"))
metadata_r2 = float(required(model_metadata, "fit.r2"))

if abs(global_metrics["rmse"] - metadata_rmse) > 1e-9:
    raise RuntimeError(
        "TERRAIN_VALIDATE: recomputed RMSE does not match fitted Dataset metadata "
        f"({global_metrics['rmse']:.17g} vs {metadata_rmse:.17g})"
    )
if abs(global_metrics["r2"] - metadata_r2) > 1e-9:
    raise RuntimeError(
        "TERRAIN_VALIDATE: recomputed R2 does not match fitted Dataset metadata "
        f"({global_metrics['r2']:.17g} vs {metadata_r2:.17g})"
    )

profile_members = sorted({int(round(v)) for v in obs_family})
profile_stats = []
profile_comparison_rows = []
profile_bias_rows = []

for profile_id in profile_members:
    indices = [
        i for i, value in enumerate(obs_family)
        if int(round(value)) == profile_id
    ]
    if not indices:
        continue

    observed_group = [obs_z[i] for i in indices]
    fitted_group = [matched_fit[i] for i in indices]
    metrics = compute_metrics(observed_group, fitted_group)
    profile_comparison_rows.append({"id": str(profile_id), "raw": metrics["raw"]})
    profile_bias_rows.append({"id": str(profile_id), "raw": metrics["bias_raw"]})

    profile_y_values = {round(obs_y[i], 12) for i in indices}
    if len(profile_y_values) != 1:
        raise RuntimeError(
            f"TERRAIN_VALIDATE: profile {profile_id} does not map to one Y coordinate"
        )

    profile_stats.append({
        "profile_id": float(profile_id),
        "profile_y_m": float(next(iter(profile_y_values))),
        "point_count": float(metrics["count"]),
        "bias_m": float(metrics["bias"]),
        "mae_m": float(metrics["mae"]),
        "rmse_m": float(metrics["rmse"]),
        "max_abs_error_m": float(metrics["max_abs_error"]),
    })

# Preserve descriptive comparison meaning: the centered comparison score does
# not establish independent validation or an inferential goodness-of-fit test.
S = "STATISTICAL_RESULT_SEMANTICS_API_v1"
comparison_context = {"y_unit": z_unit, "sample_role": "training"}
provenance = {"observed_dataset_id": observed_dataset_id,
              "model_dataset_id": model_dataset_id,
              "residual_convention": "observed_minus_predicted", "matching": "exact_xy"}
meaning = gxtxt_api_call(S, "from_numeric", [
    "math.numeric.comparison", "residual_metrics", global_metrics["raw"], comparison_context,
])
bias_meaning = gxtxt_api_call(S, "from_numeric", [
    "math.numeric.summary", "array_reduce.mean", global_metrics["bias_raw"], {"y_unit": z_unit},
])
profile_meaning = gxtxt_api_call(S, "from_numeric_table", [
    "math.numeric.comparison", "residual_metrics", profile_comparison_rows,
    comparison_context, provenance,
])
profile_bias_meaning = gxtxt_api_call(S, "from_numeric_table", [
    "math.numeric.summary", "array_reduce.mean", profile_bias_rows,
    {"y_unit": z_unit}, provenance,
])
validation_statistical_metadata = gxtxt_api_call(S, "publication_metadata", [{
    "global_comparison": meaning, "global_residual_mean": bias_meaning,
    "profile_comparison": profile_meaning, "profile_residual_mean": profile_bias_meaning,
}])
print(gxtxt_api_call(S, "report", [meaning]))

residual_variable_definitions = (
    ("v_x_m", x_unit, "coordinate", "independent"),
    ("v_y_m", y_unit, "coordinate", "independent"),
    ("v_profile_id", "", "data", "independent"),
    ("v_z_observed_m", z_unit, "data", "derived"),
    ("v_z_fit_m", z_unit, "data", "derived"),
    ("v_residual_m", z_unit, "data", "derived"),
    ("v_abs_residual_m", z_unit, "data", "derived"),
    ("v_residual_squared_m2", f"{z_unit}^2", "data", "derived"),
)

residual_variable_data = {
    "v_x_m": obs_x,
    "v_y_m": obs_y,
    "v_profile_id": [float(round(v)) for v in obs_family],
    "v_z_observed_m": obs_z,
    "v_z_fit_m": matched_fit,
    "v_residual_m": global_metrics["residual"],
    "v_abs_residual_m": global_metrics["abs_residual"],
    "v_residual_squared_m2": global_metrics["residual_squared"],
}

residual_published = publish_table(
    RESIDUAL_DATASET_ID,
    [observed_dataset_id, model_dataset_id],
    [
        observed_x_id, observed_y_id, observed_z_id, observed_family_id,
        model_x_id, model_y_id, model_z_id,
    ],
    "Python Script Workspace terrain fit validation",
    (
        "Exact XY comparison between the original terrain profile family and "
        "the persistent fitted surface. Scientific arithmetic performed through "
        "NUMERIC_API_v1."
    ),
    (
        "Per-observation fitted value and residual Dataset for diagnostic plotting "
        "and downstream validation."
    ),
    residual_variable_definitions,
    residual_variable_data,
)

stats_variable_definitions = (
    ("v_profile_id", "", "data", "independent"),
    ("v_profile_y_m", y_unit, "coordinate", "independent"),
    ("v_point_count", "", "data", "derived"),
    ("v_bias_m", z_unit, "data", "derived"),
    ("v_mae_m", z_unit, "data", "derived"),
    ("v_rmse_m", z_unit, "data", "derived"),
    ("v_max_abs_error_m", z_unit, "data", "derived"),
)

stats_variable_data = {
    "v_profile_id": [item["profile_id"] for item in profile_stats],
    "v_profile_y_m": [item["profile_y_m"] for item in profile_stats],
    "v_point_count": [item["point_count"] for item in profile_stats],
    "v_bias_m": [item["bias_m"] for item in profile_stats],
    "v_mae_m": [item["mae_m"] for item in profile_stats],
    "v_rmse_m": [item["rmse_m"] for item in profile_stats],
    "v_max_abs_error_m": [item["max_abs_error_m"] for item in profile_stats],
}

stats_published = publish_table(
    PROFILE_STATS_DATASET_ID,
    [RESIDUAL_DATASET_ID, observed_dataset_id, model_dataset_id],
    ["v_profile_id", "v_y_m", "v_residual_m"],
    "Python Script Workspace terrain profile validation summary",
    (
        "Per-profile residual statistics derived through NUMERIC_API_v1 from "
        "tutorial.terrain_fit_residuals."
    ),
    "One validation-summary row per terrain profile family member.",
    stats_variable_definitions,
    stats_variable_data,
)

global_metadata = {
    "validation.kind": "fit_residual_analysis",
    "validation.observed_dataset_id": observed_dataset_id,
    "validation.model_dataset_id": model_dataset_id,
    "validation.profile_statistics_dataset_id": PROFILE_STATS_DATASET_ID,
    "validation.numeric_backend": "NUMERIC_API_v1",
    "validation.data_access": "TABLE_STREAM_API_v3",
    "validation.matching": "exact_xy",
    "validation.observation_count": str(global_metrics["count"]),
    "validation.profile_count": str(len(profile_members)),
    "validation.global_bias_m": f"{global_metrics['bias']:.17g}",
    "validation.global_mae_m": f"{global_metrics['mae']:.17g}",
    "validation.global_rmse_m": f"{global_metrics['rmse']:.17g}",
    "validation.global_max_abs_error_m": f"{global_metrics['max_abs_error']:.17g}",
    "validation.global_r2": f"{global_metrics['r2']:.17g}",
    "validation.metadata_rmse_m": f"{metadata_rmse:.17g}",
    "validation.metadata_r2": f"{metadata_r2:.17g}",
    "schema.x_variable_id": "v_x_m",
    "schema.y_variable_id": "v_y_m",
    "schema.family_variable_id": "v_profile_id",
    "schema.observed_variable_id": "v_z_observed_m",
    "schema.fitted_variable_id": "v_z_fit_m",
    "schema.residual_variable_id": "v_residual_m",
}

stats_metadata = {
    "validation.kind": "fit_residual_profile_statistics",
    "validation.residual_dataset_id": RESIDUAL_DATASET_ID,
    "validation.observed_dataset_id": observed_dataset_id,
    "validation.model_dataset_id": model_dataset_id,
    "validation.numeric_backend": "NUMERIC_API_v1",
    "validation.profile_count": str(len(profile_members)),
    "schema.profile_id_variable_id": "v_profile_id",
    "schema.profile_y_variable_id": "v_profile_y_m",
    "schema.rmse_variable_id": "v_rmse_m",
}

gxtxt_api_call(
    "DATASET_METADATA_API_v1",
    "update",
    [RESIDUAL_DATASET_ID, global_metadata],
)
gxtxt_api_call(
    "DATASET_METADATA_API_v1",
    "update",
    [PROFILE_STATS_DATASET_ID, stats_metadata],
)

gxtxt_api_call("SESSION_PERSISTENCE_API_v1", "commit", [])

print(
    "PASS TERRAIN_NUMERIC_VALIDATION "
    f"observed={observed_dataset_id} model={model_dataset_id} "
    f"rows={global_metrics['count']} profiles={len(profile_members)} "
    f"bias={global_metrics['bias']:.9g} "
    f"mae={global_metrics['mae']:.9g} "
    f"rmse={global_metrics['rmse']:.9g} "
    f"max_abs={global_metrics['max_abs_error']:.9g} "
    f"r2={global_metrics['r2']:.12g} "
    f"residual_dataset={residual_published['dataset_id']} "
    f"profile_stats_dataset={stats_published['dataset_id']}"
)
