# Curve Viewer

Curve Viewer displays Dataset curves without editing or fitting them. Open it
from Viewers, choose **Add curve…**, select the Dataset's exact public ID and
X/Y variables, then add it. Repeating Add keeps existing curves. The browser
shows each Dataset ID, labels/units, exact row count and visibility.

Use Shift/Ctrl to select curves. **Fit selected**, **Fit all**, Show, Hide and
Remove from view affect only this view. Removing a curve does not delete its
Dataset. Wheel zooms around the pointer; dragging the canvas pans. **Dataset
Preview** reads exact source rows through the common paged Dataset Preview.

Display uses CORE's bounded native extrema sampling. A million-row Dataset
remains authoritative in its storage provider; the viewer holds a bounded proxy.
Nonfinite source gaps remain disconnected. The browser labels every source's
units; axes show its stored numeric coordinates without implicit conversion.

**Curve style…** uses shared typed color/opacity and width fields and can show a
native direction marker. **Grid / view…** opens the common Native2D grid,
background, aspect and experimental polar settings. These affect presentation,
never source coordinates. Polar pointer readout uses the shared CORE frame.

**Save view** and closing retain source requests/fingerprints, visibility/style,
direction markers, view and presentation in an Interactive Document. Reopening
reads sources again and rejects changed scientific bindings. Display-name and
axis-label catalog updates refresh without reloading scientific data.

Editing belongs to Curve Workbench; fitting belongs to Dataset Curve Fit.

**Export…** discovers enabled exporter providers through the shared Workbench
Extension API. The installable Native2D Presentation Export provider offers PNG
with an image-scale field and vector SVG. Both consume the shared Native2D
presentation snapshot, including clipping, curve style, grid, direction and
labels and the same styled curve legend. Axis titles use source labels/units;
mixed bindings/units are stated explicitly and remain visible in the curve
table. Native spline presentation is sampled and reduced inside CORE, with
bounded buffers and preserved gaps. Export creates the chosen file and reports its hash; existing files
are rejected. Formats and parameter fields belong to the provider descriptor.

## Family selection, editable filters and named Workspaces

Add curve shows CORE schema-backed categorical selectors when semantic roles are
present. Choose one or several exact members, or All members as separate curves.
Complete family discovery defaults to independent member curves; members are
never joined. Labels retain member Variable ID/value. Several family axes require
an explicit manual binding; a column name alone never selects a family. Discovery
is bounded; incomplete value lists require an explicit choice. Up to16 separate
curves may be requested at once. Numeric int64 and text member IDs stay exact.

**Point filters / manual binding** opens optional controls for Variable ID,
predicate/value/range, saved Dataset Selection and manual rank-one family ID.
Filters combine with AND through CORE Curve Source/Transform. Numeric finite
predicates and typed equality/range/set operators follow the public contracts.
Use **Source filters…** on one existing curve to inspect/change its request;
clear point filters or its saved Selection to remove those constraints. Applying
an edited curve retains its logical ID, presentation/visibility and independent
family binding. Select one member when editing; Add handles multiple members.
Invalid requests/cancellation preserve the existing view and canonical Dataset.
The source list exposes exact row count and predicate count. Display reduction is
only a rendering proxy. Dataset Preview reads the normal authoritative Dataset.

**Publish Dataset…** is supplied by the independently packaged optional
Scientific Curve Dataset Publisher. Select one visible curve and supply a new
Dataset ID. Exact X/Y values, units, source-row continuity and provenance persist
independently of this view. **Export…** continues to export presentation PNG/SVG.

Workspace provides New/Open/Save/Duplicate/Rename/Close/Delete and the standard
Session Workspaces manager. Each Workspace is the existing provider-owned
Interactive Document with CORE ID/revision/name. Exact-ID opening cannot choose
another Workspace using the same Dataset. Legacy views remain available and can
be promoted with the same ID. All scientific requests/fingerprints, styles,
visibility, grid/view and family bindings persist. Notes/previews/portable backup
use the common CORE manager. Deleting a view preserves its source Datasets.
