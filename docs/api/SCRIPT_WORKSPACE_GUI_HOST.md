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
diagnostics opens the actual Job's separate retained streams. Terminal states
clear current-frame presentation.

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
