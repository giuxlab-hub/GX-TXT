# Constrained parameter profile likelihood v1

`math.numeric` 1.60 provides `fit_profile(model, predictors, response, plan,
options)`. Public `STATISTICAL_RESULT_SEMANTICS_API_v1` owns `profile_settings`,
`profile_plan`, `profile_interpretation` and `profile_report`; generic `validate`
and `report` accept the interpretation. Both real Python and Octave Script Jobs
use these same registrations and existing binary numerical transport. Tcl callers
use `::GX::NumericAPIv1::fitProfile` with canonical transport nodes.

The source is one retained, converged, declared scalar `nonlinear_fit` through
Ceres, including linear formulas fitted by that operation. Fix one previously
free physical parameter and reoptimize the remaining parameters under the original
bounds, fixed values, scales, tolerances and quadratic loss. The original fit is
never repeated. Rank deficiency and active bounds remain visible rather than
silently replacing the profile with a Wald interval.

## Explicit request

Supply `parameter_id`, finite physical `search_lower`, `search_upper`, positive
`initial_step` and positive absolute physical `parameter_tolerance`. Optional
`confidence` defaults to .95; `max_refits` defaults to 128 (4–256); `max_seconds`
defaults to 60 (positive and at most 3600). Search limits contain the fitted
estimate and respect the original bounds. They are scientific declarations, not
display zoom limits. `profile_plan(source, settings)` returns availability and
its reason before any constrained solve.

`model.parameters` must equal the captured fitted values. Predictors, response,
precision weights, model source/binding hashes and parameter identities must
match the source exactly. Supply positive original `weights` when weighted;
absolute sigma sources use their retained inverse-variance weights. No smoothing,
robust loss, XY ODR, joint response, callback fit or undeclared noise model is
silently treated as an independent scalar Gaussian likelihood.

## Objective and threshold

For declared independent Gaussian errors with known absolute sigma, the profile
statistic is `SSE_profile - SSE_source`, using the original inverse variances.
For independent Gaussian errors with unknown common variance and unweighted or
relative precisions, it is `n * log(SSE_profile / SSE_source)`: the variance is
profiled by maximum likelihood. Zero source SSE makes the latter unavailable.
Neither objective substitutes residual degrees of freedom for the likelihood.

Numeric computes the chi-square(1) threshold once as
`2 * erfinv(confidence)^2`. CORE labels the approximation and retains its actual
threshold. Fixing a parameter, reoptimizing nuisance parameters and comparing
the likelihood ratio follow the [NIST likelihood-ratio explanation](https://www.itl.nist.gov/div898/handbook/apr/section2/apr233.htm)
and [Maiwald et al., 2016](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0162366).
These asymptotic thresholds do not establish finite-sample coverage, especially
near boundaries or weak identifiability.

## Search and retained evidence

Each side expands the stated step by 1.8 until a threshold bracket or the finite
search limit, then bisects to the absolute parameter tolerance. The lower side
receives at most half the refit budget; the upper side receives the remaining
budget. Every trial starts from the captured original solution with the profiled
parameter fixed. Refits run sequentially with one solver thread. This is a local
connected profile component: disconnected confidence regions or remote minima
are not certified. A material improvement over the original SSE invalidates the
interval and requests review of the original fit.

The typed result contains `trial_values` (parameter, weighted SSE, likelihood
ratio, direction), physical `trial_parameters`, `uint8 trial_status`, bounded
trial messages, column names and status codes. `summary` contains the original
identities, Gaussian objective, threshold, counts, elapsed time, workspace bound,
settings, endpoint records and SHA256 of the exact trial ledger. CORE receives
only this bounded summary; arrays remain in the existing binary data transport.
Owned resource hashes must bind these arrays when a consumer persists them.
`numeric_data_fields` supplies their common physical units, parameter identities,
shapes and failure-code definitions. `publication_metadata` validates the captured
meaning for canonical Dataset publication; consumers retain that meaning with
the actual numerical columns.

Endpoint statuses have distinct meanings:

| Status | Meaning |
| --- | --- |
| `threshold_crossing` | Midpoint of the retained refined bracket. `searched_value` and `likelihood_ratio` belong to the last actually evaluated bracket endpoint. |
| `constraint_bound` | Original parameter-domain bound reached below the threshold. |
| `open_search_limit` | No crossing within the explicit finite search. The interval side is represented by signed infinity, while the actual finite searched limit and objective remain recorded. Global unboundedness is not proved. |
| `refit_budget`, `time_budget`, `resolution_limit` | Search is incomplete; no finite endpoint is claimed. |
| `solver_failure` | Failed constrained solve retained; no interval is inferred across the failure. |
| `baseline_improved` | A constrained trial found a materially lower objective; original optimum requires review. |

CORE reports completed searches as `qualified`, including open or constraint
endpoints. Any unresolved side or improved baseline makes the whole interval
`unavailable`; retained partial evidence remains inspectable. Covariance-based
Wald intervals keep their separate approximation label.

The bounded contract permits 2–1,000,000 retained scalar observations, 1–128
parameters/predictors, at most 256 constrained refits, at most 128 million
row-parameter-refit work units and an upfront estimated 512 MiB workspace limit.
Worker cancellation preserves existing supervised Job semantics; incomplete
results are not converted into accepted intervals.

## Eligibility before fitting

Public CORE `profileEligibility modelId operation context` (Script
`profile_eligibility(model_id,operation,context)`) returns version1
`STATISTICAL_PROFILE_ELIGIBILITY_v1`, `status=eligible|unavailable` and a reason.
It checks the registered model profile, declared operation, residual geometry,
loss, training role and smoothing context. `eligible` establishes only these
prerequisites: it is not a confidence result or a promise of solver convergence.
The actual captured fit, noise declaration, exact observations, bounds and search
settings must still pass `profile_plan`. That plan calls the same eligibility
owner. Fitter supplies its actual adapter/geometry and consumes this public
decision before execution; it does not maintain private inference policy.
