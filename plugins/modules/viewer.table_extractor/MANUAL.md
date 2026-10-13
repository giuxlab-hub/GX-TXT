# GX-TXT Table Extractor — Manual

## 1. Purpose

Table Extractor converts tables visible in Image or PDF Datasets into normal GX-TXT `table.generic` Datasets.

It is not a PDF-specific table parser. PDF and image sources use different layout-acquisition methods but share the same table reconstruction and publication logic.

## 2. Supported input contracts

```text
image.raster
document.pdf
```

The input remains immutable.

## 3. Output

Successful publication creates one derived:

```text
table.generic
```

Dataset through Dataset Publication API v2.

The output contains a normal Variable Schema and can be consumed by the rest of GX-TXT.

## 4. PDF workflow

For a PDF Dataset:

```text
document.pdf
    ↓
selected page / ROI
    ↓
Auto mode
    ├── usable positioned PDF text → native layout
    └── otherwise → raster page + Tesseract OCR
    ↓
common layout representation
    ↓
table reconstruction
```

### Native PDF text

The plugin uses Poppler `pdftotext -tsv` to obtain words and their page coordinates.

This avoids OCR when a real text layer is available and usable.

### OCR fallback

If native positioned text is not usable, `Auto` mode renders the page at the selected DPI and runs Tesseract.

`OCR` mode forces this path.

`Native PDF text` mode refuses extraction if the selected region does not contain enough usable positioned text; it does not silently switch to OCR.

## 5. Image workflow

For an Image Dataset:

```text
image.raster
    ↓
whole image or ROI
    ↓
Tesseract TSV
    ↓
common layout representation
    ↓
table reconstruction
```

The plugin does not care whether the Image Dataset originated from a photograph, scanner, imported PNG/JPEG/TIFF/BMP, or another GX-TXT transformation.

## 6. Region of interest

A rectangular ROI may be drawn over the preview.

The ROI can be:

- created with left-drag;
- moved;
- resized with eight handles;
- cleared to analyze the complete page/image.

The ROI is stored in source-raster pixel coordinates, independent of display zoom.

## 7. OCR languages

Installed Tesseract languages are discovered dynamically with:

```text
tesseract --list-langs
```

Multiple languages may be selected. They are passed to Tesseract as a `+`-joined language specification, for example:

```text
eng+ita
chi_sim+eng
jpn+eng
```

No language list is hard-coded into the plugin.

## 8. OCR page segmentation mode

Initial choices are:

```text
Auto        PSM 3
Block       PSM 6
Sparse text PSM 11
```

`Block` is the default because many regular tables behave well as a coherent text block.

## 9. Table reconstruction

The plugin first groups positioned words into rows using vertical geometry.

It then identifies repeated horizontal gaps between words and uses them as candidate column boundaries.

The same algorithm is used regardless of whether word geometry came from PDF native text or OCR.

### Expected columns

`Expected columns = 0` uses automatic inference.

A positive value requests that number of columns and makes the boundary selector choose the strongest `N-1` candidate separators.

This is useful when OCR or a visually irregular table produces an ambiguous automatic result.

## 10. Preview and correction

The reconstructed matrix is displayed before publication.

Double-click a cell to edit it.

This correction stage is intentional: OCR and layout reconstruction are extraction aids, not authoritative scientific interpretation.

Publication uses the edited preview, not the unreviewed OCR tokens.

## 11. Header handling

When `First row is header` is enabled:

- the first reconstructed row supplies display labels and variable IDs;
- the first row is not published as data.

When disabled, generated labels are:

```text
Column 1
Column 2
...
```

Variable IDs are sanitized to stable GX-TXT-compatible identifiers and made unique if duplicate headings occur.

## 12. Type inference

Each output column is classified conservatively as:

```text
int64
float64
string
```

A numeric dtype is used only when every data cell in the column is non-empty and compatible.

Otherwise the column remains `string`.

Numeric recognition uses the GX-TXT technical convention with decimal point (`.`). The extractor does not silently reinterpret locale-specific decimal commas.

## 13. Publication and provenance

The plugin publishes through Dataset Publication API v2.

The resulting Dataset records provenance back to the original source Dataset and includes metadata such as:

```text
source Dataset ID
source SHA-256
source contract
extraction method
source page
source ROI
OCR languages and PSM when OCR was used
layout token count
row count
column count
header policy
plugin version
```

The source canonical SHA-256 is revalidated before publication. If the source changed after extraction, publication is refused.

## 14. Session-persistent workspaces

Interactive Document API v1 stores named Table Extractor workspaces.

A workspace can retain:

```text
source Dataset
source hash
page
DPI
zoom
ROI
extraction mode
OCR languages
PSM
expected column count
header policy
editable reconstructed table
last extraction method
output Dataset ID/name
```

Published Datasets are independent of the workspace and are not deleted when a workspace is deleted.

## 15. Dependencies

See `DEPENDENCIES.md`.

## 16. Limitations

Version 1.0.0 targets regular scientific and technical tables.

Complex cases may require manual correction or future specialized support, including:

- merged cells;
- nested headers;
- strongly wrapped multiline cells;
- tables without stable horizontal alignment;
- severe perspective distortion;
- heavily rotated or skewed photographs;
- handwritten tables;
- semantic interpretation of units or scientific quantities.

The plugin does not invent semantic meaning for extracted columns.

It does not automatically correct OCR text beyond user edits.

## 17. GX-TXT APIs used

The plugin uses public framework facilities only:

```text
Viewer Provider API v1
Interactive Document API v1
Dataset Inspection API v1
Contract Registry API v1
Dataset Publication API v2
Dataset Variable Schema API v3
Dataset Metadata API v1
Plugin Install API v1
```

No private Dataset Registry mutation is performed.
