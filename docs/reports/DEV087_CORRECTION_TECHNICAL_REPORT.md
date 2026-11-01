# GX-TXT dev087 — scientific interactive plot correction

Same version **0.9.8.10-dev-087**, Plot Dataset **3.13.1**. Engineering validation PASS;
**manual acceptance remains PENDING**. Pre-correction archive SHA-256
`ae34e3047e5ceeee416de34edd081c74fe2e3499077539b65d791844a82dde7d` is preserved,
with its plugin package and the previous active/expanded trees. No repeated cleanup,
new disk/storage work, scientific-original writes or unrelated interface changes.

Plots' small 3D control is placed inside the static canvas, takes no layout row and
uses the existing tooltip facility. Public `previewCompatibility` checks prepared
XYZ Variant/source/configuration eligibility; ordinary 2D/empty/unsupported selections
hide the control. Interactive controls replace it: four orbits, two viewing-direction
rolls, exact original-camera reset, Exit and scientific axes/grid toggle.

Generic CORE `NATIVE_3D_SCIENTIFIC_FIGURE_API_v1` adds copied view-owned calibration,
axis/grid visibility, original scalar palette/range/label and compatible title/legend.
The existing VTK Native3D renderer draws calibrated 3D cube axes, numeric ticks and
major grids that track camera/projection/roll. A figure presentation layer uses an
expanded frustum with the **same world/pixel projection** as the scientific scene,
keeping complete labels and the right scalar rail visible. Colors contrast against
the original opaque background. There is no private Plot Dataset axis renderer,
static Tk grid, alternative visualization engine or second scientific scene/cache.

Source inspection found flat surface colors in the real plots. Generic native direct
RGB now accepts cell arrays; both triangles of each source quad retain its original
constant color. Original point scalars remain available. No smoothing/data changes.

Double-click opens a normal maximizable window using the **same worker, view and
prepared native objects**. Resizing renders its physical viewport through existing
native target/viewport APIs without reimporting data or running Octave preparation.
Closing restores the embedded view with the synchronized camera. Existing RAM frame,
bounded host cache, source guards, cancellation and cleanup remain authoritative.

Explicit Save offers Full HD and 4K. Native offscreen rendering/supersampling uses
the current effective graphics policy, never a stretched Tk capture. Only Render &
Publish creates a canonical `image.raster` PNG through DATASET_FILE_PUBLICATION_API_v1.
Creation is transactional and rejects existing IDs. SHA/dimensions are verified;
metadata retains graph/Variant, source IDs/hashes/bindings, camera/projection,
scientific calibration/grid/scalar presentation and requested/effective graphics
settings. The normal Dataset GUI lists and reopens the result. No implicit publication,
Analysis enable, Viewer Document or saved PlotSpec edit accompanies navigation.

| Actual GUI case | Result |
|---|---|
| Thermal: installed `surface3d-example`, p0001, isolated copy | PASS: icon/axes/grid/K colorbar, six rotations, exact reset, toggle, double-click/maximize/resize, Full HD publication/provenance/reopen, static Exit and warm cache |
| Ticino: installed `demo_geospatial_ticino_valley_3d_2.0.0`, **population-density p0004**, isolated copy | PASS: exact terrain/scalar mapping, km/m axes and density colorbar, six rotations/reset/toggle, maximized window, **4K** publication/provenance/reopen, static Exit/cache |
| 2D: actual `demo_numeric_uncertainty_1.0.0`, p0001 | PASS: no icon/extra row; original PNG double-click works |
| Numerical XYZ | PASS: canonical selectors, small/250000-row cases, bounded reduction/units, retained 2D/camera/cache, no publication or Analysis enable |
| Crystal/molecule/mesh | PASS: existing scientific fixture, rendering/cube/navigation/cache/cleanup and source bytes preserved |
| Lifecycle/quality supplement | PASS: failed export retains worker/frame; 2× native supersampling; owner/window cleanup, preparation cancellation, pending-export Session replacement and read-only worker rejection/reap |

Independent check: Thermal **1681 points/3200 cells**, Ticino **5440/10586**;
coordinate maximum error **0** against original prepared MAT; point RGB and flat-cell
RGB match the original colormap exactly. Axes map original scientific ranges into
effective DAR bounds. Label/scene projections match for orthographic/perspective
and multiple roll angles. PNGs are opaque at exactly 1920×1080 / 3840×2160 and match
canonical publication SHA-256. Originals of all three catalog Sessions are unchanged.

| Measured operation (GUI settling included in first/warm/export) | Thermal | Ticino |
|---|---:|---:|
| First activation | 1531 ms | 2111 ms |
| Warm tab return | 429 ms | 431 ms |
| Embedded native camera response | 35–37 ms | 83–101 ms |
| Maximized camera response | 112–119 ms | 160–162 ms |
| Render + canonical publication | 617 ms (Full HD) | 1907 ms (4K) |

Worker PID/import count stay unchanged through navigation, toggling, enlarging and
resizing. Warm returns retain the image and PNG mtime with no render/geometry rebuild.
Viewport changes may rebuild native presentation actors, retaining scientific objects.
Earlier incomplete visual/driver attempts are retained outside the final PASS matrix.

Remaining limits: linear increasing scientific axes only. Log/reversed axes need an
explicit **nonlinear calibrated mapping contract** and are rejected, not mislabeled.
Native tick/font/grid layout, advanced annotations, boxed legend placement and marker
shapes differ from Octave. No pixel-perfect equivalence. Source surface cells are
triangulated through the existing Plot Dataset geometry API. Other providers/base or
rendered-only graphs need an exact prepared-scene identity contract. Transparent
scientific backgrounds are unsupported. D3D11 lacks the new scientific-figure/cell-RGB
backend capability; other platforms need matching compilation. Mixing cell RGB with
a point-opacity role is unsupported. Existing display/pixel/GPU/worker budgets apply;
4K with additional supersampling may exceed them. Canonical Ticino schema units were
undeclared and remain so; its original scientific graph labels are retained.

Modified implementation:
- `app/gui/graphs_page.tcl`
- `core/tcl/native3d_compact_preview_v1.tcl`, `mesh_dataset_viewer_v1.tcl`, `native3d_gui_host_v1.tcl`
- `core/native3d/gx3de_viewer_tcl.cpp`, new `native3d_scientific_figure_tcl_v1.inc`, `renderer_worker.tcl`
- new `core/native3d/include/native_3d_scientific_figure_api_v1.h`
- `core/native3d/src/native_3d_engine_api_v1.cpp`, `native_3d_renderer_impl.inc`, `CMakeLists.txt`, both compiled shared libraries
- `core/python/native3d_plot_preview.py`
- Plot Dataset's two public API Tcl files and `pd_render_3d.m`, `pd_preview_export.m`, `pd_scene_write_vtp.m`

Reused authorities: DatasetViewer/Native3D shared host, Plot Dataset public prepared
source APIs, native camera/viewport/graphics/supersampling and Dataset File Publication.
Relevant public API/GUI guide/TODO updated; unfinished prior items retained. No new
Tcl rename wrappers. Full changed-file inventory: `DEV087_CORRECTION_CHANGED_FILES.json`.
Focused logs/screenshots/geometry/presentation/provenance: `docs/evidence/dev087-correction`.
Final framework/plugin hashes and delivery parity are in the workspace corrected
handoff and archive sidecars, avoiding a self-referential archive hash.

Restart GX-TXT to load the corrected installation. Stop for manual acceptance.
