# Parameter-refit bootstrap: CORE and Numeric contract

This interface uses `STATISTICAL_RESULT_SEMANTICS_API_v1` for
scientific meaning and `NUMERIC_API_v1` for numerical work. It does not change
the canonical identity of an existing model, parameter or historical Session.
It is available to Tcl, standalone Octave and real Python/Octave Script Jobs.
Fitter supplies default-off settings, retained typed pages and a readonly Results
dialog; see [Fitter API](DATASET_CURVE_FIT_API_v1.md#retained-parameter-bootstrap).

1. Capture the original fit through `from_numeric`, with actual physical units,
   training role, constraints and noise assumptions.
2. Normalize/validate settings with CORE `bootstrap_settings(settings)` (Tcl
   `bootstrapSettings ?settings?`), then call `bootstrap_plan(source, settings={})`
   (Tcl `bootstrapPlan`).
   Settings are `method=pairs|residual|parametric_gaussian`, `replicates=1000`,
   `seed=1`, `confidence=.95`, `max_seconds=60`. Check `status` and `reason`.
3. Call Numeric `fit_bootstrap(model, X, y, plan, options={})`. Supply the
   captured fitted model and exact retained rows, with `options.weights` when
   weighted. Tcl `fitBootstrap` accepts typed model/X/y/options and the ordinary
   CORE plan dictionary; the operation is also in the typed catalog.
4. Call CORE `bootstrap_interpretation(source, raw)` (`bootstrapInterpretation`
   in Tcl), then its existing `validate`, `report`, `numeric_data_fields` and
   `publication_metadata` APIs. Python and the Octave statistics facade keep
   the large draw arrays out of the bounded interpretation call.

The plan schema is `STATISTICAL_FIT_BOOTSTRAP_PLAN_v1`, numeric receipt schema
`gxtxt.fit_bootstrap_numeric.v1`, and interpretation schema
`gxtxt.regression_bootstrap_interpretation.v1`. API/strategy versions are 1.
All fitted/fixed parameter IDs and units retain the original order. Model source
and binding digests, fitted values, original predictor/response/positive-weight
digests and shapes must agree. Existing fit receipts without a predictor hash
still validate and load; their bootstrap plan is explicitly unavailable until
the user makes a new fit. No historical result is rewritten.

Supported estimators are scalar-response full-free-rank linear-design least
squares, ordinary/origin linear regression, scaled polynomial fitting and
declared Ceres response models and registered Python/Octave scalar callbacks,
including fixed parameters and inactive bounds. Registered callbacks run inside
a supervised Script Job configured with one internal thread. The captured SciPy
backend/version, method, evaluation budget, bounds, parameter scales and three
stopping tolerances must match the original estimator. The original fit must
converge. Joint responses, orthogonal distances and radial geometry are outside
this operation. A caller cannot turn them into ordinary response uncertainty
by changing a label. Dataset ownership, filtering and row identity remain with
the calling scientific module; Numeric additionally verifies retained input
bytes, so an unchanged response cannot conceal a changed design.

| Method | Sampling meaning |
| --- | --- |
| `pairs` | Resample whole predictor/response/precision tuples; assumes IID observation tuples and treats design as random. A supported robust estimator retains its captured loss. |
| `residual` | Fixed design and relative/unweighted precisions; center weighted residuals and scale the pool to the captured estimated residual SD, then resample and unweight. Assumes a common independent standardized error distribution and ordinary least-squares loss. |
| `parametric_gaussian` | Fixed design with explicit independent Gaussian noise. Known absolute precision simulates SD `1/sqrt(weight)`; estimated relative precision uses the captured weighted residual SD. Requires the matching noise declaration and ordinary loss. |

The original fit is not repeated (`original_fit_count=0`). Each generated trial
uses the existing public solver, starts at the captured fitted parameters and
retains captured bounds, fixed mask, parameter scales, loss and tolerances.
Nonlinear results remain conditional on the recorded local solver and basin;
this is not a global-optimum guarantee or a rerun of the original multistart
search. Fits run sequentially with one internal solver thread. `park_miller_16807_v1`
supplies the isolated sequence; Gaussian simulation uses `box_muller_pairs_v1`.
Each trial stores its starting seed and the receipt stores the final seed.
This sequence does not consume Octave's ambient random state.

Both drivers share three public Numeric stages through the typed operation
catalog and Script Bridge: `fit_bootstrap_prepare(model,X,y,plan,options)` checks
exact observations/model identity and prepares one data-only state;
`fit_bootstrap_draw(state,seed)` generates one aligned dataset and next seed;
`fit_bootstrap_summarize(state,samples,status,seeds,execution)` validates the
bounded ledger and calls the existing covariance and quantile owners. Execution
contains attempted_count, next_seed, elapsed_seconds and at most eight diagnostic
messages. The state schema is `gxtxt.fit_bootstrap_state.v1`; pass it unchanged,
within the same calculation. It is scratch data, not an opaque capability or a
new persisted Session object. Callback preparation uses a data-only
`registered_callback_evaluation` with exact evaluation_query/predicted arrays and
source/binding identities. Ordinary clients use `fit_bootstrap` with a live
`registered_callback` model; no callback handle crosses into Octave. No bootstrap
sampling or summary formula is duplicated in the callback driver or Fitter.

Large results use binary transport: `parameter_samples` is float64 `[B,p]`,
`replicate_status` is uint8 `[B,1]`, and `replicate_seed` is uint32 `[B,1]`.

| Status | Meaning |
| --- | --- |
| 0 | Not attempted; seed is zero, draw is NaN. |
| 1 | Finite converged full-free-rank trial without active bounds. |
| 2 | Rank failure. |
| 3 | Solver did not converge. |
| 4 | Nonfinite result or changed fixed declaration. |
| 5 | Solver/generation error; bounded diagnostic is retained. |
| 6 | Converged at an active bound; finite draw retained. |
| 7 | Sample generated, then stopped at the shared time budget. |

Failures and unfinished trials keep their original positions and NaN draws;
there is no resampling-until-success. At least two successful trials yield
descriptive sample covariance/SE through the existing covariance owner once.
Shifting draws by one retained draw before this translation-invariant reduction
keeps fixed columns exactly zero and reduces large-offset cancellation. Only
when all requested trials have status 1 and a finite summary are marginal
percentile bounds computed by the existing Hyndman-Fan type-7 quantile owner.
Any failure, active-bound event or unfinished trial withholds nominal bounds.
Fixed parameters have `not_applicable` intervals; point-mass free distributions
have `undefined` intervals, even if the raw quantile is a single value.
The result is frequentist, approximate, marginal uncertainty, not simultaneous
coverage or Bayesian posterior probability. CORE reports these qualifications.

Repetition limits are 20–10,000, seed 1–2,147,483,646, parameter count at most 128,
row count at most 1M, `n*B <= 10M`, `n*p*B <= 128M`, and a conservative 512 MiB
workspace estimate. These are bounded work/allocation estimates, not measured
whole-process RSS guarantees. One sampled dataset exists at a time. The shared
time budget is checked before generating/starting each refit and passed to
Ceres. The callback driver checks it before and after every callback; one
callback can finish after the soft deadline, subject to the existing host callback
timeout. A host timeout, closed transport or released callback aborts the Job;
ordinary callback errors retain failed-trial positions. An in-progress direct
solve and the final bounded summary can also finish after the soft deadline. Worker cancellation discards an incomplete result through
the existing job/resource lifecycle. Fitter cancellation preserves prior previews
and accepted results.

Finite replicate counts affect percentile accuracy. CORE reports
`(B-1)*(1-confidence)/2` order-statistic positions per tail and flags quantiles
at extreme boundary positions. A 100-dataset known-Gaussian probe with 199
replicates covered 94 intercepts and 89 slopes for nominal 95% intervals; it
does not establish 95% calibration. Independent replay matched every captured
interval within `1.56e-15`. The same observations had analytic coverage 97/94;
an independent 999-draw reference gave 96/94. The latter is reference analysis,
not another production test campaign. Increasing replicates reduces Monte Carlo
quantile error, but cannot correct invalid sampling or model assumptions.

The mandatory architecture validator treats private parameter covariance/SE
computation, private CORE calls and unvalidated reporting as bypasses. Its
negative fixtures cover these cases; no module-local inference dictionary or
second statistics estimator is introduced.

Primary methodological references: [R boot](https://stat.ethz.ch/R-manual/R-devel/library/boot/html/boot.html),
[R bootstrap intervals](https://stat.ethz.ch/R-manual/R-devel/library/boot/html/boot.ci.html),
and [Fox's regression bootstrap appendix](https://www.john-fox.ca/Companion/appendices/Appendix-Bootstrapping.pdf).
