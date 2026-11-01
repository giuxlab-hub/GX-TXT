# Integrated scientific foundations — dev088

Use **viewer.engine_3d**, backed by modern CORE **libgx3de**. The separate
`viewer.native_3d` / `gx3d_native_host` / `NATIVE_3D_VIEWER_API_v1` provider is
**Legacy / Deprecated**, retained unchanged for compatibility. Do not use it for
new work. CORE files named `native3d` are modern and are not deprecated.

## Owners and semantics

Native3D owns geometry, planes, intersections, projection and renderer cameras.
Native2D owns retained paths/curves, raster calibration and editing. The modern
Viewer hosts these operations; Curve Workbench remains the editor. Interactive
Documents/Resources own persistence. Unit Registry, Dataset Publication, Geometry
Exchange, Scientific Multiview and the existing Installation Identity/Object
Origin authorities are reused. There is no second renderer or geometry engine.

A section intersects the complete mesh or supported B-Rep with a physical plane.
Mesh contours are piecewise linear, with the declared join tolerance; CAD section
profiles are sampled representations, not an exact analytical curve publication.
Disconnected contours and open/closed state are retained. No repair is implicit.
A projection orthogonally flattens all source points onto a plane, retaining
scientific arrays in lossless VTP. Editable projections follow actual mesh boundary
loops. This is **not** a silhouette or a visible-surface reconstruction. Closed
solids have a full projected surface but no editable boundary under this policy.
Overlaps remain distinct, cells may become degenerate, and depth is discarded.

Accept creates a new curve on the recorded plane. It never deforms the source
mesh or guesses depth. Retained straight paths preserve every vertex; other edited
Native2D curves use 257 display samples and are explicitly approximate. No automatic
extrusion/sweep reconstruction is claimed by this GUI acceptance operation.

## Installed GUI

1. Open a copy of `GXTXT_DEMO_dev088` as a normal GX-TXT Session.
2. Open **Native 3D Engine Viewer** (`viewer.engine_3d`) from Viewers.
3. Click **Working plane / Curve Workbench…** at the top of the Viewer controls.
4. Choose a saved workflow. `idoc_0002` is Bunny; `idoc_0005` is Ticino.
5. Use **Source**, **Plane + results**, **Section**, **Projection**, **Plane-normal
   view**, and **Accepted result**. These render the actual saved geometry.
6. Click **Edit section in Curve Workbench** or **Edit projection in Curve Workbench**.
7. Toggle **Show 3D Reference Image** and adjust its independent 0–100% opacity.
   Geometry and raster share the calibrated physical coordinate system. Pan, zoom
   and resize use the existing Native2D Viewport Host.
8. Select a defining handle and drag it; use Undo and Redo. Dense mesh contours
   retain many handles: zoom in to distinguish neighboring vertices.
9. **Accept → 3D** creates a separate magenta derived curve. **Cancel 3D Edit**
   leaves the source scientific Document and its revision unchanged. Workbench
   drafts are separate workspace state; use **Save workspace** to retain a draft.
10. Save the Session configuration and reopen. Saved workflows reconstruct from
    resource hashes, plane descriptors and definitions, never old worker tokens.

For a new workflow, add a complete VTP/STL/OBJ source artifact to the modern Viewer,
select its layer, set the Viewer's plane origin/normal/U fields, then enter the
actual source coordinate unit and positive join tolerance in the workflow dialog.
The declared units must describe the source; the dialog does not infer scale.
STEP workflows require the public Tcl entry point with an explicit tessellation
policy for the projected/reference representation; supported B-Rep sections use
CORE OCCT. Multi-occurrence STEP import retains the pre-existing explicit intake
limitations. Native3D's normal camera and working-plane controls remain available.

## Scientific calibration

The plane uses origin O, unit normal N, normalized perpendicular U and V=N×U.
World = O + uU + vV + wN. Orthogonal projection sets w=0. Plane coordinates use
one declared length unit. `plane_frame` returns the normalized reconstructible
basis; degenerate/parallel input axes are rejected.

The source-only reference is rendered from the positive normal side, with camera
up=V, explicit orthographic physical height, aspect-correct width, clipping covering
source bounds, and explicit raster dimensions. No navigation cube or decorative
plane is baked into the reference. Its metadata records source SHA, plane, units,
camera, width/height, scale and translation. Native2D raster coordinates use
**bottom-left pixel edges**: XY=translation+scale×pixel. Top-left Native3D screen
coordinates are pixel centers; convert with x_edge=x_screen+0.5 and
v_edge=height-y_screen-0.5. World depth is needed for a full screen inverse; a
single projection has no unique 3D inverse.

## Data and reproduction

Bunny uses the actual Stanford ZIPPER scan: 35,947 points and 69,451 triangles,
including its original holes. Original scanner units are undeclared in the source;
the DEMO explicitly prescribes a **150 mm model height**, using CORE scale. This is
a modeled representation of real scan geometry, not a scanner measurement claim.
Ticino uses the preserved dev087 real terrain/population-density geometry: 5,440
points, 10,586 triangles. Explicit source graph axis declarations km/km/m are
converted by CORE to m/m/m, preserving scalar and flat-cell RGB arrays. Original
Sessions are not edited. Source identities and normalization resources are retained.

Stanford source and attribution: https://graphics.stanford.edu/data/3Dscanrep/ .
The original archive is https://graphics.stanford.edu/pub/3Dscanrep/bunny.tar.gz .
Keep its research/free-redistribution terms with the DEMO; third-party scan data
are not relicensed as framework GPL source.

The release's `validation/astra_dev088/` scripts and `SCRIPT_CATALOG.md` provide
exact commands, arguments and side effects. `demo.tcl` builds the Session from
original-coordinate Bunny VTP and the supplied Ticino VTP through public APIs.
`reopen.tcl` uses a copied Session in a clean process. Numerical checks independently
verify plane residuals, distance to source surfaces, full projection/arrays and
Native2D calibration. Actual E01–E13 PNGs accompany the Session and release report.

## Limits

Linux/X11 software rendering is the tested transport. Other platforms need a
matching native build. Raster axes are linear with known scale; pose/depth are not
inferred. Boundary projection is not visibility analysis. Self-intersecting sweeps
are not repaired. Geometry Exchange transport is bounded and same-Session; it
serializes a saved snapshot through resources, rather than incremental native
streaming. Document payloads remain limited to 32 MiB. Working-plane profile limits
are 4,096 contours and 1,000,000 total points; raster dimensions 16–4,096 per side.
Full CAD editing, automatic reverse deformation and unbounded streaming are outside
this delivered workflow. Manual acceptance remains pending.
