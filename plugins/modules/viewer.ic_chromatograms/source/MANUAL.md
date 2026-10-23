# IC chromatograms — canonical consultation 0.1.2

Working supported slice authored with the official Builder/Development Workspace.
Actual installed GUI, seven-trace interaction and performance are NOT_TESTED.
Single-source baseline correction uses the public Transform owner. Saved study membership, peak chemistry and calibration are unavailable.

Open the Session containing the seven original CHW imports. Select each intended
trace explicitly: the accepted developer QA Session also has synthetic AIA data.
Discover variables, choose time_s (s) or time_min (min) and signal_value (uS/cm),
then Bind selected trace. Immediately choose Refresh traces to populate the
existing trace and target panel selectors; Load trace controls copies the first
trace identity/options into the editor. For another trace, retain the populated
target panel and use Add selected trace; Bind selected trace starts a new Plot
and replaces the current overlay. ADC is the exact signed integer source channel with unit1,
not conductivity. Source canonical data are never rewritten by this Viewer.

To overlay another related acquisition, select its canonical trace, Discover and
choose compatible X/Y. Set its source-identifying legend label and Add selected
trace. Use Refresh traces / Load trace controls to inspect an existing series.
Enabled is staged: Apply update commits visibility and other selected trace edits.
Remove trace changes the Plot, not source data. To make a separate panel, enter
Title for new panel, then Add panel with title; choose its target when adding or
updating traces. The title field applies to new panels only. Remove empty panel
accepts only an empty, unannotated panel while another panel remains.
X/Y scale controls apply only to Bind selected trace, which replaces the Plot;
Add selected trace and Apply update preserve existing panel axis settings. Fit, Zoom, native pan/wheel and
source-point release use existing Plot owners. No silent resampling, time shift,
calibration or concentration inference is performed by raw consultation.

The seven originals have10800 samples each, source interval0.10000000149011612s,
channelCond and unituS/cm. Common experiment membership is the user's assertion;
retain seven individual source/Dataset identities. Native peak strings are source
annotations, not verified analyte assignments. No wavelength/mass axis exists here.
Public Plot may reduce display points while preserving full canonical source rows,
bounds and exact source-row inspection; display points are not new measurements.

Partial limitations: generic canonical numeric table selector, explicit manual
experiment membership and no saved study/Workspace. The baseline form is limited
to one original-coordinate source; study lifecycle remains an owner request.
Preserve RAW/source and review the visible baseline parameters.

Native developer event tests verify compiled typed plans only. They are not GUI,
canonical import, scientific/vendor comparison or responsiveness acceptance.
MAIN alone integrates and schedules actual GUI/scientific acceptance. Installed
packages use their prebuilt native runtime and do not invoke a compiler.

## Explicit single-source baseline correction

Open Baseline correction using the footer control. Source and output holds a
separate source selector: choose the genuine source, Discover axes, then explicitly
choose distinct original floating X/Y with original units. For CHW use time_s and
signal_value; adc_count is an integer channel and is not an admitted baseline axis.
Enter a fresh output Dataset ID and review three fresh derived Variable IDs.

In Method and options choose asls, constant, linear or polynomial. Visible starting
values are generic and are not validated IC tuning. AsLS uses lambda/p/maximum
iterations/tolerance and the selected grid; constant uses the explicit scalar in
original Y units, linear uses its existing fit, and polynomial uses explicit degree.
Only the selected method parameters apply. No mean/median estimate or anchors are
implied. Nonfinite error refuses nonfinite pairs; explicit omit can create a gap
that fails uniform_x. Both AsLS grids require monotone unique X; uniform_x also
requires approximately uniform spacing. AsLS needs at least three rows.

Review the form and press Create corrected Dataset. Selection and Discover do not
calculate or publish a correction. Inputs disable while the owner runs; Cancel
correction and Inspect correction remain above the tabs. The footer control can
reopen a hidden panel. Cancel applies only to this captured operation before
commit; it cannot remove an already committed Dataset.

A successful correction retains all original columns and rows in a fresh canonical
Dataset, adds float64 baseline/corrected columns in original Y units and a uint64
zero-based original row column, and shows the actual canonical receipt. Result
shows original response, estimated baseline and corrected response from that
derivative. Baseline estimation uncertainty and induced correlation are not
propagated. Numerical convergence does not prove a chemically correct baseline.

Only ordinary local canonical sources, enabled rank-one float32/float64 axes with
nonempty original units and identity display/calibration are supported. Custom unit
formulas and nonidentity settings refuse; the Viewer does not reset them. No
sorting, resampling, alignment, chemical assignment or concentration is inferred.

COMMITTED_DISPLAY_FAILED means a genuine output was committed but later source,
window, provenance or Plot application failed. Keep its actual Dataset/result and
receipt; cancellation or rollback is not claimed after commit. The form checks
first/last row ordinals; complete row lineage needs separate scientific acceptance.

Actual normal GUI, Cancel/reopen/tab reachability, scientific output and response/
redraw latency acceptance remain NOT_TESTED until MAIN allocates and records them.
