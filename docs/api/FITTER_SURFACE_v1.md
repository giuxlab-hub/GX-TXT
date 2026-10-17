# Physical surface fitting in Fitter

SPDX-License-Identifier: GPL-3.0-or-later

`DATASET_CURVE_FIT_API_v1` exposes physical `z=f(x,y)` fitting, retained results,
and sampled 3D publication. Fitter owns the interaction and source capture;
[Numeric surface models](SURFACE_RESPONSE_MODELS_v1.md) own evaluation and the
existing Ceres solve. [CORE statistical semantics](STATISTICAL_RESULT_SEMANTICS_API_v1.md)
owns result interpretation, assumptions, parameter intervals and reports.

## Source and physical model

The source dictionary contains `dataset_id`, `x_variable_id`, `y_variable_id`,
`z_variable_id`, `layout`, and optional `sigma_variable_id`.

- `layout=points`: X, Y and Z are rank-one Variables sharing the exact same
  canonical dimension and shape. Their existing order and duplicates are retained.
- `layout=grid_yx`: X and Y are rank-one axes with distinct dimensions. Z is a
  rank-two matrix whose ordered dimensions are exactly Y, X. No transposition is inferred.
- Optional response sigma has the same rank, shape, dimensions and unit as Z.

Variables must be enabled real numeric values available through canonical managed
binary reads, with at most 65,536 original values per Variable. Physical units
must equal the recipe units; apply a declared upstream conversion when needed.
The [formula recipe](FIT_FORMULA_v1.md) has predictors `x,y`, explicit linear units,
one linear Z unit and 1–32 parameters with physical units, initial values, bounds
and optional fixed flags. X and Y are exact predictors in this model.

Fit options are `nonfinite` (`error` or explicit `omit`), `noise_model`,
`max_iterations` and `max_seconds`. Defaults are error, unspecified, 400 and 30.
Noise may be `independent_gaussian_known_sigma` only with response sigma, or
`independent_gaussian_estimated_variance` without sigma. Supplying sigma alone
does not declare Gaussian noise. Missing Z cells are omitted only by explicit
policy; original zero-based column-major indices remain `uint64`.

## Public lifecycle

Activate `viewer.dataset_curve_fit` / `DATASET_CURVE_FIT_API_v1`. Tcl procedures
below are in `::GX::DatasetCurveFit`; Script calls use positional argument lists
through `gxtxt_api_call` with the same API ID.

| Script operation | Tcl procedure | Arguments and result |
| --- | --- | --- |
| `surface_create` | `surfaceCreate` | Workspace name → `workspace_id` |
| `surface_preview` | `surfacePreviewSummary` | Workspace ID, source, recipe, options → preview ID, CORE statistics and domain |
| `surface_accept` | `surfaceAccept` | Workspace ID, unique accepted name → result reference |
| `surface_reference` | `surfaceResultReference` | Workspace ID, accepted fit ID → current result reference |
| `surface_info` | `surfaceInfo` | Reference → validated interpretation, domain, source layout/shape, recipe and owned resources |
| `surface_query` | `surfaceQuery` | Reference, N×2 XY coordinates, options → predictions/XYZ, optional parameter Jacobian |
| `surface_report` | `surfaceReport` | Reference → common CORE quantity and parameter report |
| `surface_residual_page` | `surfaceResidualPage` | Reference, zero-based start, count → physical residuals and exact original indices |
| `surface_export` | `surfaceExport` | Reference, `fit_` function name → Python, Octave, LaTeX and metadata |
| `surface_publish` | `surfacePublish` | Reference, new Dataset ID, X axis, Y axis, options → publication receipt |
| `surface_plot` | `surfacePlot` | Reference, previously published Dataset ID, `surface` or `mesh` → persistent Plot Variant reference |
| `surface_recipe_capture` | `surfaceRecipeCapture` | Reference → inert encoded recipe |
| `surface_recipe_run` | `surfaceRecipeRun` | Encoded recipe, new Workspace name, accepted name → new fitted result reference |

Tcl `surfacePreview` returns the captured result and accepts an optional host
for progress/cancellation. The Script summary avoids returning full observations.
A reference is `gxtxt.surface_fit_reference.v1`: Workspace ID/generation, fit ID
and state SHA256. An unavailable, replaced or changed result is refused. Results
live in the existing Session Workspace and Scientific History owners, with
owned original inputs, state, observations and exact index resources. Accept,
Undo/Redo and normal save/reopen retain these identities. Recipe replay explicitly
performs a new fit and refuses a changed source Dataset identity.

All retained operations validate the owned state, full recipe/constraints,
parameters, compiled identities, domain and common CORE receipt. The bounded
decoded-state cache is keyed by Session, owner generation and SHA; resource
integrity remains checked. Source payloads are never rewritten.

## Queries, residuals and publication

Queries accept 1–512 finite XY pairs. Integer inputs outside the exact binary64
range are rejected before conversion. `jacobian=true` requests derivatives with
respect to physical parameters. `extrapolation=error` is the default; explicit
`allow` returns flags. Retained axis bounds mean `axis_bounds_not_observation_coverage`:
they do not assert measured coverage inside holes or between observations.
Query receipts do not establish new training inference.

Residual pages contain at most 512 rows: X, Y, observed Z, predicted Z and
observed-minus-predicted Z, with physical units and a separate exact original
index array. They describe the captured training observations. The GUI shows the
first 64 rows. Parameter covariance/intervals retain the common CORE conditional
interpretation and unavailable states; there is no separate Fitter statistics policy.

Publication evaluates the retained model on explicit strictly increasing axes,
at most 65,536 cells. CORE publishes X/Y vectors and Y-by-X Z through
[`publish_managed_variables`](DATASET_PUBLICATION_API_v2.md#managed-multidimensional-variables).
The representation is `sampled_declared_surface_model`: no refit, interpolation
or modification of missing source cells occurs. Metadata retains recipe, source
binding, result/state identity and the CORE training record, explicitly scoped
to `original_training_observations_not_sampled_grid`.

`surface_plot` requires an unchanged grid published from the same accepted
reference. It uses public Plot Dataset v3, explicit Cartesian 3D bindings and
the existing persistent Variant/manifest. Use public `readPlot` for that
configuration and `buildScene`/`openViewer` for rendering; the 2D `loadSpec`
projection is not the 3D persistence contract. Plot owns canonical grid reading
and Native3D owns the scene. Fitter does not implement another renderer.

`surface_info.resources` exposes live owned references, not storage paths:
`state_resource`, `observations_resource`, `indices_resource`, `input_x`,
`input_y`, `input_z`, and optional `input_sigma`. Input arrays retain canonical
rank and dtype. Consumers can use the generic managed-variable publisher without
expanding bulk values into Tcl or Script control messages. The state resource is
a versioned control envelope, not a numeric array.

## GUI workflow

Open Dataset Curve Fit, then **Fit → Physical surface fit…**, or reopen the
saved **Physical Surface Fit** Workspace. Select the canonical Variables,
explicit layout, missing-value policy and noise assumption. Review units and
enter the physical expression and parameters. Choose **Preview fit**, inspect the
CORE report and retained residual rows, enter a distinct name, then **Accept fit**.
Editing the source, recipe or fit options requires another Preview before Accept.

Use the XY query fields and **Evaluate** for exact retained-model predictions.
**File → Export model…** writes independent model code and metadata; **File → Export rerun recipe…**
writes the inert replay declaration. Enter explicit grid bounds/counts and a new
Dataset ID, then **Publish sampled grid** and **Open published grid in3D**. The GUI limits each grid axis
to 2–256 samples. Save the Workspace and Session to retain controls, accepted
selection, history and grid settings. Closing the surface window saves its
Workspace through the normal owner.

Python retained-result example (inside a real Script Job):

```python
import numpy as np
from gxtxt import gxtxt_api_call as call
api = 'DATASET_CURVE_FIT_API_v1'
ref = call(api, 'surface_reference', [workspace_id, fit_id])
info = call(api, 'surface_info', [ref])
answer = call(api, 'surface_query', [ref, np.array([[0., 1.]]), {'jacobian': True}])
report = call(api, 'surface_report', [ref])
```

Octave uses the same names/argument order with cells and structs. Typed shape,
physical units and exact index dtypes survive both bindings.
