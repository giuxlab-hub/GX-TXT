# GX-TXT Dataset Publication API v1

Version introduced: **GX-TXT Pipeline v0.8.8**.

## Purpose

An analysis module may produce a file that should become a first-class canonical dataset in the current GX-TXT session. The module must **not edit `metadata/datasets.ini` directly**.

Dataset Publication API v1 separates responsibilities:

```text
module computes/writes file
        ↓
module writes publication request
        ↓
module exits successfully
        ↓
GX-TXT validates request + file
        ↓
GX-TXT computes SHA-256
        ↓
GX-TXT updates metadata/datasets.ini
```

Publication is processed only after successful module execution. Rerender does not publish datasets.

## Required publication metadata

Every publication records at least:

- `dataset_id`
- `contract`
- `format`
- `path`
- `source_module` — framework-owned, taken from the executing module ID
- `variables`
- `units`
- `semantic_roles`
- `source`
- `provenance`
- SHA-256 — computed by the framework, never trusted from the module

`variables`, `units`, `semantic_roles`, `source`, and `provenance` may be empty when genuinely unavailable, but the fields are supported by the contract and are persisted in the Dataset Registry.

## Runtime contract

Standard Module API runtime files contain:

```ini
[dataset_publication_api]
api_version=1
request_dir=/absolute/session/analysis/<module>/dataset_publications
contract_file_format=ini_per_dataset
```

## Publication request format

Each dataset is one UTF-8 INI file in `request_dir`:

```ini
[publication]
api_version=1
dataset_id=reactor.experiment.aggregate
contract=table.generic
format=csv
path=reactor_experiment_aggregate.csv
variables=time_s;voltage_V;current_A;nh3_mg_L
units=s;V;A;mg/L
semantic_roles=time;measure;measure;response
source=reactor experiment aggregate
provenance=derived from reactor.electrical + reactor.chemistry
notes=optional text
```

`path` is relative to the module output directory. Absolute paths and `..` traversal are rejected. The target file must exist and remain inside the module output directory/current session.

## Octave helper

Plugins may use:

```octave
gxtxt_dataset_publish_request(output_dir, dataset_id, contract, format, relpath, meta)
```

from:

```text
core/octave/io/gxtxt_dataset_publish_request.m
```

Example:

```octave
meta = struct();
meta.variables = {'time_s','voltage_V','current_A'};
meta.units = {'s','V','A'};
meta.semantic_roles = {'time','measure','measure'};
meta.source = 'reactor experiment';
meta.provenance = 'derived from primary and chemistry sources';

gxtxt_dataset_publish_request(
    output_dir,
    'reactor.aggregate',
    'table.generic',
    'csv',
    'aggregate.csv',
    meta
);
```

The helper does **not** update the registry and does **not** compute the authoritative hash. It only writes the publication request.

## Dataset Registry result

The framework stores the publication as a normal Dataset Registry entry. Important fields include:

```ini
[dataset.reactor.aggregate]
id=reactor.aggregate
kind=table.generic
contract=table.generic
format=csv
path=analysis/reactor.experiment_aggregate/aggregate.csv
variables=time_s;voltage_V;current_A
columns=time_s;voltage_V;current_A
units=s;V;A
semantic_roles=time;measure;measure
source_module=reactor.experiment_aggregate
source=reactor experiment
provenance=derived from primary and chemistry sources
sha256=<framework-computed SHA-256>
canonical_sha256=<same authoritative SHA-256>
publication_api_version=1
```

## Recalculation / ownership

A module may republish a dataset ID that it already owns through Dataset Publication API v1. The registry entry is refreshed after successful recalculation.

A module may **not** silently replace a dataset ID owned by another module/importer. That is a publication error.

## Descriptor declaration

A publishing module should list its possible output contracts using the existing Standard Module API:

```ini
[outputs]
datasets=table.generic
```

This also exposes the contract through Contract Registry API v1.

## No implicit scientific alignment

Publication does not join, interpolate, resample, or otherwise reinterpret data. It only registers the produced file and metadata. Scientific transformations remain explicit module/Scientific Analysis operations.

## Acquisition handlers

Dataset Publication API v1 remains separate from acquisition. Starting with GX-TXT v0.8.9, new vendor/import formats use Acquisition Handler Plugin API v1 (`ACQUISITION_HANDLER_PLUGIN_API_v1.md`). Acquisition handlers return canonical dataset declarations to the framework; they do not use Dataset Publication API to bypass acquisition lifecycle.

## v0.9.4.1 optional computed annotation sidecar

`meta.computed_annotations` may name a module-output-relative Computed Data Annotation API v1 sidecar. The framework validates it during publication and associates it with the canonical Dataset ID. See `COMPUTED_DATA_ANNOTATION_API_v1.md`.

## v0.9.5 binary dataset metadata

Publication requests may optionally include:

```ini
[publication]
storage_kind=binary
media_type=image/tiff
```

`storage_kind` defaults to `text`; `media_type` is optional. The fields are persisted in the Canonical Dataset Registry and transported to Analysis Source runtime metadata. The Octave helper `gxtxt_dataset_publish_request()` accepts the same fields as `meta.storage_kind` and `meta.media_type`.

## Additive schema inheritance (GX-TXT 0.9.7.19)

For a pure row filter or column projection, a CSV publication can opt into
the existing Dataset Variable Schema API v2 interpretation metadata. Add both
keys to the ordinary API v1 request:

```ini
schema_source_dataset_id=source.dataset
schema_source_variable_ids=v0004;v0001;v0003
```

The IDs are ordered to match the explicitly declared output `variables`
and the CSV header. Every source variable must be an enabled canonical
variable in the registered source dataset. The mapping must contain exactly
one distinct source variable ID per output column. The output CSV header
must match the declared canonical names, including for a header-only file.

The framework resolves each source variable by
`schema_source_dataset_id + schema_source_variable_id` and assigns new
`v0001`, `v0002`, ... IDs scoped to the derived dataset in output-column
order. The same textual ID in two datasets is not the same identity. Source
IDs are never installed as derived-variable identities.

Inherited fields are `unit`, `canonical_unit`, `to_canonical`,
`from_canonical`, `display_label`, `semantic_role`,
`semantic_source`, `semantic_reason`, `instrument_id`,
`instrument_channel`, `value_kind`, `value_format`,
`decimal_separator`, `time_reference`, and `time_origin`.
The output file supplies its own physical column number, original header,
canonical column position, delimiter, and explicit canonical name.
Source physical column and source-channel provenance are not copied.
The inherited unit and semantic role summaries are registered with the
derived dataset. If nonempty `units` or `semantic_roles` are declared in
the request, every entry must match its mapped source variable. A
contradiction fails publication.

The Octave helper accepts `meta.schema_source_dataset_id` and
`meta.schema_source_variable_ids` (a cell array or semicolon-separated
string). Both keys are optional together; requests without them retain
their previous behavior. Schema inheritance does not read or transform
row values, interpolate, resample, sort, join, or change scientific units.

Publication requests for one module are committed as one registry batch.
On validation or persistence failure, the previous Dataset Registry
content is restored and the request files remain pending. Only after a
successful registry save are requests moved to the processed directory.

## dev093 concurrent registration

The entire request batch commits under the shared per-Session Dataset authority,
including fresh registry state, producer/namespace/immutable checks and rollback.
Other writers' successful records are preserved. The original producer-written
module output contract remains; the framework cannot undo file writes a producer
performed before submitting its v1 registration request. New structured producers
should use Publication v2 staging. See [Dataset Publication v2](DATASET_PUBLICATION_API_v2.md).
