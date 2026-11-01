# NATIVE2D_GRID_PRESENTER_API_v1

Permanent trusted GUI-host CORE API, introduced in DEV111-P014. The matching
`gx2dtcl.so` advertises `retained_cairo_grid`. The standard bootstrap loads the
host adapter; `workbenchExtensionCoreApis` discovers
`::GX::native2DGridPresenterApiInfo`. No worker-side Tk or C++ SDK GUI grant is
implied. This is an existing-Canvas presenter, not a Viewer/plugin/scene manager.

## Public operations

All operations below are under `::GX` and use an existing Tk Canvas path.

| Signature | Contract |
|---|---|
| `native2DGridPresenterCreate canvas ?changed?` | Create/retrieve the one owned native C++ object; return its interpreter-local command handle. Optional no-argument command prefix requests an owning Viewer update. Omitting it preserves an existing callback. |
| `native2DGridPresenterBegin canvas ?changed?` | Begin a graphical frame, retain the native grid and owned control items, remove transient Canvas items. Return native item ID. |
| `native2DGridPresenterUpdate canvas scene plans ?options?` | Synchronously prepare the native grid/axis picture for the current scene and complete X/Y scientific plans. Does not execute an input operation or mutate geometry. |
| `native2DGridPresenterControls canvas scene object selected color` | Batch the existing native defining controls into retained Tk rectangles. `selected` contains actual native control indices; `color` is the existing outline color. |
| `native2DGridPresenterEnd canvas` | Retire owned control items not touched in this frame, including deleted/hidden/replaced objects. |
| `native2DGridPresenterConfigure canvas density` | Per-instance density override: `global` (default), or Tcl boolean. Invalidate and request its owner callback. |
| `native2DGridPresenterInvalidate canvas` | Mark native state dirty and request the registered owner callback. No second timer or hidden scientific recomputation. |
| `native2DGridPresenterDescribe canvas` | Native renderer identity, update/render/cache/control counters, item ID, dirty/density state, current presentation, selected native grid lines and native label anchor positions. |
| `native2DGridPresenterPosition canvas updates` | Batch Canvas positioning through native code. Records are `{itemId coordinateList}`; finite XY pairs, at most65,536records, for caller-owned unmanaged items. Presentation only; the caller retains scientific authority. |
| `native2DGridPresenterDispose canvas` | Idempotently unsubscribe and release the native command, pixmap/glyph cache and all owned Canvas items. Canvas destruction also performs disposal. |

Each adopted frame pairs Begin/Controls/End. Update may be skipped only if the
caller knows the grid/axes are unchanged; normal use calls it each frame and lets
the native cache decide. Reserved `native_grid_presenter` / `native_batch_item`
tags and native-owned control IDs belong to CORE. Do not delete/manipulate owned
items individually. A whole-Canvas replacement is recovered on the next Begin.
Dispose before abandoning an existing Canvas; automatic destruction is fallback.

`plans` is the existing authoritative X/Y plan dictionary. Each axis supplies
`ticks` (`value` in native coordinates and the already formatted `label`) and
`label` (complete title including unit/engineering multiplier). Other plan fields,
including lower/upper and verified physical-unit presentation, remain in the
retained public description. At most64ticks per axis, finite values and bounded
labels. C++ performs no independent unit selection, conversion or number formatting.

Options: `background`, `text_color` (existing composed RGB values) and `font`
(default `TkSmallCaptionFont`). Defaults use the existing UI Field color owner.
The adapter supplies actual font attributes/metrics, authoritative text RGBA and
CORE density policy. Normal Workbench plans come from its unchanged coordinate
presentation service. Future Viewers may use the existing CORE axis planner.

## C++ implementation and rendering

`gx2d_grid_presenter_v1.cpp/.h` implements a stateful object with a public Tk
custom Canvas item (`gx2dgrid`). One retained item copies a complete Cairo-rendered
pixmap into Tk's existing Canvas drawable. It remains below scientific objects;
it is disabled for input picking. No grid line, graduation or numerical/axis-label
Tk Canvas item is constructed. Overlay frames, selection, native gizmos, direction
arrows, Plot residuals and remaining scientific Tk objects retain their owners.

C++ calls unchanged `gx2d_grid_render` through P013's shared density filter and
uses existing device conversion/clipping. Authored grid state, snapping and all
geometry remain in the C engine. CORE does not modify that engine or algorithm.
Axis values, units and label contents arrive through the public host boundary.
Cairo paints strokes and composites glyph coverage obtained from the established
Native2D `text_photo` service, preserving Tk's font/layout authority. Temporary
coverage photos are released; the bounded glyph cache is native-owned.

The scene device dimensions must match the Canvas viewport.
The cache key covers effective view/bounds/margins, grid state/styles, coordinate
mode/polar frame, supplied plans/labels/units, composed colors, actual font state
and density policy. An unchanged view reuses the prepared native pixels. Font or
unit changes invalidate the relevant presentation. The object stores no raw scene
pointer between calls; Update/Controls receive the current scene through the
existing CORE adapter, avoiding a stale native-scene owner after Session changes.

Controls use existing `gx2d_sketch_controls` and `gx2d_world_to_device`, retaining
and repositioning Tk objects instead of rebuilding them. Existing stroke-inset
rectangle clipping is preserved; selected fill and draw order follow the host's
scientific selection state. Begin/End removes stale membership. Generic Position
batches support other caller-owned Tk presentation, with no geometry transaction
or scientific input interpretation.

## CORE policy and scheduling

Persistent user fields in Configuration -> Appearance:

| Field | Default | Meaning |
|---|---|---|
| `ui.graphics_profile` | `Low` | Intensive-update maximum: Low5FPS/200ms, Medium10FPS/100ms, Fast20FPS/50ms. |
| `ui.adaptive_grid_density` |1| Enable the additional16pixel suppression. Disabling it preserves the grid engine's own adaptive generation and authored/snap spacing. |

Settings apply to opted-in consumers after Save; normal isolated input and final
synchronization are unchanged. Scheduler Create/Configure option `profile global`
subscribes to the CORE limit. `profile custom` remains the backwards-compatible
default for independent policies. See GUI_UPDATE_SCHEDULER_API_v1.md.

The presenter has no independent redraw loop. Its changed callback should request
the existing GUI scheduler; that callback renders the latest scientific state.
The scheduler knows nothing about grid or input devices. Curve Workbench adopts
the global profile for wheel/pan/resize/viewport requests and uses this native
presenter immediately after extraction/restart. Pan release finishes pending work.
Point editing and geometric transactions retain their original interaction owners.

## Adoption example

```tcl
set scheduler [::GX::guiUpdateSchedulerCreate $canvas \
    [list ::MyViewer::drawLatest $view] \
    {policy adaptive profile global normal_ms 16}]
::GX::native2DGridPresenterCreate $canvas \
    [list ::GX::guiUpdateSchedulerRequest $scheduler]

# In the Viewer-owned callback, after processing every accepted model change:
::GX::native2DGridPresenterBegin $canvas
set plans [::GX::native2DAxisPlans $scene]
# Supply complete titles/units from the Viewer's existing scientific owner.
dict set plans x label [::MyViewer::axisTitle $view x]
dict set plans y label [::MyViewer::axisTitle $view y]
::GX::native2DGridPresenterUpdate $canvas $scene $plans
# Present scientific objects, optionally using Controls/Position batches.
::GX::native2DGridPresenterEnd $canvas
# On owner replacement/close:
::GX::guiUpdateSchedulerDispose $scheduler
::GX::native2DGridPresenterDispose $canvas
```

## Build, scope and limits

The existing CMake `gx2dtcl` target includes the new C++ source and matching header;
P014 ships the compiled Linux x86-64 library plus source/build/Tcl integration.
Existing Tcl/Tk8.6, Cairo and X11 dependencies remain. A restart is required to
load the new binary. No extra plugin, alternative event loop or background Tk
thread is introduced. Unrelated production Viewers are not migrated.

Cairo/Tk stroke rasterization and glyph compositing can differ at pixel edges;
scientific coordinates, label contents, unit choice and intended anchors remain
unchanged. Native grid snapshots/exports continue through their existing public
owners; this custom item is not a new scientific export format. Full scientific
object sampling and transient overlays still cost time. Performance is workload-
dependent: consult the measured P014 report rather than assuming a blanket speedup.
