# Restricted Viewer Development API v1

## Local project drafts without a Session (P031)

A normally admitted Development project opened without a Session retains its
local document draft through **Workspace → Save project draft**. Reopening the
same project in the same user profile restores the exact draft and declared
Viewer state, including invalid UML source and its last valid presentation.
This uses the existing native Workspace store and typed Viewer/Document codecs
in profile-local project storage. It creates no Session, canonical Dataset,
Session Workspace registry entry or new native filesystem capability. Ordinary
Project Source Save continues to save project source files; it is distinct from
saving the running interface's local draft.

Only the live validated Development project receives this context. Its complete
source/design snapshot, callback contract, project identity and window lifetime
are checked before read/save/restore. Changed projects refuse adoption and retain
the previous saved draft. Concurrent windows use native generation/revision CAS;
a stale save refuses without losing the current unsaved draft. Close provides
Save/Discard/Cancel review. Explicit local saves are synchronous; malformed or
asynchronous save requests refuse. A Session Workspace ID requires a real Session
and is not accepted as a local project identity.

The real Session Workspace/History route and installed Module route remain
separate. Local project drafts require the matching source project/profile;
this interface does not imply automatic migration to changed C++ callbacks or
a new portable project-draft archive format. Normal portable Session Workspace
and editable project-source packages retain their existing owners.

Installed and development Viewer opens accept `workspace_name` only together
with `workspace_id new`, as emitted by the normal **New Workspace** form. The
existing Workspace owner validates the name before the Viewer opens. The
shared GUI retains it until the first normal Save; opening a saved Workspace
does not rename it. Unknown context keys remain rejected. This context change
uses the packaged binary for installed Viewers and adds no compiler fallback.

The reviewed typed SDK methods are `Host.catalog_refresh(unsigned form)`,
`Host.catalog_inspect(unsigned form)` and
`Host.catalog_action(unsigned form, const char* action)`. They require a declared
GUI Host section with `catalog_owner scientific_libraries` and exact manager API
grants. Refresh maps to libraryCatalogPage; inspect to getLibraryCapabilities;
each finite action maps to its separately requested manager operation. Invalid
form/action/grant rejects at the existing broker. The Host applies successful
source-guarded event plans through the existing manager and GUI owners. No
arbitrary invoke, provider import or registry path is exposed to the author.
See the [Scientific Library manager public contract](SCIENTIFIC_LIBRARY_MANAGER_API_v1.md)
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

## Compiled artifacts and responsive events

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

Historical admitted SDK-v1 packages may lack the later Workspace callback-contract
field. Installed admission derives that absent field only after exact packaged
source/interface, ABI and current capability checks. It uses the authored design
and leaves distributed build receipts and any existing contract unchanged;
Workspace restoration guards and runtime compilation policy remain unchanged.

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

Builder reparent retains declaration positions used by all one-based restricted
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

Additional authoring facilities (same API family and kernel project grant):

- `facility_request PROJECT` reads a UTF-8 JSON request on stdin (at most 64 KiB).
  Required fields are `schema=gxtxt.core_api_gap.v1`, `request_id` matching
  `GAP-[A-Z0-9-]{1,60}`, `viewer_project` equal to the project's module ID, `task`,
  `public_api_inspected` (nonempty list of API IDs), `missing_operation_or_contract`,
  `reproduction`, `why_existing_api_fails`, `desired_input_output`,
  `minimal_acceptance_test`, and `status=REQUESTED`. Non-list fields are nonempty
  strings. The backend stores `requests/ID.json` with the exact source manifest and project/design
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

### Bound read-only document GUI tests

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

### Native screenshots as installed manual resources

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
`![Actual remote waveform](images/remote-waveform.png)`. The existing Documentation
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

Scientific form admission uses `scientific_view_v1`, extending the explicit
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
`save` writes a declared C++ source/header, project.json or inert MANUAL.md through the
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
CORE UI. After admission and exact source-tree/design/project SHA comparison, the original public
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


Scientific admission remains explicit: `Host.numeric_exp(value)` is the
bounded scalar `NUMERIC_API_v1` `array_unary.exp` operation in `numeric_view_v1`.
The project must request it. It calls the existing Numeric owner unchanged and
rejects nonfinite input/output. The Numeric owner remains the mathematical implementation. Scientific Execution,
Script Job and Parallel Execution are discoverable in the approved catalog but remain unavailable in authored C++
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
Debug builds have real `-O0 -g3` symbols mapped to original project-relative files, and a
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


### Native2D diagram SDK

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


## Restricted canonical Plot binding

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

## Optional installed native GUI tests

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
choice. Existing `diagram_tool(...,"probe")` uses the shared declared bridge
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
## Declared Numeric SDK operations

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
are not broadened implicitly. Generated packages using these methods use their declared package compatibility requirements. A `document_view_v1`/`scientific_view_v1` project may declare ordinary
Workspace/History with an explicitly granted Numeric form and their existing
scoped lifecycle capabilities without declaring an artificial schematic.

Numeric plans require the declared form, target and complete grants. Vector
interpolation, complex AC display, statistical persistence and sweep GUI
operations are outside this contract.
## Fixed source and public manual inspection

`inspect PROJECT --target TARGET` returns inert UTF-8 `content`, exact `sha256`,
`bytes` and `read_only:true`. Targets are declared source/header files plus `project.json`,
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

## Explicit reviewed Workspace copies

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
copy. The CLI success-status set includes `REVIEWED_INERT_ADDITIVE_UPGRADE`,
so a successful review returns exit0 consistently with its success payload.

The existing `key` GUI-test action accepts `Escape` on an already bound, mapped, unobscured declared Plot. This sends the actual native keyboard event to that Plot, clearing its source cursor through the normal host binding. Other Plot keys, hidden/unbound/foreign targets and input during an owned pan remain denied. Existing Diagram keys retain their enum and require an unobscured declared viewport. No global desktop key delivery or new restricted SDK operation is exposed.

## Canonical read-only consultation binding

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

## Shared electrical diagram interaction

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
[GUI Host](VIEWER_GUI_HOST_API_v1.md).
Builder export contributes each canonical article provider through the existing
module Workspace descriptors, so articles remain discoverable after restart
before opening their Viewer. Ordinary installed runtime executes the distributed
binary; a TeX document Build invokes the native TeX typesetter and never rebuilds
the C++ Viewer.

### Explicit EM presentation copies and inert review request

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
original declaration order remain significant. The same-source width/caption correction is reviewed as a separate copy.

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

The same compatibility checks apply to retained E/M interfaces and History states.
A changed generation, unavailable Job or inconsistent table hash rejects the copy.
No source hash override, author migration code, solver Job, renderer or scientific
Dataset is part of this operation.

## Canonical raster SDK methods

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

Canonical binding, rectangle/polygon gestures, semantic menus, anchored editors,
History, Save/Reopen and Session switching use the shared raster owner. See the
[Viewer GUI Host contract](VIEWER_GUI_HOST_API_v1.md) for declarations and
interaction semantics. Pixel coordinates remain uncalibrated until an explicit
existing Native2D physical-calibration operation supplies the measurement scale.

A canonical raster declaration plus the explicit `raster_bind` grant admits
Workspace/History for the existing `document_view_v1` or `scientific_view_v1`
profile. Their original `SESSION_WORKSPACE_API_v1` create/get/update/list and
`SCIENTIFIC_RECIPE_API_v1` record/navigation grants remain mandatory. A raster
slot without its binding grant, a legacy profile or an unbound display-only demo
does not gain a canonical lifecycle through this declaration.

### Explicit CAD multiple-selection presentation copies

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

### API reference allocation with enlarged fonts

The shared Browser computes its required height from actual control chrome,
three API tree rows and four reference text lines, including its native
scrollbars. Development Workspace uses the same existing Browser factory's
compact presentation: the notebook supplies the title, search and surface
controls use two rows, and Manual/Previous/Next share a responsive footer.
Refresh remains visible with its full tooltip. Successful nonempty searches
release the status row; pending catalog requests, errors and empty results keep
visible feedback. Full Session/project/admission context remains in the
scrollable reference.

The Workspace budgets both notebooks' tab chrome and retains Diagnostics'
heading, one complete row and scrollbars. The minimum client remains 980×650
at ordinary fonts. With a larger persisted Appearance font, the window manager
minimum grows to the measured height needed for the same readable source,
reference and controls. A requested smaller height is clamped honestly; no
font is reduced or control clipped to simulate a fit. Larger windows restore
more diagnostic space. Window-manager decorations and menus are outside this
client budget.

A settled resize clamps the compact Browser sash to its actual row/line minima
and preserves a usable user sash within those bounds. Deferred callbacks are
cancelled with their window. The regular Browser presentation used by the
script editors remains unchanged. Search, selection, refresh and layout do not
change source, grants or the scientific model.


## Generated installed-provider reference

Export emits an inert `public_contract` in the generated Restricted Viewer client descriptor. It documents the exact generated `handlers`, `dispatch`, `workspaceOpen` and `texOpen` host signatures and their existing Session/Workspace contexts. API Browser can inspect these declarations without loading the provider. They do not grant Script Bridge or C++ SDK operations. Re-exporting unchanged compiled source retains its native artifact; changing this documentation formatter alone does not invalidate the native build dependencies.
# Trusted existing Tcl Viewer maintenance

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
scope is eight policy-approved Workbench source units bounded to 64 KiB each,
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
remain with their established owners. Importing or comparing a layout fragment
in Builder does not alter the original widget construction. Adopting a changed
fragment requires explicit integration by the original Viewer owner.

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


## Typed Sketch and diagnostics components

See [typed Sketch and diagnostics integration](VIEWER_GUI_P020_ADDITIONS.md) for
actual component properties, admitted C++ operations, grants, lifecycle and bounded
event payloads. Existing v1 identities and non-opt-in consumers remain compatible.

## Multifile C++ projects and source identity

The existing `gxtxt.viewer_development_project.v1` metadata accepts optional
`source_files`, an ordered list of normalized project-relative names. Omission
means `["handlers.cpp"]`. The first and unique entrypoint is `handlers.cpp`;
additional translation units live under `src/` with `.cpp` extension and local
headers under `include/` with `.hpp` extension. Nested directories are supported.
At most32 files,64KiB per file and1MiB combined are admitted. Names cannot contain
traversal, empty components, absolute paths or linked ancestors. Source remains
UTF-8 text without NUL. Project metadata cannot select compiler flags or hooks.

Every declared file participates in `source_manifest` (path, role, bytes, SHA256),
whose canonical JSON identity is `source_tree_sha256`. The additive
`project_digest_sha256` binds that identity to exact project/design hashes.
Legacy `source_sha256` continues to identify handlers.cpp and `project_sha256`
continues to identify project.json. Existing one-file metadata remains valid.
A missing/changed header or auxiliary unit invalidates Build, Preview, runtime
admission, Workspace callback compatibility, GUI-test attachment and Export.
Successful native event receipts carry that same frozen source manifest/tree
identity; the GUI compares every file before applying a returned operation.
Legacy one-file event/snapshot shapes remain compatible. The API Browser saved
project context and project-associated facility requests also retain the complete
source identity; discovery still grants no execution.

Before compiler admission, every source/header include is reviewed. Only
literal reviewed system headers or declared quoted local headers are admitted.
Macro includes, include_next/import, traversal and source-location remapping
are refused. Directive digraphs use the same admission; line splices follow C++
preprocessing order. Directives inside ordinary/raw string content are inert.
Trigraph directives, embed and header-existence queries require review and are
refused before AST access. The original Clang lexer/AST policy runs against each translation
unit and its local headers. Exactly one correctly typed on_event definition
belongs to handlers.cpp. SDK call grants are the union of actual authored calls
across all units/headers. Compilation and linking use the original fixed SDK,
adapter and recipe on an immutable source snapshot. No authored Make/CMake,
external include root or alternate compiler is accepted. Diagnostics retain
actual project-relative file, physical line and column.

`project_files PROJECT` accepts a JSON request on stdin. `{"operation":"list"}`
returns the current source manifest and project metadata SHA. Mutations require
`expected_project_sha256` from that inspection. `add` takes `name` and `source`;
`remove` takes auxiliary `name`; `rename` takes auxiliary `name` and absent
`target`. Rename/move does not rewrite authored includes. `save_all` takes a
`files` object mapping declared files, project.json or MANUAL.md to
`{"source":"...","expected_sha256":"..."}`. An absent optional manual uses
JSON null. All names/bytes/preimages are checked before writing; the metadata is
published last. Ordinary I/O failure restores touched original bytes/modes.
This cooperative transaction is not a crash-atomic filesystem guarantee.
The host request equivalent uses `project_files` with `request_json`. These are
author-tool/host operations under the existing project write grant, not native
Viewer SDK or scientific Script Job capabilities.

Export includes every exact declared source/header plus SOURCE_MANIFEST.json
under source/, the full build receipt and actual compiled binary. Installed
admission compares all packaged source hashes before loading the distributed
binary and never invokes source compilation.

`import_project NEW_PROJECT --package EXPORTED_ZIP` restores an editable project
through this same owner. NEW_PROJECT must be absent. The trusted initialization
phase validates normalized ordinary archive members, total bounds, complete ZIP
checksum inventory, exact source/build receipt and source manifest. It publishes
one complete new folder, preserves authored source/design/metadata/manual assets,
then installs the existing project write grant. It never loads the packaged native
binary. A later explicit Build uses current admission and compiler inputs.
The host request uses `import_project` and option `source_package ZIP_PATH`.

The original `debug --breakpoints` additionally accepts file-aware records,
for example `[{"file":"src/physics.cpp","line":3}]`; integer lines remain
compatible and refer to handlers.cpp. A paused frame reports `project_file` only
when it maps to a declared source/header, retaining authentic GDB file/fullname.
External SDK/system frames remain external. Breakpoint records explicitly report
`resolved`; pending/nonexecutable locations are never presented as verified stops.
The frozen source tree is included in Debug state, and controls may supply its
`source_tree_sha256` in addition to the legacy source SHA. Any current source-tree
change refuses controls and cancels the previous execution.

Scientific Library catalog actions `entry_search`, `entry_next`, `entry_previous`
and `entry_info` require respectively searchLibraryEntries, libraryEntriesPage,
libraryEntriesPage and getLibraryEntryInfo. A declared catalog_entry_filter
requires all three operations. Query, selected entry and continuation belong
to the existing Scientific Library Manager/GUI Host; C++ receives no private
provider, filesystem or arbitrary dispatch capability.

## Scalar Numeric transport and native budgets

A persistent compiled Viewer with an explicit scalar Numeric grant uses a finite
trusted transport child for the existing add/sqrt/exp SDK calls. That child starts
before applying native author CPU/address-space/file-size limits and calls the
exact existing broker_message/core Numeric owner. It performs no numerical
implementation, source execution, publication or Job registration of its own.
This keeps trusted numerical service processes outside the native author budget,
matching the original nonpersistent broker boundary. The native loaded library,
state, CPU3s/address-space256MiB/file-size1MiB and event wall12s remain unchanged.
A Viewer without those scalar grants starts no transport child.

The transport accepts only bounded typed scalar messages, frozen source hashes
and explicit scalar grants; it accepts no arbitrary operation, path, Tcl or
command. Domain rejection discards the event's UI/state changes and the same
loaded Viewer can process a later valid event. Broker/core descendants use the
existing supervisor's subreaper, start identities, bounded drainage and reaping.
A parent-death signal covers hard loss of the native worker. Private diagnostic
receipts record the broker PID, frozen identity, bounded CORE-request history
and actual cleanup. Desktop D-Bus activations are outside this worker-tree
cleanup statement; the actual headless CORE environment omits DISPLAY.

Python cancellation never unwinds through the C++ callback ABI as a false scalar
result. It is recorded as an event failure, and the managed compiled lifetime
then exits with its actual cancellation status instead of serving more events.

API Browser family and method rows use the existing shared UI Field inspection
font and row padding. The native row height follows the saved Appearance font,
and the three-row minimum uses those actual rows. This does not autosize the
Browser's declared columns on queries or replace a deliberate horizontal pan.

## Installed C++ Runtime Test in Builder

`::GX::viewerDevelopmentInstalledTestOpen window module provider moduleRoot fixtureRoot retained onReady ?geometry?` is a trusted host-only connection used by the existing Builder Runtime Test control. `window` must be the live `.gxInterfacePreview`; module/provider/root must be the exact normal registered, enabled installed restricted C++ package, whether bundled or managed by Plugin Manager. Bundled modules need no removable-plugin registry record. `fixtureRoot` must be a marked private test fixture containing the current Session. `retained` is the existing inert GUI capture; `onReady` is a trusted live host command prefix, never an authored or portable callback. Optional geometry uses ordinary bounded Tk geometry. The installed design must exactly match the Builder model except inert origin. Package admission rechecks source, lifetime and Session after event pumping before replacing the same window.

The existing compiled admission, worker and Host command owners run the real client; retained GUI and image references restore before its open event. The callback receives the window and a receipt with `status ready|rejected`, `message`, and resource/state handoff information. Ready means genuine native open completed. A failed replacement retains the previous draft/resources for the Builder's normal fallback. Compiled state restores only for the matching source snapshot and callback contract. Native Workspace close/dirty and History recovery choices remain authoritative. This API does not install, compile, publish a Dataset or create a third Preview window.

## Producer-scoped Dataset Groups and publication

The additive native methods use the existing Group v1 and Publication v2 owners:

```cpp
void Host::dataset_group_review(const WorkspaceValue& dataset_ids) const;
void Host::dataset_group_create(const WorkspaceValue& definition,
                                const WorkspaceValue& review) const;
void Host::dataset_publish_batch(const WorkspaceValue& request) const;
WorkspaceValue Host::dataset_producer_result() const;
```

These methods need no Numeric form or prebound component. They enqueue finite
typed requests for the owning CORE thread after the compiled event returns.
`dataset_producer_result()` reads the latest producer receipt from an earlier event;
it does not publish authored Workspace state or advance scientific History.
The receipt has `operation` (`review`, `create`, `publish_batch`), `status`
(`completed` or `failed`), `result`, increasing `sequence`, and `event_generation`.
A failed request, including broker-time capability denial, replaces the prior
success with a fresh failed receipt, a null result and a bounded `error` string.
The current C++ event can still inspect its input receipt before its own request
completes. Closed/replaced windows and changed Sessions cannot receive a result.

Declare exact capabilities in project metadata. The minimum grouped-batch set is
`DATASET_GROUP_API_v1@1` operations `datasetGroupProducerReviewV1` and
`datasetGroupProducerCreateV1`, plus `DATASET_PUBLICATION_API_v2@2` operation
`datasetProducerPublishBatchV1`. The result accessor also requires Review.
An admitted producer with Review and Publication but no Create can publish an
ungrouped batch; adding `dataset_group` explicitly refuses. Listing operation
names, changing a module ID or receiving a receipt does not grant authority.
The host binds the actual registered installed producer, capability, current
Session incarnation and namespace. Original ABI 1 packages keep their existing
methods/layout and distributed binaries; this additive surface requires a newly
authored client, not a rebuild of unrelated installed packages.

Public flow: issue Review with an empty typed array; in the next event obtain
`receipt.result.session_token`; pass `{session_token, outputs}` to Publish Batch.
Each output is an existing Publication v2 series request. Add an explicit
`dataset_group` declaration only when desired, containing exactly those new IDs.
For owned existing outputs, Review their IDs and pass the returned full review
unchanged with the Group definition to Create. This groups canonical outputs
without copying or rewriting their scientific payloads. Mixed-producer grouping
remains an explicitly reviewed user/admin operation. See
[DATASET_GROUP_PRODUCER_API_v1](DATASET_GROUP_PRODUCER_API_v1.md) for definitions,
roles, ownership, namespace, revision and atomic rollback rules. Source-file Notes
remain a separate SOURCE_NOTE_API_v1 association.

Native request transport is UTF-8 typed `WorkspaceValue`, at most 48 KiB,
64 nesting levels and 8192 nodes. Review accepts 0..64 IDs; publication accepts
1..64 outputs. Native numeric values use the existing finite double/int64 typed
value boundary. Full opaque revision tokens remain strings; over-budget requests
are rejected, never truncated. Results are bounded to 1 MiB. Normal native event
CPU/memory/wall budgets still apply; this is bounded small-output publication,
not a replacement for scientific streaming Jobs.

The actual Python and Octave Script Bridge exposes Group v1 `review`, `create`,
`get`, `list`, and Publication v2 `publish_batch`. For example, in Python:

```python
review = gxtxt_api_call('DATASET_GROUP_API_v1', 'review', [])
result = gxtxt_api_call('DATASET_PUBLICATION_API_v2', 'publish_batch', {
    'session_token': review['session_token'], 'outputs': outputs,
    # Optional: 'dataset_group': definition
})
review = gxtxt_api_call('DATASET_GROUP_API_v1', 'review', result['dataset_ids'])
group = gxtxt_api_call('DATASET_GROUP_API_v1', 'create', definition, review)
```

Octave uses the same operations through its supported `gxtxt_api_call`, struct
requests, ordinary numeric vectors and output/member cell lists. Review and the
following mutation belong to the same actual supervised Job/Session binding.
Script numeric arrays retain the existing Publication writer's dtype and missing
value/NaN/Inf policy, unlike native finite `WorkspaceValue` transport; the adapter
does not replace samples. Numeric-array data are bounded to 64 MiB and control
descriptors to 1 MiB. Existing single publication and ungrouped batch methods are
unchanged. API discovery/coverage describes availability; invocation acceptance
is recorded separately in the release validation receipts.

### UML shared Document admission (P031 additive)

`document_view_v1` clients can declare a `document kind=uml` and request the exact
`UML_DOCUMENT_API_v1` operations described in
[UML Document API](UML_DOCUMENT_API_v1.md). Existing `Host.document_bind`/command
remain ABI26/41. Actual design admission requires Read/Parse/Layout and, for
editable components, Edit independently of the source call list. Write/Export are
separate grants and every finite runtime intent rechecks its required operation.
The trusted host receives only the recomputed admitted set. Default Markdown
admission and distributed source/binary receipts are not rewritten.

Managed UML Preview declares three real readonly direct-canvas document panes:
`diagram`, `source`, `metadata`, with one `document.uml` Contract Visualizer role.
A shared kind is required across panes; an associated-source pane is not invented.
Editor capture uses a finite typed `uml_drafts` domain, keeping exact source and
portable revision strings rather than a worker/model blob. Source editing and
canonical saving retain their public owners. This declaration describes available
host facilities; module authors must still genuinely author/build/export/install
and test their native project. Author API/fixture success is not that proof.

## Additive Acquisition project source authoring

The Development request owner also supports `project_init` for a genuine
`gxtxt.acquisition_development_project.v1` target. It creates no Viewer design.
The versioned `project_files` description/edit interface supplies a typed roster
of registered C++/header/Tcl/Python helper source, module-local format profiles,
exact byte/SHA identities and an opaque full-closure CAS revision. Source edits
reuse the existing managed Jobs, project-write grant and atomic ProjectFiles
publisher. Source and helper files retain exact UTF-8 bytes including BOM/CRLF.
Helper registration grants no execution; profiles are unvalidated until actual
native admission. Descriptions state current build/runtime availability explicitly.

The exact implemented batch-A schema and request/response shapes are documented
in `validation/dev111_p032_toolchain/PROJECT_TRANSPORT_BATCH_A_01.md`. Existing
Viewer source operations, policy, SDK/adapter ABI and compile recipe are unchanged.
This source-authoring surface alone does not establish native Acquisition,
selected-source access, publication or independently accepted Builder workflows.

The Acquisition publisher carries the reviewed prestate through staging and
checks it again immediately before replacement. Compensation restores only its
own unchanged postimages; unexpected external edits remain intact and produce
`SOURCE_RECOVERY_CONFLICT` for review. This is ordinary concurrent-edit detection,
not an operating-system atomic compare-and-swap against hostile processes.
Acquisition C++/Python source notes reuse the existing SourceAuthoring owner.
Descriptions expose per-file `source_notes_available`, `source_notes_language`
and `source_notes_reason`; Tcl helper notes are explicitly unavailable while
their source remains editable. Raw metadata cannot create or replace a Source
Note owner pointer. Typed source saves/renames/removals preserve or detach notes
through the same owner. Local note operations retain exact project/source/
authoring CAS; actual canonical attachment still requires SOURCE_NOTE_API_v1 and
the real Development workspace capability/context.

The additive native Acquisition target now has actual Validate/Build/Export and
inert distributed `runtime_inspect` branches using the same Development compiler,
managed requests and standard package writer. Its separate SDK/worker/factory and
exact guard/output protocol are documented in
[Native Acquisition SDK](NATIVE_ACQUISITION_SDK_v1.md). CORE normal registered
package/profile admission remains mandatory. Old Viewer run/prepare/test paths
explicitly refuse Acquisition: actual Test/Import uses the CORE source/output
broker. Current descriptions retain runtime_available=false until that owner is
integrated; registered helpers are not execution claims. Normal Acquisition
source-project ZIP import verifies inventory/checksums and source/build closure,
restores exact sources/helpers/notes/assets with fresh note identities and origin
lineage, and neither imports nor executes a compiled binary. See the C2 handoff
`validation/dev111_p032_toolchain/SOURCE_NOTES_PROJECT_IMPORT_C2_01.md` for exact
local note forms and scoped author evidence.

Optional Acquisition `config_fields` declarations preserve producer scalar
defaults/types/constraints through existing source CAS and normal Module config
sections. Absent declarations in earlier projectv1 mean []. Current descriptions
and inert installed admission expose exact config_fields/config_schema_sha256;
no runtime settings store or permission is added. See
`validation/dev111_p032_toolchain/CONFIGURATION_FIELDS_C3_01.md`; actual CORE owns
runtime normalization, ModuleCfg persistence, live scope and provenance.

### Acquisition project Test (P032)

The primary **Run → Test** command in Acquisition Plugin Builder and **Develop → Test**
in its C++ source Workspace share one CORE selection/configuration dialog. Choose
1–64 ordinary files, an actual saved format profile and typed configuration.
Configuration values here are transient Test overrides of the declared defaults;
they do not change ModuleCfg, Configuration or a Session Manifest. Cancel keeps
source and drafts. Changed source revisions refuse and require a fresh review.

`VIEWER_DEVELOPMENT_API_v1` retains its `test` operation. For an Acquisition target
its `request_json` uses `gxtxt.acquisition_project_test.v1` with `expected_revision`
(from public ProjectFiles `describe`), `profile_id`, absolute chosen `sources`,
and optional typed `config`. The complete request is bounded to64KiB; files are
bounded to2GiB aggregate and the actual native Test to60seconds after admission.
No private Tcl command is required. `project_test_available` is distinct from the
Viewer-style `runtime_available` flag; Acquisition has no synthetic Viewer Demo.

Test uses the existing normal candidate exporter and distributed native admission
without installing/registering the module. The same Source Grant checks full SHA,
the existing guarded broker executes the actual compiled callbacks, and the same
typed buffer owner verifies/seals then discards provisional outputs after reap.
No Session, Registry entry, Dataset, Dataset Group or scientific publication is
created. The current producer/profile/config/source closure remains pinned;
foreign profiles, stale revisions, unknown config, FIFO/linked sources, protected
producer replacement and malformed output identity refuse. The private
`derived/acquisition-test.json` reports actual guard, configuration and source
identities, discarded output schema/SHA and reap; it explicitly does not certify
scientific correctness or final installed-module behavior. Normal Plugin Manager
admission and real canonical import/rollback/GUI acceptance remain separate.

Project Test first invokes the saved **recognize** and **inspect** callbacks in
separate admitted, bounded read-only phases. It reports their actual metadata
and reaped actors before the full import-callback Test; an unrecognized source
refuses without creating numeric outputs. All three phases share the reviewed
source/configuration closure and overall60second native deadline. This exercises
the declared callbacks without assigning scientific validity to their claims.
The Acquisition API and Development metadata report helper availability through
the same actual CORE helper admission owner, independently of reference catalog
presence.

Compiled Viewer and Preview admission allows 20 seconds for the fixed headless
runtime-design/catalog request, within the existing 30 second outer admission.
The separate native-library probe remains bounded to 5 seconds. Ordinary CORE
requests retain their 12 second default; scalar execution retains its existing
remaining-deadline budget. A timeout refuses admission and kills/reaps the
owned request group. There is no automatic retry or partial capability grant.
