# Curve Workbench

<a id="workbench-2112-gx-txt-dev-067"></a>
## Continuous placement and protected restore

Spline instructions appear once beside live coordinates. Click an existing
line/branch defining point to finish the current Path placement; the tool stays
ready for another Path until Escape. Compatible Workspaces without a CAD
block reopen normally. If restoration genuinely fails, the original saved
Workspace remains protected and the status shows its cause.

<a id="workbench-2110-gx-txt-dev-065"></a>
## Branched paths and parameters

Paths retain branched networks and shared junctions. Click an existing defining
point while drawing to connect automatically. Select exact internal segments with
Ctrl and use Constraints or the canvas right-click menu. Spline knots expose both
available tangent arms. Separate is not needed for these operations.

Parameters... opens the framework editor for this Workspace. Create `span` with
formula `session.base * 3`, then enter `span` in a dimensional constraint. Formula
changes recalculate geometry and save in the canonical Workspace. Session Parameters
is managed in the Session page dropdown. Workspace Actions invokes this same editor.
Core documentation: `docs/api/CORE_PARAMETER_SERVICE_v1.md` and
`docs/api/NATIVE2D_NETWORK_dev065.md` in the installed framework.

<a id="curve-workbench--dev-063-square-grid-and-path-spline-arms"></a>
## Square grid and Path Spline arms

A new Workspace opens with a visible grid and equal X/Y visual scale. The
initial vertical extent is 20 grid units, with extra horizontal room adapted
to the canvas. The operation indicator and live coordinates share one row.
Grid spacing/appearance are in Grid / view; coordinate aspect overrides are
reserved for module/host APIs.

In Select, click an interior Spline knot to display its incoming and outgoing
arms. Drag either arm to edit the exact retained shape. This works identically
for a standalone Spline and a Spline inside a composed Path. The Path stays one
object; Separate is unnecessary. Endpoint knots expose only their existing side.
See the [Session/Dataset navigation guide](../../../docs/guides/SESSION_DATASET_GRID_dev063.md).

<a id="curve-workbench--dev-062-pivot-and-editable-path"></a>
## Pivot and editable Path

Activate Transform/Pivot even with no selected curves. Click empty canvas to
place the pivot, or drag the gizmo center. Select the intended curve afterward;
the placed custom pivot remains the Workbench transform state.

Draw a Line/Polyline or Spline from a compatible retained endpoint. Finishing
the new stroke automatically forms one logical Path in the object list. In
Select mode, drag any displayed constituent vertex/control directly, or select
its defining-handle row and apply X/Y. Shared Path junctions remain connected.
Exact primitive definitions stay authoritative; Separate is optional for
making independent copies, not required for editing a Path.

<a id="curve-workbench--dev-061-icon-placement"></a>
## Viewport tool placement

Select and Transform/Pivot appear in the compact pictographic toolbar directly
above the canvas. Left-click activates the existing tool; right-click Select
chooses a selection mode and right-click Transform/Pivot chooses Translate or
Rotate. The upper mixed command and sketch bars have no duplicate buttons.

<a id="curve-workbench--dev-060-path-and-selection-correction"></a>
## Path and selection

The main and sketch toolbars use the shared arrow glyph for Select. The main
glyph's right-click menu chooses selection mode. Join Path (`j`) consumes a
compatible connected selection and presents one logical Path, retaining the
exact Polyline, Spline, Bézier, Arc or other supported constituent definitions.
Internal coincident junctions become part of the Path topology; constraints to
outside geometry prevent Join. Undo restores the source objects and internal
relations. Separate exact constituents creates editable copies while preserving
the Path. See [Path and selection guide](../../../docs/guides/WORKBENCH_DATASET_UI_dev060.md).

<a id="curve-workbench--dev-059-consolidated-interaction"></a>
## Creation and interaction

**Create → Line** draws one continuous retained path. Click the start, then each
successive vertex; Enter or Finish commits it. Two vertices make one segment.
Clicking the start again closes the path with one shared vertex. Escape cancels an
unfinished path. Segments and defining vertices remain selectable and dimensionable.
Use **Modify → Split selected Path / entity…** or **Join Path…** (`j`).
Heterogeneous endpoint-connected primitives retain exact definitions; disconnected
or closed primitives use **Combine / Compound…** (`Shift+j`). Sources remain
available. **Separate exact constituents** creates editable copies. See
[Construction workflows](../../../docs/guides/WORKBENCH_dev059.md) for sampling,
Dataset promotion, command configuration and the namespace browser.

**Select** addresses every visible included curve, regardless of origin. The active
row is the property focus. Fit Selected includes all semantically selected logical
curves and their selected defining controls. Ctrl adds, Shift subtracts; click defining points,
controls or segments. Drag empty canvas for a rectangle, or choose **View → Select
polygon…**, click its vertices and press Enter/Finish. Escape leaves the previous
selection exactly intact. **Objects → Visible reference only** keeps geometry
visible while excluding it from ordinary picks/regions; **Include in selection**
restores participation. Hidden geometry is excluded. Selected editable Native
points from several curves move together in one undoable drag. Dataset points can
be selected but require explicit conversion before editing.

Dataset display points/straight/spline are reversible presentation choices. Original
values, variables, units and ordering remain the scientific/export authority.
**Dataset → retained geometry (review)…** creates a separate editable interpolating
spline; trustworthy GX-TXT provenance reconstructs the exact original primitive/path.
Review and accept explicitly. The immutable source remains in the Session. Ordinary
save stores untouched Dataset bindings; reopening requires the original validated
Dataset. Missing/changed sources are reported and do not create substitute geometry
or overwrite the saved workspace on failed restore.

**Publish primitive as Dataset…** publishes one straight path as exact ordered
vertices. The optional integer ordering name defaults to `index`; rename it or
leave blank to omit it. Closed endpoint repetition is explicit. Publication keeps
retained topology, direction and source/conversion provenance. Dataset source points
are never resampled merely because the display is a spline.

Residuals remain blank until you explicitly choose both comparison paths and
click **Compare**. The completed comparison records Reference, Target and Method
in the existing Workspace/Undo payload; changing property focus does not retarget
it. Editing either path or its coordinate presentation marks results stale and
clears the current residual presentation. Select Compare again to refresh.

Wheel zoom updates immediately, with one checkpoint after a burst. Pan draws at a
coalesced frame cadence and checkpoints when released. Chrome only relayouts when
resize, panel, Settings, theme/font/DPI state changes. Reference images render
asynchronously through the existing calibrated Native plan; canvas interaction
remains responsive. Named workspaces, notes, previews, symmetry, tangents, context
menus and Settings retain the workflows below.

<a id="current23-sketch-constraints-and-dimensions-dev-054"></a>
## Sketch constraints and dimensions

Draw using **Create**, then click bodies/segments or defining handles to select. Ctrl adds references; Shift subtracts. **Constraints** applies a supported relationship to the current selection; **Start constraint tool** selects a tool before selecting its geometry. The tool hint states what to select next; Esc cancels to Select. Native2D drives the retained component and preserves compatible relationships through later handle/gizmo edits. Unsupported selections produce a clear message. Fix locks a complete selected body, or the selected control; **Unfix** removes its Fixed relationships.

Use **Dimension** (D), select a line/round primitive, point or two compatible references, move the pointer to preview the dimension and choose orientation/side, then click to place it. Enter a number in the small canvas editor and press Enter. Optional compatible suffixes such as `0.25 cm` use Unit Registry conversion; angles use rad and may use compatible angle units. Plain numeric input and declared Workspace parameter expressions use the shared Parameter Service. No internal IDs or indexes are required.

Linear types include horizontal/vertical/aligned point distances, line length, point-line distance and parallel-line separation. Angular types include two-line angle and line angle to X. Circular types are R/Ø. Select a defining point for X/Y position to sketch origin. The Constraints menu can choose a specific type; the Dimension tool infers it. Witnesses, arrows, arcs, notation, unit and readable value are drawn before committing and remain associated with the geometry.

Driving dimensions change geometry. If a new driving dimension conflicts or adds no independent local condition, the inline editor offers **Create as reference**. A reference measures existing geometry, updates automatically, uses parentheses/dashed lines and is read-only. Double click a driving dimension to edit inline. Drag its annotation in Select to move the label/witness layout without changing value or geometry; this is one undoable presentation action. Right click offers Edit, Enable/Disable, Delete, Details, valid Driving/Reference toggle and reset position.

Badges use original GX-TXT symbols, enlarged hit regions, hover/name feedback, selected borders and associated-geometry highlighting. Click near the visible badge, right click to manage it, or Tab through visible relationships and Delete the selection. Defining handles take precedence over nearby dimension regions; modifiers and double clicks retain their tool meaning.

**Sketch palette** / **Inspector** is inside the Workbench. It shows active relationships, available constraints, construction/reference role, dimension mode and truthful local component DOFs. Show Constraints and Show Dimensions are independent and saved with the existing workspace state. Hide retains the panel's lifecycle. Advanced remains a separate expert reference editor. Fixed/locked/conflicting/stale edit rejection removes previews/drags/captured references, thaws controls and returns to Select; subsequent mouse-up and Escape are harmless.

Tangency supports finite line/circle/arc, circle/arc pairs (including internal branch), and supported Bézier/Spline endpoint joins with lines/curves/rounds. G2 uses actual endpoint curvature for quadratic/cubic Bézier and the existing Catmull-Rom Spline; it includes positional/tangent continuity. Equal supports straight segments and round radii; concentric includes ellipse centers. Symmetry supports points and compatible line/circle/Bézier/Spline/polyline objects about a selected straight axis. Unsupported arc/ellipse/rectangle object symmetry is rejected. Point-on-curve uses native retained evaluation. Legacy scientific Native point-curve relationships retain their validation behavior; reference measurements remain distinct from retained driving.

The solver is local and bounded:64 objects,256 parameters,1024 residual slots and100 iterations. Singular, unsupported or nonconvergent cases reject atomically. Local rank is not a global uniqueness proof, and legacy/generic components are explicitly marked partial analysis. All Dataset rows, source bytes, retained definitions, conversion paths, publication, units, Undo/Redo and recovery continue to use their existing authorities. See [architecture](../../../docs/architecture/SKETCH_dev054.md) and [acceptance](../../../docs/reports/SKETCH_dev054.md).

The sections below also describe the advanced forms; the inline Dimension tool and retained component constraints above are the ordinary workflow.

<a id="curve-workbench-220"></a>
## Scientific curve workflows

Sketch → **Scientific Recipe Recorder…** records one structured geometry-state
operation per accepted edit/drag, with original parameters, stable IDs, units
and captured sources. Validate or replay through one Undo transaction. Export
as Python script, execute unchanged in Script Workspace to validate/stage the
proposal, then package the same source with Builder profile W and invoke it
through Extensions. Replay uses exact captured retained geometry/resources and
stops at changed sources, missing resources/APIs or plugin versions. Recipes
are Session-scoped and create no implicit Dataset.

Click a point row, use Shift for a range or Ctrl for individual rows. Table and
canvas selection share the native selection model. Selected Dataset rows have
red outline locator rings around their displayed points, separate from the inner
selection marker. Pure native geometry has no Dataset-row locator. A single
selected point populates the numeric X/Y editor. Selection-only changes retain
the table scroll position and range anchor.

Table changes are coalesced into one idle request. A native point drag owns its
selection snapshot until release or Escape, so a pending table request waits for
that lifecycle boundary. Canvas-to-table notifications that already match native
selection do not clear or rewrite it. Escape restores original geometry; curve
switches and closing also cancel the gesture safely. Selection and its locator
rings survive workspace Save/reopen.

Point picking measures tolerance in screen pixels through Native2D, so it stays
consistent when X and Y scales differ or after zooming and panning.

Ctrl-select curves in the object tree to form a multi-object CAD target. Give a
group a scientific name and use **Group selected**, **Add members**,
**Remove members**, or **Ungroup**. The CAD target selector distinguishes the
selected objects from the chosen named group. These operations create local
geometry, with Dataset publication still explicit.

**Move…**, **Rotate…**, **Physical scale…**, **Mirror copy…** and **Pivot…** use
shared typed numeric forms. Rotation is entered in degrees. Length fields show
coordinate units; mixed X/Y or target units require explicit Unit Registry /
Dataset Transform normalization. Physical scale changes geometry with
dimensionless factors. Mirror copies retain their source point identities and
leave originals available.

Choose **Gizmo: translate/rotate/mirror** for Native canvas manipulators.
Translation offers X/Y and free handles; rotation uses the Native arc; the visible
pivot is draggable. Mirror-axis endpoints transfer directly into **Mirror copy…**.
Controls freeze during a held Native geometry drag, queued object selection waits
for commit/cancel, and Escape restores the exact starting state. One committed
gesture creates one undo step. Pivot and mirror-axis changes are also undoable.
Choose **none** to return to point editing. Dataset row locators follow the actual
Native geometry during manipulations and retain selected row identity afterward.

Large Dataset sources retain every finite exact point in Native2D and owned
Session document resources. The canvas uses CORE display reduction and the point
table shows 200 exact rows per page. First/Previous/Next/Last and the page number
control navigate it; clicking a canvas point opens its corresponding table page.
Paging preserves selection outside the displayed page. The source-row column and
red locator rings retain original Dataset row IDs, including filtered or ordered
sources. Nonfinite pairs are omitted from geometry with explicit disconnected
gaps, and remain in the authoritative Dataset.

Large Dataset geometry is read-only. **Convert to Native…** creates a separate
editable curve from an explicitly chosen exact index/count range of 2–65536
points. It retains source row identity and gap information. The source remains
available, and conversion does not publish a Dataset. Numeric editing, splitting,
or changing source geometry uses such an explicit Native copy. Linear/Spline
from selection can also create a separate derived curve directly from bounded
exact selected source controls, including selections spanning table pages.
Linear controls are limited to 65536 and spline controls to 4096; the complete
source is retained and unchanged.

Curve Workbench is a planar scientific X/Y workspace. Open it from **Viewers → Curve Workbench** or from a Dataset viewer action. **Add curve…** accepts an ordinary Dataset with X and Y alone. Filter, Family, and Order are optional. With no Order, points follow source-row order. If a Family is chosen, select one or several members, or leave the member list unselected to add all. Reopen **Add curve…** to bring curves from other Datasets into the same workspace.

The left list shows every curve's visibility, name, source Dataset, point count, and source or edited state. Click a row to make its curve active; the point table and blue curve follow that choice. **Show/Hide** and **Lock/Unlock** affect the active curve. The original stays available when a derived curve is created. The workspace, curve geometry, visibility, source bindings, provenance, reference, target, external feedback, and view are saved in the Session. **Save workspace** forces a save; normal edits save automatically.

Click points to select them; Ctrl adds and Shift subtracts. Drag an already selected point to move the selected group. Drag empty canvas to select a rectangle. **Select X interval** selects points between entered bounds. The point table also selects exact points. **Apply X/Y** edits one selected point numerically. **Insert point** then click a segment; **Delete points**, **Point earlier/later**, **Reverse**, **Keep range**, **Remove range**, **Trim before/after**, **Split**, **Duplicate**, **Undo**, and **Redo** operate on the active curve. The first and last selected points define a range. A removed interior range leaves a disconnected gap; it does not create a false joining segment. Wheel zooms around the pointer, Pan drags, and **Fit all/active** reset framing.

To compose a curve, select a range and choose **Add selected fragment ↓**.
Add fragments from other curves, then reorder, reverse or remove them. Spline
fragments are evaluated by Native2D from their exact selected range. The green
dashed preview shows the geometry that will be accepted. **Gap bridge: none**
retains disconnected gaps; choose **straight**, **quadratic**, **cubic**, or
**smooth** to construct an explicit bridge. The straight shortcut retains the
previous one-click workflow. Geometric bridges require identical X/Y working
units across fragments: convert deliberately through Dataset Transform / Unit
Registry before joining different units.

Native2D owns endpoint coordinates, tangents and analytical controls. Cubic and
smooth (Hermite) bridges match both incident source derivatives (C1 in each
source segment's local [0,1] parameter). Quadratic bridges match tangent
directions where their forward rays intersect; the retained receipt identifies
whether derivative magnitudes also match C1. Incompatible quadratic rays fail
explicitly; choose cubic or smooth for independent tangents. Straight bridges
guarantee C0. **Settings…** controls 3..4096 subdivisions and derivative
tolerance. The preview/output is that explicit sampled materialization, with
analytic controls and continuity evidence retained in Session and Dataset
provenance. Polyline chords do not themselves have analytic C1 continuity.

Name the result and choose **Previewed fragments → new curve**. Acceptance
transfers the reviewed Native preview as one undo transaction. Original curves
remain unchanged, no Dataset is published automatically, and the direction
marker controls later explicit Dataset row order. Editable compositions are
bounded to 65536 exact samples; spline fragments at 16 subdivisions permit up to
4096 controls. A failed preview clears stale preview geometry and prevents
acceptance. Bridge settings and accepted descriptors survive Save/reopen.

**Linear from selection** and **Spline from selection** create separate simplified curves from at least two selected points. Spline uses Native2D Catmull–Rom geometric sampling, with editable controls and a continuously redrawn preview. Use Insert point, Delete points, mouse drag, numeric editing, or **Snap to reference** to adjust the controls. The reference curve remains separate. Dataset Curve Fit remains the tool for statistical/scientific fitting methods.

Open the in-canvas **Compare / residuals** panel. Choose explicit **Reference path**, **Target path** and **x** or **path**, then **Compare**. X comparison samples the derived curve at valid reference X positions and requires single-valued monotonic X for both curves. Path comparison aligns curves by normalized cumulative path position and handles folded profiles. The main view overlays both curves and marks the largest deviation; the lower panel plots signed residual against reference X or path distance. The panel reports current status, sample count, maximum absolute residual, mean absolute residual and root mean squared residual (RMSE), with the existing physical units. Edits mark the receipt stale; only an explicit Compare calculates new results. Disconnected compositions must be compared by their separate fragments.

Comparison summaries use every exact native reference point. CORE reduces only
the residual presentation to a bounded ordered set, retaining the maximum and
its exact original residual ordinal. View changes do not change scientific
comparison results.

The 2-D metric selector reports path length, X/Y span, length-to-X-span ratio, or signed enclosed area for a connected closed curve. In the panel's **Geometric Measurements** section, enter a numeric **Expected value** and select **Evaluate** to report the measured value and its signed difference. This numeric value is separate from **Target path** and uses the existing metric units/validation. The **External downstream feedback** field records measurements from a separate geometry/CFD workflow; Curve Workbench does not calculate extrusion or 3-D surface metrics.

Enter a fresh Dataset ID and choose **Publish selected curve(s)**. A single curve publishes X/Y without an artificial Family column. A multiple-curve or disconnected result additionally includes `segment_id`; all outputs include source-row ordinal, point identity, and source-order fields. Dataset Publication v2 writes the canonical Dataset; metadata records source Datasets and variables, source names, filters, family/order information, parent/operation history, spline controls, residual summary, metric target, and external feedback. Existing Datasets cannot be overwritten. Published spline curves contain evaluated samples; controls remain in provenance and the saved workspace.

Large unedited Dataset source publication streams complete exact source tuples
through CORE Dataset Transform and Publication, including auxiliary columns,
filters, stable ordering and explicit intended direction. Reverse publication
reverses whole tuples, including equal-key order, and records original source row
ordinals in `workbench_source_row_ordinal` (a collision-free prefix is chosen if
needed). Compatible Dataset source curves and Native results can be published
together through the same CORE writer. Edited Dataset-backed Native points
retrieve their original complete tuples by source-row identity and replace only
XY. Unbound Native samples explicitly mark absent auxiliary values with
`workbench_auxiliary_valid=0`; zero/empty placeholders are not observations.
Integer/text types stay exact and gaps/member boundaries are explicit.
The entered public Dataset ID
is preserved; collisions are reported and sources are never overwritten. Storage
Auto is selected centrally from logical size, so large output normally uses HDF5.

**Source Dataset Preview…** opens the normal Preview using the exact source ID.
Changed scientific schema/payload marks the cached source stale; Preview shows
the current Dataset without replacing local geometry. Source-tuple publication
rejects stale/missing bindings. Explicitly reload after reviewing a change.
Missing sources remain clearly labeled after reopen while saved owned local
geometry/row identities remain available; no replacement Dataset is invented.

Large source publication uses CORE responsive Transform planning and bounded
staging. Progress reports exact rows, controls are frozen during publication,
and **Escape** cancels before commit. Closing during publication requests the
same cancellation; close again once controls return. Cancellation retains
workspace geometry, removes staged output, creates no Dataset, and restores
usable controls. Mouse/selection callbacks cannot edit geometry recursively
while publication yields. A failed progress callback or changed Session/source
is an explicit error, with staged cleanup. The final canonical commit is atomic
and does not yield to GUI callbacks.

Enable **Object snap (8 px)** to snap a Native translation gizmo's captured pivot
onto reference vertices. Free movement produces exact coincidence; X/Y handles
retain the configured gizmo axis and align its projected coordinate. Moving
objects and all group members are excluded from reference search. Reference
geometry uses its complete Native points, with visible locked sources still
usable. Matching working units are required. Grid snapping runs first when
enabled, and a nearby object vertex takes precedence. Snapping moves a selected
object/group coherently and records the reference curve/original Native index
in the gesture provenance. The setting, logical reference and resulting geometry
persist through Save/reopen. No source Dataset is changed or implicitly published.

**Working units…** converts the whole workspace coordinate frame through the
public Unit Registry and Native2D. Enter the current and target common units;
undeclared coordinates require the explicit assumption checkbox. Known mixed
units reject the whole action. Normalize calibrated source coordinates with
Dataset Transform before proportional frame conversion. Scientific extent
and canvas position stay unchanged; this differs from **Physical scale…**.
Native geometry, dimensional grid/polar settings, custom pivots and mirror axes
convert together. Axis labels and point editors show the working unit. The
conversion is one Undo/Redo action and preserves point/row identities, selection,
Dataset-row red locators and frozen source provenance.

Large Dataset-backed curves retain complete converted Native geometry in owned
resources, with bounded point tables and empty Tcl sample lists. Explicit
publication converts complete source tuples through the common Dataset Transform
API, preserving auxiliary strings, integer values and row lineage, and declares
the converted X/Y schema units. Undeclared input assumptions are included in
that publication provenance. Save/reopen restores the converted resource and
working unit. Original Dataset bytes, IDs and schema remain unchanged.

The CORE recovery journal records committed edit/Undo/Redo boundaries separately
from the last explicitly saved state. After an unclean exit, choose **Recover**
or **Open last saved state** in the recovery dialog; details show the saved and
checkpoint revisions plus recent operation receipts. Cancel leaves the Session
untouched. Recovery never advances the saved snapshot automatically. **Save
workspace**, Session Save and normal close compact valid journals and mark them
clean. Corrupt or unwritable journals produce a persistent warning while normal
Document open/save remains available. Large geometry stays in owned resources;
valid recovery references protect those resources from garbage collection.
See [CORE recovery API](../../../docs/api/WORKBENCH_RECOVERY_API_v1.md).

**Documents…** opens the common Interactive Documents manager. Review an owned
Document's ID/module/revision, then **Delete selected document…**. Confirmation
closes only that owner's live view, cancels pending selection/operations and
removes its unreferenced resources and recovery journal. Source Datasets and
published results remain available, including resources retained by published
provenance. A stale Session or changed Document requires Refresh before deletion.
The tables support horizontal/vertical navigation and larger-font headings.


**Sketch… → Create primitive…** opens the common typed, scrollable parameter form.
Choose point, line, infinite construction line, polyline, oriented rectangle,
circle, signed arc, ellipse, quadratic/cubic Bezier or Catmull-Rom spline. Controls
are `{X Y}` pairs; the form explains the required count. Coordinates and radii use
the chosen working unit; angle fields use degrees. Native2D owns the definition
and exact bounds/derivatives/measurements. The complete parameter sampling count
is recorded separately from that authority. Editing **Parameters…** preserves
logical identity; Undo/Redo and Session/recovery restore defining parameters.

Sampled rows remain selectable in table and canvas, with one-point X/Y population.
Retained primitive points require parameter edits or **Explode editable points**
before point editing. Whole-object CAD transforms/gizmos/mirror copies preserve
the primitive. Pure Native geometry has no source Dataset or red Dataset-row
locator. Normal explicit publication preserves the entered Dataset ID, declares
working units and records its definition and complete sampling policy.

An infinite construction line renders across the current viewport and reports
undefined finite bounds/length/area. **Sample finite range…** asks for first/last
parameters and a complete result count (Workbench ≤65536; public Native/Script API
≤1,000,000). The result is an independent finite Native point curve, ready for
normal explicit Dataset publication. One-control points retain their type and
have no direction arrow. Finite materializations inherit intended direction.

**Sketch… → Create series…** creates rectangular rows/columns with signed X/Y
spacing, or circular positions about a numeric pivot with an angular step.
Position zero is the original; the optional checkbox also copies it. Circular
geometry may rotate about the pivot or retain orientation while its combined
bounds center rotates. Original geometry remains unchanged. The complete series
is one Undo/Redo action; generated objects have independent identities and retain
mathematical primitive definitions. Native transaction limits are 10,000 result
objects and 8,000,000 copied vertices; invalid/budget/overflow failures preserve
the workspace. Large Dataset-backed sources require explicit Convert to Native
before creating an editable Workbench series. The Sketch menu keeps numeric point
editors accessible at the existing window size; forms scroll and reveal fields
when keyboard focus advances.


**Sketch… → Constraints…** lists stable relationship IDs/names, kind, validity,
enforcement, dimension/residual and unit. Create/Edit opens the common typed
parameter form with logical geometry IDs, point/segment indices, optional partner
or symmetry axis, value, world and angular tolerances. Relationships validate
Native edits; the Workbench does not claim a general parametric solver. Enabled
parameters must already be satisfied. Disable keeps scientific diagnostics and
allows explicit edits; editing/re-enabling requires a valid supported relationship.

The 21 supported kinds include Fixed, Distance, Angle, Parallel, Perpendicular,
Coincident, Horizontal, Vertical, Equal length/radius, Tangent, Concentric,
Collinear, Midpoint, Point on line/supported curve, Symmetry, Radius, Diameter and
Lock X/Y. Radius semantics require a similarity circle/arc. Point-on-curve currently
supports lines, rectangles, polylines and circles; unsupported curve families fail
explicitly. All partners require matching declared/assumed coordinate units.
Values use working units; angle uses radians; tangency has a separate radian
tolerance. Sampling-count changes with references require explicit disconnection.

A complete constrained multi-point drag uses Native2D's atomic candidate API.
Joined selected points move together; a failed candidate visibly reports rejection
and restores previous geometry/selection. Relationship create/edit/enable/remove
is one Undo/Redo action. Logical IDs, dimensions, Fixed anchors, enabled state and
native enforcement persist through Save, recovery and fresh Session reopen.
The manager scrolls in both directions and wraps controls/help at larger fonts.


Select one source point, then **Sketch… → Join point on canvas**. Move over another
visible curve endpoint: the native hit query draws a green target ring (orange for
incompatible units). Click to merge the source onto that exact endpoint and create
its persistent Coincident relationship. Escape cancels. The target stays unchanged.
Pointer mode searches other curves; **Join point numerically…** supports explicit
same-curve/point indices and a merge checkbox for already-satisfied relationships.
Merge supports generic points and retained point/line/polyline/Bezier/spline
endpoints. Other retained families require parameter edits first and a satisfied
non-merge relation. Locked/bulk source geometry must be made explicitly editable.

The Native transaction commits source parameters, point cache and relationship
together; existing Fixed/dimensional constraints reject the whole merge. Undo
restores prior geometry and disconnects the relation; Redo restores the same
logical IDs. Remove its relationship in Constraints to disconnect explicitly.
Original Dataset bytes and target geometry remain unchanged; explicit publication
uses the entered public Dataset ID and records the Join provenance. Fresh reopen
restores exact parameters, relationship and point-selection workflow.

Extended point/segment relationships require explicit removal before operations
that reindex their geometry (insert/remove/reorder/reverse or point-count change),
including disabled records. This prevents accidental remapping to another point.
Changes to curve breaks validate the complete relationship state atomically.
Pure Native rows are labelled native primitive/geometry, separately from source
Dataset and derived Dataset-backed geometry.

### Native measurement inspection

Sketch → Measurements opens a scrollable inspection table. Create captures a
Native2D value, logical geometry references, geometry SHA-256 identities, anchors,
units and evaluation policy. Native2D computes scientific geometry; sparse display
polygons do not determine retained circle area or length. Geometry edits mark old
receipts **stale**; deleted references mark them **missing**. The old value remains
available for inspection. Refresh selected evaluates all requested rows before
committing one undoable update. Saved receipts retain their logical identity after
Undo, recovery and Session reopen. Current distance receipts draw their native
witness pair on the canvas; stale/missing witnesses stay hidden.

Publish report as Dataset asks for the public Dataset ID and storage policy.
Stale/missing rows must first be refreshed. Reports contain IDs, names, kinds,
values, per-row units, status, geometry references/fingerprints, anchors, exactness,
evaluation policies and witness points. Normal Dataset Schema/Metadata/publication
APIs own storage, ID validation and collision errors. Source Dataset provenance is
included only where an actual Dataset backs the geometry. Mixed report dimensions
use the per-row unit column rather than a false shared numeric-variable unit.

### Names, sketch attributes and fragments

Sketch → Names / Attributes edits stable logical curves, primitives, groups,
fragments or document metadata. Names support UTF-8; attributes use namespaced
keys such as `sample.temperature` or `curve.role` and inert text values. Derived
geometry inherits the primary parent's user attributes; explicit fragment
materialization carries the fragment's own attributes. Names do not substitute
for public Dataset IDs. Normal publication records document attributes under
`sketch.attributes` and named entity descriptors under `sketch.entity_descriptors`,
with the mapping policy in provenance. Internal UI fields are excluded.

Sketch → Fragments creates named parent-linked intervals without copying curves.
Retained primitives use parameter intervals; discrete curves use inclusive point
ordinals. Parent transforms and ordinary parameter changes preserve fragment
identity. Point reordering/topology changes mark the interval **stale**; parent
deletion marks it **missing**. Saved stale references remain stale after reopen.
Update interval is the explicit rebind action. Sample to Native asks for a count
and creates independent geometry through Native evaluation; Publish selected
curve(s) then publishes it under the entered public Dataset ID. The source sketch,
fragment, sampled Native geometry and Dataset remain distinct resources.

### Selection Sets, Layers and saved views

Sketch → Selection Sets / Layers keeps three concepts separate: Groups contain
editing/transform membership, Sets remember object/point/fragment references, and
Layers organize presentation. Create Set prefills the current point or curve
selection. Activate restores its table/canvas selection and Dataset-row locators.
Edit / Rebind explicitly replaces references; Add member, Remove member and Rename
preserve other captured references, including stale members. Reordering/resampling
points marks affected ordinals stale. Deleted references stay missing. Save/reopen
preserves these states; no silent ordinal remapping occurs. Names such as inlet,
wall or catalyst carry no automatic solver boundary-condition semantics.

Create Layer selects presentation member curves and visibility/selectability/lock/
opacity. A curve belongs to at most one Layer; reassignment removes it from its
previous Layer. Show / Hide preserves geometry and point selection, with one
Undo/Redo action. Effective curve visibility also respects its editing Groups.
The canvas composites Layer opacity against its background through shared color
APIs. Layer deletion leaves its scientific geometry in the default presentation.

Sketch → Saved views captures logical bounds/zoom/pan, Cartesian/polar mode, grid,
aspect, background and curve/group/layer visibility. Restore keeps the current
window size and scientific geometry/point selection; it is one undoable
presentation action. Names and IDs persist across Session save/reopen. Update from
current view explicitly recaptures the bookmark. If coordinate units changed,
restore rejects the old frame with a clear update instruction. Missing presentation
references are reported. These bookmarks do not publish Datasets.

### Parametric rectangular series

Create series supports axis spacing and optional column-Y/row-X basis components. Rectangular results have persistent Series containers distinct from groups. Sketch → Parametric series opens shape/basis/member inspection, Edit/Preview, Transform as unit, Explode and Delete. Preview uses an isolated temporary Native scene, then releases it; Apply regenerates from independent current originals with one undo. Counts/basis edits retain the series frame, while working-unit conversion rescales dimensional parameters. Explode preserves members; Delete removes generated geometry. Save/reopen retains container parameters, logical cells and geometry. Origin is omitted unless an independent copy is explicitly requested; circular series remains the established explicit static-copy operation.

### Script-based extensions

Extensions… lists enabled installed compatible actions. Configure its shared fields and Apply; a mutating action produces one Undo/Redo. The host receives logical operation proposals from unchanged packaged Python/Octave scripts, validates ownership/units/locks/Native constraints and rolls back failed multi-operation results. Script/plugin/action/config provenance remains with resulting geometry. Modules controls enable/disable; source or bundle checksum changes require a correctly rebuilt package.

### Construction/reference roles and whole-sketch export

Sketch → Construction / reference role assigns the selected editable geometry's shared Native role without changing coordinates or measurements, with one Undo. Such entities remain usable for constraints, snap, mirror and inspection and persist after reopening. Normal publication excludes them and reports excluded members. Reference-only publication clearly rejects; Sample finite range creates regular independent geometry that can be explicitly published.

Export sketch… discovers the normal PNG/SVG providers and exports the live scene's regular geometry, labels, legend, grid, aspect, polar/background and current bounds through the renderer-neutral snapshot. Default export excludes construction/reference entities; the public snapshot API also supports explicit inclusion. Choose the provider, configure shared fields and choose a file; normal publication collision/atomic-write rules apply. Export creates no Dataset and preserves document revision.

### Geometric comparison and deviation reports

Choose distinct **Reference path** and **Target path** and the `geometry` method, then Compare. Native2D uses the existing scientific sampling policy and 257-sample budget independently of display caches; the actual query count comes from its receipt. The view shows unsigned curve distance by sampled reference path, plus RMS, sampled bidirectional Hausdorff and closest distance. Retained mathematical definitions remain authoritative; the captured report records which target projections/closest pairs are exact and which use bounded scientific samples. These sampled metrics do not assert continuous Hausdorff extrema.

**Publish deviations…** is enabled only for a current, explicitly completed Geometry comparison of the selected pair. The adjacent explanation states why it is unavailable. Opening the panel never calculates or publishes. The original reviewed dialog creates an explicitly named Dataset containing query/projected XY pairs, unsigned distances, sampled path and indices, with source/fingerprint/units/policy metadata. Geometry edits make the receipt stale and clear its presentation; Compare again before publishing. Measurements… also offers geometric RMS, sampled Hausdorff, length/closed-area difference and closest-curve distance with configurable 6–4096 scientific samples. Use its shared explicit Refresh, one Undo, stale/missing inspection and normal report publication.


<a id="task-9-dev-052-final-behavior"></a>
## Scientific interaction behavior

The point table and canvas preserve one logical point selection. Repeated/rapid row clicks coalesce to the newest selection at idle. An active Native gesture retains the pending selection until release/cancellation; its generation and owner are checked before applying it. Table refresh does not recursively rebuild the selection scene. Ctrl/Shift selects multiple points; one selected point populates X/Y. Dataset row identities draw red locator rings; pure Native geometry has no Dataset row. The sidebar scrolls vertically; Tab scrolls the focused point/numeric/composition control into view. Publication controls wrap with labels at narrow widths and larger fonts.

Coordinates chooses Cartesian, polar or both; Arrangement chooses a concatenated table, long family or exact shared-X wide output. Normal publication preserves your requested public Dataset ID, validates/collision-checks it and uses CORE Dataset Transform/Publication/Schema/Metadata. Dataset-backed sources preserve complete typed auxiliary tuples, including exact uint64/text. Edited Native derivatives use immutable source-row lineage to recover the original auxiliary tuple and replace only accepted XY. Pure Native rows carry no source Dataset ID and explicitly mark unavailable auxiliaries with validity0, zero/empty placeholders. Long families preserve per-member auxiliary descriptors and presence masks. Wide output requires identical point counts and X values, with no implicit interpolation. Wide polar output is rejected because it has multiple independent Y bindings; use table/long polar for one coordinate pair.

Polar output uses the shared Native frame: origin, theta-zero, CW/CCW and degrees/radians. Radius uses the common working unit, angle uses deg/rad; origin has an explicit theta_defined0 mask and a zero placeholder. Normalization covers one positive full turn without implicit unwrapping. Source Preview opens the real public Dataset ID. Missing/stale sources are visible; saved owned local geometry remains available. Source-tuple publication rejects missing/stale dependencies until you explicitly reload/restore them. No automatic geometry replacement occurs.


<a id="dev-053-cad-workspace"></a>
## CAD workspace

### Objects in one workspace

The object list distinguishes an immutable **Dataset source**, an exact **Retained line/circle/arc/etc.**, and an editable **Native point curve**. Dataset rows keep their exact source identities and red locators; off-viewport markers are omitted without changing selection. Pure Native points have no Dataset-row locator. Retained primitives expose defining handles rather than rendering samples. Names are display labels on existing logical identities, never another identity system.

### Draw and edit

**Create** opens Point, Line, Rectangle, Circle, Arc, Ellipse, quadratic/cubic Bézier, Polyline and Spline. Click defining positions on the canvas. Circle uses center then perimeter; Arc uses center, start and end (counterclockwise sweep); Ellipse uses center, major-axis position and minor-axis extent; Bézier uses its true control polygon. Rectangle uses opposite corners. Polyline/Spline finish with Enter, Space or **Finish**. Canvas creation chooses X=Y aspect so a circle is displayed as a circle; scientific Auto aspect remains available in Grid/view.

Pointer motion displays a transient Native preview; circle/arc previews show a radius witness and value. **Esc**, changing tool or closing cancels incomplete tools without a document/history entry. **Object snap** uses Native endpoint/center/control/midpoint candidates, with visible feedback. Grid snapping remains independent. Defining-point attachment creates persistent Native Coincident relationships with visible attachment feedback. Incompatible projected control roles reject clearly.

**Select** clicks a body, segment or defining control; Ctrl adds retained references; Shift subtracts. The defining-handle table provides the same references. Drag a handle to edit its exact Native definition; center drag moves a round primitive, perimeter drag edits its radius, line endpoints/Bezier controls edit their parameters. Preview is separate from the commit on release. Rejected constraint edits preserve geometry/history with a visible reason. **Modify → Move/Rotate on canvas** uses existing Native gizmos. Exact parameters and numeric handle X/Y remain available. Existing Native point operations/groups are preserved behind **Modify → Native point operations / groups…**; scientific range, composition, comparison, measurement and publication controls remain available.

### Constrain and dimension

Select geometry, then **Constraints**, or right-click on the canvas. Native2D offers structurally compatible relationships only. Select two line bodies/segments for Parallel/Perpendicular/Angle; two defining controls for Coincident/Distance; a round body for Radius/Diameter; two round bodies for Concentric/Equal Radius; point control plus body for Point-on-curve. Horizontal/Vertical, locks, equal length, midpoint, collinear, supported line/circle tangent and symmetry use the same native model.

The Native retained component solver drives supported relationships and compatible later edits atomically. Tangent covers supported line/circle/arc and Bézier/Spline joins; Curvature / G2 uses actual supported endpoint continuity. Unsupported combinations report a reason. The Sketch Palette reports truthful bounded local rank/DOF status, with singular/global analysis limits. Fixed/locked conflicts restore a clean idle state.

Use Dimension, select geometry, move the pointer to preview witnesses, click to place, then enter a numeric value and optional compatible unit inline. Double-click edits a driving value; driven/reference values are read-only, associated measurements. Over-constraining creation offers reference mode. Drag the annotation to change presentation only. Show Constraints / Show Dimensions are in the internal Sketch Palette.

Readable labels identify geometry and dimensional values, including R and Ø. Click a canvas marker or **Inspector / dimensions…** to highlight referenced geometry. Edit a dimension, disable/re-enable, remove and Undo/Redo through ordinary actions. **Advanced…** retains the exact generic reference editor, prepopulated when inspecting an existing relationship. Internal IDs/encoded reference indices belong there. Deleting a referenced object removes its Native relationship; Undo restores both, avoiding dangling references.

### Explicit representations

| Source | Explicit action | Result |
| --- | --- | --- |
| Retained primitive | Publish primitive as Dataset… | Separate Canonical Dataset with chosen finite domain and uniform parameter sample count; original primitive unchanged |
| Original primitive-produced Dataset | Reconstruct exact primitive from Dataset | Separate exact retained definition/transform/units, after validating original producer receipt and all materialized values |
| Arbitrary Dataset / Native point curve | Fit to retained primitive… | Scientific approximate circle/arc/quadratic/cubic Bézier candidate; review RMS/max geometric error, then explicit Accept |
| Dataset source | Dataset → Native editable points… | Existing exact bounded point-range copy, editable independently |
| Retained primitive | Primitive → Native sampled points… | Existing explicit finite materialization, independently editable point curve |
| Native point curve / mixed scientific selection | Publish selected curve(s) | Existing complete-tuple, direction, Cartesian/polar, table/long/wide canonical publication |

Primitive publication/reconstruction records `NATIVE2D_PRIMITIVE_PUBLICATION_v1` in the existing Metadata/Canonical provenance authorities: complete retained definition, affine matrix, units, domain endpoints, uniform distribution/count, source logical identity and operation/version. Exact reconstruction requires the original Cartesian binding and unchanged producer receipt, compatible metadata/schema and verified samples. Edited/spoofed metadata, missing provenance or changed bindings are rejected; use scientific fitting for arbitrary data. No sampled approximation is promoted to exact equivalence.

Fitting uses **complete explicitly selected input** (3..65536 points, one continuous range), the existing Numerical API/Parallel Execution policy and a separate Native candidate. A larger source requires an explicit fitting range; display reduction is never used as fit science. Quality/provenance identifies approximation even for a very small residual. Closing/Esc discards the preview; Accept creates one separate retained object and one Undo. Source Dataset bytes remain unchanged.

### Units, history and saved work

Use the unit chooser/Working units dialog and existing Unit Registry. Euclidean geometry requires one validated common proportional unit on both axes. Compatible non-length dimensions are supported; resolve ambiguous or mixed X/Y bindings explicitly. Complete-workspace conversion rescales geometry and dimensional relationships together. Angular labels use rad. One created object, accepted fit, control edit, relationship or dimension edit is one Undo; preview/cancel produces no history spam. Publication is an explicit Session operation and does not replace the document object.

Save workspace and close normally. Existing Interactive Documents/owned resources/recovery persist mixed types, definitions/transforms, constraints/dimensions, Dataset bindings, roles, names and conversion provenance. Transient tool/hover/incomplete previews are excluded. Reopen in a fresh process and continue exact parameter editing. Keyboard focus, numeric forms, Enter/Space/Esc, scroll-to-focused controls and wrapping toolbars provide alternatives to mouse input.

Illustrations: [mixed CAD workspace](../../../docs/evidence/dev053/mixed-cad.png), [fresh reopen](../../../docs/evidence/dev053/fresh-mixed-cad.png).

<a id="dev-055-drawing-and-compact-controls"></a>
### Drawing and compact controls

Line creates one connected retained Path continuously; click successive endpoints, then Enter or Finish to commit. Escape cancels an unfinished Path; after a commit, Escape returns to Select. Click a chain's initial/intermediate defining endpoint for semantic closure. Polyline and Spline remain separate primitives; Enter/Finish completes them. Endpoint coincidence does not mean periodic spline topology. Placed defining controls and attachment feedback remain visible. Single Points are filled dots even when deselected.

Objects contains selection operations including explicit Show/Hide; they cover the full current selection in one Undo. Points/ranges contains the existing scientific point/range operations. View contains Pan, Fit, Source Dataset Preview and More scientific controls. All existing source, range, composition, measurement, comparison, fitting, representation and publication workflows remain available. Compact Constraints groups Directions, Connections, Shape, Fixing and Dimensional, with corresponding tool-first cascades.

For multiple selected publishable objects, Publish selected curve(s) publishes all of them through the chosen Coordinates/Arrangement. Publish selection offers One structured Dataset or Separate Dataset outputs. Review every separate Dataset ID before Publish reviewed batch. All ID collisions are checked before any output starts; the status lists the actual output IDs. Retained outputs use explicit uniform parameter sampling and preserve exact definition/provenance for reconstruction. Sources remain unchanged.

<a id="remote-x11-in-dev-066"></a>
## Remote X11

Viewport icons, tool instructions and the publication footer are visible on an
idle forwarded display. The initial window reserves space for native decorations
and a taskbar. The utility area and Sketch palette have scrollbars; Settings
controls their visibility. Create tools keep the placed preview visible while
placing additional controls; Enter / Finish commits and Escape returns to Select.
Ordinary network latency is expected. No local-Xorg performance equivalence is
required. Retained geometry, constraints, parameters and Save Workspace follow
the existing scientific and Session authorities.

<a id="description-and-persistent-history-gx-txt-dev073"></a>
## Description and persistent History

The bottom strip offers **Description | History**. Description shows the current
operation instructions. History shows the retained Scientific Recipe as a horizontal
timeline. The Settings menu can hide or show this strip. Use the mouse wheel over
the timeline to reach earlier or later operations. Consecutive creations, constraint
additions and matching transforms are grouped; right-click a group and choose
**Expand individual operations** to see its steps. Clicking a step reconstructs its
geometry, constraints and parameter read view through CORE. It does not publish a
Dataset or change the saved Workspace, and future steps remain retained.

While browsing a past state, construction, constraint edits and publication are
read-only. Undo/Redo moves through retained History in this mode. Choose **Return
to latest state** to resume the current editable state. **Restart editing here;
discard future…** explicitly confirms how many future steps will be discarded,
restores the chosen state, and saves the restarted Workspace. Cancel leaves the
future intact. Restart resets the previous editing Undo/Redo stacks. Subsequent
edits have normal Undo/Redo and are recorded in the new retained History. Shared
Session parameters must match the historical state; CORE rejects an unsafe restart
instead of changing other Workspaces implicitly.

Right-click an expanded constraint step to **Select / inspect constraint ID**.
This selects the actual retained relationship in the palette and canvas. **Restart
here, then edit/remove constraint ID…** makes the same explicit confirmed transition
to editing before delegating to the existing CORE constraint authority. Driving
dimensions use the existing inline editor. Geometric relationships use inspection
and Enable/Disable or Delete in the palette; they have no fabricated numeric editor.
Reference dimensions remain read-only. Solver, dependency and tolerance checks
still apply. Merely opening a context menu or inspecting an identity never changes
historical geometry or truncates the future. Delete and subsequent edits support
normal Undo/Redo on the restarted state.

Saving a Workspace retains its Scientific Recipe, logical geometry/constraint IDs,
parameters and working units. Reopening reconstructs the same current state and
History. Older Workspaces without a complete recipe expose only the retained base
and available operations. Discarded History cannot be recovered.
The strip is a projection of the saved CORE recipe, not a second history
database or a global Session Undo stack.


<a id="dev092-contextual-directions-and-reference-graphics"></a>
## Contextual directions and reference graphics

Right-click a Path to show or hide its arrow, flip its direction or edit its marker
properties. For a compound/network, right-click the individual subpath: visibility,
flip and drag affect that stable constituent only. Constituent arrows start hidden.
Drag a visible arrow along its own path to change physical arc-length placement.
Direction settings configure appearance; they do not enable every subpath.

An unordered compound has no global traversal. Branched/disconnected networks are
published as reviewed separate constituent Datasets. A single ordered Dataset
requires a continuous retained sequence after the chosen constituent directions.
Shared boundary samples are deduplicated only when equal; other samples are kept.

Workspace → Background image / reference graphic… imports a managed raster behind
scientific geometry. Reference Images manages visibility and 0–100% opacity.
Calibrate selects two image points, then accepts a known positive physical distance
and compatible unit. The manager reports scale, rotation, translation and units.
Reset clears calibration without deleting the source graphic. Recalibrate changes
physical scale; scale is read-only while calibrated. Dimension can annotate native
calibration controls as reference measurements. Uncalibrated pixels cannot supply
physical dimensional references. Save Workspace preserves resource/calibration
through the normal Session portable export/import services.

Construction grid/view uses shared tabs for Visibility, Grid, Lines, Axes,
Background and Polar/advanced. Apply validates all values; field reset and grid
reset retain their existing scope. Escape returns to Select. Pressed buttons
follow the active controller, including keyboard actions and History browsing.

<a id="clear-history-and-shared-configuration-2151"></a>
## Clear History and shared configuration

**Workspace → Clear History…** validates a checkpoint of the complete current
scientific state before confirmation. Yes permanently discards old Timeline and
Undo/Redo entries; No opens the official Workspace manager to export a protected
copy first; Cancel changes nothing. Curves, retained definitions/parts/directions,
constraints, parameters, images/calibration, styles/groups/layers/selections,
view, Dataset bindings and notes remain unchanged. New edits start fresh history
at this base. The complete-retention limit remains8MiB/4096steps; no automatic
clearing/pruning occurs. An oversized single base cannot be cleared safely.

Finish active gestures/publication/restore and return to Latest first. A stale
owner/revision/Session or precommit save failure rejects the operation and keeps
old history recoverable. CORE Scientific Recipe creates the pure rebase candidate;
existing Interactive Document/Workspace and Recovery authorities commit it.
Recovery journals remain separate from the scientific Timeline.

Command shortcuts are editable in **Configuration → Modules → Curve Workbench**
before this Viewer opens, and in **Settings → Keyboard shortcuts…**. Both use the
same CORE defaults, Session overrides, module-owned command validator and typed
form. Conflicting/reserved keys reject. Saving either surface updates a running
Workbench immediately; a dirty editor retains its draft and reports conflicts.
Reload/discard explicitly reconciles it. User defaults survive restart; Session
scope remains independent and can reset to inherit the current User default.

<a id="scientific-comparison-reports-dev097"></a>
### Scientific comparison reports

Use **X** for a vertical response difference, including plots whose axes have
unlike dimensions (for example V and mA). The signed residual is reference Y
minus target Y at reference X. Compatible coordinate units are normalized by CORE;
a folded X curve requires a different explicitly chosen comparison.

**Path** compares equal normalized path positions; **geometry** measures sampled
nearest-curve distances. Those Euclidean modes require a common physical X/Y
unit, including mm/m axes converted before distance evaluation. Reports distinguish directional and pooled results and preserve scientific
sampling policy. They make no R-squared, DOF or parameter-uncertainty claim.
Comparison publication includes the reusable CORE statistical records. Changing
coordinate units invalidates cached comparisons. An older or stale saved receipt requires an explicit Compare to obtain current
semantics without changing its source geometry.
<a id="dev097-scientific-coordinate-integration--development-checkpoint"></a>
## Scientific coordinate integration

**View → Axis display units…** selects X and Y independently through compatible
CORE conversions. Choices belong to the named Workspace. **Use Dataset defaults**
removes those overrides. **View → Dataset coordinates…** opens the shared editor
for persistent display defaults, per-Variable magnification/pivot and explicit
calibration. Saving calibration does not change Workbench calculations or samples;
the shared editor offers explicit Derived Dataset creation when desired.

Ticks, pointer coordinates, point tables/handles, numeric point edits and X-range
selection use the chosen display units. Edits convert back to the Native frame.
The view policy identifies its Dataset basis; Fit captures a canonical reference
range and applies magnification once. Subsequent pan/zoom is transient view state,
retained by Workspace save/reopen. Changing only display units preserves it.
Changing magnification recomputes from the saved reference. Source Dataset bytes,
units and stable Variable IDs stay unchanged. Source/schema mismatch prevents
applying new Dataset policy to frozen geometry and shows the reason.

Unlike physical X/Y axes offer X-based signed Y residuals and axis spans; raw
geometric path/length choices are unavailable. Publication preserves scientific
coordinates and records display choices separately, including explicit flags that
display conversion and effective calibration were not applied to stored output.

**Grid / view…** shows origins and spacing in the selected affine display units;
Apply maps them back through the declared inverse conversion. A stale form rejects
Apply after a source, display-context or active-curve change. Polar controls require
a common physical frame. Nonlinear display relations retain explicitly labelled
geometry grid units because a uniform displayed spacing would be misleading.
Rotation remains in geometry coordinates.

**Export sketch…** captures converted ticks and axis labels, visible curve colors,
points-only mode and actual source/control markers. The SVG and PNG share the same
snapshot; neither changes geometry or materializes a Dataset. Compound direction
markers and centered labels are retained. Export is a frozen presentation captured
when the chooser opens; reopen the chooser after changing the view.

Variable-specific nonlinear normalization requires an explicit Dataset Transform.
Scientific unit declarations and dimension/transform controls retain the explicit
ownership and coordinate policies described below.

Comparisons use the target's selected axis display units for X matching; geometric
comparisons use its X display unit on both compatible axes. Changing that display
choice marks the comparison stale; select Compare explicitly to refresh it through CORE. Receipts/publication preserve both
source units and actual evaluation matrices. Residual plots show those units;
highlight points map back to each original Native frame. Selecting **Geometric
length** on mm/m data normalizes both axes before the Native metric calculation.
Readable menu labels preserve the existing saved metric IDs.


New Dataset sources enter an existing compatible working axis frame when the
CORE can establish positive affine unit conversions. Different physical axes
cannot be imported into a populated incompatible frame. Create a separate
Workspace or explicitly declare/normalize the source first. Historical Workspaces
may retain separate frames: selecting a curve switches those preserved frames
and restores each frame's pan/zoom. The curve list and viewport notice identify
hidden historical frames. Source values, units and stable Dataset/Variable IDs are unchanged.
View → Align Dataset working axes explicitly changes an existing untouched
binding's working frame; Undo/Redo and Workspace reopen retain its conversion.
Historical Workspaces are not silently converted. Custom Variable formulas need
explicit Dataset Transform normalization before physical comparison/alignment.
Whole-Workspace physical unit conversion preserves pan/zoom, including legacy
explicit assumptions for missing source units. Assumptions remain recorded in
Workspace provenance and public CORE presentation receipts; they do not change
canonical Dataset declarations. Geometric metric values follow the active X
display unit after CORE normalization. Opaque/undeclared units do not enable
physical length/area controls. Scientific declarations for unbound geometry and independent coordinate
controls are described below.

## Accepted Fitter models

Fitter’s **Results → Results and publication → Transfer selected model to Workbench…** creates a separate
named Workspace. The curve label states **exact retained model** or **sampled approximation**. X and Y keep independent units. Editable geometry and the
immutable imported scientific model are separate: editing the curve does not
refit data or update the captured coefficients, uncertainty or provenance.
The Workspace owns copies of the model resources and supports ordinary portable
export/import. See [exact transfer and limits](../../../docs/api/FITTER_WORKBENCH_TRANSFER_v1.md).


## Declaring scientific axis meaning

Use **Create → Scientific point curve…** in a new Workspace to enter actual
physical XY points, independent registered units and the reason those units
describe the data. Use **Modify → Declare scientific axis meaning…** for an
existing original unbound curve or a Dataset source with missing units. Choose
`1` explicitly for dimensionless coordinates. A declaration leaves the numerical
values unchanged; **Axis display units…** instead converts compatible displayed
values, while **Physical scale…** changes geometry. These are separate actions.

The declaration and previous meaning stay in scientific History/provenance.
Known Dataset units cannot be relabelled incompatibly: use their legitimate
Unit Registry conversion or create a normalized derived Dataset. Missing source
units remain missing in the original Dataset schema; the explicit Workspace
assumption is retained on reopen and publication. Existing constraints and
dependent curves prevent reinterpretation of their parent frame. Metric CAD
primitives retain their own working units. A scientific Hz/V curve has no physical
Euclidean length; Compare uses signed response residuals.


## Scientific transform and dimension entries

**Move…** accepts X and Y displacements in their independently selected display
units: on a Hz/V curve displayed as kHz/mV, entering1 and2 moves native geometry
by1000Hz and0.002V. **Pivot…** uses displayed coordinate values. **Physical scale…**
uses dimensionless factors about that native pivot. Changing display units does
not change geometry. The operation records displayed inputs and the actual native
transform separately. Reopening a form is required after its coordinate context
changes.

Horizontal/vertical dimensions and X/Y coordinate locks use the corresponding
axis unit. Inline numeric entries use the displayed unit; an explicit compatible
unit is also accepted. Retained parameter formulas continue to use the native
coordinate unit stated in the editor. Numeric values are stored canonically, so
changing display units or reopening cannot multiply a driving dimension again.
Offsets apply to coordinate locks, never to displacement or distance. A nonlinear
display relation cannot define a constant displacement: choose a linear display
unit or explicitly normalize the Dataset.

Rotation and reflection operate in the explicitly authorized native coordinate
plane. For unlike physical axes their angle, radius and norm are numeric plane
parameters; they do not establish physical equivalence, distance or area.
Euclidean physical metrics retain their compatible-unit checks. Geometry may use
independent display units; reflection-axis points convert back to the native
frame before Native2D acts.
The rotation form calls this **Numeric plane rotation (degrees)**. Angular and
mixed-axis scalar dimension labels identify both stored native axes, for example
`rad · native plane X [V], Y [A]` or `numeric plane parameter · native plane
X [V], Y [A]`. Read these as parameters of that chosen plane, not a physical
mixed-axis angle or length. X/Y displacements and coordinate locks retain their
own axis units; changing display units does not redefine the native plane.

If an open Join/composition or coordinate-action form reports that its coordinate
context changed, close and reopen that action after reviewing the current frame.
For example, a form opened before a whole-Workspace unit conversion cannot apply
its old coordinate inputs to the converted state. An active handle gesture may
instead be cancelled by that conversion; start a fresh gesture afterward.

Use **Workspace → Workspace Configuration…** for the physical context of a new
or empty workspace, and **Axis display units…** for presentation choices. Exact primitive parameters identify
local native units explicitly because their retained world transform is separate.

## Common physical working units

Creation Configuration accepts registered or CORE-validated intrinsic unit
expressions. V/V, kg/kg and (m/s)/(m/s) planes support
the same applicable Native2D primitives as mm/mm. **Working units…** converts a
whole consistent frame explicitly: cm→mm multiplies coordinates by10 and mV→V by
0.001. Known mixed source units must first be normalized explicitly with Dataset
Transform; no implicit aspect normalization changes their scientific meaning.

V/mA and kg/(m/s) remain independent scientific axes and are rejected for Euclidean
CAD. Unknown, opaque, nonlinear and affine-origin units cannot define that metric.
Distance and area receipts use the actual formal units, for example V and V² or
m/s and `(m/s)^2`. Compound square labels preserve mathematical grouping and do
not promise conversion of every formal expression. Physical Native3D/export and
raster-calibration contracts still require length where their API mandates it.
Source Dataset/Variable identities and bytes remain unchanged; Workspace,
History, Undo/Redo and explicit publication retain the conversion provenance.

### Workspace physical Configuration and Dataset intake

**Workspace → New named workspace…** asks for the name, X and Y stored coordinate
units, and **Allow dimensionally heterogeneous axes**, initially off. Unit Registry
dimensions determine homogeneity; similar numerical ranges do not. Use `1` for an
explicit dimensionless axis or an empty unit for plain numeric coordinates.
**Workspace Configuration…** exposes the same policy. It cannot relabel stored
coordinates after geometry exists; use an explicit compatible conversion instead.

Adding a canonical Dataset to a genuinely empty workspace adopts its actual X/Y
Variable units and source meaning. Heterogeneous quantities such as V/A require
the explicit Configuration opt-in before intake. Numeric axes remain numeric.
A populated workspace retains its dimensional identity and coordinates: an
incoming compatible source can be converted into that working frame with recorded
provenance, while incompatible or undeclared frames require a separate workspace
or an explicit source declaration/normalization. Original Dataset bytes and
Variable identities remain unchanged. Stored units, display units and calibration
are separate. Preserved historical heterogeneous workspaces are not silently
given consent for new heterogeneous geometry or imports.

Native construction and point editing use the current declared coordinate frame.
Dimension-dependent Euclidean distances, areas and other metric actions retain
their existing compatibility checks; independent scientific axes do not acquire
physical length merely because a geometric primitive is visible.

Axis graduations use the shared Native2D numerical planner at their true world
positions. Tick marks and the light dashed scientific grid align with the labels;
the authored CAD construction/snap grid remains separate. Zoom, pan and resize
adapt graduation spacing and automatic engineering prefixes through Unit Registry.
For numeric/dimensionless axes, a displayed `×10^n` multiplier introduces no physical
unit. Explicit axis display-unit choices remain fixed. Presentation changes never
rewrite geometry or canonical source values. Native exports consume the same
mapped tick positions instead of six arbitrary viewport fractions.

### Opening a canonical Sketch Dataset

Use the Dataset browser's **Open** action for a canonical Sketch Dataset. This
opens an editable new draft; it does not reinterpret or replace its source.
To show its imported objects, enable **Settings → Left utility area** and
**Settings → Objects list**. Click a visible object-name row to select it; the
existing tables show its defining handles or points. These visibility controls
do not change the source Dataset.

When an object has unlike effective X/Y dimensions, **Review Sketch coordinate
plane** shows an example's stored and effective units before replacing a draft.
Identical stored unit labels alone do not establish matching physical dimensions.

**No** is the default: it leaves the current Workspace in place, or creates no
Workbench window if none is open. **Yes** explicitly enables **Allow dimensionally
heterogeneous axes** for this new draft. Existing Save/discard/Cancel questions
still apply when replacing another draft. That consent does not convert source
values, establish physical metric equivalence, or silently carry the previous
Workspace's policy into a new draft.

If the reviewed Session, source or parent window changes, reopen the Dataset
rather than applying an old review. A rejection during later window construction
can leave an empty new draft; it does not promise restoration of a closed window.
Homogeneous objects need no extra axis-review question. The existing **Add curve…**
route for ordinary table Datasets still uses the Workspace Configuration policy
described above. Keep that policy enabled while heterogeneous geometry remains;
turning it off cannot reinterpret existing geometry.

**Help → User Manual… / F1** opens this rendered guide in an independent nonmodal
window. Search, links, scrolling and navigation belong to this manual; other
Viewer manuals and the main GX-TXT Help remain independent.


## Return a retained edit to its originating 3D Workspace

The 3D Workbench's section/projection actions open a distinct retained 2D draft
with a calibrated original reference image. **Show 3D Reference Image** and its
opacity control affect presentation only. Edit retained paths/primitive parameters
in the captured physical unit; the original 3D body is never edited by 2D dragging.

**Accept → 3D** retains the accepted planar result, then asks the original 3D owner
to add a separate profile to the same captured Workspace. Exact path vertices and
retained definitions are preserved; other retained families explicitly identify
their 257-sample 3D profile approximation. Depth discarded by projection cannot be
reconstructed. New profile extrusion/replacement is an independent 3D action.

Original owner generation/revision/SHA, body identity, units and plane are checked.
A stale origin is refused. Cancel writes nothing to the original 3D owner. If only
the accepted planar stage committed, it remains retained and the draft offers
**Commit staged result → 3D**. Retry does not duplicate an already committed result;
it cannot silently accept a changed original. Save/reopen retains that pending
context through the existing Workspace, without serializing worker tokens.
See [the public planar-return contract](../../../docs/api/NATIVE_3D_PLANAR_RETURN_v1.md).

## DEV111-P010 — embedded comparison controls

The existing canvas **Compare / residuals** header opens a scrollable ViewportHost
panel with two compact sections. There is no permanent comparison row above the
canvas and no independent comparison window. Selectors show names plus stable
logical curve IDs; active drawing/selection changes do not substitute another
Target. Invalid, identical, missing and incompatible pairs receive an inline
explanation through the existing validation services. Missing IDs remain visibly
unavailable rather than silently selecting another object.

**Curve Comparison** contains both path selectors, Method, Compare, current
status, existing Statistics receipt values and Publish deviations with its
prerequisite explanation. **Geometric Measurements** retains the existing active
path metric, numeric Expected value, Evaluate and measured/difference output.
Use the scrollbar or normal focus navigation to reach controls in a small panel.

Click the header to collapse/reopen controls. The existing close button hides the
panel; **View → Compare / residuals** reopens that same panel. A current residual
graph stays with its original Plot v4 owner when controls are collapsed or hidden.
Neither opening nor resizing/collapsing the panel evaluates a comparison.
Publication rechecks the current pair/receipt and Session, including changes made
while its reviewed dialog is open, then uses the original Dataset writer/schema/
sampling/projection/provenance workflow.

Completed definitions/receipts retain their existing Workspace and Undo/Redo
format. Uncompared edits to the new Target selector are local to the open GUI;
Compare commits the explicit pair through that existing owner. No persistent
format, scientific engine, renderer, cache, module category or GUI system is added.
