# Native2D temporary display API v1

`NATIVE2D_TEMPORARY_DISPLAY_API_v1@1` is a bounded RAM fixture over the existing
native C++ scene, geometry, hit test, transaction and viewport/presentation owners.
Its authority is `core/tcl/native2d_temporary_display_v1.tcl`, not the Builder's
layout-map canvas. The fixed curve, point markers, grid and orange closed shape
carry `display_only_RAM` provenance and no scientific source identity.

```tcl
set widget [::GX::native2DTemporaryDisplayCreate .viewer.canvas.demo callback]
pack $widget -fill both -expand 1
set receipt [::GX::native2DTemporaryDisplayInspect $widget]
::GX::native2DTemporaryDisplayMode $widget pan
::GX::native2DTemporaryDisplayNavigate $widget fit
::GX::native2DTemporaryDisplayReset $widget
::GX::native2DTemporaryDisplayDestroy $widget
```

`callback` is an optional trusted command prefix receiving `(widget, event)`;
authors in the restricted SDK request typed demo binding instead of supplying
Tcl. Inspect returns real native scene/geometry/view/selection receipts. At most
eight fixtures may be live. They allocate no Dataset, Session, Workspace, Script
Job or imported CSV. No arbitrary model/file loader is exposed.

Select / Move uses the real native device-space hit test. Drag records selected
object, device point, world point, world delta and actual start/update/end/cancel
phase. The scene's existing drag_begin/translate/commit/cancel owns geometry.
Pan changes the native view transform, leaving object geometry unchanged. Wheel
zoom, Fit and Reset retain independent meanings. `Navigate ... zoom factor x y`
accepts factor0.1–10 and the device anchor; `Mode` selects move or pan. Escape or
`native2DTemporaryDisplayCancel` cancels an active native transaction. Reset
cancels it and recreates the initial RAM scene. Closing/destroying any parent
releases its timer, viewport host and native scene exactly once.

The callback log is capped at128 events and records `author demo_fixture`,
empty `source_identity`, presentation provenance and generation. Display/world
coordinates are demo units; moving the shape is not a canonical Dataset edit.
Scientific object editing is a separate future contract.
