# Plot Dataset API v3 — current public facade

The dev096 Builder adapter adds host-only
`renderTransientIndependentCurves2D series label destination`: each of 1..64
series has its own finite `x_values`, `y_values`, `label`, `x_unit`, `y_unit`;
total points are bounded at 200000. It uses the existing transient snapshot
worker and 2D renderer and creates no Dataset/Graph/Workspace. Scripts do not
gain a filesystem destination operation. Optional PlotSpec v2 series fields
`source_row_ordinals` and `source_row_continuity` preserve exact selected-row
display and explicit gaps; old specs and the default continuity policy retain
their previous behavior. Full source values remain canonical and immutable.

GX-TXT 0.9.8.10-dev hosts this API in `plot.dataset` 3.12.6. Activate only
`::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3` for a new
consumer. The namespace is `::GX::PlotDatasetAPIv3`. It loads its stable v1/v2
dependencies as needed; callers do not activate v2 separately.

API version and persisted data schema are separate. Normal declarative plots
still use `PLOT_DATASET_PLOTSPEC_v2`. Existing public APIs v1 and v2 remain
supported with their prior signatures and behavior. v3 delegates to them;
it does not copy the renderer or the approximately 1,400-line v2 PlotSpec
implementation.

## Declarative plots

The following v3 calls delegate directly to the same-named v2 operation and
preserve its arguments, return value and error behavior:

`newSpec`, `validateSpec`, `createPlotFromSpec`, `applySpec`, `saveSpec`,
`loadSpec`, `reconcilePersistentPlots`, `deriveSpec`, `removeSpec`, `readPlot`,
`setSeriesPresentation`, `multiPanelEnabled`, `setMultiPanel`, `panelIds`,
`panelInfo`, `addPanel`, `removePanel`, `movePanel`, `setPanelTitle`,
`setPanelAxis`, `setSeriesPanel`, `plotRefForArtifact`,
`panelIdsForArtifact`, `render`, `rerender`, `artifacts`, and `openEditor`.

`capabilities`, `supports` and `requireCapability` include all v2
capabilities and the v3 snapshot and interactive capabilities. `apiInfo`
reports API version 3 and the current module version.

For existing persistent graphs, v3 also delegates the stable v1 lifecycle:
`createPlot`, `openPlot`, `deletePlot`, `setPlotEnabled`, `setConfig`,
`getConfig`, `setTitle`, `setSeries`, `getSeries`, `listSeries`,
`removeSeries`, `setSeriesEnabled`, `moveSeries`, `setSeriesOrder`, and
`renderCommand`. Normal new 2D and 3D graphs should use a PlotSpec.

`upsertPlotFromSpec producerModuleId providerKey spec` gives a producing
module a stable graph/Variant identity across reruns. The key must begin
with `producerModuleId:`. Plot Dataset finds its own matching Variant or
creates one, applies the validated PlotSpec, and returns the public plot
reference. Modules do not read or edit private Variant registries.

```tcl
::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
set spec [::GX::PlotDatasetAPIv3::newSpec -graph_id plot.dataset.xy -title "Result"]
# Fill the PlotSpec's panels with stable Dataset and Variable IDs.
set ref [::GX::PlotDatasetAPIv3::createPlotFromSpec $spec variant]
::GX::PlotDatasetAPIv3::render $ref
set artifact [dict get [::GX::PlotDatasetAPIv3::artifacts $ref] graph_artifact]
```

## Interactive 3D graph sources

`interactiveSources` enumerates resolvable persistent 3D graph/Variant
references. `interactiveSourceInfo plotRef` returns the graph configuration,
stable X/Y/Z and optional Family/Color bindings, source Dataset SHA-256 and a
deterministic source fingerprint. No PNG/PDF filename is source identity.

`buildScene plotRef ?representationId?` asks Plot Dataset to prepare and export
scientific VTP geometry. Without a representation ID it creates an independent
Viewer representation; with the exact existing ID it explicitly synchronizes
that representation. `openInteractive plotRef` creates and opens a new view.
`refreshInteractive plotRef` synchronizes an existing matching view when one
exists. The dedicated `PLOT_DATASET_3D_API_v1` remains supported and is the
implementation behind these convenience calls.

`interactiveRepresentations` lists persistent Viewer representation IDs,
plot references and status. `interactiveStatus representationId` returns one
of `SYNCED`, `OUT OF SYNC`, or `SOURCE MISSING`. `activateInteractive
representationId` makes an existing representation the active Viewer scene.
`syncInteractive representationId` explicitly rebuilds it from its exact
source and opens the result. `sourceFingerprint plotRef` exposes the current
authoritative source digest.

The source graph/Variant and Viewer representation have **separate persistent
identities**. One source may have multiple views. Source changes leave each
existing view unchanged and report `OUT OF SYNC` until the user invokes Sync.
Deleting the exact graph/Variant reports `SOURCE MISSING`; the independent
derived Viewer artifacts and presentation remain saved. A successful Sync
preserves valid camera, projection, clipping, background, lighting and
compatible layer presentation, then records the new last-sync fingerprint.

## Detached snapshots and point identity

The existing v3 calls remain: `captureForArtifact artifact destinationDir`
captures a live graph's prepared scientific data into a detached HDF5
snapshot; `renderSnapshot cloneDir graphId` renders that snapshot without
reading the original Dataset; `writePointIndex artifact destination` writes
displayed 2D points with exact canonical source-row identities. The caller
owns the destination and cleanup. An existing valid render cache is required
for capture and point indexing.

Task 003 adds `renderTransientOverlay` and `renderTransientCurve3D` to the provider facade for unpublished scientific previews. See `plugins/modules/plot.dataset/PLOT_DATASET_API_v3.md` for the public signatures.

## Script Bridge operations (GX-TXT dev-037)

Octave/MATLAB and Python call the following positional operations through `gxtxt_api_call('PLOT_DATASET_API_v3', operation, arguments)`. `create_plot` uses the normal `createPlotFromSpec` path and accepts a PlotSpec, `base` or `variant`, and optional source Variant; it does not require producer identity. `upsert_plot` remains producer-owned and prefixes its provider key with the current script module ID. Plot/Variant creation, deletion, enabled state, Graph Series presentation, and `apply_spec` persist through the public framework lifecycle. `save_spec`, panel edits, and series placement save the existing PlotSpec; they do not implement a second layout engine.

`render` and `rerender` return the public execution result with nested `artifacts`; `artifacts`, panel information, interactive source information and representation results retain nested dictionary/list structure. Empty list results are returned as script cells/lists. `save_spec` returns integer `1` on success instead of a private PlotSpec filename. A script may delete only a Variant; base plots are disabled with `set_plot_enabled`. `open_plot` opens a persistent graph reference, not a GUI window. `interactive_sources`, `interactive_source_info`, `interactive_representations`, `source_fingerprint`, and `interactive_status` are read-only discovery calls. Existing `build_scene` creates or synchronizes a persistent representation, and `sync_interactive` synchronizes it and opens the Viewer; these two mutating public calls are also registered. Separate `openInteractive`, `refreshInteractive`, and `activateInteractive` GUI actions remain host-only.

| Script operation | Public v3 mapping | Positional arguments | Result |
| --- | --- | --- | --- |
| `api_info` | `::GX::PlotDatasetAPIv3::apiInfo` | none | descriptor struct |
| `new_spec` | `::GX::PlotDatasetAPIv3::newSpec` | `graph_id`, `title` | PlotSpec v2 struct |
| `validate_spec` | `::GX::PlotDatasetAPIv3::validateSpec` | `spec` | logical |
| `create_plot` | `::GX::PlotDatasetAPIv3::createPlotFromSpec` | `spec`, `kind`, `source_variant` (optional) | plot reference struct |
| `upsert_plot` | `::GX::PlotDatasetAPIv3::upsertPlotFromSpec` | `provider_key`, `spec` (producer is the current script module) | plot reference struct |
| `read_plot` | `::GX::PlotDatasetAPIv3::readPlot` | `plot_ref` | plot record, including a nested `plotspec` for 2D |
| `render` | `::GX::PlotDatasetAPIv3::render` | `plot_ref` | render result struct |
| `artifacts` | `::GX::PlotDatasetAPIv3::artifacts` | `plot_ref` | artifact struct |
| `build_scene` | `::GX::PlotDatasetAPIv3::buildScene` | `plot_ref` | representation struct |
| `interactive_status` | `::GX::PlotDatasetAPIv3::interactiveStatus` | `representation_id` | status string: `SYNCED`, `OUT OF SYNC`, or `SOURCE MISSING` |
| `sync_interactive` | `::GX::PlotDatasetAPIv3::syncInteractive` | `representation_id` | scene struct; also opens the Viewer |
| `rerender` | `::GX::PlotDatasetAPIv3::rerender` | `plot_ref` | render result struct |
| `apply_spec` | `::GX::PlotDatasetAPIv3::applySpec` | `plot_ref`, `spec` | updated plot record; 3D returns its plot record |
| `load_spec` | `::GX::PlotDatasetAPIv3::loadSpec` | `plot_ref`, `derive_if_missing` (optional) | PlotSpec struct |
| `save_spec` | `::GX::PlotDatasetAPIv3::saveSpec` | `plot_ref`, `spec` | integer `1` on success |
| `remove_spec` | `::GX::PlotDatasetAPIv3::removeSpec` | `plot_ref` | integer `1` if removed, else `0` |
| `open_plot` | `::GX::PlotDatasetAPIv3::openPlot` | `graph_id`, `variant_id` (optional) | plot reference struct |
| `delete_plot` | `::GX::PlotDatasetAPIv3::deletePlot` | `plot_ref` | integer `1` on success |
| `set_plot_enabled` | `::GX::PlotDatasetAPIv3::setPlotEnabled` | `plot_ref`, `state` | integer `0` or `1` |
| `set_series_presentation` | `::GX::PlotDatasetAPIv3::setSeriesPresentation` | `plot_ref`, `series_id`, `fields` | series struct |
| `multi_panel_enabled` | `::GX::PlotDatasetAPIv3::multiPanelEnabled` | `plot_ref` | integer `0` or `1` |
| `set_multi_panel` | `::GX::PlotDatasetAPIv3::setMultiPanel` | `plot_ref`, `state` | integer `0` or `1` |
| `panel_ids` | `::GX::PlotDatasetAPIv3::panelIds` | `plot_ref` | cell of panel IDs |
| `panel_info` | `::GX::PlotDatasetAPIv3::panelInfo` | `plot_ref`, `panel_id` | panel struct |
| `add_panel` | `::GX::PlotDatasetAPIv3::addPanel` | `plot_ref`, `panel_id` | updated PlotSpec struct |
| `remove_panel` | `::GX::PlotDatasetAPIv3::removePanel` | `plot_ref`, `panel_id` | updated PlotSpec struct |
| `move_panel` | `::GX::PlotDatasetAPIv3::movePanel` | `plot_ref`, `panel_id`, `delta` | PlotSpec struct (changed or unchanged at an edge) |
| `set_panel_title` | `::GX::PlotDatasetAPIv3::setPanelTitle` | `plot_ref`, `panel_id`, `title` | panel struct |
| `set_panel_axis` | `::GX::PlotDatasetAPIv3::setPanelAxis` | `plot_ref`, `panel_id`, `axis`, `fields` | panel struct |
| `set_series_panel` | `::GX::PlotDatasetAPIv3::setSeriesPanel` | `plot_ref`, `series_id`, `panel_id` | updated PlotSpec struct |
| `interactive_sources` | `::GX::PlotDatasetAPIv3::interactiveSources` | none | cell of plot references |
| `interactive_source_info` | `::GX::PlotDatasetAPIv3::interactiveSourceInfo` | `plot_ref` | source struct |
| `source_fingerprint` | `::GX::PlotDatasetAPIv3::sourceFingerprint` | `plot_ref` | fingerprint string |
| `interactive_representations` | `::GX::PlotDatasetAPIv3::interactiveRepresentations` | none | cell of representation structs |

`openEditor`, `openInteractive`, `refreshInteractive`, and `activateInteractive` remain GUI/host actions. `sync_interactive` is different: its registered script operation does open the Viewer as part of synchronization. `captureForArtifact`, `renderSnapshot`, `writePointIndex`, `renderTransientOverlay`, `renderTransientCurve3D`, and `renderTransientCurves2D` remain unavailable to scripts until a safe destination policy is designed and validated (SB-014). Other public facade calls not listed above are classified individually in `SCRIPT_BRIDGE_COVERAGE_v1.json`; their absence from the Bridge is intentional or tracked as not yet bridged.

The host-only `sharedXAxisGet` and `sharedXAxisSet` facade calls use the v2
PlotSpec state. They let Plot Dataset graph settings and the framework Plots
tab read and edit one shared 2D X scale, major step, and minor grid across all
panels. A log10 major step of `1` is one decade; minor-grid `auto` draws the
unlabelled `2..9 × 10^n` subdivisions in each panel.

```octave
spec = gxtxt_api_call('PLOT_DATASET_API_v3', 'new_spec', {'plot.dataset.xy', 'Result'});
% Add public panels and Series to spec, then validate and create a normal Variant.
ref = gxtxt_api_call('PLOT_DATASET_API_v3', 'create_plot', {spec, 'variant'});
result = gxtxt_api_call('PLOT_DATASET_API_v3', 'render', {ref});
```

`previewExportCommand plotRef temporaryDirectory` delegates to the dedicated 3D
API's ordinary read-only export. Capability: `readonly_native3d_preview_export`.
It returns a command, not a persistent representation. The host owns cancellation,
source validation, bounded common lifecycle and transient cleanup. Existing
`buildScene`, `openInteractive` and explicit Sync retain their persistent semantics.


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
