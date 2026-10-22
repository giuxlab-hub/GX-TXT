# CORE OCR and Layout API v1

SPDX-License-Identifier: GPL-3.0-or-later

CORE owner `core/tcl/ocr_layout_api_v1.tcl`, namespace `::GX::OCRLayoutAPIv1`, is
loaded independently of module Run selection or GUI startup. It wraps configured
Tesseract/Poppler tools and returns positioned-word data; no OCR engine is
reimplemented in a Viewer.

## Exact public host signatures

| Signature | Arguments/defaults | Result/effect |
|---|---|---|
| `capabilities` | none | supported capability string list |
| `supports capability` | required exact string |0/1 membership |
| `requireCapability capability` | same |1 or error |
| `dependencyStatus` | none | dict for tesseract/pdftotext/pdftoppm/pdfinfo, each available boolean/path; executable discovery only |
| `apiInfo` | none | API name/version, owner CORE, capabilities and dependencyStatus |
| `languages` | none | sorted unique installed Tesseract language IDs; executes --list-langs |
| `pdfInfo pdfPath` | required existing PDF file | normalized path/page_count and available pdf_version/encrypted/page_size/page_rotation/title/author/subject/creator/producer |
| `extractImage imagePath ?options?` | existing image; options default `{}` | Tesseract positioned-word layout |
| `filterRoi layout roi` | required layout and normalized rectangle | copied layout with center-selected words/count and roi_normalized |
| `renderPdfPage pdfPath page outputPath ?options?` | required files/1-based page; options default `{}` | writes PNG, returns path/page/dpi/format png/media_type image/png |
| `extractPdfPage pdfPath page ?options?` | required PDF/1-based page; options default `{}` | native-text or OCR page layout |
| `extractPdfDocument pdfPath ?options?` | required PDF; options default `{}` | dict api_version1/source_kind pdf/source_path/page_count/pages (list of layouts) |
| `toText layoutOrDocument ?options?` | layout or document; options default `{}` | reconstructed text, no file write |

Capabilities are dependency_discovery, tesseract_languages, image_ocr, pdf_info,
pdf_page_render, pdf_native_text, pdf_page_ocr, pdf_auto_text,
pdf_document_layout, normalized_coordinates, roi_filter, positioned_words,
plain_text_reconstruction. Capability support is distinct from an executable
being installed and from successful processing of a particular file.

## Options and coordinates

Options are Tcl dicts. The current reader consumes the following keys where
applicable; unknown keys are not globally rejected by a typed options schema.

| Key | Default / constraints | Used by |
|---|---|---|
| languages | eng; nonempty text | Tesseract extraction |
| psm |3; integer0..13 | Tesseract page-segmentation mode |
| method | auto; auto/native/ocr | PDF extraction |
| native_min_words |1; nonnegative integer | auto native-text acceptance threshold |
| dpi |300; positive integer | PDF raster rendering/OCR |
| min_confidence |-1; finite numeric, no other declared bound | positioned-word TSV filtering |
| roi | absent/empty; otherwise four finite values `{x1 y1 x2 y2}` in0..1 with positive width/height | extraction center-based ROI filter |
| page_separator | newline, form-feed, newline | toText document output |

`filterRoi` should receive a nonempty valid rectangle; it selects words whose
normalized centers lie inclusively inside the rectangle, without clipping
boxes/rebasing coordinates. ROI is dimensionless, not physical length.
Image/OCR coordinates are pixels (`px`); native PDF text coordinates are points
(`pt`). PDF OCR adds render_dpi. The generic empty-TSV early return has an empty
coordinate_unit and zero dimensions; do not infer a calibrated coordinate system
from a no-word result.

## Layout shape and behavior

A page layout contains api_version, source_kind image/pdf, source_path, page,
method tesseract/pdf_native, coordinate_unit, page_width/page_height, word_count
and words. Each word has text, confidence, x/y/width/height, normalized
x_norm/y_norm/width_norm/height_norm/cx_norm/cy_norm, block, paragraph, line,
word_index and source method. Missing/non-numeric TSV confidence becomes-1;
this score is backend metadata, not probability, scientific uncertainty or
independent recognition accuracy. Positive page dimensions support normalization;
otherwise normalized values become0. Host layouts include source paths.

Auto PDF extraction tries native TSV first and accepts enough words, otherwise
falls back to raster/Tesseract. Native-only does not silently OCR. OCR-only
renders a temporary page image, extracts it and removes the temporary image.
Document extraction processes every page sequentially into a materialized list.
toText groups by block/paragraph/line, orders groups by vertical geometry and
words by horizontal geometry, joins tokens with spaces/lines with newlines;
it does not preserve typography or infer tables. Table reconstruction belongs
to [Table Extractor](TABLE_EXTRACTOR_API_v1.md).

renderPdfPage normalizes outputPath, creates its parent and replaces it using
`file rename -force`. It is an explicit host file-writing operation, not a
create-only publication API. Choose an owned destination; use the normal
[File Publication](FILE_PUBLICATION_API_v1.md) owner for canonical/export policy.

## Context, limits and exposure

These host functions accept explicit filesystem paths; no Session is required
for file/layout operations. They run external tools synchronously and declare
no Job cancellation, universal page/byte/time/word bound or paged result API.
Large whole-document extraction materializes its outputs; no silent truncation
or bounded-memory promise is invented. Tesseract uses Runtime tool resolution
when available; Poppler paths use installed executable lookup.

Missing files/tools, bad options/ROI/PSM/page/DPI, invalid page count/TSV and tool
failures raise actual errors, generally prefixed `ocr.layout API v1:`. Auto mode
may legitimately catch a native-text failure before its OCR fallback. A returned
layout is not proof of scientific source correctness or measurement quality.

There is no registered Python/Octave Bridge family or typed C++ SDK method for
this API in the retained/current reviewed scope. Do not synthesize gxtxt_api_call
or a generic C++ invoke from catalog visibility. Existing Viewer clients and
Dataset Preview use this same public CORE owner. A safe host discovery example:

```tcl
set info [::GX::OCRLayoutAPIv1::apiInfo]
set canRender [::GX::OCRLayoutAPIv1::supports pdf_page_render]
```

This example only resolves metadata/paths; it does not execute OCR or validate a
tool version. No new runtime/GUI/scientific tests were run for this reference.
