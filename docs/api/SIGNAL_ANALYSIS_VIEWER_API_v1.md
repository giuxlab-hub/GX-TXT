# Signal Analysis Viewer service API v1

SPDX-License-Identifier: GPL-3.0-or-later

Provider `viewer.signal_analysis` declares version1 in `api/viewer.tcl`, which
loads the public `::GX::SignalAnalysisViewer` service in `handlers.tcl` once.
Its numerical Dataset work belongs to the existing math.signal provider and
Scientific Execution/Job owners; the Viewer is a workflow client.

## Exact trusted-host entries

| Signature in `::GX::SignalAnalysisViewer` | Result/effect |
|---|---|
| `apiInfo` | API ID/version, scope `headless_service optional_gui`, execution_owner SCIENTIFIC_EXECUTION_API_v1 |
| `methods` | activates math.signal SIGNAL_API_v1, returns its datasetMethods list |
| `submit parameters` | activates same public provider and delegates datasetSubmit; returns its Scientific Execution submission receipt with `job_id`, not computed values |
| `status job` | existing Scientific Execution status dict for the Job |
| `cancel job` | existing Scientific Execution cancellation/status result |
| `design` | validated read of this provider's installed gui/design.tcldict |
| `handlers` | action-ID dict with `command ::GX::SignalAnalysisViewer::action` |
| `open ?context?` | context dict default `{}`; composes/raises `.gxtxt_signal_analysis`, returns that Tk path |
| `workspaceOpen context` | required context; existing design Workspace-open result |
| `dispatch operation scene` | calls open with scene.open_context or `{}`; returns its result |

All arguments are required except open's context. Existing open window is raised
and returned before a new context is applied. `open` explicitly checks Viewer
presentation enablement. `dispatch` does not branch on operation. Host service
methods and optional GUI presentation are distinct: a hidden Analysis Run
selection is not by itself a prohibition on its admitted service.

## Dataset submit parameters

`parameters` is a Tcl dict. Current datasetServiceRegister metadata declares:

| Key | Type / required or default | Units/bounds |
|---|---|---|
| dataset_id | required string | canonical Dataset ID |
| primary | required string | stable rank-one numeric Variable ID |
| operation | required choice | one of methods below |
| secondary | string default `{}` | aligned second Variable when method requires it |
| time | string default `{}` | measured time Variable; public affine conversion to seconds |
| sample_rate | number default0 | Hz; metadata min0; positive if required without time axis |
| window | integer default256 | samples; metadata min8; method-specific full row bound |
| overlap | number default0.5 | dimensionless; 0..0.95 |
| normalization | choice default coefficient | none, biased, unbiased, coefficient |
| cutoff | number default10 | Hz; metadata min0; filter requires strictly between0 and Nyquist |
| order | integer default3 | 1..6 |
| decimation | integer default2 | 2..64 |

The current method list is quality.basic, correlation.auto, correlation.cross,
spectral.periodogram, spectral.welch, spectral.asd, spectral.coherence,
spectral.frf_h1, spectral.frf_h2, analytic.envelope, analytic.phase,
analytic.instantaneous_frequency, filter.causal, filter.zero_phase,
multirate.decimate. This is the Dataset workflow's subset, not all SIGNAL_API_v1
operations. Consult actual provider operationSchema/constraints for its scientific
arguments; a Viewer field choice is not a substitute for those constraints.

The Dataset provider checks at least3 rows, full rank-one numeric inputs,
and finite/complete values. Its integer-input admission conservatively rejects
any absolute value greater than2^53 before binary64 conversion, including larger
integers that individually happen to be representable; accepted integers retain
exact conversion within that bound.
Its default managed full-input budget is2GiB, adjustable by the host's configured
GXTXT_SIGNAL_INPUT_BUDGET. It never silently truncates input. Measured times must
be strictly increasing and uniform within its1e-6 relative step tolerance;
positive declared sample rate must agree within1e-6 relative rate. Required paired
signals must be distinct/aligned. Frequency/rate methods need measured time or a
positive declared rate. These are provider checks, not this manual's independent
scientific validation.

## Results, units and lifecycle

Submission uses canonical Dataset identity and the existing managed Scientific
Execution provider `math.signal.dataset`. Status includes job_id, provider_id,
state, captured source identities and available lifecycle/resource/error fields.
Status/cancel require ownership by the current Session's scientific Job; they
do not adopt arbitrary process IDs or unrelated Jobs.

Vector output is exposed through the Job's declared `signal_result` CSV output;
some methods provide only scalar/report outputs. The Viewer explicitly imports
an available table through Scientific Execution import/publication, preserving
provider columns and source lineage. Display uses a4096-sample budget separately
from full-resolution calculation. Hz/seconds/radians/dimensionless values and
known signal units follow the actual provider's columns. Blank derived units
mean unavailable; real/imaginary components must not be relabeled magnitude or
phase. No uncertainty/sampling validation is implied by a completed Job.

Private action/poll/published callbacks and generated Handler delegates are GUI
integration, not additional generic service operations. The public contracts
remain [Scientific Execution](SCIENTIFIC_EXECUTION_API_v1.md),
[Script Job](SCRIPT_JOB_API_v1.md), the installed math.signal SIGNAL_API_v1
manual, [Dataset Publication](DATASET_PUBLICATION_API_v2.md) and
[Session Workspace](SESSION_WORKSPACE_API_v1.md).

For trusted-host metadata discovery only:

```tcl
::GX::modulePublicApiActivate viewer.signal_analysis SIGNAL_ANALYSIS_VIEWER_API_v1
set methods [::GX::SignalAnalysisViewer::methods]
```

No Script Bridge family is registered for this Viewer API and no typed C++ SDK
method directly invokes it. Underlying SIGNAL_API_v1/Scientific Execution
bindings or reviewed typed capabilities are separate grants. There is no generic
C++ invoke. Missing provider, invalid parameters/source/unit/time, stale Session,
resource-budget, provider execution and publication errors retain the real
owner's diagnostics. This reference is not a runtime, numerical or GUI receipt.
