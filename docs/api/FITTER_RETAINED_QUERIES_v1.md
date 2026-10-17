# Accepted Fitter queries and local inversion

Select one accepted fit and choose **Results → Query selected model and derivatives…**.
Enter exact query values, optionally allow extrapolation, and press the query
button. The read-only report shows physical coordinates, dy/dx and dx/dy with
CORE unit interpretation. Inverse queries require an explicit continuous branch
bracket and model-response targets. They return local roots or an unavailable
reason, and never claim global uniqueness. No fitting or uncertainty calculation
occurs. Closing the popup removes its temporary overlay.

Tcl public calls are `::GX::DatasetCurveFit::resultQuery reference values ?options?`
and `resultInverse reference targets bracket ?options?`. Script Bridge operations
on DATASET_CURVE_FIT_API_v1 are `result_query(reference,values,options)` and
`result_inverse(reference,targets,bracket,options)`. Obtain the immutable reference
using `result_reference(document_id,fit_curve_id)`. Source, result identity and
Document generation are verified before and after execution.

Queries accept 1..4096 finite values, inverses 1..64 targets; no sampling is used.
Supported retained states include native scalar models, frozen formulas/components/
regions and exact saved direct-model JSON. Frozen declarations are reconstructed
through their existing public Numeric constructors, with captured identity and
fitted parameters. Retained JSON is bounded to 128 MiB with the packaged native
decoder. CORE streams its owned resource into a temporary worker file in 64 KiB
chunks; public Numeric `model_state_decode` restores exact binary64 numbers once
per request. Neither the saved bytes nor their identity change. The public API
accepts retained references, never arbitrary worker paths. Temporary files are
released on success, failure and cancellation. No full JSON Tcl list or numeric
Base64 substitute is created. The separate standalone text-export budget remains
2 MiB; large retained queries do not enlarge exported artifacts.
Registered Python/Octave models use a supervised callable Job with the exact
retained declaration, source SHA, entrypoint, revision, bounds and fitted
parameters. Changed current callable declarations are refused; querying never
silently updates a registry or refits an accepted model.

New fits retain `training_domain` and `training_domain_basis` from the exact
eligible training rows after orientation, regions and measurement selection,
before coordinate translation. This is the minimum/maximum interval, not the
union of disjoint selection windows. Parametric models use the normalized fitted
parameter interval. The exported output domain is a separate concept. Historical
fits lacking this receipt require explicit `reference_domain=[lower,upper]` and
are labeled `user_declared_not_verified_training`; no historical data is rewritten.

Query options: `extrapolation=error|allow` (default error), `derivative` (default
true), `tangent_floors=[fx,fy]`, optional `derivative_unit` and
`inverse_derivative_unit`. Inverse options instead accept `x_tolerance`,
`response_tolerance`, `max_iterations`. Intrinsic model domains remain enforced.
Physical query/response and X/Y units are included in `context`; radial inverse
is for radius versus angle, and parametric XY inversion is explicitly unavailable.

Results preserve raw Numeric slopes and validity masks. Separately,
`interpreted_derivative`, `interpreted_inverse_derivative` and their validity
masks apply public CORE differential plans. Unknown or incompatible units and
nonfinite converted values yield NaN with false validity, never a fabricated unit
or coefficient. Differential resistance is identified only for CORE-compatible
resistance dimensions. See [CORE units](UNIT_REGISTRY_API_v1.md) and
[Numeric query semantics](RETAINED_MODEL_QUERIES_v1.md).

The overlay marks every exact requested point. Ordered queries may be joined;
segments touching an extrapolated query are orange and dashed. Unordered queries
show markers only. These connecting segments are a display aid, not extra model
evaluations. The overlay and report do not change accepted results or source data.

## Retained registered callable ownership

The same result_query/result_inverse operations and Results action accept retained
registered Y(X)/X(Y) models. No alternate client interface is required. A verified
CORE callable invocation reconstructs the live model and calls public Numeric
model_query/model_inverse. The report declares the numerical derivative method
and its limitations. `difference_step` and `difference_relative_tolerance` are
additional callback-only query options; see [Numeric's policy](RETAINED_MODEL_QUERIES_v1.md).
An ordinary `derivative=false` query preserves physical predictions while both
raw and interpreted derivatives remain unavailable. Unit conversion processes
only valid finite entries. A one-point result retains the same N-by-2 points
contract as a multi-point query, including in Script Bridge and text reports.

Query children use CORE owned-child waits (120 seconds per request), cancellation
and managed temporary resources. A caller retains only its reconstructed bounded
result, not a durable reference to temporary output. Completed/cancelled requests
remove their dedicated query Document after the child becomes terminal. Recovery
of an interrupted parent requires verified terminal parent/child linkage; unknown
owners are retained. Accepted Workspace Documents, source Datasets and historical
scientific records are unchanged. Script callers can submit queries within Jobs
under the configured worker limit; the parent yields capacity through CORE.

The registered_query_run operation is a callable integration hook. It requires a
live execution-scoped handle, verified CORE invocation identity and an owned,
nonce-bound request with its exact hash. Ordinary clients use result_query or
result_inverse. Unowned calls are refused. No callback source is reconstructed
from a guessed formula or sampled fit curve.

The report labels query/model-response units separately from physical X/Y units.
Derivative method is always declared, including numerical registered callbacks.
Integer arguments outside [-2^53,2^53] require an explicit scientific conversion;
the public query layer never silently rounds source identities into coordinates.
Accepted-output Dataset extrapolation columns are separate from these query
results and their temporary overlay.

## Accepted output domain flags

Every newly fitted output row retains its original independent query coordinate
and `is_extrapolated` flag. The closed envelope is the minimum/maximum of exact
eligible training coordinates, before translation. X(Y) uses physical Y; radial
models use the captured angle and angular unit; parametric models use normalized
parameter with unit1. Excluded interior windows are not classified as extrapolation.
Intrinsic evaluator domains remain mandatory: PCHIP and other bounded evaluators
refuse invalid output rather than invent values.

Preview and accepted fitted segments touching an outside row are orange and dashed.
This conservative connecting-line style is a display aid; each exact point marker
is classified once. CORE display sampling preserves exact output row indices.
The report states the outside count and reference domain. Historical results with
no captured receipt stay explicitly unclassified; no Session is migrated.

`result_info` exposes `output_domain` with schema `gxtxt.fit_output_domain.v1`,
status, row_count, outside_count, reference_domain, reference_basis, boundary_policy,
intrinsic_policy, coordinate_space and query_unit. Both Script languages receive
typed integer counts and a numeric two-element reference_domain. Historical status
is unavailable with reason historical_receipt_not_recorded. `resources` exposes
the Session-owned output_domain_resource when present. Its float64 interleaved
columns are fit_query/is_extrapolated, aligned exactly to fitted geometry; bounded
standalone samples may retain at most10000 inline rows instead.

Published Datasets append float64 `fit_query` with the physical query unit and
uint8 `is_extrapolated` (0 or1, unit1), with the same versioned metadata receipt.
CSV appends the two columns after its existing columns and retains the receipt
in its metadata sidecar. Generic Plot consumers may use the published flag for
styling; no additional model evaluation or statistics is needed. Dataset/CSV
publication streams exact rows; display decimation never becomes scientific data.
