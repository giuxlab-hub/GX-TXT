# Python Script 1.2.0

## Python Script Workspace

Open **Viewers → Python Script Workspace** in a Session. Choose **New**, select User or Session scope, enter a stable script ID, name, semantic version, description, required APIs, and optional typed parameters, then edit the Python source and **Save**. The Script Registry records revision and SHA-256. **Save As** creates another ID. The editor has line numbers, Python highlighting, undo/redo, search in both directions, go to line, UTF-8 `.py` import/export, and public `gxtxt` bridge help. Closing an unsaved edit prompts to save or discard it.

Select a registered Python script in the left list to reopen it. **Run → Open Script Runner...** opens the existing CORE dialog with the exact registered identity, saved revision, SHA and typed parameters; it does not submit a Job. Session scripts also appear in Session Script Explorer and the `analysis.python_script` selector; User scripts appear in Script Library and can be assigned to a Session. Deletion uses the common resource lifecycle and refuses active Analysis dependencies. Execution snapshots remain in the Session.

Python Script is a normal GX-TXT Analysis module for researcher-authored
scientific data processing. Create or import a `.py` file in Python Script Workspace or Script Library,
assign it to a Session, select the `session:<id>` entry in Analysis > Python
Script, enable the module, and run it through the normal Run page. Registered
Session scripts retain their own source snapshots; a later user-library edit
does not change the Session copy. Execution snapshots and provenance are under
`analysis/scripts/` in the Session.

The configured `runtime.python` supplies Python and any scientific libraries.
The public `gxtxt` client discovers and calls the same provider-owned public
Script Bridge bindings as Octave. Declare required APIs for preflight before
scientific code runs. The execution context includes a framework-owned
`output_dir`; completed files there can be published through
`DATASET_FILE_PUBLICATION_API_v1`. Use
`PARALLEL_EXECUTION_API_v1/resources` to bound worker pools.

See [the shared scripting guide](../../../docs/help/scripting.md),
[the client reference](../../../docs/api/PYTHON_SCRIPT_CLIENT_v1.md), and
the [parallel policy](../../../docs/api/PARALLEL_EXECUTION_API_v1.md).

## dev097 editor menus and saved revisions

File, Edit, Run and Help share one compact menu row. Ctrl+A and Edit → Select All
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

An unregistered buffer must first be saved. Octave legacy documents require the
explicit Run → Register legacy as Session/User action; merely opening a Runner
never converts them. Existing documents and execution snapshots retain their
identities. An editor opened for another or subsequently closed Session cannot
save, delete, register or open a Runner there: export any unsaved source if needed,
close it, and reopen the workspace in the intended Session.
