# GX-TXT native 2D CORE

The shared host loader is `::GX::native2DEnsure`, backed by the installed
`core/native2d/bin/gx2dtcl` adapter. Curve Workbench and Curve Fit use this same
loader. The `GX2D_TCL_LIBRARY` host environment override permits controlled
builds and validation.

The native Plot v4 painter wraps an overflowing automatic inside-series legend
within its panel using Cairo glyph metrics. It keeps the complete source label,
declared font, series identity and scientific geometry. Short captions and
explicit manual anchors retain their previous primitives. If the wrapped legend
cannot fit vertically, the painter reports insufficient viewport space rather
than silently clipping its text. This policy is separate from the cell-field
scalar-range legend and does not alter scalar values or physical axis units.

`gx2d_curve_endpoint_frame` and `gx2d_curve_point_frame` return exact endpoint
coordinates and incident derivatives, including reversed traversal and native
Catmull–Rom interpolation. Derivatives use the incident source segment's local
parameter [0,1]; a disconnected incident edge or zero derivative is an explicit
error. They remain readable during a drag. Tcl exposes `endpoint_frame scene
curve end reverse spline` and `point_frame scene curve index incoming reverse
spline`. `gx2d_point_distance` / `distance scene point_a point_b` performs finite
native distance inspection.

`gx2d_bridge_create` creates a separate curve from an explicit endpoint-frame
pair and a `gx2d_bridge_spec`; source curves remain unchanged. Straight,
quadratic Bézier, cubic Bézier and cubic Hermite/smooth choices all enforce C0.
Cubic and Hermite retain the supplied endpoint derivatives exactly within the
requested tolerance. Quadratic uses the positive intersection of tangent rays;
parallel collinear rays use the midpoint, while incompatible or backwards rays
return a constraint error. Receipts separately report C1 at each end and tangent
continuity, so a geometrically smooth quadratic is not mislabeled C1 when its
derivative magnitudes differ. Cubic numerical loss preventing the requested C1
match is an explicit range failure. Creation refuses active native transactions
and preserves prior geometry on failure.

Receipts retain analytic controls, endpoint/bridge derivatives, local parameter
policy, tolerance and explicit subdivision count (1..4096). Curve geometry is
the declared sampled materialization of that analytic bridge; finite polyline
chords are not claimed to have analytic derivative continuity. Tcl exposes
`bridge scene start_curve end_curve kind subdivisions tolerance reverse_start
reverse_end spline_start spline_end`, or `bridge_frames scene start_frame
end_frame kind subdivisions tolerance`. Kinds are `straight`, `quadratic`,
`cubic`, and `smooth`.

`gx2d_sample_spline_range` samples only a specified exact control range, with
bounded Tcl `spline_range` output up to 65536 points. `gx2d_sample_spline_object`
and Tcl `spline_object` retain a complete sampled spline in Native2D without
creating a full Tcl coordinate list. Use paged/binary resources or bounded
comparison/display queries on that object.

Flat group lifecycle includes `group_add`, `group_remove`, `group_contains`,
`group_members` and `ungroup`. Last-member removal deletes the empty container,
preserving member geometry; deleting the last ordinary member also removes its
empty group. Group bounds include its exact members. Locked containers/members
remain authoritative for in-place transforms and native drag.

`gx2d_expand_objects` / `expand_objects scene object_ids` expands flat groups
in stable request/member order and removes duplicate targets. `gx2d_affine_objects`
applies `{a b c d tx ty}` atomically to explicit targets without altering
selection. All transformed points are prepared and finite-validated before any
swap; constraints are checked against the complete proposed state, and failure
restores all targets. `gx2d_copy_affine_objects` preserves originals, breaks,
styles, lock policy and direction while clearing selection on new copies.
Tcl `affine scene object_ids matrix ?copy?` returns paired `source_ids` and
`object_ids`. `gx2d_reflection_matrix` / `reflection_matrix scene axis_a axis_b`
defines reflection about any finite line through two distinct world points.

`gx2d_pivot_set/get` / `pivot scene ?bounds|centroid|origin|custom ?world_point??`
stores pivot policy. Automatic bounds and the equal-point centroid use current
native selection; the centroid counts repeated closing vertices as points.
Custom/origin choices are world coordinates. A gesture captures its pivot, so
readback during preview remains fixed until commit/cancel. With no selection,
the Tcl automatic getter returns an empty point with the retained mode.

Numeric file ingestion through `native2DLoadNumericRows` and
`native2DLoadNumericRowsWithGaps` accepts an optional progress command. Each
complete 65536-row append finishes before the cooperative event boundary;
callbacks receive `stage=native_geometry`, `completed_rows`, and `total_rows`.
Callback cancellation/errors discard the partially created native object and
close input handles. These files are explicit owned Numerical/Source staging
artifacts, never caller-discovered Dataset storage paths.

`gx2d_drag_is_active(scene, &active)` reads the drag lifecycle without mutation;
Tcl exposes `core drag_active scene`. During a drag, selection and scene mutation
continue to return `GX2D_BUSY`. Commit or cancel before applying deferred requests.

`gx2d_selection_replace_points(scene, object, indices, count)` atomically replaces
the scene's selection with explicit zero-based indices on one object. It checks
every index, selectability and drag state before any mutation; duplicates are
harmless and an empty array clears selection. Failed requests preserve selection.
Tcl exposes `core selection_replace scene object indices`; it uses scene/object
IDs, never pointers, and does not recreate geometry.

`gx2d_selection_patch_points` / `selection_patch scene object start count indices`
atomically synchronizes a bounded page (at most 65536 points), preserving manual
selection outside that page and existing rectangle predicates. Invalid indices
and busy-state failures preserve all selection. `selected scene object start
count`, `selection_flags scene object indices`, `selection_summary scene object`
and `selection_state scene object start count` provide bounded or scalar readback
without reconstructing the scene. Read queries remain valid during a drag.

`gx2d_hit_point_device` / `hit_point_device scene object {px py} tolerance_px`
picks exact vertices in the effective Native2D projection. It excludes segments,
hidden/non-selectable objects and out-of-viewport clicks. Tolerance and returned
distance are pixels, avoiding false point hits on anisotropic X/Y views.

`gx2d_view_aspect_set/get` selects `GX2D_ASPECT_AUTO` or `GX2D_ASPECT_XY_EQUAL`.
Equal aspect expands requested bounds around their center to give equal numeric
world distance per device pixel on both axes, without cropping requested data.
`gx2d_view_requested` retrieves the original request independently from effective
`gx2d_view_get` bounds. Tcl exposes `aspect scene ?auto|xy_equal?` and
`view_requested scene`. Fit, zoom, pan and resize preserve the aspect mode.

`gx2d.h` is the C99 geometry model API. It has no Tcl, Tk, Canvas, or renderer dependency. Build with CMake from this directory; `BUILD_SHARED_LIBS=ON` produces a DLL-capable API on Windows. Define `GX2D_USE_DLL` in a Windows DLL consumer. The default build is a static library.

`gx2d_tcl.c` is an optional portable C/Tcl adapter used by `viewer.dataset_curve_fit` and `viewer.curve_workbench`. CMake builds it as `gx2dtcl` when Tcl development files are present. Both bundled viewers load the single CORE-installed module without a compiler. Their separately installable packages require a compatible framework and contain no private adapter. The same C source and CMake target can produce a Windows DLL in a later platform build. The adapter marshals CORE scene, curve, point-set, style, enumeration, selection, geometry, residual and view calls without owning their algorithms. The `nearest` and `hit` bridge commands return a hit dictionary (`object`, `index`, `point`, `distance`) or an empty result for `GX2D_NOT_FOUND`; `rect` returns the CORE selection-block ID. Both viewers use a separate exact-point selection scene so a segment crossing a rectangle cannot add outside data points.

The five-curve visual API validation, independent known-scene state test, and nonvisual public API contract test live in `../../validation/native2d/` and have a shared run guide. The Tk canvas is a test renderer; these tests do not change this CORE API.

A scene owns all objects and allocates monotonic 64-bit IDs, never Canvas IDs. ID zero is invalid. IDs are stable until the object is deleted and are not reused within a scene. A new scene starts its own ID sequence. The caller owns the scene and must call `gx2d_destroy`.

`gx2d_get_points` and `gx2d_export_selected` use a count query when the output buffer is NULL. A caller may then allocate the reported number of `gx2d_point` values and call again. The dev-049 additions include geometric Catmull–Rom spline sampling and residual evaluation; statistical fitting and model estimation remain in the Numerical API. `gx2d_selected_points` exports object ID, index and coordinate together. Replacing a curve's points does not change its object ID and preserves selection for indices that still exist.

Curves are polylines with at least two points. Their global direction is the first-to-last unit vector; a segment direction uses its zero-based segment index. `SIZE_MAX` asks for the global direction. Coincident endpoints yield `GX2D_CONSTRAINT` for direction queries. Hit testing projects onto curve segments; `gx2d_hit.point_index` identifies the first vertex of the nearest segment, or the vertex for a point object. Rectangular blocks select included vertices. If a curve crosses a block with no vertex inside, the intersecting segment's endpoints are selected. Add and subtract blocks are evaluated in insertion order, and removing a block recomputes the effective selection. An explicit point add/remove overrides rectangle blocks for that point. A hidden object remains in the scene and retains explicit selection state; rectangle blocks only add visible, selectable objects.

Group membership is flat; groups may contain curves, point sets, and individual points. Selecting a group moves its members. A deleted member is removed from the group. Layer ID zero is the implicit default layer; deleting a named layer reassigns its objects to layer zero. Hidden and non-selectable objects are omitted from hit testing; locked objects or locked layers refuse geometry edits. Every operation returns a status. Geometric edits are atomic on error.

`gx2d_object_ids` and `gx2d_layer_ids` enumerate IDs in creation order; renderers may sort by the exposed order fields. `gx2d_snap_point` covers point-to-point and endpoint-to-endpoint attachment by using index zero or the final curve index. `gx2d_snap_to_curve` projects onto the nearest polyline segment.

Drag updates are absolute relative to `gx2d_drag_begin`, so pointer movement can repeatedly update without accumulation. `gx2d_drag_commit` validates constraints. A failed commit restores the drag baseline and leaves the drag session open for another update or cancel. Fixed constraints capture the current point when added. Distance uses point indices; angle, parallel, and perpendicular use first-to-last curve directions. Angle is signed from object A to B in radians. Constraints are checked at creation and on edits with caller supplied positive tolerances. They validate a requested transform, not solve a CAD system. `gx2d_align_direction` rotates one curve around a chosen pivot to a requested angle relative to another, subject to all active constraints.

## Dev-049 curve and view additions

The public C header defines zero-based point insertion, removal, replacement, reorder and reverse; inclusive extract, keep, remove and split ranges; and ordered concatenation. `gx2d_concatenate_parts` accepts a per-part reverse flag and a `break_before` flag. A break after point *i* suppresses segment *i* → *i+1*; it is retained through supported edits, extraction and composition. `gx2d_get_breaks` and `gx2d_set_breaks` expose this geometry state. Callers may deliberately connect disconnected fragments by omitting a break. These operations keep object IDs and selection indices coherent or create new stable IDs for derived objects.

`gx2d_object_bounds`, `gx2d_scene_bounds`, `gx2d_nearest_segment`, `gx2d_nearest_spline`, `gx2d_path_length`, `gx2d_path_point`, and `gx2d_curve_metrics` support inspection and navigation. Length omits disconnected gaps; enclosed area is reported only for connected closed curves. `gx2d_sample_spline` evaluates an ordered control polygon geometrically. `gx2d_compare_curves` produces per-sample signed and absolute residuals plus maximum, mean absolute and RMSE summaries. X mode samples at reference X positions and requires monotonic single-valued curves; path mode aligns normalized cumulative path positions, including folded curves. Residual comparison rejects disconnected inputs so a gap is never silently treated as a segment.

`gx2d_compare_curves_display` retains exact full-input summaries while returning
an ordered extrema presentation of at most 65536 residual records and their
original residual ordinals. Native scratch memory is bounded by the requested
budget. X interpolation uses binary searches; path comparison advances through
segments in source path order. Tcl `compare_lod scene reference derived x|path
budget` returns exact `count`, maximum/mean/RMSE, bounded `rows`/`row_indices`,
`max_source_index` in the full residual result and `max_index` in presentation.
Viewport changes never alter these scientific metrics.

Typed `append_binary_xy`, `append_binary_pointset` and `append_binary_xy_gaps`
ingest bounded interleaved float64 little-endian chunks. Point-set ingestion
retains point-only rectangle semantics. Gap ingestion consumes one 0/1 byte per
incoming point and preserves the preceding edge break across chunk seams.
`numeric_pack_columns scene x_column y_column source_rows_or_empty row_base companions`
adds the `numeric_companions` capability to the same bounded transport. The
dictionary contains one to eight named typed columns, each matching the XY row
count. Its `companions` result contains float64 little-endian byte arrays aligned
to precisely the finite XY rows. Companion NaN/Inf/zero values remain intact for
the consumer's scientific policy. The original `numeric_pack` optional parameter
contract and its finite-value requirement remain available unchanged.

`numeric_pack` supplies finite XY pairs, exact uint64 source-row mapping, bounded
`break_before` bytes and `ends_finite`, enabling shared host staging without a
whole-source Tcl list. Failed appends leave existing geometry unchanged.
`points_page` and `points_binary` provide bounded exact ranges. `render_lod`
reduces exact controls, while `render_curve_lod` evaluates stored Native2D
interpolation and then reduces presentation. Both retain explicit gap boundaries.

The renderer-neutral `gx2d_view_*` family stores viewport size, margins and world extent in the scene and provides fit, anchored zoom and device pan. World/device conversion and pixel tolerance use that same state. `gx2d_render_points` returns device coordinates; the Tcl adapter also exposes connected render paths for drawing without inventing gap geometry. Scene objects and view persist across pointer events, so consumers can use C selection, drag and hit queries incrementally. Independent C and Tcl bridge fixtures for these APIs are in the workspace `validation/dev049_curve_workbench` directory.

## Direction markers and construction grid

Direction markers belong to logical curve IDs. `gx2d_direction_marker_get/set`
stores independent intended direction, visibility, normalized path position,
pixel offset/length/width/head scale and RGBA color. Defaults are hidden,
forward, halfway along the path, 12-pixel offset and 32-pixel length.
`render` returns device primitives and bounds; `hit` and `place` use the same
native geometry. Interpolation selects the stored polyline or a native sampled
Catmull–Rom path. Hidden markers do not hit. Marker placement and styling do not
modify scientific coordinates. `attach` transfers marker state between curves;
`order` returns bounded source-index pages in intended forward/reverse order,
independently of an explicit geometry reversal. Presentation state is retained
through coordinate transforms. Device dimensions stay constant under pan,
zoom and coordinate aspect changes. Setters refuse an active native drag.

`gx2d_grid_get/set` owns an orthogonal world grid with origin, positive X/Y
spacing, rotation in radians, major interval, independent visible/snap flags,
major/minor/origin-axis visibility and RGBA/width/style. The default grid is
disabled, hidden and unsnapped. `gx2d_grid_render` clips device primitives to
the native viewport and limits output to 2048 lines. Dense presentation is
decimated without changing logical spacing or snap results. A NULL output is
a count query; a smaller supplied buffer returns `GX2D_RANGE` and required count.
Cartesian display thinning retains integer multiples of the configured major
period until parallel rendered lines are at least eight device pixels apart.
It uses their perpendicular screen distance under rotation and unequal axis
scales. Zooming in reveals the original minor lattice again; origin, spacing,
major classification, colors, snapping, geometry and saved Workspace values
remain unchanged. Canvas, Preview and presentation export consume these same
CORE primitives, so density follows each actual output viewport.
`gx2d_grid_snap` explicitly snaps in rotated local grid coordinates with
round-half-away-from-zero ties. Axis bits 1/2/3 select local X/Y/both. Explicit
queries work even when the grid is hidden; the host applies `enabled` and
`snap_enabled` policy to normal gestures. `gx2d_grid_translation` snaps one
chosen pivot and returns a common delta, preserving the shape of a multi-point
selection. All inputs and results must be finite.

`gx2d_background_get/set` stores RGBA. `gx2d_presentation_set` validates grid,
background and aspect together on a trial scene before committing any property.
Invalid inputs and busy-state failures preserve all presentation properties.
The Tcl adapter exposes `grid`, `background`, `presentation`, `render_grid`,
`grid_snap` and `grid_snap_delta`, plus `direction_marker`, `marker_attach`,
`render_marker`, `marker_hit`, `marker_place` and bounded `marker_order`.
These host calls accept scene/object IDs, never pointers or Canvas items.

## TASK-9 CAD objects and Native manipulators

`gx2d_group_add_member/remove_member/contains` extend the existing flat editing
container. `gx2d_ungroup` deletes only the container. Removing its last member
also removes only that empty container. Group bounds include all members.
`gx2d_expand_objects` expands group/object targets in stable first-occurrence
order, bounded to 65536 targets. `gx2d_affine_objects` transforms an explicit
target set without changing selection; overlap transforms each member once.
Matrix order is `{a,b,c,d,tx,ty}`. Locks and all constraints are checked before
the prepared geometry commits. `gx2d_copy_affine_objects` returns independent
complete copies, preserving geometry/breaks/style/direction and original objects;
new copies have no selection. Its source/result order follows expanded targets.
`gx2d_reflection_matrix` accepts two distinct points on an arbitrary mirror axis.
Rotation/scaling matrix helpers retain an explicit world pivot. All transforms
reject nonfinite input/results and active-drag mutation.

`gx2d_pivot_set/get` supports selection bounds, equal-point centroid, world
origin and custom world point. Repeated closing vertices count as points in the
centroid policy. A Native drag captures both the pivot and the starting view.
Existing `gx2d_drag_translate/rotate` apply absolute displacement/angle to their
exact snapshots; commit checks constraints and cancel restores exact coordinates.
CORE rotation uses radians. Adapter `rotate_degrees`, `rotation_matrix_degrees`
convert the numeric UI's degree boundary before invoking Native rotation.

`gx2d_gizmo_get/set/render/hit/parameters` owns translation X/Y/free handles,
rotation arc/arrows, pivot and mirror-axis endpoint handles. Render output is
at most 64 typed line/circle/box primitives with device points, RGBA, widths and
semantic handle roles. Dimensions remain stable in screen pixels. Mirror-axis
lines are clipped in Native code. Native hit testing obeys the viewport and
returns a semantic handle; parameter calculation uses world/view projection and
the captured starting view during a drag, including intervening pan/resize.
Gizmo rendering/readback remains legal during an active drag. Setters and
destructive operations remain lifecycle guarded. Tcl exposes `gizmo`,
`render_gizmo`, `gizmo_hit`, `gizmo_parameters`, `pivot`, group lifecycle,
`expand_objects`, `affine` and matrix helpers. The shared canvas renderer only
draws Native primitives; it does not compute a second manipulator geometry.

Scripts use the document/Session/revision-scoped
[NATIVE_2D_GEOMETRY_API_v1](../../docs/api/NATIVE_2D_GEOMETRY_API_v1.md), which maps
execution-owned opaque scene/object tokens to this host authority. It includes
exact Source intake, bounded pages/comparison, native bridges/groups/affine
copies and complete Interactive Document resources. Dataset publication stays
explicit through the common Dataset APIs.


TASK-9 retained sketch additions expose `gx2d_sketch_validate/evaluate/bounds/
sample/create/get_definition/update/explode/materialize` and raw Tcl `sketch_*`.
Definitions cover point, finite/construction line, polyline, oriented rectangle,
circle, signed arc, ellipse, quadratic/cubic Bezier and existing Catmull-Rom spline.
The Native scene deep-owns controls and defining parameters, retaining them through
whole-shape transforms, copies, constraints, drag/cancel and coordinate conversion.
Direct sampled-point mutation rejects; parameter updates or explicit independent
explosion/materialization preserve the authority boundary. Exact extrema and
scientific curve metrics/path points do not use the display cache as authority.
Construction lines have undefined finite bounds/length, viewport-clipped rendering
and exact infinite-line projection; an explicit finite parameter range is required
to materialize them. Stateless sampling supports complete million-point grids in
pages of at most 65536, with atomic caller outputs.

`gx2d_series_create` and raw Tcl `series scene object_ids parameters` implement
atomic rectangular/circular copy series with stable source association, retained
primitive definitions and bounded native allocation. Parameters and typed Script
contracts are documented in `docs/api/NATIVE_2D_GEOMETRY_API_v1.md`. Late failures
remove all created copies without rewinding monotonic native identities.


The additive `gx2d_constraint_v2` API preserves the legacy constraint POD ABI.
It extends relationships to 21 kinds and provides stable native create/get/IDs/
update/enable/diagnostic lifecycle. Rules validate active Native mutations; no
full parametric solver is claimed. Separate angular tolerance supports tangent/
collinear checks. Similarity circles/arcs support radius semantics; supported
point-on-curve families are explicit. Coordinate conversion scales dimensional
values/tolerances without changing radians. `gx2d_join_points` stages optional
source-point/retained-endpoint merge and one persistent coincidence rule together,
with unchanged target and atomic Fixed/lock/invalid/new-rule failure rollback.
Complete point candidates use the existing `gx2d_replace_points` transaction so
joined selected points can move together. Extended ordinal references require
explicit disconnection before topology reindexing; legacy five-kind semantics
stay unchanged. The Tcl adapter uses `constraint_*` operations and structured
validation/enforcement/solver diagnostics. Scoped Script and Workbench contracts
are described in the shared Native2D Geometry API reference and module manual.

### Shared geometry role

`gx2d_geometry_role_get/set` provide regular/construction/reference semantics through reserved validated Native identity metadata. Roles preserve scientific geometry and remain available for constraints, measurements and transforms. Infinite construction lines default to construction; explicit finite samples default to regular. Copies and document resources retain explicit roles. Native2D consumers use this shared policy for default Dataset/geometry/presentation exports, with explicit finite materialization or reference inclusion when requested.


## TASK-9 dev-052 final behavior

The additive `gx2d_cartesian_to_polar_many` validates the complete input before writing output, supports the same explicit polar frame as scalar conversion, and returns angle-defined bytes (origin0). Tcl `polar_binary` uses bounded binary XY, avoiding a million-point Tcl list. The scoped geometry Bridge exposes it as `polar_bulk` with base64 receipts.

Native selection transactions preserve pending changes during drag and flush only at safe release/cancel lifecycle boundaries. Workbench table synchronization schedules one idle callback for rapid selection events, verifies scene/curve/lifetime epochs and prevents recursive redraw/table refresh cascades. Point tables keep stable rows when only selection changes.


## dev-053 CAD workspace

Additive retained interaction lives in gx2d_interaction.inc and gx2d_interaction_constraints.inc; the optional Tcl adapter only marshals public C calls. True controls, retained inverse transforms, construction/preview/fit mapping, pixel pick/snap and viewport segment clipping are reusable CORE functions. Existing geometry, constraints, units, identities and POD ABI remain authoritative. Scoped scripting is described in docs/api/NATIVE_2D_GEOMETRY_API_v1.md. Packaged CMake tests use shipped053 interaction plus052 compatibility fixtures; production builds may set BUILD_TESTING=OFF. Tiny gestures/compatibility/clipping remain serial. Complete fitting uses existing Numeric/Parallel Execution limits; no new worker pool or nested oversubscription.

dev-062 exposes real constituent controls on an exact composite Path through
the same interaction/reference API. Shared junction edits preserve topology.
`gx2d_control_definition_owned` and its release function deep-own edit candidates
so nested definitions never borrow freed preview storage; the old primitive
caller-buffer ABI remains available. No new script endpoint is required.
# Scientific tangent evaluation (dev-059 candidate)

Tangent-angle measurements and tangent constraints evaluate the authoritative
curve: exact retained definitions, or the selected outgoing/incoming segment of
sampled source rows. `direction_marker.interpolation` is presentation-only and
cannot change these scientific results. The explicit `gx2d_curve_point_frame`
and endpoint-frame interpolation argument remains available to callers that
deliberately choose an interpolant. Workbench Dataset display choices do not
make that scientific choice; reviewed retained promotion records its provenance.


Dev-063: scenes initialize equal X/Y visual scale through the existing view
setter. Hosts may override aspect explicitly; the Script Bridge and default UI
cannot. The existing spline tangent API resolves Path control ordinals to exact
Spline leaves, composes root/leaf matrices for reads and inverts both for edits.
Leaf side names are independent of Path traversal orientation; deep update and
constraint validation preserve one owned Path and its defining controls.

## Numerical reduction ownership (integrated dev097)

The source build requires the matching public Numeric C binding at
`plugins/modules/math.numeric/api/c/gxtxt_numeric_reductions_v1.h`. Native2D
owns geometric matching, projections, path and contour traversal; Numeric owns
streaming mean absolute error/RMS/maximum reductions. Both `compare`/
`compare_lod` and `compare_geometry` consume this binding without IPC or an
observation-array copy. Display sampling/retrieval passes reuse the first
scientific reduction rather than computing the same summary three times.
CMake rejects a missing binding. The public Native2D C
structs, Tcl operations and result fields remain unchanged.

The additive `numeric_row_audit` capability extends numeric_pack and
numeric_pack_columns with input_source_rows and nonfinite_source_rows byte arrays.
Both use exact little-endian uint64 encoding; input order and existing finite XY,
companions, parameter and gap outputs remain intact. Row ordinals retain the
existing0..INT64_MAX contract. The adapter retains the validated integer buffer
through audit packing; no binary64 conversion or second Tcl value read is used.
CORE streams these bounded chunks into owned temporary audit inputs.


## DEV111-P014 retained grid presenter

`gx2d_grid_presenter_v1.cpp/.h` belongs to the existing `gx2dtcl` CMake target.
It provides one retained public-Tk Canvas item painted by Cairo, native-owned
font/glyph/pixmap resources, and retained control-position batches. The C geometry,
grid-generation and snapping sources remain unchanged. Public host documentation:
`docs/api/NATIVE2D_GRID_PRESENTER_API_v1.md` at the framework root.
The patch ships the matching Linux x86-64 `bin/gx2dtcl.so`; restart after applying.
A normal source build remains:

```sh
cmake -S core/native2d -B /tmp/gxtxt-native2d-build -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/gxtxt-native2d-build --target gx2dtcl -j2
```

Existing Tcl/Tk8.6, Cairo and X11 development headers/libraries are required.
There is no new graphics plugin, background Tk thread or separate scientific engine.


### Retained sprite presentation (DEV111-P015)

`gx2d_sprite_scene_v1.cpp/.h` is part of the existing `gx2dtcl` CMake target,
C++17 with the existing Tk8.6/Cairo/X11 dependencies. The standalone C scientific
engine, grid generator and snap algorithms are unchanged. The public GUI host
contract is documented in `docs/api/NATIVE2D_SPRITE_SCENE_API_v1.md`.
The target includes both the accepted P014 grid presenter and the new retained
sprite scene; use the matching binary and complete cumulative sources together.
No additional plugin, worker, renderer backend or event loop is required.
