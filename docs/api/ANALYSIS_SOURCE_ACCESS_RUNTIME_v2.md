# Analysis Source Access Runtime Extension v2

SPDX-License-Identifier: GPL-3.0-or-later

GX-TXT 0.9.7.23 extends Standard Module runtime.ini additively for consumers of
Canonical Dataset API v2. Existing path, contract, format, storage kind,
media type, variables, units and semantic fields remain present.

Each `[analysis_source.<id>]` section additionally publishes:

```text
access_api_version=2
storage_provider=csv|hdf5|...
capabilities=semicolon-separated true capabilities
row_count=<known count or -1>
sample_count=<known count or -1>
```

Each existing `[analysis_source.<id>.variable.<n>]` section additionally
publishes the Dataset Variable Schema v3 fields for dtype, rank, shape,
dimensions, coordinate relationships, uniform axes, components and logical
groups.

Runtime metadata is discovery information. Consumers perform reads through
Canonical Dataset API v2 and must not open HDF5 paths or import provider
libraries directly. Standard Module API v1 and Analysis Source Map API v1 are
unchanged.

## Dataset Metadata runtime bridge

Analysis Source Access Runtime v2 remains the backend-neutral discovery/read
contract for scientific Dataset data. GX-TXT 0.9.7.57 adds a separate additive
[Analysis Source Dataset Metadata Runtime Extension v1](ANALYSIS_SOURCE_DATASET_METADATA_RUNTIME_v1.md)
for arbitrary Dataset-level namespaced metadata. It does not change access
providers, capabilities, row/sample counts, variable schemas or Dataset read
semantics.

## Elapsed-time values

Analysis Source runtime metadata preserves the Dataset Variable Schema fields,
including the original `unit`, `value_kind`, and `value_format`. Numeric data is
read through CORE. Therefore `value_kind=elapsed_time` / `value_format=hms` is
received numerically as elapsed seconds according to
[Elapsed Time Contract v1](ELAPSED_TIME_CONTRACT_v1.md); consumers must not use
the preserved source-unit field to rescale the already normalized value. When a
consumer needs another temporal representation it may use
[Elapsed Time Requested-Unit API v1](ELAPSED_TIME_REQUESTED_UNIT_API_v1.md),
which converts explicitly from canonical seconds through the Unit Registry.
