# Native2D Presentation Export 1.0.1

This installable provider offers Export PNG and Export SVG through the shared
Workbench Extension API. It renders a Native2D presentation snapshot, including
viewport clipping, source curve style, background, Cartesian or polar grid,
direction markers, labels and units. SVG contains vector paths and text, with
no embedded raster image. PNG uses Cairo and its standard font support.

Image scale controls PNG pixel resolution. Export creates the chosen file and
reports its SHA-256; an existing file is rejected. Export never changes a
source Dataset or Workbench geometry. The snapshot's bounded display sampling
policy is returned in the receipt and does not constitute scientific export.

The provider can be installed, disabled or removed through Plugin Install and
the Modules browser. A viewer discovers compatible exporter actions; it does
not define the available formats itself. Runtime requirements are Python 3,
Python Tk's Tcl list decoder, and Python Cairo for PNG.

Version 1.0.1 preserves centered text anchors, compound-part direction markers
and optional explicit `point_markers` in the shared snapshot. A host can supply
actual source/control points separately from sampled curve paths, avoiding markers
that would falsely identify every display sample as a scientific source point.
Workbench supplies its visible palette, visibility and display style along with
converted axis/tick labels; these do not change Native or Dataset coordinates.
