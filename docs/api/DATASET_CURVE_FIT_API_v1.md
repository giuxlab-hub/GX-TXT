# Dataset Curve Fit API v1

Akima and explicit-knot B-splines use `model=akima|bspline` and `knot_options`.
The [knot workflow](FITTER_KNOT_MODELS_v1.md) documents original units, explicit
boundaries, retained state, recipes and real Script consumers.

Physical rational fitting uses `model=rational`, `rational_recipe` and explicit
`rational_extrapolation=error|allow`. Controls, retained state, both orientations,
measurement policies and existing Script consumers are defined in the
[rational workflow](FITTER_RATIONAL_v1.md).

Initial suggestions, exact-source manual parameter evaluation and inert recipe
updates are available through the [parameter view API](FITTER_PARAMETER_VIEW_v1.md).

`resultResidualSequence reference options` / `result_residual_sequence` describes
complete retained residuals through Numeric and CORE without refitting. Explicit
ordering, lag limits, unavailable cases and both-language semantics are defined
in the [residual sequence contract](RESIDUAL_SEQUENCE_v1.md).

## Accepted display names

`accept key ?name?`, `acceptSources key source_ids ?names_by_source?`,
`recipeRun encoded_recipe ?workspace_name? ?accepted_name?` and
`registeredAccept preview_reference ?accepted_name?` accept optional display names.
The Script operations `recipe_run(encoded_recipe, workspace_name, accepted_name)`
and `registered_accept(preview_reference, accepted_name)` retain their previous
arities when the final name is omitted. An empty optional name uses the existing
automatic label. A supplied name is trimmed, contains 1–160 characters and no
control characters. Unicode and duplicate labels are allowed; canonical
`fit_curve_id` and source identities remain distinct and unchanged.

The GUI proposes editable names through the same acceptance owner. The batch
mapping must cover exactly the selected source IDs and is fully validated before
mutation. Cancel creates no History edit. Public `result_info` returns
`accepted_name`; accepted provenance and publication metadata retain
`curve_fit.accepted_name`. Historical records keep their saved automatic label
without requiring a new field or a refit. A changed saved label/provenance pair
cannot validate as an intact named result.

## Retained residual pages and linked inspection

`::GX::DatasetCurveFit::resultResidualPage reference start count` and Script
`result_residual_page(reference, start, count)` return `FITTER_RESIDUAL_PAGE_v1`,
version 1. The durable accepted reference guards owner generation and frozen
provenance. `start` is zero based; `count` is 1..512 and clips at the final row.
The result carries the public CORE evaluation `meaning`, typed float64 `residuals`
and exact uint64 `source_rows` pages. Their fields match the existing influence
and bootstrap page contracts. Empty pages preserve their dtypes and column counts.
Shape, row counts, canonical columns and owned resource hashes are validated.

Columns follow the retained model: scalar response uses `source_x`, `source_y`,
`fitted_y`/`fitted_x`, `y_residual`/`x_residual`; radial fitting retains fitted and
observed radius plus theta; geometric fitting retains projected coordinates,
signed distance and parameter. These are physical coordinates after the explicit
translation inverse. Evaluation rows are distinct from the training population:
zero/missing training precision does not erase a finite evaluated observation.
Historical results without owned residual resources report unavailability and
are never silently refitted.

The GUI reads the same retained rows. Native2D supplies bounded sampled offsets;
CORE managed resources resolve the exact tuples. Table/graph inspection does not
change fitting selection. The explicit selection action shares the existing
influence source-row validation/selection owner, including stale-source checks.
Source-to-table lookup streams only bounded original-row index blocks. A separate
Native2D diagnostic scene uses the documented module-specific `aspect auto`
override; the main scientific scene retains its equal-scale policy. The additive
Workspace panel field `residual_axis=source|predicted` defaults to source for older
documents and never changes scientific identities or stored numerical values.

`sampleDescriptor sample_id` returns a dictionary containing `sample_id`, `title`,
`description`, `axes` (X/Y Variable IDs, labels, units, semantic roles and value
kinds), `generator_id`, `generator_version`, `producer_module`, `producer_version`,
deterministic `generator_parameters`, and `expected_result` with a named metric
and tolerance. `sampleCatalog` retains the compatible ID-to-title mapping.

`publishFitDataset key requested_id` and `publishSampleDataset sample_id requested_id`
use the exact validated nonempty public ID supplied by the caller. They perform
normal create-only collision checking through Dataset Publication v2. Invalid IDs
are rejected, never sanitized/generated. Full schema and structured metadata are
part of the publication transaction. Samples and accepted local CORE curves do
not enter the Dataset Registry until an explicit publication call.

Built-in provenance is `source_kind=builtin_sample`, `source_sample_id` and the
complete descriptor; `source_dataset_id` is absent. Real Dataset sources retain
Dataset ID, fingerprint, variables and filters. The CSV header uses the applicable
source identity column, and its sidecar preserves this lineage. Legacy
saved `source_kind=sample` documents remain readable and their accepted sample
curve provenance is upgraded when restored.

Provider `viewer.dataset_curve_fit`. Activate through `::GX::modulePublicApiActivate viewer.dataset_curve_fit DATASET_CURVE_FIT_API_v1`. The existing Tk viewer and public host API share canonical Dataset reads, Native2D CORE curves, Numerical API calculations and Interactive Document persistence. Viewer UI lifecycle stays host-only.

```tcl
set key [::GX::DatasetCurveFit::new]
::GX::DatasetCurveFit::loadSample $key circular_arc
set fit [::GX::DatasetCurveFit::preview $key circular_arc all {parameter 0 1 1000} 2 {} {}]
set coreId [::GX::DatasetCurveFit::accept $key]
# Only an explicit publication creates a Session Dataset.
set published [::GX::DatasetCurveFit::publishFitDataset $key "circular_arc_result"]
::GX::DatasetCurveFit::exportCsv $key /host/chosen/result.csv
::GX::DatasetCurveFit::close $key
```

`loadSource key dataset_id x_variable_id y_variable_id filters` reads a filtered canonical source with stable identities. `loadSample key sample_id` uses an internal source; `sampleCatalog` lists local samples. Samples are not added to Dataset Registry by loading or fitting. `publishSampleDataset sample_id name` explicitly creates a Dataset. `preview key model scope domain degree initial options` returns fitted/residual samples, training/source metrics, source/selection identity, grid kind/count and reconstructible `model_state_json`. Scope is `all` or `selected`; point selection uses the existing public Native2D API.

Response models include linear, polynomial, exponential, power_law and gaussian. Other supported models are circular_arc, quadratic_bezier, cubic_bezier, pchip, smoothing_spline and fourier. Domain remains `source` or `{min max samples}` for function models; parametric arc/Bézier use `{parameter t_min t_max samples}` within `[0,1]`. Existing 2–10000 output bounds are preserved. Fourier degree is harmonic order, with optional positive `period`; it requires at least `2N+1` independent samples and a full-rank design. No low order cap is introduced. Smoothing uses nonnegative `smoothing_lambda`: zero interpolates, larger values penalize curvature. See [Numerical API](../../plugins/modules/math.numeric/NUMERIC_API_v1.md) for reconstruction/projection and conventions.

`accept` creates a separate CORE curve, without Dataset publication. Accepted records persist model state, points, grid/options, selected source points/filters/hash, residual convention and metrics through the GUI's Interactive Document lifecycle. `publishFitDataset` explicitly writes fitted X/Y and complete namespaced model/provenance metadata through Dataset Publication v2. CSV export writes the accepted curve and `<csv>.metadata.ini` with model/provenance and CSV SHA. A stale source/selection or duplicate acceptance is rejected. Sample, source Dataset, CORE fit and published Dataset identities remain distinct.

See [viewer manual](../../plugins/modules/viewer.dataset_curve_fit/MANUAL.md), [publication](DATASET_PUBLICATION_API_v2.md) and [Canonical Dataset API](CANONICAL_DATASET_API_v2.md). Numeric model operations are separately callable by both Script Bridge languages; this does not expose arbitrary host file destinations through the viewer API.

## Dataset measurement bindings

The existing `solver_options` dictionary also accepts Numeric's additive
`multistart_mode`, `multistart_count`, `multistart_initials`, `multistart_lower`,
`multistart_upper`, `multistart_seed` and `multistart_max_seconds` options for
exponential, power-law and Gaussian fitting. Explicit initials are a list of
additional parameter rows; GUI text uses semicolon-separated rows. The common
Numeric strategy and CORE solver report own selection and interpretation;
Fitter retains the winning model and all bounded trial receipts through its
existing accepted-result lifecycle. See the Numerical API for limits and replay.

For `linear`, `polynomial`, `exponential`, `power_law` and `gaussian`, the
`preview` options accept `measurement {kind sigma variable_id sigma_y nonfinite
error}`. The kind is `none` (default), `sigma`, or `relative_precision`;
`variable_id` is an enabled numeric Variable ID in the real source Dataset.
`nonfinite` is `error` (default) or explicit `omit`. Other model contracts reject
weighting until their scientific meaning is implemented.

Sigma is a strictly positive standard uncertainty of the fitted response:
Y for Y=f(X), X for X=f(Y), or radius for R=f(theta). CORE converts its unit to
the actual response unit using the absolute affine scale, without an additive
offset. A converted source view uses the view's response units and values.
Relative precision is dimensionless and nonnegative; zero excludes that training
row. Finite negative precision and nonpositive sigma always reject. Explicit
omission applies only to nonfinite measurements. At least two positive-precision
rows must remain, with the model's existing rank and sample requirements still
enforced. Noise assumptions and future-observation sigma/precision remain
separate explicit settings.

CORE Curve Source captures measurements beside exact XY and original uint64 row
identities through filters, transforms, reversal and selected training masks.
Numeric performs one weighted fit. `measurement_binding` captures Variable ID,
descriptor, source identities, units, scale conversion, orientation and policy;
`measurement_selection` records input, fit, omitted and zero-precision counts.
Owned `measurement_resource` has four interleaved float64 columns:
`original_measurement`, `converted_measurement`, `effective_weight`,
`used_for_fit`. `measurement_rows_resource` holds every selected input row's
original uint64 identity; `training_rows_resource` holds only the retained fit
rows. Transient transport paths are never persisted.

Training statistics declare their actual weight semantics. Full-source residual
evaluation is unweighted and retains its separate population. CORE's weighted
R-squared definition is available on `quantities.r_squared.definition`.
Accept, Workspace/History and Dataset publication preserve these bindings,
counts and owned resources; restore validates their scientific lineage and
resource checksums. Legacy records without measurement fields remain readable.

## Exact source science

The additive GUI workspace retains per-source descriptors and accepted model/resource identity. Exact filtered/selected input streams independently of display extrema. Orientation X=f(Y) swaps mathematical dependent/independent bindings while retaining physical output X/Y; R=f(theta) records shared polar frame and native/Numerical conventions. Ordered parametric polynomial/natural/periodic cubic supports row/path/user parameterization and explicit topology. No accepted curve is refitted on restore. Shared model APIs provide bounded exact projection/residual pages and model-owned resource lifetime. The manual describes batch acceptance, source reversal, source removal and explicit publication of historical accepted results.

## Coordinate translation and History

The optional `translation_u` and `translation_v` fit options are dictionaries
with `mode` (`auto`, `manual`, `off`) and `delta`. An omitted option retains
legacy OFF semantics. The GUI explicitly supplies its per-source configuration,
whose factory mode is AUTO. Numerical API owns positive-translation resolution;
the Viewer records its effective constants and applies the inverse once to
physical geometry and residuals.

Preview and accepted provenance contain `translation`, including original and
transformed bounds, variable/axis identity, units, margin, resolved delta,
forward/inverse conventions and `inverse_applied=1`. `physical_formula` is the
same physical expression rendered as one line for portable metadata. Explicit
Dataset publication writes `curve_fit.translation` and
`curve_fit.physical_formula`; accepted CSV sidecars retain both as well. The
exported coordinates are physical values, not translated fitting coordinates.

Changing model, orientation, fit scope, output domain, numerical parameters,
translation, parametric or radial settings invalidates the stored unpublished
Preview. Previously accepted geometry remains independent. Invalidation and
configuration participate in the shared CORE History checkpoint, so reopen or
Redo cannot re-enable an incompatible Preview. Bound form edits recover the
displayed checkpoint before branch confirmation and apply the captured user
choice only after confirmation. Numeric field commits precede plot gestures.
The GUI adapter uses `SCIENTIFIC_RECIPE_API_v1`; it introduces no separate
History format or persistence service. See the manual for scoped panel/shortcut
configuration and protected History clearing.

## Statistical compatibility

Preview and `fitPrimitive` quality results contain `statistical_results` with
CORE training/evaluation records and `statistical_aliases`, keyed by each retained
legacy numeric field. Each alias is a public CORE scalar row with an added
`sample_role`. Values, statuses, units and quantity identities must match the
records; publication, CSV export and Workspace save/reopen reject modifications.
Non-value compatibility fields use NaN with an explicit status and reason.

Functional `train_r2`/`source_r2` map to `r_squared`. Geometric models preserve
their historical XY-dispersion convention under those fields and also expose
`train_geometric_dispersion_score`/`source_geometric_dispersion_score`, all mapped
to `geometric_dispersion_score`. Geometric errors map to CORE `rmse` and
`max_abs_error`. No fit or statistic is recomputed for presentation. Published
Dataset metadata uses the existing `curve_fit.` namespace; CSV sidecars and
accepted Workspace provenance retain the complete records. Older releases'
payloads without these records remain unmodified and explicitly unvalidated.

### Native nonlinear state and diagnostics

The existing `exponential`, `power_law` and `gaussian` identities and parameter
orders now use public Numeric declared fitting and prediction with Ceres.
Preview carries `numeric_model_state` and its SHA256 alongside CORE statistical
results; this bounded typed state preserves binary64 coefficients and signed
infinite bounds through accepted records, CSV metadata, Dataset publication and
Workspace reopen. It is not converted to JSON. Its identity/parameters/settings
are checked against the solver receipt before persistence or acceptance.
The existing model-state JSON for other models remains readable. Original
Dataset values and saved historical fits are preserved.

Results show the public stopping interpretation; Results > Solver diagnostics
opens exact settings and backend details. A new native preview that has not
converged can be inspected but cannot be accepted or published. Advanced solver
editing and weighted Dataset bindings use the contracts documented here.

### Scoped native solver controls

`preview(..., options)` accepts `solver_options` for the three declared native
nonlinear models. Supported fields: `solver` (auto/ceres), `strategy`
(levenberg_marquardt/dogleg), `max_iterations`, `max_seconds`,
`function_tolerance`, `gradient_tolerance`, `parameter_tolerance`, `loss`
(linear/huber/cauchy/soft_l1/arctan/tukey), `loss_scale`, and parameter vectors
`lower_bounds`, `upper_bounds`, `fixed_mask`, `parameter_scales`. Unbounded
endpoints use -Inf/Inf. Vectors follow canonical parameter order. Blank vectors
request Numeric defaults. Numeric remains the authoritative mathematical
validator, including initial/bound consistency. Unknown settings and applying
nonlinear settings to other model families are rejected.

Fit > Solver settings edits the same policy. Settings are captured per
source and per model in `solverSettings`; source/model changes invalidate stale
dialog ownership. Applying settings invalidates the preview. Historical
Workspaces without this additive field use defaults. Raw data are unchanged.
The common CORE bounded transport carries exact policy values into the existing
worker; there is no separate optimizer or module-specific configuration parser.


### Reusable component fitting

`componentCatalog` returns public Numeric descriptor cards. `preview` accepts
model `components` with `options.component_recipe`, the public
`NUMERIC_API_v1 fit_model_compose` recipe. Its declared x/y units must match the
independent/response axes (including X=f(Y)); missing unit fields are bound
explicitly from the source. Initial parameters come from that recipe. This
consumer uses `math.numeric.nonlinear` statistical semantics and preserves the
component parameter identities and units. The resulting `numeric_model_state`
contains the frozen composition and shared-parameter constraints.

Existing measurement bindings, solver options, accepted result validation,
publication, History and Workspace persistence apply. The additive Workspace
field `componentRecipe` defaults to empty for historical documents. Existing
model IDs and the historical builtin Gaussian convention are unchanged.

The independent physical cards add Voigt area, logistic response, Arrhenius
activation temperature, exponential/multi-exponential decay and Shockley with
series resistance. Model cards and the registered `component_settings` command
use the **Model components…** label; the existing `components` model identity,
widget path, recipe field and accepted state remain compatible. Solver-menu
availability includes composed models and supported linear/polynomial XY fits.
`numeric_model_state.input_constraints` captures physical domain, required units
and translation policy. Arrhenius and diode recipes reject nonzero input/output
translations; failed preview retains the previous scientific result. All domain
evaluation and statistical meaning still belong to Numeric and public CORE.

## Comparable accepted models

`::GX::DatasetCurveFit::compareFits key fitIds ?criterion?` compares two to 64
accepted canonical `fit_curve_id` values (existing native IDs remain accepted by
the lookup API). Criterion defaults to `aicc`; choices are `rmse/aic/aicc/bic`.
Returns public CORE `gxtxt.model_comparison.v1`; no estimator or refit runs.
New previews retain `observation_binding`, `model_selection` (CORE plan and,
when eligible, Numeric receipt) and exact `comparison_rows_resource` for managed
Dataset inputs. Statistical provenance captures original/translated response
fingerprints. All records are validated before comparison and on persistence.
Historical records without evidence remain usable but cannot be certified for
comparison. The registered GUI command is `model_comparison`, in Results.
The same CORE/Numeric APIs are public to real Python/Octave Script Jobs without
requiring a GUI Fitter instance.


## Explicit data-only fit rerun

`gxtxt.fit_recipe.v1` captures a newly accepted fit's initial parameters, solver
and multistart settings, physical orientation/translation, output domain, exact
Curve Source point mask, Dataset filters/transform, sigma/weight bindings,
scientific schema/content fingerprints, module/API versions and frozen model
card identities. It contains inert data. It does not replace the retained
geometry/history contract `gxtxt.scientific_recipe.v1`.

The same public API is available in Tcl, Python and Octave. Script operations:

| Operation | Positional arguments | Result |
|---|---|---|
| recipe_capture | document_id, fit_curve_id | encoded inert recipe |
| recipe_validate | encoded_recipe | source/version/card checks; no estimation |
| recipe_run | encoded_recipe, workspace_name | new durable result reference |
| recipe_script | encoded_recipe, Python or Octave | runnable explicit-rerun script text |
| result_reference | document_id, fit_curve_id | verified durable reference |
| result_info | reference | parameters, formula, CORE statistics, resource receipts, recipe |
| result_publish | reference, dataset_id | normal create-only Fitter Dataset publication |

Tcl names in `::GX::DatasetCurveFit` are `recipeCapture`, `recipeValidate`,
`recipeRun`, `recipeScript`, `resultReference`, `resultInfo`, `resultPublish`.
`recipeRun` uses the existing `new/loadSource/preview/accept` implementation and
saves a normal Fitter Workspace. It never computes an alternative set of
statistics. Script parameter values are typed numeric arrays in the captured
canonical order; statistical meanings come from
`STATISTICAL_RESULT_SEMANTICS_API_v1 validated_result`.

A `gxtxt.fit_result_ref.v1` contains document ID, owner generation, stable
accepted-fit ID and provenance SHA-256. It survives Job exit, viewer closure and
ordinary Workspace rename. Removing/replacing its owner or changing the retained
scientific provenance invalidates it. There is no native pointer or process
handle to release, and Job cleanup does not delete retained scientific results.
A later Job can obtain a new verified reference from the document and fit IDs.
Publishing an existing reference restores its retained geometry without refitting.

`result_info.resources` exposes Session-owned residual, exact row, measurement,
model-state and prediction receipts when available. Use `MANAGED_RESOURCE_API_v1
read_numeric(resource,start,count)` for bounded binary numeric pages. Row
identities remain uint64; columns, row count, dtype and source SHA accompany each
page. Large geometry/model state is retained in managed resources, not embedded
as an unbounded control result.

Replay refuses changed source bytes/scientific schema, incompatible producer
versions and changed frozen card definitions. It does not silently remap a recipe
to another Dataset. Old accepted fits remain readable; fits created before
replay provenance was recorded need an explicit new preview/accept before
capturing a reproducible rerun. Ordinary Workspace/Session reopening does not
rerun a fit. The Results menu exports the selected accepted fit as Python or
Octave source; execution is explicit and creates a distinct Workspace. Replay
selection is evaluated against original rows, including rows absent from the
bounded display sample. The accepted provenance retains that exact mask.

The requested rerun Workspace name is a preferred label. If it already exists,
a numbered suffix creates a distinct Workspace and preserves the prior result.
Re-executing the same generated script therefore never replaces its earlier fit.
The bounded control transport preserves a declared one-row matrix of additional
multistart starts. The regional adapter restores the declared N-by-2 container
for a single observation window after the bounded result-vector representation.

## Named fit templates

Named templates are ordinary Session Workspaces contributed by this same module:
provider `dataset_curve_fit_recipe`, schema `gxtxt.fit_template.v1`, version 1.0.
CORE owns their names, generations, persistence, export/import and deletion. There
is no separate template database. The payload contains an inert fit recipe,
frozen required Variable contracts, and the original retained-result reference.
A template remains inspectable when its original Dataset is unavailable.

| Script operation | Positional arguments | Result |
|---|---|---|
| template_create | retained_result_reference, name | saved template description |
| template_list | none | descriptions of this Session's templates |
| template_inspect | template_id | model, producer versions, required Variables/units and selection counts |
| template_bind | template_id, target_dataset_id, variable_mapping, selection_policy | encoded bound recipe and explicit review |

Tcl names are `templateCreate`, `templateList`, `templateInspect`, `templateBind`.
The Variable mapping dictionary must explicitly cover all required original IDs:
axes, source filters, response/independent sigma or precision, and any curve
parameter Variable. Enabled scalar type/rank and declared units are checked.
Different units require an explicit Unit Registry/Dataset Transform conversion;
initial values, bounds and geometric selection coordinates are never silently
rescaled. A pre-existing transformed source must first be materialized as a
canonical Dataset; a built-in sample must first be published. Templates transfer
fit settings, not an implicit preprocessing pipeline.

`selection_policy=coordinate_regions` retains coordinate-region selection but
clears all original row-specific picks, whose identities cannot refer to a new
Dataset. `all_rows` clears the fit-point mask and uses all rows passing the
captured, explicitly remapped source filters. The review reports dropped picks,
filters, regions and the required separate Preview/Accept actions. No binding
operation runs a fit. Target content/schema fingerprints are frozen in the bound
recipe, then checked again before use. Frozen original source contracts make
binding independent of the original Dataset's later availability.

Python/Octave callers explicitly run the returned recipe using `recipe_run`.
The GUI offers Results → Save selected fit as template and Fit → Apply fit
template; Workspace Manager opens the same binding dialog. Review enables Apply
settings, which loads a distinct source and its model/solver/measurement settings.
The user then explicitly previews and accepts. Existing accepted fits remain.

`gxtxt.fit_template_binding.v1` records the template ID/generation/SHA, immutable
original Dataset identity, actual target ID/SHA, Variable mapping, selection
policy and dropped-pick count. It is retained in accepted provenance, per-source
Workspace/History state, the public `result_info.template_binding` and published
`curve_fit.template_binding` Dataset metadata. `curve_fit.recipe_producers` also
records the recipe producer versions. Workspace names may change; scientific
Dataset/Variable/fit identities are preserved. Portable template Workspace
packages keep these contracts and require explicit target binding after import.

The host-only `recipeLoadSettings(key, encoded, exact=0)` shares the same loader
with headless replay; it performs no fitting. Headless replay requests the exact
original-row mask. A rebound GUI template contains coordinate selections and
allows ordinary subsequent GUI selection edits. Explicit producer-version and
frozen-card checks remain in effect when a template is bound or run.


### Independent accepted-model functions

`result_export(reference, function_name)` / Tcl `resultExport reference name`
returns `python`, `octave`, `latex`, and `metadata_json` UTF-8 text. The function
name must be `fit_` plus a letter and up to 55 further ASCII letters, digits or
underscores. Use the same base filename for `.py` and `.m`. Python needs NumPy;
Voigt/erf expressions additionally use SciPy. Octave needs only its core runtime.
The exported files do not import GX-TXT, call a fitting engine, or compute
statistics. CORE retains sole authority over the accepted statistical results.

Functions accept finite real scalar/vector physical independent coordinates
(or normalized dimensionless t for parametric curves) and return N-by-2 physical
X/Y coordinates. Values outside the explicit accepted output interval reject.
Translations, reversed orientation and the captured polar frame are applied
exactly once. Piecewise cubic knots, interval ownership, Fourier origin/frequency,
parametric topology and the native compiled expression are frozen. Physical
scientific model IDs are retained independently of evaluation representation.

Numerical constants use 17 significant digits. Scaled polynomials retain the
actual centered/scaled Horner coefficients: their units differ from the original
physical power coefficients. Metadata/LaTeX includes accepted parameter IDs,
values and units in their original CORE order, separate evaluation coefficients,
axis units, transformations, source/ref SHA, domain assumptions and license.
The LaTeX fragment uses amsmath; Unicode metadata needs a Unicode-capable TeX
engine. No TeX compiler is required to evaluate the functions.

Results -> Export selected model creates a single create-only four-file bundle
through CORE File Publication. It neither prepares a History edit nor modifies
the retained Workspace. Script callers receive the same source text and choose
their own explicit managed destination. Export works after the original Job or
viewer has closed and does not need source data. Owner generation/provenance and
saved model state are validated before export. Historical ordinary polynomials
without exact scaled state refuse; users may explicitly preview/accept a new fit.
Existing scientific results are never silently reconstructed or overwritten.
Large saved model JSON is read through its owned resource in bounded chunks.
Input model text and each generated artifact are bounded to 2 MiB; a larger model
requires an explicit smaller model, never implicit downsampling. The original
model and all prior releases remain untouched.

Validation compares sampled physical points with the numerical owner/accepted
geometry using abs(error) <= 5e-11*max(1,abs(reference)). Extreme ill-conditioned
expressions need a separately assessed tolerance. This evaluates a frozen model;
rerunning estimation remains the distinct `recipe_run` operation.


### Registered model consumer

`registeredModelDeclare(reference, callable_id, entrypoint, definition)` attaches
`gxtxt.fit_model.v1` to the existing CORE Script Registry, preserving executable
UTF-8 bytes and canonical parameter order. The declaration requires parameter
IDs, units, initial values, predictor/response units, N-by-1 predictors/responses
and P-by-1 parameters. Bounds and finite/positive predictor domain are explicit.
Optional `fixed_mask` contains one 0/1 value per parameter; 1 fixes that value
at the selected initial estimate. Equal lower/upper bounds also fix a parameter,
and its initial value must equal that bound. An absent mask stays absent from the
canonical declaration, preserving existing declaration hashes. Script discovery
returns an explicitly supplied mask as a typed numeric vector.
`registeredModels` and `registeredModelDescribe` expose these declarations.
Script Bridge exposes `registered_models`, `registered_model_describe` and
`registered_model_declare` with the corresponding arguments.

`registeredRecipe(controller, reference, callable_id, scope, domain, options)`
captures exact Dataset identities, filters and the CORE row mask into the existing
`gxtxt.fit_recipe.v1`; the model is `registered`, and `options.registered_model`
pins executable/declaration SHA, revision and scientific declaration.
`registeredSubmit(encoded_recipe, workspace_name)` / Script `registered_submit`
returns a supervised Script Job. It executes the declared Python/Octave function
through the existing callback contract and `registered_run(callback, envelope)`.
The latter only accepts the exact current registered callable identity from
`SCRIPT_EXECUTION_API_v1`, never an arbitrary evaluator or file path.

The Job returns `gxtxt.fit_preview_ref.v1` through its verified callable receipt:
Document ID/generation, source curve ID, executable SHA and preview content SHA.
Its preview is retained and **unaccepted**. `registeredPreviewInfo(reference)`
validates it; `registeredAccept(reference)` / Script `registered_accept` performs
explicit acceptance and returns the existing durable fit-result reference.
`result_info`, publication, Session retention and exact-resource ownership are
shared with ordinary fits. A closed originating controller does not cancel a Job.

The host consumer obtains full numeric rows only within CORE Curve Source's
owned input lifetime. Native geometry, residuals, uint64 source/measurement rows
and exact executable source are retained by the Document resource owner. No live
callback handle is persisted. Numeric owns optimization, evaluation, Jacobian,
covariance, coordinate translation, residual metrics and comparison facts; CORE
owns statistical meaning. The recorded callback solver is SciPy least_squares when parameters are free;
all-fixed requests record `fixed_evaluation` and zero optimizer iterations. Fixed
values retain their full parameter order and CORE fixed role; the prediction
Jacobian has zero columns for fixed constants. This is separate from a native
Ceres receipt. Nonconverged previews cannot be accepted.

Registered recipes accept `options.solver_options` with `solver=auto|least_squares|scipy_least_squares`,
`method=trf|dogbox`, `max_function_evaluations` (1..2000000), positive
`function_tolerance`, `gradient_tolerance`, `parameter_tolerance` greater than
binary64 machine epsilon, and optional positive `parameter_scales` in canonical
parameter order. Defaults are `scipy_least_squares`, `trf`,8000 evaluations,
1e-8 for each tolerance and unit scales. Native Ceres-specific controls remain
invalid for this consumer. The existing Solver settings command stores this same
policy per source/registered model in the ordinary Workspace/recipe fields.
The common statistical result retains and validates
`gxtxt.callback_solver_receipt.v1`, including effective values and backend version.
Old results without detailed receipts remain readable and report that limitation.

Current integrated contract supports functional Y(X)/X(Y), declared units,
response sigma/relative precision, explicit missing/zero precision row receipts,
selection, output domain, pointwise response intervals and independent source export.
Registered radial/orthogonal models and synchronous recipe_run
are unsupported and fail explicitly.

Registered response intervals use the existing CORE prediction inference plan
and Numeric covariance propagation operation. Parameter uncertainty is computed
once, and its critical value is reused. The live callback supplies the bounded
finite-difference Jacobian while its supervised Job is active; no handle survives
Job exit. CORE retains the explicit registered-callback method. Mean confidence
and future-observation intervals share the ordinary noise eligibility and future
sigma/weight controls. Ineligible plans remain explicit without interval columns.
The canonical eight-column `prediction_resource`, Native2D boundary resources and
uint8 gap mask use the same ownership, acceptance, publication and portable
Workspace contracts as ordinary models. Translation is undone in the retained
scientific coordinates, including both interval bounds.

`resultExport` / Script `result_export` also supports retained registered models.
Fitter passes the exact immutable executable source and canonical fitted state
to public Numeric `model_export`, using the saved declaration even if the Script
Library has since changed. Generation does not evaluate source or refit. The
existing GUI four-file bundle remains create-only. Both generated interfaces
return physical Nx2 coordinates with the original domain and translations.

The generated adapter preserves the original language. A Python model needs
Python3/NumPy and its source imports; an Octave model needs GNU Octave and its
source packages. Calling from the other language explicitly uses that original
runtime. The Octave adapter also uses Debian's `timeout` utility. Each batched
call executes the trusted saved source in a separate process with a 120-second
bound and private temporary binary64 files. No GX-TXT runtime is needed for
standalone-compatible sources. Explicit GX-TXT dependencies are refused at
generation; other imports, external files and environment are declared as
uncaptured dependencies. Stateful/nondeterministic models require their author's
review and are not certified reproducible by source capture alone.

LaTeX uses executable-function notation linked to the exact source SHA and lists
the accepted numerical coefficients/units; arbitrary source is not symbolically
translated. Original source license notices remain embedded verbatim. Generated
adapter licensing does not relicense the user's scientific source. Each source
is limited to 1 MiB UTF-8, with the existing 2 MiB generated-artifact limit.


The Fit menu exposes
registered declaration, selection and cancellation actions through the normal
viewer command/dispatch registry. Preview submits an asynchronous Job. A
completed preview is adopted only if its source/settings/row mask still match;
all owned resources are copied through CORE to the original Workspace. The Job
keeps its independent retained result. Acceptance and History remain explicit.

`registeredPreviewReference(document_id, source_curve_id)` / Script
`registered_preview_reference` produces the pinned preview reference from a
retained Workspace, including an imported Workspace with a new owner. The
Script `registered_accept` operation returns the existing durable result
reference. Exact source/parameter identity, metadata publication, templates,
Undo/Redo and fresh reopen share the established Fitter consumers.

Registered response shape is enforced by Numeric's `response_shape=column`
contract: a one-dimensional vector or N-by-1 column is accepted; row vectors and
matrices are refused even when their element count equals N. Public ordinary
callback fitting retains its existing vector behavior unless this option is set.


Registered-model Jobs refuse stale completion, retain completed previews after
the originating GUI closes, and allow cancellation during callback execution. `registered_execution` retains the
actual run ID, Script/callable identity, source/declaration SHA, revision,
language, entrypoint and public consumer. Publication preserves this provenance.
New Job Workspace display names include the invocation ID to prevent repeated
or concurrent runs from colliding. Resource owners and result references use
Document IDs; no existing Workspace or scientific identity is renamed.

### Smoothing selection

For `smoothing_spline`, public preview/recipe options accept `smoothing_options`
containing `smoothing_selection` (`manual` default or `gcv`), explicit
`gcv_lambda_bounds`, `gcv_grid_count` (3..65) and
`gcv_refinement_evaluations` (0..64). Manual mode still uses the existing
`smoothing_lambda`, including zero. All computation belongs to public Numeric;
the Fitter sends bounded typed settings through its existing worker protocol.
The accepted result retains CORE statistical interpretation, exact Numeric model
state and complete bounded search receipt. Recipe replay works through both real
Python and Octave Script Bridge jobs; saved Workspace controls default to manual
when absent in historical records. `result_info` exposes the same retained facts.
The actual predictor unit, including X(Y) or radial angular units, is supplied to
CORE for lambda units. No source rows, scientific IDs or original data are renamed.

## Explicit logarithmic response fitting

The Fit → Logarithmic fitting action delegates to CORE Dataset Transform
`log_variables`. It creates a separate Dataset retaining the original columns,
exact original row ordinals, positive same-unit references and source SHA. Y is
transformed by `ln(Y/Yref)`; optionally X is transformed by `ln(X/Xref)`. These
columns have unit `1`. This changes the residual objective to additive log-space
errors. Merely displaying logarithmic axes does not perform this operation.

Accepted fits retain both axes' `logarithm_lineage`. CORE receives the oriented
response transformation: Y for Y=f(X), X for X=f(Y). Recipe validation checks the
current normalization/lineage as well as source bytes. Named templates follow a
real column rename only when original/logarithmic status, base, reference, unit
and inverse eligibility agree. Original scientific identities remain immutable.

`::GX::DatasetCurveFit::resultRetransform reference dataset_id`, registered as
`DATASET_CURVE_FIT_API_v1/result_retransform(reference, dataset_id)` in Python and
Octave, publishes a separate HDF5 Dataset from an accepted durable result. It
uses exact retained geometry or captured prediction centers/bounds; it does not
refit. One Numeric call receives owned binary resources through shared CORE
transport. The canonical managed-column writer publishes the result create-only.

Columns are `query`, `median`, and eligible `mean`, `lower`, `upper`. The stable
`median` ID is labelled by CORE as either conditional median (declared Gaussian
log errors) or back-transformed fitted value. The optional mean is a Gaussian
log-variance plug-in estimate, not an unbiased finite-sample estimate; it excludes
variance-estimation uncertainty. Unavailable columns are omitted, with their
reasons retained in `curve_fit.statistical_results.physical_retransformation`.
Exponentiated mean-confidence limits concern the conditional physical median;
future-observation limits retain their pointwise prediction target. Physical
response units are restored; a log predictor remains dimensionless.

`curve_fit.log_result_reference`, `curve_fit.logarithmic_source`,
`curve_fit.retransformation_coordinates`, resource SHA, column identities and
actual transport counters record the producer chain. Stale result owners,
changed normalization, uncertified modified log coordinates, nonfinite physical
inverses and existing Dataset IDs refuse. Old results without a captured log
response cannot acquire a fabricated inverse. GUI creation/publication shows
only the new source initially; prior sources/fits remain stored and explicitly
hidden. Workspace restore preserves their visibility and scientific provenance.
## Retained linear influence

Preview/recipe option `influence_diagnostics` is an explicit boolean, default false.
It is supported for ordinary or response-weighted linear/polynomial fits in Y(X)
or X(Y), within Numeric's one-million-row / 128-coefficient / 512 MiB estimated
workspace limits. A Session-owned Workspace is required. Unsupported nonlinear,
registered, geometric, radial or orthogonal models refuse the request explicitly.
The existing fit computes the diagnostics once using its original factorization.

`::GX::DatasetCurveFit::resultInfluencePage reference start count` and Script
`result_influence_page(reference, start, count)` read an accepted result without
fitting. `start` is zero based; `count` is 1..512, clipped at the last row. The
versioned `FITTER_INFLUENCE_PAGE_v1` result includes public CORE `meaning` and three
typed pages: `diagnostics` (seven float64 columns), `input_rows` (uint64 one-based
Numeric input positions), and `source_rows` (uint64 original source ordinals).
Each Script page has `values`, `columns`, `dtype`, `start`, `row_count`,
`total_rows`, and `source_sha256`; Tcl pages expose owned little-endian bytes.
Empty final pages retain their declared types. No arbitrary resource paths are
accepted. Do not reinterpret Numeric input positions as Dataset ordinals.

Diagnostic column identities are `leverage`, `deleted_residual`, `loo_prediction`,
`studentized_residual`, `cooks_distance`, `deletion_available`, `scaled_available`.
Their labels, response units, coordinate system and availability rules come from
`STATISTICAL_RESULT_SEMANTICS_API_v1`. LOO predictions undergo the same explicit
response-translation inverse as the fitted curve. NaN and the availability masks
remain intact. CORE's 2p/n and 4/n review flags are not hypothesis tests, outlier
probabilities, or instructions to delete observations.

Accepted provenance retains `statistical_results.influence` and three owned
resources (`influence_resource`, `influence_input_rows_resource`,
`influence_source_rows_resource`). Resource metadata binds the bounded Numeric
receipt, original source and exact fitted training-row SHA. Validation checks
shape, role, canonical columns and captured CORE meaning. Recipe replay, templates,
Workspace/History and ordinary fit publication retain this additive information;
historical results without diagnostics remain readable.

The Results → Linear influence dialog reads bounded pages, displays the full CORE
qualifications and selects an exact original source row for review. CORE lookup
also locates observations outside the display sample. Selection checks source
identity/content/schema, persists the exact mask and draws a linked marker; it
never edits scientific source data or automatically refits/removes an observation.

## Retained parameter bootstrap

Preview/recipe option `bootstrap` is empty by default (off). A nonempty dictionary
uses public CORE `bootstrapSettings` / Script `bootstrap_settings(settings)`:
`method=pairs|residual|parametric_gaussian`, `replicates=1000`, `seed=1`,
`confidence=.95`, `max_seconds=60`. The full bounds and inference contract are in
[Parameter bootstrap](PARAMETER_BOOTSTRAP_v1.md). Recipe validation checks these
settings before execution. A Session-owned Fitter Workspace is required.

Fitter supports linear, polynomial, exponential, power-law, Gaussian, composed
regional, formula and registered Python/Octave scalar-response models in
Y(X)/X(Y). Registered refits run in their supervised one-thread Job with the
captured callback solver/version and exact predictor hashes. Older fitted
records without those identities remain readable, with bootstrap unavailable.
Radial, orthogonal and geometric requests refuse explicitly. The existing worker
keeps the exact solver predictor/response coordinates before display translation
inversion, then calls public CORE plan → Numeric refits → CORE interpretation.
It never reconstructs inputs by undoing/reapplying a rounded translation.

`::GX::DatasetCurveFit::resultBootstrapPage reference start count` and Script
`result_bootstrap_page(reference,start,count)` return `FITTER_BOOTSTRAP_PAGE_v1`,
version 1, with validated `meaning` and three typed pages: `parameter_samples`
(float64, B-by-P), `replicate_status` (uint8, B-by-1), and `replicate_seed`
(uint32, B-by-1). Start is zero based and count is 1..512, clipped to the remaining
trials. Each page exposes the same values/columns/dtype/start/row_count/total_rows/
source_sha256 fields as influence pages; Tcl uses owned little-endian bytes.
Empty pages retain dtype and shape. Reading never runs a fit.

Accepted provenance carries `statistical_results.bootstrap`,
`bootstrap_parameters_resource`, `bootstrap_status_resource`, and
`bootstrap_seed_resource`. Each resource binds the exact Numeric receipt SHA,
original source SHA and retained training-row SHA. Validation checks size, type,
column order, role and reinterpreted CORE meaning against the captured training
result. Missing or mismatched resources cannot validate as complete results.

The default-off setting is per source in Workspace/History and transfers through
recipe replay and named templates. Ordinary fitted-curve publication retains
meaning and resource references; Script pages permit separate typed trial Dataset
publication through the existing CORE Dataset Publication API. Old results without
bootstrap remain readable and do not acquire invented inference. The host-only
settings and readonly Results commands use the ordinary command registry.

## Retained profile likelihood

Preview/recipe option `profile` is empty by default. Explicit settings use public
CORE `profileSettings`: canonical `parameter_id`, finite `search_lower` and
`search_upper`, positive `initial_step` and absolute `parameter_tolerance`,
`confidence` (default .95), `max_refits` (4–256, default128), and `max_seconds`
(default60). Read [Profile likelihood](FIT_PROFILE_LIKELIHOOD_v1.md) for the
Gaussian objective, local search, boundary and failure qualifications.

Supported Fitter models are exponential, power-law, Gaussian, components,
regions and declared formulas with independent scalar Gaussian response errors,
in Y(X) or X(Y). The model must retain its native nonlinear-fit identity.
Orthogonal, covariance-whitened, registered callback and other unsupported
estimators refuse explicitly. Profile limits use the displayed model's fitted
parameter coordinates, including declared translations. The worker retains exact
solver inputs before translation inversion and never repeats the original fit.

**Fit → Profile likelihood settings…** saves future search controls per source.
**Results → Profile likelihood…** displays the shared CORE report and all bounded
trials, with physical parameter units and numerical status. Updating controls
does not change an accepted result. Workspace, History, exact recipes and named
templates retain the controls; a new explicit preview or recipe replay executes
the search. Old fits without profiles remain readable.

Tcl `resultProfilePage reference start count` and Script
`result_profile_page(reference,start,count)` return `FITTER_PROFILE_PAGE_v1`,
version1: validated `meaning`, `trial_values` (float64,N×4: parameter value,
weighted SSE, likelihood ratio, direction), `trial_parameters` (float64,N×P in
canonical parameter order), `trial_status` (uint8,N×1), and
`trial_messages_utf8` (JSON string containing all bounded trial messages).
Start is zero based; count must be1–256. Pages clip to remaining rows and preserve
empty array dtypes/shapes. Reading runs no numerical fit. CORE
`numeric_data_fields` supplies column units, identities and status definitions.

Accepted provenance retains `statistical_results.profile` and four owned
resources: `profile_values_resource`, `profile_parameters_resource`,
`profile_status_resource`, `profile_messages_resource`. Each binds the Numeric
receipt, original source and retained training-row SHA. Validation also checks
search settings, coordinate orientation/translation, resource owner/content,
dtype, shape, order and parameter identities. Canonical fitted-curve publication
retains those references and the shared interpretation; Script jobs can publish
trial columns with CORE `publication_metadata`. Profile intervals remain
separate from Wald intervals. An open search limit does not prove global
unboundedness, and an unfinished search does not provide nominal confidence
limits.

## Accepted nested-model comparisons

Accepted pairs also expose `::GX::DatasetCurveFit::resultNestedF reducedReference
fullReference` and Script `result_nested_f(reduced_reference,full_reference)`.
These validate durable references and return the reusable CORE nested-F
interpretation. See [Nested-model F test](NESTED_MODEL_F_TEST_v1.md). Comparison
uses captured facts and never refits or alters accepted records.

## Accepted parameter Datasets

`::GX::DatasetCurveFit::resultParametersPublish references datasetId` and Script
`result_parameters_publish(references,dataset_id)` publish one row per accepted
fit through Dataset Publication v2. Supply 1..64 distinct durable result references
and a new public Dataset ID. The result is the ordinary publication receipt;
Script Jobs record the committed Dataset in their publication journal.

The create-only HDF5 table has eight string identity columns: `result_id`
(`document_id/fit_curve_id`), `document_id`, `fit_curve_id`, `source_curve_id`,
`source_kind`, `source_identity`, `accepted_name`, and `model`. For each of 1..128
scalar parameters, prefix `p001`, `p002`, etc. has float64 columns `_estimate`,
`_standard_error`, `_ci_lower`, `_ci_upper`, `_confidence`, and string columns
`_value_status`, `_se_status`, `_ci_status`, `_role`. Estimates, errors and bounds
use the exact parameter unit; confidence and text use unit `1`. Every value/status
is a projection of public CORE `parameterRows`; missing numeric values are NaN.

Structured metadata `curve_fit.parameter_dataset` has schema
`gxtxt.fitter_parameter_dataset.v1`, version 1, `row_semantics=independent_accepted_fit`,
the `coefficient_space`, `parameter_columns` mapping each ordinal prefix to its
canonical parameter ID/unit/order/field IDs, and zero-based `rows`. Each row binds
its durable reference, name, full CORE parameter rows, original source/selection/
measurement identity and retained model/translation/physical formula where present.
`analysis.statistical_results` retains validated training meanings under `fit_1`,
`fit_2`, etc. Real source Dataset IDs also enter canonical publication lineage.

All selected records are validated before opening the writer. Model identity,
parameter order, units and coefficient-coordinate contracts must match. Composed
and regional definitions use the retained declared expression and bindings;
registered models use saved source/binding SHA. Different fitted values, source
filters and per-row fixed/free roles are allowed. Full per-row model states remain
retained. Translated parameters are not silently converted to physical coefficients.
Missing scalar parameter rows, duplicate/stale references, incompatible models and
ID collisions refuse. Writer failures use the existing publication abort owner.
No model execution, statistics calculation, accepted-record edit or History change
occurs. Historical accepted results can publish when their existing CORE meaning
and provenance validate; recipe replay provenance is not required.

The Results chooser uses shared typed fields and captured durable references.
Opening or cancelling it creates no Dataset. Workspaces with more than 64 accepted
fits can select bounded subsets through the public API.

## Independent family fitting

`familyMembers datasetId variableId` / Script `family_members(dataset_id,variable_id)`
discovers up to 64 finite numeric or text members in source encounter order through
CORE Table Stream/Graph Series. Its `FITTER_FAMILY_MEMBERS_v1` result includes
`api_version=1`, Dataset/Variable IDs, dtype, exact `members`, `source_identity`
(Dataset ID, SHA256 and schema identity), and `scope=dataset_before_active_filters`.
Integer member identities, including int64/uint64, are decimal strings in Script
results; clients must preserve them. Numeric-looking text remains text. Discovery
is bounded; explicit member lists can select a subset from a larger Dataset.

`familySourcesCreate handle variableId members` adds 1..64 distinct independent
sources to a loaded canonical Dataset. Each selected member replaces an existing
equality filter on that same Variable; every other source predicate remains.
Different members retain their own X grids. Source/schema changes, mismatched row
dimensions, transformed unmaterialized sources and empty/insufficient members
refuse. A failed member removes only newly added sources and restores the previous
active source. Source counter gaps remain valid scientific identities.
`FITTER_FAMILY_SOURCES_v1` reports `source_curve_ids`, `{member_value,source_curve_id}`
mappings and `fit_semantics=independent_per_member`. This operation does not fit,
accept or publish. GUI **Fit → Independent family sources…** uses this owner,
then existing selected-source Preview and named Accept. One History step owns the
source addition; Workspace reopen and Undo/Redo preserve canonical IDs with gaps.

`familyRun encodedRecipe variableId members workspaceName` / Script
`family_run(encoded_recipe,variable_id,members,workspace_name)` validates a saved
recipe and creates a new uniquely named Workspace. It explicitly fits all rows
matching the remaining source filters and each selected member, clearing prior
row picks/regions. Every independent preview must succeed before any acceptance.
The `FITTER_FAMILY_RESULT_v1` result contains `api_version=1`, `document_id`,
Dataset/Variable IDs, `fit_semantics=independent_per_member`, the explicit
`selection_policy`, and member/source mappings with durable accepted `reference`s.
Use `result_parameters_publish` to publish these results explicitly. Shared/global
parameters are a separate family-model contract. Registered callbacks require
their supervised asynchronous workflow and are explicitly unsupported here.

## Joint global family workflow

`globalFamilyRecipe encodedFitterRecipe familyVariableId modelId config scope` /
Script `global_family_recipe(encoded_fitter_recipe, variable_id, model_id, config,
scope)` converts a valid Fitter source recipe into the public
[`CURVE_FAMILY_API_v1`](../../plugins/modules/curvefit.family_global/CURVE_FAMILY_API_v1.md)
recipe contract. `scope` must explicitly be `complete_canonical_dataset`.
The original canonical X/Y bindings and physical units become the family model's
X/response inputs; the selected numeric Variable supplies physical family values.
Loaded source filters, point picks, regions and display translations do not limit
this explicitly selected whole-Dataset operation. An unmaterialized source
transform or stale scientific fingerprint is refused. Capture/conversion changes
no source, accepted record or Fitter History.

Use the family API's `recipe_validate`, `recipe_run` or supervised `submit`, then
`job_result`, `results` and `result_info`. That owner supplies shared/local/fixed
mapping, one joint covariance/free-rank inference, canonical parameter/prediction
Datasets, exact commit receipts and durable result files. Fitter does not convert
a global solution into independently accepted member fits.

GUI **Fit → Global family fit…** uses shared forms to choose the physical family
Variable and callable model, explicitly select the complete Dataset, then review
parameter scopes, expanded initial/bound/fixed vectors and solver controls. A named
supervised Job keeps the GUI responsive. On completion, CORE's parameter/global
reports open; **Results → Global family results…** reopens retained results after
Session/Workspace reopen. Table actions require the current Dataset payload SHA
to match the selected result's commit receipt; a later replacement is disclosed.

### Smoothed source preprocessing

The registered `smooth_source` command opens **Fit → Smooth into a separate
Dataset…** for loaded canonical Dataset curves. Savitzky–Golay and LOWESS/LOESS
use the existing public Numeric owner through CORE Dataset Transform
`smooth_curve`. Programmatic clients use `DATASET_TRANSFORM_API_v1` in either
Script language, then the existing Fitter Dataset-source and fit operations.

Original columns and rows remain available alongside smoothed Y, removed
component and exact source ordinals. Active Dataset filters apply; fit rectangles
do not. Edited geometric curves require explicit materialization first. The form
binds the source, loaded axes and SHA; changing them requires reopening it.

Recipes freeze `source.smoothing_lineage`. Validation checks current ancestry;
templates preserve affected axes and captured smoothing settings and cannot
silently switch between raw and smoothed inputs. Accepted results validate source
lineage against the CORE statistical context. Normal Workspace reopen preserves
both original and derived sources without repeating smoothing or fitting.
CORE qualifies inference after correlated preprocessing; no module computes its
own substitute uncertainty or likelihood policy.

## Safe physical-unit formulas

Select `formula` and open **Fit → Safe formula**. The expression uses `x` for
the independent axis (physical X for Y(X), physical Y for X(Y)). Enter named
parameters, initial values, optional bounds/fixed flags and units. Blank parameter
units request unique CORE dimensional inference; initial values and bounds then
use the displayed canonical units. Validate before fitting. The constructor
rejects unsafe syntax, ambiguous dimensions and invalid domains. Dimensional
variable powers require an explicitly dimensionless base. Affine/semantic units
require an explicit source conversion. Coordinate translations must be zero.

The GUI delegates to [Numeric's safe formula constructor](FIT_FORMULA_v1.md).
`formula_recipe` in the existing fit options carries its five-field recipe,
restricted here to one predictor named `x`. Recipes, templates and Workspace
state retain it. `recipe_capture`, `recipe_validate`, `recipe_run`, `result_info`,
`result_export` and parameter publication expose the same model to both Script
languages. A template must preserve the exact source units; changing an axis
label cannot perform a conversion. Solver controls, response/XY uncertainties,
prediction and supported parameter bootstrap use the existing native expression
model. Original formula text is shown; the frozen effective expression includes
unit-scale conversions and drives evaluation, derivatives and standalone exports.

## Retained result queries

`resultQuery` / `resultInverse`, also exposed as `result_query` / `result_inverse`
in both Script languages, evaluate immutable accepted results through Numeric.
See [the complete public contract](FITTER_RETAINED_QUERIES_v1.md) for exact query
limits, physical frames, CORE differential units, historical domains, local-root
limitations, explicit availability and the read-only GUI consumer.

New accepted output also exposes `result_info.output_domain` and exact published
`fit_query` / `is_extrapolated` columns. The [retained-result contract](FITTER_RETAINED_QUERIES_v1.md#accepted-output-domain-flags)
defines closed training envelopes, physical/normalized coordinates, display style,
CSV/Dataset persistence and historical unavailability.

## Preprocessing receipt and scientific report

`result_info` includes the versioned `preprocessing` receipt.
`result_preprocessing_rows(reference, stage, start, count)` returns bounded exact
uint64 identities; `result_report(reference)` returns the standalone scientific
report using CORE interpretation. The [full contract](FITTER_PREPROCESSING_v1.md)
describes original/filter/finite/selected/model counts, exclusion sets, coordinate
lineage, sorting, closure-node policy, publication and historical availability.

## Model documentation cards

`model_cards()` returns read-only `gxtxt.fitter_model_card.v1` records for all
Fitter model choices, including equations, parameter meanings/units, domains,
initialization, solver assumptions, uncertainty availability and extrapolation.
See [the public records and complete cards](FITTER_MODEL_CARDS_v1.md).
The Viewer’s Fit → Model documentation action uses the same records.

## Transfer an accepted model to Curve Workbench

**Results → Transfer selected model to Workbench…** and the Script operation
`result_workbench(reference, workspace_name)` create an independent Workspace
with exact supported primitives or explicitly sampled geometry. No fitting is
performed. The complete scientific model, resources, parameter domain, units and
provenance are retained separately from editable geometry. See [transfer support
and approximation limits](FITTER_WORKBENCH_TRANSFER_v1.md).

## Derived physical properties

Evaluate named parameter expressions with full correlated covariance, physical
units and explicit unavailable states through the public CORE/Numeric APIs.
Fitter exposes linear thresholds, exponential characteristic intervals, regional
knees and custom expressions in **Results → Derived physical properties…**.
Use **Evaluate properties**, review the report, then **Publish evaluated result**
to create a Dataset from that captured receipt without refitting.
See [declarations, scientific assumptions and Script operations](DERIVED_PHYSICAL_PROPERTIES_v1.md).

## Interpreting a fit

The [common fitting errors guide](../guides/COMMON_FITTING_ERRORS.md) gives
worked numeric examples of model choice, extrapolation, covariance, absolute
versus relative uncertainty, transformed response and interpolation/ODR.
[Bayesian MCMC availability](BAYESIAN_INFERENCE_AVAILABILITY.md) describes the
current public provider status without implying a posterior sampler exists.

## Physical plausibility review

`plausibility_definitions(reference)`, `result_plausibility(reference, rules)`
and `result_plausibility_publish(receipt_utf8, dataset_id)` expose retained
parameter review and create-only publication. Tcl entrypoints are
`plausibilityDefinitions`, `resultPlausibility`, `resultPlausibilityPublish`;
Script text receipts use `resultPlausibilityPublishText`. See
[CORE meaning, inputs and persistence](PHYSICAL_PLAUSIBILITY_v1.md).

## Advisory source model suggestions

Tcl `sourceSuggestions key scope options references` inspects a live source;
`datasetSuggestions sourceRequest options references` uses the canonical Curve
Source API without creating a Workspace. Python/Octave operation
`dataset_suggestions(source_request, options, references)` returns typed CORE
interpretation, report and an opaque source receipt.
See [the source model suggestion contract](MODEL_SUGGESTIONS_v1.md).

## Full observation covariance binding

Linear and polynomial functional previews accept a `covariance` option with
Dataset/Variable identity, explicit original-row correspondence, source response
identity, scale semantics and singular policy. The normal preview/accept/owned
resource/statistical result/recipe path is reused. Full covariance is mutually
exclusive with independent measurement weights. The ordinary model identities
and stable polynomial evaluator remain unchanged.

See [the complete covariance binding contract](FITTER_COVARIANCE_v1.md) for
units, exact row selection, constraints, availability and Python/Octave replay.

## Implicit equation fitting

`preview key implicit options` requires `implicit_recipe` and `implicit_branch`
as defined in [Implicit equation models](IMPLICIT_EQUATION_MODELS_v1.md).
`orientation` is `y_of_x` or `x_of_y`; formula predictor IDs remain physical
`x,y` with the Dataset X/Y units in either orientation. Omitted translations
default to off; nonzero or automatic translation is refused. The branch
response index must match the selected orientation. Output size is 2–256.

Retained residual pages have columns `source_x`, `source_y`, `equation_value`,
`equation_residual`. Their CORE meaning is `implicit_residual` with
`implicit_algebraic` geometry. Algebraic and physically normalized objectives
are distinct from vertical residuals, measurement sigma and ODR. The common
CORE result governs all covariance/inference/reporting; no private statistics
are added by Fitter. R-squared and ordinary response-likelihood ranking are
unavailable. Independent Gaussian equation errors with estimated variance can
permit conditional local parameter intervals; unspecified noise cannot.

The existing accept, result query, recipe, export, parameter Dataset and
Workbench transfer operations retain complete equation/branch identities and
owned resources. Implicit retained queries accept 1–64 values; their physical
slope is dY/dX even when the response is X. Missing roots remain unavailable;
curve construction refuses missing samples. Workbench representation is sampled
and preserves the original model separately. See the linked guide for rejected
measurement/preprocessing/inference combinations and bounded solver policies.
The registered GUI command is `implicit_settings`; persistence stores
`implicitRecipe` and `implicitBranch` without changing historical identities.

## Joint complex response fitting

The `complex_response` model uses ordered physical channel formulas and explicit
Cartesian or polar observation bindings. `complex_recipe` and `complex_data`
carry the model, display projection and shared/per-observation Cartesian
covariance. Physical source-row counts remain distinct from CORE component counts.
Existing recipe, query, export, residual, publication and Script operations preserve
the complete model and owned scientific resources. See the
[complex Fitter contract](FITTER_COMPLEX_v1.md) for fields, units, original-row
mapping, covariance limits, unavailable inference and GUI/persistence commands.


## Physical surface workflow

The same public API exposes a separate `dataset_surface_fit` Workspace/Viewer
for canonical XYZ point rows or Y-by-X response matrices. `surface_create`,
`surface_preview`, `surface_accept`, `surface_reference`, `surface_info`,
`surface_query`, `surface_export`, `surface_report`, `surface_residual_page`,
`surface_publish`, `surface_plot`, `surface_recipe_capture` and
`surface_recipe_run` are registered for real Python and Octave Jobs.
See [the complete surface lifecycle contract](FITTER_SURFACE_v1.md) for exact
Tcl/Script signatures, source units/dimensions, public managed resources,
CORE interpretation, explicit model sampling and persistent 3D rendering.

## Digitizer uncertainty provenance

Measurement and covariance bindings retain the producer's exact original point,
calibration/image and numerical state resources. Public CORE controls independent
sigma/XY ODR/full-response covariance eligibility. Fitter verifies axes, units and
source rows before computation and validates captured bindings on retained results.
See [the shared Digitizer contract](DIGITIZATION_UNCERTAINTY_v1.md).
