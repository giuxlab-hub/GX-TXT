# GX-TXT dev097 tutorial revision 1.1.0: public Numeric + CORE statistical semantics.
# Original scientific basis, source order, Dataset/Variable IDs preserved.
# GX-TXT Python Script Workspace test: family terrain profiles -> fitted surface Dataset.
# SPDX-License-Identifier: GPL-3.0-or-later

from gxtxt import gxtxt_context, gxtxt_api_require, gxtxt_api_call
import numpy as np


REQUIRED_METADATA = (
    "binding.x",
    "binding.y",
    "binding.z",
    "binding.family",
    "family.variable",
    "terrain.x_unit",
    "terrain.y_unit",
    "terrain.z_unit",
    "terrain.profile_count",
    "fit.model",
    "fit.degree",
    "fit.grid_nx",
    "fit.grid_ny",
    "fit.output_dataset_id",
    "presentation.surface_plot_type",
    "presentation.mesh_plot_type",
)


def require_metadata(metadata, key):
    value = str(metadata.get(key, "")).strip()
    if not value:
        raise RuntimeError(f"TERRAIN_FIT: required Dataset Metadata key is missing: {key}")
    return value


def as_positive_int(metadata, key, minimum=1, maximum=10000):
    text = require_metadata(metadata, key)
    try:
        value = int(text)
    except ValueError as exc:
        raise RuntimeError(f"TERRAIN_FIT: metadata {key} must be an integer, got {text!r}") from exc
    if value < minimum or value > maximum:
        raise RuntimeError(f"TERRAIN_FIT: metadata {key} must be in [{minimum}, {maximum}], got {value}")
    return value


def resolve_variable_id(schema, requested_name):
    requested = requested_name.strip()
    for item in schema:
        candidates = []
        for field in ("canonical", "label", "name", "variable_id"):
            value = item.get(field)
            if value is not None:
                candidates.append(str(value).strip())
        if requested in candidates:
            return str(item["variable_id"])
    raise RuntimeError(
        f"TERRAIN_FIT: metadata requested variable {requested!r}, "
        "but it is not present in the canonical Variable Schema"
    )


def total_degree_powers(degree):
    powers = []
    for total in range(degree + 1):
        for px in range(total, -1, -1):
            powers.append((px, total - px))
    return powers


def design_matrix(xn, yn, powers):
    return np.column_stack([(xn ** px) * (yn ** py) for px, py in powers])


ctx = gxtxt_context()

gxtxt_api_require([
    "NUMERIC_API_v1@1",
    "STATISTICAL_RESULT_SEMANTICS_API_v1@1",
    "CANONICAL_DATASET_API_v2@2",
    "DATASET_VARIABLE_SCHEMA_API_v3@3",
    "DATASET_METADATA_API_v1@1",
    "DATASET_PUBLICATION_API_v2@2",
    "SESSION_PERSISTENCE_API_v1@1",
])

inputs = ctx.get("inputs", {})
primary = inputs.get("primary")
if not isinstance(primary, dict) or not primary.get("dataset_id"):
    raise RuntimeError("TERRAIN_FIT: select the raw terrain family Dataset as Analysis Source 'primary'")

source_dataset_id = str(primary["dataset_id"])
metadata = gxtxt_api_call("DATASET_METADATA_API_v1", "read", [source_dataset_id])

for key in REQUIRED_METADATA:
    require_metadata(metadata, key)

if require_metadata(metadata, "fit.model") != "polynomial_total_degree":
    raise RuntimeError("TERRAIN_FIT: this test requires fit.model=polynomial_total_degree")

degree = as_positive_int(metadata, "fit.degree", 1, 8)
grid_nx = as_positive_int(metadata, "fit.grid_nx", 2, 2000)
grid_ny = as_positive_int(metadata, "fit.grid_ny", 2, 2000)
expected_family_count = as_positive_int(metadata, "terrain.profile_count", 1, 10000)
output_dataset_id = require_metadata(metadata, "fit.output_dataset_id")

schema = gxtxt_api_call("DATASET_VARIABLE_SCHEMA_API_v3", "list", [source_dataset_id])

x_id = resolve_variable_id(schema, require_metadata(metadata, "binding.x"))
y_id = resolve_variable_id(schema, require_metadata(metadata, "binding.y"))
z_id = resolve_variable_id(schema, require_metadata(metadata, "binding.z"))
family_id = resolve_variable_id(schema, require_metadata(metadata, "binding.family"))

description = gxtxt_api_call("CANONICAL_DATASET_API_v2", "describe", [source_dataset_id])
row_count = int(description["row_count"])
if row_count < 16:
    raise RuntimeError("TERRAIN_FIT: source Dataset has too few rows")

block = gxtxt_api_call(
    "CANONICAL_DATASET_API_v2",
    "read_range",
    [source_dataset_id, [x_id, y_id, z_id, family_id], 0, row_count],
)

x = np.asarray(block[x_id]["values"], dtype=float).reshape(-1)
y = np.asarray(block[y_id]["values"], dtype=float).reshape(-1)
z = np.asarray(block[z_id]["values"], dtype=float).reshape(-1)
family = np.asarray(block[family_id]["values"], dtype=float).reshape(-1)

if not (len(x) == len(y) == len(z) == len(family) == row_count):
    raise RuntimeError("TERRAIN_FIT: source variables are not row-aligned")

finite = np.isfinite(x) & np.isfinite(y) & np.isfinite(z) & np.isfinite(family)
if not np.all(finite):
    raise RuntimeError("TERRAIN_FIT: source Dataset contains non-finite X/Y/Z/family values")

family_rounded = np.rint(family)
if not np.allclose(family, family_rounded, rtol=0.0, atol=1e-9):
    raise RuntimeError("TERRAIN_FIT: family variable must contain integer-valued profile IDs")
family_rounded = family_rounded.astype(int)

family_members = np.unique(family_rounded)
if family_members.size != expected_family_count:
    raise RuntimeError(
        f"TERRAIN_FIT: metadata declares {expected_family_count} families, "
        f"but Dataset contains {family_members.size}"
    )

# Validate the family semantics: each profile ID must correspond to one Y coordinate.
for member in family_members:
    member_y = np.unique(np.round(y[family_rounded == member], 12))
    if member_y.size != 1:
        raise RuntimeError(
            f"TERRAIN_FIT: profile_id={member} spans {member_y.size} Y coordinates; "
            "expected exactly one"
        )

x_min, x_max = float(np.min(x)), float(np.max(x))
y_min, y_max = float(np.min(y)), float(np.max(y))
x_center = 0.5 * (x_min + x_max)
y_center = 0.5 * (y_min + y_max)
x_scale = 0.5 * (x_max - x_min)
y_scale = 0.5 * (y_max - y_min)
if x_scale <= 0.0 or y_scale <= 0.0:
    raise RuntimeError("TERRAIN_FIT: X and Y must both span nonzero ranges")

xn = (x - x_center) / x_scale
yn = (y - y_center) / y_scale

powers = total_degree_powers(degree)
A = design_matrix(xn, yn, powers)
fit = gxtxt_api_call("NUMERIC_API_v1", "least_squares", [
    A, z, [], {"has_intercept": True, "rank_policy": "error"},
])
coefficients = np.asarray(fit["coefficients"], dtype=float).reshape(-1)
rank = int(fit["rank"])
if rank != len(powers):
    raise RuntimeError(f"TERRAIN_FIT: polynomial design rank {rank} is below {len(powers)}")
# response_rmse uses N physical observations; residual_rmse uses residual DOF.
# Use Numeric's existing facts without recalculating or changing their meaning.
rmse = float(fit["response_rmse"])
r2 = float(fit["r_squared"])
meaning = gxtxt_api_call("STATISTICAL_RESULT_SEMANTICS_API_v1", "from_numeric", [
    "math.numeric.linear_design", "least_squares", fit,
    {"x_unit": "1", "y_unit": require_metadata(metadata, "terrain.z_unit"),
     "sample_role": "training", "constraints": "none",
     "noise_model": "independent_gaussian_estimated_variance"},
])
statistical_metadata = gxtxt_api_call(
    "STATISTICAL_RESULT_SEMANTICS_API_v1", "publication_metadata", [{"terrain_fit": meaning}],
)
print(gxtxt_api_call("STATISTICAL_RESULT_SEMANTICS_API_v1", "report", [meaning]))

x_grid = np.linspace(x_min, x_max, grid_nx)
y_grid = np.linspace(y_min, y_max, grid_ny)
Xg, Yg = np.meshgrid(x_grid, y_grid, indexing="xy")
xgn = (Xg.reshape(-1) - x_center) / x_scale
ygn = (Yg.reshape(-1) - y_center) / y_scale
Ag = design_matrix(xgn, ygn, powers)
grid_prediction = gxtxt_api_call("NUMERIC_API_v1", "linear_matrix", [
    "multiply", {"real": Ag}, {"real": coefficients.reshape(-1, 1)},
])
zg = np.asarray(grid_prediction["value_real"], dtype=float).reshape(-1)

out_x = Xg.reshape(-1)
out_y = Yg.reshape(-1)
out_z = np.asarray(zg, dtype=float).reshape(-1)

x_unit = require_metadata(metadata, "terrain.x_unit")
y_unit = require_metadata(metadata, "terrain.y_unit")
z_unit = require_metadata(metadata, "terrain.z_unit")

definition = {
    "dataset_id": output_dataset_id,
    "contract": "table.generic",
    "storage": "auto",
    "replace_owned": True,
    "producer_version": "1.1.0",
    "structured_metadata": statistical_metadata,
    "source_dataset_ids": [source_dataset_id],
    "source_variable_ids": [x_id, y_id, z_id, family_id],
    "source": "Python Script Workspace terrain surface fit",
    "provenance": (
        f"Total-degree {degree} polynomial least-squares fit of Z=f(X,Y) "
        "from a family of terrain profiles."
    ),
    "notes": (
        "Dense rectangular fitted terrain grid. Fit settings and diagnostics "
        "are stored through Dataset Metadata API v1."
    ),
}

writer = gxtxt_api_call("DATASET_PUBLICATION_API_v2", "begin", [definition])
try:
    gxtxt_api_call(
        "DATASET_PUBLICATION_API_v2",
        "declare_dimension",
        [writer, "row", 0, {"extendible": 1}],
    )

    variable_definitions = (
        ("v_x_m", x_unit, "coordinate", "independent"),
        ("v_y_m", y_unit, "coordinate", "independent"),
        ("v_z_fit_m", z_unit, "data", "derived"),
    )
    for variable_id, unit, coordinate_role, semantic_role in variable_definitions:
        schema_def = {
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
            [writer, variable_id, schema_def],
        )

    gxtxt_api_call(
        "DATASET_PUBLICATION_API_v2",
        "append",
        [
            writer,
            "row",
            {
                "v_x_m": out_x,
                "v_y_m": out_y,
                "v_z_fit_m": out_z,
            },
        ],
    )

    published = gxtxt_api_call("DATASET_PUBLICATION_API_v2", "finalize", [writer])
    writer = None
except Exception:
    if writer is not None:
        gxtxt_api_call("DATASET_PUBLICATION_API_v2", "abort", [writer])
    raise

power_text = ";".join(f"x^{px}y^{py}" for px, py in powers)
coefficient_text = ",".join(f"{float(c):.17g}" for c in coefficients)

derived_metadata = {
    "data.synthetic": str(metadata.get("data.synthetic", "true")),
    "demo.type": "python_script_terrain_fit_output",
    "demo.domain": str(metadata.get("demo.domain", "synthetic_terrain")),
    "terrain.coordinate_system": str(metadata.get("terrain.coordinate_system", "local_cartesian")),
    "terrain.surface_quantity": str(metadata.get("terrain.surface_quantity", "elevation")),
    "terrain.x_unit": x_unit,
    "terrain.y_unit": y_unit,
    "terrain.z_unit": z_unit,
    "terrain.grid_nx": str(grid_nx),
    "terrain.grid_ny": str(grid_ny),
    "terrain.grid_rows": str(grid_nx * grid_ny),
    "processing.kind": "surface_fit",
    "processing.language": "python",
    "processing.source_dataset_id": source_dataset_id,
    "processing.source_family_variable_id": family_id,
    "processing.source_family_count": str(family_members.size),
    "fit.model": "polynomial_total_degree",
    "fit.statistical_model_id": "math.numeric.linear_design",
    "fit.metric_rmse": "response_rmse",
    "fit.numeric_api": "NUMERIC_API_v1",
    "fit.degree": str(degree),
    "fit.basis": "normalized_xy_total_degree",
    "fit.term_powers": power_text,
    "fit.coefficients": coefficient_text,
    "fit.x_center": f"{x_center:.17g}",
    "fit.x_scale": f"{x_scale:.17g}",
    "fit.y_center": f"{y_center:.17g}",
    "fit.y_scale": f"{y_scale:.17g}",
    "fit.rmse_m": f"{rmse:.17g}",
    "fit.r2": f"{r2:.17g}",
    "schema.x_variable_id": "v_x_m",
    "schema.y_variable_id": "v_y_m",
    "schema.z_variable_id": "v_z_fit_m",
    "presentation.surface_plot_type": require_metadata(metadata, "presentation.surface_plot_type"),
    "presentation.mesh_plot_type": require_metadata(metadata, "presentation.mesh_plot_type"),
    "interactive.target": str(metadata.get("interactive.target", "native_3d")),
}

updated_metadata = gxtxt_api_call(
    "DATASET_METADATA_API_v1",
    "update",
    [output_dataset_id, derived_metadata],
)

gxtxt_api_call("SESSION_PERSISTENCE_API_v1", "commit", [])

print(
    "PASS TERRAIN_FIT_PUBLISH "
    f"source={source_dataset_id} rows={row_count} families={family_members.size} "
    f"degree={degree} terms={len(powers)} rmse={rmse:.9g} r2={r2:.12g} "
    f"dataset={published['dataset_id']} output_rows={out_z.size} "
    f"metadata_keys={len(updated_metadata)}"
)
