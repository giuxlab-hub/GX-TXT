## 1.0.3 — dev-070

Share PDF canvas and Poppler rendering with CORE integrated consultation; preserve OCR workflows.

## 1.0.2

- Resolve Session context and PDF payload through public Session Inspection.

# Changelog

## 1.0.1

- Added direct whole-page publication as an `image.raster` Dataset.
- Added real Tesseract OCR of the whole rendered page with direct publication as a `document.text` Dataset.
- Added real Tesseract OCR across every PDF page with publication as one UTF-8 `document.text` Dataset, using form-feed page separators.
- Added persistent output Dataset IDs for whole-page image, whole-page text and whole-document text outputs.
- Preserved the existing ROI image/text and OCRmyPDF-derived `document.pdf` workflows.

## 1.0.0

- Added native GX-TXT `document.pdf` Viewer workflow.
- Added Session Dataset selection instead of external PDF file picking.
- Added Poppler page rendering with page/DPI control.
- Added source-coordinate zoom, pan and resizable rectangular ROI.
- Added ROI publication as `image.raster` through Dataset File Publication API v1.
- Added Tesseract ROI OCR and editable OCR preview.
- Added plugin-provided `document.text` contract and UTF-8 text Dataset publication.
- Added dynamic Tesseract language discovery through `tesseract --list-langs`; additional installed traineddata become available without plugin changes.
- Added whole-document OCR through OCRmyPDF, qpdf verification and derived `document.pdf` publication.
- Added source Dataset lineage and structured Dataset Metadata for all published outputs.
- Added Session-persistent workspaces through Interactive Document API v1.
- Removed the standalone utility's external input/output directory model; retained outputs are GX-TXT Datasets.
- Removed the ImageMagick dependency; Pillow handles preview resizing and source-raster crop operations.
