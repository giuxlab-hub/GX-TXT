# Native2D axis presentation

`NATIVE2D_PRESENTATION_SNAPSHOT_v1` and `NATIVE_2D_GEOMETRY_API_v1` share one
view-scoped descriptor. Scientific data limits, viewport bounds, tick placement
and formatted labels remain distinct. This service changes no scientific values,
geometry, source identity or physical calibration.

```tcl
set axes {
    x {title Time ticks {placement integer step 5 format integer}}
    y {title Response ticks {format fixed_decimal precision 2}}
}
::GX::native2DAxisPresentation $nativeScene $axes
set saved [::GX::Native2D::core view_state $nativeScene]
```

The raw native scene host owns `axis_presentation scene ?descriptor?`. Public
execution-scoped callers instead use `native2DGeometryCall scene_token
axis_presentation {axis_presentation descriptor}` or the equivalent registered
Python/Octave operation. An empty request queries; an empty descriptor resets.
`native2DPresentationSnapshot` also accepts a transient `axis_presentation` option.

Each optional `x`/`y` entry accepts `title`, `unit_label`, `ticks` and `context`.
Titles/unit labels are bounded to256 characters. Tick fields are `placement`
(`auto` or `integer`), `step` (`auto` or a positive finite interval), `format`
(`auto`, `integer`, `fixed_decimal`, `significant_digits`), and `precision`
(0..15 decimal places or1..15 significant digits when relevant). Integer format
requires integral display-coordinate anchors. Fixed/significant formatting plans
representable tick coordinates before formatting; it does not round arbitrary
viewport-fraction anchors into fictitious numerical positions.

Ticks use the existing coherent numerical planner. Explicit intervals define a
zero-anchored lattice. Dense lattices are thinned by an integral multiple to fit
available pixels and the64-tick bound; receipts distinguish `requested_step`
from actual `step`. No source point or viewport bound is discarded. Each tick
retains its true world `value`, mapped `display_value` where applicable and label.
Canvas, scientific grid and export consume the same positions. Explicit legacy
`x_tick_labels`/`y_tick_labels` (six strings) and `x_label`/`y_label` options retain
their established precedence. Construction grids retain their authored geometry.

The host snapshot optionally accepts `axis_plans {x PLAN y PLAN}` from an existing
coordinate presentation adapter. Each plan must match the current world bounds
and contain at most64 finite, distinct in-bounds tick `value`/`label` pairs. These
are the actual mapped world anchors produced with the shared numerical planner
and public coordinate conversions; label strings do not select positions. The
snapshot validates the bounds and anchors before drawing/export. This supports
Curve Workbench's per-axis engineering presentation without changing its geometry,
stored units, source Dataset or authored construction grid.

## Coordinate contexts and units

The absent context is `{kind world}` and permits no unverified unit label.
`{kind conversion source_unit mm target_unit um}` declares a display conversion
through the actual CORE Unit Registry affine plan; numeric ticks are selected in
the converted frame and mapped back to their true world anchors. This explicit
source-frame declaration is not image calibration.

`{kind image_pixel object_token OWNED_IMAGE}` is accepted by the public opaque-scene
operation. The native host accepts an actual `image_id` at its direct owner boundary.
The normalized persisted context uses the verified `image_resource_id`, avoiding
transient object numbers across reopening. Exactly one current image must resolve
that identity; a missing/ambiguous image requires explicit rebind. The actual inverse
`image_map` supplies scale and offset. A rotated nonseparable mapping is refused,
never labelled as raw raster X/Y. Unit is `px`. A sole visible uncalibrated reference
image gets this truthful default where its mapping is separable; mixed geometry
retains ordinary world axes unless explicitly configured.

`{kind image_physical object_token OWNED_IMAGE target_unit mm}` requires actual
native image calibration and a proportional Unit Registry conversion from its
recorded physical length unit. An uncalibrated image cannot acquire physical
units by changing text. Pixel/physical mapping is revalidated on every redraw.
A supplied `unit_label` must equal the verified context unit.

## Persistence and hosts

`view_state` carries the descriptor; states without it retain empty/default
presentation. Named saved views capture/restore it with their existing ownership
and unit checks. An owner saves that state in its ordinary Workspace/Document
payload. Stable raster resource identity resolves a fresh native object on reopen.
`view_state_rescale` scales explicit world-coordinate intervals in the copied
state; nonidentity rescale with a unit/pixel context is rejected until its new
frame is explicitly validated. Live geometry is not changed by that operation.

Scientific Multiview accepts `axis_presentation` on Native2D Attach and Configure
(`{slot descriptor ...}`). Pan/zoom/resize reads the same scene state; old Session,
deleted/replaced Document and revision changes use existing host guards. Independent
X/Y titles and formatting do not create another tick registry or renderer.

Native Canvas Preview/export receives the same descriptor. Where annotations/axis
text are requested, PNG/PDF retain the mapped text anchors and title rotation.
Snapshot exporters receive the exact public text positions. Data transformation,
physical unit reassignment and image processing remain separate explicit services.
