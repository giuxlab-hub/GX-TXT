# Script Library native client API v1

This restricted native client reuses the existing Script Registry, Project,
SourceSurface, SourceNote, parameter, Job and lifecycle owners. It adds no source
reader for a worker, Registry, code runner or scientific Dataset publication path.
Source and parameter bodies remain in CORE-managed editors.

The SDK methods are `script_library_command(form, operation, request)` and
`script_library_result()`. Requests use typed WorkspaceValue objects, with a
separate 48 KiB request/result limit. Getters read only the immutable current
event context. `scriptLibraryApiInfo` and the normal API Catalog describe actual
native operation availability; metadata alone grants nothing.

The actual module must request `SCRIPT_LIBRARY_API_v1.script_library_command`
under the admitted document profile. The shared backend recomputes grants from
the current validated source, design, profile and CORE Catalog for both ordinary
and installed admission. CORE independently checks the enabled registered module,
provider, normally installed package/root, binary and complete source/design
snapshot, exact declared component role map, current event/window incarnation,
generation and opaque Session token. A changed package requires reopening.

The form uses `script_library_components` as documented in
[component roles](VIEWER_GUI_CLIENT_ROLE_MAPS_v1.md). User and Session records
share their existing owners. User operations also work with no open Session;
Session actions explicitly require their current Session. Opening may list or
refresh only. Canonical write/review operations require a real declared mutating
handler. Select and Close can save through their explicit dirty-draft review and
therefore also require that effect. A maintained source-tree notification is a
distinct trusted lifecycle event; it grants no native command or source read.

Finite operations are list/select, new_script/new_project, source_select/save,
copy_record/assign_session/open_workspace/run_review, import_script/import_project,
export/delete, jobs/refresh/close, and the existing source editing commands
undo/redo/find/replace/cut/copy_text/paste/select_all. Unknown fields or unavailable
corrected owner operations refuse. Exact record and namespace comparisons remain
separate from executable source SHA. The host alone owns file choosers and paths.

Receipts contain `operation`, `status`, `error`, `result`, separate `view`,
`sequence` and `event_generation`. Initial `snapshot/completed` uses sequence0
and null result; it is not a successful command. Completed Library commands use
an empty result object; their actual selection/source revision and inventory are
in `view`. Failed/cancelled commands have null result. Failure replaces any older
success; no getter dispatches work. Complete inventory identities are never
truncated to fit. Absolute host paths are redacted from worker diagnostics.

`view` contains selected `{reference revision sha256 draft_token}`, inventory
`{offset limit total records}`, draft `{scope language dirty}`, current selected
row/relative source identity, `selection_valid` and a conflict message. Source
bodies, widgets, capabilities and transient root authority are absent. Restored
local drafts require explicit current-owner review before canonical Save; matching
qualified IDs alone cannot silently rebind another Registry root.

The additive `project_source_read_admission_v1` feature separates source-file
inspection from canonical write admission. `view.source_read_valid` is a Boolean
availability hint for the selected relative file; `source_read_error` gives a
bounded, path-redacted explanation. Neither field grants authority. A client
supporting this feature checks the Boolean's presence and type, then sends its
ordinary finite `source_select` request so CORE can return the authoritative
fresh success or refusal. A missing feature explicitly refuses in that client.
Existing clients and canonical write checks retain their prior behavior.

Already captured local buffers remain inspectable after History restoration.
Reading an uncaptured registered file requires a live read admission established
by the window's authorized selection or its own successful guarded Save.
Save admits only its exact returned commit, never a newer Registry revision.
Exact revision, source SHA,
full-record SHA and physical User/Session Registry identity are checked before
and after the existing source owner's read, together with the roster file SHA.
This bounded admission is transient, never serialized into History, Workspace
or portable resources and never substituted for canonical write authority.
Cold restoration without it requires explicit ordinary reload/review before
reading uncaptured files. History browsing remains read-only. A refused source
selection restores the roster highlight to the actual displayed source.

The additive `restored_owner_review_v1` feature provides an explicit current-owner
review without replacing a restored draft. Optional `select.review_owner` is a
Boolean; native clients must send an actual typed Boolean. True permits only
review of the same selected record whose complete saved logical baseline and
roster still match the actual current record. It never falls through to ordinary
reload, discard or Save. An older CORE rejects the unknown field explicitly.
Ordinary selection also offers this review when that exact restored state is met.

The shared host dialog displays current record, revision, Registry root and full
source/record SHA in a bounded scrollable readonly body. Declining retains the
draft without writer admission. Approval rechecks current Session, window/draft
identity, revision, source, full record and physical Registry after the modal;
only then may the existing owner context be reviewed into this live binding.
Source, Parameters, widgets and Undo remain unchanged. Save is a separate declared
action using the unchanged canonical Registry CAS. Stale metadata, known changed
owners or a different restored baseline do not acquire authority this way.

P033 development gates still requiring separate completion/acceptance include
the normal launcher, genuine compiled/installed frontend, all corrected shared
CRUD owners, managed Resource persistence of large drafts, Workspace/History and
WM-close integration. Host author fixtures with synthetic compiled admission
must not be presented as installed/native or real-input GUI acceptance.

## Draft transport and close review

The trusted CORE Viewer capture now retains a declared `script_library_drafts`
domain. Each controller entry uses `gxtxt.script_library_transport.v1` and contains
an inert inline snapshot when no Session exists, or a typed managed Resource
reference in an actual Session. The controller snapshot remains
`gxtxt.script_library_ui_draft.v1`: source-relative names, exact current and
baseline UTF-8 text, metadata/parameter drafts, selected source and presentation.
It carries no filesystem root, authority token or executable callback. Restoring
it never replaces canonical Registry records or SourceNote Datasets. Saved
identity is rechecked by the normal Registry owners before subsequent writes.

Current and baseline Projects each retain their existing16MiB aggregate and4MiB
per-file limits. The serialized inert snapshot is bounded at96MiB; the complete
transport domain at128MiB. In a Session, source-bearing bytes go through the
existing `managedResourceWrite` and verified bounded Resource reader, with an
actual Interactive Document resource owner and generation/SHA checks. They do
not enter the48KiB native command receipt or the16MiB typed Workspace state.
The resource owner is local draft infrastructure, not a canonical Dataset or a
replacement source association. Existing typed resource transfer, Save As,
portable resource handling and native Workspace owners remain authoritative.
No Session is created implicitly for a User draft.

The codec declares the Resource kind explicitly. Capture reuses an unchanged
snapshot/reference, live Viewer references participate in the existing resource
collector, and restoration validates every entry/controller/resource before
changing widgets. Restoring an earlier unbound state removes later disposable
controller widgets. Canonical scientific payloads remain untouched.

Native Close and window-manager close use the same host review. Cancel retains
all local drafts. Yes saves through the current authorized Registry owner with
its existing identity checks. No authorizes only local discard. A stale Session
or unavailable module permits explicit local discard or Cancel, never a write
under changed authority. A trusted host-close scope is limited to the current
window incarnation, lifetime, module, generation and Session; it is restored after
the modal review and is not a new SDK grant.

Qualification: focused author checks use real Registry, Resource and native
Workspace owners with explicit synthetic module admission. Actual compiled C++
module, independent GUI, cold Session, portable/Save As and History navigation
acceptance remain separate mandatory gates. The source-edit adapter described below uses that existing History owner; capture transport alone does not establish independent acceptance.


The host `scriptLibraryOpen ?qualified_reference?` opens or raises the actual enabled `viewer.script_library` / `script_library` provider. The legacy GUI name `scriptLibraryDialog` delegates to it, including Run, language Workspace, Jobs and Session Script Explorer entrypoints. The ad hoc Tcl Library window/editor has been removed. An unavailable or disabled compiled provider produces an explicit diagnostic; no parallel fallback UI is activated.

A qualified-reference request pins the full Registry record/owner and current Session, waits for the actual admitted C++ controller, sets the real filters, pages through its actual bounded inventory and invokes its existing record selection handler. It does not bind source privately, forge a native receipt, or execute a Script. The existing compiled selection review handles an unsaved draft. Cancellation retains the original Source and highlights only its true stable reference if present on the current page. Callback serials, Development lifetime and the admitted widget incarnation prevent stale/reentrant requests from adopting a different window, Session or namespace; user navigation cancels pending automatic selection. Opening-shell composition is pinned by its Development lifetime until its final native widget is admitted. All original module ZIP/binary/source bytes remain unchanged by this host entrypoint adapter.

Local SourceSurface edits coalesce for450ms through the existing Viewer History append. The existing typed Workspace/resource capture carries exact source and parameter buffers; no source enters the native48KiB control receipt. Before navigation, browse, Save, Clear or admitted Library commands, a host callback flushes pending edits, including changes whose Tk Modified notification has not yet arrived. Other managed Viewers without Library drafts have no adapter work.

History browsing restores Source and Parameters in read-only mode and disables metadata editing. Copy, Find, Jobs and normal Close remain available; state-changing Library commands explicitly require returning to latest. Returning to latest restores the exact local draft. History restoration never writes canonical Registry or SourceNote state. A refused History append restores the unaccepted local draft and keeps it retryable; navigation/Save cannot silently discard it. Timers are tied to the actual window incarnation and retired with that host.

A deferred Modified notification after restoration is compared against the accepted semantic draft before any branch review. Dirty Source text/baselines, Parameters, metadata and file identities count as changes; visiting a clean file from the pinned roster does not create an edit. Cursor, selection, scroll, filters and active-file presentation alone do not request a branch or append. A genuine source edit after Undo still uses the existing explicit branch review.
