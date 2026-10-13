# Script Module Builder

Script Module Builder packages a researcher authored GNU Octave `.m` or Python `.py` script as an ordinary installable GX-TXT Analysis module. It copies the scientific source bytes exactly. It generates `module.ini`, `plugin-package.ini`, documentation, SHA-256 inventories and a flat-root Plugin Install ZIP around that source. A generated module needs no Tcl/Tk code.

Open **Modules → Tools → Script Module Builder…**. Choose **New from script…** for a file or **New from registered…** for a Script Library or Session registry `script.ini`. Enter module details, add Analysis Sources, variable selectors, configuration fields and API requirements, then set outputs and notes. **Validate** checks the project; **Build ZIP** writes a new package. The project is JSON so it can be reopened and versioned. The GUI buttons create the common declarations; the JSON view also supports advanced settings.

The command-line form uses the same implementation:

```text
python3 tools/gxtxt_module_builder.py validate research_module.json
python3 tools/gxtxt_module_builder.py build research_module.json /new/package/output
```

The builder refuses to replace an existing versioned ZIP. Reopen a project, increment its version when its source or contract changes, then build again. The ZIP contains a portable `builder-project.json` with relative bundle paths for reproducible rebuilding. If source bytes change, the new build records the new SHA-256. No source transformation, translation or formula editing occurs.

## Minimal project

```json
{
  "schema_version": 1,
  "id": "research.example",
  "name": "Example analysis",
  "description": "Scale one canonical Dataset variable.",
  "version": "1.0.0",
  "group": "Research",
  "license": "GPL-3.0-or-later",
  "profile": "A",
  "language": "Python",
  "source": "example.py",
  "sources": [{"id": "primary", "required": true, "contracts": "timeseries.table"}],
  "bindings": [{"id": "signal", "label": "Signal variable", "required": true}],
  "fields": [{"id": "scale", "type": "number", "label": "Scale", "default": "2", "required": true}],
  "required_apis": ["CANONICAL_DATASET_API_v2@2", "DATASET_PUBLICATION_API_v2@2"],
  "outputs": {"datasets": ["research.example.derived"], "files": []}
}
```

`sources` uses the normal Analysis Source Map. Declare `primary` and optionally other source IDs, Dataset contracts, and explicit Dataset defaults. `bindings` uses the existing normal variable selector; GX-TXT displays `primary.variable_name` and records its selected value. `fields` uses Standard Module configuration types: `dataset`, `selection`, `temporal_set`, `number`, `integer`, `string`, `text`, `boolean`, `choice`, `file`, `path`, `unit`, `model` and `table`. For a choice, add `"values": "first;second"`. These declarations become ordinary descriptor fields and the normal Analysis configuration box. The builder never generates ordinary-field GUI code.

A repeatable table uses native Standard Module columns. For example, add `{"id":"samples","type":"table","label":"Samples","min_rows":1,"columns":[{"id":"variable","type":"variable","source":"primary","required":true},{"id":"weight","type":"number","default":"1"}]}` to `fields`. Its rows reach `ctx["parameters"]["samples"]` in Python as a list of dictionaries with `row_id`, `variable` and `weight` string values. In Octave, `ctx.parameters.samples` contains the same structured rows as decoded by the shared Bridge. Convert numeric cell strings in scientific code as needed. The normal table editor and Session persistence own the rows.

## Values in researcher scripts

Both languages use the same public Script Bridge context. Dataset sources are in `inputs`; configuration and resolved variable bindings are in `parameters`. A binding such as `primary.measured_V` names a source and canonical variable name. Resolve its stable variable ID through `DATASET_VARIABLE_SCHEMA_API_v3` before calling Canonical Dataset read operations.

Python:

```python
from gxtxt import gxtxt_context, gxtxt_api_call
ctx = gxtxt_context()
dataset_id = ctx["inputs"]["primary"]["dataset_id"]
signal_name = ctx["parameters"]["signal"].split(".", 1)[-1]
scale = float(ctx["parameters"]["scale"])
variables = gxtxt_api_call("DATASET_VARIABLE_SCHEMA_API_v3", "list", [dataset_id])
signal_id = next(v["variable_id"] for v in variables if v["canonical"] == signal_name)
```

GNU Octave:

```octave
ctx = gxtxt_context();
dataset_id = ctx.inputs.primary.dataset_id;
parts = strsplit(ctx.parameters.signal, '.');
signal_name = parts{end};
scale = ctx.parameters.scale;
variables = gxtxt_api_call('DATASET_VARIABLE_SCHEMA_API_v3', 'list', {dataset_id});
for k = 1:numel(variables)
  if (strcmp(variables{k}.canonical, signal_name))
    signal_id = variables{k}.variable_id;
  endif
endfor
```

Declare every GX-TXT public API used by the script in `required_apis`. The syntax is `API_ID@major:provider+capability|capability`; the provider and capability clauses are optional. The shared Script Bridge checks requirements before scientific code runs in either language. Script code uses `gxtxt_api_call` for public Dataset, Selection, Publication, Plot Dataset, Viewer, Progress, Session Persistence and other script-safe services. Python and Octave scripts can read `PARALLEL_EXECUTION_API_v1/resources` to respect GX-TXT worker limits. Output files belong under `ctx["output_dir"]` or `ctx.output_dir`; publish them with `DATASET_FILE_PUBLICATION_API_v1`.

## Bundles and profiles

Add `bundle` entries such as `{"source": "helper.py", "target": "helper.py"}` or a lookup table. The builder preserves every file byte for byte with a bundle SHA-256 inventory. Python imports helpers from the module-owned bundle directory for the duration of the run. Octave receives that directory on its temporary path. A static resource is available at `ctx["bundle_dir"]` in Python or `ctx.bundle_dir` in Octave. Neither language adds the bundle to a global path. The installed module has no dependency on the researcher's original working directory.

Profile **A** packages a research workflow while allowing normal Octave or Python scientific libraries. Profile **B** is an explicit production target: provide a scientific method, declared inputs and outputs, stronger tests and use public numerical and plotting services where appropriate. The builder never rewrites Profile A mathematics to make it resemble Profile B.

## Optional public API

A project may add a `public_api` declaration. The builder then emits normal module public API registration, a structured Tcl entrypoint and, for opted-in operations, a provider-owned Script Bridge binding. Each operation runs the same authoritative script with declared arguments mapped to an Analysis Source, variable binding or configuration field. It returns a structured execution receipt. Public API exposure is optional; the simple project above has none.

```json
"public_api": {
  "id": "RESEARCH_EXAMPLE_API_v1",
  "version": 1,
  "name": "Example analysis API",
  "capabilities": ["structured_analysis_run"],
  "operations": [{
    "id": "run",
    "summary": "Run the example analysis.",
    "result_contract": "execution receipt struct",
    "read_only": false,
    "script_bridge": true,
    "arguments": [
      {"name": "dataset_id", "kind": "Dataset ID", "required": true, "target": "source.primary"},
      {"name": "scale", "kind": "number", "required": true, "target": "config.scale"}
    ]
  }]
}
```

The operation is mutating because it executes an Analysis module. The caller supplies only declared structured arguments. No raw Tcl commands, GUI callbacks or private paths are public API operations.

## Install, run and provenance

Install the generated ZIP through **Configuration → Modules → Plugin Manager → Install…**. Enable the installed module in **Modules**, configure its normal Analysis box and select **Run / recalculate now**. The normal Run page executes the script through shared Octave/Python adapters and the provider-owned Script Bridge. Save and reopen the Session to keep the module's configuration and Analysis Source bindings. Each run stores an exact source snapshot, status, module version, language, required APIs and source SHA-256 under Session analysis provenance. A failed script or API preflight appears as a failed run with diagnostics.

The runnable validation projects and source examples are in `validation/gxtxt_module_builder/`. They show Dataset/Plot publication, NumPy worker budgeting, Selection use, STEP file publication and optional public API exposure.

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

Builder requires the policy v1 capability and Python's standard tkinter/Tcl runtime (headless validation creates no Tk window). The package declares dev079 as the earliest known capable release; execution validation discovers the capability rather than pinning an exact framework release.
