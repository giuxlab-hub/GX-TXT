# Fitter preprocessing and scientific reports

`DATASET_CURVE_FIT_API_v1` retains the exact row stages used by a fit. CORE
`CURVE_SOURCE_API_v1` owns source streaming, filters, row identities, finite-pair
eligibility and point masks. `NUMERIC_API_v1` owns model ordering, duplicate and
endpoint policies. Fitter captures these decisions without repeating selection,
sorting, fitting or statistical computation. All statistical wording and
applicability come from `STATISTICAL_RESULT_SEMANTICS_API_v1`.

## Public receipt and row access

`result_info(reference).preprocessing` has schema `gxtxt.fit_preprocessing.v1`.
For a captured result, `status=value` and these fields describe the actual input:

| Field | Meaning |
| --- | --- |
| `original_count`, `original_count_status` | Number of original source rows; `-1/unavailable` explicitly marks an unknown original count. |
| `filtered_count` | Rows after source filters and any requested source window, before finite-pair omission. |
| `finite_count`, `nonfinite_count` | Retained finite XY pairs and omitted NaN/Inf pairs. |
| `selected_count`, `selection_excluded_count` | Finite rows included or excluded by the captured point mask. |
| `region_count` | Optional row count after explicit regional observation windows. |
| `fit_count` | Actual observations after regional and measurement eligibility, including zero-precision or explicitly omitted measurements. |
| `model_input_count` | Model construction nodes after captured sorting or terminal closure-node removal. This can differ from the number of fitted/evaluated observations. |
| `source`, `source_request`, `selection_descriptor` | Captured source identity, exact request and point-selection decisions. Explicit upstream ordering/filtering remains visible here. |
| `finite_policy`, `duplicate_policy`, `order_policy` | Source-stage policies. Model-specific decisions are in `model_policy`. |
| `coordinate_transform` | Actual orientation, source-axis descriptors/units, forward/inverse translation, and explicit smoothing, baseline or response transformation lineage. |
| `row_identity_kind` | The source ordinal namespace, or `sample_row` for a bounded built-in sample. |
| `stages` | Stage names mapped to retained resource or inline-row fields. |
| `excluded_ids` | Exact set expressions over the retained row stages. |

Stage names are `input`, `finite`, `selected`, `nonfinite`, `unselected`, `fit`,
`model`, and optionally `region`. Each stage preserves its actual execution
order and original integer identities. Unchanged stages can share a resource;
that sharing does not change their meaning. Source ordinals use the existing
nonnegative signed-64 ceiling and travel in uint64 storage, never binary64.

Call `result_preprocessing_rows(reference, stage, start, count)` in either Script
language. Tcl callers use
`::GX::DatasetCurveFit::resultPreprocessingRows $reference $stage $start $count`.
The result has schema `gxtxt.fit_preprocessing_rows.v1`, integer `start`, `total`
and `count`, `row_identity_kind`, and a typed uint64 `source_rows` vector.
Requests are bounded to 1–4096 rows. A request at `start=total` returns an empty
vector. A page approaching the end is shortened; out-of-range starts and unknown
stages fail explicitly. Accepted references retain their normal generation and
provenance checks.

```python
from gxtxt import gxtxt_api_call as call
info = call('DATASET_CURVE_FIT_API_v1', 'result_info', [reference])
rows = call('DATASET_CURVE_FIT_API_v1', 'result_preprocessing_rows',
            [reference, 'fit', 0, 4096])
report = call('DATASET_CURVE_FIT_API_v1', 'result_report', [reference])
```

```octave
info = gxtxt_api_call('DATASET_CURVE_FIT_API_v1', 'result_info', {reference});
rows = gxtxt_api_call('DATASET_CURVE_FIT_API_v1', ...
  'result_preprocessing_rows', {reference, 'model', 0, 4096});
report = gxtxt_api_call('DATASET_CURVE_FIT_API_v1', 'result_report', {reference});
```

## Excluded identities

Exclusions are exact, reconstructible sets rather than an unbounded list inside
a control message. `exact_stage` names an explicitly saved exclusion stage.
`stage_difference` means the IDs in `from` minus those in `subtract`.
`range_difference` means `[start, stop_exclusive)` minus the named stage.

| Exclusion | Set |
| --- | --- |
| `nonfinite` | Exact `nonfinite` stage. |
| `point_mask` | Exact `unselected` stage. |
| `filter_or_window` | Original ordinal range minus `input`; explicitly unavailable if original count is unknown. |
| `region` | `selected` minus `region`, when regional windows exist. |
| `measurement` | `region` minus `fit`, or `selected` minus `fit` without regional windows. |
| `region_or_measurement` | `selected` minus `fit`. |
| `model_nodes` | `fit` minus `model`, including a removed terminal closure node. |

The combined regional/measurement set overlaps its two reason-specific sets;
these are alternative views of the same IDs and must not be added together.
Sorting is a permutation, not an exclusion. The `model` stage records that
permutation. No source is averaged or rewritten implicitly.

## Model-owned input policy

`NUMERIC_API_v1/fit_input_policy(model, captured_state)` returns
`gxtxt.fit_input_policy.v1`. Direct Octave uses
`gxtxt_numeric_v1('fit_input_policy', model, captured_state)`; the generic Tcl
`callOperation` and both Script languages expose the same operation.
It describes recorded decisions; it does not fit or calculate statistics.

| Model | Ordering and duplicate policy |
| --- | --- |
| Linear, polynomial, exponential, power law, Gaussian, components, regions, formula, registered | Preserve observation order and distinct repeated-X observations. No aggregation. |
| Fourier | Uniform-grid orthogonal DFT uses ascending independent-coordinate order and records its actual permutation; nonuniform least squares preserves observation order. Repeated observations are retained by an eligible least-squares design. |
| PCHIP, smoothing spline | Sort ascending in the independent coordinate; reject repeated independent coordinates. The saved model's actual `input_order` permutation determines retained row order. |
| Quadratic/cubic Bézier | Preserve rows, using normalized source-row parameterization. |
| Circular arc | Preserve rows, using unwrapped angular order. |
| Parametric polynomial/spline | Preserve rows under the captured row-order, path-length or user-parameter policy. Path-length parameterization rejects zero-length consecutive segments; user parameters must be strictly monotone. |

Fourier state must identify its actual `solver` branch (`orthogonal_dft` or
`least_squares`); a policy request without that fact is rejected. Parametric state
must carry `parameterization` and
`repeated_endpoint_removed`. A closed curve can remove its repeated terminal
node for model construction while retaining that observation in the fit/evaluation
receipt. The producer records actual `observation_count` and `model_input_count`.
Policies never imply statistical independence or valid uncertainty by themselves.

## Reports, export and persistence

`result_report(reference)` returns a standalone text report. The Tcl equivalent
is `::GX::DatasetCurveFit::resultReport`. Results → **Scientific report** shows
the current preview through the same report owner. Reports contain the equation,
parameter estimates/units/uncertainty status, training and evaluation meanings,
applicable captured quantities, standard fit diagnostics, solver receipt,
source/coordinate/selection inputs, producing framework/API identities, exact
retained model state or its owned SHA256 reference, row-stage references and
output domain. Unknown producing versions remain explicitly unavailable.
Unrelated statistical-module quantities are omitted. Standard fitting quantities
retain explicit unavailable/not-applicable reasons from CORE.

Accepted CSV export publishes an atomic bundle including `.report.txt` and,
when captured, `.preprocessing.csv`. The latter has columns
`stage,row_position,source_row`, with exact decimal integer IDs and every stage
in actual order. Empty stages have no data lines; their zero counts remain in
the receipt. The metadata sidecar names and SHA256-checks both files. This audit
is usable outside the original Session. Export streams bounded chunks; it never
materializes a complete large row map as a Tcl control list.

Dataset publication carries the receipt and all referenced owned row resources.
Workspace save/reopen and CORE resource collection preserve their ownership.
Built-in samples use bounded inline maps of at most 10000 rows. Historical fits
without a captured receipt report `status=unavailable` and
`reason=historical_receipt_not_recorded`; an adapter without a row audit reports
`source_adapter_without_row_audit`. Reading or exporting a historical result
does not refit it or invent missing provenance.
