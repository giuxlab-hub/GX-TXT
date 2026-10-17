## 0.9.8.10-dev-097

Reuse the existing family grouping renderer in stacked panels, including right Y
axes and explicit styles. Preserve exact source rows and prevent cross-family
line segments. Single-panel grouping and ordinary traces retain their contracts.

# plot.dataset 3.18.0 / dev097

Integrate persistent Dataset coordinate presentation through public CORE snapshots.
Canonical preparation and detached source identity remain retained.
For narrow log X ranges, label visible frequency subdivisions when automatic
decade ticks provide fewer than three labels. Reapply the presentation policy after
coordinate view limits; saved custom ticks and explicit major steps take priority.
Repeated grid application keeps one set of minor lines.
Share explicit unit-suffix conversion between 2D, 3D and colorbar labels. The
3D Native preview export receives the same corrected visible axis labels.

# plot.dataset 3.17.0 / dev097

Consume canonical rank-two Y-by-X grids through public managed hyperslabs, with
strict dimension/unit/axis checks and bounded reads. Validate every source cell;
refuse holes and unsafe integer narrowing. Display stride retains exact physical
coordinates and original indices. Preserve the existing XYZ table reader.
Align module/package and cache producer/consumer versions; APIv1 is unchanged.

# plot.dataset 3.16.0 / dev097

Preserve exact typed integer members in both ordinary filtered and two-pass grouped
preparation. Share CORE's exact integer conversion, and invalidate prior render
and preparation caches through matching producer/consumer versions. Scientific
Dataset, Series, graph and Workspace identities remain unchanged.

# plot.dataset 3.15.0 / dev097

Optional uncertainty no longer removes finite central observations. Finite-run
identities prevent reduced bands from bridging unavailable bounds in single and
multiple panels. Streaming, filtered batches, CSV compatibility, source-row
selection, ordering and cache fingerprints share this behavior. Align module,
package and render-cache producer/consumer versions; preserve scientific IDs.

Scalar-width and interval bars honor source-unit baselines after display/level
conversion. Final axis scales determine the positive log-Y fallback; independent
series baselines remain independent across panels. Auto uses display zero.

## 3.14.0

Exact selected source rows and continuity through PlotSpec/Variant rendering; backend-neutral Table Stream v3 for HDF5 3D.

## 3.13.1 / dev087

Read-only prepared graph preview export via public 3D/v3 APIs, preserving scientific
rendering/presentation and delegating lifecycle/navigation to the shared CORE host.

# Changelog

## 3.13.0 / GX-TXT dev-051

- Batch Graph Series row presentation, lazy bounded cached distinct values, wide Session Dataset choices, incremental PlotSpec mutations and per-series preparation cache; compatible filtered series share one Dataset stream. Presentation/Graph resources and safe portable scientific snapshots use CORE APIs.

## 3.12.9

- Preserve point-order bindings through the v1 Series API and expose explicit
  As stored, By X and By variable modes in the Graph Series editor.
- Honor explicit per-panel Y labels and improve automatic Y-label spacing
  after aspect and external legend layout.

# 3.12.8

Shared X scale, major step, and minor grid now use the common Axes dialog and
one PlotSpec authority for base graphs and Variants. Linear major steps are
applied during rendering. Signed Y-label offsets are honored when the graph
opts in through Plot layout. A 3D colorbar whose visibility is inherited
remains visible after an Axes override is enabled.

# 3.12.7

Single-panel Graph configuration now exposes Y Left and Y Right
Auto/Linear/Log scale using the existing first-panel PlotSpec axis state. The
right selector is available when a right-axis series is present. Multi-panel
graphs continue to use their per-panel Y controls; shared X remains unchanged.

# 3.12.6

`validateSpec` returns logical true for valid 3D PlotSpecs, matching its 2D
contract and allowing Script Bridge v2/v3 `validate_spec` to decode success.
3D PlotSpec validation errors and render behavior are unchanged.

# 3.12.5

Shared-X 2D PlotSpec accepts `axis.x.major_step` and `axis.x.minor_grid`.
Plot Dataset graph settings and the framework Plots tab edit the same saved
X scale, decade step and automatic logarithmic subdivisions across panels.
Script Bridge result descriptors now match the shipped v2/v3 values.

# 3.12.4

Completed the Script Bridge v3 lifecycle, panel/Series presentation and read-only interactive discovery operations. Nested render/rerender/artifact results now use recursive Tcl value normalization in CORE.

# 3.12.3

Graph and Axes controls now persist Linear/Log X scale on the shared PlotSpec
X domain. Deleting a Variant removes its persisted PlotSpec and owned artifacts.
Script Bridge v3 exposes normal `create_plot` without producer identity.

## 3.12.2

- Added visible Graph Series selectors for Dataset values, categorical row
  filters, primary family, secondary parameter and numeric point ordering.
  The corrected_contour owner Dataset produces eight independent ordered
  `contour=internal` traces with exact source-row identity.
- PlotSpec v2 now accepts public row filters and secondary/ordering variables
  alongside textual family values, and keeps these bindings after reopen.

## 3.12.1

- Converted numeric auxiliary table values retained as CSV text cells before 2-D uncertainty band, error and bound rendering. This restores the Sardinia campaign's automatic confidence-band graph while preserving the canonical Dataset.

## 3.12.0

- Added direct transient 2-D vector plotting through the existing Plot Dataset renderer for Scientific Worksheet previews. Multiple aligned Y series and source units are supported without publishing a Dataset or persistent graph.

## 3.11.0

- Added text/numeric family and category selection with explicit Filter, Style and Split semantics.
- Added transient 2-D overlay and 3-D curve previews through the Plot Dataset renderer.

## 3.10.0

- Made Plot Dataset API v3 the current complete facade for v2 PlotSpec operations, v1 graph lifecycle, existing snapshots and interactive 3D. API v1/v2 and PlotSpec v2 remain supported.
- Added public persistent 3D graph/Variant enumeration, source fingerprint, independent Viewer representation identity and explicit manual Sync with SYNCED, OUT OF SYNC and SOURCE MISSING states.
- Moved derived interactive artifacts into independent Viewer resources so deleting a graph does not delete its existing view.

## 3.9.0
- Added public Plot Dataset 3D API v1 for the seven existing XYZ plot types. It builds Session-owned VTP scene layers from persistent scientific Plot Variants and opens the shared Native 3D viewer.
- Preserved static Plot Dataset output and APIs v1, v2 and v3. Derived interactive geometry carries source Dataset identity and checksum; refresh rebuilds it.

## 3.8.0
- Added public Plot Dataset API v3 for detached HDF5 scientific snapshots and exact displayed-point to source-row indexes. APIs v1 and v2 retain their existing contracts.
- Preserved canonical source-row identities through bounded 2D reduction and family grouping so CORE can publish selected source data without treating reduced display samples as the complete Dataset.
- Corrected 3D GUI legend precedence and layout propagation for module-published plots, including explicit legends on colorbar-oriented surfaces.
- Improved exported raster calibration when external legends or borderless styles leave a measured left/bottom frame rather than two complete frame pairs.

## 3.7.0
- Added public `series_family_grouping` for 2-D PlotSpec series using a numeric Dataset variable.
- Family groups render as independent traces from the original canonical Dataset rows without creating derived curve copies or resampling.
- Added optional `family_label_prefix`; Dataset variable units are preserved in legend labels.
- Family-grouped series deliberately disable display reduction in this first release so group boundaries and source rows cannot be mixed by a reducer.


## 3.6.0

- Added generic PlotSpec v2 axis `direction=normal|reverse` persistence and rendering for scientific graphs that conventionally reverse an axis, including IR wavenumber plots.
- Added the public `axis_direction` capability without changing existing automatic/linear/log axis behavior.

## 3.5.0

- Added generic PlotSpec v2 exact X-interval bars through Dataset-bound `bar_bounds.lower_variable_id` / `bar_bounds.upper_variable_id`.
- Added optional `bar_baseline` presentation state; ordinary scalar-width bars remain backward compatible.
- Interval-bound variables participate in preparation fingerprints, persistence, rerender, display-unit conversion and the Series Presentation editor.
- Added capability `bar_x_bounds` to `PLOT_DATASET_API_v2`.

## 3.4.1

- Render box/whisker IQR and median outlines with portable line primitives instead of `patch`, which the Debian GNU Octave/gnuplot headless renderer dropped from PNG output. This restores visible boxes in Session graphs without changing statistical values or PlotSpec settings.

## 3.4.0

- Added public PlotSpec v2 `histogram` and `box_whisker` series kinds, including histogram bin/normalization options and configurable box-whisker IQR/outlier behavior.
- Distribution plots consume the complete finite Y-variable sample with display reduction disabled, so bin counts and quartiles never derive from a decimated trace.
- Kept stable Dataset/Variable Graph Series identity and persisted presentation options without creating binned or quartile Dataset variables.
- Restricted distribution plots to one `plot.dataset.xy` panel and the left axis, with explicit rejection of mixed Cartesian/distribution or histogram/box states.
- Validated both representations with real GNU Octave against a retained copy of the Chiarello `test-10` scientific Session.

## 3.3.12

- Added a final layout pass based on an immutable per-render baseline. Single-panel manual margins and multi-panel automatic/manual geometry are absolute and idempotent across rerenders.
- External Above, Below, Left and Right legends now reserve measured bands before final axes placement. Inside and Manual legends remain in their owning panel.
- Replaced the toolkit-dependent global title annotation with a centered axes-normalized title positioned after legend finalization.
- Made Y-label spacing symmetric for Y Left and Y Right and reserved explicit label bands to prevent overlap with ticks or page clipping.
- Preserved the hidden shared-X Region Selection frame exactly: box off, visible off, stable tag and hidden handle.
- Requires GX-TXT 0.9.7.56 for persistent layout runtime serialization. Public PlotSpec and PLOT_DATASET APIs are unchanged.

## 3.3.11

- Fixed the vertical line between stacked panels. 3.3.10 turned the shared-X selection frame's box off, but an Octave axes with `box off` still draws its left spine, which is why the line survived on the left only. The frame axes is now `visible off` and draws nothing.
- Added `apply_plot_layout_overrides()`: when the Plots-tab layout controls are not on Automatic for this plot, the stored margins, panel gap and Y-label distance replace the computed layout. It reads `axis.<graph>.layout_*` directly and does not depend on `axis.<graph>.enabled`.
- Reduced how far the automatic margins move back towards the configured values, and the Y label is now placed a full padding clear of the tick column, with the left margin reserving that clearance on both sides of it.
- No public API, PlotSpec schema, Graph Series identity or data-preparation change. The single-panel renderer is byte-identical to 3.3.5.

## 3.3.10

- Fixed the continuous vertical lines running between stacked panels. `create_shared_x_selection_frame()` drew a `box on` axes spanning the union of the panels; its top and bottom edges coincide with the panel frames, so the only pixels it contributed were the two vertical segments crossing the inter-panel space. The box is now off. The tag is referenced nowhere else in the package and `write_shared_x_region_metadata()` builds its own synthetic axes, so no Region Selection input is removed; raster calibration now locks onto the panel frames, whose X extent is identical because all panels share left and width.
- Fixed margins being too tight after 3.3.9, which clipped the X label against the page edge. Each measured band now moves 35% of the way back towards its configured margin when the configured one is larger, so the Graphics stacked margins act as the generosity anchor instead of a floor.
- Added minima that do not depend on `tightinset`: the bottom band holds a tick line plus the X label line, the top band a panel title plus the global title line, and the gap one title line with air above and below. In 3.3.9 the rendered gap collapsed to a single shared frame line; this floor makes the separation independent of whatever the inset reports.
- No public API, PlotSpec schema, Graph Series identity or data-preparation change. The single-panel renderer is byte-identical to 3.3.5.

## 3.3.9

- Fixed multi-panel margins being the static defaults rather than an automatic layout. Measured on a rendered 1600x900 PNG, every band sat exactly on its configured value (left 10.00%, right 4.06%, top 10.11%, bottom 10.00%, gap 2.56%): the 3.3.8 measurements were all smaller than the configured floor, so `max(configured, measured)` returned the floor every time. The measured need is now the value; the configured margin is used only when that band cannot be measured, and a small absolute floor prevents any band from collapsing.
- Fixed panels sitting too close together. The gap reserved only the lower panel's top inset plus one padding, which is exactly the height of its title, so the title touched both panel frames. It now reserves that inset plus padding above and below.
- Left margin, right margin, top and bottom are likewise derived from the measured tick, label and title extents, so a stacked plot no longer carries a fixed 10% gutter regardless of content.
- No public API, PlotSpec schema, Graph Series identity or data-preparation change. The single-panel renderer is byte-identical to 3.3.5.

## 3.3.8

- Fixed stacked margins growing pass after pass: `multipanel_layout_from_single_panel()` is now computed from the pristine `gxtxt_plot_config()` values on every call instead of from its own previous output, so the two geometry passes converge on one layout.
- Removed the single-panel default axes rectangle as a margin floor. It described a full-height plot and forced roughly 13% left and 9.5% right on every stacked plot regardless of content.
- Reserved the aligned Y-label band explicitly. `gxtxt_plot_align_ylabel()` empties the native label and draws a free text object that `tightinset` cannot see, so the margin was sized for a label that was no longer there while the label itself sat at a constant offset.
- Y-label offset is now derived from the widest measured tick column across panels instead of the fixed `stacked_ylabel_x` fraction. Panels stay aligned with each other; the distance is measured. With Y-label alignment disabled the native label is kept and nothing is reserved twice.
- Global title is pinned to the top edge; the room between it and panel 1 stays available for panel 1's own title.
- A per-panel legend that CORE clamped against the whole figure is pulled back inside its owning panel when it fits there.
- Configured stacked margins remain the lower bound. The legend is still created after the final geometry pass, so room is not yet reserved for external legend placements.
- No public API, PlotSpec schema, Graph Series identity or data-preparation change. The single-panel renderer is byte-identical to 3.3.5.

## 3.3.7

- Fixed panel Y Left/Y Right Min/Max set in the provider Graph configuration dialog having no effect: `apply_panel_axes()` now resolves authority per bound through `core_axis_bounds_present()`, so CORE keeps every bound it declares and PlotSpec fills only the bounds CORE leaves empty. Previously any declared CORE axis field suppressed the whole PlotSpec axis and the panel stayed autoscaled.
- Reverted the 3.3.6 `core_axis_panel_state_declared()` widening; per-field authority covers the per-panel CORE keys precisely and does not affect shared X.
- Shared X keeps the historical whole-axis authority. The single-panel renderer and `apply_axis_one()` are byte-identical to 3.3.5.

## 3.3.6

- Fixed multi-panel right-Y series being hidden by their own panel: each panel overlay is raised above its opaque primary immediately before export, and that panel's legend is restored above it. This mirrors the pre-export contract the single-panel renderer already had; the single-panel path is unchanged.
- Fixed CORE axis authority in multi-panel: axis state saved only in the per-panel keys (`panel<j>_*`) is now recognized, so PlotSpec no longer overwrites ranges applied from the Axes dialog. Single-panel authority resolution is untouched and still uses the graph-level scan.
- Removed the temporary overlay retag workaround in `apply_core_panel_axes()`; GX-TXT 0.9.7.50 resolves panel overlays directly, and keeping the retag would hide every panel from the new resolver. Requires framework 0.9.7.50.
- No public API, PlotSpec schema, Graph Series identity, panel membership or data-preparation change.

## 3.3.5

- Reconcile PlotSpec presentation with current Graph Series stable IDs before runtime generation while preserving valid panels, axes and styles.
- Remove stale PlotSpec-only series and add neutral presentation for newly committed Graph Series so multipanel rerender cannot silently omit them.
- Rebuild missing, incompatible, incomplete or unreadable derived cache through the normal rerender path without changing persistent variants.
- Regenerate plot summaries on every render/rerender, including cache reuse, so summaries always describe the selected graph.
- Support explicit render/rerender of a USE-disabled base plot or variant without changing persistent USE, and keep variant runtime generation isolated from the base runtime.
- Keep PLOT_DATASET_API_v1, PLOT_DATASET_API_v2 and PlotSpec v2 schemas unchanged.

## 3.3.4

- Fix elapsed-time X coordinates that are delivered by Canonical Dataset API v2 as numeric seconds while Graph Series retains the original declared unit such as `h`.
- Normalize every temporal 2-D X coordinate to seconds once during preparation; display conversion to `s`, `min`, `h` or `day` is then presentation-only.
- Preserve the original declared unit as `x_meta.source_unit` while `x_meta.unit`/`runtime_unit` describe the prepared numeric coordinate (`s`).
- Bump the render-cache module version so caches prepared with the previous mismatched X-unit contract cannot be reused.
- Single-panel and multi-panel use the same normalized X representation; Region Selection continues to operate on the prepared coordinate and display-unit conversion path.

# Changelog — Scientific Dataset Plot

SPDX-License-Identifier: GPL-3.0-or-later

## 3.3.3

- Reworked only the multi-panel renderer to reuse the proven single-panel X and dual-Y primitives. Shared X now uses the merged `V.axes.x` authority and the standard `v2_axis_label()` path; the renderer-local shared-X label/configuration helpers were removed.
- Multi-panel right-Y axes are now created with CORE `gxtxt_plot_dual_y_axes()` and keep the native right-side `ylabel()` behavior used by working single-panel plots.
- Fixed shared-X linking so all panel primary axes and all right-Y overlays belong to one X link group. This prevents a later primary-only `linkaxes()` call from detaching right overlays and leaving stale X limits.
- Added adaptive stacked geometry derived from native axes `tightinset`: right margin grows for Y Right ticks/label, inter-panel gaps grow for panel titles, top margin preserves global-title room plus the top-panel title, and bottom margin grows for the shared X label.
- Region Selection code and metadata writers are unchanged; the selection frame is created only after final panel geometry.
- Added regression coverage for elapsed-time shared X and for the same canonical Y variable used in two panels with distinct `series_id` values. No temporal parser, Table Stream or single-panel behavior changed.
- Public PlotSpec/API schemas remain unchanged.

## 3.3.2

- Fixed multi-panel Y compatibility validation: units are compared only among series sharing the same panel and Y side. The graph-wide X compatibility contract is unchanged.
- Fixed multi-panel Y Right label placement by using an explicit normalized right-side label position on each right-axis overlay.
- Cooperates with GX-TXT 0.9.7.43 notebook-safe scrollable Axes and Graph Series dialogs; no PlotSpec or public API schema change was required.
- Preserved independent panel Y Left/Y Right display units/scales/ranges, shared X, Graph Series identity, variants, stale-reference reconciliation, Dataset Selection and the large-data dataset-native path.
- Requires GX-TXT 0.9.7.43 for the complete GUI behavior. `PLOT_DATASET_API_v1` remains byte-identical and API v2 remains backward-compatible.

## 3.3.1

- Reconcile persisted PlotSpec state when a referenced canonical dataset or X/Y variable no longer exists. Stale series are removed rather than rebound; valid series keep their exact `dataset_id + x_variable_id + y_variable_id`.
- Drop only invalid error/uncertainty auxiliary bindings when their referenced variables disappear.
- If no valid series remain, remove the dead PlotSpec plus PNG/render-cache/summary artifacts so the obsolete graph no longer persists as a result.
- Expose panel membership as a read-only `Panel` column in the standard CORE Graph Series table through the backward-compatible Series Editor Extension API v1 table-column hook.
- The standard and standalone Series editors are vertically scrollable for large series sets.
- Requires GX-TXT 0.9.7.42. `PLOT_DATASET_API_v1` remains byte-identical and API v2 remains backward-compatible.

## 3.3.0

- Added integration with GX-TXT Axis Configuration Extension API v1 so a rendered multi-panel `plot.dataset` artifact exposes provider-specific panel title, Y Left/Y Right label, display-unit and linear/log scale controls directly inside the shared **Axes / grid / 3D / color** dialog.
- Kept CORE per-panel numeric limits, tick formatting, grid and alignment authoritative; the provider extension does not duplicate those controls.
- Artifact matching uses the public `plotRefForArtifact(path)` surface, so plots created through `PLOT_DATASET_API_v2` receive the same extended axes controls even when another module is the consumer.
- Preserved Graph configuration as the owner of multi-panel enable/create/remove/order and Series editing as the owner only of series-to-panel assignment.
- Requires GX-TXT 0.9.7.41. `PLOT_DATASET_API_v1` remains byte-identical and `PLOT_DATASET_API_v2` remains backward-compatible.

## 3.2.1

- Fixed multi-panel global-title rendering so it uses the configured GX-TXT title font size/weight and is positioned from the finalized top-panel geometry instead of a hard-coded figure Y coordinate.
- Fixed multi-panel legend placement by creating legends only after stacked axes layout and panel axis overrides are final. GNUplot helper legends therefore follow their panel instead of overlapping at the pre-layout axes position; manual placement is translated to the corresponding panel-local position.
- Extended `PLOT_DATASET_API_v2` backward-compatibly with `plotRefForArtifact` and `panelIdsForArtifact` plus the `artifact_panel_discovery` capability, allowing CORE consumers to discover persisted panel IDs from a rendered `plot.dataset` artifact without inspecting private PlotSpec files.
- Preserved single-panel rendering, Graph Series identity, variants, Dataset Selection, dual-Y, typed-binary Table Stream v3 and bounded large-data preparation. `PLOT_DATASET_API_v1` remains byte-identical.
- Requires GX-TXT 0.9.7.40 for CORE `stackedGraphPanels(path)` integration with public `plot.dataset` panel discovery.

## 3.2.0

- Moved multi-panel lifecycle management from Series editing to the normal **Graph configuration** workflow. `plot.dataset.xy` now exposes an explicit Multi-panel toggle plus panel create/remove/order controls through Graph Configuration Extension API v1.
- Added optional per-panel titles and panel-local Y Left/Y Right label, display unit, scale, minimum and maximum controls while retaining the existing graph-wide title and shared X domain.
- The standard Series Editor now shows only the existing-panel assignment selector, and only while multi-panel mode is enabled. Panel creation/removal/reordering is no longer owned by any Series editor.
- Extended `PLOT_DATASET_API_v2` backward-compatibly with `multiPanelEnabled`, `setMultiPanel`, `panelInfo`, `setPanelTitle`, and `setPanelAxis`. PlotSpecs written before 3.2.0 infer multi-panel enabled when more than one panel is present.
- Preserved panel state when multi-panel mode is temporarily disabled; rendering falls back to the established single-panel path and re-enabling restores the saved panel layout.
- Preserved Graph Series scientific identity, variants, dual-Y, shared-X Dataset Selection, dataset-native Table Stream v3 access, typed-binary transport, implicit coordinates, bounded large-data reduction and the existing 3-D path.
- Requires GX-TXT 0.9.7.39 for the new public Graph Configuration Extension API v1. `PLOT_DATASET_API_v1` remains byte-identical.

## 3.1.1

- Fixed the standard CORE Graph Series editor integration for multi-panel plots: panel creation, removal and ordering are now directly available in the `plot.dataset` provider area, next to the per-series Panel selector.
- The standalone PlotSpec v2 editor remains supported but is no longer required to create the first additional panel interactively.
- Added a real standard-Series-Editor GUI regression so future releases cannot expose only panel assignment without panel lifecycle controls.
- No GX-TXT CORE files or public CORE APIs are changed. `PLOT_DATASET_API_v1` remains byte-identical and `PLOT_DATASET_API_v2` remains backward-compatible.

## 3.1.0

- Added real vertically stacked multi-panel rendering for `plot.dataset.xy` through the existing PlotSpec v2 `panels[]` schema.
- Added one graph-wide synchronized visible X domain across panels while preserving every Graph Series `dataset_id + x_variable_id + y_variable_id`; panels may contain different canonical datasets and different X identities/samples.
- Added panel-local Y Left/Right rendering, axes, annotations and legends while preserving the existing CORE graph/panel axis-authority surface.
- Extended `PLOT_DATASET_API_v2` backward-compatibly with multi-panel validation/persistence plus `panelIds`, `addPanel`, `removePanel`, `movePanel`, and `setSeriesPanel`.
- Added panel create/remove/order and per-series panel assignment to the module-owned PlotSpec editor; the Series Editor provider can move the selected series between existing panels.
- Preserved one-panel PlotSpecs and the existing single-panel renderer unchanged. `plot.dataset.xy_region` remains deliberately single-panel.
- Preserved Base/Variant/Duplicate PlotSpec isolation; complete panel layout and series assignments are copied independently while Graph Series identities remain unchanged.
- Added shared-X multi-panel Region Selection metadata so `plot.dataset.xy` continues to publish one graph-wide X interval through the existing CORE Dataset Selection path.
- Preserved Canonical Dataset API v2 / Table Stream API v3 access, typed-binary numeric transport, implicit coordinates and bounded large-data preparation; panel layout consumes already prepared series and does not reinterpret storage.
- `PLOT_DATASET_API_v1` remains byte-identical. No GX-TXT CORE source was modified.

## 3.0.1

- Fixed the 3.0.0 regression that corrupted 2-D graphs containing heterogeneous Graph Series X bindings/references.
- Restored the proven 2.1.6 per-series CSV preparation semantics for heterogeneous explicit CSV series; each series is read from its own canonical CSV path with its own X/Y binding and is never rebound to another series' X domain.
- HDF5 datasets, implicit coordinates, and homogeneous/shared-X graphs continue to use the dataset-native Table Stream API v3 path introduced in 3.0.0.
- X-axis limits are used for source-range pre-reading only when every active Graph Series shares the same `dataset_id + x_variable_id`; heterogeneous X limits remain presentation-only.
- Changed the 2-D preparation fingerprint so render caches produced by the broken 3.0.0 multi-X path cannot be reused.
- Preserved PlotSpec, variants, dual-Y, selections, implicit-coordinate support, bounded extrema-preserving reduction, and 3-D behavior.
- No CORE/framework API or source changes.

## 3.0.0

- Migrated the normal 2-D Graph Series preparation path from physical-path Table Stream v2 reads to dataset-aware Table Stream API v3 using `runtime.session + dataset_id + variable_id`.
- Added transparent support for canonical CSV and HDF5 tables, including uniform implicit coordinates synthesized by CORE. `plot.dataset` no longer requires an implicit X variable to exist as a physical storage column.
- Added bounded, chunked extrema-preserving display preparation for large 2-D series. Automatic reduction keeps source-row minima/maxima plus endpoint samples instead of naive stride-only decimation.
- Added safe X-range planning for canonical uniform coordinates. Explicit graph X bounds are converted to source units and mapped to Dataset `start/count`; random-access providers can read only the useful range while sequential providers remain correct through CORE fallback.
- Kept canonical datasets unchanged: reduction exists only in `render_cache.mat` presentation data.
- Preserved Graph Series identity, heterogeneous Dataset/X bindings, dual-Y, variants, PlotSpec styles/error/band bindings, selections, ordinary CSV 2-D behavior, and the existing 3-D workflow.
- 2-D cache identity no longer depends on physical Graph Series paths. Dataset IDs and stable Variable IDs are the scientific identity.
- Added 3.0.0 regressions for dataset-native architecture, canonical CSV/HDF5 access, implicit frequency coordinates, large-data extrema preservation, and X-range direct access.

## 2.1.6

- Fixed provider-owned PlotSpec initialization for new 2D variants. A variant now receives an independent copy of the exact source PlotSpec (base or source variant) when CORE creates it, so per-series line/marker/opacity/error/band presentation is present immediately instead of reverting to defaults.
- Variant presentation copying is module-only and leaves CORE Graph Series as the scientific binding authority. The copied PlotSpec is a separate sidecar, so later Base/Variant/Duplicate edits remain isolated.
- Added a fallback initialization when the Series Editor opens a New-from-base variant that was created before `PLOT_DATASET_API_v2` activation.
- Preserved the 2.1.5 prepared-data fingerprint fix: presentation-only changes remain rerender-only while error/band auxiliary variable bindings still invalidate preparation.
- Added a focused Base -> Variant -> Duplicate presentation inheritance/isolation regression.

## 2.1.5

- Fixed variant presentation rerender invalidation on GX-TXT 0.9.7.35. `pd_prep_fingerprint` no longer changes merely because a PlotSpec v2 exists or because a presentation-only series entry is saved.
- PlotSpec line style, line width, marker, marker size/fill, opacity and other presentation-only edits now keep the existing prepared-data cache reusable for `Save and render` / rerender.
- Auxiliary data bindings used by error bars and uncertainty bands remain part of the preparation fingerprint, including their owning `series_id`; adding, removing or changing those bindings still correctly requires data preparation.
- The package now requires GX-TXT 0.9.7.31 so Variant Editor `Save` / `Save and render` uses the corrected Series Editor provider-save lifecycle.
- Added `tests/test_v215_variant_presentation_rerender.py` to prevent the 2.1.4 false cache invalidation from recurring.

## 2.1.4

- Fixed a 2.1.3 cache-rerender regression that broke the framework `Axes... -> Save and rerender plot` workflow: `pd_source_map` gained the enabled-graph argument during the Graph-Series-only refactor, while `plot_dataset_rerender_main.m` still called the obsolete two-argument form. Rerender now resolves enabled graphs first and passes the same source-map contract used by the normal run.
- Added a regression test that rejects any stale two-argument `pd_source_map` call in the rerender path and verifies that framework Axes state remains graph-addressed and writable under GX-TXT 0.9.7.22.
- Removed the legacy 2-D descriptor/runtime fallback: active Graph Series are now the only 2-D scientific binding authority.
- Removed the legacy 2-D Y-right binding, Additional 2D Series configuration, and private Family/group row-grouping renderer path.
- Preserved the current 3-D X/Y/Z plus optional Family/Color binding model and 3-D renderer.
- Added an explicit error when a 2-D graph has no active Graph Series instead of silently using legacy bindings.
- Prevented an unrelated Standard Module `primary` source from becoming 2-D scientific authority; Graph Series datasets drive 2-D loading/cache identity and unrelated-primary computed annotations are excluded.
- Preserved `PLOT_DATASET_API_v1` byte-for-byte while modernizing the newer/internal runtime path.
- Added session regression coverage proving obsolete persisted Y-right/Additional-series state no longer affects modern 2-D runtime after save/reopen.
- Added target-host Region Selection diagnostics that report loaded module identity, duplicate/shadow copies, axes classification, graph/variant identity, PNG dimensions, plot rectangle, and calibration status.
- Retained the 2.1.2 module-side Region Selection topology/calibration instrumentation, but do not claim the target-host Region Selection failure fixed until the real Octave/GNUplot/Tk acceptance path passes.
- Documented the remaining 2-D Family modernization blocker: Graph Series API v1 has no public exact row-membership predicate; no hidden filter, private family registry, temporary per-family CSV, or legacy renderer was introduced.
- No CORE source was modified.

## 2.1.2

- Restored robust module-side use of the existing CORE X-range Region Selection calibration path without modifying CORE or adding a private selection model.
- Reasserted the primary/overlay axes tags immediately before export, tagged the GNUplot custom-legend helper axes explicitly, and rendered a closed primary 2-D frame so CORE exported-raster calibration has a deterministic plotting rectangle with or without grid lines.
- Kept dual-Y as one shared X geometry; the right-Y overlay is not a second selectable panel.
- Carried forward the 2.1.1 title-authority and dual-Y grid corrections: descriptor/variant title remains authoritative and the right-Y overlay does not receive a late common-grid reapplication.
- Verified that CORE 0.9.7.22 already provides X-range edge resize and whole-range move operations, graph/variant persistence, raster pixel-to-scientific mapping, and linear/log/reverse-X conversion.
- Confirmed a public-contract limitation without introducing a workaround: automatic Dataset Selection promotion currently requires all active Graph Series to resolve to one `dataset_id + x_variable_id`, so heterogeneous Graph-Series X bindings cannot complete the current CORE gesture transaction.
- Confirmed that the existing 1:1 PNG viewer has no public Region Selection canvas-registration hook in CORE 0.9.7.22; normal-view Region Selection remains fully framework-owned.
- No CORE source, Graph Series API, legacy 2-D renderer, or private selection registry was added or modified.

## 2.1.0

- Added `plot.dataset.presentation` integration with GX-TXT 0.9.7.21 Series Editor Extension API v1 when `PLOT_DATASET_API_v2` is activated.
- Added provider-owned per-series controls for representation kind, line/marker style, line width, marker size/fill, opacity, step/bar options, X/Y error bindings and uncertainty-band bindings, including `draw_center`.
- Reused the same PlotSpec v2 presentation collection, validation and atomic persistence path for the standard provider area and standalone `openEditor`; Graph Series generic fields remain CORE-owned.
- Added regressions for series switching, validation rejection, close/reopen persistence, base/variant isolation and graph isolation.
- Confirmed that GX-TXT 0.9.7.21 has no public graph-addressed axis configuration action for the Analysis `Configure...` workflow; no second axis state or private `axisOverride` access was introduced.
- Confirmed that the Plots-viewer `USE / NON USE` flag is private transient viewer state and is not projected into Standard Module runtime. Public Graph Provider enablement and Variant enablement remain honored; no private viewer-state workaround was introduced.
- Documented the two CORE access gaps separately. Clone, Variant semantics, Frozen/Dirty lifecycle, Dataset Selection and Series Editor provider activation are unchanged.

## 2.0.1

- Targeted GX-TXT 0.9.7.21+ without changing Module ID or either public Plot Dataset API version.
- Removed the effective 2D axis dual-authority bug: saved CORE Axes state now owns X/Y-left/Y-right display units and manual bounds; CORE automatic/reset state suppresses overlapping persisted PlotSpec values.
- Kept PlotSpec axis fields backward-compatible as the fallback when no CORE axis state has been declared. PlotSpec retains 2D X/Y `linear`/`log` scale because GX-TXT 0.9.7.21 has no overlapping CORE control.
- Made explicit descriptor graph labels authoritative over PlotSpec labels while retaining PlotSpec labels as the `auto` fallback.
- Avoided treating all-`inherit` in-memory defaults created by opening/canceling the CORE Axes dialog as saved CORE axis authority.
- Verified Series Editor Extension API v1 callback semantics, but did not add an order-dependent partial registration: GX-TXT 0.9.7.21 lacks a public provider activation/bootstrap path before standard `Series...` extension lookup. The exact CORE blocker is documented separately.
- Added focused static/diagnostic/real-render regressions for axis authority and the Series Editor provider-activation blocker.
- Clone, Variant Duplicate, Frozen/Dirty lifecycle, Dataset Selection and unrelated plotting features are unchanged.

## 2.0.0

- Kept `PLOT_DATASET_API_v1` byte-for-byte frozen and added discoverable `PLOT_DATASET_API_v2`.
- Added declarative `PLOT_DATASET_PLOTSPEC_v2` with a future-proof `panels[]` structure; this release intentionally supports exactly one Cartesian 2D panel.
- Added per-Series `kind` independent from `style`: `line`, `scatter`, `line_marker`, `step`, `errorbar`, `band`, and `bar`.
- Added per-Series color, line style/width, marker/size/fill and opacity with explicit distinction between an absent property, `inherit`, and `auto`.
- Added symmetric/asymmetric X/Y error bindings and uncertainty-band lower/upper bindings using stable dataset-scoped variable IDs.
- Added PlotSpec axis configuration and reference line/reference region annotations.
- Added streamed auxiliary-variable preparation tied to the same selected source rows as X/Y, with no interpolation/resampling.
- Added presentation-only v2 refresh for cache rerender; auxiliary binding changes correctly require a fresh analysis run.
- Added standalone public PlotSpec-v2 Series/style editor without patching the CORE Graph Series dialog.
- Added v2 API, consumer, persistence, wrapper render/rerender/artifact, GUI and real-Octave graphics regressions.
- Preserved legacy fallback, Graph Series, base/variant behavior, dual-Y, Level Scale, multi-dataset plotting and existing 3D implementation.
- Histogram, pie, multi-panel rendering and a v2 3D PlotSpec are intentionally not advertised in this release.

## 1.2.0

- Added public, versioned `PLOT_DATASET_API_v1`, discoverable from the normal `plot.dataset` Standard Module API descriptor.
- Added programmatic base/variant plot references, Graph Series create/update/remove/enable/order operations, descriptor-backed plot configuration, render/rerender requests, artifact lookup, configuration inspection and capability discovery.
- Reuses CORE Graph Series, Plot Variant, Standard Module runner/rerender and manifest persistence instead of introducing a second rendering or Series registry.
- Added consumer-only API regressions covering one-series, multi-series, multi-dataset, dual-Y, variants, render, rerender, artifacts, persistence and invalid references.
- Retains the 1.1.2 elapsed-time fix: `semantic_role=elapsed_time` accepts HMS `value_kind=elapsed_time` and numeric-duration `value_kind=number` when units are convertible.
- Updated render-cache/summary module version metadata to 1.2.0.

## 1.1.2

- Fixed multi-dataset X compatibility for elapsed time represented differently by different datasets.
- `semantic_role=elapsed_time` now accepts the scientifically equivalent pair `value_kind=elapsed_time` (HMS representation) and `value_kind=number` (numeric duration), provided the X units are convertible through the Unit Registry.
- The relaxation is deliberately narrow: other semantic roles still require matching explicit `value_kind` values, and mismatched semantic roles remain rejected.
- Added a regression for HMS elapsed hours versus numeric elapsed seconds, preserving the no-interpolation/no-resampling rule.

## 1.1.1

- Fixed GNU Octave dual-Y rendering order: the transparent right-Y overlay is now kept above the primary axes at export, while the legend remains the final top graphics layer.
- Fixed Y Right label styling by routing it through the common `gxtxt_plot_text` service.
- Moved computed data annotations before legend creation so the GNUplot custom legend remains the final graphics operation, as required by the framework renderer.
- This is a presentation-only fix: Graph Series identities, data, units and Y2 scientific limits are unchanged.

## 1.1.0

- Reworked 2D plotting around Graph Series API v1 for both base graphs and plot variants.
- Added direct multi-dataset 2D display without joining, interpolation or resampling.
- Added graph-specific `xy` / `xy_region` preparation caches and fingerprints.
- Added conservative shared-X semantic/unit/time compatibility validation.
- Applied large-dataset presentation reduction independently to Graph Series and counted non-finite dropped rows.
- Added deterministic Series colors across left/right axes and persistent Series ordering.
- Kept X/Y/Y2/Additional Series as a legacy fallback only when a graph has no active Graph Series.
- Made X/Y descriptor bindings optional so pure Series-based 2D graphs no longer require redundant legacy bindings.
- Kept 3D as a distinct X/Y/Z + Family/Color path.
- Updated documentation and module regressions for GX-TXT 0.9.7.13.

## 1.0.1

- CORE plotter consumes Computed Data Annotation API v1 sidecars attached to the selected canonical dataset.
- Draws framework-owned `vline`, `hline`, `point` and data-anchored `text` annotations after scientific traces and before export.
- Converts annotation source coordinates to current display units without modifying canonical data.
- Explicitly accepts first-class `spectrum.table`.


## 1.0.0

- New stable module ID `plot.dataset`.
- New generic canonical-dataset plotter built for GX-TXT Pipeline >= 0.9.3.3.
- Added 2D line/scatter/line+markers rendering.
- Added arbitrary additional 2D series through Repeatable Config API v1.
- Added framework Multi-Y Left/Right support.
- Added Family/group rendering with Unit Selector API v1 for numeric Family labels.
- Added separate framework-owned `x_range` and `rectangle` Dataset Selection graph offerings.
- Added Plot 3D API v2 support: `line3`, `scatter3`, `surface`, `mesh`, `contour3`, `trisurf`.
- Added optional C color-variable support where supported by the 3D primitive.
- Added strict gridded-vs-scattered behavior with no implicit scientific interpolation.
- Added Table Stream API v1 selected-column/chunked input.
- Added presentation-only 2D min/max/stride reduction and 3D stride/grid subsampling.
- Added standard Render Cache API v1 with source/preparation fingerprint validation.
- Added Progress API v1 reporting.
- Uses framework-owned units, axes/grid, legend, annotations, 3D view, colormap/colorbar and Plugin Install API.
- Documented the public CORE integration contract.

## 1.0.0 / GX-TXT v0.9.4 CORE integration

- promoted to bundled CORE scientific dataset plotter;
- numeric Family grouping now canonicalizes equivalent numeric spellings (`1`, `1.0`, `1e0`);
- retains categorical Family text unchanged;
- relies on v0.9.4 framework contract-specialization matching for future `table.generic` descendants.

Dev087 same-version manual correction: canvas eligibility, native calibrated axes/grids/scalar bar, flat-cell fidelity, roll, shared enlarged viewport and explicit high-resolution Dataset publication.

## Retained release notes from the module overview

Version 3.10.0 made `PLOT_DATASET_API_v3` the complete current facade for
PlotSpec v2 operations, legacy graph lifecycle, detached snapshots and
interactive 3D. A consumer activates only v3. A persistent graph/Variant can
create multiple independent Viewer representations. Each records its source
fingerprint; changes report OUT OF SYNC until explicit Sync, and deleting the
source reports SOURCE MISSING without deleting an existing view. The Native
3D Viewer panel lists compatible graph/Variant identities alongside imported
3D Datasets. PlotSpec persistence remains `PLOT_DATASET_PLOTSPEC_v2`.

Version 3.9.0 adds public `PLOT_DATASET_3D_API_v1`: a configured persistent
XYZ Plot Variant can be rendered interactively by the shared Native 3D viewer.
Plot Dataset interprets the Dataset and emits Session-owned scene artifacts;
the viewer renders them. Seven existing XYZ types are supported. Static plots
and public APIs v1/v2/v3 remain available. See `PLOT_DATASET_3D_API_v1.md`.

plot.dataset 3.8.0 adds [Plot Dataset API v3](PLOT_DATASET_API_v3.md) for detached HDF5 scientific snapshots and exact source-row indexes for displayed 2D points. Public APIs v1 and v2 remain available without changed consumer semantics. The existing PlotSpec v2 supports numeric 2D family grouping, reversible axis direction, Dataset-bound bar intervals, histogram and box/whisker plots, stable Graph Series identity, layouts, variants and 3D paths. It targets GX-TXT 0.9.7.56 or newer.

Release 3.3.5 reconciles persistent PlotSpec presentation against current Graph Series before runtime generation. Removed scientific series are not revived from provider state, newly committed stable IDs receive neutral presentation in the first existing panel, and surviving panel/axis/style state is preserved. Missing, incompatible or unreadable derived runtime/cache is rebuilt by the normal rerender path without deleting variants. Explicit render/rerender operates on the requested graph without changing persistent USE, variant serialization preserves the base runtime, and summaries are regenerated for every selected graph.

Release 3.3.4 fixes the temporal-X runtime-unit contract. Canonical Dataset API v2 materializes HMS `elapsed_time` values as numeric seconds; `plot.dataset` now normalizes every temporal 2-D X coordinate to seconds during preparation and performs `min`/`h`/`day` conversion only for display. The original declared unit is retained as source metadata. Prepared-cache versioning was bumped so older mismatched caches are rejected.

Release 3.3.3 made the multi-panel renderer follow that working single-panel path for shared X and Y Right: X uses the merged PlotSpec X authority and normal axis-label resolver, right overlays are created through CORE `gxtxt_plot_dual_y_axes()`, all primary/right axes share one linked X group, and stacked margins/gaps grow from the actual native text/tick extents. That release did not change global elapsed-time parsing or single-panel behavior.
