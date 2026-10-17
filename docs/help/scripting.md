# Scripting

CORE Script Execution is always available. Its optional Analysis workspace can be shown or hidden from **Modules** without disabling the backend.

Use the one Script Library to create or import a GNU Octave `.m` or Python `.py` script. Every script has a language, stable ID, version, revision, SHA-256 hash, description, required public APIs and optional typed parameters. The user library stores reusable scripts across Sessions. Assign a user script to the current Session to create a physical Session-owned snapshot. The stable reference is `user:<id>` or `session:<id>`; a filesystem path is not the Session script identity.

Run a registered script directly from the Script Library, Analysis Script Workspace or Session Script Explorer. The execution uses an exact source snapshot, validates typed parameters and writes its report, log and provenance under `analysis/scripts/` in the Session. Session-owned scripts and their executions appear in the offline HTML export; unrelated user-library scripts do not.

For the normal **Octave Script** or **Python Script** Analysis module, choose `registered_script` and select a matching-language `session:<script_id>` entry. The selector lists current Session scripts and shows language, stable ID, name, version, revision, SHA-256 and required APIs. Enable **Run / recalculate now** and run through the normal Run page. GX-TXT verifies the Session-owned source hash, executes an immutable snapshot, and records the same identity in provenance. A later user-library revision never replaces the Session snapshot. Editing the Session script keeps its ID while increasing its revision and changing its SHA-256; earlier runs remain intact. Save and reopen retain the Analysis reference.

Octave retains an `external_file` compatibility mode for standalone `.m` paths. Registered Session scripts are the normal reproducible workflow for both languages. Workspace Interactive Documents can be exported and imported into Script Library; registered scripts need no export to run in Analysis.

Python uses the configured `runtime.python`, including whatever scientific libraries the researcher installed there. Import the public `gxtxt` client for API discovery, required-API checks, context and calls. NumPy arrays are available when NumPy is installed; large numeric arrays reuse the Bridge binary transport. A missing import or Python exception produces its traceback. Read the public Parallel Execution resource policy before creating worker pools. `gxtxt_context()["output_dir"]` is a framework-owned area for scientific output files; publish completed files through `DATASET_FILE_PUBLICATION_API_v1`. See the [Python client reference](../api/PYTHON_SCRIPT_CLIENT_v1.md) for examples and transport details.

See [Script Execution API](../api/SCRIPT_EXECUTION_API_v1.md), [Sessions](sessions.md) and the [Configuration API](../api/CONFIGURATION_API_v1.md).

To package an exact `.m` or `.py` research script as an ordinary installable Analysis module, use the [Script Module Builder](script_module_builder.md) from the Modules page.

## New public operations (dev-051)

Python/Octave examples `examples/scripts/combined_stabilization.*` demonstrate new curve models, explicit series publication, graph aspect/background, annotations, Graph Notes and Graph Metadata through `gxtxt_api_call`. Completed files use `publish_auto` inside the script output directory. See [Script Bridge API](../api/OCTAVE_SCRIPT_BRIDGE_API_v1.md) and coverage JSON. Portable Resource import/export remains a host/GUI operation. Octave namespaced keys use dynamic field access without JSON name rewriting.

## Runner history and named views (dev097)

Use **Run → Open Script Runner** in either Script Workspace to review a saved
script's parameters and Dataset bindings. Opening it creates no Job. Dirty buffers
let you save first, use the explicitly identified last saved revision, or cancel.
The Runner's own Run button submits the execution. **Script Jobs** then manages
that exact Job ID and retained log.

In Script Jobs, select one or several finished rows and choose **History → Hide
selected / Remove from visible list**. Repeated executions of the same script
remain independent. **Include hidden** or the **Hidden** filter reveals hidden
rows; **Restore selected** reverses hiding. **Hide finished in current scope**
shows its count, state filter and Session scope before confirmation. Cancellation
is a separate Jobs command for active executions. Hiding preserves the script,
immutable snapshot, log, output files and all published scientific data.

**View** changes state filters, Session scope, columns and pages. Click headings
to sort; the status line gives visible, matching, hidden and stored counts. The
list displays up to 500 Jobs per page, with Previous/Next under View. Details and
complete logs remain available for hidden jobs.

**Workspace** saves named user-local layouts and filters, including column widths,
pane proportions, geometry and safe selection. New/Open/Save/Save As/Rename and
Manager reuse Configuration persistence; the active name appears in the window
title. These layouts work without an open Session and do not contain Job records
or scientific data. Hidden Job IDs apply across all named Runner layouts. Closing
or switching a layout never runs or cancels a Job and never applies resource policy.
Change concurrency and limits separately under **Settings → Concurrency and resource
policy**, then explicitly save that policy.
