# Advisory model suggestions v1

Numeric owns `fit_characteristics(X, Y, options)` for two equal finite real
floating vectors of 2 to 1000000 rows. CORE Statistics owns
`fit_suggestions(numeric, candidates, context, entries, criterion)` and
`fit_suggestions_report(result)`. This is an advisory workflow. No model is
fitted, selected or accepted by an inspection or ranking.

## Deterministic facts

Numeric records exact ordered predictor/response signatures through the existing
observation-signature operation, ranges, distinct predictors, signs, constant
response and declared thresholds. It sorts a private view for shape analysis;
original observation order remains in the fingerprints. Repeated predictor
values are retained, with ordered shape hints unavailable. Nonfinite, complex,
integer or unequal vectors require an explicit upstream handling decision.
Zero or unrepresentable predictor spans yield unavailable characteristics.

Default thresholds are `relative_flat_tolerance=1e-8`,
`monotonic_fraction=.95`, `linearity_tolerance=.02`, `prominence=.2`,
`period_tolerance=.15`, and `saturation_ratio=.25`. All are dimensionless.
Monotonicity counts adjacent response differences after normalizing the observed
range. A linear hint bounds maximum deviation from the endpoint chord by .02
of that range. A constant response is treated separately.

Prominent interior extrema require a reversal of at least .2 of the observed
response range. Endpoints are not peaks. A repeated-pattern hint requires at
least three peaks and two troughs, or the reverse; all same-kind extremum
intervals must be within .15 of their median. The suggested period has the
predictor's physical unit. This is not a periodicity test, spectral estimate or
stationarity claim. An irregular chirp can remain unclassified.

A saturation hint requires at least eight observations, monotonic behavior,
at least .1 of the response range covered by the first fifth of observations,
and the final fifth's endpoint slope no more than .25 of the first fifth's.
Irregular sampling, noise, outliers and limited coverage can affect all hints.
Thresholds are captured, configurable through Numeric and Script APIs, and do
not represent confidence levels. Unavailable interval/ratio fields are NaN.

## CORE interpretation and ranking

Candidates are explicit `{id, model_id, label}` records referencing the existing
CORE statistical model catalog. Context supplies `x_unit`, `y_unit` and optional
canonical `observation_binding`. Built-in functional families have reviewable
defaults; other declared formulas, components, registered callables and geometric
models require manual scientific definition. Eligibility is not evidence of
convergence, identifiability or likelihood applicability.

The versioned result schema is `gxtxt.fit_suggestions.v1`. It retains the full
request, candidate suggestions, deterministic advisory order, assumptions and
optional existing `gxtxt.model_comparison.v1` result. Common `validate`,
`validated_result`, `report` and protected publication metadata apply.
Altered candidate conclusions, settings, order or nested comparisons are rejected.

Only explicit `aic` or `aicc` ranking is offered. At least two retained fitted
entries and the current source binding are needed. Source and ordered-row hashes,
population count, predictor and physical response signatures must match the
inspected source. Existing CORE model comparison then verifies weights, units,
response frame and likelihood eligibility, and uses the captured Numeric scores.
No likelihood or fit is recomputed. Incompatible, missing or legacy evidence
gives no ranking. Native functional fits capture an additive physical predictor
signature before translation; prior results without it remain readable and keep
their original meaning, but do not acquire a fabricated assistant binding.
Shape priority and fitted AIC/AICc order are separate fields.

## Fitter and actual Script jobs

Tcl `::GX::DatasetCurveFit::sourceSuggestions key scope options references`
inspects a live Fitter source with `scope=all|selected`. Exact point selection is
captured through the canonical Curve Source API; display decimation is not used.
The existing managed worker reads its exact inputs and invokes public Numeric
characterization through an explicit mode that exits before fitting.

`DATASET_CURVE_FIT_API_v1.dataset_suggestions(source_request, options, references)`
is available to Python and Octave. Tcl uses `datasetSuggestions`. The source
request is the public Curve Source request (`dataset_id`, `x_variable_id`,
`y_variable_id`, optional filters/Selection/Transform). Options are
`orientation=y_of_x|x_of_y`, optional public `point_mask`, `thresholds`, and
`criterion=aic|aicc`. Defaults are Y=f(X), all finite points, default thresholds
and AICc. References are existing public accepted-result references; an empty
list inspects the source without ranking.

The return contains typed CORE `interpretation`, readable `report`, and opaque
Unicode `source_receipt_utf8` containing canonical source/options/preprocessing
evidence. The adapter opens/closes transient sources and worker resources; it
does not create a Workspace or modify a preview, accepted fit or Dataset.
The GUI is **Fit → Model suggestions…**, followed by an explicit inspection.
Selected retained candidates are used only for comparison. Normal fitting and
acceptance remain explicit subsequent actions. Cancel/Escape uses the existing
managed operation lifecycle. Physical source coordinates precede optional fit
translations; measurement-error weights do not determine shape hints.

For example, with an existing Dataset and canonical numeric variable IDs:

```python
from gxtxt import gxtxt_api_call as call
advice = call("DATASET_CURVE_FIT_API_v1", "dataset_suggestions", [
    {"dataset_id": "source", "x_variable_id": "x", "y_variable_id": "y"},
    {"criterion": "aicc"}, []])
print(advice["report"])
```

Saved Session/Workspace schemas and scientific identities are unchanged. Advice
is returned to the caller; it is not silently written into an accepted result.

The CORE context carries `x_unit` and `y_unit` for the oriented predictor and response. Optional `orientation` defaults to `y_of_x`; `x_variable_id` and `y_variable_id` identify the original physical Dataset axes. Fitter supplies all three identity fields. Retained-score reuse compares orientation, exact unit strings and supplied axis IDs as well as source/row/value fingerprints. Changing only units or axis roles therefore makes ranking unavailable; it never silently converts or relabels an accepted fit. Closing an idle advice dialog leaves another active Fitter operation running.
