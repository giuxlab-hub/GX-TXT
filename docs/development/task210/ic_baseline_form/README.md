# Explicit baseline correction through an admitted Viewer form

Route B source proposal; GX210-MAIN1-SUB3, from MAIN efab107c. Not integrated,
executed, installed or GUI/scientifically accepted. Independent CORE1 review and
MAIN's central loader/catalog/descriptor adoption are required before use.

This finite extension to existing VIEWER_GUI_HOST_API_v1 routes declared actions
before authored C++ dispatch. It adds no SDK method, native ABI, scientific math,
provider/backend, durable Job/result store or generic callback dispatcher. The
existing responsive Dataset Transform performs baseline_correct; existing Numeric,
Parallel Execution, canonical Publication/Provenance and Plot v4 remain owners.

Declare a section with transform_kind=baseline_correct and all following fields.
Values are component IDs unless specified otherwise:

| Property | Existing component/meaning |
| --- | --- |
| transform_dataset | Canonical dataset_selector |
| transform_x, transform_y | Distinct inert choice/combobox controls, explicitly selected enabled rank-one float32/float64 numeric Variables with nonempty original units |
| transform_method | choice/combobox, exact choices `asls constant linear polynomial` |
| transform_grid_policy | choice/combobox, exact choices `uniform_x sample_index` |
| transform_nonfinite | choice/combobox, exact choices `error omit` |
| transform_output | String field/entry, explicit fresh output Dataset ID |
| transform_baseline, transform_corrected, transform_row | String fields/entries, distinct new Variable IDs not present in the original source |
| transform_options | Exact dictionary `lambda CONTROL p CONTROL max_iterations CONTROL tolerance CONTROL value CONTROL degree CONTROL`; numeric fields, iterations/degree integer fields |
| transform_commands | Dictionary ACTION→OPERATION with all four unique closed operations `discover create_corrected cancel inspect` |
| transform_status, transform_report | Read-only status/label and log |
| transform_plot | Dedicated Plot component, no competing plot_form |

All controls and option fields are distinct across Transform forms; no field
change_action, tool, History, visibility, series, netlist or other form command may
claim a Transform action. Create's handler effect is **mutating**. The other three
effects are presentation, with Cancel restricted to stopping captured work.
No Transform action is an initial_action. Source/option selections do not run or
publish anything. Discover only populates real canonical Variable choices; it
does not silently choose a scientific mapping or perform a preview calculation.

Declare requirements VIEWER_GUI_HOST_API_v1@1, DATASET_TRANSFORM_API_v1@1 and
PLOT_DATASET_API_v4@4. The actual project must be scientific_view_v1 and explicitly
request VIEWER_GUI_HOST_API_v1/transform_form, DATASET_TRANSFORM_API_v1/
execute_responsive,cancel,provenance and PLOT_DATASET_API_v4/widgetCreate.
Normal capabilities for other declared controls remain required. Declared-form
admission runs even when authored sdk_calls is empty. There is no authored
transform_command SDK method and no new Script responsive operation grant.

Current backend validation returns gxtxt.viewer_transform_admission.v1 with the
profile, admitted form IDs, exact required grants and source/design/project SHA.
The existing Development window stores it only after actual report/source
checks. Development Preview and installed compiled admission both recompute the
proof; mutable author JSON receipts are not a trusted source. Queue/start reread
all three admitted source files and the exact live design. The operation captures
form, source schema/declared SHA/public persisted revision (including metadata
SHA/coordinate binding identity), Session token/path, window XID/opened_us,
Workspace identity/generation/revision/SHA, and an independent operation epoch.
Progress checks lightweight project stat identity plus captured form/window/
Session state; the precommit-phase cancellation prefix rechecks admitted project
hashes both before and after the final event-loop yield. Unrelated
compiled event counters are not used as the scientific operation epoch.

Only explicit Create builds a closed baseline_correct manifest: one complete
original source, no selected-column or row compression, strict dtype/explicit
unit policy, inherit_single_source, fresh output and three fresh derived IDs.
Start is deferred after0 and delegates once to datasetTransformExecuteResponsive;
there is no synchronous Plan presented as a responsive preview. Active form
inputs are disabled, other creates in that Viewer are refused, and the existing
global Transform owner still admits only one responsive execution.

Options are a finite subset of the actual owner: AsLS uses lambda/p/iterations/
tolerance plus explicit grid/nonfinite policy; constant uses an explicit value;
linear uses the existing linear fit; polynomial uses explicit degree. Constant
mean/median estimation and anchors are outside this first form. The existing
owner validates numerical bounds/convergence/monotone X; AsLS requires at least
three rows. uniform_x requires monotone unique approximately uniform X;
sample_index applies the penalty to consecutive selected rows and still requires
monotone unique X. No sorting/resampling is implicit. Source rows are1..2000000,
original schema at most4096 Variables, and each newly requested ID at most128
characters. This first form supports ordinary local canonical sources and
original numeric axes; nonidentity display/calibration/units are explicitly
refused through the public Coordinate owner after deferred start. It does not
guess calibration or treat formatted elapsed-time text as numeric coordinates.
Custom canonical-unit/formula overrides are refused before queueing; this form
does not transfer an original Variable's custom conversion onto new derived axes.

Cancel stops only the captured queued callback or the execution ID supplied by
its trusted progress prefix, through public datasetTransformCancel. It does not
inspect private Transform arrays or cancel a global/foreign execution. Cancel
and inspect remain reachable after current-source/project/Session admission
fails: the narrow shared command exception checks captured XID/opened_us,
form/epoch, original Session token, original live design and exact CORE handler;
it never grants Create or authored handler execution. Additional adapter guards
are not bypassed. Destroy/Restore stop captured work, and the cancellation prefix
requests cancellation when live input/lifetime changes. Existing Transform
Session/precommit checks remain authoritative even before callbacks can run.

Successful responsive return is a canonical commit. The form then reads actual
Provenance effective.baseline_receipt; checks source hash, requested IDs/method,
full original column names/dtypes/shapes/units, row count, float64 derived columns
in original Y units and uint64 original zero-based row identity. It reads actual
first/last canonical row ordinals as bounded boundary samples, not a claim of
host-side full-row verification. Raw/baseline/corrected series bind through Plot
v4 to the real new Dataset, without private vectors. Receipts preserve effective
options/convergence and the fact that baseline uncertainty/correlations are not
propagated. Convergence is not proof of a physically correct baseline.

If later provenance/host/source/Plot validation fails, the state is
COMMITTED_DISPLAY_FAILED, retaining the genuine output/result/available receipt;
no output is deleted and rollback/cancellation is not claimed. Closed-window
commit identity is also emitted as GXTXT_VIEWER_TRANSFORM_COMMITTED diagnostics;
the canonical Dataset/provenance remains durable truth. Ephemeral execution state
is not a second scientific store and is not restored as a running operation.
Full IC study/seven-source membership and lifecycle persistence are not supplied
by this first slice. Original Viewer routes remain; parity/performance are not
waived. See QA_PLAN.md and MAIN_INTEGRATION_DELTA.md for unexecuted next steps.
# CORE1 review501 final-yield admission correction — SOURCE ONLY

The preserved original e333077d leaf checked full project/design/source admission
in the precommit progress callback before Transform's final vwait. The callback's
later cancellation check used second-resolution lstat stamps and could miss a
same-size in-place edit during that last yield. The corrected form records its
own precommit phase in ephemeral operation state. The existing cancellation
prefix then requires exact captured Authority/hash equality on every check in
that phase, including the final post-yield check; a mismatch or failed admission
requests cancellation of only its captured execution and returns cancellation.
The form never reads private Transform state. Full hashing remains disabled for
ordinary50ms planning pulses; no shared Transform owner changes. Existing final
canonical Dataset verification remains independently authoritative. This source
correction is unexecuted and needs CORE1 independent re-review before adoption.
