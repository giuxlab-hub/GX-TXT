# Script Execution API v1

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
These registry mutation and runner lifecycle calls are host-owned. The additive
dev097 Script Bridge operations on this API expose only callable declarations
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

Normal Analysis modules `analysis.octave_script` and
`analysis.python_script` select only matching-language Session records and
invoke this shared execution path. Script Library Run and Session Explorer
Run invoke the same path. The Octave module retains its explicit standalone
`external_file` `.m` compatibility mode; registered Session scripts are the
normal reproducible workflow for both languages.

## Local asynchronous GUI execution (dev093)

Run and registered Analysis now use the durable [CORE Script Job API](SCRIPT_JOB_API_v1.md).
The synchronous host v1 runner remains compatible for existing headless consumers.
Optional current-namespace input aliases and output bindings are part of the shared
Script Bridge context; the supervisor owns queue/lifetime, Publication owns data.

## Declared callable entrypoints (dev097)

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
