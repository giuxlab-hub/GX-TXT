# Akima and explicit-knot B-spline models

SPDX-License-Identifier: GPL-3.0-or-later

`NUMERIC_API_v1` uses existing `curve_model_fit(name,x,y,options)` and
`curve_model_evaluate(state,q,options)` operations for `akima` and `bspline`,
available through Tcl and real Python/Octave Script Jobs. Retained state is
`gxtxt.knot_spline.v1`; canonical IDs are `math.numeric.akima` and
`math.numeric.bspline`.

## Common inputs and state

Inputs must be paired finite real vectors with strictly increasing predictors.
The API does not sort, merge duplicates or omit nonfinite values. Bounds are
2–65,536 observations, with at least five for Akima. Exact integers outside
binary64's integer range are refused before conversion. `x_unit` and `y_unit`
default to dimensionless `1`; declare physical units when appropriate.

State preserves exact knots, piecewise cubic coefficients in physical
`x-left_knot` coordinates, degree, method class, continuity, boundary choice,
endpoint slopes, source count, units and SHA256 identity. Lower-degree pieces
have zero leading coefficients. Shared `model_state_decode` preserves decimal
values. Changing knots, coefficients, degree, boundary or units invalidates
retained state. The hash provides integrity, not authenticity against someone
deliberately constructing a different model.

## Akima interpolation

`curve_model_fit('akima',x,y,options)` constructs a cubic Hermite interpolator
with C1 continuity at the original observation knots. Local variation of adjacent
secant slopes determines interior derivatives. Zero total variation uses the
adjacent slopes' mean; there is no global relative-weight cutoff. The original
Akima weighting may overshoot; it is not modified Akima.

`boundary='extrapolated_slopes'` extends endpoint secants linearly to determine
endpoint derivatives. These are construction values, not extra observations.
`boundary='clamped'` requires two `endpoint_slopes` in physical response-unit/
predictor-unit. Degree and knot overrides are refused. Zero residuals at knots
do not establish statistical fit quality. The
[SciPy Akima reference](https://docs.scipy.org/doc/scipy/reference/generated/scipy.interpolate.Akima1DInterpolator.html)
describes the local interpolation principle and continuity.

## Fixed-knot B-spline approximation

`curve_model_fit('bspline',x,y,options)` requires `knots`: 2–257 increasing
simple breakpoints, with endpoints exactly equal to the observed minimum and
maximum. No automatic knot placement or repeated-knot policy is selected.
`degree=1|2|3` defaults to3 and gives C0/C1/C2 interior continuity. Each knot
span must contain at least degree+1 distinct observations, a conservative
sufficiency rule. Underidentified spans are refused.

Existing GNU Octave `splinefit` performs unweighted least squares in its
B-spline basis. The adapter preserves breakpoints and captures polynomial
pieces, adding no solver, penalty or robust-weight loop. There is no
interpolation constraint; exact agreement on special inputs does not change
the declared approximation method.

Boundary choices are `free` (default), `periodic`, cubic `natural` (zero endpoint
second derivatives), and cubic `clamped` with two explicit `endpoint_slopes`.
Periodic construction matches value and derivatives through degree−1 across
the endpoints; it does not wrap evaluation coordinates. Recorded basis
dimension describes the function space, not measured rank or confidence.
[GNU Octave splinefit](https://docs.octave.org/latest/Polynomial-Interpolation.html)
is the existing basis and boundary-constraint owner.

## Evaluation, geometry and export

Evaluation accepts1–1,000,000 finite query values and optional `derivative=true`.
Outside-support evaluation defaults to `extrapolation='error'`. Explicit `allow`
uses the first/last polynomial piece and flags extrapolation; observed support
does not expand. A degree-one interior slope jump has no unique derivative:
the tangent is NaN and generic query marks it invalid. Equal adjacent slopes
retain a valid derivative.

`model_query` requires the complete captured knot domain as reference support,
even for a smaller requested subset. It retains physical orientation,
translations, derivatives and inverse slopes. `model_geometry` converts an
explicit output interval to exact Native2D lines or cubic Bézier pieces within
the existing256-part limit. Larger Akima states use the existing explicitly
sampled representation.

`model_export` emits standalone Python/Octave evaluators and LaTeX through the
existing emitter. Export bounds must stay inside retained knots. Metadata
preserves model ID, degree, continuity, boundary, endpoint slopes, knots and
state SHA. Units and scientific IDs cannot be relabelled. Query, geometry and
export perform no fitting or inference.

## Common statistical meaning

Use `from_numeric('math.numeric.akima','curve_model_fit',result,context)` or
the corresponding `math.numeric.bspline` call on the public
[CORE statistics API](STATISTICAL_RESULT_SEMANTICS_API_v1.md).
`gxtxt.knot_spline_summary.v1` carries bounded method, domain, complexity,
units and identity facts. CORE distinguishes interpolation from fixed-knot
least squares and supplies descriptive residual meaning. Injected covariance,
standard errors, rank, inferential DOF and reduced chi-square are refused.
Akima R² is not applicable; neither model's residuals establish parameter CIs.
Original datasets remain unchanged. Published samples are model evaluations,
not new observations. Dataset-aware Fitter controls consume these contracts
separately.
