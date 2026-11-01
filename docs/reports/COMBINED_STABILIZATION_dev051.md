# Combined bug6/bug7 stabilization — dev-051

## Scope and baseline

One working copy was created from published dev-050. The frozen predecessor archive is `cb84271e91eeb8cf2d73a12bc7f12d37d6c5b0e658f4ac70e2c1695669b589ab`. This is one combined release. Existing output grids, accepted CORE curves, local fitter samples, Session Dataset authority, Native2D selection/view architecture and Curve Workbench 2.0.1 were retained.

## Components and implementation

- Plot Dataset 3.13.0: bounded lazy cached distinct values; wide Session Dataset selector and manual IDs; trace suppression while loading; one provider batch for tree rows; incremental PlotSpec mutations; per-series scientific preparation identity and cache; one bounded stream for compatible filtered series.
- Dataset Curve Fit 0.2.0 / Numerical module 1.15.0: circular arc, quadratic/cubic Bézier, PCHIP, smoothing spline and Fourier. Public fit/evaluate/project operations, reconstructible model state, nearest parametric projection, source/full residual conventions and geometric RMSE. Existing grid mechanism handles parametric domains and user output counts. Explicit fit/sample publication and CSV metadata sidecars. Internal samples never become Session Datasets implicitly; CORE acceptance remains separate.
- CORE graph presentation setter exposes existing 2-D/3-D aspect/background state to Python and Octave. Transparent PNGs use native GNUplot pngcairo alpha, preserve requested raster dimensions and white/light foreground. Raster selection calibration respects alpha and bridges only small foreground interruptions in measured frame lines.
- Public operational Plot Annotation API enforces graph descriptors, stable IDs, atomic writes and Session identity. Public Graph Notes and Graph Metadata use existing resource/Manifest lifecycle; Variants/Clones copy resources independently, deletion cleans them up. Clone title/USE and annotation copy survive reopening.
- Public `publish_series` and `publish_auto` reuse Dataset writer/file transactions. Full scientific declaration fields, namespaced metadata and coherent V2/V3 updates preserve units, source semantics and restricted conversions. Octave preserves exact namespaced result keys; Tcl dictionary serialization preserves annotation `id`.
- Portable Resource API exports/imports one Dataset or Graph with explicit SHA manifest, unchanged CSV/HDF5/opaque bytes, scientific schemas, reversible schema snapshots, resources and declared dependencies. Graph import creates a new Detached Clone; scientific snapshots are validated in staging, rendered-only fallback is explicit. Host-only filesystem transport stays outside Script Bridge.
- HTML Export 1.0.4 includes Graph Notes and preserves clean/annotated PNG alpha. Notes editor keeps Save/Close visible.

## Performance evidence

Same disposable Chiarello Session, 100 Graph Series, Linux Tcl/Tk on Xvfb. One focused run per final fixture; timings include real Tk event processing. These are local observations, not hardware-independent promises.

| Action | dev-050 ms | dev-051 ms |
| --- | ---: | ---: |
| Open 100-series editor | 18254.733 | 779.460 |
| Refresh rows | 17872.629 | 394.564 |
| Select/load row | 1053.625 | 353.442 |
| Update one series | 577.422 | 228.984 |
| Move series | 607.110 | 260.438 |
| Remove series | 571.942 | 227.668 |
| Distinct values, warm | 9.785 | 0.309 |

Four filtered series over the real 33,673-row joined Dataset, with its row count supplied accurately in the disposable fixture: all X/Y/auxiliary values, exact source-row identities, counts and reduction modes equal independent preparation. One batch stream replaces four independent streams. None: 4.662 s → 1.085 s (4.30×); stride: 4.590 → 1.095 s (4.19×); minmax: 4.689 → 1.186 s (3.95×); auto: 4.758 → 1.182 s (4.03×). Fingerprint checks preserve preparation across presentation/order/unused-target changes and invalidate changed filters/scientific schema.

## Focused validation

Scripts and usage/side effects are cataloged in the workspace `SCRIPT_CATALOG.md`; reusable candidate fixtures are in `validation/combined_dev051/`.

- Deterministic scientific test passed all six models, exact Bézier controls, arc orientation/noise/degeneracy, parametric projection, monotonic PCHIP/duplicate rejection, smoothing-lambda and analytic natural-spline midpoint, Fourier DC/sine/cosine/phase/explicit period/orders 3/100/1000, rank/insufficient-sample rejection and 20-to-1000 resampling.
- Fitter integration passed sample-local separation, CORE acceptance, 1000-point results, explicit fit/sample publication, complete metadata/CSV sidecar, actual Plot Dataset rendering and Session reopen.
- Real fitter Tk controls passed all six model previews/acceptance and exact points/model-state/provenance after save/reopen, without automatic Dataset creation. Existing five-model fitter compatibility and Curve Workbench 2.0.1 GUI fixture passed.
- Real Python/Octave registered scripts passed numerical model operations, CSV/HDF5 series publication, structured metadata, scientific schema updates, atomic unsafe-formula rejection, completed PNG publication/source confinement, 2-D equal aspect, 3-D xy_equal/data_equal/manual rerenders, background inheritance/opaque/transparent, Notes/Metadata and annotation CRUD. Shipped examples executed in both languages.
- Representative common 3-D Axes Tk fixture passed auto/xy_equal/data_equal/manual and reopen; final manual metadata DAR is `1;1;2`. Static 3-D PNG is RGBA with alpha-zero corner.
- Dataset ZIP round trips passed exact HDF5 and opaque PNG bytes/schema/metadata/notes; CSV Use=no snapshot transport and Use=yes byte restoration; custom unregistered semantic/unit strings and Dataset-owned conversion pairs survive import without global provider registration. Graph scientific Clone, embedded dependencies, ID collisions, rendered-only fallback and reopen passed.
- Hostile ZIPs reject hash/size mismatch, duplicates, traversal, absolute/noncanonical paths, symlinks, undeclared files/dependencies, unsupported versions, excessive compression, host presentation/output paths, executable snapshot files and HDF5 external dependencies. Direct API tests reject invalid annotation type/space/nonfinite fields/duplicate or unknown IDs/undeclared identity, invalid background, multiline graph metadata, unsafe formulas and unequal publication vectors; previous annotation state/base PNG/schema remain unchanged.
- PDF/WAV/STL/STEP/SDF helper fixtures verified registry-derived real format/MIME and unchanged opaque transport bytes; these fixtures do not claim to test external scientific file parsers. Actual PNG and HDF5 fixtures use valid formats.
- Alpha fixture passed requested 640×360 PNG, alpha-zero margins, visible white/light curves/white text and white annotation composition. HTML export passed 12 Datasets/14 graph artifacts, three Graph Notes pages and three clean/annotation switches.

## Mandatory real mouse test-10 Plots validation

Authoritative Session: `/home/giu/CHIARELLO/1/GXTXT_sessions/test-10`. Every mutation used `_evidence_dev051_chiarello_test10_gui` or another disposable copy. Xvfb :93, real X11 mouse/keyboard via xdotool and screenshots; tests included repeated selections/events and reopen, not only one render.

| Workflow | Result |
| --- | --- |
| Discovery, base/Variant selection, Refresh, All/None/Toggle USE | Passed; independent resource identities and persistent Clone USE checked. |
| Rerender and selected rerender | Passed; completion dialog and unchanged source Datasets. |
| Title, X/left/right labels | Passed; persisted title/labels. |
| Axes ranges/steps/grid, 2-D equal/auto aspect | Passed; saved presentation and scientific image. |
| Graphics width/height/DPI/ticks/line width and 3-D general aspect settings | Passed; corrected transparent final raster 1400×800. |
| Opaque/inherited/transparent background | Passed; actual RGBA alpha, independent Variant state. |
| Legend layout/placement and mouse Place legend | Passed; manual position saved/rerendered; restored layout controls exercised. |
| Graph Series | Passed wide Dataset chooser, row selection, update label, add/remove series, reorder, provider panel state, Family/Second/filter choices/value refresh and save/render. 100-series Tk timings above quantify responsiveness. |
| Annotations | Passed text/arrow/rectangle, properties, undo/redo/z-order, save/reopen and annotated export. |
| Graph Notes / Metadata / Info | Passed note editor save/read/reopen, Clone note copy, imported metadata inspection; public metadata mutation tested in both languages. |
| Variant lifecycle | Passed create from base, duplicate, edit, render, delete with confirmation in disposable Session. |
| Clone lifecycle | Passed scientific create, presentation edit/rerender, independent title/USE/resources, import and confirmed deletion on copy. |
| Full-size viewer | Passed Open PNG 1:1, fit/zoom, annotation toggle, Notes, copy and saved image. |
| Graph/Dataset ZIP actions | Passed real export, import review/collision/rendered-only choices, commit and info inspection. Dataset ZIP menu remains reachable at 1080-pixel window width. |
| Save/reopen | Passed graph list, title/labels/axes/legend/alpha/annotations/notes and Clone title/USE; source Session preserved. |
| 3-D controls | test-10 has 2-D graphs; representative 3-D Axes GUI and both-language API rerenders cover applicable 3-D controls. |

GUI observations found and corrected clipped Dataset resource controls, missing Clone annotation/title/USE persistence, blank legacy schema defaults, transparent DPI size mismatch and alpha-blind raster selection calibration. Final mouse verification passed area selection/clear, exact Cl- source-row 1 point selection, and explicit creation of a one-row HDF5 Dataset; the source Dataset stayed unchanged. Raster calibration is `182;60;1266;711` for the 1400×800 transparent test image.

## Limits and deferred work

SB-014 remains unfinished: path/destination-sensitive detached snapshot and point-index operations stay host-only. Portable Resource import/export is intentionally host-only. Scientific graph ZIP reconstruction supports the existing static Plot Dataset snapshot provider; other graphs use rendered-only Clones. Dependency IDs default to collision errors, with explicit Dataset rename or rendered-only Graph import; no replace-existing policy. Archive limits are documented. HDF5 packages require h5py; static alpha requires GNUplot pngcairo and does not add transparent native interactive 3-D scenes. High-cardinality distinct lists are bounded (2000 values); cold scans remain proportional to source size. Large Fourier systems are subject to sample count/rank and machine memory/time, with no arbitrary low order cap. Existing output sample bound is retained at 2–10000. Native2D view cleanup/custom analytical models and deeper indexes remain deferred. No broad platform/package matrix was rerun; focused compatibility and real GUI evidence define this validation scope.

Authoritative test-10 latest file modification remained 2026-10-03T12:09:07.895257Z (`report/previews/preview_45573efa.png`), preceding this cycle. Its Session was never written by validation. The previous handoff was copied exactly to workspace `GXTXT_HANDOFF_CURRENT_v09810dev050.md`, SHA-256 `ab2a1eef9d52abe0a8c6282ac1c2c2ec7391f1fa02c15bfc9a686a5789e9878e`.
