# Plot Dataset API v4

Native Plot v4 is the required public scientific plotting API for every new or
rebuilt Viewer, in both 2D and 3D. PlotSpec v2, Graph Series, Variants, Dataset
schemas, canonical values and physical units retain their existing authorities.
Activate `PLOT_DATASET_API_v4` through the Module API; the Tcl namespace is
`::GX::PlotDatasetAPIv4`. APIs v1/v2 retain their compatibility behavior.
**v3 is DEPRECATED for historical compatibility only and is denied to new
restricted C++ Viewer authoring.**

The v4 facade preserves the public v3 lifecycle/specification operations and exposes native `widgetCreate path spec ?context?`, `widgetConfigure`, `widgetDraw`, `widgetHit`, `widgetView`, `widgetEdit`, `widgetExport`, `widgetDestroy` and `widgetReceipt`. Native2D C++ retains a disposable typed view and projects through CORE C geometry to the shared native Cairo/Tk surface. Source access uses bounded public Curve Source/Table Stream services; full source extrema remain independent of display reduction. Hit receipts retain exact source-row strings, including uint64 values above 2^53.

`widgetCreate` validates prepared source snapshots before allocating its native
controller or surface. A rejected stale source leaves the path available for an
explicit valid retry. `widgetConfigure` likewise validates the replacement before
changing the accepted controller; rejection preserves its previous model.

Host-only `widgetValidateSources spec ?context?` runs the same model/source
snapshot checks without creating, configuring or destroying a controller or
surface. It returns `valid 1` and `source_count`, or raises the existing source
admission error. Hosts can check a replacement before clearing accepted UI.
`prepared_model 1` has the same meaning as in widget creation. This is a source
preflight, not a guarantee of later widget allocation or full UI transaction
success; create/configure still revalidate. It publishes no Dataset or cache,
and adds no Script Bridge or restricted C++ method.

A widget context containing `prepared_model 1` accepts an explicit disposable native presentation model; it does not publish scientific data. Canonical plot publication requires actual Dataset identities. Wheel zoom, middle-button pan and double-click complete fit change presentation only. Grid lines and labels use the same numeric ticks from the existing CORE axis authority.

## Canonical Scientific Dataset consultation

`scientificModel datasetId xId series coordinateContext ?options?` admits the
Scientific Dataset Viewer's existing asynchronous Curve Source results into the
same native Plot v4 model. Each trace supplies `id`, `y_variable_id`, `label`,
`filters`, the actual `source_descriptor` captured before closing its Curve
Source, and its prepared `display`. Descriptor Dataset/X/Y and `source_id` must
match that display; canonical `dataset_row` identities remain exact integers.
Canonical and displayed coordinates are separate. A presentation buffer is not
a new Dataset or an independent scientific authority.

Options are `title`, `axis_labels {x caption y caption}`, `aspect auto|xy_equal`,
the existing `native_presentation`, and an optional `progress` callback prefix.
Fit uses full finite source bounds. Nonlinear coordinate bounds use the existing
complete public Curve Source pass, yielding at bounded cooperative boundaries;
the callback must retain the host's cancellation/epoch check. Source, Session and
coordinate context are revalidated at preparation and controller admission.
Declared display units, magnification and canonical pivot use the existing
coordinate API. No numerical calibration is applied to canonical samples.

Create/configure with context `{prepared_model 1 retain_presentation 1}`.
`widgetDraw`, `widgetReceipt` and `renderModel` additionally return
`coordinate_presentation`, including reference bounds, actual painter view
bounds and coordinate ranges. The native receipt retains its original owner.
`xy_equal` uses the shared Native2D equal numeric aspect service for one linear
X/Y scale; it does not assert equal physical dimensions or CAD calibration.
Right-Y and logarithmic equal-aspect panels are rejected explicitly. A legacy
numeric/boolean axis outside the real-number coordinate contract remains
drawable, but its PNG metadata does not claim supported inverse calibration.

`widgetPointer path operation x y ?factor?` dispatches `pan_start`, `pan`, `zoom`
and `fit` through the owned controller. `widgetRetain path reason` freezes the
previous frame and pending draw/pointer activity during preparation, cancellation
or failure. A valid explicit `widgetConfigure` re-enables it. Fit cannot reactivate
an incomplete or cancelled preparation. These are trusted-host methods and add
no Script Bridge or restricted C++ SDK permission.

A valid filtered trace containing one observation uses the existing native
scatter/circle painter. It is not drawn as an invisible markerless one-vertex line.

## Derived numerical comparison display

`comparisonModel ownerBinding comparisonRecord ?options?` accepts the actual
public Curve Workbench comparison source and unchanged numerical result record.
The companion `CURVE_WORKBENCH_API_v1::comparisonDisplayValidate` must validate
the live owner, Session, window incarnation, Document generation, active request,
geometry fingerprints and coordinate signature. Validation runs both at model
admission and every live widget operation, even when no Dataset file changed.
Missing companion support is an explicit error. This is a live derived display;
it is not a detached scientific snapshot.

The existing Plot v4 line painter displays receipt samples and its scatter
painter highlights the recorded maximum. Comparison evaluation indices and
display-relative maximum indices remain distinct from Dataset row identities;
no canonical `source_rows` or fabricated Curve Source is attached. The complete
original comparison/statistics receipt and sampling policy remain in the model
and returned receipt. Statistics are not recomputed from display rows. Captured
source provenance is labeled `source_provenance_at_admission`; editable cached
geometry is not promoted to a claim of current canonical Dataset content.

Widget context may provide `refresh_hint {Select Compare to refresh.}` for a
stale derived display. The shared controller retains the old frame and reports
the appropriate action without recurring modal errors. Canonical publication
continues through the original comparison owner, never from Plot display data.

## Source-grounded 3D consultation

`consultationSource reference`, `consultationExportCommand reference directory`
and `consultationScene reference expectedSourceKey directory` provide the v4
construction/admission boundary for existing scientific provider graphs. Graph
Workflow still proves the producer's actual bindings, geometry, cache and units.
The original module, graph and base/Variant identity remain unchanged; the
provider is never relabeled `plot.dataset.xyz`. The existing native preparation
command is reused. Source/Session/coordinate keys and real native artifact hashes
are revalidated before adopting the bounded scene descriptor.

For numerical Dataset Preview, `xyzConsultationSource datasetId axes` resolves
three explicit distinct enabled rank-one numeric Variables and their canonical
source/coordinate identity. `xyzConsultationPrepare id axes w` and
`xyzConsultationChunk w` own the existing bounded stream and VTP construction,
using the existing shared host, cancellation and Native3D worker. They preserve
the limits of 100000 scanned rows and 12000 displayed points, without invented
connectivity or interpolation. `xyzCoordinatePresentation context axes
canonicalPoints` retains the existing unit conversion and magnification policy;
its normalized display frame does not modify canonical triples. Spatial X/Y in
millimetres and temperature Z in kelvin remain separately identified quantities.

`consultationReceipt hostWindow` verifies the current source and real layer
hashes and reports `preparing`, `updating` or `current`. A retained old frame is
insufficient to claim a current scene. These host-only methods reuse Native3D;
they create no additional renderer, scientific Dataset or Script/SDK permission.

Public Graph Metadata records `renderer_owner=PLOT_DATASET_API_v4` and `renderer_owner_api_version=1`. This selects native render, capture and portable dispatch without rebinding legacy sources.

`captureForArtifact artifact directory` captures complete public portable Dataset archives and a data-only `native_v4_snapshot.tcldict` manifest. `snapshotValidate`, `snapshotCopy`, `renderSnapshot`, `snapshotPresentationFields` and `snapshotPresentationSet` preserve the scientific capture after source deletion. Rendering imports into a newly owned disposable Session; no caller Session is changed. SHA and public ZIP validation precede use.

Python and Octave use their existing Script Bridge `gxtxt_api_call` interface
under `PLOT_DATASET_API_v4`. Discover exact operation/argument/result descriptors
with `gxtxt_api_describe('PLOT_DATASET_API_v4')` in the active managed script
context. Tcl host procedures, Script Bridge operation names and restricted C++
SDK methods are distinct surfaces: a host method is not automatically callable
by scripts or admitted to C++. The C++ Workspace API catalog and project profile
are authoritative for that author's admitted typed subset.

## Exact cell-associated triangular fields

`cellFieldSpec cellDatasetId centroidXVariableId centroidYVariableId binding ?title?` constructs a canonical PlotSpec with an explicit `cell_field` extension on its stable series ID. Python and Octave call `cell_field_spec` with the same five operands (title optional). The binding is an inert dictionary with exactly these fields:

```
schema GXTXT_CELL_FIELD_BINDING_v1
nodes_dataset_id canonicalNodeDataset
node_id_variable_id stableIntegerNodeId
x_variable_id nodeCoordinateX
y_variable_id nodeCoordinateY
cell_id_variable_id stableIntegerCellId
node_variable_ids {firstNodeId secondNodeId thirdNodeId}
scalar_variable_id cellAssociatedScalar
```

All names resolve through actual Variable Schema v3; no physical column positions or producer-specific headers are assumed. Connectivity contains three distinct existing node IDs. Node and cell identities are unique, coordinates and scalar values finite, triangles nondegenerate. Clockwise and counterclockwise source orientation are both retained. Node coordinate units are converted through the existing public coordinate context. The complete exact node domain determines bounds independently of scalar samples or display reduction. Colors are constant within each source cell; there is no Delaunay triangulation, nodal interpolation or implicit averaging of unrelated values. Picking returns the actual cell ID, source-row ordinal, scalar variable ID, value and unit.

Canonical Graph Metadata retains the binding by stable series identity alongside the renderer-owner marker. A missing required binding fails explicitly; it cannot silently become a scatter plot. Complete scientific snapshots, Clones and portable graphs include both canonical node and cell Datasets and their exact role dependencies. Current bounded projection supports at most 60,000 nodes and 30,000 cells. Filters, grouping and row selection on this extension require an explicitly published canonical submesh; unsupported selections fail rather than changing topology silently. Other native plot kinds retain their existing behavior. A host without the `native_cell_field` capability rejects the binding.

## Retained explicit presentation

Host widget context `retain_presentation 1` opts a prepared model into persistent explicit-view semantics. CORE Dataset Viewer's `datasetViewerScientificIdentity` binds content, schema, public metadata, coordinate calibration and storage revision. Changes confined to user Preview controls/visibility can refresh the guard without rebuilding geometry or resetting navigation. A scientific dependency change still refuses interaction and preserves the previous frame until explicit reconfiguration. Ordinary widgets retain their stricter existing revision policy. This is a host-only presentation capability; it creates no alternate Dataset or source identity.

Native wheel, pan and double-click Fit now treat a rejected source/controller as
an inactive previous render. The first rejection records its message/options and
reports it through nonmodal status; subsequent pointer events leave the retained
frame untouched. Successful explicit `widgetConfigure` validates source checks
before changing native buffers and then re-enables interaction. Direct public
operations retain their strict revision/Session errors. This dev109 event-boundary
correction requires focused positive, stale-source and Render-recovery GUI tests;
it does not weaken scientific validation or certify an untested original Session.

## Planar cell field presentation through Native3D

`cellFieldSourceIdentity spec` validates a single complete cell-field panel and
returns its spec, both canonical scientific identities and coordinate contexts.
`cellFieldNativeScene spec` returns the same exact node/triangle/cell-value
projection used by the 2D owner, an ordinary Native3D scene and its source identity.
Use `native3DViewportBind handle {kind cell_field spec ...}` for the managed
interactive lifecycle. These operations neither publish a Dataset nor run a Job.

Coordinates are compatible physical lengths; field amplitude retains its own
unit and cell association. Z=0 expresses a planar display embedding. There is
no centroid triangulation, nodal interpolation, fictitious thickness or volume.
Initial framing delegates to the existing native Fit Scene service.

`cellFieldProfileSpec fieldSpec` authenticates one complete canonical cell-field
binding and returns a source-bound scatter of the actual stored cell-centroid X
and cell scalar, including all Y locations. It performs no interpolation,
centerline selection or new scientific calculation. The original EM Viewer and
Builder Host share this adapter. Its profile is an independent numerical chart;
only the field scene requires linked node geometry.


### Cell-field color normalization

`cellFieldNativeScene` supplies the existing native layer `scalar_range` explicitly.
Its `scalar_display` receipt preserves full-precision `source_scalar_range`, the
separate `color_range` and `display_range_expanded`. As in Native2D, a scalar span
at most 1e-12 of its magnitude uses a five-percent display margin (minimum scale
1e-300), with finite bounds. This avoids exaggerating floating-point roundoff in
an effectively constant field. The margin is a color display choice, never a
measurement uncertainty, a new physical range or a change to stored values.
The caption identifies coordinate/scalar units, Z=0 and an expanded display scale.
Nonconstant data retain their actual range. Canonical cell values, node/triangle
identities, source revisions and coordinate transformations remain unchanged.

### Scientific 3D scalar labels

Automatic colorbar labels describe the actual scalar binding: C when explicitly
bound, otherwise Z. An independent C uses its public variable label and scalar
display unit. `color_unit=auto` retains C's source unit for an explicit binding;
without C it follows Z's display unit. An explicit color unit takes precedence.
Z's coordinate-only level-scale suffix is not added to the untransformed scalar.
An explicit `colorbar_label` still overrides the automatic text. This changes
descriptor text only; scalar values, coordinate transformations, source guards,
PlotSpec identities and the existing table/grid preparation defaults are retained.

`interactiveStatus` also checks the retained figure's scalar label against this
current contract, including manual override. An unchanged source fingerprint
does not make an older Z-for-C label current: that representation reports
`OUT OF SYNC` and the existing explicit Sync operation can replace it. Status
inspection leaves the stored representation and canonical source untouched.

Prepared 3D layers also receive the effective per-plot `marker_size` and
`line_width`, with per-plot values preceding inherited graphics defaults.
`marker_size` maps to the existing public Viewer Layer `point_size`; both styles
pass its finite `(0,64]` validation before native use. This changes presentation
parameters, not coordinates, source-row identities, scalar values or geometry.
Existing independently saved scene styles are not rewritten by this projection.
Explicit Sync also retains compatible saved `point_size` and `line_width`,
including when synchronizing an inactive representation after Session reopen.
An older representation without those fields receives the current source's
validated defaults. Source Plot settings and each saved view retain their
separate persistent identities.

Scientific `scatter3` layers request native screen-sized points through public
Viewer Layer `sphere_glyphs=0` and `representation=points`. Their marker size
stays in pixels when physical axes use different units and independent scales.
Explicit saved point/sphere choices survive Sync; an older unset choice receives
the scientific point default. This requires the public Viewer Layer capability
from CORE commit `2c2e2fb`; no engine, source values or physical units change.


## Inert native host reference

`widgetVisibility path panel series visible` changes the presentation visibility
of the selected native panel/series. It returns a dictionary containing `widget`,
`model_token`, `panel_id`, `series_id` and `visible`; it preserves canonical
source data and the existing widget's strict Session/source guards.

The provider descriptor declares exact named formals, parameter/result types and context for the current native widget lifecycle and the four cell-field adapters, including `widgetValidateSources spec ?context?` and the existing `widgetEdit path spec` companion. API Browser reads this metadata without invoking those operations. These Tcl host methods do not grant new Script Bridge or C++ SDK calls. `widgetView` and `widgetDestroy` have no stable scientific-result return; query `widgetReceipt` for authoritative view state. Cell-field profiles retain all actual centroid samples, and their Native3D presentation remains a planar XY mesh with Z=0 and scalar color, never a CAD volume or a new simulation.

Finite line runs containing one actual sample use the native circle painter even
when the retained line style has no general markers. This keeps isolated finite
observations visible between missing-data gaps without connecting those gaps,
changing point/row identity or adding interpolated samples. Ordinary multi-point
line runs retain their configured style.
