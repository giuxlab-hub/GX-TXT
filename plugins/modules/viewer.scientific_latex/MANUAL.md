# Scientific LaTeX Article Workspace

Candidate 0.2.4 updates this manual to the independently observed installed 0.2.3 behavior. The retained scientific campaign produced a genuine three-page native-TeX PDF. Focused follow-ups verified the 960 × 740 layout, source-linked warning navigation, association History persistence and a full cold restart. The subsequent Configuration and LaTeX continuation verified native Copy, the chosen runtime after same-profile restart, populated normal/narrow inventory panels, unavailable-tool recovery and authentic Session A → empty B → A. This documentation does not declare full dev109 integration or all fifteen workstreams accepted.

## Article and interface

The left inspector selects a canonical article and displays its identity, source revision, build status and associated assets. The main area separates editable TeX source from its compiled PDF association. Diagnostics and the full compiler transcript have separate lower tabs.

**New** creates an empty canonical TeX article in the current Session. It does not generate a scientific article or build a PDF. **Refresh projects / status** refreshes the actual article choices and retained status. Select an article and choose **Open**. A dirty previous buffer receives the existing Save, Discard or Cancel decision.

**Import .tex** opens the existing managed source chooser and creates a new canonical article from a real UTF-8 TeX source. The original scientific source is preserved. Source size, encoding and resource failures must remain explicit.

The article is an existing canonical TeX Workspace. The optional interface Workspace controls at the bottom save the Viewer's association and presentation state. These identities have different purposes. Saving interface state must not create another editable source store or overwrite a newer canonical article from an old presentation snapshot.

## Source editing and Save

Type TeX in the existing editable Source Surface. Its native cursor, selection, clipboard, keyboard navigation, Find/Replace and text Undo/Redo operate on the current buffer. TeX lexical colors are conservative; highlighting is not compilation or proof that a package exists.

**Save** commits exact UTF-8 text through the existing Document and managed Resource owners. It checks the current article identity and saved revision. Unsaved edits and the last saved revision remain distinct. Resolve a stale-save conflict through the normal owner rather than discarding another editor's changes.

Native text Undo changes the current buffer. The interface History controls manage saved interface presentation and article association. They do not turn an old interface snapshot into replacement canonical article bytes. Installed 0.2.2 recorded and browsed genuine association History, but its History-only normal-close persistence failed to offer Save; that failure remains preserved as historical evidence. The corrected installed 0.2.3 offered the native Yes/Save decision after actual association navigation 3 → 1 → 3. Four History steps, cursor 4 and the current article association survived a full process restart. This is association History, distinct from native source Undo.

## Figures, bibliography and support assets

**Add assets** uses the existing managed file chooser followed by the shared relative-name form. Give each resource the exact project-relative name referenced by the article, including a nested directory if needed. Replacing a linked resource uses a normal confirmation.

The asset table is a read-only bounded projection of canonical managed resources. Its exact rows are:

| Visible column | Canonical field | Meaning |
| --- | --- | --- |
| Asset | name | Normalized relative project name. |
| Format | format | Declared resource format. |
| Bytes | bytes | Actual managed byte count. |
| Availability | availability | Actual current availability result. |

At most the first 1,000 rows are shown. A larger project must report that bound truthfully; absence from the visible page does not mean an asset was deleted. The table does not infer scientific metadata. Native selected-row identity belongs to the host. Select a row and choose **Remove selected asset** to request a confirmed canonical removal. The original imported file remains preserved.

Use legitimate figure resources and .bib bibliographies, and any genuinely needed local support files admitted by CORE. Asset names must be normalized relative project names. The canonical source is main.tex; .gxtxt-build is reserved for generated outputs. The article must use a package, class, font and bibliography workflow actually installed on the configured TeX environment. The Viewer does not install packages.

## Build and diagnostics

**Build** explicitly saves the current draft first. If guarded Save fails, compilation must not start. A successful Save is then passed to the existing managed TeX build service. **Rebuild** also saves current input before requesting a fresh managed build. The scientific typesetter is the real configured native TeX toolchain; clicking Build does not compile the C++ Viewer.

Configuration Runtime owns executable choice, Detect and Test. Configuration Scripts owns the read-only LaTeX environment inventory beneath the Python environment table. Check actual executable versions and installed packages/classes/fonts there. This Viewer does not maintain a second runtime or package catalog. The practical steps and independently verified scope are described below.

Status and Compiler output belong to the genuine managed build. The diagnostics table shows the first 1,000 real compiler diagnostic rows; the full native transcript remains in Compiler output.

| Visible column | Diagnostic field | Meaning |
| --- | --- | --- |
| Severity | severity | Genuine error or warning classification. |
| Asset | file | Actual source or project-asset filename, when reported. |
| Line | line | Actual reported source line, when available. |
| Message | message | Native diagnostic message. |

The host owns each selected diagnostic identity, actual build revision and exact source_link. The static text above the table gives guidance; it does not report whether a build has errors or warnings. Read the actual table and build status for that result. Select a diagnostic and use **Go to selected source error**. Navigation requires the genuine build revision and a verified source link. A genuine warning can have a reported line but no filename or source_link; in that case its location is unavailable. No source location is guessed. Asset source can open read-only through Source Surface.

**Cancel build** targets the article's exact current request. A cancellation request is not proof of terminal cancellation: a short build can finish first. Refresh and inspect the observed state and real log.

Compilation stages verified source and assets in managed resources, disables shell escape and retains native tool diagnostics. The Viewer supplies no private compiler, log parser, filesystem exporter, renderer or process supervisor.

## Authentic PDF preview and export

After a successful build, **Open PDF preview** opens or raises the existing native managed-resource PDF reader. That reader owns page navigation, page count, Fit Page/Fit Width, zoom and scrolling. It is a real typeset PDF, not a TeX approximation or source text presented as output.

Resize the window or drag the source/PDF divider to choose useful pane widths. The PDF status label stretches with its existing grid column and wraps through the shared host. The installed 0.2.3 focused 960 × 740 test verified the allocated source/table layout, wrapping PDF status and empty-state text, and native scrolling of diagnostic guidance. This observation does not promise that arbitrarily tiny windows can display every control simultaneously.

The displayed compiled revision and the current source/assets revision remain distinct. Editing source or changing assets makes a prior PDF stale. An unsuccessful build retains genuine diagnostics and may retain a previous good PDF with its older revision clearly identified. Reopening or changing a view never implicitly builds.

**Export .tex** uses the existing File Publication chooser for editable UTF-8 source. **Export PDF** requires a successful authentic PDF matching the current complete source/assets revision. A stale or failed build must not publish an older PDF as current. Existing destinations use the normal replacement confirmation.

**Export linked assets** publishes legitimately associated resources at their source-relative names. Source/PDF export can use the shared bundled-asset policy where offered. The required document outputs are only .tex and PDF; assets support the same project. No format converter or additional document output is provided.

## Session, close and failure behavior

Article selection, build callbacks, preview resources and canonical saves are scoped to the actual Session and Document generation. A Session change, deleted/replaced owner or closed Viewer must not commit a stale callback. Refresh or reopening must not submit another build automatically.

Use the native Save/Discard/Cancel prompt for a dirty buffer. Failed imports, stale saves, missing packages, invalid TeX, cancelled builds, missing resources and publication errors must retain truthful diagnostics and preserve the last valid canonical source. An error or an old PDF is never a fresh build success.

## Configuration: runtime and environment inspection

1. Open **Configuration → Runtime**, locate the LaTeX runtime, choose an actual installed executable, then use the normal Save, Detect and Test controls. An executable version confirms that tool, not every possible document package. The installed tests selected `/usr/bin/pdflatex`; the same complete profile retained this choice after a fresh GX-TXT process restart. The supported engine/build-driver contract belongs to CORE; this Viewer supplies no separate command line.
2. Open **Configuration → Scripts**. The existing Python environment table remains above the read-only LaTeX environment panel. **Refresh** inspects the actual native tools, search roots and discoverable package/class/font/helper records. It does not install, update or remove packages.
3. Use the panel search to narrow the retained observations, inspect the actual package/location/status columns and scroll the native table. **Clear** resets the search. A visible row bound is a presentation limit, not a count of all installed packages. The tested environment recorded 914 Python observations and 8,298 TeX observations, with a bounded 500-row visible TeX page; these are environment-specific observations, not guaranteed counts. Searches for `article` and `amsmath` returned six and five actual matches respectively. Normal and 960 × 740 populated panels retained usable native tables and wheel scrolling after the shared layout correction.
4. For a genuinely running refresh, **Cancel** requests cancellation of that exact inventory operation. Inspect its actual terminal status; do not infer cancellation from a click. The independent test observed a live cancellation and owned-process cleanup while retaining prior valid observations. An unavailable explicitly chosen runtime produced a precise error without starting an inventory request; restoring `/usr/bin/pdflatex` through normal controls recovered it.

The environment inventory is machine-scoped rather than article source. Its valid observations may remain available after switching Sessions. A tested refresh completed before the actual Session transition, so simultaneous live-refresh/Session overlap was **not observed**; this manual does not claim that timing case. Inventory and version checks do not compile the article or the C++ Viewer.

## Clipboard and Session switching

Native **Ctrl+C** copies the actual Source Surface selection. In the independent test, Ctrl+Home, Ctrl+Shift+End and Ctrl+C copied all 3,941 UTF-8 bytes of source revision 7 without changing source, History or dirty state. Other native keyboard editing remains owned by Source Surface.

Switch Sessions using the normal Sessions controls. The independent continuation opened the authentic saved article in A, switched to a genuinely empty B, and returned to A through normal saved-Workspace opening. The old A source naturally became read-only and its PDF reader expired; an empty B Viewer exposed no A article, source or PDF. Returning to A retained exact source revision 7, both linked assets, the current genuine PDF and History 4/cursor 4. A newly opened unsaved interface in empty B may itself be dirty even though B contains no scientific article; declining its native interface Save prompt discards that empty presentation, not A’s scientific source. Preserve the distinction between interface state and canonical article content.

## Independently exercised scientific workflow

The installed 0.2.1 test used a clearly labelled synthetic scientific article with two real linked assets: a triangle figure and a .bib bibliography. Import the article, add its assets at the exact relative names used in its TeX, then use **Build**. The managed native toolchain produced a genuine three-page PDF.

Independent review of the actual PDF pages confirmed UTF-8 caffè and naïve plus a literal em dash; numbered and aligned equations; a scientific table containing 2.50 m, 0.125 s and 8.00 Hz; the figure, footnote, resolved cross-references/citation and real bibliography. This is evidence for that tested article and installed environment, not a promise that every package or arbitrary document works.

The native reader was exercised through pages 1, 2 and 3, its end boundary, Zoom, Fit Width and Fit Page. Genuine .tex and PDF exports included both original linked assets. Declining an asset-bundle collision preserved the original outputs; attempting PDF export from a dirty unsaved source was refused.

The error-path example inserted an undefined TeX command. The managed native build failed and retained the previous good PDF as stale. Selecting the actual main.tex line 79 error and choosing **Go to selected source error** visibly highlighted that source location. Native text Undo followed by explicit **Rebuild** repaired the article. This proves that actual error link. The subsequent installed 0.2.3 test also navigated a genuine main.tex line 19 warning with its authenticated source_link. A different external shellesc warning reported line 73 without a verified source file; selecting it correctly produced a precise unavailable-location message while preserving the source and caret. A reported number alone is not an authenticated location.

A deliberately long native TeX computation was genuinely started, then cancelled through **Cancel build**. The managed owner drained its process group and retained the prior good PDF as stale. Native Undo removed the long-loop edit; Save and explicit Rebuild produced the current successful PDF again. Cancellation status must still be observed rather than inferred from the button click.

Normal interface Workspace Save and close were exercised after the successful build. The historical installed 0.2.2 focused follow-up reopened source revision 7, the current PDF and both linked assets. Normal Development Review/Create upgraded copy retained the old interface Workspace and created a compatible copy. The corrected installed 0.2.3 then reopened saved interface Workspace 5 with four History steps after a full process restart. Its current PDF SHA-256 begins 579bea4f0d3a; the native read-only reader reopened page 1 and was normally reaped on close. Ordinary installed operations used the distributed Viewer binary with zero C++ compiler/linker invocations.

The historical 0.2.2 follow-up verified corrected static Diagnostics guidance beside two retained warnings, read-only Compiler output, current native PDF reopening, Runtime Detect/Test and native F1 help. Its observed History-only persistence failure and narrow PDF-status clipping were subsequently corrected and genuinely retested on installed 0.2.3. One authentic current TeX Build, linked main.tex line 19 navigation, precise source-less external line 73 refusal, native guidance scrolling and History-only Yes/Save plus cold restart were observed; the earlier full scientific campaign was retained rather than repeated.

## Candidate evidence and remaining gates

The public finite C++ broker operations behind the controls are new, open, save, build, rebuild, cancel, preview, diagnostic_open, import_assets, remove_asset, export_tex, export_pdf, export_assets, refresh and import_source. The complete section references the existing source, PDF, project selector, asset and diagnostic tables, compiler log, status and revision labels. Changing an article may save its dirty predecessor, so Open is declared mutating. A declaration alone does not authorize a private source write.

The recorded 0.2.0 Check Source and Validate passed without code generation. One explicit Build produced the compiled Viewer binary. The declared native test exercised only Open to the finite refresh plan. These results prove neither an installed article editing session nor a TeX typesetting run.

All project authoring uses the official Interface Builder and C++ Development Workspace. C++ dispatch emits only the finite declared tex_command plans for the existing shared owners; no source bytes or raw file destinations enter author C++.

Source/Builder/compiled-event checks certify only their stated stage. The qualified installed scientific, layout, diagnostics, History/restart, Configuration, Copy and Session workflows described here have independent evidence. Candidate 0.2.4 changes documentation and package version, preserving all 39 component ordinals and the author C++ source. A new development artifact is required by actual changed SDK/adapter/policy and package-version dependencies; this is distinct from normal installed execution, which must not compile. Remaining delivery gates for this manual revision are normal Plugin Manager update, installed F1/manual content-and-hash attachment, and MAIN’s complete 14B/integrated acceptance reconciliation. No completed source campaign is represented as full integrated acceptance and no unfinished TODO is removed here. Debugger: NOT USED by the Viewer author.
