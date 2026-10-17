# Scientific Worksheet — User Manual

Scientific Worksheet is a calculation Workbook inside a GX-TXT Session. It combines typed cells, safe formulas, public scientific operations, canonical Dataset snapshots and live native charts. Editing a Worksheet never changes a bound source Dataset.

## Start and save

Open a Session, then choose **Viewers → Scientific Worksheet**. A draft starts with **Sheet1**. The top menu provides Workbook, Edit, Insert, Data, Formulas, View, Workspace, History and Help. The compact toolbar provides Save, Undo, Redo, Functions, the inspector toggle and a Go To address.

**Workspace → Save** persists the complete Workbook as a canonical Session Workspace. Open, New, Save As / Duplicate, Rename, Manager, Notes, Preview, Import, Export, Close and Delete use the shared [Workspace host](../../../docs/api/SESSION_WORKSPACE_API_v1.md). New remains an unsaved draft until Save. A dirty close or switch asks **Save / Discard / Cancel**; it never publishes a Dataset automatically. A stale Session, deleted document or externally changed scientific document must be reopened before editing or saving. The title follows the actual Workspace name.

**Help → User Manual…** or **F1** opens this rendered manual in its own nonmodal window. Find, scrolling, Back and Forward belong to that manual window. Closing it leaves the Worksheet and main application Help available.

## Native grid and docked editor

The native grid virtualizes visible rows and columns, with bounded overscan. Its address domain is **A:ZZ** and **1:1,000,000**. Scrollbars, fast wheel input, arrows, Page Up/Down, Home/End and Ctrl+Home/End use the same clamped viewport. Filtering preserves original row numbers. Headers show column identities, names and declared units; drag a column divider to change its display width.

The resizable **left inspector** has Cell & Formula, Functions, Data / Lineage and Chart tabs. Its controls scroll vertically on smaller windows. **Inspector** hides or restores the panel; **View → Reset layout** restores the standard arrangement.

- Click a cell, press **F2** or double-click to edit directly. Typing in the grid starts a direct edit. **Enter** commits and moves vertically; **Tab / Shift+Tab** commits and moves horizontally. **Escape** cancels the draft. One native caret editor is used for the active cell.
- The **Cell & Formula** tab contains a multiline editor. **Apply** commits its value or formula; **Ctrl+Enter** also applies. **Cancel / Escape** restores the stored source. A formula begins with `=`. Selecting another cell commits a valid pending cell edit; an invalid transaction stays available for correction.
- Drag to select a rectangle, use Shift to extend it, or click row/column headers. **Ctrl+A** selects the populated extent. Drag the active cell's small fill handle to complete one fill transaction. Edit also provides Fill Down and Fill Right.
- **Ctrl+C / Ctrl+X / Ctrl+V** use bounded, quoted UTF-8 TSV externally and typed cells internally. Internal formulas shift relative references once; fixed and mixed references retain their meaning. A dedicated clipboard format identifies internal copies; identical plain-text content from another application remains external TSV.
- Data / Lineage shows computed values, units, source Dataset and Variable IDs, original row identities and provider interpretation. Errors remain visible and editable. Long cell previews are bounded; the stored source/formula remains intact.

**View → Viewer configuration…** uses the shared Configuration editor for User defaults and Session overrides, including inspector visibility/width, grid font and density, individual column widths, numerical display format/digits and command shortcuts. Text formatting changes no canonical value; integer strings retain their exact precision. Navigation and hover do not create scientific History steps.

## Sheets and table preparation

Sheet tabs sit below the grid. **+** creates a sheet; Insert provides rename, duplicate and guarded delete, plus row/column insertion and deletion through the reference-aware model. A deleted sheet cannot reappear after Save/Open. Structural changes that would invalidate a captured guided operation require explicitly unlinking that operation first.

**Data → Columns / Ranges…** sets a column display name/unit or a named range. For example, name column B `Voltage` and define `voltages` as B1:B10; formulas can use `=numeric.mean(voltages)` or `=Voltage[2]`. A acts on A only; AA and AB retain their separate identities. Renaming a sheet updates parsed references while preserving quoted text.

**Data → Sort / Filter…** performs bounded table preparation on the Workbook snapshot. Sorting and restoring source order preserve exact source-row lineage. Filtering hides rows without renumbering them or rewriting a Dataset. **Convert Unit…** applies an explicit compatible CORE Unit Registry conversion to the selection; incompatible or opaque semantic conversions reject.

## Durable History

Undo/Redo and Previous/Next/Return to latest use the shared CORE Scientific Recipe History. The timeline, Details and explicit Branch / Restart here operate on the same retained semantic steps. Browsing is read-only until an explicit branch is confirmed. Cancelling that confirmation leaves scientific state unchanged. Clear History is guarded and offers an external Workspace backup first.

Cell, paste/fill, sheet, Dataset binding, sorting/filtering, unit, operation and chart edits are recorded as semantic actions. One completed drag or paste is one step. Published Datasets, external exports and published Graphs are explicit side effects and are not silently deleted by local Undo. Save/Open retains History; it is not a process-local list of twenty snapshots. The CORE limit is 4096 steps and an 8 MiB recipe; larger saved scientific checkpoints use the existing Document-owned resource authority. Large unsaved work must be saved before managed scientific execution or resource-backed checkpoints.

## Formulas and calculation

References can be relative (A1), fixed ($A$1), or mixed (A$1, $A1). Copy and Fill shift only relative row or column parts. Formulas support arithmetic, comparisons, parentheses, ranges (A1:B10), named ranges, named columns, cross-sheet references, and formula-safe functions. Enable **Pick cell/range reference** in the left editor, then click or drag in the native grid to insert one cell or range. The green reference highlight preserves the formula target; releasing the pointer returns focus to the editor. **Ctrl+Space** completes a function, range, column or sheet name when there is one matching public candidate; otherwise the status line lists candidates.

~~~text
=B1-$J$1
=numeric.mean(B1:B10)
=numeric.mad(B1:B10)
=Sheet1!A1+$B$2
=field(signal.convolution.linear(A1:A3,B1:B2),"value_real")
~~~

Scalar results occupy one cell. A vector spills downward and a matrix spills across rows and columns. A blocked destination reports #SPILL! without overwriting an occupied cell. Blank, boolean, text, numeric, missing, Dataset-bound, and derived cells remain distinct.

Statistical scalar formulas (mean, median, extrema, sum, population/sample
variance and standard deviation, RMS, quantile, covariance, correlation and MAD)
retain the shared CORE interpretation of the Numeric result. For example,
sample variance of voltage has unit V²; a single observation has an explicit
undefined variance. **Data / Lineage** displays its meaning and reason. Units
must agree within an aggregated vector or range, including undeclared units.
Arithmetic, cell references and spills retain the statistical inputs and source
Dataset/Variable identities. The inspector distinguishes those inputs from the
cell's final transformed value. Publication preserves the captured interpretation
and links it to output cells without repeating the numerical calculation.

Structured `field(numeric.statistics(B1:B10),"variance_sample")` and the
corresponding guided operation retain the same interpretation. Quantile vectors
keep their probability order; parameter uncertainty vectors keep each parameter's
own unit. Guided output stores its captured interpretation once with the saved
operation. Save/Open and publication reuse it; explicit operation recalculation
uses the current inputs. A manual cell edit replaces that cell's statistical claim.
Undefined or unavailable output remains explained by the captured reason.

PCA component summaries retain ordered component identities in one compact CORE
table; both formulas and guided outputs preserve the selected component through
spills, Save/Open and publication. A zero spectrum has undefined explained ratios,
shown as `NaN`; inspect the cell for the reason. Propagated uncertainty vectors and
covariance matrices retain positional output identities. Their physical output
units stay `unspecified` when the Worksheet inputs do not declare them; the
Jacobian's unit is not sufficient to identify heterogeneous output units.

Dataset statistics, weighted summaries and polynomial fits retain their recorded
Variable units and source lineage even when the operation uses Dataset IDs
instead of imported cells. Named Selections are resolved before execution;
publication retains their ID with the captured calculation. The shared typed
model path also applies named Selections to nonlinear fits.

Fields outside the captured CORE interpretation retain their public provider
values without being relabelled as interpreted statistical quantities. Arithmetic
and compatible conversions use CORE's Unit Registry and dimensional plans.
Unspecified dimensions and inference requiring undeclared assumptions remain
unavailable, even when a provider supplies a candidate numerical value.

**Formulas → Automatic / manual mode** changes the calculation mode. Automatic recalculates after edits. Manual leaves cached results until explicit Workbook recalculation is selected. Guided operation definitions retain their inputs, options, result field, and destination for recalculation. The calculation mode is saved with the workbook.

The formula parser accepts only its documented data grammar. It does not evaluate Tcl, Octave, Python, shell commands, callbacks, or macros. The vector, matrix, complex, record, empty, and field helpers construct data-only operands and inspect structured scientific results.

## Bind a canonical Dataset

Choose **Data → Bind Dataset…**, select a current Session Dataset and one or more canonical variables, then set the destination column/row, optional Dataset Selection and row limit. The picker shows actual Variable IDs, kinds, names and units; destination columns extend through ZZ. Explicit `A=variable_id B=variable_id` mapping remains available.

Binding reads public Table Stream pages and copies a snapshot of at most **20,000 source rows per binding**. Each bound cell retains Dataset/Variable identity, absolute source-row ordinal, optional Selection, unit and original value. Rebind explicitly to refresh a changed source. CSV and supported HDF5 paths use the same canonical access authority; no physical column position is inferred.

## Functions and managed scientific operations

Open **Functions** or press **F3**. Search the public operation catalog and select a function to read its provider, signature, typed inputs, shapes, units, result fields and applicability. **Insert formula** places its name in the docked formula editor. The guided editor stays in the left pane: enter cells/ranges/literals, options or a provider-owned declarative model, then choose Preview fields and an output cell/field.

Save the Workspace before submitting a managed operation. Preview/Apply use existing CORE Script Jobs, with real status, retained logs and **Cancel operation**. A captured result is not recomputed merely to inspect or apply a different permitted field. Changed inputs, a replaced editor, changed document or Session prevent stale adoption. Job tickets can be saved in the Workbook and explicitly recovered through **Recover saved scientific Job** when their canonical owner and scientific inputs still match. Closing a Viewer does not reassign its Job or scientific result to another Session.

The Worksheet calls public Numeric, Signal, RF Network and Magnetics providers; it implements no independent mathematical solver. Foundation actions are listed individually. Process settings and metadata-only contracts are not cell calculations. Callback operations require provider-owned safe declarative models.

## Live native charts and Plots

Select a table range, then choose **Insert → Native chart from selection**, or use **Add selection** in the Chart tab. Source columns extend through ZZ; each chart uses an explicit bounded row interval of at most 20,000 rows. Several live Native2D charts can share the resizable chart area. Drag a chart header to move it or its lower-right grip to resize it. Click a native point or object to select it. Wheel zooms, middle-button drag pans, and double-click fits the complete selected source.

The left Chart tab edits the title, X/Y and right-Y columns, source rows, representation, line/marker style, legend, axis bounds/scales and text annotation. Its property form scrolls independently. Compatible Y units are explicitly converted for a common display through CORE Unit Registry; original values, units and source-row lineage remain intact. Incompatible dimensions require separate panels or an appropriate independent right axis. A completed move or resize is one History transaction. Workspace Save retains every chart descriptor and layout.

**Publish immutable Graph to Plots** first publishes a canonical immutable Dataset with exact scientific provenance, then its native Graph variant. Later Workbook edits do not alter that retained Graph. Existing Plots actions, including Info, Notes, USE, rerender, Clone/Edit and portable export, retain the native owner. **Publish and open authentic Native3D** additionally requires a genuine Z column and uses the existing Native3D host.

## Publication and errors

**Data → Publish Dataset…** publishes a standalone canonical Dataset through the existing publication workflow. **Data → Charts / Publish…** restores the left inspector and opens its native Chart tab. Save the Workbook first. Canonical Dataset publication records exact source Dataset/Variable IDs, selected original rows, units and derivation lineage. A committed Dataset remains a real result if a later graph/export phase fails; the reported receipt identifies partial completion. Live charts use the public native v4 owner described below; existing standalone v3 consumers remain unchanged.

A parse error preserves its formula source. `#CIRC!` identifies a dependency cycle, `#REF!` a missing reference, `#UNIT!` incompatible units, `#SPILL!` a blocked output region and `#VALUE!` unsupported data or arguments. Correct or cancel the draft; use Data / Lineage for details. Missing, explicit NaN, text, complex and finite numeric values retain their distinct meanings.

The address domain is not an unlimited operation size: formula ranges and guided spills are limited to **20,000 cells**, selection statistics to **5,000**, formula text to **8,192 characters**, and clipboard input to **2 MiB**. A native value fetch is at most **4,096 cells**. Captured unsaved statistical vectors retain the **8,192-row** limit. These bounds produce explicit errors rather than silent truncation. Statistical summaries include finite compatible scalar inputs and explain omitted/unavailable content through CORE semantics.

## Worked scientific examples

In a disposable statistics Session, bind X and measurement variables into A:B, save the Workspace, then choose `numeric.statistics` in Functions. Preview B1:B10, select `mean` and apply at J1. Enter `=B1-$J$1` in F1 and fill F1:F10. The original example with mean **2.9** produces **10.1** at F10. A regression column can use `=$J$2+$J$1*A1` and Fill Down.

For mixed text/numeric data, bind the canonical identity, family parameter and scientific coordinates together. Inspect retained source row IDs, sort/filter the snapshot, then Restore order. Units, text and provenance remain linked to their actual sources. The source Dataset bytes are unchanged.

## Integrated spectral powers and Welch summaries

`numeric.power_level` expects already integrated, nonnegative spectral band
powers. Declare their actual column unit (for example `V^2`). The RMS reference
is a numeric magnitude in the derived RMS unit (`V` in this example). CORE keeps
power, RMS and dB meanings separate, and explains the undefined finite level at
zero power in the cell inspector. This function does not integrate a PSD or
establish sampling uncertainty. The captured result does not invent PSD provenance.

Ranges are vectors. Use `matrix(A1:B2,2,2)` for a rectangular input; values follow
Workbook row order. Guided and formula power fields preserve this shape and
record input row/column identities. Saved guided operations retain their CORE table
and undefined states through reopen and publication without repeating the calculation.
Formulas retain their established automatic or explicit recalculation behavior.

`numeric.welch_aggregate` takes summed normalized one-sided PSD and amplitude
vectors plus `window_count`, `frequency_step_hz` and `enbw_sum_hz`. The first bin
is DC. Declare both input units; incompatible PSD/amplitude units reject. CORE
supplies the units and interpretation of the scalar aggregate fields.

The provider adapter converts row-ordered real and complex Workbook matrices
to the public column-major transport convention. Nonsymmetric matrix values keep
their original positions. Saved derived values are preserved; explicit
recalculation uses the current inputs and provider. Source data remain unchanged.

### Matrix summaries

Guided `numeric.matrix_statistics` and `numeric.reduce_summary` preserve the
actual output orientation. Dimension 1 yields a row; dimension 2 yields a column.
Their shared input count is one scalar. Formula `field` results expose the whole
array at the anchor and scalar components in the adjacent spill cells. Source
units, squared variance units and undefined singleton sample spread come from
CORE; saved guided results and Dataset metadata retain those receipts. The cell
inspector explains unavailable values. Signal `statistical_contract` describes
an API and is excluded from Worksheet calculations.

### Signal summaries and physical units

Signal basic quality, supplied-noise SNR, coherent harmonic/spectrum quality,
correlation peaks/delays, event periods, pulse metrics and window gains use the
public Signal contract and shared CORE interpretation. Formula `field` and guided
operations retain that meaning through cell inspection, save/open and Dataset
publication. A missing correlation sample rate exposes delay in seconds as
unavailable; it does not manufacture a finite time. Capturing a result does not
run the estimator again.

`complex(real, imaginary)` requires matching physical units and preserves them.
SNR requires matching signal/noise units. Correlation permits different units and
uses the CORE product or dimensionless normalization. Event and pulse time
coordinates must declare `s`; use explicit unit conversion for `ms`. Supplied
threshold/hysteresis units must match the measured signal. Sample-rate and
fundamental-frequency parameters accept bare values in their documented Hz unit
or values explicitly labelled Hz; convert kHz first. Window coefficients are
dimensionless. Undeclared signal units remain explicitly unspecified in CORE.

Raw fields outside the captured CORE mapping retain their provider meaning;
a contributor receipt does not relabel them as interpreted statistical quantities.

### Captured spectral rows

Periodogram, Welch PSD, amplitude spectral density, cross spectrum, coherence,
and H1/H2 frequency responses retain per-frequency CORE meaning and physical units.
A saved Worksheet captures the full result once in binary columns owned by its
existing Document. Unsaved Workbooks support compact results up to 8192 rows;
save the Workbook before requesting a larger spectrum.

Choose **First result row** (starting at 1) and **Number of rows** in the guided
editor to select a bounded result window. A blank count selects the whole field,
subject to the Worksheet's 20000-cell spill limit. Formula
`field(result,"imag",16385,3)` selects three rows starting at result row 16385.
The existing two-argument `field` form selects the whole field. Shared scalar
facts such as sample rate remain scalars. The inspector reports original result
row identities, units and unavailable-value reasons from CORE.

The public Tcl call is `applyOperation book operation inputs options destination
field ?model? ?outputWindow?`. Its optional output window is
`{start ZERO_BASED_OFFSET count ROW_COUNT}`; persisted operations keep that window
beside the unchanged canonical field identifier. Existing calls retain their defaults.
Windows apply to captured statistical vector fields and accept 1–20000 rows.

Unchanged Preview and Apply share one captured calculation. Editing inputs or the
selected output during calculation prevents stale adoption. Saved guided results
reopen without an estimator call; published selected values carry the full captured
binding as provenance. Formulas recalculate normally and save their latest resource
references as provenance. Resource reads use the public CORE owner and bounded
pages; presentation caches clear on reopen and recalculation.

### Accumulated summaries

A scalar result from `numeric.reduce_summary` or `numeric.reduce_accumulate` can
be passed as the first accumulation operand. For example,
`field(numeric.reduce_accumulate(numeric.reduce_summary(A1:A2),A3:A4),"mean")`
combines two blocks through the public Numeric owner. The guided editor accepts
the same source expression or a reference to a cell holding the summary result.
`empty()` initializes a state. Explicit records need dimensionless `count` and
`sum`, `min`, `max` in the new observations' physical unit. Captured state facts,
identity and units are checked before calling Numeric. A non-scalar axis summary
cannot silently become one scalar state. Convert observations before summarizing.
Both source and accumulated receipts survive guided save/open and publication.

### Foundation location estimates

Guided `numeric.foundation.statistics.confidence_interval` and
`numeric.foundation.statistics.robust_location` retain CORE units and meaning.
The former accepts `alpha`; the latter accepts `huber_constant`. In formulas,
options are the fourth operand, after explicit `empty()` placeholders, for
example `field(numeric.foundation.statistics.confidence_interval(A1:A10,
empty(),empty(),record("alpha",0.1)),"lower")`. The inspector explains singleton
undefined confidence limits and distinguishes a Huber scale from mean uncertainty.
Captured guided results persist and publish without re-running the estimator.

### Seeded foundation inference

The foundation bootstrap/permutation actions accept an explicit integer `seed`
and `replicates` (at least 100); bootstrap also accepts `alpha`. Guided operations
and formula option records use the same public call. Permutation samples must
have matching physical units. Saved results retain the seed, method, source
counts and actual conventions. CORE explains why singleton groups or degenerate
bootstrap distributions cannot establish the requested inference. Publication
uses those captured receipts without another randomized run.

### Partial correlation and multiple testing

`numeric.foundation.statistics.partial_correlation` takes two aligned measured
vectors and control columns. Their units may differ; the coefficient is
dimensionless. CORE records covariance rank and distinguishes ordinary partial
correlation from the descriptive pseudoinverse coefficient for singular inputs.
An invalid normalization appears as unavailable numeric content with an explicit
undefined reason in the cell inspector.

`numeric.foundation.statistics.multiple_testing` accepts dimensionless p-values.
In the guided editor, enter a quoted method expression such as `"holm"` for the
`method` option. `adjusted_p` spills in original input order; `family_size` is one
shared scalar. In formulas use, for example,
`field(numeric.foundation.statistics.multiple_testing(D1:D6,empty(),empty(),
record("method","bh")),"adjusted_p")`. CORE retains method-specific FWER/FDR
assumptions and hypothesis positions through guided save/open and publication.
No second adjustment is performed during presentation or publication.

### Survival curves

`numeric.foundation.statistics.survival_kaplan_meier` accepts observed coordinates
and dimensionless event indicators (one for an event, zero for censoring). Declare
the coordinate unit on its input column. The result includes `time`, `survival`,
`at_risk`, `events`, `censored` and the shared observation count `n`. Coordinates
with censoring only remain in the curve. CORE states the right-censoring and
independence assumptions; no confidence interval is supplied.

Save the Workbook to capture survival or multiplicity output in canonical binary
Document resources. The guided result-row controls and four-argument `field`
syntax select bounded rows using the same conventions as spectral results.
Saved guided values reopen and publish with their full captured binding without
another estimator call; formulas retain their normal recalculation behavior.
Unsaved compact curves/tables retain the 8192-row limit.

### Covariance diagnostics

For `numeric.foundation.statistics.covariance_diagnostics`, construct a matrix
with observations in rows, for example `matrix(A1:B4,4,2)`. A vector input is
one variable. Select `covariance_real` or `covariance_imaginary` for the CORE
matrix component; `eigenvalues_real` and `eigenvalues_imaginary` expose the native
spectrum. Original raw provider fields remain available. Explicit components
preserve complex meaning without treating a whole complex matrix as its real part.

CORE retains matrix entry identities and product units through spills, guided
persistence and publication. Eigenvalues have squared units only for common-unit
variables; their ordering is a spectral position, not a variable-specific variance.
The inspector explains why a singleton has undefined sample covariance even
though the underlying provider returns a zero placeholder. These diagnostics do
not supply fit-parameter uncertainty or a statistical significance test.

### Clustering and regression results

For `numeric.foundation.statistics.kmeans`, supply observation rows and explicit
`seed` and `clusters` options. `centroids` is a cluster-by-feature matrix;
`cluster_counts` and `within_ss` follow its row identities. `labels` are integer
identifiers in original observation order, not continuous measurements. Guided
row windows and the four-argument `field` syntax retain the original observation
position. The inspector shows the corresponding cluster identity. The native
provider supplies no selected-solution convergence status; requested starts do
not establish a global optimum.

The existing `robust_regression`, `logistic_regression` and `glm` actions take
a design matrix and response as their first two operands. Include any intercept
column explicitly. Robust residuals use the response column's physical unit.
Logistic responses are zero/one; GLM accepts binary logit or nonnegative integer
Poisson counts. These response columns must be dimensionless. CORE interprets
the actual method and family, iteration count, stopping flag and coefficient
components. Complex robust estimates retain explicit real/imaginary fields.
Unknown coefficient units remain unspecified instead of copying response units.

Select `probability` or `fitted_mean` for dimensionless response predictions,
or `residual`, `residual_real` and `residual_imaginary` for supported robust
residuals. Guided results save the original selected values and interpretation;
reopening or publishing them does not fit again. Formulas retain normal
recalculation behavior. The inspector includes CORE's definition of each scalar
diagnostic: satisfying the numerical stopping criterion does not establish
statistical identification, finite maximum likelihood or inferential coverage.
These foundation routines do not provide parameter covariance or intervals.
