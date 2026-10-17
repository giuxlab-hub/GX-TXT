# Shared Native2D ViewportHost

Native2D C owns retained geometry, references, constraints, units and scientific
view transforms. Shared Tcl/Tk owns viewport chrome, panels, icons, scrolling,
focus, tooltips and context menu composition. The provider owns its logical
payload and pointer/tool orchestration. Tk widget paths and canvas item IDs are
never persistent scene identities.

`native2DViewportHostCreate container canvas scene changed_callback` registers a
host. The chrome container is resolved from the canvas geometry manager; create
the canvas as a real child of that viewport frame. Chrome shares that actual
parent, avoiding remote X11 overlays which obscure child controls until hover.
`native2DViewportPanelWidget host id` resolves the panel widget; callers must not
assume a toplevel child path. These are additive host/UI-only helpers, with no
scientific state or Script Bridge exposure. Zoom,
pan and aspect transform geometry underneath fixed widgets. Panel creation takes
ID, title, semantic anchor and bounded options. Anchors cover all nine ordinary
viewport positions. Font-scaled margins, priority lanes, collisions and narrow
fallback are shared. Panels support show/hide, collapse/reopen, optional close,
bounded size, scroll content and keyboard focus. Pinning is optional and not
implemented. Explicit reopen overrides automatic narrow collapse.

`native2DViewportPanelContent` embeds existing provider widgets with a Tk canvas
window item; its clipping and scroll region belong to the shared container.
Do not simulate this by packing a sibling over a blank scroll frame. Focus
reaches offscreen content through `native2DViewportSeeWidget`; X11 wheel routing
is scoped to the actual panel under the pointer.

Standard controls reuse C Fit All/Selected, zoom, reset, grid/snap and aspect.
Pan, zoom-box and object-snap gestures use provider callbacks. Icons come from
framework-owned integer strokes converted to Tk photos; no emoji, icon fonts or
vendor assets. Ttk provides hover/pressed/disabled state; grid/snap/aspect reflect
Native state. Glyph size follows font metrics and color follows theme contrast.
Panels and chrome never query/transfer large scientific arrays.

`native2DViewportContextMenu` composes ordered shared actions and compatible
constraint cascades from Native semantic targets, then provider actions. This
does not create a second compatibility authority. The Workbench contributes
publication/representation actions. Its Settings controls utility visibility;
the Sketch palette and residual strip collapse to shared compact controls.
Narrow windows release the left utility area to keep the canvas usable.

All these capabilities are intentionally host/UI-only. Their underlying view,
geometry, calibration, symmetry, tangent and preview services are bridged.

Hosts drawing an opaque plot rectangle give it the shared
`native_plot_background` canvas tag. The shared reference-raster presenter places
pixels above that background role and below geometry/grid/annotation items.
A canvas background color needs no item. Lowering a raster beneath an opaque
plot rectangle would make a retained, correctly transformed image invisible.

## State-managed controls

`native2DViewportToolState widget active` styles an existing ttk button or
menubutton and manages its `selected` state. The caller supplies its actual
controller mode; the CORE service stores no alternative tool choice. The
Workbench derives Select/Pan/Transform/Create/constraint/dimension states from
its established controller, including shortcuts, Escape and modal transitions.
The existing `native2DViewportTooltip` remains the only tooltip engine.
Context popup clients use the documented shared `uiMenuPopup` service.


## Embedded canonical curve source

`native2DViewportCurveCreate parent session request ?options?` composes the public
Curve Source and this existing ViewportHost. It creates a real child Canvas;
pack/grid the returned widget. `request` is the unchanged Curve Source request
with Dataset and explicit X/Y Variable IDs, filters and optional display budget.
Options are `selected`, `completed`, `progress` callback prefixes, color and title.
This helper adds no Plot Dataset migration, data store, selection engine or
scientific calculation. It uses the same native geometry projection, complete
source bounds, continuity/breaks, shared snapshot painter and adaptive axes.
Independent axis units such as seconds and volts are retained; this is not a
Euclidean CAD measurement plane. No implicit resampling/conversion occurs.

Display preparation uses the existing cancellable Curve Source async service.
`native2DViewportCurveDescribe canvas` returns the authoritative source descriptor,
loading/ready/unavailable state, bounded display receipt and current viewport.
LOD is explicitly presentation-only; the complete canonical source remains the
only scientific authority. Wheel zoom, middle drag pan and double-click whole-data
fit reuse Native2D navigation. Automatic fit uses complete source extrema,
including negative data, independently of the display budget.

`native2DViewportCurveHit canvas x y ?notify?` picks an actual displayed source
vertex using Native2D's device point hit. A hit retains exact original row ordinal,
source ID, both physical variables and their units/coordinates. With notify true,
the selected callback receives `(canvas, receipt)`; no canonical selection or
Dataset is changed implicitly. `native2DViewportCurveNavigate canvas action args`
also accepts `fit`, `zoom factor x y`, `pan_begin x y`, `pan x y`, `pan_end`.

`native2DViewportCurveDestroy canvas` destroys only this child. The existing
ViewportHost destruction path cancels its pending source job, unsubscribes its
catalog callback, closes its Curve Source and releases its native display scene.
Changed Session/schema/payload guards reject stale operations and show an explicit
unavailable source. A caller must create a fresh binding to adopt changed science.

```tcl
set curve [::GX::native2DViewportCurveCreate $frame $::GX::currentSession \
    [dict create dataset_id measurement x_variable_id measured_time \
        y_variable_id voltage display_budget 2048] \
    [dict create title {Measured response} selected [list MyApp::selected]]]
pack $curve -fill both -expand 1
```

## Managed image ROI and composition

The existing scoped Geometry scene can attach to this same viewport host through
its guarded host adapter. Reference images continue to use the shared native
transform/layer and image painter. Source-pixel ROI geometry is validated by the
native image owner and retained in existing image identity attributes. Managed
ImageMagick work uses the existing supervised execution and resource authorities;
see [Native2D raster composition](NATIVE2D_RASTER_COMPOSITION.md) for actual ROI,
mask, blend, persistence, bounds and ownership contracts.
