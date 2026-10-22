# Document Extraction Viewer activation API v1

SPDX-License-Identifier: GPL-3.0-or-later

`viewer.document_extractors` declares version1 of this family in
`api/document_extractors_viewer_api_v1.tcl`, namespace
`::GX::DocumentExtractors`. It has two **module-qualified** Viewer IDs:

| Viewer ID | Backend | Public namespace entry |
|---|---|---|
| generic_ocr | document_ocr_tk | `ocrDispatch action scene` |
| table_extractor | document_table_tk | `tableDispatch action scene` |

Use the existing trusted-host dispatcher, for example:

```tcl
::GX::viewerOpen viewer.document_extractors generic_ocr
```

Both entries require two arguments, with no defaults. Supported action strings
are `open` and `rerender`. They open or focus the corresponding native window
and return a dict `{status opened}` or `{status focused}`. They return **neither
a Tk path nor an extraction result**. Unknown actions raise a Tcl error. The
`scene` argument is currently ignored, including `open_context`; this API does
not promise Dataset/file/Workspace selection through context. The existing
Viewer dispatcher checks installation/presentation enablement before activation.

## Context, actions and data owners

Both paths require the actual current Session before opening/focusing, and the
CORE OCR Layout and Table Extractor capability commands. Sources are canonical
Datasets satisfying `image.raster` or `document.pdf`; external paths are not a
public source-selection argument. Windows are `.gxGenericOcr` and
`.gxTableExtractor`, separately reused. Preview uses Dataset Preview and
temporary Preview Descriptor resources; closing cleans the corresponding image
and preview directory. IDs and lifecycle remain with existing public owners.

The GUI exposes preview/page/method/language/PSM/DPI controls, rectangular ROI,
table reconstruction/edit/publication or OCR/text and ROI-image publication.
Its initial method is Auto, languages `eng`, PSM3, DPI300. Native choices expose
PSM3/6/7/11 and DPI150/200/300/400/600; those choices are GUI controls, not the
complete CORE validator's allowed range. The ROI is a dimensionless ordered
`{left top right bottom}` rectangle normalized to displayed image dimensions in
0..1. ROI selection below2 displayed pixels on either axis is cleared. Image
acquisition maps the normalized bounds into full source pixels with floor/ceil
and clipping; render DPI, page and pixel bounds are retained as provenance.
Scientific physical length/calibration/uncertainty is not inferred from pixels.

Table reconstruction calls `::GX::TableExtractorAPIv1::extractDataset`; OCR calls
`::GX::OCRLayoutAPIv1` image/page/document extraction and `toText`. Table output
uses Dataset Publication v2 and `table.generic`/CSV; OCR output uses File
Publication and `document.text`/UTF-8, while ROI acquisition publishes
`image.raster`/PNG. Explicit publish uses owned replacement policy. This
activation facade declares no independent scientific table/OCR result schema,
numeric precision or unit inference; those remain the actual extraction and
publication owners' contracts. Consult the separate
[CORE OCR Layout](OCR_LAYOUT_API_v1.md) and
[CORE Table Extractor](TABLE_EXTRACTOR_API_v1.md) references for those service
contracts; this Viewer activation reference does not replace them.

The underscore-prefixed GUI/protocol callbacks are implementation details, not
new public methods. Use existing public CORE extraction APIs for programmatic
processing, never force a GUI callback or private source path as a service API.

## Exposure, bounds and errors

This family has no registered Python/Octave Script Bridge operations and no
typed C++ `gx::Host` entry. There is no generic invoke by API name. Supported
underlying services retain their own independent language admission.

Opening can fail for no Session, missing CORE capability, disabled/uninstalled
provider or Tk/dependency failure. Source preview/extraction/publication errors
are displayed through the owning native error dialog. No blanket receipt or
scientific success result is promised by the activation call. Preview, OCR,
publication and schema limits are enforced by their existing owners; this
facade supplies no universal input/sample-size or OCR-accuracy guarantee.
Installed module manual is `viewer.document_extractors/README.md`; related
references include [Viewer Provider](VIEWER_PROVIDER_API_v1.md),
[Dataset Preview](DATASET_PREVIEW_API_v1.md),
[Dataset Publication](DATASET_PUBLICATION_API_v2.md) and
[File Publication](DATASET_FILE_PUBLICATION_API_v1.md).
