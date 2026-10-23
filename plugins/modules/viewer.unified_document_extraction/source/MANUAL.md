# Unified document extraction — preview

This preview provides PDF consultation, canonical image ROI tools and read-only
table consultation in one window. A current Session and compatible existing
Datasets are required. No Dataset is created by selecting or opening a source.

## PDF

Choose an existing PDF Dataset in **PDF consultation**, then **Open PDF**. Source
selection only stages the choice; it does not open or replace a binding. The
existing CORE PDF reader opens it using its normal page, zoom, Fit page, Fit width
and pan controls. This preview does not add PDF-page raster conversion or PDF ROI OCR.
Choose the empty selection, then **Open PDF**, to release the binding. A missing or changed source is checked
by the existing canonical owner.

## Image ROI

Choose an existing raster Dataset in **Image ROI**. Selection only stages the
choice and leaves the current ROI scene in place. **Save the existing Workspace
before starting or replacing a scene.** Then use **Start new ROI scene**: every
explicit action requests a separate ROI Document owner, even for the same source.
The current view may be replaced; this preview does not offer an idempotent
rebind or a guarded dirty-scene disposition dialog. Reopen saved ROI work through
its Workspace rather than starting a new scene. **Select**,
**Rectangle**, **Polygon** and **Pan** use the shared native image controller;
the Image menu exposes the same actions. Rectangle drag and polygon clicks are
drafts until accepted. **Finish polygon** or Return accepts a valid polygon;
**Cancel draft** or Escape cancels it. **Delete ROI** changes the selected ROI
through the existing Document and History owners. **Fit image** fits the view.
The coordinate system remains source pixels (`px`); no physical calibration is
inferred. ROI edits do not rewrite original image bytes or publish a Dataset.

## Table consultation

Choose a compatible existing table Dataset in **Table consultation**, then
**Open table**. Source selection only stages the choice; it does not bind or
publish automatically. The shared read-only pager shows 100 rows per page with Source
row, scrollbars and Go to row. Canonical variable names, data types and units
remain with their Dataset. This preview does not edit cells or infer a schema.

## Workspace and History

The normal Workspace menu saves this preview's declared interface state through
the existing owner. History records supported image ROI changes. Source revision,
Session and Document guards apply. These controls require a current Session.
Saved workspaces from PDF OCR or either Table Extractor retain their original
module/provider; there is no automatic legacy-workspace conversion here.

## Extraction remains available in the existing Viewers

Use the existing PDF OCR, Generic OCR and Table Extractor Viewers for text
recognition, language/PSM/DPI selection, native/OCR/Auto extraction, editable
table review, text/image/table publication and searchable PDF production. Their
packages, public entries and saved workspaces remain available. This preview
does not replace them and does not claim complete functionality or GUI parity.

Typed extraction, editable review/publication, whole searchable-PDF processing,
legacy-workspace migration, and safe same-source rebind/source-switch disposition
have separate project-bound CORE requests.
Real original/candidate GUI comparison and measured responsiveness are pending
MAIN scheduling. Current developer checks cover source policy, compiled event
plans and package export; they do not establish OCR accuracy or GUI acceptance.
