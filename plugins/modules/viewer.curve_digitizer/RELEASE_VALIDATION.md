# Curve Digitalizer 2.0.5 — corrected GitHub-based packaging

SPDX-License-Identifier: GPL-3.0-or-later

Authoritative GitHub baseline: giuxlab-hub/GX-TXT commit c84faff8a87d,
Curve Digitalizer 2.0.3 (GX-TXT dev098), 90 SHA256-confirmed source files.
Changes:
- Opt-in assisted tracing smoothness, red-X exclusion paths and calibration identification.
- Public viewer discovery: semantic_group=images, group_title=Imaging & Documents.
- ZIP internal entry names use / with proper api/, python/, tests/ directories.
- Plugin version: 2.0.5; baseline APIs and numerical model otherwise retained.

Archive integrity is checked after extraction using all SHA256SUMS entries.
Dynamic GUI/Tk, Numeric, and GLS/ODR integration tests remain pending.
No framework source was modified; zero-pixel Numeric integration is separate.

## 2.0.6 tests and integration caveat

Verified source baseline: GX-TXT Curve Digitalizer 2.0.5, itself rebased on GitHub Curve Digitalizer 2.0.3 (dev098 commit c84faff8a87d). No framework CORE source changes.

Hermetic tests tests/test_exclusion_undo_206.py exercise legacy path migration, stable IDs, path toggle, node drag as one undo transaction, clearing paths and preference checkpoints. tests/test_unified_history_206.py extracts and runs the real 2.0.6 Undo/Redo methods without Tk and verifies interleaved edits, branch invalidation, drag preimage and Session guard. The installed GUI must still be tested with actual mouse interactions, user Sessions and Numeric assisted proposals.

The Numeric provider patch to support exactly-zero pixel uncertainty, managed covariance and Fitter GLS/ODR tests remain separate integration tasks and are not claimed here.

## 2.0.7 icon restoration
The two icon assets are original GitHub blobs from giuxlab-hub/GX-TXT under plugins/modules/viewer.curve_digitizer/icons/: PNG 9,056 bytes, blob caeeef9fcb7f40a7c48a56bac0058d45aca65696, and SVG 1,227 bytes, blob 00f9707dd785ca0bc467228d90032f010fb04794. The package descriptor explicitly references the existing PNG; no substitution or regeneration of the artwork occurred.
## 2.0.8 validation scope
The new stroke-width diagnostics live entirely within the viewer package and expose a read-only CURVE_DIGITIZER_STROKE_WIDTH_API_v1, leaving the public CORE unchanged. Existing Curve/Quality/Uncertainty/Calibration APIs and source-image/digitization dataset behavior remain intact. The original icons restored in 2.0.7 are preserved.

All tests are isolated package checks unless separately confirmed within the installed host. The full GUI/Tk, Numeric and Fitter integration must be tested in GX-TXT dev108. The Numeric provider zero-localization patch remains a separate framework task.

## 2.0.9 additional verification
Two new headless tests exercise the actual GUI `on_curve_selected()` method through a minimal harness. All prior bundled 2.0.6 and 2.0.8 headless regression tests passed against the updated 2.0.9 tree (18 test cases across six files). The public Stroke Width API was also exercised with Tcl 8.6 under a stub of public CORE calls, confirming read-only configuration, curve and Dataset metadata access; synthetic raster tests demonstrate line-width estimates but not instrument uncertainty. Final archive SHA256SUMS and structural ZIP checks are required and recorded separately before installation. Actual installed GUI/CORE/Fitter integration remains pending.

## 2.0.12 — Isolated packaging and regression

Exact installed baseline: GX-TXT DEV111-r3, viewer.curve_digitizer 2.0.11,
including local Workspace integration patches. The installed source is not
modified. Regression covers short window heights, nested wheel routing and
the existing calibration management controls. Full host validation requires
installation by the user; no framework CORE modification is involved.

### 2.0.13 — Reproduction and remediation

Screen evidence showed "Constraints changed. Generate a fresh proposal before
accepting" after an exclusion edit. The guard is scientifically correct; the
previous UX did not clearly link it to the mandatory Propose/inspect/reaccept
workflow. The original implementation also required a proposal in the hit
test, so orange guides could not be moved/deleted before the first Propose.
This release keeps stale acceptance fail-closed and fixes early guide editing.

Baseline is the 2.0.12 isolated package derived from the installed GX-TXT
DEV111-r3 2.0.11 with its Workspace bridge; the installed copy remains untouched.

Verified on 2026-10-29 (isolated Tk tests, not installed GX-TXT):
- PASS: tests/test_guides_before_proposal_2013_gui.py: early Move/Delete,
  Unified Undo/Redo, two active exclusion paths, Strong smoothing, stale
  acceptance refused, pending asynchronous Propose refused, new candidate
  produced using the normal Propose/poll path, exactly 64 points accepted.
- PASS: tests/test_calibration_scrolling_2012_gui.py, retained short-window GUI.
- PASS: tests/test_curves_scrolling_1229_gui.py, nested scrolling.
- PASS: test_stroke_curve_switch_209, test_assisted_constraints_205,
  test_exclusion_undo_206, test_unified_history_206,
  test_assisted_tracing_advanced, test_assisted_tracing,
  test_stroke_width_208, test_stroke_companion_208.
- SKIPPED: test_assisted_sampling_1223.py requires optional pytest not
  installed in this environment (ModuleNotFoundError: pytest).
- Full installed GX-TXT integration and complex real-image tracing remain
  operator acceptance steps, not claimed by isolated synthetic tests.

## 2.0.14 — Scientific mode activation and display

The installed GX-TXT module remains unchanged. Exact original generator
raster re-rendered from registered generator source for independent tests.
With 502 candidate points per curve, c5/c15 gave:
Off vs Gentle: 6 positions >0.01 px; maximum 1 px; mean 0.011952 px.
Off vs Strong: 32 positions >0.01 px; maximum 2 px; mean 0.071713 px.
These are algorithmic proposal differences, not accuracy or uncertainty.
The GUI now automatically updates an unaccepted proposal on mode selection,
and explicitly reports the applied mode and resulting preview displacement.

Verified 2026-10-29 (isolated package, no installed GX-TXT modifications):
- PASS test_smooth_prior_effect_2014.py: Off/Gentle/Strong return distinct
  real numerical paths on a synthetic two-stroke raster.
- PASS test_smoothing_mode_refresh_2014_gui.py: changing a combo option
  automatically requests the correct replacement through Propose and
  asynchronous Numeric fit; the old candidate remains non-acceptable until
  resolved, status exposes applied mode and numerical displacement.
- PASS test_guides_before_proposal_2013_gui.py and
  test_calibration_scrolling_2012_gui.py and test_curves_scrolling_1229_gui.py.
- PASS test_stroke_curve_switch_209, test_assisted_constraints_205,
  test_exclusion_undo_206, test_unified_history_206,
  test_assisted_tracing_advanced, test_assisted_tracing,
  test_stroke_width_208, test_stroke_companion_208.
- Full installed host/source-image operator acceptance remains pending.
- Numeric smooth search itself was NOT rewritten: altering strong prior
  solely to force visible differences on a genuinely smooth curve would
  distort data without justification.

## 2.0.15 — Source-pixel interaction and stale-candidate regression

Real Tk tests exercise identical image points under varying zoom/pan and check
selection/placement invariance. Stale-candidate guards protect against mixed
segments when exclusions or smoothing are changed; an explicit fresh proposal
is required before editing. Source-corrected reconstruction is verified to
preserve non-target segments and accepted scientific point sets. Validation
uses only an isolated copy and no installed module or CORE modifications.

Verified 2026-10-29:
- 16 Python/Tk test groups passed on the isolated 2.0.15 source tree.
- GUI regression covers 1x/4x/8x zoom, pan, 6 source-pixel hit
  selection, actual Tk pointer-to-raster mapping, far correction placement,
  calibrated interval selection, reversible source pixel edits and stale
  proposal rejection.
- Exact calibrated_curve_family generator raster tested at curves c5/c15;
  insertions at px=420 and 720 preserved non-target proposal segments.
- Regression retained early guide Move/Delete, Off/Gentle/Strong modes,
  scrollable Calibration, Curves scrolling, Undo/Redo and stroke width tests.
- Full real host/Session integration remains user acceptance; scientific
  model APIs unchanged and no local GX-TXT installed or Session data changed.

### 2.0.16 — Configuration workflow regressions

Version 2.0.15 installed tree used as immutable source. Tests are run from
a separate copied module, with a fake GX-TXT RPC for controlled rollback
and name receipts. The normal Tcl handler calls existing public
sessionWorkspaceRename without changing CORE. JSON and catalog name updates
are separate operations: rollback is attempted and a failure explicitly
reported, not represented as a guaranteed transaction.

## Final isolated 2.0.16 test report — 2026-10-29

Test execution: **18 groups PASS, 0 FAIL**. Includes real Tk
test_workspace_config_2016_gui.py with stubbed host receipts and
test_workspace_rename_2016.tcl with the actual production Tcl handler
executed against a mocked public sessionWorkspaceRename.
Regression tests cover prior 2.0.15 source-pixel proposal edits, normal
and far correction, reversible guide editing, 2.0.14 smoothing, 2.0.12
Calibration scrolling, original tracing and stroke diagnostics.

Verified scenarios: pan/zoom alone never prompts Save/Discard; explicit Save
persists view; Notes remain dirty; Duplicate Yes/No/Cancel; distinct
configuration identity; native Workspace name and configuration JSON name
match after Rename; stale-generation, stale-SHA and duplicate-name rename
refused; failed second-stage JSON save triggers attempted native rename
rollback; external window FocusOut saves; queued callbacks cannot overwrite
a reviewed/discarded draft or a different document; internal modal grab does
not autosave.

Not represented as verified: real host/session Workspace native C++ runtime,
concurrent external rename, or failure of a compensating rollback after a
successful native rename but unsuccessful JSON update. The latter fails
visibly and requires reopening/review; no hidden fallback or CORE change.

## 2.0.17 — Analytical reference regression and limitations

Exact synthetic source from the registered calibrated_curve_family generator:
1201x1001 px, 50 closely spaced color-coded curves, original one-pixel stroke,
curves c5 and c15. Three guides at raster x=100,600,1100; Corridor=6 px,
Step=2 px; candidate positions are compared in ORIGINAL raster pixels against
the mathematical generator reference. This is an algorithmic benchmark, not
a metric of measured physical accuracy.

Old 2.0.16 observed approximately RMS=2.95 source px with Strong and 500/503
points >1 px away, often selecting adjacent white pixels.
Repaired 2.0.17 Strong: 503 points, RMS ~0.000 source px with exact guides
on c5/c15; shifted operator guide positions ±1/±2 px have RMS <=0.18
px on the same raster and unchanged guide endpoints. Both curves passed
correction insertion at x=420 and 720, preserving unaffected segments.
A separate 83-guide experiment reconstructed 82 spans without the old
piecewise-chord artefact, within its analytic test tolerance.

The package tests include original GUI behavior and native Workspace mock
tests. Full installed host testing and validation on actual datasheet images
are not claimed by this analytical fixture.

### 2.0.18 — Extended Step acceptance and scientific trade-off

The isolated test suite evaluates Step=2,5,10,15,20 with the exact
calibrated_curve_family synthetic image and both c5/c15. In a
two-interval, 1000-pixel source span the candidate point counts are
503,203,103,69,53. All tested candidate paths with exact
guides and Strong prior had approximately zero RMS error against
the known analytical geometry. Benchmarked single-run runtime
on the workstation decreases from ~0.52 seconds at Step=2 to
~0.07 seconds at Step=20. These figures are not general estimates
of runtime and do not imply accuracy on arbitrary raster sources.
The result must be separately inspected by the operator.

## 2.0.19 — Per-curve Exclusion persistence UI validation

A real Tk application is loaded against an in-memory fake GX-TXT native
document RPC, with two distinct curves and independent exclusion paths.
The test checks serialized JSON, native document reopen, curve selection,
visibility, enabled state and restoration of both curves. No real user
Session, dataset, Workspace or CORE files are touched.

## 2.0.20 — Publication classification contract

Test against 1201x1001 raster with full-image BL/BR/TL/TR and declared
X='s', Y='V', three physical calibration realizations k0/k1/k4 and three
source curves c5,c15,c25. The Python caller passes the manifest's verified
scientific classification to the Tcl publisher, not a legacy geometry hint.
Synthetic 900-row combined call and preserved refusal of mismatched classes
are checked without touching CORE, real Session datasets or the installed module.
