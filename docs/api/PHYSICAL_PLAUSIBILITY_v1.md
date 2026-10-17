# Physical plausibility review v1

CORE `STATISTICAL_RESULT_SEMANTICS_API_v1` owns interpretation of explicit
physical conditions on captured parameter point values. This reusable contract
accepts any validated `gxtxt.statistical_result.v1` scalar parameter result.
It does not fit, calculate a statistic, infer probability or propagate uncertainty.

Python and Octave use `physical_plausibility(source, rules, context)` and
`physical_plausibility_report(result)`. Tcl uses
`::GX::StatisticsV1::physicalPlausibility source rules ?context?` and
`physicalPlausibilityReport result`. Common `validate`, `validated_result`,
`report`, `publication_metadata` and Dataset metadata protection apply.

Each rule has a unique identifier `id`, exact captured `parameter_id` and `unit`,
`kind` and a nonempty physical `rationale`. Optional `label` defaults to the ID,
`severity` to `advisory` and `enabled` to true. Severity `domain_requirement`
means the caller explicitly declares the condition as a physical requirement.
Neither severity changes the accepted fit or intrinsic model constraints.

`kind=interval` requires a finite `lower` and/or `upper`. Endpoint flags
`lower_inclusive` and `upper_inclusive` default to true. The interval must be
nonempty and ordered. `kind=domain_fraction` accepts a positive finite
`maximum_fraction` (default1), and requires `context.domain` with finite ordered
`minimum`, `maximum`, and the same `unit`. It compares the point value with
the inclusive interval from zero to that fraction of the declared range width.
Missing or zero-width domains yield unavailable conditions. Mixed units,
unknown parameters/fields, nonfinite limits and invalid flags are rejected.
There is no implicit unit conversion. Bounds must be expressed in captured units.

Results have schema `gxtxt.physical_plausibility_review.v1`, API version1,
`request` containing the captured source, normalized rules and context, ordered
`checks`, counts, `coefficient_space` and explicit assumptions. Each check keeps
the normalized rule, parameter role, finite value when available, limits, status,
outcome and reason. Outcomes are `satisfied`, `violation`, `disabled` or
`unavailable`. Overall assessment is `domain_requirements_violated`,
`advisories_present`, `incomplete`, `not_assessed` or `no_violations` in that
precedence. Overall status is unavailable if any enabled condition cannot be
evaluated, otherwise value when any condition was evaluated, else not_applicable.
Counts preserve simultaneous warnings and unavailable conditions. Disabled is
never a successful assessment. Common validation reconstructs the interpretation
from its request and rejects altered conclusions or fields.

Rules concern the declared coefficient coordinate frame, not an implicit inverse
transformation. A positive Gaussian width can still be poorly constrained; a
satisfied physical interval proves neither identifiability nor model validity.
Fixed parameters remain conditional point values. Limits are at most32 rules,
128 captured parameters,64 characters per rule ID,256 per label/unit and2048
per rationale. These bounded review records are not a bulk-data transport.

## Fitter and Script Bridge

`DATASET_CURVE_FIT_API_v1.plausibility_definitions(reference)` returns captured
parameters, suggested rules, coordinate frame and retained training domain.
Suggestions use intrinsic Gaussian width, optional exponential decay, or frozen
composed-model domains and descriptor hashes. Additional physical assumptions
must be supplied explicitly. There is no inference of positivity from a name.

`result_plausibility(reference, rules)` returns CORE `interpretation`, readable
`report` and opaque Unicode `receipt_utf8`. Python uses dictionaries/lists;
Octave uses structs/cell lists. No Numeric invocation is needed. For example,
with an existing reference whose captured parameter is `rate` in `1/s`:

```python
from gxtxt import gxtxt_api_call as call
rule = dict(id="expected_decay", parameter_id="rate", unit="1/s",
            kind="interval", upper=0, upper_inclusive=False,
            severity="advisory", rationale="This experiment expects decay")
review = call("DATASET_CURVE_FIT_API_v1", "result_plausibility", [ref, [rule]])
print(review["report"])
```

`result_plausibility_publish(receipt_utf8, dataset_id)` checks the exact retained
source and domain, validates CORE meaning, and publishes a new one-row HDF5
Dataset. `rule_<rule_id>_violation` is0/1, orNaN when not assessed; a finite captured
parameter is retained as `rule_<rule_id>_value` with its exact unit. The fixed `rule_` prefix keeps leading-underscore IDs valid and distinct;
scientific rule and parameter identities are unchanged. Structured metadata
`physical_plausibility` is the complete protected CORE result;
`physical_plausibility.source_reference` and `.report_lines` retain provenance
and explanation. Existing Dataset IDs cannot be replaced. Empty rule sets cannot
be published. Receipt size is limited to16MiB. The Tcl UTF8 text adapter preserves
Unicode in real Python/Octave Jobs; receipts should be treated as opaque.

Session/workspace schemas and prior accepted results are unchanged. Published
review metadata remains interpretable without the live Fitter document. Review
conditions are persisted in the new Dataset receipt, not automatically inserted
into the original accepted fit. The GUI requires committing editor changes with
Add/Replace, reviewing, then publishing the captured result.
