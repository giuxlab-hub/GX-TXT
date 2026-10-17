# Physical rational response models

SPDX-License-Identifier: GPL-3.0-or-later

`NUMERIC_API_v1` declares a physical polynomial quotient and fits it through the
existing dimensional formula compiler, Ceres solver and covariance owner. The
canonical statistical identity is `math.numeric.rational`. Common
[CORE statistical interpretation](STATISTICAL_RESULT_SEMANTICS_API_v1.md) owns
inference and reporting for all scientific consumers and both Script languages.

## Declaration and fitting

`rational_model_compose(recipe)` returns `gxtxt.rational_model.v1` for
`(a0+a1*x+...+aM*x^M)/(1+b1*x+...+bN*x^N)`. Numerator degree M is 0–8;
denominator degree N is 1–8. Fixing the denominator constant at one removes its
arbitrary overall scale. Coefficient IDs remain exactly `a0` through `aM`, then
`b1` through `bN`; leading coefficients may be zero. Common factors are never
silently cancelled and scientific identities are never relabelled.

The closed recipe requires `numerator_degree`, `denominator_degree`, `x_unit`,
`y_unit`, `parameters` and an explicit finite increasing `domain`. Parameters
use the [shared formula contract](FIT_FORMULA_v1.md): physical unit, initial
value, optional lower/upper bounds and fixed flag. The dimensional compiler
resolves omitted coefficient units. Mixed linear scales, such as cm predictors
and mV responses with V/m coefficients, retain their physical conversions.
`pole_tolerance` defaults to 1e-10 and must lie in [1e-12,1e-2]. Formula source,
binding and complete declaration hashes retain units, constraints and domain.
Signed infinite bounds have a distinct canonical hash encoding.

`rational_fit(model,x,y,options={})` accepts 2–1,000,000 matched original
observations. Finite predictors must lie inside the declared domain. Explicit
`nonfinite=omit` delegates paired omission to the existing solver; the default
is `error`. Optional response `sigma` or precision `weights` use existing
absolute/relative weight semantics. The objective is quadratic response error
at exact predictor values. Robust loss and predictor-error fitting are separate
contracts. Solver controls are `solver`, `strategy`, `max_iterations`,
`max_seconds`, `function_tolerance`, `gradient_tolerance`, `parameter_tolerance`,
`parameter_scales` and `threads`; defaults are 400 iterations and 30 seconds.

The whole declared interval must pass the denominator guard before fitting and
again at the final coefficients. Intermediate optimizer iterates do not acquire
a pole-free guarantee. The returned fit retains the original solver facts,
physical parameter covariance, exact observation signature, observed predictor
bounds and `gxtxt.rational_fit_summary.v1` domain receipt. This is rational
least-squares approximation, including Padé-type polynomial quotients. It does
not perform Taylor-series Padé coefficient matching or select degrees silently.

## Whole-interval domain checks

`rational_domain(model_or_recipe,domain)` accepts a compiled model or the physical
recipe above, compiling the latter through the same owner. It returns a bounded `gxtxt.rational_domain.v1`
receipt with `safe`, `unsafe` or `unresolved` status. Declaration can expose an
unsafe initial model for inspection; fitting, retained state and evaluation
require a safe guard. All physical denominator coefficient scales are applied.
The polynomial is normalized by its absolute-coefficient bound on the interval,
converted to Bernstein coefficients on [0,1], and subdivided by de Casteljau.
The convex-hull bounds must establish consistent separation from zero over every
subinterval. Work is limited to degree 8, depth 24 and 4,096 visited intervals.
Repeated roots, near-zero denominators and poles between observation samples
cannot be hidden by a sampled-grid check. An unresolved guard is refused.

This is a bounded binary64 numerical guard, not an exact-arithmetic certificate.
Its separation threshold includes a floating-point floor. Approximate pole
locations use [GNU Octave roots](https://docs.octave.org/latest/Finding-Roots.html)
as diagnostics only; they do not establish domain safety. Possible common
numerator/denominator roots trigger an identifiability warning and make regular
likelihood comparison unavailable. No cancellation removes a declared pole.

## Retained queries, state and export

`rational_evaluate(model,x,options={})` accepts 1–1,000,000 finite scalar/vector
coordinates, returning predictions, physical Nx2 points, domain receipt and
extrapolation flags without fitting. Exact integer values outside binary64's
integer range are refused before narrowing. `jacobian=true` requests the existing
parameter Jacobian; `predictor_derivative=true` requests its physical derivative.
Evaluation does not manufacture residuals or training inference.

Default `extrapolation=error` uses captured observed bounds, or the declared
bounds for an unfitted model. Explicit `allow` checks the entire interval joining
the declared domain and every requested coordinate. Finite endpoint predictions
do not permit jumping across a pole. The shared `model_query` retains this guard
and requires the captured domain; it does not silently translate coordinates.

`rational_model_state(model)` returns `gxtxt.rational_state.v1` with the full
recipe, physical coefficients, observed bounds and three declaration identities.
`rational_model_restore(state)` verifies these identities, parameter constraints
and domain before restoring the model without fitting.

`rational_residuals(model,x,y,options={})` evaluates 1–1,000,000 finite matched
pairs through the same guarded model and existing residual-metrics owner. It
performs no optimization. The closed options accept only the explicit
extrapolation policy. Its `gxtxt.rational_residual_summary.v1` records the actual
evaluation count and extent separately from the original observation domain.
The CORE `from_numeric` operation for `rational_residuals` supplies descriptive
evaluation meaning; injected training covariance, rank, DOF, standard errors,
reduced chi-square or solver inference are refused.

`model_export(model_or_state,options)` accepts a compiled model or a validated
`gxtxt.rational_state.v1`, emitting standalone Python and Octave functions and
LaTeX through the existing expression emitter. An explicit export interval is
required and the entire interval joining it to the declared domain must pass
the guard. Generated functions enforce finite scalar/vector inputs, exact
integer conversion and the exported interval. Metadata retains the full recipe,
signed decimal/Inf bound encoding, physical parameter identities, units,
observation domain and guard receipt. `y_of_x` and `x_of_y` retain the physical
predictor and swap returned axes/units explicitly. Additive coordinate
translations and consumer relabelling of parameters or units are refused.

## Common statistical meaning and comparison

`from_numeric('math.numeric.rational','rational_fit',fit,context)` adapts captured
facts to the public versioned CORE result. Physical coefficient values, units,
formula hashes, exact predictor signature and safe domain receipt must agree.
Other model IDs or removal of the rational context cannot bypass these rules.
Common confidence intervals remain local and conditional on fixed degrees,
declared domain, exact predictors, regular constraints and the noise model.
The existing uncertainty engine consumes the captured covariance once.

The common model-selection plan and existing Numeric information-criteria engine
handle eligible Gaussian rational fits. Comparison with polynomial or other
candidates requires identical source/ordered-row bindings, captured predictor
values, response values, weights, physical coordinate frame and noise assumptions.
Missing legacy predictor evidence is unavailable for rational comparisons.
Possible common factors require identifiability review. Known-sigma AIC/BIC do
not acquire the estimated-scale AICc correction. No second scoring engine exists.

All seven public operations are discoverable through the Tcl operation catalog
and registered Python/Octave Script Bridge. Fitter consumes them through its
[rational workflow](FITTER_RATIONAL_v1.md), preserving the same scientific owner.
