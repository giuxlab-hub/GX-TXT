# `NUMERIC_API_v1`

Constrained Gaussian parameter profiling uses the public
[profile-likelihood contract](../../../docs/api/FIT_PROFILE_LIKELIHOOD_v1.md). Physical search limits, actual
thresholds, local-solver qualifications and unresolved endpoints remain explicit;
covariance-based Wald intervals retain their separate approximation.

Physical `z=f(x,y)` declarations, exact point/grid fitting, retained evaluation,
parameter Jacobians, explicit model sampling, descriptive residuals and independent
exports share the [surface response contract](../../../docs/api/SURFACE_RESPONSE_MODELS_v1.md).
CORE interprets their captured facts through canonical `math.numeric.surface`.

Public `fit_formula_compose(recipe)` creates a safe expression declaration with
CORE dimensional inference and physical parameter units. The same model uses
existing nonlinear fitting/evaluation/export operations; see the
[formula contract](../../../docs/api/FIT_FORMULA_v1.md).

Public `residual_sequence(residuals, ordering_keys, options)` computes bounded
ordered runs, lag correlations and Durbin–Watson facts with exact integer keys.
CORE owns interpretation; see the [complete contract](../../../docs/api/RESIDUAL_SEQUENCE_v1.md).
Legacy Tcl `smooth` and `smoothDataset` preserve explicit `robust_iterations`;
unknown smoothing controls are rejected. The operation catalog lists the same
LOWESS/LOESS controls as the binary and Script bindings.

SPDX-License-Identifier: GPL-3.0-or-later

## 1. Scope and stability

`NUMERIC_API_v1` is the public mathematical/numerical service of bundled CORE module `math.numeric`. API version `1` is independent of the GX-TXT release number and of the module implementation version. Existing v1 calls are retained where practical; new methods/results may be added additively without changing established call signatures.

`residual_metrics` returns `relative_n` and
`relative_floor`, preserving the eligible denominator count and configured floor
from its existing calculation. Relative errors exclude zero observed values and
absolute observed values below the floor; they are dimensionless fractions.
The numerical algorithm and existing output fields are unchanged. The CORE
statistical API gives prediction scores and relative errors their public meaning.

The API provides mathematical primitives. It includes reusable FFT/IFFT, analytic-signal construction, transform-coordinate, detrending and window-generation primitives, but it does not define domain-specific spectrum/PSD workflows, model-specific fitting semantics, chromatographic interpretation, UV/Vis interpretation or chemistry-specific processing.

## 2. Discovery

`prediction_uncertainty(model, predictors, plan, options={})` propagates captured
parameter covariance through the existing native model/Jacobian evaluator. Tcl
uses `predictionUncertainty model_node predictors_node plan ?typed_options?`;
Octave uses `gxtxt_numeric_v1('prediction_uncertainty', model, predictors, plan,
options)`. Script Bridge exposes the same operation with native values.
The plan comes from CORE `prediction_inference_plan`. Formula and binding hashes,
all fixed/free parameter identities and values must match the recorded fit.
For registered linear/polynomial/builtin models without native fit hashes, the
canonical compiled expression is checked. No fitting or covariance estimation
is repeated. Evaluation uses blocks of at most 4096 query rows.

Polynomial response propagation requires the CORE plan's captured
`STATISTICAL_POLYNOMIAL_PROPAGATION_BASIS_v1`. Numeric evaluates the existing
polynomial/Jacobian in the recorded centered/scaled predictor coordinates and
uses its original scaled covariance. This avoids catastrophic cancellation in
physical power coefficients at large predictor offsets. The canonical model
hashes and physical parameter IDs remain unchanged; the complete plan identifies
the coordinate transformation. `propagation_coordinate_space` records the actual
evaluation basis. A missing scaled basis rejects instead of using an unstable
unscaled covariance calculation.

Only `prediction_sigma` or `prediction_weights` are accepted as future-noise
options when required by the plan. Each is a positive finite scalar or one value
per query. Relative precision scales the captured residual standard deviation;
known absolute sigma uses Normal inference. Estimated variance uses the plan's
Student-t degrees of freedom. A captured critical value at the same confidence
is reused. The covariance must be positive semidefinite; only tiny negative
correlation eigenvalues within `64*eps*max(1,max(abs(eigenvalues)))` are clipped,
and their actual count is recorded. Larger violations reject.

Outputs include predictions, mean and selected standard errors, future-noise
scales, lower/upper bounds, availability mask, query indices, actual counts,
compiled model hashes and the original plan. Unrepresentable pairs become NaN
with `bounds_available=0`. Return the receipt to public CORE
`prediction_interpretation` before presenting or publishing statistical claims.

The additive Tcl capability `captured_statistical_columns` provides
`::GX::NumericAPIv1::callOperationCaptured document_id operation operands context
?options? ?provenance?`. It uses the existing catalog validation and public
numerical function once. Input arrays use binary descriptor v2; registered real
binary64 vector facts are captured as columns in the existing Document resource
store. The Document must already exist. CORE supplies model interpretation and
physical units from the explicit context, and validates the captured row shape.

The result has `values` (remaining scalar/control fields), `types`,
`captured_statistics` and bounded `transport` byte counters. Captured vector fields
have type `captured_column` and are absent from `values`: their first-row prototype
must never be displayed as the full vector. Access the binding through the public
CORE `resourceBindingTable` and field operations. Scalar-only results retain a
scalar statistical capture. This route requires a registered parameterless
table-compatible profile and equal-length mapped real vectors; it does not flatten
parameter covariance or arbitrary tensors. Preserve the binding in saved Document
payload/live references/publication metadata to establish resource lifetime.

Python/Octave Jobs use the existing public Numeric operation, then CORE
`from_numeric` and `store_columns` on those same results. This gives both languages
the same storage and interpretation without a second numerical invocation.

A data-only declared model is supported by `nonlinear_fit`
and `dataset_nonlinear_fit` operations. Octave passes the model in the
existing callback position. Script Bridge uses `[X, Y, model, initial, options]`;
the Dataset operation uses `[dataset_id, x_id, y_id, model, initial, options]`.
The Tcl `callModelOperation` route accepts `kind=expression`.
The model requires `expression` and ordered, unique `parameter_ids`;
`predictor_ids` defaults to `{'x'}`, and explicit `parameter_units` follows
the same parameter order. Formula text uses the existing CORE controlled
expression grammar and cannot execute code. Supported functions are exp, log,
sqrt, sin, cos, tan, sinh, cosh, tanh, abs, atan, erf and log10.

The declared route requires the Numeric-owned Ceres 2.2.0 adapter compiled for
the running Octave ABI. It reports a dependency error if unavailable. Existing
Octave and registered Script callbacks retain their established route.
The adapter invokes Ceres with automatic derivatives and dense QR inside the
existing provider worker. `solver=auto|ceres`, `strategy=levenberg_marquardt|dogleg`,
`max_iterations`, `max_seconds`, `function_tolerance`, `gradient_tolerance`
and `parameter_tolerance` are recorded in model state. `tolerance` supplies
the three tolerances when not explicitly set. Threads cannot exceed the Job
internal thread budget.

`lower_bounds`, `upper_bounds`, and boolean `fixed_mask` have parameter length;
equal lower/upper bounds also fix that parameter. Initial values must satisfy
bounds. Positive `parameter_scales` map physical parameters to solver coordinates;
the default is absolute initial value, using 1 only for zero initial values.
Returned estimates, bounds, Jacobian and covariance use physical coordinates.
Covariance uses a column-scaled Jacobian SVD and the free-parameter tangent
space; fixed parameter rows are zero. Active bounds, rank deficiency,
nonpositive residual DOF and robust losses do not claim ordinary Wald
uncertainty. Losses are linear, huber, cauchy, soft_l1, arctan and tukey, with
positive `loss_scale` in whitened residual units.

For joint responses, each formula is one response column and shared parameter
identities remain shared. Explicit `response_units` and per-component sigma or
inverse-variance weights are required. No aggregate physical RMSE or R squared
is reported across differing response units. Nonfinite input defaults to an
error; explicit `nonfinite=omit` removes complete affected observation rows.
A zero weight removes its complete row, including other response components;
source and dropped row positions are recorded, with one-based input positions.
Saved `model.solver_options` contains bounded effective policy. Full sigma,
weights and Dataset selection vectors remain with source/owned resources and
are not copied into model metadata. The additive `model.input_contract` records
input/retained row counts, dimensions, weighting and missing-value policy.
`solver_options.required_measurement_input` records `sigma`, `weights`, or
`none`; using saved policy for another fit requires supplying the corresponding
original measurement input. Missing required input rejects instead of silently
fitting unweighted. Evaluating old saved models still accepts their original
policy fields, including embedded measurements, without refitting.
The adapter bounds each Jacobian to 512 MiB; this is not a total-process RSS cap.
`adapter_dataset_copy_bytes` counts copies only inside the C++ entry;
preparation, transport, solver workspace and returned arrays have separate costs.

Use `STATISTICAL_RESULT_SEMANTICS_API_v1/from_numeric` for reports and publication.
It preserves declared parameter identities and units, marks fixed parameters,
and prevents caller context from relabeling active constraints as unconstrained.
Successful reference cases do not establish universal convergence.

<a id="reproducible-declared-model-multistart-dev097"></a>
### Reproducible declared-model multistart

The same `nonlinear_fit` and `dataset_nonlinear_fit` operations accept
`multistart_mode=single|explicit|uniform`; omitted mode preserves the original
single fit. This strategy applies to declared models. Callback models reject
multistart until they have an equivalent replay contract.

`multistart_count` (default 8, range 2–64) includes the original initial vector as
start 1. In `explicit` mode, `multistart_initials` is a matrix of count-minus-one
rows in canonical parameter order. In `uniform` mode, provide finite parameter
vectors `multistart_lower` and `multistart_upper` inside the solver bounds, and
`multistart_seed` (default 1, integer 1–2147483646). These are starting ranges;
the existing `lower_bounds`/`upper_bounds` continue to constrain optimization.
Fixed parameters retain their original values in every trial; explicit rows that
change them reject. Equal bounds also fix a parameter.

Uniform starts reuse public `resample_indices` and its
`park_miller_16807_v1` generator. Trials are generated in row order, parameters
in canonical order, including draws subsequently replaced by fixed values.
An integer state divided by 2147483647 supplies the open-unit uniform value;
convex interpolation maps it into the requested interval. The receipt records
seed, next seed, generator/version and every exact initial vector. Global random
state is unchanged. Explicit mode records generator `none` and seed zero.

Trials execute sequentially with one Ceres thread; an explicit `threads` other
than 1 rejects. The original initial vector supplies common default parameter
scales; caller scales override these. `multistart_max_seconds` (default 60,
maximum 86400) limits the whole strategy, while `max_seconds` still bounds an
individual solve and is clamped to remaining time. Start generation and input
validation precede this timer; it is a solver-work limit, not a hard process
deadline. The existing worker cancellation discards an incomplete result.
Time limits can change the attempted subset and therefore the selected result;
replay comparisons require completion of the same trial set.

The strategy retains one existing result with the lowest finite Ceres objective
among converged trials. Exact ties select the earliest index. If none converged,
the best finite result is provisional and cannot certify parameter uncertainty.
If no finite result exists, the call errors with a bounded JSON trial receipt.
Invalid starts and unattempted time-limited starts keep explicit status/reason.
The selected result is never refitted. Only its observation arrays are returned;
trial receipts contain bounded parameters and diagnostics, not repeated datasets.

`solver_receipt.multistart` and `model.multistart` contain the versioned receipt,
all trial outcomes, selection/counts and execution policy. CORE validates the
receipt and supplies the public solver report to GUI and both Script languages.
Selection among a finite set of starts does not certify a global optimum.

The catalog provides Octave `point_sequence_order(points, options)` for a
finite 2..4096 by 2 or 3 matrix. `policy=x_monotone|geometry_auto` and an explicit
zero-based `start_index` select a deterministic candidate. Results include
unchanged points, permutation/inverse, changed count, segment starts, ambiguity,
coincident-point and 2-D crossing diagnostics. Geometry always requires review;
when starting at ordinal zero, an exactly repeated final closing observation is
retained at the end with its distinct original identity. The receipt records
`closed_endpoint_preserved` and algorithm `stable_x_or_greedy_nearest_v2`.
This endpoint rule does not infer unique interior connectivity or close open paths;
3-D topology cannot be inferred. It neither interpolates nor changes a Dataset.
This is an Octave binding callable through the typed host dispatcher;
no direct Python/Script Bridge binding is advertised for this operation.

The public service also provides `polar_coordinates(X,Y,options)` and`cartesian_coordinates(theta,radius,options)`, available in Octave and both
Script Bridge languages. The explicit frame options are `origin`,
`theta_zero` (radians), `clockwise`, `angle_unit=rad|deg`,
`unwrap_policy=cut|continuous` and `angle_cut` in the chosen angular unit.
Conversion reports origin points with `angle_undefined`; Cartesian conversion
rejects negative radii. The fitting consumer decides whether a curve is a
single-valued radial graph. Continuous unwrap keeps ordered angular continuity
and cut mode retains the explicitly selected branch. Structured frame values
and projection diagnostics retain typed nested transport.

Ordered parametric cubic projection uses a native conservative control-hull
BVH when the supplied `.oct` module is installed. It evaluates every candidate
segment's stationary roots and endpoints; it never substitutes display samples.
The portable Octave implementation remains an exact fallback. The native module
source is supplied alongside it and can be built with `mkoctfile -std=c++17 -O3`.
Projection diagnostics expose full segment/query counts and candidate/index
work, independently of rendering or viewport settings.

Consumers discover `NUMERIC_API_v1` from `math.numeric/module.ini` and use the advertised Tcl entrypoint or Octave entrypoint. Do not source `runtime/` files.

Tcl:

```tcl
source $advertised_entrypoint
set info [::GX::NumericAPIv1::apiInfo]
if {![::GX::NumericAPIv1::supports polynomial_fit]} { error "polynomial fitting unavailable" }
```

Octave modules obtain the advertised Octave API directory/function and call:

```octave
out = gxtxt_numeric_v1(operation, ...);
```

The public operation catalog is data-only and available without invoking the
numerical worker:

```tcl
set ids [::GX::NumericAPIv1::listOperations]
set meta [::GX::NumericAPIv1::operationMetadata array_reduce.mean]
set byName [::GX::NumericAPIv1::operationByExpressionName mean]
set foundationIds [::GX::NumericAPIv1::listFoundationOperations]
set dotMeta [::GX::NumericAPIv1::foundationOperationMetadata vector.dot]
```

Octave offers `gxtxt_numeric_v1('list_operations')`,
`gxtxt_numeric_v1('operation_metadata', id)`, and
`gxtxt_numeric_v1('operation_by_expression_name', name)` with the same source
catalog. Each record declares bindings, data-operand arity (excluding family
selector and optional options struct), argument kinds, shape/broadcast rules,
options, result shape, nonfinite policy, unit behavior, and capability.

The provider-owned foundation catalog expands the grouped `foundation` call
into individually discoverable `family.action` records. Each record includes
its public invocation family/action, argument names, input shape, result kind,
callback/file-resource flags, and a Worksheet range example. The stable
dispatcher remains `foundation(family, action, a, b, c, options)`.

`callOperation(id, typedOperands, typedOptions)` is an additive, data-only Tcl
entrypoint for catalogued operations that have an Octave binding. Operands use
the same `ScientificTransportv1` typed nodes as the scientific providers. It
validates catalog identity and arity, rejects callback operations, and returns
the public result dictionary while `resultTypes` reports each field's shape.
For example:

```tcl
set p [::GX::ScientificTransportv1::array {1 1} {0.975}]
set df [::GX::ScientificTransportv1::array {1 1} {9}]
set result [::GX::NumericAPIv1::callOperation student_t_quantile [list $p $df]]
```

Only result fields supported by the shared typed scientific transport can
cross this Tcl boundary; execution-scoped callbacks remain in the registered
Octave/Python Script Bridge.

For guided interactive clients, `modelKinds(operationId)` and
`callModelOperation(operationId, typedModel, typedDataOperands, typedOptions)`
offer a bounded data-only model callback path. The provider constructs fixed
Octave callbacks internally; no Tcl, Python or Octave code is accepted from
the Worksheet. Supported model kinds include polynomial roots and scalar
minimization, polynomial/Gaussian/exponential nonlinear fitting, quadratic
norm minimization, linear equations and ODEs, and quadratic Lagrangians. The
same path covers catalogued callback-based `foundation.family.action` calls.
The model is a typed struct with a text `kind` and explicit numeric fields;
`modelKinds` is the authoritative compatibility list for each operation.
Registered scripts remain the public path for arbitrary user callbacks.

Callback-bearing operations (`nonlinear_fit`, `dataset_nonlinear_fit`, `root_find`, `minimize_1d`, `minimize`) are Octave-binding operations. The Tcl worker deliberately does not serialize executable functions.


## 2.1 Public binding inventory

The Tcl facade exposes data-only operations: `arrayUnary`, `arrayBinary`, `arrayCompare`, `arrayMask`, `arraySelect`, `arrayWhere`, `arrayReduce`, `complexUnary`, `complexBinary`, `unwrap`, `rank`, `covariance`, `correlation`, `mad`, `histogram`, `ecdf`, `normalCdf`, `studentTCdf`, `fCdf`, `matrixSvd`, `resampleIndices`, `normalizeVector`, `vectorSimilarity`, `fft`, `ifft`, `analyticSignal`, `frequencyGrid`, `oneSided`, `detrend`, `window`, `interpolate`, `resample`, `resampleUniform`, `splineCreate`, `splineEvaluate`, `splineIntegral`, `integrate`, `cumulativeIntegrate`, `differentiate`, `gridInfo`, `validateMonotonic`, `uniformGrid`, `commonRange`, `statistics`, `quantiles`, `weightedQuantiles`, `cumulativeSum`, `weightedStatistics`, `leastSquares`, `linearRegression`, `polynomialFit`, `polynomialEvaluate`, `smooth`, `digitalFilter`, `findPeaks`, `baseline`, `baselineAnchored`, `propagateIndependentUncertainty`, `propagateCovariance`, and the Dataset-aware commands listed in section 15.

The Octave dispatcher additionally exposes callback-bearing operations: `nonlinear_fit`, `dataset_nonlinear_fit`, `root_find`, `minimize_1d`, and `minimize`.

<a id="22-complex-linear-algebra-extension-mathnumeric-1100"></a>
## 2.2 Complex linear algebra

`linear_matrix(action, A, B, options)` is a public `NUMERIC_API_v1` operation. It uses GNU Octave's LAPACK-backed matrix operations; no new native runtime or worker pool is introduced. `A` and optional `B` are nonempty finite two-dimensional real or complex numeric arrays in Octave. The Tcl facade and Script Bridge accept `{"real": matrix, "imaginary": matrix}`; `imaginary` may be omitted for real input. A right-hand-side vector is an `N x 1` matrix. Real and imaginary shapes must match. Empty matrices and NaN/Inf input are rejected. Inputs are dimensionless mathematical values: callers remain responsible for compatible physical units.

Octave: `gxtxt_numeric_v1('linear_matrix', action, A, B, options)`; pass `[]` for unused `B`. Tcl: `::GX::NumericAPIv1::linearMatrix $action $A ?$B? ?$options?`. Script Bridge in either language: `gxtxt_api_call('NUMERIC_API_v1', 'linear_matrix', {action, A, B})` (Python uses a list). For options without `B`, pass an empty second operand. `gxtxt_api_require('NUMERIC_API_v1@1:math.numeric+complex_linear_algebra')` provides preflight.

Actions and result fields:

| Action | Contract | Added result fields |
|---|---|---|
| `inspect` | Any matrix; trace/determinant only when square | `hermitian`, `symmetric`, `positive_definite`, `norm_one`, `norm_frobenius`, `norm_infinity`, optional `trace_*`, `determinant_*` |
| `identity`, `transpose`, `conjugate_transpose`, `diagonal` | Identity matches A shape; diagonal extracts a matrix diagonal or constructs a diagonal matrix from a vector | `value_real`, `value_imaginary` |
| `multiply` | `columns(A) = rows(B)` | `value_*` |
| `solve` | `rows(A) = rows(B)`; multiple RHS columns allowed | `value_*`, `residual_*`, `residual_norm`, `relative_residual`, `rhs_columns`, `solution_kind` |
| `inverse`, `pseudoinverse` | Inverse requires nonsingular square A; pseudoinverse uses SVD threshold | `value_*` |
| `lu`, `qr`, `cholesky`, `svd` | LU square; QR any shape; Cholesky Hermitian positive definite; SVD economy form | `l_*`, `u_*`, `p_*`; `q_*`, `r_*`, `p_*`; `r_*`; or `u_*`, `s_*`, `v_*` |
| `eigen`, `hermitian_eigen`, `generalized_eigen` | Square A; Hermitian check for named action; generalized requires equally shaped B | `eigenvalues_*`, `eigenvectors_*` |
| `exponential`, `power` | Square A; power requires integer `options.exponent` | `value_*` |

Every result also contains `rows`, `cols`, numerical `rank`, `rank_tolerance`, and `condition_number`. All array results use paired `*_real`/`*_imaginary` fields, including real arrays (zero imaginary part). Octave reconstructs with `complex(result.value_real, result.value_imaginary)`. Tcl returns row lists for matrices and flat lists for vectors. Script Bridge returns numeric arrays. LU satisfies `P*A=L*U`; QR satisfies `A*P=Q*R`; SVD satisfies `A=U*S*V'`. Eigenvector ordering and phase are backend-dependent; verify eigenpair residuals rather than exact eigenvector bytes.

`solve` defaults to `rank_policy='error'`, rejecting rank deficiency. `rank_policy='minimum_norm'` uses the Moore-Penrose pseudoinverse for underdetermined or rank-deficient problems. Full-rank overdetermined systems use least squares. `rank_tolerance` is a nonnegative singular-value threshold; by default it is `max(size(A))*eps(max(svd(A)))`. Inverse and default solve reject `condition_number > condition_limit` (default `1e12`); an explicit larger finite limit permits an informed ill-conditioned calculation. These checks are diagnostics, not guarantees of accuracy. `relative_residual` divides by `max(norm(B,'fro'),eps)`. Matrix exponential uses Octave `expm`; matrix power uses integer powers. Matrix logarithm and square root remain P1 work.

Invalid inputs return `GXTXT:Numeric:*` Octave identifiers; the Tcl facade and Script Bridge preserve a useful error message. Notable errors are `InvalidOperand`, `DimensionMismatch`, `RankDeficient`, `IllConditioned`, `NotHermitian`, `NotPositiveDefinite`, `InvalidTolerance`, and `InvalidExponent`. The existing Dataset representation is unchanged: callers read canonical variables through Dataset APIs, then pass explicit matrix values to this raw mathematical service.

Python Script Bridge example:

```python
from gxtxt import gxtxt_api_call
result = gxtxt_api_call("NUMERIC_API_v1", "linear_matrix", [
    "solve", {"real": [[2, 1], [1, 3]]}, {"real": [[1], [2]]}
])
assert abs(result["value_real"][0] - 0.2) < 1e-12
```

## 3. Common numerical rules

Most low-level curve operations use real numeric data. The Octave `fft` operation additionally accepts complex numeric vectors; transform results are returned as separate real/imaginary vectors so the public contract remains transportable. Unless stated otherwise, `nonfinite='error'`; `nonfinite='omit'` explicitly discards invalid observations/pairs where omission has a well-defined meaning. No operation silently sorts X, merges duplicate coordinates, or converts units.

Interpolation, resampling, spline construction, integration, cumulative integration, differentiation, smoothing and peak primitives require strictly increasing X. Duplicate or decreasing/non-monotonic X produces an error. Polynomial/regression/nonlinear fitting does not require sorted X and preserves repeated observations.

Weights are non-negative observation weights. Zero-weight observations are discarded and at least one positive weight is required. Fitting operations use `weight_semantics=relative` by default for backward compatibility: coefficient covariance is scaled by the fitted residual variance. `weight_semantics=inverse_variance` declares absolute inverse-variance weights and leaves the normal-matrix covariance unscaled; the result then reports `reduced_chi_squared`. If positive uncertainties `sigma` are supplied to nonlinear fitting, weights are `1/sigma^2` and inverse-variance semantics are selected automatically.

Low-level APIs do not attach or convert physical units. Callers must pass numerically compatible quantities. Dataset-aware results report source units and derived calculus units, but `math.numeric` does not invent unit conversions or reinterpret fit-parameter units. Polynomial coefficient units are implied by the caller's X/Y units and polynomial power; they are not synthesized into unit strings.

Dataset operations use stable `dataset_id + variable_id`. Dataset Selection filtering is applied through the public Selection API before the numerical primitive. No provider-private file is opened by `math.numeric`.

## 3.0 Generic real-array operations

The Octave binding exposes `array_unary(name, values, options)`, `array_binary(name, left, right, options)`, `array_compare(name, left, right, options)`, `array_mask(name, first, ?second?)`, `array_select(values, mask)`, `array_where(mask, true_values, false_values)`, and `array_reduce(name, values, options)`. Each returns a struct with `values`. Scalars expand against arrays; two non-scalar operands must have identical shape. Arrays are real and have at most two dimensions. Masks contain only zero or one and can be scalar or match the value shape.

Unary names: `negate`, `abs`, `sign`, `sqrt`, `square`, `reciprocal`, `exp`, `expm1`, `log`, `log10`, `log1p`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `sinh`, `cosh`, `tanh`, `floor`, `ceil`, `round`, `is_finite`, `is_nan`, `is_inf`, `is_pos_inf`, `is_neg_inf`. Binary names: `add`, `subtract`, `multiply`, `divide`, `power`, `minimum`, `maximum`, `atan2`, `hypot`. Comparison names: `equal`, `not_equal`, `less_than`, `less_equal`, `greater_than`, `greater_equal`. Mask names: `logical_not`, `logical_and`, `logical_or`, `logical_xor`. Reductions: `sum`, `product`, `minimum`, `maximum`, `argmin`, `argmax`, `any`, `all`, `count`, `count_true`. Reduction `axis=0` flattens to one result; `axis=1|2` reduces columns or rows and retains the other dimension. Argmin/argmax indices are one-based. `array_select` returns a column vector in linear index order.

Inputs and arithmetic results must be finite by default. `nonfinite='ieee'` explicitly permits IEEE NaN/Inf values for arithmetic and comparison. Predicates `is_nan`, `is_inf` and `is_finite` accept non-finite input by design. A complex result is always rejected; invalid real domains such as square root of a negative value cannot silently become complex.

The Tcl facade accepts typed operands: `[dict create kind scalar|vector|matrix value $values]`. For example:

```tcl
set left [dict create kind vector value {10 20}]
set right [dict create kind scalar value 2]
set result [::GX::NumericAPIv1::arrayBinary divide $left $right]
```

Dataset-aware operations are `arrayUnaryDataset(session, datasetId, variableId, name, options)`, `arrayBinaryDataset(session, datasetId, leftVariableId, rightVariableId, name, options)`, and `arrayScalarDataset(session, datasetId, variableId, scalar, name, options)`. The Octave names are `dataset_array_unary`, `dataset_array_binary`, and `dataset_array_scalar` with the same positional values. `scalar_first=1` changes operand order for scalar operations. Binary variable operations require both stable IDs in the same Dataset; no implicit Dataset alignment or unit conversion occurs. `selection_id` in Tcl options, or the public Selection struct in Octave options, filters rows through Table Stream before arithmetic. Results retain source IDs, source units and the Selection ID, without claiming a derived physical unit.

### Additional reductions and observation counts

`array_reduce` also supports `mean`, `median`, population/sample variance and
standard deviation, `rms`, `quantile`, and `valid_count`. Quantile uses type-7
interpolation and requires an explicit `probability` from 0 to 1. With
`nonfinite=omit`, argmin/argmax retain the original one-based input indices.
Every reduction returns `action`, `requested_axis`, original `input_shape`, and
per-group `n_input`/`n_valid` arrays with the same shape as `values`. The existing
resolved `axis` and numeric values are unchanged. Quantile also records its
probability and definition. These additive facts let CORE interpret scalar or
axis-indexed results without calculating the statistic again; use the qualified
`array_reduce.ACTION` CORE operation ID. `count` and `valid_count` keep their
existing arithmetic meanings.
`statistics`, `weighted_statistics`, and `weighted_quantiles` report
`n_input`, `n_valid`, and `n_nonfinite`; weighted results also report
`n_zero_weight` and `n_positive_weight`. The existing `n` field remains for
compatibility. These counts distinguish omitted nonfinite observations from
finite observations given zero weight.

### Complex, inferential, matrix, and random primitives

`complex_unary(name, real_part, imaginary_part, options)` accepts
`conjugate`, `magnitude`, `magnitude_squared`, `phase_rad`, `phase_deg`,
`real`, and `imag`. Conjugate returns `real` and `imaginary`; real projections
return `values`. `complex_binary(name, real_a, imag_a, real_b, imag_b,
options)` accepts `add`, `subtract`, `multiply`, and `divide`, returning
split `real` and `imaginary`. Parts and operands use exact shapes with scalar
expansion. `unwrap(phase, options)` returns continuous phase `values` with
positive `period` (default `2*pi`). These are generic array operations;
domain-specific spectra remain in their analysis modules.

`rank` supports `ties=average|min|max|dense`. `covariance` and `correlation`
pair observations before `nonfinite=omit`; correlation supports
`method=pearson|spearman`. `mad` accepts an explicit scale choice
(`raw` or `normal_consistency`), and `histogram` supports automatic, count,
width, or explicit-edge bins. `ecdf` returns unique support and cumulative
probability. `normal_cdf`, `student_t_cdf`, and `f_cdf` accept real scalar or
array inputs with scalar expansion and require positive scale/degrees of
freedom. The functions return probability `values`.

`matrix_svd` returns economy `u`, `singular_values`, `v`, numerical `rank`,
rank tolerance, and condition number for a finite real matrix.
`resample_indices(population_size, draw_count, replicates, seed, options)`
returns one-based `indices` as a replicates-by-draw-count matrix and
`next_seed`; pass `next_seed` into the next call to continue a reproducible
batched sequence. The seed is
an integer from 1 to 2147483646. `replace` defaults to true; false draws
without replacement within each replicate. The isolated Park-Miller generator
has no effect on Octave's global random state and produces the same index
matrix on Linux and Windows for the same inputs.

`dataset_reduce_summary(session, dataset_id, variable_id, options)` streams
Table Stream chunks into a composable count/sum/min/max state, then returns
`mean`, `n_input`, `n_valid`, and `n_nonfinite` with Dataset identity and unit.
It supports a public Dataset Selection and `nonfinite=error|omit`. Memory is
bounded by the requested `chunk_rows` for this operation. Other Dataset
operations that return full vectors or require sorting/fitting still retain
their full result or observation arrays in memory.

## 3.1 Reusable transform, frequency, detrend and window primitives

### `fft(values, options)`

Computes a generic discrete Fourier transform without hidden detrending, windowing, resampling or PSD interpretation. `options.nfft` defaults to the input length and may explicitly zero-pad or truncate according to the documented Octave FFT length behavior. `normalization` is `backward` (default: forward unscaled, inverse scaled by `1/N`), `forward`, or `unitary`. Non-finite input is rejected; `nonfinite=omit` is deliberately unsupported because omission changes sample coordinates.

Returns `real`, `imaginary`, `nfft`, `input_length`, `normalization`, and `ordering=fft`. The Octave binding accepts real or complex input. The Tcl `fft` facade accepts real input and receives the same split-complex result.

### `ifft(real_values, imaginary_values, options)`

Computes the inverse transform from explicit real and imaginary vectors. It uses the same `nfft` and `normalization` conventions as `fft`. Returns split real/imaginary output plus transform metadata.

### `analytic_signal(values, options)`

Constructs the discrete analytic signal of a finite real-valued record with the standard FFT Hilbert multiplier: DC is preserved, positive-frequency bins are doubled, negative-frequency bins are suppressed, and the Nyquist bin is preserved for even record lengths. Returns split `real` / `imaginary` vectors, `amplitude = abs(real + i*imaginary)`, sample count `n`, and `method=fft_hilbert_multiplier`. The operation is mathematical only: it does not perform detrending, band selection, windowing or spectrum/PSD interpretation. Non-finite samples are rejected and `nonfinite=omit` is not supported because omission changes sample coordinates.

### `frequency_grid(sample_rate, nfft, options)`

Builds transform-bin frequencies independently of any scientific spectrum semantics. `representation=one_sided|two_sided`; two-sided grids support `ordering=fft|shifted`. One-sided grids include DC and include Nyquist only for even `nfft`. Returns `frequency`, `df`, `nyquist`, representation/order metadata and `has_nyquist`.

### `one_sided(real_values, imaginary_values, options)`

Selects the canonical one-sided bins from a full FFT-ordered transform. `scaling=none` (default) performs selection only. `scaling=amplitude` doubles interior complex coefficients while leaving DC and even-length Nyquist unchanged. Power/PSD normalization remains the responsibility of the scientific workflow unless a future generic contract defines it explicitly.

### `detrend(values, options)`

Generic detrending with `method=none|mean|linear`. Linear detrending uses sample index as the independent coordinate. Returns detrended `values`, removed `trend`, method and sample count. No samples are silently omitted.

### `window(name, length, options)`

Generates reusable weighting windows. Current names are `rectangular`, `hann`, `hamming`, `blackman`, `blackman_harris`, and `flat_top`. `sampling=symmetric` is the default; `periodic` is available explicitly. Returns window `values`, `power_sum`, `coherent_gain`, `rms_gain`, and equivalent noise bandwidth in bins.

These primitives are mathematical services only. Welch averaging, cross-spectrum/H1/H2/coherence semantics, cepstral interpretation and amplitude/PSD reporting stay in their analysis modules.

### `matrix_statistics(values, options)`

Octave binding for finite real matrices. `options.dimension=1|2` selects the
column or row reduction (`1` by default). Returns `n`, `mean`, `median`,
population and sample variance/standard deviation, `min`, and `max` with
the reduced dimension retained. Sample variance and deviation are `NaN` when
only one value exists along that dimension. Input values must be finite.

### `reduce_summary(values, options)` / `reduce_accumulate(state, values)`

Octave bindings for finite real data. `reduce_summary` returns `count`, `sum`,
`mean`, `min`, and `max` without sorting or computing quantiles. A vector is
reduced to scalars unless `options.dimension=1|2` is supplied; matrices require
the desired dimension for row or column aggregation. `reduce_accumulate`
combines successive vector chunks into a scalar summary; pass `[]` initially.
Both operations require nonempty chunks and reject nonfinite values. This
contract supports streaming timing checks and peak/mean display reduction
without invoking the more expensive descriptive-statistics operation.

### `configure_fft_threads(count)`

Octave binding for a positive integer internal-thread recommendation. It
returns the requested count, whether the setting was applied, and the backend
name. The backend may decline thread configuration; the FFT result is
unaffected. Consumers should obtain the recommendation from CORE Parallel
Execution and pass it through this public numerical operation.

## 4. Interpolation, resampling and splines

### `interpolate(x, y, xq, options)` / `interpolate`

Methods: `nearest`, `linear` (default), `cubic`, `spline`, `pchip`. `cubic`, `spline` and `pchip` require at least three valid source points. Extrapolation: `error` (default), `nan`, `nearest`, `linear`, `method`.

Returns `xq`, `yq`, `method`, `extrapolation`, `n_source`, `n_query`.

Tcl: `::GX::NumericAPIv1::interpolate x y xq ?options?`.

### `resample(x, y, target_x, options)`

Resamples explicitly onto an arbitrary target grid using the interpolation contract. Returns `x`, `y`, `grid_kind=explicit` and interpolation metadata.

Tcl: `resample`.

### `resample_uniform(x, y, step, options)`

Creates a uniform grid between `start`/`stop` (defaults to source endpoints) and resamples onto it. `step` must be finite and positive. Returns `x`, `y`, `step`, requested/actual range, counts and interpolation metadata.

Tcl: `resampleUniform`.

### `spline_create(x, y, options)`

`options.method` is `spline` or `pchip`. Returns a portable piecewise-polynomial model containing `breaks`, `coefficients`, `pieces`, `order`, `dimension`, range and method.

Tcl: `splineCreate`.

### `spline_evaluate(model, xq, options)`

Evaluates a model returned by `spline_create`. `derivative_order` defaults to `0`. Extrapolation is `error`, `nan`, or `method`. Returns `values` and evaluation metadata.

Tcl: `splineEvaluate`.

### `spline_integral(model, a, b, options)`

Analytically integrates the piecewise-polynomial representation between `a` and `b`. Default behavior rejects bounds outside the model range; `extrapolation=method` explicitly permits polynomial continuation.

Tcl: `splineIntegral`.

## 4A. Generic vector normalization and similarity

### `vector_normalize(values, options)`

Normalizes a finite real vector. `options.method` is `unit_vector` or `mean_center_unit_vector`. Returns normalized `values`, the applied Euclidean `norm`, the removed `center`, sample count `n`, and `method`. Zero-norm vectors are rejected. Tcl name: `normalizeVector`.

### `vector_similarity(a, b, options)`

Computes a reusable vector similarity without assigning any domain interpretation. `options.method` is `cosine`, `pearson`, `angular_similarity`, or `normalized_residual`. Returns `score`, the underlying cosine value, sample count `n`, and `method`. Pearson mean-centers both vectors; angular similarity maps the vector angle to `1 - angle/pi`; normalized residual uses `1/(1 + sqrt(sum((a-b)^2)/sum(a^2)))`. Equal-length finite vectors are required and zero-norm inputs are rejected. Tcl name: `vectorSimilarity`.

These are mathematical primitives only. A spectroscopy, signal-processing, or other scientific module remains responsible for deciding which method is scientifically meaningful, how scores are combined, and how thresholds are interpreted.

## 5. Numerical calculus, grid and range

### `integrate(x, y, options)`

Composite trapezoidal integration using actual X coordinates. Returns scalar `value`, range and method.

### `cumulative_integrate(x, y, options)`

Cumulative trapezoidal integral aligned with X. Returns `x`, `integral`.

### `differentiate(x, y, options)`

Numerical derivative using Octave `gradient(y,x)`, therefore supporting non-uniform strictly increasing X. Returns `x`, `dy_dx`.

### `grid_info(x, options)`

Returns `uniform`, nominal `step` (median step), mean/median/min/max/std of steps, direction, monotonic/strict flags, duplicate count, maximum step deviation and tolerances. `rtol=1e-9`, `atol=0` by default.

### `validate_monotonic(x, options)`

Returns monotonicity/direction/duplicate diagnostics without transforming X.

### `uniform_grid(start, stop, spacing, options)`

`mode=step` (default): `spacing` is positive step. `mode=count`: `spacing` is positive integer point count. Returns grid and actual step/range.

### `common_range(x1, x2, options)`

Returns overlap flag, common min/max/width and each source range.

Tcl names: `integrate`, `cumulativeIntegrate`, `differentiate`, `gridInfo`, `validateMonotonic`, `uniformGrid`, `commonRange`.

## 6. Statistics

### `statistics(values, options)`

Returns count, min/max/range, sum, mean, median, Q25/Q75/IQR, population/sample variance and standard deviation, RMS. Quartiles use Hyndman-Fan type 7 linear interpolation.

Presentation/publication consumers can adapt the captured Numeric result through
CORE `STATISTICAL_RESULT_SEMANTICS_API_v1`, then call `numeric_fields` (Tcl:
`::GX::StatisticsV1::numericFields`). It exposes validated source-field meanings,
statuses and units, including squared variance units and undefined sample
dispersion. `numeric_field_map` discovers aliases only; it does not establish
availability. Both operations perform no numerical computation.

The Tcl host adapter `statisticsResponsive values ?options? ?progress_command?`
executes this same worker through CORE Parallel Execution while servicing the
event loop. It accepts at most 65,536 values; bulk consumers should use Dataset
or managed-resource operations. The advisory progress callback receives the
standard CORE event dictionary, including `run_id`; it may request
`parallelExecutionCancel`. Cancellation raises `GXTXT NUMERIC CANCELLED`.
Worker request/response files and coordinator state are released on completion,
failure or cancellation. This host scheduling adapter adds no calculation or
new Script Bridge operation; Python/Octave Jobs use the existing `statistics`.

### `residual_metrics(observed, predicted, options)`

Returns count, sum of squared errors (SSE), RMSE, MAE, maximum absolute error, R², maximum relative error and RMS relative error for equal finite real vectors. `relative_floor` is non-negative (default 0); zero observed values and observations below the floor are excluded only from relative metrics. R² is `NaN` for fewer than two observations or zero observed variance. Relative metrics are `NaN` if no observation qualifies. This operation uses linear reductions without sorting or creating quantiles. Tcl name: `residualMetrics`.

### `quantiles(values, probabilities, options)`

Probabilities must lie in `[0,1]`. Returns `probabilities`, `quantiles`, count and definition.

### `weighted_quantiles(values, weights, probabilities, options)`

Computes arbitrary weighted empirical-CDF inverse quantiles after applying the normal public non-finite and positive-weight policy. Probabilities must be in `[0,1]`. Returns `probabilities`, `quantiles`, `n_total`, `n_positive`, `sum_weights`, and the documented weighted-quantile definition.

### `cumulative_sum(values, options)`

Computes the ordinary cumulative sum of a finite real vector. Returns `values`, final `total`, count `n`, and `method=cumulative_sum`. This is a generic vector reduction and carries no probability, spectrum, integration, or physical-unit semantics by itself.

### `weighted_statistics(values, weights, options)`

Returns positive-weight count, sum of weights, effective sample size, min/max/range, weighted sum/mean/RMS, weighted empirical-CDF median/quartiles/IQR, population weighted variance and reliability-weight unbiased variance where defined.

Tcl names: `statistics`, `quantiles`, `weightedQuantiles`, `cumulativeSum`, `weightedStatistics`.

## 7. Linear least squares and regression

### `least_squares(design, response, weights, options)`

General design-matrix OLS/WLS. `weights=[]` means ordinary LS. `rank_policy=error` (default) rejects rank deficiency; `minimum_norm` explicitly requests a pseudoinverse solution. `has_intercept` controls whether adjusted R² is reported as meaningful.

Result includes coefficients, predicted values, residuals, weighted residuals, SSE/RSS, objective-space `rmse`, unweighted `residual_rmse`, R², adjusted R² where meaningful, degrees of freedom, covariance, standard errors, singular values, rank, condition number, `weight_semantics`, covariance scaling, reduced chi-square where applicable, and status metadata.

Tcl: `leastSquares design response ?weights? ?options?`.

### `linear_regression(x, y, weights, options)`

Convenience wrapper over the same LS foundation. `intercept=true` by default.
The operation catalog's `has_intercept` option is an equivalent spelling here;
conflicting values reject. This differs from general design-matrix LS, where
`has_intercept` describes the caller's design rather than adding a column.
Adds `slope`, `intercept`, `intercept_included`, X and Y. Through-origin fits retain
only the estimated slope in their parameter vector. Catalog calls preserve the
empty weights position when options are supplied without weights (also for
general LS and polynomial fitting). Existing direct call signatures are unchanged.

Tcl: `linearRegression`.

## 8. Polynomial fitting

### `polynomial_fit(x, y, degree, weights, options)`

`degree` is any non-negative integer with enough valid observations. Weighted and unweighted fits share the LS foundation. `center_scale=true` by default improves conditioning by solving in a centered/scaled coordinate and transforming coefficients/covariance back to the original X polynomial basis.

Result includes original-basis `coefficients` in descending powers, `scaled_coefficients`, degree, scaling metadata, fitted values, residuals, SSE/RSS/RMSE/R²/adjusted R², covariance, standard errors, rank, singular values and condition number.

Tcl: `polynomialFit x y degree ?weights? ?options?`.

### `polynomial_evaluate(model, xq, options)`

Evaluates a model returned by `polynomial_fit`, using scaled coefficients when present. Returns `xq`, `yq`, degree.

Tcl: `polynomialEvaluate`.

## 9. Generic nonlinear least squares

### `nonlinear_fit(model_fun, X, Y, initial_parameters, options)` — Octave binding and Script Bridge

The callback contract is:

```octave
yhat = model_fun(parameters, X)
```

X may be a vector or predictor matrix with one row per observation. Options may contain `weights` or positive `sigma`, `lower_bounds`, `upper_bounds`, `solver=auto|lsqnonlin|fminsearch`, `max_iterations`, `tolerance`, `bounded_fminsearch=reject|penalty_clip`, and `fallback_on_solver_error=true|false`.

`auto` uses `lsqnonlin` when the Octave `optim` package is available; otherwise it selects `fminsearch`. By default finite bounds require `lsqnonlin`/`optim`. The explicit `bounded_fminsearch=penalty_clip` option enables the legacy scaled, clipped, quadratic-penalty search for models that require a bounded fallback. It minimizes the weighted residual norm, clamps the final parameter vector to the bounds, and reports the final residual SSE. `fallback_on_solver_error=true` permits `auto` to retry with this fallback after a `lsqnonlin` error. Consumers must request these options explicitly; the existing default remains strict.

Result contains parameters, predicted values, residuals, weighted residuals, objective/SSE, objective-space `rmse`, unweighted `residual_rmse`, R²/adjusted R², convergence/exit information, iterations/evaluations where available, Jacobian, covariance/standard errors when mathematically supportable, rank, condition number, `weight_semantics`, covariance scaling and reduced chi-square for absolute inverse-variance weights. Solver non-convergence is returned as `converged=false`; invalid inputs/model output are errors.

Direct Octave callbacks and both Script Bridge languages accept `fixed_mask`,
one boolean per parameter. Equal lower/upper bounds also fix that parameter.
The supplied initial value must lie within its bounds, including fixed values.
Optimization uses only free coordinates; the callback always receives the full
original parameter vector. Returned `parameters`, `fixed_mask`, `active_bounds`,
Jacobian and covariance retain that original order and size. Fixed Jacobian
columns and available covariance rows/columns are zero; fixed values are not
treated as active free bounds. `p` is the full count, `free_parameter_count` is
the number optimized, rank is the free-subspace rank and DOF is `n - rank`.

Live registered `nonlinear_evaluate` uses the same optional fixed mask and equal
bounds. Its full-order prediction Jacobian leaves fixed columns zero without
perturbing those constants. It returns the effective `fixed_mask` and
`free_parameter_count`; absent masks preserve ordinary all-free evaluation.

All-fixed requests call the model once, use `solver=fixed_evaluation`, and report
zero optimizer iterations. They are evaluations with no freely estimated
parameters; CORE marks parameter inference inapplicable. Fewer observations
than total parameters are permitted when the free count is supported. Callback
fits allow 1..128 parameters and at most 512 MiB for their full dense Jacobian.
Rank deficiency or an active free bound withholds ordinary covariance, including
known-sigma cases. CORE supplies role, inference eligibility and interval meaning.

Script callback fits accept `solver=auto|least_squares|scipy_least_squares`,
`method=trf|dogbox`, `max_function_evaluations` (1..2000000), three separate
`function_tolerance`, `gradient_tolerance`, `parameter_tolerance` values above
binary64 machine epsilon, and positive `parameter_scales` in physical canonical
parameter order. `tolerance` supplies the default for unspecified separate
tolerances. Legacy `max_iterations` maps to20 times that value in function
evaluations; it cannot be combined with the explicit evaluation limit. Defaults
retain `trf`,8000 function evaluations,1e-8 tolerances and unit scales. Unsupported
backend names are refused, including in all-fixed evaluation.

Callback precision input accepts either `weights` or `sigma`, never both.
Weights default to relative precision; sigma declares inverse variance.
An explicit `weight_semantics=relative|inverse_variance` accompanies weights,
so a retained absolute-precision vector can be reused without a sigma round trip.
`unweighted` is valid only for unit weights, and a declaration that contradicts
sigma or omits its required precision input is rejected.

`solver_receipt` uses `gxtxt.callback_solver_receipt.v1` with actual SciPy version,
method, termination code/message, effective settings, physical bounds/fixed/scales,
solver objective and elapsed time. Solver function evaluations exclude extra
finite-difference callback invocations; both counts are retained. `iterations=-1`
means unavailable from SciPy, while all-fixed evaluation records0. CORE validates
and reports this receipt. Rank/condition use unit-norm free Jacobian columns;
covariance is transformed back to physical parameter units. The optimizer solves scaled parameters `q=p/parameter_scales`, including mapped
initial values and bounds; `scale_convention` records the physical mapping. This
also makes active-bound tests meaningful for tiny physical intervals. Unrepresentable
scaled initial values or bounds are refused. The returned Jacobian remains the
weighted physical full-order Jacobian with zero fixed columns. Unsupported Script
callback options are refused rather than silently ignored.

Script callbacks retain their existing SciPy least-squares backend; direct Octave
callbacks retain the configured Octave solver. The declared-expression Ceres path
has its own existing fixed-mask implementation. No callback is silently translated
into a declared native expression.

## 10. Smoothing and filtering

### `smooth(x, y, options)`

Methods: `moving_mean`, `moving_median`, `savitzky_golay` (`savgol` alias), `local_polynomial`, `lowess`, and `loess`. All v1 smoothing windows are explicit positive odd integers. Savitzky-Golay requires explicit polynomial `degree` (default 2), a uniform X grid, and `sgolayfilt` from the Octave `signal` package. `local_polynomial` performs local polynomial least squares using the actual X coordinates and is therefore the corresponding generic choice for non-uniform X. Returns preserved X, smoothed Y, residuals and endpoint policy.

`lowess` defaults to local degree1; `loess` defaults to degree2. Both use the
same Numeric implementation and canonical result method `lowess`. Set `degree`
explicitly to1 or2, odd `window` between degree+3 and min(N,1001), and
`robust_iterations` from0 to10 (default2). Each source point uses its nearest
X neighbors with tricube distance weights; exact neighbor ties choose lower X.
Optional residual reweighting uses a bisquare with six times the median absolute
residual. The receipt records requested/completed reweightings, zero-weight
count, scale and endpoint policy. Nearly exact data terminate without pointless
reweighting. Insufficient robust support or local rank causes a readable refusal.
No lower-order fallback, implicit sorting, duplicate merging, extrapolation or
silent decimation occurs. See the
[LOWESS algorithm reference](https://www.statsmodels.org/stable/generated/statsmodels.nonparametric.smoothers_lowess.lowess.html).

Limits are one million retained points and50million conservative work units
`N * window * (degree+1)^2 * (robust_iterations+1)`. Unknown LOWESS settings are
refused; `window` is a neighbor count, not a fractional span. All smoothing
methods preserve one-based uint64 `source_row_positions` and
`dropped_row_positions`; `nonfinite=omit` must be explicit. `dataset_smooth`
also returns the corresponding original canonical Dataset row ordinals, units
and selection identity. These are smoothing outputs, not fitted model parameter
inference; smoothing induces correlations which must be accounted for by any
subsequent inferential procedure.


Tcl: `smooth`.

### `digital_filter(y, b, a, options)`

Generic causal difference-equation filtering through Octave `filter`. `b` and `a` are caller-supplied FIR/IIR coefficients; zero initial state is explicit in the result. This API does not design low/high/band filters and does not duplicate signal-analysis workflows.

Tcl: `digitalFilter`.

## 11. Peak primitives

### `find_peaks(x, y, options)`

Generic local-maxima primitive. Options: `min_height`, `min_prominence`, `min_distance`, `distance_mode=samples|x`, `relative_height` (default `0.5`). Returns 1-based sample indices, peak X, heights, prominences, widths and left/right width crossings. Distance suppression keeps higher peaks first. No peak identity or chromatography-specific integration is performed.

Tcl: `findPeaks`.

## 12. Baseline primitives

### `baseline(x, y, anchor_x, anchor_y, options)`

Methods:

- `constant`: explicit `value`, or `estimator=mean|median`;
- `linear`: degree-1 polynomial LS;
- `polynomial`: `degree=N`;
- `asls`: second-difference asymmetric least squares; see the explicit contract below;
- `anchors`: interpolated anchor points, with `anchor_method=linear|pchip|spline` and explicit extrapolation policy.

Returns `baseline` and `corrected` separately plus method/degree/coefficients where applicable.

Tcl provides `baseline x y options` for constant/linear/polynomial and `baselineAnchored x y anchorX anchorY options` for anchors.

Python and Octave Script Bridge expose `baseline` with
`[x, y, options]` (or the full five-argument anchor form), and `dataset_baseline`
with `[dataset_id, x_variable_id, y_variable_id, options]`. The direct Octave
five-argument signature is preserved; the three-argument options form is additive.

AsLS minimizes the asymmetric response-square penalty plus `lambda * ||D2 b||²`.
At each iteration the weight is `p` where `y > b`, otherwise `1-p`, including
ties. These are algorithm weights, **not measurement precision**. The compiled
sparse QR solver uses the augmented system, avoiding normal equations. Defaults:
`lambda=1e5`, `p=0.01`, `max_iterations=50`, `tolerance=1e-6`; bounds are
`0 < lambda <= 1e16`, `1e-8 <= p <= 1-1e-8`, 1..500 iterations, and tolerance
in [0,1). The iteration receipt reports relative weight change, weights actually
used by the returned solve, history, and honest `converged` status. Numerical
convergence does not establish a scientifically correct baseline: inspect peaks
and vary lambda/p. Positive peaks typically require p below 0.5; above 0.5 targets
negative peaks. Lambda depends on sample density; it has no sampling-invariant
physical interpretation. Maximum selected length is 2,000,000.

`grid_policy=uniform_x` requires strictly monotone, unique, approximately equally
spaced X (either direction). The tolerance is max(1e-8 times the step magnitude,
min(64 ulps at the largest coordinate magnitude, 1e-4 times the step magnitude)).
This cap prevents a large coordinate offset from hiding substantial irregularity.
The effective tolerance is captured. `sample_index`
explicitly applies the penalty to consecutive selected rows on an irregular grid.
No sorting, averaging, resampling or duplicate merging occurs. `nonfinite=omit`
explicitly removes nonfinite X/Y pairs; uniform spacing is checked **after** that
selection, so an irregular gap rejects unless sample-index treatment was requested.

All baseline methods add `original_x`/`original_y` with their input dtypes,
one-based `source_row_positions`,
`dropped_row_positions`, counts, row order and nonfinite policy; each output vector
has the selected length. Dataset calls also return exact one-based uint64
`source_row_ordinals`/`dropped_row_ordinals`. These positional conventions differ
from Dataset Transform's zero-based source ordinal column. No input is overwritten.
Integer array inputs outside the exact binary64 range reject; make any intended
scientific conversion explicit. Estimation itself uses binary64.
The baseline is a preprocessing estimate; its uncertainty and induced correlations
are not propagated. Downstream fits must supply the public CORE
`context.baseline_correction` receipt and retain its applicability decisions.
Generic Dataset Transform's `baseline_correct` publishes separate columns and
preserves all selected original rows, including explicit NaNs at omitted positions.

Scientific formulation: [Whittaker/AsLS documentation](https://pybaselines.readthedocs.io/en/latest/algorithms/whittaker.html).

## 13. Root finding and optimization — Octave binding and Script Bridge

### `root_find(fun, bracket_or_initial, options)`

Uses `fzero`. Returns root, function value, convergence/exit flag and iteration/evaluation diagnostics.

### `minimize_1d(fun, [lower upper], options)`

Uses `fminbnd`. Returns optimum, objective and convergence diagnostics.

### `minimize(fun, initial_vector, options)`

Uses unbounded `fminsearch`. Returns optimum vector, objective and convergence diagnostics.

Direct Octave calls accept function handles. Registered Octave and Python scripts pass execution-scoped handles through [Script Callback API v1](../../../docs/api/SCRIPT_CALLBACK_API_v1.md). The provider invokes them in the originating script runtime.

## 14. Uncertainty propagation

### `propagate_uncertainty(J, uncertainty, options)`

First-order linear propagation `C_y = J C_x J^T`. `input_kind=standard_uncertainty` accepts a standard-uncertainty vector and constructs a diagonal covariance; `input_kind=covariance` accepts the full covariance matrix. Returns output covariance and standard uncertainties, with `input_kind`, positive `input_count`, `output_count` and `method=first_order_linear_propagation`. The same operation is registered for Python/Octave Script Jobs and the generic Tcl operation catalog. Interpret the result with CORE `math.numeric.propagation`, explicit output IDs/units and optional one-based output index; raw uncertainties do not imply a confidence level.

Tcl: `propagateIndependentUncertainty`, `propagateCovariance`.

## 15. Dataset-aware operations

Script Bridge exposes `dataset_statistics`, `dataset_weighted_statistics` and
`dataset_polynomial_fit` with an implicit current Session. The accepted
`statistics_dataset` spelling remains supported. Typed `callOperation` and
`callModelOperation` resolve `selection_id` before invoking the Octave worker.
Declared-model and registered-callback Script Bridge nonlinear fits share the
same resolver. Both use inclusive, order-independent interval bounds and reject
mismatched fit/Selection Variable identities. The result preserves the selected
resource ID; it is not a frozen copy of the Selection resource.

All forms below read through Table Stream v3 and resolve stable variable identities. Tcl Dataset calls accept `selection_id` and resolve it through Dataset Selection API v1 before execution. Direct Octave Dataset calls accept the corresponding Dataset Selection v1 structure in `options.selection`; callback-bearing `dataset_nonlinear_fit` therefore remains usable without a private registry dependency. Units are reported, never converted.

| Operation | Octave dispatcher operation | Tcl facade | Notes |
|---|---|---|---|
| integration | `dataset_integrate` | `integrateDataset` | reports Y*X result unit |
| cumulative integration | `dataset_cumulative_integrate` | `cumulativeIntegrateDataset` | aligned vector |
| differentiation | `dataset_differentiate` | `differentiateDataset` | reports Y/X result unit |
| interpolation | `dataset_interpolate` | `interpolateDataset` | explicit target X |
| arbitrary resampling | `dataset_resample` | `resampleExplicitDataset` | explicit target X |
| uniform resampling | `dataset_resample_uniform` | `resampleUniformDataset` | step-based |
| legacy uniform resampling | `dataset_resample_uniform` by default | `resampleDataset` | preserved Tcl name; scalar fifth argument is a step; `grid=explicit` selects arbitrary target X |
| statistics | `dataset_statistics` | `statisticsDataset` | one variable |
| weighted statistics | `dataset_weighted_statistics` | `weightedStatisticsDataset` | data + weight variable |
| grid analysis | `dataset_grid_info` | `gridInfoDataset` | coordinate variable |
| polynomial fit | `dataset_polynomial_fit` | `polynomialFitDataset` | optional `weight_variable_id` in options |
| nonlinear fit | `dataset_nonlinear_fit` | Octave binding and Script Bridge | callback-bearing; optional `weight_variable_id` and `selection_id` in scripts |
| smoothing | `dataset_smooth` | `smoothDataset` | X/Y variables |
| peaks | `dataset_find_peaks` | `findPeaksDataset` | X/Y variables |
| baseline | `dataset_baseline` | `baselineDataset` | constant/linear/polynomial; anchor mode remains low-level |

Dataset operation options may include `selection_id` in Tcl and `chunk_rows`. A Selection must belong to the requested dataset and have compatible X/Y variable identity. Direct Octave signatures follow the dispatcher pattern `gxtxt_numeric_v1(operation, session, dataset_id, ...stable variable ids..., options)`. `dataset_interpolate`/`dataset_resample` additionally receive the target X vector; `dataset_resample_uniform` receives a scalar step; `dataset_polynomial_fit` receives degree; `dataset_nonlinear_fit` receives `model_fun` and initial parameters.

## 16. Errors and edge cases

- Empty inputs are rejected except empty query grids, where an empty output is meaningful.
- One/two-point behavior is operation-specific; e.g. statistics accepts one value, linear interpolation/integration need two, cubic/spline/PCHIP need at least three, peak finding may return zero peaks.
- Mismatched vector lengths/dimensions are errors.
- NaN/Inf default to error; `nonfinite=omit` must be explicit where supported.
- Duplicate/non-monotonic coordinates are errors for coordinate-ordered curve operations.
- Extrapolation defaults to error and must be explicitly enabled.
- Invalid/negative weights are errors; zero weights are discarded; all-zero weights are an error. Fit covariance interpretation is explicit through `weight_semantics=relative|inverse_variance`; nonlinear `sigma` selects inverse-variance semantics automatically.
- Underdetermined polynomial/LS fits are errors. Rank deficiency defaults to error unless `rank_policy=minimum_norm` is explicit.
- Nonlinear solver failure is a structured result with `converged=false`; invalid model output/bounds are errors.
- Filtering rejects non-finite signal/coefficients because implicit omission would alter sample alignment.

## 17. Examples

### Polynomial degree chosen by caller

```octave
r = gxtxt_numeric_v1('polynomial_fit', x, y, 4, [], struct());
yq = gxtxt_numeric_v1('polynomial_evaluate', r, xq, struct());
```

### Weighted polynomial fit

```octave
r = gxtxt_numeric_v1('polynomial_fit', x, y, 2, weights, struct());
```

### Nonlinear least squares

```octave
model = @(p,x) p(1).*exp(p(2).*x);
r = gxtxt_numeric_v1('nonlinear_fit', model, x, y, [1; -1], struct('sigma',sigma));
```

### Cubic spline and PCHIP

```octave
s1 = gxtxt_numeric_v1('spline_create', x, y, struct('method','spline'));
y1 = gxtxt_numeric_v1('spline_evaluate', s1, xq, struct());
s2 = gxtxt_numeric_v1('spline_create', x, y, struct('method','pchip'));
y2 = gxtxt_numeric_v1('spline_evaluate', s2, xq, struct());
```

### Smoothing

```octave
s = gxtxt_numeric_v1('smooth', x, y, struct('method','savitzky_golay','window',9,'degree',3));
```

A runnable version is in `examples/numeric_api_examples.m`.

### Dataset resampling

```tcl
set r [::GX::NumericAPIv1::resampleUniformDataset $session ds_001 v_time v_signal 0.001 \
    [dict create method pchip]]
```

### Dataset integration over a Selection

```tcl
set r [::GX::NumericAPIv1::integrateDataset $session ds_001 v_time v_signal \
    [dict create selection_id sel_003]]
```

### Dataset differentiation

```tcl
set r [::GX::NumericAPIv1::differentiateDataset $session ds_001 v_time v_signal]
```

### Statistics over a Selection

```tcl
set r [::GX::NumericAPIv1::statisticsDataset $session ds_001 v_signal \
    [dict create selection_id sel_003]]
```

### Baseline and corrected signal

```octave
r = gxtxt_numeric_v1('baseline', x, y, [], [], struct('method','polynomial','degree',2));
base = r.baseline;
corrected = r.corrected;
```

### Peak detection

```octave
p = gxtxt_numeric_v1('find_peaks', x, corrected, struct('min_prominence',0.02,'min_distance',0.1,'distance_mode','x'));
```

### Root finding

```octave
r = gxtxt_numeric_v1('root_find', @(z) z.^2-2, [0 2], struct());
```

## 18. Persistence

`math.numeric` returns numerical results; it does not create a parallel Dataset/storage subsystem. A scientific module that needs persistent derived data publishes through the existing GX-TXT Dataset Publication mechanisms.

## 19. Deliberate v1 boundaries

A smoothing-spline constructor is not part of v1 because it is not available as a dependable base-Octave primitive in the expected GX-TXT numerical stack; adding one later can be additive through the existing method/options/result pattern. Filter-design workflows are also intentionally excluded: v1 filters already-designed FIR/IIR coefficients but does not become a signal-analysis subsystem. The API owns generic FFT/IFFT and transform helpers, while scientific spectrum workflows remain in analysis modules such as `analysis.fft_spectrum`, Welch, cepstrum and cross-spectral transfer.

The API is designed so new interpolation/smoothing/baseline methods can be added through method names and additive result fields without changing established signatures. Existing callers must ignore unknown additive result fields.

## Hypothesis-test primitives (Octave binding)

`gxtxt_numeric_v1('student_t_quantile', probability, degrees_of_freedom)` returns a scalar `values` field for confidence intervals. `gxtxt_numeric_v1('hypothesis_test', method, x, y, options)` supports `one_sample_t`, `independent_t`, `welch_t`, `paired_t`, `mann_whitney`, and `signed_rank`. Use `[]` for `y` in the one-sample test. Options are `mu0` (default 0), `alternative=two_sided|greater|less`, `confidence` (default 0.95), and `nonfinite=error|omit`.

Results include the method, statistic, degrees of freedom where defined, input and valid sample counts, p-value, alternative, confidence, estimate, confidence bounds/status, effect size/name, missing-data policy, and exact/approximation method. T-test confidence intervals describe the tested mean or mean difference. Rank-test confidence intervals are reported as undefined. Mann-Whitney and signed-rank p-values use exact conditional enumeration for at most 20 pooled or nonzero paired observations, respectively, including ties; larger samples use a tie-corrected normal approximation with continuity correction. These operations are currently Octave-only and are discoverable as such in the public operation catalog.

### One-way ANOVA (Octave binding)

`gxtxt_numeric_v1('one_way_anova', values, groups, options)` accepts numeric or text group labels and `method=ordinary|welch`, `nonfinite=error|omit`. It returns first-seen group names, counts, means, sample variances and standard deviations, observation counts, sums of squares, degrees of freedom, F and p-value. Ordinary ANOVA returns eta-squared and omega-squared when defined. Welch ANOVA requires at least two observations and positive variance per group; its ordinary-ANOVA effect sizes are reported as undefined. This operation is Octave-only and appears in the public catalog with that binding availability.

## Octave Script Bridge

Bridge API ID: `NUMERIC_API_v1`. The API-owned script binding registers
`array_unary`, `array_binary`, `array_compare`, `array_mask`, `array_select`,
`array_where`, `array_reduce`, and `statistics_dataset`.

`array_unary` and `array_reduce` accept `{operation_name, operand_struct,
optional_options_struct}`. `array_binary` and `array_compare` accept
`{operation_name, left_operand_struct, right_operand_struct,
optional_options_struct}`. `array_mask` accepts `{operation_name,
first_operand_struct, optional_second_operand_struct}`. `array_select`
accepts `{values_operand_struct, mask_operand_struct}` and `array_where`
accepts `{mask_operand_struct, true_operand_struct, false_operand_struct}`.
An operand struct has `kind=scalar|vector|matrix` and a numeric `value`.
These operations return the existing public numerical result fields as a
struct, with numerical `values` transported as an Octave array.

`statistics_dataset` accepts `{dataset_id, variable_id,
optional_options_struct}` and returns the public statistics result struct;
the bridge supplies the current Session. All operation and option names obey
NUMERIC_API v1 semantics.

```octave
a = struct('kind', 'vector', 'value', [1; 2; 3]);
b = struct('kind', 'scalar', 'value', 4);
r = gxtxt_api_call('NUMERIC_API_v1', 'array_binary', {'multiply', a, b});
```

<a id="mathematical-foundation-extension-mathnumeric-1130"></a>
## Mathematical foundation

`gxtxt_numeric_v1('foundation',family,action,a,b,c,options)` adds the raw mathematical primitives used by the signal, RF and magnetic providers. The Tcl binding is `::GX::NumericAPIv1::foundation family action a b c ?options?`; the provider-owned Script Bridge operation is `foundation` with arguments `{family,action,a,b,c,options}`. Tcl/Bridge operands use explicit typed nodes (`kind=array|cell|struct|text|empty`) with column-major shape and split real/imaginary arrays, as documented by the scientific provider transport. `::GX::NumericAPIv1::listOperations` includes the foundation operation. Direct Octave accepts ordinary numeric arrays, cells and structs.

| Family | Actions and signature meaning | Contract |
|---|---|---|
| `vector` | `dot`, `cross`, `norm`, `normalize`, `outer`, `projection`, `angle`, `triple`, `contract`; `a`, `b`, `c` vectors | Complex Hermitian dot and norm; ordinary geometric cross/triple; zero normalization/projection basis fails. Angle is real in radians. |
| `tensor` | `transpose`, `conjugate_transpose`, `trace`, `symmetric_part`, `antisymmetric_part`, `contract`, `apply`, `outer`; rank-2 matrix and optional second operand | Frobenius/Hermitian contraction, matrix-vector application and vector outer product. |
| `grid` | `interpolate`, `sample`, `compatible`, `resample`; `a` cell of 2/3 increasing coordinate vectors, `b` field array, `c` queries/target axes | Regular 2D/3D nearest/linear interpolation. Extrapolation is explicit: `error` (default), `nan`, or boundary-clamped `nearest`. `compatible` accepts `atol`/`rtol`. |
| `scattered` | `interpolate`; `a=N×2` or `N×3` points, `b=N` values, `c=M×D` queries | Octave Delaunay-based nearest/linear spatial interpolation. Out-of-hull policy is explicit. Degenerate point clouds can fail at the backend. |
| `family` | `align`, `surface`, `derivative`, `extrema`, `envelope`, `parameter_interpolate`; cells of member coordinates and values or a parameter axis and aligned matrix | Align sampled families on an explicit common coordinate grid, derive per-member gradients/extrema/envelopes, and interpolate across a declared parameter axis. The result matrix uses one column per member; no Dataset identity is synthesized. |
| `calculus` | `integrate2`, `integrate3`, `weighted_integral`, `line_integral`, `line_scalar_integral`, `surface_flux`, `surface_integral`, `gradient_grid`, `gradient`, `jacobian`, `hessian`, `directional` | Coordinate-aware trapezoidal grid integration; vector/scalar path and oriented triangular-face integration; finite differences on nonuniform grids; function-handle derivatives in direct Octave. Grid derivative boundary policy is `one_sided` (default) or `nan`. |
| `ode` | `solve`; `a=RHS(t,y)` function handle, `b` time interval or requested output times, `c` initial state | Direct Octave adaptive `ode45` for non-stiff or `ode23s`/`ode15s` for stiff scalar/vector first-order systems. `method=stiff` selects the stiff backend; `events` is an Octave event callback and `dense_times` requests interpolated solver output. Options `reltol`, `abstol`, `max_step`, and optional `progress(fraction,t,y)`/`cancel(t,y)` callbacks; results include time, split state, output count, success and cancellation status. |
| `constrained` | `solve`; objective handle, initial point, constraints struct | Direct Octave SQP or `method=derivative_free` penalty search with lower/upper bounds, linear equalities/inequalities, optional nonlinear callback, convergence and active-constraint diagnostics. Constraints use `Aeq*x=beq`, `A*x<=b`; nonlinear callback returns equality and nonnegative inequality functions. Results include backend multipliers, numerical KKT multipliers, stationarity, complementarity and dual-violation residuals. |
| `special` | `erf`, `erfc`, `gamma`, `log_gamma`, `beta`, `incomplete_gamma`, `incomplete_beta`, `bessel_j`, `bessel_y`, `bessel_i`, `bessel_k`, `spherical_bessel_j`, `spherical_bessel_y`, `airy`, `exponential_integral`, `sinc` | Real finite input, split output. Incomplete gamma uses `tail=lower|upper`; incomplete beta uses the second shape in `b` and `third_shape` in options. Poles/nonfinite results fail. |

The Tcl facade remains data-only. Callback-bearing `equations` and `variational` actions are direct Octave operations; data-only geometry, sparse, statistics and special actions use the existing typed Tcl/Bridge foundation path. The provider-owned Script Bridge binding accepts execution-scoped callback handles for `ode/solve`, `constrained/solve` and callable `calculus` derivatives. The callback-bearing script path uses SciPy RK45/SLSQP and finite differences; direct Octave uses its existing `ode45`/`sqp` backend. Both expose the same documented input/result fields, while method and solver status values identify the backend. Script nonlinear constraints return one struct with `equality` and `inequality` fields. Units are caller-owned except that integration multiplies coordinate units and derivatives divide by them; no implicit unit conversion occurs. Empty, invalid shape, nonfinite, singular or unsupported policy inputs produce `GXTXT:Numeric:*` errors. Explicit parallel workers are not created.

```octave
r=gxtxt_numeric_v1('foundation','grid','interpolate',{[0;1],[0;1]},[0 1;1 2],[0.25 0.75],struct());
assert(abs(r.value_real-1)<1e-12);
```

```python
from gxtxt import gxtxt_api_require, gxtxt_api_call
gxtxt_api_require('NUMERIC_API_v1@1:math.numeric+mathematical_foundation')
a={'kind':'array','shape':[2,1],'real':[1,2]}
b={'kind':'array','shape':[2,1],'real':[3,4]}
r=gxtxt_api_call('NUMERIC_API_v1','foundation',['vector','dot',a,b,{'kind':'empty'}])
```

```octave
gxtxt_api_require('NUMERIC_API_v1@1:math.numeric+mathematical_foundation');
a=struct('kind','array','shape',[2 1],'real',[1 2]);
b=struct('kind','array','shape',[2 1],'real',[3 4]);
r=gxtxt_api_call('NUMERIC_API_v1','foundation',{'vector','dot',a,b,struct('kind','empty')});
```

<a id="p1p2-foundation-actions-mathnumeric-1130"></a>
## Advanced foundation actions

All rows use `gxtxt_numeric_v1('foundation',family,action,a,b,c,options)`. Public Tcl and Script Bridge retain the same `foundation` entry; typed nodes are required there. Callback handles for the new equation and variational rows require direct Octave. The full operation and result schemas are in `api/octave/gxtxt_numeric_advanced_v1.m`; `api/operations_v1.tsv` lists `foundation` as the stable public operation.

| Family | Actions | Inputs and output |
|---|---|---|
| `geometry` | `plane_frame`, `plane_three_points`, `centroid`, `plane_offset`, `plane_flip`, `plane_orient`, `trajectory_tangent`, `plane_containing_tangent`, `trajectory_plane_intersections`, `frame_transform` | Explicit XYZ, orthonormal U/V/N frame, one-based source row and deterministic intersection fractions. Degenerate frames fail. |
| `geometry` | `nearest`, `kdtree_query`, `point_segment_distance`, `point_triangle_distance`, `point_mesh_distance`, `triangle_area`, `tetrahedron_volume`, `mesh_surface_area`, `mesh_volume`, `barycentric`, `plane_fit`, `line_fit`, `rigid_transform` | Numeric arrays of points/connectivity. Distances and fits report coordinates or residuals; enclosed volume requires a closed manifold. |
| `geometry` | `orientation2d`, `orientation3d`, `delaunay`, `voronoi`, `mesh_section`, `volume_slice`, `mesh_smooth`, `mesh_remesh`, `mesh_boolean` | Explicit predicates/Qhull services and VTK-backed mesh processing. File-backed actions accept source path, format and optional SHA-256, and return source identity. STEP cuts tessellate through Gmsh/OpenCASCADE first. `mesh_remesh` is Loop subdivision; boolean requires closed surfaces. VTI `volume_slice` samples the actual scalar grid. |
| `sparse` | `construct`, `matvec`, `solve`, `least_squares`, `eigen_subset` | Triplets with one-based indices or sparse representation; returns values, residual norms or selected eigensystem. |
| `equations` | `solve`, `multiple_start`, `continuation` | Octave residual callback, initial states or parameter path; optional Jacobian; solutions, residual norms and convergence status. |
| `variational` | `action`, `functional`, `first_variation`, `euler_lagrange_residual`, `legendre`, `constrained` | Octave functional/Lagrangian callback, generalized coordinates and velocities; finite-difference variations/momentum/residual and quadrature. `constrained` delegates to the public constrained optimizer. |
| `statistics` | `confidence_interval`, `robust_location`, `robust_regression`, `covariance_diagnostics`, `partial_correlation`, `multiple_testing`, `bootstrap_ci`, `permutation_test`, `logistic_regression`, `glm`, `survival_kaplan_meier`, `kmeans` | Explicit sample/design data; Huber estimators, Bonferroni/Holm/BH correction, binomial/Poisson GLM, Kaplan-Meier and seeded clustering/resampling. Bootstrap/permutation need a seed and at least 100 replicates. Existing PCA remains in the statistics provider. |

`linear_matrix` adds `schur`, `logarithm`, and `square_root`. Matrix functions use the principal branch and report split complex values. Stiff ODE result `backend_method` names the solver actually used; on this Octave build, a broken Sundials `ode15s` path falls back to `ode23s`. Event termination and dense-output completion are explicit. All numerical geometry coordinates and distances remain in caller units.

<a id="reconstructible-curve-models-mathnumeric-1160-dev-051"></a>
## Reconstructible curve models

Octave dispatcher operations `curve_model_fit(model,x,y,options)`, `curve_model_evaluate(state,query)` and `curve_model_project(state,x,y)` are also available through the typed Tcl `callOperation` catalog and both Script Bridge languages. `fit` returns a data-only model struct suitable for persistence and evaluation. `evaluate` returns X, Y and paired points. Projection supports arc/Bézier and ordered parametric polynomial/spline models and returns the nearest finite-curve point, normalized parameter and geometric distance.

The public service provides `curve_model_residual(state,x,y)` for parametric geometry. It returns
nearest projected X/Y and parameter, full Euclidean distance, signed residual,
count/SSE/RMSE/MAE/maximum and an explicitly defined XY dispersion R². Positive
distance is left of the oriented tangent. At zero cross product (including
stationary tangents or tangential displacement beyond an endpoint), the distance
is nonnegative, and `zero_normal_sign_policy` states that convention. It never
reduces a geometric residual to only its Y component. Coordinates and distances
use the caller's declared coordinate metric; compatible physical units must be
provided or explicitly converted by the caller.

Geometric R² is `1 - sum(distance²) / sum((x-mean(x))²+(y-mean(y))²)`, and is NaN
for zero XY dispersion. `r2_convention` records this definition. It is distinct
from functional regression R². Parametric `curve_model_evaluate` also returns
analytic `tangent_x/tangent_y`, without finite differencing or renderer geometry.

| Model | Reconstructible state and convention |
| --- | --- |
| `circular_arc` | Center/radius, unwrapped start/end angles and orientation; query is t in [0,1]. Collinear/degenerate data fail. |
| `quadratic_bezier`, `cubic_bezier` | Ordered fixed endpoints and least-squares inner control points using uniform source-sequence t. Input order is preserved; query t is in [0,1]. |
| `pchip` | Sorted unique source knots/values, shape-preserving interpolation; no extrapolation. Duplicate X fails. |
| `smoothing_spline` | Natural cubic spline minimizing squared residuals plus lambda times integral squared second derivative. Lambda is finite/nonnegative; zero interpolates and larger values smooth more. Nonuniform X is supported; duplicate X/extrapolation fails. |
| `fourier` | DC plus cosine/sine coefficients for order N, explicit period or deterministic inferred period, origin and angular frequency. At least 2N+1 independent samples and full rank are required; no arbitrary small order cap. |
| `parametric_polynomial` | Independent least-squares X(t)/Y(t), degree 1..12, preserving source order and supplied parameterization. More independent nodes than degree are required. Closed topology is rejected; it cannot imply periodicity. |
| `parametric_spline` | Ordered natural open or genuinely periodic closed cubic interpolation of both coordinates. Closed interpolation solves a cyclic sparse curvature system and shares position, first and second derivatives at the seam. It never sorts geometry on X. |

Ordered parametric models accept `topology=open|closed|auto` (default auto) and
`parameterization=row_order|path_length|user_parameter` (default row_order).
Auto recognizes endpoints within explicit `closure_tolerance`, default
`1e-9*max(1,XY_extent)`. A closed repeated endpoint is removed from the independent
nodes and its measured distance is retained in state. Explicit closed topology
also supports an implicit final-to-first segment. Path length includes that
closing segment; zero-length consecutive segments are rejected. User parameters
must be finite, strictly monotone and aligned with every original row, including
a repeated endpoint. Decreasing parameters preserve the same supplied geometric
order. Closed user parameters without a repeated endpoint require a positive
`user_period` exceeding their span. Queries use the normalized [0,1] domain.

Parametric polynomial/spline projection evaluates all stationary-distance roots
and endpoints on eligible polynomial segments; spline control-hull bounds prune
segments without approximation. It reports full geometric distance. Large
projection query/segment scaling still needs dedicated performance validation;
bounded GUI display does not substitute for this exact scientific operation.
Spline evaluation also returns analytic `second_x/second_y` for curvature/seam
checks. Natural smoothing uses sparse difference/curvature matrices and indexed
vectorized evaluation, preserving the original nonuniform penalized objective.

Fourier uses period M*step for a uniform M-point source cycle when omitted, otherwise the training span. `options.period` overrides it. Uniform single-cycle data use the orthogonal DFT; other data use rank-checked least squares. Coefficient layout is `[DC,a1,b1,...,aN,bN]`, with phase `(x-origin)*2*pi/period`. High orders store coefficient vectors and concise model summaries rather than enormous formulas. Requested output sample count is independent of training sample count.

```octave
state = gxtxt_numeric_v1('curve_model_fit','fourier',x,y,struct('order',3,'period',1));
curve = gxtxt_numeric_v1('curve_model_evaluate',state,linspace(0,1,1000)');
```

Units remain caller-owned; model fitting does not infer physical conversions. These operations are numerical services and contain no Dataset/GUI publication lifecycle.
<a id="additive-positive-coordinate-translation-integrated-dev096-candidate"></a>
# Additive positive coordinate translation

Octave: `gxtxt_numeric_v1('positive_translation', values, options)` accepts a
complete finite real array and `{mode: auto|manual|off, delta: finite scalar}`.
Default AUTO resolves zero for strictly positive input; otherwise it adds
`-min(values) + max(realmin,32*eps(max(abs(values))))`, then verifies finiteness
and strict positivity. Manual adds its exact declared scalar; Off adds zero.
Return fields include `values`, `mode`, `delta`, `margin`, original/transformed
bounds and versioned forward/inverse formulas. Units are preserved; callers
associate the same original axis units with the scalar. This is an additive
mapping, with no fitted parameters, scaling, omission or clipping. Existing
`array_binary` operations perform the arithmetic; existing solvers are unchanged.
The operation is advertised as an Octave binding in the existing operation
catalog, without claiming a Tcl binding.

<a id="dev097-shared-transport"></a>
# shared transport

Script Bridge regression, polynomial fitting, residual metrics, polar/Cartesian
conversion and `curve_model_*` operations invoke this same public Octave owner
through the existing CORE scientific binary worker. Large arrays remain typed
resources rather than Tcl lists. Public operation names, model identities,
coefficient order and reconstruction contracts are preserved. Mathematical
validation and solver behavior remain provider-owned; numerical errors propagate
and do not silently substitute a model. See CORE
`docs/api/SCIENTIFIC_BINARY_TRANSPORT_v2.md` for resource lifetimes and counters.

<a id="dev097-additive-parameter-uncertainty"></a>
# additive parameter uncertainty

`parameter_uncertainty(plan)` consumes a public
`STATISTICAL_RESULT_SEMANTICS_API_v1/parameter_inference_plan` record. It computes
free-parameter correlation from the supplied covariance and eligible Normal or
Student-t pointwise marginal intervals, without refitting or estimating another
covariance. Return the receipt to CORE `with_parameter_uncertainty` before
reporting or publishing it. Fixed parameters are excluded; finite shape,
positive variances, covariance symmetry and positive semidefiniteness are checked.
The public Tcl convenience is `::GX::NumericAPIv1::parameterUncertainty PLAN`;
the typed `callOperation parameter_uncertainty` catalog route and both Script
Bridge languages use the same Octave implementation. Maximum 256 free parameters.
See the CORE API document for noise assumptions, unavailable states and units.


<a id="empty-descriptive-groups-dev097"></a>
### Empty descriptive groups

`statistics(values, opts)` retains its default error for no finite values.
Explicit `empty_policy=undefined` together with the requested nonfinite policy
returns zero valid count and NaN estimates after all observations were omitted.
This supports public CORE undefined-state interpretation for existing empty
groups; it never fabricates a location, variance or mean uncertainty.

<a id="hypothesis-test-interpretation-and-tail-accuracy-dev097"></a>
### Hypothesis-test interpretation and tail accuracy

`hypothesis_test` is available through the public Script Bridge in both languages
using the existing Numeric binary worker. The result adds `standard_error`,
already computed by the selected t method. Numeric retains raw degenerate
results for compatibility; use CORE `math.numeric.hypothesis` interpretation
before reporting or publication. Small t and normal tail probabilities are
evaluated directly instead of subtracting a rounded CDF from one.

<a id="existing-distribution-resampling-summary-dev097"></a>
### Existing-distribution resampling summary

`resampling_summary(distribution, observed, options)` accepts up to one million
finite real replicates and a finite scalar observed statistic. Methods are
`bootstrap`, `permutation_independent`, `permutation_paired`; defaults are
bootstrap, 0.95 confidence and two-sided alternative. Options `n_x`/`n_y` record
source counts required by CORE interpretation. Bootstrap returns type-7 percentile
endpoints and the sample standard deviation of replicates. Permutation returns
extreme count and `(count+1)/(replicates+1)` with the existing 32-ULP boundary
tolerance. It neither regenerates replicates nor computes the observed statistic.
Use `math.numeric.resampling` through CORE to interpret/publish these raw facts.
All three public Tcl/Octave/Script Bridge routes use the same Numeric operation.

The existing `mad(values, options)` operation is available in both real Script
Bridge languages as well as Tcl and Octave. It preserves its `raw` or
`normal_consistency` scaling convention. Pass its existing result to CORE
`from_numeric('math.numeric.summary', 'mad', result, context)` for reusable
median and dispersion interpretation; no second estimate is computed.

### `pca_summary(singular_values, observation_count, options)`

Summarizes an already computed descending nonnegative SVD spectrum (one to 8192
components), with integer observation count at least two. `centered` defaults
to true; false retains the explicit uncentered n-minus-one moment convention.
Returns component-indexed singular values, moments, proportions, cumulative
proportions and common dimension/method facts. Zero total moment yields NaN
proportions; negative/unordered/nonfinite magnitudes and overflow are rejected.
It does not calculate another SVD. CORE `math.numeric.pca` owns interpretation.

`matrix_svd`, `matrix_statistics`, and `pca_summary` are callable through both
Python and Octave Script Jobs via the existing Numeric worker and typed matrix
transport. Python matrix operands use NumPy arrays. Existing canonical operation
names and original Tcl/Octave routes remain intact.

<a id="declared-builtin-models-and-prediction-integrated-dev097"></a>
### Declared builtin models and prediction

The existing declarative fitting kinds `exponential`, `gaussian` and
`polynomial_fit`, plus additive `power_law` and `linear`, use the shared compiled expression
backend with the default `auto`/`ceres` solver. Their canonical parameter orders
are respectively amplitude/rate/offset, amplitude/center/width/offset,
descending `power_N` coefficients, scale/exponent and intercept/slope. Builtin formulas and
parameter identities cannot be silently overwritten; use an explicit expression
model for a different formula. The existing Tcl `callModelOperation` retains
explicit legacy solver choices for previously supported kinds.

Octave accepts `nonlinear_fit(struct('kind','exponential'),X,Y,initial,options)`.
Script Bridge retains `[X,Y,model,initial,options]`. Both return a reconstructible
`model` containing the controlled expression, ordered bindings, fitted parameters,
initial parameters, source SHA and binding SHA. A single observation with multiple
explicit predictor IDs preserves its row shape.

`nonlinear_evaluate(model,predictors,options?)` is available in Tcl's typed operation
catalog and in both Script Bridge languages, with the same argument order.
Use the returned fit's `model`, not the complete fit result. Prediction requires
finite real parameters and a nonempty real predictor matrix. Power-law inputs
must be positive; Gaussian width must be nonzero. Changed persisted expression
or binding hashes are rejected. Nonfinite intermediate expression values are
also rejected rather than silently producing a finite final value.

The default prediction path owns its output matrix and allocates no observation,
weight, residual or Jacobian arrays. It returns backend identity and scoped
adapter buffer counts. Those counts do not describe total process or transport
memory. Optional `jacobian=true` returns the physical automatic-differentiation
Jacobian and applies the existing 512 MiB Jacobian limit. The separate
`predictor_derivative=true` request returns two-sided automatic predictor derivatives
and validity masks for one predictor; request it separately from the parameter
Jacobian. With neither request, only the
prediction buffer is subject to that limit. Constant polynomial powers zero and
one retain their exact derivatives at X=0.

Exact scientific persistence must retain typed numeric state. Octave JSON can
change a binary64 parameter by an ULP and encodes infinite bounds as null; a JSON
prediction compatibility check is not proof of a lossless solver receipt. The
shared typed scientific transport remains the owner of complete replay data.

Declared fits include `solver_receipt` with schema
`gxtxt.numeric_solver_receipt.v1`. This bounded receipt records effective
settings, backend version, termination/message, convergence, Ceres iteration
records (including initial state), evaluation counts, elapsed solver time,
objective, physical scales, initial values and bounds/fixed mask. Observation
arrays remain with their input owner; the receipt alone is not a replay Dataset.
CORE `solver_report` supplies its validated human interpretation.

<a id="both-axis-uncertainty-fitting-numeric-121-integrated-dev097"></a>
### Both-axis uncertainty fitting

Use the existing declared-model `nonlinear_fit` with
`fit_geometry='orthogonal_xy'`, `sigma_x` and `sigma` (response sigma), each a
positive real column matching its coordinate. The default remains
`vertical_response`. Supplying `sigma_x` without explicit XY geometry rejects;
response weights, callbacks, multiple predictors/responses and robust losses
cannot masquerade as this measurement model. All declared scalar expressions
and builtin families use the same native Ceres solver.

The solver fits one latent predictor per observation pair and the physical model
parameters, minimizing `(delta_X/sigma_X)^2 + (delta_Y/sigma_Y)^2` summed over
pairs. Independent absolute axis uncertainties normalize units independently;
the two physical axes need not share a unit. Correlated axis/observation errors
are outside this contract. Bounds, fixed model parameters, explicit scales,
stopping controls and reproducible multistart retain their existing meaning.
The native limit is 200000 retained pairs and the existing 512 MiB returned
Jacobian cap; at most 128 model parameters are supported. Through 2048 rows the
solver uses dense QR; larger problems eliminate independent latent blocks with
dense Schur. Cancellation uses the same supervised worker ownership.

Returned `adjusted_x` and `predicted` are the fitted latent predictor and its
model response. `coordinate_corrections` is N×2, fitted minus observed in each
physical axis; `normalized_corrections` divides each component by its sigma.
`residuals` and `weighted_residuals` are the same unsigned normalized XY norm.
Use `nonlinear_evaluate(model, observed_X)` for a separate functional evaluation
at measured predictors. The returned projected Jacobian eliminates each latent
coordinate tangent before shared column-scaled QR/SVD covariance. Absolute-sigma
covariance is unscaled, DOF is N minus identifiable free model-parameter rank,
and ordinary response R²/physical residual RMSE are NaN. CORE gives their actual
not-applicable statuses, validates the optional
`gxtxt.numeric_orthogonal_xy_receipt.v1` solver receipt, and publishes matrix
column units/identities through `numeric_data_fields`.

`nonfinite='omit'` explicitly drops rows with nonfinite coordinates or either
sigma, retaining original input positions. Finite zero/negative sigma always
rejects. Saved model policy contains `required_measurement_input='sigma_xy'`
and bounded geometry/count metadata; replay must restore both original sigma
arrays from their source or owned resources. Full measurement arrays are never
copied into model metadata.

`dataset_nonlinear_fit` additionally accepts `sigma_x_variable_id` and
`sigma_variable_id` with XY geometry and no competing array/weight inputs.
Both columns are streamed with the same canonical Selection. This direct
Dataset route requires each sigma column to have the same declared unit as its
corresponding coordinate; mismatches reject. For other units, use the public
CORE unit conversion scale with explicit array inputs. Fitter provides paired
column scale conversion in its own Dataset adapter. The Dataset result includes
exact one-based uint64 `source_row_ordinals` and `dropped_row_ordinals`; input
`source_row_positions` remains relative to the selected input arrays. CORE
retains the four Variable identities and units in Dataset provenance.

CORE parameter intervals use local linearization, even for an XY line model.
Pointwise mean/future-response intervals condition on a fixed true query
coordinate; they do not propagate uncertainty in a future measured predictor.
Future response intervals still require explicit response sigma. Polynomial
ODR uses its declared physical coefficient basis, with the captured model and
covariance; ordinary polynomial LS retains its separate centered/scaled basis.

### Native residual reductions (C API v1, Numeric 1.19)

The public `api/c/gxtxt_numeric_reductions_v1.h` is the allocation-free C99 /
C++ binding of `NUMERIC_API_v1` for streaming residual summary facts. Discovery
fields are `native_c_header` and `native_c_api_version`; capability
`native_residual_reductions`. Compile the header from the same framework source
revision as its consumer; no private Octave implementation dependency is needed.

Initialize `gx_numeric_residual_accumulator_v1` with
`gx_numeric_residual_init_v1`, push finite signed residuals using
`gx_numeric_residual_push_v1`, and call `gx_numeric_residual_finish_v1` for
count, first maximum index, maximum absolute error, mean absolute error and RMS.
`gx_numeric_residual_merge_v1(a,b,out)` concatenates the two sampling sequences
without observation buffers; output may alias either input. Treat accumulator
fields as opaque and retain their initialization and source sampling order.

The scaled sums avoid intermediate squared-value overflow/underflow, including
platforms with binary64 `long double`. Accumulation precision may improve
compared with historical plain binary64 sums. `GX_NUMERIC_EMPTY_V1` means no
observations; it does not fabricate a zero error. Invalid/nonfinite input and
count overflow are explicit errors, preserving the previous output/accumulator.
The result defines no parameter DOF, uncertainty, R squared or physical metric
policy: consumers must supply those meanings through the CORE statistical
contract. Native2D retains matching/projection geometry and consumes these
Numeric facts for both legacy X/path and sampled geometric comparisons.

Native `residual_summary` facts from the public C reduction binding now adapt
through `STATISTICAL_RESULT_SEMANTICS_API_v1`. The registered
`math.numeric.geometric_deviation` descriptor covers descriptive path and
nearest-curve comparisons without regression-inference claims. Numerical
reductions remain in this Numeric binding; consumers report their CORE records.

### Spectral distribution

`spectral_features(frequency, values, options={})` is available through the
Octave dispatcher, typed Tcl catalog, Worksheet `numeric.spectral_features` and
both Script Bridge languages. Frequency and values are matched vectors with at
least three finite values on a nonnegative, increasing uniform grid. Options are
`input_semantics=amplitude|power|psd` (default amplitude) and Boolean `exclude_dc`
(default true). At least two bins with positive total weight must remain.

The operation preserves the established spectral module algorithm and returns
scalar descriptors plus the retained frequency/source/weight/proportion,
cumulative proportion and relative-dB vectors. Equal maxima select the first
frequency; zero weights produce zero flatness. Negative values, irregular grids
and zero total weight reject. `quantile_definition` records the weighted empirical
CDF inverse. Interpret the captured result through the provider-declared
`math.numeric.spectral_distribution` CORE model; only bounded scalar facts are
needed. Physical input units are supplied as `x_unit` and `y_unit` to CORE.

### Power level

`power_level(power, options={})` accepts finite, nonnegative real scalar/vector/
matrix powers and preserves their shape. `reference_rms` defaults to 1 and must
be positive and finite. Results contain `power`, `root_power`, `level_db`, the
reference and `zero_policy`. Zero power has a typed NaN level; positive levels
use a difference of logarithms to avoid intermediate ratio overflow/underflow.
The calculation does not integrate a PSD or derive physical units.

The registered `math.numeric.power_level` CORE profile currently interprets
integrated spectral powers with the actual `psd_unit` context. One scalar uses
`from_numeric`; multiple bands use `from_numeric_columns` and explicit band row
identities. CORE owns RMS/power units and zero-power states; publication must
retain that result. The typed Tcl and real Python/Octave bindings share Numeric.
Worksheet supplies input units and context through the same CORE interpretation.

<a id="welch-aggregation-dev097"></a>
### Welch aggregation

`welch_aggregate(sum_psd, sum_amplitude, options)` combines deterministic sums
of already normalized one-sided periodograms. Required options: positive integer
`window_count`, positive `frequency_step_hz` and `enbw_sum_hz`. Both sums must be
matched finite nonnegative vectors beginning at DC. It returns averaged PSD,
ASD, amplitude, Hz frequency and dB relative to a unit PSD reference. Zero PSD
yields NaN dB. Scalar facts retain integrated power, non-DC peak, mean ENBW and
zero-bin count. Interpret with `math.numeric.welch_spectrum` and original signal
`y_unit` through CORE statistics. Overlap does not supply sampling DOF. Reporting
and publication do not repeat aggregation. Full vectors remain Numeric resources.

<a id="local-unlabelled-point-cloud-estimator-dev097"></a>
### Local unlabelled point-cloud estimator

`local_cloud_fit(x, y, query, options={})` returns per-query `local_mean`,
`local_sigma`, `local_count`, `local_degree`, `quadratic_condition`,
`local_effective_n`, `local_dof` and actual `query`, with the recorded method,
variance correction and insufficient-information policy. Inputs are finite real
vectors; X/Y counts match and every query is inside the source X domain.
Only empty options are accepted. Selection, positive tricube weights and the
quadratic/constant fallback match the accepted Replicate estimator.

`local_dof` names the legacy effective-count variance denominator and does not
claim sampling DOF. Values at or below zero produce NaN dispersion; positive
fractions are preserved. Interpret with CORE `math.numeric.local_cloud`, actual
X/Y units and named query rows. This numerical prerequisite does not itself
complete the Replicate Analysis module's report/publication migration.

`replicate_summary(values, source_ids, options={})` reduces a finite real matrix
with coordinate rows and contributing-curve columns. Each column has a positive
integer source ID. Default `mode=labelled_traces_anova` preserves the accepted
one-way random-effects moment estimator with actual unequal source counts.
Negative between-source moments are truncated to zero with an explicit
`between_clamped` flag. A single curve has undefined dispersion and SEM.
`sampling_model=independent_traces` explicitly enables conditional SEM; the
default `unspecified` leaves it unavailable. Labels alone do not verify this
sampling assumption.

`mode=unlabelled_point_cloud` requires one curve per source and a matching
`local_dispersion` matrix captured from the public local-cloud estimator.
Unavailable local dispersions may be NaN in direct Octave calls. Finite-input
Tcl clients can use a matching `local_available` zero/one matrix with any
nonnegative placeholder at unavailable entries; Numeric consumes that mask before
reduction. A mask cannot declare a NaN available. Invalid rows do not suppress
valid neighbouring coordinates. Cloud components are a descriptive combination
of local residual RMS and source-location sample spread; they do not establish
independent replicate counts or identified physical variance components.

The result includes consensus mean/median, dispersion, conditional SEM, three
components, counts, component coefficient, availability/truncation flags and
plus/minus spread envelopes. Those envelopes have no confidence or prediction
coverage claim. Numerical arrays remain transport resources. Interpret them with
CORE `math.numeric.replicate_profile`, actual response units, and compact tables
or Dataset-local column bindings; one scalar result represents one coordinate.
The same operation is callable from Tcl, Python and Octave. Replicate GUI,
reports and caches retain these shared CORE meanings and resource bindings.

`statistics` additionally returns `max_absolute`, interpreted by CORE as
`absolute_maximum` in the actual input unit. This lets signed-deviation reports
reuse one captured summary for bias, RMS and maximum absolute deviation.
`replicate_summary` also returns `source_means` in the order of `sources`; the
same group centers are reused by variance decomposition and downstream reports.

<a id="dev097-signal-summary-and-quality"></a>
## signal summary and quality

`signal_summary(x)` describes finite real or complex samples with magnitude RMS,
peak, real-component range and split DC means. `signal_snr(signal,noise)` uses
equal-length vectors and computes the log energy ratio with scaling, so a finite
ratio can survive individual energy overflow or underflow. Zero energies have no
finite logarithmic SNR. These operations infer no sampling standard error.

`signal_spectrum_quality(x,fs,{fundamental_hz:f0})` retains the Signal coherent
positive FFT-bin estimator. The signal must be real and the declared fundamental
must be a positive coherent bin below Nyquist. Existing power-named fields are
raw unnormalized squared FFT magnitudes, with the Nyquist bin undoubled. They are
not normalized mean-square power or a PSD. Added harmonic order IDs preserve the
vector's identity; `thd_db` is computed here once.

Capture either result through CORE `numeric_model`, `from_numeric`, and
`numeric_fields` with the actual response unit. CORE owns definitions and result
availability. Harmonic vector metadata has a 65536-element bound; it is never
silently truncated. Large waveform operands still use the binary Script Bridge.

<a id="dev097-amplitude-spectrum-quality"></a>
## amplitude-spectrum quality

`fft_spectrum_quality(samples, sample_step, options)` exposes the accepted FFT
lobe estimator. Options select window, detrending, fundamental, tracked orders,
guard width and spur exclusions. Existing amplitude normalization and lobe/bin
choices are retained; source coordinate units are caller-owned. Its large
`amp` and `magnitude_dbc` arrays use the binary Bridge. Scalar CORE capture
excludes these bulk arrays.

`harmonic_peak_quality(frequency, amplitude, options)` analyzes an existing
amplitude spectrum without recomputing it. It retains the local single-bin peak
search, available harmonic range and source normalization. It is distinct from
raw coherent FFT-bin quality and from FFT lobe RSS quality.

`harmonic_components(orders, expected_frequencies, detected_frequencies, amplitudes,
options)` computes relative levels and frequency errors once. Required option
`fundamental_amplitude` declares the reference. `component_method` is
`supplied_component_amplitude`, `fft_lobe_rss` or `single_bin_peak`; `level_floor`
is `none` or `realmin`. Ordered component columns remain identifiable. CORE
`from_numeric_columns` interprets bounded scalar component rows with actual
frequency and amplitude units, preserving individual zero-level availability.
A floored reported level does not claim a positive physical amplitude.

FFT Spectrum 2.3 and Harmonic Analysis 1.2 use these public owners, captured CORE
metadata and CORE reports. Their targeted integration evidence is separate from
the owner contract checks and final release acceptance.

`event_period(crossings, options={})` and
`pulse_timing(rising_crossings, falling_crossings, options={})` summarize already
detected events in seconds. Options are currently empty. Nondecreasing finite
crossing vectors retain repeated detections and zero intervals. Frequency is
the reciprocal mean period. Pulse widths use the first strictly later falling
event before the next reference event; incomplete widths do not remove reference
intervals from period statistics. Duty is mean width divided by mean period.
The bounded result records actual crossing, interval and complete-width counts.
Sample jitter uses count minus one and is NaN for one interval. CORE interprets
these operations under the registered `event_timing` profile and requires
`x_unit=s`. No independent-sample or timing-accuracy assumption is inferred.

For full-rank linear least squares, the solve now uses the same column scaling
as the rank decision and transforms coefficients back to their physical units.
This prevents an unscaled solve from silently discarding a tiny independent
column that the rank check accepted. The explicit rank-deficient `minimum_norm`
policy remains in physical coefficient coordinates. Covariance units and the
existing public result identities are preserved.

`signal_correlation(first, second, options={})` computes full uncentered
conjugate sequence correlation, with an empty second input selecting the first.
Arrays are flattened in column-major order as in Signal v1. Lag k sums
`first(j+k)*conj(second(j))`; lags run from `1-length(second)` through
`length(first)-1`. Options `normalization=none|biased|unbiased|coefficient` retain
the accepted Signal definitions: raw sum, division by maximum length, division
by actual overlap, or division by full-sequence Euclidean norms. Coefficient
normalization scales before convolution, avoiding squared-energy overflow and
underflow. No centering or Pearson correlation is introduced.

Full `value_real`, `value_imaginary` and `lags` arrays stay in binary transport.
Bounded facts identify both lengths, lag count, selected peak components,
normalization, input kind and first-absolute-maximum tie policy. `sample_rate`,
when supplied, must be finite and positive. Delay is integer lag/rate; no
sub-sample estimate or confidence interval is inferred. Zero raw correlation
retains the legacy first lag but sets `peak_resolved=false`; zero-energy
coefficient normalization rejects. CORE `math.numeric.signal_correlation`
requires the actual first and second signal units in `x_unit` and `y_unit`;
these are signal units, not the time-coordinate unit. CORE marks zero/nonfinite
delay undefined and seconds unavailable without a rate.

`window_metrics(window, sample_rate, options={})` owns coherent gain, power gain
and equivalent noise bandwidth for finite real dimensionless window coefficients
with nonzero sum. It retains signed mean gain, mean squared gain (denominator N),
and `sample_rate*sum(window^2)/sum(window)^2` in hertz. Internally scaled moments
avoid avoidable overflow/underflow in ENBW. A positive power gain below binary64
is represented as NaN, rather than a false zero; CORE marks nonfinite moments
undefined while retaining the available gain and bandwidth. The sample rate
must be finite and positive. No window coefficient is a statistical observation
for inference. Capture with CORE model/operation `math.numeric.window_metrics` /
`window_metrics` and actual coefficient unit `x_unit=1`.

The public Numeric operations `signal_periodogram(x, fs, options={})`,
`signal_welch(x, fs, options={})`, `signal_asd(x, fs, options={})`, and paired
`signal_cross_psd|signal_coherence|signal_frf_h1|signal_frf_h2(x, y, fs, options={})`
own Signal's spectral estimators. Existing vector names are retained. Options
are `window`, `nfft` and native `overlap` fraction (0 through 0.95). Welch accepts
an explicit coefficient vector, scalar window length greater than three, or an
empty window for its native default. A zero-energy window rejects. NFFT is
increased to cover a Welch segment; periodogram requires a positive NFFT and a
full-length window, folding the windowed input when NFFT is shorter. Empty
periodogram windows are rectangular. Default Signal windows remain Hamming.

Periodogram removes no mean. Welch explicitly uses native Octave conventions,
removing one global mean over the span covered by complete segments, including
padding for a signal shorter than one window. The caller's persistent pwelch
compatibility setting is restored on exit. Paired spectra are computed together
with a common grid and conjugation `Pxy=Y*conj(X)`. This also supports mixed
real/complex pairs on the same grid. Real
effective inputs yield a one-sided density with DC/Nyquist exceptions; complex
inputs yield the full unshifted grid. Coherence is `abs(Pxy)^2/(Pxx*Pyy)`, H1 is
`Pxy/Pxx`, H2 is `Pyy/conj(Pxy)`. Zero denominators remain nonfinite/unavailable.
No effective independent-segment count or confidence interval is inferred.

CORE registers a distinct `math.numeric.signal_*` model for each estimator under
profile `signal_spectral`. Capture *per-bin* scalar facts with `from_numeric`,
bounded rows with `from_numeric_columns`, or publish complete spectra with
`bind_columns` and canonical Dataset Publication. Full vectors must not be sent
as scalar statistical metadata. Common method/grid/segment facts stay scalar;
`frequency_hz` and the returned value fields vary by row. A binding prototype is
an example bin, never a summary statistic. Both real Script languages support
sealed publication and bounded per-frequency reads through `binding_table`.

Supply the first signal's actual unit as `x_unit`; paired estimators also require
the second signal's unit as `y_unit`. These are signal units, not frequency units.
CORE owns Hz coordinates, squared-unit/Hz PSD, unit/sqrt(Hz) ASD, input-product/Hz
cross-density, dimensionless coherence and second/first-unit transfer estimates.
Use `numeric_fields` for exact unit text and availability; it does not recompute
spectra. Wrong estimator model IDs, inconsistent grids and relabeled definitions
are rejected by common validation.

<a id="axis-summaries-dev097"></a>
### Axis summaries

`matrix_statistics(values, options)` and `reduce_summary(values, options)` accept
one data operand and optional `dimension` 1 or 2. Their additive `input_shape`,
`output_shape` and `requested_dimension` facts preserve the actual reduction.
The default summary flattens a vector (`requested_dimension=0`); a matrix reduces
along dimension 1. `reduce_accumulate(state, values)` has two data operands and
retains scalar-state accumulation. These are separate catalog and Bridge entries.
CORE `math.numeric.summary` accepts scalar facts directly; select actual axis
columns with `from_numeric_columns` for non-scalar outputs. No estimates are
recomputed by interpretation. Singleton sample spread remains undefined.

<a id="foundation-location-facts-dev097"></a>
### Foundation location facts

The existing `foundation` family `statistics` actions `confidence_interval` and
`robust_location` now supply additive scalar facts for CORE interpretation.
Mean intervals add `n`, `standard_error`, `degrees_of_freedom`, and method
`student_t_mean`. They use public `student_t_quantile`, so a fresh worker no longer
needs an externally loaded statistics package.
Singleton uncertainty remains NaN; the sample mean remains valid.
Huber adds `n`, `huber_constant`, `converged`, and the exact fixed-scale method.
Both actions require real observations; invalid alpha and tuning constants reject.
The existing algorithms and field identities remain; no additional estimation is
performed by the CORE capture or by Worksheet presentation.

<a id="foundation-seeded-resampling-dev097"></a>
### Foundation seeded resampling

`foundation/statistics/bootstrap_ci` and `permutation_test` retain their existing
operands and seeded results. Bootstrap explicitly selects native quantile method
5, preserving the accepted default. Permutation retains zero tolerance in its
absolute-tail comparison. New fields capture sample counts, method, inference,
replicates, actual seed/generator and estimator-specific facts. Bootstrap adds the
variance/standard error of its already generated replicate distribution; it does
not generate a second distribution. Explicit integer seeds preserve replay and
caller RNG restoration. CORE uses distinct registered models for these methods;
the newer `resampling_summary` keeps its own quantile/tolerance convention.

<a id="foundation-correlation-and-multiplicity-facts-dev097"></a>
### Foundation correlation and multiplicity facts

`foundation/statistics/partial_correlation` retains the accepted covariance
pseudoinverse normalization. Additive fields record `n`, `variable_count`,
`control_count`, `covariance_rank`, `normalization_valid`, and the exact method.
It requires aligned real sample vectors and a real control matrix with at least
two rows. A singular covariance does not turn this descriptive coefficient into
ordinary residual partial correlation. Zero normalization remains undefined.
No p-value, confidence interval or causal claim is supplied.

`multiple_testing` retains Bonferroni, Holm and BH values for valid input p-values.
It now rejects values outside [0,1] and complex input, and records `original_p`,
one-based `hypothesis_index`, `family_size` and `method` beside `adjusted_p`.
Use CORE `from_numeric_columns` for the three varying columns and keep family
size/method as common facts. CORE validates identities and explains conditional
FWER/FDR control; it does not repeat an adjustment or establish the validity of
the supplied marginal p-values.

<a id="kaplan-meier-facts-and-captured-foundation-calls-dev097"></a>
### Kaplan-Meier facts and captured foundation calls

`foundation/statistics/survival_kaplan_meier` retains the sequential product limit
at sorted distinct coordinates, including censor-only coordinates. It groups
observations once instead of rescanning them for each coordinate. Additive `n`,
`at_risk`, `events` and `censored` record the actual counts used by the estimator.
Tied events use the risk set before both events and censoring are withdrawn.
Coordinates must be real and finite; indicators must be zero or one. Signed time
origins are retained. No confidence interval or standard error is computed.

The public Tcl `foundationCaptured document family action a b c context
?options? ?provenance?` calls the same public foundation owner once with binary
input/output. Its result follows `callOperationCaptured`: common values, captured
CORE statistics and transport byte counters. Only operations with a registered
CORE scalar-column mapping are eligible; captured columns must have a common
length. It uses the existing Document owner and resource API. For survival pass
`x_unit` in context. No private file path is exposed to consumers.

<a id="sample-covariance-diagnostics-dev097"></a>
### Sample covariance diagnostics

`foundation/statistics/covariance_diagnostics` preserves its original `covariance`,
`eigenvalues`, `condition_number` and `rank`. Additive fields are `n`,
`variable_count`, `method`, `input_kind`, `covariance_real`, `covariance_imaginary`,
`eigenvalues_real` and `eigenvalues_imaginary`. Components are projections of the
same computed arrays; there is no second covariance or eigendecomposition.
A vector is one variable regardless of row/column orientation. The native
singleton zero remains available in raw results; CORE marks sample covariance
undefined because its n-minus-one denominator has no sample information.

Data-only `foundation` calls from real Python/Octave Script Bridge jobs now use
the existing CORE binary worker and its registered `gxtxt_numeric_v1` entrypoint.
This fixes unsupported complex matrix results in the old text adapter and avoids
serializing bulk observations through Tcl/INI. Typed operands, options and
`result_fields` projection are retained. Existing callback dispatch is unchanged.

<a id="seeded-native-clustering-dev097"></a>
### Seeded native clustering

`foundation/statistics/kmeans` preserves accepted seeded `labels` and `centroids`
and restores the caller's RNG state. Rows are observations, including a single
row with several feature columns. A finite nonnegative integer seed is required;
`clusters` is a positive integer within the observation count and `replicates`
is a positive integer (default five). The actual native settings remain plus
initialization, squared Euclidean distance, singleton empty-cluster handling and
100 iterations. Additive facts are `within_ss`, `cluster_counts`,
`total_within_ss`, `n`, `feature_count`, `cluster_count`, `replicates`, seed,
generator, method, settings and backend name/version. The objective comes from
the same native call; no second clustering or final-center refit is performed.

Interpret with CORE `math.numeric.foundation_kmeans`. Centers retain separate
cluster-row and feature-column identities and per-column coordinate units.
Counts and label numbers are dimensionless. Homogeneous feature units give a
squared objective unit; mixed units give `unspecified` and a scaling limitation.
The native provider does not return convergence/iteration evidence, so CORE
records `not_reported`. The installed statistics implementation initializes
its iteration error outside the replicate loop; requested starts therefore do
not prove every start iterated to convergence. Existing numeric outputs are
preserved, and neither a global optimum nor a final-assignment refit is claimed.

Raw `labels` remain in the Numeric binary result. CORE `numeric_data_fields`
describes their original-observation shape, integer range and matching cluster
identities without embedding the observation array in statistical metadata.

<a id="foundation-robust-logistic-and-glm-regression-dev097"></a>
### Foundation robust, logistic and GLM regression

These existing algorithms retain every original valid-input output. Additive
fields include `n`, `p`, `coefficients_real`, `coefficients_imaginary`, actual
`iterations`, `converged`, `last_update_norm`, `last_threshold`, `tolerance`,
`iteration_limit`, `input_kind` and method. No automatic intercept is inserted.
Huber regression also returns `huber_constant`, `last_scale`, `residual_real`
and `residual_imaginary`. It preserves complex design/response support and the
accepted Hermitian weighted normal equations. Its captured scale is the scale
used before the last update, not a newly computed final residual error estimate.

Logistic regression requires real design and binary response, with its existing
variance floor 1e-10 and absolute update threshold 1e-9. GLM preserves binomial
logit and Poisson log-link behavior, update predictor clipping to [-40,40],
variance floor 1e-8, information reciprocal-condition threshold 1e-12 and Poisson
backtracking rule. Final fitted means are still evaluated without clipping.
GLM options require a positive finite tolerance and positive integer iteration
limit. Huber's constant must be positive and finite. Original numerical fields
are unchanged for accepted valid inputs, including nonconverged returned iterates.

Use the corresponding CORE `math.numeric.foundation_robust_regression`,
`foundation_logistic_regression` or `foundation_glm` model. The shared profile
`foundation_regression` preserves the actual method/family/link and coordinate
identities. A stopping flag does not certify identification, finite maximum
likelihood under separation, sampling inference or a global optimum. These
providers do not supply coefficient covariance or intervals; CORE does not invent
them. Raw observation arrays remain in binary transport; public numeric data
contracts describe real residual components, probabilities and fitted means.


<a id="independent-component-models-and-frozen-composition-1220"></a>
## Independent component models and frozen composition

`fit_model_catalog()` returns `gxtxt.fit_model_catalog.v1` with independent
`plugins/models/*/model.ini` cards that declare `[fitting] api_version=1`.
Cards contain the version, descriptor SHA256, equation, parameter identities,
unit relationships, domain, initialization, derivative, inference and
extrapolation policies. Callable family models retain their existing contract.

`fit_model_compose(recipe)` returns a data-only `kind='expression'` model for
existing `nonlinear_fit`, `dataset_nonlinear_fit`, `nonlinear_evaluate` and
`prediction_uncertainty`. Tcl uses `callOperation` with typed operands; both
real Script Bridge languages expose the same operation names. Composition does
not calculate statistics or run a fit.

A recipe has explicit `x_unit`, `y_unit`, a list of `components`, and optional
`parameters` overrides. Each component has a unique symbol `id`, installed
`model_id`, optional `initial_parameters` in card order, and optional `bindings`
from local parameter name to a shared global symbol. Otherwise global names are
`component_id_parameter_id`. Components are summed in their listed order.

```python
recipe = dict(x_unit='s', y_unit='V', components=[
    dict(id='peak', model_id='peak.lorentzian_height_v1',
         initial_parameters=[2, 1, .7]),
    dict(id='background', model_id='baseline.linear_v1',
         initial_parameters=[.2, .03])])
model = gxtxt_api_call('NUMERIC_API_v1', 'fit_model_compose', [recipe])
fit = gxtxt_api_call('NUMERIC_API_v1', 'nonlinear_fit',
                    [x, y, model, model['initial_parameters'], options])
```

Available cards include Gaussian peak height/center/sigma, Lorentzian peak
height/center/HWHM, constant baseline and linear baseline. Gaussian sigma and
Lorentzian HWHM have different meanings. The historical Gaussian builtin with
amplitude/center/width/offset retains its identity. Baselines are fitted jointly;
original observations are preserved. Negative peak heights can represent dips.

A shared symbol requires equal parameter units and initial values. A parameter
override can contain `initial`, `lower`, `upper`, and boolean `fixed`. Sharing
uses one actual optimizer parameter and the full common covariance. Bounds may
narrow the model domain; solver options cannot weaken captured bounds or release
captured fixed values. Positive widths use the smallest normal binary64 number
as a computational lower bound. Defaults are dimensional placeholders requiring
review, not automatic guesses from data. Severe overlap or exchangeable peaks
can remain unidentifiable; ordinary rank/constraint/convergence checks apply.

The model carries `gxtxt.fit_composition.v1`, frozen cards, exact bindings, initial
values and constraints. Replay checks captured definition digests and parameter
identity against the frozen composition; it does not load a newer installed
formula. Keep typed CORE transport/publication for persistence: generic JSON
writers can replace infinity by null or round tiny nonzero bounds/parameters
to zero. Both are lossy and the model validator rejects changed constraints.

Limits are 32 components, 128 shared/free/fixed parameter identities, 32768
formula characters and 128 KiB model metadata. Descriptors declare finite-real
or strictly positive scalar coordinates. The existing native fitter provides
bounds, fixed parameters, robust objectives, multistart and independent XY-error
fitting. Numerical limits and inference eligibility of those operations apply.

<a id="physical-library-1240"></a>
### Physical library

| Descriptor | Parameters in order | Unit relationship / convention |
| --- | --- | --- |
| `peak.voigt_area_v1` | area, center, sigma, gamma | Y*X, X, X, X; integrated area, Gaussian standard width, Lorentzian HWHM |
| `response.logistic_v1` | amplitude, center, rate | Y, X, 1/X; continuous response sigmoid, distinct from binary logistic regression |
| `decay.exponential_v1` | amplitude, tau | Y, X; positive lifetime; compose multiple cards for multi-exponential decay |
| `kinetics.arrhenius_temperature_v1` | prefactor, activation_temperature | Y, K; positive prefactor; signed Ea/R in K, never mislabeled as energy |
| `diode.shockley_series_v1` | saturation_current, thermal_voltage, series_resistance | A, V, V/A; effective thermal voltage n*k*T/q; nonnegative series resistance |

Each card documents its equation, initialization, derivative policy, limitations
and inference eligibility. Voigt uses the installed Octave complex `erfcx`
owner and analytic derivatives, including stable far-tail expressions. Logistic
uses a stable sign-dependent evaluation. `shockley_series(V,Is,Vt,Rs)` evaluates
the unique implicit ideal-diode solution and its physical derivatives. These
functions are additive to the existing controlled expression grammar; no source
evaluation or module-specific fitting optimizer is introduced.

Arrhenius requires strictly positive X in `K`; diode requires `V` and `A`.
Their `translation_policy=forbid_translation` prevents Fitter offsets from
changing the physical law. Other supported policies are `allowed` and
`forbid_input_translation`. Optional card fields `required_x_unit` and
`required_y_unit`, together with `input_domain`, are frozen and aggregated into
model `input_constraints`. Old finite-real cards keep their exact definition
digests and can reopen saved models predating this additive field.

Array callers declare and supply the actual recipe units. Dataset binding
additionally checks the recipe against authoritative axis metadata. Convert
Celsius, mV or mA values explicitly before binding; relabeling is not conversion.
Explicitly omitted/zero-weight rows are removed before retained-domain checks.
Positive input domains apply inside native evaluation to ODR-adjusted X too;
caller solver options cannot disable this model-derived condition. Invalid
trial evaluations reject; no coordinate clipping changes scientific values.

The public fit/evaluate operations, binary Script transport and CORE statistical
semantics are shared by every card. Multi-exponential and overlapping peak
decompositions can be nonunique; user-specified bounds and sharing retain exact
parameter identities. Active boundaries, poor rank and solver failure retain
the shared restrictions on local intervals. Descriptor READMEs explain physical
limits such as omitted diode breakdown, shunt leakage and self-heating.

<a id="captured-observation-identity-and-model-selection-scores-1240"></a>
## Captured observation identity and model-selection scores

The `bootstrap_refits` capability exposes
`fit_bootstrap(model, predictors, response, CORE_plan, options={})`, including
Tcl `fitBootstrap` and real Python/Octave Script bindings. It uses captured
parameters, exact retained input hashes, original solver policy and isolated
seeds. Registered scalar callbacks use the same sampling and summary stages,
with their captured SciPy backend/version and solver settings in a supervised
one-thread Job. The additive public stages `fit_bootstrap_prepare`,
`fit_bootstrap_draw` and `fit_bootstrap_summarize` expose data-only bounded state,
aligned draws and validated ledgers; callback handles remain in the Script Job.
See the complete [CORE/Numeric parameter-bootstrap contract](../../../docs/api/PARAMETER_BOOTSTRAP_v1.md).
All scientific meaning and reporting belong to the public CORE statistics API.

`fit_observation_signature(observed, weights=[], response_offset?, predictors?)` returns
`gxtxt.fit_observations.v1`: N, ordered response/weight SHA-256 and
`log_weight_sum`. Inputs are the retained finite responses and strictly positive
effective precisions in exact fit order. Empty weights mean ones. Digests use
prefix `gxtxt.fit_observations.v1:f64le:` followed by ordered IEEE binary64 LE
words, including signed zero. Optional finite `response_offset` also captures
`fit_response_sha256` for the exact additive map used by public `array_binary`;
the primary response SHA remains the original supplied response. Shared fit
diagnostics already attach the actual fitted-response signature automatically.
An optional fourth predictor matrix adds `predictor_count` and
`predictors_sha256`, using the same binary64 encoding in column-major order;
pass an empty third argument to omit translation. New scalar-response fits
capture their exact retained predictors automatically, including the original
physical predictor of a scaled polynomial. Historical receipts without these
additive fields remain valid. This operation fingerprints evidence; it does not
infer Dataset identity.

`fit_information_criteria(plan)` consumes an eligible public CORE
`STATISTICAL_MODEL_SELECTION_PLAN_v1`. It returns the unchanged bounded plan,
full Gaussian log likelihood, AIC/AICc/BIC, free and likelihood parameter counts,
ML scale and explicit AICc availability. It reuses captured weighted SSE and
normalization; it does not refit or reduce residuals again. CORE owns eligibility,
comparability, scale counting and interpretation. See the shared statistical API.
Tcl uses `fitInformationCriteria plan` or typed `callOperation`; both operations
are also in the public Octave dispatcher and Python/Octave Script Bridge.

`nested_f_test(plan)` / Tcl `nestedFTest plan` computes a nested polynomial F
statistic and stable upper-tail probability from the captured weighted SSEs in
an eligible `STATISTICAL_NESTED_F_PLAN_v1`. It returns its plan, numerator and
denominator DOF, explicit roundoff/undefined states and numerical facts without
refitting. Use public CORE `nested_f_interpretation` for meaning, validation and
reporting. See [Nested-model F test](../../../docs/api/NESTED_MODEL_F_TEST_v1.md).

Fit `response_rmse` is sqrt(unweighted physical residual SSE/N). Historical
`rmse` remains the weighted residual SD using residual DOF, and `residual_rmse`
remains unweighted residual SD using DOF. CORE maps these distinct identities.
No old scientific field is renamed or silently redefined.


<a id="joint-regional-models-and-knee-primitives-1250"></a>
## Joint regional models and knee primitives

`fit_region_catalog()` returns `gxtxt.fit_region_catalog.v1` with independent
`regional_increment` descriptors under `plugins/models/`. Initial shapes are
linear, exponential, quadratic and cubic increments. They are distinct from the
summed scalar cards returned by `fit_model_catalog()`. The latter also discovers
`piecewise.linear_knee_v1`, whose physical breakpoint, junction response and two
slopes share one solve and full covariance.

`fit_region_compose(recipe)` returns one frozen declared-expression model for
`nonlinear_fit`, `nonlinear_evaluate`, prediction uncertainty and Dataset fitting.
Its `regional_composition.schema` is `gxtxt.fit_regions.v1`. A recipe contains:

- Explicit `x_unit`, `y_unit`, finite physical `origin`, and 2..8 ordered
  `regions`, each with its own identifier and a regional descriptor `model_id`.
- Exactly one breakpoint between neighbours: unique `id`, finite `initial`,
  `lower`, `upper`, boolean `fixed`, and `continuity` (`C0` or `C1`). Search
  windows must be strictly ordered without overlap. The first lower bound must
  be at or above the origin. Equal lower/upper bounds fix that breakpoint.
- Optional `fit_windows`, up to 64 ordered finite `[lower, upper]` pairs.
  Windows may touch; their union selects each actual observation once. Blank
  means all caller-selected observations. These are observation windows,
  independent of the breakpoint search bounds.
- Optional `parameters` overrides, each with `initial`, `lower`, `upper`, `fixed`.
  `level` is the response at the physical origin; regional parameters use
  `<region_id>_<local_parameter>`. Breakpoint controls belong in `breakpoints`.
  A C1-derived starting slope is absent from the parameter vector and cannot
  have an override. Descriptor defaults are dimensional placeholders.

Example Python Script Bridge recipe (use matching physical Dataset units):

```python
recipe = {
    'x_unit': 'V', 'y_unit': 'mA', 'origin': 0.,
    'regions': [
        {'id': 'left', 'model_id': 'region.linear_increment_v1'},
        {'id': 'right', 'model_id': 'region.exponential_increment_v1'}],
    'breakpoints': [{'id': 'junction', 'initial': 3.5, 'lower': 2.,
                     'upper': 5., 'fixed': False, 'continuity': 'C1'}],
    'fit_windows': [[0., 4.], [6., 10.]],
    'parameters': {'level': {'initial': 1.},
                   'left_slope': {'initial': .4},
                   'right_rate': {'initial': .2}}}
model = gxtxt_api_call('NUMERIC_API_v1', 'fit_region_compose', [recipe])
fit = gxtxt_api_call('NUMERIC_API_v1', 'nonlinear_fit',
                    [x, y, model, model['initial_parameters'], options])
```

The direct Octave binding retains its established argument order:
`gxtxt_numeric_v1('nonlinear_fit', model, x, y, initial, options)`. The real
Octave Script Bridge uses the same `[x,y,model,initial,options]` order as Python,
expressed as a cell argument list. No callback or private solver is needed.

The expression sums completed/clamped increments and one global level. For the
first region its span is `minimum(x,b1)-origin`; an interior span is
`positive_part(minimum(x,bnext)-bprev)` and the final span is
`positive_part(x-blast)`. Earlier increments remain constant after their region.
C0 shares the junction value exactly. C1 substitutes the preceding endpoint
slope into the next increment and removes the independent next slope. All free
shape parameters and breakpoints share one native optimization and covariance.
The exponential increment is `slope*t*exprel(rate*t)`, including its analytic
linear limit at zero rate. Native selection avoids cancellation between large
positive parts; flat outer knee branches retain their physical level.

`fit_region_selection(model,x)` returns `gxtxt.fit_region_selection.v1` with a
binary `selected_mask`, one-based `source_row_positions`, `region_indices`
(zero outside observation windows), bounded counts, current breakpoint values,
windows and explicit right-region ownership at equality. `nonlinear_fit`
intersects this selection with its existing finite/positive-weight selection;
its row positions still refer to the original arrays. Dataset fit ordinals retain
their documented one-based uint64 contract. Fitter's original Dataset row IDs
retain their separate zero-based Curve Source contract; they are never relabelled.

Fit results carry bounded `regional_fit` facts for public CORE interpretation:
actual physical breakpoint identities/values, fixed/free masks, continuity,
per-region observation counts and exact predictor/breakpoint coincidences. Knee
components use this same contract, including shared breakpoint identities and
multiple knees ordered by their fitted physical positions. For ODR, inference
support uses the fitted latent predictors; observation selection remains based
on the measured predictor. Regional fit-window counts and binary membership
remain distinct from measurement omission and zero-weight exclusions.

Use `STATISTICAL_RESULT_SEMANTICS_API_v1.from_numeric` for all scientific meaning.
Local breakpoint covariance is conditional on identified changes, observation
support and model/error assumptions; it is not a profile interval or proof of a
unique minimum. CORE refuses an ordinary symmetric interval for a free C0
breakpoint exactly on a training predictor, and for an unobserved regime. Its
existing rank, active-bound, loss and convergence guards also apply. Regional
information criteria require eligible local inference; physical RMSE remains a
separate descriptive comparison. Use explicit multistart and review the retained
trials when different breakpoint starts expose competing minima.

Declared-expression primitives added with these models:

- `positive_part(z)`: max(z,0), with right derivative one at zero.
- `minimum(a,b)`: select the smaller operand; select the second at equality.
  This convention gives the outgoing region ownership at a clamped upper end.
- `exprel(z)`: expm1(z)/z, with value one and derivative one-half at zero;
  native analytic/series evaluation avoids removable-limit cancellation.

Expressions, parameter identities, dimensional roles, constraints and descriptor
SHA definitions are frozen and checked on evaluation/replay. Coordinate
translations are forbidden for regional models and knees. Scientific Sessions
retain their original source arrays; gaps and extrapolation are explicitly model
continuations. Expression length, native instruction/stack and bounded metadata
limits also apply to expanded C1 compositions.


<a id="independent-model-export-1270-dev097"></a>
## Independent model export

`gxtxt_numeric_v1('model_export', model, options)` and Script Bridge
`NUMERIC_API_v1/model_export` return Python, Octave, LaTeX and metadata JSON text.
Tcl uses catalogued `callOperation model_export {model_node} options_node`.
A model is either a saved declared expression with finite parameters, an existing
`curve_model_fit` state, or `kind=polynomial_export` with coefficients and optional
scaled_coefficients/x_center/x_scale. An inert JSON encoding of the same state is
also accepted. `polynomial_export` denotes evaluation representation; `model_id`
retains the caller's scientific model identity. No estimator or statistics runs.

Options: required increasing finite `domain=[lo,hi]`; `name` (default fit_model),
orientation (y_of_x, x_of_y, r_of_theta, parametric), delta_u/delta_v, x_unit/y_unit/
query_unit, source_reference, model_id, parameter_ids/parameter_values/
parameter_units, positive_predictor and polar_frame. The name starts with fit_
then a letter and at most 55 letters/digits/underscores. The caller supplies saved
CORE parameter metadata; Numeric does not infer or reinterpret those quantities.
The output contract, dependencies, bounds, precision and physical coordinate
semantics are documented in DATASET_CURVE_FIT_API_v1's independent export section.

The existing controlled expression compiler produces the export statements;
user expressions are never evaluated as source code. Voigt, stable logistic,
positive_part, minimum, exprel and monotone diode evaluation have independent
numerical helpers. This is the requested evaluation export, not a second fitter.
PCHIP derives its deterministic piecewise coefficients from frozen nodes; smoothing
and parametric splines retain their accepted curvature/coefficient state. No
training Dataset is reopened, no covariance is recomputed and no random seed is
consumed. Failures refuse instead of silently changing a scientific identity.

Saved JSON model numbers are parsed from their decimal tokens through the native
binary64 conversion before structure restoration. The JSON parser still validates
syntax and container layout, using exact small integer slot markers; numeric text
inside strings remains literal. This avoids approximate JSON numeric conversion
at tightly spaced, large-offset knots, and preserves existing saved payloads and
negative zero without a format migration or refit.

<a id="callback-buffer-lifetime-1280-dev097"></a>
### Callback buffer lifetime

Callback `nonlinear_fit` reuses one unchanged predictor matrix throughout its
SciPy least-squares evaluations. CORE retains it only for that callback sequence;
Python receives it read-only and Octave uses copy-on-write values. Each consumed
callback prediction/vector is released by the originating runtime, preventing
temporary storage growth with iteration count. Input files and unrelated owned
resources are preserved. Error exits release the same constant argument and
consumed outputs. The numerical optimizer and existing statistical calculations
are unchanged.

These real-valued callback operations reject complex operands and integers beyond
±2^53 before the float64 numerical conversion. They never discard imaginary
components or silently round large int64/uint64 values. Typed transport itself
continues to support all thirteen dtypes, including complex and exact integers.


`nonlinear_evaluate` accepts a live
`registered_callback` model with callback, parameter IDs/values, source and
binding SHA, declared predictor domain and bounds. It returns prediction and an
optional bounded finite-difference Jacobian without refitting. The callback
nonlinear fitter now computes covariance directly from the weighted Jacobian
SVD, avoiding the squared condition number of normal equations; it also reports
physical response RMSE/MAE, active bounds and parameter/observation counts.
Existing public `positive_translation` and `uniform_grid` operations are now
available through Script Bridge using their original Numeric implementation.

`nonlinear_fit` accepts `response_shape=column` for declared functional models:
N-by-1 predictor/response contracts are enforced before residual flattening.
Row vectors and matrices with the same element count are refused. The default
ordinary callback `vector` behavior remains compatible. The callback result also
reports weighted centered response variance for the declared weighting policy.

`prediction_uncertainty` also accepts a live `registered_callback` model in both
Script languages. It verifies the eligible CORE plan and exact source/binding
identity before callback evaluation. Numeric evaluates predictions and the
bounded central finite-difference Jacobian, then reuses the existing binary
propagation implementation for covariance checks, quantiles and future noise.
No refit or duplicate parameter uncertainty is performed. The callback result
adds `model_evaluation_kind=registered_callback`; CORE interprets this method
explicitly. `maximum_jacobian_rows` records the actual full callback query size
and `evaluation_blocks=1`; native expressions retain their 4096-row evaluator.
Expired callbacks and changed fitted model identities are refused.

Independent `model_export` also accepts `kind=registered_callback_source` with
`source` (exact UTF-8), `source_sha256`, `binding_sha256`, `language` (Python or
Octave), `entrypoint`, `parameters` and ordered `parameter_ids`. Its export options
must supply the matching accepted parameter values/IDs and one declared unit per
parameter. Source SHA, declaration digest syntax and entrypoint are validated;
explicit GX-TXT source dependencies are refused. The operation only generates
text and performs no source evaluation, fitting or statistical computation.

Both output languages embed the same exact source. Their adapters execute its
original runtime for each batched Nx1 query, validate finite real Nx1 responses,
and return the existing physical Nx2 mapping. Exact-integer responses outside
binary64's supported integer range are refused. The original source runtime and
its external imports/packages remain explicit dependencies; the Octave adapter
also needs Debian `timeout`. Original source is capped at 1 MiB and each generated
artifact at 2 MiB. LaTeX retains formal executable-function notation and exact
source identity instead of inventing a symbolic equivalent. Metadata records
120-second execution bounds, temporary-file cleanup, uncaptured state/dependencies
and separate source-versus-generated-adapter licensing. Native model exports
retain their existing independent evaluators and contracts.

<a id="natural-cubic-smoothing-diagnostics-and-bounded-gcv-dev097"></a>
### Natural cubic smoothing diagnostics and bounded GCV

`curve_model_fit('smoothing_spline', x, y, options)` preserves the natural cubic
objective `sum((y-f(x))^2) + lambda * integral(f''(x)^2 dx)`. Manual selection is
the default: supply finite nonnegative `smoothing_lambda`; zero interpolates.
The predictor must be distinct; the existing owner sorts it without changing
source Dataset row identities. This contract is unweighted and requires3..1M
finite real observations. Weights/sigma are refused rather than ignored.

Optional `smoothing_selection='gcv'` requires at least5 observations and explicit
positive increasing `gcv_lambda_bounds=[lower,upper]`. `gcv_grid_count` is3..65
(default17), `gcv_refinement_evaluations` is0..64 (default24). A deterministic
log-grid followed by local golden-section refinement retains the best evaluated
candidate. The receipt includes all candidates in columns lambda/EDF/SSE/GCV,
actual count/budget, bounds, criterion, selected facts and endpoint flag. It does
not claim a global minimum; bounds are expressed in predictor units cubed.

The Numeric-owned native banded LDL/selected-inverse implementation uses O(N)
work/storage and analytic differentiated trace calculations, not random trace
estimates. Outputs include `edf=trace(S)`, `residual_mean_dof=n-edf`,
`residual_variance_dof=trace((I-S)'*(I-S))`, `smoother_trace_squared`,
`smoothing_lambda`, `gcv_score=n*SSE/(n-edf)^2`, `gcv_available`, solver/precision
identity and a conservative native workspace bound of480Nbytes. This bound is
not a measurement of whole-Job peak memory. Internal arithmetic is long double;
public results are binary64. Ill-conditioned/nonfinite factorization refuses.
Lambda0 has EDF=N, zero residual traces and unavailable GCV (not a zero score).
The existing nodal model state, exact interpolation and evaluation contract stay
readable. Cancellation follows the existing supervised Numeric worker lifecycle.

Pass the raw result to public CORE `from_numeric` with model
`math.numeric.smoothing_spline` and operation `curve_model_fit`. CORE owns units,
applicability, assumptions and report text. EDF is not residual variance DOF;
fixed-lambda variance assumptions exclude smoothing bias and selected-lambda
uncertainty. GCV is neither probability nor a confidence interval.

<a id="explicit-logarithmic-response-dev097"></a>
## Explicit logarithmic response

`log_ratio(values, reference)` returns `gxtxt.log_ratio.v1`: natural logarithms of
the dimensionless ratio, exact reference, unchanged shape, count and method.
Inputs are real float32/float64, finite and strictly positive, with at most one
million elements per call. Reference must be finite/positive in the same units.
Integers require explicit conversion. No omission, clipping or replacement with
zero occurs. Near-reference values use log1p; extreme ratios avoid division overflow.

`log_response_retransform(log_predictions, options)` requires `reference` and
returns `gxtxt.log_response_retransform.v1`. `median` contains reference times exp
of each prediction. Its interpretation as a conditional median requires a Gaussian
log-error model; without that assumption CORE labels it a back-transformed fit.
Optional scalar `log_standard_deviation` supplies the Gaussian log-variance plug-in
arithmetic `mean` and bounded correction facts. It is not a finite-sample unbiased
estimator. `mean_available=false` and empty mean/scale/correction preserve missing
variance explicitly. Positive physical underflow/overflow refuses instead of
publishing zero/Inf, including when exp alone overflows but its product is finite.

Optional `lower`, `upper`, `confidence` require explicit `interval_kind`:
`log_mean_confidence` or `log_new_observation`. Bounds must have the prediction
shape, contain it, and use paired NaN gaps. Monotone transformation preserves the
captured kind and actual finite-row count. Default is `none`, with absent bounds.
CORE `log_response_plan` and `log_response_interpretation` own eligibility, units,
median-versus-mean meaning and interval target; no module should invent those labels.
Both operations have catalog discovery, Tcl typed operands and real Python/Octave
Script Bridge bindings. Tcl catalog calls supply the reference as the second operand
for `log_ratio`, and as an options field for `log_response_retransform`.

<a id="opt-in-exact-linear-influence-dev097"></a>
### Opt-in exact linear influence

`least_squares`, `linear_regression` and `polynomial_fit` accept
`influence_diagnostics=true` (default false). The existing fit/factorization is
performed once. The optional `influence` result uses its column-scaled QR/SVD
factor, retained residuals and captured estimated residual scale. It never forms
an N×N hat matrix and does not perform N deletion refits. Python and Octave Script
Bridge expose all three operations; Tcl uses the public operation catalog.

The versioned `gxtxt.linear_influence_numeric.v1` receipt returns `leverage`,
`cooks_distance`, `studentized_residual`, `deleted_residual`, `loo_prediction`,
`deletion_available`, `scaled_available`, and exact uint64 `input_row_index`.
Indices are one-based positions in the caller's original input, before explicit
nonfinite omission and removal of zero-weight rows. They are not automatically
Dataset row IDs. Weighted fits use the weighted design. Centered/scaled
polynomials retain their stable internal basis for these calculations.

Deletion formulas require a full-rank unconstrained linear-parameter model.
Nonlinear/robust/geometric operations reject the option. A rank-changing deletion
or leverage within `64*eps*max(1,p)` of one is unavailable. A zero or unavailable
estimated residual scale leaves Cook/studentized diagnostics as NaN, with a false
availability mask. This does not manufacture zero influence. Cook's distance uses
the estimated weighted residual mean square even for absolute precision weights.

The receipt retains original/retained counts, rank, degrees of freedom, finite
availability counts, maximum diagnostics, review thresholds and flagged counts.
Leverage above `2p/n` and Cook's distance above `4/n` are heuristic review aids.
CORE `influence_plan` and `influence_interpretation` own their labels, units,
applicability, qualifications and publication meaning. They are not outlier tests
or permission to delete observations. See the [CORE statistical API](../../../docs/api/STATISTICAL_RESULT_SEMANTICS_API_v1.md).

Opt-in limits are one million input rows, 128 coefficients and an upfront
conservative workspace estimate `80*N*p + 128*N + 64*p*p <= 512 MiB`.
Leverage evaluation uses blocks of at most 4096 rows. Default fits do not allocate
these diagnostics or original-row vectors. This estimate is not process peak RSS.
General matrix fits have the explicit CORE model identity
`math.numeric.linear_design`, with generic basis coefficient identities; they
are not relabelled as polynomial fits.

Primary conventions: [NIST regression diagnostics](https://www.itl.nist.gov/div898/software/dataplot/refman1/auxillar/line_fit.htm)
and [R deletion diagnostics](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/influence.measures.html).

## Model-aware initialization

The public `fit_initial_guess` operation proposes bounded initial parameters;
existing `nonlinear_evaluate` supports manual parameter-only evaluation. See
[the initialization contract](../../../docs/api/FIT_INITIALIZATION_v1.md).


### Compact direct-model parameters

`curve_model_parameter_state(state, parameters)` is available through Octave,
typed Tcl `callOperation`, and both Script languages. Empty parameters retain the
current values. The `gxtxt.curve_parameter_state.v1` receipt contains a bounded
reconstructible model, ordered `parameter_ids`, `unit_roles`, values, intrinsic
bounds and a false fixed mask. It performs validation/mapping only; evaluation
continues through `curve_model_evaluate`. No statistics or optimization occur.

Arc order is center_x, center_y, radius, angle_start, angle_end; angles are radians,
radius positive and the oriented angle interval nonzero. Bezier controls preserve
the existing column-major X-then-Y order. Open parametric polynomial coefficients
preserve descending powers for X then Y and their dimensionless normalized
parameter domain. Fourier order is constant, cos_1, sin_1, ... with fixed origin
and positive period, bounded to order1..63 for manual editing. Existing accepted
model states/exports are unchanged; manual identifiers are explicit adapter fields.
Unneeded source arrays and fit diagnostics are excluded from the compact state.
Spline/PCHIP interpolation state is not a finite manual optimization vector and
is explicitly refused. Parameter edits create an unaccepted exploratory model;
they do not change direct fitting behavior or reuse an old uncertainty estimate.


See [retained queries and local inverses](../../../docs/api/RETAINED_MODEL_QUERIES_v1.md)
for model_query/model_inverse, per-row extrapolation flags, analytic derivatives,
singular reciprocal slopes and explicit branch/tolerance contracts.

## Exact saved-model decoding

`model_state_decode(saved_json)` accepts JSON text or an exact typed uint8 vector
through public Octave, typed Tcl and Python/Octave Script Bridge. It returns the
decoded model structure. Decimal numbers use locale-independent binary64 parsing,
including signed zero and subnormals; overflow/nonfinite literals are refused.
This is the saved Numeric floating-point model format, not an arbitrary integer
identity codec. Canonical uint64 source identities remain in typed resources.
Strings, booleans, nulls and array structure retain Octave JSON semantics.

The canonical packaged native adapter tokenizes number slots in linear time;
Octave owns JSON structure validation and restores exact numbers. Limits are
128 MiB each for input and indexed syntax, 16 Mi numeric values, nesting depth16,
65536 objects, 2 Mi arrays and 512 bytes per numeric literal. These allocation
bounds are not a total-process RSS guarantee. Malformed/over-budget input is
refused without a sampled substitute. The previous exact decoder remains a
2 MiB fallback when the native adapter is absent. Standalone `model_export`
keeps its independent 2 MiB artifact budget and embeds numeric constants without
requiring this decoder. Local inverse operations decode a textual model once,
then reuse it; PCHIP values and derivatives share one public spline construction.

## Captured fit input policy

`fit_input_policy(model, captured_state)` describes model-owned observation order,
duplicates, aggregation and terminal endpoint decisions in
`gxtxt.fit_input_policy.v1`. It performs no fitting or statistical calculation.
The [preprocessing contract](../../../docs/api/FITTER_PREPROCESSING_v1.md#model-owned-input-policy)
lists supported models, required parametric state and Fitter row-stage consumers.

## Retained model geometry

`model_geometry(model, options)` returns `gxtxt.model_geometry.v1`: an exact
Native2D definition or `sampled_required` with a reason. Options require a finite
increasing `domain`; physical `orientation`, `translation`, `polar_frame` and
explicit `extrapolation` follow `model_query`. No fitting or inference occurs.
Known polynomial spans of degree at most three map exactly through analytic
endpoint tangents; arcs retain their center/radius/sweep. The original parameter
breaks map piecewise affinely onto Native2D’s equal-part normalized parameter.
See [transfer contract](../../../docs/api/FITTER_WORKBENCH_TRANSFER_v1.md).

## Derived physical properties

Evaluate named parameter expressions with full correlated covariance, physical
units and explicit unavailable states through the public CORE/Numeric APIs.
Fitter exposes linear thresholds, exponential characteristic intervals, regional
knees and custom expressions in **Results → Derived physical properties…**.
Use **Evaluate properties**, review the report, then **Publish evaluated result**
to create a Dataset from that captured receipt without refitting.
See [declarations, scientific assumptions and Script operations](../../../docs/api/DERIVED_PHYSICAL_PROPERTIES_v1.md).

## Deterministic source characteristics

`fit_characteristics(X, Y, options)` returns bounded deterministic shape facts
and the existing exact ordered observation signature. It accepts two finite
real floating vectors of2..1000000 rows; it never fits or accepts a model.
Thresholds, unavailable states and physical coordinate basis are explicit.
See [the source model suggestion contract](../../../docs/api/MODEL_SUGGESTIONS_v1.md).

## Full observation-covariance regression

`generalized_least_squares(A, y, C, options)` fits a finite real linear design
with full absolute or relative-scale observation covariance. Positive covariance
uses Cholesky whitening; explicit singular policy enforces exact null-mode
equations. Coefficient covariance, effective residual DOF, whitened residual
facts and source fingerprints are retained. Pass `result.summary` to public CORE
`gls_interpretation` and `gls_report` for unit-aware validated meaning.
See [the full-covariance contract and Script example](../../../docs/api/GENERALIZED_LEAST_SQUARES_v1.md).

`polynomial_gls(x, y, degree, C, options)` adds the existing centered/scaled
polynomial basis, physical coefficient/covariance transformation and stable
`polynomial_evaluate` model. Degree is bounded to 0..63; no rows are silently
removed. Both GLS operations can feed the common CORE `from_numeric` adapter
and its existing parameter-uncertainty/report consumers, under explicit
correlated-noise assumptions.

## Implicit equation models

`implicit_model_compose`, `implicit_fit`, `implicit_evaluate` and `implicit_query`
provide physical two-coordinate equations through the existing formula/Ceres
and root owners. Equation residuals, physical reference normalization and
explicit response branches remain separate contracts. See
[Implicit equation models](../../../docs/api/IMPLICIT_EQUATION_MODELS_v1.md).

## Shared physical complex responses

`complex_model_compose`, `complex_fit`, `complex_evaluate`, `complex_residuals` and
`complex_from_polar` expose shared physical parameters, explicit Cartesian
component covariance and separate magnitude/phase conversion. See
[Joint complex response fitting](../../../docs/api/COMPLEX_RESPONSE_MODELS_v1.md)
for units, count/shape/budget, phase and Gaussian-conditioning contracts.
The shared model query/inverse/geometry/export operations accept retained real,
imaginary, magnitude and explicitly referenced db20 projections. Residual
evaluation never refits or establishes training parameter inference.

`fit_formula_compose` also accepts2–32 expression strings with a matching list
of response units in `response_unit`. Shared parameters require explicit units;
each must occur in at least one response. Each response is checked by the same
dimensional compiler. `nonlinear_fit` requires inverse-variance normalization
for multiple responses; complex fitting additionally supplies its full declared
Cartesian covariance transformation. Scalar formula behavior is unchanged.

The native declared-expression adapter accepts1–32 predictors and1–32 responses.
Predictor, prediction and Jacobian buffers each obey the512MiB bound. Compiled
operand indices are checked against the actual column count. Three complex
channels use22 internal predictors for physical frequency and the Cartesian
Cholesky transformation; these remain internal bindings, not new scientific axes.

## Physical two-predictor surfaces

`surface_model_compose`, `surface_fit`, `surface_evaluate`, `surface_grid` and
`surface_residuals` use exact physical X/Y predictors and a Z response. Point
and Y-by-X grid inputs retain original missing-cell indices; common CORE owns
the qualified training/evaluation interpretation. `surface_model_state` and
`surface_model_restore` preserve the full recipe, parameters, domain and hashes
without refitting. Independent export uses the existing `model_export` operation.
See [surface contracts](../../../docs/api/SURFACE_RESPONSE_MODELS_v1.md) and
[Fitter/Script lifecycle](../../../docs/api/FITTER_SURFACE_v1.md).

## Physical rational responses

`rational_model_compose`, `rational_domain`, `rational_fit`, `rational_evaluate`,
`rational_residuals`, `rational_model_state` and `rational_model_restore` expose normalized polynomial
quotients with physical units and whole-interval pole guards. Shared Ceres,
parameter covariance, retained query and standalone exports remain their public
owners. Canonical `math.numeric.rational` supplies common CORE interpretation,
conditional inference and matched-observation comparison. See
[rational response contracts](../../../docs/api/RATIONAL_MODELS_v1.md).

## Akima and explicit-knot B-splines

Existing `curve_model_fit` and `curve_model_evaluate` accept `akima` and
`bspline`, with immutable physical knots, declared continuity/boundary policies,
retained exact geometry and independent export. Shared CORE distinguishes
interpolation from unweighted fixed-knot approximation and refuses unvalidated
parameter inference. See [knot model contracts](../../../docs/api/KNOT_SPLINE_MODELS_v1.md).

## Pixel and shared calibration uncertainty

`digitization_uncertainty` accepts bounded physical calibration Jacobians and
explicit pixel/calibration distributions; `digitization_covariance` materializes
retained x/y/xy covariance without discarding shared dependencies. See the
[public contract](../../../docs/api/DIGITIZATION_UNCERTAINTY_v1.md) for exact
shapes, units, original row order, override meaning and first-order limitations.
