# Derived physical properties and correlated uncertainty

`STATISTICAL_RESULT_SEMANTICS_API_v1` owns derived-property eligibility and
interpretation for any module with a captured fitted statistical result.
`NUMERIC_API_v1` evaluates the declared expressions and propagates the captured
covariance. Python and Octave use the same public operations through real Script
Bridge Jobs. No fit is performed and no covariance is estimated again.

The sequence is `derived_properties_plan(source, definitions)` in CORE,
`derived_properties(plan)` in Numeric, then
`derived_properties_interpretation(source, numeric)` in CORE. CORE also exposes
`derived_properties_report(source, numeric)`. Tcl adapters are
`::GX::StatisticsV1::derivedPropertiesPlan`, `derivedPropertiesInterpretation`,
`derivedPropertiesReport` and `::GX::NumericAPIv1::derivedProperties`.

## Declarations and identities

A definition has `id`, optional `label`, `expression`, explicit output `unit`,
and optional `constants`. Each constant has `id`, finite `value` and explicit
linear `unit`. A definition must reference at least one captured parameter.
Use the stable aliases `p0`, `p1`, … in the captured parameter order. The plan
retains each original parameter ID, role, unit and value alongside its alias;
aliases do not rename the scientific parameters. Output IDs must be unique.
The limits are 128 captured parameters, 32 properties and 32 constants per
property. The existing expression compiler also limits the combined referenced
parameter and constant count to 128.

For an intercept and slope in `V` and `V/s`, this definition gives a threshold
time in seconds, with a target supplied in millivolts:

```python
definition = {
    "id": "threshold", "label": "Threshold time",
    "expression": "(target-p0)/p1", "unit": "s",
    "constants": [{"id": "target", "value": 5000, "unit": "mV"}]
}
```

The CORE dimensional parser validates compatibility and the Numeric formula
compiler applies the declared unit scales. Unknown, opaque, affine or nonlinear
units cannot be silently treated as dimensionless. Expressions use the existing
controlled scientific grammar, with no evaluation of host-language code.
Retained model declarations and their digests are unchanged. Derived expressions
have separate compiled source and binding digests.

## Scientific meaning

The plan is `STATISTICAL_DERIVED_PROPERTIES_PLAN_v1`; the interpretation is
`gxtxt.derived_properties.v1`, carrying the public CORE API identity and its
source/Numeric request. The common `validate`, `validated_result`, `report` and
metadata replacement boundaries protect it. Each property has separate `value_status` and
`standard_uncertainty_status`, reasons, physical unit and compiled identities.
Numeric evaluates the expression and uses the existing native two-sided
automatic differentiation to build its Jacobian in the exact free-parameter
order. It calls public `propagate_uncertainty` once for all eligible properties,
using the full covariance including off-diagonal correlations. The resulting
CORE propagation record includes between-property covariance and row/column
units. `propagation_indices` maps these rows to the declared properties using
one-based indices. It is empty when no property is eligible.

First-order propagation is exact for affine expressions with the supplied
covariance. It is a local approximation for nonlinear properties; large
uncertainty, near-zero denominators or strongly nonlinear transformations can
make it unreliable. It does not imply a confidence level or new degrees of
freedom. Constants and fixed parameters are exact conditional inputs; their own
uncertainty is not included. With no freely estimated parameters, uncertainty
is not applicable. A valid zero covariance can produce zero uncertainty.

Source covariance restrictions, including rank deficiency, active bounds or
unsupported inference after preprocessing, remain effective. A finite value can
still be available when its uncertainty is unavailable. A finite but
nondifferentiable expression has unavailable ordinary first-order uncertainty.
An expression outside its finite real domain has an undefined value. Dependency,
unit, declaration and other backend failures remain errors.

## Fitter and publication

Select an accepted fit and open **Results → Derived physical properties…**.
Choose a template or a custom parameter expression, review the displayed alias
mapping, enter the output unit, then use **Evaluate properties**. The threshold
template has an editable target in the response unit. Available templates are a
linear threshold, an exponential characteristic e-folding interval, and captured
regional knee positions. A characteristic interval is a time only when the
independent axis has a time unit. Templates account for captured coordinate
translations and Y(X)/X(Y) orientation. Custom expressions use the displayed
captured coefficient space; physical coordinate corrections must be explicit.

**Publish evaluated result** publishes the last evaluated receipt. Editing the
fields does not change that receipt; evaluate again to publish changed inputs.
Publication creates a new Dataset with one row and separate value and standard
uncertainty columns, each with its actual physical unit. Unavailable columns are
omitted and their explicit statuses remain in metadata. A Dataset ID collision
is rejected. Publication never changes or re-estimates the accepted fit.

The Fitter Script operations are `derived_definitions(reference)`,
`result_derived(reference, definitions)` and
`result_derived_publish(receipt_utf8, dataset_id)`. The evaluation result contains
the typed CORE interpretation, report text and an opaque UTF-8 receipt. Pass that
receipt unchanged to publication; do not parse or edit it. Tcl callers use
`resultDerivedPublish` for the UTF-8 byte receipt or `resultDerivedPublishText`
for its decoded Unicode text; Script bindings use the latter adapter. Publication rechecks
the accepted source reference and CORE meaning before opening its writer.
Published `derived_properties` metadata is the CORE result, including complete
source statistics and the Numeric receipt. Separate
`derived_properties.source_reference` and `derived_properties.report_lines`
fields retain historical provenance and presentation. The CORE result is the
authoritative meaning; metadata updates cannot erase it or change its labels,
values, units or uncertainty without a consistent validated request. Its scientific meaning
survives removal of the original Fitter Workspace. It does not claim to archive
the original raw observations or an editable model.
