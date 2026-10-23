# Dataset Preview API v1

The shared table measures headings with the active Tk heading font and includes
unit suffixes in its minimum column widths (bounded to 480 pixels). Horizontal
navigation handles wide tables. Page refresh retains user column sizing; schema
or font changes refresh only the affected heading configuration. Narrow-window
paging/Go controls use the shared UI_FIELD adaptive layout, preserving keyboard
and mouse access. These presentation changes leave exact values/source rows and
the 1000-row/32-variable preview bounds unchanged.

SPDX-License-Identifier: GPL-3.0-or-later

`datasetPreviewPage(session, dataset_id, options={})` returns a bounded,
backend-neutral table page using Canonical Dataset metadata and Table Stream v3.
Options are zero-based `start` (default 0), `count` (default 100; range 1–1000),
and ordered `variable_ids`. Default projection includes at most 32 rank-1
variables. Table Stream validates the shared row dimension and dtype.

A successful page includes Dataset identity, storage provider (informational),
total row count (`-1` when unknown), start/count/page size, complete selected
column schemas/labels/units, rows, one-based original `source_rows`, and previous/
next availability. Non-table resources report `available=0` and a textual reason.
Invalid variables or ranges fail explicitly. Scientific data is never reduced
or changed. CSV and HDF5 pages use the same table model.

`datasetPreviewCreateTable(parent, session, dataset_id, ?variable_ids?)` embeds a
paged Tk tree with source-row identities, units, vertical/horizontal scrolling,
Previous/Next, and direct row entry. `datasetPreviewOpenTable(dataset_id)` opens
the reusable table window. These GUI operations remain host-only.
The legacy `datasetPreviewTableSnapshot` delegates to the same page authority.

**Column details** reveals a read-only, scrollable inspection of the displayed
columns' exact Variable IDs, labels, declared dtypes/value kinds, units, semantic
roles and shapes. Missing metadata says `(not declared)`; it is never inferred
from values. The panel states how many columns are displayed out of the full
schema. Page and Dataset changes refresh it from the same `datasetPreviewPage`
result. Ctrl+C copies the selected schema row without editing data.
`datasetPreviewTableInspect(parent)` observes that same bounded page, current
selected one-based source rows, read-only state and details visibility. These
host operations introduce no schema parser, data store or publication route.

Script Bridge `DATASET_PREVIEW_API_v1/page` takes Dataset ID and an options
struct, returns the same bounded model, and never exposes a provider path.
Preview is read-only. A displayed page is not the input for fit-all or publication.

The GUI provides optional Z and read-only XYZ scatter beside existing X/Y Render.
It consumes the same canonical schema/Table Stream and shared Native3D consultation
host. The paged table API and its 1000-row bounds remain unchanged. XYZ limits and
source-row reduction receipts are documented in DATASET_VIEWER_API_v1 and the
shared Native3D preview guide; no scientific Dataset is created by activation.


## Native graphical consultation

`native3DPreviewAcquire` retains the existing shared DatasetViewer host/worker
and RAM frame. Plots' eligibility control is a placed canvas child and does not
reserve a layout row. The shared Graph Workflow owner resolves the exact selected
Graph reference and verifies its scientific 3D source before consultation.
Plot Dataset v4-owned `plot.dataset.xyz` references use the v4 compatibility,
source-fingerprint and preview-export contract. Existing legacy Plot Dataset
XYZ references remain readable through CORE's v3 compatibility path; this does
not authorize direct v3 use in new restricted Viewer authoring.

A different producer Graph can use its declared scientific 3D bridge when the
retained preparation, runtime geometry kind, current canonical Dataset SHA,
Variable IDs/units/bindings, coordinate receipt and presentation agree. CORE
retains the original producer/Graph/Variant identity and uses the existing Plot
Dataset 3D exporter and Native3D consultation. A retained compatible preparation
may be used even when its representation Variant is not currently registered;
consultation does not create a Variant or rename the provider. A static PNG
alone supplies no interactive geometry. No persistent Viewer Document is needed,
and ordinary 2D/static double-click is unchanged.
The compact controls provide orbit left/right/up/down, native camera roll clockwise/
counterclockwise, exact reset, Exit and a presentation-only scientific axes/grid toggle.

`::GX::native3DPreviewEnlarge host` moves the shared consultation into a resizable
independent Tk window. It reuses the same prepared VTP/native objects/worker/camera.
Resize uses the existing native target/viewport APIs; no Dataset reload or Octave
preparation occurs. Closing returns the synchronized camera to the embedded host.
The frame remains cached across unchanged tabs. Source/Session guards and cancellation
remain authoritative. Destroying the original owner closes enlarged/export resources.

Only explicit Render & Publish in Save High-Resolution Image creates a Dataset.
Full HD (1920×1080) and 4K (3840×2160) use native offscreen rendering and the current
CORE graphics export-supersampling policy; intermediate pixel/GPU/worker budgets apply.
The PNG includes the current geometry, calibrated axes/grid when enabled, original
scalar-bar palette/limits/label when present, compatible title/legend and opaque
background. No Tk screenshot enlargement. Existing IDs are rejected; no replacement.
CORE `DATASET_FILE_PUBLICATION_API_v1` publishes `image.raster`, binary PNG/image/png
transactionally and verifies SHA-256. Structured metadata retains graph/Variant identity,
source IDs/digests/bindings, exact camera/projection, dimensions, figure calibration,
scalar palette/limits and graphics settings. The normal Dataset GUI lists/reopens it.

Calibrated axes use linear increasing displayed scientific ranges mapped to effective
aspect-scaled world bounds. Original units/labels and scalar mapping are retained.
The native cube axes follow projection, orbit and roll, with camera-calibrated label
margins. Flat source surfaces retain constant per-cell RGB on both triangles of each
original quad; interpolated source colors remain interpolated. No scientific smoothing.
Ticks/grid/font layout follows Native3D's scientific presentation rather than Octave's
pixel layout. Logarithmic/reversed axes still require a nonlinear calibrated coordinate
mapping contract and are rejected, never labeled as linear. The producer bridge
admits its declared `surface`, `mesh`, `contour3`, `scatter3`, `line3`, `trisurf`
or `heatmap` preparation only after the shared source/configuration checks above.
Missing or inconsistent scientific preparation is refused with its actual
diagnostic; an unrelated provider or PNG is never relabelled as compatible
geometry. Transparent figure backgrounds remain unsupported.

## Persistent Session Preview cache

After a successful canonical catalog commit, CORE schedules standard Preview preparation through the existing Script Job Supervisor. Publication success is independent of preparation success. Native2D prepared Plot models, Digitalizer raster/Quality summaries and supported image/PDF/audio derivatives are disposable representations. Unsupported graphical contracts retain an honest descriptive/table Preview. Existing Native3D consultation remains the owner of supported interactive XYZ and prepared 3D scenes.

`datasetPreviewCacheRequest dataset_id ?options? ?callback?` returns a source-bound key and prepares outside Tk. Callback receipts report preparing with the genuine Supervisor state, then ready/error, key, Job ID and cache hit. `datasetPreviewCacheStatus key`, `datasetPreviewCacheCancel key`, `datasetPreviewCacheRead dataset_id key ?allow_stale?`, `datasetPreviewCacheInventory session`, and `datasetPreviewCacheClear session ?keys?` inspect/manage the same owner. `datasetPreviewCacheGenerate` is the worker operation, not a GUI-thread reader. Python/Octave expose `cache_generate`, `cache_inventory`, and `cache_clear`; widget lifecycle operations are host-only.

Entries live only under `Session/cache/dataset_previews/SHA256`. Keys bind canonical identity/content/schema, coordinate/calibration metadata, source revision, rendering code and exact render options. Representation and derived artifacts carry SHA checks. Symlink entries are refused. Missing, stale or damaged entries are regenerated; an explicitly restored stale custom view is visibly labelled previous render. Configurable preparation policy and a default 64 MiB Session budget apply. Clearing/eviction never deletes canonical payloads, Graphs, Workspaces or original images. This subtree is hidden from ordinary Session Files and omitted from portable exports.

Fresh generic curve defaults keep declared `calibration_identity` Variables as
independent calibration grouping dimensions alongside family/curve/trace/replicate
identities. A single enabled compatible numeric rank-one `point_order` Variable
supplies within-series order; multiple such roles require an explicit choice.
Existing genuine Digitizer schema defaults retain their own authority. Variable
IDs, producer names and ad hoc `source_grouping_variables`/`source_order_variable`
metadata do not establish a separate binding contract. Manual grouping remains
available through the existing controls and Graph Series validation.

Saved Preview axes, selections, order and processed-image choice supply omitted
render options. Processed images retain their existing source/lineage checks. Explicit
options take precedence, including `ordering {}` for original acquisition order.
The controls, renderer and cache use the same metadata defaults; the cache binds
their current values before lookup/task coalescing and again before publication.
A changed saved default invalidates an older derivative even when a caller still
holds its resolved options. These are presentation choices; canonical values,
row identities, calibration roles and source images remain unchanged.

Sessions → Preview Cache shows Dataset, representation, generation date, source/render key, size, status and errors and offers refresh, regenerate, clear selected/all and policy. Standard automated previews and explicit custom Render have separate keys. Successful Render saves its exact captured options and cache key as `last_render` in the existing Dataset Preview private metadata. Completion preserves all saved scientific configuration and opaque fields; automatic discovery does not turn default controls into new saved scientific selections. Explicit Apply, axis and processed-image choices retain their existing persistence before requesting Render. Controls and the last-render receipt restore on reopen; changing axes, filters, grouping, calibration or ordering keeps the previous successful frame until explicit Render. Failed/cancelled preparation preserves that frame. Source changes are labelled stale rather than current. Automatic schema reconciliation requires both saved `selections` and `ordering` keys, including legitimate empty values; receipt-only, visibility-only and partial profiles do not acquire scientific defaults.

Before any successful render exists, the Plot placeholder and Source pane show
the same current preparation, cancellation or failure message as the 2D status.
A terminal failure must leave no obsolete Loading/Preparing message in those
initial panes. Once an accepted representation replaces the placeholder, later
status changes preserve its frame and source contents. This is presentation of
the existing lifecycle receipt; it neither validates an unavailable source nor
starts another preparation.

The Digitalizer chart is a resizable retained Plot Dataset native viewport. Visibility changes affect existing XY objects and raster overlay primitives, retain camera/zoom/pan, and start no reader or Job. Visibility preferences are saved after a short idle period. Expensive scientific reads, raster decoding and Quality preparation run through the existing managed execution owner. Session lifetime, generation and source guards reject stale completions; asynchronous status polling does not block Tk. Processed-image choices require verified identity-preserving raster lineage and retain the original source alongside the chosen derivative.

Retained visibility uses the same `_gxtxt.framework.dataset_preview` owner, in
`retained_visibility {version 1 hidden_filters LIST}`. Each entry has exactly
`filter_variable_id`, `predicate not_equal`, and `value`: the captured curve
Variable ID and opaque text curve key must match literally (`01` and `1` differ).
This field is excluded from scientific render options and does not change the
scientific cache-key contract. If absent, the historical
`selections.@hidden_filters` remains readable. A present valid empty list means
show all and overrides that legacy value; reads do not migrate metadata.

Only currently represented curves are patched by a visibility save. Well-formed
hidden identities outside the current scientific subset are preserved as inactive
preferences, without claiming complete publication membership or scanning rows.
The field accepts at most 4096 unique entries, 16384 encoded Tcl string bytes per
curve identity, 1024 per Variable ID, and 1 MiB for the complete preference.
These are saved-preference limits, not canonical data or scientific curve limits.
Malformed, unsupported or oversized preferences produce a local notice and are
not applied or overwritten: the admitted scientific view remains available,
with all its curves initially shown, and further visibility changes in that view
are temporary. No silent truncation or legacy fallback occurs for a present
invalid field.

Toggle and the pending 750 ms save/Release flush compare the representation's
original preparation source with the current source, together with its Session
and widget lifetime. A restored previous representation is not certified using
the source observed at display time. A stale refusal retires its pending timer;
changing scientific settings alone does not invalidate a matching source's
retained presentation. Private preference writes preserve scientific selections,
ordering, axes, schema, types, processed-image choice and unrelated metadata.

Array-only Datasets use a bounded exact storage plane (at most 128×128 original
cells, with earlier dimensions fixed at zero). Canonical Dataset Access remains
its sole reader; typed binary hyperslabs are preferred when the provider supports
them, with the existing values transport retained otherwise. The shared Native2D
C++ adapter computes the finite range and nearest-cell palette without Tcl cell
loops. Signed/unsigned 64-bit range labels remain exact, including values above
2^53; adjacent integers remain distinct in the display normalization. Gray denotes
missing or nonfinite values. PNG encoding uses the configured codec and a temporary
PPM beside the requested output, removed on success or failure. It is an overview,
not a coordinate interpolation or replacement Dataset. Image, PDF and audio
preparation uses the existing configured codecs. Supported mesh formats use the
same Native3D layer contract and installed read-only renderer as live consultation;
the disposable standard frame uses Software policy. Open Dataset retains the
interactive camera, navigation and resize. Missing codecs/native support report
the actual limitation without changing publication success or source bytes.

The retained 2D generation status is independent of an active XYZ overlay.
While XYZ is visible, the shared status reports its actual preparation/frame
state and checks its existing source/configuration contract. A source or mapping
change remains explicitly stale. Exiting XYZ restores the retained 2D status;
this transition does not apply pending 2D options, acknowledge a revision or
request a new scientific Job. An explicit 2D Render keeps its existing meaning.

When the matching shared native adapter is installed, standard 2D cache
preparation resolves the existing grouping policy into a Curve Source batch plan.
It avoids the separate Tcl row-wise combinations scan and per-series Transform
reads. The existing individual request planner remains available to its other
consumers and to older native runtimes. Canonical filters, explicit single-series
confirmation and mandatory grouping roles retain their existing authority.
Transient plans are not persisted as render options: cache identity retains the
actual user selections/order and the renderer implementation. Native source
preparation alone does not establish installed GUI/scientific/performance results.


Preview cache subscriptions use the existing Script Job managed-request owner
with a fixed trusted Tcl worker on supported hosts. Requests have bounded stdin,
timeout/output limits, an owned process group, cancellation and UI lifetime;
there is no additional worker pool. Preparing/terminal receipts disclose
`execution_kind=managed_request`, their actual `request_id` and an empty `job_id`.
A request token is never presented as a durable Job. A cached hit requires no new
execution. Default direct `datasetPreviewCacheRequest` calls retain the existing
durable CORE service Job route, including its real Job identity and persisted
record (CORE services remain excluded from ordinary user Job lists). Platforms
without the required process-group/Tcl tools retain that route.

Subscribers/direct callers joining an existing preparation receive its actual
execution kind. Unsubscribing the final UI consumer cancels only a UI-owned
preparation with no legacy consumer, including consumers waiting on a queued
retry. Cancelled work drains through its existing owner before retrying; malformed
worker responses become terminal errors. The fixed worker validates framework,
Session, request schema, source key and resulting cache entry without evaluating
request data. Normal framework messages are bounded diagnostics, separate from
its control dictionary. It removes the Preview Python launcher from that managed
route; canonical HDF5, remote and Resource Management owners retain their existing
runtime boundaries. No zero-Python or performance claim follows from this change.
# Published raster overlay collection

The existing Digitizer Preview host can use the precompiled CORE overlay
collector when registered in Native2D. It consumes the same canonical projected
Table Stream value chunks (2048 rows), retains exact curve/point lexemes and
first labels, and rejects conflicting repeated raster identities. Graph
Selection remains the predicate authority; Tcl's existing integer admission and
integer sort retain historical behavior. No canonical values, calibration,
source image, public descriptor or vendor Viewer is rewritten.

The existing65536 unique-point limit remains. Retained token payload is bounded
to64MiB and distinct-value validation cache payload to2MiB; these counters exclude
Tcl/allocator bookkeeping. Collection and final sorting execute synchronously in
the caller, normally the existing managed Preview worker. This is not a promised
event-loop latency or total-RSS bound. Missing native support keeps the existing
collector; failed native preparation cannot publish a partial overlay. Canonical
source identity is checked before and after collection, and the outer Preview
cache owns Session/source lifetime. Visibility still uses the retained host.
## Published Quality versus independent host source verification

The installed Curve Digitizer Quality dictionary remains provider-owned and is
retained unchanged. Its reported integrity/digest fields are labeled as provider
results: a provider may measure current bytes or may compare only recorded
registry metadata. In unchanged vendor2.0.9 these fields do not establish live
source-byte verification. CORE does not replace registry SHA meanings or modify
the vendor API to disguise that limitation.

The existing Digitizer Preview representation additionally carries the internal
`host_source_verification` receipt: source Dataset ID, published expected SHA256,
registered canonical expected SHA256, observed SHA256, status, owner/method,
observation UTC time and reason. The ordinary successful local path reuses
`SESSION_INSPECTION_API_v1`'s verified Dataset Payload receipt already needed for
the source raster; it adds no second routine source hash pass. `verified` requires
a valid publication SHA, registered canonical identity and successful owner
verification matching both expected identities. A publication mismatch is
`changed`; the original aligned-overlay refusal remains in force. Published
curve data, point ordering, diagnostics and uncertainty are not rewritten.
An absent or malformed registered canonical identity or observed digest is
`unverified`, with an explicit reason; it is not evidence that source bytes
changed. The ordinary payload owner already refuses invalid registered digests,
and the successful-receipt branch retains this defensive distinction.

Only after a failed payload check may the existing linked-source/resource owner
measure current bytes for explanation. A measured mismatch is `changed`; a later
matching observation cannot waive the earlier canonical-owner refusal and stays
`unverified`. Missing/rejected sources retain the actual owner reason. This local
raster route reports `unsupported_remote` rather than asserting a remote source
was checked locally. Missing/invalid publication identity is `unverified`.

The Quality host shows this CORE receipt separately from provider fields. Old
numeric Quality row selectors remain unchanged; added rows use stable semantic
IDs (`host_source_status`, `host_source_digest`, `host_source_expected`,
`host_source_registered`, `host_source_method`, `host_source_checked_at`,
`host_source_reason`). Source/cache invalidation qualifies both the provider's
old report and the host's old observation as previous-render data. A receipt is
evidence at its preparation epoch, not continuous verification. Source/Session
lifetime, linked identity and Preview cache remain owned by existing services.
This is an internal representation extension, not another public data pipeline.


TASK210 failure-inspection extension: each `datasetPreviewCacheInventory` row
also contains `execution_kind`, `job_id` and `request_id`, with empty defaults.
Error rows project only identities already retained by the same cache owner in
its preparation-failure record or current terminal outcome. Execution kind is
`durable_job` or `managed_request`; only a bounded ASCII Job token or a bounded
`job-request-N` token is returned for its matching kind. Unknown kinds, missing
or malformed identities remain empty. These fields support the existing public
Job engineering inspection; they confer no Job authority and do not expose logs,
parameters or scientific data. No additional cache file is read or written.
A retained request ID is historical and does not imply a still-live request.
The cache-owner fingerprint includes this source file: updated source can make
previous prepared representations stale, following the existing normal source
identity policy. This diagnostic change does not fix a failed Render or establish
its cause, geometry support, native3D behavior or performance.
