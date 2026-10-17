# Plot Dataset API v4

Native Plot v4 is an additive public API. PlotSpec v2, Graph Series, Variants, Dataset schemas, canonical values and physical units retain their existing public authorities. Activate `PLOT_DATASET_API_v4` through the Module API; the namespace is `::GX::PlotDatasetAPIv4`. APIs v1/v2/v3 remain available with their original implementation.

The v4 facade preserves the public v3 lifecycle/specification operations and exposes native `widgetCreate path spec ?context?`, `widgetConfigure`, `widgetDraw`, `widgetHit`, `widgetView`, `widgetEdit`, `widgetExport`, `widgetDestroy` and `widgetReceipt`. Native2D C++ retains a disposable typed view and projects through CORE C geometry to the shared native Cairo/Tk surface. Source access uses bounded public Curve Source/Table Stream services; full source extrema remain independent of display reduction. Hit receipts retain exact source-row strings, including uint64 values above 2^53.

A widget context containing `prepared_model 1` accepts an explicit disposable native presentation model; it does not publish scientific data. Canonical plot publication requires actual Dataset identities. Wheel zoom, middle-button pan and double-click complete fit change presentation only. Grid lines and labels use the same numeric ticks from the existing CORE axis authority.

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
