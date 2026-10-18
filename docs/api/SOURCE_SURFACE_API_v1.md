# Source Surface API v1

Discover `::GX::sourceSurfaceApiInfo`. CORE creates one shared Tk Text adapter:
`sourceSurfaceCreate parent {mode editable language python}` returns the text
widget. Use read_only for Dataset source consultation. Set/Get/Configure/Replace,
Scan, Find, Fold, Breakpoints, Location and Refresh have the `sourceSurface`
prefix. Both existing script editors and read-only Dataset code views use it.

`sourceSurfaceScan language source` is headless and returns native C++ tokens
(category, Tcl character start/end, physical line/column, UTF-8 byte start/end),
fold ranges and an explicit limit indicator. Supported families: JavaScript, C,
Python, Octave/MATLAB syntax, Fortran, Perl, Tcl/Tk, XML, HTML and Markdown source.
The ordinary Markdown document Open uses the established rendered markup owner
and has no syntax controls. XML/HTML rendered consultation uses native C.

`sourceSurfaceReady widget` reports whether the asynchronous structural model
belongs to the exact current source. Set and edits immediately invalidate the
old model. Breakpoint toggle/enable is refused with visible retry feedback until
the new model is ready; stale replies cannot authorize a line in another source.

Source is bounded to 4 MiB and 200,000 tokens. Async scanning runs in an existing
managed CORE request; a generation check rejects stale replies. Tk applies at
most 250 token ranges per idle turn. Limit/error status is visible. The native
scanner is a conservative lexical service, not a language compiler: advanced
f-string expressions, full fixed-form Fortran and dialect-specific constructs
may receive approximate colors. No source is imported, evaluated or compiled.
The full bounded model is scanned in a worker; an incremental parser cache is
future optimization, not an implemented claim.

Tk owns Unicode input, native selection, clipboard, Undo/Redo and accessibility.
C++ owns lexical ranges and physical byte/line maps. Python AST supplies Python
structural folds without executing source; native Octave block parsing excludes
strings/comments and indexing `end`. Folding uses elided display ranges, never
inserts source text. Edits clear breakpoint positions with an explicit change
signal; set them again before Debug. Debug arrows refer to physical source lines.
Replace is one Undo transaction. Styling/folding never changes the dirty baseline.

## Gutter and breakpoint presentation

The gutter measures the current Text font, line count and display-line geometry.
Its adjacent lanes contain breakpoint circles, the selected paused-frame arrow,
fold chevrons and right-aligned physical line numbers. Elided physical lines do
not paint numbers. Changing font or crossing a digit boundary never changes
source bytes. Enabled breakpoints are filled red (`#D32F2F` in the light palette);
disabled breakpoints are hollow. The independent yellow arrow uses `#F5C542`
with a dark outline. Fold chevrons contain no appended counters.

`sourceSurfaceBreakpoints widget ?operation? ?physicalLine?` accepts `get`,
`describe`, `toggle`, `enable`, `disable`, `remove` and `clear`. `get` returns
enabled physical lines for native Job admission; `describe` returns
`{line integer enabled boolean}` records. Host-only `lock` / `unlock` prevent
local marker edits from pretending to update a running Job's admitted set.
Stop Debug before changing that set. Invalid statement targets are refused with
their exact line and a visible reason. Python instruction lines come from inert
compilation/disassembly of nested code objects; the displayed code is never run.
Octave comment/declaration/block-delimiter targets are refused. The native
debugger remains the authority for actual stops and runtime errors.

Click the first lane or press F9 to toggle. Ctrl+Shift+F9 clears all. The gutter
context menu exposes enable/disable/remove. A fold-lane click changes only the
fold whose header occupies that physical line. An execution-pointer click
reveals its source line. Hover identifies each independent lane.

Exact registered identity, SHA and content CRC key breakpoint presentation in
user Configuration `editor.breakpoints`. Session records also use their public
Session context in that local preference. At most 128 exact revision entries
are retained. Reopening the same revision restores markers; an edit clears
positions with explicit feedback. No automatic relocation or scientific Session
mutation is implied.

`sourceSurfaceLocation widget line` refers to the actual selected native frame.
Clear it with zero during execution, completion, cancellation, source edits or
an external frame whose file differs from the registered snapshot. The managed
debuggers report selected `line` / `function` separately from actual
`execution_line` / `execution_function`; stack, locals and the arrow belong to
one native observation and source identity.

`sourceSurfaceConfigure widget {mode editable|read_only}` explicitly changes the
native Text edit/Undo capability as well as the retained option. Appearance-only
configuration does not change that capability. Changing mode never edits source;
use Set when opening a different file to establish its own Undo baseline.

Appearance presets are Automatic, Readable Light, Rich Dark, High Contrast Light,
High Contrast Dark and Custom. The application GUI theme and source palette are
independent. Token color overrides, named saved schemes, per-language highlighting,
live Python/Octave previews, reset controls and measured contrast warnings live
in Configuration → Appearance. Source buffers are never saved by a palette edit.

`sourceSurfaceFunctionAt widget physical_line` returns the innermost enclosing
function label from existing structural fold ranges and their source headers,
or `<script>`. It supplies breakpoint display metadata; native interpreter stack
facts remain separate. Revealing a paused location unfolds only ranges that
contain that physical line. Unrelated collapsed functions retain their
presentation during subsequent debugger observations.
