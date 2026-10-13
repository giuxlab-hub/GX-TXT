# Curve Source API v1

CORE owns Dataset-backed X/Y curve identity, exact access and display reduction.
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

The host adapter `curveSourceWithNumericInput token consumer ?point_mask? ?progress? ?parameter_variable_id?` streams exact
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
`api_info`, `open`, `describe`, `display`, `page`, `open_stream`, `close_stream`,
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
