# Shared interactive 3D preview — dev087

In Plots, select an already rendered Plot Dataset XYZ Variant, then click the small **3D** icon inside the canvas.
The original PNG stays in its existing canvas. The interactive layer appears above
it in that same container. ◀/▶ rotate horizontally; ▲/▼ rotate vertically; ■ restores
the captured initial Native3D camera and frame; ↶/↷ roll around the viewing direction; **✕** immediately reveals the
unchanged PNG. These controls have no Navigation Cube. Existing mesh/structure
Dataset previews retain their working cube and navigation interface.

Dataset → Preview retains its X/Y Render workflow and adds an explicit Z selector
and **⟳ 3D XYZ**. All three selectors use canonical, distinct numerical Variable IDs.
The resulting representation is scatter: no inferred connectivity or interpolation.
It scans at most the first 100000 canonical rows in 2048-row chunks and displays at
most 12000 finite original triples. The caption states total/scanned/display counts,
stride, IDs and declared units. Display reduction is never a scientific Dataset.
The last 2D view remains intact; 2D Render explicitly updates its X/Y mapping.
For the compact XYZ mode, clear actual row predicates first. Independent 2D series
grouping and within-series ordering do not restrict unfiltered XYZ. Meaningful row
predicates produce a diagnostic and are never silently discarded.
No Analysis module, Viewer Document or publication is required by Dataset preview.

The dev109 retained Preview places XYZ in the visible Plot pane. It can open even
before a valid 2D curve has been rendered, provided all three canonical numerical
axes are selected. Exit reveals the previous 2D frame, or returns to Source image
if there is no valid 2D frame. Render explicitly returns to 2D. These transitions
use the existing scene/worker owner; they do not change the source Dataset.

Plots uses the graph's existing prepared cache and saved rendering configuration,
through Plot Dataset API v3/v1 and the normal `pd_render_3d` scientific renderer.
It retains exact Variant/source bindings, prepared transforms/reductions, graph
geometry/type, display-unit and Z-level conversion, limits, original camera/view,
projection/FOV, effective aspect, scalar values, exact sampled colormap and range,
titles, labels, legend entries and background. Aspect is a read-only Native layer
transform; source coordinates and scalar arrays remain unchanged in the temporary
VTP. A changed source/binding/configuration requires rerendering before a new
preview can reuse the existing static preparation. Preview never rerenders the
static PNG or creates persistent scientific presentation content.

The shared CORE host retains at most two compact owners, with one source per owner.
Plots and XYZ use the same authority, read-only worker, Native scene, graphics policy,
derived cache and RAM photo. Tab unmapping retains camera and last frame. An unchanged
return performs no Dataset stream, preparation, geometry rebuild, worker restart or
PNG write. Genuine viewport resizing may rebuild the same scene at its new size.
The existing Dataset/Session stamps plus graph/configuration/resource stamps guard
both watches and replies. Exit retains a completed scene; changing source, explicit
release, failure or Session lifetime invalidation closes workers, streams, timers,
images and temporary files. Cancel during preparation also reaps the owned export
process group. Original previews remain available after failures.

Renderer differences are explicit. Native3D renders calibrated scientific
axes, numeric ticks and grids with its own label layout. Legend box positioning,
advanced annotations/layout typography and marker shapes differ from Octave.
Compatible title/legend and the exact original color ramp are rendered natively. Transparent backgrounds require a CORE alpha-background API and are diagnosed.
Logarithmic/reversed axes are rejected: CORE needs a calibrated
coordinate/axis mapping API before those can be faithfully transferred. Persistent
Plot Dataset XYZ Variants are supported; other providers, detached rendered-only
clones and base graphs need their own public prepared-scene/identity contract.
The preview intake bound is 128 MiB prepared cache, 16 series and 200000 display
points/400000 cells; over-budget/nonfinite or unsupported geometry preserves static
mode and diagnoses the limitation. Existing published Viewer workflows remain
separate explicit actions. The new bridge commands are delivered for the current
Debian runtime; other platforms require a matching compiled CORE transport.


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


## Dataset coordinate settings in dev097

Open **Dataset coordinates** in Preview to choose each compatible display unit,
view factor and source-unit pivot, then activate **3D XYZ**. The axes show physical
displayed values. The legend identifies factors and pivots; numerical calibration
is unapplied. A larger view factor narrows that axis around its pivot. Points
outside the visible range remain in the original Dataset and retained preview.
Use the axes/grid button to hide or restore scientific axes. Camera navigation,
reset and resizing keep the Dataset coordinate policy. After editing metadata,
activate XYZ again to obtain a current source-verified frame.

The same policies apply to XY Preview/scientific Viewer and Plot Dataset. Explicit
Plot graph units and limits take precedence. None of these display choices edits
scientific samples or silently materializes calibration. Elapsed-time values use
the public seconds boundary and correctly display requested h/min/s units.
