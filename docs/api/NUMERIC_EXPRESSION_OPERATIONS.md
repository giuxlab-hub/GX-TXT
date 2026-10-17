# Bounded mathematical expressions

These operations belong to `NUMERIC_API_v1`. Discovery, typed transport,
canonical Dataset access and execution remain with their existing public owners.
Expressions use the shared CORE Analysis grammar and dimensional validator;
arithmetic/functions and scalar root/minimization methods remain Numeric.
There is no source-code evaluation, symbolic algebra system or second solver.

## Typed expression evaluation

Octave: `gxtxt_numeric_v1('expression_evaluate', expression, symbols,
symbol_units, options={})`. Python/Octave Script Bridge uses the same operation
and argument order, excluding the initial dispatcher operation string. Tcl uses
`::GX::NumericAPIv1::callOperation expression_evaluate` with three typed operands
and typed options. Symbols are explicit scalar/vector values, not code.

The grammar supports finite numeric literals, identifiers, parentheses,
`+ - * / ^` and functions genuinely registered as pointwise `elementwise`
Numeric expression operations. `pi` and `e` are reserved dimensionless constants.
Function metadata determines the approved operation and unit behavior; unknown
names, statement syntax, callbacks and non-pointwise reductions reject.

Declare every referenced symbol's actual linear physical unit; `1` denotes
explicit dimensionless quantities. CORE converts compatible scales before
arithmetic and validates sums, powers and transcendental arguments. An optional
`output_unit` requests a compatible linear result unit; otherwise the result
uses the canonical dimension label. Absolute affine/semantic units, ambiguous
unit arithmetic and invalid/nonfinite real domains reject rather than guessing.

Example in a registered Python script:

```python
result = gxtxt_api_call('NUMERIC_API_v1', 'expression_evaluate', [
    'a*x+b', {'x': [-2, 0, 2], 'a': 2, 'b': 1000},
    {'x': 'V', 'a': '1', 'b': 'mV'}, {'output_unit': 'mV'}])
# result.values: -3000, 1000, 5000; result.unit: mV
```

Inputs are nonempty finite real scalars/vectors, at most 64 symbols and 65536
values per vector. Nonscalar lengths must agree; scalars expand. Formula text
is bounded to 8192 characters and 1024 shared-parser tokens. Exact integers outside
binary64's integer range reject before numerical conversion. The Tcl bounded
transport also caps the combined numeric control payload at 65536 values; scripts
use existing typed binary transport for larger aggregate input. Output includes
values, unit, dimensional receipt, expression and actual symbol identities.

## Canonical Dataset inputs

Tcl: `::GX::NumericAPIv1::expressionDataset expression bindings parameters options`.
Script Bridge: `dataset_expression(expression, bindings, parameters, options)`.
Direct Octave uses `gxtxt_numeric_v1('dataset_expression', session, expression,
bindings, parameters, options)`, where trusted CORE supplies Session context.
Ordinary Viewer/Script callers use only canonical Dataset/Variable IDs.

`bindings` maps each symbol to `{dataset_id, variable_id}`. `parameters` maps
scalar parameter IDs to `{value, unit}`. Options require explicit `count`
(1–65536), optional zero-based `start` (default 0), and optional `output_unit`.
Only 1–32 genuine numeric table Variables are read, through bounded public
Table Stream pages. Original scientific bytes, Variable identities and units
remain intact. Missing/nonfinite observations reject; no rows are omitted
implicitly. A short source rejects rather than truncating the requested domain.

Results include each symbol's Dataset/Variable identity, actual source unit,
absolute source row start/count and source-order mapping. Choosing equivalent
row positions across different Datasets is an explicit caller operation; this
does not infer temporal alignment, coordinate registration or sample independence.
Publication is a separate explicit canonical operation.

## Roots, intersections and local extrema

Octave: `gxtxt_numeric_v1('expression_analyze', request, options={})`.
Tcl uses the typed operation catalog; both Script languages expose
`expression_analyze` with the same request/options.

The request requires `expression`, `variable`, increasing finite `interval`,
`symbol_units` including that variable, and scalar parameter `symbols`.
`mode=roots|intersections|extrema` defaults to roots. Intersections also require
`expression2`; both expressions must produce compatible response dimensions.
The interval/tolerance use the independent variable's declared input unit;
`response_tolerance` uses the returned response unit. Options include
`output_unit`, `sample_count` (5–4097, default 129), `max_evaluations`
(sample_count–65536, default 8192), `max_iterations` (1–256, default 128), positive
`x_tolerance` (default 1e-9) and `response_tolerance` (default 1e-9).

A finite grid proposes intervals. Sign-changing roots use existing Numeric
`root_find`; sampled valleys of absolute response use `minimize_1d` to expose
possible even-root candidates. Residuals and candidate kinds remain explicit.
Local extrema use the same minimizer on sampled interior neighborhoods. Interval
endpoints and their values are reported separately. Candidates are deduplicated
within8times the requested X tolerance.

Statuses distinguish roots/extrema found, none detected, indeterminate sampled
zero, partial candidate failure and exhausted evaluation budget. Domain errors
reject. A small residual is not a proof of continuity, exact multiplicity or
scientific eligibility. Finite sampling can miss narrow, oscillatory or multiple
features; `completeness=finite_sampling_is_not_a_completeness_proof` is always
retained. No measurement uncertainty, confidence interval or independence is
inferred. Returned roots/extrema preserve actual coordinate/response units.

## Execution, cancellation and persistence

Direct calls are synchronous and retain finite input/evaluation bounds. Use the
existing registered Script Job/Bridge path for long work, durable status/logs,
resource budgets, process-tree cancellation and restart reconciliation. There
is no additional expression scheduler. Caller Session/Document revisions must
be captured and checked before result adoption.

Mathematics Explorer calls this owner, uses managed Jobs for Analyze/Cancel,
and displays evaluated samples with the existing native Plot widget. Its
Document persists formulas, units and numerical viewport; explicit Dataset and
Graph publication preserve canonical scientific identities/provenance. See its
[user guide](../../plugins/modules/viewer.mathematics_explorer/docs/USER_GUIDE.md).
