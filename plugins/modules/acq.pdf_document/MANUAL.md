# PDF Document Import — Manual

## Purpose

`acq.pdf_document` imports Portable Document Format files as normal GX-TXT canonical Datasets. The acquisition boundary is intentionally narrow:

```text
PDF source
→ content/structure validation
→ original bytes preserved
→ document metadata
→ document.pdf Dataset
```

One source PDF always corresponds to one Dataset. Multiple selected PDFs therefore create multiple independent Datasets rather than one merged document.

## Dataset contract

The plugin provides the contract:

```text
document.pdf
```

A valid `document.pdf` Dataset guarantees only:

- a structurally readable PDF payload;
- byte-for-byte preservation of the imported source snapshot;
- a stable GX-TXT Dataset ID;
- canonical GX-TXT SHA-256 provenance;
- `document.format=PDF`;
- `document.page_count >= 1`.

The Dataset does not imply an extractable text layer, searchable text, rendered pages, a title, an author, unencrypted content or any OCR result.

## Single import

Choose **Acquisition → PDF Document Import**, select a source, confirm the Dataset ID and run the acquisition. GX-TXT owns the RAW snapshot, Dataset registration, SHA-256 provenance and Session persistence. The plugin validates and copies only the authoritative preserved PDF bytes into the canonical Dataset payload.

## Multiple / batch import

The module declares normal Acquisition Handler batch capability. Use the framework source-batch table to add one or several PDFs, including multi-select where available. Each enabled row has its own editable Dataset ID and becomes one independent Dataset.

Suggested Dataset IDs are derived from filenames by the existing GX-TXT batch UI and are not the technical identity of the source file. The original filename is preserved as metadata.

Duplicate Dataset IDs must be resolved before they can coexist in one Session.

## Validation

A `.pdf` extension is not trusted. The importer requires a PDF header signature and successful structured parsing sufficient to establish the mandatory page count. A non-PDF renamed to `.pdf`, a fatally truncated document, or a zero-page unusable document is rejected.

A valid PDF stored under a non-`.pdf` filename is accepted when selected through a workflow that permits it, because content is authoritative.

The inspection backend is Python `pypdf`, called directly with an argv list. The source file is never passed through shell interpolation.

## Original source preservation and integrity

The framework creates its normal RAW acquisition snapshot. The plugin revalidates that exact RAW file, copies it byte-for-byte to the canonical Dataset payload and verifies:

```text
SHA256(source at import)
=
SHA256(framework RAW snapshot)
=
SHA256(canonical PDF payload)
```

If the selected source changes while import is in progress, the import fails explicitly.

Authoritative SHA-256 values are stored by the existing Dataset Registry fields `source_sha256`, `canonical_sha256` and `sha256`. The plugin therefore does not duplicate the source hash as a second Dataset Metadata key.

## Dataset Metadata

Contract-required document/provenance properties are represented through the existing Dataset Registry plus Dataset Metadata. The mandatory Dataset Metadata keys are:

```text
document.format=PDF
document.page_count=<integer >= 1>
source.filename=<original filename>
source.size_bytes=<original byte count>
```

The source SHA-256 is mandatory provenance but is stored in the canonical Dataset Registry rather than duplicated as a Dataset Metadata key. The importer currently also records `pdf.version` and `pdf.encrypted` when the inspection backend establishes them; these remain optional contract metadata and consumers must not require them. Other optional metadata is written only when actually available:

```text
pdf.version
pdf.encrypted
pdf.title
pdf.author
pdf.subject
pdf.keywords
pdf.creator
pdf.producer
pdf.creation_date
pdf.modification_date
```

Missing optional metadata never invalidates an otherwise valid PDF Dataset.

## Encryption policy

Encryption is a property of `document.pdf`, not a separate Dataset contract.

If an encrypted PDF can be inspected without a supplied password and the mandatory page count can be established, import succeeds with:

```text
pdf.encrypted=true
```

If encryption prevents establishing the mandatory contract properties, import fails with an explicit diagnostic. The module does not crack passwords, repeatedly prompt for passwords, decrypt the authoritative source or rewrite it.

## Invalid or corrupt documents

Fatal structural errors fail the import. The source is treated read-only. The importer never repairs or rewrites malformed PDFs automatically.

Optional metadata failures are fail-soft: the missing optional field is omitted and the valid Dataset may still be imported.

## Dataset Metadata and Notes

After import, the document uses the normal GX-TXT **Variables → Metadata...** and Dataset Notes infrastructure. There is no PDF-private metadata editor and no PDF-private notes store.

## Session save / reopen

PDF Datasets are Session-scoped and use the ordinary Dataset Registry and Session storage. On reopen, Dataset IDs, canonical payload paths, hashes, provenance and Dataset Metadata are restored by the existing GX-TXT infrastructure.

## Future viewers and transformations

The canonical PDF bytes live inside GX-TXT-managed Session storage. Future consumers can therefore open a PDF Dataset without depending on the original external filesystem path.

A later workflow may perform page rendering, OCR or curve digitalization as a separate transformation, for example:

```text
PDF Dataset
→ select page
→ render derived page resource
→ image / curve consumer
```

None of those transformations is part of `acq.pdf_document`.

## Limitations

- No OCR is performed by this acquisition module.
- No text extraction is performed during normal acquisition.
- No page rasterization or thumbnails are generated.
- No PDF repair, optimization, editing or annotation is performed.
- Password entry is not implemented; password-protected PDFs that hide mandatory contract properties are rejected.
- The module requires Python `pypdf`.

## Public GX-TXT APIs used

- Standard Module API v1
- Acquisition Handler Plugin API v1
- Canonical Dataset API v1
- Dataset Metadata API v1
- Binary Dataset Foundation v1
- Preview Descriptor API v1
- Contract Registry API v1
- Plugin Install API v1
- Documentation API v1

The module uses `variable_mapping=none`; no fake page, byte, text, X or Y variables are created.
