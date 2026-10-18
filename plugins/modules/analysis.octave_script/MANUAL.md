# GX-TXT Octave Script — Manual

SPDX-License-Identifier: GPL-3.0-or-later

**Module:** `analysis.octave_script`
**Editor API:** `OCTAVE_SCRIPT_EDITOR_API_v1`  
**Execution:** CORE Script Registry and `OCTAVE_SCRIPT_BRIDGE_API_v1`

## Purpose

The Octave Script Workspace edits GNU Octave `.m` programs that run against registered GX-TXT public APIs. Script Registry is the authoritative executable identity. The Workspace, Script Library, Session Script Explorer and normal Octave Analysis selector see the same registered source.

The bridge is not a sandbox. Scripts run as researcher-authored code with the current user's local permissions. Use trusted source and review its required APIs and input parameters before execution.

## Create and run a Session script

1. Open a Session and enable the **Octave Script** module.
2. Open **Viewers → Octave Script Workspace** and choose **New**.
3. Choose **Session** scope, enter a stable Script ID and name, write the source, then choose **Save**.
4. The saved script is immediately listed as `session:<script_id>` in Script Library, Session Script Explorer and the normal `analysis.octave_script` registered-script selector.
5. In Analysis choose `source_mode=registered_script`, select the Session script, set any input aliases and parameters, then run.
6. Save and reopen the Session to reuse the same identity and source. A run uses an immutable verified copy and records its source SHA-256 in execution provenance.

Choose **User** scope for a reusable `user:<script_id>` Library script. A user script is separate from Session identity. Assign it to a Session through Script Library when it should become a Session input. Editing a user script never silently rewrites a Session copy.

## Edit, copy and remove

Selecting a registered script in the Workspace loads its current name, description and code. **Save** updates that exact registered identity and its ordinary revision and SHA-256. Metadata such as language, semantic version, required APIs and typed parameters remains under Script Registry authority. Concurrent edits are checked against the previously loaded SHA-256; reload before retrying a stale save.

**Save copy** creates a new Script ID. **Delete** removes the selected registered record after confirmation. Script Library and Session Script Explorer reflect normal registry changes. Scope and stable ID of an existing record cannot be changed in place; create a copy or assign a user script to the Session.

## Legacy Workspace documents

Documents saved by older versions through `INTERACTIVE_DOCUMENT_API_v1` remain visible in the Workspace with a `legacy:` reference. They are readable without changing their Session identity. Select one and choose **Register as Session Script** or **Register as User Script** to create a new executable registry record from its source. The legacy document remains until explicitly deleted. New Workspace saves use Script Registry and do not create a legacy Interactive Document.

## Import and export

**Import .m** loads UTF-8 source into the editor. Choose a scope and Script ID, then Save to register it. **Export .m** writes the current source as an external Octave file. Import/export is useful for interchange and is not required between Workspace and Analysis. The Analysis `external_file` mode can run a standalone `.m` when intentionally selected.

## Workspace editing controls

The editor provides line numbers, syntax coloring, search next/previous, go-to-line, undo/redo, UTF-8 source, a bridge template and snippets. Its list shows registered Session and User scripts plus readable legacy documents. The Workspace requires an open Session for Session scope; user scope uses the user's Script Registry library.

## Script source and public APIs

A script can call `gxtxt_context()` to inspect Session context and aliases. Use `gxtxt_api_list()`, `gxtxt_api_describe()`, `gxtxt_api_require()` and `gxtxt_api_call()` for public API discovery and invocation. The editor and runner contain no private Dataset, Plot Dataset, numerical or publication adapter. API arguments and results use the documented Script Bridge typed-node contract.

Example:

```octave
ctx = gxtxt_context();
api = gxtxt_api_require('NUMERIC_API_v1@1:math.numeric');
value = gxtxt_api_call('NUMERIC_API_v1', 'array_unary', ...
  {'abs', struct('kind','scalar','value',-2)});
disp(value);
```

Required API preflight combines the registered script's declared required APIs with the optional Analysis configuration list. Missing or incompatible APIs fail before the script runs. Script Library can edit semantic version, description, required APIs and typed parameter declarations for the same Script Registry identity.

## Analysis configuration

- **Script source mode:** `registered_script` for a Session record, or `external_file` for a standalone `.m`.
- **Session registered script:** `session:<script_id>`; the selector lists current Session Octave scripts.
- **Working directory:** optional explicit execution directory. Leave empty to use the Session directory.
- **Include script directory:** opt in when helper `.m` files beside an external script are needed.
- **Arguments:** module-specific text passed to the script execution context.
- **Required APIs:** optional additional API preflight.

The runner writes `executed_script.m` and `octave_script_run_report.txt` for each Analysis run. The snapshot and report identify the exact source used. Script Library Run and Session Script Explorer Run use CORE Script Execution with the same registry identity rules.

## Troubleshooting

If a new Workspace script is absent from Analysis, check that its scope is **Session**, its language is Octave and the module is enabled; the selector intentionally excludes user-only scripts. If Save reports a changed source SHA-256, reopen the record and reapply the edit. A legacy document must be explicitly registered before it is an Analysis input. If public API preflight fails, inspect required API IDs and versions in Script Library.

## References

- `OCTAVE_SCRIPT_EDITOR_API_v1.md` for the Workspace activation and persistence contract.
- CORE `SCRIPT_REGISTRY_API_v1`, `SCRIPT_EXECUTION_API_v1`, `OCTAVE_SCRIPT_BRIDGE_API_v1` and `VIEWER_PROVIDER_API_v1` documentation.
- `examples/` for executable Bridge examples.

## Editing menus and saved revisions

File, Edit, View, Run and Help share one compact menu row. Ctrl+A and Edit → Select All
select the focused editable control, including multiline UTF-8 source and metadata.
Ctrl+C/X/V keep that focus. Pasting over selected source replaces it as one local
undo transaction; Ctrl+Z undoes it and Ctrl+Y redoes it. Selection and copying do
not mark the document modified or write a Script Registry revision. Ctrl+S saves;
Ctrl+F, F3/Shift+F3 and Ctrl+G retain find and go-to-line; Escape in Find returns
to the source. Disabled line numbers and Bridge reference text are not editable.

Run → Open Script Runner opens the existing CORE Runner without submitting a
Job. A dirty registered buffer prompts: Yes saves it and opens the Runner, No
opens the last saved revision while retaining edits, and Cancel returns to editing.
The Runner shows its actual scope, ID, version and SHA, and requires its own Run
command to execute. A source changed elsewhere is explicitly identified; stale
saves remain rejected. Run also opens the existing Script Library and Jobs Manager.

An unregistered buffer must first be saved. Legacy Octave documents require the
explicit Run → Register legacy as Session/User action; merely opening a Runner
never converts them. Existing documents and execution snapshots retain their
identities. An editor bound to another or subsequently closed Session cannot perform
Session-scope save, delete, register or Runner operations there: export any unsaved source if needed,
close it, and reopen the workspace in the intended Session.

## Authoring without a Session

[Layout](#workspace-panes-and-layout) · [Breakpoints](#source-gutter-folding-and-breakpoints) · [Debugging](#start-and-inspect-a-real-debug-job) · [Worked examples](#worked-examples)

Open **Viewers → Octave Script Workspace** even when no Session is open.
New scripts default to **User** scope. Edit, import, export and Save work in
the User library without creating a Session. Session registration, scientific
execution and Debug require a real open Session. Use Script Library to assign
a User script to that Session; this creates a distinct Session identity.

## Workspace panes and layout

The menu row is **File, Edit, View, Run, Help**. Explorer selects registered
scripts on the left; the editable source is central; public Bridge snippets
remain on the right. **View** independently controls Explorer, Snippets,
Debugger, Call Stack, Variables, Debugger Output and Breakpoints. Opening Debug
adds a lower assistant; it preserves both side panes. Drag the horizontal and
vertical splitters to allocate space. Closing Debug restores the source area.
Five repeated open/close cycles do not require rebuilding the editor.

**View → Focus source** is reversible; **Reset layout** restores the default
proportions. Pane visibility and splitters are presentation settings saved in
the user's configuration. **View → Script properties / parameters** collapses
metadata without changing its values, source or dirty state. This is useful
with a 900 × 560 window and a large GUI font. **Show script properties / parameters** expands it again. Appearance font settings apply when GX-TXT
starts; restart after saving a different GUI font size.

![Three-pane editor with the managed native debugger.](images/debugger-paused.png)

## Source gutter, folding and breakpoints

The narrow gutter has independent lanes for breakpoints, the current execution
arrow and folding, followed by physical line numbers. A filled red dot is an
enabled breakpoint; a hollow red dot is disabled. A yellow arrow marks the
selected paused native frame. Small chevrons collapse a function or block;
folding never edits the source. Clicking a fold chevron does not toggle a
neighboring breakpoint. Digits widen as the file grows beyond 99, 999 or 9999
lines. Scrolling and folding retain physical line identities.

Click the breakpoint lane on an executable line. **F9** toggles the current
line; **Ctrl+Shift+F9** clears all breakpoints. The gutter context menu and
Breakpoints tab offer Enable, Disable, Remove and Clear all. Blank lines,
comments and non-executable targets are refused. Breakpoints are associated
with the exact source identity/SHA; editing invalidates their old positions.
Set them again after editing. Breakpoint changes are locked during a managed
Debug Job so the display cannot pretend that the running snapshot changed.

## Start and inspect a real Debug Job

1. Open a real Session. Save or assign a Session script and select it in Explorer.
2. Save source edits. Debug always runs the immutable registered source and SHA.
3. Choose **View → Debugger** or the Debug command in **Run**.
4. Place a valid breakpoint, then click the **Start Debug** play icon.
5. Inspect STARTING, RUNNING and PAUSED feedback. At PAUSED, compare the yellow
   source arrow with the selected Call Stack row, file, line and local values.
6. Use **Step Into**, **Step Over** and **Step Out** for genuine interpreter
   stepping. Selecting a caller row requests that native frame and its locals;
   it does not move the interpreter's actual execution frame.
7. **Continue** resumes the program. **Pause** uses Python native tracing while
   running. The managed GNU Octave CLI adapter does not support verified
   asynchronous Pause: its button is disabled with an explanation. An interrupt
   can terminate an Octave loop, so use native breakpoints and steps instead. **Stop** cancels the managed Job. Completion clears the arrow
   and active stack/variables before another run.

![Selected native caller and synchronized source location.](images/caller-frame.png)

Toolbar icons have pointer and keyboard-focus tooltips. At narrow widths their
labels collapse to icons; the functions remain available. Disabled buttons
reflect actual Job state. Locals / Globals are bounded read-only summaries
with type, shape and value; this is not an expression Watch or arbitrary eval.
An external stack frame shows its actual path/line, with no misleading arrow
in unrelated source. Folded current source is revealed for inspection.

**Debugger output** contains bounded native command/status receipts.
**Program output / diagnostics** opens the ordinary Script Job details with
stdout, stderr and immutable execution provenance. These are distinct streams.

## Closing, source revisions and Session changes

Hiding Debug through View preserves its managed Job. **Close / cancel Debug**
asks before cancelling an active Job; Cancel keeps it open. Closing the editor
also protects unsaved edits and an active owned Job. A closed or changed
Session blocks stale scientific operations; export an unsaved buffer before
reopening in the intended Session. Debug refuses unsaved, unregistered or
externally changed source. Editing while paused does not alter the running
snapshot: source stepping controls are disabled until the saved identity agrees.

## Worked examples

`examples/debug_temperature.m` uses only
public `NUMERIC_API_v1` calls for conversion and reduction. Input temperatures
are 18, 20, 22, 21 and 19 °C. Add the exact Celsius-to-kelvin offset 273.15 K.
Expected output is 291.15, 293.15, 295.15, 294.15 and 292.15 K; mean 293.15 K.
Declare `NUMERIC_API_v1@1:math.numeric` in required APIs. Import the example,
save it as a Session script, and place a breakpoint on the first output line
after the reduction. Inspect `celsius`, `kelvin` and `average`.

`examples/debug_nested.m` deliberately
uses ordinary language arithmetic for stepping practice. The five adjusted
values are 1, 2, 3, 4 and 5; the final total is 15. Break on the call to
`adjust`, Step Into, inspect `value`, Step Out, then Step Over the addition.
Select the caller to compare its `sample` and `total`. Continue to completion,
then run the saved script normally through Script Runner. No example publishes
a Dataset or modifies scientific source data.

## Integrated help and troubleshooting

**Help → Viewer manual / Debugger guide…** and **F1** open this independent rendered guide with
embedded real GUI images. Use Find / Find next, the section links and Back /
Forward. The manual remains available without a Session and after closing the
editor. Source example links are supplied in the module's `examples/` folder;
import them through File rather than executing a documentation hyperlink.

If Start is disabled, read the IDLE explanation: check Session, Session scope,
saved source and registered SHA. If panels seem missing, inspect View checkmarks
and Reset layout. If values seem stale, compare the selected native frame and
the Job source identity before interpreting them. Missing required APIs fail
preflight; use the public API documentation rather than a private fallback.
