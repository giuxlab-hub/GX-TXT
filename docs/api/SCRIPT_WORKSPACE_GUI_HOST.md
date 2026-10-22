# Shared Script Workspace GUI host

The Python and GNU Octave Viewers retain their metadata and Script Registry
adapters. `app/script_workspace_surface.tcl` owns their common pane lifecycle;
`app/script_debug_surface.tcl` observes real managed native Debug Jobs.
`SOURCE_SURFACE_API_v1` owns source presentation, folds and gutter markers.
No scientific registry, interpreter or renderer is duplicated.

## Authoring and Session boundaries

`scriptWorkspaceSessionToken` obtains an Interactive Document lifetime token
only when a Session exists; otherwise it returns an empty token.
`scriptWorkspaceDefaultScope` chooses User without a Session.
`scriptWorkspaceEditorSessionValid parent token ?scope?` permits User-library
authoring independently and guards Session writes against changed lifetimes.
An explicit load in a previously unbound editor adopts the current token; an
already bound stale editor cannot save into another Session. Import/export
never executes source or manufactures a Session.

## Run launcher and existing Job supervision

The final **Scripts & Jobs…** control at the right of the Run command row opens
the existing **Script Runner…** or **Job Manager (local / remote)…**. It does not
change the analysis Run/Stop/Refresh/Copy actions. Script Runner requires an open
Session. With an available selected registered script, it opens that script's
review; otherwise the existing Script Library opens: select the saved script and
choose Run there. Opening a review never submits a Job. Reopening the same
unchanged review in the same Session preserves its parameter entries; an explicit
Session/source change requires a new review before submission.

Job Manager can inspect historical local executions without an open Session.
Its **Jobs > Open/reconnect Job ID (local / remote)…** action accepts a local Job
ID or the original opaque `remote/NODE/SESSION/JOB` receipt. Remote inspection uses
the configured, enabled node and logical remote Session, independently of the
currently open local scientific Session. Unknown/disabled nodes report an error;
they are never replaced with a default or fabricated endpoint. The local journal
list and its Recover action remain local; remote details are not copied into it.

Execution details provide **Reconnect** and an explicit, confirmed **Cancel Job…**
for an observed active Job. Remote details use the existing authenticated
Scientific Execution transport and bounded Script Job request owner, not a second
scheduler. This protocol exposes its retained combined log, not separate remote
stdout/stderr streams or local Dataset publication. Those unsupported controls are
disabled. The original remote ID remains the inspection/cancellation target even
when the returned record contains a node-local ID. Closing details cancels only
its pending client requests; it does not cancel the durable Job. **Execution
help** in the launcher opens this manual in the existing Documentation Browser.

## Layout host operations

Both shells call `scriptWorkspaceViewMenu editor menu language` and
`scriptWorkspaceLayoutInit editor`. The horizontal Explorer/Source/Snippets
panes retain their widgets and splitters. `scriptWorkspaceAssistMount editor
panel` attaches a debugger/import assistant to the lower source notebook.
It never forgets or recreates the side panes. A separate assistant bindtag
handles Destroy independently of client bindings. Closing the last assistant
restores the source area and prior focus without editing text.

View independently controls Explorer, Snippets, Debugger, Call Stack, Variables,
Debugger Output and Breakpoints. Checkmarks describe currently mapped content;
an unchecked tabbed pane can be brought into view. Focus Source is reversible;
Reset restores side panes and normal fractions. Neither cancels a Job. Hiding
Debugger keeps its Job managed; Close / cancel Debug asks before cancellation.

User Configuration owns `scripts.editor_layout.python` and
`scripts.editor_layout.octave`: left/right and properties visibility, horizontal fractions and
source/assistant fraction. Values are validated as inert fractions/booleans.
Native sash input and normal close save only these presentation keys. Scientific
storage and source dirty baselines are unaffected.

## Shared API Browser

The existing Development catalog and Script Bridge registration owners supply
one shared API Browser presentation in Python, GNU Octave and the C++ Development
Workspace. `core/tcl/viewer_development_api_browser_v1.tcl` owns its widgets and
presentation lifetime; it does not create another API registry or numerical
implementation. `apiBrowserMount` retains the actual Explorer widgets above the
Browser in a vertical split. View > API Browser independently hides/restores the
lower pane. The existing Configuration owner also registers
`scripts.editor_layout.cpp`; each language's dictionary preserves `api_fraction`
and `api_visible` alongside that editor's other presentation fields.

Discovery is metadata only and needs neither a Session nor a selected project.
Distinct declaring providers remain separate children of their logical API
family. Registered Script Bridge operation rows show actual argument kinds,
required/optional flags, declared conventions/context and result contracts.
Absent signatures are labelled undeclared. Registration, module enabled state,
external-runtime availability, active managed Bridge context and C++ project/SDK
admission are separate facts; displaying a declaration grants none of them.

To use the Browser, enable **View > API Browser**, enter a family/provider or
operation term in its search field, then expand the matching family. Search is
case-insensitive substring matching over the declared reference, bounded to the
first 256 query characters and 250 displayed families; narrow the query if the
inventory is larger. There is no separate scientific operation behind search.
The refresh glyph explicitly rereads declarations; resizing and Session changes
reuse the existing catalogue and update its presentation/context.

Select a provider child for its trusted-host reference, a **Python/Octave**
operation child for its registered arguments/results and editor-language example,
or a **Host::… C++** child for the exact admitted SDK method. A Python/Octave
operation visible in the C++ editor is discovery, not a direct C++ permission.
The details distinguish no saved project, project request admission, runtime
grants and actual Build/source validation. An API version conflict, unavailable
runtime or missing manual is not equivalent to an absent API.

The list and reference have independent scrollbars. Drag the horizontal divider
between Scripts and Browser, or the divider inside the Browser between its list
and reference, to allocate reading space. **API manual** delegates to the full
existing Documentation Browser and preserves the source buffer. Copy from the
focused query/reference uses the normal text-editing contract; selecting a row
or copying documentation does not insert source or execute the displayed call.

The query and read-only reference use the existing UI text-editing owner, with
focused Select All/Copy semantics. Manual opening delegates to the existing
Documentation Browser and can report an unavailable manual. No universal manual
or complete operation schema is inferred from an API ID. Widget destruction
cancels owned metadata requests/layout callbacks without editing source,
submitting scientific Jobs or modifying canonical Session data.

The optional properties collapse preserves the actual metadata widgets and their
values. Restoring presentation does not write defaults over saved fractions.
Both native import/export adapters preserve exact UTF-8 bytes, including BOM,
CRLF and tabs. Registered Octave reads use the same binary decode/round-trip
validation so reopening cannot silently change its immutable source identity.

## Native debugger client

The toolbar uses the existing `scriptJobDebugSubmit`, `scriptJobDebugRead`,
`scriptJobDebugControl` and cancellation owner. Enablement follows the same
callback as the native observation. There is no fake stepping or arbitrary
Watch evaluation. Session/source changes produce an explicit snapshot guard.

Supported controls come from the existing Job owner's
`scriptJobDebugCapabilities language`. Python supports native asynchronous
Pause. The GNU Octave managed CLI adapter reports it unavailable because a
real interrupt can terminate a loop without yielding a verified stopped frame.
Both the GUI and public Job backend reject that unsupported operation; native
Octave breakpoints, steps, frame selection, Continue and Stop remain available.

Call Stack and Locals/Globals share one observation. Native adapters bound
values and never call researcher display methods merely to draw the inspector.
External frames show their precise file/line without an arrow in unrelated
source. Debugger Output contains state/command receipts; Program output /
diagnostics opens the actual Job's separate retained streams. Completion and
cancellation clear current-frame presentation. A genuine managed Octave error
can instead retain its native origin trace and explicitly labelled **last
paused** user variables after failure. These are the last observed snapshot,
not live post-unwind locals; technical caught-runner frames remain in Debugger
Output. The unwound origin trace cannot be selected as a live execution frame.
Changed editor bytes or Session context still prevent a stale source highlight.

Debug client replies also capture the pane incarnation, submission generation
and exact owned Job ID. Closing and recreating the same widget path cannot adopt
an earlier submission, observation or control reply. A late successful submission
without a current claimant is cancelled through the existing Job owner; a reply
for a Job already adopted by a current pane cannot cancel that Job.

Execution arrows and stepping require the original registered source reference,
saved SHA, actual observation SHA, unchanged editor bytes, source-widget
incarnation and Session lifetime. Loading another clean source is a context
change even when its dirty flag is false. The original Job can still be stopped;
its historical observation does not become an execution location in the newly
loaded source. This is client/source admission in the existing debugger, with
unchanged native interpreter and durable Job authority.

The Breakpoints table includes physical line, enabled state, enclosing source
function, file, Registry reference and full SHA-256. `sourceSurfaceFunctionAt`
provides the display label from existing structural fold ranges and their source
headers; interpreter observations remain authoritative for execution/frame state.
The Python footer uses a short SHA prefix to keep cursor/dirty feedback visible;
the full revision remains in Registry, Runner and Job details.

## Illustrated integrated documentation

Both editor Help menus and F1 explicitly call the existing Documentation Browser
module-window owner. Its optional GX-Markup image callback renders bounded local
PNG resources beneath the installed module root, with no executable markup or
external image retrieval. User manuals support language-labelled fenced code,
search, navigation, responsive image subsampling and a full-resolution native
image window with both scrollbars. Photo resources are released on reload/close.
Other Markdown clients retain their ordinary renderer call without an image
callback. No new documentation store or scientific publication is introduced.

The icon resource is the existing CORE `native2DViewportGlyph` owner, with
integer-stroke names `debug_start`, `debug_continue`, `debug_pause`, `debug_stop`,
`debug_into`, `debug_over`, `debug_out`, `debug_breakpoint` and `debug_clear`.
Glyph size follows the GUI font. Narrow toolbars use one row of icons with full
pointer/focus tooltips; ordinary widths include text. This scoped vocabulary
does not add a general Viewer icon authoring system.

These are host-only GUI operations. Scientific Python/Octave clients use the
existing Script Execution/Job APIs, without Tk widget pointers or unrestricted
GUI callbacks.
