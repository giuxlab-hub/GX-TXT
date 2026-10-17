# Numeric integration changes

##1.61.0

Add bounded public expression_evaluate/dataset_expression/expression_analyze using existing CORE parser/units and Numeric root/minimization owners, typed Tcl/Python/Octave interfaces and explicit resource/classification limits. Review the complete current Numeric manual, remove stale release-task commentary and correct obsolete availability statements without changing scientific contracts.

## 1.60.1

Accept exact zero pixel localization and propagated zero marginal variance in
digitization uncertainty. Omit undefined zero-variance Pearson pairs from
correlation summaries; require exact zero cross-covariance on a zero marginal.
Preserve physical zero without an artificial positive epsilon. Focused dev098
public Numeric, covariance, Statistical Semantics, GLS/ODR and Script evidence
is recorded in docs/reports/DEV098_INTEGRATION_AND_EVIDENCE.md.

## 1.60.0

Correct live Tcl profile catalog metadata and transport infinite original
parameter bounds explicitly in profile and bootstrap plans. Ordinary observations
remain finite-only; both adapters preserve exact binary64 values.

Add bounded constrained profile likelihood through the existing Ceres solver,
with exact captured model/observation binding and no repeat original fit. Retain
physical trial parameters, objective thresholds, open/boundary endpoints and
solver failures. Common CORE owns Gaussian inference meaning for both languages.

## 1.59.0

Add explicit pixel/calibration uncertainty propagation and retained full
covariance materialization through the existing propagation owner. Keep local
pixel errors separate from shared calibration factors; preserve physical units,
original rows, declared distributions, reviewed overrides and state integrity.
Common CORE owns eligibility and interpretation for both real Script languages.

## 1.58.0

Add Akima interpolation and explicit-knot B-spline approximation to the existing
curve-model API. Reuse Octave splinefit for B-spline least squares; retain exact
knots, degree, boundary slopes, continuity, state identity and physical units.
Shared query/geometry/export and both actual Script languages consume the same
state. CORE distinguishes descriptive interpolation/approximation and refuses
unvalidated inference. C0 corners retain unavailable derivatives at slope jumps.

## 1.57.0

Add public rational_residuals through existing evaluation and residual metrics,
with separate CORE descriptive meaning and no manufactured training inference.
Accept physical recipes in rational_domain and versioned state in model_export.
Retained geometry preserves original training bounds while sampling an explicit
output interval; whole-interval and extrapolation checks remain mandatory.

## 1.56.0

Add normalized physical rational declarations, bounded whole-interval denominator
guards, shared Ceres fitting and retained state/evaluation. Reuse dimensional
compilation, parameter covariance, model query and independent export. Register
all six operations for Tcl and real Python/Octave Jobs. CORE retains explicit
Padé-type approximation, domain, identifiability and conditional inference
meaning; comparison requires exact matched observations and predictor values.

## 1.55.0

Add versioned surface_model_state and surface_model_restore through the existing
public operation catalog and both Script bindings. Preserve exact physical
parameters, recipe constraints, coordinate-domain meaning and compiled identities;
refuse altered state without refitting. Fitter consumes this shared state owner.

## 1.54.0

Add physical surface declarations and explicit points/grid_yx fitting through the
existing formula/Ceres owners. Preserve exact original indices for omitted grid
cells, physical parameter covariance and both predictor identities. Add retained
evaluation/parameter Jacobians, sampled grids, descriptive residuals and standalone
Python/Octave XYZ export. CORE owns versioned surface interpretation and refuses
private geometry/inference bypasses. Real Script Jobs verify both input layouts,
typed summaries and lossless rank-two sampled-model Dataset publication.

## 1.53.0

Add retained complex real/imaginary/magnitude/db20 projection query, derivative,
local inverse, sampled geometry declaration and independent Python/Octave export.
Add public complex_residuals using the same captured physical model and Cartesian
whitening without optimization. CORE keeps evaluation metrics separate from
training DOF/covariance; typed adapters preserve invalid facts for rejection.
The shared fit-input policy preserves complex observation order and duplicates.
Align the native adapter limit with32 public formula predictors, enabling the
22-column three-channel whitening map, with an explicit predictor buffer bound.

## 1.52.0

Add reusable physical complex response declarations, full per-row Cartesian
covariance whitening, shared-parameter Ceres fitting and retained evaluation.
Extend the existing dimensional formula compiler to multiple responses without
changing scalar declarations. Add explicit linear/db20 polar conversion and
common CORE statistical interpretation. Real Script Jobs verify scientific
results and lossless publication through grouped real/imaginary Variables;
complex-valued Dataset dtypes remain unsupported by that separate contract.

## 1.51.0

Integrate retained implicit branch query/inverse/geometry and standalone
Python/Octave exports through the existing formula/root owners. Enforce exact
branch identities, physical derivative conventions, missing-root refusal and
bounded evaluation. Fitter and real Script consumers share these contracts.

## 1.50.0

Add general two-coordinate implicit equations, algebraic/reference-normalized
Ceres fitting, bounded explicit branch queries and common CORE statistical
interpretation. Reuse dimensional compilation, covariance and root owners;
normalization never implies measurement sigma or orthogonal error distance.

## 1.49.0

Add centered polynomial GLS through the shared polynomial basis and canonical coefficient identities. Extend the common CORE retained regression adapter and existing parameter uncertainty/report consumers to captured full covariance; preserve unavailable and exact-constraint meaning.

## 1.48.0

Add full observation-covariance linear GLS with explicit singular exact constraints, shared QR/SVD covariance, bounded source facts and reusable CORE interpretation. Expose the numerical and semantic operations to Python/Octave Script jobs.

## 1.47.0

Add deterministic finite-source characterization, reusable CORE advisory model
suggestions and Fitter/API/Script access. Reuse exact source input and captured
AIC/AICc comparison; no automatic fit, model selection or acceptance.

## 1.46.0

Registered Python/Octave scalar bootstrap now shares Numeric preparation,
sampling and summary with native fits. CORE captures actual callback solver
settings; Fitter binds exact retained predictors and persists typed ledgers.
Targeted tests cover three methods, independent analytic draws/covariance,
precision/fixed identities, rank/bound/failure/deadline records and cancellation.
No original fit is repeated. Historical results remain unchanged. Shared spectra
manuals now describe current mixed real/complex grids without implementation
chronology; this history remains here.

## 1.45.0

Add public CORE derived physical-property plans, interpretation and reports.
Numeric reuses existing dimensional compilation, native analytic derivatives
and one full-covariance propagation. Fitter evaluates accepted threshold/time/
knee/custom expressions and publishes independent physical-column Datasets.
Both Script languages share the public contracts; no accepted model is refit.

## 1.43.0

## 1.44.0 — dev097 integration in progress

Accepted-model Workbench transfer retains exact supported Native2D primitives,
independent axis units, original parameter mappings and immutable model resources.
Unsupported representations are explicitly sampled; no refit or statistics are
computed. Public Numeric/Fitter operations and CORE nested resource adoption
serve both scripting languages.
Workbench/current API manual chronology is moved to existing release history;
compatibility contracts and literal document paths remain unchanged.

Capture the actual Fourier input-order permutation on the uniform-grid FFT
branch and distinguish the nonuniform least-squares branch in fit_input_policy.
A missing captured solver branch is explicitly rejected. Fits are unchanged.

## 1.42.0

Add public fit_input_policy for captured model input decisions. PCHIP and
smoothing-spline state retain their existing sort permutation for row provenance.
No fit, evaluator or statistical algorithm is replaced.

## 1.41.0

Refuse implicit large-integer query narrowing; convert supported integer domains
before physical translation and inverse root arithmetic. Plain numeric lists with
large integers require explicit conversion or typed arrays.

## 1.40.0

Expose exact saved-model JSON decoding for text and typed uint8 Script inputs.
The canonical native adapter provides bounded linear tokenization up to128 MiB,
preserving binary64 words and existing JSON structure. Decode inverse models
once and share PCHIP value/derivative spline construction. Existing native fit,
prediction and parameter differentiation remain unchanged.

## 1.39.0

Add public live-callback retained queries and inverses for Python/Octave Jobs.
Declare numerical difference method, agreement limits, effective steps and
unavailable masks. Reuse the existing root owner and preserve prediction-only
behavior. Accept a scalar callback response only for an expected single row.

## 1.38.0

Retained physical-frame queries and inverse responses, analytic polar tangents,
and physical derivatives of centered/scaled polynomials. Existing default
polynomial and coordinate evaluation remains unchanged.

## 1.37.0

Public retained model_query/model_inverse, derivative-validity masks and explicit
extrapolation/branch contracts. Add native two-sided predictor AD, retaining
ordinary fit/predict/parameter-Jacobian actions. Functional curve tangents reuse
Numeric spline/analytic owners. No inference or accepted state is created.

## 1.36.0

Add public curve_model_parameter_state for validated compact arc, Bezier, open parametric polynomial and Fourier parameter mappings; existing solvers unchanged.

## 1.34.0 — integrated dev097 safe formula foundation

- Add a public data-only formula constructor using the shared CORE expression
  grammar and dimensional inference, explicit internal unit conversions and
  immutable original equations/constraints. Reuse the existing Ceres evaluator,
  analytic derivatives, fitting, CORE inference and standalone export paths.
- Preserve physical coefficient/covariance units and refuse incompatible or
  ambiguous dimensional formulas, unused parameters and changed declarations.

## 1.33.0 — integrated dev097 residual sequence diagnostics

- Add explicit-order runs, conditional runs reference, Durbin–Watson and bounded
  lag correlations through the public Numeric and Script operations. Preserve
  exact integer keys, input/order fingerprints and explicit omission conventions.
- Repair legacy Tcl LOWESS robust-iteration transport, reject unknown smoothing
  controls and reconcile its public operation catalog with the binary bindings.

## 1.32.0 — integrated dev097 reusable LOWESS

- Add bounded tricube local linear/quadratic smoothing and optional bisquare
  residual reweighting to the existing smooth and dataset_smooth operations.
- Preserve selected/omitted original row identities, reject unknown LOWESS
  settings and keep Python arrays on the managed binary transport.
- Guard Savitzky–Golay windows against retained input length.

## 1.31.0 — integrated dev097 callback solver receipts

- Validate actual SciPy method, limits, tolerances and parameter scaling before
  every callback fit, including all-fixed evaluation. Record backend/version,
  stopping reason and distinct solver/callback evaluation counts in a versioned
  receipt. Optimizer iterations are unavailable rather than renamed evaluations.
- Diagnose callback rank/conditioning in normalized Jacobian columns and map
  covariance back to physical parameter units. Preserve the legacy iteration
  option as an explicitly documented 20x function-evaluation budget.

## 1.30.1 — integrated dev097 registered prediction constraints

- Respect fixed masks and equal bounds during live registered-model evaluation.
  Keep full parameter order with zero fixed Jacobian columns, without perturbing
  fixed constants. Report the effective fixed mask and free count.

## 1.30.0 — integrated dev097 callback constraints

- Handle fixed_mask and equal-bound constants in the existing direct Octave and
  Script callback solvers. Optimize only free coordinates, preserve full physical
  parameter order and correctly report free rank, DOF and fixed covariance rows.
- All-fixed requests evaluate once without optimization. Validate fixed bounds
  and explicit dense-Jacobian limits. The declared Ceres path is unchanged.
- Withhold ordinary callback covariance for active free bounds or a deficient
  free rank, including known-sigma cases. Script reduced chi-square is unavailable
  unless the supplied weights are absolute inverse variances.

## dev097 integrated development — nested F testing

- Calculate nested polynomial F statistics and stable upper-tail probabilities
  from a public CORE plan and captured weighted SSE. Preserve degrees of freedom,
  roundoff flags and undefined states without refitting or reducing residuals.
- Publish the Tcl, Octave and both-language Script operation and shared contract.
- Consolidate user/API documentation into current behavior. Earlier positive
  coordinate translation and point ordering originated in dev096; the native
  solver, transport, inference, shared summaries, model library and diagnostics
  sections were extended during dev097. Mean-interval reference changes were
  at most 3.02e-13 relative to max(1,abs(reference)); named NIST cases are evidence
  for those inputs, not universal convergence. Retain full functional contracts
  in the manual and release history here.

## dev097 integrated development — parameter bootstrap

- Add public parameter refits for aligned pairs, standardized residuals and
  explicit Gaussian simulation through existing solvers, with deterministic
  seeds, bounded work, full trial accounting and typed retained draws.
- CORE owns eligibility, percentile interpretation, assumptions and publication
  meaning. Failed, unfinished or active-bound trials withhold nominal intervals;
  fixed/degenerate parameters retain distinct states. Share covariance/quantile
  owners and preserve exact captured predictor, response and precision hashes.
- Existing observation receipts remain readable; new refits require the additive
  predictor binding. The 199-replicate coverage probe is documented as mixed,
  not as proof of nominal calibration. Fitter integration follows separately.

## dev097 integrated development — linear influence

- Add opt-in exact linear-design leverage, Cook/studentized diagnostics and
  leave-one-out values using the existing fit factorization, with uint64 original
  input positions and explicit rank/scale availability. Expose general matrix
  least squares through both Script Bridge languages and its distinct CORE model.

# 1.29.0 — dev097 in development

- Add dimensionless natural log ratios with explicit same-unit references and
  physical response retransformation. Preserve near-reference accuracy, reject
  nonpositive domains and unrepresentable physical outputs; CORE owns median,
  plug-in arithmetic mean and captured-interval interpretation.

- Export exact retained registered sources through the existing model exporter,
  with explicit original-language runtime adapters, physical mapping and source
  provenance; do not evaluate source or refit during generation.

- Propagate registered callback response intervals through the existing Numeric
  prediction owner; preserve exact identities and actual callback allocation facts.

- Evaluate live declared model callbacks with bounded Jacobians, source identity
  and strict column-response contracts. Compute callback covariance directly
  from weighted-Jacobian SVD; report physical residual and weighted variance facts.
- Expose existing positive translation and uniform grids through Script Bridge.

# 1.28.0 — dev097

- Reuse one CORE-owned constant predictor argument throughout a callback fit and
  release consumed callback output buffers through their originating runtime.
  Exception paths release the same resources. Existing numerical solvers remain.
- Refuse complex operands and integers outside exact float64 representation in
  real-valued callback operations instead of silently discarding information.

# 1.27.0 — dev097

- Export frozen model evaluation as independent Python/Octave functions and LaTeX,
  with controlled compiler statements, exact constants, physical-coordinate
  mapping, domains, original parameter metadata and stable special functions.

# 1.26.0 — dev097

- Add public AsLS baseline estimation using compiled sparse augmented QR, explicit grid and convergence receipts, exact selected/Dataset row identities and both Script bindings. Preserve existing baseline signatures and alternatives.

# 1.25.0 — dev097

- Add independent knee and regional increment descriptors, public joint C0/C1
  region composition, physical breakpoint constraints and observation windows.
  Exact selected positions and bounded support facts travel with the fit.
- Add stable native positive_part, exprel and minimum declared-expression
  primitives. Preserve all earlier opcodes. Branch selection retains completed
  increments and flat knee levels even far beyond observed support.
- Bind regional Dataset recipes to actual axis units and original row ordinals.

# 1.24.0 — dev097

- Capture exact ordered response/weight fingerprints and physical-to-translated
  response bindings. Add Gaussian likelihood, AIC, AICc and BIC from public CORE
  plans and existing fit facts; preserve distinct physical RMSE and residual SD.
- Use the shared typed result writer/reader for legacy Tcl calls, including
  bounded nested receipts. No change to scientific model or parameter identities.

# 1.23.0 — dev097

- Add independent Voigt area, continuous logistic response, Arrhenius activation
  temperature, exponential decay and series-resistance Shockley model cards.
  Multiple decay components reuse the shared fitter. Preserve historical model
  identities and frozen definitions.
- Extend the controlled expression VM with stable Voigt/logistic/implicit-diode
  values and derivatives. Enforce physical unit/domain declarations, including
  positive ODR-adjusted predictors; Dataset recipes must match actual axis units.
- Frozen input and translation constraints accompany typed model state. CORE
  remains the single statistical interpretation owner for GUI and both Scripts.

# 1.22.0 — dev097

- Discover independent scalar model cards and compose frozen peak/baseline
  expressions with stable parameter identities, units, shared parameters and
  captured bounds. Reuse public native fitting, evaluation and CORE uncertainty.

# 1.21.0 — dev097

Add genuine explicit-model XY uncertainty fitting through existing declared
Numeric operations and native Ceres latent-coordinate elimination. CORE owns
versioned objective, covariance, DOF, data-field and conditional interval
semantics. Preserve exact Dataset row identities and bounded model policy;
replay requires original measurement inputs. Both real Script languages use
the shared binary transport. Independent ODRPACK/Deming and Fitter evidence
is recorded in integrated checkpoint 94.

# 1.20.0 — dev097

Add bounded explicit or reproducibly seeded multistart to the shared declared
nonlinear fit. Reuse existing Ceres solves and Numeric random generator; retain
one computed winner with every trial's bounded receipt, failure accounting,
fixed-parameter policy and overall time limit. Public CORE validates and reports
these records for all consumers, including real Python and Octave jobs.

# 1.19.0 — dev097

- Preserve sample covariance, native eigenvalues, condition and rank while adding actual observation/variable counts and explicit real/imaginary components for CORE interpretation. Data-only foundation Script Bridge calls now use the existing CORE binary channel, including complex matrix results and result-field projection.

- Group Kaplan-Meier event/censor counts once while preserving the accepted sequential product limit, including ties and censor-only coordinates. Expose actual risk sets through CORE and support binary foundation captures under an existing Document owner.

- Partial correlation records the actual covariance-pseudoinverse method, rank, dimensions and normalization validity. Multiple testing records the selected adjustment, family size and original hypothesis positions. Valid accepted numerical results are preserved; nonreal/misaligned observations and invalid p-values reject explicitly. CORE supplies their shared interpretation.

- Captured-column Tcl calls use binary input/output with the existing CORE Document owner and statistical binding, without rerunning the numerical operation.

- Foundation bootstrap/permutation results retain seeded type-5 quantiles and strict absolute-tail counting, with additive CORE inference facts and seed provenance. Invalid noninteger/random seeds and complex observations reject explicitly.

- Foundation mean intervals and fixed-scale Huber location expose actual count, inference and convergence facts for public CORE interpretation. Mean intervals use the existing public Student-t quantile owner, fixing fresh-worker failure when Octave statistics was not loaded.

- Matrix/reduction summaries expose actual input/output shapes and distinct one-operand summary versus two-operand accumulation signatures in Tcl and Script Bridge. CORE interprets their retained facts without recomputation.

- Spectral estimators use one explicit native Welch/periodogram owner, shared mixed-complex grids and CORE per-frequency units/availability/column bindings. Signal exposes public contract discovery.
- Window gain and ENBW use public Numeric and CORE deterministic semantics, including scale-stable bandwidth and truthful unrepresentable power gain.
- Sequence correlation delegates to the public Numeric owner with bounded CORE meaning, retained uncentered lag identity and scale-stable coefficient normalization.


Public statistical primitives and CORE-compatible receipts now cover spectral
features, Welch/band power, local-cloud and replicate profiles, signal quality,
FFT/harmonic components and event timing. Native Ceres inference uses the shared
column-scaled factorization. Full-rank linear solves now use that same column
scaling before restoring physical coefficients; explicit physical minimum norm
is retained. See the framework checkpoint receipts for exact verification scope.

# math.numeric 1.18.0 — dev097

Public `spectral_features` now owns the existing spectral-distribution algorithm,
with a registered CORE model and typed catalog/Script Bridge exposure.

Dev097: the Numeric-owned `comparison` descriptor exposes public CORE meaning for already-computed pointwise error metrics. It introduces no new error-estimation algorithm and makes no regression or sampling-inference claim.

Statistical array reductions now carry per-group input/valid counts and original
axis/shape facts for CORE interpretation. Model declarations expose default
operation associations without changing captured descriptor records. Regression
through the origin has an explicit slope-only descriptor; ordinary linear
regression keeps its intercept/slope identity. `has_intercept` and the established
`intercept` option agree for the linear wrapper, and conflicting aliases reject.
Typed catalog options no longer occupy an omitted weights argument in general
LS, linear or polynomial fitting.

Dataset summary names now have Script Bridge parity while preserving the accepted
`statistics_dataset` spelling. Typed catalog/model calls and both Script Bridge
fit backends resolve named Selections before calculation. Callback intervals
match Octave's inclusive reversed-bound behavior and reject mismatched Variables.
The shared generic provider worker loads public CORE Dataset/analysis utilities.

Declared nonlinear expressions use the existing CORE grammar and Numeric-owned
Ceres backend, with automatic derivatives, physical parameter scaling, native
bounds, fixed parameters and explicit weighted joint responses. Existing
callback signatures remain supported. Nonlinear covariance now uses the
column-scaled Jacobian SVD, avoiding the squared condition number of a normal
matrix. Shared binary resources carry Script Bridge inputs and outputs.
Numerical evidence is scoped to the named case/start/platform in delivery
receipts;

# math.numeric 1.17.0

Reusable reversible positive-axis translation and optional reviewed point ordering, including retained closed endpoints.

# 1.16.1 — dev093

Use the shared typed binary Script Bridge worker without changing scientific
algorithms or public v1 defaults. Preserve existing Tcl/Octave consumers.

# math.numeric changelog

## 1.16.0 — GX-TXT0.9.8.10-dev-052




Ordered parametric/polar/oriented models, sparse smoothing and indexed native cubic projection, exact reconstruction and independent scientific validation.

## 1.12.0 — Execution-scoped script callbacks

## 1.13.0 — P1/P2 mathematical foundation

- Added Schur, principal matrix logarithm/square root, stiff ODE/events/dense output, variational/equations/sparse/statistics/geometry families and VTK-backed mesh/STEP cuts.
- Added derivative-free constrained fallback and advanced special functions.
- Validated 67 known-answer checks plus public API and Bridge discovery.

- Accept registered Octave and Python callbacks for public ODE, constrained optimization, callable derivatives, root finding, minimization and nonlinear fitting, including Dataset fitting.
- Keep callback registration and reverse invocation in the shared Script Bridge; preserve direct Octave and data-only provider paths.

## 1.11.0 — Mathematical foundation extension

- Add vector/tensor algebra, 2D/3D regular and scattered interpolation, integration, finite differences, adaptive ODE IVP, constrained SQP/KKT diagnostics and essential special functions.
- Expose data-only foundation operations through the same provider-owned Octave/Python Script Bridge.

## 1.10.0 — Mathematical API foundation

- Add split-complex matrix transport, inspection, solve with explicit rank policy, decompositions, eigenproblems, inverse/pseudoinverse, matrix exponential/power and provider-owned Octave/Python Script Bridge operation.
- Add focused numerical and script acceptance fixtures.

## 1.9.1

- Resolve Dataset Selections through public read-only Session Inspection and Canonical Dataset variable metadata.

# math.numeric changelog

## 1.9.0

- Added data-only operation introspection to the Tcl and Octave bindings, with stable IDs, signatures, binding availability, result metadata, and unit rules.
- Added explicit input/valid/nonfinite observation counts to descriptive and weighted results; expanded axis reductions and typed Script Bridge result adaptation.
- Added generic ranking, covariance, Pearson/Spearman correlation, MAD, histogram, ECDF, split-complex arithmetic/phase, probability CDFs, matrix SVD, and seeded resampling indices.
- Added a chunk-composable Dataset summary for count, sum, mean, min, and max; full-result and sorting/fitting operations retain their explicit memory requirements.
- Shared Scientific Analysis expressions now dispatch arithmetic and discoverable functions through the public numerical API.
- Added Octave `student_t_quantile` and `hypothesis_test` primitives for one-sample, independent, Welch and paired t-tests plus Mann-Whitney and signed-rank tests. Rank tests use exact conditional enumeration for at most 20 observations and a documented tie-corrected normal approximation for larger samples.
- Added Octave `one_way_anova` for ordinary and Welch group comparisons, group summaries, F/p values, sums of squares and ordinary-ANOVA effect sizes.

## 1.8.0

- Adds public `residual_metrics` to NUMERIC_API_v1 for reusable RMSE, MAE, maximum error, R² and relative-error summaries, with a finite-input and relative-floor contract.

SPDX-License-Identifier: GPL-3.0-or-later

## 1.6.0

- Added public Octave `matrix_statistics` with dimension-aware mean, median, variance and standard deviation for replicated curve datasets.

## 1.5.0

- Added public `vector_normalize` / `normalizeVector` with `unit_vector` and `mean_center_unit_vector` methods.
- Added public `vector_similarity` / `vectorSimilarity` with cosine, Pearson, angular-similarity and normalized-residual methods.
- These generic primitives remove reusable vector mathematics from spectroscopy/domain consumers while preserving their scientific matching semantics.

## 1.4.0

- Added public `weighted_quantiles` / `weightedQuantiles` for arbitrary weighted empirical-CDF inverse quantiles.
- Added public `cumulative_sum` / `cumulativeSum` as a generic vector reduction.
- These additions allow scientific consumers such as `analysis.spectral_features` to keep percentile and cumulative-distribution semantics in the analysis layer without implementing generic reductions privately.

## 1.3.0

- Added public `analytic_signal` / `analyticSignal` construction using the standard FFT Hilbert multiplier for even and odd real-valued records.
- The primitive returns split complex data plus amplitude and deliberately excludes detrending, band selection and PSD/spectrum semantics.
- Added Octave and Tcl regression coverage and exposed the `analytic_signal` capability through normal dependency discovery.

## 1.2.0

- Added public `NUMERIC_API_v1` FFT and IFFT primitives with explicit transform length and normalization conventions.
- Added reusable frequency-grid and one-sided transform selection helpers with explicit DC/Nyquist behavior.
- Added generic `none`/`mean`/`linear` detrending and reusable rectangular, Hann, Hamming, Blackman, Blackman-Harris and flat-top windows.
- Exposed the new data-only operations through the Tcl facade/worker using split real/imaginary transport for complex transforms.
- Added deterministic transform, round-trip, odd/even, frequency-grid, detrend and window regression coverage.

## 1.1.0

- Completed `NUMERIC_API_v1` before framework integration while preserving the existing v1 operation names where practical.
- Removed the dependency on internal `gxtxt_analysis_dispatch_kernel` implementation details; low-level primitives now use documented GNU Octave numerical functions.
- Added nearest/linear/cubic/spline/PCHIP interpolation, arbitrary-grid resampling, portable spline models, spline evaluation and spline integration.
- Added cumulative integration, non-uniform-coordinate differentiation, uniform-grid generation, monotonic validation and expanded grid statistics.
- Added quantiles, expanded descriptive/weighted statistics, linear regression and richer OLS/WLS diagnostics.
- Added arbitrary-degree polynomial fitting, weighted polynomial fitting and polynomial model evaluation, with explicit relative/inverse-variance weight semantics for covariance scaling.
- Added generic nonlinear least squares with structured diagnostics, optional bounds through Octave `optim`/`lsqnonlin`, and an unbounded `fminsearch` fallback.
- Added moving mean, moving median, Savitzky-Golay and local-polynomial smoothing; coefficient-based causal digital filtering.
- Added generic peak detection with height, distance, prominence and width primitives.
- Added constant, linear, polynomial and anchor-interpolated baseline estimation with corrected-signal output.
- Added scalar root finding, one-dimensional and multivariable minimization, plus first-order covariance/independent uncertainty propagation.
- Expanded Dataset-aware operations to interpolation/resampling, cumulative integration/differentiation, weighted statistics, polynomial fitting, nonlinear fitting (Octave callback binding), smoothing, peaks and baseline estimation.
- Removed Plugin Install API packaging/instructions: `math.numeric` remains bundled CORE.

## 1.0.0

- Initial protected bundled numerical service with interpolation/resampling, integration/differentiation, grid/range utilities, statistics, OLS/WLS and basic Dataset-aware operations.
# 1.7.0

- Added explicit bounded `fminsearch` penalty/clipping and optional `auto` solver retry to the public Octave `nonlinear_fit` operation. Curve Family Fitting can now use the CORE numerical service while preserving its prior bounded fallback.
## 1.14.0 — Guided mathematical clients

- Added provider-owned discovery metadata for 115 foundation subactions.
- Added public data-only catalog dispatch, including Octave-only statistics operations, and bounded declarative model callbacks for guided clients.
- Extended shared scientific transport to preserve nested result structs and cells.
# dev097 parameter uncertainty

- Shared least-squares covariance now uses a column-scaled Jacobian QR/SVD,
  preserving the existing solve and polynomial coefficient convention. Longley
  standard errors now agree with the certified reference within recorded tolerance.
- Added public `parameter_uncertainty`: correlation and marginal intervals from
  a CORE inference plan, without refitting. Tcl, Octave and both Script languages
  share the numerical owner.


## 1.19.0 — integrated dev097

- Public allocation-free C99/C++ native residual reductions used by Native2D,
  with scaled extreme-value arithmetic, stable first-maximum identities and
  atomic error handling. No scientific interpretation is delegated to viewers.

natural cubic smoothing keeps its original objective and
manual lambda0 semantics, adds O(N) native exact trace diagnostics and explicit
bounded deterministic GCV. Independent dense/SciPy references, typed CORE/Script
jobs, saved Fitter replay and active native cancellation targeted PASS.

## 1.35.0

Public bounded initial suggestions for linear, polynomial, signed power-law,
exponential and Gaussian models reuse existing least-squares and native
expression evaluation. Explicit bounds/fixed values, unavailable conditions and
initialization-only receipts are shared by Tcl, Octave and both Script languages.

## 1.50.0 — implicit equation foundation

Added versioned two-coordinate implicit declarations, bounded Ceres equation
fits, retained equation evaluation and explicit local branch queries through
existing unit, solver, covariance, root and AD owners. Physical reference
normalization is never interpreted as sigma or ODR. Common CORE interpretation
retains conditional uncertainty and truthful unavailable branch/inference cases.
