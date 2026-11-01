# STDERR_DIAGNOSTICS_API_v1

SPDX-License-Identifier: GPL-3.0-or-later

Trusted CORE host dispatcher: `::GX::stderrDiagnostics operation ?arguments?`.
Source `core/tcl/stderr_diagnostics_v1.tcl` from the normal framework loader.
This component does not install capture hooks, override standard streams, persist
Configuration, create a Viewer, or grant filesystem/Tk access to a Viewer worker.
The existing host owners supply those integrations and truthful producer context.

## Lifecycle and configuration

Sourcing, `info`, `status`, OFF `configure`, OFF `emit`, and OFF `subscribe` create
no helper, capture IPC, queue, writer, capture polling timer, or log directory.
Native code is loaded lazily by explicit start/read/meta/export/cleanup requests. Merely
opening a reader does not enable capture. Explicit bounded reader tasks may run
while OFF; read/meta never open files for writing. Explicit export writes an
incident artifact; explicitly confirmed cleanup removes only validated inactive
diagnostic files while OFF.

| Operation | Arguments and result |
| --- | --- |
| `info` | API/build identity, defaults, maximum raw payload, operation names; no native load |
| `status` | O(1) shared-counter snapshot; no log reads or disk writes |
| `configure` | Optional changes dictionary; returns status. OFF changes are memory only. ON changes stop the previous helper and start a new generation asynchronously. Old directories are not moved/deleted. |
| `start` | Optional changes dictionary; returns immediately with `starting`/`running` status. Requires `log_directory`. Safe to repeat with unchanged configuration. |
| `stop` | Immediately closes the producer endpoint, disables acceptance and terminates the helper without waiting for disk. Returns `stopping`/`off`; pending records are explicitly counted as interrupted loss after child reaping. |

| Configuration key | Default | Supported native range |
| --- | --- | --- |
| `log_directory` | empty; selected by host | absolute path, at most4096 UTF-8 bytes; no NUL, symlink components, or `..` traversal |
| `max_file_bytes` | 10485760 (10MiB) | 4096..1073741824 bytes |
| `max_files` | 5, **including current** | 1..100 |
| `ring_bytes` | 8388608 (8MiB) | 65536..67108864 bytes |

The normal UI exposes MiB configuration starting at1MiB. Native smaller limits
exist for private deterministic tests. Unknown configuration keys are errors.
Configuration's persistent keys are owned by the host, which translates
`diagnostics.stderr_capture_enabled`, `diagnostics.stderr_log_directory`,
`diagnostics.stderr_max_file_mib`, `diagnostics.stderr_max_files`, and
`diagnostics.stderr_ram_buffer_mib` into this API. The Runtime page presents
these ordinary preferences under **Process diagnostics**, with an editable path
and **Browse**. They are not executable-runtime entries and have no Detect/Test
buttons. Save applies the preferences through the existing Configuration owner.

The default directory is
`${XDG_STATE_HOME:-$HOME/.local/state}/gxtxt_pipeline/diagnostics/stderr`.
The host also refuses scientific Session/Dataset and framework/plugin-package
directories. Changing it does not move or delete the former directory's logs.

Exactly one collector belongs to the owning Tcl interpreter/process. A second
interpreter cannot obtain this trusted adapter; safe interpreters are rejected.
The helper obtains a nonblocking exclusive `flock` on the selected directory's
`.stderr-diagnostics.lock`. Another host cannot collect into that directory.
The final log directory must belong to the current user and have no group/world
write bits (0755 is accepted); missing directory components are created0700 only
by the ON helper, including a fresh application-state hierarchy. Each newly
created component is reopened without following links and verified private and
user-owned. Existing parent directories are never chmodded. OFF reads do not
create any component.
Every path component is opened with `openat/O_NOFOLLOW`; managed files must be
regular, user-owned, singly linked, and have no group/world write bits. Newly
created files are0600. Unrecognized content under managed log names is refused.

Managed logs are `stderr-diagnostics.current.jsonl`, then
`stderr-diagnostics.1.jsonl` through `stderr-diagnostics.N.jsonl`, where
`N=max_files-1`. Rotation and all file I/O run outside Tk. A record is never split
across files; an encoded record larger than `max_file_bytes` is dropped with
explicit counters/error text. Shrinking retention evicts complete managed files
that exceed the new file/count bounds, with `retention_evicted_*` counters.
Unrelated filenames are neither scanned nor removed.

Stop has bounded host work and intentionally does not drain slow/full disks.
The finite10ms transition callback reaps a stopping child and finishes a requested
restart. It ceases at OFF/error/running. There is no idle OFF timer. Interpreter
destruction kills its helper and delegates child reaping to a finite native
thread, without waiting for disk or calling Tcl/Tk from that thread.

## Producer records

`emit originDict bytearray` returns `{accepted 1 reason queued}` or
`{accepted 0 reason off|overload|oversize|broken_ipc}`. `accepted` means accepted
by the UNIX transport, not written/durable. Payloads are at most32768 raw bytes;
the existing producer drain must split longer chunks before calling emit and
retain its normal stream/Job behavior. `chunk_id`/`chunk_index` can identify a
producer's split event. Stream framing and GUI/error-policy ownership remain
with that producer; this component never merges independent streams or claims
causal order.

The fixed string origin fields are `source`, `component`, `module_id`,
`viewer_id`, `job_id`, `api_id`, `operation`, `process_id`, `stream`, `severity`,
`chunk_id`, and `chunk_index`. Each absent field is the explicit string
`unknown`; each field is at most512 UTF-8 bytes, and the total is at most2048.
The trusted host supplies actual known identities. In particular, child stderr
must use the child's actual `process_id`; missing origin is never inferred from
the active Viewer/Module. The adapter's `pid` and `capture_pid` both mean the
**host capture process**, not the original child process.

The producer performs bounded serialization and one `MSG_DONTWAIT|MSG_NOSIGNAL`
UNIX datagram send. It never waits for a GUI, helper acknowledgement, RAM space,
file lock, writer, disk flush, or queue retry. The helper admits to a fixed byte
ring with drop-on-overload. Its ring mutex covers only bounded memory copies;
the disk writer never holds it during file I/O. Additional transport/socket,
one-record receive/write buffers and metadata are bounded separately from the
configured ring allocation. No per-Job queues, registries, or scientific Jobs
are created.

The JSONL wire/disk record is:

```json
{"schema":"gxtxt.stderr_record.v1","generation":123,"sequence":1,"record_id":"123:1","timestamp_us":1234567,"pid":42,"capture_pid":42,"origin":{"source":"job.stderr","component":"unknown","module_id":"example.module","viewer_id":"unknown","job_id":"job-7","api_id":"unknown","operation":"process.stderr","process_id":"99","stream":"stderr","severity":"error","chunk_id":"unknown","chunk_index":"unknown"},"payload_bytes":3,"payload_base64":"YQr/","record_crc32":12345}
```

The checksum above is illustrative. Actual `record_crc32` is IEEE CRC32 over all
serialized bytes preceding the final `,"record_crc32":...}` suffix. Readers
validate schema, canonical checksum suffix, stable identity and decoded payload
length before exposing a record. CRC32 detects accidental corruption; it is not
an authentication mechanism. Raw bytes, NUL, invalid UTF-8 and embedded multiline
content survive exactly via base64. JSON metadata is UTF-8. `timestamp_us` is
host capture wall time in microseconds since Unix epoch. `generation` is a
positive63-bit system-random collection identity; `sequence` starts1 and records
helper arrival order. Sequence gaps expose helper-admission drops. Stable
`record_id` is a string; never convert it through floating-point GUI/JSON values.

Completed file writes increment `written_*`; they do not promise `fsync` crash
durability. A failed partial write attempts to truncate back to the previous
complete record and stops capture with an error. After process interruption an
incomplete final current-file record is recovered only within the bounded record
size, with exact `recovered_tail_bytes` and visible `last_error`. Archived partial
records, foreign content, or unbounded corrupt tails are refused. Reader
checksum/format errors are explicit failures rather than skipped records.

## Bounded asynchronous retained access

`read ?cursor? ?maxRecords? ?maxBytes?`, `meta`, and
`export selectionDict destinationPath` return an opaque request token immediately.
One compact native I/O task may be active; additional submissions return busy.
At most16 unconsumed terminal requests are retained. Workers never call Tcl/Tk,
execute scripts, receive arbitrary read paths, load whole files, or use an
Analysis Engine. Cancellation is checked at bounded record/write boundaries.
A slow individual kernel I/O operation can delay its worker, never Tk.

`request token` returns one of:

```tcl
state pending token TOKEN
state done token TOKEN result RESULT_DICT
state error token TOKEN error_code CODE message TEXT
state cancelled token TOKEN
```

A terminal request is consumed by this call. `cancel token` requests
cancellation; keep requesting until its terminal result is consumed. A host may
schedule finite polling only for these explicitly pending tasks; idle capture
polling while OFF is prohibited.

Read defaults are100 records/262144 serialized bytes; supported bounds are
1..256 records and1..1048576 bytes. The result has `schema gxtxt.stderr_read.v1`,
`records`, `record_count`, `cursor`, `eof`, `bytes`, and `files`. A record dictionary
contains `schema`, `record_id`, `generation`, `sequence`, `timestamp_us`, `pid`,
`capture_pid`, `origin` dictionary, exact `payload` bytearray, `payload_bytes`, and
`raw_json`. `bytes` counts serialized JSON bytes including line endings. Read
pages never exceed either budget. `READ_BUDGET_TOO_SMALL` means the next complete
record cannot fit; its message gives the required bytes. A missing log directory
is an empty read/meta result and is not created.

An empty initial cursor selects the oldest retained record. Returned cursors
contain only numeric directory/file identity, first-record incarnation and byte
offset; callers must treat them as opaque strings. The incarnation prevents
inode reuse from making a stale cursor point at unrelated records. Evicted,
truncated or changed-directory cursors return `CURSOR_EXPIRED`. The host may show
an explicit retention gap and restart from an empty cursor. Open descriptors pin
a bounded file snapshot across rotation. The current trailing incomplete record
is not exposed. `eof` means the end of that snapshot, not permanent stream EOF;
the cursor can be used again after more records arrive.

`meta` returns the same result envelope with at most`max_files` entries in
`files`. Each contains `name`, `device`, `inode`, `bytes`, and `modified_unix_s`.
It performs no record-content scan beyond a bounded file identity prefix.

Export selection is either `{record_ids {GEN:SEQ ...}}` or a bounded interval
`{cursor CURSOR limit N max_bytes B}`. Defaults/caps are4096 records/8388608 bytes.
Explicit stable IDs must all remain available and fit the requested budgets;
otherwise `SELECTION_EXPIRED` is returned without publishing an artifact.
Unmatched retained records are scanned with bounded memory, off Tk. Interval
export includes the requested next page and returns its continuation cursor.
The artifact preserves the selected original JSONL bytes, base64 and origin.

Only the trusted CORE host obtains `destinationPath` (for example from its Save
dialog); a Viewer receives no arbitrary path argument or reader capability.
The absolute destination's parent must pass the same ownership/no-write-bits/
no-symlink validation. Existing destinations and managed log/lock basenames are
refused; choose a fresh filename. Publication uses a private0600 temporary,
bounded writes, `fsync`, and atomic non-replacing `linkat` publication followed by
temporary cleanup. No automatic incident archives are produced. Terminal export
results contain `path`, `record_count`, `bytes`, `cursor`, and `eof`; `records` is
empty. A process killed during export may leave its visibly named private
`.gxtxt-diagnostics-export-*.tmp` artifact; no unmanaged cleanup scan runs.

## Status, counters, subscriptions

Status has `schema gxtxt.stderr_status.v1`, `state off|starting|running|stopping|error`,
`enabled`, `helper_pid`, `generation`, `capture_ipc`, `writer`, `config`,
`log_directory`, `last_error`, `subscription_errors`, `pending_records`, and
`pending_bytes`. `enabled=1` only when helper acceptance is ready. An emission
during startup returns `off`; the host must preserve its ordinary stderr path.
`last_error` preserves actual startup/permission/IPC/disk/crash or recovery text.
An explicit stop returns the state to OFF while retaining diagnostic history.

Lifetime counters are available both as flat fields and under `counters`:

- `accepted_records/bytes`: producer datagrams successfully sent; bytes are raw payload bytes.
- `transport_dropped_records/bytes`: saturation, oversize, or broken transport.
- `received_records/bytes`: helper datagrams received and validated.
- `ring_dropped_records/bytes`: bounded-ring or configured-file admission loss.
- `disk_dropped_records/bytes`: the record whose write failed.
- `written_records/bytes`: complete writes; bytes are raw payload bytes.
- `interrupted_records/bytes`: accepted records not written or already counted
  as ring/disk loss when a helper stops/crashes; computed after child reaping.
- `dropped_records/bytes`: aggregate transport+ring+disk+interrupted loss.
- `queue_records/bytes`: current ring gauges (encoded bytes plus frame overhead), zero OFF.
- `queue_high_water_bytes`: largest observed ring occupancy across generations.
- `recovered_tail_bytes`: explicitly repaired incomplete final bytes.
- `retention_evicted_files/bytes`: whole files removed by configured retention.

`generation_counters` contains active-helper counters, zero with no helper.
`pending_*` includes accepted IPC/ring/in-flight records not yet written/dropped;
queue gauges describe only the actual ring. Shared snapshots are individually
atomic and may transiently differ during concurrent progress; they are not a
cross-counter transaction. Disk-error shutdown accounts remaining queue/IPC
records as interrupted, avoiding double-counting the failed record.

`subscribe callbackPrefix` returns a token; at most16 subscriptions. While ON,
status notifications coalesce at100ms and invoke `callbackPrefix statusDict` on
the owning Tcl thread. Callbacks do not carry a second unbounded record stream;
the Viewer reads pages through the same bounded reader. OFF subscriptions create
no timer. `unsubscribe token` removes a subscription. A stop delivers one final
status notice; callback errors increment `subscription_errors` without recursive
diagnostics or stderr replacement. Once helper failure is observed, recurring
notifications stop. Viewer/session owners unsubscribe and cancel their own
requests on close.

## Build, delivery, validation

Linux x86_64/Tcl8.6, C++17, libc/libstdc++/pthread and Tcl only. No JSON library,
new scheduler, worker Tk grant, scientific store, or Analysis Engine dependency.

```sh
cmake -S core/diagnostics -B BUILD -DCMAKE_BUILD_TYPE=Release
cmake --build BUILD -j2
cmake --install BUILD --prefix FRAMEWORK
```

Delivered matching artifacts are `core/diagnostics/bin/gxdiagnostics.so` and
`core/diagnostics/bin/gxtxt-diagnostics-helper`. The adapter locates only the
sibling helper, passes private inherited UNIX/status handles and closes other
inherited nonstandard descriptors. Normal startup never invokes a compiler.

`core/diagnostics/tests/smoke.tcl FRAMEWORK` checks default OFF, exact binary
roundtrip, metadata attribution, stable-ID export, configured rotation, bounded
OFF reads, cursor eviction, directory changes and crash/restart. Private fault
builds require explicit `-DGXDIAG_PRIVATE_FIXTURES=ON`; never package those bins.
`tests/faults.tcl FRAMEWORK FIXTURE_SO` tests transport saturation by stopping its
own helper, ring pressure/slow disk, shutdown loss, synthetic ENOSPC, broken IPC,
unsafe permissions, symlink refusal and incomplete-tail recovery. Fixture-only
environment controls are compiled out of delivered binaries. All fixtures and
builds remain below their assigned scratch root; see its `SCRIPT_CATALOG.md`.

`tests/concurrency.tcl FRAMEWORK` checks400 consecutively ordered records through
live rotation while Tcl event-loop heartbeats continue, independent-host lock
contention,10 immediate stop/start cycles, active directory reconfiguration and
idle OFF subscriptions. Rapid start during a pending stop queues its restart;
correcting configuration while capture remains requested retries a failed helper.

## External managed producer attachment

The trusted CORE launch owner calls
`::GX::StderrDiagnostics::producerDescriptor`, obtaining `descriptor`, `library`,
`generation`, and `max_payload_bytes`. This procedure is deliberately absent
from the public dispatcher, status, and the finite Viewer operation list. OFF
queries return an empty descriptor and generation0 without loading native code.
Only pass a nonempty capability to the existing managed Job/native worker owner;
never expose it to Viewer code as a new filesystem or Tcl capability.

The host can pass `GXTXT_STDERR_DIAGNOSTICS_DESCRIPTOR` and the validated installed
library path to its next managed worker launch. Clear them OFF. Existing managed
context-update ownership may refresh a worker's descriptor between generations.
The worker caches one attachment, emits each already-drained raw chunk once,
and closes the attachment on OFF/broken/stale context. Diagnostic failure must
not interrupt its normal stderr drain, scientific Job outcome, or standard streams.
No diagnostic helper, queue, writer, or polling loop belongs to that worker.

`core/diagnostics/gxtxt_diagnostics_producer_v1.h` declares exported C symbols in
`gxdiagnostics.so`; they require no Tcl initialization or Tcl/Tk calls:

```c
int gxdiag_producer_attach_v1(const char *descriptor,
    gxdiag_producer_v1 **out, char *error, size_t error_capacity);
int gxdiag_producer_emit_v1(gxdiag_producer_v1 *producer,
    const gxdiag_origin_v1 *origin, const void *payload, size_t payload_bytes);
void gxdiag_producer_close_v1(gxdiag_producer_v1 *producer);
```

`gxdiag_origin_v1` has twelve `const char*` fields in this exact order: `source`,
`component`, `module_id`, `viewer_id`, `job_id`, `api_id`, `operation`, `process_id`,
`stream`, `severity`, `chunk_id`, `chunk_index`. NULL fields become `unknown`;
provided strings are UTF-8 with the same512/2048-byte limits. The owner serializes
calls for its handle. Attach returns0 ready,1 stale/OFF, or5 invalid/system failure
with optional bounded error text; its output handle is NULL on failure. Emit
returns0 queued,1 OFF,2 overload,3 oversize,4 broken IPC, or5 invalid argument.
It never retries or waits for transport/ring/disk capacity. Invalid API arguments
are errors, not accepted records. Failed attachment cannot truthfully increment
an inaccessible global page; its caller receives the explicit result/error.
Native emit exceptions are contained inside the emission guard, return5,
increment global transport loss plus the diagnostic subset
`producer_failed_records/bytes`, and preserve bounded error text. Python binding
argument/buffer failures return5 with local `python_failures`/`last_error`;
they cannot be claimed as native/global events that never entered the ABI.

The fixed-format capability is
`gxdiag1:gxtxt.diag.UID.GENERATION:/gxtxt-diag-UID.GENERATION:GENERATION`.
It grants only one abstract nonblocking UNIX datagram endpoint and a newly
created random-generation0600 POSIX shared status/counter page. Attachment rejects
arbitrary names/paths, wrong UID, unsafe type/ownership/link/mode/size, and ABI or
generation mismatch. The helper enables `SO_PASSCRED`, validates the actual sender
UID and PID against `capture_pid`/`pid`, and rejects malformed/forged packets with
`ipc_rejected_records`/`ipc_rejected_wire_bytes`; these protocol-invalid datagrams
are not accepted producer records and do not alter payload-loss counters.
All legitimate producer successful-send/overload/oversize/broken-IPC counts update
the same global atomic page used by the host, so stderr origins share rotation,
arrival sequence, admission budget, writer and status.

The descriptor is published only once the helper is running. Stop first marks
the shared generation OFF, unlinks its status name and removes the helper's
abstract receive endpoint. Existing mapped handles immediately observe OFF;
new stale attachments fail precisely. A stale external socket is inert and its
owner closes it. The helper uses `PR_SET_PDEATHSIG(SIGTERM)` plus a parent-PID
race check; GUI death marks existing handles OFF, unlinks its status name and
terminates the helper without waiting for its writer. There is no orphan capture
service or persistent pathname socket.

A bounded emission guard handles a producer call concurrent with stop. If such
a call has not finished, only its tiny **unnamed counter/status page** is retained
for truthful final counter snapshots; its ring, writer and receive endpoint are
gone. `producer_inflight` and `retired_status_pages` expose this state. Completed
calls release pages on the next explicit status/lifecycle operation without an
OFF timer. A process killed inside the guard can leave its page retained; at
most64 pages are allowed, then a precise restart-owner error prevents growth.
`producer_attachments` counts successful external attachments, not currently
live producers. No queue/buffer for capture is retained by this mechanism.

`core/diagnostics/producer_v1.py` is the production CORE binding with exact `ctypes` structure,
function declarations, binary-safe buffer ownership and result handling. It loads only its matching sibling `bin/gxdiagnostics.so`, refusing arbitrary paths and symlink assets; there is no library environment override. Its
`Producer(library, descriptor)` performs one attachment; `emit(rawBytes,
process_id=actualChildPid, ...)` sends one chunk; `close()` releases it. The real
managed-worker hook and per-request context/environment propagation remain with
their existing CORE owners.

`tests/producers.tcl FRAMEWORK` loads the C ABI from a separate Python process,
captures an actual child stderr with exact binary bytes/unchanged stdout and real
child/capture PID separation, verifies globally shared counters, saturates2000
emissions, rejects forged capture credentials, closes stale generations, and
kills only its private temporary host to verify helper/shm parent-death cleanup.


## Normal framework capture integration

The normal bootstrap loads the API; GUI startup alone applies the persistent
Configuration preference. Headless public requests inherit a capability, never
start a second helper. The existing managed Job worker duplicates only its
already separate stderr, after retaining mandatory streams. A durable supervisor
takes each launch's current capability instead of reusing stale inherited state.
Existing auxiliary requests are covered only when their owner has a genuine
separate stderr channel; merged streams are not reinterpreted.

The trusted Development runtime attaches its native producer before applying its
unchanged project-write Landlock grant. The author DLL and optional drain thread
are started after that grant. This is necessary because attachment maps the
collector's shared status page with O_RDWR, outside the author's project tree.
No extra author filesystem access or grant waiver is introduced. The native
worker's original output log still receives stderr. Capture OFF restores fd2 and
retires the optional route; an initially OFF worker creates neither that pipe
nor reader thread. Global stop disables accepted writes immediately.

The GUI observer attaches through `interp bgerror {}` and delegates genuine
callback failures to the original handler with its original options. Disable
restores that handler. API/module identity is unknown unless genuinely supplied;
traceback text does not establish provenance. There is no broad event tracing.

See [bounded Builder/Development consultation](VIEWER_GUI_P020_ADDITIONS.md).
Opening or closing that Viewer does not change capture. No private descriptor,
raw file handle or arbitrary path reader is granted to its C++ code.

## Explicit inactive diagnostic cleanup

The trusted host uses `cleanup_preview` to obtain an asynchronous request token.
It scans only the existing owner's 100 canonical managed diagnostic filenames,
using the same contained directory, regular-file ownership/link/mode checks,
record schema/CRC/payload validation and exclusive writer lock as capture and
rotation. A file may contain at most 1 GiB. Unrecognized or incomplete content,
linked paths, another writer or a busy snapshot refuse the operation. Other
filenames, scientific Job logs, publication evidence and Workspace History are
never enumerated or removed by this operation.

The normal `request token` envelope returns `files`, each with its managed name,
byte count and opaque `guard`, plus validated record/byte totals. The guard binds
directory/file device and inode, size and nanosecond modification/change times.
It is a concurrency preimage, not a cryptographic authentication token. Show
the complete preview and obtain explicit confirmation before invoking
`cleanup guardList`. The complete current managed set must still match exactly.
Capture must be stopped explicitly by its existing owner; cleanup never stops
it automatically. Preview does not create a missing directory or owner lock.

Cleanup is also an asynchronous request. It validates all selected files before
the first removal and rechecks identity before each unlink. Successful file
receipts include `removed=1`; a failure after some removals includes
`removed_files` in its error envelope. Previously removed files are not claimed
to have been restored. Directory changes are flushed after removal. Cancellation
is accepted before the mutation boundary; `cancel` returns zero once removal
has started, and the host must consume the actual done/error receipt. Memory is
bounded to one record plus at most 100 file descriptors/metadata records; slow
I/O remains outside Tk. The GUI cancels a pending scan after its explicit time
budget and reports the resulting outcome.

Configuration → Framework Maintenance → Logs & Diagnostics exposes bounded
read/filter/export and this separate preview/confirm flow. Filtering applies to
the displayed page; it does not claim an unbounded search of retained records.
