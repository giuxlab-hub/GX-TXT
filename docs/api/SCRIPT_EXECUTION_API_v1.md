# Script Execution API v1

Script Projects use this SAME Registry and Job owner. See
[Registered Script Projects](SCRIPT_PROJECTS_v1.md) for whole-tree Save All,
manifest/source identities, portable artifacts, Session copies and file-aware
native debugging. Existing one-file paths remain compatible. Source and metadata
schemas share [literal parameter declarations](SCRIPT_PARAMETER_DECLARATIONS_v1.md).
Single-file updates atomically exchange a complete source/schema record with
Linux `renameat2` under the existing Registry CAS lock; missing atomic capability
refuses publication and retains the previous source. User/Library editors also
pin `metadata.expected_revision`, protecting newer defaults even when source
bytes did not change.

SPDX-License-Identifier: GPL-3.0-or-later

`job_submit(reference, parameters)` submits a registered Script through the
existing durable CORE Job owner and returns `job_id` and actual `state`.
`job_wait(job_id, timeout_seconds)` waits for an owned same-Session child from a
supervised client and returns `job_id`, terminal `state` and
`wait_cancel_requested`. A timeout requests cancellation and drains the child.
Timeouts are integer seconds from1 to86400. Both operations use the existing
`gxtxt_api_call` façade in Python and Octave. No source path or command is accepted.
See the [Job dependency contract](SCRIPT_JOB_API_v1.md#owned-child-waits) for
admission, resource reservations, nesting and cancellation ownership.

CORE owns one Script Registry for GNU Octave and Python. Each registered
record has a stable ID, display name, language, semantic version, revision,
SHA-256, description, required public APIs, typed parameter schema, scope,
source provenance and creation/update timestamps. Its qualified reference is
`user:<id>` or `session:<id>`; a filesystem path is never the registered
identity. Existing Octave records keep their `source.m` bytes and format;
Python records store `source.py` in the same registry structure.

The optional `default_arguments` field (default empty for existing records):
inert single-line UTF-8 text, at most4096 bytes, with no NUL. The existing Registry
Save/Update/Read/assignment serialization preserves it. Octave Workspace's
Default arguments field and Save copy use this metadata. Ordinary execution
freezes it as `config.arguments`; the public Script Bridge exposes the unchanged
text at `gxtxt_context().arguments_raw`. It is not a shell command or the trusted
runner's process `argv()`. The ordinary Runner review shows saved nonempty text.
Analysis runtime templates retain their existing explicit argument override.
Named typed parameters remain a separate schema/context property.

On save and revision, the registry discovers literal `gxtxt_api_require(...)`
declarations without running the source. `script.ini` stores `declared_apis`
and `explicit_apis` separately; `required_apis` is their union. The
additional-APIs editor controls `explicit_apis`. A source revision can remove
an obsolete declaration while preserving additional requirements. Copies
retain both sets, and old records without these fields treat their existing
`required_apis` as explicit metadata.

`scriptRegistrySave`, `scriptRegistryUpdate`, `scriptRegistryDescribe`,
`scriptRegistryList`, `scriptRegistryAssignToSession` and
`scriptExecutionRun` are the framework-owned Tcl operations. The Script
Library and Session Script Explorer use these operations for both languages.
These registry mutation and runner lifecycle calls are host-owned. The read-only
Script Bridge declaration operations on this API expose callable declarations
and the current supervised invocation; scripts call scientific provider APIs
through the Bridge after preflight.
Assignment copies exact user source bytes into a separate Session record.
Later user edits cannot change that record. A Session edit keeps the ID,
increments revision and replaces the current SHA; older execution snapshots
remain under `analysis/scripts/<run_id>/`. Reads and execution reject a
source whose SHA differs from the registry record.

`scriptExecutionRun` selects the language adapter from the verified registry
record. Octave uses the existing Octave runner; Python uses the configured
`runtime.python` and the public [Python Script Client](PYTHON_SCRIPT_CLIENT_v1.md).
Both languages use the same provider-owned Script Bridge API descriptors and
operations. Required API declarations are checked before researcher code.
The framework invokes Script Bridge catalog preflight before launching the
Octave or Python process. Analysis selection displays and imports the stored
`required_apis` automatically.
Execution writes the exact source snapshot, report, log and `execution.ini`
in a framework-owned Session run directory. Provenance includes the qualified
reference, language, stable ID, version, revision, SHA-256, required APIs,
source provenance and actual runtime information where applicable.

Job inspection verifies both existing whole-project snapshot layouts: Registry
Project runs retain `project/`, while packaged provided-API runs retain
`project-revisions/<project-SHA>/`. Only the exact run-owned location recorded
by execution is admitted. The project, language, entrypoint and source hashes
must agree with the execution pins and the complete frozen manifest. Inspection
does not consult the current Registry or use an arbitrary recorded source path.
After portable Session import, frozen runtime sidecars can still record the old
Session path. Inspection validates that logical origin's Session/run identity
and exact snapshot layout, then verifies only the matching snapshot under the
current opened run. It never resolves or reads the old path, and does not rewrite
execution provenance or acquire authority over another Session.

Normal Analysis modules `analysis.octave_script` and
`analysis.python_script` select only matching-language Session records and
invoke this shared execution path. Script Library Run and Session Explorer
Run invoke the same path. The Octave module retains its explicit standalone
`external_file` `.m` compatibility mode; registered Session scripts are the
normal reproducible workflow for both languages.

## Typed parameter editing

Script Library and both Script Workspaces edit one Registry schema, separately
from Default arguments. Each row is `name | type | required | default | description`;
for example, `dataset_prefix | string | 1 | | Base name for four temperature Datasets`.
Existing validation facets such as choice values and numeric limits remain attached
to unchanged parameter names. Source variables are not parameter declarations.

The text editor uses `\\` for a literal backslash, `\|` for a literal pipe,
`\n`, `\r` and `\t` for control characters, and `\s` for a significant space.
Formatting escapes padded defaults so source-only saves preserve their exact value.
Descriptions retain the Registry's single-line validation. Duplicate names and
unsupported types are rejected through the existing Registry schema validation.

## Local asynchronous GUI execution

Run and registered Analysis use the durable [CORE Script Job API](SCRIPT_JOB_API_v1.md).
The synchronous host v1 runner remains compatible for existing headless consumers.
Optional current-namespace input aliases and output bindings are part of the shared
Script Bridge context; the supervisor owns queue/lifetime, Publication owns data.

## Declared callable entrypoints

The existing Script Registry accepts an optional `callables` dictionary in
`scriptRegistrySave`/`scriptRegistryUpdate` metadata. Each stable callable ID
contains exactly `entrypoint`, `contract`, and `declaration`. Entrypoints are
single public function identifiers, at most 64 characters. The versioned
contract identifies the scientific declaration schema; `declaration` is an inert
`SCIENTIFIC_RECIPE_API_v1` encoded envelope with that exact format. The scientific
consumer owns validation of parameter identities, units and input/output shapes.
CORE validates the bounded envelope and never evaluates it as code.

Declarations persist in `[callable.<id>]` sections of the same `script.ini`.
There is no second executable registry. Old records have no callables. Revision
updates and user-to-Session assignment retain the declarations alongside the
exact source. Host `scriptRegistryCallableList ?session?` and
`scriptRegistryCallableDescribe reference callable_id ?session?` expose the
qualified reference, language/version/revision, exact source SHA and declaration
SHA. Resolving a callable requires an open Session.

Public read-only Script operations, available in both languages:

- `callable_list()` lists verified declarations.
- `callable_describe(reference, callable_id)` resolves one declaration.
- `current_callable()` validates the current supervised invocation against its
  exact source/revision/declaration and returns the declaration, consumer API,
  operation and run ID. An ordinary script has no invocation and rejects this
  operation explicitly. It does not acquire any execution capability.

The source defines the named Python function or an Octave script-local function.
The host submits it through the existing Job API, then the language runner
registers that function using `SCRIPT_CALLBACK_API_v1`. It calls the declared
public consumer with `(callback_handle, payload)` and releases the handle on
success or failure. The consumer performs scientific work through its existing
numerical authority. No source is evaluated in Tcl and no runtime is created
per callback evaluation. Callback handles are never persisted for later use.


## Canonical invocation presets

The shared Script Runner reviews typed per-Job values independently of the
Registry declaration editor. Explicit Save/Load uses
[SCRIPT_PARAMETER_DATASET_API_v1](SCRIPT_PARAMETER_DATASET_API_v1.md), canonical
Publication and Schema v3. Values, exact Script schema/source/revision and stable
Dataset/Variable identities are retained. Loading never changes Registry
defaults or executes source. Script Workspace View → Parameters independently
hides/restores the declaration panel without losing values or changing debugger
state; View → Script properties controls the other metadata rows.


P033 host Registry snapshot operations extend this same owner. `scriptRegistryCopySnapshot reference targetId expected ?session?` requires all four reviewed fields: `expected_sha256`, `expected_revision`, `expected_record_sha256`, and `expected_owner_context`. It creates a new identity in the source scope. `scriptRegistryAssignToSession userId ?session? ?expected?` additionally accepts those expected fields while preserving existing calls; it creates the same ID under the explicitly selected Session. An occupied destination, including an empty directory, refuses. Both operations lock and recheck the source, prepare the complete Script or Project and local SourceNote snapshot privately, then publish once with the existing Linux Registry no-replace transaction. Failures before publication discard only the owned pending tree. No partially created Registry record is presented as a completed copy. Exact UTF-8 bytes, optional BOM, CRLF, Project relative paths and helper hashes are retained. The new record has revision 1 and source lineage; local note owner/file identities are newly allocated with inert origin metadata. Existing canonical Dataset associations are not silently reassigned to the new source owner.

`resourceLifecycleDeleteScript reference ?expected?` checks active dependencies again under the existing source-owner lock and compares the full reviewed identity before the finite Registry removal. The exact validated owned record is atomically removed from the Registry namespace before cleanup; no later record reusing the ID is deleted. Unknown members, source/record corruption, locks, stale expectations and changed roots refuse. Historical Jobs, execution snapshots, external files and canonical scientific Datasets are outside this operation. `scriptRegistryRemove reference ?session? ?expected?` remains the lower-level host owner with backward-compatible arguments; user-facing deletion uses Resource Lifecycle dependency admission. These are host-only operations and grant no Script Bridge/native administrative authority.

The existing Project and provided-API parsers accept an optional UTF-8 signature for syntax inspection only. Original bytes remain the size/SHA and execution snapshot authority; parsing does not normalize or rewrite source files.
