# Native3D GUI Host: bounded planar projection (DEV111-P021)

SPDX-License-Identifier: GPL-3.0-or-later

This additive CORE adapter supports Native2D CAD interaction in an existing
Native3D viewport. It does not change the Native3D C API/ABI, camera, renderer,
picking, Navigation Cube or scientific geometry authority. Native3D owns the
camera and viewport; Native2D owns planar scientific geometry and constraints.
The GUI Host owns frame display, input priorities, frame admission and lifecycle.

## Opt-in native worker receipt

The existing renderer worker admits the finite `projection` command:

```tcl
projection enable 1
projection disable
projection snapshot
projection fit_plane $normalizedPlane {xmin ymin xmax ymax} $png
```

`enable 1` can precede the first render. It returns `enabled 1 ready 0` without
creating a scene. Enabling after a render also returns `projection_snapshot`.
The default is disabled. An ordinary nonparticipating consumer receives its
original replies and performs no additional projection sampling.

While enabled, viewport frame replies include `projection_snapshot` after the
native frame operation has completed. This applies to render, camera, viewport
resize, navigation, native presets, focus, Navigation Cube clicks, presentation,
scientific-axes changes and supported gizmo/plane/timeline frames. A pick includes
a snapshot only when its PNG argument is supplied. Separate export/timeline
capture targets are deliberately not treated as current editing viewport frames.
An unavailable snapshot is reported as `projection_error`; it does not turn a
successfully completed legacy render into an error.

A receipt contains schema `gxtxt.native3d.projection.v1`, an opaque printable
ASCII `frame_id`, monotonic per-adapter `revision`, physical `width`/`height`,
logical dimensions/device pixel ratios, `orthographic`, native camera origin,
actual orthographic height, near/far distances, six native unprojection basis
samples and, where available, the native-normalized `working_plane` and public
`navigation_cube` specification. A frame ID identifies a worker/process lifetime
and revision; it is not a pointer, persistent scientific identity or durable
Document revision. A host must retain the receipt with the exact admitted PNG,
not pair a new camera receipt with an older displayed frame.

The worker samples the existing public
`gx3de_viewport_screen_to_world` at positive forward depths 1 and 2. Sampled
viewport positions include both axes and the native scientific-figure margins.
The half-pixel convention, perspective/orthographic behavior, camera orientation,
FOV and aspect are inherited from that native authority. Depth is distance along
the camera forward direction, not normalized device depth. Screen coordinates
are physical viewport-local pixels with top-left origin.

The native `projection world_to_screen $xyzRows` and
`projection screen_to_world $xyDepthRows` operations provide bounded direct
public-C-API queries for qualification or infrequent explicit queries. They are
not required on pointer motion. Each accepts at most 262144 rows and returns
per-row `valid`, native `point` or native result `reason`.

## GUI-side bounded mapper

The mapper is a small C++17 Tcl module linked only to Tcl and standard libraries.
It does not load VTK, the Native3D engine, worker objects or native scene handles
into the GUI process:

```tcl
load $framework/core/native3d/bin/gx3de_projection_tcl_v1.so Gx3deprojection
set map [::GX3DEProjection::create $snapshot $normalizedPlane]
set pin [dict create frame_id [dict get $snapshot frame_id] \
                    revision [dict get $snapshot revision] \
                    width [dict get $snapshot width] height [dict get $snapshot height]]
set drawing [$map map to_screen {{0 0} {1 2}} $pin]
set pointer [$map map to_plane {{320 240}} $pin]
set scale [$map scale {0 0 639 479} $pin]
$map dispose
```

The normalized plane is a dictionary with three-element numeric lists:
`origin`, `normal`, `u_axis`, `v_axis`. Obtain it from the public native plane
owner. Axes must be unit-length, orthogonal and right-handed. The mapper rejects
malformed or inconsistent frames rather than silently renormalizing science.
Its algebra evaluates the native sampled basis and a ray/plane intersection;
it does not independently implement camera, FOV or figure-layout formulas.

Methods:

| Method | Result and responsibility |
|---|---|
| `info` | Frame identity/dimensions, orthographic state and normalized plane. |
| `map to_screen rows ?expectedFrame?` | Plane-local XY to physical pixels. |
| `map to_plane rows ?expectedFrame?` | Physical pixels to plane-local XY. |
| `scale ?screenRectangle? ?expectedFrame?` | Conservative visible-plane derivative bound. |
| `dispose` | Releases the command and its retained bounded snapshot. |

`map` accepts at most 262144 finite XY rows per call. It returns aligned `points`,
`valid`, `depth`, `reason` and `outside` lists plus the frame identity/dimensions.
Invalid points have an empty point list, not fabricated coordinates. Reasons
include `behind_camera`, `edge_on` and `range`. Outside-viewport points can remain
geometrically valid, with `outside 1`. The mapper deliberately does not duplicate
native clipping or picking. An unknown optional guard key is rejected; supported
guards are `frame_id`, `revision`, `width`, `height`. A mismatch raises
`GX NATIVE3D STALE_PROJECTION`. Safe Tcl interpreters cannot load this trusted
CORE host facility.

A map is immutable. The GUI Host disposes/replaces it when admitting a different
camera/plane/size/frame; it rejects or cancels active input when its scientific
frame generation cannot be preserved. Merely evaluating an old map cannot
itself know that its host has admitted another frame. The expected-frame guard
must therefore be supplied by that authoritative host, never by untrusted user
input. No asynchronous worker response may reinterpret an active gesture.

`scale` returns `valid`, `reason`, `maximum_pixels_per_unit`,
`minimum_forward_depth`, `local_polygon`, `local_bounds` and
`domain visible_convex_plane_quad`. The default screen rectangle is
`{0 0 width-1 height-1}`. Its bound follows from the projective Jacobian's affine
numerator corner maxima and minimum positive depth denominator. The bound holds
throughout the returned convex visible-plane quadrilateral. **It is not a bound
for the additional corners of its enclosing local AABB outside that quad.**
A rectangle crossing the plane horizon, an edge-on plane or unavailable forward
intersection returns `valid 0`; callers must not claim complete visibility or
invent a density. The shared presentation owner controls its bounded fallback
or diagnostic. This query supports conservative Native2D tessellation without
moving the scientific geometry authority out of Native2D.

## Fit and orthographic camera state

`fit_plane` accepts finite ordered local bounds, including point, horizontal and
vertical extents. It creates one temporary native plane and a four-vertex bounds
object through existing public APIs, delegates to native `FIT_OBJECT`, then
retires the object and plane before rendering the original scene. No Sketch
geometry is mirrored into Native3D. For orthographic views a bounded temporary
native view obtains the existing native fitted height; it too is retired before
render. Failures restore the preceding camera and height. The reply reports
`temporary_extent_vertices 4`, `retained_extent_objects 0`, the fitted camera,
`orthographic_height` and matching projection snapshot.

The existing camera request accepts optional positive `orthographic_height`;
original seven-field camera requests remain admitted. Source render descriptors
also accept the field. A host retaining a fitted camera must retain this native
height across frame updates and reopen. In opt-in orthographic navigation only,
zoom delegates to existing `gx3de_view_camera_zoom` so an explicitly retained
height remains responsive. Non-opt-in navigation retains its established path.

## Navigation Cube and layering

The receipt exposes only native public cube state: `visible`, `corner`,
`size_pixels`, `margin_pixels`. Corners are TL=0, TR=1, BL=2, BR=3. The existing
native renderer/picker layout reserves the top-left-origin physical rectangle:

```text
size = min(size_pixels, width-2*margin_pixels, height-2*margin_pixels)
left = (corner & 1) ? width-margin_pixels-size : margin_pixels
top  = (corner & 2) ? height-margin_pixels-size : margin_pixels
[left, top, left+size, top+size)
```

This is a chrome-layout contract, not a replacement hit-test algorithm. Native
cube pick/click remains authoritative. A shared Host must reserve cube input
and preserve its native pixels above CAD overlays. The protected renderer and
native cube implementation are unchanged.

## Build and qualification

CMake adds `gx3de_projection_tcl_v1` beside the existing Tcl viewer adapter;
installation places it in `core/native3d/bin`. No engine target or ABI changes.
The focused `validation/dev111_p021_projection` catalog documents isolated
component builds and native-golden tests. These tests complement actual
single-viewport GUI tests; they do not constitute user GUI acceptance.
