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

Sessions → Preview Cache shows Dataset, representation, generation date, source/render key, size, status and errors and offers refresh, regenerate, clear selected/all and policy. Standard automated previews and explicit custom Render have separate keys. Successful custom Render persists its exact options and cache key through Dataset Preview Configuration. Controls restore on reopen; changing axes, filters, grouping, calibration or ordering keeps the previous successful frame until explicit Render. Failed/cancelled preparation preserves that frame. Source changes are labelled stale rather than current.

Before any successful render exists, the Plot placeholder and Source pane show
the same current preparation, cancellation or failure message as the 2D status.
A terminal failure must leave no obsolete Loading/Preparing message in those
initial panes. Once an accepted representation replaces the placeholder, later
status changes preserve its frame and source contents. This is presentation of
the existing lifecycle receipt; it neither validates an unavailable source nor
starts another preparation.

The Digitalizer chart is a resizable retained Plot Dataset native viewport. Visibility changes affect existing XY objects and raster overlay primitives, retain camera/zoom/pan, and start no reader or Job. Visibility preferences are saved after a short idle period. Expensive scientific reads, raster decoding and Quality preparation run in managed Jobs. Session lifetime, generation and source guards reject stale completions; asynchronous status polling does not block Tk. Processed-image choices require verified identity-preserving raster lineage and retain the original source alongside the chosen derivative.

Array-only Datasets use a bounded exact storage plane (at most 128×128 original
cells, with earlier dimensions fixed at zero). Its nearest-cell PNG retains the
original finite value range; gray denotes nonfinite values. It is an overview,
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
