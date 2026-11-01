Historical initial dev087 report. Superseded for current acceptance by [DEV087_CORRECTION_TECHNICAL_REPORT.md](DEV087_CORRECTION_TECHNICAL_REPORT.md).

# GX-TXT dev087 technical handoff

Engineering validation complete; manual acceptance PENDING.
Baseline: published dev086; historical release/restore and scientific originals preserved.

Cleanup: free space before **31,560,134,656 B**; immediately after **38,851,428,352 B**;
reclaimed **7,291,293,696 B (7.29 GB / 6.79 GiB)**. Removed 22 complete historical
software worktrees proven byte-identical to canonical expanded releases, plus 756
regenerable ELF/static-library build outputs. Source/build logs and dependency
packages remain. Exact paths, occupied sizes and reasons: workspace
`GXTXT_DISK_CLEANUP_DEV087_MANIFEST.json`; packaged summary/journal:
`docs/evidence/dev087/cleanup-summary.json`, `cleanup-deletions.jsonl`.
The original journal's file allocation counts exclude directory blocks; the summary
adds exact occupied sizes from the retained pre-cleanup `du -x` inventory.

Scientific Sessions/Projects/Experiments/Datasets, scientific libraries, user code,
active work, release archives, restore points and installed identity were untouched.
Sixteen nonidentical historical worktrees remain listed as uncertain. Active-process
references (including older dev056 work) and scientific evidence Session trees are
preserved. The workspace originally occupied 128.5 GB; much of its largest old
validation material contains protected Session data, so no broad deletion was made.
No other mounted filesystem was traversed; no new disk/Samba/migration work occurred.

Implementation: Plots and numerical Dataset Preview share the existing CORE mesh
consultation host/state, readonly renderer worker, Native ABI, graphics policy,
owned derived cache and RAM frame. One shared bounded host dictionary retains at
most two compact owners. It is an extension, not a replacement renderer/scene or
consumer-specific cache. Existing crystal/molecule/mesh navigation cubes stay.

API authority: DATASET_VIEWER_API_v1 + Table Stream v3 / Dataset Access; existing
PLOT_DATASET_API_v3 and PLOT_DATASET_3D_API_v1 gain readonly previewExportCommand;
NATIVE_3D_GUI_HOST_API_v1 gains compact host lifecycle. Native transport exposes
existing native camera reset/direct RGB/point-glyph policy operations. Kernel ABI,
engine sources and libgx3de are unchanged. No new Tcl rename wrappers.

Preserved exact graph/Variant/source and stable bindings, prepared transformations,
filters/reduction, surface/mesh/line/scatter/contour geometry, display units and Z
level transformations, labels/limits/linear scales, effective aspect, projection,
view/camera/FOV, colors/colormap/scalar ranges and applicable series settings,
text titles/legend entries, colorbar and opaque background. The saved effective
rendering configuration is used. Changes to source/bindings/configuration invalidate
and diagnose before silently reusing an old static preparation. Original PNG,
PlotSpecs and scientific content are unchanged by navigation/Exit. No Viewer
Document, published Dataset or module enable is created by ordinary preview.

Limitations: Native3D axis ticks/grid, boxed legend placement, annotations/typography,
marker shapes and renderer-specific framing differ from Octave. Log/reversed axes
need a calibrated CORE coordinate/axis-mapping API; transparency needs an alpha
background API. Unsupported properties/budgets diagnose while retaining static.
Other providers/base graphs/rendered-only clones need a public exact prepared-scene
contract. Numerical XYZ currently requires unfiltered/separate-off selection;
filtered XYZ remains a documented extension. Intake: 128 MiB MAT, 16 series,
200000 points/400000 cells; numerical scatter first 100000 rows, 2048/chunk,
12000 finite original points. Non-Debian transports require matching compilation.

Focused actual Tk/Xorg GUI on DISPLAY :1, isolated copies of installed catalog Sessions:
- Thermal Surface: surface3d-example, existing XYZ Variant p0001; 1681 points,
  3200 cells. Original static, Z scale/colors, original camera/projection, all four
  arrows, exact reset, unchanged Exit, retained tabs/warm return PASS.
- Ticino Valley: demo_geospatial_ticino_valley_3d_2.0.0, existing p0001; 5440 points,
  10586 cells. Terrain/aspect, km/m graph labels, colors/camera, arrows/reset/Exit
  and retained tabs PASS. Undeclared canonical schema units remain undeclared;
  rendered graph labels are preserved rather than inventing source calibration.
- Numerical XYZ: thermal canonical IDs v0001/v0002/v0003 and explicit 250000-row
  private test fixture x/y/z; 1681 and 11112 points respectively. 100000-row scan,
  stride 9 in the large case, units/source rows, no topology, retained 2D, tab cache,
  zero publication/Viewer Documents/Analysis enable and byte preservation PASS.
- Existing crystal073/molecule071/mesh071 previews: actual prior scientific fixture
  Session, rendering, original navigation/cube, orbit/zoom, tab camera/cache and
  owned cleanup PASS. No source bytes or document/catalog identities changed.
- API/lifecycle supplement: real export cancellation and process-group reap,
  readonly mutation rejection/renderer failure, graph and Dataset revision guards,
  destroyed embedded container and Session invalidation PASS; originals preserved.

Independent VTP/scientific check: coordinates match the original prepared MAT arrays
with maximum error 0; scalar values/ranges and exact per-point colormap RGB mapping
PASS. Camera/original view/effective aspect/projection are captured in presentation
receipts. Reset also reproduces the initial Native3D PNG SHA byte for byte.

Measured final runs (driver sleeps included in first/tab totals): Thermal first
~1.43 s, Ticino first ~1.91 s; warm tab returns ~0.43 / 0.46 s. Native camera round
trips ~28–65 ms. Numerical first ~0.65 s / 2.36 s (250000 rows), native rotations
~52–61 ms. Unchanged returns retain worker PID, scene/camera, image and PNG mtime,
with no geometry regeneration or PNG write. Watches use cheap source/config/resource
stamps rather than repeating scientific payload hashes. Real resizing may rebuild
presentation at the new viewport size. Exit retains a ready scene; explicit source
change, failure, owner destruction and release clean it up. No renderer/IPC rewrite.
Earlier incomplete GUI driver/fixture runs are retained outside the final PASS matrix;
range bounds, control overlap, return-code handling and sphere tessellation were
corrected, and the unnecessary static 2D render removed from XYZ activation.

Documentation and unfinished-only TODO updated; prior pending manual acceptance
items remain. Delivery: new framework archive/expanded/active/restore parity and
SHA-256; new Plot Dataset 3.13.1 ZIP/expanded pair. Session Generator pairs and all
previous archives remain unchanged. Complete former active dev086 is retained as
`_backup_active_dev086_for_dev087_native3d`. Final archive SHA is in its sidecar and
workspace versioned handoff, avoiding a self-referential archive hash.

Modified implementation/module files:
- `app/gui/dataset_preview_sync.tcl`
- `app/gui/graphs_page.tcl`
- `core/native3d/bin/libgx3de_viewer_tcl.so`
- `core/native3d/gx3de_viewer_tcl.cpp`
- `core/native3d/renderer_worker.tcl`
- `core/python/native3d_plot_preview.py`
- `core/tcl/dataset_viewer_api_v1.tcl`
- `core/tcl/graph_selection_gui_v1.tcl`
- `core/tcl/mesh_dataset_viewer_v1.tcl`
- `core/tcl/native3d_compact_preview_v1.tcl`
- `core/tcl/native3d_gui_host_v1.tcl`
- `core/tcl/native3d_plot_prepare_worker.tcl`
- `core/tcl/scientific_dataset_preview_v1.tcl`
- `plugins/modules/plot.dataset/CHANGELOG.md`
- `plugins/modules/plot.dataset/GUI_MANUAL.md`
- `plugins/modules/plot.dataset/PLOT_DATASET_3D_API_v1.md`
- `plugins/modules/plot.dataset/PLOT_DATASET_API_v3.md`
- `plugins/modules/plot.dataset/api/plot_dataset_3d_api_v1.tcl`
- `plugins/modules/plot.dataset/api/plot_dataset_api_v3.tcl`
- `plugins/modules/plot.dataset/module.ini`
- `plugins/modules/plot.dataset/plugin-package.ini`
- `plugins/modules/plot.dataset/runtime/pd_preview_export.m`
- `plugins/modules/plot.dataset/runtime/pd_render_3d.m`
- `plugins/modules/plot.dataset/runtime/pd_scene_write_vtp.m`
- `plugins/modules/plot.dataset/runtime/plot_dataset_preview_export.m`
