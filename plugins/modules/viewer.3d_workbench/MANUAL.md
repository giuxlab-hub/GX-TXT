# 3D Workbench

**Compare complete geometry / deviations…** captures a named reference/target
comparison through Native. Inspect RMS, sampled Hausdorff/closest, exact Native
area/defined-volume differences, complete bounds and scientific policies. Source
changes make the result stale; Refresh explicitly. Scientific vertex budgets are
independent of display LOD, and B-Rep tessellation quality/limits are explicit.
Publish deviations uses the requested public Dataset ID, normal storage/Schema
and provenance, bounded row batches and standard Preview/consumer workflows.
Reference/construction geometry may participate in inspection. Unit conversion
reexpresses dimensional comparison parameters; captured metrics remain stale
until an explicit refresh. Compare/capture/refresh each has one Undo.

**Selection Sets / Layers / Saved Views…** manages three distinct persistent
records. Sets capture logical objects or explicit B-Rep vertex/edge/face anchors;
changes mark captured references stale rather than remapping them. Use Edit and
Recapture to repair the chosen Set. Activate selects its current logical rows.
Layers independently control color, opacity, visibility, selectability and edit
locks; locks apply to public Native3D geometry calls. Groups remain transform
containers. Names such as inlet/walls do not impose external solver semantics.

Saved Views capture camera/projection, background, clipping, working plane,
object visibility/styles and Layer presentation. Restore preserves complete
scientific geometry. Missing object/Layer references and changed coordinate units
reject before mutation; recapture explicitly after coordinate conversion.

Details includes shared regular/construction/reference roles. Native owns object
roles; copies and document/resource restore preserve them. All roles remain
available for inspection and constraints. Normal Dataset publication rejects
reference/construction results; explicitly create a regular copy when intended.
Role changes have one Undo.

**Scientific Recipe Recorder…** displays accepted semantic operations, validates
sources/APIs/plugins/units and replays through one staged Native transaction.
Export as Python, run unchanged in Script Workspace, and package the same source
with Builder profile W for invocation through **Extensions…**. Recipes retain
Session-owned scientific resources; move/copy their Session through normal APIs.
Extensions support structured primitive creation, translation/rotation/scale,
identity, deletion and recipe proposals with full candidate-scene rollback.

The Workbench uses the shared CORE Native3D host, isolated worker and OCCT
kernel. Exact B-Rep solids and complete meshes remain unpublished Interactive
Document resources until **Publish selected as Dataset…** is used. A typed
object tree distinguishes B-Rep and mesh records.

Choose an ordered X/Y Dataset with both coordinate units matching the explicit
working unit (initially mm). Choose the working plane in the shared view controls
and apply it before loading a closed profile. Enter a signed distance, choose
New/Join/Cut/Intersect and an unlocked B-Rep target where needed. Preview and
Accept use the same retained CORE result. Cancel removes the preview.

Box and Cylinder use the public analytical solid APIs. Shared navigation,
navcube, presentation and transform gizmos use the existing Native3D host.
Accepted geometry is stored as complete owned STEP/STL resources. STEP input
is converted from millimetres back to the document working unit on restore.
Undo/Redo store at most 32 semantic snapshots and recipes at most 128 operations.
Acknowledged body/profile/group/constraint/measurement allocation counters are
stored separately from undo snapshots. Undo retires committed logical IDs, and
new objects after undo/reopen receive unused IDs. A failed uncommitted action can
retry its pending ID. Older documents seed counters from retained snapshots.

Publication preserves the requested public Dataset ID, checks collisions and
uses the normal Dataset File Publication and Metadata APIs. STEP produces
`model.cad`; STL/VTP produces `geometry.mesh`. Tessellated output is derived
from the full B-Rep with explicit budgets and never from its display preview.

The complete geometry, Workspace, export and recovery behavior is described in this manual and the public Native3D API contracts.

The current controller also provides shared typed forms for coordinate
transforms, complete tessellation, clean/weld/orient/heal, clipping/capping and
analytical sections. Profile and section lines render through complete Native3D
VTP resources. Group creation preserves logical object IDs; group transforms
use one CORE group placement and duplication uses atomic subtree copy.

Working-unit conversion uses Unit Registry and public coordinate rescaling.
It changes local coordinate numbers and translations while preserving physical
rotation/scale separately. Reset after conversion retains physical size in the
new unit. Profile intake can explicitly convert compatible Dataset coordinates
through an unpublished Dataset Transform; missing units require an explicit
assumption. Sources remain unchanged.

Constraint definitions are persisted and listed with references, target,
status, residual and tolerance. Fixed, point, line, plane, surface and axis
constraints use the public CORE solver. CORE can satisfy a target while leaving
degrees of freedom; this is reported as underdetermined. Incompatible sets
retain source geometry. Constrained group movement currently requires removing
or solving the relevant object constraints first.

Measurements use all twelve CORE kinds, explicit world/local points and working
units (angular results are radians). Supported value/marker annotations use
the shared Native3D presentation. A measurement retains its source snapshot;
inspection marks it stale if that geometry or a referenced surface changes.
Stale/missing records retain their previous value, while their Native markers and
value annotations stay hidden. **Inspect measurements…** offers explicit
**Refresh selected against current geometry** and **Delete selected measurements**.
Refresh resolves all selected anchors through CORE before saving any values;
invalid or missing topology aborts the entire action. Delete removes only the
selected records and their own annotations. Each action has one undo boundary.
Working-unit conversion also converts saved length anchors, plane origins and
length results; refreshed geometry references remain an explicit inspection step.

**Publish selected measurements as Dataset…** publishes a current inspection
table through the common Dataset Publication v2 writer. Enter the public Dataset
name/ID and choose Auto/CSV/HDF5. The requested ID is preserved and collisions
remain explicit. Stale or missing measurements require refresh before publication.
Rows contain stable measurement/object IDs, kind, value, unit, complete geometry
fingerprint, captured anchors and world placement. The numeric value variable has
a schema unit when selected measurements share one unit; mixed reports retain
their units in the explicit per-row unit column. Metadata retains document
revision, original real Dataset IDs and source fingerprints, including unpublished
unit-normalization Transform views. Shared Dataset Preview and normal Session
consumers can open the resulting Dataset. Anchor specifications are data-only
Tcl list/dictionary notation, declared in metadata; they are never executed.

Actions verify presentation staging before checkpointing the authoritative
document. A failed checkpoint restores the document-facing model, view, recipe
and undo state for retry. Resource cleanup follows a successful commit; cleanup
failure is reported as pending while preserving the committed action and undo.

**Combine B-Rep bodies…** previews Join, Cut or Intersect using an explicit target
and ordered tool IDs. Select bodies with Ctrl in the tree to prefill the form.
Combine requires validated closed B-Rep solids. Triangle meshes use their
separate mesh operations. Sources stay unchanged during review; Cancel disposes
only the preview. Accept transfers the identical reviewed Native result with
frozen source/provenance records. Choose a new derived body (default) or explicit
target replacement, and whether to keep tool bodies. One Undo restores target
and removed tools. Referenced constraints become stale/missing when replacement
or tool removal invalidates their geometry.

**Import mesh / CAD Dataset…** consumes a logical Session Dataset through the
public Native3D intake API. It owns complete geometry locally without changing or
publishing a Dataset. STEP uses embedded units. STL/OBJ/VTP use published mesh
unit metadata, or the explicitly chosen input-unit assumption when none exists.
Working-unit conversion, original SHA/resource and source ID remain in the
result provenance and survive save/reopen. Intake has one Undo boundary.

Undo and Redo hydrate a separate retained Native scene and verify presentation
before checkpointing history. A failed restore/checkpoint retains the original
live scene, authoritative document, history and settings for retry. Old scene
cleanup occurs after a successful commit and a cleanup error is reported visibly.

**Append / merge / stitch / bridge meshes…** derives a new complete mesh from
explicit source choices, preserving both sources and recording their snapshots
in one undo action. Tolerances use current working-coordinate units; Bridge uses
a positive maximum gap and requires compatible unambiguous open boundaries.
The Edit chooser adds **mesh_heal_seam** for exactly two compatible boundaries,
**mesh_lod** for an explicit derived reduced mesh, and **align_three_points** for
three congruent local/world point pairs with a positive alignment tolerance.
Rigid alignment derives an independent result and leaves its source available.

**mesh_boundaries** and **mesh_intersection_pairs** open a read-only inspector
with exact complete counts, bounded source identities/world coordinates and
visible truncation status. Inspection adds no document/history action. The
inspector supports vertical/horizontal navigation and Escape/Close. Append and
Merge remain separate from Boolean Combine; disconnected closed components
retain CORE's explicitly undefined volume status.

**Extrusion targets / keep tool…** accepts an explicit ordered list of unlocked
B-Rep target IDs (Ctrl-select tree rows to prefill), plus a separate keep-tool
choice. Empty targets use the main target control. The main New/Join/Cut/Intersect
mode and signed distance still define the operation. New creates one local body;
other modes review an independent CORE Boolean result for every target. All
results and the optional separate extruded tool are displayed before acceptance.
Cancel preserves every accepted source. Accept transfers the reviewed Native
results with frozen profile/target provenance in one checkpoint/undo action.
A failed checkpoint retains all preview bodies for retry. Replacement invalidates
attached constraint topology explicitly. No Dataset is created unless published.

The shared CORE recovery journal retains a consistent semantic checkpoint and a
separate last explicitly saved state, including owned solid/mesh resources,
source identities and operation provenance. After an unclean exit, the recovery
dialog offers **Recover**, **Open last saved state** and revision/receipt details.
Cancel leaves the saved Session untouched. Recover does not advance the saved
snapshot. **Save Workbench state**, Session Save and normal close compact valid
journals and mark them clean. Corrupt journals remain visible as warnings while
normal scientific Document open/save/close stays usable. A recovery-write failure
after acceptance explicitly reports that the geometry action committed and keeps
the preceding consistent checkpoint. Failed scientific or authoritative Document
staging does not advance recovery. Large geometry stays in content-addressed
owned resources protected by valid saved/checkpoint references.
See [CORE recovery API](../../../docs/api/WORKBENCH_RECOVERY_API_v1.md).

**Interactive Documents…** opens the shared owner/revision browser. Explicit
reviewed deletion closes the selected Document's live Native scope/renderer and
cleans unreferenced owned resources and recovery state. Other Documents, source
Datasets and published results remain available. Published provenance resources
survive as read-only retained resources. A changed revision or Session invalidates
the dialog's captured review; Refresh before confirming a new deletion.


## Native3D Workspace behavior

The complete profile/plane/extrude, transforms/gizmos/group/alignment/constraint, B-Rep Combine, section, measurement/area/volume, tessellate/diagnose/clean/weld/orient/boundaries/intersections/clip-cap workflow is implemented through the shared Native3D host and public scoped CORE geometry API. Escape cancels an active native gesture at a coalesced worker-idle boundary before rebuilding presentation, preserves the authoritative document/history, and ignores its stale release. Orbit/pan/zoom/NavCube remain shared viewer actions; numeric alternatives use the same geometry authority.

Compare supports complete surfaces and sections in an explicit common plane. Section reports store captured contours, plane origin/normal/U axis, chaining tolerance, working units and bounded plane-XY projected distances; unit conversion makes old results stale until Refresh. Sampled RMS/Hausdorff are explicitly sampled science, independent of display LOD; closest section/curve policies are recorded.

Export geometry… discovers the official STEP/STL/VTP exporter and its shared tessellation quality/resource limits. Native/OCCT/VTK writes complete world geometry with declared units; a `.gxtxt.json` sidecar records logical identity, role, source provenance/SHA and tessellation. Atomic create-only publication rejects geometry or sidecar collisions without overwriting either file. Publish selected as Dataset… uses the same official provider and normal Dataset APIs, preserving the requested public ID (`model.cad` for STEP; `geometry.mesh` for STL/VTP). Reference/construction objects are excluded by default. The normal generic Native3D Viewer and Workbench Dataset intake consume the real published ID/SHA with explicit unit conversion, preserving canonical bytes. Restore reconstructs authoritative presentation layers before restoring measurement markers, including a Session saved only through the Workbench.
