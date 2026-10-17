# CURVE_REPLICATE_ANALYSIS_API_v1

Public CORE orchestration in Replicate 16.0 / framework dev102. The legacy Analysis
remains default-off, opt-in and uses its unchanged standard Octave entrypoints,
Dataset IDs, graph IDs and Numeric scientific kernels. No separate unpublished
user service package was available in deposited dev101. The new facade reuses
its existing public Numeric interpolation/parametric spline/replicate reducers,
Statistical Result Semantics, CurveSource, Unit Registry, Native2D geometry,
Script Registry/Jobs, Publication and Dataset Authority owners.

Tcl: `modulePublicApiActivate curve.replicate_analysis CURVE_REPLICATE_ANALYSIS_API_v1`.
Python/Octave: ordinary `gxtxt_api_call(api_id, operation, arguments)` discovery and
registration. No Analysis window/enablement is required. Host operations:

| Operation | Input → output |
| --- | --- |
| capabilities | Supported methods/designs/limits and explicit unavailable estimators |
| preflight | request → source/coordinate/revision-qualified request; no analysis |
| submit | request → opaque ticket (Tcl dictionary in host) |
| status / cancel | ticket → existing managed Job receipt |
| result | completed ticket → scientific receipt, source guards enforced |
| publish | completed ticket → atomic create-only canonical products |
| describe_output | Dataset ID → persisted schema, interpretation and lineage |

Bridge helpers `preflight_encoded` and `encode_result` serialize a request/result
using UTF-8 Tcl/base64 for the bounded managed worker. Tickets are opaque across
language boundaries to preserve their immutable request serialization. Bridge
`result` exposes numeric column arrays plus units/roles/qualifications/metadata and
source-row receipts and structured original/aligned trace arrays. Original CurveSource
descriptors remain exact public `descriptor_utf8` receipts in Bridge results; host
results retain their complete structured descriptors. Python/Octave schema
strings are public receipt serialization, not filesystem handles.

A request requires `analysis_id`, `method` (`yx`/`xy_path`), `design`
(`repeatability`/`calibration_sensitivity`/`hierarchical`), `reference_frame`,
`traces`; `grid_points` defaults to 200 (3–2048). Frame requires `id`,
`declaration=explicit_user_verified`, `x_unit`, `y_unit`. A declaration asserts
user-verified physical alignment; it is not an automatic registration algorithm.
Every trace requires Dataset/X/Y Variable IDs and all seven identities (study ID
at request level; per-trace `physical_feature_id`, `curve_key`, `observation_id`,
`point_set_id`, `calibration_realization_id`, `source_group_id`). `frame_id` must
match. Optional `curve_variable_id` creates an exact canonical curve filter.
`filters` uses the existing GraphSeries/CurveSource normalized predicate contract.
The exact coordinate metadata snapshot and source revision are captured by CORE.

XY additionally requires `topology=open|closed`, `order_variable_id`,
`landmark_id`, `direction=forward|reverse`, closed `phase_index` (zero-based source
vertex after canonical ordering) and request
`correspondence=anchored_source_arclength`. Coordinates are converted by CORE
into the common X length unit. CORE validates topology before/after periodic or
open parametric spline evaluation. No extrapolation or arbitrary branch matching
is performed. Y(X) requires strictly increasing X and intersects valid domains.

Results contain numeric `columns`, `units`, `roles`, canonical `source_rows`,
`original_traces`, `aligned_traces`, qualifications and Statistical Result Semantics
metadata. Sample cross-coordinate covariance is descriptive at the declared
correspondence. Independent SEM is conditional on independent traces. Calibration
sensitivity has one independent observation and no inferred SEM; hierarchical
components use the existing identifiable Numeric random-effects moment estimator,
with unsupported SEM unavailable. Shared-factor covariance-aware estimation and
confidence/prediction intervals remain unavailable. User-specified localization
and calibration uncertainty remain explicit qualifications, not invented factor
covariances; exact zero is never replaced by epsilon.

Publication creates `replicate.<analysis_id>.profile`, `.traces`, `.summary` in
`module/curve.replicate_analysis/studies/<analysis_id>`. Atomic authority rollback
covers all products. Existing IDs refuse replacement by default. Full per-coordinate
statistical bindings belong to profile; trace/summary reference prototypes state
their first-coordinate scope explicitly. Stage 0 rows are exact original canonical
ordinals; stage 1 rows are derived aligned samples with source-row `-1`. Original
producer, captured coordinate context and source identities remain independent of
metadata contributors. Reopening reads canonical sidecars, not a retained worker.

Use the Viewer guide for physical study design. For a registered Script, preflight
and submit with the schema above, then get `status(ticket)['id']` and use existing
`SCRIPT_EXECUTION_API_v1.job_wait(job_id, 180)` to release parent admission while
waiting for its owned child. Polling without the owned dependency wait under a
single Job slot can leave a child queued. The bridge acceptance includes real
Python and Octave calls under the ordinary Job supervisor. Use result or publish
only after COMPLETED; cancellation/stale Session/source/script/request fails.
