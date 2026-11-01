# NATIVE2D_API_v1

SPDX-License-Identifier: GPL-3.0-or-later

Native2D C remains the scientific geometry, constraint, coordinate and snapping
authority. `native2DCadApiInfo` reports the installed native capabilities and
additive managed host operations. No raw native address is a public Tcl handle.

The existing contracts remain authoritative:

- [CAD controller](NATIVE2D_CAD_CONTROLLER_v1.md): scientific object/component
  references, selection, native manipulation transactions and relationships.
- [Embedded Canvas](NATIVE2D_CAD_CANVAS_HOST_v1.md): pointer/keyboard routing,
  admission, preview, commit/cancel and independently chosen GUI placement.
- [Advanced tools](NATIVE2D_ADVANCED_CAD_TOOLS_v1.md): exact construction,
  defining controls, topology and native constraint/dimension workflows.
- [Relationships](NATIVE2D_CAD_TOOLS_RELATIONSHIPS_v1.md): scientific relationship
  identity and shared presentation/editor ownership.
- [Retained sprites](NATIVE2D_SPRITE_SCENE_API_v1.md): native scientific references,
  selective synchronization, hit testing and existing Cairo presentation.

## Managed Sketch and contextual actions (P020)

`nativeCadSketchCreate parent ?options?` returns a managed component with an
editable plane inside one existing Native3D Canvas. The caller chooses the
parent. Exact definitions and P017 History use an existing Interactive Document;
the Native3D plane-frame service owns local/world conversion. Working units must
be length units. No new geometry engine, canonical store or History stack is
introduced. See [full Sketch contract](NATIVE_CAD_SKETCH_P020.md).

`native2DCadActions`, `native2DCadActionState sketch action` and
`native2DCadActionInvoke sketch action` expose the current common action catalog,
its authoritative enabled/selected facts and finite invocation. Menus, external
palettes and Canvas-owned ViewportHost controls use those same facts and the
existing shared icon catalog. The catalog is an admitted GUI action surface;
the underlying advanced controller retains its broader documented native API.

The restricted Viewer SDK declares `NATIVE2D_API_v1@1` and explicitly requests
`cad_sketch_create`, `cad_sketch_command` and `cad_sketch_state`. A Builder
`cad_sketch` component owns the managed instance; `Host::cad_command(component,
action)` invokes it without exposing Tk paths or scientific memory addresses.

## Single Native3D Canvas (P021)

[Surface integration](NATIVE_CAD_SURFACE_P021.md) borrows an existing Native3D
Canvas; the default factory creates one ordinary Native3D component. Shared
CAD tools, retained transparent presentation and native camera receipts operate
on that same Canvas. The P020 mirror is no longer an update path. The existing
`world_scene` method remains an explicit bounded compatibility snapshot only.
