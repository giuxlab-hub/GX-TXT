# Plot Dataset API v4

Native Plot v4 is an additive public API. PlotSpec v2, Graph Series, Variants, Dataset schemas, canonical values and physical units retain their existing public authorities. Activate `PLOT_DATASET_API_v4` through the Module API; the namespace is `::GX::PlotDatasetAPIv4`. APIs v1/v2/v3 remain available with their original implementation.

The v4 facade preserves the public v3 lifecycle/specification operations and exposes native `widgetCreate path spec ?context?`, `widgetConfigure`, `widgetDraw`, `widgetHit`, `widgetView`, `widgetEdit`, `widgetExport`, `widgetDestroy` and `widgetReceipt`. Native2D C++ retains a disposable typed view and projects through CORE C geometry to the shared native Cairo/Tk surface. Source access uses bounded public Curve Source/Table Stream services; full source extrema remain independent of display reduction. Hit receipts retain exact source-row strings, including uint64 values above 2^53.

A widget context containing `prepared_model 1` accepts an explicit disposable native presentation model; it does not publish scientific data. Canonical plot publication requires actual Dataset identities. Wheel zoom, middle-button pan and double-click complete fit change presentation only. Grid lines and labels use the same numeric ticks from the existing CORE axis authority.

Public Graph Metadata records `renderer_owner=PLOT_DATASET_API_v4` and `renderer_owner_api_version=1`. This selects native render, capture and portable dispatch without rebinding legacy sources.

`captureForArtifact artifact directory` captures complete public portable Dataset archives and a data-only `native_v4_snapshot.tcldict` manifest. `snapshotValidate`, `snapshotCopy`, `renderSnapshot`, `snapshotPresentationFields` and `snapshotPresentationSet` preserve the scientific capture after source deletion. Rendering imports into a newly owned disposable Session; no caller Session is changed. SHA and public ZIP validation precede use.

Python and Octave use the existing `gxtxt_api_call` interface under `PLOT_DATASET_API_v4`, with the same operation names and argument/result conventions as v3. No additional SDK is required. The finite parity matrix and focused receipts document actual verification; unsupported or unverified work is never reported as PASS.
