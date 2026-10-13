# TABULAR_TEXT_API_v1

SPDX-License-Identifier: GPL-3.0-or-later

## Status

Candidate public CORE API for ordinary scientific text tables. It parses source
records and does not assign scientific meaning, change values, or replace RAW
source preservation by Acquisition Handlers.

## Tcl interface

The API is loaded by `gxtxt_pipeline.tcl` in namespace
`::GX::TabularTextAPIv1`.

```tcl
set info [::GX::TabularTextAPIv1::inspect $path $options]
set opened [::GX::TabularTextAPIv1::open $path $options]
set handle [dict get $opened handle]
set chunk [::GX::TabularTextAPIv1::next $handle 1024 {1 3 5} {1 3}]
::GX::TabularTextAPIv1::close $handle
```

`inspect` returns delimiter, header mode, column count and source columns,
preview rows, scanned row count, optional exact row count and warnings. By
default it reads only ten data records. Set `scan_all 1` to validate the entire
file and obtain the exact count. `open` returns the same structural identity
fields plus an opaque handle. `next` returns `rows`, `count`, `eof` and the
cumulative `row_number`; `count` is a positive maximum row count, so memory is
bounded by the requested chunk. The third argument selects 1-based source
columns in their requested order. Omit it to return every column. The fourth
argument identifies selected columns for explicit real-number conversion;
without it, values remain text. Always close the handle, including after an
error.

Options are a Tcl dictionary:

| Key | Values and default |
| --- | --- |
| `delimiter` | `auto` (default), `comma`, `semicolon`, `tab`, `whitespace`, or one literal character |
| `header` | `present` (default) or `absent` |
| `header_row` | 1-based retained record to use as the header; default `1` |
| `skip_rows` | Physical lines to discard before header/data; default `0` |
| `comment_prefixes` | List of prefixes, default `{#}`; blank records are ignored |
| `encoding` | `utf-8` only; an initial UTF-8 BOM is accepted |
| `nonfinite` | `error` (default) or `allow` for requested numeric columns |
| `preview_rows` | Nonnegative number, default `10` (inspection only) |
| `scan_all` | `0` (default) or `1` (inspection only) |

CSV-style double-quoted fields and doubled embedded quotes are supported for
character delimiters. Whitespace mode treats runs of spaces or tabs as one
separator. Automatic detection accepts comma, semicolon, tab or whitespace when
unambiguous. For mixed tabs and spaces, configure the delimiter explicitly.
The decimal separator is `.`; decimal commas are not inferred.

Headerless tables receive stable 1-based source-column indices. Header text is
reported verbatim and has no scientific semantics. Rows with a changed field
count, invalid quoting, invalid requested numeric data, non-finite values under
the default policy, invalid column selections and unsupported options raise
explicit errors. The API never pads or truncates records. Files are opened
read-only, and inspection does not write sidecars or change the source.
