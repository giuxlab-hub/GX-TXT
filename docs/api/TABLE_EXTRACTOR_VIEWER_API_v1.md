# Table Extractor Viewer activation API v1

SPDX-License-Identifier: GPL-3.0-or-later

`viewer.table_extractor` declares this version1 family in
`api/table_extractor_viewer_api_v1.tcl`, namespace `::GX::TableExtractor`.
Viewer ID `table_extractor` uses backend `table_extractor_tk`. This is distinct
from `viewer.document_extractors`' same-named Viewer ID and from CORE
TABLE_EXTRACTOR_API_v1. Always qualify the module.

```tcl
set receipt [::GX::viewerOpen viewer.table_extractor table_extractor]
```

## Public signature and context

`::GX::TableExtractor::viewerDispatch action scene` requires both arguments and
has no defaults. It supports `open`/`rerender`; scene/context is currently
ignored. Its result is `{status opened pid ...}` or `{status focused pid ...}`,
not a Tk path/table/publication result. The PID is the channel process-ID list.
Unsupported actions error explicitly. Existing Viewer dispatch controls normal
installation/presentation activation.

First launch requires a current Session, Python3, Python tkinter/Pillow, and
`pdfinfo`, `pdftoppm`, `pdftotext`, `tesseract`. It opens installed
`python/table_extractor.py` over retained IPC. A live existing channel is first
sent FOCUS; that branch precedes the launch-time Session check. A focused
receipt alone is not proof of current-Session data admission.

## Actual document/publication boundaries

Eligible canonical sources satisfy `image.raster` or `document.pdf` and are
resolved through existing Session Inspection/Metadata. Interactive Documents
use owner `viewer.table_extractor`, provider `table_extractor`, schema
`gxtxt.table_extractor.workspace`, version1.0. Update/delete check current
Session token and exact owner. Private IPC request names are not public methods.

The current table publication path checks Session token, current source SHA,
nonempty columns/rows, legal unique Variable IDs and equal row widths. Supported
column types are `int64`, `float64`, `string`. It writes rank-one Variables on
an extendible row dimension through Dataset Publication v2, producing
`table.generic`/CSV with owned replacement policy. It writes explicit empty
unit and semantic-role fields: the extractor **does not infer physical units**.
Column labels are added through the Schema owner. Source SHA, page, pixel ROI,
method/language/PSM and row/column counts are retained as metadata.

These are implementation-backed workflow boundaries, not permission to invoke
`_publishTable` or send a raw channel request. Consumers should use the actual
public CORE Table Extractor and Dataset Publication contracts. The activation
family declares no public extraction options/result schema or universal table
size limit; do not invent a cross-language headless extraction call from it.

## Errors and language access

No Session, incompatible source, stale token, changed source SHA, foreign
Document, malformed table, unsupported dtype, duplicate column ID, failed
publication and missing dependency/adapter are explicit failure paths.
Activation success proves only adapter launch/focus. Output numeric values,
OCR correctness, headers, locale and extraction quality still require review
and the scientific owner's validation; physical uncertainty is not measured.

No Python/Octave Script Bridge family or typed C++ `gx::Host` method is
registered for this activation API. No generic C++ invoke exists. Related
authorities are [Viewer Provider](VIEWER_PROVIDER_API_v1.md),
[Interactive Document](INTERACTIVE_DOCUMENT_API_v1.md),
[Dataset Publication](DATASET_PUBLICATION_API_v2.md),
[Variable Schema](DATASET_VARIABLE_SCHEMA_API_v3.md) and the installed module's
MANUAL.md/DEPENDENCIES.md. The separate
[CORE Table Extractor](TABLE_EXTRACTOR_API_v1.md) reference documents the actual
extraction service rather than this desktop activation adapter.
