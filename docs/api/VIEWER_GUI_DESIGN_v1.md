# Declarative Viewer design and GUI laboratory

This additive Tcl/Tk facade belongs to `VIEWER_GUI_HOST_API_v1`. Discover its
operations with `viewerGuiHostApiInfo` and construction contracts with
`viewerGuiComponentCapabilities`. It composes existing UI Field, Configuration,
Native2D/Plot, Documentation, Workspace and History owners. It introduces no
scientific source registry, renderer, scheduler or cross-language widget API.

## Project and model

`viewerGuiDesignNew ?title?` returns an inert `gxtxt.viewer_design.v1` Tcl
dictionary. Fields are schema, title, module_id, provider_id, version, geometry,
requirements, components, handlers and origin. Optional `shell` records initial
inspector width and status text. Requirements map actual public
API IDs to supported integer versions. Each component has id, type, parent,
properties and layout. Parents precede their children; root slots are toolbar,
inspector, canvas, footer and menubar. Tabs contain tab pages and menus belong
to menubar. Unknown fields, duplicate IDs, incompatible parents, unavailable
capabilities and overlapping grid spans fail validation.

`viewerGuiDesignRead path` reads at most 4 MiB as data, never Tcl code.
`viewerGuiDesignSave path design` uses Resource Management's atomic byte writer.
Designs contain at most 1000 components. Grid properties are row, column,
rowspan, columnspan, weight, padding, sticky, minimum_width and minimum_height.
Indices/weights are bounded to 0–1000, spans are positive and minimum dimensions
are bounded to 2000 px. Splitters and tabs retain their native container layout.
Runtime default geometry is separate from the Designer's desktop geometry.
`manager pack` accepts native side/fill/expand/anchor/padding properties. A
container cannot mix grid and pack. Copy/reparent preserves minimum dimensions
and padding, adopts the destination manager, and allocates after occupied grid
spans. Packed siblings use Move up/down; direct cell swaps require grid.

`viewerGuiDesignModelCreate design`, `viewerGuiDesignModelEdit model operation
...` and `viewerGuiDesignModelNavigate model undo|redo` are functional operations.
Edits include add, property, layout, constraints, bind, remove, duplicate/paste
subtree, reparent, reorder, swap and metadata. Every result validates before
returning. Failure preserves the caller's model. Undo retains at most 50 design
snapshots and no scientific arrays. Handler contracts declare the exact
`{window action}` arguments and an explicit unbound/presentation/mutating effect.
An effect declaration alone never executes or authorizes a callback.

Dev108 preserves the component declaration list during `reparent`. Its one-based
positions are the restricted C++ SDK component identities. A parent may appear
later in that list: validation checks the complete ID map, container types and
acyclic dependencies; native composition and the Builder hierarchy derive their
parent-first construction order without changing the saved list. Moving an
existing control into a later container therefore requires no C++ renumbering.
Deep subtree copy/duplicate/remove follows dependencies, including children that
precede their parents. Duplicate appends new declarations; remove necessarily
removes indices and requires the author to review affected SDK references.
`reorder ID STEP` remains a signed sibling layout step, never a request for an
absolute SDK index. Packed/menu sibling order changes can change declaration
positions and must be reviewed; ordinary grid cell swaps change layout only.
Undo/Redo restores exact design snapshots. Missing/noncontainer/cyclic parents
fail before committing a model or constructing widgets. Existing parent-first
files retain their saved order and need no migration.

Notebook selections persist as logical child-tab IDs in the existing interface
state's `values` entry for each `tabs` component. Capture reads actual native
selection; restore accepts only a declared direct tab child. Legacy empty values
keep the native default. No widget paths or second presentation registry are
serialized. This preserves nested RC/AC/interpolation views across Workspace
save/reopen without scientific recomputation.
Input components may declare `change_action`; Bind creates its stable handler
contract. Return followed by FocusOut commits a changed value only once. Menus,
context menus and command toolbars select the same command catalog. Logical
Help/Workspace/History components use their existing footer/menu owners.

## Runtime and source boundary

`viewerGuiDesignCompose design window module provider ?preview|runtime|demo?
?handlers? ?context?` uses identical public constructors in Preview and installed
Viewers. Context accepts the existing workspace_id and an optional logical
command_catalog owned by the actual installed module. Its default is
`module.provider.design_commands`. Workspace/scientific ownership remains the
actual module. UI Field owns generic widgets, scrolling and geometry.

Preview returns `not_connected` for custom actions. Runtime binding records have
a command prefix and optional enabled prefix; a callback receives `(window,
action)` and may return a dictionary containing status. Fit/Zoom require an
actually bound public host. Source slots start empty. Use
`viewerGuiDesignSourceSet window component curveSourceRequest ?expectedSourceID?`
or `viewerGuiDesignPlotSet window component plotV4Spec` for explicit binding.
The optional Plot context `prepared_model 1` is for an already prepared public
Plot presentation snapshot. Scientific bindings retain source IDs and units;
diagnostic exports summarize models without copying scientific arrays.
Session changes block native input until the source is reopened.
No Plot Dataset implementation is changed by the facade. Native3D is available
through `NATIVE_3D_GUI_HOST_API_v2@2`, with independent child widget, scene,
camera, source generation, subscriptions and renderer worker per instance. The
legacy v1 singleton remains compatible. Native3D properties include dimensions,
projection, default camera triples, axes/orientation cube and an explicit RAM
`demo` flag. `viewerGuiDesignNative3DSet window component source` binds either
`{kind demo}` or `{kind scientific module M provider P}` through that public owner.
Actual ready/view_changed/selected/error/source_changed events retain native
provenance. See the v2 guide for bounds, picking and lifetime restrictions.

`viewerGuiDesignTemporarySceneSet window component native2d|plot|native3d`
explicitly mounts the matching B1 RAM display through its public owner. It clears
any previous scientific binding and records separate `demo_bindings`, never
canonical source IDs. Rebinding a canonical source clears its old demo marker.
Runtime Inspect reports DEMO_BOUND and the actual native receipt, instead of
claiming a scientific source or a stale protected Plot widget. Fit/Zoom actions
use the corresponding public temporary/native host; ordinary scientific source
slots continue to require their original explicit binding.

Demo composition rejects domain handlers, has no scientific Session token and
uses the existing host-owned inert Workspace/History/Help samples. The Dataset
selector receives explicit sample choices rather than querying canonical data.
The dynamic Component Gallery uses these exact constructors; see
[VIEWER_COMPONENT_DEMO_API_v1](VIEWER_COMPONENT_DEMO_API_v1.md).

`viewerGuiDesignValues window`, `viewerGuiDesignValueSet window id value` and
`viewerGuiDesignTableSet window id rows` provide public UI access. Tables are
read-only pages bounded to 1000 rows / 4 MiB. Dataset selectors consult the
canonical catalog when posted. Scientific Variable IDs and units remain with
the Dataset schema. Existing History retains UI edits and binding requests.
Workspace saves check Session plus document generation/revision/SHA; stale saves
fail. No new scientific authority is inferred from a graphical display.

## Import, handlers and package generation

`viewerGuiDesignImport module provider` reads a safe descriptor gui_design path
when present: FULL_DECLARATIVE is a representation status, not a tested
round-trip PASS. Legacy published manifests yield DECLARED_HOST_ONLY with
unrepresented inspector/domain boundaries. Missing declarations return CORE_GAP.
`viewerGuiManifestDescribe` reads published CORE declarations without walking
private widgets. A provider may declare a zero-argument gui_handler_command
factory. `viewerGuiDesignHandlerBindings module provider` activates that explicit
public factory only when requested; importing a design does not connect it.

`viewerGuiDesignGenerate project sourceDirectory outputDirectory callback`
uses bounded nonblocking Script Job transport to the existing Script Module
Builder's viewer-build profile. The tool invokes the actual CORE validator in
an isolated environment and emits an ordinary Standard Module/Viewer Provider
ZIP. Generated assets and API source maps are separate from handlers.tcl, whose
existing bytes are preserved. Packages are deterministic, refuse existing
ZIP/checksum destinations and use atomic promotion. The returned managed
request ID supports cancellation.
Designed packages declare `gui_roundtrip`. For those packages,
`viewerGuiDesignHandlerSource module provider` returns their bounded handwritten
handler file as bytes, without evaluating it. Generating an imported designed
Viewer seeds a missing local handler file from those installed bytes and then
preserves the local file on subsequent generation. The output remains a separate
package requiring explicit installation. Other imported Viewers require a new
module identity, keeping their domain implementation with its original owner.

## Diagnostics and finite tests

`viewerGuiRuntimeInspect window` reports actual mounts/properties, command
enablement/applicability/shortcuts, geometry/theme/scaling, source readiness,
native metrics, focus/grab, scoped timers/subscriptions and correlated redacted
events. Global request counts are explicitly un-attributed and do not prove
per-Viewer execution. Curve Source metrics count actual display requests,
paints, navigation and last paint duration; they do not claim complete OS I/O.

`viewerGuiTraceSubscribe window callback` / `viewerGuiTraceUnsubscribe id`
observe CORE hooks. Traces retain at most 2000 records.
`viewerGuiRecordingStart window ?filter?` / `viewerGuiRecordingStop id`
capture normalized command/result actions with component/event glob filters.
Field values and scientific payloads are redacted. Scenarios are inert
gxtxt.viewer_gui_scenario.v1 dictionaries with at most 200 actions. The Designer
allows editing, Save/Open and rerun. Supported actions are invoke, resize,
select, checkpoint and dialog_absent; state-ready waits are 50–10000 ms.

`viewerGuiReplayStart window scenario callback ?options?` queues actual Tk
pointer events on mapped declared buttons and waits for correlated results.
It does not claim OS-level input; independent acceptance uses the official X11
harness. Timeout is FAIL. Runtime replay requires an explicit fixture_root,
its .gxtxt-gui-test-fixture marker, the current Session below that root and
permitted_commands. Safe Preview never connects custom scientific callbacks.
`viewerGuiReplayCancel id` cancels a suite/replay between cases.

`viewerGuiTestPlan window ?families?` exposes exact cases/count before
`viewerGuiTestsStart window plan callback`. Families are structure, negative,
lifecycle and scientific binding readiness. Mount/readiness tests do not claim
navigation or scientific correctness. Selected cases can be rerun under a new
run ID; completed in-memory runs are bounded to 20. Independent scenario and
fixture tests supply additional behavior evidence.

`viewerGuiDiagnosticExport report newJSONPath callback` writes versioned JSON
through the managed worker and refuses an existing destination. Opaque
observations may remain inert Tcl strings, disclosed in format_notes. Reports
identify actual environment, assertions, status and per-case coverage scope;
an aggregate passing count never implies complete API/scientific coverage.

The Analyzers panel offers a finite two-second responsiveness measurement.
`viewerGuiMonitorStart window duration_ms callback ?interval_ms?` samples real Tk
callback intervals, native-owner paint/display counters, and Linux process RSS/
I/O counters for 100–10000 ms. `viewerGuiMonitorCancel id` and Viewer destruction
stop its timer. Process-wide counters are explicitly labeled and cannot prove
per-Viewer memory/I/O or scientific execution. Runtime inspection also correlates
synchronous command callback duration and flags duplicate/reentrant/incomplete
command records; scientific Job and later native paint duration remain separate.

Designed interfaces keep shortcut preferences under their own design identity.
Removed command IDs remain saved but unbound, listed as obsolete shortcut IDs;
Configuration editing still validates new overrides strictly. Importing a
second design does not apply the first design's shortcut map.

Native2D Curve Source metrics also expose `last_input_to_frame_us` and
`coalesced_navigation`: time from the first pending native navigation input to
publication of its actual rendered canvas frame, and the number of navigation
operations coalesced into it. This includes native paint work and event-loop
waiting; it is not display-hardware scanout latency or scientific Job duration.

An imported handler's optional `available` snapshot is preserved in both Preview
and generated runtime. It declares initial availability, not a scientific handler
implementation. Unbound domain Undo/Redo returns `not_connected` if there is no
local GUI-history step to navigate; it never fabricates the original domain
history. Authors connecting their domain backend must deliberately revise the
snapshot/enablement contract as that backend's state changes.

## Native command-container project icons (dev108)

`command_toolbar`, `menu` and `context_menu` accept optional `command_icons`.
Each key is an existing ID in that component's `actions`; each value contains
only `icon`, state-resource IDs and the existing typed presentation fields.
The ordinary Icon Library Command target selector edits one binding transaction.
No opaque JSON entry is required. Rename updates nested references; removing a
referenced asset is rejected; Remove binding, Undo/Redo, Save/Open and generated
Module resources use the same catalog/model owners. The existing Configuration
command owner still decides enablement, dispatch and shortcuts.

Toolbar controls support normal/disabled/hover and declared selected resources
where the actual native control has selected semantics. Plain command buttons
have no selection state. Native command menus support normal/disabled image,
image+text/text and placement; custom spacing, hover/selected image variants and
icon-only tooltips are explicitly unavailable. Assign rejects unsupported
requests and keeps its error visible in Icon Library. Menu Preview is an actual
native menu. Older designs without command_icons retain their appearance.

## Declared scientific probe references (dev108)

The existing Scientific section accepts `scientific_probe_diagram`,
`scientific_probe_plot` and `scientific_probe_mode` as typed identifier properties.
They connect an electrical Native2D diagram, canonical Plot and voltage/current
choice through the existing Host owner. Supply all three atomically using the
ordinary Builder properties operation. Exact registered-provider mapping,
completed-publication/source guards and unavailable-current behavior are in
`VIEWER_GUI_HOST_API_v1`; the restricted Development contract lists the existing
required grants. No guessed net names, separate graph model or raw endpoint
access is needed.

## Existing navigation command IDs

The Host already implements the reserved presentation commands `fit`, `zoom_in`
and `zoom_out`. Declare the corresponding ordinary handler contract (arguments
`window action`, effect `presentation`) and an action/menu/toolbar using that
exact command ID. A canonical Plot binding enables them; the Host delegates
fit/zoom to public Plot widgetView before authored C++ dispatch. No `plot_view`
C++ method is needed for these commands. They operate on the Viewer's supported
bound display components, so use a separate intended Viewer context if several
different bound canvases should not navigate together. Existing diagram commands
with domain-specific IDs retain their separate callback behavior. Native Plot
wheel zoom, middle-button pan and double-click fit also remain available to human
developers; approved automated gestures have their own bounded testing contract.
