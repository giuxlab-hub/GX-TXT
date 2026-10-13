# GX-TXT Session Inspection API v1

License: GPL-3.0-or-later

## Purpose

Session Inspection API v1 is a read-only public surface for exporters,
archival tools and presentation modules. It exposes structured Session facts
without requiring modules to read private CORE registry arrays or registry file
layouts.

Public entry points:

```tcl
::GX::sessionInspectionSummary ?session?
::GX::sessionInspectionDatasetIds ?session?
::GX::sessionInspectionDataset datasetId ?session?
::GX::sessionInspectionDatasetPayload datasetId ?session?
::GX::sessionInspectionCurrentSession
::GX::sessionInspectionResolveResource relativePath ?session? ?expectedSha256?
::GX::sessionInspectionSelectionIds ?session?
::GX::sessionInspectionSelection selectionId ?session?
::GX::sessionInspectionFileInventory ?session?
::GX::sessionInspectionWriteSnapshot path ?session?
```

The optional Session argument defaults to the open Session.

`sessionInspectionCurrentSession` returns the validated current Session path
for a module that must create Session-owned resources. It does not expose
private CORE state. `sessionInspectionResolveResource` resolves a relative
Session file, rejects escape and symlink paths, computes SHA-256 and can
require an expected digest. It returns path, relative path, size and digest.

`sessionInspectionSelectionIds` and `sessionInspectionSelection` query
persistent Dataset Selection records directly from the named Session without
loading or replacing global Selection registry state. Stable Dataset and
variable IDs remain the Selection authority. For current-Session editable
selection operations, use Dataset Selection API v1.

`sessionInspectionDatasetPayload` returns `dataset_id`, absolute `path`,
Session-relative `relative_path`, canonical `sha256`, `format`, and `contract`.
It rejects missing payloads, paths outside the Session, symlinks, and content
whose digest differs from the canonical Dataset registry. Viewer modules should
use this public call to select imported geometry and scientific data.

## Snapshot

`sessionInspectionWriteSnapshot` writes UTF-8 `GXTXT_SESSION_INSPECTION_V1`.
Records contain a category, object identity, field and value; variable fields
are Base64 encoded so arbitrary UTF-8 and line breaks remain unambiguous.

The snapshot includes the Session summary, manifest fields, Dataset registry
fields, Dataset Metadata through the public metadata API, Dataset notes through
the public notes API, and an SHA-256 file inventory. It is a read-only export
snapshot, not authoritative Session storage.

## Security and scope

File inventory is Session-root scoped and does not expose arbitrary external
filesystem trees. Consumers must continue to treat labels, filenames, notes
and file content as untrusted data and escape/sanitize them for their target
format.

Dev083 adds `sessionInspectionMarkdownDocuments ?session?` for verified document-only
discovery without hashing scientific payloads. Unavailable files carry explicit diagnostics.

## dev084 availability without payload scans

`sessionInspectionDatasetLocation datasetId ?session?` reuses the guarded Dataset
path resolver, rejects escape/symlink/missing payloads and requires the recorded
canonical digest. It returns dataset_id, path, relative_path, expected_sha256,
size_bytes, format, contract and `integrity=not_checked`; it does **not** hash/read
scientific payload bytes. `sessionInspectionDatasetPayload` retains its original
return fields and verifies SHA-256 using this same location guard.

Script Bridge `SESSION_INSPECTION_API_v1.dataset_location(dataset_id)` provides the
current-Session availability record to Python/Octave, omitting absolute `path`.
Read-only availability is not proof of payload integrity or module execution.

## Current Dataset section documents (dev096 host service)

`datasetInspectionSectionDocument dataset_id section ?request?` returns the
complete UTF-8 text of `notes`, ordinary `metadata`, explicitly selected
`technical` inspection, `variables`, or `temporal` sets. The result contains
`dataset_id`, `section`, `source`, `text`, and the current `session_token`.
It projects the existing Notes/Metadata/Schema/Temporal owners and does not read
or rewrite scientific payloads or implement a separate metadata authority.

The default request is `source saved`. GUI hosts may supply `source draft`
and the relevant `notes`, `metadata`, or `variables` value. Metadata's optional
`pending_metadata` is an inert `{key value}` dictionary for the editor's typed,
unapplied buffer. Reserved CORE keys are omitted from both ordinary values and
that buffer. Draft documents are visibly identified as unsaved; the operation
does not save edits. Dataset/plot images retain their existing rendering owner.
This projection accepts current GUI editor context and is intentionally host-only;
scripts retain the existing structured Session Inspection and Metadata APIs.
