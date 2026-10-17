# CORE scientific binary descriptor v2

The Tcl Numeric/Signal captured-column calls use descriptor v2 for
real and complex binary64 input. One provider invocation writes equal-length
registered real fact vectors in binary column-major order; a bounded control
response retains scalar facts and original vector shapes. CORE interprets the
scalar prototype, assigns actual quantity units and imports that exact artifact
through the existing Document resource owner. The runtime workspace is allocated,
released and cleaned by Resource Management, including error paths. Numerical
payloads do not travel in JSON, Tcl value lists or base64 between the worker and
CORE. The caller's initial typed Tcl inputs remain Tcl values at its API boundary.

The returned `transport` dictionary records input/output binary bytes,
request/response control bytes and provider invocation count. This is transport
evidence, not a statistical quantity or performance guarantee. Binary capture
preserves provider NaN payload/sign bits that the older decimal result path
normalizes; CORE still interprets these values as unavailable/undefined under the
registered scientific contract. Existing ordinary result calls remain available.

The existing Python and Octave `gxtxt_api_call` interface carries ordinary
scientific values. Scripts do not allocate or manage transport files. Public API
IDs, operations and persisted Dataset identities retain their existing names.
`gxtxt_bridge_info` reports transport version 2 and descriptor versions 1 and 2.

Descriptor v2 preserves boolean, signed/unsigned 8/16/32/64-bit integers,
float32, float64, complex64 and complex128 arrays, their shape and nonfinite
values. Complex values use interleaved real/imaginary components. Layout is
column-major, byte order little-endian, and the limit is 512 MiB per buffer.
Dimensions, dtype, element/byte counts and opaque resource identity are checked
before access. Descriptor v1 float32/float64 decoding remains supported.

The Python client, Bridge server and persistent scientific worker share the
CORE buffer implementation. Octave client and worker share the corresponding
CORE descriptor implementation. Dataset Publication retains the typed source
array when constructing its existing publication block. Canonical Dataset and
Table Stream Script bindings preserve the declared source dtype, including
exact integer values above 2^53. Numeric algorithms may explicitly adapt working
precision under their own documented scientific contracts.

Float64 arrays up to 64 elements retain the small-value transport. The Python
client, Octave client and Bridge response encoder use this same boundary;
larger arrays use the existing managed binary resources. This avoids per-element
decimal conversion for statistical tables without changing their API or schema. Other
array dtypes use typed binary resources even below this size. Logical and real
numeric scalar conventions remain compatible; array shape and scalar identity
are distinct. Strings, cells and nested structures retain their existing form.

Repeated views of the same result array are encoded once per response. In a
Table Stream chunk, `values` and a column's `values` refer to the same data.
Python may share the same ndarray between these views; use an explicit copy
when independent mutable working arrays are required. Octave uses its normal
copy-on-write value behavior. These local arrays never modify the source Dataset.
References are bounded and valid only within their own response.

Publication shape arguments accept a dimension vector or a scalar for a rank-1
variable, with nonnegative integer validation. Complex buffer support does not
itself advertise complex Dataset schema/publication support; consult the
operation's supported dtypes. Source transport, algorithm support and storage
support are separate capabilities.

This descriptor improvement is not a claim of zero-copy Dataset reads. The
managed HDF5 path now forwards provider-owned resources through Canonical
Dataset/Table Stream to Python, Octave Script Bridge and standalone Octave
consumers. Legacy HDF5 Base64 and CSV text paths remain separately available.
Resource allocation and cleanup remain under
the existing CORE Resource Management and execution lifecycle. No plugin owns
an additional Dataset reader or buffer pool.
# Scientific worker and publication resource forwarding

The existing per-execution worker receives validated descriptors for input
resources already owned by that execution. It reads them once; the Bridge
server does not load and serialize them again. Numerical output is written to
the same execution scope and forwarded to the client, which reads and releases
it. Worker-local input resources are removed after each call; the existing CORE
Resource Manager owns final execution/crash cleanup. Integral JSON dimensions
written by Octave in exponential notation are normalized exactly; fractional,
nonfinite, boolean and text dimensions are rejected.

`input_binary_bytes` counts newly written worker inputs;
`input_forwarded_bytes` counts existing payloads referenced without a server
rewrite. `output_binary_bytes` counts the worker's writes and
`output_forwarded_bytes` is the subset forwarded without a server read/rewrite.
These are overlapping counters, not additive copy counts or zero-copy claims.

Dataset Publication's HDF5 provider accepts the same managed descriptor through
its existing transactional owner. The public writer capability
`managed_binary_write` selects this route. Shapes preserve actual array order;
the internal legacy Base64 lane retains its C-order interpretation. Standalone
Octave negotiates a provider-owned Resource Manager scope and releases each
buffer after a complete write acknowledgement. Provider errors retain the
existing failed-writer/abort policy. CSV stays on its documented value path.


## Bounded solver policy/result envelopes

Small structured binary64 control state can use the existing CORE result INI
envelope without routing values through JSON floating-point conversion:
Tcl `ScientificTransportv1::writeResult path fields` accepts the existing
text/array/struct/cell/empty typed nodes plus boolean;
Octave `gxtxt_scientific_result_read_v1(path)` returns the corresponding
real binary64 vectors/matrices and nested values. Limits: 8 MiB envelope,
65,536 nodes/elements, depth 16. Shape/order and exact nested field identity
are checked. The writer refuses an existing destination and publishes atomically.
Unknown node types, duplicate INI keys, malformed numeric literals and overflow
are rejected. This interface is for bounded real control state; bulk arrays,
complex data and exact integers use managed binary v2.

Strings written by the Tcl writer use `encoding=base64_utf8`; this marker
adds exact Unicode, whitespace, literal backslashes and newlines to the existing
string node. Tcl `readResult` decodes it. Octave's existing
`gxtxt_scientific_result_write_v1(path, result, exact_strings=false)` retains its
legacy default; passing true opts into exact strings. Negative zero is written
as `-0.0`, preventing Tcl from interpreting `-0` as an integer zero.
The shared INI reader's optional `exact_keys=true` returns a Map of complete
section.key names and rejects duplicates; its default legacy struct behavior
is unchanged. No module-private parser is introduced.

The unified Bridge's bounded Tcl scalar/array argument conversion preserves
negative binary64 zero as `-0.0`. It must not pass negative zero through the
integer-token shortcut or serialize it as Tcl integer `-0`. Scalar, small text
array and typed-binary request paths are verified by real Python/Octave unit
conversion Jobs; this is a shared transport rule, independent of unit semantics.

The bounded Tcl-to-Octave provider request encodes real/imaginary array elements
and uniform-grid start/step as 16 lower-case hexadecimal binary64 words with
`number_encoding=float64_hex_be`. Shape/count integers stay ordinary JSON numbers.
The common worker decodes words with `hex2num`, rejects nonfinite/malformed words
and unknown encodings, and preserves signed zero in real arrays. Legacy requests
without `number_encoding` remain readable. This avoids a demonstrated one-ULP
Octave JSON decimal-decoder change to `96.363708192447092`; scientific plan
validation keeps exact equality. The public typed node constructors and binary
v2 bulk resources retain their identities. Captured calls still write arrays as
binary resources and use the bounded encoding for remaining control operands.

The legacy Numeric Tcl worker now writes nested results with the same CORE
typed result writer and reads them with `ScientificTransportv1::readResult`.
Flat result values and existing Numeric error codes remain compatible; bounded
observation/likelihood receipts no longer require a module-specific flat parser.

### Explicit infinite control bounds

`ScientificTransportv1::array shape real ?imaginary? ?nonfinitePolicy?` defaults
to `finite`. The explicit `allow_infinity` policy carries signed infinite control
bounds in the existing exact binary64 word encoding. It still rejects NaN and
unknown policies; the Octave decoder enforces the same policy. Scientific data
operands remain finite by default. Numeric profile/bootstrap plan adapters use
this opt-in only for original lower/upper parameter bounds. The numerical owner
still validates their dimensions, ordering and applicability. This is additive
to the existing version1 bounded transport and leaves managed array bytes intact.

## Owned Document array ingress

Tcl `::GX::ScientificTransportv1::resourceArray reference shape ?dtype?` creates
a typed input node for the existing `withCapturedColumns` provider call. The
reference is a canonical Interactive Document resource, never a caller file path.
CORE validates its live owner, SHA, byte count, optional dtype/endian metadata,
1–16 positive dimensions and the existing real-dtype width contract. The limit
is 512 MiB. The node declares a little-endian Fortran-order byte view; callers
must supply the correct shape for the resource's actual byte layout.

The existing owned reader streams at most 1 MiB per chunk into the provider's
binary-v2 workspace. Cleanup follows the captured call lifetime. No scalar Tcl
list or base64 expansion is introduced. This is shared transport, not a Fitter
format parser or a new numerical implementation. For accepted interleaved XY
geometry the byte view is 2×N; for an eight-field interleaved prediction resource
it is 8×N. Captured column-major outputs retain their own declared N×P layout.

## Large integer scalar ingress

The CORE Python-to-Octave scientific worker carries integer scalar magnitudes
above2^53 through the existing8-byte typed buffer descriptor, preserving their
exact value up to int64/uint64 limits. Values outside that representable range
are refused. Ordinary small scalar control values keep the established number
node. Typed results already use the shared binary output path. This preserves
integer identity until the receiving scientific API explicitly accepts or
rejects conversion to its numerical representation; it does not authorize an
implicit floating-point cast in a model algorithm. No wire version, Session
format, resource owner or cleanup policy changes.

## Staged Dataset array ingress

`::GX::ScientificTransportv1::stageDatasetResource resource workspace` copies a
validated live Dataset Access binary resource into an existing absolute
computation directory. It returns `descriptor` and `sha256`, preserving dtype,
Fortran layout, bytes and opaque resource ID. Shape delimiters are normalized
through the shared schema helper. An existing destination is never overwritten;
length and SHA must agree. The original Dataset lease remains caller-owned and
must be released through `datasetAccessReleaseResource` before closing its handle.
The staged copy belongs to the computation directory's existing cleanup owner.

`gxtxt_scientific_array_read_v1(workspace, descriptor)` is the public Octave
reader for that staged array. The directory must be absolute, owned by the current
process user and a real directory. The existing CORE binary decoder validates
the descriptor, file identity, dtype, shape, bounds and layout and reads the array.
This entrypoint adds no codec, Dataset reader, statistical calculation or private
module buffer pool. Source lease and staged-copy lifetimes are distinct.
