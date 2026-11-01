# Native CORE History engine (DEV111-P017)

`history_engine.cpp` is a Tcl 8.6 C++17 extension. Build with `make -C core/history`
using the server's existing compiler, Tcl headers and OpenSSL. No dependency is
fetched. Load with:

```tcl
load [file join $framework core history libgxtxt_history.so] Gxtxt_history
```

The extension provides `gxtxt_history 1.0` and `::GX::historyNative`. CORE Tcl owns
scientific hooks and GUI scheduling. The extension invokes no Viewer callback and
calls no Tcl API from a worker. All Tcl objects belong exclusively to the owning
interpreter thread; a worker receives independently owned byte strings and scalar
metadata.

## Internal service commands

These are CORE implementation commands; Viewers use the public scientific History
APIs. A record retains the existing `gxtxt.scientific_recipe.v1` data contract.

| Command | Result / purpose |
| --- | --- |
| `open OWNER RECORD PATH IDENTITY ?INITIAL_AUXILIARY?` | Opaque handle; empty PATH creates RAM-only History. Nonempty PATH requires an existing parent directory and an inert Session/Document generation identity. |
| `append HANDLE SNAPSHOT DESCRIPTION ?SEMANTIC?` | Compare the current snapshot, construct only the new top-level patch, accept it in RAM and enqueue owned bytes. |
| `appendPatch HANDLE PATCH DESCRIPTION ?SEMANTIC?` | Accept an already prepared incremental patch. The existing `@gxtxt.recipe.delete` sentinel removes a key. |
| `entry HANDLE INDEX` | Complete stored semantic step, one-based bounds, immutable Tcl object reference; no record export or accumulated serialization. |
| `auxiliary HANDLE ?DICT?` | Get / accept separately bounded presentation or lifecycle state without changing scientific steps, cursor, state or legacy record. |
| `state HANDLE ?INDEX?` | Current state by default; another index is a read-only scientific snapshot. |
| `navigate HANDLE INDEX` | Apply forward/inverse patches to the active cursor and enqueue that cursor event. |
| `branch HANDLE INDEX` | Explicitly discard the later branch while preserving the selected state. |
| `clear HANDLE SNAPSHOT` | Explicitly replace the base with current scientific state and remove retained steps. |
| `status HANDLE` | Acceptance, pending count, durable revision, failure and bounded queue information. |
| `rows HANDLE ?START? ?COUNT?` | Zero-based requested step range; rows have one-based timeline indices and small presentation metadata. |
| `summary HANDLE` | Legacy header plus presentation-only steps (`patch {}`); never scientific replay/export data. |
| `record HANDLE` | Full legacy inert record for explicit Save/export/compatibility boundaries. |
| `checkpoint HANDLE` | Queue an atomic checkpoint; worker builds it from its independent byte model. |
| `flush HANDLE ?TIMEOUT_MS?` | Explicit durability barrier (default 30 s, maximum 600 s); errors on failure/timeout. |
| `close HANDLE` | Flush up to 30 s, then drain/join/release the writer. Failure retains the handle and RAM for export/retry. |
| `recover PATH IDENTITY` | With no active writer: return `{record ... revision ... durable_revision ... torn_tail ... status recovered}`. |
| `queueLimit HANDLE BYTES` | Tune outstanding byte ceiling between 1 KiB and 32 MiB; cannot reduce below already outstanding bytes. |

Submission returns a status dictionary with `count`, `cursor`, `revision`,
`accepted_revision`, `durable_revision`, `pending`, `queued_bytes`, `queue_limit`,
`record_bytes`, `auxiliary_bytes`, `accepted`, `failed`, `status`, and `error`. `status` is `ram`,
`pending`, `durable`, or `failed`. A failed asynchronous write does not roll back
accepted RAM state. Subsequent mutating submissions reject while failed; the
caller can still inspect/export the retained state. A full queue rejects before
changing RAM state or the accepted revision. No operation is silently omitted.

An unchanged `append` creates no step/revision. Editing an older active cursor
requires explicit `branch`; browsing through `state` does not move the cursor.
`checkpoint` is a revisioned lifecycle event without an extra scientific step.
Grouping metadata (`group`, `group_id`, `group_label`) is preserved with semantic
steps. GUI grouping remains a CORE presentation decision.

## RAM costs and ownership

The engine stores the base dictionary, retained semantic steps, inverse patches,
and the active dictionary. Undo/Redo applies adjacent patches rather than
replaying the whole timeline. Append compares at most the supplied/current
snapshot, serializes the new step, and extends an amortized vector. It never
encodes, hashes or traverses the accumulated record. `appendPatch` avoids the
snapshot comparison. Native rows omit bulk patch/parameters/targets/results.

The existing complete-retention contract remains capped at 4096 steps and 8 MiB;
size accounting is incremental and conservative by a few header bytes. Exceeding
a cap is an explicit error; no automatic scientific truncation occurs.

Legacy scientific steps may lack `description` and `timestamp`. Import preserves
their exact semantic bytes and unknown fields; presentation rows alone synthesize
a description from `semantic_operation` / `operation` and timestamp `0` (unknown).
New appends always include both display fields. Imported metadata can carry the
CORE-only `legacy_import 1` marker: initial load and recovery then permit at most
4096 extra bytes for the one-time CORE owner/cursor/API envelope around an
otherwise capped scientific record. This allowance cannot be spent by an append;
new retained data still rejects above 8 MiB. A capped legacy history remains
browsable/exportable and requires explicit Clear before accepting more edits.
Only SCIENTIFIC_RECIPE_API_v1, NATIVE_2D_GEOMETRY_API_v1 and
NATIVE_3D_GEOMETRY_API_v1 semantic APIs at version 1 are admitted. If a record
supplies a format, it must be `gxtxt.scientific_recipe.v1`. Auxiliary state has its own independent 8 MiB bound. Scientific retention limits
are unchanged. Each
writer has a maximum 32 MiB / 8192-event outstanding queue, inclusive of an
in-flight batch. At most 32 engines can exist per interpreter. These are explicit
resource bounds, not a promise of constant total RSS: retained inverse values,
Tcl's immutable sharing, the active domain state, separately bounded auxiliary state and a checkpoint buffer also use
memory. Snapshot comparison/restoration scales with domain state size. Full
record export and arbitrary distant navigation are explicit O(history) boundaries.

## Persistence and recovery

The storage family is `PATH`, `PATH.checkpoint`, and `PATH.lock`. CORE constructs
PATH from a verified Session/Document owner; IDENTITY binds at least Session
identity and Document generation. An advisory exclusive lock prevents concurrent
writers; recovery takes a shared nonblocking lock and refuses a live writer.
Symlink final components and non-regular storage files are rejected.

A writer processes ordered batches of at most 64 events / approximately 1 MiB.
It acknowledges a durable revision only after `fsync` completes. Acceptance is
immediately available in RAM and does **not** assert crash durability. In a large
burst the durable worker can legitimately lag the GUI by seconds. `flush` is the
explicit boundary for Save/Close/Session transfer policy in CORE.

The worker owns a serialized metadata/base/step model. It publishes an automatic
checkpoint every 1024 events or after the incremental journal exceeds 8 MiB.
Checkpoint construction, serialization, SHA-256 and disk writes run entirely in
the worker. It writes and fsyncs a temporary checkpoint, atomically renames it,
fsyncs the directory, then atomically publishes a complete empty journal header.
A crash between those publications leaves an older suffix whose revisions are
covered by the newer checkpoint. Older events cannot overwrite newer state.
Temporary interrupted publications remain outside the active file names.

Internal binary storage version 2 begins with `GXH17\0\2\n`, a little-endian
32-bit identity length, the exact identity bytes and a SHA-256 header digest.
Each event has a little-endian 64-bit revision, 32-bit payload length, previous
32-byte payload digest, 32-byte payload digest, **separate 32-byte frame-header
digest**, then a Tcl-list event encoded in owned string bytes. The payload digest
covers revision, length, prior digest and payload. Verifying the frame-header
digest before trusting the length distinguishes a corrupted length from a torn
payload. Checkpoint frames start a fresh chain; incremental frames remain ordered
by revision. Storage data is inert and is never evaluated as Tcl code.

Current checkpoint payloads are `snapshot_bundle {record RECORD auxiliary DICT}`.
Recovery also accepts the earlier `snapshot RECORD` payload and assigns empty
auxiliary state to it. An `auxiliary DICT` event advances the same ordered revision
stream without a scientific timeline entry. Auxiliary remains separate from the
legacy record and from the base/patch state; it never changes Undo/Redo, browsing,
branching or scientific Clear. Worker-owned checkpoint bytes include both states
atomically. Complete scientific and auxiliary values may each approach 8 MiB;
the existing 32 MiB frame ceiling accommodates their bounded dictionary quoting
and envelope. The ordinary worker queue still rejects before RAM acceptance when
its logical 32 MiB ceiling would be exceeded.

Recovery verifies every complete frame and returns the longest complete prefix
when the final header or payload is incomplete. Complete-frame checksum errors,
ownership mismatch, malformed semantic data and revision gaps are explicit
errors. A valid checkpoint can survive an absent journal. Resume truncates only
the already identified incomplete final tail. Existing complete records are
never silently replaced: opening an existing storage family requires the supplied
record to match the recovered record. CORE must ask the user to recover, or
explicitly retire the whole prior storage family before opening a saved state.
Recovery fsyncs the successfully read files and directory before reporting a
recovered durable revision, including complete frames left in the OS cache by a
killed process.

## Focused evidence

Run `tclsh validation/dev111_p017/native/contract.tcl FRAMEWORK NEW_OUTPUT`.
The test deliberately uses only new isolated files and one owned child process.
It covers operation/state semantics, inverse patches, grouping, Unicode, no-op,
concurrent writer exclusion, accepted/durable separation, snapshot and suffix
recovery, header and payload corruption, torn writes, new checkpoint plus stale
suffix, missing suffix, queue rejection, asynchronous I/O failure, failed-close
RAM retention and SIGKILL recovery. Compatibility cases additionally verify an
exactly 8,388,608-byte legacy scientific record with missing display metadata,
byte-preserving recovery, bounded envelope allowance, normal append rejection at
the scientific cap, and successful new recording after explicit Clear.

The 3200-operation test retains 7,991,567 bytes. In `native-test08`, first-100
acceptance median/p95 was 18/27 µs and last-100 was 29/44 µs. Draining the pending
worker after acceptance took 2.541850 s. These measure this native engine fixture;
actual Viewer GUI acceptance, capture, scientific restoration and rendering are
separate CORE integration evidence. Earlier development evidence remains intact.

## Auxiliary presentation state and resource shutdown (native AUX09)

`auxiliary HANDLE` returns the active inert dictionary. The setter validates the
8 MiB independent cap, accepts in RAM, increments the revision and queues owned
bytes through the existing writer. Identical key/value dictionaries (including
reordered top-level keys) are no-ops. Setter results are ordinary acceptance /
durability receipts; auxiliary changes create no scientific operation or row.
Typical values are current camera/view settings, selection descriptors or pending
presentation preferences. Work on these values scales with their bounded current
size, rather than accumulated scientific History.

New-journal `open` can receive `INITIAL_AUXILIARY`. Existing-journal `open` with an
explicit initializer requires it to match recovered auxiliary bytes. Omitting the
optional argument resumes recovered auxiliary automatically; the original call
signature remains valid. `recover` always returns an additional `auxiliary`
dictionary, empty for older checkpoint data. A portable Session owner must carry
this separately recovered dictionary into the new owner's initial open or set it
through `auxiliary` before flushing. Full `record` export remains byte-compatible.

`entry HANDLE INDEX` gives CORE one retained semantic step directly. A Viewer or
CORE can retain a small `undo_auxiliary` value in the normal semantic metadata of
a scientific operation; that metadata is charged to the normal scientific record
limit. The native getter leaves auxiliary application policy to CORE hooks.

An interpreter-deletion cleanup drains and releases writers. A process exit
handler also drains open writers before Tcl unloads extension libraries, including
normal Tclsh completion and a controlled top-level Tcl error. It makes no Tcl API
calls and never invokes a Viewer callback. An asynchronous failure is reported to
stderr during exit; explicit `flush` / `close` remains the normal API boundary for
handling failed persistence while RAM is still available. SIGKILL and power loss
remain covered by the journal's last complete durable prefix.

Focused `auxiliary.tcl` evidence is in `native-aux-evidence/aux05`: 45 assertions
cover no-op / retention / caps, a legal selection descriptor beyond 64 KiB,
combined 7.8 MiB scientific + 8 MiB auxiliary checkpoint recovery, direct semantic
entry access, Undo/Redo invariance, strict/resumed opens, old snapshot compatibility,
torn/corrupt auxiliary recovery, newer checkpoint plus stale/absent suffix,
interpreter deletion, normal/error process exit and failed-I/O RAM retention.
`native-aux-evidence/contract02` passes the unchanged full earlier contract; its
3200-operation fixture retained 7,991,567 bytes, last-100 acceptance median/p95
28/45 µs, with 2.029353 s separately measured durable catch-up. Both scripts
intentionally leave one controlled failed writer and therefore print the expected
persistence-failure diagnostic when their interpreter exits.
