# Generalized least squares with observation covariance

Use `NUMERIC_API_v1/generalized_least_squares(A, y, C, options)` for a
linear-in-parameters model `y = A beta + error`. Supply a finite real floating
N-by-P design, one N-element response vector, and the full N-by-N observation
covariance. Limits are 2048 rows and 64 coefficients. Every observation remains
in its original order: reorder both covariance axes whenever rows are reordered.
Nonfinite values, mismatched shapes and unidentified coefficients are errors.

**Absolute covariance** is the default. `C` contains the declared covariance of
measurement errors in squared response units. Coefficient covariance is conditional
on that supplied structure; it is not rescaled to make a reduced objective equal
one. `covariance_semantics=relative_scale` means the true covariance is an unknown
common nonnegative scale times `C`. The scale is estimated from the whitened
objective and residual degrees of freedom. An estimated covariance shape has its
own uncertainty, which this conditional fit does not propagate automatically.

## Positive and singular covariance

Positive covariance uses a lower Cholesky factor in captured row order. The solve
reuses the public linear least-squares implementation after whitening and column
scaling. Coefficient covariance uses the same QR/SVD factor authority as ordinary
regression. No inverse of the observation covariance or diagonal jitter is formed.

Singular covariance is rejected unless `singular_policy=exact_constraints` is
explicit. Zero-variance eigenmodes then impose exact equations on the model and
response. Inconsistent equations fail. Positive eigenmodes supply the remaining
stochastic least-squares problem. Ignoring covariance-null residuals would change
the model and is not this policy. The construction follows the same constrained
interpretation documented for [generalized least-squares singular covariance](https://www.mathworks.com/help/matlab/ref/lscov.html).

The effective residual DOF is positive covariance rank minus the number of
coefficient directions remaining after exact constraints. Original physical rows,
positive modes, null modes and exact constraint rank are reported separately.
Known absolute covariance can still determine coefficient covariance at zero
residual DOF. Unknown relative scale is unavailable in that case; its covariance
and standard uncertainties stay NaN. Fully determining exact equations produce
a deterministic coefficient solution, explicitly labelled as conditional on
those exact equations.

Default eigenvalue and symmetry relative tolerances are 64*eps*N; the constraint
relative tolerance is 512*eps*max(N,P). Each may be set explicitly between 0 and 1e-6.
Eigenvalues below the declared relative cutoff are treated as null modes, including
roundoff-sized negative values; a more negative eigenvalue fails. Symmetry is
checked before averaging the two triangles. The original and effective covariance
fingerprints, cutoff, smallest eigenvalue and constraint discrepancy/limit are
retained. These tolerances are numerical rank policy, not scientific regularization.

## Results and interpretation

The Numeric result contains physical coefficients/covariance/standard uncertainties,
predictions, observed-minus-fitted residuals, whitened residuals, exact source/design
fingerprints and bounded method facts. Its `summary` omits the three observation
vectors; pass that bounded summary to the public CORE operation:

`STATISTICAL_RESULT_SEMANTICS_API_v1/gls_interpretation(summary, context)`

Context requires `response_unit`, `covariance_unit`, ordered `parameter_ids`,
ordered `parameter_units` and `noise_model` (`second_moments_only` or `gaussian`).
`design_label` is optional. Numeric values must already use those units. CORE
checks covariance_unit/response_unit against response_unit through the shared
Unit Registry differential plan, requiring scale 1. For example, fitting response
in V with covariance values expressed in mV^2 is rejected: convert values first.
Affine coordinate offsets do not enter covariance scaling. Parameter units belong
to the supplied design-column convention and must be declared accurately.

CORE returns `gxtxt.gls_interpretation.v1` with parameter identities, quantity
statuses, physical and effective populations, covariance meaning, and residual
qualifications. `gls_report`, common `validate`, `validated_result`, `report` and
protected `publication_metadata` use the same authority. This summary does not
supply likelihood ranking, confidence intervals or prediction intervals. Gaussian
inference requires additional distribution assumptions; covariance itself only
requires the declared second-moment model.

Whitened residual sequence facts reuse `residual_sequence` and its CORE
interpretation. Default maximum lag is min(10,N-1), bounded by the available
positive modes; explicit `max_lag` is 1..64. Cholesky innovations retain source-row
order. Singular-model eigenmodes have no temporal order. Fitted residuals retain
parameter-estimation dependencies; a small lag statistic does not prove that the
noise covariance is correct. No diagnostic automatically removes observations.

## Script example

In Python, use `gxtxt_api_call` with NumPy floating arrays. In Octave, use the same
operation through `gxtxt_api_call` or call `gxtxt_numeric_v1` directly. Both public
Script bindings use the existing managed scientific binary transport.

```python
from gxtxt import gxtxt_api_call as call
fit = call('NUMERIC_API_v1', 'generalized_least_squares', [A, y, C])
meaning = call('STATISTICAL_RESULT_SEMANTICS_API_v1', 'gls_interpretation', [
    fit['summary'], dict(response_unit='V', covariance_unit='V^2',
    parameter_ids=['intercept', 'slope'], parameter_units=['V', 'V/s'],
    noise_model='gaussian', design_label='Physical line')])
print(call('STATISTICAL_RESULT_SEMANTICS_API_v1', 'gls_report', [meaning]))
```

The design must be `[1, x]` in this example, with x in seconds. Supplying a
covariance matrix is an explicit scientific declaration; diagonal precision
weights alone cannot represent correlations.

## Centered polynomial models

`polynomial_gls(x, y, degree, C, options)` uses the same centered/scaled
Vandermonde construction and physical coefficient transformation as
`polynomial_fit`. Degree is 0 through 63. `center_scale` defaults to true;
all other options have the GLS meaning above. Coefficients and covariance are
returned in descending powers of the supplied x coordinates. The retained
`scaled_coefficients`, `scaled_covariance`, `x_center` and `x_scale` preserve
stable evaluation through the existing `polynomial_evaluate`, including large
coordinate offsets. The summary identifies `polynomial_gls` and fingerprints
the original x vector. Missing uncertainty remains NaN after transformation.

## Retained regression results and intervals

Use `from_numeric(model_id, operation, result, context)` to obtain the standard
`gxtxt.statistical_result.v1` representation. General design GLS accepts the
existing linear-design, linear, through-origin or polynomial model identities;
the coefficient ordering must match the declared design. `polynomial_gls` uses
only `math.numeric.polynomial` with canonical `power_N` parameter identities.
No scientific model or parameter is renamed.

Context declares the existing x/y units and functional orientation, plus
`covariance_unit`. Its `noise_model` is `unspecified`,
`correlated_gaussian_known_covariance` for absolute covariance, or
`correlated_gaussian_estimated_scale` for relative covariance. Independent-noise
labels are rejected. The common result embeds the same validated full-covariance
meaning; physical observation count, stochastic DOF, whitened objective and
physical response RMSE remain distinct. Covariance is available without claiming
a Gaussian distribution. R-squared, diagonal likelihood AIC and independent-error
bootstrap/influence plans do not apply to this full-covariance result.

The existing `parameter_inference_plan`, Numeric `parameter_uncertainty`,
`with_parameter_uncertainty` and parameter reports consume captured coefficient
covariance without refitting. Declared Gaussian absolute covariance uses normal
marginal intervals, including zero residual DOF; estimated scale uses Student t
with the stochastic DOF. Coordinates with exactly zero conditional variance are
excluded from ordinary marginal intervals. No Gaussian declaration means no
Gaussian interval. Future-observation bands require an explicit query covariance
contract and are unavailable here. Smoothing, baseline correction or logarithmic
response transformations require propagated covariance and are rejected by this
retained adapter; coordinate translations retain their explicit existing context.
