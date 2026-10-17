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
