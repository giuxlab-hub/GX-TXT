# CORE Table Extractor API v1

SPDX-License-Identifier: GPL-3.0-or-later

CORE owner `core/tcl/table_extractor_api_v1.tcl`, namespace
`::GX::TableExtractorAPIv1`, reconstructs tables from OCR Layout positioned words.
It is independent of Viewer/Analysis Run selection, and distinct from the two
module-qualified Table Extractor Viewer adapters. It does not publish a Dataset
or infer physical semantics/uncertainty merely by extracting a matrix.

## Exact public host entries

| Signature | Arguments/defaults | Result |
|---|---|---|
| `capabilities` | none | capability string list |
| `supports capability` | required exact capability string |0/1 membership |
| `apiInfo` | none | API name/version/owner/capabilities and nested actual OCR Layout apiInfo; missing required OCR methods error |
| `extractLayout layout ?options?` | required positioned-word dict; options default `{}` | extraction envelope described below |
| `extractImage imagePath ?options?` | explicit image file; options default `{}` | public OCR image extraction followed by extractLayout |
| `extractPdfPage pdfPath page ?options?` | explicit PDF file and1-based page; options default `{}` | public OCR page extraction followed by extractLayout |
| `extractDataset session datasetId ?options?` | explicit Session directory/ID; options default `{}` | same extraction plus source_dataset_id/source_contract |
| `tableToMatrix table` | required table dict containing matrix | exact matrix field |
| `tableToCsv table ?options?` | table and options default `{}` | escaped CSV text, no file write |
| `inferSchema table ?options?` | table and options default `{}` | columns/data_rows/header metadata, no Dataset commit |

Capability IDs are layout_input, dataset_input, image_input, pdf_input,
normalized_geometry, row_clustering, column_inference, table_reconstruction,
matrix_export, csv_export and schema_inference. Support does not prove tools or
source suitability. apiInfo uses existing OCR command discovery/dependency paths,
not an extraction test.

## Options and source admission

| Key | Default / constraints | Meaning |
|---|---|---|
| expected_columns |0; nonnegative integer |0 automatic; otherwise preferred reconstruction column count |
| split_repeated_headers |1, Tcl boolean use | use repeated textual-header anchors to split tables |
| page |1, positive integer | PDF Dataset page; ignored for raster source |
| separator | comma; exactly one character | tableToCsv only |
| first_row_header |1, Tcl boolean use | inferSchema only |

Image/PDF methods forward method, languages, psm, dpi, roi, min_confidence and
native_min_words to the existing [OCR Layout](OCR_LAYOUT_API_v1.md) owner with
its exact defaults/ranges. Options must be Tcl dicts; unknown keys are not
globally rejected by a separate schema. Do not confuse GUI choice limits with
these service options.

extractDataset requires an existing Session, readable canonical payload and
contract compatible with image.raster/document.pdf. It uses public Session
Inspection/contract/path resolution; unsupported contracts error. File/layout
methods do not themselves require a current Session. No source file/Dataset is
modified by these extraction/serialization methods.

## Input and result shape

extractLayout requires `layout.words`, each word supplying the geometry/text
used by OCR Layout: x_norm, y_norm, width_norm, height_norm, cx_norm, cy_norm,
text and optional confidence. The service assumes that upstream positioned-word
contract; it does not independently validate every coordinate/field. Coordinates
and box/boundary values are dimensionless normalized page/image coordinates.
OCR source coordinate_unit remains px/pt metadata; no physical calibration is
inferred.

The envelope contains api_version1, source, word_count, table_count and tables.
Source copies available source_kind/source_path/page/method/coordinate_unit/
page_width/page_height/roi_normalized/render_dpi. A table has table_index,
row_count, column_count, matrix (rows of strings), rows (structured rows),
boundaries_norm, bbox_norm and confidence. Structured rows contain row_index,
bbox_norm and cells. Cells contain zero-based row/column, text, confidence,
bbox_norm and the contributing words. Empty extraction returns table_count0 and
an empty table list, rather than fabricating a blank numerical table.

Rows are clustered by normalized centers/heights; recurring horizontal gaps
infer boundaries. Repeated predominantly textual header rows can start separate
tables. Sparse data may not provide expected_columns: it is not a guarantee or
permission to invent equally spaced columns. Confidence is a mean of available
nonnegative input scores (or-1 when unavailable), not a probability of a correct
table, scientific accuracy or an uncertainty estimate. Review extraction and
headers before publication.

tableToCsv quotes separator/quote/newline/carriage-return fields, doubles quotes,
joins rows with newline and does not add a trailing newline or write a file.
inferSchema pads short rows to maximum width, optionally consumes first row as
labels, generates lowercase legal-ish stable column IDs (up to80 characters
before duplicate suffix), and suffixes repeated bases. Columns contain id, name,
dtype, empty unit and empty semantic_role. Dtype is int64/float64/string based
on textual recognition; any empty cell forces string. Unicode minus/dash is
normalized **for type inference only**; returned data_rows retain original cell
text. Decimal-comma, thousands separators, numeric range/overflow and scientific
semantics are not independently normalized/validated here. An empty input matrix
returns only `columns {}` and `data_rows {}`; `first_row_header` is absent in
that early-return result. Final Variable IDs, types and values must pass the
real Schema/Publication owner.

## Errors, bounds and languages

Missing OCR/public Dataset capabilities, malformed options/layout/matrix,
negative/noninteger expected_columns, invalid page/CSV separator, unreadable or
unsupported Dataset and external OCR failures raise existing owner errors,
generally `table.extractor API v1:` or the delegated OCR diagnostic. No universal
table/sample/byte/time bound, streaming output or asynchronous Job contract is
declared here; reconstruction/matrices are materialized in memory.

No Python/Octave Script Bridge family or typed C++ `gx::Host` method is registered
for this API in the retained/current scope, and no generic C++ invoke exists.
Trusted host consumers use these public commands and
[Dataset Publication](DATASET_PUBLICATION_API_v2.md)/
[Variable Schema](DATASET_VARIABLE_SCHEMA_API_v3.md) for explicit canonical output.
Inert host serialization example (not an executed scientific test):

```tcl
set table [dict create matrix {{name value} {example 2}}]
set csv [::GX::TableExtractorAPIv1::tableToCsv $table]
set schema [::GX::TableExtractorAPIv1::inferSchema $table]
```

This does not prove OCR reconstruction, scientific units, publication or runtime
acceptance. Actual Viewer adapters reuse this CORE owner where declared.
