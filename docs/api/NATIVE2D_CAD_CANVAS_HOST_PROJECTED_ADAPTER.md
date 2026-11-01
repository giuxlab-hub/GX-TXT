# Projected CAD Canvas Host adapter (P021)

SPDX-License-Identifier: GPL-3.0-or-later

This is an additive host capability in `NATIVE2D_API_v1` and
`NATIVE2D_CAD_CANVAS_HOST_v1`. It does not replace either scientific engine or
introduce another CAD controller. Existing planar consumers do not opt in and
retain their existing behavior.

## Attachment and ownership

```tcl
set host [::GX::native2DCadCanvasAttach $existingNative3DCanvas $native2DScene \
    {bind_events 0 external_render 0 callbacks {navigation MyNavigation}}]
set projected [::GX::native2DCadProjectionAttach $host $publicNative3DMapper \
    {chrome_raise_command RaiseExistingNavigationChrome}]
$host refresh final
```

The Canvas is the **existing Native3D Canvas**, not a transparent second widget.
The consumer owns the scene, native camera, working plane, Native3D worker,
Document and History. The Host adopts its existing Native2D CAD context and
selection. The projection adapter owns only presentation resources and local
presentation caches. Destroying it or the Host never destroys scientific objects.
The consumer routes actual Canvas-pixel input through `$host event`; it retains
priority for Native3D navigation and Navigation Cube input.

The mapper is the public, immutable Native3D projection command supplied by the
viewport owner. Its `map to_screen|to_plane ROWS`, `scale`, and `info` operations
use authoritative native camera snapshots and normalized working-plane state.
No camera mathematics or raw native addresses enter a Viewer script.

`$projected configure {mapping NEW_MAPPER}` replaces an immutable camera/plane
snapshot, invalidates presentation, and cancels a live pointer manipulation before
it can cross camera generations. Staged construction points remain scientific
plane points and survive an ordinary camera change. The consumer pins active
pointer gestures against camera replacement. It must supply a fresh mapper on
resize and camera changes, and call `$host refresh navigation` afterwards.

`$projected info` reports readiness, rejection reason, mapper metadata, cache
count and the overlay-depth policy. `dispose` releases only presentation resources.
An expired mapper, edge-on plane, invalid ray, behind-camera point or a viewport
crossing the plane's perspective horizon is rejected explicitly. The Native3D
frame remains intact; no fabricated planar coordinates are used.

## Coordinate and interaction helpers

All Host input remains actual Canvas pixels. Additive public Host helpers are:

- `world XY`: actual screen point to scientific local plane point.
- `device LOCAL_XY`: scientific local plane point to actual screen point.
- `nativeDevice XY`: actual point to the existing Native2D virtual device frame.
- `projectNativePoint XY`: native presentation device point to actual Canvas.
- `inside XY`, `interactionSnap XY EXCLUDED OBJECT_SNAP`, and
  `constructionPick XY PLACEMENTS EXCLUDED`.
- `pointerActive`: active pointer/annotation/direction operation; this differs
  from a staged, unfinished construction.

The existing native begin/plan/apply/commit/cancel controller receives the mapped
Native2D device points. Native definitions, constraints, selection membership,
epoch-checked references, grid snapping and rollback stay authoritative.
Rectangle selection unprojects all four screen corners into the exact local
polygon; it does not replace an inclined rectangle with an axis-aligned local box.

The retained Cairo sprite service supplies actual projected graphical hit regions.
Defining-control glyphs reference `interaction_controls`, not rendering samples.
Straight Path and spline segment hits use native `interaction_reference` and
`interaction_render`. For complex constituents without a public
`part_id`-to-segment-reference query, a graphical object hit is resolved through
native selection scoped to that object. The adapter does not recreate the private
native topology index convention. At overlapping constituents this fallback uses
the existing native planar tie-breaking; it is not a new projected topology solver.

Native snapping proposes exact points; screen-space distance admits only proposals
within the visible 9/10-pixel tolerance. The bounded native candidate-search radius
is 256 virtual pixels. Very extreme perspective compression can therefore omit a
valid candidate; it never moves to an out-of-tolerance candidate. Moderate inclined
planes are the supported validation range. Scientific grid snapping itself remains
unchanged.

## Presentation and quality

The same Canvas contains the Native3D image, one retained transparent Cairo sprite
item, and bounded text/editor overlays. It contains no opaque CAD background and
no additional Canvas. Authored grid/geometry RGBA colors pass through the existing
public UI Field descriptor to the additive retained-sprite color parser; Cairo
blends them over the actual underlying 3D pixels. Grid, geometry, defining controls, exact segment highlights,
direction glyphs and gizmos are retained sprites. Constraint/dimension text and
inline editors use existing CORE presentation. No complete Native3D scene is
rebuilt after an edit. CAD overlays deliberately draw **always on top** of solids;
they are editing annotations, not depth-tested scientific solids.

The native C renderer remains the sole retained-curve tessellator. The public
mapper provides a conservative projective Jacobian bound over the visible convex
plane quadrilateral extended by eight screen pixels. This includes the local-error
neighborhood of visible curve fragments; a near-horizon expanded domain is rejected. During synchronous native sampling only, the adapter sets a
virtual pixel scale at least that bound, converts the resulting native points back
to local coordinates and restores the original native view in `finally`. No GUI
callback or event-loop entry occurs inside this scope. This preserves the native
0.35-pixel tessellation tolerance over the visible domain rather than reducing
sampling quality for speed. The bound does not claim validity over all invisible parts of the quadrilateral's
axis-aligned bounding box. Uniform native local tessellation error is converted
using the expanded-domain bound, not an assumed constant perspective scale. Native budget/capacity
limits remain unchanged.

Local sampled geometry is reused while only selection, navigation scheduling or
annotation previews change; native geometry/solver edits invalidate it. A camera
change invalidates tessellation because pixel accuracy changes. Full Document
reads, native worker RPC and derived 3D-scene synchronization are absent from this
adapter's pointer path.

Grid generation and optional 16-pixel density suppression remain the existing
native CORE policy applied to the planar virtual view. It is presentation-only;
snap spacing is never changed. Under perspective the visible spacing naturally
varies across the plane. Scientific graduation values and units come from
`native2DAxisPlans` and `native2DAxisPresentation`; the adapter projects their
positions without changing their numbers. Labels remain upright and use the
public readable-text color policy against the configured viewport background.

The Host's `presentation` callback is called once after the virtual view is ready.
It may return `{plans {x PLAN y PLAN}}`; absent plans use the public native planner.
`chrome_raise_command`, if supplied, runs after ordinary Host overlays so the
existing Native3D Navigation Cube can retain its intended priority.

## Navigation callback

The projected Host does not own camera logic. Existing `navigation` callbacks
receive `operation pan` with actual `dx`, `dy`, `device`; `operation zoom` with
`factor`, `delta`, `device`; or `operation fit` with scientific `local_bounds`.
The consumer routes these through the Native3D public navigation/plane-fit owner.
No planar camera change is silently substituted for actual 3D navigation.
