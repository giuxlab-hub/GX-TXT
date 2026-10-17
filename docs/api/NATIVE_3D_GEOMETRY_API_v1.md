# Native3D Geometry API v1

`compare_sections` accepts owned `base`/`tool`, a shared explicit `plane`
(`origin`, `normal`, `u_axis`), positive chaining `tolerance`, `working_unit` and
optional scientific `sample_budget`6..4096. CORE sections the complete Native3D
geometry, captures chained contour resources and streams them as gap-separated
Native2D geometry. Native2D supplies bounded geometric distances/RMS/Hausdorff/
closest/length/defined-area differences. Projection rows are explicitly
`section_plane_xy`, accompanied by the frame, source sections and tolerance policy;
they are not world XYZ or full-surface distances. Temporary Native profiles/scenes
close after the query. Python and Octave expose typed rows/resources through the
same existing Native3D provider.

`compare_geometry` accepts owned `base`/`tool`, explicit `working_unit`,
`sample_budget`6..4096, `linear_deflection`, `angular_deflection`, `weld_tolerance`,
`max_triangles` and `max_output_bytes`. Additive C `gx3de_compare_geometry` samples
deterministic source vertex indices in both directions and builds one full-target
VTK triangle locator per direction. B-Rep inputs use the explicitly budgeted
tessellation. Readable rows include direction/source vertex/query/projected XYZ
and unsigned distance. Summary includes directed/symmetric RMS, mean/max, sampled
bidirectional Hausdorff and closest witnesses, Native exact area/defined-volume
differences and complete world bounds differences. Hausdorff/closest are sampled
metrics; no continuous-surface extrema or area-weighted RMS is asserted.
Policies, tessellation parameters and units accompany the typed Python/Octave
receipt. Complete triangle targets remain independent of renderer LOD/cache/view;
outputs remain unchanged on C failure and no Dataset is implicitly published.

`geometry_role` queries/sets regular, construction or reference participation on
an owned object. Additive C `gx3de_object_geometry_role_get/set` preserves geometry
fingerprints and copied-object roles. Exported owned resource metadata and restore
preserve role. Role is distinct from visibility, color or selection.

CORE scoped state adds `selection_set_{create,get,list,update,delete,activate}`,
`layer_{create,get,list,update,delete,assign}` and
`saved_view_{create,get,list,update,delete,restore}`. Each takes scene plus request;
collection tokens are opaque, scene-owned and limited to256 per kind. Names are
scientific labels, never automatic external solver boundary conditions.

Sets contain up to65536 verified `{object_token, optional anchor}` members with
captured geometry fingerprint/world placement. Get reports current/stale/missing;
Activate supports Replace/Add/Subtract and rejects invalid or unselectable Layer
members. Update explicitly captures new references. Layers independently own
visible/selectable/locked/color/opacity policies and member assignment; public
geometry mutations respect assigned edit locks. Saved Views contain validated
shared camera/projection/background/clipping/plane state, object-token visibility
and explicit working unit; Restore rejects missing objects or unit mismatch and
returns presentation data without modifying geometry. Python and Octave expose
typed receipts through the same existing provider.

SPDX-License-Identifier: GPL-3.0-or-later

`native3DGeometryOpen document_id` opens a retained CORE geometry scene in the
shared isolated Native3D worker. Its opaque token belongs to the current Session
lifetime, persistent document generation/revision and worker generation.
`native3DGeometryCall scene action request` uses the operations advertised by
`native3DGeometryApiInfo`. Source geometry remains immutable for transformations,
duplicates, Boolean results and mesh derivation. Ordinary renderer redraws
replace only view/cache state and preserve the authoritative geometry scene.

`native3DGeometryProfileFromSources scene sources plane tolerance` accepts
`{source_token closed}` entries from the shared Curve Source API. Exact finite XY,
gap bytes and original row identities become owned document resources through
the public resource APIs. Native contour input rejects missing-pair gaps,
crossings, touching contours, collapsed edges and oversized input; it captures
the explicit working plane. X/Y require equal declared units. Apply an explicit
Unit Registry/Dataset Transform conversion before using another working unit.

The resource-based `profile` request accepts contours with `xy_resource`,
optional `gap_resource` and explicit `closed`, plus `plane` and `tolerance`.
Planes use `origin`, `normal`, `u_axis`. `extrude` accepts `profile_token` and
signed nonzero `distance`. Returned object tokens expose bounded scientific
receipts, complete bounds, transform, fingerprint and B-Rep diagnostics.
`native3DGeometryCheckpoint scene payload` updates the authoritative document
and acknowledges its new revision. An external revision change invalidates the
cache; an in-flight change disposes newly produced geometry before error.
`native3DGeometrySceneInfo scene` validates ownership/revision/Session/worker
lifetime and returns a bounded document-generation/revision descriptor without
mutating geometry or the document. Script operation `scene_info(scene)` returns
the same public descriptor with the authority-side Session lifetime token omitted.
`native3DGeometryClose scene` releases the owned scope, including after a Session
change or worker loss. Scope reopening never revives previous native tokens.

Python and Octave Script Bridge share execution ownership for scene, object,
profile and Curve Source tokens. Their advertised operations accept typed arrays,
explicit source/plane/parameter structs and opaque handles. They do not expose
native pointers, arbitrary Tcl callbacks or private storage paths. Geometry
creation makes no Dataset Registry entry. Mesh/CAD Dataset publication remains
explicit through the normal File/Dataset Publication APIs.

`native3DGeometryExportResource scene object format millimeters_per_unit
?local|world?` imports a complete CORE-owned STEP/STL/VTP artifact into the
document. The default is world coordinates. `local` keeps immutable local
geometry and records complete placement separately. `load_step`/`load_mesh`
accept a `resource` reference; STEP millimetres are explicitly normalized into
the declared working unit before restoring recorded placement. Reset then
returns original local geometry rather than a transformed serialization.

Source-preserving Translate/Rotate/Scale, mesh Clean/Weld/Orient, B-Rep Heal,
Clip/Clip-cap and complete self-intersection queries use public Native3D APIs.
Mesh receipts report area/volume in world coordinates, with explicit validity,
boundary, nonmanifold, orientation and component counts. Mesh derivation requires
positive bounded triangle/output budgets. `group_copy` takes `object_tokens`
and copies their geometry into an independent native group; optional `matrix`
or `transform_action` applies one atomic shared placement. `group_duplicate`
uses the public atomic subtree duplication API. `group_delete` releases the
group and copied members. Source objects remain unchanged.

VTP `load_mesh` is an explicit geometry-only conversion of a complete pure
polygon/triangle-strip surface into an independent indexed triangle mesh. It
uses public `gx3de_scientific_triangle_mesh_create(source,max_triangles,
max_output_bytes,out)`, with adapter budgets of 1000000 triangles and 128 MiB.
Mesh diagnostics/repair operate on the actual triangle mesh. Scalar/vector fields
remain in the unchanged source VTP resource and are not transferred to the mesh.
PolyData containing lines or vertices is rejected, as is non-surface scientific
data; no non-surface cells are silently dropped. Conversion failure releases its
temporary imported object and publishes no geometry or Dataset result.

The shared host retains up to 64 independent document scenes concurrently.
Each owns its kernel and opaque handle namespace. Closing one scene preserves
other scenes; a foreign scene's object/profile/group token remains invalid.
This lets a controller hydrate and validate a history replacement before its
authoritative checkpoint, while keeping the current scene available for rollback.

`native3DGeometryImportDataset scene dataset_id working_unit ?assumed_input_unit?`
imports a complete Session Dataset into owned geometry. Supported inputs are
STEP and STL/OBJ/VTP surfaces. CORE resolves the canonical payload, verifies its
SHA-256 before and after intake, and retains the exact original resource.
STEP uses its embedded physical units; a Dataset unit label does not override
them. Mesh intake uses `geometry.working_unit`, or requires an explicit input-unit
assumption when metadata has none. Unit Registry converts coordinates into the
requested length working unit without a physical Scale operation. The receipt's
`dataset_binding` includes real Dataset ID/SHA, original resource, input and
working units, declared unit, unit policy and conversion factor. No Dataset is
created or changed. VTP fields stay in the immutable source resource while the
explicit editable surface conversion yields a Native triangle mesh.

Script operation `import_dataset(scene, dataset_id, working_unit,
assumed_input_unit)` uses the same authority and returns typed provenance and an
execution-owned object token. `anchor_describe` returns typed world point,
normal/tangent where defined and availability flags. `measure`,
`align_three_points` and `constraint_solve` accept nested typed anchors/arrays,
validate every embedded object reference and return independent derived receipts.

Mesh operations reuse the complete public Native3D kernel: `mesh_append`,
`mesh_merge`, `mesh_stitch`, `mesh_bridge`, `mesh_heal_seam` and `mesh_lod`.
Pair requests contain owned `base`/`tool` tokens and an explicit world-space
`tolerance` where required. Bridge/seam tolerance is a positive maximum gap;
CORE rejects ambiguous or incompatible boundaries. LOD requests choose
`preview|low|medium|high|full` and produce independent derived geometry.
Append/merge are not Boolean operations. Diagnostics preserve the CORE policy:
closed disconnected components report `volume_defined=false`, rather than
presenting a guessed aggregate volume.

`mesh_boundaries` accepts `object_token`, `max_items` (1..4096) and `max_vertices`
(1..65536). It returns exact complete edge/loop counts, bounded source-index
edge pairs, captured world loop points and explicit truncation flags.
`mesh_intersection_pairs` accepts a world `tolerance` and `max_items` (1..4096),
returning exact complete pair count, bounded deterministic triangle IDs/world
witnesses and truncation. Python and Octave receive typed nested records/arrays.
The native C `gx3de_mesh_boundary_edges_range` provides deterministic source-index
pages of at most 65536 edges, with copied/full counts and short final pages.
The prior all-or-error boundary-edge API keeps its existing behavior.

## Dev088 numerical and integrated planar extension

Headless `::GX::native3DGeometryApiInfo` and `::GX::native3DPlanarApiInfo` describe
these additive contracts without initializing Tk. Calls need a document-owned
scene from `native3DGeometryOpen documentId`; `native3DGeometryCall scene action
request` validates Session lifetime, document generation/revision and worker lifetime.
A stale scene must be closed/reopened. Object/profile tokens are process-local.
Persist resource descriptors and scientific definitions, never tokens.

| Action | Required request fields and result |
|---|---|
| `indexed_mesh` | `working_unit`, `points` (list of XYZ triples), `cells` (list of `{type triangle indices {i j k}}`), optional `arrays`. Returns retained scientific object with counts, fingerprint, bounds and transform. Degenerate triangle geometry is rejected. |
| `polydata` | Same schema; cell `type` is `vertex`, `line`, `polyline`, `triangle`, `polygon`. Each cell has zero-based `indices`. Connected cells are retained, not one layer per feature. |
| `masked_surface` | `working_unit`, row-major `points`, binary `present` list, `rows`, `columns`. A whole quad is absent if any corner is missing; two triangles per surviving quad. `source_point_id` and `source_cell_id` arrays preserve input correspondence. No interpolation. |
| `sweep` | `working_unit`, 3D path `points`, one positive `radii` value per point, `sides` 3..256, `caps` 0/1, explicit `initial_u`. Persistent triangles use a rotation-minimizing transported frame and tangent bisectors. Zero-length/reversing path or parallel initial axis is rejected. Source point/ring and segment/cap arrays are retained. |
| `load_scientific` | Managed `resource` with `format native3d.vtp.v1`. Restores connectivity/arrays losslessly. Historical `load_mesh` is unchanged and remains geometry-only. |
| `logical_id` | `object_token`, `association point|cell`, zero-based `index`. Resolves `logical_point_id` or `logical_cell_id`; returns integer `logical_id`. Missing/invalid identity is an explicit error. |
| `plane_frame` | `plane {origin {x y z} normal {nx ny nz} u_axis {ux uy uz}}`; optional `points` and `direction to_world|to_plane|project_point|project_vector`. Returns normalized origin/normal/U/V and mapped XYZ or UVW triples. Coordinate units belong to the caller's physical scene/document. |
| `project` | `object_token`, `plane`. New orthogonal geometry preserves scientific arrays; CAD requires explicit `mesh` tessellation first. Source immutable; overlaps/degenerate cells are preserved. |
| `projection_profile` | `object_token`, `plane`, positive `tolerance`. Projects actual surface boundary loops into a retained profile. Closed solids/no boundaries and over-budget contours report distinct errors. Not a silhouette. |
| `section_profile` | Existing request, now also accepts complete scientific surface objects through a temporary diagnostic mesh; original arrays remain on source. |
| `mesh` | Existing tessellation fields (`linear_deflection`, `angular_deflection`, `weld_tolerance`, `max_triangles`, `max_output_bytes`); a scientific surface produces an explicit geometry-only diagnostic mesh. Result reports topology/area/volume diagnostics. Source arrays remain on source. |

`arrays` entries are dictionaries `{name NAME association point|cell components N
values LIST}`. N is 1..16; tuples match the associated count. Values are finite
Float64. Logical IDs are exact nonnegative integers <=2^53-1, unique when the client
needs a unique feature. CORE does not invent source IDs. VTP export preserves the
arrays and connectivity in world coordinates; STL intentionally loses attributes.
`native3DGeometryExportResource scene object vtp millimetersPerUnit ?world|local?`
returns a content-addressed Document resource. Existing local-placement restrictions
remain. Scientific explicit `export` VTP writes losslessly and refuses overwrite.

Budgets: 1M points/cells, 6M connectivity entries, 64 arrays/16M values, 64 MiB Tcl
numerical request; native sweep output <=1M ring vertices (caps add two), raster
16..4096 per side. Invalid shape/index/finiteness/unit/ownership is rejected before
commit. Masked grids require at least one surviving quad. Sweep input radius may
vary; collision/self-intersection correction is not automatic. Finite absent grid
coordinates are required by the Tcl marshaler even though the native mask ignores
them. Scene closure releases temporary geometry; only an explicit checkpoint
updates an authoritative Document. No implicit Dataset publication occurs.

`native3DGeometryConvertAxes scene object {unitX unitY unitZ} targetUnit` uses Unit
Registry conversion factors and returns a new scaled object plus the conversion
receipt. It does not infer undeclared axis units or mutate the Dataset.

### Integrated owner workflow

- `native3DPlanarCreate sourcePath unit plane tolerance ?options?` creates a
  `viewer.engine_3d/engine_3d` Document (`gxtxt.native3d.planar`, version 1). Options:
  raster `width`/`height` (default1024/768), `color_array`, and required explicit
  STEP `tessellation` dictionary using the fields above. It generates source,
  section, projection, physical reference raster and origin/derivation records.
- `native3DPlanarList` lists persisted workflows; `native3DPlanarShow document
  source|all|section|projection|reference|accepted` reconstructs the actual modern
  Viewer scene. Both operations are independent of previous worker tokens.
- `native3DPlanarEditBegin document section|projection` captures revision,
  generation, SHA and Session token; returns token/context/payload.
- `native3DPlanarEditAccept token definitions unit presentation` accepts dictionary
  entries `{name LABEL definition NATIVE2D_RETAINED_DEFINITION units {u u}}` and
  `{reference_opacity 0..1 reference_visible boolean}`. It validates retained
  definitions and source again after derivation, then makes one owner checkpoint.
  Output is a new planar curve. Native2D `path` retains every straight vertex and
  explicit closure; other families are sampled at257 points. Source unchanged.
- `native3DPlanarEditCancel token` closes the edit without scientific writes.
- `native3DPlanarFocus document section|projection|accepted contourIndex` focuses
  a saved contour's durable cell identity in an already visible modern Viewer.

Create/Show/Focus require desktop rendering. Numerical capabilities and discovery
are headless. A failed Create removes its document and restores prior Viewer
layers/camera; generated content-addressed artifact cache files may remain reusable.
Accept failures retain the source revision, collect unreferenced staged resources,
and leave the edit open for correction/Cancel. Reopened stale drafts cannot Accept;
Cancel remains available even if the source has been deleted. Distinct edit intakes
receive distinct saved workspace names. The GUI uses the same public owner boundary.

See [Native3D Engine API](NATIVE_3D_ENGINE_API_v1.md) for calibration,
scientific policies, actual desktop steps and limits. Public Script Bridge calls use `gxtxt_api_call` and typed values. The corresponding
Tcl numerical/resource API follows the same documented CORE contracts. Python XYZ uses lists of triples;
Octave uses cell arrays of 3×1 vectors and cell arrays of cell/array structs.

Native C additive exports are declared in `native_3d_engine_api_v1.h`:
`gx3de_scientific_masked_surface`, `gx3de_scientific_sweep`,
`gx3de_scientific_logical_id`, `gx3de_scientific_write_vtp`, and selective target
presentation. They reuse the same engine, scene ownership, result codes and VTK
scientific data authority. `native_foundations.cpp` and `picking.cpp` are executable
standalone C++ clients (with assertions enabled).

### dev097 comparison interpretation and resource metadata

Surface and section comparison receipts preserve their existing fields and add
`statistics.reference` and `statistics.bidirectional` from public CORE statistical
semantics. Native surface RMS/mean/max reductions now use the public Numeric C
binding; closest-point queries, area, volume and tessellation stay in Native3D.
Surface records explicitly describe 3D unsigned nearest-triangle distances;
section records describe 2D unsigned nearest-curve distances in the captured
plane. Scientific budgets and full-target projection policy remain in provenance.

Section `position` is cumulative physical path distance, not a normalized
fraction. Its legacy `signed_residual` field contains the same unsigned distance
as `distance`; neither key nor values change. New Workbench Dataset publications
label these facts accurately and assign `position` the working length unit.
Previously published Datasets and historical releases are preserved.

Both language bindings preserve managed-resource metadata as the opaque metadata
dictionary used by `MANAGED_RESOURCE_API_v1`. A metadata `origin` denotes Object
Origin provenance, whereas a geometric `origin` is an XYZ point. Inspect resource
provenance through public `OBJECT_ORIGIN_API_v1/resource`; it is never converted
into a coordinate array.
