# NMR_SPECTRUM_VIEWER_API_v1

Activate with `::GX::modulePublicApiActivate viewer.nmr_spectrum NMR_SPECTRUM_VIEWER_API_v1`.

- `::GX::NmrViewer::datasets` lists acquired NMR Datasets in the current Session.
- `::GX::NmrViewer::compatibleOverlays datasetId` lists same-nucleus choices.
- `::GX::NmrViewer::peakList datasetId` and `integralList datasetId` read published NMR Analysis tables.
- `::GX::NmrViewer::createPlot datasetId ?overlayId? ?reverse|normal?` creates a retained Plot Dataset variant.
- `::GX::NmrViewer::openGraph ...` renders and opens the standard graph editor.
- `::GX::NmrViewer::saveState id ?overlayId=""? ?axisDirection=reverse? ?plotRef=""?` persists selection and returns the Session state-file path.
- `::GX::NmrViewer::loadState` returns the saved state dictionary, or an empty dictionary when no state is available.
- `::GX::NmrViewer::open context` opens the original Tk Viewer and returns its window path. The required context is the resolved Viewer scene; its preferred Dataset is `context.open_context.dataset_id`.

`peakList` returns dictionaries with `ppm`, `intensity`, `prominence` and
`width_ppm`. `integralList` returns dictionaries with `min_ppm`, `max_ppm` and
`integral`. These values come from genuine published analysis tables; absence
of a table produces an empty list. `plotRef` retains the actual Plot/Variant
identity and does not replace the canonical spectrum.

The source Dataset must carry `nmr.nucleus` structured metadata. Graph rendering is delegated to public `PLOT_DATASET_API_v3`.

## Viewer Provider callback

`::GX::NmrViewer::viewerDispatch {action scene}` is the trusted Tcl Viewer Provider callback. `action` is the lifecycle string `open` or `rerender`; other actions raise an error. `scene` is the complete resolved Viewer scene dictionary, passed unchanged to `::GX::NmrViewer::open`, including any `scene.open_context.dataset_id` selection. The return value is the existing Tk window path. Canonical NMR source identity and explicit `nmr.nucleus` metadata remain authoritative; this callback neither runs numerical analysis nor changes Script Bridge or C++ SDK admission.
