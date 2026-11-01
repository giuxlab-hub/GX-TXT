# Dev-057 corrective interaction acceptance

The sole candidate starts from canonical published GX-TXT 0.9.8.10-dev-056,
archive SHA-256 `147b52051682f030626d446450b424e2c2e8a8ccb6813d2920314c9b7d636156`.
Published056 is the technical baseline; its reported UX failures were reproduced,
not treated as manually accepted behavior. Published055/056, old working trees,
prior versioned handoffs and canonical user Sessions were not modified.

## Audit and reused authorities

Audit found per-redraw full viewport layout, per-wheel synchronous Session
Workspace writes, a sibling inspector still intercepting input after palette
collapse, and split sampled/retained selection state. CORE Native2D selection
sets now own semantic references across existing logical curve records. The
former selection-scene names alias the main Native scene; property focus does
not define a separate selection universe. Stable controls/segments are not
sampled points. Existing layers, groups, named sets, constraints, units, direction,
source descriptors, canonical publication and workspace/resource APIs remain
the authorities. Named retained-reference stamps follow mathematical topology,
not display sample density. No parallel persistence or scientific engine exists.

The shared drag restoration now preserves live owned controls, tangents and path
segment buffers. A mixed-scene ASAN fixture reproduced use-after-free before the
fix and passes afterward; an ordinary point drag can no longer corrupt an
unselected retained curve. Residual visibility no longer unmanages/remaps the
scientific canvas; the corresponding Tk remapping crash is corrected structurally.

## Resulting behavior

- Chrome layout is invalidated by actual layout changes. Geometry/view frames
  coalesce at 16 ms; wheel view updates are immediate and checkpoint after a
  350 ms quiet period. Pan checkpoints at release. Recovery remains enabled.
- Managed reference raster rendering uses one asynchronous worker/request and
  one replaceable pending plan. Native owns calibration/transform/clip math;
  Tk/Python host owns pixels and lifetime. Stale plans cannot reappear, and
  cached pan translation preserves the underlay while the final raster completes.
- Click, rectangle and arbitrary polygon selection share one public Native
  semantic set, including replace/add/subtract and exact Escape cancellation.
  Hidden/reference-only objects are excluded from ordinary picks. Visible widgets
  alone intercept input. Fit Selected includes participating logical owners and
  selected real defining controls through the shared bounds API.
- Immutable Dataset points remain point entities. Display points/straight/spline
  changes never change scientific backing or default exports. Untouched save
  stores validated Dataset bindings, not a private geometry copy. Reopen requires
  the original source; a failed restore does not overwrite the saved workspace.
- Reviewed promotion checks exact GX-TXT provenance against every published row,
  units, variables/order and canonical receipt; otherwise it explicitly creates
  a retained interpolating Catmull-Rom spline with source/order/method/quality
  provenance. Original Datasets remain unchanged.
- Line is one retained path with shared vertices once, explicit Enter/Finish,
  stable selectable/dimensionable segments, closed topology, Join/Split and one
  undo transaction. Coincident does not combine unrelated object identities.
- Straight path publication creates one canonical Dataset with exact global
  vertices, optional int64 `index` (rename or omit), deterministic direction and
  explicit closed endpoint repetition. Joined/split source conversion receipts
  survive republication independently of input actor lifetime.
- Residuals require an explicit valid reference/target/method request. Drawing,
  reference choice alone or property-focus changes never activate or retarget
  comparison. Disable stops output; fresh reopen preserves truthful state.

## Actual source-bound evidence

Full acceptance: `/home/giu/electronics-server/work-agent/TK_GIUXLAB/_evidence_dev057_final01/acceptance.json` (PASS).
Evidence SHA-256: `c59a910cd0f4e93a070176c88274734e58f14f366c7ced1053d784d8398f270e`.
Runtime behavior SHA-256: `96c122e0a2b3e76af189986c18b5e6593af16a6241e8f8a31136f516fc9fc107`.

26 actual parent processes, validated nested outcomes, 21 CTest and 21 current-source
ASAN/UBSAN fixtures pass. All18 scientific GUI cases pass, including the million-row
complete-data primary/fresh workflow. The additional16-case preservation suite
passes attachments, units, constraints/dimensions/Fixed, CAD/snap/collections,
selection/point-table drag lifecycle, atomic publication, Curve Fit clipping/fresh,
representations, workspaces and independent preview pixels. Real focused/fresh,
crash-recovery and portable imported workspaces pass. Python and Octave execute
actual Script Workspace services for semantic selection/bounds, paths, publication,
promotion and the preserved tangent/image/symmetry/workspace/note/resource APIs.

Actual X11 input verifies Dataset + editable Native points + Line/path + Arc +
Spline + Bézier; real knots/tangents/vertices/segments, cross-curve rectangle and
trapezoid modifiers/cancel, hidden/excluded geometry, pointer routing at panel
edges, multi-curve point drag/undo and selection after pan/zoom/fresh reopen.
The permanent same-gesture fixture visibly succeeds in published055, reproduces
published056's hidden inspector interception, and succeeds in the candidate.
Visible opaque palette content correctly owns its actual pixels.

## Fluidity measurements

Published056's 40-event wheel burst had 4979 ms post-input backlog, 40 layouts and
40 saves. Source057 primary/fresh tests use twelve retained curves, open/collapsed
utilities and palette, calibrated image, 40 rapid wheel events and 4000 continuous
X11 motion requests per pan burst, without settling between individual inputs.
X11 coalesces motion requests; evidence records both requested input and actual
processed events rather than claiming every request was delivered separately.

Primary wheel backlog:23–36 ms; fresh:33–35 ms. Primary pan backlog:84–106 ms;
fresh:102–109 ms. Maximum measured frame:21.288 ms primary,16.183 ms fresh.
Latest raster completes within175 ms. Every burst has zero full layouts, one
checkpoint, zero empty geometry frames, and pointer-follow error below
`2.4e-13` pixels. Post-burst controls respond. Debounced checkpoints take65–81 ms.
Burst tests run alone after the other acceptance children have completed.

## Preserved work and explicit limits

Spline tangents, image calibration, symmetry-first construction, named workspaces,
notes, current/fit previews, Settings, collapsible shared panels, existing context
menus, Script Bridge and Curve Fit clipping/adapter parity remain validated.

This release implements all-straight paths, as permitted by the frozen corrective
scope. Heterogeneous Line/Arc/Spline/Bézier composite Join/Split/sampling remains
unfinished in the TODO. Curved joins are rejected explicitly. Polygon regions
support3–4096 vertices; individual semantic membership is bounded at65536 and
oversized requests reject atomically. Dataset spline presentation supports4096
continuous points; reviewed spline promotion supports at most65536 authoritative
knots and refuses implicit gap bridging. Path publication supports65536 output
vertices including any explicitly repeated closure. Existing bounded local solver
limits remain; no global solver/uniqueness claim is added.

No TASK-10, Native3D, Scientific Libraries, named-parameter expressions, final HTML
guide or further development cycle was started. Publication and authoritative
handoff hash gates follow this actual source acceptance. Stop for manual user review.
