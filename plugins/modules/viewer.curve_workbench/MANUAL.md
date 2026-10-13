## Drawing paths and reopening Workspaces

Spline instructions appear once beside live coordinates. Click an existing
line/branch defining point to finish the current Path placement; the tool stays
ready for another Path until Escape. Existing Workspaces without a CAD
block reopen normally. If restoration genuinely fails, the original saved
Workspace remains protected and the status shows its cause.

## Connected paths, constraints and parameter formulas

Paths retain branched networks and shared junctions. Click an existing defining
point while drawing to connect automatically. Select exact internal segments with
Ctrl and use Constraints or the canvas right-click menu. Spline knots expose both
available tangent arms. Separate is not needed for these operations.

Parameters... opens the framework editor for this Workspace. Create `span` with
formula `session.base * 3`, then enter `span` in a dimensional constraint. Formula
changes recalculate geometry and save in the canonical Workspace. Session Parameters
is managed in the Session page dropdown. Workspace Actions invokes this same editor.
Core documentation: `docs/api/CORE_PARAMETER_SERVICE_v1.md` and
`docs/api/NATIVE_2D_GEOMETRY_API_v1.md` in the installed framework.

## Grid and Spline controls

A new Workspace opens with a visible grid and equal X/Y visual scale. The
initial vertical extent is 20 grid units, with extra horizontal room adapted
to the canvas. The operation indicator and live coordinates share one row.
Grid spacing/appearance are in Grid / view; coordinate aspect overrides are
reserved for module/host APIs.

In Select, click an interior Spline knot to display its incoming and outgoing
arms. Drag either arm to edit the exact retained shape. This works identically
for a standalone Spline and a Spline inside a composed Path. The Path stays one
object; Separate is unnecessary. Endpoint knots expose only their existing side.
See the [Dataset navigation guide](../../../docs/help/datasets.md).

## Pivots and constituent editing

Activate Transform/Pivot even with no selected curves. Click empty canvas to
place the pivot, or drag the gizmo center. Select the intended curve afterward;
the placed custom pivot remains the Workbench transform state.

Draw a Line/Polyline or Spline from a compatible retained endpoint. Finishing
the new stroke automatically forms one logical Path in the object list. In
Select mode, drag any displayed constituent vertex/control directly, or select
its defining-handle row and apply X/Y. Shared Path junctions remain connected.
Exact primitive definitions stay authoritative; Separate is optional for
making independent copies, not required for editing a Path.

## Toolbar and selection modes

Select and Transform/Pivot appear in the compact pictographic toolbar directly
above the canvas. Left-click activates the existing tool; right-click Select
chooses a selection mode and right-click Transform/Pivot chooses Translate or
Rotate. The upper mixed command and sketch bars have no duplicate buttons.

## Joining, separating and selecting paths

The main and sketch toolbars use the shared arrow glyph for Select. The main
glyph's right-click menu chooses selection mode. Join Path (`j`) consumes a
compatible connected selection and presents one logical Path, retaining the
exact Polyline, Spline, Bézier, Arc or other supported constituent definitions.
Internal coincident junctions become part of the Path topology; constraints to
outside geometry prevent Join. Undo restores the source objects and internal
relations. Separate exact constituents creates editable copies while preserving
the Path. See [Viewers guide](../../../docs/help/viewers.md).

## Drawing and canvas interactions

**Create → Line** draws one continuous retained path. Click the start, then each
successive vertex; Enter or Finish commits it. Two vertices make one segment.
Clicking the start again closes the path with one shared vertex. Escape cancels an
unfinished path. Segments and defining vertices remain selectable and dimensionable.
Use **Modify → Split selected Path / entity…** or **Join Path…** (`j`).
Heterogeneous endpoint-connected primitives retain exact definitions; disconnected
or closed primitives use **Combine / Compound…** (`Shift+j`). Sources remain
available. **Separate exact constituents** creates editable copies. See
[Workbench manual](../../../docs/help/viewers.md) for sampling,
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

Residuals remain blank until you choose a reference and explicitly click **Compare**.
The comparison records its reference and target; changing property focus does not
retarget it. Editing the active comparison geometry updates it. Disable comparison
to stop calculation. This explicit state survives save/reopen.

Wheel zoom updates immediately, with one checkpoint after a burst. Pan draws at a
coalesced frame cadence and checkpoints when released. Chrome only relayouts when
resize, panel, Settings, theme/font/DPI state changes. Reference images render
asynchronously through the existing calibrated Native plan; canvas interaction
remains responsive. Named workspaces, notes, previews, symmetry, tangents, context
menus and Settings retain the workflows below.

## Sketch constraints and dimensions

Draw using **Create**, then click bodies/segments or defining handles to select. Ctrl adds references; Shift subtracts. **Constraints** applies a supported relationship to the current selection; **Start constraint tool** selects a tool before selecting its geometry. The tool hint states what to select next; Esc cancels to Select. Native2D drives the retained component and preserves compatible relationships through later handle/gizmo edits. Unsupported selections produce a clear message. Fix locks a complete selected body, or the selected control; **Unfix** removes its Fixed relationships.

Use **Dimension** (D), select a line/round primitive, point or two compatible references, move the pointer to preview the dimension and choose orientation/side, then click to place it. Enter a number in the small canvas editor and press Enter. Optional compatible suffixes such as `0.25 cm` use Unit Registry conversion; angles use rad and may use compatible angle units. Plain numeric input is supported; parameter expressions use the CORE Parameter Service in supported dimension editors. No internal IDs or indexes are required.

Linear types include horizontal/vertical/aligned point distances, line length, point-line distance and parallel-line separation. Angular types include two-line angle and line angle to X. Circular types are R/Ø. Select a defining point for X/Y position to sketch origin. The Constraints menu can choose a specific type; the Dimension tool infers it. Witnesses, arrows, arcs, notation, unit and readable value are drawn before committing and remain associated with the geometry.

Driving dimensions change geometry. If a new driving dimension conflicts or adds no independent local condition, the inline editor offers **Create as reference**. A reference measures existing geometry, updates automatically, uses parentheses/dashed lines and is read-only. Double click a driving dimension to edit inline. Drag its annotation in Select to move the label/witness layout without changing value or geometry; this is one undoable presentation action. Right click offers Edit, Enable/Disable, Delete, Details, valid Driving/Reference toggle and reset position.

Badges use original GX-TXT symbols, enlarged hit regions, hover/name feedback, selected borders and associated-geometry highlighting. Click near the visible badge, right click to manage it, or Tab through visible relationships and Delete the selection. Defining handles take precedence over nearby dimension regions; modifiers and double clicks retain their tool meaning.

**Sketch palette** / **Inspector** is inside the Workbench. It shows active relationships, available constraints, construction/reference role, dimension mode and truthful local component DOFs. Show Constraints and Show Dimensions are independent and saved with the existing workspace state. Hide retains the panel's lifecycle. Advanced remains a separate expert reference editor. Fixed/locked/conflicting/stale edit rejection removes previews/drags/captured references, thaws controls and returns to Select; subsequent mouse-up and Escape are harmless.

Tangency supports finite line/circle/arc, circle/arc pairs (including internal branch), and supported Bézier/Spline endpoint joins with lines/curves/rounds. G2 uses actual endpoint curvature for quadratic/cubic Bézier and the existing Catmull-Rom Spline; it includes positional/tangent continuity. Equal supports straight segments and round radii; concentric includes ellipse centers. Symmetry supports points and compatible line/circle/Bézier/Spline/polyline objects about a selected straight axis. Unsupported arc/ellipse/rectangle object symmetry is rejected. Point-on-curve uses native retained evaluation. Legacy scientific Native point-curve relationships retain their validation behavior; reference measurements remain distinct from retained driving.

The solver is local and bounded:64 objects,256 parameters,1024 residual slots and100 iterations. Singular, unsupported or nonconvergent cases reject atomically. Local rank is not a global uniqueness proof, and legacy/generic components are explicitly marked partial analysis. All Dataset rows, source bytes, retained definitions, conversion paths, publication, units, Undo/Redo and recovery continue to use their existing authorities. See the public [Native2D Geometry API](../../../docs/api/NATIVE_2D_GEOMETRY_API_v1.md) and [CORE implementation notes](../../../core/native2d/README.md).

## Scientific recipes and Workspace operations

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

Choose a reference curve and **x** or **path** in the validation row, then **Compare / residuals**. X comparison samples the derived curve at valid reference X positions and requires single-valued monotonic X for both curves. Path comparison aligns curves by normalized cumulative path position and handles folded profiles. The main view overlays both curves and marks the largest deviation; the lower panel plots signed residual against reference X or path distance. The status reports sample count, maximum absolute residual, mean absolute residual, and RMSE. Edits recalculate an available comparison after commit. Disconnected compositions must be compared by their separate fragments.

Comparison summaries use every exact native reference point. CORE reduces only
the residual presentation to a bounded ordered set, retaining the maximum and
its exact original residual ordinal. View changes do not change scientific
comparison results.

The 2-D metric selector reports path length, X/Y span, length-to-X-span ratio, or signed enclosed area for a connected closed curve. Enter a target for a live signed error after edits. The **External downstream feedback** field records measurements from a separate geometry/CFD workflow; Curve Workbench does not calculate extrusion or 3-D surface metrics.

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
public Unit Registry and Native2D. Select the current and target length units;
undeclared coordinates require the explicit assumption checkbox. Known mixed
units reject the whole action. Normalize calibrated source coordinates with
Dataset Transform before proportional frame conversion. Physical geometry
size and canvas position stay unchanged; this differs from **Physical scale…**.
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

Choose a different reference and the `geometry` method, then Compare. Native2D evaluates 257 scientific query positions independently of display caches. The view shows unsigned curve distance by sampled reference path, plus RMS, sampled bidirectional Hausdorff and closest distance. Retained mathematical definitions remain authoritative; the captured report records which target projections/closest pairs are exact and which use bounded scientific samples. These sampled metrics do not assert continuous Hausdorff extrema.

Publish deviations… creates an explicitly named Dataset containing query/projected XY pairs, unsigned distances, sampled path and indices, with source/fingerprint/units/policy metadata. Geometry edits make the receipt stale and clear its presentation; Compare again before publishing. Measurements… also offers geometric RMS, sampled Hausdorff, length/closed-area difference and closest-curve distance with configurable 6–4096 scientific samples. Use its shared explicit Refresh, one Undo, stale/missing inspection and normal report publication.


## Native2D selection and complete-data behavior

The point table and canvas preserve one logical point selection. Repeated/rapid row clicks coalesce to the newest selection at idle. An active Native gesture retains the pending selection until release/cancellation; its generation and owner are checked before applying it. Table refresh does not recursively rebuild the selection scene. Ctrl/Shift selects multiple points; one selected point populates X/Y. Dataset row identities draw red locator rings; pure Native geometry has no Dataset row. The sidebar scrolls vertically; Tab scrolls the focused point/numeric/composition control into view. Publication controls wrap with labels at narrow widths and larger fonts.

Coordinates chooses Cartesian, polar or both; Arrangement chooses a concatenated table, long family or exact shared-X wide output. Normal publication preserves your requested public Dataset ID, validates/collision-checks it and uses CORE Dataset Transform/Publication/Schema/Metadata. Dataset-backed sources preserve complete typed auxiliary tuples, including exact uint64/text. Edited Native derivatives use immutable source-row lineage to recover the original auxiliary tuple and replace only accepted XY. Pure Native rows carry no source Dataset ID and explicitly mark unavailable auxiliaries with validity0, zero/empty placeholders. Long families preserve per-member auxiliary descriptors and presence masks. Wide output requires identical point counts and X values, with no implicit interpolation. Wide polar output is rejected because it has multiple independent Y bindings; use table/long polar for one coordinate pair.

Polar output uses the shared Native frame: origin, theta-zero, CW/CCW and degrees/radians. Radius uses the working length unit, angle uses deg/rad; origin has an explicit theta_defined0 mask and a zero placeholder. Normalization covers one positive full turn without implicit unwrapping. Source Preview opens the real public Dataset ID. Missing/stale sources are visible; saved owned local geometry remains available. Source-tuple publication rejects missing/stale dependencies until you explicitly reload/restore them. No automatic geometry replacement occurs.


## CAD Workspace

### Objects in one workspace

The object list distinguishes an immutable **Dataset source**, an exact **Retained line/circle/arc/etc.**, and an editable **Native point curve**. Dataset rows keep their exact source identities and red locators; off-viewport markers are omitted without changing selection. Pure Native points have no Dataset-row locator. Retained primitives expose defining handles rather than rendering samples. Names are display labels on existing logical identities, never another identity system.

### Draw and edit

**Create** opens Point, Line, Rectangle, Circle, Arc, Ellipse, quadratic/cubic Bézier, Polyline and Spline. Click defining positions on the canvas. Circle uses center then perimeter; Arc uses center, start and end (counterclockwise sweep); Ellipse uses center, major-axis position and minor-axis extent; Bézier uses its true control polygon. Rectangle uses opposite corners. Polyline/Spline finish with Enter, Space or **Finish**. Canvas creation chooses X=Y aspect so a circle is displayed as a circle; scientific Auto aspect remains available in Grid/view.

Pointer motion displays a transient Native preview; circle/arc previews show a radius witness and value. **Esc**, changing tool or closing cancels incomplete tools without a document/history entry. **Object snap** uses Native endpoint/center/control/midpoint candidates, with visible feedback. Grid snapping remains independent. Defining-point attachment now creates persistent Native Coincident relationships with visible attachment feedback. Incompatible projected control roles reject clearly.

**Select** clicks a body, segment or defining control; Ctrl adds retained references; Shift subtracts. The defining-handle table provides the same references. Drag a handle to edit its exact Native definition; center drag moves a round primitive, perimeter drag edits its radius, line endpoints/Bezier controls edit their parameters. Preview is separate from the commit on release. Rejected constraint edits preserve geometry/history with a visible reason. **Modify → Move/Rotate on canvas** uses existing Native gizmos. Exact parameters and numeric handle X/Y remain available. Existing Native point operations/groups are preserved behind **Modify → Native point operations / groups…**; scientific range, composition, comparison, measurement and publication controls remain available.

### Constrain and dimension

Select geometry, then **Constraints**, or right-click on the canvas. Native2D offers structurally compatible relationships only. Select two line bodies/segments for Parallel/Perpendicular/Angle; two defining controls for Coincident/Distance; a round body for Radius/Diameter; two round bodies for Concentric/Equal Radius; point control plus body for Point-on-curve. Horizontal/Vertical, locks, equal length, midpoint, collinear, supported line/circle tangent and symmetry use the same native model.

The Native retained-component solver drives supported relationships and compatible later edits atomically. Tangent covers supported line/circle/arc and Bézier/Spline joins; Curvature / G2 uses actual supported endpoint continuity. Unsupported combinations report a reason. The Sketch Palette reports truthful bounded local rank/DOF status, with singular/global analysis limits. Fixed/locked conflicts restore a clean idle state.

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

Use the unit chooser/Working units dialog and existing Unit Registry. Geometry conversions require declared compatible length units; resolve ambiguous X/Y bindings explicitly rather than guessing. Existing complete-workspace conversion rescales geometry and dimensional relationships together. Angular labels use rad. One created object, accepted fit, control edit, relationship or dimension edit is one Undo; preview/cancel produces no history spam. Publication is an explicit Session operation and does not replace the document object.

Save workspace and close normally. Existing Interactive Documents/owned resources/recovery persist mixed types, definitions/transforms, constraints/dimensions, Dataset bindings, roles, names and conversion provenance. Transient tool/hover/incomplete previews are excluded. Reopen in a fresh process and continue exact parameter editing. Keyboard focus, numeric forms, Enter/Space/Esc, scroll-to-focused controls and wrapping toolbars provide alternatives to mouse input.

Original validation screenshots are not included in this source distribution.

### Drawing tools and compact controls

Line creates separate connected retained segments continuously; click successive endpoints, then Esc or Finish. Click a chain's initial/intermediate defining endpoint for semantic closure. Polyline and Spline remain separate primitives; Enter/Finish completes them. Endpoint coincidence does not mean periodic spline topology. Placed defining controls and attachment feedback remain visible. Single Points are filled dots even when deselected.

Objects contains selection operations including explicit Show/Hide; they cover the full current selection in one Undo. Points/ranges contains the existing scientific point/range operations. View contains Pan, Fit, Source Dataset Preview and More scientific controls. All existing source, range, composition, measurement, comparison, fitting, representation and publication workflows remain available. Compact Constraints groups Directions, Connections, Shape, Fixing and Dimensional, with corresponding tool-first cascades.

For multiple selected publishable objects, Publish selected curve(s) publishes all of them through the chosen Coordinates/Arrangement. Publish selection offers One structured Dataset or Separate Dataset outputs. Review every separate Dataset ID before Publish reviewed batch. All ID collisions are checked before any output starts; the status lists the actual output IDs. Retained outputs use explicit uniform parameter sampling and preserve exact definition/provenance for reconstruction. Sources remain unchanged.

## Remote X11 behavior

Viewport icons, tool instructions and the publication footer are visible on an
idle forwarded display. The initial window reserves space for native decorations
and a taskbar. The utility area and Sketch palette have scrollbars; Settings
controls their visibility. Create tools keep the placed preview visible while
placing additional controls; Enter / Finish commits and Escape returns to Select.
Ordinary network latency is expected. No local-Xorg performance equivalence is
required. Retained geometry, constraints, parameters and Save Workspace follow
the existing scientific and Session authorities.

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
and available operations. History already discarded by an older release cannot be
recovered. The strip is a projection of the saved CORE recipe, not a second history
database or a global Session Undo stack.


## Direction markers and reference graphics

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
