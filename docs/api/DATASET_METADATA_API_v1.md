# Dataset Metadata API v1

SPDX-License-Identifier: GPL-3.0-or-later

Dataset Metadata API v1 stores one generic structured metadata resource for
each canonical Dataset ID. It is separate from scientific data, Variable
Schema, provenance fields in the Dataset registry, and free-form Dataset Notes.

CORE persists the resource and owns its lifecycle. Importers and other callers
define the meaning of fields. CORE does not interpret audio, image,
experimental or other domain metadata.

## Storage model

The Dataset registry stores structured_metadata_file, a session-relative link
to one UTF-8 INI sidecar under:

    metadata/datasets/<dataset-stem>.ini

The sidecar records the Dataset ID and an arbitrary set of generic string
keys. Dot-separated namespaced keys are recommended for domain-specific
metadata, while simple keys are also valid for portable/generator metadata.
Unknown keys are retained. Dataset IDs that need filesystem normalization
receive a deterministic CRC suffix so distinct IDs cannot share a sidecar
accidentally.

## Public Tcl API

    set metadata [::GX::datasetMetadataRead $session $datasetId]

    ::GX::datasetMetadataWrite $session $datasetId $metadataDictionary

    set merged [::GX::datasetMetadataUpdate \
        $session $datasetId $updatesDictionary]

    set remaining [::GX::datasetMetadataUnset \
        $session $datasetId {audio.encoder tags.legacy}]

datasetMetadataRead returns an empty dictionary when no resource has been
written yet. datasetMetadataWrite replaces the complete resource explicitly.
datasetMetadataUpdate reads and merges the existing resource, so fields unknown
to the caller are preserved. datasetMetadataUnset removes only the named keys.

Keys may be simple generic identifiers such as `description` or `function`, or
dot-separated namespaced identifiers such as `audio.title`, `image.exposure`,
`experimental.temperature` or `source.original_filename`. Key segments may use
letters, digits, underscores and hyphens. Values are opaque UTF-8 strings and
may contain line breaks in the persistent API.

All write operations verify that the Dataset ID exists. The sidecar path is
restricted to the session metadata/datasets directory.

## Lifecycle

- A newly imported or published Dataset may receive metadata through the API.
- Metadata survives registry save and session reopen.
- Updating a Dataset does not discard fields owned by other importers.
- datasetDelete removes the sidecar in the same staged lifecycle transaction
  used for canonical storage and Dataset Notes.
- Deleting one Dataset never removes another Dataset resource, even if a
  malformed registry attempts to share a path.

Variable Schema and Dataset Notes remain independent APIs and storage
resources.

## Importer examples

A future audio importer can attach container tags after it creates or publishes
the canonical Dataset:

    set audioMetadata [dict create \
        audio.title "Calibration sweep" \
        audio.artist "Lab A" \
        audio.album "2026 tests" \
        audio.codec "pcm_s24le" \
        audio.container "wav" \
        source.original_filename "sweep-01.wav"]
    ::GX::datasetMetadataUpdate $session audio.recording01 $audioMetadata

A future experimental importer can add acquisition conditions without CORE
knowing their scientific meaning:

    set runMetadata [dict create \
        experimental.temperature_C "350" \
        experimental.pressure_kPa "240" \
        experimental.sample "catalyst-B" \
        experimental.instrument "reactor-02" \
        experimental.reactor_conditions "continuous flow"]
    ::GX::datasetMetadataUpdate $session reactor.run17 $runMetadata

The two importers use the same API and storage model. No domain-specific fields
are built into CORE.

## GUI

The Variables workspace exposes **Metadata...** for the selected imported
Dataset. The generic editor lists all fields and supports add/update, remove,
**Import...**, **Export...** and **Save**. Changing the selected Dataset closes a
stale editor; reopening **Metadata...** loads the resource for the new
selection.

### Portable Import / Export text format (GX-TXT 0.9.7.74)

**Import...** and **Export...** are convenience operations on the editor's
current in-memory metadata dictionary. They do not introduce a second metadata
store and they do not bypass Dataset Metadata API v1.

The portable file is UTF-8 plain text with one field per line:

```text
reference.function=y=sin(x)+0.1*x
reference.sampling=sparse nonuniform
reference.noise=none
description=Interpolation validation dataset
```

Rules:

- the first `=` character separates the key from the value, so later `=`
  characters remain part of the value;
- blank lines are ignored;
- a line whose first non-whitespace character is `#` or `;` is a comment;
- `#` and `;` inside a normal value are ordinary value characters;
- surrounding whitespace around the key and value is trimmed on import;
  whitespace inside the value is preserved;
- the whole file is parsed and validated before the editor is changed;
- malformed lines report their line number and do not produce a partial import;
- duplicate keys are deterministic: the last occurrence in the imported file
  wins;
- importing merges into the current editor state: new keys are added, matching
  keys are replaced, and unrelated editor fields remain untouched;
- imported changes remain unsaved until the user selects **Save**;
- closing without **Save** keeps the existing editor semantics and discards
  uncommitted changes;
- **Export...** serializes the current editor state, including unsaved edits,
  without implicitly saving the Dataset;
- exported keys are sorted deterministically;
- the normal default filename is `<dataset>.metadata.txt` and ordinary `.txt`
  files are also accepted.

Because this portable representation is deliberately one physical field per
line, values containing CR/LF line breaks cannot be represented losslessly.
**Export...** therefore reports an explicit error for such a value instead of
silently corrupting it. The persistent Dataset Metadata API itself continues to
support multiline UTF-8 values.

A typical review flow is:

```text
Open Dataset Metadata
→ Import...
→ review/edit merged fields
→ Save
```

Export can be used independently:

```text
edit metadata
→ Export...
```

The exported file can later be imported back into the same or another Dataset
Metadata editor, subject to the one-line value rule above.

## Acquisition Handler metadata transfer

Acquisition Handler Plugin API v1 Dataset result descriptors may include an
optional `structured_metadata` dictionary. CORE registers the Dataset and then
passes that dictionary to `datasetMetadataWrite`. Handlers therefore do not
write sidecars or wait for registration. Missing `structured_metadata` preserves
the original handler lifecycle. Malformed keys and persistence failures abort
the import without retaining a partial Dataset registration.


## `standard_octave` Analysis Source runtime bridge (GX-TXT 0.9.7.57)

Dataset Metadata API v1 remains the sole persistent authority. When a Standard
Module runtime is generated, CORE can expose the current Dataset Metadata for
each selected Analysis Source through the additive
[Analysis Source Dataset Metadata Runtime Extension v1](ANALYSIS_SOURCE_DATASET_METADATA_RUNTIME_v1.md).

The runtime bridge serializes indexed exact `key` / `value` pairs. Arbitrary
Dataset Metadata keys are not normalized into Octave struct fields, so legal
keys that differ only by punctuation cannot be silently merged. Missing
metadata is represented as an empty/not-found resource and does not fail
analysis.

Analysis modules consume this data only through the public Octave CORE helpers
and must not open `metadata/datasets/*.ini` directly. Runtime is derived state:
a later call to `datasetMetadataWrite`, `datasetMetadataUpdate` or
`datasetMetadataUnset` becomes visible after normal runtime regeneration.

## Octave Script Bridge

Bridge API ID: `DATASET_METADATA_API_v1`.

| Operation | Positional `args` | Result |
|---|---|---|
| `read` | `{dataset_id}` | Framework-managed metadata struct. |
| `update` | `{dataset_id, updates_struct}` | Updated metadata struct. |
| `unset` | `{dataset_id, key_cell}` | Remaining metadata struct. |

The current Session supplies the storage context. Keys and values follow the
normal Dataset Metadata API validation rules.

## Bulk metadata paste (TASK-9)

**Import... = load metadata from a file.**
**Add multiple fields... = paste the same kind of metadata directly from the clipboard.**

The embedded bulk panel provides a multiline paste area and Apply, Clear, and
Close panel controls. Apply parses and validates the entire block before merging
it into the editor. It displays counts of new and updated fields. An invalid
line leaves every editor field unchanged and retains the text for correction.
Closing the panel preserves unrelated edits. The existing **Save** button remains
the only persistence action; applying a block does not write Dataset metadata.

Both input surfaces use `datasetMetadataParseText(text, options={})`, a
headless-safe public helper returning a validated dictionary. No options are
currently accepted. The first `=` separates key and value; later `=` and all
`:` characters remain in the value. Blank lines and lines beginning, after
whitespace, with `#` or `;` are ignored. Surrounding whitespace is trimmed;
internal whitespace is preserved. Duplicate keys use the last occurrence.
Existing keys may be replaced without changing unrelated fields. Errors name
the physical line number. Optional UTF-8 BOM and CR/LF input are supported.

Script Bridge `DATASET_METADATA_API_v1/parse_text` takes one UTF-8 string and
returns the same validated metadata dictionary in Python and Octave. Parsing
never mutates or publishes a Dataset. GUI controls remain host-only.

## dev-059 reserved private extension

`_gxtxt` and `_gxtxt.*` are reserved. Ordinary `datasetMetadataRead` returns only
user/domain fields. Ordinary Write/Update/Unset and metadata-text import reject
reserved key writes; replacement preserves existing private fields. Ordinary
metadata-text serialization omits private fields. Dataset ZIP transfer preserves
private fields through the existing Portable Resource authority. The canonical metadata INI resource
still stores both classes and remains the sole persistence authority. Existing
catalog transactions notify only after this commit completes.

`datasetPrivateMetadataRead session datasetId` returns all reserved fields.
Modules may read all private fields. Module ownership is encoded as
`_gxtxt.module.m<lowercase UTF-8 hex module identity>.<relative key>`; framework
fields use `_gxtxt.framework.<key>`. Encoding is reversible and distinguishes
legal identities containing different separators or case.

`datasetPrivateMetadataUpdate capability session datasetId updates` and
`datasetPrivateMetadataUnset capability session datasetId relativeKeys` accept
only relative keys within the capability's module prefix. They reject forged
capabilities and absolute reserved keys, including foreign/module/framework
prefixes. They never accept a module ID or owner prefix from a write request.
Writes additionally require the Dataset to be in the caller's assigned Dataset
namespace. A user/admin may move it using the Dataset browser; fields belonging
to all previous module owners remain preserved. Private reads span namespaces.
Script ordinary metadata updates/unsets obey the same module placement rule;
ordinary user/admin Metadata editing remains available through the host UI.

CORE issues the capability from the registered module identity during trusted
activation/open. During activation, `datasetPrivateMetadataContext` returns that
bound context for retention by asynchronous Tcl callbacks. Viewer scene contexts
also contain `dataset_private_context`. The context includes module_id,
owner_prefix, dataset_namespace and capability. CORE alone uses its internal
framework-write path. Capabilities are ephemeral process identities, not a second
metadata store and not an OS sandbox against fully trusted in-process Tcl code.

The Python/Octave `DATASET_METADATA_API_v1` binding adds `private_read`,
`private_update`, `private_unset`, and `private_owner`. The Bridge obtains its
capability from the host runtime module identity and never exposes the capability
or privileged framework writes as RPC operations. `private_owner` reports only
module_id and owner_prefix. Framework organization changes use the dedicated
Dataset Namespace API, with its validated semantics.

Authority regression covers cross-owner/framework rejection, ordinary replacement
preservation, text filtering, observer consistency and failed-commit rollback.
The local Linux browser journey and actual Python/Octave Bridge journeys cover
ordinary filtering, owner-bound writes and namespace placement.
