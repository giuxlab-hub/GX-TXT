# Fitter model documentation cards

Fit → **Model documentation** opens the selected model card. Its selector can
browse every Fitter model without changing the active fitting configuration,
source, preview, accepted results or History. Documentation is available before
loading a Dataset. Components and Joint regions retain their individual public
Numerical model cards; the workflow cards below link those existing authorities.

The public `DATASET_CURVE_FIT_API_v1/model_cards()` operation returns a list of
`gxtxt.fitter_model_card.v1` records. Tcl uses
`::GX::DatasetCurveFit::modelCards`; Python and Octave use the shared
`gxtxt_api_call` entry point. Each record has `documentation_only=true`,
`model_id`, `label`, `equation`, `parameters`, `domain`, `method`,
`initialization`, `solver`, `uncertainty`, `extrapolation`, `source_owner`,
`statistics_model_id`, `statistical_profile` and `statistical_label`. The last
two fields are read from the registered CORE statistical model, not privately
interpreted by the Viewer. This is documentation, not an executable model or
an alternative numerical/statistical registry.

U and V denote independent and response units. Functional equations describe
fit-space coordinates; the scientific report retains physical translations
and inverse mapping. Parametric coordinates retain their own X/Y units.
The actual fit report remains authoritative for the data, parameter roles,
constraints, solver outcome and uncertainty availability.

## linear — Linear regression

**Equation.** v = intercept + slope*u

**Parameters and units.** intercept: response V; slope: response change per independent unit V/U. Named statistical parameters define order; the legacy coefficient vector uses slope then intercept.

**Domain.** Finite paired observations; enough independent coordinates for full rank.

**Method.** Ordinary/weighted response regression; optional both-axis ODR when sigma_X and sigma_Y are explicitly bound.

**Initialization.** Direct least squares has no iterative start. Both-axis ODR uses the declared initial parameters.

**Solver.** Public linear least squares; both-axis uncertainties use the existing native ODR route. Weights and missing-measurement policy must be explicit.

**Uncertainty.** Covariance, standard errors, marginal confidence intervals, rank/DOF and correlation follow the captured noise/weight model. Exact linear influence is available for eligible ordinary or weighted response fits. Both-axis ODR has its separate absolute-sigma interpretation.

**Extrapolation.** Finite real queries are evaluated; points outside the captured training envelope are flagged. A line is not evidence for distant continuation.

Scientific owner: [source](../../plugins/modules/math.numeric/api/octave/gxtxt_numeric_v1.m); registered statistical model `math.numeric.linear`.

## polynomial — Polynomial regression

**Equation.** v = sum(c_k*u^k), k=0..degree

**Parameters and units.** c_k: V/U^k; retained descending-power coefficients and centered/scaled evaluation state preserve their documented ordering.

**Domain.** Finite paired observations and enough distinct coordinates for the requested degree and rank.

**Method.** Ordinary/weighted polynomial response regression, with optional declared both-axis ODR.

**Initialization.** Ordinary least squares is direct; centered/scaled predictor arithmetic improves conditioning. ODR uses explicit physical coefficients.

**Solver.** Public polynomial fit retains scaled evaluation state and physical coefficients; rank and conditioning remain scientific constraints.

**Uncertainty.** Covariance, standard errors, marginal confidence intervals, rank/DOF and correlation follow the captured noise/weight model. Exact linear influence is available for eligible ordinary or weighted response fits. Both-axis ODR has its separate absolute-sigma interpretation.

**Extrapolation.** Polynomial continuation is mathematically defined but can grow rapidly outside support. Captured extrapolation flags do not certify validity.

Scientific owner: [source](../../plugins/modules/math.numeric/api/octave/gxtxt_numeric_v1.m); registered statistical model `math.numeric.polynomial`.

## exponential — Exponential regression

**Equation.** v = amplitude*exp(rate*u) + offset

**Parameters and units.** amplitude and offset: V; rate: 1/U. A physical time constant is -1/rate only for the explicitly chosen decay interpretation.

**Domain.** Finite inputs and parameters whose evaluated exponential remains finite.

**Method.** Nonlinear response regression; fitting log(v) is a separate operation with a different residual model.

**Initialization.** Explicit initial values or reviewed model-aware initial estimates. Translation changes the fit-space coefficients and is retained.

**Solver.** Public declared nonlinear least squares; native Ceres settings, bounds, fixed parameters and stopping receipt are retained.

**Uncertainty.** Local Jacobian covariance, standard errors and marginal confidence intervals require identified free parameters and the declared noise/weight assumptions. Active bounds, robust losses, rank loss or failed convergence can make inference unavailable. Read the CORE result statuses.

**Extrapolation.** Finite evaluable continuation is allowed and flagged outside support; exponential overflow fails explicitly.

Scientific owner: [source](../../plugins/modules/math.numeric/api/octave/gxtxt_numeric_declared_fit_v1.m); registered statistical model `math.numeric.exponential`.

## power_law — Power-law regression

**Equation.** v = scale*u^exponent

**Parameters and units.** exponent: dimensionless; scale has conditional units V/U^exponent, with the fixed coordinate-unit covariance basis recorded by CORE.

**Domain.** Strictly positive fitted independent coordinates and finite evaluated response. Review any coordinate translation in the physical formula.

**Method.** Nonlinear response regression in original response space, not automatic logarithmic regression.

**Initialization.** Explicit initial values or reviewed power-law initialization; inferred starts do not declare a log-noise model.

**Solver.** Public declared nonlinear least squares with bounds/fixed roles; positive predictor domain is enforced.

**Uncertainty.** Local Jacobian covariance, standard errors and marginal confidence intervals require identified free parameters and the declared noise/weight assumptions. Active bounds, robust losses, rank loss or failed convergence can make inference unavailable. Read the CORE result statuses.

**Extrapolation.** Only positive valid predictor queries can continue; out-of-support valid points are flagged.

Scientific owner: [source](../../plugins/modules/math.numeric/api/octave/gxtxt_numeric_declared_fit_v1.m); registered statistical model `math.numeric.power_law`.

## gaussian — Gaussian peak regression

**Equation.** v = amplitude*exp(-0.5*((u-center)/width)^2) + offset

**Parameters and units.** amplitude and offset: V; center and width: U. Nonzero width is required; its sign is not independently identified by the squared Gaussian formula.

**Domain.** Finite paired inputs and nonzero finite width; user bounds can select the positive-width convention.

**Method.** Nonlinear peak response regression with a constant baseline.

**Initialization.** Explicit start or reviewed peak-aware initialization; multiple peaks require explicit components.

**Solver.** Public declared nonlinear least squares; amplitude/center/width/offset roles, constraints and solver receipt are retained.

**Uncertainty.** Local Jacobian covariance, standard errors and marginal confidence intervals require identified free parameters and the declared noise/weight assumptions. Active bounds, robust losses, rank loss or failed convergence can make inference unavailable. Read the CORE result statuses.

**Extrapolation.** Valid finite continuation is allowed and flagged; tail behavior is a model assumption, not measured baseline evidence.

Scientific owner: [source](../../plugins/modules/math.numeric/api/octave/gxtxt_numeric_declared_fit_v1.m); registered statistical model `math.numeric.gaussian`.

## components — Composed scientific regression

**Equation.** v = sum of the explicitly selected component expressions

**Parameters and units.** Each component card declares names, meanings, units and domains. Explicit bindings share parameters; fixed roles and bounds remain visible.

**Domain.** Intersection of all selected component domains and unit requirements. Physical model cards can prohibit coordinate translation.

**Method.** One joint nonlinear regression with a shared residual and covariance.

**Initialization.** Use component card defaults only as reviewed starts; named parameter overrides are explicit.

**Solver.** NUMERIC_API_v1 fit_model_compose freezes the selected public model cards and hashes, then uses the existing nonlinear owner.

**Uncertainty.** Local Jacobian covariance, standard errors and marginal confidence intervals require identified free parameters and the declared noise/weight assumptions. Active bounds, robust losses, rank loss or failed convergence can make inference unavailable. Read the CORE result statuses.

**Extrapolation.** Every selected component domain must permit the query. Read individual cards in the Components editor or fit_model_catalog.

Scientific owner: [source](../../plugins/modules/math.numeric/api/octave/gxtxt_numeric_fit_composition_v1.m); registered statistical model `math.numeric.nonlinear`.

## regions — Joint regional regression

**Equation.** v = the explicitly selected piecewise incremental expressions with declared junction continuity

**Parameters and units.** Initial level: V; breakpoint positions: U; slopes: V/U; additional region parameters use their independent card units. C1 can derive a slope instead of fitting it.

**Domain.** Ordered finite breakpoint domains and explicit observation windows. Gaps are not observed support.

**Method.** One joint nonlinear fit across all regions and eligible observations; C0/C1 continuity is explicit.

**Initialization.** Reviewed level, region parameters and breakpoint starts within their separate search bounds.

**Solver.** NUMERIC_API_v1 fit_region_compose freezes region cards and continuity; fit_region_selection owns observation windows.

**Uncertainty.** Local Jacobian covariance, standard errors and marginal confidence intervals require identified free parameters and the declared noise/weight assumptions. Active bounds, robust losses, rank loss or failed convergence can make inference unavailable. Read the CORE result statuses. Breakpoint intervals are local approximations, not proof of a unique regime boundary.

**Extrapolation.** The active end-region expression determines continuation. Observation gaps and out-of-support queries remain model assumptions.

Scientific owner: [source](../../plugins/modules/math.numeric/api/octave/gxtxt_numeric_fit_regions_v1.m); registered statistical model `math.numeric.nonlinear`.

## formula — Safe formula regression

**Equation.** v = the explicitly declared safe expression f(u, named_parameters)

**Parameters and units.** Parameter IDs and units are explicit or inferred only when the public dimension authority gives a unique result.

**Domain.** The parsed expression, domain declaration, dimensional constraints and parameter bounds define valid inputs.

**Method.** Declared nonlinear response regression; source is parsed as data, never executed as arbitrary code.

**Initialization.** Explicit named initial values; manual views evaluate those values without claiming optimization.

**Solver.** Public fit_formula_compose, dimension validation and native declared-model solver. Full saved expression and parameter order remain available.

**Uncertainty.** Local Jacobian covariance, standard errors and marginal confidence intervals require identified free parameters and the declared noise/weight assumptions. Active bounds, robust losses, rank loss or failed convergence can make inference unavailable. Read the CORE result statuses.

**Extrapolation.** Expression domains are enforced. Valid continuation outside captured training support is flagged.

Scientific owner: [source](../../plugins/modules/math.numeric/api/octave/gxtxt_numeric_fit_formula_v1.m); registered statistical model `math.numeric.nonlinear`.

## registered — Registered Python/Octave model

**Equation.** v = the frozen registered callable(parameters, predictors)

**Parameters and units.** Callable declaration fixes parameter IDs, order, units, initial values, bounds and fixed roles; predictor/response units must match.

**Domain.** Declared finite-real or positive-real predictor domain, callable output shape, units and finite values.

**Method.** Explicit registered nonlinear response regression inside a supervised Script Job.

**Initialization.** Reviewed callable declaration starts or explicit parameter edits; callback code and declaration hashes are frozen.

**Solver.** Existing public callback least-squares owner uses its captured backend/settings and bounded callback transport; no silent native Ceres claim.

**Uncertainty.** Local Jacobian covariance, standard errors and marginal confidence intervals require identified free parameters and the declared noise/weight assumptions. Active bounds, robust losses, rank loss or failed convergence can make inference unavailable. Read the CORE result statuses. Pairs, residual and declared-Gaussian parameter bootstrap use the shared Numeric sampling and summary owners in a one-thread Script Job. Eligibility requires exact retained observations and the captured callback backend/version; failures or active bounds withhold nominal intervals.

**Extrapolation.** Only the declared predictor domain and finite callback evaluations are eligible. Retained query operations verify the frozen callable identity.

Scientific owner: [source](../../plugins/modules/viewer.dataset_curve_fit/api/registered_model_consumer.py); registered statistical model `math.numeric.nonlinear`.

## circular_arc — Circular arc approximation

**Equation.** X(t)=cx+r*cos(a0+t*(a1-a0)); Y(t)=cy+r*sin(a0+t*(a1-a0))

**Parameters and units.** Center coordinates and radius: compatible coordinate units; start/end angles: radians; t is dimensionless.

**Domain.** At least three noncollinear points, positive radius and a nonzero oriented angular span.

**Method.** Centered algebraic circle approximation with mean radial radius, followed by oriented arc projection. It is not a full orthogonal-distance parameter optimization.

**Initialization.** Direct centered solve; source order determines unwrapped endpoint angles.

**Solver.** Public curve_model_fit and curve_model_project; compatible physical coordinates are needed for meaningful geometric distances.

**Uncertainty.** Geometric residual distance and projection diagnostics are descriptive. Ordinary response R-squared and automatic coefficient confidence intervals are not established by a small geometric residual; inspect the CORE report for explicit unavailable states.

**Extrapolation.** The retained arc evaluates only t in [0,1]; it does not silently extend the angular span.

Scientific owner: [source](../../plugins/modules/math.numeric/api/octave/gxtxt_numeric_curve_models_v1.m); registered statistical model `math.numeric.circular_arc`.

## quadratic_bezier — Quadratic Bezier approximation

**Equation.** P(t) = sum(binomial(2,j)*(1-t)^(2-j)*t^j*P_j)

**Parameters and units.** 3 control points with X/Y coordinate units; t is dimensionless. Endpoints are fixed to the first/last observed points.

**Domain.** At least 3 finite ordered points and a full-rank inner-control design.

**Method.** Endpoint-constrained coordinate least squares; interior measured points are not necessarily interpolated.

**Initialization.** Direct solve using normalized source-row order.

**Solver.** Public curve_model_fit solves inner control coordinates; curve_model_project supplies separate geometric diagnostics.

**Uncertainty.** Geometric residual distance and projection diagnostics are descriptive. Ordinary response R-squared and automatic coefficient confidence intervals are not established by a small geometric residual; inspect the CORE report for explicit unavailable states.

**Extrapolation.** Only t in [0,1] is accepted by the retained evaluator.

Scientific owner: [source](../../plugins/modules/math.numeric/api/octave/gxtxt_numeric_curve_models_v1.m); registered statistical model `math.numeric.quadratic_bezier`.

## cubic_bezier — Cubic Bezier approximation

**Equation.** P(t) = sum(binomial(3,j)*(1-t)^(3-j)*t^j*P_j)

**Parameters and units.** 4 control points with X/Y coordinate units; t is dimensionless. Endpoints are fixed to the first/last observed points.

**Domain.** At least 4 finite ordered points and a full-rank inner-control design.

**Method.** Endpoint-constrained coordinate least squares; interior measured points are not necessarily interpolated.

**Initialization.** Direct solve using normalized source-row order.

**Solver.** Public curve_model_fit solves inner control coordinates; curve_model_project supplies separate geometric diagnostics.

**Uncertainty.** Geometric residual distance and projection diagnostics are descriptive. Ordinary response R-squared and automatic coefficient confidence intervals are not established by a small geometric residual; inspect the CORE report for explicit unavailable states.

**Extrapolation.** Only t in [0,1] is accepted by the retained evaluator.

Scientific owner: [source](../../plugins/modules/math.numeric/api/octave/gxtxt_numeric_curve_models_v1.m); registered statistical model `math.numeric.cubic_bezier`.

## pchip — Shape-preserving PCHIP interpolation

**Equation.** v = piecewise cubic Hermite interpolant through the captured knots

**Parameters and units.** Knot coordinates: U and V; there is no ordinary fitted coefficient parameter vector or regression residual-noise estimate.

**Domain.** At least three finite pairs with distinct independent coordinates. Actual ascending sorting is captured; repeated X is rejected.

**Method.** C1 shape-preserving interpolation through every retained knot.

**Initialization.** No optimization start; knot values are the input observations.

**Solver.** Public spline_create/spline_evaluate with PCHIP; duplicate rejection and intrinsic domain checks are explicit.

**Uncertainty.** Zero knot residual is interpolation, not statistical fit success. Ordinary regression R-squared, coefficient standard errors and confidence intervals are not applicable without a separate uncertainty model.

**Extrapolation.** Queries outside the first/last retained knot are rejected.

Scientific owner: [source](../../plugins/modules/math.numeric/api/octave/gxtxt_numeric_curve_models_v1.m); registered statistical model `math.numeric.pchip`.

## smoothing_spline — Natural cubic smoothing spline

**Equation.** Minimize squared response error plus lambda times integrated squared curvature

**Parameters and units.** Knots: U/V; lambda controls the curvature penalty with a scale tied to the predictor units. The report supplies its unit interpretation and effective degrees of freedom.

**Domain.** At least three finite pairs with distinct independent coordinates; nonnegative lambda. Natural second-derivative boundary conditions.

**Method.** Penalized smoothing for lambda>0; interpolation when lambda=0.

**Initialization.** Explicit lambda or reviewed bounded GCV search; all candidates, selected value and search status are retained.

**Solver.** Public sparse/natural cubic smoother and existing diagnostic owner; actual sorted knot permutation is retained.

**Uncertainty.** EDF, residual DOF and GCV diagnostics describe complexity. Ordinary coefficient covariance/SE/CI are unavailable when the numerical owner supplies no eligible rank/covariance; interpolation does not establish uncertainty.

**Extrapolation.** Queries outside the captured knot interval are rejected.

Scientific owner: [source](../../plugins/modules/math.numeric/api/octave/gxtxt_numeric_smoothing_spline_v1.m); registered statistical model `math.numeric.smoothing_spline`.

## fourier — Fourier series regression

**Equation.** v = c0 + sum(a_k*cos(k*omega*(u-origin)) + b_k*sin(k*omega*(u-origin)))

**Parameters and units.** c0, a_k and b_k: V; period/origin: U; omega=2*pi/period has inverse predictor units. Order is the highest harmonic.

**Domain.** Positive finite period; at least 2*order+1 independent observations and full rank.

**Method.** Linear trigonometric regression with an explicit periodic basis.

**Initialization.** Direct coefficients. Period is explicit or uses the recorded grid/span inference rule; it is not a fitted frequency estimate.

**Solver.** Uniform complete-cycle data use sorted orthogonal DFT; other inputs use the original-order least-squares design. The actual branch/permutation is captured.

**Uncertainty.** Residual diagnostics are available. The current curve-model adapter does not supply rank/covariance for coefficient SE/CI; the CORE report marks these unavailable.

**Extrapolation.** Periodic continuation is evaluable at finite coordinates and flagged outside training support. Periodicity remains a model assumption.

Scientific owner: [source](../../plugins/modules/math.numeric/api/octave/gxtxt_numeric_curve_models_v1.m); registered statistical model `math.numeric.fourier`.

## parametric_polynomial — Ordered parametric polynomial approximation

**Equation.** X(t)=sum(a_k*t^k); Y(t)=sum(b_k*t^k)

**Parameters and units.** X/Y coefficient columns retain their respective coordinate units; normalized t is dimensionless. Source-parameter normalization is captured.

**Domain.** At least three independent ordered nodes, supported degree with more nodes than degree, open topology and t in [0,1].

**Method.** Separate coordinate polynomial least squares; geometric assessment is subsequent projection, not automatic orthogonal fitting.

**Initialization.** Direct fits under explicit row-order, path-length or strictly monotone user-parameter normalization.

**Solver.** Public polynomial fits at the parametric model owner. Closed polynomial topology is rejected; use an explicit periodic spline.

**Uncertainty.** Geometric diagnostics and explicit parameter-role interpretation are available. Ordinary response-model inference is not automatically transferable to projected parametric residuals; inspect CORE statuses.

**Extrapolation.** Only normalized t in [0,1] is accepted.

Scientific owner: [source](../../plugins/modules/math.numeric/api/octave/gxtxt_numeric_parametric_models_v1.m); registered statistical model `math.numeric.parametric_polynomial`.

## parametric_spline — Ordered parametric cubic spline

**Equation.** X(t), Y(t) are piecewise cubic coordinates on the saved normalized knots

**Parameters and units.** Knot/control coefficients retain X/Y units; t is dimensionless. Open and periodic boundary policies are retained explicitly.

**Domain.** At least three independent ordered nodes. Path length rejects zero consecutive segments; supplied parameters must be strictly monotone.

**Method.** Ordered coordinate interpolation: natural open boundaries or explicit periodic closed continuity.

**Initialization.** No optimization start. Topology, parameterization and closure tolerance are explicit; a repeated closure node can be removed for construction while all observations remain recorded.

**Solver.** Public parametric spline owner uses the existing natural-cubic owner for open axes and its periodic system for closed curves.

**Uncertainty.** Geometric residual distance and projection diagnostics are descriptive. Ordinary response R-squared and automatic coefficient confidence intervals are not established by a small geometric residual; inspect the CORE report for explicit unavailable states. Passing through knots is not a confidence statement.

**Extrapolation.** Only t in [0,1] is accepted, including the explicit closing endpoint.

Scientific owner: [source](../../plugins/modules/math.numeric/api/octave/gxtxt_numeric_parametric_models_v1.m); registered statistical model `math.numeric.parametric_spline`.


## implicit — Implicit equation

**Equation.** f(x,y,p)=0 with an explicit Y(X) or X(Y) branch

**Parameters.** Named physical parameters retain declared units, initial values, bounds and fixed values.

**Domain.** Two physical coordinates,2..65536 observed pairs; equation and continuous response bracket/domain are explicit. Preview output2..256 points.

**Method.** Algebraic or physically reference-normalized equation residuals; these are not vertical response errors or genuine ODR distances.

**Initialization.** Explicit equation parameter table. Reference normalization is not measurement sigma.

**Solver.** Existing bounded native Ceres solver, automatic equation Jacobian and checked local branch roots.

**Uncertainty.** Common CORE conditional equation-error parameter inference; no ordinary response R-squared, known-sigma chi-squared, response bands or likelihood ranking.

**Extrapolation.** A local root is checked in its saved bracket/domain; global uniqueness is not certified and unavailable branches are never fabricated.

Scientific owner: [source](../../plugins/modules/math.numeric/api/octave/gxtxt_numeric_implicit_v1.m); registered statistical model `math.numeric.implicit`.

## complex_response — Joint complex response

**Equation.** Shared physical real/imaginary frequency-response formulas

**Parameters.** Named shared parameters with explicit physical units, initial values, bounds and fixed values.

**Domain.** Positive physical frequency,1..3 channels,2..65536 original rows; exact Cartesian or declared amplitude/phase Variables.

**Method.** Absolute positive-definite Cartesian component covariance in real/imaginary channel order; different frequency rows are independent.

**Initialization.** Explicit physical parameter table; covariance never inferred from display or phase units.

**Solver.** Existing bounded real multi-response Ceres solver and shared covariance owner.

**Uncertainty.** Common CORE conditional known-Gaussian parameter intervals; no mixed-channel R-squared or pooled physical RMSE.

**Extrapolation.** Display real/imaginary/magnitude or physically referenced db20; zero-amplitude dB is unavailable and phase is diagnostic only.

Scientific owner: [source](../../plugins/modules/math.numeric/api/octave/gxtxt_numeric_complex_v1.m); registered statistical model `math.numeric.complex_response`.
