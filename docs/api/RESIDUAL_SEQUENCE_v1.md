# Residual sequence diagnostics v1

Numeric computes sequence facts through `NUMERIC_API_v1.residual_sequence`;
CORE owns their interpretation through
`STATISTICAL_RESULT_SEMANTICS_API_v1.residual_sequence_interpretation`.
Fitter and other scientific modules use these same public operations.

## Numerical input and ordering

`residual_sequence(residuals, ordering_keys, options)` accepts 2..1,000,000 real
float32/float64 residuals and a matching real numeric key vector. Integer keys,
including the complete uint64 range, retain their exact storage and sort order.
Empty keys generate positions only when `ordering='input'`. An explicit
`ordering='ascending'` sorts keys, preserving input order within ties.
`max_lag` defaults to min(10,N−1) and must be an integer in 1..min(64,N−1).
`nonfinite='error'` is the default; explicit `'omit'` removes nonfinite residual/key
pairs jointly and joins the remaining observations. No interpolation or time-gap
correction occurs. Unknown options fail. The bounded calculation uses at most
64 million lag products and does not fit a model.

For ordered residuals r, lag k is the sum of
`(r[i]−mean(r))*(r[i+k]−mean(r))` divided by the full centered sum of squares.
It is an observation lag, not elapsed time. Constant sequences have undefined
centered correlations. Durbin–Watson is `sum(diff(r)^2)/sum(r^2)` and is
undefined when every residual is zero. Scaling before reduction protects finite
very small/large responses. This is the statistic defined by
[statsmodels](https://www.statsmodels.org/stable/generated/statsmodels.stats.stattools.durbin_watson.html).

Sign runs use signs relative to zero and remove exact zeros only for runs.
With a positive count a, negative count b and m=a+b, the conditional reference
has E(R)=1+2ab/m and Var(R)=2ab(2ab−m)/(m²(m−1)). The reported standardized
deviation uses that reference without a continuity correction; one-sign or
zero-variance cases are explicitly unavailable. The conditional formulas are
described in the [NIST runs-test reference](https://www.itl.nist.gov/div898/handbook/eda/section3/eda35d.htm).
NIST illustrates median splits; this API explicitly uses residual signs about
zero. It supplies no p values or universal regression significance test.

The `gxtxt.residual_sequence_numeric.v1` receipt contains input/retained/omitted
counts, exact ordering class and policies, sign counts, runs/reference values,
Durbin–Watson, lags/pair counts/correlations, degeneracy flags and work count.
Four SHA256s bind the input and ordered residual/key sequences. Residual hashes
use their canonical float64 values; key hashes retain their exact dtype. Both
include a versioned dtype prefix and little-endian bytes. No original rows are
rewritten or removed from a Dataset.

## CORE interpretation and validation

Tcl: `::GX::StatisticsV1::residualSequenceInterpretation numeric context`.
Both Script languages: `residual_sequence_interpretation(numeric, context)`.
The context requires `residual_unit`, `coordinate_space`, `population`,
`order_label`, `residual_convention` and source content `source_sha256`.
Population is explicitly `fitted_residuals`, `independent_observations` or
`unspecified_dependence`. Declaring independence does not establish it.

The returned `gxtxt.residual_sequence_interpretation.v1` preserves the request,
row count, dimensionless metric labels/definitions/value/status/reason and
shared scientific qualifications. `validate`, `validated_result` and `report`
support this schema. CORE checks contracts and interprets captured values; it
does not recompute reductions. Mutated presentation, unavailable states, count
invariants or policies fail validation. The anti-bypass gate checks private
helpers and duplicate statistical computations in consumers.

Fitted residuals depend on the model and generally on one another, even when
measurement errors are independent. Runs, correlations and Durbin–Watson can
describe patterns; they do not prove independence, validate parameter uncertainty,
or authorize discarding observations. The Gaussian runs reference is not promoted
to a significance claim for arbitrary nonlinear, weighted or smoothed fits.

```python
raw = gxtxt_api_call('NUMERIC_API_v1', 'residual_sequence',
                    [residuals, exact_keys, {'ordering': 'ascending', 'max_lag': 4}])
context = dict(residual_unit='V', coordinate_space='physical',
               population='fitted_residuals', order_label='ascending source row',
               residual_convention='observed_minus_predicted',
               source_sha256=source_sha256)
meaning = gxtxt_api_call('STATISTICAL_RESULT_SEMANTICS_API_v1',
                        'residual_sequence_interpretation', [raw, context])
print(gxtxt_api_call('STATISTICAL_RESULT_SEMANTICS_API_v1', 'report', [meaning]))
```

```octave
raw = gxtxt_api_call('NUMERIC_API_v1', 'residual_sequence',
    {residuals, exact_keys, struct('ordering','ascending','max_lag',4)});
meaning = gxtxt_statistics_v1('residual_sequence_interpretation', raw, context);
disp(gxtxt_statistics_v1('report', meaning));
```

Tcl callers can use Numeric `callOperation` with typed operands/options. Owned
large arrays use the public Scientific Transport resource path rather than a
Tcl list. Script arrays use the existing managed binary transport.

## Retained Fitter results

Tcl `resultResidualSequence reference options` and Script
`result_residual_sequence(reference, options)` read the complete owned residuals
of one accepted result. Choose `order=retained`, `source_rows`, `predictor` or
`predicted` explicitly. Source rows use exact uint64 canonical identities;
predictor uses the captured independent coordinate or geometric parameter.
Geometric fits refuse a single predicted-response order. Optional `max_lag` and
`nonfinite` have the policies above. The output is the public CORE interpretation.
Historical fits lacking exact residual resources are refused without rewriting
the accepted record. No fit, plot sample, parameter edit or source write occurs.

Select an accepted fit and open **Results → Residual sequence diagnostics…**.
Review the order/lag/omission controls and press **Describe retained residuals**.
The dialog shows the CORE report and its scientific limitations. The diagnostic
does not change selection masks or accepted model state.
