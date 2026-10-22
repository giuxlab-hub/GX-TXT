# Curve Source API v1

CORE owns Dataset-backed X/Y curve identity, exact access and display reduction.

The dev096 candidate adds host-only `curveSourceDisplayCacheStore document token
record_id` and `curveSourceDisplayCacheRestore session document cache record_id
request scene`. Curve Source owns the prepared-display policy and complete
source-row/break receipt; Interactive Document resources own immutable UTF-8
receipts and portable float64 little-endian Native2D buffers. Restore verifies
owner generation, blob size/SHA, version/encoding, exact request, scientific
source/schema identity and Namespace before restoring a display object. The
return contains display/descriptor/native identity and `scientific_authority=0`.
It grants no exact publication or source token. Missing/stale/corrupt buffers
must rebuild through normal Curve Source services; incompatible scientific
sources remain unavailable in historical browsing. No GUI handle is persisted.
These host operations are intentionally unbridged; scripts retain exact public
Dataset/Curve Source streams and their existing safe destination contracts.
The API uses logical Dataset/Variable IDs and public Canonical Dataset, Table
Stream, Schema, Dataset Transform and Native2D APIs. No consumer selects a
physical CSV/HDF5 reader. Loading or displaying a source never publishes a Dataset.

`curveSourceOpen session request` returns a Session-scoped token. Required
request fields are `dataset_id`, `x_variable_id`, `y_variable_id`. Optional
`start` and `count` define an exact zero-based row window. `display_budget`
defaults to 4096 and permits 6..65536 points. `member_id` records caller-supplied
source identity; family selection is expressed with explicit filters. `filters`
uses Dataset Transform predicates; `selection_id` uses the shared Selection
authority. These create an owned read-only Transform view with original Dataset
row lineage. An explicit `transform_manifest` is also supported; its output X/Y
Variable IDs must match the request. A view without Dataset-row lineage reports
`row_identity_kind=transform_view_row`, rather than inventing Dataset row IDs.

Optional `order_variable_id` requests a stable complete-tuple sort through the
same Dataset Transform authority. Equal keys keep original source order, every
tuple column stays aligned, and source-row lineage survives the ordered view.
Numeric keys must be finite; text keys use exact lexical ordering. No Dataset
is implicitly published.

`curveSourceDescribe token` returns logical identity, scientific source/schema
fingerprints, row count, request and selected variable descriptors.
`curveSourceDatasetIdentity session dataset_id` exposes the same
existing identity calculation without opening a display token. The Session
must be current. Result fields are `dataset_id`, `sha256`, `schema_identity`;
the schema fingerprint excludes presentation-only labels/descriptions and
retains scientific units/coordinate semantics. It grants no resource or exact
stream authority. Both Script Bridge languages expose
`gxtxt_api_call('CURVE_SOURCE_API_v1', 'dataset_identity', [dataset_id])`
(use `{dataset_id}` in Octave). They return the same three string fields for
their bound Session; unknown Datasets fail explicitly. Standard Octave module
runtimes can call `gxtxt_curve_source_dataset_identity_v1(session,dataset_id)`.
That thin adapter calls this CORE owner and does not duplicate fingerprinting,
open a display, mutate a registry, or widen the statistics service's authority.
`curveSourceDisplay token` returns bounded points, exact zero-based source-row
mapping, finite-source count/full bounds, reduction status and streaming
diagnostics. Native C stores extrema of X and Y in ordered row buckets, retaining
first/last and deterministic earliest ties. Nonfinite pairs are omitted from
display, with explicit path breaks across those gaps; reduction never bridges
an omitted nonfinite run. Memory depends on display budget and input chunk size, not Dataset row
count. Cached presentation is invalidated by scientific source/schema changes.
Display budget does not change scientific source identity.

`curveSourceDisplayAsync token completed progress` provides the same result,
scheduled at bounded chunk boundaries using the Tcl event loop. Its job token
can be cancelled with `curveSourceCancel`; completion reports `ok`, `error` or
`cancelled`. Progress carries completed/total exact rows. No repeating GUI
polling timer is used. Cancel a pending job before closing its source.

Host-only `curveSourceDisplayResponsive source ?progress_callback?` reuses the
same asynchronous job and returns its display result through a cooperative Tcl
event loop. The progress receipt includes the job ID for `curveSourceCancel`.
Cancellation returns error code `GX CURVE_SOURCE CANCELLED`; hosts can treat that
user action as an ordinary cancelled workflow. Cleanup precedes completion.

The host adapter `curveSourceWithNumericInput token consumer ?point_mask? ?progress? ?parameter_variable_id? ?companion_variables?` streams exact
finite XY pairs into temporary interleaved float64 little-endian input and an
exact uint64 little-endian source-row map. It invokes the declared consumer
while these owned files exist and removes them on return or failure. These
are newly created Numeric staging files, never provider or Dataset paths.
An optional host progress command receives completed/total rows at each bounded
chunk. CORE yields between complete transactions, invoking the command before
and after the yield so a host can raise an explicit cancellation error. Stream,
Native staging scene and all temporary files are released before propagation.
The default headless contract remains synchronous without event-loop yields.
This host-only transfer operation is excluded from Script Bridge. Both script
languages instead use scoped exact Table Stream tokens. Scientific fingerprints
include calibration and other schema semantics; presentation labels are excluded.

The complete input also supplies `break_before_file` (`uint8`), one 0/1 byte
per finite pair. Missing pairs create a break before the following finite point,
including at source chunk seams. `native2DLoadNumericRowsWithGaps` consumes these
owned files through bounded binary Native2D appends. These masks affect geometry
continuity; they do not replace original row identities or alter fitting input.

An optional `CURVE_SOURCE_POINT_MASK_v1` descriptor contains `base_selected`,
ordered XY `regions` (`bounds`, `mode=add|subtract`) and `manual_rows`
(original zero-based row ID → `1` include or `2` exclude). Rectangle predicates
apply to every finite exact source pair. Manual row overrides follow all regions.
The callback receives both the full source and a separate `training` input with
its own exact row count/map. At least two selected finite pairs are required.
Training contains independent samples; it does not inherit the full-source gap
file, whose shape and adjacency do not describe a selected subset.
An optional logical parameter Variable ID is read through the same exact stream
and row transforms. Native packing aligns its values with finite XY pairs and
the same selected training mask. The full input and training each expose their
own owned `parameter_file` (`float64_le`), `parameter_format` and variable ID.
Parameters must be finite for every finite XY pair; invalid parameters fail
instead of silently discarding scientific rows. These files share staging
lifetime and cleanup. No Dataset/provider paths are exposed.
`companion_variables` optionally maps up to seven named roles to canonical
Variable IDs. Its `companion_columns` result maps each role to an owned `file`,
`format=float64_le`, `variable_id` and the actual stream's `variable_descriptor`.
Full and selected inputs contain distinct aligned companion files. Filters,
transforms, finite-XY exclusion and the exact selected source-row mask apply
equally to these columns. Duplicate roles are impossible in the dictionary;
`__parameter` is reserved for the unchanged parameter transport.

Missing/nonfinite companion values and zero values stay attached to their rows.
The consumer must explicitly validate their scientific role before calculation;
transport never infers a missingness policy or silently removes a measured point.
The existing optional parameter still requires finite values for every finite XY
pair. Native packing accepts at most 65536 rows per chunk and converts supported
numeric columns to float64, rejecting integer values outside its exact range.
No complete source column is expanded into a Tcl value list. All companion files
are closed and removed on normal return, consumer error or cancellation.
Only a bounded chunk enters Tcl; the full selected set never becomes a GUI list.
Native2D's read-only `selection_state scene object start count` supplies semantic
regions and bounded manual point overrides, including during an active gesture.
Curve Fit maps those display point indices to original row IDs, persists the
descriptor and uses it to invalidate previews after selection changes.

`curveSourcePage token start count` reads exact X/Y rows, with their identities,
independently from the display proxy. Pages permit at most 1000 rows.
`curveSourceLocateRows token source_rows ?progress?` resolves 1..65536 distinct
exact row identities to current source positions, preserving request order.
Transformed sources use a bounded lineage stream; duplicate/ambiguous or absent
identities fail explicitly. A single-source explicit manifest with declared
lineage retains real Dataset-row semantics. This allows a selected endpoint
interval to become an exact complete-row Transform range without deriving
scientific tuples from the display proxy. The host progress form yields at
bounded work boundaries. Both Script Bridge languages expose `locate_rows`
without host progress callbacks.
`curveSourceOpenStream token variable_ids chunk_rows options` returns a normal
Table Stream token with a bounded chunk size up to 65536. Stream `start/count`
are relative to the opened source window. Scientific operations use these exact
streams, including complete tuple columns where requested.
`curveSourceCloseStream` and `curveSourceClose` release owned streams/views.
Unknown provider counts use a bounded counting pass before display ingestion.

Both Script Bridge languages use provider `curve_source`. Operations are
`api_info`, `dataset_identity`, `open`, `describe`, `validate_snapshot`,
`display`, `page`, `locate_rows`, `open_stream`, `close_stream`,
`close`. Tokens belong to one script execution. Display `points` and page `rows`
are typed N×2 numeric matrices. Source-row identities are integer cells, avoiding
conversion to floating-point IDs. Normal Table Stream `close` also releases the
source's ownership receipt. Native scenes, buffers and file paths are not exposed.


## TASK-9 dev-052 final behavior

`curveSourceValidateSnapshot session descriptor` / Script `validate_snapshot(descriptor)` reports `valid`, `status=current|stale|missing`, missing/stale Dataset IDs, current identities and reasons. Identity compares complete source payload SHA and scientific schema fingerprints fieldwise, independently of dictionary order. It does not mutate/reload geometry, publish a Dataset or grant filesystem authority. Saved local owned geometry may remain usable after its source disappears, while complete source-tuple publication explicitly rejects that missing dependency.

## dev073 explicit Preview filters

Preview and the CORE scientific viewer share schema-backed categorical discovery
and existing `filters` / `in_set` requests. No selection remains one unfiltered
source in canonical order. Explicit family choices create separate source requests;
Trace, Replicate and text source-kind filters combine with AND. These are viewing
resources only. The public Curve Source contract and scientific data are unchanged.

## Explicit row continuity (dev094)

A canonical Dataset may declare Metadata `curve_source.continuity_policy` as
`source_row_adjacency` and `curve_source.continuity_variable_id` as a rank-one
integer Variable containing original exact row identities. Display carries a
break across any nonadjacent original-row boundary, including boundaries omitted
by the display sampler. The exact Dataset row count/values remain unchanged.
Nonfinite gaps keep their existing Native policy. Source-order scanning uses
bounded Table Stream chunks and retains only display-budget targets/breaks;
asynchronous display schedules the scan at chunk boundaries and supports cancel.
No implicit sort/interpolation or Native algorithm changes are introduced.

## dev095 responsive display boundaries

The existing asynchronous/Responsive display reads 4096 exact rows per scheduled
Table Stream step instead of 65536. This limits value-provider work inside Tk;
the same complete Native accumulator and normal display budget are unchanged.
Exact point/row/bounds/gap results do not depend on stream chunk boundaries.
Synchronous non-GUI exact access retains its prior contract.

Native2D's owning numeric-column adapter accepts an empty canonical coordinate
cell as a nonfinite pair for display/gap accounting. Exact Table Stream/Page
values retain the missing token. Integer coordinate validation remains exact;
values above the established Native double precision range are rejected rather
than rounded. Missing cells spanning 4096-row seams preserve the same path breaks
as synchronous full-source display.


`::GX::curveSourcePointMaskValidate mask` exposes the existing bounded
`CURVE_SOURCE_POINT_MASK_v1` validator to public consumers. Original unsigned
row identities, ordered add/subtract regions and manual row overrides retain
their existing meanings; validation does not open or estimate a Dataset.

## Exact preprocessing row audit

The host-only Numeric input carries `preprocessing` with schema
`gxtxt.curve_source_preprocessing.v1`: original_count and its availability,
filtered_count (including the requested window), finite_count, selected_count,
nonfinite_count, selection_excluded_count, the exact source descriptor/request,
row_identity_kind and selection descriptor. Original count comes from canonical
metadata for Dataset-row lineage, or the logical Transform view otherwise.
Unknown provider counts remain explicitly unavailable; they are never invented.

`input_source_rows_file` retains every filtered/window row before XY omission;
`nonfinite_source_rows_file` retains exactly the omitted XY row IDs;
`unselected_source_rows_file` retains finite rows excluded by the point mask.
All three are bounded-stream uint64 little-endian files with the same owned
callback lifetime as source_rows_file. Without a point mask the unselected file
is empty. Native source ordinals use the existing nonnegative signed64 range;
the uint64 storage representation does not widen that identity contract.

CORE preserves observations (including repeated X) and stream order. Explicit
source sorting/filtering/transform operations remain in source_request. Scientific
model-specific sorting, duplicate rules, regional or measurement exclusions occur
later and must be captured by that model consumer. The CORE receipt does not
claim those later operations have already happened. An exact filtered exclusion
set is the complement of input row IDs in the original identity range when that
range is known; Transform-view identities retain their distinct source namespace.
No source data are altered.

## Grouped display from one canonical projection

`curveSourceDisplayBatch session request ?options? ?progress?` prepares bounded
series through one canonical Table Stream and the existing Native2D display
accumulator. `request` admits dataset_id, x_variable_id, y_variable_id, filters,
start, count, display_budget and optional order_variable_id. `options` admits
`group_variable_ids` (up to16 distinct rank-one Variables), `max_series` (1–512,
default512), and `total_display_points` (6–100000, default100000). The maximum
per-series display budget is4096. All selected groups must fit the aggregate
budget; no nonempty group is silently dropped. Start/count address each group's
filtered, ordered window as in the existing individual source operation.

The result identifies this existing API and operation `batch_display`, returning
shared source identities, `series` and diagnostics. Each series contains its
normalized group_key, filters, source_descriptor and canonical display. The
Curve Source owner issues the descriptor with `source_kind dataset_batch` and
exact original Dataset row identities. It describes a prepared snapshot without
claiming an open Transform view. Its request can be reopened through the existing
`curveSourceOpen` for exact access. Snapshot validation also checks the batch's
Session origin and declared continuity context; payload/schema/source and Session
lifetime are checked before committing the batch and after cooperative yields.
Coordinate presentation remains with the existing coordinate owner.

Native C++ owns grouping, stable numeric ordering, full bounds and reduction.
The existing Graph Series and Graph Selection authorities validate distinct
identity/predicate values through a bounded2MiB cache; this deliberately retains
those semantics rather than introducing another validator. CSV lexemes and typed
integer identities remain exact. HDF5 keeps its canonical storage worker.
Diagnostics report actual provider reads, one canonical stream and native batch
counts. These facts do not imply zero Python storage work or a performance result.

The current batch supports rank-one numeric X/Y and numeric ordering, up to
2million selected rows and4096bytes per grouping tuple. It explicitly rejects
Selection/Transform manifests, string ordering and unsupported continuity rather
than approximating them; existing individual-source operations remain available
for those cases. Failed/cancelled/stale batches publish no partial series and
release canonical streams and native instances. This method alone does not
establish scientific or GUI acceptance.
