# Workbench Path and Dataset namespace UI — dev-060

For current Session/Dataset navigation, square grid defaults and Spline arms
inside a Path, see the [dev-063 UI guide](SESSION_DATASET_GRID_dev063.md).

## Curve Workbench

The arrow glyph in the compact icon toolbar above the canvas activates Select.
The adjacent four-way glyph activates Transform/Pivot. Right-click Select to choose its
selection mode; Ctrl adds objects and Shift subtracts them. The tool keeps the
existing object, handle, canvas region and context-menu selection behavior.
Right-click Transform/Pivot for Translate or Rotate; drag the gizmo center to
place a custom pivot. In dev-062 the tool can be activated without selected
geometry. Click empty canvas to place its pivot, then choose a curve to
transform around the retained pivot.

Select endpoint-connected retained objects, then press `j` or choose **Modify →
Join Path…**. The normal result is one logical Path in the object list, even
when its exact constituents include Polyline, Spline, Bézier, Arc or other
supported open primitives. Join requires one unbranched endpoint-connected
traversal within the reviewed tolerance. It consumes the selected top-level
objects; Undo restores them. Internal endpoint coincidence constraints are
represented by the resulting Path junctions, and Undo restores those relations.
A constraint that also refers to geometry outside the selection blocks Join so
its target cannot silently change. Unsupported topology is rejected without
changing the source objects. **Combine / Compound…** (`Shift+j`) retains
independent objects when a single traversal is not truthful.

Drawing onto a compatible retained endpoint automatically forms a Path when
the topology supports one traversal; manual Join is optional. The Path stores
exact Native2D constituent definitions. Display sampling does not replace its
retained geometry. Inspect it as one object and directly drag its internal
line/polyline vertices, spline knots or other defining controls in Select.
The defining-handle table supports the same numeric X/Y edits. Shared junction
controls update the incident leaves together. **Separate exact constituents**
creates independent exact copies while keeping the Path; **Split** divides a
heterogeneous Path at a reviewed constituent junction. Neither is required to
edit a Path's defining controls.

## Dataset page

The right-side namespace tree has separate highlight and active-Dataset states.
Click a Dataset row to browse or highlight it; right-click to open its menu.
Neither action changes the Dataset used by the main Dataset/Variables page.
Click the small arrow glyph on that Dataset row, or choose **Activate Dataset**
from its context menu, to change the active Dataset explicitly.

Right-click a namespace and choose **Create namespace…** to create an empty
namespace, including one with no Dataset. Right-click a Dataset to **Move to
namespace…** or **Create namespace and move…**. Moving changes only its
organizational placement: the canonical Dataset ID, values, metadata and
provenance stay under their existing authorities.

The pictographic tree button above **Current namespace** opens the namespace
manager. Its hierarchy shows each namespace and its member Datasets. Create a
namespace, select one as current, or select a Dataset and move it to a chosen
namespace. You can also drag a Dataset row onto a namespace row. The move is
committed through the same Dataset Namespace API as the context menu.

## Session page without a Session

The Session tab and Workspace area may be opened before any Session is open.
They show the empty/no-Session state. Open or create a Session before using a
workspace operation that needs a Session Document.
