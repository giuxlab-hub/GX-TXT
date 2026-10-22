# Statistical Analysis Viewer service API v1

SPDX-License-Identifier: GPL-3.0-or-later

The installed `viewer.statistical_analysis` version1 API entrypoint
`api/viewer.tcl` loads the `::GX::StatisticalAnalysisViewer` public service in
`handlers.tcl` once. It delegates one targeted Standard Analysis invocation to
the existing application queue; it is not a numerical solver or second Job
supervisor. Statistical estimates/tests remain the selected module's contracts.

## Exact trusted-host signatures

| Entry in `::GX::StatisticalAnalysisViewer` | Arguments/defaults and result |
|---|---|
| `apiInfo` | none; dict with API ID/version, scope `headless_service optional_gui`, execution_owner MODULE_TARGETED_ANALYSIS_API_v1 |
| `providers` | none; list of installed analysis.statistics.* modules of kind analysis, each actual capability dict enriched with name, analysis_visible and Configuration fields |
| `submit module request` | required module ID and Tcl request dict; calls moduleAnalysisSubmit with caller viewer.statistical_analysis, returns its run receipt |
| `status module run` | required exact module/run IDs; caller-qualified targeted invocation receipt |
| `cancel module run` | same required IDs; existing cancellation/status receipt |
| `table variables` | required Tcl list of Variable IDs; returns `{api_id REPEATABLE_CONFIG_API_v1 rows ...}` with row1,row2,..., each values dict containing variable |
| `design` | none; installed gui/design.tcldict read through public design owner |
| `handlers` | none; action-ID dict with this provider's GUI action command |
| `open ?context?` | Tcl dict default `{}`; raises/composes `.gxtxt_statistical_analysis`, returns that Tk path |
| `workspaceOpen context` | required context; existing design Workspace-open result |
| `dispatch operation scene` | two required backend arguments; calls open with scene.open_context or `{}` |

`providers` is discovery, not admission: it can include unavailable providers;
analysis_visible records module UI state separately. `table` constructs an inert
selection snapshot; it does not validate existence, type, ownership or scientific
suitability of Variables. Those checks belong to targeted admission/module
schema. It does not return observations or a calculated statistic.

## Targeted request and result

The public request dict accepts the fields enforced by
[Targeted Standard Analysis](MODULE_TARGETED_ANALYSIS_API_v1.md):

| Key | Meaning |
|---|---|
| session_token | required current Interactive Document Session token |
| sources | optional source-role→canonical Dataset-ID dict |
| config | optional descriptor-declared scalar settings, normalized by UI Field |
| tables | optional table-key→typed Repeatable Config snapshot dict |
| bindings | optional declared input-role→qualified Variable bindings |
| document_id/document_revision/document_generation | optional caller-owned Document and exact revision/generation guards |

Omitted settings use the module's effective configuration. Overrides affect the
admitted invocation; the existing owner restores the caller's configuration and
selections before starting the queue. No Run checkbox is toggled by this wrapper.
The actual capability/admission owner, rather than a Viewer method list, decides
whether a runnable Standard Octave module/dependencies/request are valid.

Receipt fields include run_id, module_id, caller_id, Session token, state,
source identities and output directory. Status states are RUNNING, COMPLETED,
FAILED, CANCELLED and INTERRUPTED. A reopened/orphaned unfinished invocation is
reported INTERRUPTED. Status requires the exact admitting Viewer; cancellation
targets its live queue invocation only. Busy queue raises GXTXT ANALYSIS BUSY.
Stale Session/Document/source, unknown fields/module/configuration, incompatible
typed selections and ownership errors are explicit existing-owner failures.

No universal statistical result array, units, sample count, probability,
confidence or uncertainty shape is defined by this workflow facade. Use each
selected Analysis's parameter/output schema and
[Statistical Result Semantics](STATISTICAL_RESULT_SEMANTICS_API_v1.md). The GUI's
descriptive preview explicitly assumes no sampling/uncertainty model and does
not publish. A successful queue receipt is not a scientific validation result.

## GUI, language access and example

The optional GUI uses the existing design/Workspace/Source owners. It checks
Viewer presentation policy before opening; existing window is raised before a
new context is applied. Its action callbacks select schema-backed Variables,
run/cancel, inspect, preview and plot; they are not generic service entrypoints.
Display budget4096 does not define full scientific Analysis row limits.

Trusted-host discovery only (no Analysis submission):

```tcl
::GX::modulePublicApiActivate viewer.statistical_analysis STATISTICAL_ANALYSIS_VIEWER_API_v1
set providers [::GX::StatisticalAnalysisViewer::providers]
```

No registered Python/Octave Script Bridge family or typed C++ SDK method directly
calls this Viewer API. The targeted GUI queue itself is host-owned; detached
Scripts use the actual durable Script Job/scientific provider bindings. There is
no generic C++ invoke. The provider declares no facade-specific byte/sample/time
bound; the selected Analysis and existing queue/resource policies own those
limits. Discovery, native usability, execution and scientific accuracy are
separate acceptance gates.
