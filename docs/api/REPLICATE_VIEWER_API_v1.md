# REPLICATE_VIEWER_API_v1

Version 1, provider `viewer.replicate_curve_analysis` version 1.2.0, namespace
`::GX::ReplicateViewer`, entrypoint api/replicate_viewer.tcl. The existing Viewer
is a consumer of CURVE_REPLICATE_ANALYSIS_API_v1, shared Viewer GUI/History/
Workspace owners, real managed scientific Jobs and Plot v4. It does not own a
second consensus/covariance engine. No direct Script binding or typed C++ SDK
method is registered for this Viewer family; use the separately admitted public
scientific service for headless analysis.

## Activation, state and scientific meanings

`open ?context={}?` returns Tk path `.replicate_consensus`. Context may supply
request, workspace_id,workspace_name; empty/new ID creates an unsaved draft,
existing ID loads its Workspace payload. A live window switches through the
shared host prepare/dirty contract before destruction/reopen. `dispatch action
scene` delegates scene.open_context (default empty) to open; the action argument
is not independently validated in this adapter. Backend is replicate_consensus_tk.

Default request: new analysis_id, method yx, design repeatability, grid_points
200, reference_frame with empty ID/declaration and mm/mm labels, no traces.
These are UI defaults, not verified physical agreement. Analyze builds the
explicit_user_verified/unverified declaration from the user's actual checkbox,
sets anchored_source_arclength for xy_path, then delegates preflight/submit to
the actual Replicate service. Valid methods/designs shown are yx/xy_path and
repeatability/calibration_sensitivity/hierarchical. Scientific identification,
unit conversion, admissibility, uncertainty and correspondence belong to that
service's documented request/result contract.

Each source observation retains Dataset/X/Y stable IDs, optional curve/order
Variable IDs, physical_feature_id, curve_key, observation_id, point_set_id,
calibration_realization_id, source_group_id, topology open/closed, landmark_id,
direction forward/reverse, phase_index and common frame_id. UI defaults are
editable suggestions, never proof of independent observations or physical
landmarks. Missing uncertainty is not zero. Shared calibrations are sensitivity
studies unless the public scientific owner supplies stronger qualified results.

## Complete host function reference

All signatures use `::GX::ReplicateViewer::` except the final Workspace pair.
Window/state callbacks are host integrations; listing them does not create
generic Script/C++ access. Most results are UI/state effects unless specified.

| Exact signature | Result / effect and boundary |
|---|---|
| `guard w` | Requires live window, captured Session token, matching saved Workspace generation/revision; returns 1 |
| `safe w method args` | Guard then invoke this namespace callback; caught error goes to status and returns 0, success returns 1 (not callback result) |
| `capture w` | Captures current plot axes when present, returns payload without history |
| `resultValue payload` | Returns inline result or UTF-8 managed result resource; read limit 32MiB, 1MiB chunks |
| `storeResult w payload result` | Returns payload containing inline result up to 512KiB or managed resource; larger result requires already-saved Workspace |
| `restore w payload` | Clears live ticket, restores payload and refreshes; not a solver replay |
| `historyCommit w record` | Stores shared History record in payload |
| `historyValidate record` | Checks workbench_id is viewer.replicate_curve_analysis; returns 1 |
| `historyCapture w` | Returns shared scientific History record |
| `historyReplay context record` | Explicitly errors: navigate in owning Replicate Workspace |
| `change w payload description` | Guard/prepare History edit; changed request invalidates result/resource/publication/Plot/view fields and live ticket; changes state/history then refreshes |
| `current w` | Current Workspace ID, empty for draft |
| `dirty w` | Compares captured history-free payload with saved payload |
| `prepare w action` | Guard, disallow busy Workspace transitions except query; returns 1 |
| `discard w` | Destroys host window; no canonical deletion |
| `close w` | Invokes guarded closeWorkspace; returns safe's boolean |
| `closeWorkspace w` | Delegates close to Session Workspace Viewer action/normal dirty handling |
| `callbacks w` | Existing current/save/open/close/dirty/prepare/discard callback dictionary |
| `save w` | Creates/updates canonical Workspace with History, updates captured generation/revision/saved payload, returns Workspace ID |
| `open ?context={}?` | Create/reuse host GUI and register real shared command/workspace/history/plot controls; returns Tk path |
| `enabled w action` | Actual per-action UI state: busy/cancel/plot/selection/ticket/published-Dataset conditions; no scientific validation receipt |
| `refresh w` | Refresh source list, render retained result or remove absent plot/visibility UI, refresh shared actions and publish actual GUI declaration |
| `sourceDialog w` | Opens observation dialog from compatible canonical tables; rejects busy/no compatible source |
| `sourceVariables w` | Populates source Variable choices from Table Stream schema; independent/measured semantic roles set suggested X/Y |
| `sourceAccept w` | Requires nonbusy and nonempty frame ID, appends/replaces explicit trace in request through change; closes dialog |
| `removeSource w` | Removes selected trace through change; busy rejects, no selection is no-op |
| `analyze w` | Captures visible scientific fields, public preflight, state/history change, public submit, busy state and initial poll |
| `poll w` | Public status; schedules every 300ms while active. On completion requires same request, gets real result, stores/adopts through change; errors retain actual status |
| `cancel w` | Delegates cancellation of existing owned ticket to Replicate service |
| `navigate w direction` | Shared scientific History navigation |
| `fit w` | Plot v4 fit if plot exists, remember axes |
| `zoom w factor` | Plot v4 zoom main panel about fractional center (.5,.5), remember axes |
| `draw w result` | Builds renderer-neutral consensus/original/aligned/sample-spread model, configures real Plot v4 widget, qualified report and retained visibility controls |
| `publish w` | Public scientific result publication for live ticket, stores published_dataset and returns canonical receipt |
| `publishGraph w` | Publishes result Dataset if needed, creates native editable Plot v4 variant of x_mean/y_mean, records/returns Plot reference |
| `destroyed w actual` | On actual owner destruction cancel GUI poll timer and clear UI arrays; it does not itself cancel the durable scientific Job |
| `dispatch action scene` | Delegate open_context to open; no extra action validation |
| `visibility w id` | Shared History prepare, actual Plot v4 series visibility, retain hidden map and record change |
| `pick w x y` | Actual Plot v4 device hit, retain hit receipt, select original observation when identity matches trace_N, refresh controls/status |
| `rememberView w` | Guard when possible; capture actual Plot widget axes into payload |
| `editSource w` | Opens selected trace's observation editor with exact saved fields |
| `publishGui w` | Publish read-only current GUI design/component/value/binding manifest through existing Viewer GUI owner; returns publication receipt |
| `describeGui` | OPEN_REQUIRED if original window absent; otherwise current manifest plus DECLARED_MAIN_INTERFACE |
| `::GX::ReplicateWorkspace::validate payload` | Requires format/request/hidden and exact gxtxt.replicate_viewer.v1 format; returns 1, not full scientific request validation |
| `::GX::ReplicateWorkspace::open id` | Activates this API and opens exact Workspace ID |

Direct callbacks do not each repeat guard; normal command dispatch uses safe
and the existing shared host. Consumers must not infer uniform standalone
atomicity/Session checks for every UI callback from the guard method's presence.

## Result presentation, persistence and bounds

The scientific result supplies x_mean/y_mean and units, original_traces with
canonical row identities, aligned_traces and qualifications. Original closed
traces may repeat their first row for display closure. Aligned coordinates and
mean±sample-SD curves use source-row sentinel −1: they are explicitly derived
samples, not original row picks. Spread is descriptive sample SD, not confidence
or prediction interval. Nonfinite spread suppresses that envelope rather than
inventing zero; report preserves public qualifications for uncertainty/design/
correspondence. Plot v4 owns rendering/hit/axes/visibility; GUI host owns controls.

Workspace payload format is gxtxt.replicate_viewer.v1 with request/hidden, optional
result/result_resource, published_dataset, plot_ref, view_axes and History.
Structural Workspace validation is intentionally weaker than scientific
preflight. Request changes clear old results, ensuring a completed Job cannot
replace a different live request. Large result adoption requires a saved
Workspace and managed UTF-8 resource; resultValue's 32MiB read bound is not a
guarantee storeResult prevents every larger resource from being written.

Closing/discarding removes UI polling/state; a durable managed Job remains under
CORE lifetime/supervisor authority unless explicitly canceled. No extra scheduler
or process termination is introduced. Publication, later Plot creation and
Workspace save are separate effects; failed graph/save is not evidence the
already committed scientific Dataset disappeared. Source Datasets stay original.

publishGui exports actual current component/widget/value/Plot bindings and marks
scientific Source editor/Analyze/Publish/Save as domain callback boundaries.
Importing that reusable design does not execute or duplicate those scientific
callbacks. describeGui requires the actual original Tk host; OPEN_REQUIRED is
not a synthetic substitute for a live interface declaration.

## Source-backed activation example

```tcl
set w [::GX::ReplicateViewer::open [dict create workspace_id new]]
set declaration [::GX::ReplicateViewer::describeGui]
```

Unexecuted host example, requiring actual Session/Tk/installed service. No real
analysis is implied until explicit user source/frame declaration and managed
preflight/submit complete. Native controls, cancellation/lifetime/reopen, genuine
scientific results and independent release verification remain separate gates.
