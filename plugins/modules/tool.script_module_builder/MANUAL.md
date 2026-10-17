# Script Module Builder

## Viewer interface profile (1.3.0)

The standard Viewer Interface Builder uses this tool's `viewer-build PROJECT
SOURCE_DIRECTORY OUTPUT_DIRECTORY` CLI. PROJECT is an inert CORE Viewer design,
validated by the actual framework owner. SOURCE_DIRECTORY holds generated assets
plus independent `handlers.tcl`; OUTPUT_DIRECTORY receives a new ordinary
installable Viewer module ZIP and checksum. The tool emits a public API source
map, exact handler contracts and a generated-asset change report. Handwritten
handlers are preserved byte-for-byte. Existing ZIP/checksum destinations are
refused. The package uses public CORE constructors; scientific callbacks require
explicit action invocation. See [the public design contract](../../../docs/api/VIEWER_GUI_DESIGN_v1.md).

The existing Python/Octave A/B/W project formats and exact research-source
packaging retain their behavior.

Create or open a Builder project in the Modules-page tool. Choose an authoritative `.m` or `.py` script, set module identity and declare normal Analysis Sources, variable bindings, configuration fields, required APIs and outputs. **Validate**, then **Build ZIP**. Install the ZIP with normal Plugin Install.

Python and Octave scripts may declare their Analysis Sources with the same single-line `GX-TXT-ANALYSIS-SOURCES-V1` JSON comment described in `core/SCRIPT_ANALYSIS_SOURCES_API_v1.md`. **New from script…** and **New from registered…** discover that comment without executing the research code. The visible source table shows the IDs, labels, required flags, accepted Dataset contracts and purposes. You can review the rows before saving. If project source settings differ from the script, choose **Use script declaration** or **Keep manual source settings** explicitly; a manual decision is tied to the exact declaration fingerprint and must be reviewed if the script declaration changes. The generated module uses the ordinary Analysis Source Map and normal Dataset selectors.

The main script and every bundle member are copied byte for byte. The generated module records their SHA-256 values, supplies a normal descriptor-generated Analysis box and uses the shared script execution and Script Bridge services.

See [the full researcher guide](../../../docs/help/script_module_builder.md) for the project schema, language-specific context examples, public API exposure, profiles and rebuild procedure.

## Workbench extension profile

Open/import the same Python or Octave research script and choose **Workbench extension…**. Set the stable action ID, category, compatible Workbench IDs, selection kinds and mutation declaration; the project becomes profile `W`. Add normal shared scalar fields for action parameters/persistent configuration and declare required APIs. Workbench actions receive logical context instead of Analysis source/binding rows. Existing Analysis profiles A/B retain their original behavior.

The script reads `WORKBENCH_EXTENSION_API_v1.script_context` and returns a bounded successful operation proposal through `return_result`. The generated normal module ZIP includes unchanged source bytes, bundle checksums, generated public API registration, extension descriptors, documentation and portable project. Install with Plugins, enable through Modules and invoke through the Workbench Extensions chooser. Mutating hosts validate/apply one transaction with one Undo/Redo; disabled, hash-invalid, stale or failed proposals reject/rollback. See the public Workbench Extension API for supported host operation contracts.

## Standard authoring and Builder 1.2.0

New or substantially updated GX-TXT modules MUST declare an Experiment Duplication Policy using the public CORE contract when they introduce module-owned Session-persistent state. Modules with no additional privately owned persistent state SHOULD use the minimal explicit empty policy supported by the API.

This MUST is an authoring requirement, not an installation or execution gate. Existing and third-party modules without a policy remain installable and runnable. Their custom configuration may be completely reset in a duplicate; safe omission and fresh configuration are intentional outcomes.

`duplication_policy` is an optional object in an existing `schema_version=1` Builder project. Its keys are the actual flat public INI descriptor keys; it is not another policy language. Absent policy becomes `{"experiment_duplication.api_version": 1}`. CLI Validate/Build and the GUI **Duplication policy…** advanced editor use the installed CORE INI parser and public validator, without executing research code. The editor supports Validate, Apply and Cancel; document/file declarations are advanced JSON authoring, not an ownership wizard.

A reviewed scalar and verified external setup file:

```json
"duplication_policy": {
  "experiment_duplication.api_version": 1,
  "experiment_duplication.config_copy": "gain",
  "experiment_duplication.config_external": "calibration_file"
}
```

Declare `gain` as an independent number and `calibration_file` as a file/path field in the project's ordinary `fields`. External references must resolve to independent regular readable files outside the source Session. A declaration does not make a scientific file independent.

Exact optional document ownership can be added to the same object:

```json
"experiment_duplication.documents": "setup",
"duplication_document.setup.provider": "setup_editor",
"duplication_document.setup.format": "example.preparation",
"duplication_document.setup.format_version": "1",
"duplication_document.setup.action": "COPY_PREPARATION",
"duplication_document.setup.payload_kind": "structured",
"experiment_duplication.preparation_files": "preparation/example.policy/setup.txt"
```

The module ID must be `example.policy` for that preparation file root. Register documents/resources through their existing public APIs; reference actual resource receipts in structured payloads. CORE records generation-bound classification automatically, and rejects source scientific dependencies regardless of policy. The synthetic acceptance fixture verifies this exact schema and the Builder validates a working full-policy package. Scripts receive no host cloning or classification mutation authority.

Runnable examples `examples/experiment_duplication_policy/policy_python.json` and `policy_octave.json` wrap `policy_author.py` and `.m`. Build with `python3 tools/gxtxt_module_builder.py build examples/experiment_duplication_policy/policy_python.json /tmp/new-policy-packages`; install the resulting ZIP normally, enable, choose a fresh primary Dataset and Run. They discover capabilities, inspect supported/absent policy, validate safe and unsafe flat descriptors and read the preparation receipt through actual `gxtxt_api_call`. Both also read canonical Dataset metadata and produce an ordinary output report. Use a new output directory for each immutable package build. `minimal_python.json`/`minimal_octave.json` demonstrate copying no settings; safe projects copy only reviewed gain. Neither source injects duplication logic.

Builder requires the policy v1 capability and Python's standard tkinter/Tcl runtime (headless validation creates no Tk window). Execution validation discovers the public capability rather than pinning an exact framework release.
