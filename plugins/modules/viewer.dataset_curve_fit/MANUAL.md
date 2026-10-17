# Dataset Curve Fit

## Finding controls and scientific guidance

The left inspector has eight existing panels grouped under **Data and selection**,
**Models and fitting**, **Results and publication**, and **Samples and presentation**.
Click a panel heading to collapse or expand it. **View → Panels / Configuration…**
sets each panel to visible, collapsed or hidden, using User defaults and Session
overrides. A panel's visibility does not remove its data or disable its methods.
Scrolling remains local to the inspector; the graph and results keep their own area.

The top menus group the existing advanced methods:

| Menu | Category | Purpose |
| --- | --- | --- |
| Fit | Models and fitting | Model cards, initialization, solver, specialized models, families and templates |
| Fit | Measurements and uncertainty | Translation, measurement assumptions, full covariance, bootstrap and profile settings |
| Fit | Advanced methods and preprocessing | Smoothing, baseline and logarithmic response preparation |
| Results | Measurement and uncertainty results | Covariance, parameter correlation, solver and interval evidence |
| Results | Model comparison and diagnostics | Comparison, linked residuals, influence, retained queries and physical review |
| Results | Results and publication | Scientific report, canonical Datasets, family results, Workbench transfer and exports |

The action names used below remain the labels within those categories. Preview
and Accept remain in the Fit menu with F5 and F6. Model controls show applicable
fields while retaining entered settings for other models. Hidden panels leave
these registered menu commands available when their scientific preconditions hold.

**Help → User Manual…** and **F1** open this independent rendered guide. Start
with [Common fitting errors](../../../docs/guides/COMMON_FITTING_ERRORS.md) for
method selection and interpretation. The complete [Statistical Result Semantics
reference](../../../docs/api/STATISTICAL_RESULT_SEMANTICS_API_v1.md) explains all
registered interpretation operations, units, unavailable states and inference
assumptions. The [Numeric API reference](../math.numeric/NUMERIC_API_v1.md)
documents the actual calculation contracts and Python/Octave access. An available
numeric estimate does not imply a justified confidence interval or physical model.

Select an accepted fit and use **Results → Query selected model and derivatives…**
for exact physical queries, slopes, differential resistance where units permit,
and explicit local inverse brackets. Read the [query guide](../../../docs/api/FITTER_RETAINED_QUERIES_v1.md)
for domain, extrapolation, historical-result and availability limits.


For a supported nonlinear scalar model, declare Gaussian errors in Statistical
assumptions, then use **Fit → Profile likelihood settings…**. Choose the canonical
parameter and explicit physical search limits, step and endpoint tolerance. Limits
refer to the fitted coefficient coordinates, including any declared translations.
Preview runs the constrained search; accepting saves its trials and interpretation.
Use **Results → Profile likelihood…** to inspect the saved interval and trial
objectives. Editing settings affects the next fit and preserves accepted evidence.
Read [Profile likelihood](../../../docs/api/FIT_PROFILE_LIKELIHOOD_v1.md) before
interpreting asymmetric, boundary or open results. An unfinished search has no
nominal interval; a finite search limit cannot establish global unboundedness.

For worked examples of extrapolation, overfitting, R²/chi squared, correlation,
log transformations and regression/interpolation/ODR, read
[Common fitting errors](../../../docs/guides/COMMON_FITTING_ERRORS.md).
[Bayesian MCMC availability](../../../docs/api/BAYESIAN_INFERENCE_AVAILABILITY.md)
is separate from ordinary covariance and parameter bootstrap inference.

Use **Fit → Initial parameters and manual curve…** to request model-aware
suggestions or edit named parameters with a live purple curve. Apply saves
initial values; Preview fit explicitly performs fitting. Bounds, fixed values
and exact selection remain enforced. See the [parameter controls and API](../../../docs/api/FITTER_PARAMETER_VIEW_v1.md)
for coordinate conventions, supported models and Script examples/contracts.
Built-in scalar models also support radial manual curves through the selected
polar frame, angular unit and branch. X/Y must have the same declared unit; a
negative predicted physical radius is refused.
Registered Python/Octave models use supervised evaluation Jobs for the same
manual controls, preserving declared units, bounds and fixed values. Their
automatic-initialization button explains that no rule is registered. Manual
evaluation remains cancellable and cannot be accepted as a fitted result.

Select an accepted fit and open **Results → Residual sequence diagnostics…**.
Choose retained row, canonical source row, predictor or predicted-response order,
then press **Describe retained residuals**. The report uses the complete retained
resources and does not fit again. Review its limitations: order-dependent
patterns do not establish independent errors or justify deleting observations.
See the [full contract](../../../docs/api/RESIDUAL_SEQUENCE_v1.md) for exact
zero, tie, nonfinite, lag and geometric-response policies.

An explicitly entered publication name is the **public Dataset ID**. Use letters,
numbers, underscores, dots or dashes, for example `my_fitted_curve`. Invalid IDs
and collisions produce an error; GX-TXT does not replace your ID with a technical
name. The same ID is retained in the Registry, Preview, Session, Plot Dataset and
saved Session. Cancel or Escape in the publication dialog creates nothing.

Built-in/Test samples are local deterministic test inputs. `sampleDescriptor`
describes their title, scientific meaning, axis labels, dimensionless units,
semantic roles, generator parameters and expected scientific result/tolerance.
Opening a sample and accepting a fit create no Session Dataset. Use **Publish
sample as Dataset...** to publish one explicitly with these schema and metadata
descriptors. Sample lineage uses `source_kind=builtin_sample` and
`source_sample_id`, without `source_dataset_id`. Fit CSV files and their metadata
sidecars preserve the same distinction. Publishing a fit includes its original
sample descriptor and fit statistics; publishing a real Dataset fit records the
real source Dataset ID and fingerprint. Schema, payload and metadata commit
together; a publication failure leaves no partial Dataset.

Open **Dataset Curve Fit** from the Viewer menu in a GX-TXT Session. If you open it from a Dataset context, that Dataset is offered first. Choose a Dataset and numeric X and Y variables, then select **Add Dataset curve**. Variable labels include units when supplied. Add retains earlier sources and their accepted fits. Each source has a stable workspace ID and owns its Dataset/Variable/filter binding and selection; built-in samples retain their separate source kind.

## Filter the Dataset

Add any number of conditions on any Dataset variable. Conditions are combined with AND. Numeric variables support `=`, `!=`, `<`, `<=`, `>`, `>=`, and inclusive `between` (enter `lower,upper`). Text variables support `=`, `!=`, case-sensitive `contains`, and SQL-style `LIKE` (`%` matches any span; `_` matches one character). No variable has a special family role.

Changing the Dataset, X, Y, or applied filters makes the loaded binding stale. Add the Dataset curve again before previewing or accepting. Historical accepted curves retain their frozen geometry and source descriptors and can be exported or explicitly published independently of the current chooser. The viewer checks whether the underlying Dataset or Session changed after loading.
Adding the new binding creates another source curve. It preserves accepted fits and their original source ownership. Activate a source in the workspace table to restore its binding and controls. Show/Hide applies to the selected source curves. **Fit selected curves** performs independent fits for the selected sources with the chosen model settings; **Accept all selected previews** accepts their independent local CORE curves. A failed batch preserves previous previews and accepted results.

Dataset display loading reports bounded source progress and keeps the event
loop active. **Cancel load** or Escape cancels the pending load, releases its
stream/native resources and preserves existing curves. Source-changing controls
are disabled during this operation and restored afterward. Finish the load or use Cancel load before switching or closing its Workspace.
The shared Workspace host refuses a transition while this operation is active.

## Select fit points and navigate

The blue curve is the immutable Native 2D CORE source. Red markers show selected data points. Click a point to select it. Shift or Control toggles a clicked point within the selection. Drag a rectangle to select points; the orange outline shows its extent while dragging. The **Rectangle** control chooses Replace, Add, or Subtract. Shift or Control while dragging adds, and Alt subtracts. **Remove last rectangle** reverses the newest rectangular selection block; **Clear selection** removes all selected points and blocks.

Rectangle selection operates on a separate CORE point set with the same display coordinates as the source curve. This keeps fit-point selection restricted to points inside the rectangle even when a connecting source segment crosses it. Native CORE supplies the ordered rectangle operations and manual point overrides. For a Dataset source, rectangles apply to all exact streamed XY rows and clicked display points map to their original row IDs. A separate bounded Numeric input contains every selected finite pair, independent of display reduction. Both training count and the exact selection descriptor accompany the scientific report; changing a rectangle invalidates the preview even if its display markers do not change. Save/reopen preserves rectangles and point overrides.

The canvas has numeric X/Y ticks and Dataset variable labels with units. Use the mouse wheel to zoom around the pointer, drag with the middle mouse button to pan, or choose **Reset view**. These controls change only the view, not data or selection.

## Preview and accept a fit

### Inspect linked residuals

Choose **Results → Residuals vs source coordinate** or **Residuals vs predicted
response**. The latter uses the physical fitted Y, fitted X for X(Y), or fitted
radius for radial fitting. Geometric projection residuals use their parameter
axis and explicitly refuse a single predicted-response interpretation. The
diagnostic panel scales its axes independently so small residual variation is
visible; the main geometric plot keeps its own equal-scale view.

Click a residual dot or select a residual table row to highlight the same original
observation in both plots. Inspection keeps the fitting mask unchanged. **Use
inspected row for fitting** explicitly selects that exact source row; changing a
selected-point fit invalidates its old preview. Selecting a source point also
locates its residual table page when a preview remains available. The table uses
exact retained values and original row IDs, including rows omitted from training
because their response weights were zero or missing. Display sampling is bounded
and preserves the Native2D sample's original offsets; it never changes the fit.

The chosen residual axis survives Workspace save/reopen. Changed source data
refuse linked inspection until the source is reloaded and fitted explicitly.

Choose **all** or **selected** fit points. Choose an output domain independently: **source** uses the sorted, distinct source X values; **range** uses minimum X, maximum X, and sample count. The original source order and repeated observations remain intact for fitting and residuals. Changing the output domain does not change fit points.

Basic response models are linear, polynomial (degree 1–12), exponential `a exp(b x)+c`, power law `a x^b`, and Gaussian `a exp(-0.5 ((x-mu)/sigma)^2)+c`. Polynomial degree is active only for that model. Nonlinear models expose initial parameter guesses in the displayed order; power law requires positive X and Gaussian width must be nonzero. Range fields are active only for a range output domain. Use a declared Script Library model for a custom executable response function; direct expression text is not an evaluator in this panel.
For Gaussian data, set the initial center near the observed peak and the initial width near its visible spread. A solver can report convergence at a poor local solution when the generic initial guess is far from the data; inspect RMSE and R² before accepting.

**Preview fit** uses the public Numerical API for fitting, evaluation, residuals, and fit statistics. The report shows a formatted formula, named fitted coefficients, training-point and full-source RMSE/R², and solver status. The table reads bounded exact residual pages with original source-row IDs. Previous/Next/First/Last navigate them. A dashed preview curve appears on the canvas. **Show residual panel** collapses or restores both residual plot and table; its adjacent size control changes plot allocation. Hiding it retains the result and never reruns fitting.

**Fit orientation** selects **Y = f(X)** or **X = f(Y)** for function models.
The latter fits physical X against physical Y, uses a Y output domain and reports
X residuals at source Y. The geometry stays in the original physical X/Y axes;
units and original Dataset row identity stay aligned. Formulas, parameter powers,
residual columns, CSV headers and published coordinate/data roles follow the
chosen orientation. Each source remembers its own orientation. Arc/Bézier use
**X=x(t), Y=y(t)** with normalized parameter output.

**R=f(theta) (experimental)** fits radius against angle while retaining physical
X/Y source and accepted geometry. **Radial settings…** captures that source's
fitting origin, theta-zero direction, CW/CCW direction, radian/degree unit and
explicit cut or continuous unwrap policy. Source angles must be ordered and
span at most one turn; ambiguous/nonmonotone contours require another branch or
Parametric mode. The origin cannot lie on the source. X/Y must use the same
declared physical unit. Selected points keep the full source's exact angular
branch. The output range is an angle interval in the declared unit; negative
predicted radii fail without replacing the previous preview. Residuals are
observed minus fitted radius at source theta, with original Dataset rows and
physical coordinates retained. Published X/Y stay physical coordinates with
their original units, and Dataset/CSV provenance freezes the fitting frame,
branch, sampling interval, topology and radial residual semantics. Each source
remembers its fitting frame independently of later canvas presentation changes.

**parametric_polynomial** fits independent polynomial X(t)/Y(t), using the degree
control. **parametric_spline** interpolates an ordered open or closed contour,
including loops that have several Y values at one X. **Parametric settings…**
opens the shared typed, scrollable form for open/closed/auto topology, row-order,
path-length or Dataset-variable parameterization, the logical parameter Variable
ID, optional user period and endpoint closure tolerance. A Dataset parameter
variable remains aligned through the same exact Source stream and training mask
as X/Y. It must be finite and strictly monotone in source order. A closed curve
without a repeated endpoint needs a user period exceeding its parameter span.
Auto detects repeated endpoints within the recorded tolerance. Closed splines
solve a genuine periodic cubic system, sharing model position, first and second
derivatives at the seam. Closed polynomial mode is rejected because it cannot
imply periodicity. Model output uses normalized t in [0,1]; source geometry is
preserved. Metadata and Session state retain topology and parameter binding.

Dataset display loading and exact Numeric staging yield at bounded CORE chunk
boundaries. Numerical fitting uses the public Parallel Execution coordinator's
file events and isolated worker environment. **Cancel operation** or **Escape**
cancels these phases; the previous preview, accepted curves and source remain
available. Cancel an active operation and wait for cleanup before closing or
switching Workspaces. Source/model/selection controls are held during the job.

**Reverse whole to new source** adds a local Dataset-backed source with complete
rows reversed. **Reverse span to new source** uses selected endpoint identities
to reverse the exact interval between them. All tuple columns, including text
and auxiliary variables, move together through the common Dataset Transform
authority. Repeated reversals compose as an ordered recipe. The original source
and its accepted fits remain available; no Dataset is changed or implicitly
published. The recipe, original row lineage and active source survive Session
reopen. Accepted results keep their frozen source recipe and scientific schema
fingerprints. Restoring changed content/calibration/schema requires explicit
reload rather than silently binding old scientific results to new semantics.

Arc and Bézier reports use full nearest-model geometric distance. Positive
residual lies left of the oriented tangent; a zero cross product uses a
nonnegative distance. A horizontal displacement from an endpoint therefore
remains visible in RMSE even when its Y component is zero. The table also shows
projected X/Y and normalized parameter, and the residual plot uses that parameter.
The report labels **Geometric RMSE** and **XY dispersion R²** explicitly. Geometric
R² compares squared projection distances with total XY dispersion around the
source centroid. Publication and CSV sidecars retain both residual and R²
definitions. Both published geometric axes are coordinates, with original units.

**Accept as new CORE curve** proposes an editable curve name. Choose **Accept named curve** to create a separate CORE curve. Cancel leaves the preview and History unchanged. Names contain 1–160 characters after trimming, with no control characters; Unicode is supported. The name is a display label, separate from the stable scientific curve ID. Accepted fits appear with that label, model, scope, fit size, statistics and a distinct color. Select a fit to show, hide, delete or export it. Several accepted fits can coexist.

**Accept all selected previews** presents one proposed name per source and validates every name before accepting the batch. Undo reverses one acceptance or the whole batch; Redo restores the same names and canonical IDs. Names survive save/reopen and explicit Dataset publication. Changing the active source or captured preview while the form is open requires reopening the form.

## Export and resume

### Fit independent members of a Dataset family

Load the Dataset with its X/Y variables and any common filters. Choose **Fit →
Independent family sources…**, select the family/group Variable, and choose
the members. Discovery shows the Dataset's members before filtering. The chosen
member replaces an existing equality on that same Variable; all other filters
remain active. Up to 64 members can be added together. Each uses its own actual
observations and X grid, without resampling or shared parameters.

The new sources are selected together. Review the model settings, use **Fit
selected curves**, then **Accept all selected previews**. The parameter Dataset
chooser below gathers the independent results. Source addition has one Undo/Redo
step. An insufficient or stale member leaves the original sources unchanged.
Exact integer member IDs and Unicode text are preserved through save/reopen and
Python/Octave Script Jobs. Materialize an edited source before family traversal.

### Publish accepted parameters as a Dataset

Choose **Results → Publish accepted parameter Dataset…**, select the accepted fits and
enter a new public Dataset ID. The chooser supports up to 64 fits. Each chosen
fit becomes one row, retaining its name, stable fit/source identities and model.
Matching model definitions, parameter order, units and coefficient coordinates
are required. Separate source filters and fitted values may differ; this records
independent results without pooling their observations or refitting.

Each parameter has binary64 estimate, standard-error, confidence-bound and
confidence-level columns, plus explicit value/uncertainty statuses and fixed/free
role. Missing inference is NaN with its CORE reason retained in metadata. Fixed
parameters keep their value and have no estimated uncertainty. Column groups
`p001`, `p002`, and so on map explicitly to the original parameter IDs and units.
Use the column labels or this mapping; the ordinal prefix does not rename a
scientific parameter. Coefficients retain their declared fitting coordinates;
the metadata preserves each fit's translation, physical formula and exact model.

The new HDF5 Dataset appears in the Session catalog and supports the normal table,
plot and Script APIs. It retains complete CORE meanings and original source
bindings. An existing ID, stale result or incompatible selection produces an
error before publication; existing data and accepted fits remain unchanged.
Cancel creates nothing. Dataset publication has its own lifecycle and is not
removed by undoing a local Workspace action.

**Export accepted fit CSV** writes the selected accepted CORE curve with `x_<X>` and `fitted_<Y>` columns from its original binding, plus source kind, Dataset ID or sample ID, model, fit scope, and CORE object ID as provenance. Its sidecar includes stable accepted/source curve identities. **Publish selected fit as Dataset…** publishes the selected historical accepted geometry with its frozen source labels, units and model provenance. The entered name/ID becomes the exact validated public Dataset ID; a collision names that ID and leaves the existing Dataset intact. These actions preserve each source's accepted-fit ownership.

The viewer saves Dataset bindings, filters, view, selected points and accepted fits in the Session Interactive Document. A missing or changed Dataset restores as a textual **missing/stale** source entry, alongside its independently restored accepted curves. Fitting is disabled for that entry. Restore the Dataset or update its schema, then use **Reload active source**. Reload keeps the workspace source ID, resets point selection and preview, and reads the current exact source; earlier accepted curves retain their original model and frozen provenance. A failed reload leaves the existing entry and accepted curves intact.

**Style sources…** applies shared RGBA/opacity, line width and pattern controls to selected sources without refitting. **Remove sources** removes selected local inputs and their previews, while retaining independently accepted curves. Those accepted curves can still be inspected, published, exported or deleted, and remain available after save/reopen even when every source has been removed.

Large reconstructible model JSON and parameter arrays stay in owned document resources. Reports show the resource identity, size and parameter count rather than loading complete arrays into GUI fields. Small models retain their inline coefficient reports. Published Dataset metadata and other documents keep their referenced scientific blobs alive during resource collection and document deletion.

The shared Curve Source and Dataset Transform APIs read and filter CSV/HDF5 and other supported canonical storage. Native extrema sampling bounds display memory; it preserves source-row identity and nonfinite gaps. Fit-all reads exact data through bounded native binary staging, independently from the proxy. Large accepted curves remain complete in Native CORE and persist as content-addressed Interactive Document resources. Explicit Dataset publication streams the complete curve and uses size-aware Storage Auto. The shared native C/Tcl adapter is installed under CORE; `GX2D_TCL_LIBRARY` can point to a development build. A compiler is needed only to build it. GNU Octave is required by the Numerical API worker.

## Scientific models and independent publication

The existing source filters, point/rectangle selection, immutable source, multi-fit visibility/deletion, zoom/pan, residuals and Interactive Document resume workflow remain available. The model list also includes circular arc, quadratic/cubic Bézier, PCHIP, natural cubic smoothing spline and Fourier series. Arc/Bézier preserve source sequence and use normalized parameter output in [0,1]; function models use source X or a regular X range. Output sampling is independent of the selected training points and supports resampling a small training curve to 1,000 points.

Circular arc reports center/radius/oriented interval; Bézier reports control points. PCHIP preserves shape without overshoot, rejects duplicate X and does not extrapolate. Smoothing lambda is reproducible: zero interpolates; increasing it penalizes curvature. Fourier accepts any positive order supported by the independent sample count/rank, with explicit or deterministic inferred period. Order 100 and 1,000 are supported with sufficient samples; coefficient metadata replaces huge expanded formulas. Model state and conventions are documented in [NUMERIC_API_v1](../math.numeric/NUMERIC_API_v1.md).

Parametric residual tables report signed full nearest-model geometric distance
and projected X/Y with normalized parameter. Function-model residuals use the
chosen independent axis: source X for Y=f(X), source Y for X=f(Y). Model state,
orientation, scope, filters, selected indexes, metrics, grid, degree/order/options
and producer version accompany explicit publication.

**Built-in / Test sample** is a fitter-local source. **Open sample in fitter** does not register a Session Dataset. **Accept as new CORE curve** creates only an independent fitter-local CORE curve. **Publish as Dataset...** explicitly publishes the current fitted output with stable fitted X/Y variables and full provenance through Dataset Publication API v2. **Publish sample as Dataset...** explicitly publishes the chosen built-in sample. Published Datasets appear in the normal Session Dataset workspace and can be plotted through Plot Dataset.

The bundled sample catalog includes exact/noisy arcs, quadratic/cubic Bézier, a monotone PCHIP step, noisy smoothing wave and DC+sine+cosine Fourier wave. These sources remain separate from imported Session Datasets and accepted CORE curves.

CSV export keeps the accepted curve's X/Y values and writes `<csv>.metadata.ini` with its frozen model/provenance and CSV hash. Large model state is streamed to `<csv>.model.json`; the sidecar records its relative filename and SHA-256 so the exported model is reconstructible independently of the Session. Small model JSON stays inline. The common File Publication API stages the complete CSV/model/sidecar bundle and rolls back original files on failure. Exporting an older accepted fit uses that fit's saved provenance. Interactive Document resume restores model controls, accepted fits, source kind and model state without publishing a Dataset.


## CAD workspace and native clipping

Source, preview, accepted-fit, selection and residual lines are clipped to the actual Native plotting viewport before rendering. Markers/text crossing the plot are omitted; scientific coordinates and fit input stay unchanged. Auto/X=Y, zoom, pan and resize share this authority. There are no cosmetic margin masks. If controls leave less than the minimum plot size, stale drawing is cleared. The resizable sidebar scrolls independently; plot margins follow the current font metrics.

Host service `DatasetCurveFit::fitPrimitive points family unit` delegates to existing Numerical parametric models and returns `definition`, `quality`, `working_unit`, `method=scientific_fit`, `numeric_api=NUMERIC_API_v1`, `approximation=1`. It accepts declared compatible length units and 3..65536 complete continuous points. Native2D maps Numeric parameters; this service does not publish or adopt an object. The Workbench controls source validation, Preview and explicit Accept.


## Shared native adapter

The Fitter loads the canonical CORE Native2D adapter. Complete-input policies,
physical conversions and viewport clipping share that owner with Curve Workbench.

## Remote X11 placement

The window requests shared bounded placement before mapping. Results, status,
residual rows and paging reserve space before the plot. Filter and residual
lists show fewer rows and retain normal keyboard/wheel scrolling. The residual
checkbox can free plot space while exact residual data stays retained.

## Layout and named Workspaces

Sources/Fit/Selection/Results/View group the existing actions. Preview fit and
Accept stay directly accessible. The resizable left panel contains Dataset/X/Y,
source collection, filters, model/parameters, selections, accepted fits, samples
and view/residual controls; scroll it without reducing the prominent right-side
Native2D canvas. The right residual/report region preserves exact paged residuals
when hidden. All numerical engines, parameter/domain/orientation semantics,
preview/accept, publication/export and selection/zoom/pan remain unchanged.

Workspace provides New/Open/Save/Duplicate/Rename/Close/Delete and the standard
Session Workspaces manager. This is the named Session Workspace around the
existing internal multi-source document, not another scientific data store.
It retains source/filter/model/selection/style state per source, active source,
accepted exact fit records/resources, presentation/residual state and notes.
Opening an explicit Workspace ID never selects the first Dataset match.
Version1/2 legacy documents remain available; saving an older document upgrades
its schema with the same Document identity and preserved metadata. Scientific
source changes/missing sources produce diagnostics while recoverable accepted
fits remain available. CORE owns lifecycle, resource remapping and portable backup.
## Panels, translation and History

The scroll controls have actual Tk ancestors inside the left viewport, so
clipping applies during scrolling. Preview fit and Accept fit are in the single
top Fit menu; factory keys are F5 and F6. All actionable commands contribute
stable configurable slots through CORE Configuration. View → Panels /
Configuration opens the same module editor as central Configuration → Modules.
Each of the eight panel categories can be visible, collapsed or hidden. User
defaults are inherited by Session overrides; there is no separate Workspace
panel registry. Hiding a panel preserves its scientific state.

Fit → Input translation offers AUTO (factory default), Manual and Off separately
for independent u and dependent v. AUTO examines every finite training value,
complete source value used for residual evaluation and functional output domain.
It uses zero for a strictly positive range; otherwise C = −minimum +
max(realmin, 32×eps(maximum absolute value)). Overflow or an unresolved positive
margin fails without accepting a fit. Manual uses the declared constant; it does
not silently force positivity. Off means zero. Model-specific domain validation
still applies. For X=f(Y), u is physical Y and v is physical X. Radial mapping
acts on theta/radius after the explicitly declared polar frame. Geometric models
translate physical X/Y; their dimensionless parameter remains unchanged.

All models are solved by the existing Numerical API. Physical output is
u=u_fit−delta_u and v=f(u+delta_u)−delta_v, with each inverse applied once before
Preview, Accept, CSV or Dataset publication. Coefficients and initial parameters
refer to fit-space. Residuals compare original-coordinate observations and
physical predictions. Each receipt records modes, actual constants, original and
transformed bounds, physical Variable IDs, original units, forward/inverse rules
and coefficient space. Accepted geometry and provenance remain frozen when the
user changes settings; Preview must be repeated before a new Accept/Publication.
Existing accepted records are restored without refitting or another inverse.

History uses CORE Scientific Recipe and the current Session Workspace. Sources,
selection, model/translation settings, Preview resources, accepted curves and
presentation are reversible local state. Undo/Redo retain the future; older-step
browsing is read-only until Return to latest or an explicitly confirmed restart.
The compact Description/History selector shares the footer. Workspace → Clear
History requires the latest idle state and explicit confirmation, with an
optional external Workspace backup. It preserves current scientific resources.
Published Datasets and external exported files have separate owners and remain
present after local Undo. Portable Workspace export/import carries the retained
Recipe and its owned scientific resources.

## Parameter results and statistical assumptions

Preview displays the equation followed by a table of named estimates, physical
units, standard errors and confidence limits. Select a row to read the reason
for an unavailable quantity. Results → Parameter correlation opens the matrix
for freely estimated parameters, with the exact parameter order and coefficient
space. A fixed parameter has no estimated uncertainty.

Fit → Statistical assumptions and intervals records the measurement error
assumption and confidence level for the active source. The default is unspecified:
covariance/correlation can be available while confidence intervals remain
unavailable. Independent Gaussian errors with variance estimated from residuals
permit Student-t intervals when the model is identifiable and other CORE checks
pass. Known absolute sigma requires actual inverse-variance input; selecting the
assumption alone does not create measurement uncertainties. Nonlinear intervals
are local approximations and marginal, not simultaneous intervals.

Changing an assumption invalidates the preview. Preview again before Accept.
Settings, interval method, statuses and numeric receipts survive source switching,
Workspace save/reopen, shared History and Dataset publication. Older Workspaces
without these fields reopen with unspecified noise and do not gain a confidence
claim. Script/API preview options are `noise_model` and `confidence`; reusable
calculation/interpretation APIs belong to Numeric and CORE, not the viewer.

The same settings dialog offers **No response interval**, **Pointwise mean
confidence interval**, and **Pointwise future-observation prediction interval**.
The latter includes independent future response noise. With known measurement
sigma, provide future absolute sigma; with relative training weights, provide
future relative precision. Unweighted estimated Gaussian noise uses the fitted
residual scale. These settings never create missing training weights or sigma.
Script/API options are `prediction_band` (`none`, `mean_confidence`, or
`new_observation`), `prediction_sigma` and `prediction_weights`. Future sigma or
precision may be a positive finite scalar or one value per query.

For linear, polynomial, exponential, power-law and Gaussian fits, the dialog also
binds a **Training measurement role** and **Training measurement column** from
the loaded Dataset. Choose response standard uncertainty (sigma) for absolute
measurement errors, or relative precision for relative weights. Sigma must be
positive and have a unit compatible with the response: Y, X for reversed fits,
or radius for radial fits. Only the unit scale applies to uncertainty; an affine
temperature offset is never added. Relative precision is dimensionless; zero
explicitly excludes a row. Negative precision and nonpositive sigma are errors.

The default missing-measurement policy reports an error. **Omit explicitly and
record rows** excludes nonfinite measurements from training, retaining their
original values and identities. Filters, source reversal and selected-point
fitting keep each measurement with its original row. At least two weighted rows
must remain and the chosen model must still be identifiable. Choose **No training
weights** to clear the column binding. Changing these settings invalidates the
preview; preview again before accepting.

Results → **Training measurement details** shows units, conversion, original and
used counts, omitted/zero-weight counts and CORE's statistical interpretation.
Weighted R-squared compares weighted residual variation with weighted centered
response variation; it does not establish that the physical model is valid.
The complete-source residual report remains a separate unweighted evaluation.
Workspace, History and published fit metadata retain the measurement binding,
original selected measurements and exact retained training rows. Other model
families reject this response-weighted option until their own contract exists.

Choose **Both-axis standard uncertainties (ODR)** to fit measurement errors in
both coordinates. The training measurement column supplies response sigma;
the separate independent-axis sigma column supplies predictor sigma. For Y(X)
these are sigma Y and sigma X; for X(Y) they exchange roles. Linear, polynomial,
exponential, power-law and Gaussian models support this option. Both columns
must have positive compatible physical units; each conversion uses its absolute
scale, never an affine temperature offset. Missingness applies to the pair:
explicit omission retains both original measurements and the excluded row.

ODR fits latent true predictor coordinates and minimizes the sum of squared
standardized corrections in both axes. It supports independent errors with
known absolute standard uncertainties; quadratic loss is required. Ordinary
response R² is not applicable. Parameter covariance and Gaussian intervals use
a local approximation after accounting for latent coordinates. Active bounds or
rank deficiency prevent an ordinary covariance claim. **Solver settings**
also applies to linear/polynomial ODR, including bounds, fixed values and
multistart. Linear initial order is intercept, slope; polynomial order is highest
power first. Blank linear/polynomial initial values use zeros. Pointwise bands
condition on a fixed true query coordinate; a future measured predictor's
uncertainty is not included.

Training measurement details explains this objective and both unit conversions.
The source residual panel separately evaluates response deviations at observed
coordinates. The accepted Document owns original and converted sigma values,
retained source rows, fitted latent coordinates, signed physical corrections
and normalized corrections. Workspace, History and Dataset metadata preserve
these resources. **Export accepted fit CSV** includes `.measurements.csv` and
`.orthogonal.csv` companions for ODR, with exact source indices and 17-digit
numerical values; the sidecar records their filenames and SHA-256 values. The
whole export uses the existing atomic file-publication bundle.

Preview draws interval boundaries. Accept, visibility, delete, Workspace and
History keep them with the fitted curve. Results → Response interval details
shows the full CORE interpretation and limits. Bands concern one query at a time;
they are not simultaneous confidence regions. Nonlinear bands use local
covariance propagation. Polynomial propagation uses the original stable scaled
basis while the parameter table retains physical coefficient identities.
Unavailable inference has an explicit reason and creates no boundary curve.

Published fits retain `fitted_x` and `fitted_y` and add `prediction_query`,
`prediction_mean`, `prediction_lower`, `prediction_upper`, `prediction_mean_se`,
`prediction_se`, `prediction_noise_sd`, and `prediction_available`. Query and
response are in original physical coordinates after inverse translation; reversed
fits use Y as query and X as response. Use `prediction_query` with these bounds
for a response plot. For ordinary Y=f(X) fits, shared Plot bands may use
`fitted_x`/`fitted_y` with `prediction_lower`/`prediction_upper`. Metadata retains
units, orientation, inverse transformation, source and CORE interpretation.
Original unavailable rows remain as NaN bounds with availability zero. Display
resources preserve gaps instead of connecting across omitted rows. For radial
fits, negative lower radii remain in scientific columns, with those Cartesian
boundary portions omitted and explained. Projected geometry and joint response
models need their own covariance model and remain explicitly unsupported by this
scalar-response interval API.

Compatibility fields such as `train_rmse`, `source_rmse` and `train_r2` come
from those same validated CORE records. Their `statistical_aliases` entries give
the quantity identity, sample role, unit, status and reason. A quantity without
a value carries NaN together with its explicit status. For geometric models,
the historical `train_r2`/`source_r2` names retain the XY dispersion score;
`train_geometric_dispersion_score`/`source_geometric_dispersion_score` expose the
same identity by name. This score is not centered response R squared. Workbench
primitive fitting displays the CORE labels, units and applicability directly.
New Workspace, Dataset and CSV metadata preserve and validate these aliases.
Historical results without CORE records remain unchanged and unvalidated.


### Native nonlinear solver report

Exponential, power-law and Gaussian fits use the Numeric Ceres backend and
its canonical model definitions. Results explain whether its stopping criteria
were satisfied. Open **Results > Solver diagnostics** for the exact tolerances,
limits, backend version, message, scales and bounds. The iteration-record count
includes the initial state. Convergence does not guarantee a global optimum.
A new unconverged preview must be corrected and fitted again before acceptance
or Dataset publication. Exact native model state accompanies accepted fits,
CSV/Dataset metadata and saved Workspaces.

Use **Fit > Solver settings** for native nonlinear models.
Choose LM or Dogleg, stopping tolerances, limits and loss. Bounds, fixed masks
and positive scales use space-separated values in the displayed parameter
order; blank vectors use defaults. Keep initial parameters in the Fit panel.
Settings belong to the current source/model and survive Workspace reopen.
Apply invalidates the current preview. Bounds are enforced by Ceres; robust-loss
fits do not receive ordinary least-squares confidence intervals.

**Starting strategy** in this form offers `single`, `explicit`, or `uniform`.
Single preserves the usual one-start fit. Other modes include the Fit panel's
initial values as start 1 and run 2–64 starts. Explicit mode takes additional
parameter rows separated by semicolons. Uniform mode takes finite lower/upper
starting ranges and an integer seed; optimizer bounds remain separate. Fixed
parameters keep their initial value in every start. The overall multistart time
limit bounds the complete set of trials; the per-solve limit still applies.

Results → **Solver diagnostics** lists attempted, converged, failed and unrun
starts, their initial/final values and objectives, the selected index, seed and
versioned generator. Numeric retains the lowest objective among converged
trials, breaking exact ties by original order, without fitting the winner again.
If none converged, a provisional finite result cannot be accepted. All-error
or expired-before-start runs report the recorded failure instead of a fit.
The strategy runs sequentially with one thread, uses no global random state,
and preserves its receipt in accepted model state, Workspace and CSV/Dataset
metadata. Replay needs the same inputs/settings and completed trial set; a time
limit or cancellation can prevent that completion. These finite trials cannot
establish a global optimum.


## Model components and fitted baselines

Choose **components** in the Model list, then **Model components…**, also
available from the Fit menu. Add Gaussian, Lorentzian or Voigt peaks, logistic
responses, exponential decays, Arrhenius or series-resistance Shockley models,
and an optional constant or linear baseline.
Each tab shows its equation, parameter meanings, units and scientific limits.
Parameter controls and scientific notes scroll together; Apply and Cancel remain visible when
the dialog is resized.
Review initial values; blank bounds retain the component domain. Gaussian width
is sigma, while Lorentzian width is HWHM. Heights may be negative for dips.
Voigt uses integrated area, Gaussian sigma and Lorentzian HWHM. Its area has
units Y times X; it is not the peak height or total Voigt FWHM. Logistic is a
continuous-response sigmoid, distinct from binary logistic regression.

Add multiple decay cards for a multi-exponential model. Their positive lifetimes
have X units and amplitudes refer to predictor zero. Review distinct starting
lifetimes and optional bounds; equivalent component permutations are not silently
sorted or renamed. Equal lifetimes can make separate amplitudes unidentifiable.

Arrhenius needs positive absolute temperatures in K and fits the original
response. Its activation-temperature parameter is Ea/R in K, not energy.
Shockley needs V/A axes and fits saturation current, effective thermal voltage
n*k*T/q and series resistance; it does not separate n from T or include reverse
breakdown, shunt leakage or self-heating. Both cards require zero translations
on both axes. Convert source values explicitly before binding; use an explicit
baseline component if the physical model calls for one.

Enter the same optional shared name to tie parameters across components. Their
units, initial values and constraints must agree. **Fixed** holds that parameter
at its displayed initial value. Apply the settings, preview, inspect the common
parameter table and uncertainty, and accept the curve explicitly. The fit uses
all selected scientific rows through the public Numeric service. The baseline
is part of that one model; it does not overwrite or subtract from the source.

Y=f(X) and X=f(Y) are supported. Parameter coordinates follow the displayed
fitting translation; the report states the physical formula and translation.
Review components after changing axis units. Existing Dataset response/both-axis
uncertainty bindings, native solver settings and pointwise bands also apply.
Overlapping peaks can be strongly correlated or unidentifiable; a successful
optimizer does not establish a unique physical decomposition.

Accepted curves, CSV/Dataset publication, History and Workspace retain the full
frozen component declaration and exact parameter identities. The component
settings reopen with their source. Later installed descriptor changes do not
replace the captured scientific model in an accepted result.

## Compare accepted models

Fit and accept each candidate explicitly, then choose **Results → Compare
accepted models…**. Select two or more entries (Ctrl/Shift for multiple selection)
and choose RMSE, AIC, AICc or BIC. Compare reads saved evidence and performs no
new fit. The displayed order applies only to the selected candidates. Acceptance
remains your decision.

For a nested polynomial test, select exactly two accepted fits in list order:
the reduced degree first, the higher degree second. Choose **Nested F (first →
second)**. The report identifies both models, F, its degrees of freedom and the
upper-tail p-value. Both fits need the same exact training rows, response, weights
and predictor coordinates, full rank, no constraints, and an explicit independent
Gaussian unknown-variance assumption. An ordinary line with intercept can be the
reduced polynomial. Unsupported pairs show a reason without a nominal p-value;
use eligible information criteria for non-nested models.

Specify models independently of the observations before interpreting the nominal
test. Searching degrees or many pairs needs a separate selection/multiplicity
policy. A p-value does not establish the probability that a model is true. The
test reads retained fit facts and does not refit, change History or accept a model.

Use the same original training rows, response, effective weights, variable units
and likelihood assumptions. Set statistical assumptions before fitting. Gaussian
estimated variance supports unweighted or relative precision fits; known absolute
sigma supports AIC/BIC with no extra estimated scale parameter. AICc is unavailable
for known sigma and when N is too small. RMSE is descriptive, in response units,
and does not penalize complexity. Nonlinear criteria use local regular-model
approximations; robust objectives, active bounds, rank deficiency, unconverged
fits, geometric/radial/joint or XY-error fits do not receive an ordinary Gaussian
likelihood score. The reason is displayed instead of a ranking.

Numeric captures both the original response and the response actually fitted,
so different additive translations can compare when their physical observations
and all other conditions agree. Missing old evidence remains unverified and needs
an explicit rerun. Historical accepted fits are preserved. Criteria, assumptions,
source/row fingerprints and owned original row ordinals persist in acceptance,
History, Workspace, Dataset publication and CSV companion metadata. The dialog
is a view of these records; opening it never accepts another fit.


## Joint regional fitting and continuous knees

Choose `regions`, then **Joint regions…** in the Fit menu or model controls.
Append two or more ordered shape cards. Choose the physical origin and response
level, initial shape parameters, bounds and fixed flags. For each incoming
junction set its physical initial value and a finite search interval; the
intervals must stay ordered without overlap. C0 shares the junction response;
C1 also shares its slope. The C1 starting-slope controls are visibly disabled
because that slope is derived from the preceding region.

Observation windows use `lower upper; lower upper` in the physical predictor
coordinate. Leave them blank for all source rows selected by the existing Fit
points control. Adjacent and disjoint windows select original observations,
including their measurement columns and row identities. Output domain is a
separate control: a curve drawn through a gap is model extrapolation across
unobserved input, not evidence of an observed regime.

Apply saves the regional settings and explicitly turns both coordinate
translations off. Preview runs one joint fit. Native solver controls expose the
actual global parameter order, including free/fixed breakpoints and excluding
C1-derived slopes. Use reviewed multistart when competing transitions are
plausible. Inspect CORE uncertainty and convergence reports before accepting.
Weak changes, unobserved regimes, active bounds, rank deficiency or a free C0
breakpoint on a training predictor can prevent ordinary local intervals. A local
interval is not a profile interval or a claim that a breakpoint is unique.

For a single two-line knee, **Model components… → Continuous linear knee**
exposes the physical breakpoint, response level and both slopes. It can be
combined with existing scalar components and uses the same public statistical
interpretation. Original historical model identities remain unchanged.

Accepted regional results preserve the frozen joint model, full covariance,
actual selected original row IDs, region membership and measurement selection
stages in History, Workspace, Dataset publication and CSV companion metadata.
The editor uses the shared scrollable dialog body at narrow window sizes.
## Baseline correction for spectra

Choose **Fit → Baseline correction…** on a canonical Dataset curve. Review the
AsLS lambda, asymmetry p, stopping settings and grid policy, or select a constant,
linear or polynomial alternative. The operation uses active Dataset filters;
graphical fitting rectangles are not baseline masks. An edited/transformed curve
must first be materialized as a Dataset. Use the explicit source grid: duplicate
coordinates reject and an irregular grid requires the sample-index option.

**Create corrected Dataset** publishes to a new ID, preserving original columns,
separate baseline and corrected Y, source SHA and original row identities. It adds
the corrected curve as a separate Fitter source and sets translations off. Inspect
the result before choosing peak components and previewing a separate fit. Changing
lambda/p changes the estimated baseline, not the original spectrum. A failed or
cancelled estimation publishes no corrected Dataset.

CORE retains baseline provenance through acceptance, CSV, Workspace and subsequent
Variable aliases. Parameter/response intervals and likelihood comparisons are
unavailable until estimated-baseline uncertainty and induced correlations are
propagated. Descriptive residuals and fitted coefficients remain usable. A smooth
converged baseline alone is not evidence that a spectral background is correct.



### Reproduce an accepted fit in a script

Select one accepted fit, then choose Results → Export selected fit rerun
(Python or Octave). The script creates a new named Fitter Workspace through the
public API. Its recipe records the exact original-row selection, source schema
and SHA, initial values, solver settings, uncertainty bindings, model cards and
producer versions. A changed scientific source or incompatible producer is an
explicit error. Running the script is a new calculation; reopening a Workspace
continues to restore its retained result without calculating again.

The returned document/fit reference remains usable after the Job exits. Use
`result_info` for the formula, typed parameters, CORE statistics and managed
residual/prediction resources; use `result_publish` to create a new Dataset from
the retained result. Existing Dataset IDs are never overwritten. Recipes from
fits without captured provenance require an explicit new
preview and acceptance; their older saved results remain readable.

### Reuse named fit settings on a new Dataset

Select an accepted fit and choose Results → Save selected fit as template. Give
it a unique name in the Session. Templates appear in Workspace Manager alongside
other scientific Workspaces and use its export/import and rename actions.

Choose Fit → Apply fit template, select the target Dataset, and map each required
Variable. The dialog checks units, numeric/text roles and rank; perform an explicit
Dataset unit conversion first if units differ. Review the mapping and selection
policy. Individual source-row picks are cleared because another Dataset has
different observations. Coordinate regions may be retained, or choose all rows
passing the saved source filters. Review states exactly how many picks are cleared.

Apply settings loads a separate source and preserves the initial values, solver
policy and uncertainty bindings. It does not calculate or accept a fit. Inspect
the settings, then use Preview and Accept. Previous accepted fits remain, and
the new fit retains its template/target lineage through saving and publication.
Templates preserve fit settings; prepare the target's preprocessing explicitly.
Materialize transformed source views or publish built-in samples before saving
a reusable Dataset template. A saved template can bind to a compatible target
even after its original Dataset has been archived.


### Export a fitted model for use outside GX-TXT

Select one accepted fit, then Results -> Export selected model (Python, Octave,
LaTeX). Choose a new filename such as `fit_spectrum.py`. A matching `.m`, `.tex`
and metadata `.json` are saved together. Existing files are preserved.

In Python, import `fit_spectrum` from that file and call `fit_spectrum(x)`.
In Octave, put the `.m` file on your path and call `fit_spectrum(x)`. The output
has two columns, physical X and Y. For X=f(Y), supply physical Y; for parametric
curves supply normalized t; for radial curves supply the saved angular units.
The function checks the accepted output interval. Export does not refit data.
Python requires NumPy and uses SciPy for Voigt/erf formulas; Octave uses its core.

The equation and coefficient notes distinguish scaled evaluation coefficients
from the accepted physical parameter estimates. Keep the source/domain/unit
metadata with your function. Old polynomial results without their exact scaled
evaluation state need an explicit new Preview and Accept before export; they
remain available in the Session. Very large model text has an explicit 2 MiB
export bound. The saved model is never reduced automatically.


## Registered Python and Octave models

Save a function in the existing Script Library, then use **Fit → Declare Script
Library model**. Its arguments are `(parameters, predictors)` and its return is
one response per predictor row. Parameters have shape P-by-1 and predictors
N-by-1; return a column (Python may return a one-dimensional vector). Declare
stable parameter IDs, physical units, initial estimates and optional bounds in
matching order. The optional fixed-parameter field accepts comma-separated 0/1
values: 1 keeps that parameter at the selected initial estimate. Equal lower and
upper bounds also fix it; its initial value must match. Leave the field blank
to use equal bounds alone. Fixed values appear as fixed in the result and are
excluded from the free-parameter count and covariance intervals. When every
parameter is fixed, the model is evaluated without optimization.
Use `1` for dimensionless quantities. Source predictor/response
units must match the declaration; apply an explicit Dataset unit conversion if
needed. A declaration preserves source bytes and pins its Script revision.

Use **Fit → Registered Python/Octave model** to select it. Set the fit-point
selection, output domain and statistical assumptions, then Preview. A supervised
Job runs while the GUI remains available. Completion retains an unaccepted
preview, parameters, residuals and exact executable source. If the current
source/settings still match, its resources are copied into the original
Workspace. If they changed or the viewer was closed, the separate preview
remains available in Session Workspaces. Review it before Accept. Publishing,
Undo/Redo, reusable templates and Workspace packaging retain model identity.

Response sigma and relative precision use the existing measurement controls;
explicit missing-value omission preserves original row IDs. Callback fitting
uses the reported SciPy least-squares backend and CORE statistical meaning.
**Fit → Solver settings** selects bounded `trf` or `dogbox`, maximum solver
function evaluations, objective/gradient/parameter-step tolerances and positive
physical parameter scales. Scales use the displayed canonical parameter order;
they do not change physical units. Bounds and fixed roles remain in the model
declaration. Settings survive recipes and Workspace reopen; selecting another
declaration resets its solver settings so scales cannot silently follow different
parameter identities. Apply invalidates the preview without launching a Job.
The result records the actual SciPy version, stopping reason and all settings.
Function evaluations are distinct from numerical-Jacobian callback invocations;
this backend does not report optimizer iterations. Cancellation uses the existing
supervised Job. All-fixed requests validate these settings and evaluate without
optimization.
Registered callbacks support scalar Y(X)/X(Y). Radial and orthogonal callback
requests are refused.

Registered models support pointwise mean-confidence and future-observation
intervals through the usual statistical settings. Declare the noise model and,
where required, future observation sigma or relative precision. The retained
report explains eligibility and the callback finite-difference method. Bounds
are in original physical coordinates and survive acceptance, publication and
Workspace packaging. They are pointwise intervals, not simultaneous coverage.

For an accepted registered model, **Export independent model** creates Python,
Octave, LaTeX and metadata files from the exact saved source and coefficients.
The original model language and imports remain dependencies: an Octave source
still uses Octave when called from the generated Python function, and conversely.
No automatic source-language translation occurs. Pass an entire query vector
per call; the adapter runs the model once in a separate process, with a
120-second limit and temporary files removed afterward. The metadata lists
dependencies, source SHA, units and physical domain. Generation does not execute
the model or change the accepted fit. The source must work independently of
GX-TXT and reproduce a deterministic function of its parameters and predictors;
external files, packages and mutable state are not automatically captured.

Use **Fit → Cancel registered model Job** to cancel the active callback. A
cancelled Job has no successful preview receipt and does not accept a fit.
Each Job Workspace name includes its invocation ID, allowing repeated runs to
remain independently retained. Changing output settings during computation
keeps the completed original preview in its Job Workspace and prevents stale
adoption into the current viewer.

### Choose a smoothing penalty

Select Smoothing spline. The main lambda field keeps manual control, including
zero for interpolation. Fit → Smoothing selection opens the shared settings form.
For GCV, enter two positive increasing lambda bounds, a log-grid count and a
refinement budget. Preview runs the bounded search on the full selected source.
The displayed lambda and GCV are Numeric facts; Results → Smoothing diagnostics
shows EDF, the distinct residual variance DOF, evaluated candidates and CORE's
scientific qualifications. A selected endpoint indicates that the chosen bounds
constrain this search. GCV does not guarantee a global optimum or provide a CI.
Accept/publish only after inspecting the result. Accepted models, recipes and
Workspace reopen retain exact settings, model state and search evidence. Merely
reopening a Workspace does not rerun the search. Use manual mode to override it.

### Model controls and technical details

The fit panel shows the fields and settings relevant to the selected model and
output domain. Switching models retains their entered values. Both-axis
uncertainty exposes the initial vector for linear/polynomial native fitting.
Labels wrap in the sidebar; keyboard focus scrolls the active control into view.

Results begins with the model and parameter table. The scientific status explains
solver completion and its limits. Show technical details expands the retained
solver settings, iteration/evaluation counts and model-state storage information.
Results → Solver diagnostics provides the same details in a separate window.
Expanding or collapsing details does not edit the scientific Workspace. The
results area scrolls independently, retaining room for the source and accepted
curve plot at smaller window sizes and enlarged fonts.

Plot labels adapt their margins and tick spacing to the actual display font.
Physical coordinates and units remain those of the captured source axes. The
caption occupies a separate band above the data, and axis titles have their own
space. A residual subplot appears when its caption and data region fit; the exact
residual table remains available below. These presentation changes do not alter
Dataset values, fitted parameters or the canonical CORE view/selection contract.

## Fit logarithmic responses explicitly

Load a canonical Dataset curve and choose **Fit → Logarithmic fitting**. Enter a
new Dataset ID and a positive Y reference in the displayed Y unit. Optionally
transform positive X values with their own same-unit reference. The action creates
new dimensionless ln(value/reference) columns while retaining the original data.
Zero or negative values refuse; this operation does not add an implicit offset.

Select the desired model and orientation, then choose the log-error assumptions
in **Fit → Statistical assumptions and intervals** before interpreting inference. The residuals,
RMSE and scores describe the transformed response. The main report links to
**Results → Log-response interpretation**, containing the complete read-only
CORE explanation. A direct exponential fit to original Y has a different loss
model. Logarithmic display axes alone do not transform the fitting objective.

Accept the fit. Select that accepted row and choose **Results → Publish physical
log-response result** to create a separate physical-response Dataset. CORE labels
the inverse fitted value/conditional median, the eligible Gaussian variance
plug-in arithmetic mean, and the actual interval target. A confidence interval
for the fitted log mean becomes a physical-median interval, not an interval for
the arithmetic mean. Future-observation intervals retain their prediction
meaning. Unavailable mean or interval columns are omitted with recorded reasons.

The new source becomes the visible curve and its selectors/axis units are updated.
Earlier sources and accepted fits remain in the Workspace, hidden initially so
physical and logarithmic coordinates do not share an unlabeled overlay. Residual
and parameter displays clear until a fit for the new source is selected or
previewed. Saved results, recipe replay and compatible renamed-column templates
retain the original references, units and source identities.
## Linear influence diagnostics

For a linear or polynomial response fit, open **Fit → Statistical assumptions
and intervals**, enable **Exact linear influence diagnostics**, then preview.
Weights and explicit measurement omission use the same exact training rows as
the fit. Nonlinear, orthogonal and geometric fits cannot use this option.

Open **Results → Linear influence** for the preview or selected accepted fit.
The report explains leverage, Cook's distance and leave-one-out results, with
unavailable cases and review thresholds. Scroll the table horizontally to see all
diagnostics; Previous/Next read bounded pages. Select a table row and choose
**Select exact source row** to identify it on the original source, including rows
outside its display sample. This preserves the data and does not refit. Source
changes require reloading/reviewing; a stale diagnostic cannot select another row.

The source-row ordinal is zero based; the separate Numeric input index is one
based after Fitter's explicit source/measurement preparation. Saved Workspaces,
recipes, public Script pages and accepted metadata retain these distinct identities.
Table numbers are formatted for reading; owned resources preserve full binary64
precision. Cook/leverage thresholds are review aids, never automatic deletion rules.


## Parameter bootstrap uncertainty

Open **Fit → Parameter bootstrap settings** for an explicit resampling fit.
The default is Off. Choose observation tuples, standardized residuals, or declared
Gaussian errors; enter the replicate count, seed, marginal confidence level and
shared time budget. Defaults are 1,000 refits, seed 1, 95% and 60 seconds.
Preview performs the requested refits through Numeric, using the exact retained
training observations after filters, selection and measurement omission.

Supported scalar-response models are linear, polynomial, exponential, power law,
Gaussian, components, joint regions, formulas and registered Python/Octave
callbacks in Y(X) or X(Y). Registered refits run in a supervised Job with one
internal thread, preserving the captured callback solver/version/settings.
Historical fits without exact predictor hashes keep bootstrap unavailable.
Orthogonal, radial and geometric fits refuse this operation. Each local nonlinear
refit starts at the original fitted parameters and retains its loss/constraints;
it does not repeat a multistart search or guarantee a global optimum. Tuple
resampling assumes independent observation tuples. Residual resampling assumes
independent standardized errors with fixed design; Gaussian simulation requires
the matching declared noise model. Inspect these assumptions before interpreting
confidence limits.

**Results → Parameter bootstrap** shows the readonly CORE interpretation and
100 trials per page. Parameter estimates and draws retain their stated translated
fit coordinates and units. The separate response residual coordinate label does
not convert the coefficients. Every failed, boundary or unfinished trial remains
in the table. Any such trial withholds nominal percentile intervals; covariance
and standard errors can still describe successful replicates. Fixed parameters
have no estimated interval, and a point-mass empirical distribution is not proof
of zero uncertainty. More replicates reduce percentile Monte Carlo error but
cannot validate a wrong sampling assumption.

Cancel operation or Escape stops the worker and preserves the prior preview and
accepted results. Accepted provenance, Dataset publication, recipes, templates,
Workspace and History retain settings, CORE meaning and exact typed trial data.
Opening results or reopening a Session reads those resources without refitting.
Script callers use `result_bootstrap_page` for at most 512 trials per request;
parameter draws are binary64, status codes uint8 and starting seeds uint32.

## One model for a complete family

Choose **Fit → Global family fit…**, select the numeric physical family Variable
and a callable mathematical model, then explicitly choose the complete Dataset.
This uses the original canonical X/Y values, including rows outside the current
curve filters or point selection. Publish an edited source as a canonical Dataset
first when those edits should define the input. Your active curve, point selection,
accepted fits and History remain available throughout this separate joint fit.

The next form lists parameters in their original model order. Choose `shared` for
one common value, `local` for one value per physical family member, or `fixed` for
one common constant. Optional initial/bound/mask vectors use semicolons: expand
local parameters in ascending family-value order. For example, with family values
`-2` and `-1`, shared `mu`, fixed `Kp`/`Kvb`/`Ex`, and local `Kg1`, the order is
`mu;Kp;Kvb;Kg1@family=-2;Kg1@family=-1;Ex`. A fixed mask may also fix an individual
local slot. Blank vectors use the selected model's declarations.

Give the Job a descriptive name and select **Run global fit**. Follow or cancel
it in Session Jobs. The source/model fingerprints are checked again when the Job
executes. A completed run opens its joint parameter and statistical report.
The full covariance and effective free-parameter count belong to the joint model;
member parameter rows are not independent estimates.

Use **Results → Global family results…** to reopen a retained report after closing
Fitter or reopening the Session. Its parameter and prediction table buttons open
the matching canonical Dataset. If a later run has replaced that Dataset, the
saved report/files remain available and the table action reports the mismatch.
The [Curve Family guide](../curvefit.family_global/README.md) documents frozen
evaluation, member-subset replay, declared units and the public Script workflow.

### Smooth a source before fitting

Load a canonical Dataset curve and choose **Fit → Smooth into a separate
Dataset…**. Choose Savitzky–Golay for a uniform grid or LOWESS/LOESS for ordered,
distinct coordinates. Review the odd window, local degree and LOWESS robust
reweightings. LOWESS uses degree1 or2; larger windows smooth more strongly.
Savitzky–Golay requires a degree smaller than its window. Nonfinite values fail
unless you explicitly choose omission. Omitted positions remain gaps.

Apply creates a new Dataset and selects its smoothed response as a separate
Fitter source. It preserves original columns, the removed component and exact
source rows. Dataset filters apply; graphical fit rectangles do not select the
smoothing input. Original data are unchanged, and the operation has the normal
progress/cancel controls. Large LOWESS requests must fit its recorded work limit;
there is no silent reduction of scientific samples.

A later fit still provides coefficients and descriptive residuals. Smoothing
correlates errors, so ordinary independent-error intervals, bootstrap and
likelihood rankings are unavailable until that correlation is modeled. The CORE
report explains this limitation. Choosing a Gaussian noise option does not remove
it. Saved recipes, templates and Workspaces preserve the smoothing provenance,
including renamed variables and subsequent derived coordinates.

## Safe formula fitting

Choose **formula**, then **Fit → Safe formula**. Enter an equation using `x`
for the selected independent physical axis and add named parameter rows. Each
row has its unit, initial value, optional lower/upper bounds and a fixed flag.
**Validate units and formula** shows the parameter units. Blank units request
unique dimensional inference; the initial values and bounds then refer to the
shown canonical units. Apply the settings, select zero translations and Preview.

The same shared native model supplies parameter derivatives, fitting, response
intervals, supported bootstrap and standalone exports. Arbitrary executable code
is rejected. Convert affine/semantic source units explicitly before fitting.
Use dimensionless arguments for logarithms/exponentials and dimensionless bases
for variable powers. Ambiguous parameter dimensions require explicit units.
The report retains your symbols: in X(Y), `x` denotes physical Y, and parameter
names are never rewritten by an axis change. Saved Workspaces, templates and
Script recipes retain the original formula, units and constraints.

Power-law results show a conditional coefficient unit such as
`(mA)/(V)^exponent`, with a dimensionless exponent. The parameter report explains
that estimates and covariance refer to the captured coordinate-unit basis.
Changing predictor units requires a joint parameter/covariance transformation;
renaming a unit label does not convert a retained result. Parameter Datasets and
independent export metadata preserve this meaning. Historical accepted results
retain their original unit labels until an explicit new fit is performed.

Direct arc, Bezier, open parametric-polynomial and Fourier models also expose
[manual parameter controls](../../../docs/api/FITTER_PARAMETER_VIEW_v1.md). Their
starting state comes from the existing direct solver; edited values describe an
exploratory curve and do not change the next direct fit. Interpolators retain
their existing data/knot/smoothing controls. No new accepted fit is created.

Accepted registered Python/Octave models use the same Results query action.
The report names the numerical derivative method and its limitations. Evaluation
uses a supervised cancellable Job and the captured callable declaration; a changed
declaration is refused. Prediction-only queries retain unavailable derivative
fields explicitly. Source data and accepted results remain unchanged.

New fitted output outside the closed training-coordinate range appears orange
and dashed in Preview and accepted curves. The report gives the count and range.
Points inside gaps between selected windows are still inside this envelope.
X(Y), radial and parametric fits use their own physical/normalized independent
coordinate. PCHIP and other intrinsically bounded models reject invalid output.
Published Datasets and CSV include `fit_query` and `is_extrapolated` for each
exact output row. Saved Workspaces retain this classification. Older fits without
the receipt remain unclassified. See the [output-domain contract](../../../docs/api/FITTER_RETAINED_QUERIES_v1.md#accepted-output-domain-flags).

## Scientific report and preprocessing audit

Results → **Scientific report** shows the current preview’s equation, parameters,
CORE uncertainty and fit-quality interpretation, solver receipt, source units
and transforms, exact row stages and exclusions. The main Results summary shows
original, filtered, finite, selected and fitted observation counts. Model nodes
can differ from observations when a repeated closure node is removed.

Accepted CSV export includes a readable `.report.txt` and an exact
`.preprocessing.csv` row audit, with filenames and checksums in the metadata
sidecar. PCHIP and smoothing splines declare their sorting and duplicate-X
rejection; other fits preserve distinct observations. No source is silently
averaged. The [preprocessing contract](../../../docs/api/FITTER_PREPROCESSING_v1.md)
explains exclusions, stage ordering, public row pages and historical availability.

## Choosing a model from its documentation card

Open Fit → **Model documentation** for the current model. Each card explains the
equation, parameter meanings and units, valid input domain, method classification,
initialization, solver assumptions, uncertainty diagnostics and extrapolation
policy. Its selector browses other models without changing your fit settings.
Cards are available before loading a Dataset. The [complete card reference](../../../docs/api/FITTER_MODEL_CARDS_v1.md)
and public `model_cards` operation provide the same information outside the Viewer.

Read the actual scientific report for eligibility under your data and constraints.
For example, PCHIP interpolating its knots does not establish statistical success;
Fourier’s current curve adapter does not supply coefficient inference, and a
circular arc’s algebraic approximation is not an orthogonal-distance fit.

## Transfer an accepted model to Curve Workbench

**Results → Transfer selected model to Workbench…** and the Script operation
`result_workbench(reference, workspace_name)` create an independent Workspace
with exact supported primitives or explicitly sampled geometry. No fitting is
performed. The complete scientific model, resources, parameter domain, units and
provenance are retained separately from editable geometry. See [transfer support
and approximation limits](../../../docs/api/FITTER_WORKBENCH_TRANSFER_v1.md).

## Derived physical properties

Evaluate named parameter expressions with full correlated covariance, physical
units and explicit unavailable states through the public CORE/Numeric APIs.
Fitter exposes linear thresholds, exponential characteristic intervals, regional
knees and custom expressions in **Results → Derived physical properties…**.
Use **Evaluate properties**, review the report, then **Publish evaluated result**
to create a Dataset from that captured receipt without refitting.
See [declarations, scientific assumptions and Script operations](../../../docs/api/DERIVED_PHYSICAL_PROPERTIES_v1.md).

## Physical plausibility review

Select one accepted fit, then choose **Results → Physical plausibility review…**.
Review the suggested conditions or add explicit parameter intervals. Bounds use
the displayed captured parameter unit and coefficient coordinates. An optional
maximum-domain-fraction rule compares a nonnegative parameter with a fraction
of the retained independent-coordinate range, in the same unit. It is useful
for Gaussian width coverage; it is not a probability or confidence interval.

**Advisory warning** records an optional concern. **Physical domain requirement**
records a violation of an explicitly declared physical condition. Intrinsic
model domains and optimizer bounds remain enforced independently. Disabling a
review condition cannot relax them. A satisfied condition does not establish
model correctness, identifiability or small uncertainty. Fixed parameters are
reviewed as conditional point values, without invented error estimates.

Use **Add rule** or **Replace selected rule** to commit editor changes, then
**Review rules**. Changing the committed rule list clears the previous review.
Use **Publish reviewed result** with a new Dataset ID to retain the result,
source reference, conditions, units and report independently of the Fitter.
The accepted fit is unchanged and no fit or statistics are recomputed.

Gaussian suggestions distinguish required positive width from an advisory about
width exceeding observed coverage. The exponential decay suggestion is optional:
a positive growth rate can describe valid growth. Composed models use their
frozen descriptors' declared positive/nonnegative parameter domains. Other
parameters can have user-defined intervals with an explicit physical reason.
At most 32 rules and 128 captured scalar parameters are supported per review.
Missing values or domain width are unavailable; disabled rules are not passes.

See [the public physical review contract](../../../docs/api/PHYSICAL_PLAUSIBILITY_v1.md)
for CORE and Python/Octave Script Bridge operations.

## Advisory model suggestions

Load a source, then open **Fit → Model suggestions…**. Choose all or selected
source points and use **Inspect source and compare selected fits**. The assistant
reads exact finite rows, including the actual point selection, rather than the
bounded display curve. It supports functional Y=f(X) and X=f(Y) orientations and
up to 1000000 finite observations. Source values are inspected before optional
fit translations; measurement-error weights do not determine shape hints.

The report distinguishes eligible defaults, manual scientific definitions and
unavailable candidates. Monotonic, peak, saturation and repeated-pattern hints
use explicit deterministic thresholds. A suggested period carries the physical
independent-coordinate unit. Repeated predictors remain separate observations;
ordered shape hints require an explicit duplicate policy. A hint is not a
probability, an identified physical mechanism or evidence of a successful fit.

Optionally select two or more retained fits in the dialog for AIC or AICc. Their
captured source, exact row and predictor/response identities must match the
inspected population, and CORE must verify compatible weights and likelihoods.
Missing/incompatible evidence yields no ranking. Existing scores are reused.
No model is fitted, selected or accepted automatically, and inspecting advice
does not change a preview, accepted result, solver setting or saved Workspace.
Use the normal fit controls explicitly after reviewing the model documentation.
Cancel or Escape stops an active inspection through the existing worker manager.

See [public source-advice and Script contracts](../../../docs/api/MODEL_SUGGESTIONS_v1.md).

## Full observation covariance

For a linear or polynomial Y(X)/X(Y) fit, open **Fit → Correlated observation
covariance…**. Choose a real N×N covariance Variable and explicitly confirm that
both axes correspond to every original source row in its original order.
Choose absolute covariance or an unknown common scale, and whether zero-variance
modes should be rejected or treated as exact equations. Declare Gaussian errors
only when scientifically justified. Preview, review **Results → Full covariance
fit details…**, then accept/save normally.

The response Dataset and Variable are bound explicitly. Both covariance axes
follow exact filtered/selected/reversed source rows; display decimation is never
used as fit data. Values must already use squared response units. This dense
workflow permits2..2048 original rows and preserves the selected matrix as an
owned result resource, so accepted results remain inspectable after source changes.
Independent sigma/precision, unpropagated smoothing/baseline/log transformations,
independent bootstrap/influence and response bands cannot be combined with GLS.
Normal coefficient intervals require known correlated Gaussian covariance;
estimated common scale uses Student t with stochastic residual DOF. Relative
scale at zero DOF is unavailable. Exact zero-variance coordinates have no ordinary
marginal interval. R-squared and diagonal-error AIC are not reported for training.

See [covariance binding, exact recipes and Script use](../../../docs/api/FITTER_COVARIANCE_v1.md).

## Fit an implicit equation

Select **implicit** and open **Fit → Implicit equation and branch…**.
Enter f(x,y,p)=0 with physical X/Y units, named parameter units/initial values,
and any bounds or fixed parameters. Choose algebraic residuals or normalized
algebraic residuals with a positive physical reference value in equation units.
That value is a normalization scale, not measurement sigma. Choose Y(X) or X(Y),
enter the response bracket and independent-coordinate domain, and explicitly
declare a continuous branch. Validate checks the declaration; Apply saves it.
Preview fit runs the solve and checks every output sample before drawing.

X and Y keep their physical identities when the response orientation changes.
The table shows equation value and equation residual at each observed pair;
it does not label these as vertical response errors or ODR distances.
The residual plot uses equation units. R-squared and ordinary likelihood ranking
are unavailable. Conditional parameter intervals require an explicit Gaussian
equation-error assumption and a valid local covariance; unknown noise does not
supply that assumption.

Use 2–256 output points. Retained query calls accept up to 64 values. Brackets
must contain the selected continuous branch; missing roots refuse the curve and
retain the previous result. No global uniqueness is asserted. Translation,
measurement weights/sigma, XY/full covariance, smoothing, baseline/log-response
preprocessing, response bands, bootstrap, influence and multistart are refused
for this model. Configure its initial parameters in the equation editor.

Accept, save/reopen, exact recipes, physical queries, standalone Python/Octave
exports and parameter publication retain the equation and branch. Workbench
transfer uses a sampled curve and separately retains the original equation.
Read the [implicit equation guide](../../../docs/api/IMPLICIT_EQUATION_MODELS_v1.md)
for the full scientific contract, limits and API fields.

## Fit complex frequency responses

Choose a positive-frequency X Variable and a real, imaginary, magnitude or db20
Y display Variable. Open **Fit → Joint complex responses…**. Enter one to three
physical channel formulas, shared parameters with explicit units and bounds,
and exact Cartesian or amplitude/phase Variable bindings. Polar units and dB
references are explicit. Choose a shared Cartesian covariance matrix or an
M×M×N covariance Variable covering every original source row; confirm its units
and correspondence. Declare Gaussian innovations only when justified.

Validate and Apply the declaration, Preview, then Accept and save normally.
Filtering, selection and reversal map every component and covariance slice to
the same original rows. The displayed trace does not replace the joint objective.
The report distinguishes frequency-row counts from Cartesian residual counts;
wrapped phase remains diagnostic. Retained queries, exports, recipes and result
publication keep the full physical model and owned scientific resources.

See the [complex Fitter guide](../../../docs/api/FITTER_COMPLEX_v1.md) for an
RLC-compatible declaration, input units, covariance rules, limits and Script use.


## Fit a physical surface

Choose **Fit → Physical surface fit…** for a physical `z=f(x,y)` model.
Select canonical X/Y/Z Variables, optional response sigma and an explicit
`points` or `grid_yx` layout. Grid Z must have the exact Y/X axis dimensions.
Review units, missing-value policy, noise assumption and physical parameters,
then **Preview fit**. Inspect the common CORE report and original-index residual
table, give the result a name and **Accept fit**. Changing the declaration requires
another Preview before acceptance.

Use **Evaluate** for an exact retained XY query. Independent model export and
rerun recipe export are in **File**. To view a surface, choose explicit grid
bounds/counts and a new Dataset ID, **Publish sampled grid**, then **Open published
grid in3D**. This samples the retained physical model; original missing cells and
source data stay intact. Axis bounds do not imply measured coverage inside them.
Save the Workspace and Session to retain accepted models, controls and History.
See the [surface guide and public API](../../../docs/api/FITTER_SURFACE_v1.md)
for source shape, uncertainty, retained-resource, query/export and Script contracts.

## Physical rational models

Use **Fit → Rational / Padé…** to declare physical numerator/denominator degrees,
coefficient units/constraints and a guarded predictor interval. Validate before
applying; explicit extrapolation still checks the whole intervening domain.
The quotient uses rational least squares and does not match Taylor coefficients.
See the [rational workflow](../../../docs/api/FITTER_RATIONAL_v1.md) for controls,
response uncertainty, inverse orientation, saved state and Script examples.

## Akima and explicit knots

Choose akima or bspline, then Fit → Knots / boundaries… to declare physical
knots, degree and endpoint conditions. Both orientations use original Dataset
coordinates and retain separate construction and source-evaluation meaning.
See the [knot workflow](../../../docs/api/FITTER_KNOT_MODELS_v1.md) for limits,
explicit extrapolation, saved recipes, Script access and unavailable inference.

## Shared Workspace manager

**Workspace → Session Workspaces…** opens the common manager scoped to Fitter. Session → Workspaces uses the same controls with provider and name/type filters. New opens a named unsaved draft; Save persists it through the existing Document authority. Existing scientific edits retain their History/autosave behavior. Remaining unsaved field changes are reviewed before New, Open, Duplicate, Close or Delete: Save commits them, Discard abandons only the uncommitted draft, and Cancel keeps editing. Rename changes only the Workspace name.

Select a saved Workspace for Notes, a managed Preview, Duplicate, Export or Delete. Import and Duplicate use independent names and remap nested owned resources. Delete confirms removal of the selected Document, notes, History and managed resources; source and published Datasets stay intact. Stale Session/generation/revision commands fail clearly. Finish or cancel active scientific work before switching or closing. See the [shared Workspace controls and API](../../../docs/api/SESSION_WORKSPACE_API_v1.md).

## User Manual

**Help → User Manual…** or **F1** opens this Viewer's own nonmodal rendered manual window. Find, scrolling, links and Back/Forward are independent from another Viewer's manual. Repeated F1 raises this manual; closing it preserves the scientific Session and Workspace. The main GX-TXT Help page remains available separately.
