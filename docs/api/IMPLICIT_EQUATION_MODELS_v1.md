# Implicit equation models

These public `NUMERIC_API_v1` operations use the existing controlled formula,
CORE units, Ceres solver, covariance diagnostics and local root owners.

| Operation | Arguments | Result |
|---|---|---|
| implicit_model_compose | recipe | Versioned physical equation declaration |
| implicit_fit | model, x, y, optional solver options | Parameters, conditional covariance, equation residuals and bounded summary |
| implicit_evaluate | model, x, y, optional `{jacobian: true}` | Retained equation values and physical parameter Jacobian |
| implicit_query | model, independent queries, branch | Checked branch roots, points, derivatives and availability |

The recipe contains `formula`, `residual_mode` and, for normalized residuals,
`normalization`. `formula` follows `fit_formula_compose`: exactly two named
predictors with physical units, one equation expression and residual unit,
and 1–32 named parameters with physical units, initial values and optional
bounds/fixed declarations. Unit inference and internal conversion remain at
the shared formula owner. The equation is interpreted as **f(x,y,p)=0**.

`residual_mode` is `algebraic` or `normalized_algebraic`. Normalized mode requires
`normalization = {value: positive_number, unit: equation_unit,
role: reference_scale}`. Its unit must already match the equation's residual
unit; convert reference values explicitly first. The objective is the sum of
squared equation residuals divided by the square of this reference value.
Algebraic mode uses reference value 1 in equation units.

This scale is a physical reference, **not measurement sigma**. Residuals are
zero minus the equation value at the observed coordinate pairs. They are not
vertical Y errors or orthogonal measurement-error distances. A noisy implicit
equation can introduce bias when both coordinates are uncertain; these fits
condition on the supplied observed coordinates. Genuine XY measurement-error
fits use their separate declared ODR contract.

Fitting accepts 2–65,536 finite matched coordinate pairs without hidden omission
or display reduction. Solver options are the existing Ceres solver/strategy,
iteration/time/tolerance, loss, bounds/fixed/scales and thread controls.
Defaults are 400 iterations and 30 seconds. Independent weight/sigma/sigma_X
options are refused here. Actual stopping/rank/bound/loss diagnostics are kept.
No Y(X) or X(Y) curve is inferred merely by solving the equation residual fit.

## Query an explicit response branch

`branch` requires `response_index` (1 for X, 2 for Y), a two-value response
`bracket`, `continuous_branch_declared = true`, and a two-value
`independent_domain`. Queries number 1–64. Extrapolation defaults to `reject`;
`allow` records each extrapolated query. Optional `x_tolerance`,
`response_tolerance` and `max_iterations` use the existing local inverse/root
contract. Tolerances refer to the response coordinate and equation value,
respectively. The optional boolean `derivative` defaults to true.

The caller declares a continuous branch within the bracket. Positive and
negative circle branches, for example, require different brackets. Returned
roots are checked against the equation tolerance; global uniqueness is not
certified. Missing roots and invalid evaluations retain per-query reasons and
unavailable values. Derivatives use the ratio of existing two-sided automatic
coordinate partials. Nonsmooth or singular derivatives remain unavailable.
Queries perform no fit and provide no uncertainty interval.

## Common statistical interpretation

Use `STATISTICAL_RESULT_SEMANTICS_API_v1.from_numeric` with model ID
`math.numeric.implicit`, operation `implicit_fit`, the captured numerical result,
and the declared noise context. Physical covariance/parameter units and
normalized objective units are distinct. R-squared, known-sigma chi-squared
and ordinary functional-response likelihood ranking are not defined by this
contract. Unknown noise does not imply Gaussian confidence intervals.
Explicit independent Gaussian equation errors permit existing local Student
parameter inference, conditional on the observed coordinate pairs and equation.
Nonconvergence, rank failure, active bounds and robust loss retain the normal
unavailable-inference qualifications. No statistics are recomputed by CORE.

Python and Octave Script calls use the same argument order as the table;
arrays use the existing managed binary transport. Tcl uses the public Numeric
operation catalog with typed scientific operands. Model schemas, original
equation/parameter identities, exact coordinate signatures and immutable
declaration hashes are retained across these consumers.

## Retained branch models and standalone exports

The shared `model_query`, `model_geometry`, `model_inverse` and `model_export`
operations accept `kind=implicit_branch`, schema
`gxtxt.implicit_branch_model.v1`. Capture the original `recipe`, fitted
`parameters`, `declaration_sha256`, `equation_source_sha256`,
`equation_binding_sha256` and complete `branch`. These fields are validated
against the shared frozen equation declaration; the wrapper contains no
executable callback. Physical orientation must agree with `response_index`;
coordinate translations must be zero.

Retained queries distinguish the accepted output domain from the declared
branch domain. Requested extrapolation records both domains' flags. `derivative`
is physical dY/dX and `inverse_derivative` is physical dX/dY, even for an X(Y)
branch; `model_response_derivative` follows the branch response coordinate.
Singular tangents and missing roots remain unavailable with reasons. Each call
accepts at most 64 values. These operations never refit the equation.

An implicit branch requires sampled geometry; it does not become an exact
Native2D primitive. Missing roots at requested geometry endpoints refuse the
conversion. Fitter additionally verifies every requested output sample before
creating or replacing its curve. A sampled Workbench transfer retains the
complete equation and independently owned resources alongside its approximation.

Standalone Python and Octave exports use the shared expression compiler and
bounded bracket solver. They include explicit domain, branch, residual mode,
normalization and declaration identities in their metadata. Python requires
NumPy; Octave uses its standard runtime. Neither generated function needs GX-TXT.
The export domain must be within the declared branch domain. Invalid evaluations,
missing/ambiguous bracket roots or exhausted budgets raise an error rather than
fabricating coordinates. The caller's continuity declaration is retained and
never presented as a proof of global uniqueness.

## Fitter controls, persistence and consumers

Select **implicit** and **Fit → Implicit equation and branch…**.
Choose Y(X) or X(Y), enter the two-coordinate equation, physical parameter units,
initial values/bounds/fixed declarations, equation residual unit and residual
mode. Normalized mode also needs a positive physical reference value. Enter the
response bracket and independent-coordinate domain and explicitly declare a
continuous branch. Validate checks the shared formula and units; Apply stores
controls without fitting. Preview fit performs the bounded solve.

Predictors are always named `x` and `y` with the physical Dataset X/Y units;
choosing X(Y) does not swap their scientific identities. Translation must be
off. Output uses 2–256 checked branch samples; larger requests are refused
explicitly. Source rows and observations remain complete and in their actual
order. Retained residual columns are `source_x`, `source_y`, `equation_value`
and `equation_residual`, where the last value is minus the equation evaluated
at the observed pair. Residual plots use equation units. Predicted-response
residual ordering is unavailable for this contract.

Fitter accepts unspecified noise or explicitly independent Gaussian equation
errors with estimated variance. It refuses independent measurement sigma/weights,
XY error covariance, full observation covariance, response bands, bootstrap,
linear influence, multistart, smoothing, estimated baselines and log-response
preprocessing for this model. These refusals prevent a reference scale or
algebraic distance from acquiring an unsupported measurement-error meaning.

Accepted results, exact recipes, Workspace save/reopen, retained queries,
parameter Datasets and standalone exports preserve equation, normalization,
branch, physical units, original rows and immutable producer identities.
Python and Octave Script jobs use the same public Fitter operations and common
CORE results. The usual exact-producer recipe replay checks apply. Existing
transformed-source templates require explicit materialization before reuse.
The model card describes these assumptions and limits.
