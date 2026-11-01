# GX-TXT Acquisition Handler Plugin API v1

## Managed native producer protocol (P032, additive)

The existing API has a target-specific native protocol
`gxtxt.native_acquisition_request.v1`. `acquisitionHandlerDispatchApiInfo`
reports `native_operation_contracts`, exact limits and
`native_runtime_available`. An unavailable runtime explicitly refuses; a
catalog declaration alone does not authorize execution. The ordinary Tcl
handler and prepared Publication interfaces retain their existing contracts.

An admitted package/profile requests a subset of `source_info`, `source_read`,
`cancelled`, `progress`, `prepare_output`, `output_write`, `output_finish`,
`helper_call`, `scientific_spectrum_parse` and `scientific_spectrum_read`.
The last two reuse the common CORE decoder over an already granted source and
bounded request-local pages; see `SCIENTIFIC_SPECTRUM_IMPORT_API_v1.md`.
CORE intersects profile operations, package declarations and the
current phase's admitted operations. Every exchange rechecks the live package,
request/phase, cancellation and relevant Session incarnation. Source handles
are opaque indexed capabilities; authored code receives no RAW/source path or
FD. A slice contains at most65536 raw bytes, transported as canonical base64
with exact offset/count/EOF. Inspection may honestly lack a full reviewed SHA;
Test/import require it. Metadata identity alone is not a content hash: a
same-stat edit may reach a read, but reviewed full-SHA finalization must refuse
before canonical publication.

Numeric output bytes stay in CORE-issued typed buffers. `output_write` carries
only opaque IDs, sequential offset/count and optional checked chunk SHA.
`output_finish` returns a provisional reference. CORE requires actor closure,
final byte/SHA/source checks and actual scoped capability admission before
resolving the reference to `gxtxt.acquisition_prepared_numeric.v1` through the
existing Publication v2 transaction. Test discards; inspection cannot output.
The legacy output form supports rank1. The additive explicit-dimensions overload
supports rank1..16 and independent coordinate lengths,64 outputs,
128 variables/output and512MiB per variable; see
`ACQUISITION_PUBLICATION_API_v1.md`. Helper registration is not execution admission; unavailable helper
capabilities refuse. No native operation grants arbitrary paths, Tcl commands,
Registry access or administrative Dataset mutation.

Installed native packages use the ordinary Module catalog and Plugin Manager.
CORE admits the distributed binary, matching source closure, SDK, factory,
profile and current public operations before starting a fixed managed worker.
The existing Acquisition callbacks route to this worker; authors do not supply
a Tcl facade. `format_profile` selects one declared local profile, including its
actual text/binary source kind. Existing Acquisition activation policy applies
(Acquisition tools are always available), as do dependency and pending-update
guards. Changing configuration, Namespace, Session incarnation or the reviewed
package during a request refuses that request rather than retargeting it.

P033 retains the exact accepted DEV111-P032 SDK-v1 ABI contract as a bounded
compatibility case. Admission still verifies all distributed SDK, fixed adapter
and policy bytes against both build and validation receipts. An older package
must match the three exact accepted P032 SHA-256 values together and request
only its original eight operations. Altered/unknown old contracts and new
capabilities under an old contract refuse. All current source/profile/binary,
factory, live capability, process/source confinement and final SHA checks remain
mandatory. The runtime receipt identifies `sdk_admission`; this permits existing
compiled code, without recompilation or changing an accepted package.

`AcquisitionRequest.mapping` is an inert object with `variables` (the reviewed
mapping rows), `dataset_id` and `contract` (the host's proposed output identity
and contract). Its `config` contains only the ordinary typed ModuleConfig
snapshot. Neither object grants publication or replacement authority. Native
outputs must use a contract declared for the actual selected profile; replacing
an existing Dataset is unavailable on this Acquisition pathway.

The private CORE transport uses existing Script Job request ownership and
Resource Management, with live host preflight and cancellation checks. After
native actor reap, CORE adopts sealed arrays into its existing Acquisition
transaction and rechecks their SHA before and after transfer. Prepared variables
may add `sha256` to the previous `{variable_id schema path}` declaration; legacy
three-field declarations remain supported. Exact typed arrays require the
existing `typed_numeric` storage capability, negotiated through the normal
storage policy without selecting a new writer. An explicit incompatible storage
request refuses. Existing Publication owns schema checks, canonical SHA and
atomic rollback, RAW provenance and optional Group creation.

Canonical metadata records `acquisition.profile`, its SHA, module manifest and
binary SHA, plus exact typed configuration JSON/SHA and the native completion
JSON. When declared, `acquisition.config_schema_sha256` pins the ordinary Module
configuration schema as well. Native outputs receive the actual admitted Module
version; a contradictory authored producer version refuses. Producer metadata
cannot replace these CORE facts. Inspection can run
without a Session; Test prepares and hashes buffers then discards them. A Test
result explicitly reports `scientific_acceptance=0`: successful parsing alone
does not certify scientific publication, Group lifecycle or cold reopening.
Managed Tcl/Python helpers use the fixed CORE subordinate dispatcher.
`native_helper_runtime_available` reports that wired runtime's presence; actual
execution still requires `helper_call` in both the installed module and selected
profile, an exact registered runtime-helper ID/language/entrypoint/source SHA,
and the current CORE request/lease. Merely registering a helper never executes
it. Missing runtime, roster or capability explicitly refuses.

Each call runs one fixed child under the same managed Acquisition Job. The
parent checks actual PID, factory pins and enforced filesystem/process guard
before invoke, rechecks live module/configuration/Session/lease/source closure
while waiting and after reap, and returns only finite typed metadata. No source
FD/path, output buffer, Registry, scheduler or publication interface is supplied
to helper code. Python receives/returns plain JSON data; Tcl receives/returns the
existing native Workspace JSON typed nodes in a bounded safe interpreter in the
same child PID. The separately pinned CORE codec is preloaded without granting
it as a root-owned system file. Python execution has a filesystem/process
boundary, not a Python-language, account or network sandbox claim.

One Acquisition request permits at most 32 calls, 1 MiB cumulative arguments/results/
diagnostics and 30 seconds spent in helpers. Each call has at most 192 KiB argument
and result metadata, 8 KiB captured diagnostics plus 8 KiB raw diagnostic pipe data,
6 seconds parent deadline, 2 seconds CPU/5 seconds worker wall alarm and 256 MiB
address space. Tcl additionally enforces 100000 commands, 1.5 second deadline and
recursion 64. Parent drains capped diagnostic pipes and reaps every child before
accepting its result; crash, limit, stale identity or revocation refuses the
native request. Helper results are not scientific publication receipts.

New native producers may declare additional contracts through the existing
Module/Contract Registry sections. Before changing that Registry projection,
CORE refuses a provided identity already owned by CORE or another provider and
cycles reachable through the combined parent declarations. Legacy declarations
retain their existing behavior. Unknown future parent names remain honest
declarations, with no provider or scientific-compatibility claim inferred from
their mere presence. Source editing/export and actual scientific qualification
remain distinct operations.

## Managed import requests (P028, additive)

`acquisitionHandlerImportSourcesAsync module session sources datasetId contract
variables ?options? ?callback?` returns `{operation_id request_id session state}`.
It is a trusted user/admin host operation; `sources` contains1..64 reviewed local
paths, `variables` is bounded to256 KiB and `options` to64 KiB with the same
`source_provenance`/`destination_namespace` semantics as synchronous dispatch.
The normal GUI opts in only for a handler declaring `managed_request` capability.
Old six/seven-argument synchronous APIs and non-opted handlers remain compatible.

An auxiliary managed ScriptJob request owns the process group, bounded controls,
progress, cancellation and drain. The worker calls the SAME Acquisition and
Publication APIs under one Dataset Authority transaction. No new scheduler,
Dataset registry, writer or recovery journal is added. Session token, source and
module/config/runtime identities are pinned; source SHA is checked across the
whole operation. A Session change cancels the original operation and never
retargets it to the newly opened Session. Worker-local settings do not overwrite
the authoritative Session Manifest; the normal matching host GUI may persist its
current drafts through the existing writer after successful completion.

The callback receives `{ok 1 result result}` where result includes `operation_id`,
`status completed|cancelled`, `session`, `module_id`, `dataset_ids`, or the normal
`{ok 0 error diagnostic}`. Recovery failure includes `recovery_required 1` and
retains BUSY protection. Progress reports phases and actual processed rows/variables
or channels; `prepared_channels` means finalized inside the pending transaction,
not a committed partial Group. A completion receipt enlisted in that transaction
distinguishes a real committed result from a late cancellation race.

`acquisitionHandlerCancelAsync operation_id ?reason?` requests cancellation and
returns a boolean. Repeated cancellation is idempotent. Recovery runs only after
the owned request group has drained; it restores partial payloads, Registry, RAW,
metadata and Group. Cleanup removes only a newly created empty exact request RAW
directory, preserving pre-existing directories and any contents. Resource release
uses the live host's existing Resource Management authority. No child impersonates
its parent to release resources.

`acquisitionHandlerAuthorityBusy session` is a cheap nonblocking host query.
Mutable Dataset operations keep their lock/recovery guards and refuse BUSY while
the managed import owns that Session. Advisory Browser/Preview refresh retains the
last view and coalesces until the same Session becomes available. Protected
resource accounting is coalesced asynchronously on Tk hosts; scientific locking,
journaling and recovery remain synchronous authorities. This is independent of
the explicit user Cancel operation.

Dataset Authority COMMIT fsyncs every enlisted surviving file, then each affected
ancestor directory once in deepest-first order, before the same durable committed
journal marker. This coalesces redundant directory flushes inside one durability
boundary; it does not skip file flushes, disable durability or mark partial output
committed. Pending recovery, abort and committed-journal cleanup retain their
existing ordering and ownership. Normal publication flushes files serially:
measured full Rigol comparisons did not establish a reliable gain from concurrent
flushes on the shared storage. The private authority protocol retains an optional
1..8 worker count for isolated qualification. Only fsync calls on already
quiescent enlisted files may run concurrently in those experiments. All started
flushes join before any directory flush or committed marker, including on an I/O
error; journal/Registry mutations remain on the single Dataset owner. The private
count defaults to1 for predecessor callers. Public Dataset/Acquisition signatures
and source precision remain unchanged.

`acquisitionHandlerExecuteWorker command request` preserves the handler's normal
synchronous command outside a managed worker. Within the admitted request it
uses the existing bounded process envelope (1 MiB diagnostic output,64 KiB line,
8 KiB retained tail), with no source/content evaluation. Control request bound is
1 MiB; progress/control records are at most64 KiB. `acquisitionPublishPrepared`
also accepts an optional fifth `callbacks` dictionary for existing phase progress
and cancellation checks before numeric transfer and finalize. Actual canonical
storage remains `DATASET_PUBLICATION_API_v2`.

A handler declaring `consumable_prepared_buffers` may return the boolean result
field `prepared_buffers_consumable=1` with its admitted `prepared_publications`.
CORE derives the consumable root from its own transaction's `datasets/` directory;
the producer cannot nominate another root. Each prepared file is reference-counted
across all channels and Variables, including a shared time axis. After its last
successful writer acknowledgement, CORE may delete that transient file before
remaining finalization work. RAW, canonical output and undeclared files are never
consumables. Handlers without this explicit opt-in retain their staged buffers
until ordinary transaction cleanup. Failures and cancellation still use the same
outer Dataset Authority rollback. The normal adapter uses serial providers because
measured full-fixture comparisons did not establish a reliable parallel gain.

## Selected Library source dispatch

The host operations `acquisitionHandlerImportSourceToSession moduleId session
sourcePath proposedId proposedContract variableMap ?dispatchOptions?` and
`acquisitionHandlerImportSourcesToSession` (source-path list instead of one path)
accept an additive optional dictionary. Old six-argument calls retain their
behavior and return actual Dataset IDs.

`source_provenance` is a dictionary of at most 64 `library.*` metadata fields,
pinned by the Library-to-Acquisition adapter. It is merged into each actual
output's structured metadata before registration; conflicting values refuse.
`destination_namespace` is an optional ordinary published Namespace. Both use
the same Acquisition/Dataset transaction as RAW, payload, metadata, Registry
and any declared Group. No post-import private Dataset writer is needed.
Unknown options, unowned metadata names, oversized options (>64 KiB), pending
destinations, bound module contexts and Script-registration outcomes refuse.
Whole Groups move together; standalone results use the existing Namespace owner.
No remote search or Library population invokes this explicit Session dispatch.

**Status:** public framework API, introduced in GX-TXT Pipeline v0.8.9.  
**License:** GNU GPL v3 or later.

## Purpose

This API removes the historical `standard_tcl` acquisition dispatch limitation. A new acquisition/import format can be installed as a normal module under:

```text
plugins/modules/<stable-id>/
```

without adding an `elseif`/`switch` branch to `gxtxt_pipeline.tcl` or `core/tcl/module_api_v1.tcl`.

The framework owns:

- file selection and the common Preview/Variables workspaces;
- session creation and current-session lifecycle;
- RAW snapshot/provenance;
- Dataset Registry updates (`metadata/datasets.ini`);
- SHA-256 calculation;
- duplicate Dataset ID protection;
- refresh of Results/Variables/Analysis-source selectors.

The acquisition plug-in owns only format-specific behavior:

- format recognition;
- RAW parsing;
- vendor/instrument metadata extraction;
- discovery of source variables;
- canonicalization into one or more output files;
- provenance text specific to the format.

No acquisition plug-in may update `metadata/datasets.ini` directly.

If inspection rejects a source group, CORE retains the handler's existing
`preview_metadata Diagnostic` and nonduplicate `warnings` in the admission
error, together with guidance to inspect Preview or correct the source. The
recognition guard remains mandatory; rejected sources are not registered.
The plug-in acquisition queue keeps failed rows and offers **Failed: details...**
to read that reason. Preview remains available on the retained row. Opening
details does not retry acquisition or modify the Session.

## Descriptor contract

A plug-in acquisition module remains a Standard Module API v1 module:

```ini
[meta]
api_version=1
id=acq.vendor_format
kind=acquisition
runner=standard_tcl
...

[inputs]
contracts=raw.vendor

[outputs]
datasets=timeseries.table
files=datasets/*;metadata/datasets.ini

[runner]
handler=vendor_format

[acquisition_handler]
api_version=1
script=runtime/acquisition_handler.tcl
inspect_proc=::VendorFormat::inspect
import_proc=::VendorFormat::import
file_label=Vendor log files
file_patterns=*.csv;*.txt
supports_batch=1
variable_mapping=required
```

`[runner].handler` is a stable handler identifier. It no longer has to be one of the legacy `generic_csv` / `rigol_csv` values.

For a non-legacy handler, `[acquisition_handler]` is mandatory.

### Keys

- `api_version=1` — required.
- `script` — required; path relative to the plug-in directory. Absolute paths and `..` traversal are rejected.
- `inspect_proc` — required Tcl command loaded from `script`.
- `import_proc` — required Tcl command loaded from `script`.
- `file_label` — optional human-readable file type label.
- `file_patterns` — optional semicolon/comma-separated file patterns; default `*`.
- `supports_batch` — capability declaration reserved for framework batch orchestration. v0.8.9 exposes the capability but does not force a plug-in to implement its own batch lifecycle.
- `variable_mapping` — `required` (default), `optional`, or `none`. `required` preserves historical/tabular behavior. `optional` permits zero or more inspected variables. `none` declares an opaque source/dataset for which the framework must not require a Variables mapping (for example, a raster image stored as one binary object).

The plug-in script is loaded lazily by the framework when the handler is first inspected or executed.

## `inspect_proc` contract

Signature:

```tcl
proc ::VendorFormat::inspect {requestDict} {
    ...
    return $resultDict
}
```

The request contains:

```text
api_version
module_id
handler_id
source_path
config            dict of descriptor-driven module config
```

The result MUST be a Tcl dict. The public fields are:

```text
recognized    boolean-like 0/1
format        stable format label/string
metadata      dict
variables     list of variable dicts
preview_rows  list of row lists
warnings      list of strings
```

A variable dict may contain:

```text
source_column
source_channel
original_header
canonical
unit
semantic_role
instrument_id
instrument_channel
```

Minimum useful variable declaration:

```tcl
[dict create \
    source_column 1 \
    original_header Time \
    canonical time_s \
    unit s \
    semantic_role time]
```

The framework displays the inspection result in the common Preview workspace and uses it to seed the common Variables workspace. The user may then change canonical aliases, units or semantic roles before import.

If `variable_mapping=none`, an empty `variables` list is a valid inspection result and batch validation must not reject the source. Plugins must not fabricate placeholder variables merely to satisfy the UI.

`inspect_proc` MUST NOT create a session or register a dataset.
The `config` field is additive in GX-TXT 0.9.8.10-dev. It contains only
settings declared by that module's descriptor, including the current Session
values. Inspectors can therefore preview the same parser and encoding choices
that `import_proc` receives, without reading CORE configuration variables.

## `import_proc` contract

Signature:

```tcl
proc ::VendorFormat::import {requestDict} {
    ...
    return $resultDict
}
```

The request contains:

```text
api_version
module_id
handler_id
source_path       original selected source
raw_path          framework-owned RAW snapshot
session_path      target GX-TXT session
output_dir        framework-owned canonical output directory

dataset_id        proposed/default Dataset ID
config            dict of descriptor-driven module config
variables         current Variables mapping (after user edits)
inspection        result previously produced by inspect_proc
```

The plug-in must read the selected source/RAW data, create its canonical output file(s) under `output_dir`, and return:

```tcl
[dict create datasets [list $dataset1 $dataset2 ...]]
```

Each dataset is a dict containing at least:

```text
dataset_id
contract
format
path
variables
units
semantic_roles
source
provenance
```

Optional:

```text
notes
structured_metadata
variable_schema
```

`structured_metadata` is a dictionary of generic namespaced Dataset Metadata
API v1 fields, for example:

```tcl
structured_metadata [dict create \
    source.original_filename $sourceName \
    experimental.instrument $instrument \
    tags.vendor_code $vendorCode]
```

The field belongs to each returned Dataset descriptor. It is optional; handlers
that omit it retain their existing behavior. CORE validates every namespaced
key before changing the Dataset Registry.

`variable_schema` is an optional list of dictionaries describing the canonical
variables produced by this Dataset. It is an additive API v1 field. Each entry
requires a stable `variable_id` and may declare `canonical` (or `name`),
`source_column` for CSV, `unit`, `semantic_role`, `value_kind`, `dtype`, `rank`,
`shape`, `dimension_ids`, coordinate relationships/roles/axis metadata,
`component_ids`, `group_id` and `display_label`. Valid v3 field semantics come
from Dataset Variable Schema API v3. For example:

```tcl
variable_schema [list \
    [dict create variable_id member_id canonical member_id source_column 1 \
        dtype string semantic_role member_identity] \
    [dict create variable_id spectral_x canonical spectral_x source_column 2 \
        dtype float64 unit nm coordinate_role coordinate] \
    [dict create variable_id spectral_y canonical spectral_y source_column 3 \
        dtype float64 unit count coordinate_variable_ids spectral_x]]
```

For canonical CSV, the declaration must cover every physical column exactly
once. `source_column` is one-based; the declared canonical name must match the
actual header in that column. CORE checks row widths and the declared
`row_count`, if present. Table variables use rank 1 and the `row` dimension;
CORE derives their shape from the canonical payload. A display label may differ
from the canonical header. A non-CSV storage form may declare v3 variables
without `source_column`, but its ordinary storage provider and contract still
govern whether consumers can read that payload. The schema field does not add
a storage backend.

CORE validates IDs, names, column associations, types, dimensions, coordinate
references and metadata, then applies the declaration inside the normal
Acquisition transaction. An invalid declaration or persistence failure rolls
back the new RAW/payload files, Dataset Registry entry and metadata sidecar.
Existing handlers that omit `variable_schema` keep generated IDs such as
`v0001` and require no changes. Handlers must never edit registry/schema files
or use private CORE functions to publish their declarations.

`path` is relative to `output_dir`. Absolute paths and `..` traversal are rejected, and the file must exist before the callback returns.

Example:

```tcl
return [dict create datasets [list [dict create \
    dataset_id $datasetId \
    contract timeseries.table \
    format csv \
    path $relativeOutput \
    variables {time_s current_A} \
    units {s A} \
    semantic_roles {time measure} \
    source "vendor current logger" \
    provenance "parsed from vendor RAW export"]]]
```

## Framework registration

After a successful `import_proc`, GX-TXT validates every returned dataset and registers it centrally. Important registry fields include:

```text
kind / contract
format
path
variables / columns
units
semantic_roles
source_module
source
provenance
source_raw
source_sha256
canonical_sha256 / sha256
acquisition_handler_api_version=1
created_at
```

SHA-256 values are computed by GX-TXT, not trusted from plug-in output.

### Structured Dataset Metadata handoff

For a descriptor containing `structured_metadata`, CORE performs this lifecycle:

```text
import_proc returns the Dataset descriptor
-> CORE validates and registers the Dataset
-> CORE calls Dataset Metadata API v1
-> the metadata sidecar and registry reference are persisted
```

The acquisition handler does not call `datasetMetadataWrite` or
`datasetMetadataUpdate` because the Dataset does not exist while
`import_proc` is running. CORE does not interpret domain keys. Audio, image,
experimental, source and vendor namespaces remain owned by the importer.

Malformed metadata fails the import. If Dataset Metadata persistence fails
after registration, CORE restores the previous registry and removes any
metadata sidecars created by that import. This uses the existing Dataset
Metadata API storage and ownership model; no acquisition-specific metadata
store is created.

The plug-in MUST NOT call `datasetRegister`, `saveDatasetRegistry`, write
`metadata/datasets.ini`, or write Dataset Metadata sidecars directly.

## Dataset ID ownership and callback safety

Dataset IDs use the framework-safe character set `[A-Za-z0-9_.-]`. From v0.9.6, the proposed/default `dataset_id` is validated **before** the framework creates RAW/output work for that source and before `import_proc` is invoked. Plugins may therefore use the supplied validated ID when deriving filenames under `output_dir`; they must still keep every returned `path` relative to `output_dir`. Returned dataset IDs are validated again centrally, and collisions are rejected rather than silently replacing data.

## Session lifecycle

The public framework entry point is:

```tcl
::GX::acquisitionHandlerImportSync $moduleId ?$session?
```

- without `session`, GX-TXT creates a new session and owns its lifecycle;
- with an existing `session`, the framework imports into that session without clearing the Dataset Registry.

This makes the handler API compatible with the framework's multi-dataset lifecycle. Scientific joins/alignment/resampling are never implicit acquisition behavior.

## Common Preview and Variables integration

For non-legacy plug-in handlers:

- `refreshCsvPreview` routes to `inspect_proc` and renders the standardized inspection result in the existing Preview workspace;
- the common Variables workspace is seeded from `variables` returned by `inspect_proc`;
- user edits are passed back to `import_proc` as `request.variables`.

The Preview workspace name is historical; plug-in acquisition handlers are not required to parse CSV.

## File chooser

For plug-in handlers the framework uses `file_label` and `file_patterns` from `[acquisition_handler]` instead of hard-coding CSV extensions.

## Legacy compatibility

`acq.generic_csv` and `acq.rigol_csv` remain fully supported through compatibility adapters in the same handler registry. Their established import algorithms are unchanged.

New formats MUST use Acquisition Handler Plugin API v1 instead of adding a new core dispatch branch.

## No implicit scientific transformations

An acquisition handler may parse and canonicalize its own vendor format. It must not silently perform scientific joins, interpolation, resampling, model fitting or cross-dataset transformations. Those belong to Scientific Analysis Definition API / analysis modules.

## Minimal author checklist

1. Create `plugins/modules/<id>/module.ini`.
2. Use `kind=acquisition`, `runner=standard_tcl`.
3. Declare `[runner] handler=<stable-handler-id>`.
4. Declare `[acquisition_handler]` with API v1, script, inspect and import callbacks.
5. Declare all possible output contracts under `[outputs] datasets=`.
6. Implement `inspect_proc` without side effects.
7. Implement `import_proc` to write only under `request.output_dir` and return dataset descriptors.
8. Never create sessions or edit Dataset Registry files in the plug-in.
9. Add Documentation API v1 metadata and tests.

---

## GX-TXT v0.9.0 additive capabilities

The API version remains **1**. Existing v0.8.9 handlers remain valid. GX-TXT v0.9.0 adds optional, descriptor-driven capabilities so a handler can grow without adding core dispatch branches.

### Normal file chooser and batch-capable handlers

If a handler declares:

```ini
[acquisition_handler]
supports_batch=1
```

selecting the first source with the normal **Browse...** button now automatically:

1. enables the framework source-batch workspace;
2. creates or reuses one batch row for the selected file;
3. sets `Use=ON`;
4. leaves the row `Pending` until import;
5. exposes `+ Add source` / `Add sources...` for further inputs.

The first PHASE 1 import therefore imports all enabled batch rows into one newly created session. Later enabled `Pending` rows can be added to the same current session through the existing incremental-import button.

The plug-in does not implement this lifecycle.

### `capabilities=`

Optional semicolon/comma separated declaration:

```ini
capabilities=batch;preflight;dataset_preview;multi_file_group;cooperative_async;progress;instrument_suggestion
```

`supports_batch=1` remains supported and implies the `batch` capability.

Public framework queries:

```tcl
::GX::acquisitionHandlerCapabilities $handlerId
::GX::acquisitionHandlerHasCapability $handlerId capability
::GX::acquisitionHandlerModuleSupportsBatch $moduleId
```

Capabilities are descriptive. Optional callback keys also imply their corresponding capability.

### Progress and cancellation callbacks

Every v0.9.0 import request may contain command prefixes:

```text
progress_callback
log_callback
cancel_callback
```

A Tcl plug-in calls them as command prefixes, for example:

```tcl
set cb [dict get $request progress_callback]
::GX::acquisitionHandlerInvokeCallback $cb [dict create \
    state running \
    mode determinate \
    current 25 \
    total 100 \
    stage parse \
    message "Reading vendor records"]
```

`cancel_callback` returns a boolean. Long synchronous parsers should check it at natural chunk boundaries. Plug-ins MUST NOT access Tk widgets directly.

### Cooperative asynchronous / streaming execution

A handler may optionally declare:

```ini
begin_proc=::Vendor::begin
step_proc=::Vendor::step
cancel_proc=::Vendor::cancel
```

This implies `cooperative_async` and `streaming`.

Contract:

```text
begin_proc(request) -> state token
step_proc(request + state_token) -> dict
```

`step_proc` returns at least:

```text
state=running|completed|failed|cancelled
```

and may return:

```text
state_token
progress       dict compatible with Progress API v1
result         normal import result when state=completed
error          text when state=failed
```

The framework invokes `step_proc` through the Tcl event loop and keeps the GUI responsive. `cancel_proc`, when provided, is called after a user cancellation request.

This contract is intended for very large vendor files where one monolithic in-process Tcl callback would make the UI unresponsive.

### Preflight

Optional descriptor key:

```ini
preflight_proc=::Vendor::preflight
```

The GUI exposes a framework-owned **Preflight...** button. The callback receives:

```text
api_version
module_id
handler_id
source_paths
progress/log/cancel callbacks when applicable
```

Return:

```tcl
dict create \
    ok 1 \
    checks {...} \
    warnings {...} \
    errors {...}
```

Preflight must not modify RAW data or the Dataset Registry.

### Multi-file-as-one-log grouping

Optional callbacks:

```ini
group_proc=::Vendor::groupSources
group_inspect_proc=::Vendor::inspectGroup
```

When `group_proc` is declared, **Add sources...** passes the selected paths to it. It returns:

```tcl
[dict create groups [list \
    [dict create label "Run 001" source_paths $paths dataset_id run001] \
    ...]]
```

Each returned group becomes one framework batch row. During import the request contains both backward-compatible singular fields and plural fields:

```text
source_path      first source
source_paths     all sources in the logical acquisition
raw_path         first framework RAW snapshot
raw_paths        all RAW snapshots
```

Registry provenance additionally records source count and the RAW/hash lists. Scientific alignment is not implied by grouping.

### Non-CSV canonical dataset preview

Optional:

```ini
dataset_preview_proc=::Vendor::previewDataset
```

It is used only when the imported canonical dataset format is not `csv`. Request fields include:

```text
dataset_id
dataset_path
session_path
format
contract
module_id
handler_id
```

Return may contain:

```text
text       human-readable preview
metadata   dict
rows       list of row lists
```

The common Dataset Preview workspace remains owned by the framework.
`session_path` is the open Session supplied by CORE. Providers may pass it to
public Dataset Metadata or Session Inspection APIs to show the persisted
Dataset state. Providers must not read CORE's `currentSession` variable.

### Format / MIME registry

A handler may declare stable format IDs:

```ini
[acquisition_handler]
formats=vendor.current_log

[acquisition_format.vendor.current_log]
description=Vendor current logger export
mime=text/x-vendor-current-log
extensions=*.txt;*.log
canonical_formats=csv
```

Public queries:

```tcl
::GX::acquisitionFormatRegistryIds
::GX::acquisitionFormatField $formatId mime
```

The registry is descriptive and does not perform vendor parsing or silently choose a parser.

### Instrument suggestions

`inspect_proc` or `group_inspect_proc` may return:

```text
instrument_suggestions = list of dicts
```

A suggestion can contain:

```text
instrument_plugin_id
id
display_name
type
role
manufacturer
model
serial
firmware
notes
```

If `instrument_plugin_id` is installed, GX-TXT may create the corresponding instrument instance after successful import. Duplicate module/serial associations are not added twice. An unknown instrument plug-in ID is ignored rather than replaced by guessed metadata.

### Compatibility rule

All v0.9.0 extensions are additive. A minimal v0.8.9 handler that declares only `inspect_proc`, `import_proc`, `file_label`, `file_patterns` and optional `supports_batch` remains valid.

## v0.9.5 additive binary-source extension

The API version remains 1. A handler may optionally declare:

```ini
[acquisition_handler]
source_kind=binary
```

Allowed values are `text` and `binary`; omitted means `text` for backward compatibility.

`inspect_proc` now receives two additive request fields:

```text
source_kind=<text|binary>
preview_dir=<framework-owned temporary directory, possibly empty>
```

For binary sources the common Preview workspace never attempts to render source bytes as text. The handler may return Preview Descriptor API v1 fields (`preview_kind`, `preview_metadata`, `preview_artifact`). Artifact generation is optional when `preview_dir` is empty.

Dataset dictionaries returned by `import_proc` may additionally contain:

```text
storage_kind=text|binary
media_type=<MIME media type>
```

These fields describe the canonical dataset representation and are independent of the scientific `contract`.

### Acquisition project Test (P032)

The primary **Run → Test** command in Acquisition Plugin Builder and **Develop → Test**
in its C++ source Workspace share one CORE selection/configuration dialog. Choose
1–64 ordinary files, an actual saved format profile and typed configuration.
Configuration values here are transient Test overrides of the declared defaults;
they do not change ModuleCfg, Configuration or a Session Manifest. Cancel keeps
source and drafts. Changed source revisions refuse and require a fresh review.

`VIEWER_DEVELOPMENT_API_v1` retains its `test` operation. For an Acquisition target
its `request_json` uses `gxtxt.acquisition_project_test.v1` with `expected_revision`
(from public ProjectFiles `describe`), `profile_id`, absolute chosen `sources`,
and optional typed `config`. The complete request is bounded to64KiB; files are
bounded to2GiB aggregate and the actual native Test to60seconds after admission.
No private Tcl command is required. `project_test_available` is distinct from the
Viewer-style `runtime_available` flag; Acquisition has no synthetic Viewer Demo.

Test uses the existing normal candidate exporter and distributed native admission
without installing/registering the module. The same Source Grant checks full SHA,
the existing guarded broker executes the actual compiled callbacks, and the same
typed buffer owner verifies/seals then discards provisional outputs after reap.
No Session, Registry entry, Dataset, Dataset Group or scientific publication is
created. The current producer/profile/config/source closure remains pinned;
foreign profiles, stale revisions, unknown config, FIFO/linked sources, protected
producer replacement and malformed output identity refuse. The private
`derived/acquisition-test.json` reports actual guard, configuration and source
identities, discarded output schema/SHA and reap; it explicitly does not certify
scientific correctness or final installed-module behavior. Normal Plugin Manager
admission and real canonical import/rollback/GUI acceptance remain separate.

Project Test first invokes the saved **recognize** and **inspect** callbacks in
separate admitted, bounded read-only phases. It reports their actual metadata
and reaped actors before the full import-callback Test; an unrecognized source
refuses without creating numeric outputs. All three phases share the reviewed
source/configuration closure and overall60second native deadline. This exercises
the declared callbacks without assigning scientific validity to their claims.
The Acquisition API and Development metadata report helper availability through
the same actual CORE helper admission owner, independently of reference catalog
presence.

Native Acquisition `integer` configuration is signed64. CORE rejects values
outside −9223372036854775808…9223372036854775807 before JSON/native conversion.
The normal Configuration owner and shared project Test form apply these implicit
bounds unless the producer declares a narrower range. Programmatic ModuleCfg
inspection is checked again at admission. General UI Field bignums, typed
scientific uint64 payloads and the existing codec ABI keep their domains.
