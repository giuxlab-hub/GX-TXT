# Code Dataset Viewer

Code Dataset Viewer reads compatible canonical source Datasets in the current Session. It is a consultation tool: opening source never imports, compiles or executes that code, and there is no source-edit or Save command.

## Choose and open source

Open **Code** under **Documents** in the Viewers catalog. Choose a source in **Source Dataset**. Selecting a compatible source opens it; **Open source** refreshes the selected consultation. With no eligible selection the document area displays an awaiting-selection prompt.

The selector uses current-Session canonical Dataset identities. It accepts `code.source` and supported `document.text` sources through the shared CORE compatibility contract. Images, tables and PDFs belong to their corresponding Viewers. A Dataset label is a selection aid; the canonical Dataset identity and source revision remain authoritative.

## Find, read and copy

Use the shared Find bar above the source: type literal text and choose **Next** or **Previous**. **Enter**, **F3** and **Shift+F3** navigate matches; **Ctrl+F** focuses Find. A no-match result is reported by the existing Source Surface.

Click the source to focus it. Use the mouse wheel, scrollbars, Page Up/Down, arrows, Home/End and Ctrl+Home/End to navigate. Select text with ordinary pointer/keyboard selection and use **Ctrl+C** to copy. **Ctrl+A** selects the source. Copying changes neither the Dataset nor its canonical source.

Physical line numbers and syntax colors come from the shared Source Surface. Its existing structural fold controls are available where the language model supplies folds; folding changes presentation only. Source language comes from canonical metadata. Unknown languages use plaintext; colors are not a code-validity or execution result.

The shared native scanner advertises Tcl/Tk, Python, C, JavaScript, Octave/MATLAB syntax, Fortran, Perl, XML, HTML and Markdown source families. Its lexical model is conservative: complex dialect constructs may receive approximate highlighting. This Viewer adds no lexer or parser.

## Read-only behavior and source lifetime

The source text is read only. There is no source Save, Replace, Run or Compile control. Find, selection, copy and folding are presentation operations. The Viewer does not publish derived scientific data.

Changing Session invalidates the previous source binding. Select a source from the new Session and open it again. Changed, missing, incompatible or stale source must produce an explicit state rather than retain an apparently current old document. Close and reopen the Viewer to begin a new consultation.

The shared scanner documents a 4 MiB source and 200,000-token bound. The document host also bounds canonical reads; these limits are not permission to load arbitrary files. Observe an actual size, token or encoding diagnostic rather than treating a partial structural model as full analysis. Canonical bytes and source identity remain under CORE Dataset and Resource authority.

## Layout, Help and ownership

The source uses the central reading area, with the Dataset selector above and compact keyboard reminders below. No permanent inspector narrows the source pane. Resize the window as needed; horizontal scrolling preserves long physical source lines.

Use the integrated **Help** control or **F1** for this manual through the normal Documentation Browser.

The original folded-page icon with code brackets identifies source consultation. It is a project-authored GPL-3.0-or-later asset admitted and packaged by the official Builder icon owner.

This Viewer reuses CORE Dataset access/catalog filtering, SOURCE_SURFACE_API_v1, GUI Host lifetime, shared Find/navigation/clipboard behavior and the Documentation Browser. Its C++ handler submits only the typed `document_bind` request for its own declared document and selector. No source bytes or filesystem path enter authored C++; the Viewer contains no alternate editor, runtime, publication service or renderer.
