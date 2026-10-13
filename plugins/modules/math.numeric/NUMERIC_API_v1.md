# `NUMERIC_API_v1`

SPDX-License-Identifier: GPL-3.0-or-later

## 1. Scope and stability

`NUMERIC_API_v1` is the public mathematical/numerical service of bundled CORE module `math.numeric`. API version `1` is independent of the GX-TXT release number and of the module implementation version. Existing v1 calls are retained where practical; new methods/results may be added additively without changing established call signatures.

The API provides mathematical primitives. It includes reusable FFT/IFFT, analytic-signal construction, transform-coordinate, detrending and window-generation primitives, but it does not define domain-specific spectrum/PSD workflows, model-specific fitting semantics, chromatographic interpretation, UV/Vis interpretation or chemistry-specific processing.

## 2. Discovery

The public service provides `polar_coordinates(X,Y,options)` and
`cartesian_coordinates(theta,radius,options)`, available in Octave and both
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

Convenience wrapper over the same LS foundation. `intercept=true` by default. Adds `slope`, `intercept`, `intercept_included`, X and Y.

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

## 10. Smoothing and filtering

### `smooth(x, y, options)`

Methods: `moving_mean`, `moving_median`, `savitzky_golay` (`savgol` alias), and `local_polynomial`. All v1 smoothing windows are explicit positive odd integers. Savitzky-Golay requires explicit polynomial `degree` (default 2), a uniform X grid, and `sgolayfilt` from the Octave `signal` package. `local_polynomial` performs local polynomial least squares using the actual X coordinates and is therefore the corresponding generic choice for non-uniform X. Returns preserved X, smoothed Y, residuals and endpoint policy.

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
- `anchors`: interpolated anchor points, with `anchor_method=linear|pchip|spline` and explicit extrapolation policy.

Returns `baseline` and `corrected` separately plus method/degree/coefficients where applicable.

Tcl provides `baseline x y options` for constant/linear/polynomial and `baselineAnchored x y anchorX anchorY options` for anchors.

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

First-order linear propagation `C_y = J C_x J^T`. `input_kind=standard_uncertainty` accepts a standard-uncertainty vector and constructs a diagonal covariance; `input_kind=covariance` accepts the full covariance matrix. Returns output covariance and standard uncertainties.

Tcl: `propagateIndependentUncertainty`, `propagateCovariance`.

## 15. Dataset-aware operations

All forms below read through Table Stream v3 and resolve stable variable identities. Tcl Dataset calls accept `selection_id` and resolve it through Dataset Selection API v1 before execution. Direct Octave Dataset calls accept the corresponding Dataset Selection v1 structure in `options.selection`; callback-bearing `dataset_nonlinear_fit` therefore remains usable without a private registry dependency. Units are reported, never converted.

| Operation | Octave dispatcher operation | Tcl facade | Notes |
|---|---|---|---|
| integration | `dataset_integrate` | `integrateDataset` | reports Y*X result unit |
| cumulative integration | `dataset_cumulative_integrate` | `cumulativeIntegrateDataset` | aligned vector |
| differentiation | `dataset_differentiate` | `differentiateDataset` | reports Y/X result unit |
| interpolation | `dataset_interpolate` | `interpolateDataset` | explicit target X |
| arbitrary resampling | `dataset_resample` | `resampleExplicitDataset` | explicit target X |
| uniform resampling | `dataset_resample_uniform` | `resampleUniformDataset` | step-based |
| legacy uniform resampling | `dataset_resample_uniform` by default | `resampleDataset` | preserved v1.0.0 Tcl name; scalar fifth argument is a step; `grid=explicit` selects arbitrary target X |
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

## Mathematical foundation operations

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

## Geometry, sparse, equation and statistics foundation actions

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
