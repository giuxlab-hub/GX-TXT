# Restricted Viewer Development API v1

Installed and development Viewer opens accept `workspace_name` only together
with `workspace_id new`, as emitted by the normal **New Workspace** form. The
existing Workspace owner validates the name before the Viewer opens. The
shared GUI retains it until the first normal Save; opening a saved Workspace
does not rename it. Unknown context keys remain rejected. This context change
uses the packaged binary for installed Viewers and adds no compiler fallback.

Dev109 adds reviewed typed SDK methods `Host.catalog_refresh(unsigned form)`,
`Host.catalog_inspect(unsigned form)` and
`Host.catalog_action(unsigned form, const char* action)`. They require a declared
GUI Host section with `catalog_owner scientific_libraries` and exact manager API
grants. Refresh maps to libraryCatalogPage; inspect to getLibraryCapabilities;
each finite action maps to its separately requested manager operation. Invalid
form/action/grant rejects at the existing broker. The Host applies successful
source-guarded event plans through the existing manager and GUI owners. No
arbitrary invoke, provider import or registry path is exposed to the author.
See the [complete Step2 public contract](SCIENTIFIC_LIBRARY_MANAGER_API_v1.md#step2-catalog-capability-declarations-and-provider-delegation-dev109)
for declarations, shapes, action vocabulary, bounds and lifecycle.

The existing source-identical private-fixture `gui_test` additionally admits
`{"operation":"list_select","component":"DECLARED_LIST","index":0}`.
Index is an existing row0..999; the host scrolls that actual list row into view,
checks the owned pointer hit and change-action grant, then sends native input.
It cannot nominate a widget path or manager ID. Direct `entry` and `combobox`
controls use their actual leaves for existing text/choice operations. Status
adds read-only `lists` (count, first1000 labels bounded256characters, selection),
`tables` (columns/count, first50 rows with1024characters per cell, selection) and
`library_catalogs` summaries from the public CatalogDescribe owner (current
generation/selection/request/page and capability strings bounded4096characters).
These are bounded QA observations; full scientific records remain public-owner
data. They do not create an author filesystem or administration bypass.
For declared read-only tables, `table_select` takes `component` and an existing
zero-based `index`0..999 and clicks that actual native row. `table_scroll` takes
`component`, `axis` (`x` or `y`) and `direction` (`backward` or `forward`); it
clicks a visible arrow of the component's declared native scrollbar and reports
before/after view fractions and the actual pointer. A theme without such an
arrow is rejected explicitly. `table_copy` takes only `component`, requires an
actual selected row and sends native Ctrl+C. Its clipboard observation contains
the first4096 characters plus full character/UTF-8 byte counts, marked bounded.
The receipt requires observing the existing copy service complete during the
actual Ctrl+C event, with unchanged selected values and matching clipboard.
An old clipboard after a rejected/missing copy cannot pass. Data values follow
the existing tab-separated contract; source-row labels are correlated separately.
Table status includes declared `scrollbars` and current `xview`/`yview` fractions.
These operations never set a cell value, synthesize a selection callback or
directly change a table's scroll fraction.
The same table input operations also accept a declared `document` whose `kind`
is `table`, bound to a current canonical Dataset. No internal child widget path
is accepted. Its `document_receipts` status comes from the public table Preview
owner and retains the actual Dataset ID, source rows and declared column schema.
For that document, `table_page` takes `component` and `command`:
`previous`, `next`, `first`, `last`, `goto` or `schema`. Only `goto` also takes
`row`, a bounded integer literal entered into the real Go-to-source-row field.
The public CLI admits these same six commands and preserves exact decimal row
identities, including integers beyond binary64 precision. CLI admission still
requires the normal live Workspace attachment before any native input.
First/last use that same visible field and Go button. `schema` clicks Column
details. Actual native typing/clicks operate the existing pager; the facade does
not set page state or replace its validation. An out-of-range/negative row reaches
the normal validation and preserves the previous page, with its visible status
included in the receipt. Disabled navigation is refused precisely. A nonpaged
`table` still supports selection/scroll/copy and rejects paging. Session/source
attachment checks continue to apply before input and after focus/layout settling.
The catalog summary also retains the public correlated `last_action` receipt;
result scalar strings are bounded4096characters for this GUI-test projection
and marked `result_presentation_bounded=1`. The actual Activity/public owner
retains the manager response independently of automatic capability refresh.

## Compiled artifacts and responsive events (dev109)

Development Build reuses its existing successful artifact while its source,
Builder interface, build-relevant project metadata, SDK, trusted adapter, policy, compiler,
toolchain manifest, effective flags, compile recipe and recorded included-header
bytes match. A changed input requires fresh source AST/design/capability admission
and compilation through the same Build owner. Normal and debug artifacts have
separate receipts. Build reports `artifact_reused=1` and
`code_generation_invoked=0` on reuse. Existing Preview preparation, Run, Test and
Export use the source-bound artifact; they do not rebuild every unchanged event.

Changing only development test events, provenance, package version or interface
presentation retains the compiled binary when the existing callback contract is
identical. Project/interface module and version must agree. Source bytes,
component ordinals/types/defaults, scientific references, capability grants,
profile, unknown semantic fields and every recorded build/header dependency
remain checked. The original compilation receipt is not rewritten.
Export records the current metadata admission in `review/build.json` and retains
the actual compilation receipt as `review/original-build.json`; the binary is
unchanged. Installed admission still requires exact packaged source, interface
and project fingerprints. This exception never enables compilation at runtime.

Build dependency identities use fixed framework-relative roles and content
hashes, rather than the absolute checkout location. Historical absolute receipt
paths are matched only to those same known roles; missing, duplicate, extra or
changed dependencies still invalidate reuse. Recorded SDK/adapter header paths
resolve to the current corresponding inputs; other included headers retain
their original path/content checks. Moving an unchanged development tree or
opening it through its compatibility alias therefore does not require a build.
Compiler bytes, flags, recipe and validation-owner fingerprints remain exact.

Installed applications execute the distributed `native/viewer.so`. Admission
checks binary/build/source/interface correlation, packaged SDK/build fingerprints,
compatible SDK-v1 Event/State/Host and entry ABI, existing adapter-operation
mappings and current public grants. Additive SDK methods do not alone invalidate
an older compatible package. A bounded separate native probe checks runtime
libraries and the actual exported entry after admission. Missing/incompatible
artifacts produce explicit errors and require a matching precompiled package;
installed startup/events do not invoke source AST validation or Build.

The existing Script Job auxiliary owner retains one duplex compiled worker per
Viewer lifetime. Short native events return typed plans through
`scriptJobRequestExchange`; the exchange does not pump Tk input. The host applies
successful, unchanged-source plans through the existing public owners before
returning to queued input. Long-running scientific plans retain their existing
asynchronous service/Job owners. Default exchange timeout preserves the existing
12000ms native wall budget; worker
startup uses5000ms. These limits describe the current transport, not a measured
latency or native GUI acceptance result. Workspace persistence captures the
existing explicit SDK state and callback fingerprint; native process globals
do not gain automatic Workspace serialization.

Development builds publish a new binary inode atomically, so an open Preview
never maps a file that Build truncates. Source changes still invalidate that
Preview's callback snapshot; reopen it for the new explicit build. Ordinary
C/C++ stdout/stderr go to the existing runtime allocation's bounded
`derived/native-output.log`, separately from the typed reply channel.

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

The same `metadata` operation accepts the optional project `catalog` dictionary:

```json
{"operation":"metadata","arguments":["catalog",{"semantic_group":"documents","group_title":"Documents","short_title":"HTML","icon":"html-document"}]}
```

Use an icon ID already admitted into this design by the existing `icon_import`
or icon editor. The normal exporter copies the admitted icon and these semantic
catalog fields into the ordinary Module descriptor. They change catalog
presentation only, without changing compiled handlers or granting capabilities.
Discover shared icon sources with `{"operation":"icon","arguments":["catalog"]}`;
import takes source path, logical ID, title, category and license. Source paths
must belong to the author project or the shared CORE icon catalog.

### Bound read-only document GUI tests (dev109)

These are author-test operations on an explicitly attached, source-identical
private Viewer, not additional authored C++ runtime capabilities. `status` and
`capture` include the actual selector `choices` per component and
`document_receipts` for bound HTML/code documents: actual Text `state`, bounded
`text_prefix` (16,384 characters), rendered character count, `xview`/`yview`,
first/last visible indices, mapped state and pixel dimensions. Canonical source
SHA and identity remain in the ordinary `bindings` receipt.

```json
{"operation":"key","component":"html_content","key":"Page_Down"}
{"operation":"document_pointer","component":"html_content","x":0.5,"y":0.5,"phase":"wheel_down"}
{"operation":"click","component":"html_content"}
```

`document_pointer` accepts only `click`, `wheel_up`, `wheel_down`; x/y are
normalized0..1 within that actual visible read-only component. It accepts no
widget, window, file or desktop path. Document keyboard input permits exactly
`Escape`, `ctrl+f`, `F3`, `shift+F3`, `ctrl+a`, `ctrl+c`, `Home`, `End`,
`ctrl+Home`, `ctrl+End`, `Page_Up`, `Page_Down`, `Up`, `Down`, `Left`, `Right`,
`Tab`, `shift+Tab`. `PageUp`/`PageDown` are aliases for the underscored names.
Find shortcuts act only where the existing source surface provides a Find bar;
they do not add an HTML search implementation. Editing/execution keys reject.
After native `ctrl+c` with a selection, `clipboard_receipt` reports actual
clipboard character/UTF-8 byte counts, SHA256, bounded prefix/completeness and
`matches_selection`; with no selected text it returns `no_selected_text` and
does not read unrelated clipboard contents. `document_find` is code-only and
takes declared component, literal value and `forward`/`backward` direction.

Empty `host.document_bind` selection returns `awaiting_selection` and a prompt;
an incompatible/missing source clears previous content and reports its actual
error. A nonnumeric changed selector emits scalar `Event.value=0`; the typed
Host binding reads the actual declared selection through its existing owner.

To draw an original project icon without writing an asset file, the first
`icon_import` argument may instead be an inline SVG object:

```json
{"operation":"icon_import","arguments":[{"source_format":"svg","source":"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"64\" height=\"64\" viewBox=\"0 0 64 64\"><rect x=\"8\" y=\"4\" width=\"48\" height=\"56\" fill=\"none\" stroke=\"#245678\" stroke-width=\"4\"/></svg>"},"html_document","HTML document","Documents","GPL-3.0-or-later"]}
```

The same icon admission, safe SVG validation, managed rasterization and Builder
Undo/Redo owners process both forms. Inline source has a 256 KiB bound (the
whole author request retains its 64 KiB transport bound), explicit 1–512 pixel
dimensions and at most256 elements. Supported geometry is svg/g/path/rect/
circle/ellipse/line/polyline/polygon with literal paint; script, text, styles,
external resources and references are rejected. Accepted original SVG and PNG
bytes are embedded in the design and preserved by ordinary export. Logical IDs
use lowercase letters, digits and underscore, starting with a letter.

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

The document and scientific profiles also admit the explicitly requested finite
`CONFIGURATION_API_v1/open_page` and `FILE_PUBLICATION_API_v1/publish_bundle`
facilities used by declared EM forms. Their typed Host operations retain the
complete-form and finite-action checks. This does not expose arbitrary
Configuration changes or writer callbacks to C++. Synthetic/numeric profiles
and unreviewed operations remain denied.

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

`viewerDevelopmentPreview project ?module? ?provider?` prepares/reuses the current
development artifact before composing the design; the loading window is trusted
CORE UI. After admission and exact three-file SHA comparison, the original public
Builder constructors mount the interface and a compiled Open event runs in the
managed separate worker lifetime.
`viewerDevelopmentInvoke window action` maps an admitted declared control to a
typed C++ event. Returned UI operations are applied only after successful worker
completion and unchanged source SHA. Closing cancels the owned request and
releases native children. No authored C++ library is loaded into the Tk process.

`viewerDevelopmentInstalledOpen module provider root ?context?` requires the
actual Plugin Manager registration and compatible packaged build/source/interface
identity. It executes `native/viewer.so` in place and allocates temporary runtime
receipts through Resource Management; it does not copy source into a development
project or compile it. Closing cancels the owned compiled worker through Script
Job and releases the temporary allocation with retained diagnostics. Export
creates an ordinary candidate for normal Plugin Manager admission/installation.

## Facility matrix

| Facility | Author exposure / authorization | Independent owner / evidence |
|---|---|---|
| Ordinary C++17 local logic/types/templates/pointers/recursion/RAII/exceptions/concurrency | Real Clang parsing, explicit reviewed headers and typed SDK/entrypoint checks | [Exact current support catalog](CPP_SUPPORT_CATALOG.md); CORE ownership review |
| Fixed Event and State | Literal indices0..15, finite scalar fields, counter | Versioned automatically supplied SDK v1 |
| Host.text / number / flag | Declared compatible component; bounded literal/finite scalar/boolean | Public Viewer GUI Host, no Tcl/eval/widget pointer |
| Host.demo | Matching0 Native2D,1 Plot,2 Native3D; requested facility/profile | B1 RAM native owners, no scientific publication |
| Host.numeric_add | numeric_view_v1 + requested array_binary.add | Real public math.numeric NUMERIC_API_v1 |
| Host.numeric_sqrt | numeric_view_v1 + requested array_unary.sqrt | Same public Numeric owner, finite nonnegative scalar |
| Reviewed C/C++ headers; local files, threads, fork/wait | Admitted for ordinary project logic; canonical framework stores/execution remain public owners | Exact header rationale, actual budgets and toolchain in support catalog |
| Author types, recursive/indirect calls, macros, normal C++ facilities | Supported by actual C++17 toolchain, with fixed public SDK integration | New headers/libraries/compiler flags require purpose-specific architectural review |
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

For a complete declared TeX article form, `source_text` takes `component` and
`value` (at most 4096 UTF-8 bytes). It types through native OS input at the current
source caret or selection. It does not set source through an API, select all,
save, or build. Use an explicit native `key` action with `ctrl+a` when replacement
of the whole draft is intended. The current article generation and source/assets
stamp must still match; the source must be visible and editable. Its `key` action
also accepts ordinary navigation, Return, Delete/BackSpace, source Undo/Redo,
Find/Replace and Copy. `document_find` and click/wheel `document_pointer` accept
this same source. Read-only HTML/code components retain their existing key
restrictions. Native `document_find` queries reject control characters (including
Return, Tab and newline) before input, so typing a query cannot transfer focus
and send its remainder into editable source. The article identity, canonical
content stamp and editability are rechecked after focus/event-loop settlement.
`source_replace` takes `component`, nonempty `query`, `replacement` and `scope`
(`current` or `all`). Both literals are bounded to 4096 UTF-8 bytes and exclude
control characters. It types the actual visible Find/Replace fields and clicks
their normal Next and Replace/Replace all buttons through native input; it never
calls a source setter or replacement API. Source must remain unchanged while
the fields are entered. Normal source Undo remains a separate native key action.
Status/capture receipts include the actual TeX source prefix,
character count, native selection/search and scrolling presentation. These are
author test transports on an explicitly attached installed Viewer; source
changes are committed only through the normal article Save/Build controls.
The additive transport is source implemented; installed native validation remains
required before acceptance.

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
| pointer | component,x,y,phase | Diagram world coordinate through public world_to_device; phase click/double/press/move/release/wheel_up/wheel_down; point must lie inside the visible assigned viewport. Wheel phases deliver actual native buttons4/5; no arbitrary button or desktop destination is accepted. Keyboard actions preserve held pointer buttons so Escape can genuinely cancel an in-progress drag. |
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

The current source-reviewed additive allowance also permits adding the checked
presentation property `diagram_tool {ORIGINAL_DIAGRAM_ID TOOL}` to an **original
action** that did not have it. Its target must be an original declared `native2d`
component with a canonical `diagram_catalog`; complete current GUI Host admission
validates the real catalog tool. It only displays the authoritative viewport's
selected tool. The original C++ bytes/profile/grants/handler/defaults/component
ordinals remain unchanged; it neither intercepts the existing action nor writes
a separate tool state. Review reports `diagram_tool_checked:ACTION_ID` in
`approved_presentation_changes`. Changing/removing an existing binding, adding an
arbitrary callback, changing the original target contracts, or using an appended
replacement diagram remains outside this allowance.

Other currently source-reviewed additive profiles include original-form netlist
consultation, Plot-series controls, checked visibility bindings, inert layout
reparenting into newly appended containers and trusted presentation-menu suffixes,
under the same full original callback/source/grant and retained-History checks.
Their complete model validation still applies; this does not authorize arbitrary
source evolution or migration code. A review receipt is not an applied canonical
copy. The CLI success-status set now includes `REVIEWED_INERT_ADDITIVE_UPGRADE`,
so a successful review returns exit0 consistently with its success payload.
The positive fourteen-binding review and five rejection cases still require
their current-source verification. Actual GUI review/apply and Workspace
preservation evidence remain separately qualified.

GAP032 extends the existing `key` GUI-test action to `Escape` on an already bound, mapped, unobscured declared Plot. This sends the actual native keyboard event to that Plot, clearing its source cursor through the normal host binding. Other Plot keys, hidden/unbound/foreign targets and input during an owned pan remain denied. Existing Diagram keys retain their enum and now also require an unobscured declared viewport. No global desktop key delivery or new restricted SDK operation is exposed.

## Canonical read-only consultation binding (next candidate)

The reviewed `VIEWER_GUI_HOST_API_v1` operation `document_bind` maps to exactly
`host.document_bind(unsigned document, unsigned dataset_selector)`. Both arguments
are one-based original Builder component ordinals. Declare `document {kind
html|pdf|code|table}` and a matching `dataset_selector {content_kind ...}`. The
trusted broker rejects mismatched kinds/types before a GUI plan is applied.
Existing native HTML, Source Surface, PDF reader and Preview paging owners retain
all decoding, source identities, read-only state and lifecycle. See GUI Host's
manual for syntax and limits; no general Document/private file/compile permission
is implied. This does not yet provide editable TeX or managed TeX compilation.

The exact Builder action binding request is
`{"operation":"bind","arguments":["COMPONENT_ID","ACTION_ID","presentation"]}`.
The first ID is the existing action/menu/input component, the second the handler
identity; the third is `unbound`, `presentation` or `mutating`. Selector bindings
use the same arguments and set that component's `change_action`. `save` stdin is
raw UTF-8 source (or raw JSON for `--file project.json`), not a JSON envelope.

## API Browser project and language context

The shared reference transport `--api-browser-tcl` accepts optional `--project`
for a saved C++ project. It reads bounded project inputs and fingerprints them;
it does not validate/compile source, write grants or activate a scientific API.
`cpp_context` distinguishes `NO_PROJECT`, saved metadata and unavailable/invalid
projects. Each family retains actual provider availability and SDK exposure
separately from `cpp_project_status` / `cpp_project_request`.

`cpp_methods` contains exact prototypes and typed call patterns from the current
SDK, linked to the same method-capability requirements used by Validate.
`ADMITTED_REQUEST` means the saved request matches current provider/version and
profile policy. It is not a source validation, successful Build or active runtime
grant. Additional form and finite action requirements still apply. Unrequested
methods and Script Bridge operations without a direct C++ method stay explicit.
Python/Octave references retain the actual registered argument/result contracts
and show syntax for the current language only.

The Workspace passes its selected project through the shared Browser context
owner and refreshes after project metadata Save. Browser-owned Session traces
refresh only the cached selected reference and are disposed with their widget.
No Session transition starts a metadata request, renderer or scientific Job.
The common layout measures actual Treeview rows and font lines to preserve three
list rows/four detail lines at the supported narrow editor size; the reference
text remains scrollable and the main source editor retains its own layout.

## Current C/C++ support and structured aggregate inspection

**Develop → C/C++ support catalog** opens the existing rendered manual window,
with exact current headers/rationales, compiler/runtime choices, SDK signatures
and source fingerprints. Author CLI: `api PROJECT --document CPP_SUPPORT_CATALOG`.
The catalog is generated from actual owners and must pass synchronization check
before packaging; ordinary C/C++ availability never grants canonical owner bypass.

Public `debug_status` includes `inspection_id`, root `locals` and `variable_nodes`.
A node has its opaque `node_id`, actual name/type/value, `child_count`, loaded
`children` identities, `loaded_count`, depth and inspection identity. The initial
state fetches no aggregate members. `debug_control` accepts the additional typed
operation `children` with current `source_sha256`, actual `node_id`, current
`inspection_id` and `offset` equal to the node's actual `loaded_count`. It returns
SAVED; poll status for the asynchronous GDB response. At most64 children per
request, depth8 and512 active nodes; further ranges are explicit. Children are
read-only GDB/MI variable objects, not arbitrary expressions. A stop/frame change
or continuation invalidates old identities; stale requests return DEBUG_VARIABLE.
GUI aggregates default collapsed at every new stop/frame; click row/disclosure
or Space to toggle vertical children. Existing scalar values and unavailable
diagnostics remain truthful. Source and run tokens retain existing admission.

For a bound HTML document, native GUI testing accepts
`{"operation":"document_zoom","component":"html_content","value":"in"}`
(`out` and `reset` are the other fixed values). This clicks the actual existing
Smaller/Larger/Reset button; it never invokes the zoom callback directly. Native
`key` also permits `ctrl+plus`, `ctrl+equal`, `ctrl+minus`, `ctrl+0` for HTML.
Document receipts include the actual Text font and visible zoom percentage, in
addition to the canonical binding/source SHA and read-only text/scroll receipt.

### Existing PDF reader: native GUI test targeting

A declared PDF document can expose its existing source-bound CORE reader through
the same attached `gui_test` facility. No caller supplies a window, PID or path.
After native selector/Open actions, poll `status` until
`document_receipts.COMPONENT.state` is `ready` (or an actual `unavailable` error).
The receipt reports actual page count/current page, zoom, page dimensions,
rendered page SHA/pixels and canvas view fractions. Actions return observations;
wait for the desired settled state after asynchronous child-window input.

- `pdf_control` takes `component` and `command`: `previous`, `next`, `zoom_out`,
  `zoom_in`, `fit_page`, `fit_width`; it clicks the actual enabled button.
- `pdf_pointer` takes `component`, normalized `x`,`y` in0..1 and `phase`:
  `click`, `press`, `move`, `release`, `wheel_up`, `wheel_down`. Finish a native
  owned canvas pan before changing the source or closing its parent.
- `pdf_key` takes `component`,`key`: Left/Right/Up/Down or Tab/shift+Tab.
- `pdf_resize` takes `component`,`width`,`height` within640..1880 by480..1100.
- `pdf_close` takes `component` and sends native Alt-F4 to that owned reader.
- `capture` with `component` and `dialog: pdf_reader` captures its actual native
  frame; normal capture verification/manual asset provenance applies.

The trusted Dataset Media owner receives bounded observations over its existing
child-process pipe. Source/Session admission, rebind and parent-close cleanup use
that same owner. The PDF decoder/rendering remains the existing Poppler reader;
no OCR or scientific Dataset mutation is implied. Native installed acceptance
must be recorded separately from successful transport or package builds.

## Shared electrical diagram interaction (dev109)

Existing typed SDK diagram selection executes its compiled local event before
the next queued Canvas input. Builder action property `diagram_tool` binds
checked presentation to that actual controller; it adds no new C++ call or
private tool variable. Native segment attachment, electrical engineering input,
canonical waveform symbols and wire voltage Probe are shared diagram/GUI Host
services. See [Native2D viewport](NATIVE2D_VIEWPORT_HOST_v1.md),
[geometry](NATIVE_2D_GEOMETRY_API_v1.md) and
[GUI Host](VIEWER_GUI_HOST_API_v1.md) for exact target/guard contracts.
Normal installed startup and events load the packaged compiled binary, including
these public service calls; only an explicit new development build compiles.

The additive SDK method `void Host::tex_command(unsigned form, const char*
operation) const` uses operation 30 and the `VIEWER_GUI_HOST_API_v1.tex_command`
grant. Existing Event/State/Host storage, entry point and operations 1–29 retain
their ABI. The full declared form, finite operations and canonical article versus
interface Workspace distinction are documented in
[GUI Host](VIEWER_GUI_HOST_API_v1.md#declared-tex-article-form-dev109).
Builder export contributes each canonical article provider through the existing
module Workspace descriptors, so articles remain discoverable after restart
before opening their Viewer. Ordinary installed runtime executes the distributed
binary; a TeX document Build invokes the native TeX typesetter and never rebuilds
the C++ Viewer.

### Explicit EM presentation copies and inert review request (dev109)

The fixed `workspace_upgrade_review PROJECT` CLI reads a JSON object from
standard input with exactly three inert string fields:

```json
{"saved_design":"<saved design Tcl dictionary>","saved_snapshot":"<source_sha256/design_sha256/project_sha256 Tcl dictionary>","callback_contract":"<64 lowercase hex characters>"}
```

The trusted normal GUI derives these fields from the chosen canonical saved
Workspace. The CLI reviews only declarations and source contracts; it cannot
apply a canonical state. The exact current source bytes/profile/grants and old
callback contract remain mandatory. Ordinary installed Workspace Open retains
its exact snapshot guard.

Explicit presentation review additionally admits a validated change of
`shell.inspector_width` and a Plot component's display `title`. Other shell
properties, handlers, scalar defaults, scientific model/variable references and
original declaration order remain significant. This allows the same-source
EM031→032 width/caption correction to be reviewed as a separate copy.

The original shared EM owner performs read-only admission of saved model
associations. Current state requires the actual canonical model and generation;
retained History may contain valid earlier models or an unsaved initial draft.
Review never restores or saves a model. A retained Job must be the genuine
EM-provider execution of that model generation; its original source receipt is
preserved even when it precedes a later model edit. Document/table bindings use
the same scientific identity/schema/content checks as normal restoration,
independently of any selected field Dataset. Plot cell and node sources are
rechecked using their original canonical public identities. Review and Apply
recheck source stamps, original Workspace, Session lifetime and current project.
Every retained History state, including redo, is transformed in RAM before a
normal managed export/import can create the reviewed copy.

The actual retained E/M typed contract covers both original interfaces and all
nine History states each, with generation, missing-Job and table-hash negatives.
Canonical copy creation and actual installed Save/Open remain separate GUI
acceptance gates. No source hash override, author migration code, new solver
Job, renderer or scientific Dataset is part of this operation.

## Canonical raster SDK methods (dev109)

The additive SDK v1 methods below require the identically named explicit
`VIEWER_GUI_HOST_API_v1@1` grants:

```cpp
void Host::raster_bind(unsigned viewport, unsigned dataset_selector) const;
void Host::raster_tool(unsigned viewport, const char* tool) const;
void Host::raster_command(unsigned viewport, const char* command) const;
```

Component numbers are their ordinary one-based Builder declaration ordinals.
The viewport must be `native2d` with `source_kind raster`; the selector must be
`dataset_selector` with `content_kind raster`. The shared host admits only a real
canonical `image.raster` source. It returns `awaiting_selection` for an empty
selector and precise errors for incompatible/changed identities. Neither file
paths nor source pixels are returned to C++.

Tools: `select`, `rectangle`, `polygon`, `annotation`, `move`, `rotate`, `pivot`, `pan`.
SDK commands include `fit`, `cancel`, `delete_roi`, `delete_annotation` and the
declared anchored-section commands described in the shared host contract. Return or the shared local Finish
polygon action completes a valid polygon; `finish` is not an SDK command.
Declare action property `raster_tool {viewport_id tool}` for immediate local
toolbar selection without executing a C++ event. Checked state follows the real
controller. Native mapping, ROI admission, gizmo transforms, Document/Resource
ownership and Scientific History remain shared CORE facilities.

Builder and the Development Workspace use these same declarations and methods.
New source or actual SDK build dependencies require an explicit development
Build; installed compatible precompiled packages execute their distributed
binary with zero compiler/linker invocations. SDK v1 additions preserve the
existing Event/State/Host data ABI and exact existing method bodies. They do not
authorize silent runtime recompilation or bypassing compatibility checks.

Independent installed generic-Viewer acceptance covers canonical binding, real
rectangle and irregular-polygon gestures, semantic menus, anchored editors,
History, Save/Reopen, Session switching and native action/menu icons. See the
[generic Builder example](../examples/GENERIC_RASTER_BUILDER.md) and
acceptance scope. This evidence
uses an uncalibrated pixel source; physical calibration remains an explicit
existing Native2D operation, never an inferred measurement.

A canonical raster declaration plus the explicit `raster_bind` grant admits
Workspace/History for the existing `document_view_v1` or `scientific_view_v1`
profile. Their original `SESSION_WORKSPACE_API_v1` create/get/update/list and
`SCIENTIFIC_RECIPE_API_v1` record/navigation grants remain mandatory. A raster
slot without its binding grant, a legacy profile or an unbound display-only demo
does not gain a canonical lifecycle through this declaration.

### Explicit CAD multiple-selection presentation copies (dev109)

The same reviewed-copy owner admits an optional complete pair on an existing
canonical geometry form: `workbench_selection` names a newly appended empty
`list` with `extended` or `multiple` selection, and `workbench_selection_mode`
names a new inert `choice`/`combobox` with exactly `replace add subtract` and
`replace` default. The original viewport, parameter mapping, single-object
choice, component ordinals, C++ bytes, profile, grants and handlers remain
significant. A choice's display label may change; its retained value, default,
choices and callback semantics may not. Arbitrary new lists remain inadmissible.

Review records `new_workbench_selection_forms`. For each retained state, the
existing transformer copies its original single-object ID choices into the new
list and projects its saved candidate to the corresponding index. It does not
read today's selected geometry to rewrite an old state. An empty candidate
stays empty; a missing candidate or duplicate IDs refuses the reviewed copy.
The original shared Workbench association checker validates the source owner,
format and generation, and the review/apply guard pins its current canonical
revision/SHA. Only the existing explicit managed Workspace duplication may
apply this declaration change. Ordinary installed Open keeps its exact source
snapshot check; this review is an explicit development operation.

The actual source review of the preserved 014 Workspace against official015
passed. Focused tests cover three derived control states, original-value
preservation, callback/ordinal refusal and real private canonical association
checks. They do not constitute installed GUI or full retained-History copy
acceptance, which remains a separate gate.

### API reference allocation with enlarged fonts (dev109)

The shared Browser computes its required height from actual font metrics,
control chrome, three API tree rows and four reference text lines. The C++
Workspace uses that same budget when distributing space between the source
and its scrollable diagnostics. Diagnostics retain their heading, at least two
rows and scrollbars; the explorer stays accessible. No API, source document or
metadata generation is changed by reflow.

Refresh uses a compact circular-arrow control with the existing shared tooltip
“Refresh API declarations”; the normal `API manual` button still opens the
selected public API manual. A redundant successful family-count status row
releases its space to the reference. Pending metadata, errors and empty search
results retain visible status feedback. Full Session/project/admission context
remains in the scrollable reference.

A focused actual-widget contract at Tk scaling1.998 verified 1000×700 and
1260×820, readable complete captions, three real tree rows, four actual24-pixel
text lines, source/diagnostic space, unchanged source text and one unchanged
metadata generation. Those 21 assertions do not substitute for the separate
installed Debian pointer/keyboard high-DPI regression.

### API Browser at the minimum client height

Browser layout budgets use the actual client area, font metrics and native
scrollbars. At the C++ Workspace minimum height, Diagnostics may show one row
plus its heading and scrollbars to keep three API rows and four detail lines
readable; larger windows retain two or more diagnostic rows. Window-manager
menu/decorations are outside this client budget. The shared Browser repairs a
selected row clipped by resize through the native Treeview scrolling methods,
while preserving deliberate scrolling away from a selection. Its deferred resize
callback is retired with the Browser. Metadata and source text are unchanged.


## Generated installed-provider reference

Export emits an inert `public_contract` in the generated Restricted Viewer client descriptor. It documents the exact generated `handlers`, `dispatch`, `workspaceOpen` and `texOpen` host signatures and their existing Session/Workspace contexts. API Browser can inspect these declarations without loading the provider. They do not grant Script Bridge or C++ SDK operations. Re-exporting unchanged compiled source retains its native artifact; changing this documentation formatter alone does not invalidate the native build dependencies.
# Trusted existing Tcl Viewer maintenance (TASK210 additive operations)

The existing Development owner also provides a finite **trusted maintainer**
workflow for the registered bundled Curve Workbench and Replicate providers.
Curve Digitizer is excluded entirely: its complete vendor2.0.9 package is
protected AS IS, not a maintenance target. This is separate from C++ authoring/runtime:
ordinary C++ policy, source whitelist, compiler, ABI and prebuilt runtime are
unchanged. No maintenance operation is exposed as a restricted native SDK grant.

`viewerDevelopmentMaintenanceModules` returns only the actual registered bundled
module/provider/backend identities admitted by CORE. A different registered
descriptor location is refused. `viewerDevelopmentMaintenanceCreate module
provider new_project callback` verifies this selection and delegates to the same
managed `viewerDevelopmentRequest` broker/backend and project-only Landlock grant.
The backend anchors the source to its actual bundled descriptor/package and
rechecks original file inventory, SHA256, member modes and source identity.

The additive request operations take `options {request_json JSON}` only:

| Operation | JSON request | Result |
|---|---|---|
| `maintenance_init` | `module`, `provider` | Fresh private project and opaque editable source IDs |
| `maintenance_inspect` | empty object, or `file_id` | Policy/file list, or inert bounded UTF-8 text/SHA256, `language` and actual `exists` |
| `maintenance_save` | `file_id`, `expected_sha256`, `content` | Atomic Save, or no-replace creation of the exact absent approved document; original module stays unchanged |
| `maintenance_validate` | empty object | Preserved-file identity/mode checks, Tcl lexical completeness and inert Markdown UTF-8 checks only |
| `maintenance_export` | empty object | Preserved-payload plugin candidate, full ZIP readback and explicit untested functional status |

CORE owns the editable-file policy; project metadata cannot add paths. Initial
scope is eight TASK210-approved Workbench source units bounded to 64 KiB each,
and Replicate's original `api/replicate_viewer.tcl` bounded to 128 KiB. The latter
accommodates the reviewed producer adapter without removing existing controls
or splitting it into unapproved files. The exact opaque Replicate
document IDs are `doc_manual` for existing `MANUAL.md` and
`doc_interoperability` for `DIGITIZER_INTEROPERABILITY_API_v1.md`, each inert
Markdown within 64 KiB. No other path may be created. C++ keeps its original
64 KiB source policy. JSON transport is bounded to 1 MiB for escaped text;
this does not increase source limits. Source and metadata must be ordinary
singly linked files with no linked ancestors, traversal, special files or NUL.
Inventory is bounded to 512 files / 64 MiB per original module.

New projects use `gxtxt.viewer_maintenance_project.v2` with a fixed policy revision
and explicit original-absence list. Old optional prototype projects remain
untouched and require explicit fresh staging; no automatic metadata upgrade
discards their edits. An absent approved document returns `exists=false`,
`sha256=null` and empty content. Only this absence accepts JSON null as the
expected SHA; an empty string or guessed empty-file digest does not. First Save
publishes without replacement and with mode0644. Existing files require their
real inspected SHA and retain their original mode. An intervening creation,
stale hash, changed absence provenance or symlink/hardlink refuses the Save.

Initialization supports an **absent fresh project path**, reserved by exclusive
mkdir. Existing directories, including empty ones, are refused and preserved.
Initialization creates the persistent `derived/maintenance.lock`; later requests
require it and never create, replace or unlink it. Same-project cooperative
inspect/save/validate/export and their load/preimage/readback/revalidation run
under nonblocking POSIX flock. A busy request refuses without waiting or changing
the editor baseline. The opened lock must be owned, singly linked, mode0600,
regular and still named by the same pathname/inode; descriptors use NOFOLLOW and
CLOEXEC. Source reads bind inode/link/mode checks to the actual opened FD before
and after bounded reads. This is cooperative owner serialization, **not** a
hostile-process filesystem CAS or account-wide security guarantee.

A committed save is byte/mode read back before SAVED. A lost/cancelled response
or failed postcommit readback is uncertain: retain editor text and resolve by
read-only inspection before any mutation retry. No blind rollback/retry occurs.

Every action rejects altered original provenance, foreign identities, removed
members, unapproved additions and changes to unapproved source/resources/native
binaries or permissions. Only the exact originally absent optional document may
be added, and it then enters the complete candidate inventory. Editing, Save and lexical
validation never source/evaluate Tcl or execute authored commands. Lexical
completeness is **not** runtime/security/scientific/GUI validation. Markdown is
inert UTF-8 data and is never checked as Tcl or claimed semantically validated.
A candidate
retains original backend, API, protected-core status, licensing, resources and
native bytes/modes; only approved source changes, a deterministic patch-version
bump in the two existing package descriptors and regenerated checksums differ.
The standard package owner writes the ZIP and refuses existing output.
Replicate descriptor/public-contract/capability contributions remain MAIN-owned;
this finite file policy does not provide a metadata editor or register new API
operations. A final changed public contract requires its own exact owner review.

Maintenance export does not install, activate or hot-reload a Viewer. Normal
Plugin Manager/protected-core integration and real installed GUI/science checks
remain with their established owners. Builder import/compare coverage does not
claim that a layout edit has been applied to the original widget construction.
Actual Builder fragment adoption for a changed layout remains an explicit
original-Viewer-owner integration obligation.

Legacy packages carrying both root SHA256SUMS and SHA256SUMS.txt retain both.
The standard package writer regenerates identical complete inventories covering
every nonmanifest member; both names are excluded from hash cycles. New Builder
packages remain TXT-only. Both manifest updates are explicit packaging deltas;
all other original member bytes/modes remain subject to preservation checks.
Both candidate ZIP and checksum sidecar use exclusive atomic link publication;
the checksum is completely staged/flushed first. Existing entries, including
dangling links, are preserved. If a checksum appears after preflight, the complete
ZIP remains and the competing checksum is untouched; export reports a partial
publication for explicit inspection. This is not a crash-atomic two-file pair,
automatic rollback, repair or permission to rerun blindly. Default Builder
signature, default member0644 and caller/umask sidecar permissions are retained.
