# Native 3D Field and Animation API v1

This additive API group extends the public C engine ABI. Include
`native_3d_field_api_v1.h` and `native_3d_animation_api_v1.h`. All handles are
opaque and all data structures use fixed-width fields and `struct_size`. Query
`gx3de_get_capabilities(GX3DE_API_GROUP_FIELD, ...)` or
`gx3de_get_capabilities(GX3DE_API_GROUP_ANIMATION, ...)` before use. Both groups
report version 1. No VTK, OpenGL, X11, Tk, STL, or Windows handle crosses the
public interface.

## Field lines and scalar slices

`gx3de_field_lines_create` accepts a structured VTI or in-memory image object,
the index of a point-associated three-component vector array, and optional
point scalar array. Seeds can be an explicit list, an arithmetic line, or an
arithmetic plane in source-local coordinates. The caller specifies forward,
backward, or bidirectional integration, local distance step, low-vector cutoff,
step limit, output-point limit, and temporary memory limit. The implementation
uses trilinear spatial interpolation in the image's oriented grid and
fourth-order Runge–Kutta integration of the *normalized* vector direction.
It stops at the grid boundary or low magnitude; it does not extrapolate.
`gx3de_field_line_info` reports requested seeds, created polylines, points,
and each stop reason. Budgets and invalid input reject the entire result.

The result is an ordinary immutable scientific polyline object. Optional
scalar values are sampled along it and selected for renderer coloring.
`tube_radius > 0` enables the ordinary scientific tube presentation. The
result is parented to its source image, so source and ancestor transforms move
the derived geometry together. Source deletion rebases the child into world
space through the engine's existing hierarchy behavior. Recreate field lines
when vector values or seeds change; source scientific arrays are immutable.
The source object must belong to the supplied scene; wrong ownership returns
`GX3DE_WRONG_OWNER`.

`gx3de_field_slice_create` samples a user-defined rectangular plane in source
local coordinates. Every requested sample must lie within the oriented grid;
an out-of-domain plane returns `GX3DE_RANGE` without publishing geometry. The
returned triangle surface contains the sampled point scalar array and is
parented to the source image. It can be colored, clipped, picked, transformed,
and rendered through the existing engine API.

`gx3de_field_volume_style_set/get` configures the source image itself for VTK
volume ray casting. It accepts up to 16 strictly ordered scalar-to-RGBA
transfer points, a positive ray sample distance, and a point scalar array.
Volume presentation is independent of the immutable scalar array. The
renderer applies object transform, opacity, view clipping, lighting, and
requested-resolution capture. The active OpenGL backend and device limits
control practical volume size; the setter rejects images over four million
points, while normal render resource limits still apply.

## Time-dependent pathlines

`gx3de_field_pathlines_create` integrates `dx/dt = v(x,t)` through two or more
strictly ordered compatible structured or unstructured vector-field samples.
Supply borrowed objects in `frames[]`, a lazy `gx3de_field_frame_loader`, or a
mixture. A loader returns a new source object owned by the pathline call; it is
destroyed after its arrays are copied. At most two grids are resident during
integration. Structured grids must share extent, origin, spacing and direction;
unstructured grids must share cell types, point coordinates and connectivity.
All samples must share their local-to-world transform. Point-vector arrays are linearly interpolated
between sample times, then integrated using fourth-order Runge–Kutta with a
caller-specified maximum time step. Seed points are local coordinates at the
first sample time. A low-velocity cutoff, per-seed step limit, total point
limit, and temporary memory limit bound the operation. Boundary, low-magnitude,
step-limit, and lazy-load counts are queryable.

The result is an ordinary scientific polyline object with `time_value` at
each point and, when requested, `field_scalar`. It snapshots the first source
world transform because lazy sample objects may be destroyed immediately.
The time/value arrays and point coordinates are queryable through the existing
scientific API. Pathlines are generated synchronously; a loader can implement
its own cancellation check before or during source preparation. Native line,
slice and pathline loops check a timeline cancellation token between bounded
steps; a synchronous loader can call `gx3de_animation_cancel_requested`.

## Animation timeline

`gx3de_animation_create` creates one timeline attached to one scene with UTF-8
time-unit metadata. Add frames in strictly increasing time order. A frame may
refer to an existing borrowed object or provide a callback that lazily creates
a new scientific or mesh object in that same scene. The timeline owns only
callback-created objects. The timeline remains a stable logical animation
handle while its displayed source object can change. External objects and
keyed objects must remain alive until the timeline is destroyed.
`gx3de_animation_active_object_get` returns a borrowed active source for
scientific queries and provenance checks; do not retain it across a seek.

`seek_frame` and `seek_time` update scientific time deterministically and
return only after the chosen source and keyed state have been applied. The
source sample is selected by nearest frame, breaking ties toward the earlier
frame. No interpolation of discrete topology, point arrays, scalar arrays,
vector arrays, radii, or source object identity is implied. A caller can add
multiple transform/visibility/opacity tracks through `object_key_set` and an
optional camera track through `camera_key_set`. Linear track mode interpolates
translation and opacity only when adjacent local transform rotation/scale
parts match. Visibility and camera keys remain discrete. A conflicting
rotation/scale pair returns `GX3DE_UNSUPPORTED` before committing the seek.

`play`, `pause`, `stop`, `step`, and `advance(elapsed_seconds)` support once,
loop, and ping-pong modes and positive playback rates. `advance` uses caller
elapsed time; headless frame rendering never depends on wall-clock timing.
`render_frame_rgba`, `render_frame_png`, and `write_png_sequence` use the normal
view renderer at an explicit width and height. A sequence writes names of the
form `prefix000000.png`. The caller owns the output path and may use the
ordinary PNG/image API as a later video encoder input.

Objects and views supplied to a timeline must belong to its scene; the API
returns `GX3DE_WRONG_OWNER` before changing either scene. A callback that
returns a foreign-scene object is rejected, with ownership left to the caller.

Lazy frame cache size defaults to two objects and 256 MiB estimated CPU data.
`set_resident_limit` and `set_memory_limit` adjust these caps; eviction is LRU
and never removes the currently displayed object. Estimates count point,
array, cell, vertex, and triangle payloads, while the renderer separately
enforces display budgets. An oversize lazy result returns `GX3DE_RANGE` and
is destroyed without changing the active time. Loader failures and rejected
interpolation roll back active state. `cancel` is checked before and after a
blocking loader, between sequence frames and during native field integration.
An externally supplied blocking loader must poll the cancellation query itself;
uninterruptible VTK reader calls remain bounded by the worker process. Scene teardown
automatically destroys remaining timelines before views and objects; normal
callers should destroy timelines explicitly when finished.

## Current boundaries

- Field-line and pathline integration support structured image grids and
  tetrahedral/hexahedral unstructured cells, including imported VTU and
  in-memory datasets. `gx3de_field_source_info_get` reports supported and
  unsupported cell counts. Scalar slices and volume presentation remain
  image-grid operations.
- `gx3de_animation_time_add` creates a sample without requiring a primary
  source object. `gx3de_animation_layer_create` gives each independent track a
  stable UTF-8 logical ID. `gx3de_animation_layer_frame_set` supplies a borrowed
  object or lazy loader per time sample; active objects are queryable by layer.
  `gx3de_animation_layer_bind_lines`, `_bind_slice`, `_bind_isosurface` and
  `_bind_pathlines` regenerate derived presentation when the source track
  changes. Pathline frame zero has no line; frame i contains samples 0 through i.
  `gx3de_animation_playback_range_set/get` constrain stop, step, and advance.
  Source and derived frames share resident-object and estimated CPU-byte budgets.
  A consumer persists logical IDs, source paths/fingerprints, frame times and
  definitions in Session metadata; this API does not duplicate bulk arrays.
- Lazy frame callbacks run synchronously on the calling thread. They are
  suitable for a worker process or external job. Renderer GPU memory is
  bounded by renderer limits rather than the timeline CPU-byte estimate.
- The PNG sequence operation stops on the first failure and leaves any earlier
  completed images in the caller's output directory. Callers needing an
  all-or-nothing movie package should stage and rename the output directory.
