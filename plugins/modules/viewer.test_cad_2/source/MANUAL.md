# TEST CAD 2

This is a TEST Viewer, authored through public Viewer Interface Builder and
Viewer Development C++17. It is a reusable CAD integration consumer, not a
finished scientific production application. Canvas-owned contextual menu and built-in tool controls
use the same public CORE CAD actions and selected/enabled state.
The independent **TEST Viewer action** increments its C++ display counter.

## One viewport

Draw and edit directly on the active scientific working plane inside the
Native3D viewport. The grid, geometry, previews, defining controls, selection,
constraints and dimensions form a transparent editing layer over the existing
3D background. There is no mandatory second planar editor or continuously
mirrored scientific scene. Native2D retains exact planar geometry and the
constraint solver; Native3D retains camera and 3D rendering authority.
The working coordinates start in millimetres on the XY plane.

Click the admitted construction tool, then its defining positions in the
viewport. Supported CORE tools include points, lines, paths, polylines, native
splines, rectangles, circles/arcs, ellipses and quadratic/cubic Bezier curves.
Use **Finish** for a valid multi-step definition or to leave a completed
construction tool. A rejected incomplete definition reports its reason and
remains available for correction. **Cancel** or Escape abandons only the active
uncommitted proposal. Select existing geometry to inspect or edit its defining
controls; selection-dependent commands are disabled without compatible targets.

Use the wheel to zoom. Hold Space or Alt while dragging to orbit the camera;
hold Shift as well to pan. The shared **Pan** tool pans, and **Fit** frames the
Sketch. The Navigation Cube remains native 3D camera chrome. Geometry input is
admitted only against a current camera/working-plane frame.

## Editing and scientific state

Translate, rotate and edit eligible selected geometry using the shared tools.
Join points, Join Path, Compound, Split and Separate retain their distinct native
semantics. A constituent may require Split or Separate before independent
editing; the Viewer does not fabricate unsupported direct Compound edits.

Constraint and dimension commands use the existing solver, unit rules and
relationship inspectors. Unsupported or incompatible combinations are rejected.
Driving numerical values are scientific parameters; annotation placement is
presentation. Underlying dimensions and constraints remain native definitions.

**Undo** and **Redo** navigate authoritative CORE History. **Save** stores the
Sketch Document; Workspace Save retains its association and interface state.
Reopen that Workspace to restore the saved Sketch. Finish or cancel an active
construction before closing. Starting a new Workspace creates a separate Sketch;
closing a Viewer is not a command to erase its scientific Document.

## Package and diagnostics

The package includes its exact Builder design, C++ source, admitted SDK, binary
and genuine build/export receipts. Version 1.0.1 updates Help and package metadata
for the shared single-viewport CORE integration. It does not replace its C++
controller or install a private Tk/CAD engine. Installed opening never compiles.
Help uses the ordinary GX-TXT documentation viewer.

Rendering uses the normal Configuration graphics policy. If a device produces
incorrect native 3D colors, report the actual backend/device and use the existing
explicit Software execution option for a diagnostic comparison; this Viewer does
not silently force a renderer or claim a hardware-driver correction.
