# Canonical Dataset API v2

SPDX-License-Identifier: GPL-3.0-or-later

Canonical Dataset API v2 is the CORE-owned, backend-neutral read contract for
GX-TXT 0.9.7.23. It extends Canonical Dataset API v1 without replacing the
existing registry, Dataset ID, path resolution, or scientific contract.

## Identity and ownership

A logical dataset is identified by its stable Dataset ID. Variables retain the
stable pair `dataset_id + variable_id`. `storage_provider` selects a CORE
implementation and is not a second scientific identity. Physical HDF5 object
paths are private provider locators; they are not returned in Variable Schema
v3 or Analysis Source runtime metadata.

The datasets.ini registry format remains readable by v1 consumers. Version 2
adds `access_api_version=2`, `storage_provider`, cheap counts and additive
Variable Schema v3 fields.

## Public Tcl operations

```tcl
set handle [::GX::datasetAccessOpen $session $datasetId]
set metadata [::GX::datasetAccessMetadata $handle]
set capabilities [::GX::datasetAccessCapabilities $handle]

set all [::GX::datasetAccessReadVariables $handle {v0001 v0002}]
set range [::GX::datasetAccessReadRange $handle {v0001 v0002} $start $count]
set binary [::GX::datasetAccessReadRangeBinary $handle {v0002} $start $count]
set transport [::GX::datasetAccessReadRangeTransport $handle {v0001 v0002} $start $count]
set slab [::GX::datasetAccessReadHyperslab $handle v0003 {10 20} {4 8}]
set binarySlab [::GX::datasetAccessReadHyperslabBinary $handle v0003 {10 20} {4 8}]
set chunks [::GX::datasetAccessIterateChunks $handle {v0002} 65536 callback]

::GX::datasetAccessClose $handle
```

`count=-1` means the remaining extent. Reads return a dictionary keyed by
stable variable ID. Each result contains `dtype`, `shape`, `values`, `start`
or hyperslab coordinates, `count`, and whether CORE synthesized the values.
Multidimensional variables are never silently flattened by the generic range
operation; consumers must request an explicit hyperslab.

`datasetAccessWith` provides a try/finally convenience wrapper. Closing an
already closed handle is harmless. Operations on an unknown handle fail.

## Metadata

`datasetAccessMetadata` returns:

- API version, Dataset ID, scientific contract, format and storage provider;
- row/sample count when known without a payload scan;
- the complete capability dictionary;
- Dataset Variable Schema v3 records;
- logical group IDs.

Metadata is cached per open handle. HDF5 metadata reads object headers,
attributes, dtype, shape and chunk information without reading numeric array
elements.

## Capabilities

Every provider reports all capability keys with a boolean value:

```text
read_full
read_selected_variables
row_range_read
random_access
chunk_read
hyperslab_read
multidimensional
groups
implicit_axis
typed_binary_read
```

The CSV provider supports full, selected, range and chunk reads and implicit
axes. Its range operation scans the text prefix, so `random_access=0`.

The HDF5 provider supports every listed read capability. A CORE-owned Python
worker opens one HDF5 file per access handle and remains alive until close.
Repeated chunks therefore reuse one process and one file handle. Consumers do
not depend on Python, h5py, HDF5 paths, or the worker protocol.

## Uniform implicit axes

A variable with `coordinate_role=coordinate`, `axis_kind=uniform`, origin,
step and count may have no stored payload. A range request synthesizes exactly
the requested values:

```text
value[i] = origin + (start + i) * step
```

No full coordinate column is allocated.

## Elapsed-time numeric contract

For a CSV variable declared with `value_kind=elapsed_time` and
`value_format=hms`, typed reads parse the supported HMS source representation
and expose numeric elapsed **seconds**. A compatible source `unit` declaration
of `s`, `min`, or `h` remains schema metadata and does not rescale that parsed
number. Consumers must not reconstruct or reinterpret the original text. See
[Elapsed Time Contract v1](ELAPSED_TIME_CONTRACT_v1.md).

## Compatibility

- Existing CSV consumers may keep using Canonical Dataset API v1, Analysis
  Source paths, Table Stream v2, and Dataset Variable Schema v2.
- New consumers use the same v2 access calls for CSV and HDF5.
- This phase does not materialize HDF5 as CSV for old consumers.
- Publication, writing, indexed CSV, mmap, NetCDF, Zarr, plot loading, FFT,
  audio, extraction, Spectrogram and CFD remain outside this API version.

## Typed binary numeric reads (GX-TXT 0.9.7.37)

Providers advertising `typed_binary_read=1` may return compatible numeric
ranges and hyperslabs as contiguous binary blocks. The public block dictionary
contains:

```text
__gxtxt_binary_block=1
dtype
endian=little|big
shape
byte_count
base64
```

`datasetAccessReadRangeBinary` requires a binary-capable numeric variable.
`datasetAccessReadRangeTransport` selects a binary block when the variable and
provider support it and otherwise returns the existing `values` item. This
mixed transport operation is intended for generic language bridges. Dataset
and variable IDs, schema metadata, range semantics and provider ownership are
unchanged.

Supported transport dtypes are `float32`, `float64`, `int8`, `int16`, `int32`,
`int64`, `uint8`, `uint16`, `uint32`, `uint64` and `bool`. Text/string and
unsupported numeric dtypes use the value fallback. Uniform implicit
coordinates are synthesized only for the requested range and encoded with
their declared `float32` or `float64` dtype.

See [Typed Binary Read Transport v1](TYPED_BINARY_READ_TRANSPORT_v1.md) for the
provider protocol, validation rules and Octave reconstruction.

## Octave Script Bridge

Bridge API ID: `CANONICAL_DATASET_API_v2`. The provider registers:

| Operation | Positional `args` | Result |
|---|---|---|
| `list` | `{}` | Cell of Dataset IDs in the current Session. |
| `describe` | `{dataset_id}` | Metadata struct with a cell of variable structs. |
| `read_range` | `{dataset_id, variable_id_cell, zero_based_start, count}` | Struct keyed by stable variable ID; each item has `dtype`, shape/range metadata and `values` as a numeric array or text cell. |

`read_range` retains the Canonical Dataset API bounds and stable variable ID
rules. Use a bounded `count` for large Datasets. The bridge does not expose a
Dataset file path or an open storage handle to user scripts.
