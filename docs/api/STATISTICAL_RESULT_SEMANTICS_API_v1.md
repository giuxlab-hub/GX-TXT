# Statistical Result Semantics API v1

Constrained Gaussian parameter profiling uses the public
[profile-likelihood contract](FIT_PROFILE_LIKELIHOOD_v1.md). Physical search limits, actual
thresholds, local-solver qualifications and unresolved endpoints remain explicit;
covariance-based Wald intervals retain their separate approximation.

Canonical `math.numeric.akima` and `math.numeric.bspline` adapt bounded
`gxtxt.knot_spline_summary.v1` facts from `curve_model_fit`. Shared interpretation
preserves interpolation/approximation, continuity, boundary, units and state
identity while rejecting unvalidated parameter inference. See the
[knot-model contract](KNOT_SPLINE_MODELS_v1.md).


`rational_residuals` uses the same rational owner with descriptive evaluation
scope, its actual count/extent and no training covariance or DOF. Injected solver
inference is rejected at the public typed boundary.


Canonical `math.numeric.rational` adapts `rational_fit` with the captured physical
coefficient identities and whole-interval domain receipt. CORE preserves local
conditional inference and refuses private pole-domain bypasses. Rational model
comparisons require exact matched predictor values as well as the existing
source, row, response, weight and noise identities. See the
[rational response contract](RATIONAL_MODELS_v1.md).

Canonical `math.numeric.surface` adapts `surface_fit` and `surface_residuals`
with explicit `z_of_xy` residual geometry, both exact predictor identities,
physical response/parameter units and original missing-cell provenance. Training
and descriptive evaluation remain distinct. See the
[surface response contract](SURFACE_RESPONSE_MODELS_v1.md).

Public `residualSequenceInterpretation` / `residual_sequence_interpretation`
provides versioned explicit-order residual sequence meaning, validation and
reporting for all scientific modules and both Script languages. See the
[residual sequence contract](RESIDUAL_SEQUENCE_v1.md).

API ID: `STATISTICAL_RESULT_SEMANTICS_API_v1`. Provider: CORE
`statistical_result_semantics`. Schema: `gxtxt.statistical_result.v1`.
Implementation: `core/tcl/statistical_result_semantics_api_v1.tcl`.
This API interprets existing numerical results; it does not fit models, estimate
covariance, recompute residuals or start an interpreter for normal CORE calls.
`math.numeric` / `NUMERIC_API_v1` remains the numerical authority.

Public `nestedFPlan` / `nested_f_plan` and `nestedFInterpretation` /
`nested_f_interpretation` expose matched nested polynomial testing. See the
[complete versioned nested-F contract](NESTED_MODEL_F_TEST_v1.md) for exact
eligibility, Numeric calculation, unavailable cases, persistence and both-language
examples. This reusable CORE contract is also consumed by Fitter accepted results.

## Comparable fitted-model criteria

Tcl `modelSelectionPlan result binding` and Script `model_selection_plan` return
`STATISTICAL_MODEL_SELECTION_PLAN_v1`, version 1. `result` is a validated training
fit. `binding` has exactly `schema=gxtxt.observation_binding.v1`, `source_id`,
`source_sha256` and `rows_sha256`: an immutable source identity, its SHA-256 and
the SHA-256 of exact original row ordinals in fit order. Dataset/array producers
must capture these identities; this declaration alone does not prove that two
arrays are the same observations. Numeric's independently captured ordered
response and effective positive-weight fingerprints must also agree.

The plan requires identified free parameters, converged ordinary vertical
regression, linear loss, no active bounds and an explicit independent Gaussian
noise model consistent with the actual weights. Fixed parameters are excluded
from the parameter count. Missing legacy receipts remain unavailable. Geometric,
radial, joint-response and XY-error likelihoods need distinct contracts; this
operation does not assign them ordinary vertical-regression AIC.

Pass an eligible plan to Numeric `fit_information_criteria`. For estimated scale,
ML variance is weighted SSE/N, K=p+1, and
`-2 log L = N*(log(2*pi)+1+log(SSE/N)) - sum(log(weights))`.
For known absolute sigma, K=p and
`-2 log L = N*log(2*pi) - sum(log(weights)) + weighted SSE`.
AIC adds 2K; BIC adds K log N. AICc adds `2K(K+1)/(N-K-1)` to AIC only for
estimated Gaussian scale with N>K+1. Its nonlinear application is a local
asymptotic approximation. Known-sigma AICc is unavailable. A perfect fit with
estimated zero scale has no finite maximized likelihood. These conventions
retain the full density normalization, following the parameter/constant
conventions in [R logLik](https://www.stat.ethz.ch/R-manual/R-devel/library/stats/html/logLik.html)
and [R AIC](https://www.stat.ethz.ch/R-manual/R-devel/library/stats/html/AIC.html);
the correction is explicit in the [statsmodels implementation](https://www.statsmodels.org/v0.14.6/_modules/statsmodels/tools/eval_measures.html).

`modelComparison entries ?criterion?` / Script `model_comparison(entries,
criterion)` return `gxtxt.model_comparison.v1`. Criterion is `rmse`, `aic`, `aicc`
or `bic`. Each of one to 64 entries contains a unique canonical `id`, `result`,
`binding` and, for an eligible likelihood, its Numeric receipt in `numeric`.
One entry permits validation/presentation of captured criteria; comparing
alternatives requires two or more. CORE rechecks the exact plan, count/scale
policy, ordered observations, weights, source/row identity, variables, units,
orientation and likelihood. Mismatches return unavailable with explicit reasons
and no ranking. It does not refit or recompute scores. RMSE uses the physical,
unweighted RMS residual already supplied by Numeric; it is descriptive and does
not penalize complexity. Each result row includes the score's `unit`.

For additive response translation, the training result may carry Numeric's
`physical_observation_signature` in provenance. Its `response_offset` must equal
the recorded `context.translation.v.delta`, and its `fit_response_sha256`, N,
weight SHA and normalization must exactly match the actual fit signature. CORE
then compares physical responses. Without this evidence, a nonzero translated
response is unavailable; it is never relabeled as an original response.

Comparisons support `validate`, `validated_result`, `report` and
`publication_metadata`, including real Python/Octave Jobs. `report` presents
the captured criterion, units, counts, ranking or refusal, and assumptions.
Do not pass this comparison schema to individual-fit parameter/scalar APIs.
No comparison accepts a model or establishes physical correctness.

```python
plan = call("STATISTICAL_RESULT_SEMANTICS_API_v1", "model_selection_plan",
            [fit_statistics, observation_binding])
score = call("NUMERIC_API_v1", "fit_information_criteria", [plan])
entries.append(dict(id="candidate_2", result=fit_statistics,
                    binding=observation_binding, numeric=score))
comparison = call("STATISTICAL_RESULT_SEMANTICS_API_v1", "model_comparison",
                  [entries, "aicc"])
print(call("STATISTICAL_RESULT_SEMANTICS_API_v1", "report", [comparison]))
```

## Pointwise response confidence and prediction

`predictionInferencePlan result ?kind? ?confidence?` and Script
`prediction_inference_plan(result, kind="mean_confidence", confidence=0.95)`
return `STATISTICAL_PREDICTION_INFERENCE_PLAN_v1`, version 1. The source must be
one captured functional regression with an evaluable model. The plan reuses the
parameter-inference eligibility, coefficient coordinates, free-parameter order,
covariance, distribution and approximation. It retains fixed parameter values
for model evaluation and excludes them from covariance propagation. Missing
measurement assumptions or model identities remain explicitly unavailable.
Projected geometry and joint response covariance require their own response
model and are not certified by this scalar-response plan.

`mean_confidence` concerns the fitted conditional mean at one query.
`new_observation` adds independent future response noise. Unweighted estimated
Gaussian errors use the captured DOF-scaled residual standard deviation. Relative
weights require explicit future relative precision; known absolute measurement
sigma requires explicit future sigma. Training sigmas do not supply future
measurement noise. These are pointwise intervals, not simultaneous regions, and
nonlinear covariance propagation is a local approximation. Extrapolation does
not validate the physical model.

Pass an eligible plan, the exact fitted model and query coordinates to Numeric
`prediction_uncertainty`. Then call Tcl `predictionInterpretation source raw`
or Script `prediction_interpretation(source, raw)`. CORE checks the source plan,
compiled formula/binding identities, actual counts and recorded critical value.
The result uses model `math.numeric.prediction_uncertainty` and the existing
`gxtxt.statistical_result.v1` schema. It stores bounded source/covariance facts
and one interval summary; original prediction arrays remain in numeric transport.
Both Script bindings filter arrays out before sending interpretation to Tcl.
The result supports ordinary validation, reporting and publication metadata.

Polynomial fits also capture `polynomial_propagation_basis` in source provenance.
An eligible plan carries that record as `propagation_basis`, with API ID
`STATISTICAL_POLYNOMIAL_PROPAGATION_BASIS_v1`, version 1, kind
`centered_scaled_descending_power`, `query_center`, `query_scale`,
`source_parameters` and `source_covariance`. These are the already computed
scaled coefficients and covariance from the original Numeric fit, in descending
powers of `z=(query-query_center)/query_scale`. CORE checks their bounded shape
and finite coordinates without transforming or estimating covariance. Physical
coefficient IDs, values, units and covariance remain in the ordinary parameter
plan. Missing scaled facts make polynomial response inference unavailable;
historical data are preserved without inventing a new inference claim. The
plan and interpretation validation include the complete captured basis.

`numeric_data_fields(result)` describes original `predicted`,
`mean_standard_error`, `observation_standard_deviation`, `standard_error`, `lower`,
`upper`, `bounds_available` and `query_index` vectors. Response-valued fields use
the fitted response unit. Query indices identify original query rows. Bounds
reference their mandatory `bounds_available` companion: zero means both bounds
are unavailable, represented numerically as NaN. `nonfinite_status` and
`nonfinite_reason` describe nonfinite data without inventing finite values.
Worksheet selected windows save the matching availability mask with their
captured values, validate it when reopening, and display the CORE reason.

```python
plan = call("STATISTICAL_RESULT_SEMANTICS_API_v1",
            "prediction_inference_plan", [fit_statistics, "mean_confidence", .95])
raw = call("NUMERIC_API_v1", "prediction_uncertainty", [fitted_model, query, plan])
meaning = call("STATISTICAL_RESULT_SEMANTICS_API_v1",
               "prediction_interpretation", [fit_statistics, raw])
```

The public plan/result path is available to Tcl and real Python/Octave Script
Jobs. Fitter uses it in its existing numerical worker, retains owned interval
columns and display boundaries, and publishes the same interpretation with
physical-coordinate columns. See the Fitter manual for settings and limits.

## Captured columns in managed Document resources

`bindResourceColumns prototype resource column_variables row_count ?row_start?`
and Script `bind_resource_columns` bind a captured scalar prototype to an existing
canonical Document resource. The additive schema is
`gxtxt.statistical_result.resource_binding.v1`. The resource owner verifies its
generation, exact byte size and SHA; CORE verifies the prototype, fact identities,
physical units and row span. The declared format is
`gxtxt.statistical_facts.float64_column_major_le.v1`, with positive `row_count` and
one to 128 ordered `variable_schema` records (`variable_id`, `unit`, `dtype`,
`rank`, `shape`, `dimension_ids`). Each column is a real binary64 row vector;
schema rank is one and dimension identity is `row`. No estimate is recomputed.

Python/Octave `store_columns(document_id, prototype, columns)` accepts a dictionary
or struct mapping captured quantity IDs to explicit float64 vectors of equal
positive length. It returns the resource binding. Units come from the validated
CORE prototype. At most 128 columns and 512 MiB total are accepted. Lazy bridge
buffers stream directly in binary chunks of at most 1 MiB; numerical vectors do
not pass through Tcl lists or base64. Non-vector shapes and implicit dtype casts
reject. The Document must already exist in the active Session. This operation
owns storage only, and never creates a Dataset or reruns a numerical estimator.

`resourceBindingTable result start count` / `resource_binding_table` interprets
one bounded window: zero-based binding-relative start, one to 8192 rows, at most
one million fact elements and 1 MiB mapped binary values. Row IDs retain actual
resource offsets. Existing table/field accessors apply to the returned table;
unavailable facts carry no fabricated values. `validate`, `validated_result`,
`report` and `publication_metadata` accept the binding. Reports identify prototype
values as examples, never aggregate statistics. Read a bounded window for values.

`resourceBindingFieldElements result field start count` /
`resource_field_elements(result, field, start, count)` projects one registered
Numeric source field over the same bounded resource window. It returns `shape`
and row-major `cells` with actual physical `row_id`, value/status/reason and units,
using the identical CORE interpretation and per-row validation as the full table.
Unavailable cells have no `value`. The binding and catalog are validated at page
entry; the synchronous row loop uses that descriptor snapshot and constructs only
the requested quantity. This does not expose a partial statistical-result record
or let callers bypass validation. Public `interpret` still accepts one request.
Keep the original binding alongside the projection when publishing scientific
results. A constant fact is repeated over requested rows; consumers presenting
one shared scalar can explicitly project that fact from the binding's prototype.

The Tcl provider adapter `fromProviderColumns document operation context provenance
transported artifact_path` is advertised by `apiInfo.tcl_provider_adapter`.
Numeric and Signal captured calls invoke it inside the CORE runtime allocation
lifetime. `transported` is the bounded typed-worker receipt (`values.sample`,
`values.capture.fields/shapes/row_count`, `types`, `transport`); the artifact is
the real binary64 column-major file. CORE validates the registered model,
prototype, unique fact columns, original vector shapes and exact file size,
imports through the Document owner, and returns values/types/captured_statistics.
Ordinary callers use the provider captured calls; Script jobs use `store_columns`
and do not exchange runtime filesystem paths. Private interpretation helpers are
not public operations, and the anti-bypass gate rejects external calls to them.

Keep the returned binding in saved Document payload, history, a live-reference
list passed to resource collection, or published metadata. Existing CORE resource
collection/deletion retains these references, including retired owners; Session
relocation resolves them without embedded absolute paths. An unreferenced live
result is not automatically rooted by Script variable lifetime. Worksheet large
vector integration is a separate consumer boundary and must obey the same rules.

Public Numeric `signal_summary` has a parameterless descriptive profile,
`math.numeric.signal_summary`. Supply the actual `y_unit` to `from_numeric`;
the bounded raw result carries `n`, real/complex input kind and method.
CORE maps magnitude RMS, magnitude peak, real-component peak-to-peak range,
crest factor and split complex DC to registered quantities. Zero RMS remains
valid; all-zero crest is undefined. A sample count alone implies neither
independence nor a standard error. Scalar/compact-table projections, reports,
publication metadata and real Python/Octave jobs share the same definitions.

<a id="numeric-source-field-interpretation-additive-dev097-operations"></a>
## Numeric source-field interpretation

`numericModel operation ?facts?` / `numeric_model(operation, facts={})` resolves
the provider-declared default model through `numeric_operations` annotations in
Numeric's existing model manifest. It returns the registered descriptor, without
adding these annotations to persisted descriptor snapshots. Families needing an
explicit model raise `GXTXT STATISTICS NUMERIC_MODEL_REQUIRED`; consumers must
not guess an identity. The only optional selector is the actual Boolean
`has_intercept` fact for `linear_regression`. A false fact resolves the explicit
`math.numeric.linear_origin` descriptor with parameter `slope`; the existing
`math.numeric.linear` descriptor retains `intercept, slope` in that order.
Model lookup does not establish inference assumptions or value availability.

`numericFieldMap operation` / `numeric_field_map(operation)` returns the CORE
mapping from registered Numeric source fields to statistical quantities. The
mapping describes identities, not value availability. Unknown operations reject.

`numericFields result` / `numeric_fields(result)` first validates a captured
`from_numeric` result, then returns a dictionary keyed by those source fields.
Each entry retains the CORE `quantity`, `label`, `kind`, `status`, `reason`,
structured `unit` and optional `value`, with `unit_text` for scalar presentation.
Undefined/unavailable entries have no fabricated numeric value. Quantile vectors
retain probabilities; parameter vectors/matrices retain parameter identities and
their distinct units. No estimate is computed or repeated by these accessors.
Tables require explicit row selection; indexed ANOVA group summaries use their
group-summary API rather than whole-test source-field aliases.

Numeric's existing regression field `rmse` maps to its weighted, DOF-scaled
residual standard deviation. The separately interpreted RMS residual keeps its
own quantity. Descriptive comparison `r2` maps to `centered_comparison_score`;
parametric/projection contexts retain their geometric-dispersion meaning. Source
field names and scientific model identities are unchanged.

Python/Octave Jobs call both operations through the same versioned CORE API.
Consumers must retain the full captured result in publication metadata when
exporting its numeric fields. A field map by itself is not a validated result.

`numericFieldElements result field` / `numeric_field_elements(result, field)`
validates the captured result, then projects a mapped field into `shape` (row,
column counts) and row-major `cells`. Cells retain quantity, label, status,
reason, scalar display unit and optional value. Vector entries retain
`element_id`; quantiles also retain `probability`. Covariance entries retain
`row_id` and `column_id` and their product unit. Non-value states never invent a
numeric value. The original captured result must accompany publication; these
projections are presentation views. Shape is an ordered public list (a cell list
in Octave), and cells are ordered records. No numerical estimate is repeated.
For a captured statistical table, the same operation projects one scalar field
across its existing ordered rows, returning shape `row_count × 1` and retaining
each `row_id`. It validates the complete table and removes numeric placeholders
from non-value cells. Parameter vectors/matrices are never folded into table rows.

Qualified operation IDs `array_reduce.sum`, `.mean`, `.median`, `.minimum`,
`.maximum`, `.variance_population`, `.variance_sample`, `.std_population`,
`.std_sample`, `.rms` and `.quantile` adapt the existing reduction receipt through
`math.numeric.summary`. The action must match the operation ID. One scalar result
requires one group and its actual `n_input`/`n_valid`; the numerical zero from an
empty arithmetic sum does not establish an observed statistical sum. Use
`from_numeric_columns` with explicit row IDs for axis-indexed groups, carrying
`values`, `n_input` and `n_valid` as columns and the remaining receipt as common
facts. Requested axis and original shape are retained as provenance. No axis is
flattened implicitly. Unknown operations have Tcl error code
`GXTXT STATISTICS UNKNOWN_NUMERIC_OPERATION`; other CORE failures must propagate.

## Local unlabelled point-cloud estimates

Numeric `local_cloud_fit(x, y, query, options={})` retains the accepted nearest
neighbour estimator: `min(n, min(25, max(10, round(1.5*sqrt(n)))))` points,
deterministic distance/X/Y ordering, tricube weights with floor `1e-6`, local
quadratic fit when rank is three and design condition is below `1e6`, otherwise
a weighted constant. Queries must lie within the source X domain. Fewer than
four source points yield unavailable estimates. No tuning options are currently
accepted. A vector of queries is calculated in one Numeric call.

`math.numeric.local_cloud` captures query coordinate, location, neighbourhood
count, selected degree, candidate quadratic condition, effective weight count,
variance correction denominator and local dispersion. Use actual `x_unit` and
`y_unit`. For multiple queries, `from_numeric_columns` retains caller row IDs
and the query-coordinate column. Worksheet offers the same captured query table.

The variance denominator is the Kish effective count minus the fitted coefficient
count. It is a local heuristic, **not sampling degrees of freedom**. Nonpositive
denominators yield undefined dispersion; positive fractional denominators retain
their actual value. Neither is silently replaced by one. Unlabelled points
establish neither independent repeat
count nor standard error of a consensus mean, and this API supplies no confidence
interval. CORE defines these limits without recomputing the numerical estimate.

## Welch aggregation

Numeric `welch_aggregate(sum_psd, sum_amplitude, options)` accepts already
normalized one-sided periodogram sums, with positive `window_count` (integer),
`frequency_step_hz` and `enbw_sum_hz`. It returns averaged PSD/amplitude, ASD,
frequency and dB vectors plus bounded aggregate facts. The first bin is DC;
segment FFT normalization and one-sided doubling must already be applied.

`math.numeric.welch_spectrum` interprets these facts with actual signal `y_unit`.
CORE derives Hz, PSD, ASD and integrated-power units; an empty signal unit stays
unspecified. Integrated power uses all bins times the recorded width. Peak search
excludes DC; an all-zero non-DC spectrum has an undefined peak frequency. Zero
PSD has no finite dB level: the numerical column contains NaN, never a floor
claimed as measured data. The dB reference is one in the PSD unit.

The result captures the averaging, peak and zero policies and states that
window overlap does not imply independent observations or sampling DOF. Full
spectral vectors remain Numeric resources; interpretation/report/publication
uses only the bounded scalar receipt and never repeats FFT or aggregation.
Python and Octave Script Bridge Jobs share this public contract.

## Integrated spectral power levels

`math.numeric.power_level` interprets Numeric `power_level` results using the
actual `psd_unit`, or the actual `power_unit` when the supplied values are
already integrated band powers. The latter form records no inferred PSD
provenance. Source fields `power`, `root_power` and `level_db` map to
`integrated_power`, `band_rms` and `band_level_db`. CORE preserves the positive
`reference_rms` and the explicit zero policy; zero power has no finite logarithmic
level. Units derive from PSD integration over Hz or the supplied integrated-power
unit; square-root units stay symbolic when no squared-unit form is declared. Missing source units
stay explicitly unspecified. Conflicting caller unit claims reject.

The parameterless profile supports compact tables and public field/element
projection. RMS/level values are supplied once by Numeric; CORE does not recompute
them. Band numbers and integration definition belong in the caller's recorded
row identities and provenance. No sampling independence, confidence interval,
regression or instrument filter-bank compliance is inferred.

## Spectral distribution

The Numeric-owned `math.numeric.spectral_distribution` descriptor adapts
`spectral_features` through the same `from_numeric`, field, element, reporting,
validation and publication operations. Frequency descriptors use `x_unit`.
Amplitude bin weights have squared `y_unit`; power/PSD weights retain `y_unit`.
The source `total_power_equivalent` field maps to `spectral_weight_sum`, explicitly
a bin-weight sum, with no implicit PSD integration. Source field identities stay
unchanged. CORE retains estimator definitions, input semantics, DC handling and
the descriptive limits. Regression residuals and sampling/parameter inference are
not applicable. Zero total weight is rejected by Numeric.

Python and Octave interpretation forward only the registered scalar fields and
bounded estimator facts; full distribution arrays remain numerical transport
resources. Interpretation never reruns the spectral calculation. The scalar
report includes the relevant definitions and descriptive assumptions.

## Dataset-backed Numeric results

`dataset_statistics` (and the retained `statistics_dataset` spelling),
`dataset_weighted_statistics`, `dataset_polynomial_fit` and
`dataset_nonlinear_fit` use the corresponding Numeric adapters. The captured
result must include its real Dataset and Variable bindings and recorded units.
CORE derives physical context from these facts and rejects conflicting caller
units or source bindings. Provenance retains the actual operation spelling,
ordered `source_variables`, `selection_id` and a `dataset_binding` record with
Variable roles and units. Python/Octave expose these as typed records.
This records the Selection identity; it does not claim an immutable snapshot
of its historical bounds. A later Selection edit cannot be reconstructed from
its ID alone.

CORE interpretation reuses the completed numerical result. The canonical Script
Bridge Dataset summary, weighted and polynomial names are additive; the accepted
`statistics_dataset` entry remains available. Typed catalog/model calls and
Script Bridge Dataset nonlinear fits resolve named Selections through Numeric's
existing Session-aware resolver. Direct Octave calls retain their public
`options.selection` structure contract. Supplying both a Selection ID and an
explicit structure is rejected by the named-Selection adapters.

## Scalar presentation rows

`scalar_rows(result, mapping)` (Tcl `::GX::StatisticsV1::scalarRows`) validates
a scalar result and projects selected scalar quantities into ordered records.
The mapping is an ordered alias-to-canonical-quantity dictionary; aliases must
be identifiers. Each row retains CORE `status`, `reason`, `label`, `unit`, `kind`
and optional estimator definition, plus `id`, `quantity`, `value` and `unit_text`.
Non-value states use a typed NaN placeholder. `unit_text` is a display expression
for structured powers (for example `V^2`); the structured scientific unit remains
unchanged. Vector/matrix quantities cannot be flattened through this operation.
It estimates nothing and does not invent input/bookkeeping counts.

Summary statistics record their existing Numeric quartile definition. Relative
weights may declare `context.weight_unit` (default `1`), used for weight sums and
value*weight sums. This does not turn relative weights into absolute measurement
uncertainty. Inverse-variance units still derive from the response unit. MAD
scaling accepts only `raw` or `normal_consistency`, including validation of
persisted records.

`parameter_ini_report(result)` (Tcl `parameterIniReport`) is the corresponding
validated serializer for parameter vectors. It retains legacy semicolon-separated
`coefficients` and `standard_errors` fields and adds ordered `parameter_ids`,
`parameter_units`, coefficient space, aggregate uncertainty state/reason and
per-parameter states/reasons. Identity/unit/state lists use Tcl list notation;
backslashes and line breaks are escaped for the INI scalar field. Fixed parameters
have no estimated SE, and non-value entries retain NaN placeholders. This operation
preserves identity instead of passing a parameter vector through scalar aliases.

## Compact statistical tables

The same public API also owns schema `gxtxt.statistical_result.table.v1` for
parameterless scalar summary, hypothesis, ANOVA and resampling results. It
shares a model, context, provenance and quantity definitions across 1–8192
uniquely identified rows. Rows retain their numerical facts and each quantity's
status, reason and unit. At most one million input facts are accepted. Mixed
models, contexts, vector/matrix quantities or parameter identities require
separate records; the API never silently flattens them.

`from_numeric_table(model_id, operation, rows, context, provenance={})` takes
rows of `{id, raw}` public Numeric results. For large groups prefer
`from_numeric_columns(model_id, operation, row_ids, raw_columns, common_raw,
context, provenance={})`: each numerical field is a typed column with one
value per row, while common raw fields are supplied once. Column and common
field names must not overlap. These adapt existing computations; they do not
calculate another mean, uncertainty or test.

`interpret_table(request)` interprets canonical facts. `validate(table)`
rebuilds interpretation and checks the complete record, including identities,
states and displayed values. A caller can select numerical columns through
`table_values(table, quantities)`; non-value rows return NaN and require the
accompanying full metadata to explain their status. `table_select(table, row_ids)` returns a validated subset in the requested
unique identity order and preserves original provenance. `table_report(table,
row_ids, quantities)` produces validated text. An empty row selection in the
report means all rows; quantity IDs are selected explicitly. `publication_metadata` and the normal
Dataset metadata/publication guards accept scalar and table records together.
They retain legitimate unbounded hypothesis endpoints as signed infinity with
`endpoint=unbounded`; undefined results never acquire valid numerical values.

Python and Octave expose these operations through the existing Script Bridge.
Tcl names are `fromNumericTable`, `fromNumericColumns`, `interpretTable`,
`tableValues` and `tableReport` in `::GX::StatisticsV1`. Large numeric columns
use the common managed binary transport. Standalone Octave callers can hold
`lifetime=gxtxt_statistics_scope_v1()` for multiple calls; it borrows an active
Job Bridge and otherwise owns cleanup of its private stateless CORE service.

## Parameter correlation and confidence intervals

`parameter_inference_plan(result, confidence=0.95)` returns a versioned,
bounded plan (`STATISTICAL_PARAMETER_INFERENCE_PLAN_v1`). Tcl spelling:
`parameterInferencePlan`. The plan selects **free** parameters by their recorded
identities and physical covariance; fixed values are excluded. It never refits
or computes an estimate. Unknown/active constraints, rank deficiency, failed
nonlinear convergence, robust loss and degenerate zero variances retain explicit
statuses and reasons. The plan is bounded to 256 free parameters.

Pass an eligible plan to `NUMERIC_API_v1/parameter_uncertainty(plan)` (Octave:
`gxtxt_numeric_v1('parameter_uncertainty', plan)`; Tcl:
`::GX::NumericAPIv1::parameterUncertainty $plan`). Numeric normalizes the existing
covariance to parameter correlation and, when eligible, calculates marginal
intervals. It returns a receipt identifying the public operation and original
plan. `with_parameter_uncertainty(result, confidence, numeric_receipt?)` / Tcl
`withParameterUncertainty` attaches the interpreted receipt. Omitting the receipt
records eligibility or the reason calculation is unavailable; it cannot fabricate
intervals. Interpretation/publication validation rechecks the source plan,
identities, units, method, dimensions and status on each use.

Correlation needs identifiable positive parameter variances but no Gaussian
assumption. Confidence intervals additionally require explicit matching noise:

| Noise assumption | Covariance and weights | Distribution |
| --- | --- | --- |
| `independent_gaussian_known_sigma` | Absolute measurement covariance, inverse-variance weights | Normal |
| `independent_gaussian_estimated_variance` | Residual-estimated covariance, unweighted or relative weights | Student t, recorded residual DOF |
| Unspecified or inconsistent | Any | Interval unavailable |

These are pointwise marginal intervals, not simultaneous coverage guarantees.
Nonlinear and parametric regression intervals are labelled `local_linearization`;
linear regression uses `linear_model`. Bound/profile, bootstrap and posterior
intervals require their own validated methods and must not inherit these labels.
The full receipt is retained in `result.request.parameter_uncertainty`, and the
interpreted `result.parameter_uncertainty` survives ordinary metadata publication
and Script Bridge round trips. Existing results without this additive field remain
valid and do not acquire a confidence claim.

Source covariance/parameter comparisons allow only four binary64 relative epsilons
for the existing bounded Tcl-to-Octave JSON adapter (one-ULP decimal decode drift
was observed). Counts, confidence, identities and interpretation settings must
match exactly. This tolerance concerns metadata transport, not fitting accuracy.

`parameter_rows(result)` / Tcl `parameterRows` supplies named values, units,
roles, SE and CI statuses/reasons and available bounds for GUI or report tables.
Fixed parameters explicitly have no estimated SE/CI. `parameter_correlation_report`
/ Tcl `parameterCorrelationReport` formats the validated free-parameter matrix.
`parameter_report` includes available intervals and their method/approximation.
All these operations are discoverable and available in real Python/Octave Jobs
and the stateless Octave facade.

## Descriptive and weighted summaries

`from_numeric` adapts public Numeric `statistics`, `weighted_statistics`,
`quantiles` and `weighted_quantiles`. The summary profile preserves estimator
identity, observation count, physical units, probability order and explicit
quantile definition. Sampling SEM requires `sampling_model=independent_observations`
and `mean_se_model=sampling`; known measurement SEM additionally requires
absolute inverse-variance weights. Relative weights do not imply known sigma.
Weighted sample variance uses the reliability-weight correction, and effective
count is Kish effective sample size. Neither SEM implies a confidence interval.
Zero observations are undefined; sample variance/SEM need more than one effective
observation. Negative/nonfinite estimates cannot become valid quantities.

## Hypothesis tests

The registered `math.numeric.hypothesis` profile adapts Numeric `hypothesis_test`
results for one-sample, paired, equal-variance and Welch t methods, Mann–Whitney
and signed-rank methods. CORE preserves first/second sample counts, estimator
identity, alternative, confidence, probability method and conditional sampling
assumptions. A p-value is a probability under the specified null model, not the
probability that the null hypothesis is true. Welch inference is approximate.
Rank statistics and effects are dimensionless; mean/difference estimates and
intervals retain source units. Rank methods do not acquire t degrees of freedom
or a mean confidence interval.

Positive, reported Numeric standard error and test degrees of freedom are
required for t inference. Zero-variance samples preserve their mean/difference
while p-values and intervals become explicitly undefined. One-sided intervals
retain the mathematically unbounded endpoint (`-Inf` for the lower endpoint of
`less`, `Inf` for the upper endpoint of `greater`) with `endpoint=unbounded`.
Only these method-specific endpoints may be valid nonfinite quantities. Reversed
intervals, incorrect unbounded sides, invalid probability ranges and tampered
assumptions cannot become valid CORE output. Numeric evaluates small t/normal
tails directly to avoid subtraction cancellation.

See [NIST confidence interval conventions](https://itl.nist.gov/div898/handbook/prc/section2/prc221.htm)
and the independent [SciPy t-test reference](https://docs.scipy.org/doc/scipy/reference/generated/scipy.stats.ttest_1samp.html).
The targeted fixture records exact inputs, reference-library version and tolerances.

## ANOVA and group identities

`from_numeric('math.numeric.anova', 'one_way_anova', raw, context)` interprets
ordinary or Welch ANOVA. The `math.numeric.summary` profile with the same
operation and explicit `context.group_index` selects the existing group count,
mean and sample spread; the exact group label is retained as provenance. No
statistics are recomputed. ANOVA quantities identify between/within/total sums
of squares, mean squares, numerator/denominator F degrees of freedom and effects.
Squared quantities retain squared source units.

Ordinary inference assumes independent Gaussian observations with equal
population variances; Welch inference uses approximate F degrees of freedom.
Welch does not receive classical eta/omega effect claims. Negative omega
estimates remain valid unconstrained estimates. Degenerate within-group
variance makes F inference undefined. Small F probabilities use Numeric's
direct beta survival calculation, avoiding subtraction cancellation. See
[R's documented method](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/oneway.test.html).

## Resampling results

The `math.numeric.resampling` profile adapts public Numeric `resampling_summary`.
It preserves source counts, replicate count, observed statistic, empirical
percentile endpoints or corrected permutation probability and extreme count.
Bootstrap uncertainty requires a nondegenerate generated distribution and known
source counts. Its intervals are explicitly two-sided empirical approximations,
not exact coverage guarantees. Permutation alternatives require independent
label exchangeability or paired sign exchangeability as recorded in CORE
assumptions; finite Monte Carlo plus-one probabilities cannot be zero.
Unsupported quantities have explicit not-applicable states. Numeric alone
counts extremes, calculates endpoints and evaluates probabilities.

## Scoped Octave consumer lifetime

`lifetime = gxtxt_statistics_scope_v1()` holds the existing stateless CORE
service for a caller-owned Octave scope. Repeated facade calls reuse one process;
clearing the lifetime or leaving the function closes only the bridge it created.
Nested scopes and real Script Jobs borrow an existing bridge without owning it.
A stopped/replaced bridge is protected by both process identity and its unique
buffer scope. No second statistics engine, Session, Job or publication capability
is introduced. Single facade calls retain automatic start/cleanup behavior.

## Calls and discovery

`ini_report(result, mapping)` / Tcl `iniReport RESULT MAPPING` serializes scalar
quantities for existing machine-readable summaries. Mapping keys are preserved
output identifiers and values are registered quantity IDs. Each legacy numeric
field is followed by `.statistical_status`, `.statistical_quantity`, label,
reason and unit fields. Non-values use NaN with their explicit status; escaped
line breaks cannot inject another INI entry. This supports stable historical
field names while their interpretation remains at the public CORE boundary.
Matrices/vectors require the structured result or parameter APIs.

`feature(result, quantity)` adapts a validated scalar quantity to the existing
Scientific Analysis feature contract: value/status/reason/unit plus the
original interpretation status. A CORE value becomes `valid`, an error becomes
`failed`, and other states become `unavailable` with NaN and the CORE reason.
It never recomputes the statistic.

The public Octave `gxtxt_statistics_v1` facade also works outside Script Jobs.
When no bridge is active it opens the existing unified bridge in its restricted
`stateless_core_service` profile, exposing only this registered API and closing
it after the call. No scientific Session, callback or numerical worker is created.
Active module/Script executions retain their existing bridge. The Tcl API remains
in-process and requires no GUI. Model identities/units, fixed masks, free-parameter
count, active bounds, loss and response count survive the bounded Octave facade.

The declared Numeric nonlinear model adapter preserves `model.parameter_ids`
and optional `model.parameter_units`. Its `free_parameter_count` must match
parameter roles and cannot exceed total parameters. Fixed-parameter covariance
is conditional on those fixed values; fixed rows are not estimated uncertainty.
Active bounds and robust losses remain explicitly unavailable for ordinary
Wald inference. These facts come from the returned Numeric record, and cannot
be overridden by a caller setting `constraints=none`.

`orientation=joint_responses` requires nonlinear fitting with explicitly
normalized inverse-variance residual components. It has dimensionless weighted
residuals, while pooled physical RMSE, R squared and physical residual standard
deviation are not applicable. Per-response plots retain their own physical units.

Tcl callers use `::GX::StatisticsV1::apiInfo`, `models`, `model ID`,
`quantities`, `interpret REQUEST`, `validate RESULT`, `report RESULT ?IDS?`,
`parameterReport RESULT`, `feature RESULT QUANTITY`, `scalarValue RESULT QUANTITY` (numeric-table
compatibility), `publicationMetadata NAMED_RESULTS`, and
`fromNumeric MODEL_ID OPERATION NUMERIC_RESULT CONTEXT ?METRICS? ?PROVENANCE?`.
The entrypoint is loaded by the ordinary framework bootstrap without Tk.

Validation preserves early `gxtxt.statistical_result.v1` records whose quantity
catalog predates the complete additive group `smoothing_lambda`,
`smoothing_gcv_score`, `residual_mean_dof`, `residual_variance_dof`, and
`smoother_trace_squared`. Omission is compatible only for that exact whole group,
when every quantity is inapplicable to the captured request and none is a
captured numerical fact. The record is not rewritten. Partial omissions,
missing applicable facts, changed labels/statuses/values and extra quantities
still fail validation. This preserves unrelated saved results without weakening
the authority of CORE statistical interpretation.

Python and Octave use the existing unified
`gxtxt_api_call('STATISTICAL_RESULT_SEMANTICS_API_v1', operation, arguments)`.
The complete registered operation inventory is in [Public operation index](#public-operation-index). Argument order follows each operation’s listed inputs and its detailed contract below. Optional arguments may only be omitted from the right.
Ordinary Script Bridge API discovery exposes argument and result descriptors.
The binding transports calls to the same CORE functions and contains no second
applicability table. Returned vectors/matrices use the existing typed bridge.

Standard Octave module runners start/stop the existing public Script Bridge once
per execution and use `gxtxt_statistics_v1(OPERATION,...)`. This thin CORE facade
removes large prediction/residual/Jacobian arrays from numerical facts before
transport. `gxtxt_statistics_values_v1(RESULT)` validates once and supplies numeric
table values, representing non-values by NaN; the full status and reason must
remain in the accompanying result metadata. It contains no model policy.
`gxtxt_publication_v2_open` accepts `options.statistical_results` (named records),
validates them through the shared authority and includes them in the canonical
publication transaction. `publication_metadata` returns the opaque Tcl metadata
representation for this existing publication transport; consumers do not parse
or reinterpret it. Python/Octave Script Jobs can alternatively supply the same
records in `structured_metadata['analysis.statistical_results']`.

The public Numeric bridge also exposes `linear_regression(X,Y,weights?,options?)`,
`polynomial_fit(X,Y,degree,weights?,options?)`, and
`residual_metrics(observed,predicted,options?)`. These invoke the existing
Numeric implementations. A weights placeholder is required when passing fit
options without weights.

## Provider registration

Modules declare `[statistical_models] api_version=1` and semicolon-separated
local `ids`. Each `[statistical_model.ID]` supplies `label`, `profile`,
`parameter_convention`, optional `parameter_ids` and `description`.
CORE registers each as `MODULE_ID.ID`. `registerModel OWNER ID DESCRIPTOR`
is the equivalent host registration call. Owner existence, qualified identity,
profile and parameter-order uniqueness are checked. A different definition
cannot replace an already registered identity. Registration is transactional;
disabled providers are unavailable. Ordinary scripts may inspect and use
descriptors, but cannot overwrite installation-wide scientific policy.

Profiles: `regression`, `nonlinear_regression`, `interpolation`, `smoother`,
`projection`, `parametric_regression`, `summary`, `solver`.
Parameter conventions: `named`, `descending_power`, `basis_controls`,
`model_state`, `none`. Named parameter order must exactly match the descriptor.
Extensions register scientific descriptors at this owner; private model-to-
statistics tables are prohibited. New interpretation policies require a versioned
extension of this authority and focused tests.

Statistical consumers declare `[statistical_results] api_version=1`,
`semantics_api=STATISTICAL_RESULT_SEMANTICS_API_v1`, `boundary=RELATIVE_FILE`,
and `publication_validation=COMMAND`. A declaration does not establish that the
consumer uses the API: the architecture gate also inspects source and runtime
publication tests remain mandatory.

## Result and request contract

`interpret` accepts `model_id`, `context`, `numerical`, `provenance`, and optional
`parameters`. Unrecognized fields are rejected. Numerical facts are outputs of
Numeric, not handwritten module calculations. Provenance requires
`numeric_api=NUMERIC_API_v1`, `operation`, and `producer`; additional captured
source identity and checksums may be retained without alteration.

Parameters are ordered records with `id`, `unit`, `role` (`free`, `fixed`,
`derived`, `state`), optional `label` and finite `value`. Covariance rows/columns
and standard-error entries follow this exact order. Shape/order disagreement is
an error. Parameter values and uncertainty remain in their declared coefficient
space; this API never silently transforms coefficients or scientific identities.

Context fields:

| Field | Contract |
|---|---|
| orientation | y_of_x, x_of_y, r_of_theta, parametric |
| x_unit, y_unit, radial_unit | Explicit physical unit symbols; blank means unspecified |
| x_variable_id, y_variable_id | Stable source variable identities |
| coefficient_space | original_physical, translated_fit, normalized_basis |
| translation | Captured reversible mapping provenance, not evaluated by the interpreter |
| weight_semantics | unweighted, relative, inverse_variance |
| noise_model | Declared measurement assumptions; reduced chi square requires independent_gaussian_known_sigma |
| constraints | none, inactive_bounds, active_bounds, equality, unknown |
| covariance_scaling | Explicit Numeric variance-scaling convention |
| has_intercept | Boolean numerical model fact |
| smoother_dof_convention | Validated Numeric residual-variance convention; EDF alone is insufficient |
| zero_normal_sign_policy | Projection provider's documented policy |
| sample_role | training or evaluation |
| solver, method, assumptions | Captured solver identity and conditional assumptions |

Every quantity has `status`, `label`, `unit`, `kind`, `reason`; only `value`
status has a `value` field. States are `value`, `not_applicable`, `unavailable`,
`undefined`, `error`. Invalid requests raise `GXTXT STATISTICS CONTRACT` rather
than returning a fabricated successful result. Nonfinite estimates have no valid
numeric value. Missing facts are unavailable, not proof of absent functionality.

The result includes registered model identity, physical residual convention,
parameters, quantity records, solver diagnostics, assumptions/provenance, and
the original request. `validate` repeats interpretation of that request and
rejects altered labels, values, eligibility or added fields. `report` and
`parameterReport` validate before presentation. This protects the interpretation
boundary; it does not prove an untrusted producer performed the claimed numerical
calculation. Numerical and source-integrity tests establish that separate fact.

`from_numeric` adapts public Numeric contracts centrally. Least-squares Numeric
`rmse` is the residual standard deviation using residual DOF; it is not relabeled
as the descriptive root mean square over observations. Pass separately computed
public `residual_metrics` fields (`n`, `rmse`, `r_squared` from `r2`,
`response_variance`) when that descriptive report is required. Raw solver arrays
are not copied into statistical metadata. `residual_metrics` now returns its
already computed observed-response dispersion as `response_variance`.

The `math.numeric.comparison` profile exposes `centered_comparison_score` from
Numeric's existing `r2` fact: `1 - prediction SSE / centered reference SST`.
This descriptive prediction score does not assert a fitted regression, independent
validation or a goodness-of-fit test. It is undefined with fewer than two aligned
observations or zero/nonfinite reference dispersion. The separate `r_squared`
regression quantity remains not applicable to this profile.

Comparison quantities `max_relative_error`, `rms_relative_error` and `relative_n`
retain Numeric's relative denominator policy: nonzero reference values whose
absolute magnitude is at least `relative_floor`. Both floor and eligible count
are captured as numerical facts. No eligible denominator gives undefined relative
errors, with count zero; missing facts give unavailable quantities. These are
dimensionless fractions, not percentages. CORE performs no recomputation.

## Scientific interpretation

Functional residuals use observed minus predicted at the original source
independent coordinate. `x_of_y` changes both the dependent axis and its units.
Radial residuals use physical radius at the original source angle. Projection
residuals require commensurate coordinates in the same declared unit; their XY
dispersion score is identified separately from functional-response R squared.
Translation provenance is preserved: physical residual space and
translated coefficient space are different explicit fields.

Constant-response centered R squared is undefined, including a raw solver value
of one. R squared is descriptive and is not a goodness-of-fit test. Interpolation
does not establish regression inference. Smoothers require explicit EDF and a
residual variance DOF convention; knot count must not substitute for EDF.

Rank deficiency, nonpositive residual DOF, unreported/nonconverged nonlinear
solutions, and active/unclassified constraints prevent ordinary parameter
uncertainty from being represented as valid. Local nonlinear covariance is an
approximation conditional on the model; numerical pseudoinversion alone does not
establish identifiability. See the [NIST nonlinear regression glossary](https://www.itl.nist.gov/div898/strd/nls/data/LINKS/c-nelson.shtml)
and [SciPy covariance conventions](https://docs.scipy.org/doc/scipy/reference/generated/scipy.optimize.curve_fit.html).

Relative weights or residual scaling do not establish known measurement sigma.
Reduced chi square is eligible only for the explicitly declared absolute-noise
model with positive supported residual DOF. Unavailable uncertainty is never
replaced by zero. Evaluation residuals do not recompute training-parameter
inference. The [NIST least-squares reference](https://www.itl.nist.gov/div898/handbook/pmd/section4/pmd431.htm)
documents the distinction between the residual sum of squares and the residual
standard deviation based on residual DOF.

`rmse` uses the descriptive observation-count denominator. The separately named
`residual_standard_deviation` uses Numeric's unweighted residual DOF denominator
and physical response units. `weighted_residual_standard_deviation` represents
the weighted DOF-scaled quantity; inverse-variance weighting makes it
dimensionless. These meanings remain distinct even when values happen to agree.

For weighted regression and nonlinear regression, the public
`quantities.r_squared.definition` describes the criterion as one minus weighted
residual sum of squares divided by weighted response variation about its
weighted mean. It is descriptive, not evidence of physical model validity.
The canonical quantity ID and value remain those of the original Numeric fit;
the interpretation layer does not recompute a second statistic. This definition
is part of the shared versioned result, available to GUI and Script consumers.

## Fitter integration and persistence

Declared-model solver receipts may carry optional `orthogonal_xy` schema
`gxtxt.numeric_orthogonal_xy_receipt.v1`. Numeric `fit_geometry=orthogonal_xy`
adapts through the existing `nonlinear_fit`/`dataset_nonlinear_fit` operations.
CORE validates independent absolute axis-sigma semantics, one nuisance predictor
per observation pair, two residual components per pair, N-minus-rank DOF, the
projected tangent convention and the backend's QR/Schur choice. Ordinary response
R² and physical response residual scores are not applicable to this objective.
Parameter covariance is the unscaled local Gauss-Newton approximation after
latent-coordinate elimination; Gaussian intervals require explicitly known
absolute sigma and remain local for line models. All bounded contracts persist
and revalidate through Python, Octave and Dataset metadata.

`numeric_data_fields` describes returned latent predictors, responses at those
predictors, signed N×2 coordinate corrections, standardized corrections, unsigned
normalized distances and retained source-row identities. Matrix descriptors add
`column_ids` and `column_units`; no numerical arrays are copied into semantic
metadata. The fitted coordinate basis remains distinct from ordinary evaluation
at observed predictors. Prediction plans explicitly condition on a fixed true
query coordinate and preserve the physical response unit. They do not claim
coverage for uncertainty in a future measured query coordinate.

Declared-model solver receipts may carry optional `multistart` schema
`gxtxt.numeric_multistart_receipt.v1`. CORE validates the bounded 2–64 trial
records, exact initial/selected parameters, common solver policy, fixed values,
counts, uniform ranges, generator identity, actual convergence and lowest-objective
selection with first-index exact-tie order. Nested trial receipts cannot themselves
contain multistart. Missing this optional field retains historical single-start
meaning. The public `solver_report` explains attempted and converged counts,
failed/unrun trials, replay policy and the absence of a global-optimum guarantee.
Both Script bindings preserve the same typed trial records; interpretation does
not rerun fitting or generate another random sequence.

New Fitter results carry `statistical_results.training` and `.evaluation` through
Preview, accepted provenance, CSV metadata and canonical Dataset metadata.
Numerical covariance retains Numeric's `[intercept,slope]` order even though the
legacy linear formula fields use `[slope,intercept]`. GUI parameter/statistical
reports use the shared API. Legacy raw scalar fields remain for public v1
compatibility; they are not an independent interpretation authority.

Historical Sessions without this additive record retain their original geometry
and provenance. The report explicitly identifies their missing versioned
interpretation and asks for a new fit to obtain it. Historical data are never
silently certified or recomputed.

## Architecture enforcement

Validation preserves complete known earlier v1 quantity catalogues when every
later addition is inapplicable to the captured request. Existing values,
definitions, applicability, solver receipts and inference must still match CORE
interpretation exactly. Arbitrary missing fields or missing applicable facts are
rejected. Validation does not rewrite the saved result or invent new facts.

`python3 tools/check_statistical_semantics.py FRAMEWORK --output REPORT.json`
returns nonzero for detected bypasses and unresolved dynamic/parse findings.
Python uses AST analysis; Tcl uses the installed interpreter's public command
parser without evaluating inspected code; Octave and C++ use language-aware
tokenization and balanced structural analysis. Reports include file, line, operation, violated
authority, actionable reason and coverage limits. This is not a claim to defeat
arbitrary obfuscation. Runtime publication validation and real registered Script
Jobs cover boundaries that source inspection cannot establish.

An exception registry entry in
`docs/architecture/STATISTICAL_SEMANTICS_EXCEPTIONS.json` must specify exact file,
line, rule, owner, scientific justification, test path and source SHA256. Changes
invalidate the exception. Exceptions are narrowly reviewed domain boundaries,
not blanket allowances for modules to compute their own statistical meaning.

The default production scan includes CORE, app, plugins, Session Generators,
the accepted generator libraries and expanded independent generator packages.
Archive/expanded byte parity is checked separately before packaging. The two
current exceptions cover copies of the same fixed five-measurement teaching
oracle: it writes test-only ground truth, which production analysis never reads.
Both exceptions bind one assignment, exact source SHA and the dedicated
`generator_statistics_boundary.py` test. Additional source bypasses still fail.

`from_numeric` also adapts Numeric `mad`: median, raw median absolute deviation
and scaled median absolute deviation retain physical units and `mad_scale`
(`raw` or `normal_consistency`). This is descriptive dispersion, not a standard
error or confidence interval. A zero MAD is a valid dispersion fact and does
not justify division by zero in a downstream score.


## Pointwise numerical comparison

`math.numeric.comparison` is a Numeric-owned descriptor for already-computed
`residual_metrics` on aligned predictions/reference values. Its CORE profile
`comparison` interprets n-denominator RMSE, MAE, maximum absolute error and SSE
with physical response units and explicit observation counts. These descriptive
errors establish no regression, R², degrees of freedom, parameter uncertainty
or sampling-inference model; those quantities are `not_applicable`. An empty
subset (`n=0`, no estimates supplied) is `undefined`, not a zero error. Provenance
identifies the compared method/reference and subset; no alternate estimator is
computed by interpretation. All existing scientific model IDs remain unchanged.

### Measurement uncertainty propagation

`math.numeric.propagation` interprets `NUMERIC_API_v1/propagate_uncertainty`
without repeating the Jacobian/covariance calculation. It requires context
`output_ids` (one to 256 unique identifiers) and matching explicit `output_units`.
The Numeric receipt supplies `input_kind`, `input_count`, `output_count` and
`method=first_order_linear_propagation`; sample arrays and the Jacobian are not
copied into statistical metadata. `output_covariance` preserves both unit axes;
`output_standard_uncertainties` retains ordered output identities. Optional
one-based `output_index` exposes the identified scalar `standard_uncertainty`.
These are output uncertainties, not fitted-parameter standard errors.

Input standard uncertainties imply independent measurements. Input covariance
retains the supplied correlation model. First-order propagation is exact for an
affine transformation with the supplied covariance; a general nonlinear result
is a local approximation. Zero supplied uncertainty is a valid known value.
Neither confidence coverage nor sampling degrees of freedom follow automatically.
The scalar/vector receipt comparison uses the existing four-relative-epsilon
transport bound; scientific estimates are never recalculated by CORE.

For weighted summaries, `measurement_standard_error_mean` reuses Numeric's
absolute inverse-variance result under explicit independent observations. Numeric
also exposes its existing weighted sum-of-squares reduction as reduced chi-squared
using n-positive minus one DOF; CORE displays it only with
`noise_model=independent_gaussian_known_sigma`. Unspecified noise yields
`unavailable`; a singleton yields `undefined`. Relative weights yield
`not_applicable`. No auxiliary least-squares fit is needed.

### PCA spectral summaries

Numeric `pca_summary(singular_values, observation_count, options)` consumes the
existing descending SVD magnitudes without recomputing an SVD. Pass its five
ordered fact columns (`singular_value`, `component_variance`, `explained_ratio`,
`cumulative_ratio`, `component_index`) plus common `n`, `component_count`,
`total_component_variance` and `method` to `from_numeric_columns` using
`math.numeric.pca`, stable component row IDs and the analyzed `y_unit`.

Centered results describe sample covariance eigenvalues. With `centered=false`,
CORE labels the retained historical denominator explicitly: uncentered squared
component magnitude divided by n minus one. Ratios are descriptive spectral
proportions; they imply neither sampling inference nor causal explanation. A
zero spectrum has valid zero component moments but undefined proportions.
Equivalent component signs and bases within degenerate subspaces remain possible.

`from_numeric('math.numeric.solver','matrix_svd',raw,context)` adapts existing
rank, condition and dimension facts without serializing U or V. A nonfinite
condition number remains undefined with its reason. No covariance estimate or
confidence interval is fabricated for a decomposition.

<a id="bounded-solver-diagnostics-integrated-dev097"></a>
### Bounded solver diagnostics

`fromNumeric` / `from_numeric` accepts the additive Numeric-owned
`solver_receipt` (`gxtxt.numeric_solver_receipt.v1`). The public result's solver
record validates convergence against termination, backend identity, effective
tolerances/limits, strategy/loss, physical parameter scales, initial values,
bounds and fixed roles. The receipt contains bounded optimization facts, not
observation arrays or another covariance/fit computation. Infinite bounds remain
typed nonfinite numbers. Historical results without a receipt remain valid and
explicitly lack detailed stopping evidence.

Tcl `solverReport result ?details?` and Python/Octave operation
`solver_report(result, details=False)` share the same validated interpretation.
Normal presentation states the stopping meaning and iteration-record count;
`details=True` adds the backend message and exact settings. Ceres iteration
records include the initial state, so they are not relabelled optimization
steps. A converged status establishes backend stopping criteria only, not a
global optimum, correct physical model or validated uncertainty assumptions.
Modified interpreted diagnostics fail `validate`, including on publication.

### Script callback solver receipts

`fromNumeric` also accepts `gxtxt.callback_solver_receipt.v1` for the existing
SciPy callback backend. CORE validates backend/version, requested solver,
`trf`/`dogbox` strategy, effective positive tolerances, bounded function-evaluation
budget, physical parameter scales/bounds, fixed roles, objective and stopping
code. No covariance or optimization is recomputed by this interpretation.
The receipt's `condition_convention=unit_norm_free_jacobian_columns` distinguishes
scale-normalized diagnostics from the physical returned covariance.
`scale_convention=physical_parameter_equals_scaled_parameter_times_scale`
records the optimizer-coordinate mapping, including its bounds and stopping tests.

`solver_report` explains the actual stopping criterion. SciPy function evaluation
counts are not optimizer iterations: `iterations=-1` is explicitly unavailable,
and `callback_evaluations` includes numerical Jacobian and final-prediction calls.
All-fixed requests instead require one callback evaluation, zero optimization
iterations and `method=fixed_evaluation`. Inconsistent settings/roles/counts or
modified interpreted receipts fail `validate` and publication. Both Script
languages return typed numeric settings and vectors through the shared binding.

### Comparison tables and residual direction

Parameterless `math.numeric.comparison` results support the existing compact
`from_numeric_table` / `from_numeric_columns` contracts. `table_rows(result,
mapping, row_ids=[])` (Tcl `tableRows`) validates the complete table and returns
ordered `{row_id, cells}` records. Each mapped alias retains its canonical
quantity, label, status, reason, units and value; a non-value is NaN. Omitted
row IDs select all rows. Unknown/duplicate row IDs, invalid aliases, non-scalar
quantities and modified results are rejected. The persisted table remains
mandatory alongside numeric CSV or Dataset exports. For example, a historical
`r2` column can identify `centered_comparison_score` explicitly without claiming
fitted-regression inference.

Functional regression, smoothing, interpolation and comparison contexts may
set `residual_sign` to `observed_minus_predicted` or `predicted_minus_observed`
for `y_of_x` / `x_of_y`. It describes the actual producer convention and does
not change numerical values. Omission preserves the previous defaults: fitted
responses use observed minus predicted, comparisons predicted minus reference.
CORE rejects this field for geometric and non-residual profiles.

<a id="native-comparison-reductions-dev097"></a>
### Native comparison reductions

Numeric registers `math.numeric.geometric_deviation` with the descriptive
`geometric_comparison` profile. `fromNumeric MODEL residual_summary RAW CONTEXT`
adapts the public C binding's existing `count`, `rmse`, `mean_absolute` and
`max_absolute` facts; it does not reduce residuals or infer a variance, DOF,
R-squared or parameter covariance. A bidirectional nearest-curve receipt may
also supply `hausdorff_sampled`, mapped to `sampled_hausdorff_distance`.

`fromNativeComparison METHOD RECEIPT CONTEXT PROVENANCE` (Script operation
`from_native_comparison`) provides the shared Native2D adaptation. `METHOD` is
`x`, `path` or `geometry`; context contains `x_unit`, `y_unit` and optional stable
`x_variable_id`/`y_variable_id`. Empty units explicitly mean undeclared. The
result is a dictionary of full versioned statistical records: `reference`, plus
`bidirectional` for `geometry`. It reads only bounded summary facts. Python
callers should omit `rows` and `statistics` when adapting an existing receipt;
the Octave `gxtxt_statistics_v1` facade does this automatically.

- `x`: reference Y minus target Y interpolated at reference X. The native kernel
  requires monotonic X and rejects folded curves. Unlike X/Y dimensions are
  legitimate. Missing coordinate units make physical error quantities unavailable.
- `path`: Euclidean distance between points at equal normalized path positions,
  signed by the target tangent side. A zero cross product gives nonnegative
  distance. This is not a nearest-point or normal-projection residual.
- `geometry`: unsigned nearest-curve distances at the recorded scientific sample
  locations. `reference` describes reference-to-target samples; `bidirectional`
  describes the native pooled reduction and sampled Hausdorff maximum. Neither
  establishes the continuous-curve Hausdorff distance. Both physical axes must
  have the same declared unit for interpretable distance quantities.

Scientific sample counts, native projection/sampling policies and display-row
counts stay in provenance. X/path statistics use all eligible evaluated native
reference vertices, independent of the display LOD budget. Workbench spline
comparisons additionally identify their evaluated representation. The geometry
budget selects scientific samples explicitly; viewport zoom does not select them.

`validatedResult RESULT` / `validated_result` validates a complete scalar or table
record and returns its typed public representation. Native Script bindings reuse
this registered operation for embedded results; no consumer-specific statistical
parser or reinterpretation is introduced. Altered labels, units, values, signs or
sampling context fail the existing consistency validation.

`from_native_comparison` additionally accepts `surface` for the Native3D kernel's
Numeric reductions. Context requires `x_unit`, `y_unit`, `z_unit` in one physical
unit. Its metric is `nearest_surface_distance`: unsigned distance to the complete
target triangle surface. B-Rep tessellation parameters, deterministic stride,
source-vertex/sample counts and extrema limits are retained. The same directional
and pooled records apply. A missing or inconsistent third-axis unit makes distance
quantities unavailable; no 2D interpretation is substituted.

### Dataset-local statistical column bindings

`bindColumns PROTOTYPE COLUMN_VARIABLES ROW_COUNT ?ROW_START?` / Script `bind_columns`
returns `gxtxt.statistical_result.column_binding.v1`. The prototype is one
validated, parameterless, table-compatible scalar result. `COLUMN_VARIABLES`
maps canonical numerical quantity IDs to distinct stable Variable IDs in the
Dataset being published. Map every varying fact; unmapped prototype facts are
explicit common constants. All facts must be scalar; vector and fitted-parameter
identities require their existing APIs. The bounded definition contains no row
arrays, Dataset ID or Session path. Its example values are not aggregate results.

Publish it as a named `analysis.statistical_results` record through
`publication_metadata` and Dataset Publication v2. Canonical finalization checks
actual units, real numeric dtype, common row dimension and sufficient column length, then
seals the binding with the payload SHA256 and relevant stable column schema
inside the publication transaction. An invalid binding rolls back publication,
including replacement of an existing result. A declaration written through the
generic metadata API remains unresolved until canonical publication seals it.

`bindingTable SESSION DATASET_ID RECORD_NAME START COUNT` / Script
`binding_table(dataset_id, record_name, start, count)` reads a bounded window
through Table Stream v3 and returns an ordinary CORE statistical table. START is
zero-based relative to the binding span; COUNT is 1–8192 with at most one million numerical fact elements.
Rows have physical identities `row_0`, `row_1`, etc. The reader checks the actual
payload SHA before and after the read and compares the bound schema. Each row is
interpreted from its captured facts, including NaN/undefined states. No numerical
statistics are recomputed. The total bound Dataset may exceed 8192 rows.

`validate`, `validated_result`, `publication_metadata` and `report` accept this
schema. A binding report describes the reference and requires bounded resolution
for values. Scalar/vector field access must use a resolved table. Python and
Octave use the same public binding and typed result decoder. Dataset rename and
Session relocation preserve these local references without rewriting scientific
quantity identities. A changed payload or physical column schema invalidates a
stale binding; names used only for display do not identify its columns.

ROW_START defaults to zero and records the first physical row of the binding.
Several records may describe distinct family spans in one long-form Dataset.
Each span must fit every mapped column; resolved row IDs remain physical.

The Numeric `replicate_summary` operation declares `math.numeric.replicate_profile`.
CORE maps its 19 public fact fields to stable `replicate_*` quantities, retains
source-group and sampling assumptions, and interprets each coordinate separately.
One curve cannot identify sample spread. SEM requires the explicit
`independent_traces` sampling model and is unavailable for unlabelled clouds.
Component availability describes numerical inputs, not verified causal variance
attribution. Negative labelled between-source moments retain their truncation
flag. Plus/minus dispersion and SEM envelopes are not confidence intervals.

The shared Script adapter preserves one-row table fact/value columns when Octave
returns them as native scalars. It uses the existing 17-digit binary64 array
serialization, preserves negative zero, and introduces no tolerance for altered
captured values; a one-ULP edit remains invalid.

`tableCsvRows RESULT MAPPING ?ROW_IDS?` / Script `table_csv_rows` returns a
versioned `gxtxt.statistical_csv_rows.v1` presentation with `columns`, `row_ids`
and `records`. Each record contains only comma-separated scalar numerical text
in mapping order. CORE formats values at binary64 round-trip precision, preserves
negative zero, and leaves non-value states empty. The original validated result
retains each status, reason and unit and must accompany exported scientific
numbers. This formatted view does not replace statistical-result metadata.
Consumers may combine these records with their own identifier/text columns
without reimplementing numerical formatting or applicability rules.

## Signal quality profiles

`math.numeric.signal_snr` identifies the ratio of supplied time-domain signal and
noise squared-magnitude sums. `math.numeric.signal_spectrum_quality` identifies
coherent positive FFT-bin ratios and the exact retained raw-bin normalization.
Both require the actual response unit. Nonfinite logarithmic ratios are undefined,
with no fabricated finite value. Energy sums may be nonfinite while the separately
scaled SNR is finite. No sampling uncertainty or ADC performance is inferred.

The harmonic-power vector retains its complete increasing harmonic-order IDs,
including the undoubled Nyquist bin when harmonic. Public `numeric_field_elements`
provides these identities and common squared-response units. An empty harmonic
range produces zero elements. A scalar result accepts at most 65536 harmonics;
compact scalar-row tables do not flatten vector identities.

## Amplitude-spectrum estimator profiles

`math.numeric.fft_spectrum_quality` captures coherent-gain-corrected FFT lobe
statistics; `math.numeric.harmonic_peak_quality` captures local single-bin peak
statistics from an existing amplitude spectrum. Both require actual `x_unit`
(frequency coordinate) and `y_unit` (amplitude). CORE records the retained
normalization, exclusion and peak/lobe methods. Neither is interchangeable with
`signal_spectrum_quality`, whose powers are raw squared FFT magnitudes.

`math.numeric.harmonic_components` maps component columns to order identity,
expected/detected frequency, signed frequency error, amplitude, relative level
and amplitude percent. Use `from_numeric_columns` for bounded groups of rows,
with common reference amplitude, component method and level-floor facts. CORE
keeps per-row availability: an undefined zero logarithmic level does not hide a
valid neighboring component or a valid zero amplitude. Dataset column bindings
remain available for persisted large component tables.

Summary capture excludes waveform/spectrum bulk arrays in both Script languages.
CORE only interprets the supplied Numeric facts; it does not repeat FFTs, search
peaks or recompute ratios.

## Existing-Session scope for standalone consumers

`lifetime=gxtxt_statistics_scope_v1(session_path)` explicitly binds an owned
standalone CORE statistics service to an existing Session for `binding_table`
reads. It creates no Session or Job and exposes only the statistical API. The
no-argument form retains its stateless behavior; real Script Jobs keep their
existing context. An explicit path cannot rebind an active Job or a service
bound to a different Session. Nested no-argument calls borrow the active scope;
only the owning cleanup closes it. `gxtxt_bridge_info().session_bound` reports
whether a standalone CORE service has the explicit context.

Standalone Octave Dataset Publication API v2 accepts `options.statistical_results`
as named captured records and performs their common CORE conversion. Script
Bridge publication `begin` instead accepts `structured_metadata`. These are
distinct existing bindings; callers must use the option belonging to their API.

Event timing uses the registered Numeric models `event_period` and `pulse_timing`
with the shared `event_timing` profile. Actual `x_unit=s` is required. CORE owns
mean-period, reciprocal-frequency, complete-width and duty-ratio definitions and
the undefined sample-jitter state for one interval. `from_numeric` captures only
bounded summary facts even when a Signal result includes a large crossing array.
Canonical quantities retain actual interval and width counts; repeated detections
and incomplete widths are stated explicitly. Table and Dataset column-binding
contracts retain individual availability without inventing a standard error.

The architecture validator also detects direct standard-deviation, variance and
correlation estimator calls assigned to ordinary variable names in supported
Python, Tcl, Octave and C/C++ syntax. This complements canonical field/policy and
report-boundary checks; it does not claim proof against arbitrary obfuscation.
New findings remain release failures until the real dependency is corrected.

The registered `signal_correlation` profile interprets uncentered conjugate
sequence correlation from public Numeric, including actual unequal lengths,
normalization-specific units, peak components and lag sign. This is distinct
from the existing centered `correlation`/Pearson summary. Both bridges discard
full lag vectors only from the bounded interpretation request; scientific
payload remains available to the caller. `numeric_fields` maps retained peak
and delay fields to CORE meanings. Zero/nonfinite correlation has no resolved
delay; seconds require an explicit rate. CORE performs no correlation or peak
search. The result states the exact normalization and tie policy and implies
no significance, uncertainty, unique delay or sub-sample accuracy.

`window_metrics(window, sample_rate, options={})` owns coherent gain, power gain
and equivalent noise bandwidth for finite real dimensionless window coefficients
with nonzero sum. It retains signed mean gain, mean squared gain (denominator N),
and `sample_rate*sum(window^2)/sum(window)^2` in hertz. Internally scaled moments
avoid avoidable overflow/underflow in ENBW. A positive power gain below binary64
is represented as NaN, rather than a false zero; CORE marks nonfinite moments
undefined while retaining the available gain and bandwidth. The sample rate
must be finite and positive. No window coefficient is a statistical observation
for inference. Capture with CORE model/operation `math.numeric.window_metrics` /
`window_metrics` and actual coefficient unit `x_unit=1`.

The public Numeric operations `signal_periodogram(x, fs, options={})`,
`signal_welch(x, fs, options={})`, `signal_asd(x, fs, options={})`, and paired
`signal_cross_psd|signal_coherence|signal_frf_h1|signal_frf_h2(x, y, fs, options={})`
own Signal's spectral estimators. Existing vector names are retained. Options
are `window`, `nfft` and native `overlap` fraction (0 through 0.95). Welch accepts
an explicit coefficient vector, scalar window length greater than three, or an
empty window for its native default. A zero-energy window rejects. NFFT is
increased to cover a Welch segment; periodogram requires a positive NFFT and a
full-length window, folding the windowed input when NFFT is shorter. Empty
periodogram windows are rectangular. Default Signal windows remain Hamming.

Periodogram removes no mean. Welch explicitly uses native Octave conventions,
removing one global mean over the span covered by complete segments, including
padding for a signal shorter than one window. The caller's persistent pwelch
compatibility setting is restored on exit. Paired spectra are computed together
with a common grid and conjugation `Pxy=Y*conj(X)`. This also supports mixed
real/complex pairs on the same grid. Real
effective inputs yield a one-sided density with DC/Nyquist exceptions; complex
inputs yield the full unshifted grid. Coherence is `abs(Pxy)^2/(Pxx*Pyy)`, H1 is
`Pxy/Pxx`, H2 is `Pyy/conj(Pxy)`. Zero denominators remain nonfinite/unavailable.
No effective independent-segment count or confidence interval is inferred.

CORE registers a distinct `math.numeric.signal_*` model for each estimator under
profile `signal_spectral`. Capture *per-bin* scalar facts with `from_numeric`,
bounded rows with `from_numeric_columns`, or publish complete spectra with
`bind_columns` and canonical Dataset Publication. Full vectors must not be sent
as scalar statistical metadata. Common method/grid/segment facts stay scalar;
`frequency_hz` and the returned value fields vary by row. A binding prototype is
an example bin, never a summary statistic. Both real Script languages support
sealed publication and bounded per-frequency reads through `binding_table`.

Supply the first signal's actual unit as `x_unit`; paired estimators also require
the second signal's unit as `y_unit`. These are signal units, not frequency units.
CORE owns Hz coordinates, squared-unit/Hz PSD, unit/sqrt(Hz) ASD, input-product/Hz
cross-density, dimensionless coherence and second/first-unit transfer estimates.
Use `numeric_fields` for exact unit text and availability; it does not recompute
spectra. Wrong estimator model IDs, inconsistent grids and relabeled definitions
are rejected by common validation.

### Matrix and accumulated summary facts

The registered Numeric summary model supports `matrix_statistics`,
`reduce_summary` and `reduce_accumulate`. Scalar capture preserves actual counts
and values; multi-axis results use bounded `from_numeric_columns` with stable
axis IDs and shared count. Reduction shapes are copied into provenance. CORE
does not rerun reductions or infer an inferential sample size from matrix shape.

### Foundation mean intervals and Huber location

`numeric_model("foundation.statistics.confidence_interval")` resolves
`math.numeric.mean_confidence_interval`; `foundation.statistics.robust_location`
resolves `math.numeric.huber_location`. These retain the existing Numeric
foundation call signatures. Capture the returned scalar facts with `from_numeric`
and the actual `y_unit`; registered identities are checked by both adaptation and
direct interpretation. CORE does not recompute the location or its uncertainty.

The mean interval uses a two-sided Student-t critical value, sample standard
deviation divided by square root of n, and n minus one degrees of freedom. Its
nominal confidence assumes independent identically distributed observations;
normality makes the coverage exact. Singleton means remain values, while sample
standard error and endpoints are undefined. This is no prediction interval.

Huber location retains the existing median start, fixed `1.4826*MAD` scale with
an absolute epsilon floor, tuning constant and maximum 100 iterations. CORE
reports the actual stopping flag and iterations. An exhausted unresolved estimate
is unavailable. The robust scale is neither a standard error nor a confidence
interval; changing numeric unit scale can change the effect of its epsilon floor.
No inference is manufactured. Invalid complex observations, nonpositive tuning
constants and alpha outside (0,1) now reject explicitly.

### Foundation resampling identities

The existing Numeric foundation actions resolve through `numeric_model`:
`foundation.statistics.bootstrap_ci` uses `math.numeric.foundation_bootstrap_interval`,
and `foundation.statistics.permutation_test` uses `math.numeric.foundation_permutation_mean`.
They share the public resampling interpretation profile while retaining different
registered identities from `math.numeric.resampling`.

Foundation bootstrap preserves the accepted seeded mean replicates and the native
Octave type-5 percentile estimator (now explicit). The newer public
`resampling_summary` retains type 7. Foundation permutation preserves strict
`abs(delta) >= abs(observed)` counting with zero tail tolerance; the newer summary
retains its positive floating-point tail tolerance. Both use the plus-one
probability. CORE checks those conventions against the registered model rather
than silently changing the estimator. Permutation does not acquire an invented
confidence level. Source sample counts, actual replicates and seed/generator
provenance are captured without re-running randomization.

Singleton groups and degenerate empirical bootstrap distributions keep explicit
undefined inference. A raw constant percentile does not establish interval
coverage. Numeric alone computes endpoints, distribution variance and probabilities.
Foundation randomization requires an explicit finite nonnegative integer seed;
complex samples and fractional replicate counts are rejected. Caller RNG state
is restored under the original unwind-protection contract.

### Foundation correlation and multiple testing

`foundation.statistics.partial_correlation` resolves to
`math.numeric.foundation_partial_correlation`. Capture its scalar facts with
`from_numeric`. `precision_correlation` is the normalized negative off-diagonal
entry of the covariance pseudoinverse. CORE retains its actual rank, dimensions
and normalization validity. Nonsingular covariance permits the usual linear
partial-correlation interpretation; singular covariance retains a descriptive
pseudoinverse coefficient with an explicit limitation. Invalid normalization
yields an undefined quantity. Neither case supplies sampling inference or causality.

`foundation.statistics.multiple_testing` resolves to
`math.numeric.foundation_multiple_testing`. Pass `adjusted_p`, `original_p` and
`hypothesis_index` as columns to `from_numeric_columns`; retain `family_size` and
`method` in `common_raw`. Choose stable row IDs in original input order.
The CORE mapping exposes adjusted/original probabilities, family size and index.
Bonferroni and Holm state conditional family-wise error control; BH states
conditional false-discovery-rate control under independence or suitable positive
dependence. The recorded family must include all relevant tests and marginal
p-values must be valid. An adjusted p-value is not a posterior null probability.
Reports preserve these assumptions. Compact tables retain the public 8192-row
limit; canonical binary resource bindings support larger captured columns.

Scalar result units retain semantic tokens such as `dimensionless` and `count`.
`numeric_fields` supplies their display `unit_text` as `1`; callers must not
confuse those two representations. No estimator is invoked by these projections.

### Kaplan-Meier survival

`foundation.statistics.survival_kaplan_meier` resolves to
`math.numeric.foundation_survival`, profile `survival`. The public mapping is
`time` → `survival_time`, `survival` → `survival_probability`, `at_risk` →
`survival_at_risk`, `events` → `survival_events`, `censored` → `survival_censored`,
and the common observation count `n`. Capture curve columns with
`from_numeric_columns`, retain `method=Kaplan-Meier` and `n` as common facts,
and declare `context.x_unit` for the observed coordinate. Binary resource bindings
retain the same model and quantity identities for larger captured curves.

CORE validates counts against the supplied risk set and explains independent
observations, noninformative right censoring, no delayed entry, and the actual
tied-event convention. All-censored data have survival one; complete event
exhaustion can yield zero. Neither endpoint implies a confidence or prediction
bound. No sampling error, confidence interval or causal effect is invented.
Reports retain the conditional assumptions; presentation never recomputes the curve.

### Sample covariance matrices and conditioning

`foundation.statistics.covariance_diagnostics` resolves to
`math.numeric.foundation_covariance`. `from_numeric` captures the additive real
and imaginary matrix/eigenvalue fields, actual count, numerical rank and condition
from the public Numeric result. It does not estimate moments or decompose a matrix.
The original provider fields remain available; sample covariance is separate from
fit-parameter covariance. The corresponding parameter-inference quantity remains
not applicable.

Supply `context.output_ids` and `context.output_units` in actual variable-column
order. Without explicit identities CORE uses `variable_1`, etc.; without explicit
units it uses the declared common `y_unit` or `unspecified`. The bounded record
accepts 1–128 variables. Matrix entries retain both identities and product units.
The complex convention conjugates the first variable; real components are
symmetric and imaginary components antisymmetric. CORE validates that structure.

Eigenvalues preserve native returned order and actual real/imaginary components.
Their element IDs are `eigenvalue_1`, etc., independently of measured variable IDs.
A common column unit yields its squared unit. Mixed column units yield
`unspecified` for eigenvalue units and explicit coordinate-scaling limitations.
Eigenvalues are spectral positions, not individual variable variances. Numerical
rank and condition do not establish scientific independence or population coverage.
Singleton sample covariance is undefined; a nonfinite condition has an explicit
undefined reason. Raw accepted Numeric values remain intact.

### Native clustering and numeric data contracts

`foundation.statistics.kmeans` resolves to `math.numeric.foundation_kmeans`,
profile `clustering`. `from_numeric` retains bounded centers, counts, native
distance objectives and actual settings/provenance. Supply `context.output_ids`
and `output_units` in feature-column order, or use the generated `feature_1`,
etc. and common `y_unit`/`unspecified` units. Records accept 1–128 clusters and
features. The rectangular `cluster_centers` quantity has separate `row_ids`
(`cluster_1`, etc.) and `column_ids`; each entry uses its feature's unit.
Population/objective vectors have matching cluster element IDs. No convergence,
selected iteration count, inferential uncertainty or global optimum is invented.

Public Tcl `::GX::StatisticsV1::numericDataFields result` and Script Bridge
`numeric_data_fields(result)` return `gxtxt.statistical_data_fields.v1`, with
`api_id`, `api_version=1` and `fields`. For clustering, `fields.labels` declares
`kind=vector`, `value_kind=integer`, `unit=1`, `shape=[n,1]`, inclusive
`minimum=1`, `maximum=k`, label/definition and `identity_ids` in center-row order.
The actual observation array stays in the existing Numeric result and binary
transport. This operation validates and describes captured results without
estimating anything; profiles without a registered data-field contract return an
empty fields mapping.
In Octave, generic Bridge list values such as shape may be cell arrays; normalize
with `cell2mat` when necessary, retaining the declared dimension order.

Worksheet formula/guided projections consume this contract. Label windows keep
their original observation positions, unit and cluster identity. Guided cells
save their selected original values in the Workbook operation snapshot, outside
CORE statistical metadata, and reopen/publication need no provider invocation.
Changing a captured cell while retaining its old operation lineage rejects;
explicit user edits clear that lineage through the existing cell-edit API.

### Foundation regression iterates

The three operations `foundation.statistics.robust_regression`,
`foundation.statistics.logistic_regression` and `foundation.statistics.glm`
resolve to their corresponding `math.numeric.foundation_*` models, all using
profile `foundation_regression`. `from_numeric` captures the existing provider's
coefficient components, counts and actual stopping facts. `context.output_ids`
and `output_units` describe coefficient positions in supplied design-column
order. Defaults are `coefficient_1`, etc. with unspecified units; the API does
not infer an intercept or dimensional coefficient units from column position.
The bounded contract supports 1–128 coefficients. Complex robust estimates keep
both component vectors; the real-only `coefficients` projection is explicitly
not applicable. `coefficients_real` and `coefficients_imaginary` are the supported
complex projections, with identical coefficient IDs and units.

CORE checks the recorded stopping flag against update norm and threshold and
retains the exact method's numerical conventions and statistical limitations.
Iteration convergence is distinct from statistical identification or existence
of a finite maximum likelihood solution. Parameter covariance, standard errors,
intervals, p-values and residual degrees of freedom are not supplied or inferred.
Coefficient vectors here describe returned iterates; they do not create ordinary
least-squares parameter-inference records. Quantity element projections now
preserve each available public definition, including in the Worksheet inspector.

`numeric_data_fields` describes `residual_real`/`residual_imaginary` for robust
fits and the legacy `residual` field for real fits, in `context.y_unit`.
Logistic `probability` and GLM `fitted_mean` have unit `1`, original `[n,1]`
observation shape and nonnegative bounds (upper bound one for binary response).
These real-valued contracts use optional minimum/maximum bounds. The arrays stay
in Numeric's existing binary outputs; CORE metadata holds no observation copies.


<a id="joint-regional-and-knee-inference-dev097"></a>
### Joint regional and knee inference

`from_numeric` accepts the bounded Numeric `regional_fit` receipt and records
`context.regional_fit.schema = gxtxt.regional_fit_inference.v1`. It validates the
breakpoint IDs/values and fixed/free roles against the actual parameter vector,
C0/C1 conventions, ordered physical positions and per-region counts against the
fitted observation count. The same contract serves standalone scientific
modules, Fitter and real Python/Octave Jobs, including knee components.

CORE retains and reports conditional assumptions: all regimes share one joint
optimization/covariance; local breakpoint intervals require identified changes
and observation support; gap/extrapolated predictions are model continuations.
A free C0 breakpoint exactly coinciding with a fitted predictor cannot use its
one-sided Jacobian to claim an ordinary symmetric interval. Unobserved regimes
also require a separately validated support analysis. Existing convergence,
rank, active-bound, robust-loss and noise-model restrictions remain in force.
`model_selection_plan` refuses unqualified regional likelihood criteria when
that local inference is ineligible. Descriptive physical RMSE is separate.

These are interpretation and validation rules over captured Numeric facts.
CORE, GUI, reports and Script bindings do not recompute the fit or covariance.
<a id="estimated-baseline-preprocessing-context-dev097"></a>
# Estimated-baseline preprocessing context

Any fitted baseline-corrected response supplies `context.baseline_correction`:
`schema=gxtxt.baseline_context.v1`, `method`, `source_dataset_id`,
`source_sha256`, `original_y_variable_id`, `baseline_variable_id`,
`corrected_variable_id`, and
`uncertainty_policy=baseline_treated_as_fixed_no_baseline_estimation_uncertainty`.
Capture these from the generic Dataset Transform receipt. The three Variable IDs
remain distinct historical scientific identities even after downstream aliases
change. This context works through Tcl and both real Script bindings.

CORE requires its baseline assumptions in persisted results and reports them.
Coefficients and descriptive residuals remain available; parameter covariance/SE,
intervals, adjusted fit statistics and likelihood ranking are unavailable because
baseline estimation uncertainty, induced correlations and effective complexity
have not been propagated. No second statistics calculation occurs. A numeric
conditional covariance is not presented as a full-spectrum uncertainty estimate.

Registered callback prediction receipts additionally
declare `model_evaluation_kind=registered_callback`. CORE records method
`registered_callback_bounded_finite_difference_covariance_propagation` and
explains the live callback Jacobian. Unknown evaluation kinds are refused.
Legacy/native receipts retain their original method, assumptions and validation;
the new method is an additive identity, not a rename of existing scientific
results. Script bindings, Fitter retained metadata, reconstruction, publication
and portable Workspace validation preserve this optional provenance field.


<a id="smoother-edf-gcv-and-trace-semantics-dev097"></a>
### Smoother EDF, GCV and trace semantics

The public, versioned API interprets Numeric smoothing facts for every consumer,
including real Python/Octave jobs. `from_numeric` for
`math.numeric.smoothing_spline` / `curve_model_fit` accepts the Numeric trace and
selection receipt. New quantities are `smoothing_lambda` (predictor cubed),
`smoothing_gcv_score` (response squared), `residual_mean_dof`,
`residual_variance_dof` and `smoother_trace_squared`; existing `edf` and `dof`
identities remain. `dof` uses the explicit residual variance convention,
`trace((I-S)^T*(I-S))`, never silently N-EDF. Nodal values remain state parameters
with response units and unavailable independent coefficient inference.

`context.smoother_predictor_unit` supplies the actual fitted predictor unit. For
ordinary orientations its fallback is X (Y for X(Y)); radial fallback is
unspecified unless the angular unit is supplied. Provenance carries
`gxtxt.smoothing_diagnostics.v1`, backend/precision/workspace facts and a bounded
search table. The validator checks selected facts, table shape/budget, bounds,
endpoint flag and minimum recorded candidate without recomputing statistics.
Lambda0 has undefined GCV. Historical results without the new receipt remain
readable; they do not acquire invented diagnostics. Full reports explain fixed
lambda, independent equal-variance observations, omitted smoothing bias and
selection uncertainty, plus the lack of a global search guarantee. Script unit
powers and candidate tables are structured values, not opaque text.

`solver_report(result, details=false)` presents explanatory completion/stopping
status and scientific limitations. `details=true` additionally includes the
backend identity, raw convergence state, iteration accounting and effective
controls. This changes presentation only; interpreted quantities, solver receipts
and validation remain exact. A smoothing solution is explicitly distinguished
from model/statistical validation; historical missing stopping reasons remain
unavailable. Consumers must not parse report text as a numeric data interface.

<a id="log-response-interpretation-dev097"></a>
## Log-response interpretation

Fitted `from_numeric` contexts may declare `response_transform` with schema
`gxtxt.log_response_context.v1`, `base=natural`, positive `reference`, immutable
`source_dataset_id`, `source_sha256`, `source_variable_id`, `source_unit`, the current
`variable_id`, and `inverse_eligible`/`inverse_reason`. Eligible scalar responses
must match the explicitly oriented dimensionless response Variable. Residuals use
`coordinate_space=natural_log_ratio`; later uncertified numerical changes use
`modified_log_coordinates` and cannot be inverted automatically. Reports retain
the distinction between additive errors in log space and original-response fits.

`log_response_plan(source)` returns `STATISTICAL_LOG_RESPONSE_PLAN_v1` with reference,
physical response unit, center role and mean eligibility. A Gaussian log-error model
permits the conditional-median label. Otherwise the center is a back-transformed
fit. The arithmetic mean correction currently requires unweighted training with
independent Gaussian log errors and a captured eligible residual standard deviation;
known or relative heterogeneous errors require an explicit query variance model
and do not silently borrow a common scale. CORE reuses facts without estimating
variance or computing exponentials.

`log_response_interpretation(source, numeric, prediction?)` returns versioned public
`gxtxt.log_response_interpretation.v1`. It accepts the bounded facts from Numeric
`log_response_retransform`; large arrays remain in typed resources. Captured bounds
require their matching public prediction interpretation, exact fitted source,
confidence, kind and row counts. Log-mean confidence limits become conditional-
median confidence limits; future-observation limits retain their prediction target.
They are never relabeled arithmetic-mean confidence limits. The Gaussian variance
correction is explicitly a plug-in mean estimate, not an unbiased finite-sample
estimate, and excludes variance-estimation uncertainty.

The schema supports `validate`, `validated_result`, `report`, `numeric_data_fields`
and `publication_metadata`, with exact scientific-recipe persistence. Column labels,
roles, units, availability and qualifications are regenerated by CORE; private
relabeling fails validation. Python and Octave bindings preserve structured source
contexts and trim large vectors before interpretation. Tcl names are
`logResponsePlan` / `logResponseInterpretation`. The anti-bypass gate recognizes
these public operations and rejects private logarithmic interpretation calls.

Primary definitions: [NIST lognormal distribution](https://www.itl.nist.gov/div898/handbook/eda/section3/eda3669.htm)
and [R predict.lm interval definitions](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/predict.lm.html).

## Linear regression influence interpretation

`influencePlan source` / `influence_plan(source)` returns versioned eligibility
for a captured full-rank, unconstrained linear-design training fit. Nonlinear,
robust, orthogonal, constrained and evaluation-only results receive an explicit
unavailable/not-applicable reason. Numeric remains the only calculation owner.

`influenceInterpretation source numeric` / `influence_interpretation(source,
numeric)` validates bounded `gxtxt.linear_influence_numeric.v1` facts and returns
`gxtxt.regression_influence_interpretation.v1`. It compares population, rank,
parameter count, degrees of freedom, weight meaning, captured residual scale,
review-rule thresholds and single-fit factor reuse with the source contract.
Large vectors stay in typed transport/resources; the Python binding and Octave
`gxtxt_statistics_v1` facade select only bounded interpretation facts.

The result has the public CORE API/version, exact replayable source request,
plan, row count, column descriptions and assumptions. `validate`,
`validated_result`, `report`, `numeric_data_fields`, `publication_metadata` and
canonical publication all support it. The field contract distinguishes exact
original input positions, dimensionless leverage/Cook/studentized values,
response-unit leave-one-out values, and two explicit availability masks.
Log-response residuals retain their dimensionless log-coordinate meaning.

Cook's distance measures the effect of deleting one training observation on all
fitted responses, using captured estimated weighted residual mean square.
Known measurement precision does not silently change this convention. Rank loss,
near-unit leverage, unavailable residual scale and nonrepresentable values remain
explicit. The `2p/n` leverage and `4/n` Cook cutoffs are heuristic review flags,
not tests or automatic deletion decisions. Dataset consumers must map exact
one-based input positions through their original-row identity resources.

The additive `math.numeric.linear_design` model descriptor identifies general
linear-design least squares with generic basis coefficients. Existing linear,
polynomial and historical model identities remain unchanged. Fitter-specific
controls and linked-row UI are implemented separately over this reusable owner.

<a id="parameter-refit-bootstrap-dev097"></a>
## Parameter-refit bootstrap

`bootstrap_plan(source, settings={})` and
`bootstrap_interpretation(source, numeric_receipt)` expose reusable versioned
CORE eligibility, assumptions, parameter units, interval states and reporting.
The result participates in existing validation, exact persistence, typed field
contracts and publication metadata. Numeric alone generates samples, refits and
reduces covariance/quantiles. See the complete [parameter-bootstrap contract](PARAMETER_BOOTSTRAP_v1.md),
including strict trial accounting, historical input compatibility, budgets and
the finite-replicate limitations. Ordinary Fitter controls, recipes, retained
resources and Script pages consume this public contract. Registered callback
refits use the same plan, sampling, summary and interpretation; the plan also
captures the actual callback backend/version, method and function-evaluation
budget. A different backend or incomplete historical observation identity cannot
produce an eligible callback bootstrap.

## Smoothed input coordinates

An explicit `context.smoothing` has schema `gxtxt.smoothing_context.v1` and a
`bindings` list of1..64 captured records. Each record contains current
`variable_id`, canonical `method`, original `source_dataset_id`/`source_sha256`,
`original_y_variable_id`, `smoothed_variable_id`, and
`uncertainty_policy=smoothing_induces_correlated_errors_no_parameter_inference`.
Dataset Transform exposes the authoritative ancestry; Fitter retains its exact
receipts separately from these interpretation facts. Python/Octave return
structured binding dictionaries through the same public API.

`from_numeric` adds CORE qualifications; `interpret`/`validate` require them.
Coefficients and descriptive residual measures remain readable. Covariance,
standard errors, adjusted R squared and inference based on unpropagated residual
variance are unavailable. Independent-error prediction intervals, bootstrap,
AIC/AICc/BIC and nested-model F cannot bypass this restriction. Smoothing has
introduced correlations, bias and effective complexity; merely selecting an
independent Gaussian noise option does not account for them. No correlation
matrix or effective degrees of freedom is invented.

## Conditional power-law parameter units

New `from_numeric` / `fromNumeric` results for `math.numeric.power_law` carry
`context.conditional_parameter_units`, schema
`gxtxt.conditional_parameter_units.v1`. For Y in mA and X in V, the scale has
unit `(mA)/(V)^exponent`; the exponent is dimensionless. The receipt captures
its actual exponent value/status/role, predictor and response units, reference
magnitude1 and `fixed_coordinate_unit_basis`. X(Y) uses the opposite physical
axis binding. A dimensionless predictor gives the coefficient the response unit.
Missing, semantic, affine or opaque unit bases remain explicitly unavailable.

The symbolic coefficient unit is conditional on that result's exponent. It is
an empirical coordinate convention, not a new Unit Registry conversion formula.
Parameter estimates, covariance, standard errors and intervals use the captured
coordinate units. Changing V to mV changes both the coefficient and its
correlation with the exponent: with `x_new = k*x_old`,
`scale_new = scale_old*k^(-exponent)`. Covariance requires the full Jacobian,
including `d scale_new / d exponent = -scale_new*ln(k)`. A label edit or an
independent scalar uncertainty rescaling cannot perform that transformation.

CORE validates the receipt against the registered parameter identities, actual
exponent and role, captured axis units and symbolic coefficient unit. Both real
Script bindings return its typed fields. Parameter reports, canonical parameter
Datasets and standalone export metadata retain it. Older statistical v1 results
without this additive receipt preserve their exact original meaning, including
an originally unspecified coefficient unit; they are not silently rewritten.

For a strictly dimensional user formula with variable exponent, declare
`a*(x/x0)^b`, give x0 the predictor unit and fix its reference value. Then a has
the response unit and b is dimensionless. Unit-preserving internal conversion,
this declared physical reference and optimizer parameter scales are separate
choices; none silently changes the declared parameter identity.

## Derived physical properties

Evaluate named parameter expressions with full correlated covariance, physical
units and explicit unavailable states through the public CORE/Numeric APIs.
Fitter exposes linear thresholds, exponential characteristic intervals, regional
knees and custom expressions in **Results → Derived physical properties…**.
Use **Evaluate properties**, review the report, then **Publish evaluated result**
to create a Dataset from that captured receipt without refitting.
See [declarations, scientific assumptions and Script operations](DERIVED_PHYSICAL_PROPERTIES_v1.md).

## Physical plausibility review

`physical_plausibility(source, rules, context)` and
`physical_plausibility_report(result)` interpret explicit point-value conditions
without refitting or computing duplicate statistics. Common validation, reporting
and protected publication accept this versioned CORE result. See
[the physical review contract](PHYSICAL_PLAUSIBILITY_v1.md).

## Advisory source model suggestions

`fit_suggestions(numeric, candidates, context, entries, criterion)` and
`fit_suggestions_report(result)` interpret deterministic Numeric source facts and
reuse existing captured-model comparison. Common validation/reporting protects
this result. No hidden fitting or automatic acceptance occurs.
See [the source model suggestion contract](MODEL_SUGGESTIONS_v1.md).

## Generalized least-squares interpretation

`gls_interpretation(numeric_summary, context)` interprets the bounded summary
returned by Numeric `generalized_least_squares` or `polynomial_gls`. It distinguishes physical rows,
stochastic covariance rank, exact zero-variance constraints and residual DOF,
checks response/covariance units, and preserves conditional covariance or explicit
unavailability. `gls_report(result)` and common validation/report/publication
metadata share this authority. Whitened residual sequence meaning reuses the
existing CORE sequence API. See [the scientific contract](GENERALIZED_LEAST_SQUARES_v1.md).

`from_numeric` also adapts those operations to the common retained regression
schema, preserving canonical coefficient identities and nested GLS meaning.
The context requires explicit covariance units and correlated Gaussian or
unspecified assumptions. Public parameter inference reuses captured covariance;
independent-error likelihood, bootstrap and influence shortcuts are unavailable.
See the same contract for exact constraints, zero residual DOF and interval policy.

## Implicit equation residual interpretation

`from_numeric('math.numeric.implicit', 'implicit_fit', raw, context)` adapts the
actual Numeric result into the common `gxtxt.statistical_result.v1` schema.
The orientation is `implicit_residual`, geometry `implicit_algebraic`, and
residual units belong to the declared equation. Physical reference normalization
is distinct from measurement sigma and ODR distances. The normalized objective
and weighted residual scale are dimensionless; physical equation dispersion
and parameter covariance retain their physical units. R-squared, known-sigma
chi-squared and ordinary response likelihood ranking are not applicable.

Only explicitly declared independent Gaussian equation errors support local
Student parameter intervals with estimated variance. These are conditional on
the observed coordinate pairs and the equation; unknown noise, nonconvergence,
rank deficiency, active bounds and robust loss retain the existing unavailable
inference policies. Main and parameter-only reports carry these qualifications.
An explicit branch query supplies no prediction uncertainty or uniqueness proof.
The bounded `context.implicit` receipt preserves source identities, coordinate
and parameter units, normalization, counts and conditioning; observation
signatures retain both coordinates. See [Implicit models](IMPLICIT_EQUATION_MODELS_v1.md).

## Joint complex Cartesian results

`from_numeric(math.numeric.complex_response, complex_fit, result, context)`
interprets the captured complex response fit through the common result schema.
Its bounded `context.complex` distinguishes physical observation rows from real
residual components and retains physical units, Cartesian covariance identities,
whitening, phase diagnostic policy and conditioning. The residual definition is
`lower_cholesky_whitened_cartesian_observed_minus_predicted`; a display phase is
never added to physical magnitude in the objective. R-squared and pooled physical
response RMSE are unavailable. The existing Gaussian parameter-inference and
report operations retain all qualifications. See the
[complex response contract](COMPLEX_RESPONSE_MODELS_v1.md) for explicit assumptions,
counts, units and invalid-input behavior. No statistics are recomputed by CORE.

Operation `complex_residuals` uses the same registered model and its versioned
`gxtxt.complex_residual_summary.v1` receipt for evaluation at captured parameters.
CORE establishes `sample_role=evaluation`. Dimensionless residual errors remain
descriptive; training DOF, parameter covariance and intervals are `not_applicable`.
Relabeling evaluation as training or injecting training inference facts is refused
through Tcl, Python and Octave. Reports explicitly retain the no-refit qualification.

## Digitization uncertainty interpretation

`digitization_interpretation(summary, context)` validates the bounded Numeric
pixel/calibration summary; `digitization_fit_plan(meaning, kind, orientation)`
determines response-sigma, actual XY ODR or full response-covariance eligibility.
`digitization_report(meaning)`, `validate` and `validated_result` preserve the
versioned meaning, source bindings and all qualifications. No private consumer
may turn correlated marginal sigmas into independent weights. See the
[pixel/calibration contract](DIGITIZATION_UNCERTAINTY_v1.md).


## Public operation index

The following inventory names every registered Script operation. Python and
Octave use the same operation IDs and input order through the existing Bridge;
Tcl callers use the corresponding methods documented above. Names in parentheses
are input fields, not a promise that every trailing argument is required: consult
the operation's detailed section and live Bridge descriptor for defaults and
bounds. All interpretation, plan, validation and report operations reuse captured
facts; only the named Numeric provider calculates estimates. Storage/binding
operations retain existing resource and canonical publication authority.

| Operation | Ordered inputs | Result role |
| --- | --- | --- |
| `api_info` | None | Registered discovery descriptor |
| `bind_columns` | `prototype`, `column_variables`, `row_count`, `row_start` | Existing owned storage binding / bounded read |
| `bind_resource_columns` | `prototype`, `resource`, `column_variables`, `row_count`, `row_start` | Existing owned storage binding / bounded read |
| `binding_table` | `dataset_id`, `record_name`, `start`, `count` | Existing owned storage binding / bounded read |
| `bootstrap_interpretation` | `source`, `numeric` | Validated interpretation / presentation |
| `bootstrap_plan` | `source`, `settings` | Validated eligibility / settings plan |
| `bootstrap_settings` | `settings` | Validated eligibility / settings plan |
| `derived_properties_interpretation` | `source`, `numeric` | Validated interpretation / presentation |
| `derived_properties_plan` | `source`, `definitions` | Validated eligibility / settings plan |
| `derived_properties_report` | `source`, `numeric` | Validated interpretation / presentation |
| `digitization_fit_plan` | `meaning`, `kind`, `orientation` | Validated eligibility / settings plan |
| `digitization_interpretation` | `summary`, `context` | Validated interpretation / presentation |
| `digitization_report` | `meaning` | Validated interpretation / presentation |
| `feature` | `result`, `quantity` | Validated interpretation / presentation |
| `fit_suggestions` | `numeric`, `candidates`, `context`, `entries`, `criterion` | Validated interpretation / presentation |
| `fit_suggestions_report` | `result` | Validated interpretation / presentation |
| `from_native_comparison` | `method`, `receipt`, `context`, `provenance` | Validated interpretation / presentation |
| `from_numeric` | `model_id`, `operation`, `numeric_result`, `context`, `metrics`, `provenance` | Validated interpretation / presentation |
| `from_numeric_columns` | `model_id`, `operation`, `row_ids`, `raw_columns`, `common_raw`, `context`, `provenance` | Validated interpretation / presentation |
| `from_numeric_table` | `model_id`, `operation`, `rows`, `context`, `provenance` | Validated interpretation / presentation |
| `gls_interpretation` | `numeric`, `context` | Validated interpretation / presentation |
| `gls_report` | `result` | Validated interpretation / presentation |
| `influence_interpretation` | `source`, `numeric` | Validated interpretation / presentation |
| `influence_plan` | `source` | Validated eligibility / settings plan |
| `ini_report` | `result`, `mapping` | Validated interpretation / presentation |
| `interpret` | `request` | Validated interpretation / presentation |
| `interpret_table` | `request` | Validated interpretation / presentation |
| `log_response_interpretation` | `source`, `numeric`, `prediction` | Validated interpretation / presentation |
| `log_response_plan` | `source` | Validated eligibility / settings plan |
| `model` | `model_id` | Registered discovery descriptor |
| `model_comparison` | `entries`, `criterion` | Validated interpretation / presentation |
| `model_selection_plan` | `result`, `binding` | Validated eligibility / settings plan |
| `models` | None | Registered discovery descriptor |
| `nested_f_interpretation` | `reduced`, `full`, `numeric` | Validated interpretation / presentation |
| `nested_f_plan` | `reduced`, `full` | Validated eligibility / settings plan |
| `numeric_data_fields` | `result` | Validated interpretation / presentation |
| `numeric_field_elements` | `result`, `field` | Validated interpretation / presentation |
| `numeric_field_map` | `operation` | Registered discovery descriptor |
| `numeric_fields` | `result` | Validated interpretation / presentation |
| `numeric_model` | `operation`, `facts` | Registered discovery descriptor |
| `parameter_correlation_report` | `result` | Validated interpretation / presentation |
| `parameter_inference_plan` | `result`, `confidence` | Validated eligibility / settings plan |
| `parameter_ini_report` | `result` | Validated interpretation / presentation |
| `parameter_report` | `result` | Validated interpretation / presentation |
| `parameter_rows` | `result` | Validated interpretation / presentation |
| `physical_plausibility` | `source`, `rules`, `context` | Validated interpretation / presentation |
| `physical_plausibility_report` | `result` | Validated interpretation / presentation |
| `prediction_inference_plan` | `result`, `kind`, `confidence` | Validated eligibility / settings plan |
| `prediction_interpretation` | `source`, `numeric` | Validated interpretation / presentation |
| `profile_eligibility` | `model_id`, `operation`, `context` | Validated eligibility / settings plan |
| `profile_interpretation` | `source`, `numeric` | Validated interpretation / presentation |
| `profile_plan` | `source`, `settings` | Validated eligibility / settings plan |
| `profile_report` | `meaning` | Validated interpretation / presentation |
| `profile_settings` | `settings` | Validated eligibility / settings plan |
| `publication_metadata` | `named_results` | Validated metadata for canonical publication |
| `quantities` | None | Registered discovery descriptor |
| `report` | `result`, `quantities` | Validated interpretation / presentation |
| `residual_sequence_interpretation` | `numeric`, `context` | Validated interpretation / presentation |
| `resource_binding_table` | `result`, `start`, `count` | Existing owned storage binding / bounded read |
| `resource_field_elements` | `result`, `field`, `start`, `count` | Existing owned storage binding / bounded read |
| `scalar_rows` | `result`, `mapping` | Validated interpretation / presentation |
| `solver_report` | `result`, `details` | Validated interpretation / presentation |
| `store_columns` | `document_id`, `prototype`, `columns` | Existing owned storage binding / bounded read |
| `table_csv_rows` | `result`, `mapping`, `row_ids` | Validated interpretation / presentation |
| `table_report` | `result`, `row_ids`, `quantities` | Validated interpretation / presentation |
| `table_rows` | `result`, `mapping`, `row_ids` | Validated interpretation / presentation |
| `table_select` | `result`, `row_ids` | Validated interpretation / presentation |
| `table_values` | `result`, `quantities` | Validated interpretation / presentation |
| `validate` | `result` | Consistency validation / typed result |
| `validated_result` | `result` | Consistency validation / typed result |
| `with_parameter_uncertainty` | `result`, `confidence`, `numeric` | Validated interpretation / presentation |

Non-value states retain their explicit reason; reports and field projections
never manufacture zero uncertainty or a nominal interval. Physical units and
parameter/row identities follow the detailed model contract. Storage operations
have Session/Document lifetimes; stateless discovery and interpretation do not
create scientific data or Jobs. The source-field, parameter, table and resource
contracts above explain result shapes and bounds. For numerical calculations,
use the [Numeric API](../../plugins/modules/math.numeric/NUMERIC_API_v1.md).
