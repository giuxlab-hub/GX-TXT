# Curve Family API v1

`CURVE_FAMILY_API_v1` is provided by `curvefit.family_global`. It invokes the same
standard runtime used by Analysis. Numeric owns the joint solve; CORE owns typed
Dataset transport, statistical interpretation and publication. Both Python and
Octave Script Bridge Jobs discover and call this API through `gxtxt_api_call`.

| Script operation | Tcl operation in `::GX::CurveFamilyV1` | Arguments |
|---|---|---|
| `api_info` | `apiInfo` | none |
| `models` | `models` | none |
| `run` | `run` | Dataset ID, registered model ID, bindings dictionary, config dictionary |
| `result_info` | `resultInfo` | retained result reference |
| `recipe` | `recipe` | Dataset ID, model ID, bindings, config |
| `recipe_validate` | `recipeValidate` | encoded recipe |
| `recipe_run` | `recipeRun` | encoded recipe |
| `submit` | `submit` | encoded recipe, Job name |
| `job_result` | `jobResult` | completed Job ID |
| `results` | `results` | none |

Bindings contain exactly `x`, `family`, `y`, each a stable canonical Variable ID.
Enabled real rank-one Variables must have the same observation dimension. The
scope is the complete canonical Dataset. The existing joint finite/missing-row
policy and one-million-row limit apply. Arbitrary script/runtime/output paths are
not accepted; model IDs resolve through the actual mathematical model registry.
`models` lists registered callable models and their original parameter order.

Configuration keys are the module's scalar configuration fields except
`dataset_id` and `model_id`. Values are scalar text/numbers; vectors use semicolons
in the explicit expanded order documented in the [module guide](README.md).
Each call begins with descriptor defaults plus this configuration. Existing GUI
settings, bindings and per-model parameter edits are restored after preparation.
API runs disable graph rendering. Use the normal Analysis graph workflow for
presentation. Existing supervised Script Job cancellation owns the process tree.

```python
from gxtxt import gxtxt_api_call as call
fit = call('CURVE_FAMILY_API_v1', 'run', [
    'measured_family', 'triode.koren_v1',
    {'x': 'plate_voltage', 'family': 'grid_voltage', 'y': 'plate_current'},
    {'parameter_scopes': 'shared;fixed;fixed;local;fixed',
     'solver': 'lsqnonlin', 'max_iter': 1000, 'tolerance': 1e-10}])
saved = call('CURVE_FAMILY_API_v1', 'result_info', [fit['reference']])
```

The result includes `reference`, source identity, model ID, explicit scope,
`parameter_map`, validated `statistical_results`, output file paths, committed
Dataset IDs and their exact CORE commit receipts (`publication_identity_policy=
core_commit_receipt`). This avoids attributing a later concurrent replacement to
this run. `parameter_map.parameter_indices` is a
matrix with original model parameters on rows and sorted physical members on
columns; indices are one-based. Shared-only plans have one column. Parameter
values, estimates, covariance and inference states come from CORE records and
the canonical parameter Dataset, never a second computation in the binding.

Every successful call retains a new Session-owned result directory. The reference
contains the run identity and receipt SHA-256; lookup verifies the receipt and all
declared output files without refitting. References are local to their Session,
so copying or reopening the complete Session retains them. A modified/missing
output or invalid reference is refused. Previous run files are preserved.

The four standard canonical output Dataset IDs retain module-owned replacement
semantics: they represent the latest committed publication, while saved run
files and fingerprints remain separately inspectable. An earlier result lookup
returns its retained commit receipts and does not claim the current Dataset
still has that content. Script Job journals record actual committed IDs on `run`;
read-only lookup does not publish again. Publication is transactional per Dataset,
not an atomic transaction over all four outputs. Failed runs retain their log and
do not receive a successful result reference.

Session runs retain four conditional `publication_*.tcldict` sidecars containing
exact CORE commit receipts; standalone runs without Session publication do not
create them. The public API seals all four in its result reference. Early dev097
development references without these sidecars remain readable and explicitly
report `registry_observed_after_run` as their identity policy.

For frozen replay, use `operation_mode=evaluate`, `parameter_source=csv`,
`parameter_csv_path=saved['files']['fit_parameters.csv']` and the same declared
parameter scopes. Known-member subsets are allowed; unseen members are refused.
Evaluate ignores optimizer settings and initial values. The CORE records retain
comparison semantics and the parameter Dataset labels values as frozen.

## Saved requests and supervised submission

`recipe` captures an inert, versioned `gxtxt.family_recipe.v1` request through the
CORE scientific recipe codec. It records exact Dataset content/schema, mathematical
model descriptor/source hashes and explicit bindings/settings. Frozen parameter
and optional domain files retain their existence and SHA-256; files within the
Session use relocatable references, while external files retain explicit paths.
Validation refuses changed scientific dependencies. The actual Octave process
checks captured hashes before evaluation and again before publication, including
the source identity after ingestion. It does not silently switch to newer inputs.

`recipe_run` validates and executes the captured request synchronously.
`submit` validates it and creates a named Session Script Library entry and a CORE
supervised Python Job that calls the same public `recipe_run`. The generated
script contains inert encoded request data and no independent scientific code.
The returned Job ID can be inspected/cancelled through the existing CORE Job API.
After completion, `job_result` verifies and returns its retained result. The small
`family_result.ini` in the Job output directory stores the durable reference.

`results` lists Session-local retained references and human-readable model/time
labels. Listing does not refit or verify all large output files; opening a selected
reference through `result_info` performs the full output checksum verification.
Results remain available when the originating GUI is closed. The Fitter's global
family entry uses these same operations and an explicit complete-Dataset scope.
