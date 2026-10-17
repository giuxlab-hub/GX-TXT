# CORE Script Job API v1

Dev104 auxiliary GUI requests extend the existing nonblocking
`scriptJobAsync command payload callback ?options?` transport. Options are
timeout_ms, max_bytes, process_group, ui_lifetime and label; old callers keep
their existing defaults. `scriptJobRequestCancel request ?reason?` cancels only
the transport-owned child/group, escalates TERM to KILL after 500 ms and delivers
one terminal response. Workers opting into process_group must establish their
own group before spawning descendants. Output is read in bounded chunks.
UI-lifetime requests are killed on application shutdown; durable scientific
Jobs retain the independent supervisor lifecycle described below.

Cancellation retains the owned group identity through escalation even if its
leader closes stdout early, preventing detached descendants from surviving.
Responses distinguish timeout, cancelled, closed and output_limit. This
transport does not add a scientific scheduler or make a GUI request a durable Job.

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
