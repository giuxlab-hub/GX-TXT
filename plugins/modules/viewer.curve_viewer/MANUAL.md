# Curve Viewer

The Viewer groups actions in Sources, Curves, View, Export and Edit,
with the existing CORE Workspace menu last. All commands have stable configurable
CORE shortcut slots. Undo/Redo default to Ctrl+Z/Ctrl+Y; text editing retains its
normal keys. Central Modules configuration and local Configuration use the same
typed schema and User/Session scope. Automatic legend labels prefer real family
values, carry no invented units and distinguish colliding automatic names.
Manual labels may repeat; legend clicks resolve by Native2D object identity.
Right-click a legend item for its presentation label/style/show/hide/view/remove.
Scientific Dataset values, binding IDs and filtered publication stay canonical.

The compact Description/History strip uses CORE Scientific Recipe operations.
Undo/Redo commit the current cursor; historical browsing is read-only and retains
future steps. Restart here explicitly confirms discarding later local steps.
Workspace Clear History offers Cancel, reset or a protected external backup.
History records logical source collection, bindings, style and view changes;
redraw/progress/hover do not record steps. Selection is saved with meaningful
changes or explicit Save, rather than as an independent scientific operation.

Workspace display buffers are optional owned resources validated against source
identity, request/reduction, schema, Namespace, SHA and generation. Warm reopen
does not repeat exact source preparation. Invalid/missing buffers rebuild through
bounded, cancellable Curve Source jobs. Exact Preview/publication opens canonical
rows on demand. Cancelled opening preserves the saved Workspace; reopen to finish.
The OS title always comes from the authoritative active Workspace record.

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

**Save view** retains source requests/fingerprints, visibility/style,
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

## Shared Workspace manager

Use **Workspace → Session Workspaces…** for the common provider-scoped manager. The same controls appear in Session → Workspaces. Filter by name, type or actual provider; select a Workspace for preview, notes and available actions. New creates a named unsaved draft; Save commits it through the existing Document authority. Scientific edits retain the existing History/autosave behavior. New/Open/Duplicate/Close/Delete review remaining unsaved changes with Save, Discard or Cancel. Rename changes only the name and never silently saves an editor draft. Default unavailable actions are disabled.

Duplicate and Import create independent names and managed-resource owners. Export includes notes and nested resources. Delete confirms removal of the Workspace, notes, History and owned resources while preserving original and published Datasets. A stale Session, revision or deleted owner cannot be overwritten. Finish or cancel active source work before switching Workspaces. See the [shared Workspace controls and API](../../../docs/api/SESSION_WORKSPACE_API_v1.md).

## User Manual

**Help → User Manual…** or **F1** opens this Viewer's own nonmodal rendered manual window. Find, scrolling, links and Back/Forward operate independently from other Viewer manuals. Repeated F1 raises this manual; closing it leaves the scientific Workspace unchanged. The main GX-TXT Help page remains available separately.
