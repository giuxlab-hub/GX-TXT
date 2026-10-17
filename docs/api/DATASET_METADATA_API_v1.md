# Dataset Metadata API v1

SPDX-License-Identifier: GPL-3.0-or-later

## Octave presentation adapter (dev097, version 1)

`lifetime = gxtxt_presentation_scope_v1(session_path)` opens a caller-owned CORE
service with public coordinate reads and snapshot operations. Omitting the Session
exposes only snapshot operations. The `scientific_presentation` service profile
also supplies statistical interpretation through its existing public binding,
excluding `store_columns`. Dataset writes, module bindings and callbacks are not
registered in this profile. Ordinary real Script Jobs retain their complete
registration; the scope borrows their active Bridge and never stops that owner.
A conflicting Session or an active statistics-only service is rejected explicitly.
Clearing an owned lifetime stops its process and releases its transport buffers.
The existing `gxtxt_statistics_scope_v1` profile is unchanged.

```octave
lifetime = gxtxt_presentation_scope_v1(session_path);
c = gxtxt_api_call('DATASET_METADATA_API_v1','coordinate_read',{'dataset_id'});
[shown, receipt] = gxtxt_coordinate_values_v1(c,'variable_id',original_values);
[viewport, view_receipt] = gxtxt_coordinate_view_v1(c,'variable_id',fitted_bounds);
```

`gxtxt_coordinate_values_v1(context, variable_id, values, options, optional_native_unit)` delegates
classification to `coordinate_snapshot_affine_plan`. CORE applies established
coefficients to display buffers; nonlinear relations use chunks of at most4096
finite elements through `coordinate_snapshot_values`. Options and defaults are
those of that public operation. Canonical mode is the default; numerical
calibration requires explicit effective mode. Inverse mode accepts displayed
values. Optional `native_unit` identifies an already normalized runtime frame (for
example elapsed-time seconds when the source declares hours); the same public
affine plan or bounded inverse/forward snapshot operations avoid double conversion.
Shape and nonfinite gap positions are retained. Exact identity retains
the input storage class, including distinct int64/uint64 values beyond binary64
precision. Nonidentity presentation returns float64 and reports input/output
classes; integer display may therefore be approximate. This adapter never
materializes or replaces canonical scientific arrays. Finite overflow is an error.

`gxtxt_coordinate_view_v1(context, variable_id, fitted_display_bounds,
optional_display_unit)` delegates inverse conversion, canonical view range and
forward conversion to the same public owner. It excludes numerical calibration.
Apply it once to a newly fitted reference, never to the preceding magnified range.
Factor1 preserves the original display endpoints exactly. Its receipt distinguishes
source and displayed reference/result bounds, pivot and factor. Captured snapshots
remain explicitly `snapshot_only`; they do not assert a current source revision.

Plot Dataset3.18 consumes these helpers for canonical caches, current-policy
rerender and detached snapshots. Direct Dataset XYZ uses the same public Tcl
snapshot operations and a view-owned calibrated frame; canonical triples remain
unchanged. HMS consumers respect the public numeric boundary in seconds before
applying source-unit pivots.

## Coordinate context extension (dev097, schema 1)

CORE stores optional coordinate settings under
`_gxtxt.framework.coordinate_context_v1` in this same resource. There is no
second Dataset settings store. The owning sidecar supplies Dataset identity;
the value stores `schema_version`, monotonic `revision`, `source_sha256`, and
`variables` keyed by stable Variable IDs. Names and display labels are not keys.
Each Variable entry records its source unit/dtype/value-format semantics plus:

| Field | Meaning |
|---|---|
| `display_unit` | Compatible re-expression of coordinates, using Unit Registry and any declared Variable relation. |
| `view_factor`, `view_pivot` | Positive magnification about a pivot in canonical source coordinates. |
| `calibration_factor`, `input_origin`, `output_origin` | Explicit effective coordinate: `output_origin + calibration_factor * (canonical - input_origin)`, in the source unit. |

View magnification, display units and calibration are independent. Saving settings
does not change source values, source units, ordinary Table Stream reads, or opt
calculations into calibration. Missing settings mean identity. Unknown units can
retain identity; a different display unit requires a declared compatible relation.

Public Tcl operations (prefix `::GX::`):

```tcl
datasetCoordinateRead $session $datasetId
datasetCoordinateInspect $session $datasetId
datasetCoordinateUpdate $session $datasetId $variableUpdates $expectedRevision
datasetCoordinateReset $session $datasetId $expectedRevision
datasetCoordinateValidate $session $datasetId $storedContext
datasetCoordinateValues $session $datasetId $variableId $values ?options?
datasetCoordinateViewRange $session $datasetId $variableId $canonicalReferenceRange
datasetCoordinateSnapshotValues $resolvedContext $variableId $values ?options?
datasetCoordinateSnapshotViewRange $resolvedContext $variableId $canonicalReferenceRange
datasetCoordinateSnapshotAffinePlan $resolvedContext $variableId $nativeUnit ?options?
```

Both Script Bridge languages expose these through `DATASET_METADATA_API_v1` as
`coordinate_read`, `coordinate_inspect`, `coordinate_update`, `coordinate_reset`,
`coordinate_validate`, `coordinate_values`, `coordinate_view_range`,
`coordinate_snapshot_values`, `coordinate_snapshot_view_range` and
`coordinate_snapshot_affine_plan`, omitting
the Session argument. Updates map Variable IDs to changed fields. Revision zero
means no persistent context; write/reset require the observed revision, reject
conflicting editors, and increment it atomically through Dataset Authority.
Returned read contexts include `dataset_id`, `persistent`, and identity entries
for other real numeric Variables. Validation accepts the stored four-field
context; remove the two receipt fields when validating a read result.

`coordinate_values` accepts at most 4096 finite, exactly representable binary64
inputs and preserves Script array shape. Its options are `mode=canonical|effective`
(default canonical), `unit=display|source|<explicit unit>` (default display), and
`direction=forward|inverse` (default forward). Forward applies explicit calibration
first, then display conversion. Inverse uses the declared inverse unit relation
first, then reverses calibration, suitable for editing displayed coordinates.
Formula authors remain responsible for their declared invertible domain. No
view magnification is applied to coordinate numbers. Larger scientific arrays
belong to Dataset Transform, not this bounded readout API.

`coordinate_view_range` returns `pivot + (endpoint-pivot)/factor` for two increasing
canonical reference endpoints. A consumer persists its reference range and the
applied context revision, and applies changed settings once to that reference;
it must not compound settings on an already magnified viewport. Transient pan/zoom
is separate. Multi-Dataset consumers must explicitly choose their viewport basis.
Identity magnification returns the canonical endpoints directly. Effective
calibration with factor one and equal input/output origins also preserves values
directly, including signed zero; neither operation introduces pivot cancellation.

Source-bound read/application verifies actual payload SHA and declared source semantics.
Changed payloads or unit/dtype/value-format declarations cause an error;
`coordinate_inspect` reports the reason and revision without applying stale state.
Reset can adopt a legitimate registered source revision, but cannot conceal a
payload/registry hash mismatch. Generic metadata replacement preserves this
framework-owned field, and ordinary/private-module writes cannot forge it.
Portable Dataset/Session copies preserve the same payload and Variable bindings;
Dataset-ID changes use the sidecar identity. Verified schema-owner regeneration
can rebind cosmetic canonical-name or enabled-column changes and advance revision.
Scientific parsing/unit changes remain stale until explicitly reset/redefined.

The `coordinate_snapshot_*` operations evaluate an explicitly supplied resolved
read context without Dataset IO. They return `verification=snapshot_only`, never
a claim that the current source still matches. Source-bound values/view operations
return `verification=source_verified`. Snapshot operations validate the envelope
and selected Variable settings, use the current public Unit Registry, and have
the same finite-value/shape bounds. They are suitable for repeated pointer, tick
and small point-table presentation against frozen geometry. Consumers must capture
the context with a verified read at source binding/reload, match its payload SHA
and Variable IDs to their geometry, and invalidate/reload it on relevant source,
schema, settings or unit-definition changes. Passing a modified snapshot cannot
write metadata or authorize calibration materialization. Snapshots can continue
describing old frozen geometry after the live Dataset changes; this is explicit.

`coordinate_snapshot_affine_plan` composes the declared inverse relation from an
explicit Native geometry unit, optional effective calibration, and the display
relation through the same Unit Registry grammar. Options are the same mode/unit/
direction choices as values. It returns `affine=1` with finite `scale`/`offset`
only when algebraic classification succeeds; otherwise `affine=0` with a reason.
No sample fitting is used. Inverse direction follows declared inverse formulas.
The receipt says `snapshot_only` and identifies its input/output units. This is
for Native grid/frame presentation; pointwise values remain the authority when
no finite global affine representation exists.

Values and affine-plan options also accept `source_unit_assumption`: an explicit,
registered nonopaque unit for a source Variable whose unit is empty. This cannot
override a declared unit. The assumption interprets the original source numbers;
`unit=source`/`display` then refer to that assumed unit unless an explicit target
is supplied. Calibration and pivots continue to use original source numbers.
The returned receipt includes the assumption separately from `verification`.
Neither the input snapshot, Dataset schema, metadata nor payload is modified.
This supports existing Workspaces that explicitly assumed missing units during
physical working-frame conversion. Permanent declarations/materialization use
the schema owner or Dataset Transform, with their usual provenance and guards.

Explicit materialization is available through Dataset Transform's
`calibrate_variables` operation, including consumed-calibration provenance and
atomic context adoption. See `DATASET_TRANSFORM_API_v1.md` for inheritance rules.
These targeted checks do not establish completion of all GUI consumers or the
integrated release acceptance campaign.

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

## Verified contributors (dev102)

Ordinary CORE writes now record authenticated original and latest contributor per
key in the existing reserved `_gxtxt.framework.metadata_origins` sidecar manifest.
Actors are User, System or registered module ID, independent of Dataset producer.
Revision/value SHA verification preserves unchanged attribution through publication,
prunes deletes and makes value changes atomic with origin changes. Unverified older
values remain Unclassified; editing them records the current modifier without
inventing their original creator. Callers cannot supply a trusted actor label.

Tcl `datasetMetadataContributors session datasetId` returns verified relations;
`datasetMetadataGroups session datasetId ?all|original|last?` returns actual groups.
A field can appear under its original and latest modules. Bridge `contributors`
and `groups` take Dataset ID; Python/Octave propagate their authenticated module.
User/admin `datasetMetadataAuthorizeContributors session datasetId moduleIds
expectedRevision` grants ordinary metadata contribution explicitly. Modules cannot
self-grant. Private namespaces and scientific payload ownership remain enforced.
Preview resolves actual installed names and only present contributor groups.
Publication v2, File Publication and Acquisition use the same CORE boundary: supplied
keys belong to their module, CORE integrity/administrative fields to System.
