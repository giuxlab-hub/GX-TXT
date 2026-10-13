# Optional Experiment Duplication Policy API v1

GPL-3.0-or-later. Introduced in dev079. This optional declarative extension does
not change Module installation, discovery, execution, numerical algorithms or
existing public signatures. Capability discovery, rather than a GX-TXT version
pin, identifies support. CORE alone plans, validates, copies, commits and rolls
back Duplicate Experiment. Providers execute no cloning callbacks.

Public Tcl operations:

- `experimentDuplicationPolicyInfo`: API ID/version, optional flag, actions,
  receipt version and absence of executable callbacks.
- `experimentDuplicationPolicyModule moduleId`: `module_id`, `status`
  (`supported`, `unsupported`, `invalid`), `valid`, `errors`, and validated
  `configs`, `documents`, `files`. Missing modules return unsupported.
- `experimentDuplicationPolicyValidate descriptor`: validate a flat INI-key Tcl
  dictionary, returning `valid`, `errors`, `configs`, `documents`, `files`.
  Invalid optional declarations are reported without breaking module loading.

Python/Octave Script Bridge ID `EXPERIMENT_DUPLICATION_POLICY_API_v1` exposes
`info()`, `module(module_id)`, `validate(descriptor)` through existing discovery
and public operation dispatch. Nested dictionaries/lists in receipts follow the
existing CORE bridge serialized convention. Clone writes remain host administrative
operations. `SESSION_EXPERIMENT_API_v1/preparation` exposes the persistent report
summary without adding another persistence authority.

Add optional sections to a normal `module.ini`:

```ini
[experiment_duplication]
api_version=1
config_copy=gain;apparatus_label
config_external=calibration_file
documents=setup;result
preparation_files=preparation/example.module/setup.txt

[duplication_document.setup]
provider=setup_editor
format=example.preparation
format_version=1
action=COPY_PREPARATION
payload_kind=structured

[duplication_document.result]
provider=result_viewer
format=example.result
format_version=1
action=EXCLUDE
payload_kind=structured
```

Config names must be existing `[config] fields`; scientific selectors cannot
be declared copyable. `config_copy` preserves exact independent values after
dependency validation; no substring relocation or author-text rewriting occurs.
For `file`/`path` fields COPY requires an exact declared independent preparation
file. Relative references remain relative. Source-Session absolute references
reset, even if their files would otherwise be copied. `config_external` implements
PRESERVE_VALID_EXTERNAL_REFERENCE for readable regular absolute files outside the
source Session, with no scientific dependency; symlinks are rejected. Registry
scripts and inert author code remain independently owned under their existing APIs.

Unlisted configuration uses RESET_TO_DEFAULT, except Dataset/Workspace/selection/
graph selectors and file/path inputs start empty. Selectable modules start disabled, with
empty Run selection and bindings, including participating modules. Nonselectable
CORE services retain their normal availability; no analysis is automatically run. A user configures
fresh inputs and explicitly enables/runs analysis. Descriptor defaults remain the
normal installation/execution contract. Lost uncertain settings are an intentional,
visible conservative fallback, never a module defect or an installation condition.

Document declarations match exact owner module, provider, format and format version;
wildcards and duplicate identities are invalid. COPY preserves the existing active
document registry identity, generation, revision, hash and provenance, with a new
independent Session lifetime. Structured payloads and preparation recovery records
are checked recursively for excluded sources and resources. Unknown, opaque, mixed,
missing-resource or stale-owner optional objects are omitted with reasons, and
cross-document omissions propagate until no retained owner has a missing dependency.
EXCLUDE and RESET_TO_DEFAULT omit the old document; CORE does not invent replacements.

`payload_kind=author_code` requires a dictionary containing exactly `code` (inert
author text) and `metadata` (a dependency-validated dictionary). It cannot relabel
an arbitrary scientific dictionary as code. The historical native Octave code
document uses its established codec adapter. Code/scripts are never rewritten or
executed by duplication; later explicit execution follows the author's contract.

At object creation CORE records a small versioned `duplication_policy` receipt in
the existing Interactive Document registry, bound to module/provider/schema/version/
generation. Registry updates preserve it. Valid receipts support sensible provider
updates or uninstall without fabricated provenance. Stale/unsupported receipts are
excluded. Old objects lacking a receipt need a currently installed exact declaration
or a documented native compatibility adapter. Unknown objects default to omission.

Only referenced, validated Managed Resource blobs are copied; orphan blobs,
pending writers and retired resources are excluded. SHA-256 verifies integrity,
never ownership. Different owners can legitimately have identical bytes.
Declared ordinary preparation files must be exact regular files under
`preparation/<module-id>/`; no globs, parent traversal, symlinks or arbitrary Session
paths are authorized. Source scientific ownership overrides a file declaration.

Global exclusions override every declaration: Datasets and scientific registrations/
inputs, Workspaces and owned documents/resources/History, existing graphs/Series/
Variants/annotations/outputs and observations. All analysis/raw/channel/cache/report/
log payloads and unknown metadata/loose files are omitted conservatively. CORE notes,
scripts, instruments, setup parameters and validated independent Viewer artifact
resources survive through their existing authorities. Loose preparation requiring
retention should use a declared owner, Interactive Document/Managed Resource, or
the existing author notes/script authorities. No suffix/digest ownership guessing.

Completion diagnostics are stored in the Manifest preparation receipt (`policy_api`,
`policy_version`, `summary`: action/module/provider/object/reason records) and
`metadata/experiment_preparation.txt`. Session > Duplication report opens the readable
report, while the status line explains reset/disabled modules without a modal wizard.
Source drafts/files remain unchanged. True integrity/transaction failures still abort
and roll back the owned reservation and exact Project index.

## Dev080 compatible validation correction

V1 and all public signatures are retained. Config-copy eligibility now checks existing Standard Module types (`dataset`, `variable`, `selection`, `temporal_set`, `table`, `model`, `analysis_definition`), declared binding roles and source/source_role metadata as well as selector names. `config_external` requires `file` or `path`. This corrects the reproduced dev079 `input type=dataset` gap. Invalid/unsupported declarations still trigger safe reset/omission, never installation rejection. Scientific typed descriptor defaults are cleared in duplicates so a generic name cannot revive an old binding. Ordinary scalar defaults remain unchanged.
