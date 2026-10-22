# Native3D GUI Host API v2

SPDX-License-Identifier: GPL-3.0-or-later

`native3DGuiHostApiInfoV2` discovers the additive component API. Require
`NATIVE_3D_GUI_HOST_API_v2 @ 2` through `workbenchExtensionRequireApi`. Version 1
continues to own the existing single editable Engine3D host unchanged. Its
shared-worker/single-scene contract cannot provide independent Builder windows;
v2 adds instance ownership over the SAME CORE renderer worker and public native
mesh/camera ABI. It does not copy the renderer or use singleton state.

## Component lifecycle

```tcl
set handle [::GX::native3DViewportCreate $parent.viewport {width 560 height 360}]
pack $parent.viewport -fill both -expand 1
::GX::native3DViewportBind $handle {kind demo}
set subscription [::GX::native3DViewportSubscribe $handle view_changed MyCallback]
# MyCallback receives: handle event inert-detail-dictionary
::GX::native3DViewportInspect $handle
::GX::native3DViewportUnsubscribe $handle $subscription
::GX::native3DViewportRelease $handle
```

The opaque handle owns one child frame, native-rendered image, native worker,
scene, camera, bounded input queue, subscribers and timers. Parent Destroy
releases it automatically. Releasing one never closes another or the v1 host.
At most four component/retiring worker owners exist per application. A released handle is
invalid; repeated release is harmless. Reparent by release/create in the new
container. Normal pack/grid, notebooks and splitters manage the returned child;
resize updates the existing native target, retaining camera and scene.

Rendering and startup are asynchronous. Inspect reports empty, loading,
rendering, ready, error or stale_source, generation, source kind, actual native
camera/result, pending count and owned PIDs. Events are ready, view_changed,
selected, error, source_changed and released. Geometry selection uses the actual
native pick service; see the public preset/selection contract below.
Callbacks receive inert data and must not assume their widget still exists.

## Presentation and input

Configure accepts width/height (160..4096), projection (perspective/orthographic),
semicolon XYZ camera_position/target/up, axes_world and navigation_cube_visible.
`native3DViewportConfigure handle options` and `native3DViewportUpdate handle`
rebuild only this display scene; no scientific computation or publication occurs.
`native3DViewportNavigate handle orbit|pan|zoom|roll dx dy` uses the existing
native camera services. Drag or arrow keys orbit, Shift-drag pans, wheel zooms;
Fit/f fit scene, Reset/r restores isometric, Front/Top select actual native views.
`native3DViewportCamera handle` returns the observed native camera. Supply that
complete dictionary as a second argument to restore it after rendering is ready.

## RAM scenes and scientific binding

`{kind demo}` creates a bounded eight-vertex/twelve-triangle cube in RAM through
`gx3de_object_create_mesh`, with the native orientation cube and configured world
axes. It has no Dataset ID, canonical files or Session. Its visible footer states
RAM demo / display only / no Dataset. Neither this API nor the readonly worker
provides publication or model editing. It is usable with no scientific Session.
The PNG is the existing native renderer's transfer frame in the account cache;
it is not a screenshot, an imported static model or a scientific Dataset.

Scientific sources use ONLY `{kind scientific module MODULE_ID provider PROVIDER_ID}`.
The CORE owner obtains the exact scene through `viewerSceneResolve`, resolves
registered variables and paths through `native3DScenePrepare`, and preserves
original layer IDs, units, source SHA, mesh/field roles and transforms. Clients
cannot supply private model paths or fabricated Dataset identities. A Session
lifetime mismatch stops only this worker and requires explicit rebind. Source
mutation monitoring and complete scientific lifecycle acceptance remain recorded
separately in the release matrix; RAM rendering alone does not prove them.

## Limits and failure handling

The existing configurable Native3D graphics policy applies, including per-worker
address-space and RSS limits. Requests time out after 45 seconds. Queues contain
at most eight requests; diagnostics are capped at 4 MiB. Rendering dimensions are
bounded to 4096 pixels per side. Errors remain visible in the footer and emit an
error event; explicit rebind restarts a failed instance. Destroy cancels timers,
file events and only its own worker, removes its temporary frame/log directory
and photo. Other Viewers and original scientific files remain untouched.

Builder declares native3d with the exact v2 requirement and typed presentation
properties. `demo=1` is explicit display-only provenance, preserved by Save/Open
and ordinary Script Module Builder generation. Use `viewerGuiDesignNative3DSet`
to bind a declared slot through the same public source contract. Generated
connectors require their declared CORE APIs before opening.

## Public presets and actual geometry selection

`native3DViewportCommand handle preset fit_scene|isometric|front|top` uses the
existing native camera/preset worker service; Builder Fit/Zoom actions use this
contract rather than a private command. `native3DViewportPick handle x y` queues
real native picking at bounded viewport pixel coordinates. A short pointer click
uses it; a longer drag remains orbit/pan. Subscribe to `selected` for its actual
`native_pick` result: hit, layer_id, world/local point, normal and native cell/
point index where returned by the backend. A miss is hit0, never fabricated
selection. The same native pick request renders its genuine selection marker into
the existing transfer frame before the host emits `selected`. A miss clears that
marker. No orbit, camera change, scene rebuild or extra scientific Job is needed.
Inspect exposes the last selection; the host adds no synthetic highlight.
Selection has no scientific edit/publish effect. `released` is an ownership event,
not a successful render. Queue/cancellation/generation rules apply equally to picks.

The scientific stale guard compares public layers, field/timeline definitions and
actual Dataset scientific identities. A legacy client's independent camera change
does not invalidate this component. A changed layer/source or Session does;
interaction stops and explicit rebind is required. The orientation cube is rendered
by the existing native service; camera preset buttons and keyboard navigation are
the exposed orientation commands in this version.

## Exited-worker ownership

Close/rebind sends TERM only to the owned renderer, drains its nonblocking pipe,
and closes it in blocking mode only after EOF to reap the exited child. A one-
second deadline escalates only that worker to KILL. Retiring channels remain
bounded CORE ownership; native3DGuiHostApiInfoV2 exposes their count. A new worker
waits asynchronously for the previous worker of that same instance to be reaped,
preventing old/new frame writers racing. Release defers cache removal until all
its retiring writers are gone. This avoids a zombie remaining after an otherwise
successful native window close; Tk stays responsive while cleanup completes.

## Exact planar cell fields (dev109 integration)

The additive source `{kind cell_field spec PLOT_V4_SPEC}` uses the existing
Plot v4 `GXTXT_CELL_FIELD_BINDING_v1` contract. One complete, unfiltered triangular
field binds canonical node IDs, connectivity, cell IDs and scalar values.
`cellFieldNativeScene` prepares the same source topology used by the 2D field
owner; it does not triangulate centroids or interpolate cell values onto nodes.
Compatible physical X/Y lengths use the X coordinate unit. The display embeds
that plane at Z=0; it is neither a 3D FEM solution nor a CAD volume.

The existing native polydata API receives one cell-associated scalar per triangle.
A compatible precompiled adapter must advertise `exact_planar_cell_field`; an
older binary produces an explicit error, with no compilation fallback. Initial
framing uses the existing native Fit Scene service and its physical depth range.
Session lifetime, both Dataset scientific identities and their coordinate contexts
are checked before interaction. A real source change requires explicit rebinding.
2D-only grouping does not enter this complete topology contract.

Native pick indices remain renderer ordinals. Cell-field pick receipts additionally
map these to exact `source_cell_id` / `source_node_id`, their canonical Dataset IDs
and zero-based source-row ordinals; IDs never pass through floating-point arrays.
The source binding, scalar units and planar embedding appear in the visible status.
This extension preserves the readonly component and existing renderer/worker limits.
It does not provide editable CAD operations.

The isolated CORE adapter contract has actual retained 303-node/544-triangle FEM
data and malformed-connectivity negatives. That is not installed Viewer acceptance.
The initial tiny-frame failure is preserved; corrected framing and installed GUI
interaction remain separately verified gates.


The native host keeps the bound source caption in a separate stable label from
transient activity (Loading, Rendering, Ready, selected). A wrapped scientific
caption must not repeatedly change the canvas height as activity changes: such
layout feedback would otherwise enqueue resize renders during genuine idle.
Source/Session validation, source captions, camera and process ownership retain
their existing authorities. Error text remains visible with the previous frame.
