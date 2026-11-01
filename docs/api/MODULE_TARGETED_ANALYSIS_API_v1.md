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

## Restricted C++ native form (additive DEV111-P035)

The reviewed native client is separately admitted as
`MODULE_TARGETED_ANALYSIS_API_v1@1 / analysis_command`; host catalog discovery
does not grant it. `Host::analysis_command(form, operation)` accepts only
`discover`, `submit`, `status`, `cancel`, `candidates`, `add_candidate`, with no
arbitrary request, paths, source body, scheduler or scientific implementation.
`Host::analysis_result()` receives the next-event typed status/error/result.

Declare a Viewer section with `analysis_module` (registered target module),
`analysis_dataset` (Dataset selector), `analysis_bindings` (declared binding role
to Variable-choice component), `analysis_config` (descriptor parameter to value
control), `analysis_status` (log), `analysis_candidates` (table),
`analysis_candidate` (stable rank choice), `analysis_comparison_form` (existing
Comparison section) and `analysis_commands` (handler to finite operation map).
Optional `analysis_page` selects a zero-based page of25 result rows. Submission
and cancellation require exact explicit mutating handlers; consultation and
adding a transient comparison reference use presentation handlers. Current
module, package, source, window, Session and event authority are rechecked.
No operation enables a module or commits configuration overrides.

Canonical ranked-reference projection is opt-in by the Analysis producer. Its
descriptor `[analysis_result.ranked_references]` declares
`role=ranked_references_v1`, `columns` (<=32), `rank_column`, `library_id_column`,
`library_version_column`, `library_content_hash_column`, `entry_id_column`.
Publication must identify `analysis_result_role=ranked_references_v1` and actual
`source_dataset_id`, `source_sha256`, `source_revision_sha256`,
`source_schema_sha256` provenance. CORE finds actual producer-owned Datasets,
never Dataset suffixes/display labels; it verifies payload/revision/schema and
current source. Tables contain at most100 ranked rows and expose25 per page.
Table selection maps host-owned row IDs to actual stable ranks, never parses
visible text. Result receipts contain source/result identity pins and bounded
string-valued records; no filesystem paths or implicit capability.

`add_candidate` adds only the selected current Library reference to the declared
Comparison form, validating its recorded Library version/content hash against
current provider provenance and the ordinary scientific source pin. The original
measured query remains an explicit Dataset source selection. Processed or
normalized Analysis output is a distinct scientific source and is never silently
substituted for the query or a raw reference. Comparison meaning/unit rules,
explicit display normalization and the last valid frame remain unchanged.
Similarity scores are not probabilities or independent identification evidence.

### Ordinary Builder authoring

Select a section and choose **Design → Targeted Analysis profile…** after
creating the source/Variable/configuration controls, result table/rank choice,
status log and Comparison form. The dialog maps their stable IDs. Its existing
public model operation `analysis_profile SECTION PROPERTY_MAP` creates the six
finite handlers, primary Analysis menu and design API requirement in one
validated undoable edit. SDK requests in the C++ project remain a separate
explicit admission step. No runtime authority follows from the design.

The generic `comparison_browser_only SECTION GROUP` model operation and ordinary
**Design → Use shared Library Browser…** dialog atomically remove the two legacy
Library/Entry references and `add_library` mapping. The author then removes
unused controls/menu entries normally. This permits genuine native authoring
without an invalid intermediate dependent profile or private model edits.

Ranked-result receipts additionally expose `source_variable_ids` as an actual
ordered array of stable canonical Variable IDs from the published result's
`source_variable_ids` metadata (distinct, enabled, at most32). These identities
are never inferred from names or replaced with the form's current editable
bindings. Source Dataset payload/revision/schema pins and result pins are checked
before/after read; full processing provenance remains inspectable on the actual
result Dataset through the existing public metadata services.

At composition, CORE initializes the declared role/rank controls from actual
canonical state: no source yields empty Variable choices, and no read result
means empty candidate choices/table. Palette demo labels are not scientific
identities. Configuration values remain authored; normal Workspace/History
restoration follows initialization. Discover refreshes the same role choices,
including clearing an absent source, without starting Analysis or enabling a
module. Users explicitly choose actual Variables and submit a scientific run.
