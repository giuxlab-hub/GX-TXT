## 2.0.26 — Curve list column headings (2026-10-31)

- Restore every Curve Treeview heading when enabling or disabling the secondary Y axis; no scientific model, publication or CORE changes.

## 2.0.25 — F5 shared physical uncertainty for Y1/Y2 (development)

- A single four-corner geometric calibration supplies shared covariance
  sensitivities for scientific X, Y1 and optional Y2, without re-digitizing
  or altering the pixel-to-scientific transformation.
- The independent per-point 2x2 Jacobians and shared 2N x 14 parameter
  Jacobian retain eight corner coordinates, X min/max, Y1 min/max and
  Y2 min/max, including mixed linear/logarithmic scales. Monoaxis outputs
  retain the exact former 12-input form.
- Pixel/calibration declarations require 14 nonnegative standard
  uncertainties in dual-axis mode, versus 12 legacy. Physical override
  requires explicit independent X/Y1/Y2 standard uncertainties in dual-axis
  mode, versus the existing physical X/Y pair.
- Dataset publication uses the original ordered pixels and per-row y_axis_id.
  The analytic preflight and CORE Numeric API v1/Statistics semantics must
  agree on all physical sigma, XY covariance, and every retained local/shared
  factor before canonical publication is accepted.
- Compact uncertainty factors v2 retain all 14 shared parameters with a
  SHA256-verified, bounded compressed binary record. Reader v1 keeps the
  historical 12-input factor records, and F5 supports both.
- No uncertainty is inferred from image width, quality metrics, pixel
  dimensions or unreviewed uncertainty models. Multiple independent
  calibration realizations may be published separately, but uncertain
  combined multi-realization outputs remain explicitly disallowed.
- Dataset Group formation is unchanged. Correlation across Dataset
  boundaries is described through common calibration identities, NOT
  misrepresented as an already materialized cross-Dataset covariance.
- Source image, curve/pixel identities and scientific review fingerprint
  stay mandatory. Mixed scientific Y units cannot be hidden under one
  canonical Variable Schema Y column.
- GNU Octave 9.4.0 Numeric implementation validated against analytic
  Python results for both shared calibration and physical override models,
  including log-X/log-Y2; local Tcl Numeric transport validates 12/14 and
  the retained factor integrity gate without CORE modifications.
- F5 remains an independent development increment: final real-Session
  integration and old-Workspace compatibility admission await owner testing.

## 2.0.24 — Public Y1/Y2 metadata API and Dataset Group opt-in

- The existing Curve Dataset Schema public API v1 interprets curve schemas
  0, 1 and 2. New methods: axes, curves, describe and datasetGroup.
- External readers obtain normalized scientific metadata from this adapter,
  rather than decoding version-specific JSON or assuming fixed CSV columns.
- Publish adds an optional checkbox, OFF by default, to Group the canonical
  Datasets produced by axis- or calibration-separated publication.
- The actual registered Viewer retains its CORE-issued producer capability
  from the Viewer Provider context; its backend invokes P030 Group producer
  Review/Create. No private CORE issuer or host/admin fallback is used.
- Group errors are distinct from Dataset publication failures; single
  output publication creates no unnecessary Group wrapper.
- Historical Y1-only publication receipt identity/contract now fail closed
  instead of silently accepting a mismatched backend receipt.
- Companion Preview 0.1.6 uses public Y-axis row bindings and native Plot v4
  left/right axes with valid scientific logarithmic scales.
- CORE, existing Sessions/Datasets and installed modules are untouched.
  Real Session end-to-end Group acceptance remains a separate requirement.

## 2.0.23 — Inline calibration verification layout (development)

- Convert Projective calibration and verification from side-by-side columns to
  two full-width stacked sections in the scrollable Calibration tab.
- The upper section retains the four shared projective corners, Clear corners,
  calibration status and active measurement identity.
- The lower verification section initially occupies only its compact heading
  and Verify calibration button. It expands vertically in place when active,
  without creating a Toplevel window; the source raster remains clickable.
- Compact per-axis cards report physical reference, calculated result,
  physical residual and scale-aware percent or logarithmic-decades comparison.
  Scientific calculations and accepted input forms are unchanged from 2.0.22.
- Remove long usage explanations from the GUI; the authoritative instructions
  and log-axis examples are maintained in MANUAL.md. The verification stays
  temporary and does not update calibration or published scientific data.
- Add focused real-Tk geometry, screenshot and legacy regression tests.
  No CORE, dataset-contract or Preview changes; F4 public metadata API
  and optional Dataset Group work remains a separate future increment.

## 2.0.22 — Scientific calibration verification (development)

- Replace small inline Expected X/Y controls with a modeless verification
  window, keeping the original graph clickable and the marker temporary.
- Independent expected references for X, Y1 and optional Y2 in the declared
  physical units; blank references are explicitly not assessed.
- Parse scientific notation, decimal comma and explicit 10^n notation.
  For logarithmic axes enter positive physical values, not their logarithms.
- Show each axis scale/unit, expected value, calculated reading, physical
  residual and either relative error in percent (linear) or logarithmic error
  in decades and measurement ratio (logarithmic).
- Keep one shared four-corner calibration, preserve legacy verification summary
  identifiers for existing tests/scripts; no change to published Dataset formats.
- Verification is diagnostic only: never publish it as accuracy or uncertainty.
- This is an independent pre-release user-interface correction; the remaining
  F4 public read adapter, Preview/Plot and Dataset Group work is unchanged.

## 2.0.21 — Optional Y2 axes / F3 scientific publication (development)

- Implement optional logical Y1/Y2 with one shared four-corner homography.
  Viewer settings enables Y2, Calibration edits its own unit/limits/linear or
  logarithmic scale, and Curves binds each curve explicitly to Y1 or Y2.
- Versioned \`curve_schema_version=2\` scientific publications retain the
  canonical \`table.generic\` and \`curve_family.table\` contracts and preserve
  a rank-one X/Y scientific pair. When Y1/Y2 have the same physical unit, one
  Dataset includes all curves with per-row \`y_axis_id\`. When units differ,
  separate Y1 and Y2 Datasets are emitted; each Y Variable has one true unit.
- Calibration Separate/Combined layouts remain available. Each publication
  records stable curve IDs, original pixel and point IDs, calibration IDs,
  physical axis transforms and source provenance in versioned Dataset metadata.
- Preserve the previously published monoaxis v1 schema without extra columns.
  Existing old readers are expected to refuse schema v2 until the public
  Curve Digitalizer adapter and Preview are updated in F4.
- Shared correlated physical uncertainty for Y2 remains intentionally disabled
  pending numeric F5 review; Y2 quality is marked not assessed rather than
  claiming a scientific accuracy estimate. Optional Dataset Group creation
  remains the following F4 increment, using existing P030 public APIs.
- Intermediate development worktree only: validate with mock-host scientific
  publication and Tcl public-writer stubs before distributing any Viewer ZIP.

## 2.0.20 — Publication calibration class consistency

- Fix publication preflight on full-frame corner calibration with explicitly
  declared physical axes. Full-frame image geometry is NOT sufficient to
  classify scientific X/Y as pixel coordinates. The old caller sent
  `full_image_pixels` when x=s and y=V, while the scientific calibration
  manifest correctly classified the mapping as `affine`.
- Pass the exact, already-built calibration manifest classification
  (pixel, scale_bar, affine or projective) to the public GX-TXT publisher
  rather than deriving a second inconsistent hint from source geometry.
- Preserve Tcl legacy transport aliases but validate new canonical classes
  and reject an unknown classification. Do NOT weaken source SHA,
  accepted-calibration, grouping, axes, measurement ID, provenance or
  Session revision protections.
- No CORE changes and no access to actual user Session data.
- Add classification contract tests and a fully isolated GUI publication
  fixture for 3 curves x 100 points x 3 accepted calibrations.

## 2.0.19 — Per-curve exclusion list refresh

- Keep exclusion paths in the existing persisted Session configuration field
  `tracing_constraints.paths_by_curve`, keyed by stable Curve ID and
  bound to the source raster SHA-256.
- Fix the Curves Treeview selection callback to refresh Exclusion Paths
  immediately after switching the active curve. Previously the visible
  list could retain entries from another curve even though the paths
  were correctly saved and reloaded.
- Do not delete, migrate or duplicate any saved exclusion paths.
  The persistent/disabled path state, node geometry and scientific
  proposals stay untouched. The active table and canvas update together.
- Add a Tk configuration round-trip and curve-selection regression using
  an isolated fake document RPC. CORE and installed framework untouched.

## 2.0.18 — Extended assisted tracing Step to 20 source pixels

- Raise the maximum step from 10 to 20 original-image pixels in the Curves
  Spinbox, numeric guide sampling and the C1 reference path, using one
  shared min/max contract (0.5..20.0 source px).
- Validate manually entered values **before** dispatching a GX-TXT Numeric
  request. Prevent an invalid requested Step from starting an asynchronous job.
- Display the applied Step in the generated proposal status; keep existing
  2.0 default, source-image geometry, accepted scientific coordinates and
  publication contract unchanged.
- Do not conflate Step with **Output points (Accept)**: at Step 20 the
  known 1000-pixel span yields 53 candidate positions, while output 100
  resamples the candidate shape without adding new raster evidence.
- Validation compares Step 2, 5, 10, 15, 20 on curves c5/c15 against the
  known analytical generator with exact guides, and checks resampled 100-point
  output and correction/rebuild behavior. Step 20 is not a guarantee of
  improvement on any specific real or scanned image.
- No framework CORE modifications, no Session changes, no worktree changes.

## 2.0.17 — Assisted trace foreground targeting and C1 guide interpolation

- Correct a systematic failure on thin colored lines: 3x3 **median** samples
  around a single-pixel guide selected the white background as its expected
  grayscale/RGB target. This encouraged the DP path to track empty background
  parallel to the intended curve. Estimate the ink colour from an operator
  guide, preferring its own pixel when it is an actual foreground candidate;
  otherwise use a nearby foreground candidate without moving the guide.
- Replace piecewise-linear reference chords with chord-length, shape-preserving
  **C1 Hermite/PCHIP references** through the original guide coordinates.
  Reuse the guide-aware reference in Propose, local Repair, Insert correction
  and Remove guide. Existing fixed endpoints, limits and acceptance semantics
  remain unchanged.
- This is an optimization reference, not a filter or a replacement for the
  original image: all candidate costs still come from the original raster,
  and accepting scientific points remains an explicit user action.
- Retain independent Off/Gentle/Strong second-order search penalties,
  exclusion bands, assisted Numeric CORE advisory requests, per-Session
  Workspace configuration support, original GUI and public CORE APIs.
- New exact analytical family regression: c5 and c15, three guides and all
  smoothness modes, guide ±2px, optional corrections, and **83 guide points**
  were tested against the known source geometry. No CORE files, original
  source raster, Session or installed framework were changed.
- A previous test requiring visible displacement for every smoothness setting
  was corrected: equal paths for a uniquely recognized original curve are
  scientifically valid. A preexisting Tk mock was brought in line with the
  existing native Workspace generation/revision receipt contract.
- Limitation: tests on the known synthetic raster do not prove equal quality
  on low-contrast photographs, saturated overprinted curves or real scanned
  datasheets. Operators must still inspect traces and avoid claiming
  additional independent measurements from denser interpolation.

## 2.0.16 — Configuration save/duplicate/rename/FocusOut fixes

- Ignore view-only raster zoom/pan in Workspace review dirty comparisons.
  Explicit normal saves still retain the viewport.
- Distinguish Save, Do not save and Cancel; Duplicate after Do not save
  reads the last successful saved configuration, never unsaved GUI edits.
- Rename the canonical native Workspace name through the existing public
  Session Workspace API and return its new generation/revision receipt.
  Then save the matching configuration JSON, with an attempted native-name
  rollback and explicit error reporting if the second stage fails.
- Restore automatic FocusOut commits on leaving the application, without
  firing while an internal dialog or Workspace review is active.
- Preserve public scientific APIs, Source SHA, assisted tracing, the full
  2.0.15 proposal fixes, the installed DEV111 native Workspace integration
  and existing Session data. No GX-TXT CORE edits.

## 2.0.15 — Source-raster proposal interaction and correction guards

- Remove the zoom-dependent 60-screen-pixel proximity test for Edit proposal.
- Use 6 ORIGINAL SOURCE PIXELS for nearest guide/generated vertex selection,
  both in Move/Edit and context menus. ImageCanvas already translates Tk
  pointer positions into raster pixels, unaffected by zoom or panning.
- A distant click no longer captures a random path vertex; Add correction
  point is the explicit tool for corrections far away from the current trace.
- Do not allow local corrections, guide repairs or proposal deletion while
  the candidate is invalidated by changed smoothing/exclusion constraints;
  first regenerate one coherent candidate through Propose.
- Validate inserted correction geometry and unchanged non-target segments
  before committing reversible proposal edits.
- Preserve accepted scientific points, original raster and source hash.
- Preserve 2.0.14 mode refresh, 2.0.13 early guide moves, 2.0.12 Calibration
  scroll and local Workspace provider integration. No CORE changes.

## 2.0.14 — Observable Off/Gentle/Strong proposal selection

- Selecting a different smoothness prior automatically regenerates a
  fully unaccepted candidate, using the existing public Numeric guide transport
  and the current raster/exclusion constraints. Acceptance stays explicit.
- Do not silently reset accepted-segment identities or previously accepted
  scientific points when a user changes the mode after partial acceptance.
- Show the applied Off/Gentle/Strong mode, image sample counts and numerical
  displacement versus the previous preview where point correspondence permits.
  A pre-existing smooth source curve may legitimately yield little or no
  geometric difference; do not fabricate a change in scientific coordinates.
- Preserve original three dynamic-programming objective functions and their
  distinct coefficients. Verified with independent synthetic images and the
  exact deterministic registered calibrated_curve_family raster.
- Preserve all 2.0.13 guide edits, 2.0.12 Calibration scrolling and local
  DEV111-r3 Workspace changes without modifying CORE or installed sources.

## 2.0.13 — Guided-tracing editing and proposal invalidation

- Fix Move/Delete of guide points before a generated proposal exists.
- Preserve reversible guide edits and monotonic coordinate ordering.
- Preserve validated edits on unaccepted proposals without touching saved points.
- Display explicit instructions when exclusion paths invalidate a proposal; prevent
  accepting a stale proposal or an earlier candidate during an asynchronous refresh.
- Preserve all 2.0.12 Calibration scrolling, local DEV111 2.0.11 Workspace bridges,
  and public APIs. No CORE changes.

## 2.0.12 — Scrollable Calibration and version consistency

- Scroll the complete Calibration page when the window is too short; all scientific
  axes, scale bar, verification, calibration measurements and stroke controls remain.
- Maintain independent calibration-measurement-list scrolling and raster canvas zoom;
  show the outer scrollbar only when the page exceeds the available height.
- Synchronize About, module/package descriptors, Tcl API producer versions and
  Python application log to 2.0.12. No scientific calculation or CORE change.
- Preserve the exact installed 2.0.11 Workspace bridge and patch modifications.

## 2.0.11 — Public API manual declarations

- Declare the installed provider-local Image Processing, Quality, Uncertainty and Stroke Width API manuals explicitly so both the API Catalog and normal Documentation Browser resolve the actual files.
- Describe the current Uncertainty API without historical product-version headings; retain its scientific equations, assumptions, limits and public contract identities.
- Update distribution metadata and package checksums. Scientific implementation is unchanged.

## 2.0.2 — zero localization and public Numeric execution

- Allow explicitly declared zero pixel-localization uncertainty, independently of nonnegative declared calibration uncertainty; never replace zero by an artificial epsilon or infer uncertainty from resolution.
- Route uncertainty propagation and covariance to the existing public `NUMERIC_API_v1::callOperation` via typed, in-memory Jacobian transport. Stop launching plugin-owned Python/Octave worker processes and staging temporary scientific files.
- Retain Numeric and point-order identity through public Interactive Document resource writers and managed Dataset covariance publication. Keep original publication contract, Viewer UI, Quality API v2, raster, calibration and assisted tracing unchanged.
- Supply separately staged, **unapplied** Numeric CORE patch for the upstream dev097 zero-input validation and zero-variance correlation corner case; installed-framework/Fitter integration validation is a separate task.

## 2.0.1 — dev097 Numeric/Statistical Semantics owner integration

- Removed implicit uncertainty entry defaults. Pixel, calibration and physical sigma fields are blank until explicitly entered by the user.
- Replaced local-only uncertainty publication with a mandatory public dev097 Numeric computation and independent exact-row verification; fail closed if required CORE services are absent.
- Retained original point identities, saved document, CORE propagated state/values and qualified Statistical Semantics in managed resources with a dev097 Fitter-compatible publication binding.
- Exposed Companion methods for validated uncertainty and managed response-covariance HDF5 publication; Script Bridge gains CORE meaning and managed covariance operations.
- Kept assisted tracing, SEM/image processing, Quality API v2, calibration and viewer interactions unchanged. No changes to the framework worktree.

## 2.0.0 — Reviewed uncertainty integration

- Extended the 1.2.29 Curve Digitalizer without copying the old dev097 1.2.4 GUI.
- Ported the dev097 analytic homography/axis sensitivities and introduced optional reviewed pixel/calibration or physical-override uncertainty declarations, stored per Session Interactive Document.
- Added first-order covariance propagation with local and shared calibration factors and explicit units/physical interpretation, including log and reversed axes.
- Added exact-row and point ID validation to the publication protocol, sigma_x, sigma_y, covariance_xy and retained low-rank factors; separate publications evaluate each calibration independently; combined multiple-realization uncertainty is explicitly rejected.
- Added CURVE_DIGITIZER_UNCERTAINTY_API_v1, Script Bridge readers and a bounded covariance matrix helper, while retaining Quality API v2.
- Preserved all existing tracing, image processing, scrolling, Session and calibration workflows.
- Limitations: not yet the dev097 managed-HDF5/Fitter GLS binding; a distinct SEM scale-bar error model is not yet implemented. Both are documented explicitly.

# Changelog

## 1.2.29

- Fix nested scrolling on the Curves tab: keep the independent curve-list scrollbar, reserve it before the Treeview consumes width, and prevent top-level mouse-wheel handling from also moving the enclosing page while the pointer is on the list.
- Limit wheel routing to the viewer toplevel (not every Tk window) and maintain independent mouse-wheel zoom on the image canvas.
- Show the outer page scrollbar only when the entire controls page is taller than its viewport, resetting any stale page offset after the content fits.
- Add focused Tk/Xvfb regression for normal list scrolling, Windows-style top-level wheel dispatch, short-page scrollbar suppression, and outer controls scrolling.
- No changes to tracing, calibration, publication, Dataset schemas or Quality API v2.

## 1.2.28 — Quality Schema v2 and Dataset Preview diagnostics

- Replaced v1 Quality API and report outright by `CURVE_DIGITIZER_QUALITY_API_v2`, with no legacy adapter.
- Embedded detailed published per-curve and per-segment geometric and raster-evidence observations; all identifiable by source raster coordinates.
- Distinguished source click counts, published row counts and number of selected calibration realizations, including combined layouts.
- Added individual calibration geometry and descriptive realization spread without inventing metrological uncertainty.
- Added bounded results with explicit coverage, omitted counts and observational-method limitations.
- Exposed scalar summary and complete JSON report through Tcl and Script Bridge; added tests and updated English documentation.
- Unchanged: all manual/assisted tracing and Tk UI behavior, Dataset schema and other scientific APIs.

# Changelog

## 1.2.27

- Add a dedicated vertical scrollbar to the digitalized-curve list and route mouse-wheel actions to the list instead of also scrolling the enclosing Curves controls page.
- Update Treeview rows in place so refreshing point counts, curve visibility and assistant acceptance does not unexpectedly reset the list scroll position.
- When dragging a provisional generated point into a different guide interval, resolve its insertion from the **final calibrated X/Y coordinate** whenever X/Y monotonicity or explicit X/Y ordering is configured. Maintain correctly ordered guide labels and segment numbers.
- Preserve free-form insertion ordering and reject invalid target intervals rather than assigning a correction to the wrong segment.
- Add focused Tk/Xvfb regression coverage and update the integrated English manual and assistant design documentation.

## 1.2.26

- Add a Curves-canvas right-click menu on guide points, provisional points, and scientific points, with Move/Delete actions while preserving right-button panning on empty image space.
- Allow the regular Move and Delete interaction modes to operate on unaccepted proposal points as well as on scientific points; make provisional edits reversible with an independent temporary history.
- Make deleting the most recently inserted correction point restore the exact previous candidate path, not an approximate refit. Recalculate only the merged local interval for older interior guide removals.
- Fix reopening a GX-TXT Session whose saved Interactive Documents arrive before the Dataset catalog: after a verified catalog/source identity match, restore the source raster to the canvas.
- Fix image canvas item identity invalidation after Session reset / `delete(all)` so that reloaded raster pixels actually render.
- Preserve accepted scientific points, undo history boundaries, and source SHA-256 checks; add real Tk/Xvfb regressions for right-click and Session A->B->A restoration.


## 1.2.25

- Fix Output points N when accepting a single segment: apply N to the selected acceptance rather than dividing N across all guide intervals.
- Preserve exact counts and shared guide identity when accepting another segment next to an already accepted interval; Resample accepted now uses the actually accepted set.
- Add independent read-only CORE Session identity monitoring and automatic rebootstrap on Session change; clear old-Session proposals, undo history, images and stale callbacks without saving old data into the new Session.
- Discard obsolete asynchronous image-processing work when switching Sessions.
- Add automated exact-density and Session-rebinding regression tests; update the English manual.

## 1.2.24

- Fix correction clicks rejected when Segment # held a stale value larger
  than the real number of proposed guide intervals.
- Bound Segment # to the proposal's actual interval count and synchronize it
  after a proposal is generated or a correction splits an interval.
- For monotonic X/Y, identify the correction interval from the clicked
  scientific coordinate, independent of the inaccurate proposed trace.
- Preserve explicit segment choice for non-monotonic traces and recover
  invalid legacy values using the operator's guide geometry.
- Permit corrections even on short two-vertex proposal segments, keeping
  accepted scientific points and unrelated proposal segments unchanged.
- Report clear correction outcomes in the always-visible bottom status bar.
- Add GUI regression tests for far on-image clicks, invalid selected segment,
  automatic monotonic interval selection and two-vertex corrections.
- Align the integrated English manual and design note with actual behavior.

## 1.2.23

- Make the viewer settings Apply button persistent and non-closing, with a
  clearly visible status line; keep OK (apply and close) and Cancel.
- Repair repeat-Apply optimistic CORE Session commits by advancing the
  versioned settings baseline after each successful commit.
- Report unsuccessful Session document saves instead of claiming success.
- Persist monotonicity, calibrated point ordering, output-point density and
  per-configuration display options in the selected Interactive Document.
- Introduce assisted output point density: zero preserves native proposal
  samples; explicit N produces exactly N unique points across a fully
  accepted proposal, including all shared guide vertices once.
- Add `Resample accepted` for the live accepted proposal, preserving manual
  and unrelated scientific points and supporting Undo.
- Add deterministic arclength reduction, controlled proportional interval
  allocation and regression tests; no change to the path-finding algorithm.
- Keep the integrated English manual synchronized with behavior.

## 1.2.22

- Restore compact, Curves-only point interaction modes Add, Move, Delete, Add guide, Edit proposal and Add correction point. Delete uses click selection and preserves Undo.
- Remove static tracing instructions; compact snapping and appearance controls into one row each, with background swatch color chooser.
- Add far-distance correction insertion scoped to a selected unaccepted segment, without changing accepted scientific points.
- Add per-configuration monotonic X/Y and insertion/X/Y point ordering through Viewer settings → Digitizing, with stable ordering on add, move, assisted acceptance and per-calibration publication.
- Preserve free-form insertion order in existing configurations, retain per-configuration appearance and all previous scientific APIs; add regression coverage and update the English manual.


## 1.2.21

- Restore the full-width, vertically ordered Curve family, Curves, Image
  interaction, Display and snapping, and Canvas appearance sections. Do not
  split the main Curves page into left/right work columns.
- Keep two internal columns only in Assisted tracing: trace parameters and
  image choice at left; proposal actions and segment acceptance at right.
- Retain scrollable controls on short windows, with assistant-only stacking at
  exceptionally narrow widths. Reduce unused rows in the curve list while
  preserving the complete table and its selection behavior.
- No changes to the tracing algorithm, accepted points, calibration,
  publication, metadata, or any scientific API. Update the English manual and
  the layout regression tests.

## 1.2.20

- Reorganize Curves into two work columns with a compact assistant, including
  a two-column setup/actions section and a short, always-visible status area.
- Add a dedicated vertical scrollbar and panel-only wheel scrolling so
  display, snapping, appearance, segment selection and proposal actions remain
  reachable at reduced window heights.
- Stack the work columns when the divider is dragged especially narrow; keep
  image zoom bindings, curve-state ownership, acceptance, publication and
  calibration behavior unchanged.
- Add a GUI layout regression covering normal, short and narrow windows;
  update the English integrated manual.

## 1.2.19

- Replaced the grayscale-only proposal cost with source-colour similarity,
  transverse ridge evidence, conservative image-grid suppression and bounded
  whole-interval dynamic programming.
- Added editable proposals: move a guide, insert locked corrections, recalculate
  only affected intervals, highlight ambiguous candidates and accept one
  segment independently of remaining suggestions.
- Added explicit `auto`/`original`/`processed` image-source selection for
  tracing, with source/pipeline fingerprint validation and no dependence on
  display opacity.
- Added `Try automatic enhancement` and restoration of the previous filter
  pipeline, using safe photometric ImageMagick operations with a clear
  advisory-only classification.
- Made background color and opacity persist per digitizer Interactive Document;
  CORE Configuration values now define defaults, not cross-configuration
  mutable display state. Added settings in Viewer settings -> Display.
- Preserved the Quality API and all publication contracts, added GUI/algorithm
  regressions, and documented the public NUMERIC_API_v1 boundary.


## 1.2.18

- Introduced Curves-only multi-guide assisted path proposals using a bounded
  image-cost corridor with explicit acceptance/rejection; original points
  remain untouched until acceptance and Undo/Redo applies.
- Added documented optional `NUMERIC_API_v1/interpolate` adapter, using PCHIP
  for the guide reference and an explicit local fallback on API unavailability.
- Added module-configurable source opacity and background canvas color.
- Integrated structural and geometrical digitization diagnostics into each
  newly published curve Dataset without inventing accuracy or uncertainty.
- Added `CURVE_DIGITIZER_QUALITY_API_v1` with Dataset-centric Tcl and Python/
  Octave Script Bridge calls for the future GX-TXT Dataset Preview.
- Kept separate CORE plugins unchanged; no native C/X11 GUI is required.

## 1.2.17

- Write nonempty Curve Digitalizer configuration notes into the corresponding published Dataset Notes Markdown using the public GX-TXT Dataset Notes API v1.
- Preserve pre-existing Markdown exactly, avoid duplicating identical exported sections, and retain previous note snapshots when the configuration note changes.
- Apply the same Notes behavior to published curve tables and processed raster images.
- Report post-publication Markdown failures as explicit warnings rather than incorrectly claiming the scientific Dataset publication failed.
- Keep existing public publication request/response compatibility for callers not supplying configuration notes; document the current behavior in MANUAL.md without release history.

## 1.2.16

- Correct split-view first-fit initialization for Image Processing. Defer fitting
  to usable Tk pane geometry instead of calculating scale against provisional
  1x1 sizes, which could clamp both canvases to 0.01 and offset the images.
- Fit each viewport once on its first valid layout; preserve independently
  selected zoom/pan on subsequent pane resizes and tab toggles.
- Reset both comparison viewport fits when the source raster changes, including
  a different source with the same dimensions; retain view when filters update.
- Preserve explicit saved single-view geometry on Session restore.
- Add GUI regression coverage for first open, toggling comparison, resize,
  independent navigation and synchronized raster-center behavior.

## 1.2.15

- Replace manual ImageMagick operation entry with filter checkboxes, sliders,
  numeric/choice controls and validated parameters for all eleven operations.
- Introduce Standard/Advanced filter order, preserving existing ordered
  pipelines and allowing explicit step reordering in Advanced mode.
- Add non-destructive original/processed split comparison with draggable
  divider, independent pan/zoom and optional synchronized raster-centered view.
- Add optional read-only curve overlays and debounced live processing preview.
- Enforce Curves-tab-only point editing, including click, drag and Delete,
  while retaining explicit calibration selection/verification in Calibration.
- Declare the new view/filter preferences through GX-TXT CORE Configuration API
  with User defaults and Session overrides; no standalone settings store.
- Update the functional user manual without release-specific notes; maintain
  existing processed-image publication and Script Bridge API contracts.

## 1.2.14

- Added geometry-preserving ImageMagick processing with an ordered, allowlisted filter pipeline and original/processed preview.
- Added optional canonical `image.raster` publication using host-owned staging and `DATASET_FILE_PUBLICATION_API_v1`, including original Dataset identity, SHA-256, ordered operations and runtime version.
- Registered read-only `CURVE_DIGITIZER_IMAGE_PROCESSING_API_v1` with source/operation/lineage operations.
- Exposed the processed-image API through provider-owned Python/Octave Script Bridge binding with formal operation descriptors.
- Expanded the integrated user manual with a dedicated public API developer reference and Image Processing instructions.
- Preserved non-geometric scope and existing curve/calibration/publication functionality.

## 1.2.13

- Reorganized Calibration: corner controls with verification on the same row,
  scrollable measurement manager below, new Rename and Cancel draft actions.
- Publish-tab multi-selection of accepted calibration measurements and live
  Dataset-ID preview; no need to activate a calibration to publish its X/Y.
- Added separate Dataset per calibration (default), and opt-in combined Dataset
  with calibration identity/label columns and explicit semantic roles.
- Added configurable naming template using documented `[name]`, `[calibration]`,
  `[calibration_id]`, `[configuration]`, `[index]` and `[mode]` tokens.
- Wired output layout and naming template through GX-TXT Configuration API v1,
  including central User defaults and Session overrides.
- Preserve all measurement provenance in each published Dataset; reject name
  collisions, invalid calibration mappings and incompatible combined units.
- Updated the rendered user guide and the published calibration/schema API
  documentation, without inserting historical release notes in the manual.

## 1.2.12

- Reorganized Calibration with side-by-side full-image and scale-bar controls.
- Added a persistent Calibration Measurement Manager: new/activate/accept/reject/delete;
  each measurement retains corners, axes, scale-bar reference and scientific mapping.
- Published all measurement realizations as structured Dataset metadata, with
  stable IDs, group identity, mapping SHA-256 and explicit accepted/draft/rejected state.
- Extended the existing public calibration API to enumerate realizations and
  transform points using an explicitly selected realization.
- Added a temporary verification X, with dynamic expected-coordinate residuals,
  Esc/clear action and GX-TXT central settings for color, size and line width.
- Moved namespace selection from Configuration into its own Namespace menu.
- Clear scale selection hides overlay without changing the applied calibration;
  resetting physical scale requires an explicit action.
- Updated the guide to reflect current behavior, removing release-history prose.

## 1.2.11 — CORE module configuration integration

- Declare ten typed module configuration fields discoverable by GX-TXT Configuration → Modules.
- Support User defaults, inherited/explicit Session overrides, native CORE module editor.
- Route local Viewer settings through CORE `configurationCommit` with optimistic conflict detection.
- Reflect central configuration changes in open Python viewer within five seconds.
- Preserve scientific Interactive Document state and previous preferences for compatibility.
- No modifications to CORE, datasets or scientific calibration.

## 1.2.10 — Compact toolbar and calibrated, data-centric raster access

- Compress the top controls to one prominent row with the active configuration
  and source Image Dataset. Move catalog status, namespace selection and manual
  refresh out of the toolbar while retaining bottom status warnings.
- Add **Configuration → Select Dataset namespace...**, a scrollable Canvas
  picker with namespace hierarchy, per-namespace image counts, and no Dataset
  move/rename side effects. Automatic revision checks remain available.
- Add `transformPoints`, `identity`, `jacobian`, and `pointUncertainty` as
  additive operations to `CURVE_DIGITIZER_CALIBRATION_API_v1`.
- Persist stable source-raster calibration fingerprints, calibration method and
  explicit crop/rotate/resize relationship (identity relative to imported image;
  unknown upstream processing is never inferred).
- Publish two additional first-class `pixel_x`, `pixel_y` variables through
  CORE Publication API v2, with stable `raster_x`, `raster_y` semantic mappings
  in the existing `CURVE_DIGITIZER_DATASET_SCHEMA_API_v1`.
- Add a bounded `rasterPoints` reader using CORE Canonical Dataset API v2.
- Preserve readable historical outputs and never report missing uncertainty
  as zero. No CORE changes; full UI and technical documentation remain English.

## 1.2.9 — Dataset workspace browser and automatic Catalog revision checks

- Use public GX-TXT Dataset Catalog v1 and Dataset Namespace v1 APIs from dev096; never inspect or mutate the CORE registry directly.
- Add "Dataset workspace" selector for all, exact and hierarchical Dataset namespaces; preserve already-linked source Dataset identity when switching filters.
- Add a nonblocking five-second revision monitor (default on), manual Refresh command/button, and a settings control. Only fetch complete catalog inventories after revisions change.
- Handle added, deleted, renamed, relocated and modified image Datasets. On source modification verify the actual SHA-256; report stale/missing source without rebinding, erasing digitized points or reusing calibration.
- Persist the browser namespace/automatic-monitor preference in each existing Interactive Document; maintain Session token checks, publication ownership and existing API contracts.
- No CORE or dev096 source modifications.

## 1.2.8 — Versioned published curve semantics

- Add public `CURVE_DIGITIZER_DATASET_SCHEMA_API_v1` to resolve role → Variable ID,
  variable descriptors, curve grouping and publication mode using the output
  Dataset ID alone. This removes the requirement to know internal column names.
- Publish `curve_digitizer.curve_schema_version=1`, explicit independent/family
  mode and five/six versioned role mappings atomically with every Dataset.
- Register explicit per-variable Semantic Registry roles for the curve key,
  editable label and within-curve point order; keep user-configured X/Y roles.
- Validate dtype, row dimension, contract, uniqueness and completeness on reads;
  support pre-1.2.8 outputs through a strictly verified legacy mapping.
- Preserve the separate calibration manifest/public API, the long-table
  publication format, Session/curve identity, full UI and existing features.
- CORE and dev096 reference source remain unchanged.

## 1.2.7 — GX-TXT native rendered Help

- Fixed: the Python Help pane displayed `MANUAL.md` as mostly raw Markdown text.
- Replaced it with a host-owned Help window that uses `documentationBrowserRead` for the registered plugin manual and GX-TXT `markupRenderStringToWidget` for native GX-Markup formatting.
- Preserved F1 and the Help menu, table-of-contents navigation, case-insensitive Find next, and a Close action.
- The viewer requests `HELP_OPEN` asynchronously via its existing host IPC (without blocking Tk or duplicating CORE logic); host rejects unexpected arguments and reports missing services/documents explicitly.
- Normalizes optional language labels on fenced code blocks only for the displayed copy because GX-Markup v1 expects unlabeled backtick fences; the packaged Markdown source is unchanged.
- No changes to scientific data, calibration manifests, publication, Session ownership or CORE.

# Changelog

## 1.2.25

- Fix Output points N when accepting a single segment: apply N to the selected acceptance rather than dividing N across all guide intervals.
- Preserve exact counts and shared guide identity when accepting another segment next to an already accepted interval; Resample accepted now uses the actually accepted set.
- Add independent read-only CORE Session identity monitoring and automatic rebootstrap on Session change; clear old-Session proposals, undo history, images and stale callbacks without saving old data into the new Session.
- Discard obsolete asynchronous image-processing work when switching Sessions.
- Add automated exact-density and Session-rebinding regression tests; update the English manual.

## 1.2.22

- Restore compact, Curves-only point interaction modes Add, Move, Delete, Add guide, Edit proposal and Add correction point. Delete uses click selection and preserves Undo.
- Remove static tracing instructions; compact snapping and appearance controls into one row each, with background swatch color chooser.
- Add far-distance correction insertion scoped to a selected unaccepted segment, without changing accepted scientific points.
- Add per-configuration monotonic X/Y and insertion/X/Y point ordering through Viewer settings → Digitizing, with stable ordering on add, move, assisted acceptance and per-calibration publication.
- Preserve free-form insertion order in existing configurations, retain per-configuration appearance and all previous scientific APIs; add regression coverage and update the English manual.


## 1.2.6

- Replace crowded upper button toolbar with native menu navigation (Edit, View, Calibration, Dataset, Configuration, Help); Configuration sits directly to the left of Help.
- Add a central Configuration → Viewer settings... window with Display, Digitizing, Calibration, Axes & output and Configurations pages, validation, safe Apply/Cancel, undo and existing GX-TXT Session persistence.
- Add integrated searchable, scrollable English MANUAL.md viewer with contents navigation, F1 binding and Help menu; no browser or network dependency.
- Default the SEM terminal tick reference to center-to-center; expose inner-to-inner and outer-to-outer alternatives. Detect terminal ticks conservatively and require manual two-endpoint selection when they cannot be resolved.
- Persist selected scale-bar edge convention in the existing configuration and published Dataset Metadata; expose it via CURVE_DIGITIZER_CALIBRATION_API_v1, marking historical unspecified measurements honestly.
- Preserve source SHA verification, existing manual/automatic calibration, publication API and scientific Dataset contracts. No CORE changes.

## 1.2.5

- Keep the status bar visible by reserving it at the bottom before layout of the expanding image and controls; adapt initial window height to desktop bounds.
- Attach complete calibration provenance to every published scientific Dataset with source Dataset ID/SHA-256, stable configuration ID, raster dimensions, coordinate origin, Y direction, physical unit and transform; include scale bar and uncertainty only when available.
- Classify published calibration as `pixel`, `scale_bar`, `affine` or `projective`, and publish mathematical normalized/scientific homographies with non-linear axes represented explicitly.
- Use Dataset Publication API v2 `structured_metadata` for in-transaction persistence instead of a post-publication metadata write; retain unrelated metadata and discard stale former calibration fields on republish.
- Register `CURVE_DIGITIZER_CALIBRATION_API_v1` as a separate public plugin API resolving by output Dataset ID and returning a typed Tcl dictionary independent of private viewer state.
- All new UI and documentation text is English; no CORE source changes.

## 1.2.4

- Add image scale-bar calibration after full-image autocalibration. One click conservatively detects high-contrast light/dark horizontal bars; ambiguous images can be measured using two manually selected endpoints.
- Show an outlined magenta preview of the candidate endpoints and measured source pixels, requiring explicit entry of physical length and unit plus Apply before changing scientific data.
- Apply isotropic scaling to both axes, preserving selected Y orientation and pixel-coordinate provenance; preserve image-space reference endpoints and physical length in the existing Interactive Document and show the confirmed measurement as a persistent green overlay.
- Keep previously digitized points, undo/redo, source SHA checks and publication; identify scale-bar calibrated output as `full_image_scale_bar` in publication metadata.
- Make GUI numeric bound round-trips use full float precision; retain full-image and manual projective calibration choices.
- No CORE changes; all new user interface controls and messages are in English.

## 1.2.3

- Add one-click full-image pixel calibration from the canonical source image dimensions, with selectable Cartesian or image-pixel Y direction.
- Reuse the existing four-corner homography, Session persistence, undo/redo, source SHA checks, and Dataset publication; preserve manual calibration unchanged.
- Add confirmation before replacing existing axis/calibration state and recalculate already digitized points.
- Document the new calibration workflow without changing CORE.

## 1.2.20

- Resolve Session context and source image through public Session Inspection; preserve measured-versus-registered SHA diagnostics for stale-source reporting.

## 1.2.1

- Normalize LF and CRLF protocol requests at the Tcl pipe, including Windows BOOTSTRAP.
- Read host control messages while the Python/Tk viewer is idle and acknowledge GUI readiness separately from child process creation.
- Show a responsive startup window with a bounded bootstrap wait, and retain host/Python diagnostics in the current Session logs.
- Use the configured Python runtime and preserve command-list executable paths. No calibration, persistence or Dataset publication format changed.

## 1.2.0

- Added `CURVE_DIGITIZER_COMPANION_API_v1` for tightly coupled assistant modules without a second authoritative state model.
- Added stable configuration/curve context discovery and source Image Dataset integrity resolution through public GX-TXT APIs.
- Added guarded pixel-point commit that reuses the Curve Digitalizer calibration model and writes accepted points into the existing Interactive Document.
- Added document SHA-256 optimistic concurrency so an open Curve Digitalizer window cannot silently overwrite newer companion-module changes.

## 1.0.1

- Added a source-image preview confirmation dialog when selecting a new Image Dataset for a configuration.
- Prevented accidental binding to the wrong image by requiring explicit confirmation before the source association is persisted.
- Kept packaged GUI validation deterministic by auto-accepting the preview step only in the non-interactive regression scenario.

All notable changes to `viewer.curve_digitizer` are documented here.

## 1.0.0

- Initial GX-TXT-native release for GX-TXT 0.9.7.78.
- Reused the original Curve Digitizer homography/calibration model and interactive image canvas behavior where scientifically appropriate.
- Replaced standalone image-open, project-file, and CSV-export workflows with current GX-TXT Image Dataset selection, Session-persistent Interactive Documents, Dataset Metadata, and Dataset Publication API v2.
- Added named configurations with stable IDs, rename/duplicate/delete management, and support for multiple independent configurations per source Image Dataset.
- Added source byte integrity verification with SHA-256 and explicit missing/stale-source diagnostics.
- Added linear/log X/Y calibration, labels, units, semantic roles, calibration verification, curves, numerical curve families, point editing, undo/redo, zoom/pan, overlays, and darkest-pixel snapping.
- Added publication of independent curves as `table.generic` and numerical curve families as `curve_family.table` with stable variable IDs and preserved point order.
- Added same-owner deterministic republishing, output Dataset Metadata, Variable Schema enrichment, source Dataset lineage, and CSV artifact creation in the publication transaction.
- Added lazy Viewer Provider backend activation and interactive dependency preflight for Python/Tk/NumPy/Pillow.
- Added deterministic scientific, static host-independence, and real Xvfb/Tk integration tests.

## 2.0.3 — full-factor consistency and physical product-unit schema
- Uncertainty-enabled publication checks both complete local (2N x 2) and shared (2N x 12) factor matrices against authoritative CORE Numeric state, before retaining numerical resources.
- Changed cross-point factor loadings are rejected even if all marginal sigma and within-point covariance fields still agree.
- `covariance_xy` now declares an X-times-Y physical product unit in Dataset Variable Schema v3 and its matching metadata. Companion API readback validates both.
- No changes to calibration, SEM, manual editing, tracing, Quality API v2, Session workflows or ordinary no-uncertainty publication.
- No dev097 source change. Numeric zero-localization CORE patch and end-to-end GLS/ODR acceptance remain separate.

## 2.0.5 — Guided smoothness, red-X exclusion splines and calibration identities
- Add explicit Assisted tracing "Smooth curve prior": Off (unchanged legacy first-order path), Gentle, Strong. Guided second-order dynamic programming penalizes oscillating deviations from a continuous reference. The user must explicitly select the prior; no interpolation is inferred from the image's subject.
- Add curve-scoped, editable "Exclusion paths" drawn by red X control nodes with a shape-preserving 2D spline. Width is measured in original image pixels. Soft image penalties discourage tracing competing curves and grids without an opaque image mutation or forbidden crossings.
- Exclusion edit supports new path, drag control X nodes, delete last X, remove path, undo/redo geometry; Session configuration holds the original raster coordinates and image SHA. Propose, repair, insertion and removal paths use the same priors. A proposed trace always requires explicit Accept.
- Mark active calibration identity beside TL/TR/BL/BR and state which active measurement the verifier uses. Selected-but-inactive rows are not silently used for verification.
- Existing point acquisition, raster processing, calibrations, Curve/Quality/Uncertainty APIs, Dataset publication, Numeric/Fitter semantics and default Off behavior are unchanged. No framework CORE files modified.

The exclusion editor includes a deliberate Clear all paths control for re-binding a configuration to another Image Dataset without accidentally reusing old raster-space exclusions.

## 2.0.6 — Two-row assisted tracing layout and chronological Undo/Redo
- Place Trace settings and Proposal in the first row; place full-width Exclusion paths beneath them with controls on the left and a scrollable per-path table on the right.
- Each exclusion path has a stable ID, exact red-X nodes and its own enabled flag. Checking the table's On column enables/disables a single path without changing the selection, and disabled paths remain visible as subdued overlays.
- Remove the separate Undo X and Redo X buttons and the Path # spinner. Edit → Undo/Redo and Ctrl+Z/Ctrl+Y are now the chronological history for accepted scientific edits, red-X path edits, and transient proposal corrections.
- An exclusion-node drag is recorded once on release. Opening a different Session/configuration drops the previous history. Undo followed by a new edit invalidates Redo.
- 2.0.5 list-only path records are normalized into stable path IDs on load, and per-path enabled states persist in the current Session configuration.
- No changes to CORE, scientific Dataset APIs, Numeric uncertainty, raster data, or calibration transformations.

## 2.0.7 â€” Restore original Curve Digitalizer icon
- Restored original upstream icons/curve_digitizer.png and icons/curve_digitizer.svg from the official GX-TXT GitHub repository, with byte-for-byte Git blob SHA-1 verification.
- Registered icon=icons/curve_digitizer.png in [viewer.curve_digitizer] to avoid the host generic placeholder icon.
- Kept semantic_group=images and group_title=Imaging & Documents.
- No changes to assisted tracing, exclusion path workflows, undo/redo, calibration logic or public scientific APIs.
## 2.0.8 — Per-curve raster stroke width and public API
- Optional, collapsed-by-default Stroke width panel for the selected curve (left of Show/Hide), with per-curve activation and automatic cross-sectional raster width estimation or two manual editable boundary splines.
- Raster boundaries are edited by click and drag, with Edit menu Undo/Redo, separately from orange guides and red exclusion X markers.
- Calibration shows the active curve diagnostic and offers a link to its editor; the Uncertainty dialog lists per-curve active/inactive/stale states and explicitly disclaims automatic uncertainty propagation.
- Source and, for automatic measurements, accepted trace SHA identity guard against stale results. State is persisted within the Session Interactive Document. Published Dataset metadata includes a versioned per-curve diagnostic report.
- New public module API CURVE_DIGITIZER_STROKE_WIDTH_API_v1 reads configuration and published results through public GX-TXT CORE services.
- No implicit sigma, CORE Numeric/covariance or Fitter weighting. All previous UI, preview, imaging category and restored original icons retained.

## 2.0.9 — Per-curve UI selection synchronization and API validation
- Preserve all 2.0.8 stroke-width acquisition controls, Tcl public API v1, scientific limitations, Curve family metadata, and restored original icon.
- Fix the Curves selection handler: selecting another curve immediately updates the optional stroke-width panel checkbox, detection method, radius, diagnostic status, and matching Calibration summary. A previous curve's controls are never left on the new selection.
- Add two headless regression tests for switching/reselecting curve and a numerical synthetic-raster fixture for automatic and manual stroke-width measurements.
- Confirm the public API Tcl facade can return per-curve and published reports using public CORE boundaries in an isolated Tcl 8.6 stub test; this does not replace GX-TXT host acceptance.
