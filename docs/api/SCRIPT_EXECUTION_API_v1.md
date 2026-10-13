# Script Execution API v1

SPDX-License-Identifier: GPL-3.0-or-later

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
These registry and runner lifecycle calls are host-owned and are not registered
as `SCRIPT_EXECUTION_API_v1` Script Bridge operations; user scripts call their
required public provider APIs through the Bridge after preflight.
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
