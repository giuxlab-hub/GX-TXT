# Viewer GUI Integration Manifest v1

This public **host-only** Tcl API composes
existing GUI authorities. It has no Script Bridge widget API, second registry,
scientific state, renderer, command model, execution scheduler or Workspace format.
Discover with `::GX::viewerGuiHostApiInfo` and require through the existing
Workbench Extension API's public API resolver. The first complete consumer is
`viewer.replicate_curve_analysis`; Worksheet consumes its shared command adapter.

`viewerGuiManifestValidate manifest` checks the schema, installed Viewer identity,
existing command IDs and supported canvas owner. `viewerGuiCompose manifest`
returns named `toolbar`, `inspector`, `canvas`, `footer`, `status`, `menus` slots.
`viewerGuiActionsMount window frame ?commandIds?` mounts an existing command catalog.
Callbacks belong to the Viewer and execute under its existing Session guard.

Required manifest fields:

| Field | Contract |
| --- | --- |
| schema | `gxtxt.viewer_gui_manifest.v1` |
| viewer_id | Registered module of kind `viewer` |
| provider_id | Existing Viewer/Workspace provider identity |
| window, title | Tcl widget path and English title |
| handlers | Existing Viewer command IDs → `command`, optional `enabled`/`applicable` callbacks |

Optional fields are `geometry`, `guard`, `workspace`, `history`, `history_record`,
`canvas`, `canvas_mount`, `inspector_width`, `toolbar_actions`, `menus` and
`context_actions`. Unknown fields fail. `canvas` declares `api_id` from
`PLOT_DATASET_API_v4`, `NATIVE2D_VIEWPORT_HOST_v1`, or
`NATIVE_3D_GUI_HOST_API_v1`. This declaration chooses an owner, not a new renderer.
The Plot module is activated through public module activation. Other owners are
mounted by their existing host callback via `canvas_mount canvasSlot`; a declaration
alone does not instantiate a scientific scene. Workspace and History callbacks
use their existing host contracts unchanged. Saved History may be supplied via
`history_record`. No job runs as a consequence of composition.

`menus` is an ordered list of `{label English-title actions {command-id - ...}}`
descriptors; `-` separates groups. `toolbar_actions` and `context_actions` select
registered commands. All menu/toolbar/shortcut enablement uses Viewer Commands.
`viewerGuiContextMount window widget` attaches the composed context menu to a
scientific host created after composition. `viewerGuiSelectionAttach window
widget ?event?` refreshes both menus and toolbar when the consumer's native
selection changes; `viewerGuiActionsRefresh window` handles domain state changes.
`inspector_width` is the initial splitter position (200–600 pixels); users can
drag the normal pane sash without rebuilding scientific geometry.

Dialog composition uses UI Field's `uiFieldDialogCreate`,
`uiFieldDialogPresent` and `uiFieldDialogClose`. Focus and optional grabs wait
for actual mapping and release on Unmap. This is GUI-only lifecycle state and
does not add a persistent authority or Script Bridge widget protocol.

| Responsibility | Sole existing owner / additive extension |
| --- | --- |
| Generic regions, scrollable inspector | UI Field: `uiFieldViewerShellCreate` |
| Actions, key configuration, applicability, enablement | Configuration / ViewerCommands; one catalog and consumer selection |
| Toolbar placement | UI Field controls layout; ViewerCommands widget adapter |
| Workspace menu/lifecycle | Session Workspace Viewer Host |
| History/Description and Undo/Redo | Scientific Recipe History host |
| Contained selector | UI Field: `uiFieldSelectorWithinViewer` |
| Context menu placement | UI Menu: `uiMenuPopup` |
| Scientific canvas | Public Native2D, Native3D or Plot v4 host |
| Help | Documentation Browser |

`uiFieldSelectorWithinViewer combobox viewer` preserves the combobox's values,
textvariable and `<<ComboboxSelected>>` semantics. It composes a native listbox
and scrollbar inside the Viewer, prefers available space above/below, clamps to
the client area and adjusts on resize. Enter/pointer commits; Escape dismisses;
Tab restores normal traversal. Opening does not select a History action. It uses
no global ttk private popdown modifications. Destroy releases bindings/grab.
Debian local X11 acceptance is recorded; Windows, remote X11 and alternate DPI/
theme combinations require their own platform acceptance and are not claimed PASS.

Description/History strip selection is a presentation operation. It can display
the retained window's timeline while the scientific owner is busy or its Session
has changed. A stale window updates only its local strip; it cannot write strip
preferences into another Session. Undo/Redo, History navigation, restoration,
branching and scientific changes retain the existing Session and owner guards.

Shared Documentation Browser Help attachment reuses an existing Help menu and
keeps it last in the existing native menubar or legacy menubutton row. It adds
missing Manual/About actions without another full-width row. About reads the
current installed descriptor. Frozen Digitalizer attachment is unchanged, and
legacy module-local Help adapters retain their existing ownership.

Dev104 adds optional `command_catalog` (a logical catalog with the same installed
owner), `toolbar_mode` (`actions` or `declarative`) and boolean `help` (default
true). Declarative mode mounts only deliberately selected components. Existing
consumers retain their defaults. The additive design/component facade, inert
project format, generation and finite laboratory are documented in
[Viewer GUI design](VIEWER_GUI_DESIGN_v1.md).


## Canonical Plot axis presentation and bounded inspection (dev108; GAP021)

A declared Plot form may optionally reference `plot_x_scale` and `plot_y_scale`:
existing choice/combobox IDs whose values are exactly `linear` or `log`.
`viewerGuiDesignPlotBind window plotComponent form` writes the existing public
PlotSpec `panels.axes.x.scale` and `panels.axes.y_left.scale`; absent references
retain compatible defaults. Canonical Variables, values and units do not change.
No authored logarithm or numerical transform is involved. Existing public Plot
validation rejects invalid scale domains; configuring an already bound widget
preserves its previous valid frame/spec/binding on model failure. Controls remain
available for correction. Successful bindings and native view domains persist
through the existing Workspace capture/restore owner.

`viewerGuiDesignPlotReceipt window plotComponent` returns bounded public native
`widgetReceipt` plus `width height mapped` for the declared Plot. Axis limits,
scale, direction, plot rectangle and tick device positions are disposable native
presentation metadata, not substitute scientific samples. The existing source-
bound Development GUI-test status projects these under `plot_receipts.COMPONENT`.
Pixel rectangles/ticks can change on resize/cold reopen; canonical binding and
scientific axis domains remain authoritative. No raw widget/path or C++ array
grant is added. Both existing `plot_discover` and `plot_bind` SDK methods retain
their signatures and explicit public Plot capability grants.

The existing canonical Plot form renders a one-row numeric observation with the
public Plot `line_marker`/circle representation; multirow waveforms retain their
line representation. This makes an operating point visible without inventing
another sample, interpolation, numerical transformation or renderer. Native
point hits still resolve the exact original Dataset row and units.

## Optional physical sweep in the existing Scientific section (dev108)

The same Scientific Discover/Prepare/Submit/Status/Cancel/Reconnect/Log/Import
methods accept an optional typed physical-sweep profile. Its section declares
`scientific_sweep_axes` (one or two named dictionaries),
`scientific_sweep_enabled` (toggle/checkbutton ID), `scientific_sweep_case`
(choice/combobox ID), `scientific_sweep_workers` (integer field/entry ID), and
`scientific_sweep_fail_fast` (toggle/checkbutton ID). Each axis has exactly
`component start stop count unit`: a canonical component-ID choice, two finite
numeric fields, explicit integer count1..4 and read-only status/label unit field.
Declare `NUMERIC_API_v1@1` and `PARALLEL_EXECUTION_API_v1@1` requirements.
Axis names are stable lowercase identifiers matching `[a-z][a-z0-9_]{0,31}`;
uppercase `A`/`B` are rejected before any model commit. They are dictionary keys,
distinct from component/control IDs. The approved Builder JSON representation
is nested dictionaries (no Tcl strings or JSON embedded in strings):

```json
{"operation":"properties","arguments":["simulation_form",{
  "scientific_sweep_axes":{
    "a":{"component":"sweep_a_component","start":"sweep_a_start","stop":"sweep_a_stop","count":"sweep_a_count","unit":"sweep_a_unit"},
    "b":{"component":"sweep_b_component","start":"sweep_b_start","stop":"sweep_b_stop","count":"sweep_b_count","unit":"sweep_b_unit"}
  },
  "scientific_sweep_enabled":"sweep_enabled",
  "scientific_sweep_case":"sweep_case",
  "scientific_sweep_workers":"sweep_workers",
  "scientific_sweep_fail_fast":"sweep_fail_fast"
}]}
```

All referenced controls must already be declared with the types above. A rejected
name, extra/missing axis field or incompatible control preserves the prior design.

Discover reads actual circuit R/C/L and independent V/I components and canonical
catalog SI units. Prepare requires distinct existing components, evaluates each
grid through public Numeric `uniform_grid`, and forms at most16 explicit cases.
Bounds are in the displayed catalog SI unit; no private conversion/parser or
author vector calculation occurs. Existing CircuitSweepPrepare validates every
physical case before admission and guards exact source generation/revision/SHA.
Changes to source, axes, analysis, destination or admission controls require a
new preparation. Disabling sweep preserves legacy single-run behavior.

Submit uses existing CircuitSweepSubmit and ParallelExecutionExecute. Its
in-process callback coordinator serializes admissions; ordinary Script Job
supervision owns actual scientific concurrency and resource policy. Admission
completion is distinct from simulation completion. The GUI records only child
Job references/case associations in existing Viewer domain state, polls real
states, and reports completed/expected counts and partial admission failures.
It never invents a replacement Job or retries an uncertain remote submission.
Select an admitted case before Read Log or Publish Dataset; provenance retains
its exact physical parameters, case ID, original Job and source identity.
Cancel requests cancellation of all admitted nonterminal children. Reconnect
reads those same Jobs; per-case errors retain prior publications and Plot.
Workspace saves guarded child associations, not a new Job journal or scheduler.
Restore displays RESTORED_SWEEP (or RESTORED_JOB for one saved Job), original IDs
and explicitly last-observed states, without computation/submission or automatic
network calls. Reconnect fetches actual current states from the same Job owners.
Discover refreshes declared component/destination choices and selected canonical
SI labels. When a Job/campaign already exists, it preserves that status/log,
including RESTORED_JOB/RESTORED_SWEEP during compiled Viewer initialization.
Full protocol status, including remote node-local resource provenance, is not
embedded as client-Session resource authority in Workspace; canonical Job and
Dataset provenance remains available from its original owner.

Restricted authoring additionally requires explicit Scientific grants
`circuit_sweep_prepare circuit_sweep_submit`, Numeric `uniform_grid` and Parallel
`parallelExecutionExecute`. Only declared sweep forms may consume them; no
generic C++ Parallel callback/process API or array return is exposed. Existing
eight scientific SDK methods remain unchanged. This extension is under targeted
scientific/GUI validation; its implementation alone is not an acceptance PASS.

## Pointwise Numeric form profiles (dev108)

The same declared section and five Numeric methods support optional
`numeric_kind`: `expression` (unchanged default), `interpolation`, or
`complex_projection`. Common references are `numeric_dataset`, `numeric_start`,
`numeric_count`, `numeric_x`, `numeric_status` and `numeric_report`: typed existing
Dataset/field/choice/status/log component IDs, never raw widgets.

Interpolation additionally declares `numeric_y`, `numeric_query_dataset`,
`numeric_query_x`, `numeric_query_start`, `numeric_query_count`, `numeric_method`
and `numeric_extrapolation`. Methods are `linear pchip`; extrapolation is `error`.
Discovery reads both Dataset catalogs, preserving explicit row counts. Source
and query ranges are independent. Public Numeric converts query X to source X
units; publication preserves original query X values/units and source Y units.

Complex projection additionally declares `numeric_real`, `numeric_imaginary`
and `numeric_projection` (`magnitude phase_rad phase_deg`). Both vectors share
explicit rows; Numeric converts compatible imaginary units. Published X is the
selected canonical source X, normally frequency, with original units. Values
and phase labels come from the existing complex operation.

The existing Discover/Evaluate/Statistics/Compare/Publish methods are unchanged.
Optional statistics/comparison controls retain their contracts. Evaluation
persists immutable `gxtxt.numeric_pointwise.v1@1` Documents using the existing
managed vector; expression Documents remain compatible. All Dataset revisions
and optional scientific source guards survive Workspace/History capture.
Restore validates result identity and renders stored results without a Numeric
call; a saved statistical result takes precedence in the report. Publication
retains the complete source request/revisions, result identity and active
statistical-result identity. Failure retains previous result/publication IDs.
Plot binding remains explicit through the existing Plot form.

### AC schematic probe selection (dev108; GAP040)

The existing `viewerGuiDesignScientificProbe` keeps DC/transient real-Variable
behavior. For an actual completed, source-identical AC publication it resolves
the provider's canonical `_real/_imag` pair and `frequency` Variable instead of
looking for a nonexistent unsplit voltage/current. Frequency must be Hz, the
pair V or A, with identical one-dimensional canonical shapes. Original source,
Job/case, Dataset provenance, topology and unavailable/ground guards still apply.

An AC probe populates a declared existing Numeric `complex_projection` form:
`numeric_dataset`, `numeric_x=frequency`, `numeric_real`, `numeric_imaginary`.
It preserves explicit `numeric_start/count/projection`, the previous valid Plot
and every immutable computed result. Status is `AC_SOURCE_SELECTED` with the
original Job, Dataset and exact pair. It performs **no calculation or automatic
publication**. The developer/user explicitly chooses Evaluate through public
Numeric, Publish and Bind; magnitude keeps V/A, phase uses rad/deg. An old
computed result remains identified by its own captured source until Evaluate.

When exactly one compatible complex form exists it is selected automatically.
With multiple forms declare optional typed identifier
`scientific_probe_ac_form` on the Scientific section. It must reference a
`complex_projection` section for the same `numeric_source` diagram if specified;
incomplete, foreign or wrong-kind references reject at model validation.
Ambiguous/missing compatible forms fail explicitly without changing selections.
No new C++ method, numerical grant, raw endpoint reader or renderer is exposed.

The additive AC receipt contains `numeric_form`, `real_variable_id`,
`imaginary_variable_id`, `frequency_variable_id`, physical `unit`, original
`dataset_id/job_id/source_guard`, `representation=canonical_split_complex`,
`explicit_evaluate_required=1`, `computation=none`, `publication=none`.
Selection is one normal History step; Workspace retains the existing typed form
values and old result references, without evaluation/submission on restore.
`viewerGuiHostApiInfo` advertises the supported probe analyses and explicit AC
form-selection policy. Builder component capabilities expose the optional
reference through their existing property inspector.

## Declared scientific forms (dev108)

Design reparenting preserves declaration positions used by the restricted SDK;
later-declared parents are composed in derived dependency order. See the
[design identity contract](VIEWER_GUI_DESIGN_v1.md) before structural edits.

The existing section component can declare `scientific_provider`,
`scientific_parameters`, `scientific_destination`, `scientific_status` and
`scientific_log`. For the currently admitted canonical circuit source use
`core.ngspice.circuit`; parameter mapping is provider parameter to existing scalar
component ID, destination is a choice/combobox, status is label/status, and log is
read-only log. All references must exist. Create the ordinary section and controls
first, then apply the complete profile through one existing model `properties`
transaction. Requirement SCIENTIFIC_EXECUTION_API_v1@1 is explicit. Scientific,
Script Job and Parallel Execution service requirements now negotiate through their
actual API-info owners, rather than pretending each service is a widget type.

Public methods `viewerGuiDesignScientificDiscover window form`,
`viewerGuiDesignScientificPrepare window diagram form`, and
`viewerGuiDesignScientificSubmit|Status|Cancel|Reconnect|Log window form` reuse
Scientific Execution v1 and existing registered destinations. Preparation displays
reviewable netlist/parameters/source identity, remains ephemeral and is discarded
when replaced or its Viewer closes. Submitted Job references and source guards
live in the existing Viewer domain state and Workspace format. Bounded polling
updates actual states; unavailable destinations remain explicit. Closing detaches
its view and does not cancel the durable Job.

`viewerGuiDesignScientificImport window form dataset_selector` adopts the completed
waveform through existing bounded Scientific table import and Dataset Publication
v2. Source guards are rechecked on every page. Published canonical ID enters the
existing Dataset selector and domain state; original Job/provider/circuit/typed
parameters remain provenance. Read-only text and typed fields still belong to UI
Field, diagrams to Native2D/Interactive Document, and publication to Dataset owners.
No parallel scheduler, remote transport, Dataset registry or numerical service is
introduced. Plot and additional restricted scientific capabilities remain subject
to their own approved contracts and evidence.


## Canonical Plot selection and probing (dev108)

A complete Scientific section may additionally declare all three identifier
references `scientific_probe_diagram`, `scientific_probe_plot` and
`scientific_probe_mode`. They name the existing electrical Native2D diagram,
the canonical Plot component with its `plot_form`, and a choice/combobox whose
choices are exactly `voltage current`. These are ordinary Builder properties;
no private endpoint access or new C++ include is needed. A native Probe click
on a real terminal/junction invokes the existing Host's
`viewerGuiDesignScientificProbe window scientific_form endpoint`.

The bridge resolves the currently selected completed Job/sweep case and its
published Dataset. It verifies the diagram's generation/revision/SHA, exact
Dataset/Job/provider/parameter provenance and the registered provider's current
`CircuitInspect` mapping. Voltage uses the provider's typed probe for that exact
mapped node; current uses its actual independent-voltage-source branch probe.
Canonical Variable Schema units must be V or A respectively. No name/order or
screen-coordinate inference, arithmetic, simulation, remote status request or
new Dataset is involved. Unavailable device currents, ground-reference voltage,
missing variables, foreign publication and stale source are explicit errors;
the previous waveform selection and frame remain intact. AC split-complex data
require an explicit public Numeric projection; this bridge does not invent an
automatic magnitude or phase calculation.

Restricted Development validation requires the already scoped grants
`SCIENTIFIC_EXECUTION_API_v1.circuit_prepare`,
`NATIVE2D_VIEWPORT_HOST_v1.diagram_command` and
`PLOT_DATASET_API_v4.widgetCreate`. The declared bridge reuses those existing
facilities and the current SDK's diagram-tool and Scientific/Plot operations;
it adds no raw endpoint/vector accessor or broader runtime capability. Normal
Workspace state retains canonical source/Job/Dataset/variable/mode identities,
and ordinary History captures the accepted typed selection and Plot together.
This extension remains under real GUI validation until its receipts are linked.

A normal section can declare `plot_dataset` (Dataset selector ID), `plot_x` and
`plot_y` (numeric variable choice/combobox IDs), and optional `plot_probe`
(read-only text ID). Requirement PLOT_DATASET_API_v4@4 is explicit. Construct
controls first, apply this complete profile atomically, then set the Plot
component `plot_form` to that section ID. No independent waveform store is used.

`viewerGuiDesignPlotDiscover window form` projects actual Variable Schema v3 IDs
into the existing choice owner. `viewerGuiDesignPlotBind window plot form`
constructs a public PlotSpec with canonical Dataset/variable IDs and invokes the
existing Plot v4 binding; physical axes/units and display reduction belong to
Plot/Curve Source. Dataset values are never copied into a private graph.
An accepted binding change, including Undo/Redo or saved-state restoration,
clears the previous source-point readout. The prior point is not presented as
belonging to a different restored trace; select an actual computed point again.
An optional fourth dictionary `{y_variable_id VARIABLE_ID}` requests a canonical
Y selection already admitted by the form's actual discovered choices. Binding
validates before committing selection, frame and History. Other dictionary keys
are rejected; existing three-argument calls are unchanged.

`viewerGuiDesignPlotProbe window plot device_x device_y` obtains the actual native
hit. For an exact source point it resolves its canonical series and reads only
that zero-based source row via public Table Stream. Receipt retains Dataset,
source row/variable IDs, original values/units and native display hit. Pointer
release automatically sends this receipt to the declared read-only probe control
and existing trace. A chart/axis hit is distinguished from a source point. The
existing Workspace capture preserves the PlotSpec, visibility and axes and
restoration remounts the current live probe binding.
# Declared Numeric forms (dev108, compatible v1 addition)

A `section` may declare `numeric_expression` and the following existing control
IDs: `numeric_dataset` (Dataset selector), `numeric_expression` (string field or
entry), `numeric_start`, `numeric_count` (integer fields), `numeric_output_unit`
(unit field/choice), `numeric_x` (canonical Variable choice), `numeric_status`
(status/label), and `numeric_report` (log). `numeric_variables` maps1..32 safe
symbols to Variable choice IDs. Optional `numeric_parameters` maps symbols to
`{value CONTROL_ID unit CONTROL_ID}`. Declare `NUMERIC_API_v1@1` in requirements.
All controls are ordinary Builder components; bindings contain IDs, never source
arrays, filesystem paths, code, private writer handles or arbitrary commands.

`viewerGuiDesignNumericDiscover window form` discovers actual numeric1D Schema
v3 Variables, units and row counts. It updates only choice options, preserving
an explicit count. `viewerGuiDesignNumericEvaluate window form` calls public
`NumericAPIv1::expressionDatasetCaptured`, with explicit start/count1..65536,
output units, Dataset bindings and scalar parameters. Cross-Dataset alignment
is deliberately not inferred: each form binds one Dataset. Dataset revisions,
Session lifetime and current form are checked around calculation. The optional
`numeric_source` is a declared canonical Native2D diagram whose Document
generation/revision/SHA is also guarded. A generic Numeric Viewer requires no
dummy diagram.

The existing Interactive Document owner stores each successful evaluation as
`gxtxt.numeric_expression.v1@1`, owned by this Viewer module/provider. Its payload
is `{state evaluated request REQUEST captured CAPTURE_RECEIPT}`. This reuses the
existing Numeric expression receipt/schema; the new persistence envelope adds
the reviewed request, source revisions and existing Managed Resource references.
It is not a new service, registry, Dataset format or numerical implementation.
After its initial atomic update an evaluation Document is immutable to this
form. The ordinary Viewer `domain_state.numeric_results.FORM` stores only
`document_id/generation/revision/sha256`. Workspace/History snapshots therefore
retain earlier successful evaluations when a later evaluation succeeds. Failed
evaluation deletes only its new uncommitted candidate Document through the
existing owner and preserves the previous result. Session changes invalidate
runtime handles; saved result identities remain Session-owned.

Saved Numeric results may be reopened after ordinary Portable Session import.
The existing Dataset authority revalidates the complete persisted Dataset ID,
canonical record and metadata SHA; only the carrier Session directory may
differ. The result's module/provider, Document generation/revision/SHA and
scientific source Document guard must still match. Restore neither rewrites the
immutable result nor recomputes its vector. Subsequent explicit statistics,
comparison or publication use a temporary request bound to the current Session
and retain strict current-token checks throughout the operation. A changed
Dataset record, metadata, source or result is rejected. Active computations and
publication CAS checks never accept a foreign Session token. No new public API,
resource registry or persistence schema is introduced by this correction.

`viewerGuiDesignNumericStatistics window form` requires `numeric_statistic`, a
choice of actual catalog IDs `array_reduce.rms`, `array_reduce.minimum`,
`array_reduce.maximum`, or `statistics`. It invokes public `callOperationCaptured`
on the existing managed vector and renders validated Statistical Result Semantics
fields, including units and unavailable reasons. Pointwise expression vectors
have no fabricated statistical profile. The full validated statistical result is persisted as an immutable existing
`gxtxt.statistical_result.v1@1` Interactive Document, owned by this Viewer, without
reducing again. It retains original Numeric request, result Document/SHA, actual
operation and comparison Variable/relative floor provenance. The existing Viewer
domain state stores only its guarded identity under `numeric_statistics.FORM`.
Workspace/History restore renders that exact validated stored result without a
provider call. A successful new evaluation clears only the active statistical
reference; earlier Documents remain available to their saved Workspace/History.
The trusted response additionally returns `statistics_document`; no new C++
capability or raw statistical arrays are exposed.

`viewerGuiDesignNumericCompare window form` requires both `numeric_observed`
(Variable choice) and `numeric_relative_floor` (numeric field). It captures the
observed Variable over the result's exact original rows/units, calls eligible
public `residual_metrics` once, and interprets only the public Statistics result.
The stored reference's request is authoritative even if controls later change.

`viewerGuiDesignNumericPublish window form datasetSelector` explicitly publishes
the selected successful result through Dataset Publication v2. Actual X rows
come from Table Stream v3 at exactly the captured start/count; value bytes come
from bounded Managed Resource pages. No scientific calculation occurs in Tcl.
The canonical `x/value` Variables retain units and original request, parameters,
source revision and result SHA in structured metadata. Guards are rechecked
before every page and final commit. Failed publication aborts its writer and
retains previous results.

For any receipt/request containing literal line breaks, its metadata value is
the existing Dataset UTF-8/base64 encoding and a companion `KEY.encoding` is
`base64-utf8`. Other values retain their original plain Tcl dictionary format.
Decode before interpreting; all bytes/provenance are preserved within the
portable one-field-per-line metadata contract.
Publication does not rerun or relabel a stored result
using changed controls. Use the existing Plot form to discover/bind this Dataset.

Separate interpolation/AC complex presentation/sweep controls and
separate-author installed GUI acceptance remain additional
requirements; these five methods alone do not close GAP004/005.
# Shared original icon discovery (dev108; GAP035)

`viewerGuiIconCatalog` is a read-only extension of the existing icon resource
owner. It returns `gxtxt.viewer_shared_icons.v1`, with `icons` indexed by stable
source ID and `count`. Each entry contains `id`, `title`, `category`, `license`,
`path`, `sha256`, `source_format`, `width` and `height`. The distributed bounded
manifest refers only to ordinary PNG/safe-SVG files directly in the fixed CORE
icon directory; malformed/duplicate IDs, traversal, symlinks, hard links,
oversize/missing assets and unsafe SVG content reject the catalog. There are no
caller paths or general filesystem enumeration. Reading it performs no raster
conversion, project edit, History navigation, Job or scientific computation.

Builder's existing **Shared** file chooser and restricted `builder icon catalog`
consume that same catalog. Shared selections are checked against the returned
path/SHA/provenance before ordinary image admission. Existing Import, owned
project catalog, embedded source/PNG bytes and normal Module packaging remain
the owners; this adds no asset registry or renderer. The original library now
also includes selection, remaining electrical devices/tools, Undo/Redo and
Fit/Zoom actions under its existing GPL-3.0-or-later provenance.

GAP036 extends the same safe-SVG normalization for inherited paint. The admitted
fill/stroke, width/cap/join/rule and paint-opacity attributes are materialized on
shapes and removed from nonpainting svg/g containers to avoid decoder loss or
double opacity. Group opacity and transforms remain decoder-owned. Original
source bytes/SHA and persisted-resource behavior are unchanged; reimport existing
blank resources explicitly. Group-versus-explicit stroke, nested override,
fill-opacity and transform fixtures must render byte-identical PNGs, while
explicit zero stroke opacity remains invisible. No path interpreter is added.

# SVG stroke admission correction (dev108; GAP016)

The existing bounded icon import uses the configured ImageMagick owner. The
installed MSVG decoder was independently shown to retain zero stroke opacity
after `none`, producing identical transparent PNGs for distinct original R/C/G
paths. Admission now serializes the already allowlisted SVG with inherited
`stroke-opacity` made explicit after other attributes. It preserves root/child
overrides, including intentional zero opacity, and original source bytes/SHA.
This is normalization of an existing accepted attribute, not a path interpreter,
new renderer, SVG engine, asset registry or external decoder dependency.

Already persisted PNG bytes are not silently changed during rendering. Reimport
through existing `icon_import`/`put` with the same logical ID to replace an
affected owned resource, preserving component command IDs and bindings. Historical
packages remain immutable. `icon-stroke01` verifies all11 visible original icons,
distinct electrical renders and inherited/explicit-zero fixtures; real Debian
`gui_history01/icons_native_state_preview.png` shows the actual corrected resistor
in the shared Icon Library, normal and disabled native preview. Separate author
reimported its7 referenced source assets through Builder in1.4.0; installed GUI
appearance remains a distinct required acceptance step.

### Persistent canonical source cursors (dev108, GAP028)

`viewerGuiDesignPlotCursor window plot device_x device_y` uses the same public native hit and canonical one-row table read as `viewerGuiDesignPlotProbe`. An actual source-row hit adds two existing PlotSpec `reference_line` annotations at the native displayed X/Y coordinates, on the selected series' actual left/right axis. No vector processing or scientific calculation is performed. The annotations use reserved IDs `__gx_source_cursor_x` and `__gx_source_cursor_y`; unrelated annotations/series/panels remain intact. The existing Plot renderer draws them, with no alternate overlay/graph model.

Native release on a real computed point in a declared Plot form selects this persistent crosshair and exact source-row/unit readout. The current view is preserved. Wheel zoom, middle-button pan, Fit and resize retain canonical reference annotations. `viewerGuiDesignPlotCursorClear window plot` removes only those two reserved annotations; native Escape on the focused Plot performs the same clear. Normal Dataset/variable Bind clears the old source cursor as part of its new specification. An unavailable/non-source hit leaves the cursor unchanged. A valid edit is one ordinary History step; the canonical Plot binding stores it through Save/reopen/Undo/Redo. Restore deliberately clears stale point text until a new actual source point is selected. Existing three-argument Plot Bind and read-only Plot Probe remain compatible; restricted authors need no new SDK operation or scientific grant.

### Declared checked pane visibility (dev108, GAP029)

A `toggle` or native `checkbutton` can declare `component_visibility TARGET_ID` with an explicit boolean `default`. It has no authored `change_action`: the existing host performs this presentation binding. An `action` can declare the same property with its existing distinct presentation handler. A `menu`, `context_menu` or `command_toolbar` can declare `visibility_commands {COMMAND_ID TARGET_ID ...}`; each ID must occur in its own actions and declare `effect presentation`. A command has one consistent target, cannot override reserved undo/redo/fit/zoom, and cannot target a foreign/undeclared component or the command/Workspace/History/Help surfaces. No widget paths or script callbacks are accepted.

Example through normal Builder properties: a panel `source_panel`, toggle properties `{label {Show source} default 1 component_visibility source_panel}`, and menu properties `{label View actions {view_source} visibility_commands {view_source source_panel}}`, with `view_source {arguments {window action} effect presentation label {Source pane}}`. Boolean controls and native checked menu rows remain synchronized. The same command can appear on multiple declared command surfaces. Ordinary commands/icons retain their existing behavior.

`viewerGuiDesignComponentVisible window component boolean` reuses the existing grid/pack/notebook/split-pane owners, retaining widgets, native handles, bindings and source authority. Hiding moves focus out of hidden content; showing restores the retained content/order without stealing focus. `viewerGuiDesignComponentVisibleGet window component` returns declared presentation visibility, independent of whether an unselected notebook page happens to be mapped. Notebook tab hiding/showing and ttk split-pane membership are supported; no component is destroyed/recreated. The host saves only canonical component visibility and values in the existing Workspace/History. Each accepted menu/action or boolean input records one ordinary History step; programmatic restoration synchronizes field baselines without an authored callback. Workspace restore respects a hidden selected tab. Boolean defaults initialize a new presentation; saved visibility wins on restoration.

The normal Module exporters require dev108 for these declarations even without icons. This is a compatible extension of existing GUI Host/Builder/Configuration/UI Field contracts: no C++ SDK method, runtime grant, scientific calculation, alternate layout framework or second Workspace registry is introduced.

### Separate guarded source/netlist pane (dev108, GAP029)

A circuit Scientific `section` can declare all three references: `scientific_netlist` (a separate read-only `log`, distinct from scientific_log), `scientific_netlist_diagram` (the existing electrical.basic Native2D component) and `scientific_netlist_action` (its own declared presentation handler). Bind a normal action/menu command to that handler. The existing host intercepts it; no new C++ method or arbitrary widget/file access is required. Existing scientific/diagram profile grants remain necessary.

`viewerGuiDesignScientificNetlist window form` explicitly inspects the source through public `scientificExecutionCircuitInspect`. With a saved/submitted Job or sweep, it uses the actual selected admitted case's parameters, original Job/Dataset association and source generation/revision/SHA; published Dataset provenance and canonical payload integrity must match. Without a Job, it uses current declared form parameters. The read-only pane labels which source, provider/version, parameters, Job and Dataset it represents. It is a validated canonical reconstruction by the same registered converter/version, not an unauthenticated remote artifact fetch or a new simulation. Current GUI edits do not silently replace a selected Job's parameters. Changed source/provider, foreign case/publication or invalid circuit rejects inspection and retains scientific state.

The complete netlist is bounded to32KiB; oversize rejects rather than displaying a truncated deck. The existing bounded domain state stores its context/text in `scientific_netlists`, and the ordinary Workspace/History preserves it. On restore, the host checks the cached context against current canonical source/selected Job/parameters/Dataset, displays it only when they still match, and otherwise shows a stale/unavailable explanation. It never reconstructs, computes, submits, polls or contacts remote nodes during restore. Refresh is explicit. Presentation visibility can hide/show this declared pane independently of the Job log and Plot without recreating any scientific authority.
# Declared canonical series and panel editing (dev108)

The existing Plot form accepts an optional complete series editor profile:
`plot_series` (choice of current stable trace IDs), `plot_series_label` (string
field/entry), `plot_series_axis` (choice `left right`), `plot_series_enabled`
(boolean), `plot_panel` (choice of current panel IDs), `plot_panel_title`
(string field/entry), `plot_series_target` (the Plot whose `plot_form` references
this section), and `plot_series_commands` (action ID → fixed operation).
Optional `plot_series_status` names a separate read-only log/label/status.
All editor controls must be distinct, including from the source Dataset/X/Y,
axis-scale and probe controls. Change callbacks are prohibited on editor controls.
Declare ordinary action/menu/toolbar controls with distinct presentation handlers;
the trusted Host dispatches these bindings before authored callbacks. No C++ method
or additional runtime grant is needed, and the default single-series Bind remains
compatible.

`viewerGuiDesignPlotSeries window form operation` uses only the bound canonical
PlotSpec. Fixed operations are `refresh` (derive choices/summary), `load` (load the
selected trace into source and editor controls), `add`, `update`, `remove`, `up`,
`down`, `panel_add`, `panel_remove`, `panel_up`, and `panel_down`. First Bind, then
Refresh. Select a canonical Dataset and Discover its actual variables before Add
or Update. Add retains existing traces and generates a distinct stable `trace_N`
ID; Update preserves the selected ID, style and unrelated fields while replacing
its selected Dataset/X/Y/label/axis/enabled state and panel membership. Load does
not alter the plotted trace. Up/down move within the current panel; panel operations
move whole panels. Add Panel uses the supplied title and a new `panel_N` ID;
select that panel and Update to move a trace into it. Only an empty, unannotated
non-final panel can be removed. The final trace cannot be removed. Labels/titles
are single-line, at most160 characters; the declared editor is bounded to32 traces
and8 panels. Existing PlotSpec order, styles, annotations and canonical references
remain the representation, with no parallel trace store.

Plot v4 validates actual Dataset/Variable references, shared X semantics, physical
unit conversion and native model before replacing the accepted binding. Put
voltage and current on separate left/right axes or panels; incompatible same-axis
units fail without replacing the previous frame. Each accepted coherent edit uses
the existing History owner; Save/Open persists the PlotSpec and editor controls.
Exact source-hit probes and persistent reference-line cursors continue to use the
existing Plot owner. No calculation, new simulation, Script Job, remote contact,
raw vectors, author Tcl or arbitrary editor script is admitted by these controls.
