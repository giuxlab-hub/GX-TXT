# Dataset Publication API v2

`datasetPublicationV2PlanInfo plan` returns logical identity, status, contract,
requested/effective provider, version, selection reason and capability requirements
without staging/destination paths. `datasetPublicationV2SetPlanMetadata plan metadata`
validates and sets structured metadata while the plan is prepared; it rejects
changes after a writer opens. These host lifecycle services let CORE producers
record the actual provider in the same transaction. Scripts supply metadata in
their normal `begin/publish_series` definition.

Host callers collecting a public Dataset name/ID may use
`datasetPublicationV2RequestedId requested_id ?fallback_prefix?`: a nonempty
trimmed request is validated by the standard Dataset ID grammar and returned
unchanged. Invalid requests are rejected. A generated technical ID is returned
only when the request is empty. `Prepare` remains the collision/ownership
authority. Include `structured_metadata` in the publication definition and
`display_label`, `unit`, `semantic_role` and `value_kind` in variable declarations
so payload, schema and metadata commit atomically.

Introduced in GX-TXT 0.9.7.24. API v2 is the CORE-owned write lifecycle for
backend-neutral canonical datasets. Dataset Publication API v1 remains
available with its existing request-file contract and behavior.

## Identity and schema

The public identity tuple is `dataset_id`, `variable_id`, and `dimension_id`.
Callers never pass HDF5 paths, CSV column numbers, provider handles, delimiter
rules, or backend objects. Published variables use Dataset Variable Schema API
v3 directly; there is no publication-only output schema.

The lifecycle is:

```text
logical declaration
  -> CORE publication plan and provider selection
  -> open generic writer
  -> dimensions and Schema v3 variables
  -> bounded writes
  -> provider validation and close
  -> whole-file SHA-256
  -> atomic placement
  -> Dataset Registry commit
```

The registry is not changed before every preceding step succeeds. The
temporary object has a `.partial` suffix in the destination directory. Abort
and failure remove it. Registry persistence failure removes the placed object
and restores the previous registry file and in-memory state.

## Public commands

```tcl
set plan [::GX::datasetPublicationV2Prepare $session $moduleId $definition]
set writer [::GX::datasetPublicationV2OpenWriter $plan]

::GX::datasetPublicationV2DeclareDimension $writer $dimensionId $size $options
::GX::datasetPublicationV2DeclareVariable $writer $variableId $schemaFields
::GX::datasetPublicationV2DeclareUniformCoordinate \
    $writer $variableId $dimensionId $origin $step $schemaFields

::GX::datasetPublicationV2WriteVariable $writer $variableId $values $shape
::GX::datasetPublicationV2WriteRange $writer $variableId $start $values
::GX::datasetPublicationV2Append $writer $dimensionId $variableData
::GX::datasetPublicationV2WriteHyperslab \
    $writer $variableId $starts $counts $values
::GX::datasetPublicationV2Flush $writer
::GX::datasetPublicationV2Diagnostics $writer
set result [::GX::datasetPublicationV2Finalize $writer]
::GX::datasetPublicationV2Abort $writer
```

`shape`, `starts`, and `counts` use logical dimension order. A rank greater
than one is never flattened. For multidimensional append, each variable value
is a dictionary containing `shape` and flat row-major `values`.

## Publication definition

Required keys are `dataset_id` and `contract`. Optional keys are:

- `storage`: `auto`, `csv`, or `hdf5`;
- `capabilities_required` and `capabilities_preferred`;
- `relative_path` below the session directory;
- `producer_version`, `source_dataset_ids`, and `source_variable_ids`;
- `source`, `provenance`, and `notes`.
- `replace_owned`: boolean, default false. When true, an existing Dataset may
  be replaced only if it was published by the same module through Publication
  API v2 and the publication target path is unchanged.

`auto` is deliberately small and deterministic in this release. A request
requiring append, hyperslab, multidimensional, group, or typed-numeric
capabilities prefers HDF5. A simple compatible table prefers CSV. Preferred
capabilities break ties by count. This is provider selection infrastructure,
not the final size-aware Storage Auto policy.

The plan records requested and effective provider, provider version, required
and preferred capabilities, selection reason, final relative target, and the
temporary target. The finalized registry records the same provenance plus API
versions and measured integrity time. Storage choice is provenance and is not
part of scientific dataset identity.

## Dimensions and variables

Dimension options accept `extendible=1`. A fixed dimension has its declared
size. An extendible dimension starts at its declared size and grows only
through `datasetPublicationV2Append`.

Variable declarations accept Schema v3 fields including `dtype`, `rank`,
`dimension_ids`, `coordinate_variable_ids`, `coordinate_role`, `axis_kind`,
`axis_origin`, `axis_step`, `component_ids`, and `group_id`. Shape is derived
from declared dimensions and an explicitly supplied shape must agree.

An implicit uniform coordinate is rank one, has `coordinate_role=coordinate`,
and stores origin, step, and count. HDF5 omits its payload and Canonical Dataset
API v2 reconstructs requested values. CSV materializes the coordinate column
for interoperable tabular storage while retaining the same logical Schema v3
semantics.

## Capability discovery

```tcl
::GX::datasetWriterProviderIds
::GX::datasetWriterProviderCapabilities csv
::GX::datasetWriterProviderCapabilities hdf5
```

Capability names are `complete_variable`, `range_write`, `append_write`,
`hyperslab_write`, `multidimensional`, `groups`, `implicit_axis`,
`typed_numeric`, `sequential_chunks`, and `human_readable`.

CSV advertises sequential tabular writes and rejects random range writes,
hyperslabs, groups, and multidimensional variables. HDF5 advertises typed,
chunked, extendible, range, append, group, and n-dimensional hyperslab writes.
A provider rejects an operation outside its actual capabilities.

## Finalization and integrity

The HDF5 provider validates declared objects before closing its persistent
worker. CORE then computes conservative whole-file SHA-256 in a separate pass.
`integrity_seconds` measures only that pass. The result and registry contain
the authoritative hash; a caller-supplied hash is never accepted.

After finalization, a second finalize fails. Finalize after abort fails. Abort
is idempotent before finalization and cannot remove a finalized dataset.

Owned replacement preserves the previous publication file and Dataset Registry
until the new provider output, integrity pass, atomic placement, and registry
commit all succeed. Any failure restores both previous artifacts. It never
permits one module to replace another module's Dataset or a Dataset created
outside Publication API v2.

## Required failure behavior

API v2 raises explicit errors for unavailable/unsupported backends, missing
HDF5 runtime dependencies, duplicate IDs, invalid dtype or schema, shape and
value-count mismatch, append to a fixed or unknown dimension, out-of-bounds
hyperslabs, incompatible typed values, worker termination, integrity failure,
and registry commit failure. None of these conditions registers a dataset.

## Runtime discovery

Standard Module runtime files retain the v1 `[dataset_publication_api]`
section and add:

```ini
[dataset_publication_api_v2]
api_version=2
identity=dataset_id;variable_id;dimension_id
storage_providers=csv;hdf5
```

The existing v1 INI request directory and Octave helper are unchanged.

## Language-binding transport in GX-TXT 0.9.7.30

Language bindings may use the internal typed binary block representation for numeric payloads. This representation does not change Dataset Publication API v2 operations, validation, transaction behavior, or provider contracts.

## Octave Script Bridge

Bridge API ID: `DATASET_PUBLICATION_API_v2`. The bridge exposes the normal
publication lifecycle with an opaque writer token. The current module and
Session own the publication.

| Operation | Positional `args` | Result |
|---|---|---|
| `begin` | `{definition_struct}` | Opaque writer token; combines public prepare and open. |
| `declare_dimension` | `{writer, dimension_id, size, options_struct}` | Empty string on success. |
| `declare_variable` | `{writer, variable_id, schema_struct}` | Empty string on success. |
| `write_variable` | `{writer, variable_id, values, shape}` | Empty string on success. |
| `append` | `{writer, dimension_id, variable_data_struct}` | Empty string on success. |
| `finalize` | `{writer}` | Publication result struct. |
| `abort` | `{writer}` | Empty string on success. |

Unfinalized writers are aborted when the script bridge stops. The definition,
schema, shapes and append chunks follow this API's normal validation and
transaction rules. Numeric arrays use binary bridge transport above 10,000
elements rather than decimal JSON lists.

Text transport preserves a single empty string when its declared shape has one
element. A zero-length text array retains zero elements.

## Simple scientific series and full Variable semantics (dev-051)

`::GX::datasetPublicationV2PublishSeries session module_id request` (Bridge `publish_series`) publishes one 1-D X/Y series through the normal V2 prepare/open/declare/append/finalize transaction. Required fields: `dataset_id`, `contract`, equal nonempty `x_values`/`y_values`, and `x_variable`/`y_variable` descriptor structs with distinct stable `variable_id`. Optional storage, source/provenance, producer version, source Dataset/Variable IDs, notes, structured metadata and ownership fields follow the writer contract. No filesystem destination is supplied by scripts.

Integer value-list validation uses exact Tcl integers with each declared dtype's
explicit bounds. int64/uint64 values above 2^53 remain integers; signed/unsigned
64-bit endpoints are accepted, and overflow, negative unsigned values and
fractional notation are rejected before writer mutation.

Variable descriptors support `name`, `display_label`, `unit`, `semantic_role`, `semantic_source`, `value_kind`, `value_format`, `decimal_separator`, `time_origin`, `time_reference`, `canonical_unit`, `to_canonical`, `from_canonical`, instrument associations and existing V3 typed/dimensional fields. Source-format defaults are decimal dot and elapsed reference. Numeric/string dtype must agree with value kind; HMS elapsed-time data requires the declared HMS/unit semantics. Custom canonical relations require both restricted formulas and a canonical unit. Defining a relation does not silently invent conversions for opaque units such as ppm or pH. The registry and typed payload retain the declared representation. Consumers use public Unit/Canonical Dataset APIs for requested interpretation/conversion.

```tcl
::GX::datasetPublicationV2PublishSeries $session my.service [dict create \
    dataset_id sampled_curve contract table.generic storage csv \
    x_values {0 1000 2000} y_values {1 2 3} \
    x_variable [dict create variable_id time name time_ms unit ms \
        canonical_unit s to_canonical {x/1000} from_canonical {x*1000}] \
    y_variable [dict create variable_id response name response unit V \
        semantic_role voltage display_label {Response voltage}] \
    structured_metadata [dict create experimental.sample silver]]
```

Both Python and Octave Bridge expose the helper and complete `declare_variable` fields. Dataset Metadata API associates metadata during publication and supports read/update/unset afterward. See [combined schema mutation](DATASET_VARIABLE_SCHEMA_API_v3.md), [file publication](DATASET_FILE_PUBLICATION_API_v1.md) and `examples/scripts/combined_stabilization.py` / `.m`.

## dev-055 reviewed separate batches

`datasetPublicationV2BatchPreflight` and `datasetPublicationV2PublishBatch` accept 1..64 create-only reviewed requests. All output IDs and target paths are checked before any publisher runs; duplicate/existing outputs reject the entire batch. The default publisher is the existing `datasetPublicationV2PublishSeries`. Existing trusted host controllers may pass a command prefix and a reviewed per-request `publication_module` when preserving a specialized producer (for example core.native2d primitive reconstruction provenance). The common catalog transaction owns notification and rollback. Callback controllers must create only the reviewed new outputs and use existing Publication v2, without changing predecessors. A failed batch restores registry bytes and deletes its new registered payloads/metadata.

Python/Octave `publish_series_batch` takes `{series: [ordinary_publish_series_request, ...]}`; result has `atomic`, `output_count`, `dataset_ids`, and ordinary publication receipts with raw paths removed. It shares existing units/schema/provenance validation. Scripts cannot supply a host callback.

## dev093 local concurrency and recovery

`replace_owned=true` also permits a new ID. Prepare records an explicit creating
or replacing operation; finalize revalidates full revision/producer/namespace and
immutable protection under the shared per-Session transaction. Distinct writers
cannot lose each other's registry updates. Provider streaming and hashing remain
outside the commit lock. See transaction and recovery requirements described in this document.
