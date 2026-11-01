# GX-TXT dev-069 — selection and Spline construction corrections

All requested corrections are delivered from immutable published dev-068.
Workbench 2.11.4 and Curve Fit 0.3.12 share the identical updated CORE adapter;
Curve Fit changes only shared adapter/version metadata, with no fitting/UI changes.

Spline now participates in the same attached-end dispatch as Path/Polyline.
Endpoint, junction, straight-interior and Spline-interior attachments end the
current transaction while the tool stays ready for another independent Spline.
Existing Native coincidence, point-on-line/curve and retained composition enforce
the connections. No separate connection engine or conversion into polylines.

Local Geometry is the new default canvas Select target. Controls/points remain
explicit targets; Rectangle and Circle are atomic primitives. Straight Path edges,
standalone exact Spline spans and composed exact constituents retain distinct
Native semantic references. Spline-span hits reuse exact cubic-piece evaluation
and the existing closest-point kernel. Two selected controls do not imply a segment.
The existing Select button right-click menu chooses Local Geometry or Entire Curve /
Path; its checked choice, tooltip and shared readout identify the mode. New Workbench
interactions start Local. Ctrl adds and Shift subtracts in both modes. The left-list
Select action explicitly adopts a whole-object reference even for an already Active
row. Property focus alone is not selection. Whole objects now receive distinct
visible feedback using the existing Native presentation snapshot. The baseline
Circle circumference already entered the semantic set but lacked this feedback.
Graphical rectangle/polygon selection explicitly selects whole logical owners.
Explicit annotation/marker targets keep their own interactions; broad overlay hit
bounds do not steal a geometry click. Existing menus, controls and layout are retained.

CORE owns targeting/geometry/selection. Existing pick/region APIs gain optional
`target` through Tcl and Python/Octave; omitted target preserves legacy detail
behavior. Additive C policy queries preserve old signatures and POD layouts.
Existing reference/selection persistence carries new Spline spans, with no schema
or Dataset changes. No new Dataset type, publication workflow or conversion.

Actual keyboard/mouse input on normal local Linux XFCE/Xorg :1, giu, seat0/tty2,
Remote=no tested circumference/list Select, Rectangle/controls, individual straight
and Spline spans/constituents, both modes, modifier selection, graphical whole-object
selection, straight/Spline endpoints/junctions/interiors, next-Spline readiness and
connection-preserving control edits. Circle diameter, Arc radius, cross-Path two-point
dimensions and constituent parallel constraints remain usable. Fresh GUI processes
restore exact definitions, logical identities, units and relationships. Installed
runtime repeats focused acceptance. Screenshots are inspected and controller logs
are empty. Only disposable Sessions and isolated XDG state are written. No remote X11,
forwarding or VcXsrv. 25 Native compatibility fixtures, focused native selection/
reference/attachment tests and Python/Octave target/attachment checks also pass.

Earlier harness attempts (initial canvas focus, hidden utility panel, assuming
Circle D meant radius rather than its established diameter default, and nested
composition-part field access) are diagnostic; complete successful journeys are
the acceptance evidence. Coverage is the requested behavior and necessary compatibility,
not a framework-wide GUI campaign. No requested item remains unresolved.

Affected product files are listed in ACCEPTANCE_dev069.json: four Workbench routing/
command/presentation files; Native header, interaction/collections/render adapters;
CORE public Bridge target forwarding; release/module metadata and three matching
native binaries. Existing geometry/constraints/parameter/scientific publication and
Session recovery authorities remain. Dev-068 and earlier artifacts are immutable.
Ordered framework/plugin pairs, active/alias/restore and package checksums match.
