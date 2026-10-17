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

API v2 is the CORE-owned write lifecycle for
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
Python/Octave `write_variable` and shaped `append` preserve this same row-major
meaning for flat numeric arrays. A naturally shaped array retains its logical
indices. The Script adapter reshapes before column-major resource encoding;
changing transport never changes Dataset dimension order. Already shaped
resources and vector views retain their direct forwarding path.


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

`auto` uses CORE Storage Auto size policy v2. Optional `expected_rows` and
`estimated_numeric_bytes` are nonnegative integers or `-1` for unknown. At least
100,000 rows, at least 8 MiB, or both sizes unknown prefer HDF5; a known small
table prefers CSV. Required capabilities remain authoritative: unsupported
providers are rejected and normal policy selection resolves a compatible one.
Explicit storage requests retain their requested provider. Managed-resource
helpers below select HDF5 because their writer requires managed binary writes.

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

<a id="language-binding-transport-in-gx-txt-09730"></a>
## Language-binding transport

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
transaction rules. Current Octave Bridge packing uses managed binary resources
for arrays above 64 elements, non-double numeric arrays and complex arrays;
small real double arrays may use the control representation. Descriptor v2
preserves exact integer values and source precision; see
`SCIENTIFIC_BINARY_TRANSPORT_v2.md`. The shared transport supports 13 dtypes,
including complex64/complex128; the canonical Dataset writer supports the 11
real numeric dtypes listed below. Complex transport does not imply complex
Dataset storage: declare explicit real/imaginary Variables when that contract
is required. Managed-capable writers receive owned resource descriptors;
the older typed Base64 block remains a compatibility path for other writers.
Rank-1 `write_variable` accepts either a scalar dimension or a dimension vector.
Dimensions must be nonnegative integers. Storage dtype support remains governed
by this publication API, separately from the transport's dtype capabilities.

Text transport preserves a single empty string when its declared shape has one
element. A zero-length text array retains zero elements.

<a id="simple-scientific-series-and-full-variable-semantics-dev-051"></a>
## Simple scientific series and full Variable semantics

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

<a id="dev-055-reviewed-separate-batches"></a>
## Reviewed separate batches

`datasetPublicationV2BatchPreflight` and `datasetPublicationV2PublishBatch` accept 1..64 create-only reviewed requests. All output IDs and target paths are checked before any publisher runs; duplicate/existing outputs reject the entire batch. The default publisher is the existing `datasetPublicationV2PublishSeries`. Existing trusted host controllers may pass a command prefix and a reviewed per-request `publication_module` when preserving a specialized producer (for example core.native2d primitive reconstruction provenance). The common catalog transaction owns notification and rollback. Callback controllers must create only the reviewed new outputs and use existing Publication v2, without changing predecessors. A failed batch restores registry bytes and deletes its new registered payloads/metadata.

Python/Octave `publish_series_batch` takes `{series: [ordinary_publish_series_request, ...]}`; result has `atomic`, `output_count`, `dataset_ids`, and ordinary publication receipts with raw paths removed. It shares existing units/schema/provenance validation. Scripts cannot supply a host callback.

<a id="dev093-local-concurrency-and-recovery"></a>
## Local concurrency and recovery

`replace_owned=true` also permits a new ID. Prepare records an explicit creating
or replacing operation; finalize revalidates full revision/producer/namespace and
immutable protection under the shared per-Session transaction. Distinct writers
cannot lose each other's registry updates. Provider streaming and hashing remain
outside the commit lock. The shared CORE transaction and recovery guarantees remain authoritative.
<a id="managed-binary-writes-in-dev097"></a>
## Managed binary writes

The additive writer capability `managed_binary_write` advertises the canonical
HDF5 resource lane. `datasetPublicationV2WriterCapabilities(writer)` and Script
Bridge `writer_capabilities(writer)` expose capabilities; Bridge
`diagnostics(writer)` returns actual counters including `resource_blocks` and
`resource_bytes` alongside legacy Base64 counters. These calls require an open
writer token from the same execution.

Public Python/Octave arrays preserve dtype and multidimensional element order.
The existing HDF5 writer consumes validated CORE resources within their delegated
execution scope. A different declared numeric target dtype requests conversion
at this writer; invalid integer ranges are rejected before conversion, including
floating-point 2^64 for uint64. Provider errors leave the writer failed: abort
and prepare a fresh transaction. Scientific source Datasets remain immutable.
Standalone Octave helpers use the same transport with unchanged public call
signatures; CSV and legacy small callers retain their supported paths.

## Managed column-major resources

Tcl `::GX::datasetPublicationV2PublishManagedColumns session module_id definition
reference schema` and registered Script Bridge `publish_managed_columns(definition,
resource, schema)` publish an owned matrix through the existing canonical writer.
The required format is `gxtxt.numeric_matrix.float64_column_major_le.v1`, with
positive `row_count`, 1–128 distinct ordered `column_ids`, exact 8×rows×columns
bytes and a maximum 512 MiB resource. Schema entries must declare matching IDs
and `dtype=float64`; optional rank/shape/dimension declarations must agree with
a single `row` dimension. Auto storage selects HDF5; unsupported writers refuse.

CORE checks live owner/SHA, streams each column in at most 1 MiB chunks, and
delegates binary-v2 descriptors to the existing writer. It neither calculates
statistics nor parses a private Dataset format. Publication remains create-only,
with canonical schema/metadata and rollback on an actual writer failure. The
outer Script Bridge workspace scope is restored after success or failure.
Returned publication metadata includes integer `row_count`; Script results omit
private output paths and record the published Dataset in the supervising Job.

This contract must not be confused with the row-major
`gxtxt.numeric_matrix_le_v1` resource used by `MANAGED_RESOURCE_API_v1/write_numeric`.
Relabelling existing row-major bytes as column-major is invalid.

## Managed multidimensional variables

Tcl `::GX::datasetPublicationV2PublishManagedVariables session module_id definition
dimensions variables` and Python/Octave `publish_managed_variables(definition,
dimensions, variables)` publish owned arrays through the same public writer.
`dimensions` maps 1–16 distinct canonical dimension IDs to positive extents.
`variables` contains 1–128 entries with exactly `variable_id`, `schema`, and
`resource`. The reference is a live Interactive Document owned resource, with
`format=gxtxt.numeric_array_le.v1`, `endian=little`, `order=F`, exact dtype and
shape. It is never a raw filesystem path or an inlined numeric array.

Each schema declares an identical dtype and ordered `dimension_ids`, separated
by semicolons (for example `y_sample;x_sample`). Its logical shape must equal
the owned resource shape. Optional schema rank, shape and identity must agree;
an owned resource unit, when present, must equal the declared canonical unit.
This lane writes explicit arrays; uniform coordinates use their separate public
declaration. Supported dtypes are float32/float64, signed and unsigned 8/16/32/64
bit integers, and bool. These 11 real numeric types are a Dataset writer contract;
the broader managed scientific transport also supports complex arrays.

CORE checks owner, generation, SHA256, dtype/shape byte length and the 512 MiB
per-array limit before publication. It stages at most 1 MiB per copy chunk,
verifies the staged hash and delegates to the canonical `managed_binary_write`
provider. Auto selects HDF5; incapable explicit writers fail and abort. There is
no private HDF5 parser, statistics computation or conversion of exact integers
into floating control values. Existing create-only/explicit owned-replacement
policy, schema, metadata and rollback rules remain authoritative.

Returned metadata includes integer `variable_count`. Script results omit private
paths and record the publication in the supervising Job. Success or failure
restores the outer Bridge workspace scope. Consumers may reuse the validated
input resources returned by [Fitter surface results](FITTER_SURFACE_v1.md)
without expanding the payload in Script control messages.

## Automatic same-owner replacement (dev102)

When replacing an existing owned Dataset with `storage=auto`, CORE retains the
canonical provider/path when its declared capabilities support the new request.
CSV remains CSV; HDF5 remains HDF5. Explicit provider requests keep their explicit
semantics. A retained provider that cannot meet required capabilities returns an
explicit incompatibility/migration diagnostic without altering the old Dataset.
No implicit migration or Dataset deletion is performed. New-Dataset auto policy
is unchanged. Exact IDs, authority rollback and source provenance remain enforced.
Owned descendants of `module/<producer>/` are valid scientific namespaces;
shared input namespaces still require explicit grants and CREATE-only publication.
