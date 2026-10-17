# CORE Dataset Viewer API v1

This additive authority resolves canonical Dataset identity before choosing a
consultation surface. It does not register a module/provider or require enabling
an analysis/viewer plugin. Existing API signatures remain available.

## Public Tcl entry points

- `::GX::datasetViewerDescribe datasetId`: validates the registered payload and
  SHA through Session Inspection; returns `api_id`, `dataset_id`, `contract`,
  `format`, `media_type`, `target`, `revision`, `read_only`, `implicit_publication`.
  Targets are scientific, mesh, structure, pdf, image, audio, text, sketch or
  unsupported. The sketch target is the established explicitly editable draft
  workflow; all other targets are consultation only. No payload path is returned.
- `::GX::datasetViewerOpen datasetId`: requires Tk and an open Session. Opens the
  selected CORE consultation window; Sketch delegates to guarded Curve Workbench.
- `::GX::datasetViewerClose window`: idempotent host cleanup: streams, timers,
  native scene, process pipes, isolated workers, images and temporary artifacts.
- `::GX::scientificDatasetAxes datasetId`: returns eligible rank-one numeric
  variable IDs and only unambiguous semantic default X/Y choices.
- `::GX::scientificDatasetPreview datasetId xId yId output ?member?`: creates an
  explicit caller-owned PNG using Curve Source/Native2D. Its receipt includes
  source-row identities, reduction and breaks. Omitted member retains the unfiltered one-series view; an explicit member applies a read-only source filter.
- `::GX::scientificDatasetViewerOpen datasetId` and
  `::GX::meshDatasetViewerOpen datasetId`: typed convenience entry points.

The integrated Preview uses this same dispatch and existing media descriptors.
Pending remains an acquisition source: Preview is available, canonical Open is
not. An unsupported/corrupt source receives a diagnostic, never a made-up graph.

## Scientific semantics and budgets

Schema v3 supplies names, types, units, dimensions and coordinate relationships.
Curve Source owns finite-value handling, original ordering, source mapping and
bounded reduction (4096 displayed points/trace). Up to 16 explicitly selected
traces overlay only when their declared units and coordinate presentation policies
agree. Explicit Dataset display-unit conversion uses CORE. No resampling, sorting,
smoothing or canonical publication occurs. Families use
explicit CORE read-only filter views, independently rendered member traces.
Shared filter discovery streams 2048 rows/chunk, with a 100000-row scan and 1024 distinct values per variable. Incomplete scans are labelled; only an explicit selection enables separate family curves.

Canonical table pages use Dataset Preview/Table Stream. Array inspection uses
Dataset Access hyperslabs: explicit starts/counts in storage order, at most two
nonsingleton dimensions, at most 16384 original cells. Coordinate variables supply
physical tick labels where their rank/dimension mapping is explicit; otherwise
storage indices are labeled. Nonfinite cells are gray. Preview selects the first
eligible array's bounded plane and states its starts/counts; Open provides explicit
selection. Neither path silently flattens an array into an XY trace.

Curve cursors show canonical one-based row identity. The underlying Curve Source
`source_rows` remains zero-based. Table-page row labels are one-based.

## Geometry, fields and structural consultation

CORE owns `core/native3d/gx3de_viewer_tcl.cpp`, its compiled transport and worker.
The existing Viewer Provider retains compatible use of the same transport. Mesh
consultation starts that worker in `readonly` mode: CAD, gizmo, plane-edit and
other mutation command classes are rejected. Native3D/VTK supplies STL, OBJ, STEP,
VTP, VTU and VTI intake, rendering, camera, surface/wire/point representation,
scalar array selection and isosurfaces. The transport exposes actual bounds,
counts and array descriptions. Rendering uses existing graphics resource budgets
and an isolated address-space-limited worker; Cancel terminates it.

Raw undeclared mesh units are never guessed. STEP's file units are interpreted by
OCCT; the normalized coordinate unit is not currently exposed by the summary.
CIF, XYZ/PDB/SDF and CUBE reuse the existing scientific decoders now owned by
CORE. Original bytes are preserved; derived atoms, inferred bonds, cell and CUBE
midplane artifacts are temporary. Their interpretation/atom information is
available in the scrollable inspection. Structural display choices are fixed;
camera interaction remains available. CUBE scalar colors use electron_density;
field units are retained as source declarations, not invented calibration.

## Media and lifecycle

PDF uses the shared Poppler/PDF canvas, actual active-page dimensions and rotation,
with at most eight cached PNGs/64 MiB; an oversized current PNG is removed after
loading. Image consultation supports fit/zoom/Pan, a 64-million-source-pixel and
32-million-display-pixel budget. Audio shows the declared stream's first channel,
min/max envelope and source sample rate with explicit normalized PCM amplitude;
raw PCM requires the producer's format/rate/channel metadata. It does not mix
channels, resample, play audio or imply physical calibration. Text inspection is
bounded at 256 KiB and reports truncation.

Open hosts bind Session lifetime and payload/schema/registry revision. A one-second
watch closes source/schema-stale windows; scientific coordinate-policy changes
refresh retained display samples through CORE. Media children are reaped through
process-pipe EOF.
Closing cancels asynchronous work and removes temporary displays. No consultation
UI contains a source edit, Save, Commit or publication path.

## Script Bridge

Python and Octave expose read-only discovery:

```python
info = gxtxt_api_call('DATASET_VIEWER_API_v1', 'describe',
                     [{'dataset_id': 'measurement'}])
```

The result is a portable descriptor. GUI opening is deliberately a Tcl/Tk host
operation; scripts already have canonical access/preview APIs for numerical work.

Filtered sources with unknown row counts use the additive optional third
`curveSourceOpen session request ?progressCommand?` argument. CORE invokes the
callback at bounded counting boundaries; a callback error cancels with stream/view
cleanup. The scientific viewer binds callbacks to its request generation and Session,
so Cancel, replacement requests and closing also interrupt this opening phase.
Existing two-argument calls retain their prior behavior.

Filtered family opening reuses the existing synchronous Dataset Transform planner.
The optional Curve Source progress callback does not make that earlier planning
stage asynchronous; cancellation takes effect at subsequent cooperative counting
or display boundaries. See the technical report for this unresolved latency limit.

Dev072 lifecycle correction: widget destruction precedes per-window state clearing,
so Tk listvariable traces cannot recreate selector state after Close.

## dev073 Preview host and explicit filters

See `../DATASET_PREVIEW_CONTROLS_dev073.md`. The active inspection choice remains
the only Dataset selection authority. Session token, identity, schema/payload and
metadata stamp plus view epoch guard late completions. Catalog events trigger
coalesced consultation refresh; effective per-Dataset stamps avoid heavy duplicate
renders. Explicit Clear persists for that Session/Dataset until Render or a new
activation. Editors retain their original identity locks.

CORE shared helpers: `scientificDatasetFilterDimensions id ?rowBudget? ?valueBudget?`,
`scientificDatasetFilterRequests dimensions selections separate`, and
`scientificDatasetPreviewFiltered id x y output requests`. These use Table Stream,
Curve Source and Native2D; receipts retain source rows/breaks and add trace_count
and individual trace receipts. Exact source values use in_set predicates and AND.
No normalization, sorting, publication or inferred grouping is performed.

The embedded mesh host retains one isolated read-only worker while Preview is
active and routes cube picks/clicks, preset fit_scene and navigate to existing
Native3D commands. Preview-only cube size is 80px with a 40px margin; full render
presentation remains unchanged. Geometry bounds exclude the decorative cube.

Categorical discovery now consults `DATASET_SCIENTIFIC_PROFILE_API_v1` first.
Normal CORE publication/registry commits maintain its existing Metadata resource.
Older Datasets use one controlled bounded cached read without consultation writes.
`graphSeriesDistinctValues` also reuses complete persisted profiles.

On the tested NVD9/Nouveau backend, Auto policy in the small Preview uses the
existing Mesa Software renderer for readable colored cube targets. This is scoped
to the embedded Preview. Explicit Hardware/Software choices and the full Viewer
retain their configured policy. The Native3D kernel binary and all public ABI
remain identical to dev072; no replacement cube, renderer or rotation math.

## dev087 numerical XYZ

The existing `meshDatasetViewerOpen id ?previewWidget? ?request?` accepts an additive
CORE compact-host request. Plots and numerical XYZ share this worker/state/cache,
with no new renderer or persistent Viewer Document. Numerical selectors are explicit
rank-one nontext canonical IDs. Table Stream v3 reads at most 100000 original rows,
2048 per chunk; at most 12000 finite triples retain one-based source-row IDs in VTP.
No implicit topology, interpolation, data conversion or publication occurs. Last
2D content is retained, and remains controlled by 2D Render. Family-filtered XYZ is
currently diagnosed rather than silently stripped. See the dev087 guide.


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

## dev089 canonical selector display

Numerical axis selectors display canonical name, optional unit and supplemental
stable Variable ID, resolved by `datasetVariableById` from the current public
schema. Existing numerical selections remain stable IDs. A GUI choice resolves
against the current eligible schema and Session token, without parsing `v000N`,
using raw column positions, or storing another label-to-ID mapping. The projection
is rebuilt on Dataset/Session changes. Ambiguous default axes remain unselected
until the user chooses them; transient axis choices do not add Session persistence.

Numerical XYZ uses the modern Native3D screen-space orientation indicator. It is
a camera orientation cue, not an interaction pivot or scientific origin. The
world-origin triad is disabled for this view; scientific coordinates, bounds,
units, camera navigation and the retained 2D preview remain unchanged.

## dev095 independent scientific axes

Scientific consultation explicitly selects Native2D `aspect auto`; calibrated
Native geometry defaults remain unchanged. The standalone Viewer exposes an
explicit calibrated equal-aspect toggle. Fit compares the current X/Y, overlays
and filters with the rendered request, reloads changed selections, and otherwise
fits the existing scene. Pan/zoom/resize preserve navigation. Scientific Preview
receipts add `view_bounds`, `axis_aspect=auto` and combined `displayed_points`.
Curve Source's ordered extrema/row/gap policies remain unchanged; no data conversion.


## Persistent scientific coordinate presentation

XY Preview and the full scientific Dataset viewer consume the verified coordinate
context from [Dataset Metadata API](DATASET_METADATA_API_v1.md). Explicit compatible
display units apply to shown points, ticks and readouts. Persistent per-variable
magnification/pivot changes the fitted view range; it does not multiply the samples.
The renderer calls the same bounded CORE snapshot conversion/view-range operations
used by Workbench. Original canonical samples and source-row identities remain
retained. Reprojection always starts from those original samples.

`scientificDatasetPreview` adds `coordinate_presentation` with schema
`gxtxt.scientific_coordinate_presentation.v1`, captured context, ordered Variable
IDs, display units, view factors, canonical pivots, reference/display bounds and
per-axis CORE range receipts. `calibration_applied=0` and
`source_values_modified=0` distinguish presentation from numeric materialization.
The PNG and receipt use the same final viewport. Repeated Render/Fit recomputes
from the original fitted range, so magnification does not compound. In the full
viewer, unchanged-policy refresh preserves additional transient zoom. A changed
policy reprojects retained bounded samples and rebuilds its default viewport.

Numeric calibration remains an explicit effective-coordinate/derived-Dataset
operation. The status text states that it is not applied. Canonical table pages
remain unchanged. Boolean axes outside the real-number coordinate API retain
canonical display; no alternate numeric schema is fabricated. Shared-axis overlays
require matching coordinate relations, display units, factors and pivots. Different
policies must be inspected separately.

Scientific windows tolerate only structured-metadata bookkeeping changes in the
source stamp, then reread/validate the coordinate context. Actual source bytes,
filesystem identity, canonical schema, Session lifetime and all other registry
fields retain strict invalidation. Preview's existing metadata-inclusive cache
signature triggers regeneration after a policy edit. The source selector labels
identify source units explicitly; displayed units appear with the rendered axes.


## dev097 direct XYZ coordinate policy

Direct numerical XYZ reads `DATASET_METADATA_API_v1` once for its verified source.
Its temporary VTP contains displayed units; retained canonical triples and original
source rows remain unchanged. `xyzDisplayReceipt.coordinate_presentation` records
`gxtxt.xyz_coordinate_presentation.v1`, captured context, per-axis reference/result
ranges, policies and view transform, with calibration/source-mutation flags false.
The public CORE snapshot operations own physical conversion and pivot/range.

The normalized scientific cube uses increasing displayed ranges and a fixed
camera. Per-axis magnification changes this view frame instead of multiplying
source samples or refitting transformed geometry. Calibrated axes/grid and their
labels use those same display units. Warm activation, camera reset and resize
retain the existing scene; changed source/metadata requires a new activation.
Numerical calibration stays explicit and is labelled unapplied. Existing bounded
sampling/filter limitations remain unchanged.

HMS readers return seconds regardless of the declared source h/min/s unit. The
shared XY and XYZ consumers convert only their presentation buffers through the
public elapsed-time API before using source-frame coordinate settings. Retained
numeric samples remain seconds, including repeated reprojection.
