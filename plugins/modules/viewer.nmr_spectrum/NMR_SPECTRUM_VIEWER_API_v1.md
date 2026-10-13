# NMR_SPECTRUM_VIEWER_API_v1

Activate with `::GX::modulePublicApiActivate viewer.nmr_spectrum NMR_SPECTRUM_VIEWER_API_v1`.

- `::GX::NmrViewer::datasets` lists acquired NMR Datasets in the current Session.
- `::GX::NmrViewer::compatibleOverlays datasetId` lists same-nucleus choices.
- `::GX::NmrViewer::peakList datasetId` and `integralList datasetId` read published NMR Analysis tables.
- `::GX::NmrViewer::createPlot datasetId ?overlayId? ?reverse|normal?` creates a retained Plot Dataset variant.
- `::GX::NmrViewer::openGraph ...` renders and opens the standard graph editor.
- `::GX::NmrViewer::saveState` and `loadState` persist viewer selection in the Session.

The source Dataset must carry `nmr.nucleus` structured metadata. Graph rendering is delegated to public `PLOT_DATASET_API_v3`.
