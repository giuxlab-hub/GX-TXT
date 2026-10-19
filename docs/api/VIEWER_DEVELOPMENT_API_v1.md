# Restricted Viewer Development API v1

## Fresh admission and responsive compiled events (dev108)

Build and Run each perform a fresh source AST, complete design and capability
admission. Run compiles from that same request's in-memory admission rather than
repeating it after Build. Post-compile source/design/project digests are checked
again before executing the bounded worker. Prior project reports and binaries
cannot authorize execution. This is request-local reuse, with no approval cache,
new worker pool or widened SDK policy; debugger Build uses the same fixed owner.

The fixed Development CORE request `validate_design PATH` retains its legacy
validated-design result. Its optional exact `with_catalog` argument returns
`{design VALIDATED_DESIGN catalog INSTALLED_PUBLIC_CATALOG}` from one fresh
startup. Both forms use the same full model validator and public catalog helper;
unknown modes/extra arguments reject. Standalone `api_catalog` discovery keeps
its original result. The approved CLI's public response contracts are unchanged.
The combined response has the same bounded16MiB transport ceiling as Builder;
the design itself remains at4MiB. Legacy single-result requests keep4MiB.

Scientific cancellation still has a genuine completion race: a short simulation
can finish during an admitted C++ action. A cancel request or `cancel=1` flag
does not establish terminal CANCELLED. Inspect the actual existing Script Job
state and owned cleanup, preserve completed results, and report the race as such.

Dev108 reparent retains declaration positions used by all one-based restricted
SDK component arguments. Later-declared container parents are validated and
constructed in derived dependency order; no C++ dispatch renumbering is needed
for this presentation edit. `reorder ID STEP` remains a signed sibling layout
step rather than an absolute component-number request. See the existing design
contract through the catalogued GUI Host manual.

The existing `host.numeric_discover/evaluate/statistics/compare/publish` methods
also accept declared interpolation and complex-projection forms. Declare their
typed controls with Builder using the `numeric_kind` profiles documented in
`VIEWER_GUI_HOST_API_v1`. Interpolation evaluation requires explicit
`NUMERIC_API_v1` grants `dataset_expression` and `interpolate`. Complex projection
requires `dataset_expression`, `complex_unary.magnitude`,
`complex_unary.phase_rad`, and `complex_unary.phase_deg`; all selectable operations
must be granted before execution. Publication separately requires existing
`DATASET_PUBLICATION_API_v2` grant `datasetPublicationV2Finalize`. No new Host
method, raw numeric library, filesystem or scientific execution grant is added.
The existing canonical result/Workspace and source-revision guards apply.

Dev108 additive authoring facilities (same API family and kernel project grant):

- `facility_request PROJECT` reads a UTF-8 JSON request on stdin (at most 64 KiB).
  Required fields are `schema=gxtxt.core_api_gap.v1`, `request_id` matching
  `GAP-[A-Z0-9-]{1,60}`, `viewer_project` equal to the project's module ID, `task`,
  `public_api_inspected` (nonempty list of API IDs), `missing_operation_or_contract`,
  `reproduction`, `why_existing_api_fails`, `desired_input_output`,
  `minimal_acceptance_test`, and `status=REQUESTED`. Non-list fields are nonempty
  strings. The backend stores `requests/ID.json` with exact three-file source
  hashes. Same-ID identical requests are idempotent; modified requests fail
  `GAP_IMMUTABLE`. This is project evidence, not a separate global registry.
- `builder PROJECT` reads `{ "operation": "...", "arguments": [...] }` on stdin.
  It invokes the existing Interface Builder `viewerGuiDesignModelEdit`, validation,
  save and Undo/Redo owners. Supported operations: `inspect`, `add`, `property`,
  `layout`, `constraints`, `bind`, `remove`, `duplicate`, `reparent`, `reorder`,
  `metadata`, `undo`, `redo`, `properties`, `icon`, `icon_import`. Arguments match those existing public model methods;
  nested JSON objects become inert Tcl dictionaries through a trusted serializer.
  For example `{"operation":"metadata","arguments":["title","Circuit Workbench"]}`.
  `add` takes a single component object with `id,type,parent,properties,layout`.
  `property` takes component ID, property name, value; `remove` takes an ID;
  `undo`, `redo`, `inspect` take an empty argument list. No Tcl source is accepted.
  History belongs to the existing `gxtxt.viewer_design_model.v1` model and resets
  after an external GUI edit. The request and design hash are retained in
  `derived/builder-receipt.json`. Design mutations do not change C++ source.

GUI clients call `viewerDevelopmentRequest facility_request|builder PROJECT CALLBACK
{request_json JSON}`. JSON is data, never executable source. These authoring
operations grant no runtime scientific, process, filesystem or renderer access.

`VIEWER_DEVELOPMENT_API_v1@1` is the trusted shared facade used by the ordinary
`viewer.development_workspace` module and its CLI. Discover it through
`workbenchExtensionCoreApis` / `workbenchExtensionRequireApi`; inspect
`viewerDevelopmentApiInfo`. The implementation is
`core/tcl/viewer_development_api_v1.tcl` and
`core/python/gxtxt_viewer_development.py`. UI composition remains Viewer GUI Host;
the original Script Job auxiliary owner owns asynchronous process lifetime.

## Requests and source transfer

Ordinary `export` receipts include exact generated `descriptor_text` and
`descriptor_sha256` for `module.ini`, plus `package_metadata_text` and
`package_metadata_sha256` for `plugin-package.ini`. The package descriptor owns
`framework_min`/`framework_max`; those fields are not invented in the module
descriptor. Manual/source/design/project/binary and admitted SDK/policy hashes
remain in the existing candidate provenance. These are bounded inert generated
texts for author review, not archive parsing or arbitrary filesystem reads.

### Native screenshots as installed manual resources (dev108 additive)

`manual_asset PROJECT` accepts bounded JSON on stdin through the same project
write grant. GUI clients use `viewerDevelopmentRequest manual_asset PROJECT
CALLBACK {request_json JSON}`. It adds no C++ runtime capability and accepts no
author filesystem path:

```json
{"operation":"add","asset_id":"remote-waveform","capture_id":"32_lowercase_hex_digits"}
```

First attach the source-identical installed Viewer in the Development Workspace,
open it through `gui_test`, then request `{"operation":"capture"}`. Use that
receipt's `request_id` as `capture_id`. Add requires the successful project capture
receipt, exact source/design/project SHA snapshot and exact PNG SHA. The live GUI
owner additionally verifies that it issued this capture during the current
attachment; a fabricated project receipt does not establish GUI origin. Attach,
Session-lifetime and private-fixture guards still apply. The owner retains the
latest128 captures; admit figures before detaching, changing source, or closing
the assigned Viewer. Capture verification does not execute an authored handler.

The returned `installed_path` is `images/remote-waveform.png`. Reference it on
its own Markdown image line, for example
`a Markdown image link to the installed-module path `images/remote-waveform.png``. The existing Documentation
Browser renders it and opens the full-size image. Images must be ordinary,
unlinked, noninterlaced8-bit PNGs at most8MiB and4096×4096 pixels. At most32 images
and16MiB total are admitted. Original capture bytes are preserved, including inert
native-capture canvas metadata. There is no image resizer, decoder choice, remote
URL or screenshot-to-icon conversion in this operation.

`{"operation":"list"}` returns the logical installed path inventory and original
capture provenance. Repeating add for an existing asset ID explicitly replaces
that resource after all checks pass. `{"operation":"remove","asset_id":"..."}`
removes its binding; older content-addressed project bytes remain available for
historical receipts. Neither operation changes C++ source or Builder design.

Normal export validates image hashes, dimensions, aggregate size and every
Markdown image reference before writing the standard Module candidate. It includes
installed `images/ID.png`, `review/manual-assets.json`, editable
`source/manual-assets.json` and exact content-addressed source PNGs. An admitted
historical figure retains its original source snapshot when the guide is revised;
it is not relabeled as a capture of newer source. Missing images fail export.
The normal Plugin Manager remains the sole installer. Project receipts are
cooperative provenance under the documented tool grant, not a signed archive or
a claim of account-wide hostile filesystem isolation.

Dev108 scientific form admission adds `scientific_view_v1`, extending the explicit
document profile with individually requested SCIENTIFIC_EXECUTION_API_v1@1
operations: `node_list,circuit_prepare,submit,status,cancel,reconnect,log,import_table`.
Legacy profiles retain denial. Fixed C++ methods return no arbitrary strings,
tokens, paths or vectors:

| Method | Exact component arguments / effect |
| --- | --- |
| `host.scientific_discover(form)` | declared scientific section; populates its registered destination choice |
| `host.scientific_prepare(diagram,form)` | existing native2d diagram plus declared typed parameter form; displays exact snapshot/netlist and stores preparation only in host RAM |
| `host.scientific_submit(form)` | same prepared section; original durable Job ID/guards enter existing Viewer domain state |
| `host.scientific_status(form)` | genuine original Job state |
| `host.scientific_cancel(form)` | existing Job cancellation |
| `host.scientific_reconnect(form)` | same Job reference after reopen; never resubmits or falls back |
| `host.scientific_log(form)` | bounded actual Job log into declared log component |
| `host.scientific_import(form,dataset_selector)` | completed coherent waveform to canonical Dataset, with source guard and actual provenance |

All component arguments are one-based indices in the exact Builder design,
validated against their declared types. A `section` form declares
`scientific_provider=core.ngspice.circuit`, `scientific_parameters` (dictionary
from provider parameter name to existing scalar component ID),
`scientific_destination` (choice/combobox ID), `scientific_status` (label/status
ID), and `scientific_log` (log ID). Add controls first, then apply all form profile
properties atomically through the existing Builder `properties` edit. Design
requirements include SCIENTIFIC_EXECUTION_API_v1@1 and the Native2D/UI owners.
Unknown parameters, absent targets or incompatible types fail validation.

The compiled worker emits bounded operation plans only. After successful native
execution and unchanged source checks, trusted GUI Host invokes the public
scientific operations. It owns bounded polling/display, preparation cleanup and
canonical Job/domain-state capture; closing detaches the view while durable Jobs
remain with Script Job. Remote UNAVAILABLE is explicit. Submission and publication
have genuine side effects and are not executed by headless CLI Run. CLI test
success therefore proves admission/typed plans, not a simulation or GUI PASS.
Dataset publication receipts remain separate from Job completion. The declared
Plot, captured Numeric expression/interpolation/complex/statistical forms and
bounded physical sweep contracts below are implemented through their existing
public owners. They grant no arbitrary vector accessor or numerical-library
execution to authored C++.

`viewerDevelopmentRequest operation project callback ?options?` dispatches the
approved init, validate, build, run, test, export, api, inspect, manual_asset,
save, check_source, grant, facility_request, builder, debug, debug_control,
debug_status, gui_test and workspace_upgrade_review operations. Each retains
its documented typed shape and admission guards. Callback receives
the same inert `{ok result}` or `{ok 0 error code detail}` fields as CLI JSON.
Options admit only module_id, typed event/state and bounded source/file payload.
`save` writes original handlers.cpp, project.json or inert MANUAL.md through the
same Linux project-write backend. MANUAL.md is optional, bounded to 256 KiB of
UTF-8 without NULs and cannot be a symlink, hardlink or directory. It adds no
runtime capability or source execution. Export preserves its exact bytes as both
the ordinary installed MANUAL.md guide and source/MANUAL.md, reports its SHA256,
and routes Help through the existing Documentation Browser. Projects without a
manual retain the legacy generated guide. `check_source` applies the actual Clang lexer/AST and
requested profile before the GUI accepts an import; it produces no object code.
Invalid source/project JSON can still be saved for repair, but cannot bypass a
future Validate/Build/Run admission. A source payload is at most64KiB valid UTF-8.

`viewerDevelopmentPreview project ?module? ?provider?` validates before composing
the design; the loading window is trusted CORE UI. After admission and exact
three-file SHA comparison, the original public Builder constructors mount the
interface and a bounded compiled Open event runs in a separate native worker.
`viewerDevelopmentInvoke window action` maps an admitted declared control to a
typed C++ event. Returned UI operations are applied only after successful worker
completion and unchanged source SHA. Closing cancels the owned request and
releases native children. No authored C++ library is loaded into the Tk process.

`viewerDevelopmentInstalledOpen module provider root ?context?` requires the
actual Plugin Manager registration, uses the installed original source, and
revalidates/rebuilds against the current fixed SDK. A shipped green report or
binary alone cannot authorize execution. Export creates an ordinary candidate,
not an active plugin or implicit installation.

## Facility matrix

| Facility | Author exposure / authorization | Independent owner / evidence |
|---|---|---|
| C++ scalar locals, conditions, switch, loops, scalar helpers | Actual resolved Clang AST positive allowlist | Fixed Clang19 lexer/AST policy, rejected before object generation |
| Fixed Event and State | Literal indices0..15, finite scalar fields, counter | Versioned automatically supplied SDK v1 |
| Host.text / number / flag | Declared compatible component; bounded literal/finite scalar/boolean | Public Viewer GUI Host, no Tcl/eval/widget pointer |
| Host.demo | Matching0 Native2D,1 Plot,2 Native3D; requested facility/profile | B1 RAM native owners, no scientific publication |
| Host.numeric_add | numeric_view_v1 + requested array_binary.add | Real public math.numeric NUMERIC_API_v1 |
| Host.numeric_sqrt | numeric_view_v1 + requested array_unary.sqrt | Same public Numeric owner, finite nonnegative scalar |
| I/O, processes, external headers, std/math libraries, pointers, casts, allocation, modules/preprocessors | Unavailable and rejected | Actual raw tokens and resolved AST, no author flags |
| Recursive/indirect author calls, attributes, assembly, external declarations | Unavailable and rejected | Resolved call graph and declaration/type ownership |
| Canonical Workspace/History/publish | Unavailable in read-only SDK profiles | Existing canonical owners remain separate |
| Python authoring/imports/eval/reflection | Disabled | No restricted-Python security PASS is claimed |

The API catalog separately records installed public API/version, exposed SDK
subset, permitted operations and exact unavailable reasons. Missing public
versions produce actionable `CORE_API_GAP.json`; an existing unauthorized
operation is `CAPABILITY_DENIED`. Authors cannot add compiler flags, headers,
policy, dependencies or alternate adapters via project metadata.

## Actual write grant and bounded processes

Every post-init backend stage irreversibly applies Linux Landlock plus
no_new_privs to that tool process and descendants. Filesystem create/write/remove,
rename/refer and truncate are denied outside the selected ordinary project.
Protected CORE, active installation, package repository, restore assets and
other projects cannot be written through this grant. Symlink/hardlink/special
file projects are refused. This is an actual project-write **tool grant**, not
a claim that the shared login UID is globally converted into a separate account.
Read access and some metadata operations remain outside its protection.

The fixed compiler has syntax/build time/output/address-space limits. Admitted
C++ runs in a separate native worker with CPU/address-space/output/wall limits;
typed requests broker only enumerated operations through public owners. Worker
crash, CPU exhaustion, timeout or cancellation discards incomplete UI operations.
Owned process groups are terminated, and the main GUI remains alive. This is a
cooperative architecture/quality environment, not a hostile-native-code sandbox
certification. See the installed [developer manual](../../plugins/modules/viewer.development_workspace/MANUAL.md)
for project schema, CLI examples, exact restrictions, author source preservation,
capability requests and package review workflow.


Dev108 scientific admission remains explicit: `Host.numeric_exp(value)` is the
bounded scalar `NUMERIC_API_v1` `array_unary.exp` operation in `numeric_view_v1`.
The project must request it. It calls the existing Numeric owner unchanged and
rejects nonfinite input/output. No alternate mathematical implementation or
library was added. Scientific Execution, Script Job and Parallel Execution are
now discoverable in the approved catalog but remain unavailable in authored C++
until their actual typed SDK contracts are approved.

`builder` `icon_import` takes five arguments: absolute project-owned/shared CORE
asset path, logical ID, title, category, license. It invokes the same public
bounded icon admission and model edit as the GUI. `properties` takes component
ID and a dictionary to merge in one transaction; `icon` uses the documented
Viewer GUI Host catalog put/rename/remove methods. No command identity changes.

`{"operation":"icon","arguments":["catalog"]}` discovers shared sources
read-only through the existing Builder operation. Its `builder.catalog.icons`
dictionary contains fixed library IDs, titles, categories, licenses, admitted
absolute source paths, SHA256, source formats and dimensions. No caller path,
filter, filesystem listing or source reader is accepted. The design and Builder
Undo/Redo file remain unchanged; ordinary request provenance is still recorded.
Select a returned entry and pass its path/ID/provenance to existing `icon_import`,
then assign typed properties. Import remains bounded and revalidates actual
image bytes. GUI **Icon Library → Add shared icon…** uses this same fixed source catalog;
**Import** retains its separate project-owned image workflow.

The unchanged `gxtxt.viewer_design_model.v1` retains at most50 states across
past/future plus its current and saved designs. CLI persistence permits512MiB
for the complete UTF-8 history (52 bounded4MiB designs plus Tcl quoting), rather
than incorrectly imposing one design's limit on the whole history. Each snapshot
retains its4MiB bound; no history is discarded to repair an oversized old file.
Schema/state counts and exact design/history/response bytes are checked before
commit. Existing per-file atomic writes restore both original byte sequences on
ordinary commit failure; this is not a crash-atomic transaction. Concurrent file
changes reject the request. Existing external-GUI-edit history invalidation is
unchanged. Builder-only CORE responses permit16MiB and its existing GUI request
transport64MiB, retaining the complete design/capability response schema; other
operations keep their prior output limits. Invalid input fails before mutation.

The current trusted C++ debugger adds `debug PROJECT --breakpoints '[8,9]'`,
`debug_status PROJECT`, and `debug_control PROJECT` with JSON stdin containing
`operation`, exact `source_sha256` and optional bounded `frame` index. Controls
are `continue`, `into`, `over`, `out`, `pause`, `stop`, `frame`; no expression or
GDB command input exists. The same fixed compiler/AST and broker are used.
Debug builds have real `-O0 -g3` symbols mapped to original handlers.cpp, and a
fixed GDB/MI2 backend runs the same native ABI worker in the existing managed
auxiliary process tree. Active execution retains its bounded CPU/wall budget;
paused time is limited to 15 minutes. Source/design/facility revision change
cancels old execution. Breakpoints are immutable during the active Debug Job;
Stop to edit them. Stack/local values reflect real GDB stops, including genuine
uninitialized values before assignment; no numerical state is guessed.

Use this structured debugger as a productivity tool for real C++ problems.
`debug` is long-lived; keep its managed request/session running while separate
`debug_status` and `debug_control` calls inspect/control it. An optional bounded
`--debug-token` on all three operations isolates one run. Poll actual state and
sequence; stack/locals may finish populating after the first PAUSED report.
Use `--event` for the actual declared one-based component/kind/value and optional
valid `--state` for16 finite values plus uint32 counter. Step/frame controls
require PAUSED; wait for a pending command before sending another. Stop before
editing fixed breakpoints or changed sources. No GDB invocation/expression/command
input or private-file workaround is admitted. A concise `CPP_DEBUGGER_BUG`
report should include the public operation, source identity, observed state/error
and reproduction; the CORE owner fixes confirmed infrastructure defects and
returns the original operation for retry. Ordinary author troubleshooting needs
no graphical-debugger demonstration or screenshot; independent GUI QA is separate.


### Dev108 Native2D diagram SDK extension (validation in progress)

The existing `native2d` Builder component accepts optional `diagram_catalog`
(`electrical.basic` or `flow.basic`) and stable `document_slot`. The Design →
Native2D diagram profile dialog supplies typed catalog/slot controls. It opens the
same CORE viewport in real Preview when a private/current Session is available.
No raw diagram Tcl, native pointers or Session filenames enter the author SDK.

A project must explicitly request `NATIVE2D_VIEWPORT_HOST_v1` version 1 operations
`diagram_create` and `diagram_command`. The fixed C++ SDK provides:

```cpp
host.diagram_open(3);
host.diagram_tool(3, "resistor");
host.diagram_command(3, "fit");
```

Indices are one-based design component order, not arbitrary widget IDs.
`diagram_open` opens the current binding or creates a canonical document for that
slot. `diagram_tool` accepts registered catalog symbol IDs or `select`, `wire`,
`junction`, `label`, `pan`, `probe`. `diagram_command` accepts `fit`, `properties`,
`rotate`, `delete`. Unknown tools/commands are refused. Native pointer gestures
place/select/move/connect actual stable terminals. Double-click opens the typed
symbol-property controls; `R` rotates a selected symbol, Delete removes it, Esc
selects, W wires, J places a junction, P pans and F fits. A geometric crossing
creates no electrical connection. Explicit pin/junction references own topology.

CLI Run returns **planned** admitted operations; the real GUI applies them only
following a successful source-snapshot-checked event. It is not a headless
scientific execution receipt. The component uses Interactive Document for
canonical state, existing Native2D geometry/Viewport Host/snapshot renderer for
presentation, and existing Workspace/History components for save/reopen and
Undo/Redo. No new persistent diagram registry or renderer exists. Numerical
simulation, scientific vectors, Dataset/Plot adoption and the complete independent
SPICE Viewer remain outside this initial SDK slice and must pass their open gaps.


For canonical diagram Workspace/History, use explicit `document_view_v1` and
request `SESSION_WORKSPACE_API_v1` @1 operations `create,get,update,list`, plus
`SCIENTIFIC_RECIPE_API_v1` @1 host operations
`scientificHistoryViewerRecord,scientificHistoryViewerNavigate`. These authorize
only the corresponding declared Viewer components and its guarded document state.
They expose no arbitrary SDK call, author callback, file path or recipe evaluator.
The original synthetic/numeric profiles still reject canonical lifecycle controls.
A declared valid Native2D diagram profile is mandatory for this admission.


## Restricted canonical Plot binding (dev108)

Explicit PLOT_DATASET_API_v4@4 capability `widgetCreate` is admitted in document
and scientific profiles. `host.plot_discover(form_index)` populates the declared
canonical Dataset-variable choices used by that binding; `host.plot_bind(plot_index,
form_index)` emits a typed plan to mount the selected canonical PlotSpec. Form
section fields are `plot_dataset`, `plot_x`, `plot_y`, optional `plot_probe`;
the Plot component's optional `plot_form` attaches exact native source-row probing.
All indices/types and design requirements are validated. No paths, arbitrary
PlotSpecs, author vectors or numerical calculations are accepted. Actual rendering,
units, source identity, Dataset access and Workspace restoration retain existing
public owners. Headless Run verifies plans only; real GUI/Dataset evidence is
separate. Source metadata and pointer probing do not grant C++ raw array access.

## Optional installed native GUI tests (dev108; GAP014)

The existing declared Scientific section also supports the optional
`scientific_probe_diagram`, `scientific_probe_plot`, `scientific_probe_mode`
references documented in `VIEWER_GUI_HOST_API_v1`. Configure these with the
ordinary Builder `properties` operation; the mode is a declared voltage/current
choice. Existing `diagram_tool(...,"probe")` now uses the shared declared bridge
when present. It maps genuine stable terminals via public Scientific inspection
and exact completed-publication provenance, then uses canonical Plot binding.
Validation requires existing `circuit_prepare`, `diagram_command`, `widgetCreate`
grants. No new C++ SDK method, endpoint reader, raw vectors, solver or numeric
grant is introduced. Missing/ground/current/foreign/stale sources fail explicitly
and retain the last valid frame. Real owner and same-author retests are required.

CLI `gui_test PROJECT` accepts one bounded JSON object on stdin. It is an author
tool, not a C++ SDK operation or an automatic extension of runtime permissions.
First save/build/export the project, install its standard package normally, open
a Session and the same project in Development Workspace, then choose Develop →
Enable installed native GUI testing. The three project hashes must exactly match
installed source. This calls public `viewerDevelopmentGuiTestAttach project`;
`viewerDevelopmentGuiTestDetach project` revokes it. No CLI operation can attach
itself. An attachment is limited to its current GUI process, Session and hashes.

The project-local `derived/gui-test` command/status mailbox follows the existing
native debugger pattern. It is data, never Tcl evaluation. A request must name
only an enumerated operation and the exact fields below. No module, widget path,
script, command, file destination, executable or desktop coordinate is accepted.

| Operation | Extra fields | Behavior |
|---|---|---|
| open | none | Opens only the assigned normally installed Viewer in a new native window |
| workspace_open | workspace_id | Resumes a canonical saved Workspace in the current Session through its registered installed factory; requires exact module/provider and all three attached project snapshot hashes; close any existing assigned Viewer first |
| workspace_save | none | Saves only the current assigned Viewer through its existing public Session Workspace Save owner; returns canonical Workspace ID and generation/revision/SHA stamp; no supplied ID/path/payload |
| status | none | Returns actual C++ busy/status and canonical bindings/Jobs/values |
| capture | none | Captures that native window frame, returns project-local PNG/SHA/geometry |
| capture_verify | capture_id | Verifies an exact32-hex capture UUID against this live attachment's RAM record and original file SHA |
| capture_preview | capture_id | Same live verification, then delivers original PNG as `image_content` MIME/base64 plus SHA, dimensions, source snapshot, Session and geometry; ordinary file only,2MiB/4096px maximum |
| close | none | Closes only the attached Viewer |
| click | component | Native click on a declared visible action or enabled toggle/checkbutton; boolean changes use the existing UIField commit and declared change-action grant |
| tab | component | Native selection of a declared tab |
| choice | component,value | Native selection from actual current choice/Dataset choices |
| text | component,value | Native entry editing of a declared scalar field |
| pointer | component,x,y,phase | Diagram world coordinate through public world_to_device; phase click/double/press/move/release; point must lie inside the visible assigned viewport |
| plot_pointer | component,x,y; optional phase | Native input on a declared visible Plot; x/y are normalized0..1 fractions of its own device bounds. Default click returns actual public hit receipt. Phase may be click,double,wheel_up,wheel_down,press,move,release; press/move/release is an owned middle-button pan on that same Plot |
| key | component, key | Actual native keyboard input: bound mapped Plot permits Escape only; diagram permits the documented schematic keys; source/Session lifetime, ownership and visible viewport guards remain |
| property | component,field,value | Edit an attribute in the actual already-open diagram symbol properties dialog |
| properties_commit / properties_close | component | Native click on actual dialog Apply / Close |
| wire_route | component, command; index only for select | Existing owned wire Properties draft: select a zero-based bend0..127 by actual native Tree row click, or add/replace/remove/up/down by its actual enabled button. No widget path, route payload or Document write is accepted. |
| label | component,field,value | Type into the actual already-open endpoint net-label popup; `field` must be `name` |
| label_apply / label_close | component | Native click on that popup Apply / Cancel; ordinary public label validation owns commit |
| resize | width,height | Native window-manager resize of only the attached Viewer; integer client pixels640..1880 by480..1100, further bounded to the actual display; returns verified actual geometry |

For example, `{"operation":"workspace_open","workspace_id":"idoc_0002"}`
uses the existing Session Workspace owner, resource validation and normal restricted
runtime factory. Poll `status` until compiled validation/open finishes; canonical
bindings, domain state and `workspace_id` identify the actual restored circuit,
Jobs, Dataset and Plot. Restore itself neither resubmits scientific Jobs nor
recalculates results. Unknown, foreign or mismatched saved snapshots are refused
before opening a window. Already-open Workspaces are not adopted or closed by
this operation. GUI testing deliberately requires exact saved snapshots; normal
interactive Workspace presentation-upgrade compatibility remains unchanged.

`capture` additionally accepts the exact pair `component,dialog`, where dialog
is `net_label` or `properties`, to capture only that declared schematic's existing
mapped native dialog. Its actual Document binding and transient window owner
must match. This returns an ordinary capture UUID usable by verified preview and
manual-asset admission; arbitrary paths/window handles are never accepted.
Label Properties reuse `property` with actual registered `name`, `offset_x`,
`offset_y` fields, then properties_commit/properties_close. Invalid names/offsets
are rejected by the original Native2D owner and retain prior scientific state.

Selecting a wire and invoking the same Properties action opens its reusable
Native2D editor. `property` accepts its actual typed `start`, `end`, `point_x`
and `point_y` fields. Endpoint choices are friendly names for existing stable
component pins or junctions; they cannot create implicit coordinate joins.
`wire_route` changes only the open dialog's draft. Apply sends one ordinary
canonical `route` edit through the existing source guard and History owner;
Close discards unapplied changes. Routes retain the wire ID and allow at most128
ordered finite bend points within+/-1000000 display units. Add inserts after the
selected bend, or appends when none is selected. Replace/remove/reorder require
an appropriate selection. The current owned editor appears under
`status.properties.COMPONENT`, with its stable wire ID, opening source receipt,
typed values, endpoint choices, draft route, zero-based selected index (-1 for
none), and visible diagnostic. This describes only the assigned mapped dialog.
Invalid endpoints, equal endpoints, malformed bends and stale opening receipts
leave the canonical diagram and redo history intact. Undo/Redo restore committed
wire topology and bends through existing Scientific History.

For example, after selecting a wire and opening Properties:
`{"operation":"property","component":"graphics","field":"point_x","value":"40"}`,
then the corresponding `point_y` field, then
`{"operation":"wire_route","component":"graphics","command":"add"}` and
`{"operation":"properties_commit","component":"graphics"}`. To select an
existing bend, use `{"operation":"wire_route","component":"graphics","command":"select","index":0}`.
The logical component identity must be declared by the project's design.

When a compiled request fails before entering the host callback, public GUI
status includes the bounded original `host_error` and `error_code`; it does not
report an unexplained FAILED state. A successful solver Job is independent of
that presentation request: retry Poll/Publish on the same Job after correcting
the diagnosed infrastructure problem rather than resubmitting scientific work.

`component` is a declared logical ID. Controls hidden behind tabs reject. Native
input is sent by the trusted GUI owner using fixed X11 argument lists; authors
never obtain X11, arbitrary shell or private widget-path access. Property choices
come from the actual UI Field descriptor and ordinary Apply validates/commits.
No scientific calculation occurs in this transport; scientific actions still
call the original compiled handler and trusted public service broker.

Each receipt contains the exact source identity, Session, operation and observed
runtime state. Status includes current public choice lists, bounded read-only
text, public diagram catalog/pin-world metadata, bounded public native Plot
receipts (`plot_receipts`), and History cursor/count; full
History snapshots are not copied into each status response. These are actual
owner receipts, not guessed generated Variable IDs or point offsets. A successful click is not proof that an asynchronous simulation
completed: poll status and inspect its canonical Job reference/state. CLI timeout
does not imply action cancellation; inspect the pending action before retrying.
These project evidence files are not security tokens or substitutes for source
validation, canonical Job/Dataset provenance or independent primary GUI review.
Real GUI, stale-source, denial and author workflow acceptance are tracked in the
GAP ledger; initial implementation alone is not a PASS.
## Declared Numeric SDK operations (dev108; GAP004 partial extension)

### Workspace compatibility for presentation changes

New validation reports include `workspace_callback_contract_sha256`, persisted
by the trusted host as `domain_state.restricted_cpp.callback_contract`. This
existing Workspace envelope permits an icon catalog/binding/presentation or
layout/version-only update to restore identical callbacks/state. The contract
retains exact C++ source, profile, capability grants, component declaration
ordinals/IDs/types/parents, scalar defaults, handlers, scientific references and
all unknown fields. Only icons/state images/presentation/placement/size/spacing,
container command-icons, component layout and top-level title/geometry/origin/
version are excluded; project version/provenance/test metadata are excluded.
Scientific Documents, source revisions, Dataset bindings and native state remain
guarded by their original owners. Live invocation still requires all three exact
validated project hashes; editing a live project requires closing/reopening.
Legacy Workspaces without the contract retain exact-snapshot restoration only.
Source/profile/grant/default/command/component changes cannot opt into this
compatibility by changing a snapshot alone. This additive persistence contract
is not a replacement Workspace identity or a new API family.

The fixed SDK adds five void methods taking declared one-based component indices:
`numeric_discover(form)`, `numeric_evaluate(form)`,
`numeric_statistics(form)`, `numeric_compare(form)`,
`numeric_publish(form,dataset_selector)`. They create typed plans only; a
successful, source-guarded compiled event is required before the GUI Host applies
them in its real Session. CLI `run` is not proof of numerical GUI execution.
The section/control contract and persistence are documented in
`VIEWER_GUI_HOST_API_v1.md`. No vectors, callbacks, expressions as C++ arguments,
filesystem destinations, scripts, new libraries or arbitrary CORE dispatch are
granted to author code.

Discover/Evaluate require explicit `NUMERIC_API_v1` `dataset_expression`.
Statistics requires all four admitted choices: `statistics`, `array_reduce.rms`,
`array_reduce.minimum`, `array_reduce.maximum`. Compare requires
`residual_metrics` and `dataset_expression`. Publish requires the separately
requested `DATASET_PUBLICATION_API_v2@2` `datasetPublicationV2Finalize` capability,
scoped exclusively to the declared Numeric result and selector transaction.
It does not expose arbitrary writer lifecycle calls to C++. The original scalar
template retains only its original scalar grants. Legacy project permissions
are not broadened implicitly. Generated packages using these methods require
dev108. A `document_view_v1`/`scientific_view_v1` project may declare ordinary
Workspace/History with an explicitly granted Numeric form and their existing
scoped lifecycle capabilities without declaring an artificial schematic.

Primary contract evidence: `numeric-sdk-contract01` contains actual compiled
five-operation plans and wrong-form/wrong-target/incomplete-grant denials.
Actual real Debian CORE form validation and separate restricted author adoption
remain distinct evidence. This is not completion of vector interpolation,
complex AC display, statistical persistence or sweep GUI requirements.
## Fixed source and public manual inspection (dev108; GAP015)

`inspect PROJECT --target TARGET` returns inert UTF-8 `content`, exact `sha256`,
`bytes` and `read_only:true`. Targets are only `handlers.cpp`, `project.json`,
`MANUAL.md`, `design.gxtxt-viewer`, `sdk_v1`. Source/metadata/SDK limit64KiB;
the inert manual alone has a256KiB limit matching save/inspect/export.
the existing bounded Builder design limit is4MiB. Invalid JSON/source stays
inspectable for repair; Validate/Build still enforce all original admission.
Missing optional manuals fail explicitly. Symlink/hardlink/oversize/changing files
are refused; no source is executed, regenerated or parsed as a command.

`api PROJECT --document VIEWER_GUI_HOST_API_v1` (optional `.md`) returns the same
exact text receipt for an installed catalogued public API manual, bounded1MiB.
It accepts an API identity only, never a path, file URI, parent traversal or
private/project/generated filename. Trusted catalog provider/documentation
metadata resolves the installed manual under normal framework/module roots.
Unavailable manuals fail explicitly; a catalog entry does not invent content.
The fixed companion identity `VIEWER_GUI_DESIGN_v1` (optional `.md`) reads the
public declarative design reference owned by catalogued `VIEWER_GUI_HOST_API_v1`.
It is documentation within that existing family, not another callable API;
arbitrary linked documents and paths remain refused.
The fixed companion `NUMERIC_EXPRESSION_OPERATIONS` (optional `.md`) similarly
reads the public Dataset-expression grammar, functions and physical-unit
reference owned by installed `NUMERIC_API_v1`. The historical unversioned
document title does not create a new API identity or runtime capability. Both
companions require their owning public API in the installed catalog and use the
same ordinary-file, UTF-8, link, source-change and1MiB inspection guards.

GUI host equivalents are `viewerDevelopmentRequest inspect PROJECT CALLBACK
{target TARGET}` and `viewerDevelopmentRequest api PROJECT CALLBACK
{document API_ID}`. These extend the existing Development source browser/API
explorer owner. They grant no runtime C++ API or arbitrary filesystem read.
Primary `inspection-contract01` verifies exact source/public docs and denied
private/path/link/bounds targets, including repair of invalid project JSON.
### Existing GUI laboratory policy and lifetime

Native developer testing reuses `viewerGuiTestFixtureValidate`, not a second
global test framework. Enable requires the current Session to be below an
explicitly marked private laboratory root containing an ordinary bounded
`.gxtxt-gui-test-fixture` file. The trusted operator designates that root before
the Workspace action; the constrained author request cannot nominate a Session,
create a marker or provide permitted commands. The source-identical installed
design supplies permitted action IDs. Ordinary user Sessions without a marker
are refused. Exact path ancestry replaces glob matching, including roots with
literal glob characters; symlink/hardlinked markers are refused.

Attachment and every action additionally guard `interactiveDocumentSessionToken`,
so closing/reopening even the same Session path invalidates the old attachment.
The existing laboratory replay handles logical invoke/resize/select/checkpoint
scenarios and fixture permissions. It does not provide a source-bound author
project mailbox, world-coordinate/native pointer/property input or native screen
PNG receipt. Those bounded developer facilities therefore remain in the current
Development owner while calling the same GUI Host, laboratory fixture validator,
Native2D, Plot and resource owners. No arbitrary Tcl or test script is accepted.

## Explicit reviewed Workspace copies (dev108, GAP031)

Ordinary `workspace_open` retains its exact installed source/design/project snapshot guard. An older Workspace can be reviewed explicitly through the current Session and saved project, using `gui_test` with `{"operation":"workspace_review","workspace_id":"idoc_0002"}`. The assigned Viewer must be closed. Review returns a live `review_id`, the original161 (or actual prior count) preserved ordinals, appended presentation controls, unchanged source digest and the admitted target snapshot. It changes no canonical Workspace, source or scientific result.

After inspecting that report, submit `{"operation":"workspace_upgrade","review_id":"review-...-..."}`. This creates a separately named canonical Workspace through existing Workspace export/import, checks every retained History state including redo, preserves the16 C++ state values/counter, scientific identities, Plot bindings, notes, preview and nested resources, and adds only the admitted new control defaults. Export adds a managed archive resource to the original resource store; its canonical payload/revision and all source Documents/Jobs/Datasets remain unchanged. Open the returned new `workspace_id` with ordinary `workspace_open`. A new review for the same project/Workspace invalidates its previous review token. Tokens are valid only in the issuing GUI process/Session lifetime.

Review is intentionally narrow and fails closed: the C++ bytes, profile, grants, original component ordinals/defaults/handler and scientific callback contracts must be unchanged. Currently reviewed additions comprise an explicit voltage/current scientific-probe choice and links to the original electrical diagram and Plot, inert labels/containers, and existing reserved fit/zoom navigation actions. Arbitrary source evolution requires its own supported compatibility design; no author migration code or arbitrary hash rewrite is accepted. Source, project, original Workspace and Session stamps are rechecked at apply. A changed original, unknown token, foreign module, malformed History, new control collision or unavailable managed resource rejects the copy; failed new allocation is removed. This never runs Numeric operations, submits Jobs or contacts remote nodes.

Human authors use **Develop → Review saved Workspace upgrade…**, select the canonical saved item, choose **Review selected**, inspect the report and then **Create upgraded copy**. Trusted hosts use `viewerDevelopmentWorkspaceReview project workspace_id callback` and `viewerDevelopmentWorkspaceUpgrade project review_id`. The fixed structured CLI `workspace_upgrade_review` only reviews supplied inert old declaration/snapshot/contract text; it has no Session filesystem authority and cannot apply state. The trusted GUI owns canonical resolution and copying. These are extensions of the existing Development and Session Workspace owners, with no new API family.

GAP032 extends the existing `key` GUI-test action to `Escape` on an already bound, mapped, unobscured declared Plot. This sends the actual native keyboard event to that Plot, clearing its source cursor through the normal host binding. Other Plot keys, hidden/unbound/foreign targets and input during an owned pan remain denied. Existing Diagram keys retain their enum and now also require an unobscured declared viewport. No global desktop key delivery or new restricted SDK operation is exposed.
