# DEV111-P031 presentation correction0.1.5

P0310.1.5 is a separately versioned presentation correction of the retained
owner0.1.4 input: two control-character caption separators become em dashes,
and the readonly Dataset identity wraps without taking half the curve-list
width. The runtime api/preview.tcl and all scientific/schema/Plot operations
remain byte-identical to0.1.4. Original ZIP SHA256 c07ae52b27dd81737eb2f95acaf842eb56e6c48f6eccdc6722b41d854335cfac.
Independent final P031 acceptance is required; the original historical
validation below is not claimed as acceptance of this corrective package.

# Validation — Curve Digitalizer Dataset Preview 0.1.4

Source baseline: installed GX-TXT dev111-r3 documentation and public Tcl
contracts, read-only, 2026-10-29. No CORE, installed modules, Session,
Dataset or Workspace data were changed by preparing this package.

Verified in an independent tclsh/wish test:
- Official Viewer Interface Builder CORE design validator accepts
  gui/design.tcldict as a Preview-target GUI.
- Three Preview descriptors returned (Curves GUI, Calibration & Quality
  metadata, Canonical Data table), with source-bound Dataset ID and roles.
- A synthetic 3-curve x 3-calibration x 100-point Combined example yields
  nine stable distinct (curve_key,calibration_key) Plot v4 series.
- Each series uses exact schema Variable IDs, two ANDed public source
  predicates and point_order ordering for that group.
- Plot v4 native rendering/visibility/cursor operations are used exclusively.
  Unit tests mock the Plot v4 native C++ runtime; they do not establish that
  all underlying graph resources admitted at runtime.
- Show/hide/show all and module-owned Plot cleanup after host invalidation.
- No invented uncertainty/accuracy data in published Quality metadata.
- ZIP archive path safety, SHA manifest integrity and clean extraction.

Not yet completed: real installed Dataset Preview host acceptance on a live
canonical published Dataset; native Plot v4 actual rendering/zoom; GTK/ttk
responsive resize; Module Manager enable/disable during active Preview;
table-page filtering by chosen curve/calibration pair (not exposed by
public datasetPreviewPage range/projection contract). The user must
operator-test this independent module before any CORE removal is considered.

## 0.1.4 — Verified on running pc-giux, 2026-10-29

Observed GX-TXT GUI Session in normal wish process:
- Installed 0.1.0 package: module catalog recognized it and Module enable=1;
  default Preview selection was calibrated.family.source, which correctly does
  not match the module's curve_digitizer.plugin_id metadata requirement.
- Correct published Dataset digitized.tutorial02.family.combined.curves was
  registered with curve_family.table, recognized as Curve Digitizer schema v1,
  and matched the presentation module. datasetPreviewProviderTabs returned
  Curves (gui), Calibration & Quality (metadata), Canonical Data (table).
- The actual GUI mount of 0.1.0 refused:
  Invalid canonical Dataset contract ID. Its GUI Builder source declaration
  used a Tcl space-separated list, not semicolon-delimited dataset contracts.
- Staged 0.1.4 design passed the actual running DEV111-r3
  viewerGuiDesignRead/Validate path, not only a mock validator.
- With the corrected design, normal PlotSpec row_filters created a public
  Dataset Transform request, which failed with:
  Dataset Transform: binding ownership mismatch for
  CURVE_DIGITIZER_IMAGE_PROCESSING_API_v1.
- Staged 0.1.4 replaced this path with bounded canonical Dataset Preview
  page reads and a disposable model handed to Plot Dataset API v4.
- With temporary, finally-restored module procedures, the actual running
  GUI mounted the corrected Builder controls and returned native Plot v4
  status ready, 9 groups from the registered 900-row Dataset.
- The REAL Plot v4 native engine subsequently accepted widgetVisibility
  hide(trace1)=0 and show(trace1)=1 and returned native-plot-v4#2 receipts.
- Diagnostic windows were hidden, destroyed; original live module procedures
  and in-memory state were restored. No installed CORE/module file, scientific
  Dataset or Session was changed for these tests.

Remaining: End-to-end user-facing GUI preview tab activation and selection,
quality/table layout, visible Plot rendering and restart/Module Manager
lifecycle acceptance after user installation of the 0.1.4 package.

## 0.1.4 — Preview responsive loader

- Official Builder design validator: PASS on the existing work-copy CORE.
- Synthetic Combined family (3 curves x 3 calibration IDs x 100 points):
  asynchronous one-page load, 9 distinct Plot v4 groups, source-row
  identities, show/hide, cleanup: PASS.
- Synthetic 3000-point family: actual 3 distinct asynchronous Tk event
  turns with each canonical page limited to 1000 rows, exact ordering,
  source IDs, cancel-and-dispose with zero surviving coroutine: PASS.
- Running host's old datasetPreviewProvider identity observation before
  CORE optimization: 654–946 ms, call of
  datasetMetadataContributors() all fields: 441 ms, targeted provenance
  check for just curve_digitizer.plugin_id: 27 ms.
- Production GUI's old match vs dynamically extracted optimized match
  compiled from the work-copy source: identical scientific match result,
  471.2 ms vs 59.4 ms first, 36.5 ms repeated. No application process
  code was permanently altered by this benchmark.
- Builtin GUI buttons and filter selectors belong to CORE; the module's
  own Curves list is reduced from 9 to 5 visible rows and shares an
  inspector row with Dataset identity.

Real user-visible Preview acceptance is required after installing 0.1.4
and restarting the GX-TXT work copy to apply its changed CORE Tcl code.

## 0.1.4 — GUI controls Tcl pattern regression

Root cause reproduced with the installed 0.1.2:
`::GX::DigitizerFamilyPreview::dispatch` contained an inline Tcl
` ;#` comment inside the braced `switch` pattern/body list. Tcl does not
parse comments inside that braced list; the extra literal elements violate
the pattern/body pair contract, resulting in
`extra switch pattern with no body` on any control callback.

Correction moves the explanatory comment outside the braced `switch`
list and leaves only valid pairs inside. The new
`tests/test_preview_dispatch_013.tcl` invokes the actual callback
with passive controls and Load/Hide/Show all/Fit/Zoom; PASS with the
Tcl/Tk UI mock and the nine-group dataset fixture.
`tests/test_preview_async_012.tcl` still passes for 3000 data rows
and cancellation. `tests/test_builder_design_012.tcl` passes using
the actual work-copy Builder validator.

No CORE changes, no scientific data mutations.
Normal GUI acceptance remains the operator's final check.

## 0.1.4 — GUI blank-list and retained Preview performance audit

- Observed the real GX-TXT 0.1.3 GUI host with a blank Curves Listbox:
  nine groups had **not been loaded**, the data model and pending
  coroutine were both empty. A click on the empty Listbox produced
  "control groups accepted"; this is not a successful Load receipt.
- Called the real module Load callback in the active user Session:
  preparing receipt in 257 ms followed by a populated list with nine
  exact curve/calibration groups (900 accepted rows); Plot v4 model ready.
  No canonical Dataset modification occurred.
- Confirmed real published standard Preview Session cache hit with
  300 rows / 3 series and one selected calibration; it cannot be used
  as a complete nine-group cached source.
- Timed real CORE Preview extension-tab recomposition at 3962.9 ms.
  The operation destroys the already loaded Curves pane and rebuilds it
  empty. The work-copy CORE Live observer has therefore been corrected
  independently: when source and exact cache key are current, retain
  extension panes instead of rebuilding them on preference-only stamps.
- Live in-process probe with temporary corrected Tcl procedure,
  finally restored: 415.6 ms forced watch and **zero remounts**
  with unchanged source/key. No CORE working file was patched by this
  in-memory test; the work-copy file has its separate patch.
- New module regression: Mount creates only a metadata instruction
  (zero scientific reads), selecting that row triggers cooperative Load
  and nine groups; Plot v4 Show/Hide/Fit and Zoom tests still pass.
- CORE regression on the actual edited work-copy Live observer:
  preference-only watch retains panes; changed scientific cache key
  performs the normal remount and invalidation, PASS.
- Persistent cache integration remains **design only**. No cache
  extension CORE patch has been written or installed.
