# Viewer GUI Integration Manifest v1

TASK210 source proposal: a finite declared `transform_kind=baseline_correct`
form routes explicit `discover/create_corrected/cancel/inspect` actions through
existing Dataset Transform and Plot owners. Create has effect `mutating`; exact
scientific profile/grants are checked even without authored C++ SDK calls.
There is no new SDK method or implicit analysis on selection. The complete
form/admission/lifetime contract and its unexecuted acceptance limits are in
the baseline form proposal.
Central metadata/wiring and independent CORE review remain MAIN's responsibility;
this source proposal alone does not claim runtime or GUI acceptance.

Programmatic `viewerGuiDesignValueSet` on an integer field accepts an exact
integral finite numeric value, including a C++ `Host.number` transport value
such as `1.0`, and normalizes it to an integer before the existing min/max
validation. Fractional and nonfinite values are rejected before field mutation.
Interactive UI Field integer text validation retains its existing contract.

## Declared target for reserved Plot navigation (dev111 source preparation)

An `action` component may declare the optional identifier property
`plot_navigation_target PLOT_COMPONENT_ID` only for its reserved `fit`,
`zoom_in` or `zoom_out` command. The literal target must name a `plot`
component in the same design, with the existing `PLOT_DATASET_API_v4@4`
requirement. The command retains host-owned presentation semantics; existing
reserved handlers spelled `effect unbound` remain compatible, `presentation`
is accepted, and `mutating` is refused. No authored handler, SDK method,
scientific operation or widget path is introduced.

The declaration scopes the logical command ID, including its normal menu and
key routes, to that one Plot. Duplicate action components for the same command
must all declare the same target: different targets or a mixture of targeted
and untargeted duplicates refuse. An action cannot combine this property with
visibility, diagram-tool or raster-tool/command ownership. A target-bearing
design is supported in ordinary preview/runtime composition; synthetic demo
composition refuses because its separate demonstration dispatcher does not
implement this declared target contract.

For example, the existing IC raw Plot is `chromatograms`. Through the normal
Builder `property` operation, set `plot_navigation_target` to `chromatograms`
on the existing action components `fit`, `zoom_in` and `zoom_out`. This retains
the existing action/control IDs and their built-in presentation handlers while
preventing raw buttons/menus/keys from changing a separately bound result Plot,
including one in a hidden panel. The result Plot retains only its actually
supported existing local mouse/viewport controls; no separate global command
or unsupported result toolbar is implied.

The target does not change after another Plot is bound or shown/hidden. If its
native Plot is not yet bound/live, the command has no connected Plot operation;
it does not fall back to another Plot. Designs without this optional property
retain the existing all-live-components navigation behavior, including their
existing demo route. This additive source change is not runtime, original/
candidate GUI parity, redraw/latency or performance acceptance.

## Scientific Library catalog section (dev109 additive)

`viewerGuiDesignCatalogRefresh window form`, `viewerGuiDesignCatalogInspect
window form`, `viewerGuiDesignCatalogAction window form action` and
`viewerGuiDesignCatalogDescribe window form` present the existing Scientific
Library Manager through a declared `section` with
`catalog_owner scientific_libraries`. Existing lists, read-only tables,
UI Field forms, manager, provider dispatch and ScriptJob request lifetime retain
their owners. Describe returns presentation state with owner identity, not
canonical registry authority. Actual actions require current capability,
availability and authentication checks. Raw facts use registry.* prefixes;
known operational state uses status.* and unknown remains explicit.

Exact section references, shapes, limits, provider hooks, action grants and
three reviewed typed C++ methods are documented in the
[Scientific Library Manager API](SCIENTIFIC_LIBRARY_MANAGER_API_v1.md#step2-catalog-capability-declarations-and-provider-delegation-dev109).
Declare manager API version1. Validation checks control types/table columns,
finite actions and declared command handlers. Host selection binds logical IDs;
the author does not read registry paths or mutate private Tk state. Page/filter
actions use100-record public pages; managed entry consultation shows at most1000
IDs with explicit shown/total count. Administration uses ordinary shared dialogs.
Concurrent reads coalesce; a mutation in progress blocks interfering actions;
disposal cancels owned requests; old Session/generation replies cannot update a
new window. Declarations/build success do not establish installed GUI acceptance
or later Library progression steps.

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

The compatible optional fourth argument `hitContext` accepts the shared
viewport's actual segment event detail (`hit_kind wire`, `wire_id`, `point`).
The Host verifies the canonical wire and native segment location, then uses
its endpoint's genuine provider net mapping. Voltage clicks along the same
connected wire resolve to the same available V observable and completed
Job/Dataset provenance, without creating a junction. Current at an arbitrary
ideal-wire position is explicitly unavailable; select a supported device
terminal for a genuine branch measurement. Three-argument terminal callers
retain their existing behavior. Normal Builder probing passes this context
through shared CORE; a Viewer needs no private hit-testing or circuit graph.

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

Resolved non-AC probes also select the independent Variable declared by the
registered provider's inspection (`independent_variable`: stable id, dtype,
unit). Both Variables must have aligned canonical one-dimensional rows. Prior
manual Plot **Discover** is unnecessary: explicit Plot binding validates X/Y
against the current Dataset's numeric Variable Schema, then updates the choices
and selection after the native Plot accepts the binding, in one History entry.
No cached dropdown contents establish scientific identity. Ordinary manual
Discover/Bind remains available. This dev109 correction requires the installed
first-click regression evidence before functional acceptance.

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

Builder's existing **Add shared icon** action and restricted `builder icon catalog`
consume that same catalog. Shared selections are checked against the returned
path/SHA/provenance before ordinary image admission. Existing Import, owned
project catalog, embedded source/PNG bytes and normal Module packaging remain
the owners; this adds no asset registry or renderer. The original library now
also includes selection, remaining electrical devices/tools, Undo/Redo and
Fit/Zoom actions under its existing GPL-3.0-or-later provenance.

The compatible dev111 stock extension raises only the fixed CORE manifest row
ceiling from 64 to 128. The five required row fields remain
`id,title,category,license,source`; old five-field rows remain valid. Optional
`action` and `origin` are bounded, nonempty, single-line strings with the same
200-character limit as existing provenance. Optional `sha256` is exactly 64
lowercase hexadecimal characters and must match actual source bytes. Unknown
fields remain refused. Returned `sha256` always means the actual source SHA;
`action`/`origin` are returned only when declared, without fabricated defaults.
Manifest size remains 64 KiB; each source retains its 256 KiB/512-pixel bound and
the existing safe SVG/PNG admission. No call signature or schema ID changes.

The source stock manifest declares 100 distinct semantic IDs, 20 per family:
Selection & Navigation; Geometry & Editing; Data, Plots & Analysis; Scientific
Tools & Simulation; Documents & Workflow. All 30 original source assets/IDs are
retained. The existing Builder picker filters metadata and previews one selected
source via `viewerGuiIconImport`/`uiFieldIconApply`; only explicit Add changes the
project. Selection/close generations invalidate deferred previews. Normal model
edits, Undo/Redo, Assign and Module packaging retain their public owners. Project
icons still have a separate 64-entry/2 MiB limit. Native menus keep their actual
normal/disabled image contract; this adds no menu hover/selected-state promise.
Source counts do not certify installed discovery, rendered legibility, GUI
browse/filter/assignment/save/reopen or packaged install; those require actual
release-scoped evidence. No new SDK method, grant, asset store or renderer exists.

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

## Read-only canonical document components (integrated next candidate)

Builder component `document` accepts `kind` (`html`, `pdf`, `code`, `table`) and
optional `title`. It starts empty. A `dataset_selector` may declare `content_kind`
with the same value; its normal catalog-backed selection then offers only
compatible current-Session identities. Existing selectors without this property
retain their behavior. HTML uses the existing safe native Document presenter;
code uses read-only Source Surface; table uses the existing bounded Preview table
pager (100 rows/page, Source row, scrollbars and Go to row); PDF uses the existing
separate CORE PDF reader's official open route, with no OCR or second decoder.

An optional `dataset_selector` may declare `allow_empty true` (default false).
It then offers an empty canonical choice and **Clear selection**, with the same
normal `changed` event. Bind that event to the existing `document_bind` action
to clear former content/binding and show the Session-aware selection prompt.
It grants no arbitrary text/value setter or new source access.

`viewerGuiDocumentCompatible dataset_id kind -> boolean` checks the current
canonical schema/contract. Unknown kinds fail. Images and PDFs are not tables;
all selected table variables must be rank one in a supported table container.
`viewerGuiDesignDocumentBind window document_component_id selector_component_id`
requires a live owned Viewer, matching declared kinds and compatible selected
canonical identity. It returns status, kind, Dataset ID, canonical source SHA and
read-only owner. The shared owner checks Session/source revision and clears stale
content; it never publishes, executes source or enables Save. Unknown/missing
source fails through the existing Dataset/Resource owners.

Restricted C++ declares `VIEWER_GUI_HOST_API_v1@1` operation `document_bind`, then
calls `host.document_bind(document_index, dataset_selector_index)` (one-based
original component ordinals). No source bytes, paths or arbitrary public API
invocation are given to C++. A successful CLI run produces only the typed plan;
actual reading/rendering happens in the installed Viewer through GUI Host.
Builder and Workspace use this same contract. Real scientific GUI/Session
acceptance remains a separate requirement; component admission is not acceptance.

Document `kind=code` enables the existing Source Surface's optional shared Find
bar (`sourceSurfaceCreate ... {find_bar 1}`), Previous/Next, Enter, Ctrl+F and F3 /
Shift+F3. Read-only text retains normal selection/copy/navigation. No execution or
Save is enabled. The sanctioned native author `gui_test` accepts
`{"operation":"document_find","component":"SOURCE_COMPONENT","value":"text","direction":"forward"}`
(or `backward`): it types into the owned Find entry and clicks its actual button.
`key` on this bound code component permits only navigation/find/select/copy keys;
it cannot edit or execute. Existing diagram/Plot input keeps its distinct limits.

## Declared TeX article form (dev109)

An editable TeX article composes existing owners through one `section` with all
ten component references: `tex_source`, `tex_pdf`, `tex_projects`, `tex_assets`,
`tex_diagnostics`, `tex_log`, `tex_status`, `tex_info`, `tex_source_status` and
`tex_pdf_status`. Source is a `document` with `kind tex mode editable`; PDF is a
`document` with `kind pdf`. Projects is a choice/combobox, assets and diagnostics
are read-only tables, and the remaining references are the corresponding log or
label/status components. Each TeX source belongs to exactly one complete form.
Other document kinds remain read-only.

Declare `VIEWER_GUI_HOST_API_v1@1` operation `tex_command`, then use
`host.tex_command(form_ordinal, operation)` or the public host operation
`viewerGuiDesignTeXCommand window form_id operation`. The finite operations are
`new`, `open`, `save`, `build`, `rebuild`, `cancel`, `preview`, `diagnostic_open`,
`import_assets`, `remove_asset`, `export_tex`, `export_pdf`, `export_assets`,
`refresh` and `import_source`. There is no source-text transport through C++.

The Tcl signature is `::GX::viewerGuiDesignTeXCommand window form operation`,
with three required arguments and no defaults. `form` is the declared section's
component **ID**; the C++ `unsigned form` is its one-based declaration ordinal.
Both identify the same complete form. Commands read its actual selected article,
asset or diagnostic through the existing GUI Host; they do not take a caller's
source path, resource reference or article ID. The C++ method returns `void` and
emits the typed host plan; the Tcl host returns the operation receipt below.

| Operation | Required current form context and actual immediate return |
| --- | --- |
| `refresh` | Refresh current article/list/status projections; `{status refreshed}`. For an initialized valid form opened without a Session, retain its disabled source and Session prompt and return `{status unavailable reason no_session}`. It does not typeset or permit editing. |
| `new` | Opens the shared article-name form; `{status awaiting_name}`. Article creation occurs only after its normal accepted callback. |
| `open` | Uses the selected `tex_projects` Document ID belonging to this form's provider. Dirty-source Cancel returns `{status cancelled}`; success returns `{status opened document_id ID source_revision N}`. |
| `save` | Requires a current, unchanged-generation article. Saves the actual UTF-8 Source Surface draft plus existing linked assets; `{status saved document_id ID source_revision N}`. |
| `build`, `rebuild` | Require an idle current article build, save the draft first, then call the same managed native TeX Build. Return its `{status running request REQUEST source_revision N inputs MANIFEST}` receipt. Neither command is a C++ Viewer rebuild. |
| `cancel` | No selected article returns `{status idle}`. Otherwise passes this form's retained Document generation to TeX Cancel; returns `idle`, or `cancelling`/`awaiting_completion` with the original request. A cancellation request is not terminal cancellation proof. |
| `preview` | Requires a retained prior successful PDF. Opens its actual managed-resource reader and returns `{status opened document_id ID source_revision COMPILED_N}`. A stale prior success may be viewed and remains labelled by its compiled revision. |
| `diagnostic_open` | Requires one selected current-source native diagnostic with an actual source link/positive line. Returns `{status located file FILE line LINE}`; `main.tex` navigates the editor, a linked asset opens read-only. |
| `import_assets` | Opens an ordinary file chooser then normalized-relative asset-name form; chooser Cancel returns `{status cancelled}`, otherwise `{status awaiting_asset_name}`. Import/replace occurs through the accepted form callback and normal confirmation. |
| `remove_asset` | Requires one selected currently linked asset and unchanged article stamp. No returns `{status cancelled}`; Yes saves the reduced association and returns `{status removed filename NAME}`. It does not delete an external source file. |
| `export_tex`, `export_assets` | Require a saved exact draft; both currently export a `.tex` source **and linked-assets bundle** through the existing File Publication owner. `export_assets` is not an asset-only exporter. Cancel returns `{status cancelled}`; success returns the File Publication bundle receipt. |
| `export_pdf` | Same bundle/export guards, with `.pdf` and a successful PDF matching current source/assets. Cancel returns `{status cancelled}`; success returns the File Publication bundle receipt. |
| `import_source` | Dirty-source review precedes a normal `.tex` chooser. Cancel returns `{status cancelled}`; an ordinary exact UTF-8 file at most16MiB creates a new article through the canonical owner and returns the `opened` receipt above. |

Names/IDs, file locations, counts and source-revision integers have no scientific
units. Diagnostic lines are one-based source locations. The default selected
native engine is `pdflatex`; a configured `xelatex` or `lualatex` selects that
engine. Source bytes/assets/build limits and the complete Build/Status/Cancel/
Export receipts are defined by the existing
[Interactive Document TeX profile](INTERACTIVE_DOCUMENT_API_v1.md#tex-project-profile-dev109-integration)
and [File Publication](FILE_PUBLICATION_API_v1.md). Wrong Session/generation,
uninitialized/incomplete form, foreign provider, stale source/assets, missing
selection, unsupported operation or stale diagnostic rejects before the relevant
mutation. A file dialog or pending asynchronous build is not a successful commit.

For example, when a complete TeX section is declaration ordinal1 and its public
grant includes `VIEWER_GUI_HOST_API_v1@1/tex_command`, ordinary C++ calls
`host.tex_command(1, "save");`. A trusted host with that existing form ID may call
`::GX::viewerGuiDesignTeXCommand $window $formId save`. These are qualified
context-dependent examples; neither creates a form or grants source/path access.
This dispatcher is trusted Tcl plus the specific admitted C++ method, with no
registered Python/Octave Bridge `tex_command` or generic API-name invocation.

The Source Surface owns the editable buffer, Find/Replace and native text Undo.
Save writes the exact UTF-8 draft through the existing managed Resource and
canonical TeX Workspace owners. Build/Rebuild first saves that draft and starts
the configured native TeX runtime; opening or refreshing does not build. Cancel
targets the original Document generation. Article selection and outstanding
build callbacks remain associated with their actual Document/generation.
Changing articles offers Save/Discard/Cancel for a dirty draft. Closing without
an optional presentation Workspace also protects dirty drafts.

The article's canonical Workspace is distinct from an optional saved interface
Workspace. Saved interface state contains article association and content
identities, never an additional editable source or a historical replacement for
the current canonical article. Restore validates Document generation before any
interface change; a different association cannot discard a dirty source buffer.
The article source uses native Source Surface Undo; interface History does not
replace canonical article bytes with an old interface snapshot.
Opening a different article now records one association change in shared
interface History. Restoring that association uses the current canonical
article; it does not restore an old source revision. Text edits retain Source
Surface Undo/Redo. Installed association-History verification is pending.

Assets use explicit normalized relative project names, including nested names.
Replacing/removing a linked asset requires a normal shared confirmation. Export
uses File Publication and explicitly confirms existing files in the complete
source/PDF-and-assets bundle; it preserves the managed originals. PDF preview
uses the existing native read-only managed-resource reader and reports the
compiled source revision, including a retained stale prior success. A PDF resource
must belong to the selected article and remain valid before Preview releases
an already-open reader; a foreign resource is refused with an ownership error.
Compiler diagnostic navigation requires an actual current source location; asset source
opens read-only through Source Surface.

An installed article's normal Workspace opener may pass `tex_document_id` through
the existing restricted Viewer context. CORE validates the canonical TeX ID,
current Session and exact installed module/Viewer provider before creating its
window. This reopens the existing article; it does not create another source or
compile the C++ Viewer. The pure no-Session refresh allowance does not bypass
invalid-form, changed-Session or editing guards. These two lifecycle corrections
still need focused installed verification.

These contracts are implemented in shared CORE. Installed LaTeX Viewer GUI,
build/export/lifecycle and scientific acceptance must still be recorded against
the actual installed package; source admission alone is not acceptance.

## dev109 typed electromagnetic model form (implementation under validation)

`Host::em_command(form_ordinal, operation)` is additive SDK v1 operation31. It
requires `VIEWER_GUI_HOST_API_v1/em_command` and explicit operation grants from
the existing `ELECTROMAGNETIC_SIMULATION_API_v1`. The complete declared section
maps `em_parameters` keys `kind model_id half_width_m height_m mesh_size_m
radius_m current_density_A_m2 mu_r voltage_V eps_r` to ordinary value controls.
It references `em_models` (model choice), `em_status` (read-only text), `em_log`
(log), `em_output_id` (field), and `em_dataset` (canonical Dataset selector).
Optional `em_jobs` selects retained real Jobs; `em_field_plot` is a Plot v4 slot.
Optional `em_report` names existing read-only Results text; otherwise result
inspection uses `em_log`. This allows Results to remain visible in its own tab
while the Solve tab retains the actual bounded native solver log.
Physics is a declared choice; the original EM native service supplies
`formulation=planar_2d`, normalization, geometry and material validation.
Nonvisual File Publication requirements negotiate their version through the
existing `filePublicationApiInfo` owner, consistently with the SDK catalog.

Optional `em_actions` maps finite EM operation names to distinct declared
handler IDs. The common command owner then applies the same availability to
buttons, menus and toolbars: Cancel requires an active owned Job; results and
publication require a completed Job with the current canonical source identity;
field/profile/3D actions require a qualified selected field; export additionally
requires that field to be shown in the declared Plot. Open and Reconnect require
real selections. Existing explicit `available=false` remains authoritative.
This is presentation state; each operation still revalidates its scientific
contract when executed.

The common EM host disables irrelevant electric/magnetic parameter entries and
guards model editing during an active Job without changing their values.
Availability uses a bounded 250 ms projection of the existing Job status service,
with a window-owned refresh timer only while a Job is active. Disposal cancels
that timer and stale Session tokens reject callbacks. No second Job registry,
scientific execution path or scientific History entry is created by polling.
Vertical native tabs (`tab_position=west`) and shortest-roundtrip numeric text
belong to the shared UI Field presentation owner.
The compiled event completion controller refreshes common command availability
after applying the admitted native service actions. A newly submitted or
reconnected Job therefore updates the controls without another user action.

The common compiled dispatcher returns an existing native `host_error`/`error`
as the action result's `message` when execution fails. The GUI command controller
retains that reason in its footer and result trace, instead of replacing it with
only a generic failed status. Scientific source and revision guards remain
unchanged. For example, an external TeX warning with no verified source location
reports why Go is unavailable and preserves the previous valid caret position.

Finite operations are `refresh`, `new_electric`, `new_magnetic`, `validate`,
`open`, `save`, `duplicate`, `workspaces`, `rename`, `run`, `jobs`, `reconnect`,
`status`, `cancel`, `log`, `results`, `publish`, and `field`. All forms require
EM grants `defaultModel validate loadModel saveModel listModels`. Additional
actions require their matching native operations: `runAsync/jobStatus`,
`jobStatus/cancel`, `jobStatus/jobLog`, `jobStatus/resultDescribe/resultPreview`,
`jobStatus/publish`, or `fieldDescribe` as appropriate. Field display additionally
requires `PLOT_DATASET_API_v4/widgetCreate`. Duplication uses existing
`SESSION_WORKSPACE_API_v1/export/import`; the model Workspace manager also needs
`create/get/update/list`, and Rename needs `update`. Neither C++ model payloads
nor arbitrary API names, process commands or paths cross this dispatcher.

The original `em_models` provider owns canonical models and nested resources.
Declared fields are drafts until native validation and Save. The shared
Workspace manager supplies names, Save/Discard/Cancel, resource-preserving
duplication and import/export. A separate saved interface Workspace preserves
association and controls. Shared History captures that state; generation and
held source stamps reject foreign changes before restoration. Run starts the
existing managed Gmsh/GetDP provider. Closing the Viewer leaves that supervisor
in control. Jobs lists actual retained Jobs of the selected model; Reconnect
requires a real selected identity when several exist. Publication stays explicit
and source-guarded. Field display binds actual node/connectivity/cell roles via
Plot v4, without a private graph or centroid-as-node substitution.

The implementation remains **source-only** until official Builder author
integration, installed GUI, scientific and lifecycle acceptance are recorded.
This form does not itself close the required planar Native3D presentation gap.

### Optional planar Native3D field target

A complete EM form may additionally declare `em_field_native3d`, naming an
existing `native3d` component. `Host::em_command(form, "field_3d")` requires the
existing EM `fieldDescribe`, Plot v4 `widgetCreate` and additive Native3D v2
`cell_field_bind` grants. The broker passes no scientific arrays, renderer paths
or native pointers to C++. The shared form obtains the actual linked field
contract and binds it through the public Native3D cell-field source.

The original `field` command still binds the exact 2D Plot. `field_3d` presents
those same planar elements at Z=0 and states this scientific limit visibly.
The component is a derived presentation: after reopening an interface Workspace,
use the action again against its preserved canonical Dataset selection. This
operation does not promise an automatically restored native camera or CAD state.
The SDK ABI is unchanged; this adds one finite value to existing operation31.
Installed GUI, lifecycle and scientific acceptance remain independent of compiled
command-plan admission and the narrow native bridge contract.

Additional finite EM actions (source-integrated, installed QA pending):
`runtime` opens the existing Configuration Runtime page; `profile` binds actual
cell-centroid samples to optional declared Plot component `em_profile_plot`;
`publish_charts` explicitly retains the exact field and actual sample scatter as
two independent source-bound Plots, using the installed Viewer's stable producer
identity; `export_field` requires the selected Dataset's already displayed field
and uses the normal Save dialog, native Plot PNG/SVG/PDF writer and File
Publication. Missing/stale bindings fail before publication. Cancel creates no
export. The C++ source supplies no arrays, paths, writer callbacks or new process.

Explicit additional grants are Configuration `open_page`; Plot v4
`cellFieldProfileSpec` plus `widgetCreate` for profile, `upsertPlotFromSpec` and
`render` for chart publication, `widgetExport` for export; File Publication
`publish_bundle` for export. EM `fieldDescribe` remains required for scientific
presentations. These reuse the original owners; compiled plan/admission success
alone does not establish installed behavior or full feature parity.

Native TeX diagnostic navigation uses the existing revision/generation guards.
For warnings with an input line, the worker's native input-file context must name
an exact staged source/asset before `source_link` is true. Distribution package
warnings and ambiguous/no-file contexts remain explicitly unavailable. A native
line number by itself never selects main.tex. Stored older build diagnostics are
not retroactively rewritten; build the current source explicitly to obtain new
location receipts.


Dev109 editable geometry composition adds the `editable3d` component and the
complete `workbench_*` section described in WORKBENCH_3D_API_v1. It embeds the
existing editable Native3D v1 controller, preserving its single-host restriction
and original Document/Geometry/History/Recovery owners. Restricted C++ uses only
`Host::workbench_command(form, finite_operation)` (SDK operation32) with explicit
service grants; readonly `native3d` v2 components retain their current semantics.
The initial bridge exposes original primitive/lifecycle/selection/Undo/Redo
commands; the remaining CAD parity forms and installed acceptance are pending.

Dev109 `Host::workbench_command` additionally admits the finite purpose-form
commands advertised by existing WORKBENCH_3D_API_v1 `apiInfo/guiFormCommands`.
They require the same complete declared geometry section and explicit
guiCommand/guiInspect grants. Trusted callbacks remain in the original Workbench
owner; no whole buildPanel, arbitrary Tcl dispatcher or author geometry payload
is exposed. Canonical commits and native selection refresh the declared
Document/object/status projection via the common host widget event, guarded by
current Session and window ownership. See WORKBENCH_3D_API_v1 for acceptance scope.

The editable geometry form may additionally declare the paired
`workbench_selection` extended/multiple list and `workbench_selection_mode`
Replace/Add/Subtract choice. They use the existing Select command and original
Workbench selection owner; no native token or alternative selection graph is
exposed to C++. Dynamic rows and selected indices survive interface Capture and
Restore. The legacy single-object form continues to work unchanged.

Restoration resolves pending list indices through the saved row identities before
mounting the canonical Document, then projects those IDs into its current rows.
The shortcut and pending multiple candidates remain separate from the scientific
owner's actual selection; restoring controls does not invoke Select or change
geometry/History. Invalid saved indices and missing canonical candidate IDs
reject explicitly. A refresh of the same Document generation with unchanged
native selection preserves pending candidates by canonical ID, including the
ordinary refresh requested by a compiled Viewer's Open handler. Missing pending
IDs are removed when rows change. A different Document generation or actual
native selection change projects the real native selection; a single-object
form retains its existing projection behavior. The first installed retest proved
that restoring candidates after Mount alone was insufficient because the later
Open refresh cleared them again. Both transitions require installed acceptance.

## Canonical raster binding and shared tools (dev109)

A `native2d` component may declare `source_kind raster`; its source selector is
a `dataset_selector` with `content_kind raster`. The public host operation
`viewerGuiDesignRasterBind window viewport_id selector_id` admits an actual
current-Session `image.raster` Dataset through the existing Dataset, Variable
Schema, Document Resource and Native2D owners. Empty selection reports
`awaiting_selection`. A numerical XYZ table is not a raster source. The receipt
retains Dataset identity, source SHA, native pixel dimensions and `px` coordinates;
physical calibration remains an explicit existing Native2D operation. No Dataset
is implicitly published and no author path or pixel array enters restricted C++.

`viewerGuiDesignRasterTool window viewport_id tool` admits `select`, `rectangle`,
`polygon`, `move`, `rotate`, `pivot`, `pan`. An action can declare
`raster_tool {viewport_id tool}` to select its local controller immediately and
derive its checked state from that controller, without a compiled-worker event.
The shared native kernel owns image/ROI mapping, hits, vertices, projections and
transform mathematics. Rectangle drag and polygon clicks are proposals until
acceptance. Return or the local Finish polygon action accepts a valid polygon;
Escape cancels it. A late release after cancellation cannot commit an edit.

`viewerGuiDesignRasterCommand window viewport_id command` admits `fit`, `cancel`,
`finish`, `delete_roi`. Restricted SDK `raster_command` admits `fit`, `cancel`,
`delete_roi`; the polygon completion gesture is a local host action. The source
ROI collection remains the existing native `gx.image.rois` attribute. Accepted
edits checkpoint the same Document and use existing Scientific History. Capture
retains accepted resource references and the current view/tool/ROI/pivot; pointer
frames do not repeatedly export resources or mint new origins.

The retained canonical raster snapshot and the interface's current presentation
view have separate receipts. Capture retains the accepted snapshot unchanged
and stores the current view in `presentation_view_state`; disposable viewport
pixel extents do not dirty an otherwise unchanged Workspace. Restoring only a
view, including a compatible legacy inline view, does not revise the scientific
Document. Actual image, layer or ROI changes still use the normal checkpoint and
History owners. Existing Dataset, Document generation and revision guards remain
mandatory: an externally changed Document requires an explicit current-state
open and cannot be silently reconciled by presentation restoration.

Binding prepares History before mutation and validates a candidate's source,
geometry, interaction and widgets before replacing the old host. Invalid saved
tool/ROI/pivot admission retains that host. Resize/Fit cancels a device draft;
external view changes reject an outstanding draft rather than reinterpret its
source pixels. Expired-source cleanup rolls back the retained native gesture
without admitting another scientific request. If a current frame cannot be
drawn, its transient preview is hidden and an inline source diagnostic appears.
Hidden images/layers do not leave visible ROI handles or outlines.

The basic local Fit/Delete/Finish context menu alone is not the complete declarative
semantic-context facility requested in GUI03. Existing Tcl PanelTarget mapping
alone does not complete GUI04 Builder/SDK editor exposure. The complete declarations below provide those facilities; independent installed
generic-Viewer evidence is recorded in
[the acceptance report](../reports/DEV109_RASTER_ACCEPTANCE210.md).

### Declared semantic raster menus

A Builder `context_menu` may additionally declare both `semantic_viewport`
(the ID of its canonical raster `native2d` component) and `semantic_rules`.
The existing `actions` list still determines command order and the existing
`command_icons` catalog supplies normal/disabled native menu icons. For example:

```tcl
semantic_viewport image_canvas
semantic_rules {
    properties {visible {entity {object roi}} enabled {selection_present 1}}
    delete_roi {visible {entity roi} enabled {editable 1 roi_present 1}}
    fit_image {visible {} enabled {}}
}
```

Every rule names an existing command from this menu. `visible` and `enabled`
are dictionaries of typed field/admitted-values conditions; all fields combine
with AND and a field accepts any of its listed values. Empty conditions are
true. There are no expressions, scripts, callback names or general predicates.
Unknown fields, values and commands fail normal Builder validation.

Current raster invocation grounds `entity` as `background`, `object`, `roi` or
`annotation` using Native2D's retained image/ROI picker and rendered text hit.
Boolean fields are
`selection_present`, `roi_present`, `annotation_present`, `layer_visible`,
`layer_locked`, `editable`, with exact values `0` or `1`. An annotation hit resolves
the actual current image annotation ID and generation; label text is not identity.
This controller capability does not by itself complete the anchored field editor.
Other Native2D domain controllers retain their existing semantic dispatch.

CORE filters and enables the declared commands together with Viewer Commands
availability. On invocation it revalidates the scoped viewport, actual Document
receipt, image/layer state, ROI revision, selection and view. Changed, removed,
locked or expired targets cannot silently redirect an old command to a new ROI.
Raster host commands and edit preparation recheck the captured context, including
after a History decision. Rejection reports inline and preserves the valid
scientific state. Context coordinates/tokens remain transient host state and are
not stored as Workspace identities. Designs without these optional properties
retain their existing context menu behavior.

The declaration uses existing Builder properties, Viewer Commands and admitted
raster SDK methods; it introduces no invoke-any-API callback or runtime compiler.
The native adapter adds read-only `image_hit` to `raster_roi_pick`, computed by
the same native ROI picker over the retained source bounds. The existing C ABI
and all 1857 exports are retained. Typed contracts cover real background/image/
ROI hits, locked availability, stale dispatch and one canonical Delete/History
commit. Independent installed acceptance of these semantic menus and the anchored
editors below is recorded in the same scoped report.

The local raster tool vocabulary additionally includes `annotation`. A first
click on the visible image creates one source-pixel annotation through the existing
native annotation collection and one accepted Document/History change. The native
renderer draws its retained content/style. Select uses the actual rendered text
bounds; the selected ID and generation survive a normal Workspace reopen.
`Host::raster_command(viewport,"delete_annotation")` removes that selected identity
through the same shared controller. Unchanged definitions are no-ops; invalid
styles, locked targets, stale collection revisions and replaced generations are
rejected. Edit preparation rechecks identity after a potentially yielding History
decision. These additions use existing SDK methods and require no SDK ABI change.
Declared text/font/color/size composition uses the existing UI Field owner in a
Native2D anchored section; see [the design contract](VIEWER_GUI_DESIGN_v1.md#raster-controls-anchored-to-scientific-targets).
`Host::raster_command` also admits `panel_open:SECTION`, `panel_close:SECTION`,
`editor_apply:SECTION` and `editor_cancel:SECTION`, only for that viewport's
declared section. No adapter/header ABI change or compiler is needed at runtime.
Actual installed GUI03/04 acceptance, including selection-following, text/color
edits, cancellation, pan/zoom/resize and Session cleanup, is recorded in the
scoped report. See also the [Builder example](../examples/GENERIC_RASTER_BUILDER.md).

### Restored view and live electromagnetic inventories

Designed Workspace capture retains Plot axes as `panel_id`, `axis`, `limits`,
`scale` and `direction`, including before the first mapped frame. Device tick
positions and plot rectangles are disposable layout, so mapping the restored
widget does not itself create an unsaved scientific edit.

For a declared electromagnetic form, the `em_models` and optional `em_jobs`
choice lists are live inventories of their existing model/Job owners. They
are refreshed rather than saved as authoritative interface content. The selected
IDs remain ordinary captured values; model and Job bindings, other choices,
scientific view limits, domain drafts and durable History remain compared. An
additional available model therefore does not mark an untouched interface dirty.
Existing saved payloads and History are read without rewriting their source.

## Preview modules (DEV111-P006)

Preview modules can use existing GUI/icon services through the optional
[Preview Component GUI API v1](PREVIEW_COMPONENT_GUI_API_v1.md). This host-scoped
operation set does not compose Viewer designs, alter viewer.* identity validation,
or change Viewer Builder generation or the restricted native Viewer SDK.
