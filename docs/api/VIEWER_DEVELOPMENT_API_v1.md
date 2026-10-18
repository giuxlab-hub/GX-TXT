# Restricted Viewer Development API v1

`VIEWER_DEVELOPMENT_API_v1@1` is the trusted shared facade used by the ordinary
`viewer.development_workspace` module and its CLI. Discover it through
`workbenchExtensionCoreApis` / `workbenchExtensionRequireApi`; inspect
`viewerDevelopmentApiInfo`. The implementation is
`core/tcl/viewer_development_api_v1.tcl` and
`core/python/gxtxt_viewer_development.py`. UI composition remains Viewer GUI Host;
the original Script Job auxiliary owner owns asynchronous process lifetime.

## Requests and source transfer

`viewerDevelopmentRequest operation project callback ?options?` dispatches init,
validate, build, run, test, export, api, save and check_source. Callback receives
the same inert `{ok result}` or `{ok 0 error code detail}` fields as CLI JSON.
Options admit only module_id, typed event/state and bounded source/file payload.
`save` writes only original handlers.cpp or project.json through the same Linux
project-write backend. `check_source` applies the actual Clang lexer/AST and
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
