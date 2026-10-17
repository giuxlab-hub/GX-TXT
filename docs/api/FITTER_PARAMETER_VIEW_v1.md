# Fitter initial parameters and manual curve

Fitter's **Fit → Initial parameters and manual curve…** prepares the current
exact source selection and measurement eligibility through the normal fitting
input path. `NUMERIC_API_v1.fit_initial_guess` supplies proposals for linear,
polynomial, exponential, power-law and Gaussian models. Formula, composed and
regional and registered callback models retain their explicit declared initials and explain that no
automatic initializer is registered. Suggestions are heuristics, not fitted
estimates, uncertainty results or acceptance decisions.

Named parameter fields evaluate after a 300 ms pause using the existing public
`nonlinear_evaluate` operation for scalar/callback models and `curve_model_evaluate`
for direct geometry/Fourier models. Bounds and fixed values are enforced. The purple
dashed curve shows at most 1,024 points sampled from the current output domain;
initialization still uses the complete exact eligible observations. Parameters
use the model's declared units and fitting coordinates. Automatic/manual
translations are resolved through the same Numeric operation as fitting; display
coordinates are transformed back to physical X/Y, including X=f(Y) and the
selected radial frame.

**Apply initial values** stores the values in the Workspace and invalidates an
old fit preview. Formula, component and regional recipes retain parameter IDs,
units, bounds, fixed settings and breakpoint identities. **Preview fit** and
**Accept fit** remain separate actions. Ordinary linear/polynomial least squares
does not use iterative starting values. Closing the parameter controls removes
the ephemeral display/cache. Reopening a Workspace restores applied initials.

The controls cover declared functional models in Y=f(X) and X=f(Y). The five
built-in scalar models also support r=f(theta): theta uses the selected radian
or degree unit; radius uses the common declared Cartesian unit. Origin, rotation,
clockwise direction and angular branch match fitting. Negative physical radii
and unequal Cartesian units are refused; convert units explicitly first.
Circular arcs, quadratic/cubic Bezier curves, open parametric polynomials and
Fourier curves expose finite manual parameters through the public
`curve_model_parameter_state` and `curve_model_evaluate` operations. Preparation
uses the existing direct solution as an auxiliary starting state; it does not
perform nonlinear optimization or accept a fit. Stored manual values support
exploration and do not alter the direct fitting algorithm. Curve parameter `t`
is dimensionless within [0,1]; arc angles are radians. Coordinate parameters
retain the declared metric units and positive translations. Fourier controls
retain the declared origin/period and harmonic ordering (order1..63).
PCHIP, smoothing and parametric spline interpolators have no finite optimization
parameter vector in their public model contract; their knot/data or smoothing
controls remain in their existing model workflow. The manual menu disables these
inapplicable selections.
A source, selection, domain, model or setting change invalidates preparation;
stale values cannot be applied. Nonfinite model evaluations are reported and
remove the manual curve; they never become accepted fit results.

Registered Python/Octave models use their exact source/declaration identities and
the existing supervised callable runner. Numeric `nonlinear_evaluate` evaluates
the live callable; no optimizer or uncertainty calculation runs. A bounded
CORE-managed result resource carries physical points back to the controls, then
its explicitly temporary Document is deleted. The callback view has a60-second
wait budget; cancellation drains the Job. Its receipt identifies the temporary
lifetime and `curve.job_id` identifies the actual evaluation Job.

A Script client can use the same recipe operations even with a one-worker Job
policy: CORE yields the waiting parent's execution slot to its own child while
retaining memory reservations. Parent cancellation propagates to owned children.
If abrupt client termination prevents immediate Document cleanup, the next
registered preparation collects only explicitly temporary owners with a verified
terminal parent-child relationship. Unknown or still-active owners are retained.
This recovery does not run while initially opening a Session.

The public Tcl methods in `::GX::DatasetCurveFit` are:

- `parameterPrepare key`: for a loaded configured Fitter key, return
  `gxtxt.fitter_parameter_view.v1` with named/current/suggested values, bounds,
  fixed mask, proposal status/reason, exact observation and bounded display
  counts, and resolved translations. It owns a temporary bounded context.
- `parameterEvaluate key parameters`: evaluate a previously prepared context;
  return `gxtxt.fitter_parameter_curve.v1`, an N×2 physical `points` matrix,
  the values and display count. `accepted` and `nonlinear_optimization` are false.
- `recipeParameterView encoded_recipe ?parameters?`: load an exact recipe,
  prepare it, optionally return `curve`, and release its temporary resources.
- `recipeParametersSet encoded_recipe parameters`: validate values and return
  an updated inert recipe. It does not run an optimizer or accept a fit.

Python and Octave use the existing `gxtxt_api_call` façade with
`DATASET_CURVE_FIT_API_v1`: `recipe_parameter_view(encoded_recipe, parameters)`
and `recipe_parameters_set(encoded_recipe, parameters)`. Supply an empty array
to view preparation without manual evaluation. Numeric arrays preserve their
shape; `curve.points` is always N×2. Recipe producer/source identity checks are
the same as normal replay. No arbitrary cache path is part of the public API.

The ephemeral context contains a bounded query and the public authoring recipe.
Numeric reconstructs formula/component/region declarations at evaluation time;
the immutable declaration checks remain intact. CORE owns typed transport and
exact CurveSource staging; Fitter neither computes statistical estimators nor
introduces another evaluator or solver.
