# Table Stream API v2

For registered Dataset IDs, Analysis Sources, provider-neutral ranges, and
typed modern chunks, see [Table Stream API v3](TABLE_STREAM_API_v3.md). The v2
bare-path behavior described here remains supported.

SPDX-License-Identifier: GPL-3.0-or-later

Introduced in GX-TXT 0.9.7.3. The v1 function names and three-argument stream opening remain supported. Consumers request canonical variable names or stable `variable_id` values and do not choose delimiters, decimal conventions, or typed conversion rules.

```octave
S = gxtxt_table_stream_open(path, {'v0001','v0002'}, 5000);
[S, chunk] = gxtxt_table_stream_next(S);
raw = gxtxt_table_chunk_column(chunk, 'v0001');
numeric = gxtxt_table_chunk_numeric(chunk, 'v0001');
S = gxtxt_table_stream_close(S);
```

The CORE discovers `metadata/datasets.ini` from the canonical path, matches the full registered path, and reads schema by Dataset ID and `variable_id`. It uses `canonical_delimiter` when recorded and otherwise detects comma, semicolon or tab with the quote-aware CSV splitter. CSV quoting and the v1 limitation on embedded physical newlines remain unchanged. `chunk.values` remains unmodified source text; `gxtxt_table_chunk_numeric` returns the CORE numeric view. Ordinary numeric variables retain their declared unit semantics. `value_kind=elapsed_time` with `value_format=hms` is normalized to the public elapsed-time base representation in **seconds**. Invalid or ambiguous values return NaN. No plotting module performs HMS or decimal-comma parsing.

For `value_kind=elapsed_time`, `value_format=hms`, `00:57:00` becomes `3420` and `02:02:00` becomes `7320`, including when the compatible source schema declares `unit=h` or `unit=min`. Time origin metadata is carried by Dataset Variable Schema API v2; cross-dataset alignment is not implicit. See [Elapsed Time Contract v1](ELAPSED_TIME_CONTRACT_v1.md).

The stream and chunks report `api_version=2`. Existing name-based consumers continue to work. Bare CSV files outside a registered session use delimiter detection and strict dot-decimal numeric interpretation; explicit session schema is required for typed non-default values.

The [Variables Guide](../guides/VARIABLES_GUIDE.md) shows a complete plugin read by variable_id and explains the related unit, semantic and temporal metadata.

## Strict numeric CSV specialization

`gxtxt_table_stream_open_numeric_fast(path, columns, chunk_rows)` is an additive
public v2 entrypoint for large, unquoted, all-numeric comma or tab tables with
at most 16 physical columns. It returns the ordinary Table Stream state and
uses the ordinary `gxtxt_table_stream_next` and close operations. Requested
columns may be a subset of the physical table. A bounded-memory preflight
checks every data row for quoting, missing fields, ragged rows, unsupported
characters, and non-finite numeric values. If the table is ineligible, the
entrypoint returns the established general parser state without changing its
semantics. Eligible tables use native chunked numeric transport; neither the
preflight nor the stream retains the full table. The preflight adds sequential
I/O before the first chunk, so use this entrypoint when a large numeric table
will be consumed in full.
