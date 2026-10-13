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

Script Bridge `DATASET_PREVIEW_API_v1/page` takes Dataset ID and an options
struct, returns the same bounded model, and never exposes a provider path.
Preview is read-only. A displayed page is not the input for fit-all or publication.

The dev087 GUI adds optional Z and read-only XYZ scatter beside existing X/Y Render.
It consumes the same canonical schema/Table Stream and shared Native3D consultation
host. The paged table API and its 1000-row bounds remain unchanged. XYZ limits and
source-row reduction receipts are documented in DATASET_VIEWER_API_v1 and the
shared Native3D preview guide; no scientific Dataset is created by activation.


## Dev087 manual-acceptance scientific figure correction

`native3DPreviewAcquire` retains its existing shared DatasetViewer host/worker and
RAM frame. Plots' eligibility control is a placed canvas child, with no layout row;
`PLOT_DATASET_API_v3.previewCompatibility ref` gates supported prepared XYZ Variants.
No persistent Viewer Document is needed. Ordinary 2D/static double-click is unchanged.
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
mapping contract and are rejected, never labeled as linear. Other providers/base graphs
need an exact prepared-scene identity API. Transparent figure backgrounds remain unsupported.
