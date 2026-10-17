# Retained model queries, derivatives and local inversion

These NUMERIC_API_v1 operations are shared by Tcl, Python and Octave callers.
They evaluate an explicit model state without fitting or computing uncertainty.
A caller must supply the retained training domain; an owning scientific module
must obtain it from its verified result provenance. Numeric does not invent one.

`model_query(model, query, options)` accepts1..1000000 finite real query values.
Options require `domain=[lower,upper]` and accept `extrapolation=error|allow`
(default error), boolean `derivative` (default true), and `tangent_floors=[fx,fy]`
(default zero). Intrinsic model restrictions, including spline and normalized
parametric domains, still apply when extrapolation is explicitly allowed.

The gxtxt.model_query.v1 result includes physical model-coordinate `points`,
`predicted`, per-row `is_extrapolated`, `derivative`, `inverse_derivative`, their
separate validity masks, tangents, method and the explicit domain/policy.
For a scalar model these are dy/dx and dx/dy. For a parametric XY curve they are
ratios of its analytic coordinate tangents. A zero or user-excluded denominator,
nonfinite ratio or unresolved derivative yields NaN with a false validity flag.
The two floors have the units of X/query and Y/query respectively. Zero defaults
do not claim to detect every ill-conditioned near-vertical or near-horizontal
case; select floors appropriate to the scientific coordinate scales.

Expression models use the existing compiled expression VM with two-sided
infinitesimal branch selection and automatic differentiation. No finite-difference
step is chosen. A genuine abs/positive-part/min boundary disagreement is
unavailable; a differentiable composition such as abs(x)^2 at zero remains valid.
Some singular primitive compositions can conservatively remain unavailable.
Ordinary fitting, prediction and parameter-Jacobian actions preserve their prior
branch policy. Predictor derivative output is bounded to512MiB. This API is scalar
in predictor/response; multi-response and live registered callback differentiation
are not represented as automatic derivatives. The callback evaluator explicitly
rejects unsupported options.

Direct geometry uses its existing analytic tangents. PCHIP uses the existing
public spline-create/evaluate derivative operation; natural smoothing splines
and Fourier models use their Numeric-owned analytic expressions. No scientific
consumer reimplements these algorithms. `curve_model_evaluate(state, query,
{derivative:true})` also exposes the functional-model tangents; existing two-argument
calls retain their behavior. `nonlinear_evaluate` accepts boolean
`predictor_derivative`; request parameter `jacobian` separately.

`model_inverse(model, targets, bracket, options)` accepts1..64 finite response
targets and one explicit increasing bracket. Options require the training domain
and accept extrapolation, positive absolute `x_tolerance` (default1e-12), positive
absolute `response_tolerance` (default1e-10), and `max_iterations`1..256 (default128).
The caller declares a continuous local branch. Existing Numeric root_find owns
the solve. Roots must converge inside the bracket and pass a fresh response
residual check. No sign change, both matching endpoints, a singularity or an
unresolved solver returns a false validity flag, NaN root and a specific reason.
Unknown iteration/evaluation counts on failed evaluation are NaN, not zero.

The gxtxt.model_inverse.v1 result reports roots, residuals, per-target validity,
reasons, actual iterations/evaluations where available and extrapolation flags.
It always states `uniqueness=not_certified`: a local bracket root does not prove
global monotonicity or uniqueness. An XY parametric curve needs its existing
projection operation, not a scalar inverse. No confidence interval is implied.

A differential-resistance consumer must identify the physical axis roles and use
CORE unit algebra for dV/dI (or its reciprocal dI/dV). Numeric values alone do not
establish electrical semantics or convert mA to A. The owning consumer must retain
that unit/provenance context and show unavailable singular values honestly.

## Physical coordinates and polynomial derivatives

Optional `orientation=y_of_x|x_of_y|r_of_theta|parametric` and
`translation=[du,dv]` reconstruct physical coordinates from a retained model.
Scalar query values and `domain` are in the physical independent coordinate;
parametric queries retain the normalized fitted parameter. `points` always
contains physical X,Y. `predicted` remains the physical model response (Y, X or
radius respectively); inverse targets use that response, not an unrelated
Cartesian coordinate. `model_response_derivative` retains the model slope before
physical orientation. Tangents and dy/dx, dx/dy are transformed consistently.

Radial queries require `polar_frame` and use public `cartesian_coordinates`.
Its optional `radius_derivative` is aligned with theta and produces analytic
Cartesian tangents, including angular-unit scale, rotation and clockwise sign.
It is not accepted by `polar_coordinates`; default coordinate calls are unchanged.
Negative physical radii are refused. Geometry/orientation mismatches are errors.

`polynomial_evaluate(model,target_x,options)` accepts `derivative_order=0..12`
(default zero). Centered/scaled polynomial coefficients are differentiated in
physical X, including the inverse scale power; a finite positive x_scale is
required. Retained polynomial_export states use this public owner.
See [Fitter retained queries](FITTER_RETAINED_QUERIES_v1.md) for the accepted-result
adapter, historical domain policy, CORE unit interpretation and display.

## Live registered callback models

Python and Octave Script Jobs may supply a live `registered_callback` model to
`model_query` / `model_inverse`. The model retains the existing nonlinear_evaluate
contract: callback handle, canonical parameter IDs, fitted parameters, source and
declaration SHA, bounds/fixed policy and finite_real or positive_real predictor
domain. The Script callback lifetime remains supervised. Scalar Y(X) and X(Y)
physical frames are supported. Radial and parametric callback geometry is refused.

Prediction-only queries invoke the callback once. A derivative query uses that
prediction and four nearby vector evaluations. It compares second-order left and
right estimates at the actual representable nodes. The method is reported as
`two_sided_second_order_finite_difference_agreement`; `derivative_reason` describes
its limit. Agreement is a numerical check, not proof of differentiability or an
analytic derivative. The comparison has no unit response floor that would hide
small-amplitude cusps. Failed perturbations preserve base predictions and mark
all derivative rows unavailable; no imaginary or nonfinite estimate is substituted.

Optional `difference_step` is a positive scalar in the physical independent
coordinate unit. The default is cbrt(eps) times max(1, absolute query and domain
endpoint scales), independent of fitting translation. A positive-real declaration
clips the step to one quarter of the translated predictor. Unrepresentable
stencils yield unavailable derivatives. `difference_step` in the result records
the effective per-row step. `difference_relative_tolerance` is the declared
left/right agreement tolerance, default 1e-4, allowed 1e-12..0.1, with an additional
floating-point roundoff bound. Appropriate explicit steps and tangent floors
remain the caller's scientific responsibility; finite sampling cannot detect all
oscillation, discontinuity or catastrophic cancellation.

The local inverse shares Numeric's existing callback Brent/secant root owner
(Brent for an explicit bracket), then checks a fresh finite response against the
absolute response tolerance. Poles, ambiguous matching endpoints and unverified
roots remain unavailable. No fitting, covariance, statistical interpretation or
uncertainty estimate is performed. These live-callback operations are available
through both real Script languages; ordinary native Tcl model states keep their
existing path. Fitter's [retained callable adapter](FITTER_RETAINED_QUERIES_v1.md) supplies
verified identity and temporary ownership separately from this mathematical API.

The shared callback response adapter accepts a scalar only when exactly one
model-response row is expected, accommodating Octave's 1-by-1 wire convention.
Multi-row scalar substitutes and genuine row matrices retain strict shape checks.

## Coordinate precision and retained coverage

Query coordinates, domains, translations, tangent floors, inverse targets and
brackets use binary64. Native and callback queries reject integer values outside
the consecutive exact binary64 range [-2^53,2^53]; callers must make any intended
lossy scientific conversion explicitly. Typed integer domains within that range
are converted before fractional physical translations and root arithmetic.
Scalar uint64/int64 input is preserved by CORE up to this semantic check.

The current Fitter catalog shares these query owners: native scalar evaluation,
frozen formula/component/region constructors, exact centered/scaled polynomial
state, saved arc/Bezier/PCHIP/smoothing/Fourier/open polynomial/open or closed
parametric spline state, and supervised registered Y(X)/X(Y) callbacks. Physical
X(Y) and radial frames retain their captured translation and angle policies.
Parametric XY inversion requires a projection and is explicitly unavailable
through scalar model_inverse. New model families must establish their evaluation,
derivative and domain contracts before joining this supported catalog.
