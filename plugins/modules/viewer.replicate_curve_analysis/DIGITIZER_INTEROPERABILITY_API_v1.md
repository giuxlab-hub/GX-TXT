# Replicate Viewer API v1 — optional Digitizer preparation

This candidate extends the existing trusted-host REPLICATE_VIEWER_API_v1 provider
with three additive operations. MAIN alone adopts descriptor/public-contract and
version changes. Existing open(context={}), publish(w), dispatch(action,scene) and
describeGui() signatures and ordinary generic-source workflows remain. This is not
a Script/C++ grant, solver, private Dataset parser or replacement for unchanged
Curve Digitizer2.0.9. No operation below submits analysis or publishes results.

## sourceCapabilities {}

Returns api_id/api_version; operations; source_description_schema
(gxtxt.replicate.source_description.v1); trace_binding_schema
(gxtxt.replicate.source_binding.v1); source_kinds; producer (module_id, declared,
enabled, version, missing_apis, activation=not_requested); page_rows_max=4096;
pagination_identity_guard; shared_factor_covariance=unavailable; implicit_analysis=0.
Declaration/configuration discovery does not activate Digitizer, require a Session,
open Tk or prove runtime compatibility. A disabled/missing producer remains a
capability gap. Generic sources remain supported by the original Viewer route.

## describeDigitizerSource {datasetId {options {}}}

Options are exactly start (default0), count (default4096, inclusive1..4096),
expected_revision and expected_session_token. start is a nonnegative canonical row
offset. Later pages require the first revision/token. A private internal count0
metadata probe discovers the canonical row count; public count0/-1 is rejected.
The requested page is clamped to known remaining rows. start==total returns an
empty complete tail; start>total and unknown canonical row count refuse. No full
Dataset enumeration or unbounded range is hidden inside discovery.

Returns schema, api_id/version, dataset_id, source_identity, source_revision,
session_token, columns (actual public role Variable IDs), grouping_roles,
publication_calibration_mode, publication, order_scope=within_actual_joint_group,
groups, calibration, uncertainty, total_rows/start/requested_count/page_count/
consumed_rows/next_start/enumeration_complete and qualifications. Response bound
is2MiB. Each group has actual selection, curve_key/name, calibration_key/name,
page_row_count, first-observed label_policy and optional labels_vary_within_page.
Groups are actual joint curve/measurement pairs observed in the SAME rows. Page
counts are never asserted to be full-group counts; labels are not opaque keys.
A finite stream EOF is not by itself Dataset enumeration completion.

The caller MUST compare every accepted page's public source_identity, revision
and Session token to the FIRST accepted page, not just pass successive tokens.
Public Dataset identity and opaque revision/token are distinct; do not parse their
private encoding or compare them to Curve Source recipe source_id. Session tokens
are ephemeral expectations and do not enter durable source_binding.

Public producer schema/calibration owners supply roles and records. Combined
publication admits its actual metadata-selected published measurement subset and
joint calibration_key MID. Separate publication admits its actual primary MID,
not every available Calibration.replicates record. Availability includes draft or
rejected records and is not publication. Every selected record must be accepted
and valid; actual primary/default identity agreement is checked even when preparing
a secondary. Qualified legacy fallback applies only when modern publication fields
are entirely absent; partial modern metadata is refused. MID differs from the
calibration fingerprint. Recorded calibration provenance is not current-image proof.

## prepareDigitizerTrace {datasetId selection identities expectation}

selection allows curve_key (required nonempty) and calibration_key. Combined
publication requires the actual selected MID. Separate mode allows only its actual
primary MID when calibration_key is supplied. Labels and invented cross-products
cannot select rows. The canonical Curve Source owner must admit a nonempty actual
joint selection, with1..65536 original Dataset rows and dataset_row identity.

identities requires physical_feature_id, observation_id, point_set_id,
calibration_realization_id, source_group_id and frame_id. Optional fields are
topology, landmark_id, direction, phase_index and additional_filters. Identities
are explicit study declarations, not producer-inferred independence or proof of
physical correspondence. additional_filters is a separately reviewed list of
Graph owner predicate dictionaries (at most64 and16KiB before normalization).
Provider curve/calibration predicates and additional predicates are retained
separately in the binding. Explicit rebind must replace the provider predicates;
never append a contradictory new pair to old provider predicates. A consumer must
review any additional predicates whose source meaning changes.

expectation has exactly source_revision, source_identity and session_token from
current public discovery. No silent refresh of stale expectations occurs. The
source role Variables and normalized predicates are resolved through public owners;
canonical coordinates, exact original-row receipt, context and revision remain
owner controlled. Probe/page/Curve Source handles close in finally paths.

Returns schema=gxtxt.replicate.prepared_trace.v1, trace, source_descriptor,
source_binding, qualifications and scientific_preflight=required. trace is the
complete existing scientific request trace plus durable source_binding. Binding
v1 includes kind=curve_digitizer, dataset_id, source_revision/source_identity,
roles, publication, selection, selection_filters, additional_filters,
calibration_identity, declared_calibration_realization_id, uncertainty,
source_descriptor and qualifications. No ephemeral Session token is persisted.
Preparing is inert; a trusted consumer must explicitly accept the recipe and run
the existing whole-study scientific preflight/managed Job workflow.

## Freshness, uncertainty and errors

The Viewer revalidates a known durable binding BEFORE scientific preflight can
stamp a newer outer revision, around source-specific edits and result adoption,
and before publication. It compares actual current publication, roles, selected
MID/pair, normalized predicates, calibration provenance, context/revision and the
full scientific descriptor, not merely its source_id. The service/worker remains
the authority for whole-study frame/order/correspondence/independence and numerical
acceptance. Viewer validation is not an atomic external-writer lock. Conservative
representation differences can require explicit rebind; portable equivalent-dict
serialization is not promised. A rejected submitted Job retains its identity,
requests cancellation and never supplies an adopted result. Status retries are
finite; unconfirmed terminal state is reported and Cancel can retry.

Unknown binding versions are preserved on open/save/History/no-op and refused for
interpretation. Generic prepared-source mapping changes still refuse unsafe
reinterpretation. Same-binding changes start from the full original, preserve
unknown metadata/absent defaults, and use snapshot/History compare-and-set guards.
Current bound edits require the latest History checkpoint. GUI rebind with unknown
extensions or nonempty additional predicates refuses pending explicit owner review;
the API can prepare explicitly supplied reviewed additional predicates.

Uncertainty schema2 readback is a qualified whole-Dataset summary. Publication
markers distinguish absent from incomplete metadata. Unsupported/refused owner
reports retain qualified status and owner errors. Outer/core-binding/core-meaning
point counts must agree and be1..4096. source_integrity can be verified, changed,
missing or unverified. No selected-pair uncertainty mapping, automatic weights,
zero-uncertainty substitution or shared-factor covariance estimator is supplied.
Repeated calibrations share the observation and point set; sensitivity spread is
not independent-repeat SEM. StrokeWidth never becomes sigma.

Adapter refusals use Tcl errorcode {REPLICATE SOURCE CODE}, including
INVALID_SELECTION, INVALID_IDENTITY, SOURCE_CHANGED, RANGE_OUTSIDE_DATASET,
UNKNOWN_ROW_COUNT, UNSUPPORTED_SCHEMA, UNAVAILABLE_BINDING and
UNSUPPORTED_BINDING_VERSION. Public owner errors may propagate unchanged. Messages
qualify actual gaps; no successful discovery/preparation proves accepted science.

## Real acceptance remains separate

Actual original and candidate GUI controls/menus/options, keyboard/mouse workflows,
visual organization, source dialogs, no-op/cancel/rebind, stale refusal, History,
managed cancellation/results, row receipts, publication/Graph v4 and Workspace
save/reopen must be exercised through MAIN's allocated validation. Compare measured
latency/redraw/canvas/responsiveness under comparable display context. Lexical
validation, source review and package readback do not establish GUI/scientific/
performance/installed parity. Original Viewer and prior1.2.1 candidate remain
preserved; no GUI or numerical completion is claimed by this candidate.
