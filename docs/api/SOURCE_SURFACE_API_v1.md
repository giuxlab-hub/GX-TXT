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

Appearance presets are Automatic, Readable Light, Rich Dark, High Contrast Light,
High Contrast Dark and Custom. The application GUI theme and source palette are
independent. Token color overrides, named saved schemes, per-language highlighting,
live Python/Octave previews, reset controls and measured contrast warnings live
in Configuration → Appearance. Source buffers are never saved by a palette edit.
