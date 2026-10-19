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


## Explicit diagram wire bends (dev108)

The existing canonical diagram label accepts optional `id` to update an existing
label in place, and optional `offset {dx dy}` in display coordinates. Omit `id`
to create a fresh stable identity. Existing payloads containing only endpoint
and text remain valid and retain zero offset; new labels default to `{5 12}`.
Offsets are bounded finite presentation coordinates, independent of electrical
connectivity. Invalid IDs, names/coordinates and stale owner revisions reject
before commit. The label's endpoint remains its explicit junction or component
pin reference; moving text cannot weld wires or create a junction.

Presentation annotations may carry optional bounded stable `id`. Snapshot text
retains `annotation_id`; `native2DAnnotationHit canvas x y` returns `hit`, and on
hit the exact rendered `annotation_id` and text bounds. This extends the existing
snapshot/Canvas owner, following its legend-hit pattern; labels are not identified
by duplicate text or inferred scientific coordinates. Diagram selection checks
rendered annotations before symbol/wire strokes. Double-click/Properties edits
Net name and display X/Y offsets through the existing typed dialog; drag moves
the text offset, Delete removes the selected label, and canonical Undo restores
the same ID/endpoint. Normal symbol properties and stroke selection remain.

Viewport edits emit `before_edit` through their existing owner callback before
mutation. The composed Viewer connects it to Scientific Recipe History's
existing PrepareEdit confirmation. Editing an older state therefore asks to
branch first; Cancel leaves the canonical document unchanged. The subsequent
`committed` event retains the existing capture/commit transaction. Consumers
without History need no new service or persistent state.

With the wire tool, click an actual pin/junction, click empty grid positions to
retain bend points (at most64), then finish on an actual pin/junction. The pending
orange route is a temporary curve in the same Native2D scene/snapshot renderer;
it is not a circuit connection or document mutation. Backspace removes the last
pending bend. Escape or tool change cancels the whole pending route. Final commit
uses the existing guarded diagram wire transaction and stable endpoint IDs.
Crossings and clicked empty-grid bend points never invent junctions. Explicit
junction creation remains a separate tool. The old direct two-endpoint gesture
remains valid and preserves its default route.

An electrical `probe` event carries the exact canonical endpoint identity in
its existing callback detail. In a declared Viewer the optional Scientific
section's `scientific_probe_diagram/plot/mode` references connect that event to
the existing public Scientific inspection and canonical Plot owners. The
restricted author configures those Builder references rather than reading
private endpoint strings. Dataset provenance and source guards are checked by
the Host bridge; the diagram remains the same canonical Document.

Diagram selection gives an explicitly declared junction dot precedence over
coincident wire endpoints in the Native2D picker's equal-distance scope order.
This makes the connection dot selectable without changing electrical identity,
wire routing or canonical Document order. Other stroke/point hits still use the
same Native2D geometry picker; a missed point set is an ordinary miss and cannot
invalidate selection of another curve in the same scope.

### Validated edits and History branch cancellation

The canonical diagram viewport calls the existing
`native2DGeometryDiagramEdit ... preview` mode before preparing a History branch.
Invalid properties therefore leave both the Document and its redo tail intact.
A subsequent commit repeats source/candidate validation after any confirmation.
Same-checkpoint branching retains native selection and keyboard focus. Native
keyboard command cancellation returns `status cancelled` rather than leaking an
expected confirmation refusal as a Tk background error. See
`NATIVE_2D_GEOMETRY_API_v1` and `SCIENTIFIC_RECIPE_API_v1` for the precise owner
contracts; ordinary Undo/Redo snapshot restoration is unchanged.

### Existing wire Properties and rapid routing (dev108; GAP039)

Select a wire stroke and use the same Properties command (or double-click in
Select mode). The native dialog provides typed Start/End terminal choices and
an ordered bend table. Select a row to read its X/Y fields. Add inserts after
the selected row, Replace updates it, Remove deletes it, and Move up/down change
its order. Without a selection Add appends. The buttons follow selection and
route-size limits; the scrollable body and wrapping button row remain usable at
the480x320 minimum size. Routes allow128 finite points within+/-1000000; initial
wire drawing retains its separate64 pending-point bound.

Apply commits one canonical `route` edit through the existing Document,
generation/revision/SHA and History owners. Close discards its draft. An external
edit while the dialog is open requires closing/reopening; Apply cannot silently
overwrite that changed source. Invalid candidates are refused before a History
branch, preserving its redo tail. Reconnection uses existing stable terminals,
retains the wire ID and creates no implicit geometric joins. Undo/Redo restore
the complete committed topology and bends. The optional existing Development
GUI test transport exposes only typed owned-dialog fields/actions, with no
author-supplied widget paths or payload commit.

Tk's second rapid click invokes Properties only in Select mode. With the wire
tool it reaches the ordinary routing transaction, so ending one wire and
starting another at the same junction cannot lose that second press to a
Properties popup. Other non-Select tools likewise retain their ordinary press.
