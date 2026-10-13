# Table Stream API v3

Introduced in GX-TXT 0.9.7.25. Table Stream API v3 is the table-shaped,
backend-neutral streaming facade over Canonical Dataset API v2.

```text
consumer
  -> Table Stream API v3
  -> Canonical Dataset API v2
  -> CSV, HDF5, or a future registered provider
```

Canonical Dataset API v2 remains the general scientific data-access owner.
Use Table Stream only when the selected scientific object consists of rank-1
variables sharing one logical row dimension. Use Canonical Dataset API v2
directly for matrices and general n-dimensional data. Table Stream never
flattens an n-dimensional variable.

## Compatibility

The existing Octave API remains available and unchanged for bare CSV paths:

```octave
S = gxtxt_table_stream_open(path, columns, chunk_rows);
[S, chunk] = gxtxt_table_stream_next(S);
S = gxtxt_table_stream_close(S);
```

This legacy branch retains API v2 raw-cell values, path-based schema discovery,
CSV parsing, byte progress, and current error behavior. Historical modules do
not need Dataset IDs in this release.

## CORE Tcl operations

```tcl
set stream [::GX::tableStreamOpenDataset \
    $session $datasetId $variableIds $chunkRows \
    [dict create start 0 count -1 require_direct 0 numeric_transport auto]]
set metadata [::GX::tableStreamMetadata $stream]
set chunk [::GX::tableStreamNext $stream]
set diagnostics [::GX::tableStreamDiagnostics $stream]
::GX::tableStreamClose $stream
```

An Analysis Source runtime can be opened without directory walking:

```tcl
set stream [::GX::tableStreamOpenSource \
    $runtimeIni primary {v_time v_voltage} 4096]
```

The runtime supplies `runtime.session` and
`analysis_source.<id>.dataset_id`. Each stream owns an independent Canonical
Dataset access handle, selection, range, and cursor.

## Modern Octave operations

```octave
options = struct('start', 8000000, 'count', 65536, ...
                 'require_direct', true);
S = gxtxt_table_stream_open_dataset(
      session, 'waveform.main', {'v_time','v_voltage'}, 4096, options);
[S, chunk] = gxtxt_table_stream_next(S);
metadata = gxtxt_table_stream_metadata(S);
diagnostics = gxtxt_table_stream_diagnostics(S);
S = gxtxt_table_stream_close(S);
```

Analysis Source form:

```octave
S = gxtxt_table_stream_open_source(
      runtime_cfg, 'primary', {'v_time','v_voltage'}, 4096, options);
```

The modern Octave adapter keeps a persistent private Tcl bridge for the stream
lifetime. The bridge calls Table Stream v3 and Canonical Dataset API v2. It
does not parse CSV or HDF5, detect backends, or start a process per chunk.

## Table validation and metadata

Every selected variable must exist by stable Variable ID, have rank 1, declare
one dimension, share that row dimension, use a supported Schema v3 dtype, and
have a consistent row count. Duplicate IDs are rejected. Empty selection means
all variables and succeeds only if the entire dataset is table-shaped.

Metadata transports the existing Dataset ID, provider capabilities, row
dimension/count, selected IDs in requested order, canonical/display names,
dtype, units, semantic roles, coordinates, implicit-axis fields, range, and
chunk size. The API creates no second schema registry.

## Chunk contract

Each CORE chunk contains `api_version=3`, Dataset ID, zero-based absolute
offset, row count, selected IDs, an ordered Schema v3 column list, values keyed
by Variable ID, and end-of-stream state. The final chunk may be shorter than
`chunk_rows`. Reads after end return an empty `eof=1` chunk. `count=0` creates
an immediately empty stream; `count=-1` means the remaining rows.

Modern Octave numeric columns use declared Octave-compatible types: `double`,
`single`, signed/unsigned integer classes, or logical. Strings remain cell
vectors. Legacy chunks retain raw text cells. For `value_kind=elapsed_time` /
`value_format=hms`, both modern and legacy numeric views follow
[Elapsed Time Contract v1](ELAPSED_TIME_CONTRACT_v1.md) and expose elapsed
seconds by default.

Since GX-TXT 0.9.7.37 the Octave Dataset/Analysis Source adapter requests
`numeric_transport=auto`. Compatible HDF5 numeric columns and implicit uniform
coordinates are emitted by the private bridge as `BCOL` blocks and reconstructed
with Base64 decode, `typecast`, conditional `swapbytes` and shape validation.
The older `COL` value protocol remains the fallback. Direct Tcl streams default
to `numeric_transport=values` for source compatibility and may opt into `auto`.
Chunk diagnostics report binary/value column counts and binary bytes.

## CSV behavior

Dataset-aware CSV uses Canonical Dataset API v2. Unused columns are not
accumulated in the returned chunk, although rows must still be tokenized. CSV
reports `random_access=0`, `range_mode=sequential_fallback`, and prefix scan
diagnostics. `require_direct=1` rejects it. Legacy bare-path CSV keeps the
current v1/v2 parser.

## HDF5 behavior and implicit coordinates

Table-shaped HDF5 reads only selected physical variables through the Canonical
provider. Ranges start directly, chunks remain bounded, and diagnostics report
zero prefix scanning. No intermediate CSV is created.

An implicit coordinate is synthesized only for the current chunk as
`origin + (absolute_start + i) * step`. The complete coordinate is never
allocated.

## Range, memory, lifecycle, and errors

`start` is zero-based. `count` is `-1` or nonnegative. Known out-of-range
requests fail during open, and `chunk_rows` must be positive. Working data is
bounded by selected variables times current chunk size plus provider/transport
workspace. The facade never concatenates complete vectors.

Close releases the owned Canonical handle and provider resources. Double close
is idempotent; read after close fails. Provider failure leaves cleanup
available. Explicit failures cover unknown/duplicate IDs, invalid ranges,
missing providers, provider termination, disappeared storage, dtype mismatch,
inconsistent dimensions/counts, and non-table variables.

## Whole-table helpers

`gxtxt_read_csv_table()` and `gxtxt_table_column()` remain because existing
consumers use their whole-table behavior. New large-data-aware table code
should use Table Stream v3. No scientific module was migrated in 0.9.7.25.
## Complete-record framing in the Octave bridge (GX-TXT 0.9.7.77)

The `standard_octave` Table Stream adapter uses `popen2`, whose output pipe is nonblocking. A single Tcl protocol record, especially a typed-binary `BCOL` record containing a large Base64 payload, may therefore be returned by Octave `fgets()` in multiple fragments before the terminating LF is available.

The Octave reader accumulates these fragments and exposes a record to the Table Stream parser only after the newline terminator has been received. A bridge that exits with an unterminated partial record produces an explicit incomplete-record diagnostic. This is transport framing only: chunk sizes, Dataset identities, `numeric_transport`, binary block semantics and public Table Stream API v3 signatures are unchanged.

