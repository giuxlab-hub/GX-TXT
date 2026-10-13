# Typed Binary Read Transport v1

SPDX-License-Identifier: GPL-3.0-or-later

GX-TXT 0.9.7.37 extends the existing Canonical Dataset API v2 and Table Stream
API v3 read path. It does not introduce a backend-specific consumer API or
change Dataset, variable, Graph Series or publication identity.

## Public flow

```text
Canonical Dataset API v2 range/hyperslab
  -> provider typed binary block when available
  -> Table Stream API v3 numeric_transport=auto
  -> persistent private Octave bridge BCOL record
  -> Base64 decode, typecast, endian correction, shape validation
  -> typed Octave column
```

The public Tcl operations are
`datasetAccessReadRangeBinary`,
`datasetAccessReadRangeTransport` and
`datasetAccessReadHyperslabBinary`. The additive provider capability is
`typed_binary_read`. Table Stream v3 accepts `numeric_transport=values|auto`;
the Octave Dataset and Analysis Source adapters select `auto`.

## Binary block

A block is a dictionary with marker `__gxtxt_binary_block=1`, canonical
`dtype`, `endian` (`little` or `big`), semicolon-separated `shape`,
`byte_count`, and an unwrapped RFC 4648 Base64 payload. Physical arrays use
contiguous C order. Range reads remain rank 1. Hyperslabs retain their complete
shape at the Canonical Dataset layer.

The HDF5 private worker adds `BREAD` and `BHYPER` requests and answers with
`BDATA`. The Table Stream private bridge adds `BCOL`. Existing `READ`, `HYPER`,
`DATA` and `COL` records remain supported.

## Dtypes

The binary read path accepts:

```text
float32 float64
int8 int16 int32 int64
uint8 uint16 uint32 uint64
bool
```

Octave reconstructs these as `single`, `double`, signed or unsigned integer
arrays, and `logical`. It validates the byte count and rank-1 Table Stream
shape before returning a column. Multi-byte values are swapped only when block
and host byte order differ.

## Selection and fallback

`datasetAccessReadRangeTransport` independently selects the transport for each
requested variable. It uses values when the provider lacks
`typed_binary_read`, the variable is text/string, or its dtype is unsupported.
CSV therefore keeps the existing delimiter/decimal/schema conversion path.
Existing direct Tcl Table Stream callers retain value mode unless they request
`auto`.

Uniform implicit coordinates have no physical provider payload. CORE
synthesizes only the requested range and emits it as declared `float32` or
`float64` when auto transport is active.

## Validation and diagnostics

CORE validates the marker, dtype, endian, nonnegative integer shape, element
count, byte count, Base64 alphabet and encoded length before a block reaches a
consumer. Table Stream also checks schema dtype and shared row counts.

Provider diagnostics add `binary_blocks_read`, `binary_bytes_read` and
`text_values_serialized`. Table Stream diagnostics add
`binary_columns_returned`, `binary_bytes_returned` and
`value_columns_returned`. These counters make transport selection observable
without exposing HDF5 paths or requiring a user-facing diagnostic mode.
## Large bridge records (GX-TXT 0.9.7.77)

Typed-binary payloads can exceed the operating-system pipe buffer by a large margin. The `standard_octave` readers therefore treat LF as the protocol record boundary and accumulate partial `popen2` reads before Base64 decoding. A partial `BCOL` fragment is never decoded independently. This preserves the existing RFC 4648 payload, dtype, endian, shape and byte-count contract without reducing scientific chunk sizes.

