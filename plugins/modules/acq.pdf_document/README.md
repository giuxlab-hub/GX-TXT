# acq.pdf_document 1.0.1

`acq.pdf_document` is the native GX-TXT acquisition plugin for preserved PDF documents.

Each selected source PDF becomes one independent canonical `document.pdf` Dataset. The importer validates PDF content and structure, preserves the original bytes exactly, exposes mandatory page count and format identity, and publishes available document metadata through Dataset Metadata API v1.

The module deliberately does **not** perform OCR, text extraction, page rendering, embedded-image extraction, PDF repair, optimization, editing, annotation or indexing.

## Requirements

- GX-TXT 0.9.7.81 or later.
- Python 3.
- `pypdf` available to the Python runtime used by GX-TXT.

The validated module is bundled with GX-TXT 0.9.7.81 as CORE / ALWAYS. It is
not an externally managed plugin and is not installed from this ZIP by users.

See `MANUAL.md` for the user workflow, validation scope and architecture.
