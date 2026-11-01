# Publication v2 typed numeric transport

GX-TXT 0.9.7.30 changes the internal Octave-to-CORE transport for numeric Publication v2 payloads. Public Dataset Publication API v2 operations and semantics are unchanged.

## Encoding

Each numeric request contains one typed binary block with:

- kind: BINARY
- dtype: bool, signed or unsigned integer, float32, or float64
- endian: little or big
- shape: the logical source shape
- payload: one Base64 encoding of the contiguous typed bytes

String payloads retain the text representation.

## Validation

CORE validates the descriptor, Base64 syntax, decoded byte count, dtype, endian, shape, operation count, and target conversion compatibility before storage mutation. Failed validation leaves the publication transaction uncommitted.

## Storage

CSV materialization decodes the block in CORE. HDF5 operations pass the block to the private storage writer, which reconstructs a NumPy array from the byte buffer and applies the declared shape. Full write, range write, append, and hyperslab operations share the same block contract.

## Memory behavior

The transport eliminates per-element decimal strings, Tcl token lists, and repeated parsing for numeric arrays. The source array, packed bytes, and one Base64 payload are the principal request representations. Chunking remains controlled by the caller and storage provider.

## Compatibility

There is no public API change. Existing module calls to the Octave Publication v2 binding continue to use the same functions and arguments.
