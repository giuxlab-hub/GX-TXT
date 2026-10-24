# NATIVE2D_SPRITE_SCENE_API_v1

Public, optional GUI-host API, version1. Implemented by the existing Native2D
`gx2dtcl.so` target in C++17/Cairo. Discover with
`::GX::native2DSpriteSceneApiInfo` or the existing CORE API discovery map.
No Script Bridge/restricted SDK permission is implied. Requires an existing Tk
Canvas; does not create a Viewer or scientific scene. Calls run on its Tk thread.

## Operations (namespace `::GX`)

```
native2DSpriteSceneCreate canvas                         -> native object command
native2DSpriteSceneBatch canvas updates
native2DSpriteSceneBegin canvas ?clipRectangle?
native2DSpriteSceneAppend canvas id geometry ?anchors?
native2DSpriteSceneObject canvas id objectSnapshot background
native2DSpriteSceneControls canvas scientificScene object selected color id
native2DSpriteSceneEnd canvas
native2DSpriteSceneDescribe canvas ?id?                  -> dictionary
native2DSpriteSceneAnchor canvas id name                 -> {position XY direction XY}
native2DSpriteSceneHit canvas position ?tolerancePixels?  -> IDs, topmost first
native2DSpriteSceneRemove canvas ids
native2DSpriteSceneDispose canvas
```

`Create` is idempotent per Canvas. Its native object command supports `batch`,
`begin ?clip?`, `end`, `describe ?id?`, `anchor id name`, `hit XY ?tolerance?`,
`remove ids`, `destroy`. Dispose also releases the host adapter record. Prefer
public host operations over deleting a native command behind its adapter.

## Retained sprite data and transformations

`updates` is a list of dictionaries with mandatory nonempty stable `id` (1..256
bytes), and any of:

- `geometry`: list of primitive dictionaries. `kind` is `line`, `polygon`,
  `rectangle` or `ellipse`. `points` is a list of XY pairs; rectangles/ellipses
  use two opposite corners. Optional `stroke` (Tk color, empty disables), `fill`
  (empty/default disables), `width` (device pixels, default1), `dash` (positive
  pixel-length list, default solid). A line needs >=2points; polygon >=3.
- `position` XY translation (default0,0), `angle` degrees counterclockwise in
  presentation coordinates, `pivot` XY (default0,0), `scale` XY (default1,1).
- `visible` boolean(default1), `z` number(default0).
- `anchors`: dictionary name -> `{position XY direction XY}`. Direction defaults
  to1,0, must be nonzero; anchor positions/directions transform natively.

Unspecified fields retain their previous values. New IDs receive defaults. Native
combined transformation is `position + pivot + R(angle) * S * (point - pivot)`;
coordinate convention is that of the supplied presentation plane (Tk Y down).
Stroke widths/dashes remain device-pixel presentation sizes. Sprite transforms
are graphical operations: they never mutate a scientific object or Dataset.

Batch parsing/validation completes before model changes. Duplicate IDs, invalid
coordinates, singular scale, invalid colors/shapes reject the entire batch.
Limits:65536sprites,2million stored geometry points per scene,262144points per
sprite,1024anchors per sprite,16dash elements,32million raster pixels. Numeric
coordinates bounded by1e12; scale magnitudes must be>=1e-12. No allocation/pixel
capacity failure is silently treated as scientific success. Overlarge display
surfaces do not paint; callers must keep supported finite viewport sizes.

Equal Z preserves insertion order; Z changes invalidate intersecting presentation
regions. Hit uses the same transformed Cairo paths, stroke width and filled
regions; it is a geometric hit, including dashed path gaps within tolerance.
Hidden sprites and points outside an active clip are excluded. Bounds include
transformed geometry and a conservative stroke/antialias pad. Ellipse bounds use
analytic transformed extents; hit uses exact Cairo ellipse paths. Describe without
ID reports item/count/update/change/paint/raster-update counters; with ID it reports
identity, transform, Z, visibility, primitive count and transformed bounds.

## Frames, scientific adapters and stacking

An explicit Batch retains IDs until Remove/Dispose. Begin/End is an optional
frame reconciliation contract: Begin increments a presentation generation;
Append/Object/Controls gather one bounded host batch; End submits it and removes
sprites not touched in that generation. Do not interleave two frame producers on
one Canvas. Begin optionally sets `{left top right bottom}` clipping; omission
keeps its previous clip. End is required before leaving the frame. On a failed
frame, start a new Begin to discard the host's pending batch and rebuild from the
current authoritative model. Never treat an unpainted frame as a scientific edit.

Object consumes `native2DPresentationObjectSnapshot`, using its native projected
paths/style/part markers. Unit interpretation, scientific clipping/view sampling
and scientific marker geometry remain with the existing Native2D/public owners.
Controls queries existing native defining-control descriptors and world-to-device
conversion in one native adapter operation. Neither adapter invents control points
from spline display samples. Append can add presentation primitives/anchors to
that stable object ID without creating Tk widgets/items per primitive.

The single disabled-for-picking `gx2dsprites` Canvas item has the reserved
`native_sprite_scene` tag. It sits above the P014 grid item and below existing
Tk interaction overlays; do not delete or retag an owner's item. Whole-Canvas
replacement is recovered on the next public call. Independent scenes/Canvases do
not share sprite state. Z orders sprites within this native layer, not arbitrary
Tk overlay widgets. Scientific selection still uses the Native2D selection API,
not this presentation hit test; highlights/gizmos/constraint badges remain their
existing owners. Interactive transient overlays can intentionally remain Tk.

## Rendering, scheduling and lifecycle

C++ owns persistent Sprite geometry/style/transform/anchors and Scene resources.
Changed old/new bounds invalidate a retained transparent Cairo raster; only
intersecting sprites are recomposed in correct Z order. Tk's damage callback
composites that raster into its existing Canvas backing drawable, above the grid.
There is no periodic repaint or second event loop. Unchanged objects survive
frames. Batches coalesce within the normal Tk event loop; use the public
GUI_UPDATE_SCHEDULER_API_v1 for the Viewer-owned redraw callback, as Workbench
already does. The scheduler controls when; sprites control presentation resources.

Canvas destruction disposes its native command, raster, paths and host records.
Explicit Dispose removes only this owner's item; it does not destroy the Canvas,
scientific scene, grid, selection, Dataset or Session. Callback ownership remains
with the Viewer/scheduler. The C scientific engine, grid generation and snapping
sources are unchanged. No C++ worker receives raw Tk access through this API.

## Minimal independent example

```tcl
set box [dict create kind rectangle points {{0 0} {60 30}} fill #3366bb stroke black]
::GX::native2DSpriteSceneBatch .viewer.canvas [list [dict create id tool \
    geometry [list $box] position {100 90} \
    anchors {tip {position {60 15} direction {1 0}}}]]
# Native combined translation/rotation about the chosen local pivot.
::GX::native2DSpriteSceneBatch .viewer.canvas \
    {{id tool position {140 120} pivot {30 15} angle 90 scale {1 1}}}
set anchor [::GX::native2DSpriteSceneAnchor .viewer.canvas tool tip]
set hits [::GX::native2DSpriteSceneHit .viewer.canvas {170 140} 3]
```

Curve Workbench2.21.15 is the first production consumer. Other Viewers do not
adopt this layer automatically. For DEV112, retain these public contracts and the
matching source/header/CMake/bootstrap/adapter files plus compiled native target.


## P016: direct scientific scene synchronization

Additive operations, same API version; the manual Batch/Object/Controls interface
above remains available for consumers without a scientific scene.

```tcl
::GX::native2DSpriteSceneAttach canvas nativeScene
set receipt [::GX::native2DSpriteSceneSync canvas nativeScene descriptors ?options?]
::GX::native2DSpriteSceneDetach canvas
::GX::native2DSpriteSceneDiagnostics on|off|reset|get
```

Sync attaches automatically. Native scene/object IDs come from public Native2D
CORE, never raw pointers. Attach replaces a previous binding source and removes
its scientific sprites, preserving unrelated manual sprites. Detach does the same
without destroying the scientific scene or the retained presenter. Scene closure
revokes all native observers synchronously before C geometry is released. Canvas
closure releases observers, raster, sprites and the host command.

Each descriptor contains `id` (stable presentation identity) and `object` (native
scientific identity). Optional: `z` (default0), `visible` (default1), `style`
(overrides `color` RGBA and `line_width`), `sample_markers` (default1; use0 when
actual defining controls/rows have their own presentation), `controls` (default0),
`point_markers` (default0), `selected` defining/row indices, `table_selected`
explicit row indices, `skip_path` (default0, point-only display policy).
Controls are actual native descriptors, not display samples; point markers use
original C row indices. Bounds and marker anchors come from native projections.
Options: `budget` (default4096,6..65536), `background` (Tk color, default white),
`active` (optional descriptor ID for the small Flip-label receipt).

Receipt: `locators` maps IDs to `{originalRowIndex deviceXY}` for selected row
markers; optional `active_marker` contains `bounds` and composited `color` for the
active marker's existing host label. No full geometry or sampled arrays return
to Tcl. Curve Workbench submits one small descriptor per visible object and uses
`sample_markers 0`, preserving its defining-control policy.

Use Begin/Sync/End for reconciliation. A Sync touches only listed IDs; End retires
untouched sprites/bindings. Manual and scientific IDs must be disjoint. Remove a
native binding before using that ID in manual Batch. Presentational transforms on
manual sprites never mutate scientific objects; scientific transformations use
the native CAD/geometry APIs. Native-bound transforms are rebuilt from scientific
geometry, not independently moved by manual Batch.

C++ samples through existing `gx2d_curve_display`/`gx2d_object_display`, projects
actual defining controls and native direction markers, then updates retained
sprites directly. LOD/clipping, break handling and budgets remain unchanged.
Unchanged bindings skip sampling, Tcl parsing of geometry and geometry copying.
A view change reprojects natively; it does not request a Tcl snapshot.

Invalidation observes **exact** presentation-affecting C state (including defining
controls, tangents, path nodes/constituents, masks, marker state and layer style),
not just topology epochs or collision-prone hashes. Existing topology epochs are
intentionally preserved during some coordinate/drag/solver edits, so they cannot
serve as sufficient visual revision keys. `native_revision` is an observer-local
revision of encountered native state, not a journal/Document revision. Full exact
bytes are copied only on change; unchanged checks scan borrowed byte slices.
Viewport generation, small descriptor, budget and background are separate keys.
Deleting/replacing objects, Undo/Redo restoration, constraint-driven geometry,
source updates and Session/scene replacement cannot silently retain an old binding.

Describe adds `scientific_object/native_revision` per binding and aggregate
`native_bound_objects/native_syncs/native_cache_hits/native_cache_misses/`
`native_sampled_points/native_viewport_generation/native_observed_revisions`.
Diagnostics are disabled by default, interpreter-local and opt-in; native phase
counters report calls/us/points/bytes without periodic callbacks. No ownership
moves into GUI_UPDATE_SCHEDULER_API_v1: the scheduler still determines when the
Viewer callback runs, while scientific geometry and retained presentation determine
what to draw. Native grid/axes and Cairo rasterization are unchanged.

Errors propagate as Tcl errors, including stale scientific IDs, invalid metadata,
capacity and closed resources. Metadata identities are checked before per-object
sync. Sync is a presentation reconciliation, not an atomic scientific edit: a
later invalid row can fail after earlier valid rows updated. On failure, start a
fresh Begin with corrected descriptors and finish End. No scientific state has
been modified. Existing capacity limits apply; exact observation is bounded at
128MiB per object. Source scans remain linear in original geometry size; this
avoids instrumenting every scientific mutator and is a documented residual cost.

Native build integration: matching gx2dtcl C++17 target, managed source declarations
in gx2d_sprite_scene_v1.h, read-only C visitor in gx2d_presentation_visit_v1.h/.inc.
Borrowed C slices are valid only inside their callback; observers must not mutate
or reenter C. They are process-private revision observations, not a portable
serialization format. No C scientific algorithm, grid/snapping rule, public POD
layout or worker SDK permission is changed.
