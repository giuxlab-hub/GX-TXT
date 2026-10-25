# viewer.curve_workbench 2.21.18

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

DEV111-P012 requires the cumulative framework through P012 and its public
`GUI_UPDATE_SCHEDULER_API_v1`. Only wheel redraws adopt the opt-in CORE service;
Native zoom, normal editing timers and350ms view persistence remain unchanged.

DEV111-P013 requires the matching CORE native adapter shipped with the patch.
Existing shared grid/clipping calls use its C++ presentation batches automatically;
no Viewer-specific algorithm or switch is needed. P012 scheduling is unchanged.

DEV111-P014 uses the permanent CORE retained Cairo grid/axis presenter and native
control-position batches. CORE Appearance owns Low/Medium/Fast intensive profiles
and optional additional grid-density suppression. Help follows Workspace, using
the existing manual viewer and metadata-derived About version. Restart after
applying the cumulative patch; the matching compiled native adapter is required.


DEV111-P015 / 2.21.14 uses the public NATIVE2D_SPRITE_SCENE_API_v1 in normal
operation. Retained scientific curves, Dataset markers, defining controls and
arrows share one C++/Cairo presentation layer above the P014 grid. Scientific
picking, native edits, constraints, snapping, units, undo and publication retain
their existing owners. Context/highlight/gizmo widgets remain existing overlays.
Performance measurements and their limitations are recorded with the patch;
fewer Tk items do not by themselves establish shorter complete redraw times.


DEV111-P016 requires its matching CORE native binary and adapters. Direct native
scientific sprite synchronization is active; CORE CAD contexts coordinate existing
C selection/drag/control/constraint/component operations. Public contracts are
`docs/api/NATIVE2D_SPRITE_SCENE_API_v1.md` and
`docs/api/NATIVE2D_CAD_CONTROLLER_v1.md` in the framework. No other Viewer is migrated.

DEV111-P017 requires the matching native CORE History binary and public service.
The manual Workbench supplies scientific capture/restore and descriptive hooks;
CORE owns RAM History, asynchronous persistence/recovery and the shared controls.
No additional CAD migration is part of this patch. Final user GUI acceptance is
required before subsequent CAD development.

DEV111-P018 requires the cumulative CORE through P018. Common CAD interactions
use `native2DCadCanvasAttach` with the existing native scene/controller. Tool menus,
scientific unit/source admission, Workspace and P017 History remain unchanged in
ownership. See `docs/api/NATIVE2D_CAD_CANVAS_HOST_v1.md` in the framework and the
P018 functional report; another Viewer can embed the same host without importing
this module. No native binary rebuild is required by P018.

DEV111-P019 uses the same public CORE CAD Canvas advanced tools as independent
consumers. Existing scientific menus and workflows remain available; the shared
dimension editor resizes to show errors and the reference-measurement offer.
The accepted P018 cumulative framework is required before applying this patch.
