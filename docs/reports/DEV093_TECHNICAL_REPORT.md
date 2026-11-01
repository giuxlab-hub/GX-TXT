# GX-TXT 0.9.8.10-dev-093 — integrated delivery

SPDX-License-Identifier: GPL-3.0-or-later

## Scope and authority

The accepted dev092 archive, expanded tree, installed source, restore point,
installation identity, original scientific Session and tutorial were inventoried
before development. The pinned dev092 archive SHA-256 is
`0b32a998bd2d2b49a0d538f0508843a021a129338b621803267ab89dec6b218a`.
One root integration owner coordinated isolated Publication, transport and resource
worktrees and serialized merges against recorded base/result hashes. No Curve
Workbench source, background canvas behavior, unrelated module, external plugin
package or Session Generator was changed. Numeric 1.16.1 and Signal 1.2.1 are
bundled CORE modules. Windows implementation and remote execution are excluded.

The CORE local Job Supervisor owns registered script lifecycles. Dataset
Publication retains scientific commit authority. The Resource Manager accounts
for reclaimable resources; it is not a second scientific registry. GUI Run and
registered Analysis use the durable service. Existing synchronous host execution,
public Script Bridge v1, Dataset, Plot and Viewer APIs remain available.

## Delivered behavior

Run captures immutable script source, normalized parameters, original Session,
semantic Dataset input aliases/revisions and optional output identity. Its
collapsed optional chooser contains only the current namespace. Changing GUI
Session or namespace cannot retarget running work. Equivalent active scientific
requests deduplicate atomically; completed work may be rerun. Distinct effective
inputs admit concurrent jobs subject to global policy. Output labels and output
requests alone do not create duplicate computation; an equivalent request returns
the existing job's assigned output. Compatible scripts read the generic context
binding and publish through existing CORE APIs.

Jobs exposes queue/state, origin, source/run identity, progress, bounded log tails,
resource policy/usage, cancellation and recovery. GUI submission/preparation and
monitoring use fileevents. Linux detached supervisor/guardian processes own the
child tree; closing Tk leaves work running. The guardian launch handshake,
boot-qualified process identities and inherited scratch leases protect recovery.
Cancellation drains descendants before Publication recovery and resource release.
Faults in one job/report/projection cannot kill other jobs. Uncertain interrupted
work is reconciled without implicit scientific rerun. Progress from both native
runner and public Bridge diagnostic channels is persisted.

Publication distinguishes creating from replacing even when `replace_owned=True`.
A per-Session kernel lock coordinates all affected CORE registry/metadata writers.
Commit rechecks identity, revision, producer, namespace, immutability and target.
Streaming and hashing remain outside the short commit transaction. Fsynced undo
journals recover interrupted multi-file commits; committed markers prevent a
cleanup failure from rolling back published data. No global age/glob deletion
is used. Persisted revision tokens exclude lazy in-memory schema projections;
real committed metadata/schema/namespace changes still invalidate bindings.

Large Numeric/Signal arrays use validated typed descriptors and private binary
buffers with bounded sizes, explicit shape/order/endian/dtype, and one persistent
local Octave worker per Bridge. Existing Octave scientific operations still
compute results. Optional uniform coordinates and projected results avoid unused
arrays. The existing HDF5 binary-block publication path remains authoritative.
Float32 widens according to the existing float64 contract; complex and nonfinite
policies follow the public operation contracts. Small/v1 behavior is preserved.

Configuration → Cache & Temporary Storage provides global category/subsystem
counts and bytes, refresh/rescan, policy and selective audited cleanup. Active,
unknown legacy, publication recovery, scientific, script provenance and warm
renderer cache resources remain protected according to ownership/retention.
There is no automatic server-wide cleanup.

## Verification and measured science

Acceptance evidence is bundled under `dev093_evidence/`; executable validation
sources are under `validation/async_dev093*`. `DEV093_CHANGED_FILES.json` contains
base/result file hashes; root `SHA256SUMS` covers release contents excluding itself.
Fresh archive extraction and critical tests precede active publication.

- Publication: 41 cases/operations with real independent processes, competing
  create/replace, ownership/immutable/namespace checks, unrelated-writer merge,
  genuine stale-save rejection, exact 262144-value HDF5 readback, v1/file paths,
  metadata privacy, injected ENOSPC and crashes killing both Tcl and lock helper.
  Create/replacement crashes cover prepare/payload/registry/metadata boundaries.
  Additional durability tests cover committed-marker and cleanup-failure behavior.
- Supervisor: 11 focused real-process checks cover atomic simultaneous admission,
  nested cancellation/reaping, guardian SIGKILL, launch rollback, late cancel,
  atomic reports, isolated job errors, restart reconciliation and resource leases.
  These focused fault fixtures use a synthetic publication callback; integrated
  GUI/science jobs and Publication fault tests separately exercise real authority.
- Resources: 12 tests cover live/dead owners, idempotence, diagnostics retention,
  warm renderer cache, unknown and authoritative preservation, accounting/budgets,
  inode replacement, symlink/hardlink safety, Tcl/Python round trips and crash leases.
- Registered lifecycle: Python and Octave success, explicit error, cancellation,
  active duplicate return, terminal rerun and durable public progress pass.
  Normal Analysis queue/CLI execution and legacy result projections pass.
- Bindings: normalized defaults, labels excluded from identity, multiple aliases,
  queued source immutability, stale mutable input rejection, create-only collision,
  foreign replacement denial and empty-namespace behavior pass. A repeated-read
  regression proves stable tokens and subsequent ordinary saves; real metadata
  and schema changes invalidate tokens and preserve payload bytes.
- Real Debian desktop: native XTEST pointer/keyboard interaction on local Xorg :1,
  current-only chooser (103-Dataset focused check; 23-Dataset full GUI flow), different-input concurrent runs,
  duplicate Run, responsive Tk heartbeat, Session switch isolation, committed
  output recovery, Configuration inspection/cleanup, GUI close with RUNNING job
  and fresh-process reconnection. Only private test windows were captured.
- Scientific compatibility: scalar/small/large float32/64, split complex,
  multidimensional C/F order, IEEE/nonfinite policy, deterministic seeded noise,
  malformed descriptor rejection, real Octave Bridge and a legacy large Numeric
  consumer pass. Rank-two HDF5 append/readback preserves exact shape and values.

The unchanged original script01 completed 4,194,304 samples in **6.840 seconds**
for the registered host lifecycle; its own generation/finalize interval was
3.17349 seconds (1.322 million samples/s). Historical failed execution took
1,318.181 seconds; that is historical diagnostic evidence, not a repeated paired
benchmark. The final run made 48 scientific calls and started Octave once, with
134,218,880 input binary bytes, 234,881,024 output binary bytes and 78,227 control
bytes. Sampled peak tree RSS was 334,815,232 bytes, with six processes, seven
threads and 38,896,800 temporary bytes. HDF5 storage was 33,563,808 bytes. All
samples were finite; seeded noise RMS and 997/4093/12011 Hz peaks were verified.

A matched 65,536-value warm three-operation profile fell from 20.912 seconds to
0.05495 seconds. See `DEV093_SCIENTIFIC_REPORT.md` for per-stage timings, warm/cold
qualification, array byte counts and numerical comparison. Legacy JSON parsing
introduced up to one coordinate ULP; resulting tone difference was bounded at
4.32e-12. Binary coordinates preserve exact values and seeded noise is identical.
Bounded Steps2–4 pass; Step3 public Signal Fourier results remain authoritative.
Step4 deliberately used the one-worker nested fallback, not a multi-worker FFT
claim. Separate admitted concurrency1/2 scientific results and exact HDF5
comparisons are recorded in the scientific report.

## Preservation, corrections and limits

Official tutorial script01 changes only its optional output ID/replacement
adapter; all mathematical constants, generation code and default behavior remain.
The original tutorial is copied in full before that update; instructions and
checksums record the change. The original first-create failure was a CORE bug;
no independent mathematical script defect was demonstrated. Historical failed
Sessions and existing scientific records were not rerun or overwritten. The owner
kept a separate pre-existing GUI open on display `192.168.1.111:0`; our GUI tests
used local Xorg :1 only. During development, three live interactive documents
and one Workbench recovery record changed in the original Session. The same
owner then saved the Session Manifest, runtime log and a derived preview. Dataset
payloads, canonical Dataset metadata and other scientific resource hashes still
match baseline. The release preserves those live edits and takes two additional
complete 158-file snapshots before publication; it does
not restore obsolete document hashes over the owner's current state.

Failed intermediate GUI/contract attempts were retained as development evidence
and excluded from acceptance. Integration corrected a cache UI brace, expandable
Run geometry, unique Analysis runtime paths, a missing canonical projection
folder, progress channel collection, lazy-schema revision/CAS behavior and the native
`wish` preparation-helper exit boundary. Jobs loads its actual persisted concurrency
policy and formats timestamps for display.
One profiler created 33 new bytecode files in dev092 expanded source; only those
new files absent from the baseline were removed, restoring exact original
inventory/hashes. A newly generated sibling installation-identity directory from
the profiler was moved intact to evidence, restoring archive/expanded pairing;
future profiler runs also isolate installation identity. A preliminary profiler left a released accounting record in
the default resource registry; later runners isolate both roots. Details are in
the scientific report and correction receipt.

Resource enforcement uses reservations and sampled Linux process-tree usage,
not hard cgroup limits; short peaks between samples are possible. Binary blocks
are bounded rather than unbounded zero-copy streaming. Publication fault tests
inject storage errors and process crashes; physical power-loss/full-disk tests
are SKIP. Unrelated full historical GUI matrices and native Windows execution
are SKIP, not PASS. Existing dev059 empty-metadata expectation is obsolete and
is replaced by the current metadata/privacy contract test. No claim is made
that source-code portability comments constitute a tested Windows implementation.

The future native Windows supervisor must run locally, independently of Tk,
with the mandated notification-area tray, shared CORE API and native process-tree
management; no remote Linux dispatch or mandatory service. This contract is in
actual supervisor/backend/Tcl lifecycle source comments and the public Job guide.
The existing Curve Workbench canvas limitation and all unfinished unrelated TODOs
remain deferred. Completed dev092 acceptance was removed from remaining-work TODO;
release history remains in CHANGELOG.
