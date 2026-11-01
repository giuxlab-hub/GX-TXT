# Managed CAD Sketch in NATIVE2D_API_v1

> P021 changes the display integration to a single Native3D Canvas. See
> [the current surface contract](NATIVE_CAD_SURFACE_P021.md). The older dual-pane
> description below records the original P020 contract; it does not describe
> the normal P021 display path. `world_scene` remains explicit compatibility
> sampling, while normal updates use `presentation_scene` without geometry.


`::GX::nativeCadSketchCreate parent ?options?` creates one managed TclOO
component in an existing Tk parent. The return value is the managed object;
`$sketch widget` returns its root frame. The caller places that frame.
The normal framework bootstrap loads `core/tcl/native_cad_sketch_v1.tcl`.
`nativeCadSketchApiInfo` describes this additive host surface in the established
NATIVE2D_API_v1 family. No new numerical API, renderer, registry or History store
is introduced.

Options are a dictionary:

| Key | Default | Meaning |
| --- | --- | --- |
| document_id | new | Create a Sketch Interactive Document, or reopen an existing Sketch ID. |
| working_unit | mm | Physical length unit admitted by the existing unit registry. |
| plane | origin {0 0 0} normal {0 0 1} u_axis {1 0 0} | Oriented physical frame, validated/normalized by Native3D plane_frame. |
| presentation | canvas | Host presentation identity, `canvas` or `viewer`; both include the exact local editor and actual interactive Native3D context. |
| changed_command | empty | Trusted host command prefix; receives one bounded public state dictionary after a coalesced GUI update. |
| recovery_choice | unset | Existing P017 recovery policy: recover, saved or cancel. |

Opening an existing Document retains its saved unit and plane. Invalid units,
degenerate planes, mismatched Document formats, replaced generations, changed
external revisions and stale Session scopes raise errors. These command prefixes
are trusted framework host contracts; they do not grant author Script/SDK Tcl
execution.

`get` accepts `widget`, `host`, `context`, `advanced`, `scene`, `document_id`,
`plane`, `working_unit`, `history_context`, `viewport`, and `model`. `host` is
the existing native2DCadCanvas managed Host; `advanced` is that Host's P019
Advanced object. A fresh `get advanced` is required after History hydration;
old native controls/selection references cannot be reused across that boundary.
Scientific tests and trusted host code can inspect the exact model explicitly
with `get model` or `capture`. `state` is a bounded live identity/summary and
does not capture or serialize geometry or accumulated History. It includes
document_id, revision, generation, session_token, working_unit, plane,
object_map, relationship_map, host/advanced state, history_context, native
History status, viewport, presentation, status and renderer_error. Asynchronous
renderer errors appear in both the context viewport and the component status.

`command action` and `invoke action` accept only the finite identifiers returned
by `actions`. They include exact construction families, selection/transforms,
control editing through the shared Canvas, join_points, join_path, compound,
separate, split_path, split_composition, geometric constraints, graphical
dimension, finish, cancel, fit, undo, redo and save. The return is an action/status/
Document receipt. Numeric construction/control/relationship/topology operations
remain the existing Host.Advanced contracts, accessible through `get advanced`;
this component does not implement a second controller or solver.
Topology retains source geometry according to the existing native construction
contract and selects the newly created output. It does not silently remove the
source definitions or their relationships.
The finite point-join action uses the existing native point-index conversion
and a coincidence tolerance of1e-8 working units. Finite split actions choose
the first interior boundary (index1); Host.Advanced accepts an explicit index
for other boundaries. Family-aware enablement excludes invalid split targets.

The same action descriptors, enablement and selection state drive all three
combinable presentations:

* `$sketch menu menuPath`: grouped native menus for a Viewer menu bar.
* `$sketch palette parent`: external notebook palette; the caller places it.
* `$sketch canvasControls ?parent?`: the existing ViewportHost places a collapsible
  Sketch tools panel inside the local Canvas. The return value is its managed
  body; callers must not repack or reparent it. An optional parent must be the
  Sketch root or its existing local Canvas container. Use `palette` for external
  Viewer-selected placement. Icon-only common actions include Undo, Redo and
  Save, with accessible tooltips; **All CAD actions…** and Canvas right-click
  expose the same full grouped command catalog and enabled/selected state.

`present menu|palette|canvas parent` is equivalent. ViewerCommands owns command
dispatch, bindings, menus and button states. Palette icons are admitted from
viewerGuiIconCatalog and presented with uiFieldIconApply. No separate stock
catalog or private presentation controller is used. `actionState action` returns
label, icon, group, enabled and checked facts. Selected defining controls support
direct editing with the existing shared Canvas interaction behavior.

Exact definitions, constituent identities/directions, geometry roles, identity
attributes and logical relationship identities are saved in the existing
Interactive Document (`core.native2d` / `sketch`,
`gxtxt.native_cad_sketch.v1`). Native scene IDs are process-local; stable logical
IDs map to each hydrated scene. Logical allocation counters remain monotonic
across local Undo/Redo. Exact hydration validates a staged candidate, appends all
restored owners before removing prior ones, and retains the native scene's
monotonic ID allocator. Old raw controls therefore cannot alias restored IDs.
CORE P017 owns every timeline operation. Each edit submits
a patch containing only changed `object/sN` or `relationship/rN` entries and
deleted-entry sentinels. Normal editing never serializes the accumulated History.
Save/close flush the existing CORE context; reopen restores exact definitions and
relationships. Preview objects are excluded from all scientific captures.

`transform to_world|to_plane points` returns the existing Native3D plane_frame
receipt with normalized origin/normal/u_axis/v_axis, mapped XYZ points,
working_unit and owner. Local XY points receive an explicit zero plane-normal
coordinate. `local_to_device|device_to_local` use the existing Native2D scene's
device/world transforms. These two receipts distinguish local scientific XY,
oriented world XYZ and device pixels. The display uses those same transforms.

`world_scene` supplies a bounded Native3D scene with sampled world polylines.
Its canonical source remains the exact Native2D definitions. Sampling is an
explicit visual policy (129 uniform-parameter points per exact constituent,
at most4096 constituents); Compound gaps are separate lines and points use
actual vertex cells. Existing native composition_part bakes each parent's affine
frame into the display constituent. Dynamic previews
appear in the context viewport but never in the Document. The public Native3D
binding is `{kind cad_sketch sketch MANAGED_OBJECT}` and admits only actual
managed component handles. This requires MAIN1's additive Native3D v2 binding
and point/line-cell adapter support. The transient bounded projection cache
coalesces updates and returns `display_pending 1` during an in-flight physical
frame mapping. It does not duplicate exact science or History. This avoids
reentrant requests through the existing synchronous Native3D geometry worker.
Native3D controls retain normal orbit/pan/zoom and preserve camera state on edits;
scientific edits use the shared local-plane surface. No private 3D hit mapping is
claimed.

Legacy Workbench3D exposes the finite `sketch_create`, `sketch_open` and
`sketch_close` guiCommand/guiForm routes. Create copies its actual working plane
and unit; open optionally accepts `{document_id ID}` for a Sketch already
associated with that Workbench Document. The association is an ordinary patch in
the original Workbench P017 context. Each exact Sketch uses its own existing CORE
context and Interactive Document. Closing the Workbench closes its Sketch window.
The Workbench bridge imports no CurveWorkbench private implementation.
