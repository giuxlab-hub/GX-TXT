# Plot Dataset API v4

Native Plot v4 is an additive public API. PlotSpec v2, Graph Series, Variants, Dataset schemas, canonical values and physical units retain their existing public authorities. Activate `PLOT_DATASET_API_v4` through the Module API; the namespace is `::GX::PlotDatasetAPIv4`. APIs v1/v2/v3 remain available with their original implementation.

The v4 facade preserves the public v3 lifecycle/specification operations and exposes native `widgetCreate path spec ?context?`, `widgetConfigure`, `widgetDraw`, `widgetHit`, `widgetView`, `widgetEdit`, `widgetExport`, `widgetDestroy` and `widgetReceipt`. Native2D C++ retains a disposable typed view and projects through CORE C geometry to the shared native Cairo/Tk surface. Source access uses bounded public Curve Source/Table Stream services; full source extrema remain independent of display reduction. Hit receipts retain exact source-row strings, including uint64 values above 2^53.

Host-only `widgetValidateSources spec ?context?` checks the same model/source
snapshots without creating, configuring or destroying a controller or surface.
It returns `valid 1` and `source_count`, or the existing source admission error.
Use it before retiring accepted UI; `prepared_model 1` retains its usual meaning.
Creation/configuration still revalidate. This preflight does not guarantee later
allocation or a complete UI transaction, publish scientific data, add a cache,
or expose a new Script Bridge/restricted C++ method.

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

Python and Octave use the existing `gxtxt_api_call` interface under `PLOT_DATASET_API_v4`, with the same operation names and argument/result conventions as v3. No additional SDK is required. The finite parity matrix and focused receipts document actual verification; unsupported or unverified work is never reported as PASS.

## Native interaction and presentation

`widgetReceipt path` returns per-panel axis entries containing `panel_id`, `axis` (`x`, `left`, `right`), numeric `limits`, `scale`, `direction`, actual device `plot_rect`, and numeric ticks with their projected device coordinates. Pointer zoom and pan use this actual rectangle after margins, legends and layout have been applied. `widgetView path restore $receiptAxes` validates the complete supplied axis list before changing a viewport; it changes no saved PlotSpec or scientific value. `widgetView path fit` restores the complete scientific extent. A stale Session or source revision requires explicit `widgetConfigure` and preserves the previous valid frame.

The native memory receipt reports resident point count, point-vector capacity bytes and the actual parse-to-native point copy count. Capacity bytes cover the C++ Point vectors only. They exclude allocator bookkeeping, heap storage in row-identity strings, Tcl model objects and the Cairo primitive display list. Process RSS and worker peak memory are measured separately in the focused dense-source evidence.

Existing Axes, Legend, graphics, Level Scale and Variant controls remain the presentation authorities. The CORE effective-spec reader projects them into a versioned `native_presentation` dictionary. Its layout margins and gaps are percentages. Font units are actual `px` or `pt`, with points converted by the selected DPI. Canonical values and units remain unchanged. Statistical distribution vertices and contour intersections are derived presentation objects; they never claim an invented canonical source-row identity.

## Scientific 3D and independent representations

The native adapter reads rank-one XYZ/C/family tables through bounded public Table Stream calls. Canonical rank-two grids use bounded Dataset Access hyperslabs and the exact declared Y/X dimensions. Axes must be strictly monotonic; no transposition, interpolation, missing-cell filling or guessed variable position is performed. A canonical rank-two grid represents one surface, matching the stable public contract. Numerical families and categorical family identities remain separate, including exact int64 identities.

Native3D uses VTK polydata, triangulation and contours through the existing scientific Viewer Scene/Layer owner. Raster and SVG/PDF exports use the same native scene and camera. Mathematical colormap intake obtains at most256 RGB triples from the existing Octave colormap functions; it creates no figure, axes, graphics toolkit or Gnuplot process and calls no legacy Plot Dataset renderer.

`buildScene` creates an independently identified Interactive Document with format `gxtxt.plot_dataset.native_v4_scene`. It retains registered native geometry, scene and scientific figure. Explicit v4 owner checks prevent a historical v3 document from being silently rebound. The existing Native3D Viewer graph and representation controls dispatch by actual owner. A retained representation can be opened after its source Variant or Dataset becomes unavailable; synchronization still requires the original source and reports its actual status.

## Detached scientific capture

The snapshot directory contains `native_v4_snapshot.tcldict` and complete `resources/<DatasetID>.zip` public portable Dataset archives. The manifest is inert Tcl list/dictionary data, never sourced or evaluated. Archive paths and hashes are validated through the existing transport authority. Derived source Dataset and Dataset-qualified Variable IDs are returned by `snapshotValidate`; they are not a duplicate metadata store. Render workers import validated archives into a private disposable Session and remove that Session on completion.

The unchanged CORE Graph Annotations compositor remains responsible for separate figure-normalized annotation documents. Native base rendering consumes canonical PlotSpec data annotations. This keeps the established Graph annotation workflow from compositing the same annotations twice.


`widgetHit path x y` returns `hit`, `kind`/`object_kind`, and the real object identity at device coordinates. Exact nearest displayed points take priority and retain source-row strings and canonical source-series identity. Series, axis, legend, data annotation, panel, title and chart hits use the same bounded painter geometry and carry no invented source-row ID. Data annotation IDs identify their ordinal in the current panel; they are disposable presentation identities. Text selection uses the same Cairo extents/anchor/rotation as the drawn label. After an intentional viewport change, a hit is unavailable until the matching frame has been drawn.

Tk widget creation and Native3D window opening are host-only lifecycle operations. Script Bridge consumers use the existing public v4 scientific creation, inspection, rendering and independent-representation operations. The read-only `viewerLayerPrepare` normalized-layer helper and its explicitly contained `temporary_root` are host adapters; scripts retain the public Viewer/Resource ownership contracts instead of accessing a temporary path context. Native document inspection uses the existing Interactive Document read equivalents. These host helpers do not add a separate scientific registry or Script execution route.

Host widget context `retain_presentation 1` retains the explicit view while only
disposable Preview preferences change. Its scientific identity still binds actual
content, schema, public metadata, coordinate calibration and storage revision.
Native wheel, pan and double-click Fit now record a rejected controller once and
report nonmodal status, retaining the previous frame without repeated blocking
errors. Successful explicit `widgetConfigure` validates source checks before
changing native buffers and then re-enables interaction. Direct public operations
retain strict revision/Session errors. Focused dev109 GUI acceptance of this event
boundary remains open; this is no change to scientific source validation.


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

### Native cell-field range legend (dev109)

The existing Native2D painter reserves a separate band above the scientific
plot rectangle for each visible cell-field color bar and its complete
range/unit caption. The caption uses the painter's native font metrics and
wraps within the available panel width. It is not clipped to the mesh area and
does not share the in-plot series legend position. Above-panel series legends
remain above this reserved band. Narrow views that cannot retain a 40-pixel
scientific panel report insufficient space rather than silently hiding data.

The display color range, original scalar range, physical unit, source Dataset,
node/cell identities and constant-per-cell association are unchanged. The
existing native draw receipt adds `legend_rect` and `plot_rect` to each
`cell_fields` entry; these are disposable presentation bounds, never scientific
coordinates or persistent source identity. No new renderer or scientific Job
is introduced. Six isolated retained-FEM PNG/PDF cases cover 300/560/1000-pixel
widths and 12/18-pixel fonts; installed EM acceptance remains a separate gate.


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
