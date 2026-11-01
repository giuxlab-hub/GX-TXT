# 3D CAD Workbench

Development candidate 0.1.6. All scientific operations below are connected to existing public owners through the official Builder and C++ Workspace. Final installed GUI, numerical, persistence and full feature-parity acceptance are pending. The guide describes the declared workflow; it contains no fabricated screenshots or unexecuted scientific result claims.

## Open a scientific document

Start GX-TXT with the intended Session. Open **3D CAD Workbench** under **3D & Geometry**. **Refresh** lists existing canonical geometry documents. Choose a document and use **Open document**, or use **New document** to start an empty scientific model. A different active editable document must be saved and closed first. The editor will not silently replace its current owner.

The working unit is shown with the document controls and applies to the Box X, Box Y, Box Z, cylinder radius and cylinder height fields. The five task pages use a horizontal tab row above the form. Drag the inspector divider when you need more room for dimensions or geometry. Choose an owner-issued object/profile ID and use **Select**, or pick actual geometry in the viewport. **Inspect** refreshes the current document, unit, selection and semantic History projection. The original scientific document, geometry resources, identifiers, History and Recovery remain authoritative.

Use the **Model**, **Mesh**, **Inspect**, **Organize** and **Publish** menus or the corresponding task pages. Both command surfaces refer to the same actions. Drag the normal inspector/canvas splitter to allocate space. The native viewport supplies its existing orbit, pan, zoom, Fit, orientation cube and working-view controls. Finish or cancel an active gesture before changing the document. Escape cancels supported native gestures through their normal owner.

## Select one or several canonical objects

Use **Single object shortcut** to prepare one ID, or use the list under **Objects and retained profiles** to choose targets. Click one list ID, or use Ctrl-click and Shift-click for several IDs. The shortcut and a single selected list row agree; preparing targets does not apply the scientific selection. Choose **replace**, **add** or **subtract**, then press **Select**. Replace makes the chosen IDs the complete selection; Add preserves previous targets and includes the chosen IDs; Subtract removes the chosen IDs. The operation changes selection, not geometry or scientific History. Check the viewport highlight and actual target IDs before a geometry operation. Dynamic rows belong to the current scientific document; reopen the document if a source change invalidates a captured selection.

The single-ID shortcut and extended list use the same owner-projected canonical IDs; older layouts retain their existing single-choice Select behavior. Do not treat a highlighted list row as an accepted transform, group or solid. Groups and other actions operate on the actual owner selection after Select.

In **Layers / sets / saved views…**, select a current saved Selection Set and use **Activate / restore** to replace the selection, **Add Selection Set** to include its members, or **Subtract Selection Set** to remove them. A stale or missing source must be explicitly resolved; changing a Set name does not recapture its geometry. Bodies and supported native anchors retain their original identities. These new015 controls require independent installed GUI validation; contract/Builder success alone is not that validation.

The optional **Reference fields (inactive)** checkbox below the document controls exposes preserved earlier project field declarations. It is off by default. Those reference controls do not execute current operations; use the normal purpose-form actions. Actual primitive dimensions on Solids and the canonical document/object controls remain operative.

## Create exact solids and inspect physical meaning

On **Solids**, choose **box** or **cylinder**. Box X/Y/Z, cylinder radius and cylinder height are positive lengths in the displayed canonical working unit. Enter a name and use **Create solid** in the main toolbar. No geometry exists merely because a default value is displayed. The default box dimensions are 20 × 12 × 8; the initial document normally uses mm, but always check its actual unit.

**Object properties / role…** opens the original owner form for name, visibility, lock, color, attributes and geometry role. **regular**, **construction** and **reference** roles are distinct from visibility. Nonregular geometry is excluded from normal complete-geometry publication. Select objects by their actual logical IDs; a rendered triangle or pixel is not a persistent OCCT face identity.

**Translate…**, **Rotate…**, **Scale geometry…** and **Reset placement…** use the original transform forms and commit owner. Translation and pivots are in the working length unit. Rotation input degrees are converted by the owner to native radians; scale factors are dimensionless. Physical Scale changes geometry, whereas **Convert working length unit…** changes coordinate representation while preserving physical size. Unit conversion can make captured measurements/comparisons stale and requires the existing saved-view unit checks.

**Duplicate object** on **Model** (also on **Solids**) copies exactly one selected accepted, unlocked object through the original geometry owner. First prepare one canonical ID and press **Select**, then choose Duplicate object. The copy receives an independent canonical object ID while the source and its scientific bindings remain preserved. The copy can initially overlap the source; check the IDs, then use **Translate…** for explicit placement. The action creates one normal semantic History operation. Use **Undo geometry** and **Redo geometry** to reverse or restore it, then **Save geometry** for normal persistence. Empty, multiple, stale or locked selection must be resolved through the ordinary owner controls. **Duplicate group** on **Organize** remains a separate operation on a canonical group; it is not the single-object command. MAIN277 accepted installed0.1.6 single-object duplication with exact source preservation, native independent placement, Undo/Redo, normal save/reopen and bounded invalid-selection refusals; group duplication remains a separate owner action and whole§13 acceptance remains separate.

**Working plane…** opens the validated shared plane form. Its origin has length units; normal and U axis are directions. The owner normalizes the right-handed frame. Choose XY/XZ/YZ or provide the intended arbitrary frame through the actual form controls. Changing the current working plane does not change the plane already captured in an existing retained profile.

## Import ordered profiles and extrude

Use **Import ordered XY profile…**. Select a genuine canonical numerical Dataset and distinct enabled X/Y Variable IDs, then explicitly choose closure, append and unit policies. The owner preserves original row identities and verifies Curve Source payload/schema fingerprints, working plane and current document scope when applying the delayed form.

X/Y must have equal physical coordinate units. Convert compatible units explicitly, or use the form's explicit same-working-unit assumption for undeclared coordinates; never infer a unit from a displayed number. Missing-pair gaps, crossed/touching contours, collapsed edges and incompatible profiles can correctly be rejected. Holes/islands remain part of the retained profile contract.

Select the actual retained profile and use **Preview signed extrusion…**. Enter a signed nonzero distance in the working unit and the intended New/Join/Cut/Intersect mode. **Extrusion targets…** selects explicit accepted B-Rep targets and keep-tool policy for multiple affected bodies. Targets must remain current and unlocked; their order and provenance belong to the owner.

A preview is uncommitted geometry. Inspect it, then use **Accept retained preview** or **Cancel retained preview**. Accept applies that reviewed native result after checking its captured source/document scope. Cancel releases its owned uncommitted resources and does not mutate the source solid. Failed cleanup remains explicitly reported for retry. Do not treat a completed form callback as proof that geometry was accepted.

**Combine B-Reps…** operates on actual accepted closed solids. Its trusted form provides target/tool choices, Join/Cut/Intersect policy, new-derived-body versus replacement and keep-tools. It uses the same retained preview and final scope-checked Accept path. Group membership, source bindings and stale constraints remain subject to the original owner checks.

**Retain section profile…** creates a retained profile through the original native section operation. It is different from the interactive Curve Workbench round-trip described below.

## Import CAD and operate on complete meshes

On **Mesh**, **Import CAD / mesh Dataset…** selects a real canonical STEP/STP/STL/OBJ/VTP Dataset, explicit mesh-unit assumption where needed and a local name. The owner verifies the complete source SHA before/after intake and preserves the original resource. STEP embedded units are authoritative; a Dataset label must not override them. Mesh coordinates are converted by Unit Registry into the working unit rather than physically scaled by guesswork.

VTP editable surface intake is an explicit geometry-only conversion. Non-surface cells are rejected rather than silently dropped. Original scientific arrays remain in the immutable source resource; they are not falsely reinterpreted as a CAD material model.

The available trusted operations are:

| Action | Scientific scope |
|---|---|
|Tessellate complete geometry…|Explicit full geometry with deflection, angle, weld and output budgets; independent of display LOD.|
|Clean mesh… / Weld mesh… / Orient mesh…|Original complete-mesh diagnostics and conservative derivation; source remains immutable.|
|Heal B-Rep…|Original B-Rep validity/repair policy; a failed validity check remains an error.|
|Append / merge / bridge…|Two distinct accepted meshes; Append/Merge are not Boolean solid operations; Stitch/Bridge use explicit tolerance/gap policy.|
|Heal mesh seam…|Positive maximum gap/tolerance and unambiguous compatible boundaries.|
|Derive mesh LOD…|Independent derived preview/low/medium/high/full geometry; viewport quality does not replace scientific geometry.|
|Boundary diagnostics…|Exact complete boundary counts plus bounded source-index edges/loops with visible truncation.|
|Intersection diagnostics…|Exact complete pair count plus bounded deterministic triangle IDs/world witnesses.|
|Three-point alignment…|Explicit local/world triples and tolerance; rigid source-preserving alignment.|
|Clip geometry… / Clip and cap…|Scientific geometry derivation with explicit plane/side; distinct from a presentation-only clipping view.|

Linear deflection/tolerance uses working length. Angular deflection uses radians. Triangle counts and byte budgets are explicit integers. Closed disconnected mesh components can correctly report volume undefined. A visually closed render does not establish a scientifically defined volume.

## Measurements, rigid constraints and comparisons

On **Inspect**, **New measurement…** opens the original finite anchor form. The twelve supported kinds are distance, delta_x, delta_y, delta_z, distance_on_plane, angle, point_line_distance, point_plane_distance, line_line_angle, line_plane_angle, plane_plane_angle and point_surface_distance. Choose world/local space and real points, source object/surface and additional plane data appropriate to the kind. Length results use the working unit; angular results use radians. No physical uncertainty is inferred from a geometry measurement.

**Measurements manager…** lists actual logical records and current/stale/missing state. Refresh resolves all selected records before committing; stale/missing markers and values are not silently shown as current. Delete removes the selected owned records. Publish uses a new requested Dataset ID and the original canonical writer. A mixed-unit measurement table keeps each row's unit column; its value-column unit can intentionally be blank.

**New rigid constraint…** supports fixed, coincident, distance, point_on_plane, angle_lines, parallel_lines, perpendicular_lines, point_on_line, point_on_surface and aligned_axes. Enter finite local/world anchor triples, actual surface identity, target and tolerance. **Constraints manager…** provides original edit, solve and delete actions. Editing target/tolerance/enabled status does not silently solve. Pending, stale, underdetermined and overconstrained states must retain their actual meaning; residual alone is not a proof of full rank or physical accuracy.

**Surface / section comparison…** opens the original manager for two distinct accepted sources. Surface comparison uses complete target triangles and explicitly budgeted deterministic source samples. RMS/mean/max/Hausdorff-like/closest values are sampled measures, not continuous-surface extrema or uncertainty estimates. B-Rep tessellation parameters remain part of provenance.

Section comparison captures a shared explicit plane and tolerance. Its coordinate rows are plane XY, not world XYZ. Path position is cumulative physical length. The historical signed_residual field contains unsigned nearest-curve distance and must be interpreted that way. Refresh historical/stale comparisons explicitly before publication. Current reports publish through the original canonical Dataset owner.

Scientific report Datasets use the normal GX-TXT Dataset/Plots workflow and Plot Dataset API v4, with exact Dataset/Variable identities and units. CAD viewport geometry is not a substitute scientific result plot. A 3D graph requires genuine source-grounded geometry and compatible axis bindings; never relabel a 2D table or publish fictitious volume data merely to obtain a 3D button.

## Groups, Layers, selection sets, saved views and appearance

On **Organize**, **Create group**, **Duplicate group**, **Ungroup** and the group transform forms use actual accepted selection and the original structural commit owner. Groups own geometry placement and hierarchy; constrained/locked members can correctly reject an operation. Independent copies keep their actual new logical identities.

**Layers / sets / saved views…** opens the original purpose manager. Layers control visibility, color, opacity, selectability and edit locks. Captured Selection Sets retain logical objects or B-Rep anchors with source fingerprints and explicit current/stale/missing state. Recapture is an explicit action; a rename does not recapture geometry. Replace/Add/Subtract selection policies remain distinct.

Saved Views retain actual camera, plane, clipping, styles, visibility, Layers and working unit. Missing references or incompatible units refuse restore. Applying a saved presentation does not modify scientific geometry. Presentation-only color/opacity/visibility changes use shared Native3D rendering policy and must preserve unaffected geometry/workers.

For **Assign managed face image…**, first pick the actual intended face in the live viewport. Choose a managed RGBA image and explicit width/height, rotation in radians and flips. The owner checks exact object/source/face/render-generation/viewport scope on Apply. The image is decorative placement in working units, not inferred scientific calibration. **Clear face image** removes that owned appearance through normal History. Transparency, Undo and Save/reopen require the same source/resource guards.

## Export files, publish Datasets and manage scientific history

**Export full geometry…** opens the original guarded extension export chooser. STEP requires an accepted B-Rep; STL/VTP use complete mesh geometry or explicitly budgeted tessellation. It writes a user-chosen new file plus its provenance/unit sidecar through normal File Publication. A camera image, renderer LOD or displayed triangle subset is not complete scientific export.

**Publish geometry Dataset…** is a separate explicit canonical action. Select format step/stl/vtp and a new requested Dataset ID in its purpose form. The owner captures the current document and selected accepted object, then uses the original Native3D Geometry Export and Dataset File Publication chain. STEP publishes model.cad; STL/VTP publish geometry.mesh. Existing IDs are refused, never silently overwritten. Exact original object/document/source hashes, unit policy, bindings, full resource and sidecar remain authoritative.

**Scientific Recipe…** opens the existing recorder for inspect, validate, replay and Python export through the original owner. Replay validates retained resources, units, APIs/plugins and exact source fingerprints, stages original native geometry and commits one semantic History action. **Extensions / publication…** opens the shared compatible-action chooser; extension proposals use the original Begin/Apply/Commit/Rollback adapter and source guards. It does not grant arbitrary Tcl commands or a second geometry store.

**Interactive Documents…** offers the normal reviewed deletion workflow. Inspect exact logical owner/revision/generation and confirm explicitly. Normal No/Yes, stale revision/Session and externally retained-resource preservation have genuine native evidence. The same captured Session token and document generation/revision are rechecked after Yes; changed context refuses before deletion. Same-ID generation replacement is unavailable through ordinary monotonic GUI allocation and is covered by explicitly typed guard proof, not a fabricated native workflow. Source Datasets and published resources remain preserved; deleting a derived runtime cache is not deleting the scientific document.

**Undo geometry** and **Redo geometry** restore the original canonical semantic geometry/history rather than merely changing labels. Logical allocation counters remain monotonic. A postcommit cleanup/Recovery notice means the scientific commit may already exist; do not assume failure implies rollback or retry a committed operation blindly.

## Save, close and recover

Use **Save geometry** before **Close geometry**. Geometry Save checkpoints actual resources and the existing Recovery journal. The declared **Workspace** menu and footer controls save, open, duplicate and inspect the interface Workspace through the normal CORE Workspace owner. The declared **History** controls expose interface History through its existing owner. **Undo geometry** and **Redo geometry** remain separate canonical geometry actions. Save geometry checkpoints the model; Save Workspace preserves the interface and its guarded original scientific document association. Native edits make the interface dirty according to the original scientific revision/fingerprint. Source/generation mismatches reject rather than fabricating a replacement.

Reopen the Session, choose its original canonical document and open it through normal controls. On unclean exit, existing Recovery offers Recover, Open last saved state and inspection details; Cancel leaves the saved Session untouched. A corrupt journal is retained with an explicit diagnostic. Recovery is an aid to normal Session/Document save, not another scientific source. Closing a view releases its owned native resources and callbacks through the existing lifecycle.

The earlier Viewer and old scientific Sessions remain preserved. The new presentation uses the same original Workbench3D document schema and registered Planar destination. An older source-bound interface snapshot is not permission to rewrite callback hashes; open its original canonical scientific document through the compatible owner.

## 3D → Curve Workbench → original 3D owner

Select an accepted source body and set its actual working plane. **Section → Curve Workbench…** extracts genuine contours at that plane. **Boundary projection → Curve…** projects actual supported surface boundaries; it is not a silhouette. A closed solid with no surface boundary can correctly refuse projection. Choose Section when a physical slice is intended.

Edit the retained source-grounded contours in Curve Workbench using its normal controls. **Accept → 3D** first commits the planar result, then commits a new profile to the original originating Workbench3D document. If the originating Builder component is still live in the same Session, the editable native viewport returns there immediately and its current object/profile controls refresh. Select the returned profile and use **Preview signed extrusion…**, inspect the preview and **Accept retained preview** as a separate explicit geometry operation. The original source body remains unchanged. Returning the host does not save the accepted profile; use normal **Save geometry** and Workspace Save as appropriate.

These are two owner transactions. If destination commit fails, the independently accepted planar result remains available through **Commit staged result → 3D**. On ordinary interruption after staging, reopen the saved Curve Workspace and use that same retry control; retain the original destination context. If acknowledgement was interrupted after the destination already committed, retry is idempotent: it restores a still-valid originating host without adding another profile or History operation. **Cancel** preserves an independently accepted planar result when destination return fails. Do not invent a new origin or repeat an accepted edit to force return.

Closing or recreating the originating component, changing Session, deleting the origin, or changing its captured revision/generation/frame expires or rejects return according to the original owner checks. An expired presentation destination cannot attach to a different editor. A stale source, incompatible unit or changed working frame must be resolved explicitly. A retained path preserves exact straight vertices and closure; other supported curve families use explicitly sampled257-point reconstruction and cannot restore lost depth. Boundary projection uses actual supported source boundaries; it is not a general closed-solid silhouette.

MAIN's scoped review254 accepted the genuine217 section/projection/direct-return, idempotent retry, negative lifetime and SaveCloseOpen evidence for criteria13-37/38/39. The accepted example edited the retained outer dimension20→22mm, yielding profile area236mm² and perimeter110mm; a separate3mm extrusion gave708mm³ and802mm² with two solids, preserving original source geometry. Its source-grounded five-vertex open-mesh boundary projection dropped source Z1mm to plane Z0, with area14mm² and perimeter14.67004637770997mm. These are scoped prior015/shared-owner results, not new0.1.6 author tests. Canonical STEP resources and semantic geometry/history were preserved; native serialization fingerprints are not promised identical after STEP restore. Evidence: main_cad_review254/ACCEPTANCE.json and cad_planar_roundtrip217/HANDOFF76.json. The finite geometry tails are now scoped by MAIN342; remaining current lifecycle/layout/editorial decisions, all45 acceptance and release/deposition remain MAIN-owned.


## Generated source practice and accepted current behavior

For a reproducible source-only start, use New Session → Generate Session…;
Manage Libraries… → Import Library… imports the official Workbench Source
Practice library when needed. Select CAD and Geometry → CAD Geometry Practice
1.0.0 (`org.giuxlab.gxtxt.workbench_validation/cad_geometry_practice`). The host
writes the actual library/generator versions and timestamp to
`metadata/session_generator.ini`. It generates independent mesh/profile/image
inputs, references and instructions; it does not generate completed CAD geometry,
Workspaces, History or managed textures. Import sources through the normal CAD
forms with explicit mm for unitless STL. No original user Session is required.

After changing the document working unit, close and reopen retained forms before
applying values. New measurement, New rigid constraint, Translate and Edit
constraint target/tolerance reject the old captured context with “Geometry
document changed; reopen this form”. Their first refusals preserve scientific
Document, native scene, view, History and allocation counters. This is one shared
context correction across four reported routes (MAIN331), not four independent
repairs. Fresh Translate0.02cm gives0.2mm displacement; a fresh Edit target2mm and
tolerance0.00002mm becomes pending without silently solving.

MAIN342 accepts seven finite geometry tails in addition to existing117/176/206/
246 positive evidence. An actual Heal B-Rep on a valid unitbox is an honest no-op
derived result; it is not proof of damaged-solid repair. A one-boundary mesh
correctly refuses seam healing. Ambiguous Stitch has eight independently checked
boundary offsets; its native form reports generic DEGENERATE. Rotate supports an
explicit nonorigin pivot; group Rotate/Scale preserve member identities, source
bindings and History. Missing Selection Set/Saved View references refuse Apply
with “Record has stale/missing references; recapture it explicitly”. Failed
Boolean temporary disposal/retry preserves state on failure and monotonic IDs;
no hidden heap-accounting guarantee is implied.

The standalone illustrated guide is distributed separately from this module,
framework and scientific Sessions. It preserves earlier genuine screenshots,
science and first failures and adds current normal public workflows with exact
units/source/History evidence. MAIN313/320/331/342 accept only their precise
functional scopes. Remaining current layout/lifecycle/editorial/release status
is recorded in the external current45 map; no whole§13 acceptance is implied.

## Development provenance and remaining acceptance

This candidate exposes50 finite purpose actions plus the original10 lifecycle/primitive actions through Host::workbench_command. CORE owns every form capture, kernel, canonical Dataset, Job, Geometry, History, Resource, Recovery, renderer and publication. C++ contains presentation dispatch only. Scientific native requests do not become durable Jobs merely because a form opens or a callback returns.

Installed startup and GUI events must execute the distributed precompiled native/viewer.so with zero C++ compiler/linker calls. Only genuine new source/build dependency changes require an explicit development Build. Closing/reopening an unchanged installed Viewer must reuse its distributed artifact.

All45 mandatory parity rows remain subject to installed Debian pointer/keyboard, scientific numerical, lifecycle and negative-case acceptance. Builder validation, compiled event plans and exported ZIPs do not establish those results. Debugger: NOT USED in this source integration; no observed C++ behavioral failure has required it. A separate illustrated HTML guide with genuine installed captures and verified offline links exists; current editorial/remaining-row acceptance and official deposition remain MAIN-owned. No final acceptance or TODO removal is implied by this guide.


The final font/layout wording is pending the sealed actual335 receipt; this preparation is not a complete product-manual source release.
