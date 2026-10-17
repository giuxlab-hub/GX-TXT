# Fit initialization and manual evaluation v1


`fit_initial_guess(model_kind, X, Y, options={})` returns a bounded
`gxtxt.fit_initial_guess.v1` proposal. Supported kinds are `linear`,
`polynomial_fit` (explicit degree1..12), `power_law`, `exponential` and `gaussian`.
Inputs are equal finite real floating vectors with2..1,000,000 observations;
nonfinite filtering must be explicit upstream. No source observation is changed.

Linear and polynomial suggestions reuse the existing least-squares owner.
Power suggestions use a signed logarithmic auxiliary fit with positive X and
one nonzero response sign. Exponential suggestions compare at most eight offset
candidates using auxiliary log-linear solves and existing native evaluation.
Gaussian suggestions use an edge median and signed peak moments; sampled peak
height is approximate. Internal sorting serves only this heuristic. These
procedures do not change the final response-scale noise/weight model.

Optional `lower_bounds`, `upper_bounds`, `fixed_mask` and `initial_parameters`
use canonical parameter order. Suggestions are clipped to the declared bounds;
fixed values require explicit current initials, except equal finite bounds,
which determine the value themselves. The receipt reports clipping and fixed
masks. All-fixed inputs reuse those values without an auxiliary solve. Every
proposal must evaluate to finite values through the existing native expression
engine on the supplied predictors. Unsupported models, degenerate data or failed
auxiliary initialization return `status=unavailable` with a reason. Invalid
input/options are errors. A proposal has `status=proposed`, its parameter IDs,
values, a data-only evaluation model, method and actual auxiliary-solve count.

This operation performs no nonlinear optimization and supplies no convergence,
confidence or accepted-fit claim. Review a proposal before calling the existing
fit operation. For manual parameter evaluation, copy the proposal's `model`,
set its `parameters` and call `nonlinear_evaluate(model, query)`; it uses the
same compiled expression engine without fitting. The operation is available to Tcl, Octave and Python/Octave Script Jobs.
