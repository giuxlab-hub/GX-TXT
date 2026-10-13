# Dataset Curve Fit

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
are disabled during this operation and restored afterward. Closing during a load
first cancels it, then saves and closes the existing workspace.

## Select fit points and navigate

The blue curve is the immutable Native 2D CORE source. Red markers show selected data points. Click a point to select it. Shift or Control toggles a clicked point within the selection. Drag a rectangle to select points; the orange outline shows its extent while dragging. The **Rectangle** control chooses Replace, Add, or Subtract. Shift or Control while dragging adds, and Alt subtracts. **Remove last rectangle** reverses the newest rectangular selection block; **Clear selection** removes all selected points and blocks.

Rectangle selection operates on a separate CORE point set with the same display coordinates as the source curve. This keeps fit-point selection restricted to points inside the rectangle even when a connecting source segment crosses it. Native CORE supplies the ordered rectangle operations and manual point overrides. For a Dataset source, rectangles apply to all exact streamed XY rows and clicked display points map to their original row IDs. A separate bounded Numeric input contains every selected finite pair, independent of display reduction. Both training count and the exact selection descriptor accompany the scientific report; changing a rectangle invalidates the preview even if its display markers do not change. Save/reopen preserves rectangles and point overrides.

The canvas has numeric X/Y ticks and Dataset variable labels with units. Use the mouse wheel to zoom around the pointer, drag with the middle mouse button to pan, or choose **Reset view**. These controls change only the view, not data or selection.

## Preview and accept a fit

Choose **all** or **selected** fit points. Choose an output domain independently: **source** uses the sorted, distinct source X values; **range** uses minimum X, maximum X, and sample count. The original source order and repeated observations remain intact for fitting and residuals. Changing the output domain does not change fit points.

Legacy models are linear, polynomial (degree 1–12), exponential `a exp(b x)+c`, power law `a x^b`, and Gaussian `a exp(-0.5 ((x-mu)/sigma)^2)+c`. Polynomial degree is active only for that model. Nonlinear models expose initial parameter guesses in the displayed order; power law requires positive X and Gaussian width must be nonzero. Range fields are active only for a range output domain. Custom expressions are not offered because the current data-only Numerical worker cannot bind arbitrary callbacks.
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
available. Closing during a job requests cancellation, then saves and closes
after cleanup. Source/model/selection controls are held during the job.

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

**Accept as new CORE curve** creates a separate CORE curve and leaves the source unchanged. Accepted fits appear in the list with model, scope, fit size, statistics, and a distinct color. Select a fit to show, hide, delete, or export it. Several accepted fits can coexist.

## Export and resume

**Export accepted fit CSV** writes the selected accepted CORE curve with `x_<X>` and `fitted_<Y>` columns from its original binding, plus source kind, Dataset ID or sample ID, model, fit scope, and CORE object ID as provenance. Its sidecar includes stable accepted/source curve identities. **Publish selected fit as Dataset…** publishes the selected historical accepted geometry with its frozen source labels, units and model provenance. The entered name/ID becomes the exact validated public Dataset ID; a collision names that ID and leaves the existing Dataset intact. These actions preserve each source's accepted-fit ownership.

The viewer saves Dataset bindings, filters, view, selected points and accepted fits in the Session Interactive Document. A missing or changed Dataset restores as a textual **missing/stale** source entry, alongside its independently restored accepted curves. Fitting is disabled for that entry. Restore the Dataset or update its schema, then use **Reload active source**. Reload keeps the workspace source ID, resets point selection and preview, and reads the current exact source; earlier accepted curves retain their original model and frozen provenance. A failed reload leaves the existing entry and accepted curves intact.

**Style sources…** applies shared RGBA/opacity, line width and pattern controls to selected sources without refitting. **Remove sources** removes selected local inputs and their previews, while retaining independently accepted curves. Those accepted curves can still be inspected, published, exported or deleted, and remain available after save/reopen even when every source has been removed.

Large reconstructible model JSON and parameter arrays stay in owned document resources. Reports show the resource identity, size and parameter count rather than loading complete arrays into GUI fields. Small models retain their inline coefficient reports. Published Dataset metadata and other documents keep their referenced scientific blobs alive during resource collection and document deletion.

The shared Curve Source and Dataset Transform APIs read and filter CSV/HDF5 and other supported canonical storage. Native extrema sampling bounds display memory; it preserves source-row identity and nonfinite gaps. Fit-all reads exact data through bounded native binary staging, independently from the proxy. Large accepted curves remain complete in Native CORE and persist as content-addressed Interactive Document resources. Explicit Dataset publication streams the complete curve and uses size-aware Storage Auto. The shared native C/Tcl adapter is installed under CORE; `GX2D_TCL_LIBRARY` can point to a development build. A compiler is needed only to build it. GNU Octave is required by the Numerical API worker.

From a compatible framework source checkout, run the following optional API/Tk verification in an isolated output directory:

```sh
xvfb-run -a tclsh plugins/modules/viewer.dataset_curve_fit/tests/test_dataset_curve_fit.tcl "$PWD" /tmp/gxtxt-dataset-curve-fit-check
```

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


## Native plotting workspace and fit inspection

Source, preview, accepted-fit, selection and residual lines are clipped to the actual Native plotting viewport before rendering. Markers/text crossing the plot are omitted; scientific coordinates and fit input stay unchanged. Auto/X=Y, zoom, pan and resize share this authority. There are no cosmetic margin masks. If controls leave less than the minimum plot size, stale drawing is cleared. The resizable scrollable layout described below retains its plotting area at narrow widths and larger fonts.

Host service `DatasetCurveFit::fitPrimitive points family unit` delegates to existing Numerical parametric models and returns `definition`, `quality`, `working_unit`, `method=scientific_fit`, `numeric_api=NUMERIC_API_v1`, `approximation=1`. It accepts declared compatible length units and 3..65536 complete continuous points. Native2D maps Numeric parameters; this service does not publish or adopt an object. The Workbench controls source validation, Preview and explicit Accept. The original validation screenshot is not included in this source distribution.


## Native2D integration

The module uses the shared Native2D adapter from CORE, with complete-input scientific fitting, unit conversion and native viewport clipping.

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
