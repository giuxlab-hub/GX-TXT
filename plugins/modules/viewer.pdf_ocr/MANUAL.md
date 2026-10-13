# PDF OCR Viewer — User Manual

## 1. Purpose

PDF OCR Viewer provides a native GX-TXT workflow for inspecting PDF Dataset pages, selecting a rectangular source region and producing derived image, text or OCR-PDF Datasets.

The original imported PDF remains the authoritative source Dataset and is never modified.

## 2. Input

The Viewer accepts canonical Datasets satisfying:

```text
document.pdf
```

Use the normal PDF acquisition module first to import external PDFs into the Session.

The Viewer does not contain an `Open PDF` file picker. This is intentional: it operates on GX-TXT Datasets rather than bypassing Dataset provenance.

## 3. Opening the Viewer

Open:

```text
Viewers
→ PDF OCR Viewer
```

Viewer discovery is headless. Python/Tk and external PDF/OCR dependencies are loaded only when the Viewer is opened.

## 4. Workspace persistence

The Viewer can create named Session-scoped workspaces.

A workspace stores lightweight authoritative interactive state such as:

```text
source Dataset ID
source SHA-256
current page
DPI
preview zoom
ROI coordinates
selected OCR languages
PSM/layout mode
output Dataset IDs
```

The state is stored through Interactive Document API v1. It does not duplicate the PDF or rendered page bytes.

Published Datasets remain independent from workspace deletion.

## 5. Page rendering

Select a PDF Dataset and choose:

```text
page
render DPI
preview zoom
```

Supported render DPI presets are:

```text
150
200
300
400
600
```

Poppler `pdftoppm` renders only the requested page into temporary runtime storage.

The rendered page is not automatically retained as a Dataset.

## 6. Zoom and pan

Controls:

```text
mouse wheel       zoom around pointer
arrow keys        pan
middle drag       pan
scrollbars        pan
```

Preview zoom does not change the source raster coordinate system used for crop/OCR.

For example, a region selected while viewing at 50% is still cropped from the full page raster produced at the selected DPI.

## 7. ROI selection

Use the left mouse button to create a rectangular ROI.

After creation:

- drag inside the rectangle to move it;
- drag one of the eight handles to resize it;
- use `Clear ROI` to remove it.

The status line reports the ROI in source raster pixels.

## 8. Publish crop Dataset

`Publish crop Dataset` creates a PNG from the selected ROI and publishes it through Dataset File Publication API v1 as:

```text
contract: image.raster
storage:  binary
media:    image/png
```

Metadata records the source PDF Dataset, page, render DPI and source ROI.

The crop can therefore be consumed by normal image workflows such as Curve Digitalizer without reopening an external file path.


## 9. Publish whole page as Image Dataset

`Publish whole page Dataset` publishes the complete currently rendered page as:

```text
contract: image.raster
storage:  binary
media:    image/png
```

The page is published at the selected render DPI. Metadata records the source PDF Dataset, page, render DPI and the full-page raster rectangle.

## 10. OCR languages

The language list comes from:

```text
tesseract --list-langs
```

It is not limited to Chinese or English.

Select one or more installed languages. Multiple selections are joined using the normal Tesseract syntax:

```text
eng+ita
chi_sim+eng
chi_tra+eng
jpn+eng
```

To add another writing system or language, install its Tesseract traineddata package on the server and reopen the Viewer. No plugin modification is required.

## 11. OCR layout / PSM

The Viewer exposes:

```text
Auto          PSM 3
Block         PSM 6
Single line   PSM 7
Sparse text   PSM 11
```

## 12. OCR selected region

`OCR selection`:

1. crops the full-resolution rendered page using source-pixel ROI coordinates;
2. writes only a temporary PNG;
3. runs Tesseract without shell interpolation;
4. displays the UTF-8 OCR result in the Viewer.

The text remains editable before publication.

## 13. Publish ROI OCR text Dataset

`Publish ROI text Dataset` writes the current OCR text as UTF-8 and publishes it as:

```text
contract: document.text
format:   txt
storage:  text
media:    text/plain
variables: none
```

Structured Dataset Metadata records the OCR engine, languages, PSM, source PDF Dataset, source page and source ROI.

## 14. OCR whole page to Text Dataset

`OCR whole page → Dataset` runs Tesseract on the complete currently rendered page at the selected DPI using the selected languages and PSM.

The recognized text is shown in the Viewer and immediately published as a `document.text` Dataset. The source page is represented as the full-page raster rectangle, preserving the same provenance model used for ROI OCR.

## 15. OCR whole PDF to Text Dataset

`OCR whole PDF → text Dataset` performs real OCR across every page:

```text
document.pdf
→ render each page with Poppler at selected DPI
→ Tesseract OCR each page
→ concatenate page text with form-feed separators
→ document.text Dataset
```

The resulting UTF-8 text uses `\f` page separators so page boundaries remain recoverable without inventing table variables.

Dataset Metadata records:

```text
ocr.engine=Tesseract
ocr.languages=...
ocr.psm=...
ocr.source_scope=whole_pdf
ocr.source_page_count=...
ocr.render_dpi=...
ocr.page_separator=form_feed
```

## 16. `document.text` contract

This plugin provides the `document.text` Dataset contract.

Minimum meaning:

```text
verified UTF-8 text payload
stable Dataset identity
normal Session storage
CORE-computed SHA-256
normal provenance/lineage
```

A text Dataset is not a numeric table and therefore requires no Variable Schema columns.

The contract is provided by the plugin through Contract Registry discovery; no CORE modification is required.

## 17. Whole-document OCR to derived PDF

`OCR whole PDF → PDF Dataset` executes OCRmyPDF using the selected Tesseract languages:

```text
--deskew
--rotate-pages
```

The produced PDF is checked with `qpdf --check` and inspected with `pdfinfo` before Dataset publication.

The derived document is published as a new `document.pdf` Dataset with source lineage back to the original PDF. The original PDF is never replaced.

PDFs that already contain text may require an OCRmyPDF policy different from the default command. The plugin intentionally does not silently force destructive rasterization.

## 18. Dataset replacement

Interactive re-publication of an output Dataset ID requests the public API's explicit same-owner replacement behavior.

It can replace only a Dataset previously published by this same plugin through Dataset File Publication API v1. Foreign or legacy Dataset IDs are never overwritten.

## 19. Temporary files

Rendered pages, ROI PNGs, temporary OCR text and pre-publication OCR PDFs live only in a process-specific temporary directory.

Authoritative retained outputs are GX-TXT Datasets. The temporary directory is removed when the Viewer closes.

## 20. Dependencies

See `DEPENDENCIES.md`.

Mandatory runtime tools are:

```text
Python 3 + tkinter + Pillow
pdfinfo
pdftoppm
tesseract
ocrmypdf
qpdf
```

No ImageMagick dependency is used by the Viewer.

## 21. Public GX-TXT APIs used

```text
Viewer Provider API v1
Interactive Document API v1
Dataset File Publication API v1
Dataset Metadata API v1
Session Inspection API v1
Contract Registry API v1
Plugin Install API v1
```

The plugin does not edit Dataset Registry files or Dataset Metadata sidecars directly.

## 22. Installation

Install the ZIP through GX-TXT Plugin Install API v1.

Do not manually copy the module into `plugins/modules`.

After installation, enable `viewer.pdf_ocr` if it is not already enabled, then open the Viewer from the Viewers list.

## 23. Limitations

The plugin intentionally does not implement:

```text
automatic document classification
full-text indexing
table recognition
layout reconstruction
handwriting-specific workflows
PDF editing/annotation
automatic OCR correction
```

OCR accuracy depends on source quality, DPI, selected languages and page layout. Critical technical values should still be checked against the rendered source page.
