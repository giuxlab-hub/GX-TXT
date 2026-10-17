# GX-TXT Octave Script — Manual

SPDX-License-Identifier: GPL-3.0-or-later

**Module:** `analysis.octave_script` 1.4.0  
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
value = gxtxt_api_call('NUMERIC_API_v1', 'array_unary.abs', ...
  {struct('kind','array','shape',[1 1],'real',-2)});
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
