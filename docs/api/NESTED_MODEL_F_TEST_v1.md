# Nested-model F test

CORE `STATISTICAL_RESULT_SEMANTICS_API_v1` owns eligibility, nested-model identity,
interpretation and reporting. `NUMERIC_API_v1` computes the statistic from captured
fit facts. No operation refits data or recomputes residual sums of squares.

Use Tcl `::GX::StatisticsV1::nestedFPlan reduced full` or Script `nested_f_plan`.
Each entry has exactly `id`, `result` and `binding`. IDs are distinct canonical
identifiers, `result` is a validated individual training fit, and `binding` is the
existing `gxtxt.observation_binding.v1` source/ordered-row SHA receipt. The returned
`STATISTICAL_NESTED_F_PLAN_v1`, version 1, records status/reason and captured counts,
weighted SSEs, degrees of freedom, original response/weight/source/row identities,
exact fitted predictor SHA, variable IDs/units, orientation and noise assumptions.

Supported nesting is a complete lower-degree polynomial space contained in a
complete higher-degree space, including an ordinary line with intercept. Both
models must be full rank, unconstrained, use quadratic least squares and have
strictly positive residual degrees of freedom. The response and retained weights
must be identical in original row order, with independent Gaussian errors and a
common unknown variance scale. Relative precision weights are allowed. Known
absolute variance, robust loss, nonlinear/registered models, general design
matrices without a nesting proof, fixed/active constraints, geometric/joint/ODR
fits and unpropagated estimated-baseline uncertainty do not receive this test.
Unavailable plans explain why; eligible AIC/BIC remain alternatives for non-nested
candidates. Rank or a model name alone does not prove general design nesting.

The fitted predictor coordinates must match exactly. Polynomial centering/scaling
does not change this original predictor binding. Different predictor translations
require explicit matching before comparison. Additive response translations can
differ when the existing Numeric physical-to-fit observation receipt proves their
common physical response. Old fits lacking predictor signatures remain readable
and unverified for this operation; explicit new fitting is required to supply them.

For an eligible plan, call Tcl `::GX::NumericAPIv1::nestedFTest plan`, Octave
`gxtxt_numeric_v1('nested_f_test',plan)`, or the same Script Bridge operation.
For reduced/full weighted SSEs `Sr`, `Sf`, counts `pr`, `pf`, and `n` observations,
Numeric calculates `F=((Sr-Sf)/(pf-pr))/(Sf/(n-pf))` with numerator DOF `pf-pr`
and denominator DOF `n-pf`. It reuses the F-CDF primitive and reciprocal symmetry
for accurate small upper tails, rather than subtracting a CDF close to one.
See the [F distribution definition and survival probability](https://docs.scipy.org/doc/scipy/reference/generated/scipy.stats.f.html).

The Numeric receipt contains its unchanged plan, `f_statistic`, `p_value`,
`numerator_df`, `denominator_df`, `sse_reduction`, `sse_roundoff_clamped`, status
and reason. A negative SSE reduction within `64*eps(max(Sr,Sf))` clamps to zero
and is reported; a larger increase is undefined. Zero full residual scale or an
unrepresentable F statistic yields undefined inference with NaN values. Equal
positive SSE gives F=0 and p=1. No significance threshold is applied automatically.

Pass entries and receipt to Tcl `nestedFInterpretation reduced full ?numeric?` or
Script `nested_f_interpretation`. For an ineligible pair omit `numeric`; CORE
returns a validated unavailable interpretation. Supplying a computation for an
ineligible pair is an error. The result schema is `gxtxt.nested_f_interpretation.v1`
under the public statistical API. It preserves the plan and complete request and
provides named quantities with labels, definitions, units, statuses and reasons.
It supports `validate`, `validated_result`, `report` and `publication_metadata`.
Do not pass it to individual-fit parameter APIs. Stored meanings revalidate from
captured facts without refitting. Altered plans, displayed probabilities or
scientific labels are rejected.

The null sets the additional higher-order terms to zero. The reported p-value is
conditional on fixed designs, independent Gaussian errors, the declared weight
model and models specified independently of these observations. Searching many
degrees or pairs needs a separate selection/multiplicity policy. A p-value does
not measure the probability that a model is true or establish physical adequacy.

```python
plan = call("STATISTICAL_RESULT_SEMANTICS_API_v1", "nested_f_plan",
            [reduced_entry, full_entry])
numeric = {}
if plan["status"] == "value":
    numeric = call("NUMERIC_API_v1", "nested_f_test", [plan])
meaning = call("STATISTICAL_RESULT_SEMANTICS_API_v1", "nested_f_interpretation",
               [reduced_entry, full_entry, numeric])
print(call("STATISTICAL_RESULT_SEMANTICS_API_v1", "report", [meaning]))
```

Fitter exposes `resultNestedF reducedReference fullReference` and Script
`result_nested_f` for durable accepted references. It validates each saved result,
then uses the same CORE → Numeric → CORE path. The Results comparison panel's
**Nested F (first → second)** button uses exactly two selected entries in list
order: reduced first, full second. It shows the complete CORE report and never
accepts a fit or changes source data, scientific History or accepted records.
