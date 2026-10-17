## 1.0.2

Declare distinct native-resolution scientific catalog artwork, short title and semantic group through the existing Viewer Provider descriptor.

## 1.0.10

- Resolve Session context and source payload through public Session Inspection with SHA verification.

# Changelog

## 1.0.0

Initial release.

- Added generic `image.raster` and `document.pdf` inputs.
- Added native positioned PDF text extraction through Poppler TSV.
- Added real Tesseract OCR for Image Datasets and scanned PDF content.
- Added automatic native-text-to-OCR fallback for PDF sources.
- Added dynamic Tesseract language discovery and multi-language OCR.
- Added page rendering/navigation, zoom, pan and rectangular ROI selection.
- Added common positioned-word layout representation for both source paths.
- Added row reconstruction and repeated-gap column-boundary inference.
- Added optional expected-column-count guidance.
- Added editable table preview before publication.
- Added first-row header handling and conservative int64/float64/string inference.
- Added direct `table.generic` publication through Dataset Publication API v2.
- Added source integrity verification, provenance and Dataset Metadata.
- Added Session-persistent named workspaces through Interactive Document API v1.
