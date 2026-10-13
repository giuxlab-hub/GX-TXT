# Dataset Publication API v2 standard_octave binding

GX-TXT 0.9.7.28 exposes the existing Tcl Publication v2 lifecycle to standard_octave. It is a language binding, not a new publication model. One Octave handle owns one persistent Tcl bridge and one Publication writer across all declarations and writes.

Public helpers are gxtxt_publication_v2_open, declare_dimension, declare_variable, declare_uniform, write, write_range, append, hyperslab, flush, diagnostics, finalize, and abort. Values are transferred per request with base64 framing; the request size, not the complete dataset size, bounds transport memory. HDF5 typed output goes directly to the HDF5 writer without an intermediate CSV.

The open options structure accepts `storage`, `capabilities_required`, and `capabilities_preferred`. It also accepts the standard Publication v2 provenance fields `producer_version`, `source_dataset_ids`, `source_variable_ids`, `source`, `provenance`, and `notes`. These are the existing CORE publication-definition fields; the binding does not define a second provenance model. The optional scalar boolean `replace_owned` requests replacement of an existing stable ID only when its registered Publication v2 producer is the same module and its target path is unchanged. Selection remains in CORE Storage Auto. Finalize returns the existing Publication result and closes the bridge. Abort closes it without registry publication. Calls on closed handles fail.

Example: open with storage auto and append_write, declare an extendible row dimension and variables, append bounded blocks, then finalize. For n-D output, declare dimensions, use an HDF5-compatible requirement, and write complete arrays, ranges, or hyperslabs.

## GX-TXT 0.9.7.30 numeric transport

The binding preserves all public function signatures. Numeric values are carried internally as one typed binary block with dtype, endian, and shape metadata. String values retain text transport. Callers do not construct or inspect the block.

## GX-TXT 0.9.7.61 provenance option transport

The standard Octave binding transports the existing Publication v2 provenance definition fields listed above to CORE when they are supplied to `gxtxt_publication_v2_open`. Calls that provide only the original storage/capability options remain compatible. This extension is used by Temporal Set FFT publication so each derived spectrum records the source Dataset/variables and Temporal member provenance without a module-private sidecar.

## GX-TXT 0.9.7.62 owned replacement

Set `replace_owned=true` only when recalculating a stable derived Dataset ID.
CORE rejects the request if the existing Dataset was not published through API
v2 by the same `source_module`, or if replacement would change its target path.
Finalization keeps a recoverable copy of the previous artifact until the new
file and registry entry commit. Any failure restores both the previous file and
registry state. Omitting the option preserves create-only behavior.
