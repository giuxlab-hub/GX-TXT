# CORE native History service (DEV111-P017)

The authoritative active timeline is a native C++ engine, scoped to one
interpreter, Session, scientific owner and Document generation. Viewers submit
operations and supply scientific capture/restore hooks. CORE owns ordering,
worker lifetime, journal/checkpoints, navigation, hook cancellation and shared
History controls. No worker executes Tcl/Tk or Native2D callbacks.

## Public integration

`scientificHistoryViewerAttach window owner callbacks ?record?` imports a legacy
scientific recipe once. Required callback prefixes remain `capture`, `restore`,
`commit`, `guard`. Optional `describe row` returns presentation-only description/kind/group overrides; import calls it once per retained step with semantic data, and append calls it once for the new row. Optional `document_id` binds a canonical Document immediately;
otherwise CORE allocates a Session-local draft journal. `accepted receipt` is a
lightweight owning-thread notification; `error receipt` reports background I/O
failure. `commit record` now projects the full legacy record at an explicit
persistence boundary, rather than being the ordinary operation recorder.

`scientificHistoryViewerRecordOperation window description ?snapshot?` returns
an acceptance receipt. Without a supplied snapshot, CORE invokes the existing
capture callback on its owning thread. Supplying an independently prepared inert
snapshot avoids that capture. `scientificHistoryViewerSubmitPatch window patch
description ?semantic?` accepts a domain-prepared top-level dictionary delta.
Deletion uses the existing inert `@gxtxt.recipe.delete` sentinel. New Viewer
code should use these receipt-returning operations.

Receipts contain `accepted`, `accepted_revision`, `revision`, `durable_revision`,
`pending`, `failed`, `error`, `status`, `count`, `cursor`, `record_bytes`,
`queued_bytes` and `queue_limit`. RAM acceptance immediately enables Undo/Redo.
`status pending` means the operation is not yet crash durable. Only successful native file and directory synchronization advances
`durable_revision`. This certifies the native History journal/checkpoint, not the
separate Dataset/resource storage systems. Their existing scientific owners and
backup requirements remain applicable. A failed worker retains accepted RAM state,
reports failure and rejects additional persistence-dependent submissions.

`scientificHistoryViewerState window` reads the selected RAM state.
`scientificHistoryViewerStatus window` is constant-cost status access.
`scientificHistoryViewerSummary window` provides UI metadata only; its steps
carry descriptions/group fields and empty patches. It is **not** a scientific
recipe. `scientificHistoryViewerRecord window` explicitly materializes the
complete compatible recipe for Save, export or external API clients.

`scientificHistoryViewerNavigate window undo|redo|previous|next|latest|branch`,
`scientificHistoryViewerBrowse window index` and
`scientificHistoryViewerClear window workspace` retain existing presentation
contracts and confirmation dialogs. Browsing does not change the active cursor
or write scientific state. `Browse key index index` explicitly inspects even
the last retained future row after Undo; `Navigate key latest` restores the
editable cursor. The default Browse mode keeps its historical count/latest
interpretation. Projecting Flush rejects browsing, including a clean context.
Branching and clearing are explicit destructive
timeline decisions; neither silently truncates retained scientific History.

`scientificHistoryViewerFlush window ?timeout_ms=30000? ?project=1?` drains
accepted native work, then invokes the legacy projection hook if dirty.
Projection executes on the owning GUI thread. Save, export and explicitly requested
`interactiveDocumentRead id current` are full-record boundaries. Ordinary
Document reads retain the canonical stored-payload contract and do not drain
History during title, menu or owner refresh. Close must flush before
destroying scientific widgets/state if its existing contract saves on close.
Raw widget destruction drains the journal and retains recoverable state, and
does not call dead Viewer hooks. Session-stale windows cannot project into a new
Session. `scientificHistoryViewerBindDocument window document` validates and
opens the new owner before releasing its previous engine, preserving the old
handle if rebinding fails.

The pure dictionary APIs (`scientificHistoryCreate/Validate/State/Append/
Navigate/Branch`) and the complete-record return value of
`scientificHistoryViewerChanged` remain compatible; Changed also drains and
projects its legacy commit callback before returning. They explicitly materialize
or validate legacy values and therefore remain proportional to their input.
They are compatibility/import/export APIs, not the incremental GUI submission
path. No external client is required to understand an opaque native handle.

## Nonwindow owners and scientific channels

`scientificHistoryContextAttach owner callbacks ?record?` allocates a CORE
context without creating a hidden Tk window. The same state, submission,
navigation, status and export functions accept its key. `ContextClose key
?project=1?` drains and releases it before its scientific scene is destroyed.
`scientificHistoryViewerDetach` provides the same lifecycle boundary when a
singleton Viewer replaces a source or Workspace while retaining its window.

Optional callback fields `parent` and `channel` associate an owning GUI parent
and a named scientific channel with the same Document. Channels have qualified
CORE journal identities, paths and locks. This preserves independent image and
figure Undo semantics without private Viewer stacks or persistence queues.
The principal History still records complete scientific state. Explicit Save
exports channel records; normal captures carry state/cursor markers rather than
accumulated subordinate records. `scientificHistoryContextSetParent key window`
attaches shared presentation controls later, as with a windowless 3D owner.

`scientificHistoryViewerSeek key index ?restore=1?` restores a checkpoint through
CORE or, with restore=0, verifies that the live capture already equals that
checkpoint before aligning its cursor. `scientificHistoryViewerReset key
snapshot` is an explicit lifecycle reset used after a confirmed principal
branch/clear. Optional `context menu index` supplies domain-specific menu entries;
CORE invokes it on the owning thread and retains shared navigation/menu control.
`scientificHistoryViewerRestoreContext key` distinguishes browse/latest from
Undo/Redo/branch/seek/recovery so domain parameter read views remain read-only.

## Auxiliary state and acceptance errors

`scientificHistoryViewerAuxiliary key ?dictionary?` reads or accepts independently
owned inert control/presentation state. It has its own 8 MiB limit and shares the
ordered native revision, journal and checkpoint service. It adds no scientific
step, changes no scientific cursor, and never enters the exported legacy recipe.
A no-op retains its revision. Optional `auxiliary` supplies the canonical saved
initial value; otherwise `capture_aux` seeds a new context. `restore_aux value`
restores recovered or latest auxiliary after scientific restoration. CORE calls
`capture_aux` after append/undo/redo/branch/seek/clear; `auxiliary_sync_modes`
can narrow that set. Explicit Save must embed auxiliary separately in its owner
payload. Native recovery and Session transport carry it separately. Auxiliary
resource references participate in managed-resource collection.

Curve uses this for camera/tool/selection state and monotonic allocation
high-water marks. Scientific semantic `undo_auxiliary` can preserve the exact
pre-operation presentation without making every pan or selection an Undo row.
`scientificHistoryViewerOperation key one_based_index` returns one retained
semantic entry without exporting the full History.

An auxiliary rejection returns accepted=0, stage=auxiliary and
scientific_state_retained=1, reports the error hook, and attempts presentation-only
rollback. It never reports an already accepted scientific operation as rejected.
The scientific submission receipt also identifies its `scientific_revision`;
auxiliary synchronization may advance the final receipt revision. Optional
accepted/describe hook exceptions become separate `hook_failed` / `hook_error`
warnings and preserve the accepted science and fallback row. Native I/O `failed`
remains distinct and actionable. Failures never imply durability.

## Optional asynchronous hooks

`scientificHistoryViewerRequest window input description completion` schedules
the optional `prepare_async token input` hook on the GUI thread and returns a
pending token without waiting. The hook must return promptly. It can hand
independently owned data to a domain worker or use a cooperative owning-thread
operation, then call `scientificHistoryHookComplete token ok snapshot`.
`failed message` reports failure. CORE checks the Session and starting revision,
accepts the result in order and invokes the supplied completion prefix with a
receipt. One pending preparation per Viewer bounds memory and ordering.

`scientificHistoryHookCancel window` invokes optional `cancel token`, invalidates
the token and reports cancellation. Late completions are inert. Pending hooks
must complete or be cancelled before Save, navigation or Close. Arbitrary Tcl
callbacks cannot be preempted or moved to a worker; existing synchronous capture
and scientific restore retain their owning-thread contracts.

## Persistence, ownership and integrity

The Linux binary uses one ordered worker per active engine, bounded engine and
queue counts, a default 32 MiB byte queue, and the existing complete retention
limits of 4,096 steps and 8 MiB. Queue or retention exhaustion rejects before RAM
acceptance; no accepted step is silently discarded. The worker stores isolated
bytes and its own checkpoint model. Ordinary append neither exports nor hashes
the accumulated timeline. Batched journal fsync and checkpoint construction run
on the worker.

Frames contain monotonic revisions and a SHA-256 chain. Checkpoints are fsynced,
atomically renamed, and followed by an atomic journal-header replacement and
directory fsync. Checkpoint plus ordered suffix tolerates interrupted publication
and incomplete last frames. A complete frame with a bad checksum fails recovery.
Ownership includes canonical Session identity, scientific module, Document ID,
generation and provider. A process lock rejects multiple writers. Recovery is
explicit; a journal that differs from the saved Document offers Recover, retain
saved state with journal archival, or Cancel. Recovery never evaluates stored
data as Tcl scripts. Discarded journals are archived rather than overwritten.

Resource collection includes active RAM records and retained native journals,
including closed Documents. Corrupt native recovery prevents collection of
potential scientific references. Canonical Document payload reads still verify
SHA-256. Registry-only ownership checks and revision-keyed small parameter
metadata avoid repeatedly hashing an entire History payload for parameter
lookups; they do not certify scientific payload integrity.

## Shared GUI and remaining synchronous work

The Viewer chooses the parent and packing layout for the shared Description /
History strip. CORE owns grouping, timeline rows, navigation, confirmation,
details and menus. History menus post upward and clamp to the owning application
window. Details dialogs are bounded and placed near the top of that window.
The existing within-Viewer selector and focus behavior remain in use.

Capture/delta comparison scales with current scientific state, not accumulated
History. Domain validation, Native restore, resource externalization, explicit
legacy record export, Document projection/Save and visible timeline painting
still execute on the GUI thread. In particular, large Worksheet snapshots may
externalize managed resources synchronously. A native persistence worker alone
does not eliminate these costs; test reports distinguish operation acceptance,
GUI latency and durable completion.

## Session transport and lifecycle

Session export explicitly drains native work with project=0. It verifies the
native families under writer locks without a hidden Viewer Save. Import verifies
ownership and checksums in an unpublished stage, uses native recover/open/flush
to rebind the new Session path/device/inode, and atomically publishes only after
success. The independent Session starts revision epoch1; verified original raw
journal/checkpoint bytes, prior revisions and SHA-256s remain in transport_archives.
Selected preparation duplication admits only eligible retained Documents and
all-state dependencies, and excludes orphan/draft/unselected families.

Registry metadata checks do not decode a scientific payload. Parameter metadata
is cached by Session token, Document generation/revision and payload SHA; a
successful verified read or Create/Update seeds it from the already owned value.
First parameter capture after explicit Save therefore does not reread/hash the
full History payload. No unchecked cache is substituted for an explicit scientific
payload read.

Initial legacy import, recovery, full exports, scientific resources and explicit
Save remain synchronous boundaries. A legacy_import envelope allowance of at
most4096bytes preserves otherwise legal old records missing required headers;
new scientific appends still obey the complete 8 MiB /4096step limit. Exhaustion
rejects visibly; it does not evict scientific steps. Auxiliary has a separate
8 MiB cap; queues are32MiB/8192events, at most32engines. Aggregate memory includes
main-thread scientific objects, inverse patches and isolated worker/checkpoint
copies; these limits are per engine, not a claim of a single8MiB process footprint.
