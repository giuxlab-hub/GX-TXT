# Table Stream API v1

For GX-TXT 0.9.7.3 and later, see `TABLE_STREAM_API_v2.md` for session-aware delimiter handling, typed numeric views and `variable_id` lookup. The v1 behavior below is retained for historical documentation.

SPDX-License-Identifier: GPL-3.0-or-later

**Introduced:** GX-TXT Pipeline v0.9.3.3  
**API version:** 1

## Purpose

Generic modules must be able to read selected CSV columns progressively instead of loading every column and row into RAM. This API is an I/O utility; it contains no plotting, reduction, resampling or scientific transformation logic.

## Public helpers

```octave
S = gxtxt_table_stream_open(path, columns, chunk_rows);
[S, chunk] = gxtxt_table_stream_next(S);
S = gxtxt_table_stream_close(S);
raw = gxtxt_table_chunk_column(chunk,'time_s');
num = gxtxt_table_chunk_numeric(chunk,'current_A');
```

`columns` is a cell array of canonical CSV headers. Empty means all columns. `chunk_rows` defaults to 5000.

The stream exposes byte progress (`bytes_read`, `total_bytes`) so a module can report progress through Progress API v1.

## Chunk contract

```text
chunk.names        selected canonical headers
chunk.values       one N×1 cell vector per selected column
chunk.nrows
chunk.first_row
chunk.last_row
chunk.eof
chunk.bytes_read
chunk.total_bytes
```

`gxtxt_table_chunk_numeric` converts selected cells with `str2double`; invalid/non-numeric cells become NaN. Scientific policy for NaN/status remains the consumer's responsibility.

## CSV rules and v1 limitation

The v1 parser supports comma-separated fields, quotes and doubled quotes on a physical line. Embedded newline characters inside a quoted CSV field are not supported by the streaming helper. Modules requiring that uncommon format must use a different validated reader rather than silently changing the data.

## Resource ownership

Always close the returned stream. The API does not copy, rewrite or register a Dataset and does not modify provenance.
