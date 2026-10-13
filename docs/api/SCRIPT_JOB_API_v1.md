# CORE local Script Job API v1

SPDX-License-Identifier: GPL-3.0-or-later

Registered Python and GNU Octave scripts launched from Run or Analysis execute
under one local durable supervisor. Tk owns neither calculations nor process
lifetime. Closing the GUI detaches it; Script Jobs reconnects on the next launch.
The host compatibility `scriptExecutionRun` remains synchronous for existing
headless callers. GUI surfaces use `scriptJobSubmit` and fileevent callbacks.

## Host operations

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

## dev095 read-only identity and log inspection

The existing host API additively supports `inspect id`, `log_read id offset count
?tail?`, `inspect_run session runId`, `run_log_read session runId offset count
?tail?`, and `run_summaries session`. Tcl convenience wrappers are
`scriptJobInspect`, `scriptJobLogRead`, `scriptExecutionInspectRun` and
`scriptExecutionRunSummaries`; nonblocking GUI clients use `scriptJobAsync`.
Read projection never replaces the journal or current Registry identity.
See `../reports/DEV095_API_CHANGE_REPORT.md` for fields/security/range semantics.
Submitted records add script ID/version/Session name; legacy omissions are filled
only from immutable runtime metadata. `launched_at` captures worker spawn;
existing `started` retains its preparation meaning. Never-launched exit code is N/A.
Complete log access is bounded/paged; missing, expired or unsafe sources diagnose
that exact execution. No arbitrary file-read operation is exposed to scripts.
