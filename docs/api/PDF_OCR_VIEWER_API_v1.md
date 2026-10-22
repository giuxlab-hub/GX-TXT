# PDF OCR Viewer activation API v1

SPDX-License-Identifier: GPL-3.0-or-later

Provider `viewer.pdf_ocr` declares this version1 family in
`api/pdf_ocr_viewer_api_v1.tcl`, namespace `::GX::PdfOcrViewer`. Viewer ID
`pdf_ocr` uses backend `pdf_ocr_tk`. This family activates the native desktop
adapter; it is not the CORE OCR Layout API or the separate PDF Reader.

## Exact public entry and result

`::GX::PdfOcrViewer::viewerDispatch action scene` has two required arguments,
no defaults. It supports `open` and `rerender`, otherwise raises
`Unsupported PDF OCR Viewer action ...`. It currently ignores scene/context.
The normal trusted-host route is:

```tcl
set receipt [::GX::viewerOpen viewer.pdf_ocr pdf_ocr]
```

The backend returns `{status opened pid ...}` for a launched adapter or
`{status focused pid ...}` after successfully sending FOCUS to its existing
channel. The PID value is Tcl's process-ID list for that channel; the return is
**not a Tk widget path, OCR result or committed Workspace**. First launch
requires a current Session, a Python3 executable, Python tkinter/Pillow, and
`pdfinfo`, `pdftoppm`, `tesseract`, `ocrmypdf`, `qpdf`. It launches the installed
`python/pdf_ocr_viewer.py` with CORE Python path and retains its IPC channel.
The existing-channel focus branch runs before the launch-time Session check;
do not infer current-Session revalidation from a focused receipt alone.

## Data ownership and units

The desktop lists canonical Session Datasets satisfying `document.pdf` and
resolves payload identity through public Session Inspection/Metadata. Named
workspace payloads use Interactive Document owner `viewer.pdf_ocr`, provider
`pdf_ocr`, schema `gxtxt.pdf_ocr.workspace`, version1.0. Update/delete check
current Session token and exact owner. Derived text, crop images and OCR-PDF
are published by Dataset File Publication; original PDF is not overwritten by
these publication paths. Publication carries source Dataset ID and engine,
language/page/ROI/DPI provenance as applicable.

`document.text` is UTF-8; crop output is `image.raster`/PNG; OCR-PDF is
`document.pdf`. ROI provenance fields named `*_px` are pixels; render DPI is
dots per inch. These are rendering coordinates/metadata, not calibrated
scientific coordinates, measurement uncertainty or OCR accuracy. The adapter
supplies no public cross-language extraction-result schema. Full input/output
schemas and scientific semantics remain with their actual publication/OCR owners.

Its underscore-prefixed IPC commands (bootstrap/source/document/publication)
are private transport between this installed desktop and host, not public
Script operations. A source file in such a message is not a consumer-granted
filesystem API. Do not call `_handleRequest`, write its channel or create a
second Document/Dataset registry. Public lifecycle/services are the authorities.

## Errors, exposure and limitations

Errors distinguish no Session, incompatible source contract, stale token,
foreign Document owner, missing dependencies/adapter and process-launch
failure. IPC callbacks send their original diagnostic in an error response.
GUI engine success, source identity completeness and a committed Dataset are
separate from an activation/focus receipt. The facade itself declares no
universal PDF byte/page limit, OCR confidence bound or complete argument
metadata for its private protocol; no such contract is invented here.

The family has no registered Python/Octave Script Bridge operation and no
typed C++ SDK method. Catalog presence does not grant runtime access; no
generic C++ invoke exists. See the module's installed MANUAL.md,
[Viewer Provider](VIEWER_PROVIDER_API_v1.md),
[Interactive Document](INTERACTIVE_DOCUMENT_API_v1.md),
[Session Inspection](SESSION_INSPECTION_API_v1.md) and
[File Publication](DATASET_FILE_PUBLICATION_API_v1.md).
