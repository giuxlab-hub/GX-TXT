# GX-TXT Plot Dataset 3D API v1

SPDX-License-Identifier: GPL-3.0-or-later

This public API provides the current persistent interactive-3D operations. Consumers may alternatively use the complete `PLOT_DATASET_API_v3` facade for the same interactive operations.

## Workflow

```
canonical Dataset → persistent plot.dataset.xyz Variant and bindings
→ Plot Dataset preparation and scientific interpretation
→ independent Session-owned Viewer representation and VTP artifacts
→ shared Native 3D renderer
```

Activate with `::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_3D_API_v1`.
The namespace `::GX::PlotDataset3DAPIv1` exposes:

```tcl
apiInfo
buildScene plotRef
openInteractive plotRef
refreshInteractive plotRef
sources
sourceInfo plotRef
sourceFingerprint plotRef
representations
syncStatus representationId
activateRepresentation representationId
syncInteractive representationId
```

`plotRef` is the persistent Plot Dataset reference dictionary with
`graph_id=plot.dataset.xyz` and `variant_id=<stable Variant ID>`. Configure
its X/Y/Z bindings and plot type through Plot Dataset API v3 or the normal
Plot Dataset editor before calling the 3D API. The viewer does not infer
scientific meaning from arbitrary Dataset columns.

`buildScene plotRef ?representationId?` first renders the existing static
plot, then exports prepared scientific VTP geometry into independent Viewer
resources. With no representation ID it creates a new persistent Interactive
Document; with an existing exact representation ID it performs explicit Sync.
It returns the plot reference, plot type, source identity, representation ID,
layer IDs, scene directory, source fingerprint and static graph artifact.
`openInteractive` creates and opens a new view. `refreshInteractive` is an
explicit request to synchronize an existing matching view and open it.

The source graph/Variant identity and Viewer representation identity are
separate. One source may have several views. The representation document
stores `source_module_id`, `source_graph_id`, `source_variant_id`, the public
plot reference, current source fingerprint, last successful Sync fingerprint,
source Dataset identity, Viewer scene and layers. The source fingerprint
hashes persistent graph configuration, stable bindings and canonical Dataset
SHA-256 values; render artifact paths and mtimes are excluded.

Changing the graph does not rebuild any existing view. `syncStatus` reports
`SYNCED`, `OUT OF SYNC`, or `SOURCE MISSING` by resolving the exact source
after each request, including after Session reopen. Only an explicit Sync
rebuilds scientific geometry. It preserves valid Viewer camera, projection,
clipping, background, lighting and matching layer presentation. Deleting the
source does not delete the representation or its Viewer-owned VTP artifacts.

Supported current XYZ plot types: `scatter3`, `line3`, `surface`, `mesh`,
`contour3`, `trisurf`, and `heatmap`. Scatter is a point cloud; line and
contour are ordered line geometry; surface/mesh/heatmap form sampled surfaces;
trisurf supplies triangular connectivity. Where a scalar variable is bound,
VTP carries scalar values for coloring. A sampled mathematical function is
handled by publishing its samples as a Dataset and configuring a surface or
mesh Variant. A 3D scalar grid can use the generic Viewer Provider isosurface
layer with a canonical VTI Dataset.

The existing graph PNG/PDF workflow remains the static representation.
Interactive layers are additional Session presentation state and can be
rotated, zoomed, clipped, hidden, made translucent, saved and reopened through
Viewer Provider/Native 3D. Snapshot layers retain source identity for
provenance while their hash-checked Viewer artifacts remain inspectable if the
source graph is later removed. A graphical OpenGL display and
the packaged VTK/OCCT backend are needed for interactive display.


## Read-only preview export

`previewExportCommand plotRef callerOwnedTemporaryDirectory` returns the read-only
command for the already rendered exact XYZ Variant. It uses prepared cache and
recorded runtime/effective graphics settings, applies the same normal `pd_render_3d`
presentation, and exports transient VTP plus a typed scene descriptor. No static
render, Viewer provider enable, persistent Document, Session commit or Dataset
publication occurs. It diagnoses changed source/bindings/preparation/presentation
before reuse. This is intentionally distinct from explicit persistent `buildScene`.
See the documented preview constraints and the current [GUI guide](GUI_MANUAL.md) for axis/layout behavior and supported source types.


## Native3D preview controls and scientific figure publication

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

## Dataset coordinate policy (3.18 / dev097)

Static XYZ rendering and its calibrated Native3D Plot preview share captured public
Dataset display units and view factors/pivots. Preview validates the successful
static coordinate revision receipt; changed metadata requires rerender. The VTP
contains displayed physical coordinates with no numerical calibration or view-factor
multiplication. Limits/camera/aspect express magnification, and the caption reports
its source-unit pivots. The separate persistent canonical Viewer representation
retains its own geometry/presentation lifecycle.
