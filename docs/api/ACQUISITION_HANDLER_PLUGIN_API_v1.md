# GX-TXT Acquisition Handler Plugin API v1

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

### Structured Dataset Metadata transfer

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
