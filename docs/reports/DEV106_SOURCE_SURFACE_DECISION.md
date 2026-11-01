# Source surface engineering decision

Use a single CORE Tk Text adapter backed by a compiled C++ lexical/document model.
The accepted framework already has Tcl/Tk input, Unicode, selection, clipboard,
Undo and focus behavior. Replacing that widget would duplicate a mature editor
and increase IME/accessibility/lifetime risk. A native lexer reduces duplicated
whole-document regular-expression implementations without replacing input.
The same adapter now serves both editable script workspaces and read-only Dataset
code consultation; the editor modules retain only their Registry/property shells.

The new native extension follows the installed native loading model, compiles C
rendering and C++ document/token services with strict warnings, Tcl and libxml2,
and needs no network dependency. Build: make -C core/nativegui/document. The shipped
Debian shared object and source are matched by the release manifest. Other native
transports and protected scientific modules are untouched.

The scanner runs off the GUI event loop through existing managed request ownership.
Replies carry source revisions and bounded token batches; obsolete replies are
ignored. Tk Text remains the authoritative editable buffer. Native line/byte maps
are rebuilt in a bounded worker, rather than claiming a new persistent incremental
parser. A cache and more complete dialect grammars remain measured follow-up work.
The 4 MiB/200,000-token bounds and visible limit/error status make this explicit.

Folding is display elision with immutable physical source positions. Python uses
its installed AST parser; Octave uses native lexical block tokens. The same gutter
hosts breakpoints and current execution location. Exact source/property snapshots
own dirty state; syntax jobs and folding do not own script persistence.

Debian evidence covers native mapped editors, four source palettes, disabled
highlighting, exact Undo to clean, folding source identity, managed native debugger
arrows/stacks and independent Unicode clipboard paste/export. IME and screen-reader
acceptance beyond inherited Tk behavior remain unverified; no new C++ editor or
cross-platform acceptance is claimed.
