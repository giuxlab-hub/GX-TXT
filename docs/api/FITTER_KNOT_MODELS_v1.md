# Fitter Akima and explicit-knot B-splines

SPDX-License-Identifier: GPL-3.0-or-later

Load a Dataset curve, choose **akima** or **bspline**, then open **Fit → Knots /
boundaries…**. Both use the shared [Numeric knot models](KNOT_SPLINE_MODELS_v1.md)
and [CORE statistical interpretation](STATISTICAL_RESULT_SEMANTICS_API_v1.md).
The original predictor coordinates must strictly increase. Reordering, duplicate
averaging or knot selection is never silently performed.

Akima interpolates the original observations with C1 cubic pieces. It needs at
least five observations. Choose extrapolated endpoint secants or **clamped**
and enter two slopes in response units per predictor unit. Akima can overshoot;
zero residuals at original knots do not establish regression quality.

B-spline approximates the observations by unweighted least squares using
explicit simple breakpoints. Enter degree1,2 or3 and two to257 increasing knots,
including the exact observed endpoints. Continuity is respectively C0,C1 orC2.
Each span needs at least degree+1 distinct observations. Boundaries are **free**,
**periodic**, cubic **natural** (zero endpoint second derivatives), or cubic
**clamped** (two physical endpoint slopes). Periodic boundaries constrain the
function and derivatives; they do not wrap extrapolated queries. Repeated knots
and variable continuity are outside this bounded simple-knot contract.

Both Y=f(X) and X=f(Y) preserve actual Dataset units. These models require
translations off and original physical observations; source smoothing, baseline
or logarithmic preprocessing, measurement weighting, full covariance and
nonlinear solver controls are refused. Knot construction has no scalar-parameter
editor, covariance, parameter interval, prediction band, bootstrap or influence
contract. The parameter Dataset command explicitly directs users to model export.

Preview records construction residuals separately from descriptive evaluation
on original source rows. A smaller output interval or different sample count
does not change training support or observations. Extrapolation is **error** by
default; explicit **allow** evaluates the boundary polynomial and flags points
outside observed support. Standalone exports enforce their captured interval.

Acceptance retains the exact numerical model, knots, degree, boundary/slopes,
units, source rows, CORE meaning and integrity hashes. Named recipes, templates,
Workspace and Session save/reopen preserve per-model settings. Changed scientific
identity, support, coordinate frame or retained state fails validation. Geometry
uses exact existing line/Bézier primitives when representable within the shared
piece budget; a sampled fallback is labelled explicitly and retains the model.

The existing [Fitter API](DATASET_CURVE_FIT_API_v1.md) exposes the same lifecycle
to Tcl and real Python/Octave Jobs: `recipe_run`, `result_info`, `result_query`,
`result_export`, `result_residual_page`, `result_publish` and `result_workbench`.
No new parallel solver or statistical interpreter is required. Public fit option
`knot_options` contains `boundary`, optional `endpoint_slopes`, and
`extrapolation=error|allow`; B-spline also requires `knots` and `degree`.
`x_unit` and `y_unit`, when supplied, must match the actual predictor and response.
They are captured explicitly by recipe production.

Recipe replay constructs a new model only when requested. Retained queries,
export and Workbench transfer do not fit again. Physical derivative output is
dY/dX, with dX/dY separately available. At genuine degree-one slope jumps the
derivative is unavailable. Exact original Dataset row IDs remain uint64.

Bounds are65,536 original observations and257 B-spline breakpoints. Retained
JSON decoding has a128MiB budget; the Fitter text export adapter has a2MiB model
budget and refuses oversized exports without substituting sampled data.
