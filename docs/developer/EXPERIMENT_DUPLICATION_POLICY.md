# Module author guide: optional Experiment duplication

Use the static descriptor in [the API manual](../api/EXPERIMENT_DUPLICATION_POLICY_API_v1.md)
when preserving independent setup matters. Existing modules require no changes.
Check `experimentDuplicationPolicyInfo` or Script Bridge capability discovery rather
than pinning a GX-TXT release. Validate the descriptor headlessly before shipping.

Declare only fields whose meaning is independent of source scientific state, exact
provider/document schemas, and exact preparatory file owners. Defaults and omitted
state already supply RESET_TO_DEFAULT; results use EXCLUDE. External setup files use
PRESERVE_VALID_EXTERNAL_REFERENCE. No RECONCILE_OR_REBIND/callback engine is needed:
CORE retains registry identifiers/generations in an independent Session lifetime,
checks resources and dependencies, and rejects unsafe absolute Session references.

Create documents through `interactiveDocumentCreate` and resources through the public
Managed Resource API. The existing document registry receives classification at
creation automatically when an optional policy or documented native adapter exists.
Reference actual resource receipts in structured payloads; unreferenced blobs are not
cloned. Persisted policy receipts are generation/schema bound and remain useful after
provider uninstall. Older unknown objects are omitted, with no source modification.

Inert author code uses `{code <text> metadata <dictionary>}` with `author_code`; only
the code field is exempt from rewriting/dependency interpretation. Metadata retains
normal global exclusions. Never classify serialized data/results as author code.

Duplicated selectable modules start disabled with no Run selection. Nonselectable CORE services retain normal availability. Users rebind fresh inputs
using the existing UI/API and then run normally. A missing/invalid optional declaration
does not change installation, normal execution or existing Sessions. Document
configuration loss in your guide; users can inspect Session > Duplication report.

The release audit in `docs/reports/MODULE_DUPLICATION_AUDIT_dev079.md` covers the actual
101 packaged modules and representative persisted provider contracts. Native legacy
schema adapters preserve historical Workspace classification and code/viewer ownership.
No numerical module implementation, installed package or viewer engine was changed.
The acceptance fixture demonstrates two independent added modules without new CORE
IDs, plus invalid declarations, uninstall receipts and actual fresh analysis execution.

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
