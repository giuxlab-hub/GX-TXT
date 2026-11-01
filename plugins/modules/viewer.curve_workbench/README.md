# Curve Workbench

SPDX-License-Identifier: GPL-3.0-or-later

Scientific Curve Workbench with exact source bindings, independent physical
axis declarations, compatible display conversions and retained geometry/history.
Original Datasets stay unchanged; public CORE owns units, storage and numerical
geometry. Coordinate controls show independent display units and preserve native
constraint/parameter meaning. New scientific point curves preserve explicit meaning and provenance.

See [MANUAL.md](MANUAL.md), [CHANGELOG.md](CHANGELOG.md) and
[TEST_RESULTS.md](TEST_RESULTS.md). Install this normal module package through
the existing Plugin Manager; dependencies and public API entrypoints are declared
in module.ini.

The primary **Workspace** menu uses the shared Host for New/Open/Save/Duplicate/
Rename/Manager/Close/Delete/Notes/Preview/Import/Export/Refresh. New includes the
physical coordinate Configuration form and starts an unsaved draft. Save or
Ctrl+s projects accepted native History into its stable native Workspace.
Provider-specific drawing, Configuration, image and scientific export controls
remain available in the same menu and existing toolbars.

**Clear History…** preserves the current science and named archives. Cancel
changes nothing. No on an unsaved draft resets its existing journal without
creating a saved Workspace. Yes selects a protected-backup destination, saves
and binds that draft through the shared Host, exports the backup, then clears.
Owner/session/revision changes and backup failures are reported explicitly.

CORE uses the retained Cairo grid/axis presenter and native
control-position batches. CORE Appearance owns Low/Medium/Fast intensive profiles
and optional additional grid-density suppression. Help follows Workspace, using
the existing manual viewer and metadata-derived About information. The matching
compiled CORE adapters are part of the distribution.


Retained scientific curves, Dataset markers, defining controls and arrows use
the public `NATIVE2D_SPRITE_SCENE_API_v1` and share one C++/Cairo presentation
layer above the retained grid. Scientific
picking, native edits, constraints, snapping, units, undo and publication retain
their existing owners. Context/highlight/gizmo widgets remain existing overlays.
The rendering layer does not redefine scientific picking or topology.


Direct native scientific sprite synchronization is active; CORE CAD contexts coordinate existing
C selection/drag/control/constraint/component operations. Public contracts are
`docs/api/NATIVE2D_SPRITE_SCENE_API_v1.md` and
`docs/api/NATIVE2D_CAD_CONTROLLER_v1.md` in the framework.

The Workbench supplies scientific capture/restore and descriptive hooks;
CORE owns RAM History, asynchronous persistence/recovery and the shared controls.
Explicit Save waits for durability and complete Workspace projection. Save
History As retains a complete named workflow; Named History inspects or explicitly
restores it. The module supplies no second History store.

Common CAD interactions use `native2DCadCanvasAttach` with the existing native
scene/controller. Tool menus,
scientific unit/source admission, Workspace and native History retain their
ownership. See `docs/api/NATIVE2D_CAD_CANVAS_HOST_v1.md` in the framework;
another Viewer can embed the same host without importing
this module.

The Workbench uses the same public CORE CAD Canvas advanced tools as independent
consumers. Existing scientific menus and workflows remain available; the shared
dimension editor resizes to show errors and the reference-measurement offer.
Dependencies and public entrypoints are declared in module.ini. Package history
belongs in CHANGELOG.md. Wheel redraw uses GUI_UPDATE_SCHEDULER_API_v1; normal
native zoom, editing and view checkpoint ownership remain unchanged.
