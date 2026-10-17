# Joint complex response fitting

The public `NUMERIC_API_v1` operations share the existing dimensional expression
compiler, real multi-response Ceres solver and covariance owner. CORE provides
all statistical interpretation; the adapter does not recompute fit statistics.

| Operation | Arguments | Result |
|---|---|---|
| complex_model_compose | recipe | Frozen complex physical model |
| complex_fit | model, frequency, observations, measurement, optional solver options | Shared physical parameters/covariance and complex residuals |
| complex_evaluate | model, frequency, optional derivative options | Retained complex values, magnitude, phase and real-component derivatives |
| complex_residuals | model, frequency, observations, measurement | Captured-model physical residuals and normalized evaluation metrics, without fitting |
| complex_from_polar | magnitude, phase, options | Physical complex observations and conversion receipt |

## Physical model declaration

A recipe contains `predictor_id`, `predictor_unit`, `channels` and `parameters`.
The predictor must have a linear frequency unit, such as Hz or kHz. Frequencies
are positive finite values; zero-frequency limits require a separate explicit
model and are refused by this contract. A channel has `id`, `unit`,
`real_expression` and `imaginary_expression`. Declare 1–3 channels and 1–32
shared parameters. Channel IDs must be unique. The `gxtxt_` symbol prefix is
reserved for internal coordinate bindings.

Parameters use the existing formula fields `id`, `unit`, `initial`, optional
`lower`, `upper` and `fixed`. Shared parameters require explicit physical units.
Individual responses may omit a parameter, but every parameter must occur in
at least one response. CORE checks every expression's dimensions and internal
unit conversion. Real and imaginary parts of a channel have the same unit.
No model text is executed as Python, Octave or Tcl code.

For a series RLC impedance, use real expression `resistance` and imaginary
expression `2*pi*f*inductance-1/(2*pi*f*capacitance)`, with predictor `f` in Hz,
impedance/resistance in Ohm, inductance in `Ohm*s`, capacitance in `s/Ohm`.
These are the physical henry and farad dimensions in the supported unit grammar.
Each parameter may have independently declared positive bounds. A second channel
can describe admittance in `1/Ohm` using the same parameters. Shared poles and
zeros are encoded by the supplied real/imaginary equations and constraints;
convergence is not a proof that an arbitrary physical model is identifiable.

## Cartesian covariance metric

Observations are a finite N-by-channel complex floating-point matrix; a real-only
channel is also valid with zero imaginary values. Fitting accepts 2–65,536 rows
in their original order, without hidden omission, sorting or display reduction.
Numerical working arrays use binary64/complex128; caller source data is immutable.
Physical input hashes identify these working values and shapes, not an external
Dataset file. Dataset callers must also retain their canonical source fingerprint.

`measurement` requires:

- `semantics = absolute`;
- `component_units` in channel order: real1, imaginary1, real2, imaginary2, …;
- `layout = shared` with covariance M-by-M, or `per_observation` with covariance
  M-by-M-by-N, where M is twice the channel count;
- `covariance`, whose (i,j) entry has the product of component i and j units.

The covariance may correlate components and channels within each frequency row.
Different frequency rows are assumed independent. Covariance must be positive
definite and symmetric within the documented roundoff tolerance, 64·epsilon·M
relative to its largest absolute entry. The accepted symmetric part is recorded
by a separate hash. Singular/indefinite covariance is refused; there is no jitter,
regularization or discarded null mode. Covariance is never inferred from a
normalization value or a phase/magnitude display scale.

The objective is the sum of squared innovations L⁻¹(observed − predicted), where
LLᵀ is the supplied Cartesian covariance. The existing real solver optimizes all
components jointly and computes one physical parameter covariance. This scaling
follows the [Ceres covariance contract](https://ceres-solver.readthedocs.io/latest/nnls_covariance.html).
Weights are absolute; parameter covariance is not multiplied by residual variance.
The Gaussian error assumption remains a separate caller declaration.

Solver options expose the existing solver/strategy, iteration/time/tolerances,
parameter scales and thread controls. Defaults are 400 iterations and 30 seconds.
Bounds/fixed values come from the physical model recipe. The loss is quadratic;
robust component losses, estimated covariance scale and cross-frequency covariance
require different declared contracts and are refused here. Actual convergence,
bounds, rank and solver diagnostics remain in the captured result.

## Phase, magnitude and persistence

`complex_from_polar` accepts matched finite real matrices. Options explicitly
name `phase_unit = rad|deg`, `magnitude_scale = linear|db20` and `channel_units`.
Linear amplitudes are nonnegative. db20 amplitude requires one positive physical
`reference` value per channel. This is amplitude dB, not power dB. Integer phase
turns yield the same physical complex values within floating-point accuracy.
Zero amplitude has unavailable phase. The receipt retains input hashes and
conversion options. It does not propagate phase/amplitude covariance: supply the
Cartesian covariance explicitly and retain the conversion receipt as provenance.

Fit output separates physical complex `predicted`/`residuals` from dimensionless
`whitened_predicted`/`whitened_residuals`. `wrapped_phase_residual` is the principal
phase of observed times conjugate(predicted); `phase_residual_valid` excludes zero
observed or predicted amplitude. Phase is a diagnostic, not another objective
term added to magnitude. Evaluation returns magnitude, principal phase in radians,
and a validity mask. `jacobian=true` and `predictor_derivative=true` use the shared
real expression derivatives; derivative rows retain interleaved component order,
with the existing column-major response-block layout. No evaluation refits.

`gxtxt.complex_model.v1` preserves recipe, physical parameters, channel/component
identities and declaration hash. Use the public `model_state_decode` for exact
saved JSON numbers. Retained validation compares ordered identities, normalizes
only serialization list orientation/empty lists, and reuses the formula owner
for bounds and fixed-value checks. Altered expressions/units/bindings refuse.

Python/Octave calls use the table's argument order through `gxtxt_api_call`.
Managed scientific arrays carry complex64/complex128. The canonical Dataset
publication contract supports real numeric Variables: publish explicit grouped
real and imaginary Variables with their physical units and component identities.
Their reconstruction is lossless. A complex-valued Dataset dtype is not supported
by that publication contract. Tcl's typed facade represents complex values with
separate real/imaginary fields. There is one shared scientific API facade.

## Common CORE interpretation

Call `STATISTICAL_RESULT_SEMANTICS_API_v1.from_numeric` with canonical model
`math.numeric.complex_response`, operation `complex_fit` and the captured result.
Its bounded `context.complex` records physical frequency-row count, normalized
real-component count, channel/parameter units, covariance layout and exact input/
formula hashes. `n` counts N·M residual components; degrees of freedom use the
existing Numeric rank. R-squared and a pooled physical RMSE across unlike channels
are unavailable. The objective is dimensionless and parameter covariance retains
the physical parameter basis.

Declare `noise_model = independent_gaussian_known_sigma` only for Gaussian
independent innovations under the supplied covariance and independent frequency
rows. This enables existing local normal parameter intervals and chi-squared
interpretation. `unspecified` does not manufacture Gaussian intervals. Failure to
converge, insufficient rank, active bounds or invalid covariance retain unavailable
inference. Ordinary single-response likelihood comparison is refused. General and
parameter-only reports include the same covariance, phase and conditioning limits.

## Residual evaluation without fitting

`complex_residuals` accepts 1–65,536 frequency rows, a retained physical model,
observations and the same explicit Cartesian covariance contract. It uses the
same compiled whitening expressions and existing residual-metric owner. The
parameters remain unchanged. Output includes physical and whitened residuals,
wrapped phase diagnostics, `n`, `sse`, `rmse`, `mae`, `max_abs_error` and
`fit_performed=false`. These scalar errors describe dimensionless innovations,
not pooled physical errors across channels. There is no training DOF, parameter
covariance, solver receipt or optimization.

Pass the result to common CORE `from_numeric` with model
`math.numeric.complex_response` and operation `complex_residuals`. The versioned
`gxtxt.complex_residual_summary.v1` establishes `sample_role=evaluation` and
preserves physical/covariance/formula identities. Training inference is
`not_applicable`; attempts to relabel the record as training or inject training
covariance/DOF are refused. Reports retain this qualification.

## Retained scalar display projections

The existing public `model_query`, `model_inverse`, `model_geometry` and
`model_export` accept `gxtxt.complex_projection_model.v1`. Its closed fields are
`schema`, `kind=complex_projection`, `recipe`, captured `parameters`,
`declaration_sha256`, `channel_id` and `projection=real|imaginary|magnitude|db20`.
The complete physical model stays attached to the selected channel projection.
Only db20 adds `reference={value,unit}`: a positive reference in the exact channel
unit. The resulting ordinate unit is dB; other projections retain the channel
unit. The reference cannot be attached to a linear projection.

Query options declare a positive increasing `domain`; only physical `y_of_x`
orientation and zero translation are accepted. Outside-domain queries require
explicit `extrapolation=allow`. Derivatives use existing coordinate AD and the
projection chain rule. Magnitude at zero is valid with an unavailable derivative;
zero-amplitude db20 is unavailable. Physical tangent floors retain their existing
meaning. Local inversion requires an explicit continuous sign-changing bracket
and makes no global uniqueness claim. Geometry requests report
`sampled_required`, and unavailable endpoints are refused.

Standalone Python/Octave exports preserve the full physical recipe, selected
channel/projection, parameter identities/units, declaration hash and dB reference
in metadata. They evaluate frozen parameters, enforce the positive retained
frequency domain and refuse zero-amplitude dB. Export unit/model/parameter
overrides that conflict with the captured identity are rejected. Use
`model_state_decode` for exact JSON values; executable constants retain 17
significant decimal digits. Wrapped phase remains a separate diagnostic through
`complex_evaluate`; it is not represented as a globally continuous scalar curve.

Fitter uses these same owners through its [complex response workflow](FITTER_COMPLEX_v1.md),
including exact Dataset channel/covariance binding, physical controls, retained
resources, recipes, publication and Python/Octave Script consumers.
