# GX-TXT Table Extractor

`viewer.table_extractor` is a GX-TXT Viewer plugin for extracting tabular data from Canonical Datasets.

It accepts both:

- `image.raster`
- `document.pdf`

and publishes:

- `table.generic`

The extractor is intentionally source-agnostic after layout acquisition. An image imported from a camera, scanner, PNG/JPEG file, or cropped PDF region reaches the same table reconstruction path.

For PDF Datasets, the plugin takes advantage of PDF structure when possible:

1. positioned native PDF text is read with Poppler;
2. if the selected region has no usable native text, `Auto` mode falls back to page rasterization plus Tesseract OCR;
3. `OCR` mode can be selected explicitly.

For Image Datasets, Tesseract OCR supplies positioned words directly.

Both paths converge to the same private in-memory layout representation:

```text
text + bounding box + confidence
        ↓
row reconstruction
        ↓
column-boundary inference
        ↓
editable table preview
        ↓
GX-TXT table.generic Dataset
```

The source Dataset is never modified.

## Main capabilities

- Image or PDF input through normal GX-TXT Dataset identity.
- PDF page navigation and raster preview.
- ROI selection, move and resize.
- Native positioned PDF text extraction.
- Real Tesseract OCR for images and scanned PDF pages.
- Dynamic Tesseract language discovery with `tesseract --list-langs`.
- Automatic or user-specified expected column count.
- Editable cell preview before publication.
- Optional first-row-as-header interpretation.
- Basic column dtype inference: `int64`, `float64`, or `string`.
- Publication through Dataset Publication API v2.
- Variable Schema display labels.
- Dataset Metadata and source provenance.
- Session-persistent extraction workspaces through Interactive Document API v1.

See `MANUAL.md` for the complete workflow and limitations.
