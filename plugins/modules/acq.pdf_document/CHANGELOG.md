# Changelog

## 1.0.1

- Make this external acquisition module ALWAYS available in the Module Manager (`selectable=0`, `core=0`); imports still occur only on user action.
- Route nonfatal pypdf structural warnings through the inspection protocol so older, readable PDFs are accepted without corrupting the protocol stream.
- Require GX-TXT 0.9.7.81 for generic transactional batch import and retry.

## 1.0.0

- Added native `document.pdf` acquisition.
- Added content/signature and structured PDF validation using `pypdf`.
- Added mandatory PDF page count and format identity; PDF version/encryption status are recorded when established but are not required by the minimum `document.pdf` contract.
- Added byte-for-byte canonical preservation with SHA-256 integrity verification.
- Added optional standard PDF document metadata extraction.
- Added explicit encrypted-PDF policy.
- Added normal GX-TXT multi-source batch capability and metadata-only Dataset preview; full per-row rollback/status semantics use the generic GX-TXT 0.9.7.79 Acquisition Handler transaction hardening.
- Added Plugin Install API packaging, documentation and regression tests.
- OCR, text extraction, rendering, repair, optimization, editing and annotation remain out of scope.
