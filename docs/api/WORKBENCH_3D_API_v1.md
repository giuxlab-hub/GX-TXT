# 3D Workbench controller API v1

SPDX-License-Identifier: GPL-3.0-or-later

Installed provider `viewer.3d_workbench` declares version1 in
`api/workbench_3d_api_v1.tcl`, namespace `::GX::Workbench3D`, Viewer ID
`workbench_3d`, backend `workbench_3d_native`. The module owns semantic editing
and presentation state. Public Native3D owns scientific geometry, topology,
resources and numerical inspection; CORE Document/History/Publication/Recipe
owners remain authoritative. No Viewer-local kernel or canonical registry is
defined by this controller.

This reference covers every procedure declared by the twelve loaded module
files at the documented source checkpoint:133 declarations,117 distinct names
and16 preserved base aliases. The catalogs below explain actual host functions
and GUI callbacks. They do not register133 Script/SDK operations. None of this
source review is a new installed GUI, geometry, solver or scientific parity test.

## Opening, ownership and load order

Trusted-host opening uses the existing public Viewer dispatcher:

```tcl
set window [::GX::viewerOpen viewer.3d_workbench workbench_3d]
```

The call may create/restore retained state, Native resources and a native window;
it is not a read-only discovery example. `open ?context?` defaults context to
`{}` and requires Tk and a current Session. Supported context `workspace_id`
means an exact existing Interactive Document, with module/provider and format
`workbench3d.document.v1` verified. Literal `new` explicitly requests a new empty
canonical Document when the existing scene is closed. With no explicit ID it restores the last listed provider Document
or creates one through Interactive Document if none exists. An active scene/
window is raised; a different explicit ID requires closing the current identity
first. Do not infer a universal new/duplicate Workspace protocol from that key.

`dispatch action scene` supports open (context from scene.open_context or `{}`)
and rerender (existing Engine3D backend). Other actions error. The normal Viewer
dispatcher separately enforces installed provider and presentation policy.
Native scene tokens capture Session lifetime, Document generation/revision and
worker generation; they are temporary capabilities, not retained IDs/pointers.

Entry load order is base, combine, mesh, extrusion, recovery, lifecycle,
structural, extensions/recipe, organization, comparison, planar return, texture.
Later layers rename earlier procedures before wrapping/replacing them:

- checkpoint adds recovery-journal acknowledgement after the Document commit.
- close runs lifecycle release, recovery-close acknowledgement, then base release.
- buildPanel runs comparison→organization→recipe→lifecycle→recovery→base.
- commit adds existing Scientific Recipe recording around the base commit.
- refresh runs comparison→organization→base.
- publish, details and selection gain organization/role/selectability policy.

The alias catalog at the end gives exact retained signatures. These aliases are
implementation layering, not independent consumer lifecycle entrypoints.

## Retained data, commit and units

`payload` returns model/undo/redo/allocation_counters. The model has format
workbench3d.document.v1, working_unit(default mm), objects, profiles, groups,
constraints, measurements, comparisons, views, selection_sets, layers, attrs,
recipe and logical-ID counters. Tool settings and actual scene view are retained
by checkpoint. Objects retain kind, owned geometry/display resources, name,
visibility/lock/group/style, source_bindings, provenance and optional geometry
role. Profiles retain contour resources, captured plane/tolerance, working unit
and source identity. Never persist Native object/profile/group tokens instead
of these owner-issued resources and stable logical IDs.

Base commit stages presentation before authoritative checkpoint, keeps bounded
Undo snapshots32 and recipe128, clears Redo, and restores prior semantic state/
view on precommit failure where its owner scope still matches. Structural commit
first hydrates a candidate scene and keeps the previous scene until commit.
Cleanup happens after acceptance: cleanup failure is reported as committed with
pending cleanup, not silently presented as rollback. Recovery/recipe recording
failure can be an explicit notice while the authoritative edit remains committed.
Undo/Redo hydrate replacement scenes and checkpoint the accepted history state;
logical allocation counters merge retained snapshots to avoid reusing committed
IDs. These are actual same-owner guarantees, not arbitrary cross-owner atomicity.

Length/coordinates/tolerances use model.working_unit. Working-plane normals/
directions and scale factors are dimensionless. Rotation form angle_deg is
converted to Native radians; tessellation angular_deflection and angle
measurements/constraints use radians. Area/volume have squared/cubed length
units. convertWorkingUnit changes coordinate representation and associated
length-bearing state via Unit Registry, preserving physical scale; ordinary
Scale changes geometry. Unit conversion deliberately leaves captured measurement
geometry references stale until explicit refresh, and saved views with a
different working unit require their existing owner checks.

Profile intake binds canonical Dataset/Variable IDs through Curve Source.
Different compatible units require explicit conversion; undeclared coordinates
require the explicit same-working-unit assumption for both axes, not inference.
Missing/incompatible units or changed plane/source/Document scope error.
No source Dataset is edited by importing its owned local geometry/profile.

## Function catalog conventions

Every name below is qualified by `::GX::Workbench3D::`. Signatures use Tcl
formal argument-list notation: `{arg}` is required, `{{arg default}}` is optional,
and `{args}` is variadic. `{}` means no arguments. Except metadata/model helpers,
functions depend on the current controller's actual Document/scene/model or
native widgets. Captured/record/token arguments are existing owner-issued data,
not authorization to fabricate private handles. Form callbacks must use their
captured parameters. “UI effect” means no stable public return schema is
declared; an incidental Tcl last-command return is not a scientific receipt.

### Lifecycle, retained model and Native resource adapters

| Function / exact formal arguments | Actual result, effect or checks |
|---|---|
| `defaultModel {}` | new inert default model dict; no Document creation |
| `open {{context {}}}` | create/restore/raise actual Engine3D Tk window as described above |
| `dispatch {action scene}` | open/rerender backend result; unsupported action error |
| `close {}` | final lifecycle/recovery/base release chain; unsubscribes and closes scene, clears preview/panel; no Dataset deletion |
| `payload {}` | model/undo/redo plus merged allocation_counters dict |
| `allocationMerge {counters snapshot}` | max nonnegative integer counters for next_object/profile/group/constraint/measurement/organization/comparison; invalid value errors |
| `nextId {key prefix}` | increments named model counter above merged allocation watermark; returns prefix_N; staging helper, not global identity service |
| `millimeters {}` | working-unit/mm intrinsic-scale ratio after Unit Registry compatibility check |
| `call {action request}` | delegates current scene operation to native3DGeometryCall; exact Native operation/result contract remains its owner |
| `checkpoint {}` | authoritative Native geometry/Document checkpoint result, then recovery notice/acknowledgement; saves actual tools/view and committed allocation watermark |
| `saveExplicit {}` | checkpoint plus recovery MarkSaved/compaction status presentation; recovery failure notice preserves saved Document |
| `record {operation parameters targets results}` | appends bounded128 semantic recipe entries with API/provider/units/provenance; semantic model effect |
| `commit {before operation parameters targets results}` | recipe wrapper around base staging/checkpoint; returns status committed/cleanup_status dict, with postcommit notice semantics |
| `structuralCommit {before operation parameters targets results {rollbackTokens {}}}` | staged-scene commit receipt; optional predecessor-token map for rollback; restores old owner scope on failure |
| `committedCleanupDelete {ownedTokens}` | deletes owned predecessor tokens after commit; records cleanupNotice for failures |
| `restoreStage {}` | opens candidate scene, loads owned object/profile resources/groups, reapplies retained view and refreshes; updates current token maps |
| `restore {}` | guarded scene replacement; preserves previous scene/maps/view on staging failure, closes predecessor after success |
| `undoRedo {direction}` | undo/redo only; staged restore and authoritative history checkpoint, full prior scene/maps/view/settings retained until success; UI effect, empty history is a no-op |
| `resourceToFile {reference path}` | bounded-reader copy of owned resource to supplied host file; binary write, closes reader/file in finally |
| `renderResource {reference id fields}` | SHA-keyed display cache and temporary Engine artifact→retained layer projection; returns layer ID; no canonical Dataset commit |
| `snapshotObject {receipt}` | owned local geometry/display snapshot record from Native receipt; B-Rep STEP plus explicit tessellated STL display, mesh STL; no token persisted in record |
| `installObject {receipt name {replace {}}}` | snapshots then installs record; returns new/retained logical object ID |
| `installPreparedObject {receipt record name {replace {}}}` | installs reviewed record/token map; replacement preserves visibility/lock/group/attrs/style/source_bindings/geometry_role from prior object |
| `refresh {}` | final base resource/layer projection plus organization synchronization and comparison refresh; UI/presentation effect |
| `datasetChoices {{event {}}}` | optional event ignored as selector trigger; populates numeric rank-one Dataset Variable choices; UI effect |
| `documentOwnerInvalidated {event}` | matches event.document_id/session_token to current owner then disposes; lifecycle callback |
| `disposeInvalidated {}` | closes Engine when controller not busy; otherwise schedules retry50ms; lifecycle effect |

### Profile, primitive, extrusion and B-Rep combination

| Function / exact formal arguments | Actual result, effect or checks |
|---|---|
| `loadProfile {}` | current Dataset/x/y/plane/closed/append/unit controls→public Curve Source/Native profile; commits new logical profile, source bindings/resources and assumption/conversion provenance |
| `createPrimitive {}` | selected box lengths or cylinder radius/height through Native; installs/commits object and selects it; cleanup on failure |
| `importDatasetForm {}` | native form for STEP/STP/STL/OBJ/VTP Datasets, fallback input unit mm/cm/m/in and local name; captures scene scope |
| `importDatasetApply {captured values}` | checks scene/busy; Native import for values.dataset_id/input_unit/name, commits owned resource/source SHA binding; UI effect |
| `extrudePreview {}` | current profile/distance/mode/new-join-cut-intersect/target; produces reviewed uncommitted Native result/resource and scope/profile snapshots; delegates to multi path when enabled |
| `cancelPreview {}` | disposes owned preview and display layer; multi preview uses its own retry-preserving cleanup |
| `acceptPreview {}` | requires unchanged scope snapshot; routes combine/multi or installs single extrusion; commit/provenance/history then predecessor cleanup; UI effect |
| `extrusionTargetsForm {}` | form for explicit affected B-Rep IDs and keep_tool flag |
| `extrusionTargetsApply {values}` | validates unlocked B-Reps, deduplicates targets, max128; updates target/keep-tool settings |
| `extrudeMultiPreview {}` | Native extrude/Boolean per target, all closed positive-volume results staged; optional retained tool; source snapshots and scope captured |
| `cancelMultiExtrusion {}` | releases every preview result/tool; failed releases remain owned in preview for explicit retry; error on incomplete cleanup |
| `acceptMultiExtrusion {}` | commits all reviewed results/tool as one controller action, invalidates target constraints, uses structural path for groups and only then cleans predecessors |
| `combineForm {}` | requires target+tool unlocked B-Reps; form target label/tools IDs/mode/result_policy/keep_tools defaults Join/New derived body/keep1 |
| `combinePreviewApply {captured names values}` | captured scene and label→ID map;1..128 explicit tools, distinct from target; Native sequential Booleans validate positive closed solid; reviewed preview retained |
| `acceptCombinePreview {}` | installs reviewed Boolean, preserves unioned source bindings/provenance; optional target replacement/tool removal; stale/missing constraints and group membership reconciled before commit |

Preview is not accepted geometry. Call Accept through the normal scope-checked
adapter; direct accept helpers alone do not replace the outer unchanged-snapshot
guard. The kernel owns topology validity and Boolean/extrusion meaning. Geometry
calculations are synchronous public Native requests here, not a new solver Job
or substitute for independently installed Native3D acceptance.

### Selected-object edits, mesh operations and groups

| Function / exact formal arguments | Actual result, effect or checks |
|---|---|
| `selected {}` | exactly one accepted unlocked object ID, or explicit selection/lock error |
| `deriveSelected {action parameters {replace 0} {render 1}}` | Native derived result; optional replacement/enforced enabled constraints/group structural commit; provenance/source identity retained; UI effect |
| `editForm {}` | fields/defaults for current editAction; units labelled; callback editApply |
| `editApply {action values}` | translates form scalars into Native delta/axis/pivot/radians/plane; routes group/section/inspection or deriveSelected; no generic public action-by-string grant |
| `groupOperation {{action create} {parameters {}}}` | create/duplicate/ungroup/translate/rotate/scale current accepted selection/group; constrained members refuse group transforms; commits membership/geometry and reports predecessor cleanup separately |
| `sectionProfile {parameters}` | Native section_profile with selected object token/plane/tolerance; retained contour/view resources and source geometry/bindings, commits new profile |
| `inspectSelected {}` | Native complete geometry describe→area/volume/defined/closure and available mesh diagnostics status; UI effect |
| `convertWorkingUnit {}` | explicit coordinate-unit conversion as described above, rollback of candidate geometry/view/settings on failure |
| `meshPairForm {}` | two distinct unlocked mesh choices; Append/Merge/Stitch/Bridge, working-unit tolerance and name |
| `meshPairApply {captured names values}` | unchanged scene, distinct sources, Bridge positive gap; delegates mesh_* operation, preserves sources and commits new derived mesh/source snapshots, provenance boolean0 |
| `meshInspection {action parameters}` | complete Native mesh_boundaries/intersection_pairs receipt plus bounded tree; returns actual result, no geometry mutation |

Form defaults include mesh linear_deflection.01, angular_deflection.3rad,
weld_tolerance1e-8, max_triangles1000000 and max_output_bytes134217728;
inspection controls max_items1..4096, max_vertices1..65536; default256/1024.
They are workflow defaults/bounds, not every kernel operation's universal limit.
Mesh Append/Merge/Stitch/Bridge are not B-Rep Boolean solids. Displayed boundary/
intersection rows explicitly expose omitted/truncated counts; complete geometry
is not replaced by the bounded inspection list or viewport LOD.

### Constraints and measurements

| Function / exact formal arguments | Actual result, effect or checks |
|---|---|
| `constraintSpecs {id}` | enabled object's persistent specs with logical surface/anchor IDs resolved to current Native tokens |
| `enforceConstraints {id receipt}` | input receipt unchanged if no enabled constraints, otherwise Native constraint_solve result after releasing intermediate token |
| `constraintForm {}` | fields kind/local_points/world_points/surface_object_id/target/tolerance for selected object; delayed Apply retains the actual native scene identity/revision and working-unit context |
| `constraintApply {id values}` | validates three finite XYZ triples per coordinate field, builds actual kind-specific spec, Native solve and commit; records status/residual; cleanup after acceptance |
| `constraintsPanel {}` | native current constraint table/status/residual/tolerance and controls |
| `editConstraint {window}` | exactly one selected constraint→target/tolerance/enabled form |
| `editConstraintApply {id values}` | updates tolerance/enabled/optional target, marks pending/residual empty and commits; does not silently solve |
| `solveConstraints {window}` | selected constraint's object's full enabled set through deriveSelected; then checkpoints evaluated statuses/residual and refreshes panel |
| `deleteConstraints {window}` | removes selected records through commit; does not reinterpret prior geometry |
| `measurementForm {}` | measurement type, world/local points, optional surface and second plane form; delayed Apply retains the actual native scene identity/revision and working-unit context |
| `measurementApply {id values}` | builds explicit anchors/plane(s), Native measure and anchor_describe; retains captured geometry/value/unit and markers; commits measurement |
| `measurementsPanel {}` | table of object/kind/value/unit/current-stale-missing plus refresh/delete/publish controls |
| `measurementState {record}` | current/stale/missing by exact object and optional surface geometry references |
| `measurementPresentation {}` | hides stale/missing markers and values; retains old numerical record for inspection |
| `refreshMeasurements {window}` | resolves every selected measurement first; commits all refreshed values/geometry/markers together or restores prior model/view |
| `deleteMeasurements {window}` | committed record/owned-marker removal; restores model/view on failure |
| `measurementPublishForm {window}` | captures actual scene and selected IDs, requested Dataset/storage(auto/csv/hdf5) form |
| `measurementPublishApply {captured ids values}` | current scope/current measurements only; streams explicit table.generic Variables in512-row chunks, rechecks scope before Finalize; returns actual publication receipt |

Constraint kinds: fixed, coincident, distance, point_on_plane, angle_lines,
parallel_lines, perpendicular_lines, point_on_line, point_on_surface,
aligned_axes. Distance targets use working length; angle targets use radians;
tolerance retains each public Native constraint convention. A residual/status is
not automatically a full-rank/fixed-degree-of-freedom or measurement-accuracy
proof. New/edited constraints have explicit pending/stale/missing states.

Measurements: distance/delta_x/delta_y/delta_z/distance_on_plane need2 points,
angle and point_line_distance3, point_plane_distance/point_surface_distance1,
line_line_angle4, line_plane_angle2, plane_plane_angle0 plus explicit plane data.
Points are finite XYZ triples; world/local anchors remain explicit. Values use
working length or radians for angle kinds. No physical uncertainty is measured.
Measurement publication includes ordinal, IDs, kind/value/unit, captured geometry
SHA, inert anchor specification and column-major16 world transform; mixed value
units leave the value-column unit blank and retain each row's unit column.

The form callback dictionaries are concrete host data, not unspecified blobs:
constraintApply consumes kind/local_points/world_points/surface_object_id/
target/tolerance (initial kind coincident, three initial XYZ triples, empty surface,
target0, tolerance1e-8; kind subsequently follows the current control).
measurementApply consumes kind/space/points/
surface_object_id/plane2_origin/plane2_normal/plane2_u (world default, up to four
XYZ triples; default second plane origin0, normalX, U-axisY). editConstraintApply
consumes tolerance/enabled and optional target. Measurement/comparison publish
values contain dataset_id/storage; the publication form supplies the captured
scope and selection rather than a caller-invented token.

Delayed measurement and constraint forms use the existing `purposeFormGuard`
through the internal `purposeFormApply {captured callback values}` dispatcher.
The operation form (`editForm`, including Translate) and constraint editor
(`editConstraint`) capture the same native scene identity/revision before opening
and pass their original semantic callbacks through this dispatcher. A stale
operation or constraint edit is rejected before geometry, constraint values or
History can change; reopen the form in the current document and working unit.
Changing the geometry document or its working unit invalidates the captured
form: Apply asks the user to reopen it before changing measurements, constraints,
markers, allocation counters or History. The existing `measurementApply` and
`constraintApply` signatures and numerical semantics remain unchanged. This
internal form dispatcher does not register another Script or restricted SDK
operation.

editApply's accepted form keys are delta dx/dy/dz; rotation axis_x/y/z,
angle_deg and pivot_x/y/z; scale factor_x/y/z and pivot_x/y/z; plane operations
origin_x/y/z, normal_x/y/z, u_x/y/z, tolerance and clip keep_positive;
mesh linear_deflection/angular_deflection/weld_tolerance/max_triangles/
max_output_bytes; weld/heal/self_intersections/mesh_heal_seam tolerance;
mesh_boundaries max_items/max_vertices; mesh_intersection_pairs tolerance/
max_items; mesh_lod level(preview/low/medium/high/full); align_three_points
local_points/world_points/tolerance. Corresponding Native requests use the
actual delta/axis/pivot/radians/factors/plane conventions, not these UI key names.

### GUI host, details and selection callbacks

| Function / exact formal arguments | Actual result, effect or checks |
|---|---|
| `detailsForm {}` | one object/profile→name/visible/locked/color/attrs plus final geometry_role form |
| `detailsApply {section id values}` | section objects/profiles, valid attrs dict and RGBA conversion; commits name/visibility/lock/role/style/attrs; rollback on failure |
| `hostEdit {action id fields}` | shared host callback for transform(relative_world) or presentation(base_color/opacity/representation/visible), requires accepted unlocked object; commits actual edit |
| `buildPanel {window}` | final composed Native Engine control panel; binds actual lifecycle/Dataset subscriptions and actions, not a headless form factory |
| `selectTree {}` | filters nonselectable organization members, then synchronizes selected IDs/profile/Engine layer from actual tree |
| `hostSelection {pick}` | pick.layer_id/world_point host callback; honors Layer selectability before selecting actual object/profile |
| `safe {script}` | trusted callback wrapper, busy guard and native error dialog/status; may swallow Tcl error for GUI presentation; not public script-text evaluation from a consumer |

### Selection sets, Layers and saved views

| Function / exact formal arguments | Actual result, effect or checks |
|---|---|
| `organizationCollection {kind}` | selection_set→selection_sets, layer→layers, saved_view→views; unknown kind errors |
| `organizationMemberState {member}` | current/stale/missing using member.object_id and captured source_geometry |
| `organizationCaptureMembers {}` | nonempty accepted object selection→list of logical IDs/captured geometry dicts |
| `organizationSync {}` | rehydrates current valid semantic records into Native organization IDs; applies layers/roles/presentation; skips stale/missing captured records |
| `organizationRefresh {}` | actual organization table refresh, retaining selected rows and reported state |
| `organizationPanel {}` | native selection-set/Layer/saved-view editor, no separate identity store |
| `organizationAction {action {mode replace}}` | selection_set/layer/saved_view create, edit/apply/remove workflow; Add/Subtract applies only to Selection Sets, preserving actual current native members and anchors; stale refs refuse activation |
| `organizationApply {kind id values}` | creates ID when id empty or edits existing record; explicit recapture of objects/anchors/view; commits and returns logical record ID |
| `organizationSelectable {id}` |0 if any containing Layer has selectable false, otherwise1 |

Groups transform owned geometry. Selection Sets retain reusable captured object/
B-Rep vertex/edge/face anchors, Layers control presentation/selectability/lock
fields, Saved Views retain camera/plane/visibility/style/layer presentation and
working unit. They are distinct authorities within the same Document model.
Recapture is explicit after stale geometry; a UI rename does not recapture it.
Reference/construction roles are excluded from normal canonical geometry export/
publication. This does not prevent an explicit reviewed regular copy.

detailsApply values are name/visible/locked/color/attributes/geometry_role;
attributes must be a Tcl dict and color uses UI Field's structured color/RGBA
conversion. organizationApply always consumes name/recapture; Selection Sets
add member_kind(object/brep_vertex/brep_edge/brep_face), zero-based index and
parameter/u/v; Layers add visible/selectable/locked/opacity(0..1)/color; Saved
Views capture actual view/unit/visibility/styles/layer presentation. Recapture
false preserves existing references. Native anchor validation owns topology and
edge/face parameter semantics.

### Scientific comparison

| Function / exact formal arguments | Actual result, effect or checks |
|---|---|
| `comparisonState {record}` | refresh_required without versioned statistics; otherwise current/stale/missing from source resources and working unit |
| `comparisonPanel {}` | native captured-comparison controls/table and qualified scientific summary |
| `comparisonRefresh {}` | reloads rows/semantic statistics/states in actual comparison window |
| `comparisonStatistic {record direction quantity}` | StatisticsV1 scalarRows value formatted %.9g or explicit status/Refresh required; no guessed numeric default |
| `comparisonSelected {}` | exactly one table-selected comparison ID, else error |
| `comparisonSummary {}` | reports actual semantics/sampling/units/section frame/undefined volume; UI effect |
| `comparisonAction {action}` | create/refresh/publish/remove workflows and forms, including explicit surface/section parameters |
| `comparisonApply {id values}` | Native compare_geometry/compare_sections for distinct accepted objects, captured-scope recheck; commits record and returns logical comparison ID |
| `comparisonPublish {id values}` | current semantic comparison only; explicit table.generic deviation report, actual statistics/provenance and512-row writer; returns publication Finalize receipt |

Surface comparisons use bounded deterministic source vertex samples against
complete target triangles; RMS/closest/Hausdorff-like metrics remain **sampled**,
not exact continuous global extrema or uncertainty. B-Reps record explicit
tessellation. Sample_budget defaults257, form bound6..4096; mesh budgets default
1000000triangles/128MiB. Section mode uses shared plane/tolerance, plane-XY
coordinates, length/area differences and its actual Native section policy.
Historical receipts without StatisticsV1 interpretation require Refresh.
Surface publication includes direction(0 reference→target,1 reverse), zero-based
source_vertex and XYZ; section publication includes path position and legacy
signed_residual, explicitly labelled **unsigned** nearest-curve distance.
All distances are working length; area/defined volume are squared/cubed units.

comparisonApply values contain name/reference/target/method(surface or section),
sample_budget, linear_deflection/angular_deflection/weld_tolerance,
plane_origin/plane_normal/plane_u_axis and section_tolerance. A refresh passes
the existing comparison ID, create passes empty ID. Captured records retain the
two exact geometry references, working_unit, complete parameters and actual
Native receipt, including versioned StatisticsV1 interpretation. Publish
refuses historical/stale/missing records rather than coercing old metrics.

### Extensions and Scientific Recipe adapters

| Function / exact formal arguments | Actual result, effect or checks |
|---|---|
| `extensionContext {}` | cancels preview and returns existing Workbench context with exact Document revision/selection/working units and empty parameters |
| `extensionBegin {context}` | requires matching Document/not busy; captures complete predecessor semantic/view/token state, hydrates candidate scene; returns transaction ID |
| `extensionRequire {id}` | live transaction with unchanged Document revision and valid current Native scene; returns captured transaction dict |
| `extensionTrack {id kind object}` | appends created/modified/deleted logical tracking to existing transaction; internal host callback |
| `extensionApply {id result}` | at most256 semantic operations; reviewed replay_recipe/box/cylinder/translate/rotate/scale/identity/delete; returns created_ids/modified_ids/deleted_ids/operations |
| `extensionCommit {id applied}` | commits existing transaction/provenance through same owner, releases predecessor, returns revision/warnings and clears busy state |
| `extensionRollback {id}` | restores captured scene/model/maps/history/selection/view, releases candidate and closes transaction; idempotent if already absent |
| `recipeState {value}` | model without recipe/scientific_recipe keys |
| `recipeCapture {context}` | matching owner→versioned inert recipe, required APIs/plugins, actual source fingerprints, base/steps and current state patch |
| `recipeValidate {recipe}` | validates owned complete geometry/profile resources/units and final group references through temporary public Native scene; no declared scientific-result return |
| `recipeReplay {context recipe}` | existing extension transaction applying validated encoded recipe; commits revision/warnings or finally rolls back |

These are callbacks registered with existing Scientific Recipe and Workbench
Extension owners, not a new parallel transaction manager for independent
scientific services. Extension results contain semantic operations, not arbitrary
Tcl/native code; grouped/locked/missing targets are refused where specified.
Recipe resources/source identities must remain current and owned; GUI capture,
validation and replay do not imply a proof of physical model correctness.

extensionApply's required result.operations is a Tcl list of operation dicts;
optional result.provenance defaults `{}`. box/cylinder consume parameters (the
actual Native operation request) and name. translate/rotate/scale consume
target_ids plus parameters: delta; axis/pivot/radians; factors/pivot,
respectively. identity consumes target_ids and optional name/attributes; delete
consumes target_ids; replay_recipe consumes encoded inert recipe. Context and
operation validity still belong to the registered Extension/Recipe/Native owners.
The tracking kind is created/modified/deleted, each logical object ID list;
transaction state also captures model/scene/token maps/Undo/Redo/selection/view.
It is not a serializable scientific-worker or Script argument contract.

### Geometry export, planar edit return and managed textures

| Function / exact formal arguments | Actual result, effect or checks |
|---|---|
| `geometryExportContext {}` | selected object's complete host-issued NATIVE3D_GEOMETRY_EXPORT_SNAPSHOT_v1 context, owned resource/working unit/revision; cancels preview through extensionContext |
| `geometryExportOpen {}` | normal extension export chooser with that guarded context |
| `publish {}` | final role guard then explicit export.native3d_geometry/publish with requested ID/format; returns actual canonical publication receipt, never viewport geometry |
| `planarEditSelected {mode}` | section/projection only; checkpoints origin, full resource/plane receipt, opens retained planar document through Curve Workbench and returns its Viewer result |
| `planarCopyResource {reference}` | copies bytes/metadata through current Document's bounded managed-resource writer; returns verified destination reference, aborts incomplete writer |
| `planarAcceptResult {planar origin accepted}` | validates Session origin/plane/generation/source receipt/unit; same destination-owner profile commit, returns committed/already_committed receipt; preserves original body |
| `textureAssign {object resource placement}` | unlocked current object and matching working unit; copies managed image resource into owner, binds explicit decorative placement, commits style/provenance; returns texture descriptor |
| `textureForm {}` | requires actual latest picked face/viewport; choices are retained RGBA PNGs, sizes33..134217728bytes; captures owner/render generation/viewport/resources |
| `textureFormApply {capture values}` | rejects changed owner/view/render/face, resolves actual Native anchor and delegates explicit placement assignment; clears busy state in finally |
| `textureClear {}` | selected unlocked object; removes retained texture style through commit, no action if absent |

Geometry File export and canonical Dataset publication are separate explicit
actions. Host contexts/units/sidecars/bounds follow the existing
[Native3D export adapter](NATIVE3D_GEOMETRY_EXPORT_API_v1.md) and
[CORE export reference](NATIVE_3D_GEOMETRY_EXPORT_API_v1.md). Planar return is two
owners, with destination-only transaction receipt and signature-based retry
idempotence, not a single cross-owner atomic commit. See
[Native3D Planar Return](NATIVE_3D_PLANAR_RETURN_v1.md). Texture placement is
explicit decorative resize in working units, with width/height, normal-axis
rotation_radians and flip flags; it is not an inferred scientific calibration.
Texture form values contain image(choice→owned resource), width/height,
rotation_radians/flip_u/flip_v. Capture contains exact Document owner, logical
object, actual pick, render_generation, viewport and resource-choice map.
Native texture anchor/binding owns placement validation and descriptor shape;
see [Managed texture](NATIVE3D_MANAGED_TEXTURE_v1.md). Planar accepted data
contains contours/plane/tolerance/working_unit/definitions/provenance from the
existing owner, not a free-form reconstruction request.

## Preserved base aliases: all sixteen

These names exist after successful normal loading because the listed public
names are renamed before replacement. Call the final controller adapters;
invoking an alias directly bypasses its wrapper's behavior.

| Alias / exact formal arguments | Preserved layer |
|---|---|
| `checkpoint_recovery_base {}` | base authoritative tools/view/Document checkpoint |
| `buildPanel_recovery_base {window}` | base controls/subscriptions |
| `close_recovery_base {}` | base scene/Dataset subscription release |
| `buildPanel_lifecycle_base {args}` | recovery buildPanel wrapper, variadic forwarding |
| `close_lifecycle_base {}` | recovery close wrapper |
| `commit_recipe_base {before operation parameters targets results}` | base staged commit/Undo/resource collection |
| `buildPanel_recipe_base {args}` | lifecycle buildPanel wrapper, variadic forwarding |
| `refresh_organization_base {}` | base resource/presentation refresh |
| `publish_organization_base {}` | base explicit geometry publication |
| `detailsForm_organization_base {}` | base details form before geometry-role field |
| `detailsApply_organization_base {section id values}` | base attrs/style handler, superseded by final role-aware replacement |
| `buildPanel_organization_base {window}` | Recipe/Extensions panel wrapper |
| `hostSelection_organization_base {pick}` | base host pick callback |
| `selectTree_organization_base {}` | base tree-selection callback |
| `refresh_comparison_base {}` | organization refresh wrapper |
| `buildPanel_comparison_base {window}` | organization panel/export wrapper |

## Errors, language exposure and remaining acceptance

Owner errors include no Session, incompatible/foreign/missing Document, changed
revision/generation/worker, invalid or locked selection, incompatible units or
source identities, invalid Native topology/operation/constraint/anchors,
stale form/preview/measurement/comparison and failed resource/publication. Most
functions propagate original Tcl/Native errors. `safe` is a trusted GUI callback
error/dialog wrapper, not a promise of structured machine-readable failure for
all functions. Explicit cleanup/recovery/recipe notices preserve the accepted
state and authentic diagnostic rather than invent success or retry silently.

This family has no registered Python/Octave Script Bridge operations or typed
C++ SDK method in the retained/current reviewed scope. Source-visible Tcl names,
GUI callbacks, scene tokens and context builders do not become generic remote
calls. Underlying Native3D, Unit Registry, Dataset, Document, Job and Plot grants
are separate actual public contracts. There is no generic C++ invoke. Ordinary
C++17 local facilities are not banned by this documentation; admitted public
integration remains with the official SDK/project/profile owners. Typed3D
authoring gaps and same-author/independent parity remain explicit acceptance
work; a demo Host method is not proof of complete scientific3D access.

No new managed Job or solver execution owner exists here. Synchronous Native
requests, recipe/Document transactions and UI scheduling must not be described
as durable scientific Jobs unless the invoked real public service returns one.
Resource/history/recipe bounds above are actual inspected workflow limits, not
invented global safety limits. Installed GUI, numerical/physical accuracy,
save/restart/Undo/parity and every mandatory tutorial/release criterion require
their real independent evidence. This complete source-function reference alone
does not close those gates.

Related authorities: [Native3D Geometry](NATIVE_3D_GEOMETRY_API_v1.md),
[Native3D Engine](NATIVE_3D_ENGINE_API_v1.md),
[Interactive Document](INTERACTIVE_DOCUMENT_API_v1.md),
[Managed Resource](MANAGED_RESOURCE_API_v1.md),
[Scientific Recipe](SCIENTIFIC_RECIPE_API_v1.md),
[Workbench Extension](WORKBENCH_EXTENSION_API_v1.md),
[Workbench Recovery](WORKBENCH_RECOVERY_API_v1.md),
[Statistical Result Semantics](STATISTICAL_RESULT_SEMANTICS_API_v1.md),
[Dataset Publication](DATASET_PUBLICATION_API_v2.md), and the installed module's
MANUAL.md.

Existing-owner factor (documented source integration):
`activateDocument ?context?` hydrates the original
`viewer.3d_workbench/workbench_3d` / `workbench3d.document.v1` owner, Geometry
scene, resources, History, allocation counters and Recovery without constructing
the legacy panel. `workspace_id new` is an explicit new-document request; it
cannot replace an active different Document silently. Ordinary `open` delegates
to the same activation and retains legacy presentation. Planar destination
acceptance also activates this same owner, preserving its registered identity,
source/plane/unit checks and destination-only idempotent commit.
The result is the activated canonical Document ID.

`guiMount parent ?context?` is a trusted GUI Host operation mounting the existing
single editable Native3D v1 controller, with the owner's existing edit, selection
and close hooks and no legacy panel hook. It creates no renderer, geometry store
or worker registry. Lifecycle subscription belongs to the canonical activation,
survives widget movement and is removed by the existing final close wrapper.
Its result is the embedded native Tk host path.
`guiInspect` projects actual Document identity/revision, working unit, logical
object/profile rows, selection, History availability and pending/busy status.
It returns the actual inspection dictionary, including an unbound status when
appropriate; `guiCommand` returns this same inspection shape after its action.
For a ready Document, `recovery_notice` is a read-only string, empty when no
Recovery warning applies. It carries a corrupt or unavailable secondary journal
warning independently of the ordinary action `message`; the canonical Document
can remain usable. The trusted Workbench status projection appends this notice
when it is not already present in `message`. Reopening the active owner retains
its warning; activating a different owner clears the previous notice before
inspecting that owner's Recovery state. Reading the notice does not repair or
replace journal or canonical Document content.
`selectionSet ids` validates actual logical identities and Layer selectability;
native selection remains effective without the optional legacy tree.

`guiCommand action ?values?` implements exact primitive, inspect, save,
undo and redo, invoking the original native Geometry and final commit/recovery
owners. Primitive values are exactly `primitive`, `dimensions`, `radius`,
`height`, `name`; box lengths and cylinder radius/height must be positive in the
working unit. No callback, native token, raw path or model payload is accepted.
Other finite groups require their remaining existing-owner exposure. The initial lifecycle/primitive commands are exposed by the declared
`Host::workbench_command` form below. Genuine geometry/GUI tests, the remaining
operation forms and the entire 45-row parity matrix remain mandatory. Metadata/no-Session negative checks are not geometry acceptance.

`inspect` invokes the existing `inspectSelected` owner: actual area, volume,
volume-defined flag, closure and available mesh diagnostics are reported in the
Document's physical units. It does not create measurements or scientific History.
New Documents carry a clean default scene view. A legacy Document without a
retained view also receives that default when staged, so another Document's
measurement markers, fields or curves cannot remain attached after switching.


### Declared editable geometry form (dev109 integration)

Builder exposes `editable3d`, an embedding of the original single editable
Native3D v1 host. Existing `native3d` components retain their independent readonly
v2 contract. An editable viewport requires exactly one section with
`workbench_viewport`, `workbench_documents` and `workbench_objects` choice fields,
`workbench_unit` read-only label/status, `workbench_status` read-only text, and
`workbench_parameters` mapping `primitive x y z radius height name` to declared
fields. Primitive is a box/cylinder choice; lengths use the actual Document's
working length unit. Logical object/profile IDs are projected by the owner.

An optional pair `workbench_selection` / `workbench_selection_mode` names an
existing declared `list` (`selectmode extended` or `multiple`) and a choice with
exact values `replace add subtract`. The original single-object choice remains
compatible. Changing that shortcut projects its matching candidate into the
list immediately. A single selected list row updates the shortcut; selecting
multiple rows preserves the complete candidate list. These local controls do
not change canonical selection until Select. The same Select command resolves list indices against the current
canonical object/profile IDs and exact Document generation/revision/SHA.
`selectionApply ids ?mode?` uses the shared Native3D member authority for bodies;
profiles retain their distinct canonical profile identities. Selection alone
uses mode `replace`, `add` or `subtract` and returns the `guiInspect` dictionary;
it returns no geometry-ID list. Selection
does not alter geometry or scientific History. Dynamic list rows are captured
before their selected indices and restored in that order. Changed rows clear
old positional selection rather than silently selecting another identity.
The original organization manager exposes Add Selection Set and Subtract
Selection Set only for a valid current Set row. Installed GUI verification of
these new controls remains required; typed contract success is not acceptance
of the full 45-row CAD matrix.

`Host::workbench_command(form_ordinal, operation)` uses additive SDK v1 operation32.
Finite operations are `refresh`, `new`, `open`, `inspect`, `primitive`, `select`,
`save`, `undo`, `redo`, `close`. Projects explicitly request Host
`workbench_command` plus operation-specific WORKBENCH_3D_API_v1 grants:
`activateDocument/guiMount/guiInspect` for open/new; `guiCommand/guiInspect` for
primitive/save/undo/redo/close; `selectionSet/guiInspect` for selection. No author
method accepts a native scene token, geometry payload, callback or Tcl command.

The Host refuses replacing an existing editable host or different active
Document. Save before explicit Close; the original Geometry/Document owner
continues to own actual checkpoint, resource, History and Recovery operations.
Interface snapshots retain only the canonical Document ID/generation association.
Reopening checks the exact owner/schema/generation before mounting, and rejects
deleted/replaced sources. Native edits make the interface dirty by comparison
with its last saved canonical revision/SHA; Workspace Save uses the original
geometry Save owner before capturing ordinary interface state.

This is the initial shared binding, not acceptance of the remaining Boolean,
mesh, organization, measurement, constraint, comparison, export, recipe and
3D–Curve operation groups. Those existing-owner form exposures and installed
45-row GUI/scientific verification remain open.

## Builder purpose forms (public scientific bindings)

The existing finite `guiCommand action ?values?` also admits the action names
returned by `::GX::Workbench3D::guiFormCommands` and reported by `apiInfo`.
Restricted C++ uses `Host::workbench_command(form, action)` with its complete
declared canonical geometry form and the original guiCommand/guiInspect grants.
These actions accept no author callback, native handle, geometry payload or extra
parameters. They open the existing trusted purpose forms and managers for Dataset
intake, Combine, extrusion targets, mesh pairs, properties, measurements,
constraints, organization, comparisons, textures, export, Recipe and Extensions.
Finite transform/repair/mesh actions choose exact existing editForm operation
names; grouping and planar section/projection use the original semantic owners.
preview_accept invokes the original scope-guarded acceptPreview, and
preview_cancel disposes the original uncommitted preview before redisplay.

This does not reopen the old whole buildPanel. Existing field validation, source
captures, native geometry, canonical commits, History and scientific publication
remain in their original services. Canonical commits and selection publish a
widget presentation event; the shared Builder host refreshes its actual Document
projection through guiInspect. Session/window guards retire obsolete callbacks.

A successful planar transfer can transfer the shared editable host to Curve
Workbench and leave the originating Builder form `unbound`. Its geometry trace
reports that actual status and includes Document fields only when they exist;
it does not convert the completed transition into a missing-`document_id` error
or claim that the old embedded host still owns the active geometry.
When an embedded Workbench starts that transfer, the owner retains only a
process-local return destination: parent widget incarnation, Session token,
canonical Document ID and generation. Accept returns the same native controller
to that still-live component through `guiMount`; it forwards presentation changes
to the stable component parent so its form immediately reflects the accepted
profile. No Tk path is stored in a scientific Document or Workspace. A closed or
recreated component or changed Session expires the destination and cannot steal
a new editor. Existing canonical origin, revision, plane, unit and active-owner
guards remain mandatory. The commit receipt adds `presentation` with status
`restored`, `expired` or `not_requested`. An idempotent accepted-result retry also
restores a valid host without a second profile or History commit. Remounting does
not mark the accepted profile saved; normal Save remains required.

Curve Workbench saves its staged-origin context before asking the destination
owner to commit. If ordinary window closure occurs while that request dispatches
events, its continuation checks the original widget incarnation and Session
before any UI update or save. A completed owner commit remains committed; the
closed Workspace's durable staged context remains available for normal reopen
and idempotent retry. Error reporting never opens a modal on a closed or
same-path replacement window. A still-live window retains the precise owner
error and its staged-result retry controls.
No source Dataset or geometry is duplicated in that projection.

Four further finite routes expose original semantic operations through purpose
forms: `profile_source_form`, `extrusion_form`, `working_unit_form` and
`working_plane_form`. Profile intake selects a canonical Dataset then distinct
enabled numerical Variable IDs, with explicit closure, append and unit policies.
Its delayed Apply checks the actual Curve Source payload/schema identity, native
Document revision and captured canonical working plane before `loadProfile`.
The latter reads the committed Viewer scene plane rather than uncommitted widget
variables. Extrusion previews through the original `extrudePreview`; final
Accept/Cancel retain their original scope checks and resource ownership.
Working units use Unit Registry length conversions and `convertWorkingUnit`,
preserving physical size. The plane form uses the existing scene validation and
`Engine3D::setWorkingPlane`; it does not implement plane geometry or affect
already captured profiles. Every delayed Apply checks the same native owner and
Document scope. These four routes require no new SDK call or native ABI.

Appending a contour replaces the captured existing logical profile, preserving
its ID, name, presentation and original ordered source bindings. The new
binding follows those existing contours; a multi-contour profile's first
binding alone does not identify every source. Only New allocates another
profile ID. Append provenance records the actual target. Operation inputs stay
captured across native RPC waits, independently of later selection changes.
Native staging precedes the canonical commit; failure restores the original
model, History, native profile token and tool state. Superseded native tokens
are released only after success. The focused native regression uses the actual
GUI-authored outer/HOLE resources and verifies a closed hollow extrusion of
1600 mm³ and 1136 mm², Undo/Redo and checkpoint-failure rollback. This contract
does not replace the required installed mouse/keyboard reproduction.

`publish_dataset_form` opens an explicit canonical-publication form for the
selected accepted object. It captures the native Document scope and selected
object, then calls the original `publish` extension through
`export.native3d_geometry`, Native3D Geometry Export and Dataset File Publication.
The normal file-export dialog does not implicitly publish a Dataset. STEP
requires B-Rep; STL/VTP use the existing complete-geometry export policy. Existing
Dataset IDs are not overwritten. Units, source bindings and provenance remain
the responsibility of the original exporters/publication owners.

The exact finite form/manager commands returned by `guiFormCommands` are:

```text
import_dataset_form combine_form extrusion_targets_form mesh_pair_form
details_form measurement_form constraint_form measurements_manager
constraints_manager organization_manager comparison_manager texture_form
texture_clear export_form recipe_manager extensions_manager documents_manager
translate_form rotate_form scale_form reset_transform_form tessellate_form
mesh_clean_form mesh_weld_form mesh_orient_form brep_heal_form
mesh_seam_form mesh_lod_form mesh_boundaries_form mesh_intersections_form
align_three_points_form clip_form clip_cap_form section_profile_form
duplicate_object group_create group_duplicate group_ungroup group_translate_form
group_rotate_form group_scale_form planar_section planar_projection
preview_accept preview_cancel profile_source_form extrusion_form
working_unit_form working_plane_form publish_dataset_form
```

The original `refresh`, `inspect`, `new`, `open`, `primitive`, `select`, `save`,
`undo`, `redo` and `close` host commands remain separate. Authors obtain this
list through the public manual/API metadata, without inspecting CORE source.

These routes are implementation contracts. Real installed geometry, all45 parity
criteria and full round-trip acceptance remain pending; opening a form or
returning a compiled plan is not that acceptance.

`duplicate_object` duplicates exactly one currently selected accepted, unlocked
object through the existing `deriveSelected duplicate` authority. It creates an
independent canonical object identity and one ordinary History operation while
retaining the source object and its scientific bindings. It takes no extra
parameters; the existing scene, owner, busy and selection guards apply. This
is distinct from `group_duplicate` and is available through the same finite
`Host::workbench_command(form, "duplicate_object")` contract in both sanctioned
developer tools. No development compiler is involved in the installed action.

### Canonical group selection at transform forms (dev109)

The existing group transform form accepts either one member or multiple members
of the same canonical group, including the full selection retained immediately
after Create group. `selectedGroup` is the shared owner resolver used by the
form and operation. Empty selection, profiles, ungrouped bodies and members of
different groups refuse before the form or mutation. Existing complete-member
lock and constraint checks still run before group transformation. This change
opens the original UIField form and uses the original native group operation.

The original Builder single-object shortcut also projects an explicit repeated
choice into its paired multiple-candidate list. A scoped activation binding runs
after UIField's original scalar validation; local projection precedes the
Viewer's scalar no-op guard. Normal Numeric fields and generic UIField callback
semantics are unchanged. Only Select commits authoritative selection.

Focused actual UIField/native tests verified 16 assertions for repeated-choice
projection, no scientific edit before Select, opening/cancelling a full-group
form, movement of both real native members, mixed-selection refusal and normal
cleanup. Installed corrective GUI acceptance remains separate.

After successful Document activation, the existing Workbench owner reports the
newly opened or new empty Document rather than retaining a previous Inspect
result. Its Builder refresh clears a local object candidate that is absent
from the current canonical ID projection. A focused seven-assertion contract
opens a real prior object, inspects it, saves/closes it, then uses the public
Builder New command and verifies empty candidate/list/status, empty native
model and unchanged original source/History. Installed corrective GUI remains
required; no previous scientific values are reinterpreted as belonging to the
new Document.
