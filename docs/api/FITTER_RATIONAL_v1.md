# Fitter physical rational models

SPDX-License-Identifier: GPL-3.0-or-later

Choose **Fit → Rational / Padé…** after loading a Dataset curve. Fitter uses
the public [Numeric rational model](RATIONAL_MODELS_v1.md) and common
[CORE statistical interpretation](STATISTICAL_RESULT_SEMANTICS_API_v1.md).
The quotient is a rational least-squares approximation; it does not match
Taylor-series Padé coefficients or cancel numerator/denominator factors.

## Physical declaration and controls

Declare numerator degree0–8, denominator degree1–8 and a finite increasing
predictor domain. Applying degrees builds immutable coefficient IDs a0…aM,
b1…bN, with denominator constant one. Review each initial physical value,
unit, bound and fixed flag. Existing matching rows retain their settings.
The shared dimensional compiler resolves units; the physical declaration owns
coefficient constraints. Automatic parameter guessing is unavailable.

Validate checks the full declared interval through public `rational_domain`.
Unsafe or unresolved denominator separation prevents applying the declaration.
The bounded binary64 guard is qualified explicitly; numerical root diagnostics
are not exact certificates. Fitting checks the initial and final models;
intermediate optimizer iterates carry no pole-free guarantee.

Both Y=f(X) and X=f(Y) use the actual predictor/response Variable units. No
translation or preprocessing changes these physical coordinates. Response sigma
or relative precision uses existing measurement bindings and original row
selection. Predictor uncertainty, full observation covariance, robust loss,
multistart, prediction bands, refit bootstrap and linear influence have no
rational contract and are refused explicitly. Solver tolerances and bounded
iteration/time controls use the shared Ceres owner.

## Preview, acceptance and reuse

Preview retains weighted training facts and separate descriptive source
evaluation. The output interval is independent of training support; requesting
a smaller interval preserves the complete original observation domain.
Extrapolation defaults to error. Explicit permission still requires a safe
denominator throughout the interval joining all requested coordinates to the
declared domain. A finite endpoint cannot justify crossing a pole.

Accept stores the scientific recipe, physical coefficients, parameter units,
declared/observed domains, three Numeric identities and a Fitter state digest.
Normal Session save/reopen, named recipes and templates preserve these values.
Changed recipes, domains or expression identities fail retained validation.
Manual parameter evaluation and exact queries use the retained model without
optimization, including guarded rejection of manually introduced poles.

The existing [Fitter API](DATASET_CURVE_FIT_API_v1.md) exposes `recipe_run`,
`result_info`, `result_query`, `result_export`, `result_residual_page`,
`result_parameters_publish`, `result_publish` and `result_workbench` to Tcl and
real Python/Octave Jobs. `rational_recipe` and `rational_extrapolation` are the
explicit fit options. Script recipe replay performs a new fit only on request.
Retained evaluation, export and Workbench transfer do not fit again.

Residual columns follow the actual physical orientation; original Dataset row
IDs stay uint64. Query derivatives always describe displayed physical axes:
dY/dX and dX/dY are distinct. For X=f(Y) with X in V and Y in m, dY/dX is m/V
and dX/dY is V/m. Requested units must match that dimensional identity.

Parameter Dataset publication retains the full declaration and state identity.
Published sampled curves and Workbench geometry retain their sampled
representation and original training meaning; sampled points do not become
new fit observations. Standalone Python/Octave exports enforce the declared
export interval and preserve physical axes, units and quotient identity.
