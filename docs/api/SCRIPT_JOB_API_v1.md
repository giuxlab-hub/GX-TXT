# CORE Script Job API v1

Auxiliary GUI requests use the existing nonblocking
`scriptJobAsync command payload callback ?options?` transport. Options are
timeout_ms, max_bytes, process_group, ui_lifetime, label and optional duplex;
duplex defaults to0, and old callers keep
their existing defaults. `scriptJobRequestCancel request ?reason?` cancels only
the transport-owned child/group, escalates TERM to KILL after 500 ms and delivers
one terminal response. Workers opting into process_group must establish their
own group before spawning descendants. Output is read in bounded chunks.
UI-lifetime requests are killed on application shutdown; durable scientific
Jobs retain the independent supervisor lifecycle described below.

Cancellation retains the owned group identity through escalation even if its
leader closes stdout early, preventing detached descendants from surviving.
Responses distinguish timeout, cancelled, closed, output_limit, read_error and
write_error. Transport errors cancel only the existing tracked request through
the same TERM/KILL owner; read failures also retire the failed channel after
escalation, without requiring another readable event. This
transport does not add a scientific scheduler or make a GUI request a durable Job.

With `duplex=1`, the existing pipe retains its write side for a managed compiled
Viewer lifetime. The owner buffers newline-delimited reply messages; its parsed
queue holds at most16 messages, and `max_bytes` bounds each complete line and the
unfinished line. A full queue pauses its owned readable event until its one
consumer frees capacity, instead of cancelling a valid burst. Complete staged
frames retain exact FIFO order, including empty frames. They are accounted for
separately from the unfinished line; their aggregate is not a single frame.
The compiled Viewer caller uses base64-encoded Tcl envelopes;
this encoding is its protocol, not a new general Script API.

Host-only `::GX::scriptJobRequestExchange request payload ?timeout_ms=12000?`
requires an active duplex request and a timeout from1 through120000ms. A nonempty
payload is written with a newline; an empty payload only receives, as used for
the initial worker-ready response. It returns one buffered line or errors on
cancelled/ended/timed-out transport. It polls only that managed pipe and does not
enter a Tk event loop; the existing caller applies its short local UI plan before
returning to queued native input. Durable scientific Job waits keep their
independent event-responsive supervisor behavior described below.

Normal duplex EOF also requests existing TERM/KILL group cancellation and retains
the request identity through escalation, so a fork descendant that redirected
stdout remains owned after its native leader exits. Viewer close cancels its
duplex request; application shutdown uses the same UI-lifetime group owner.

For nonblocking host consumers, `scriptJobRequestSend request payload` queues one
inert UTF-8 frame on that same duplex pipe. The request must exist, be duplex and
not be cancelled. NUL, CR and LF inside the payload are refused before writing;
exactly one LF is appended. An empty payload sends an actual empty frame, unlike
Exchange's receive-only empty argument. Admission counts the byte length of
`encoding convertto utf-8 $payload`, plus one LF and the channel's existing
`chan pending output`, against65536 bytes. This uses Tcl's actual UTF-8 channel
encoding, including its supplementary-character representation. Oversized or
busy admission errors before puts/flush with `{GXTXT SCRIPT_JOB BUSY}`, leaving
the request and queued output unchanged. Accepted means queued, not delivered or
executed: the result is `{request_id ID accepted 1 payload_bytes N}`, where N
excludes the appended LF. Send never waits, spins or enters an event loop. A
channel/write/flush failure cancels the same tracked request with `write_error`
and raises `{GXTXT SCRIPT_JOB WRITE_FAILED}`; a possibly partial frame is never
retried. Inactive/nonduplex/cancelled requests raise `{GXTXT SCRIPT_JOB INACTIVE}`;
invalid payload framing raises `{GXTXT SCRIPT_JOB FRAME}`.

`scriptJobRequestDrain request ?maximum=16?` validates an integer from1 through16
(`{GXTXT SCRIPT_JOB MAXIMUM}` on refusal), frees existing FIFO capacity, performs
at most one existing nonblocking readable service, and returns
`{request_id ID active BOOLEAN cancelled REASON messages LIST}`. Unknown or ended
requests return active0 and no messages. An existing nonduplex request is refused
with `{GXTXT SCRIPT_JOB INACTIVE}`. A surviving cancelled request returns its
reason and no messages. An active uncancelled request returns at most maximum
frames in FIFO order, preserving residual order. Empty frames remain empty list
elements. No response means an empty messages list; Drain does not wait or change
the request timeout. It rereads the actual owner state after readable/terminal
callbacks and never recreates a retired request.

Send/Drain are trusted host auxiliary operations, with no Script/SDK grant or
durable Job identity. One logical consumer owns a duplex reply stream: never mix
Exchange and Drain as competing readers. Consumers correlate their own request
IDs and source generations. Queue capacity remains16; a larger valid burst is
backpressured rather than dropped or cancelled. Readable handles staged complete
frames before another channel read. A service appends at most the existing65536
Tcl-character read to an unfinished prefix. For `max_bytes=N>0`, parked staging
has at most `N+65536` Tcl characters, with each complete frame and the actual
unfinished tail independently bounded by N Tcl bytes. This character bound is
not a65536-byte UTF-8 promise. The existing `max_bytes=0` option still leaves a
prefix unlimited; no stronger global memory bound is claimed for that option.
True overlong frames/tails still cancel with `output_limit`.

Drain releases buffered capacity before its one service and fills its bounded
result in FIFO order. Exchange also rearms after its one-frame consumption.
Both recheck the surviving owner; cancelled or terminal state supersedes any
held frames. No extra timer, event-loop pump or competing consumer is introduced.
While capacity is paused, further EOF observation may wait for consumption or
cancellation; no final-frame replay guarantee is added. Cancel rearms paused
discard-reading. Duplex UI shutdown retains immediate KILL and enters ordinary Cancel
with reason `closed` unless a first reason already exists, so a full rearmed
queue discards instead of pausing again. Normal EOF and500ms escalation retire
the same owned request. EOF can still terminalize before queued final frames are
consumed; first cancellation reason and the one terminal callback remain
authoritative. Existing timeout, UI lifetime and group escalation ownership
remain with ScriptJob; nonduplex UI shutdown retains its prior KILL/EOF behavior
and durable scientific Jobs are unaffected.

SPDX-License-Identifier: GPL-3.0-or-later

Registered Python and GNU Octave scripts launched from Run or Analysis execute
under one local durable supervisor. Tk owns neither calculations nor process
lifetime. Closing the GUI detaches it; Script Jobs reconnects on the next launch.
The legacy host `scriptExecutionRun` runs synchronously and records a Session
execution directly, without creating a durable Supervisor Job. Use `scriptJobSubmit`
when Supervisor admission, cancellation and Jobs-history visibility are required. GUI surfaces use `scriptJobSubmit` and fileevent callbacks.

## Host operations

### Owned child waits

`::GX::scriptJobWait id ?timeoutSeconds=60? ?cancelCommand?` waits through the
existing CORE supervisor while keeping host events responsive. The optional
host-only cancellation command is a trusted command prefix returning a boolean.
Python/Octave use `SCRIPT_EXECUTION_API_v1.job_submit` and `job_wait` through the
common Script façade. The returned state is the actual terminal Job state;
`wait_cancel_requested` records whether this wait requested cancellation.

A supervised submission records `parent_job_id` only after the supervisor proves
the caller belongs to that live parent's kernel process tree and start identity.
The public `describe` result exposes `waiting_for_job` while a wait lease exists.
A parent may yield its execution slot only to its own same-Session child. The
configured worker limit and canonical Job states remain unchanged. Waiting
parents retain memory reservations; their execution/thread slots are available
to their child, which takes priority over unrelated queued roots. At most eight
active nested waits are allowed. A still-active child cannot have its wait lease
released through the normal completion path.

Timeouts and requested cancellation drain the child. Failure, interruption or
cancellation of a parent cancels owned descendants; successful asynchronous
parent completion preserves its children. The supervisor retires stale caller
leases using process start identities. The journal adds a separate `job_waits`
table and an optional parent identity for new nested Jobs; historical records,
states, output reservations and scientific results retain their existing meaning.
Independent root submissions retain their established deduplication identity;
new nested submissions include their parent to prevent cross-parent aliasing.

The Fitter uses this owner for registered manual evaluation, so a public Script
client does not deadlock behind its own queued callable under a one-worker policy.

- `scriptJobSubmit reference parameters ?options? ?callback?` snapshots source,
  resolves effective typed defaults, captures the canonical Session and queues a
  job. With callback, preparation and submission run outside Tk and the callback
  receives `{ok 1 result JOB}` or `{ok 0 error MESSAGE}`. Without callback, only
  preparation/admission blocks; numerical work is independent.
- `scriptJobList`, `scriptJobDescribe id`, `scriptJobCancel id`, and
  `scriptJobRecover` inspect, request cancellation, or reconnect/reconcile.
- `scriptJobCall configure key=value ...` changes durable global resource policy.
  `scriptJobAsync [scriptJobCommand OP ...] {} CALLBACK` is the nonblocking host
  adapter used by Jobs. These lifecycle operations are host-owned, not arbitrary
  process-execution capabilities exposed to scripts.

Options include `session`, `namespace`, `inputs`, `output`, `runtime_template`,
and the existing Analysis `module_output` projection. Each input maps a unique
identifier alias to `{dataset_id ID label LABEL}`. Resolution uses only canonical
Datasets in the exact selected current namespace; descendants and unrelated
namespaces are excluded. The namespace comes from the existing Namespace API.
Current namespace changes do not retarget a job. Dataset revision tokens are
captured at admission and checked before Bridge calls; a mutable input change
fails explicitly instead of silently changing scientific inputs. Input payloads
are read through existing Dataset/Table Stream APIs without full-file copies.

The Run dialog has an optional collapsed bindings section. A semantic alias is
scientific identity; its display label is presentation. `gxtxt_context()` exposes
`inputs` and optional `output`. Output declaration fields are `dataset_id`,
`label`, `replace_owned`. A compatible script explicitly reads this declaration
and passes the desired ID/label/authorization through normal Publication APIs.
Existing hard-coded scripts keep their declared IDs. Blank output does not
rewrite source. Create-only is default, replacement requires existing ownership,
and an active job reserves its declared output ID within its original Session.
Only committed publication receipts populate the durable published Dataset list.

## Identity, concurrency and persistence

A SQLite WAL journal under the account's private configuration directory stores
job state. Admission is a single transaction with a partial unique index over
active signatures. Signature includes canonical Session, qualified script ID,
verified source hash, normalized effective parameters, semantic input aliases and
revisions, and scientific runtime settings. Visual labels/output requests do not
cause duplicate computation. An equivalent active submission returns the original
job with its assigned output. Terminal jobs may be deliberately rerun.

States are QUEUED, PREPARING, RUNNING, FINALIZING, COMPLETED, FAILED, CANCELLED,
and INTERRUPTED. Cancellation is a request until descendants stop and Publication
recovery completes. Logs, immutable source/runtime, timestamps, errors, resource
policy and actual published IDs remain in the origin Session's existing
`analysis/scripts/RUN_ID` directory. Switching GUI Session never changes it.
Configuration → Cache & Temporary Storage → Script Jobs is always available.

The supervisor is detached and account-local, with protected filesystem IPC and
no network listener. A kernel lock ensures a single scheduler for its state
root. Queued jobs survive restart; uncertain active work becomes INTERRUPTED,
never implicitly reruns. Publication owns recovery of its Dataset journal.
A launch handshake prevents execution before its child identity is durable.

Registered scientific providers use [Scientific Execution](SCIENTIFIC_EXECUTION_API_v1.md) over this same supervisor and journal; they do not create a separate scheduler.

CPU/thread admission observes effective CPU affinity and mounted cgroup quotas.
CPU/thread, process-count, memory, temporary storage, timeout, queue and concurrent
job policy are visible in Jobs. CPU/memory reservation constrains admission;
resource measurements are sampled and are not kernel cgroup quotas. Nested
Parallel Execution receives the supervised thread budget. Backend thread
variables prevent default jobs × workers × BLAS oversubscription.

## Deferred Windows contract

The future Windows implementation must execute locally with the same CORE API,
independent of Tk. It must expose a notification-area/system-tray icon while the
supervisor is active, with reopen/focus GUI, inspect jobs, cancel selected,
confirm cancel-all, and safe supervisor exit. Native Job Objects should manage
process trees; no mandatory Windows service and no remote Linux dispatch.
Logout/shutdown need not preserve live processes, but restart must reconcile
durable interrupted state. Relevant CORE process/lifecycle sources contain this
contract. The Debian release does not implement or test a Windows adapter/tray.

## Read-only identity and log inspection

The existing host API additively supports `inspect id`, `log_read id offset count
?tail?`, `inspect_run session runId`, `run_log_read session runId offset count
?tail?`, and `run_summaries session`. Tcl convenience wrappers are
`scriptJobInspect`, `scriptJobLogRead`, `scriptExecutionInspectRun` and
`scriptExecutionRunSummaries`; nonblocking GUI clients use `scriptJobAsync`.
Read projection never replaces the journal or current Registry identity.
Inspection uses the original execution identity and bounded owned run files.
Submitted records add script ID/version/Session name; legacy omissions are filled
only from immutable runtime metadata. `launched_at` captures worker spawn;
existing `started` retains its preparation meaning. Never-launched exit code is N/A.
Complete log access is bounded/paged; missing, expired or unsafe sources diagnose
that exact execution. No arbitrary file-read operation is exposed to scripts.

## Reversible history and user-local Runner Workspaces

The existing Job API supports host-only view operations. `scriptJobViewList view ?offset?`
returns `jobs`, `total_stored`, `total_scoped`, `hidden_scoped`, `matching`, `offset`,
`limit` and view-independent `lifecycle` updates. Pages contain at most 500 records;
counts cover all matching stored Jobs. Existing `scriptJobList` keeps its 100-recent
record contract. The GUI uses nonblocking `view_list` over the existing stdin/Tcl
protocol and rejects outdated responses after view/history changes. Lifecycle
observation remains independent of filters so Dataset refresh is not lost.

`scriptJobViewDefault` and `scriptJobViewValidate` describe the bounded layout:
Session `scope` (absolute path or `all`), `filter` (All/Active/Finished/Failed/Hidden),
`show_hidden`, sort/order, visible columns/widths, geometry, pane/scroll fractions
and optional selected Job ID. A Session filter reads the Job journal; it neither
opens nor accesses the selected Session's files. Stale selection is discarded.

`scriptJobHistoryHide ids` validates every exact immutable Job ID against the
Supervisor before committing a single preference change. Only COMPLETED, FAILED,
CANCELLED and INTERRUPTED Jobs are eligible. A mixed invalid/active selection fails
atomically. `scriptJobHistoryRestore ids` removes only those visibility flags.
`scriptJobHistoryCandidates view` returns eligible finished IDs under explicit
scope and filter for a separately confirmed mass hide. At most 20,000 IDs can be
hidden; larger selections require a narrower scope. Active records remain visible
even if an invalid/stale stored filter contains their IDs. Cancellation is unchanged.

Presentation is version 1 under `scripts.job_presentation` in the existing user
Configuration file. Hidden IDs are global across Runner layouts for that account;
no Journal record, source revision, log, execution directory or Dataset is deleted,
rewritten or copied. Inspection, logs and Session run summaries still resolve hidden
executions. Malformed persisted preferences yield diagnosed defaults while the
original file remains available for review. Writes use Configuration's atomic writer.

`scriptJobWorkspaceSave id name view` creates a stable layout ID when `id` is empty,
or updates that ID. `scriptJobWorkspaceOpen id`, `scriptJobWorkspaceRename id name`
and `scriptJobWorkspaceDelete id` manage named view records in the same Configuration
field. `scriptJobViewRemember view ?id?` persists the last context. Workspace names
are unique; up to 128 layouts are supported. These are user-local layouts available
without an open Session. Session scientific Workspaces remain under
`SESSION_WORKSPACE_API_v1` and Interactive Document ownership. Runner layout operations
persist only their Configuration field and do not apply runtime/resource policy.

Jobs, History, View, Workspace, Settings and Help are native menu groups. History
supports multi-selection, scoped finished cleanup, Include hidden and Restore.
View supplies filters, scope, columns and pages; column headings sort the full
query before pagination. Workspace offers New/Open/Save/Save As/Rename/Manager/Close,
with its active name in the OS title. Closing a workspace resets view context;
closing the Jobs window persists its last view. Neither action submits or cancels
an execution. Resource policy has its existing separate explicit Apply/Save action.

## Registered callable Jobs (Linux/Debian)

`scriptJobSubmit reference parameters options ?callback?` accepts additive
`options.callable_invocation` with exactly these seven fields: `callable_id`,
`source_sha256`, `revision`, `declaration_sha256`, `consumer_api`,
`consumer_operation`, `payload_json`. The first four pin a reviewed declaration
from the existing Script Registry. Changed identity refuses before execution.
The payload is bounded one-line JSON control data (at most 1 MiB); scientific
arrays belong in public Dataset/resource transport. A consumer commonly receives
an encoded scientific recipe string. Its public API is added to preflight.

Invocation identity participates in Job deduplication. The original source
snapshot remains byte-identical; the existing language runner registers its
entrypoint and calls the consumer with a live handle and decoded payload.
Cancellation, process ownership, queue limits and GUI-independent lifetime use
the same supervisor as ordinary scripts. A submission without this option has
its existing behavior even when the source has callable declarations.

Successful consumers return a bounded inert control receipt: at most 4096 nodes,
depth 16 and 1 MiB; typed result arrays are at most 64 finite real values. Large
scientific results must be retained through their public owner and returned as
references. `registered_callable_result.json` records that result plus exact
source/declaration/consumer identity. It is created only after successful consumer
return. Failed or cancelled Jobs never expose a verified success receipt through
the Job inspector, including cancellation during final receipt handling.

Existing `scriptJobInspect` and `scriptExecutionInspectRun` validate that receipt
against the immutable invocation and verified source snapshot, exposing
`registered_callable`, `callable_validation`, and `callable_result`. Inspection
uses owned, bounded, non-symlink files in the exact Session run directory. It
works on archived Sessions without consulting today's Script Registry. A corrupt
or missing completed receipt produces diagnostics and an invalid status.

## Remote registered scientific Jobs

Scientific Execution can return an opaque remote Job ID. `scriptJobDescribe`, `scriptJobInspect`, `scriptJobLogRead`, `scriptJobCancel`, and `scriptJobWait` route that ID to its original node-local Supervisor through the configured authenticated agent. They preserve source Session and durable Job identity. A remote wait observes that Supervisor and does not create a client-side admission lease. Transport unavailability is distinct from terminal scientific failure. Local submit/list/history/resource-policy behavior remains account-local; remote transport does not add a scheduler or merge unrelated node journals into the local history.

## Managed streams, preflight and native debugging

Managed Jobs retain independent actual `program.stdout`, `program.stderr`
and lifecycle/preflight `diagnostic.log` streams, described by `streams.json`.
`scriptJobStreamRead id role ?offset? ?count?` reads a bounded source page;
`scriptJobStreamPublish id role dataset_id` explicitly publishes that source
through Dataset File Publication. Roles are stdout, stderr, diagnostics and
legacy. Historic merged logs remain truthfully labeled legacy, not guessed apart.
The UI copies the focused selection, full retained selected source or an atomic
external byte-exact export. Clipboard UTF-8 scalars are carried across page edges.

`scriptJobDebugSubmit reference parameters options`, `scriptJobDebugRead id` and
`scriptJobDebugControl id operation source_sha256 ?frame?` use the same managed
Job/resource owner as normal Run. Only clean registered Session Python/Octave
scripts are admitted. Operations into/over/out/continue/pause/frame/stop validate
real state and immutable source identity. Python uses native bdb; GNU Octave uses
its genuine dbstop/dbstep/dbstack/whos state with an owned PTY and authenticated
JSON sideband. A native prompt alone never establishes a stopped source frame.
A 600-second debugger lease bounds detached pauses. CORE workers are ineligible.
Command credentials remain private and are omitted from public receipts.

`scriptJobDebugCapabilities language` returns the actual managed adapter's
backend, supported controls, `pause_supported` and `pause_reason`. Debug
observations include the same capabilities. Python bdb supports asynchronous
Pause at a traceable statement. The GNU Octave CLI adapter supports native
breakpoints, Continue, Into/Over/Out, frame selection and managed Stop, but has
no verified asynchronous Pause. It advertises Pause unavailable, disables the
GUI control and refuses a public Pause command before writing any sideband
command or sending an interrupt. A stale direct Octave adapter command also
fails explicitly. An interrupt that terminates a loop cannot be represented
as successful pausing. This limit does not disable ordinary GNU Octave
execution or its verified native breakpoint/step/frame behavior.

Paused observations report selected `line`/`function` and `selected_frame`
separately from actual `execution_line`/`execution_function`. Stack, bounded
locals and source arrow belong to one observation and exact snapshot. External
frames retain their real file/line rather than marking unrelated editor source.

Python Run and Debug perform non-executing import preflight in the exact selected
runtime/Job working directory. Missing unconditional imports or syntax/encoding
errors refuse admission by default. An explicit import_policy=continue option
records the caller's override; the ordinary GUI asks before setting it. Optional,
conditional, relative and dynamic imports retain qualified results. No package
is installed or imported by inventory/preflight. See PYTHON_ENVIRONMENT_API_v1.

Private Dataset Preview services execute an installed immutable CORE service
source with verified provenance, outside the Session Script Registry. Exact
legacy worker identities remain preserved and hidden from ordinary selection and
Results; changed/unverified legacy identities are explicit conflicts, never
silently treated as safe user scripts. Ordinary Jobs and user publications remain
visible. Scientific provider Jobs have their own legitimate Results category.

## Managed compiled Viewer exchange (dev109)

Existing auxiliary `scriptJobAsync command payload callback ?options?` accepts
boolean `duplex` (default0). With duplex1 its supervised pipe retains the write
side for a compiled Viewer's persistent worker; timeout, byte bounds, process
group and UI lifetime remain under the same existing owner. It creates no
scientific Job or alternate scheduler.

Trusted CORE may call `scriptJobRequestExchange request payload ?timeout_ms?`
on that live duplex request. It writes one line when payload is nonempty and
returns one bounded queued response. The default is12000ms; allowed1..120000ms.
It reads the existing owner directly without entering a nested Tk event loop,
so a local tool result is applied before the next queued Canvas event. Timeout
cancels the existing managed request. Scientific calculations retain their
asynchronous Job lifecycle. This host helper is not arbitrary C++ dispatch;
installed Viewer startup/events execute the distributed compiled binary and
never run a development compiler or linker.
