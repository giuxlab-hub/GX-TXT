# Targeted Standard Analysis invocation

These additive `MODULE_API_v1` operations admit one enabled Standard Octave
Analysis module into the existing application Analysis queue. They do not enable
modules, change Run checkboxes, construct discarded modules' runtimes or create a
second Job supervisor. The usual selected multi-module Run remains available.

`::GX::moduleAnalysisCapabilities module_id` is headless-safe discovery. It returns
availability, an explicit unavailable reason, runner, supported request fields and
the host-only execution scope. Service providers such as `math.signal` are not
Standard Analysis targets.

`::GX::moduleAnalysisSubmit caller_viewer_id module_id request` requires an enabled,
registered Viewer, an enabled runnable `standard_octave` Analysis target and its
available dependencies. A request is a dictionary with:

| Field | Meaning |
|---|---|
| `session_token` | Required current `interactiveDocumentSessionToken`; stale tokens fail. |
| `sources` | Optional source-role to canonical Dataset-ID dictionary, validated by Analysis Source Map. |
| `config` | Optional descriptor-declared scalar parameters normalized by `UI_FIELD_API_v1`. |
| `tables` | Optional table-key to typed `REPEATABLE_CONFIG_API_v1` snapshot dictionary. Variable choices use actual Dataset schema identities. |
| `bindings` | Optional declared input-role to qualified Variable binding dictionary. |
| `document_id`, `document_revision`, `document_generation` | Optional caller-owned Interactive Document with its required exact generation and revision. |

Omitted selections/settings use the module's effective current configuration.
Overrides affect only this invocation's existing runtime snapshot. Configuration,
Analysis Source Map, repeatable tables and binding state are restored before the
queue starts. The operation never silently commits caller overrides to Session
configuration. Complex resource/model parameter types require their existing
typed authority rather than being accepted as unchecked scalar strings.

The returned receipt contains `run_id`, `module_id`, `caller_id`, Session token,
state, source digests and the module output directory. The existing queue owns
subprocess arguments, output-contract checks, publication, graph variants and
progress. A busy queue raises `GXTXT ANALYSIS BUSY`; it never silently admits a
second invocation. Expected outputs use the module's normal output locations and
replacement policies.

`::GX::moduleAnalysisStatus caller_viewer_id module_id run_id` reads the invocation
receipt in the current Session. States are `RUNNING`, `COMPLETED`, `FAILED`,
`CANCELLED` or `INTERRUPTED`. An unfinished receipt after reopening is reported as
interrupted, never completed. The receipt belongs to its admitting Viewer.

`::GX::moduleAnalysisCancel caller_viewer_id module_id run_id` cancels only the
matching live invocation through the existing Analysis/Parallel cancellation
owner. It does not cancel an unrelated process. Session/document/source guards
prevent late completion from being adopted into a different Session. Scientific
workers retain the explicitly captured original Session paths.

Submission/status/cancel are host-only because they address the application
process's existing GUI queue. Detached Script Bridge processes cannot submit to a
different process by mutating their private copy of that queue. Scripts instead
use the public durable `SCRIPT_JOB_API_v1` and scientific provider Bridge. Safe
capability discovery is also exposed through Script Bridge.

```tcl
set request [dict create session_token [::GX::interactiveDocumentSessionToken] \
    sources [dict create primary measured_table] \
    config [dict create render_graphs 0]]
set receipt [::GX::moduleAnalysisSubmit $viewerId analysis.statistics.descriptive $request]
set state [::GX::moduleAnalysisStatus $viewerId [dict get $receipt module_id] [dict get $receipt run_id]]
```

Supply a valid variables-table snapshot when the selected module requires one.
The generic operations do not guess scientific input Variables or alter units.
