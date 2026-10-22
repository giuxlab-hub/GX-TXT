# Source Surface API v1

Discover `::GX::sourceSurfaceApiInfo`. CORE creates one shared Tk Text adapter:
`sourceSurfaceCreate parent {mode editable language python}` returns the text
widget. Use read_only for Dataset source consultation. Set/Get/Configure/Replace,
Scan, Find, Fold, Breakpoints, Location and Refresh have the `sourceSurface`
prefix. Both existing script editors and read-only Dataset code views use it.

`sourceSurfaceScan language source` is headless and returns native C++ tokens
(category, Tcl character start/end, physical line/column, UTF-8 byte start/end),
fold ranges and an explicit limit indicator. Supported families: JavaScript, C,
Python, Octave/MATLAB syntax, Fortran, Perl, Tcl/Tk, XML, HTML, Markdown and TeX source.
The ordinary Markdown document Open uses the established rendered markup owner
and has no syntax controls. XML/HTML rendered consultation uses native C.

Dev109 adds `tex` (and scanner alias `latex`) in the same native C++ lexer.
Command words, escaped control symbols, unescaped percent comments, math
delimiters/scripts, braces, inline `\verb` and verbatim/lstlisting blocks have
lexical colors. Prose quotes do not become programming-language string spans;
escaped percent and verbatim percent are not comment starts. This conservative
presentation does not expand macros, validate environments, supply TeX structural
folds or compile/typeset mathematics. The actual configured TeX engine remains
the typesetting authority. The shared Source Surface retains its existing
editable/read-only, Unicode clipboard/Undo, Find/Replace and generation contracts;
declarative TeX project persistence, managed build and PDF are separate gates.

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

## Find and visible result feedback

Host-only `sourceSurfaceFindCurrent widget ?direction=forward?` searches using
the full query stored in that Surface's declared Find bar. It delegates to
`sourceSurfaceFind` and returns the same Tk start index or empty string. A Surface
created without `find_bar 1` rejects this convenience call because it has no
stored Find query; callers can still use the explicit-pattern function below.
This is the actual shared button/Enter/F3 owner, not a new Script/C++ operation.

`sourceSurfaceFind widget pattern ?direction?` searches literal text, ignoring
case, with wraparound. Direction defaults to `forward`; `backward` selects the
previous occurrence. It returns the actual Tk start index, or an empty string
for no match or an empty query. A match is highlighted and revealed without
changing source bytes. An empty query removes the previous highlight.

With the optional `find_bar` enabled, the shared Find row displays `No matches`,
`Enter search text`, or the actual matched index. This result is independent of
the lexer readiness/error message. Ctrl+F, F3, Shift+F3 and the Previous/Next
buttons use the same owner. Opening another source resets the result.

Host-only `sourceSurfaceFindInspect widget` returns `status` (`idle`, `empty`,
`not_found`, `found`), `query`, `query_characters`, `query_truncated`, `direction`,
`index`, `end`, `message` and `source_revision`. The inspection query is limited
to its first 1,024 characters; search still uses the complete entered query.
This inspection receipt does not grant a new Script Bridge or restricted C++
operation. Native visual verification of this feedback is a separate GUI check.

`sourceSurfaceFindReplace widget pattern replacement ?scope?` replaces literal,
case-insensitive matches in an editable Surface. `current` (the default) requires
the still-matching highlighted Find result; `all` preflights up to 100,000
nonoverlapping matches. Empty searches, unsupported scope and read-only sources
reject before mutation. The result is `{replaced count scope current|all}`.
One Undo restores the complete replacement, including Replace all. An editable
Surface created with `find_bar 1` offers a second row with Replace with, Replace
and Replace all; Ctrl+H focuses the replacement field. An initially read-only
Surface does not create those controls. Reconfiguring the same Surface to
editable creates them; returning to read-only retains and disables the field and
both buttons. The public replacement API also refuses mutation. Ctrl+F/Ctrl+H
bindings consume the key after moving focus, so Tk Text's Control-h backspace
binding does not alter the source. Find/Replace positions use Tk text indices;
match counts are dimensionless and byte/character bounds remain distinct.

Independent dev109 native corrective CORE-fixture checks verified actual
Ctrl+F/Ctrl+H source preservation, native current/all replacement and single Undo,
read-only refusal and same-Surface editable/read-only transitions. The original
Ctrl+H corruption evidence remains preserved. This scoped shared-owner proof
does not establish installed LaTeX editor/build/SDK or complete release acceptance.

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
## Registered Python and GNU Octave operations

The existing Script Bridge registration for `SOURCE_SURFACE_API_v1` belongs to
CORE provider `source_surface`. It exposes only the following non-executing
operations; widget construction, live editing, breakpoint UI and GUI state are
host operations, not implied script capabilities.

| Script operation | Arguments | Registered result contract |
| --- | --- | --- |
| `info` | none | Non-executing source capability model. The binding normalizes `modes`, `operations` and `language_families` to language lists/cells. |
| `scan` | required `language` string, required `source` string | Native token/fold model; token coordinate fields and counts are integers, token collections and folds are lists/cells. The binding returns integer `line_count`, `characters`, `bytes`, `truncated`. |
| `palette` | required `theme` string | Existing source palette dictionary/struct; an appearance result, not scientific data. |

Python uses `gxtxt_api_call('SOURCE_SURFACE_API_v1', 'scan', ['python', source])`.
GNU Octave uses `gxtxt_api_call('SOURCE_SURFACE_API_v1', 'scan', {'python', source})`.
Both require an already active managed Script Bridge and preserve the declared
positional argument order. `gxtxt_api_describe('SOURCE_SURFACE_API_v1')` returns
the current registration. Scanning the string never executes/imports it.

The host's `sourceSurfaceCreate` and editor `mode=read_only|editable` controls
remain separate. Current direct restricted C++ policy does not grant this API;
the reviewed GUI Host `document_bind` operation may compose an existing
read-only source presentation without becoming a generic direct Source Surface
SDK call. Use the current C++ support catalog and project admission report.

Language availability must follow `sourceSurfaceApiInfo` and the installed
native scanner. Existing documented families are JavaScript/C/Python/
Octave/Fortran/XML/HTML/Perl/Tcl/Tk/Markdown and TeX (`tex`, native scanner alias
`latex`). TeX support is lexical presentation only, as described above; this
reference does not claim TeX structural folds, compilation/typesetting,
complete language parsing or every dialect. The
existing 4 MiB/200,000-token bounds, truncation and conservative-lexer limitations
remain those documented by the source owner.

Editable Find bars offer literal current/all replacement. Ctrl+F and Ctrl+H
transfer focus and stop subsequent Text-class bindings, preserving source bytes,
caret and the current Find match. A surface changed from read-only to editable
gains the same shared Replace controls; returning to read-only disables them and
the public replacement API refuses mutation. The dev109 native Ctrl+H failure
is preserved; the independent corrective CORE-fixture native verification passed
this scoped behavior, while installed LaTeX integration remains separately open.
