# CURVE_VIEWER_API_v1

Version 1, provider `viewer.curve_viewer` descriptor version 0.4.1, namespace
`::GX::CurveViewer`, entrypoint api/curve_viewer_api_v1.tcl. The Tcl implementation
still declares internal version 0.4.0; that is the version used in its Extension
context, not a claim of descriptor/version equality. This is a read-only
scientific source Viewer: presentation/Workspace changes do not overwrite source
Datasets. Explicit canonical publication is a separate installed utility action.

## All non-underscore host calls

| Exact namespaced signature | Return / effect |
|---|---|
| `datasetIds` | Registry IDs with at least two rank-one Variables whose dtype is not literal string; this discovery heuristic is not full numeric/admission validation |
| `open ?context={}?` | Opens/focuses `.curve_viewer`, returns its Tk path; may start asynchronous saved-source restoration |
| `viewerDispatch action scene` | open/rerender only; delegates scene.open_context (default empty) to open; returns Tk path |
| `add w record ?token=""? ?prepared={}?` | Adopts one source/display into an existing owned Viewer; returns record.id and takes ownership of accepted token/native display |
| `snapshot w` | Shared NATIVE2D_PRESENTATION_SNAPSHOT_v1 display dictionary, with real labels/units/legend |
| `workspaceValidate payload` | Checks required payload keys/version; no meaningful success receipt beyond normal Tcl return |
| `workspaceOpen id` | Activates this API and opens the named existing Workspace, returns Tk path |

The last two are declared by the metadata-discovery Workspace provider. Settings
and integrated support files add underscore callbacks, not another public
Script family. No direct Python/Octave binding or typed C++ SDK method exists
for CURVE_VIEWER_API_v1; Native/Curve Source/Plot SDK grants remain independent.
These Tk/window methods are host integrations, not generic headless data calls.

## Context and lifetime

open requires Tk, Native2D and actual Session/Document lifetime services.
Optional context: workspace_id, workspace_name, dataset_id. A Dataset ID is only
a preferred Add-source choice; no Dataset is automatically loaded as a curve.
workspace_id=new starts an empty draft, an existing ID is validated for
provider curve_viewer, and omitted ID restores the first saved owned Document
when a window must be created. A live window with no differing requested
Workspace is raised/reused; dataset_id only updates its preference. Switching
requested Workspace uses the existing host's pending-work/dirty handling.

The scene and source tokens are owned by the Viewer. Operations check captured
Session lifetime where their actual `_scope` call applies; direct snapshot
itself reads the existing state and does not add an independent lifetime guard.
Do not claim every callback has identical standalone scope validation. Dataset
catalog changes validate live source snapshots and mark changed sources unavailable.
Closing cancels pending loading, unsubscribes catalog/configuration, closes live
Curve Source tokens and destroys its Native scene/window through existing owners.

## Source record and add ownership

record is the host's inert source definition: id, request, name, visible, color,
width, direction, optional marker=0,line_style=0,presentation_label,manual_family
and retained display_cache. request is a real Curve Source dataset_id/X/Y stable
Variable request, with declared filters/selection/order semantics as applicable.
Normal UI family/member choices create independent exact requests, never join
different member curves. Color/style affect presentation only.

Without a token/cache, add opens and describes the exact source, obtains bounded
display points/breaks, and creates a locked Native display actor. A supplied
token is consumed on success. After the initial Session `_scope` check, the
try/finally closes a supplied token on failure; rejection by that initial scope
check occurs before this cleanup region. prepared may be a host-owned
display result, or a validated cache-restore dict with descriptor/display/native.
The latter native ID must already belong to this Viewer's scene; this is not
permission to submit foreign raw handles from Script/C++ code. A failed cached
restore falls back to canonical source preparation. Newly failed native/token
resources are removed in finally; success stores token/native/descriptor,
source_id/display/status=ready and returns the logical record ID.

add does not on its own refresh menus, fit/redraw, checkpoint history or save a
Workspace. Normal source-batch host callbacks perform those actions and rollback
their staged adopted records on failure. Do not replace those ownership/cancel
semantics by directly mutating the internal st array.

## Snapshot, persistence and shared behavior

snapshot chooses manual or configured automatic labels, matching visible source
Variable display labels/units. Multiple different bindings yield explicit mixed
bindings/units axis text rather than silently selecting a common physical unit.
It calls the shared Native2D snapshot with font 13, title Dataset curves,
object_labels and configured legend visibility. Paths/IDs are device display
data, not full canonical arrays or opaque Script object tokens. Scientific
publication reopens the canonical token, rechecks source identity and delegates
to CURVE_DATASET_EXPORT_API_v1; graphical PNG/SVG uses Extension exporters.

Workspace payload version 1 requires records,next,presentation,view_requested;
actual saved payload also includes selected_ids,label_preferences and managed
history/cache fields. workspaceValidate only checks required keys and version;
it is not deep source/schema/cache validation. Restore uses CORE cache validation
or live source loading, with cancellation/epoch guards; unavailable archived
sources retain identity and an unavailable status. An interrupted restore marks
incomplete and avoids overwriting the saved Workspace.

Named empty drafts are unsaved until Save/real edit. Actual save uses Workspace
and scientific History owners, capturing requested view/presentation/style and
original source definition. Generation/revision/payload conflicts require reopen.
Display caches are optional managed resources and canonical source remains
authoritative. No universal load-time, global object/byte bound or complete
scientific materialization is promised by the host API.

## Source-backed activation example

```tcl
set w [::GX::CurveViewer::open [dict create workspace_id new workspace_name {Inspection draft}]]
# The normal host Add-source workflow supplies validated source records.
set imageSnapshot [::GX::CurveViewer::snapshot $w]
```

Unexecuted illustrative host calls; require actual Tk/Session ownership. Missing
service/source, malformed record, foreign/stale token, invalid style/schema,
changed owner or unsupported Workspace/action raises errors or actual unavailable
source diagnostics. Source-backed behavior does not establish native menu,
cancel/reopen/cache/history/performance acceptance; those remain independently
verified gates. See Curve Source, Session Workspace, Native2D Snapshot and
Workbench Extension references for their separate public contracts.
