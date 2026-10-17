# MANAGED_RESOURCE_API_v1 — SB-014 boundary

This thin transport reuses the existing Interactive Document Resource writer,
reader, hash, Session and owner-generation checks. It does not create another
destination store. Python/Octave scripts address Document IDs and resource
receipts; no operation accepts a host path, callback, executable content or raw
Native pointer.

| Operation | Positional arguments | Result |
|---|---|---|
| write | document_id, metadata, bytes_base64 | immutable managed resource receipt |
| read | resource, start_byte, byte_count | bounded base64 data |
| info | resource | fully verified resource receipt |

Write decodes strict base64 with a 4 MiB bound and streams to the existing writer
in at most 1 MiB chunks. Reads use the existing 1 MiB bound and exact ranges.
Resource identity includes Document owner/generation, SHA-256, size and format
metadata. Missing/corrupt/stale-generation resources reject. Metadata contains
data; it cannot select a filesystem destination.

Canvas previews and workspace packages return these same managed receipts.
Existing larger scientific streaming services remain authoritative. Arbitrary
filesystem exporters and user-selected file dialogs remain host-only. This
cycle establishes the minimum safe managed destination policy; future detached
exporters must reuse it rather than bypass it.


### Bounded typed numeric pages (dev097)

`read_numeric(resource, start_row, count)` / Tcl `managedResourceNumericPage`
returns `gxtxt.numeric_resource_page.v1`. Supported owned formats are
`float64_interleaved_le`, `native2d.float64_xy_le_v1`, `uint64_le`, and
`native2d.uint8_break_before_v1`. Shape is checked against actual bytes and any
declared row count. Pages contain at most 65536 rows and 1 MiB, with 1–128
unique column identities. A terminal empty page is valid. Unknown formats,
out-of-range reads, corrupt bytes and expired owner generations reject.

Scripts receive a typed binary matrix `values` plus `dtype`, `columns`, `start`,
`row_count`, `total_rows`, and `source_sha256`; uint64 is never cast to double.
The host Tcl result retains little-endian row-interleaved `bytes`; the bridge
converts bounded pages to the existing typed column-major transport. This is
interpretation of declared fixed-width storage, with no numerical estimation.

### Typed durable writes (dev097)

`write_numeric(document_id, columns, values, metadata)` accepts a real typed
scalar/vector/matrix from the common Python/Octave Script Bridge (use a NumPy
array in Python). Vector shape is N-by-1; explicit row matrices retain 1-by-N
shape. Columns must be 1..128 distinct nonempty single-line IDs and match the
matrix width. Empty N=0 arrays are supported. The 512 MiB typed buffer bound is
shared with CORE binary transport. No user filesystem path is accepted.

All thirteen CORE binary dtypes are preserved: bool, signed/unsigned 8/16/32/64-bit
integers, float32/64 and complex64/128. No scientific cast, normalization or
missing-value substitution occurs. Signed zero, NaN/Inf, exact uint64 and complex
components retain their bytes. Format `gxtxt.numeric_matrix_le_v1` records dtype,
little endian, C row order, column identities and row_count. These fields are
assigned by CORE; callers cannot override them in metadata. Other descriptive
metadata belongs to the caller and does not certify statistical meaning.

For existing Native2D consumers, metadata may explicitly request
`format=native2d.float64_xy_le_v1`, requiring nonempty float64 columns exactly
`[x,y]`. CORE supplies point_count. This uses the canonical geometry loader and
resource contract; no alternative renderer or scientific identity is introduced.
The existing `native2d.uint8_break_before_v1` format is also writable with a
nonempty uint8 column exactly named `break_before`; CORE supplies point_count.
This is the original Native2D gap resource, with its existing read/restore
contract, and can be copied and packaged alongside its boundary geometry.

The writer validates the active Document generation, maps an incoming lazy binary
lease read-only, and converts at most 1 MiB of rows at a time to canonical storage.
It stages through CORE Resource Management and streams to the existing immutable
Document resource writer. Staging is released and collected through its owner;
source buffers remain with their original execution. The returned resource
receipt survives Job exit under the Document's generation. Callers must retain
the receipt in their normal Workspace payload to include it in portable packages.

`read_numeric` additionally recognizes this generic typed matrix format and
returns the original dtype in both languages, including empty terminal pages.
Existing fixed-format receipts, raw byte/base64 APIs, 65536-row and 1 MiB page
bounds remain compatible. Owner generation, hash, byte size and row shape are
checked. CORE host adapters may use `managedResourceNumericOwner document` and
`managedResourceImportNumeric document generation owned_path metadata`; these
are not arbitrary-path Script capabilities. Owner identity checks read registry
metadata without transporting the complete scientific Workspace payload.


Dev097: `copy(document_id, resource)` copies verified original bytes in 1 MiB
blocks to a new Document owner/generation, preserving metadata and SHA without
removing the original. Typed `write_numeric` also accepts canonical
`float64_interleaved_le` (float64 only) and `uint64_le` (one uint64 column only),
so existing Fitter resource identities are preserved across GUI/Script consumers.
