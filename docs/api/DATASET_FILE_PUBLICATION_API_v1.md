# Dataset File Publication API v1

SPDX-License-Identifier: GPL-3.0-or-later

Dataset File Publication API v1 is the public, headless CORE operation for registering an already-produced regular file as a Canonical Dataset. It is intended for service modules, including Viewer Provider backends, that have a complete file but do not run through the Analysis GUI lifecycle.

It does not define a new Dataset Registry or storage model. The operation uses the existing Canonical Dataset Registry, Session-owned `datasets/` storage, SHA-256 service, Dataset Metadata API v1 and publication ownership rules.

## Public operation

Research scripts can call the provider-owned Script Bridge `publish` operation
with the same request fields. The source file must be a completed file under
the configured script `runtime.output_dir`. The Bridge returns the Dataset ID
and authoritative SHA-256 but omits the internal storage path.

```tcl
set result [::GX::datasetFilePublicationPublish $session $moduleId $request]
```

`request` is a Tcl dictionary with these required fields:

```text
dataset_id
contract
format
source_file
storage_kind       text | binary
media_type
```

Optional fields are:

```text
producer_version
source_dataset_ids
source
provenance
notes
structured_metadata
replace_owned
```

The caller never supplies the authoritative SHA-256 and never edits `metadata/datasets.ini`. `source_file` is an input to the transaction and its absolute location is not stored as persistent module state.

```tcl
set published [::GX::datasetFilePublicationPublish \
    $session my.viewer.service [dict create \
        dataset_id extracted.text \
        contract document.text \
        format txt \
        source_file $temporaryUtf8File \
        storage_kind text \
        media_type text/plain \
        source_dataset_ids [list source.pdf] \
        provenance "Text produced from source.pdf" \
        structured_metadata [dict create document.language en]]]
```

The result contains the stable Dataset ID, contract, format, storage kind, media type, Session-relative path and CORE-computed SHA-256.

## Transaction and ownership

CORE validates the request and source, copies to a private staging file, computes SHA-256, atomically places the payload in Session-owned storage and commits the normal Dataset Registry entry. Structured metadata, when supplied, is committed through Dataset Metadata API v1 in the same outer transaction.

Any failure restores the previous in-memory/file registry state, previous same-owner payload and previous structured metadata. A failed new publication leaves no registered Dataset, authoritative payload, partial staging file or valid-looking metadata sidecar.

Publication is create-only unless `replace_owned=true`. Replacement is allowed only when the existing Dataset was published through this API by the same `module_id`; it retains the established Session-relative target. A foreign or legacy Dataset ID is never overwritten.

## File and schema semantics

`storage_kind=text` requires valid UTF-8 and preserves the original bytes. `storage_kind=binary` treats the payload as opaque bytes. Contracts and media types are plugin-declared rather than enumerated by CORE.

File/document Datasets legitimately contain no Variables. Their registry shape explicitly records:

```text
variables={}
units={}
semantic_roles={}
var_count=0
variable_schema_api_version=3
```

`source_dataset_ids` records stable lineage without copying the source Dataset. Every named source Dataset must already exist in the same Session.

## Distinction from related APIs

- Dataset Publication API v1 consumes completed analysis-module publication requests only after the normal analysis runner succeeds.
- Dataset Publication API v2 is a schema-first CSV/HDF5 writer lifecycle for structured variables, dimensions and bounded writes.
- Acquisition Handler API v1 imports external acquisition sources.
- Interactive Document API v1 owns editable authoritative UTF-8 documents; it is not the generic Canonical Dataset file-publication primitive.

This API performs no OCR, PDF/image interpretation, viewer activation, Octave execution or Tk initialization.

## Simple file helper (dev-051)

`::GX::datasetFilePublicationPublishAuto session module_id request` requires `dataset_id`, `contract` and `source_file`. It delegates to the same existing owned-file transaction. Optional `format_id` selects a declared Acquisition Format Registry record; otherwise extension and unambiguous registry records supply format/media defaults. PNG/JPEG/TIFF, WAV and PDF have standard MIME fallbacks. Neutral mesh/CAD/chemistry or ambiguous formats require an explicit `media_type`/`format` when their installed registry does not supply one. The helper does not infer scientific column schemas or context-dependent meanings. Contract discovery remains `CONTRACT_REGISTRY_API_v1`; file format discovery remains `ACQUISITION_FORMAT_REGISTRY_API_v1`.

`publish_auto` and the existing explicit `publish` are available in both Script Bridge languages. Completed source files must resolve within the current framework-owned script output directory, including symlink resolution. External, missing and incomplete sources fail; raw Registry/Manifest editing is not permitted. Metadata/provenance/ownership options retain the explicit API's rules.

```python
gxtxt_api_call('DATASET_FILE_PUBLICATION_API_v1', 'publish_auto',
    [{'dataset_id':'result_image', 'contract':'image.raster',
      'source_file':str(output_dir / 'result.png'),
      'structured_metadata':{'processing.method':'simulation'}}])
```

## Dev-070 producer-authorized file edits

`::GX::datasetFileEditAuthorize producerCapability session datasetId editorModule`
grants an edit of one existing `geometry.sketch`, `document.pdf` or `document.text`
revision. CORE authenticates the producer capability, then stores a reserved private
metadata grant bound to normalized Session location, exact Dataset ID, original
producer, contract, SHA-256 and editor. Copying private metadata to another identity
or Session does not confer permission. Successful content revision changes invalidate
the old grant. Reauthorization is explicit. This does not grant general namespace
write authority. Producer ownership remains unchanged; last editor is recorded.

Existing publication accepts optional `expected_sha256` for optimistic commits and
`replace_owned 1` for own or explicitly delegated updates. Existing file, metadata
and registry rollback remains authoritative, including imported acquisition files.

Script Bridge `DATASET_FILE_PUBLICATION_API_v1.authorize_edit` takes one request
`{dataset_id, editor_module}`. The host derives the producer from execution identity;
the script cannot assert another producer. An authorized editor must still publish
through the normal transaction. Public APIs trust in-process modules under GX-TXT's
existing capability model; this is not an operating-system sandbox.


Dev087's explicit Native3D Save High-Resolution Image action uses this API with
producer `core.native3d`, `image.raster`/PNG, create-only IDs and transactional metadata.
It records the originating graph/Variant, canonical source IDs/hashes/bindings,
image dimensions, exact current camera/projection, calibrated axis/grid and scalar
settings, requested/effective graphics policy and supersampling. Preview/navigation/
enlargement do not publish. Existing Dataset GUI/metadata/registry remain authoritative.

## dev093 local transaction authority

File publication and edit grants participate in the shared per-Session Dataset
transaction. Ownership, immutable protection, namespace and optional expected SHA
are validated under the same lock as the recoverable payload/metadata/registry
commit. See [Dataset Publication v2](DATASET_PUBLICATION_API_v2.md).
