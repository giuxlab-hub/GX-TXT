# NATIVE_3D_ENGINE_API_v1 — dev-032 implementation record

Framework-wide graphics preferences and the public `gx3de_graphics_policy`
API are documented in [NATIVE_3D_GRAPHICS_POLICY_v1.md](NATIVE_3D_GRAPHICS_POLICY_v1.md).

## Scientific light sources (dev-043)

`GX3DE_CAP2_SCIENTIFIC_LIGHT_SOURCES` advertises a scene-owned spectral
source family. `gx3de_scientific_light_create/set/get/destroy/count` manages
up to 32 simultaneous sources without using or changing the four slots of
`gx3de_view_lighting` or `gx3de_view_positional_light_*`. The existing view
lights remain presentation lights. Every source has enabled and per-source
shadow switches, world position and normalized beam direction, intensity,
vacuum wavelength in nanometres, a 1–85° spotlight **half-angle**, finite
centerline `beam_range`, constant/linear/quadratic distance attenuation,
falloff exponent, and independent beam-visualization controls. Invalid input
leaves the prior source unchanged; scene destruction releases its sources.

Wavelength is the canonical spectral coordinate. The query
`gx3de_scientific_light_frequency_hz` uses exactly
`299792458 / (wavelength_nm × 10⁻⁹)` for the corresponding vacuum frequency.
`gx3de_scientific_light_display_rgb` derives a bounded approximate display
color for 380–780 nm. It is a visualization mapping, not a calibrated
radiometric or human color-matching calculation; outside that visible range
the stored spectral source has black display RGB. The renderer adds an
ordinary VTK positional spotlight for each enabled source, so imported STL
meshes, scientific sphere glyphs, and explicit geometric particle clouds
share the same illumination and shadow path. Source intensity is a scientific
state scalar; VTK display intensity is capped at 10. Spotlight attenuation
has no hard GPU cutoff at `beam_range` on this backend. Sources use the
ordinary scene shadow switch and their own shadow enable flag. Finite cones
avoid the VTK 180° omnidirectional positional-shadow limitation. With more
than four scientific sources, the generic shadow baker uses 1024² maps to
bound the aggregate map cost; otherwise its prior 2048² resolution remains.

`gx3de_object_scientific_transmittance_set/get` binds an independent flat
coefficient in `[0,1]` to a mesh object; `-1` removes the binding. An unbound
mesh does not participate in scientific beam attenuation. This property is
copied with ordinary object duplication and is **independent of visual object
opacity**. `gx3de_scientific_light_beam_sample` reports centerline position,
distance factor `1/(constant + linear·d + quadratic·d²)`, completed mesh
traversals, optical factor, and intensity at a distance no farther than the
source's beam range. For each explicitly bound closed mesh, the CORE pairs
deduplicated ray/triangle entry and exit intersections in world coordinates;
each completed traversal multiplies optical intensity by that mesh's flat
coefficient. Unmatched crossings from an open mesh do not attenuate. A
disabled source reports zero intensity. The source beam shown in rendered
views is a translucent, nonpickable centerline tube whose brightness follows
that CORE optical factor; it is visualization geometry, not a physical light
volume or shadow caster.

The dev-043 real-STL fixture sets `base_lampada.stl` visual opacity to 0.50
and scientific transmittance separately to 0.50. At 545 nm, its centerline
query reports intensity 1 before the base and 0.5 after one completed
traversal; setting only scientific transmittance to 1 restores downstream
intensity 1, while changing visual opacity leaves the 0.5 beam result
unchanged. `griglia.stl` is opaque and produces different VTK spot-shadow
patterns for different sources. Raster object shading and shadow maps are
still presentation approximations: the flat centerline optical factor is
**not** propagated into VTK illumination of arbitrary downstream surfaces,
and graphical alpha is not used as physical transmission. This is a minimal
scientific beam/material interaction, not a general ray tracer. Refraction,
scattering, diffraction, interference, fluorescence, polarization, spectral
material libraries, and volumetric absorption remain unimplemented.

## Scientific sampled density presentation (dev-040)

A sampled scientific density cloud is an ordinary `gx3de_object` created by
`gx3de_scientific_create_polydata` with point-associated arrays. Existing
`gx3de_scientific_field_roles.radius_array` scales the existing
`vtkGlyph3DMapper` sphere glyphs when `sphere_glyphs` is enabled; disabling
glyphs retains point presentation. `gx3de_scientific_opacity_array_set/get`
binds a normalized point scalar opacity. The object keeps its usual hierarchy,
transform, visibility, opacity, view clipping, `GX3DE_PICK_SCIENTIFIC`, and
cast/receive shadow flags. The renderer does not expand these samples into
individual mesh objects.

`GX3DE_CAP2_SCIENTIFIC_DIRECT_COLOR` advertises
`gx3de_scientific_color_array_set/get(object, array_index)`. The index is a
point- or cell-associated array in the scientific object's normal array enumeration;
`-1` clears it. A bound array has exactly three (RGB) or four (RGBA) finite,
normalized components per associated point/cell, all in `[0,1]`. The setter validates the
whole array and leaves the previous binding unchanged on error. Direct color
has priority over enabled scalar coloring; otherwise scalar coloring has
priority over object style color. Binding direct RGB/RGBA does not remove the
scalar role, so clearing the binding restores scalar presentation.

Rendered alpha is `clamp(object opacity × bound scientific opacity-array
value × bound direct RGBA alpha, 0, 1)`. Absent factors equal one. RGB has no
alpha factor. The display RGBA array is derived at render time without
changing source point arrays; both point and sphere-glyph mappers receive it.
The glyph actor is marked translucent when any derived point alpha is below
one, so per-point alpha reaches the renderer's normal transparency path.
This is geometric alpha blending and visibility, not absorption, scattering,
or a physical participating medium. Transparent glyph shadow coverage is
renderer dependent and is not density-dependent optical attenuation.

The prior unexplained 20,000 sphere-glyph ceiling is replaced by a 100,000
instance safety cap plus the queryable graphics policy's
`display_triangle_budget`. Glyph counts above 20,000 use an 8×6 sphere
tessellation instead of 12×8 to stay within the same display budget. The
budget applies to accumulated scene display geometry. A focused 22,000
glyph render is included in dev-040 evidence; very large scenes still return
`GX3DE_RANGE` when the cap or budget is exceeded.

For a continuous field, use the existing scientific image/VTI object and
Field API volume transfer function, isosurfaces, or slices. A sampled point
cloud and a volume may represent the same synthetic scalar field, but they
retain distinct presentation and data semantics. Existing Animation API
layers accept normal scientific objects for small time sequences.

On the current Linux VTK backend, the public positional lamp is an
omnidirectional VTK positional light with cone angle 180°. VTK's
`vtkShadowMapBakerPass::LightCreatesShadow` excludes positional lights with
cone angle 180° and accepts positional spotlights only below 180°. The public
lamp API has no spotlight cone, so silently narrowing its cone would change
its lighting semantics. Positional shadow-on/off images are consequently
pixel identical; directional opaque glyphs cast visible shadows. A future
generic renderer/backend feature may add true omnidirectional shadow maps.
No optical transmission or physical density shadows are claimed.

## Particle clouds and positional lamps (dev-039)

`GX3DE_CAP2_PARTICLE_CLOUD` advertises scene-owned particle clouds.
`gx3de_particle_cloud_create(scene, style, particles, count, &cloud)` copies
up to 100,000 finite particle positions. Zero particles are valid. The style
supplies a positive global radius, RGB color, and actor opacity in `[0,1]`.
Each `gx3de_particle` may override radius with `GX3DE_PARTICLE_RADIUS` and
color with `GX3DE_PARTICLE_COLOR`; otherwise it uses the global value.
`gx3de_particle_cloud_particles_set` replaces the complete array atomically.
Invalid data leaves the previous particles intact. `count_get`, `style_get`
and `style_set` query/update the model. `transform_set/get` accept the same
column-major affine matrix convention as mesh objects, and
`visible_set/get` control cloud visibility. The scene owns the cloud; explicit
`destroy` or scene destruction releases it. Existing object APIs do not take
a cloud handle.

The renderer draws each sample as a closed, smoothly shaded 20-triangle
icosahedral sphere. RGB zones are direct per-particle colors, while global
opacity is applied to the cloud actor. These triangles participate in ordinary
depth testing and, with opaque particles and scene shadows enabled, the
existing directional shadow-map pass. Opaque particles occlude geometry
behind them; gaps remain see-through. This is discrete geometric visibility,
not absorption, scattering, translucency, or an electronic-density volume.
This primitive remains useful for explicit atoms, beads, coarse molecular or
protein models, and similar discrete geometry. Scientific sampled density
uses the normal `gx3de_scientific_*` object path above instead.
There is no per-particle opacity, cloud self-shadow control, size-based level
of detail, or particle picking in dev-039. Transparent cloud actors may not
cast meaningful shadows with the current opaque shadow baker.

`GX3DE_CAP2_POSITIONAL_LIGHT` advertises
`gx3de_view_positional_light_set/get`. A size-tagged positional light can
override one of the four existing `gx3de_view_lighting` directional slots.
The slot must be below `light_count` to render. Its world position, RGB,
intensity, and constant/linear/quadratic attenuation are explicit. Disabling
it restores that slot's directional light. This is a standard local VTK scene
lamp, not a physical sun or optical propagation model. In the dev-039 Linux
renderer, positional lamps shade the particles and floor, but the current
shadow-map path does not produce a visible cast shadow for them because of
the VTK 180° positional cone exclusion described above. Directional
lighting does cast particle shadows. The evidence keeps both observations
separate rather than simulating a positional shadow.

## Surface-conforming image assignments (dev-038)

`gx3de_object_curved_texture_add_from_pick` creates an assignment from a real
`GX3DE_PICK_MESH` hit. The source triangle and anchor are object-local and
remain stable under object transforms. `gx3de_object_curved_texture_add`
accepts the same placement with an explicit source triangle. The existing
planar texture family is unchanged. The source mesh is not altered: the image
patch consists of clipped source triangles offset slightly for rendering.

The curved chart transports image coordinates across shared triangle edges by
unfolding each newly reached triangle from a shortest-distance traversal of
the picked face. Only edge-connected triangles are traversed. Nonmanifold edges
are stopped; `max_distance` bounds traversal, `max_edge_angle_radians` bounds
neighboring face-normal changes, and `max_seed_angle_radians` keeps reached
faces on the requested side. The chart is also bounded by the image extent.
Use narrower angle limits to remain on the outward face of a thick lattice.
The image anchor coordinates remain normalized in `[0,1]`; U/V flips,
rotation, move, proportional/stretch resize, object transforms, footprint
query, and common CORE handle IDs retain their dev-035 behavior.

`gx3de_curved_texture_status_get` returns chart and rendered triangle counts,
seam count, and diagnostic stop counts/flags for distance, angles, chart extent,
open edges, and nonmanifold edges. `gx3de_curved_texture_seams_get` returns
object-local 3D edge segments where adjacent rendered triangles have differing
transported coordinates. Like `gx3de_curved_texture_footprint_get`, query with
zero capacity first; `GX3DE_RANGE` reports the required count. A zero seam
count returns `GX3DE_OK`. These seams are a deliberate split of the chart;
strong curvature, cycles, and thick lattice struts may require a smaller
assignment to keep the visual transition smooth. The stop counts include
explored chart-frontier edges, so a limit flag does not by itself prove the
visible image was clipped. No automatic multi-chart blending is attempted.

The temporary `viewer.engine_3d` client displays the existing view-owned
Navigation Cube. It delegates hit testing and camera changes to
`gx3de_viewport_navcube_pick` and `gx3de_viewport_navcube_click`; the viewer
does not construct cube geometry or compute orientations.

## ABI, ownership and state

The public C header is `core/native3d/include/native_3d_engine_api_v1.h`; the native implementation is in `core/native3d/src/`. Call `gx3de_get_info` and check capability bits before using optional families. Handles are opaque and process-local. Numeric types are fixed width, descriptors are size-tagged, boundary strings are UTF-8, and result codes are explicit. No C++ objects, Tk, X11, Win32 or POSIX types occur in the public ABI. Creation outputs are valid only on `GX3DE_OK`.

All 64 bits of `gx3de_info.capabilities` are allocated. Additive renderer families `GX3DE_CAP2_RENDER_MARKERS` and `GX3DE_CAP2_TRANSFORM_GIZMO` are advertised in `gx3de_info.reserved[0]`, which is the ABI-v1 second capability word; the other reserved words remain zero. The B-Rep mesh conversion bit remains the top bit of the first word.

An engine owns scenes, targets, STEP documents and jobs. A scene owns objects, groups, planes, anchors, sections, profile snapshots, boundary-loop snapshots, measurements, constraints and views. A target owns viewport regions; each region references a same-engine view. Destroying an owner invalidates its child handles. An object can outlive a STEP document because it retains its immutable B-Rep prototype. Destroying an object freezes its anchors at their last world position. Deleted required measurement/constraint references cause `GX3DE_NOT_FOUND` on evaluation. Calls on one engine must be serialized by the caller; an import job's worker touches only its private input/result until the owner thread takes the object. Multiple engines do not share mutable scene, camera, selection or in-memory cache state.

## Geometry, transforms and profiles

Triangle meshes copy finite double XYZ vertices and 32-bit triangle indices into immutable storage. Duplicates share geometry but own independent transforms. Column-major affine 4x4 matrices provide translation, pivoted axis-angle rotation, nonuniform scaling, reset, local/world composition and hierarchy. Parent/world composition requires an invertible parent. Groups retain world placement when adding or removing objects. Three-point rigid alignment maps three congruent, non-collinear moving anchors to three fixed anchors without changing source geometry; it rejects noncongruent sets and rolls back on failure.

Planes support origin/normal/U axis, three points and XY/XZ/YZ presets, with world/plane coordinate conversion and point/vector projection. Mesh and OCCT B-Rep sections expose queryable 3D segments and 2D plane segments. Mesh sections extract the external boundary of exactly coplanar triangle patches, including partial overlaps and T-junctions, while omitting internal subdivision edges. Duplicate/degenerate coplanar faces and non-manifold or branched coplanar boundaries fail. `gx3de_profile_create` snaps endpoints at an explicit positive tolerance and creates ordered closed or open contour snapshots with point, length and planar-area queries. Profiles survive section destruction. Branched, crossing, overlapping and collapsed segment topology returns `GX3DE_DEGENERATE` instead of an invalid contour. Multiple disjoint contours remain separate. `gx3de_object_project` returns reusable, queryable world-space projected geometry for mesh, B-Rep and scientific sources. B-Rep projection requires explicit bounded tessellation settings; scientific projection preserves point/cell arrays. The projected object survives source destruction, while refresh then returns `GX3DE_NOT_FOUND`. Projection can leave degenerate triangles.

`gx3de_mesh_clip` retains the existing uncapped VTK mesh clip. `gx3de_mesh_clip_capped` adds an explicitly toleranced, conservative cap path for transverse cuts of closed, consistently wound meshes with simple section contours. It matches each clipped boundary loop to the actual section profile and triangulates those boundary vertices. Independent convex/concave loops use ordered ear clipping; nested contours with alternating outer/hole orientation use VTK contour triangulation on the same clipped boundary points, with a 10,000-edge and 64-loop budget. The latter supports cavities and islands within cavities. It checks cap area, triangle location, closed manifold topology and nonadjacent face intersections before publishing the new mesh. Open input, detected nonadjacent self-intersections, a plane through an input vertex, touching/intersecting or inconsistently wound contours, a cap that cannot be triangulated safely, or unmatched cut boundaries return an explicit failure. The intersection diagnostic excludes face pairs that share vertex indices, so it does not prove global geometric validity. For a tangent or face-coincident plane with all source vertices on one side, capped clipping returns an unchanged closed mesh on the kept side or `GX3DE_NOT_FOUND` on the empty side. A plane touching vertices while crossing material still returns `GX3DE_UNSUPPORTED`. OCCT solid half-space clipping produces a capped B-Rep only when input and output contain validated closed, oriented solids with finite nonzero volume; tests now include oblique, offset, rotated, coincident-face and multi-solid cuts. Empty clips return `GX3DE_NOT_FOUND`. B-Rep clipping and booleans currently reject nonuniform placements.

Mesh append, explicit-tolerance weld/merge and duplicate cleanup create new objects. Boundary-edge and ordered boundary-loop queries expose actual topology. Loop extraction rejects branched or inconsistently wound boundaries. Stitching pairs complete reverse-winding loops with the same vertex count and explicit Euclidean tolerance. For separated boundaries, `gx3de_mesh_bridge` creates faces between one simple loop on each mesh, and `gx3de_mesh_heal_seam` closes two loops on one mesh. Both take a positive maximum world-space gap and publish only a uniquely paired, connected, closed, consistently oriented solid without detected self-intersections. They reject incompatible loop sizes, ambiguous pairings, degenerate faces, nonmanifold inputs, and extra unmatched loops. Neither splits edges or repairs arbitrary mesh defects. Normal repair makes edge-manifold components consistently wound and flips closed components to positive signed volume; it rejects degenerate/nonmanifold/nonorientable cases. Self-intersection diagnostics count nonadjacent triangle pairs within an explicit distance tolerance. `gx3de_mesh_intersection_pairs` also returns source triangle-index pairs and finite world-space witness locations. Exact-contact witnesses lie at contact; a near-contact witness is the midpoint between detected closest points. A zero-capacity query reports the required count through `GX3DE_RANGE`; each call copies at most one million records. Pairs have ascending indices within each record and deterministic broad-phase order. Index-adjacent pairs are excluded, and positive tolerance also counts near contacts. Mesh diagnostics report area, boundary/nonmanifold/orientation edge counts and components; volume is defined only for one closed, consistently oriented component. No physical unit is inferred.

Native OCCT B-Reps support boxes, bounds, area/volume, sections, solid clipping and explicit union/intersection/difference. `gx3de_object_geometry_fingerprint` also accepts B-Rep objects and hashes a bounded serialization without display triangulation, scoped by cache namespace and OCCT version. Object placement does not change this local-geometry fingerprint; the digest does not make subshape indices persistent across Booleans, clips, rebuilds or reimport. `gx3de_brep_validate` reports OCCT topology validity, whether the immutable source consists entirely of closed oriented solids, and solid/shell/face counts. It diagnoses intrinsic source shape topology independently of object placement. `gx3de_brep_heal` returns an independent scene object for an already valid closed solid without modifying its topology. For an invalid solid with finite properties it deep-copies geometry and applies OCCT ShapeFix at an explicit tolerance; it publishes only if the output is validated closed/oriented and solid count, area, volume and bounds remain within conservative limits. Surface-only, unbounded, substantially changed or still-invalid shapes return `GX3DE_UNSUPPORTED`. The valid-solid path has a public C test; repair of a damaged STEP solid still needs a controlled invalid-shape fixture to establish coverage. Topology counts and zero-based vertex/edge/face anchors refer to an exact immutable shape. Edge fractions are curve-parameter fractions, not arc length; face fractions are UV-parameter fractions and may be rejected outside trimming. Anchor positions, face normals and edge tangents follow non-destructive object transforms. Topology indices survive transforms and duplication of that same shape, but cannot be persisted across booleans, clips, rebuilds or reimport.

`gx3de_object_brep_mesh_create` converts any native B-Rep object, including a programmatically created solid or STEP occurrence, into an independent triangle mesh object. Its `gx3de_brep_mesh_spec` aliases the proven STEP tessellation descriptor: callers must supply positive linear/angular deflection, nonnegative weld tolerance, triangle limit and output-byte limit. The same OCCT deep-copy tessellator is used; source topology and placement remain unchanged. The derived mesh inherits placement, visibility, opacity and source-file SHA where present. `gx3de_object_derivation_fingerprint` returns the immutable source B-Rep geometry digest separately from the derived mesh's own geometry digest, even after the source object is destroyed. On Linux, synchronous conversion uses a separate, SHA-256-validated transactional mesh cache key based on namespace, source B-Rep fingerprint, tessellation parameters, budgets and OCCT version. A corrupt entry is rejected and rebuilt. `gx3de_job_prepare_brep_mesh` retains the immutable source shape and runs the same bounded conversion in an engine job; cancellation is honored before and after OCCT's uninterruptible meshing call. The asynchronous path does not populate the persistent mesh cache.

Free line, object-local axis and whole-object-reference anchors provide renderer-independent hit conversion for line/axis and object selection. A line anchor has a world point and unit tangent. An object-axis anchor follows the object's full affine transform; its tangent is normalized after the linear part of that transform. A whole-object anchor refers to the object's local origin. Destroying the object freezes an axis as a free line when its transformed direction is nondegenerate, and freezes a whole-object reference as a free point. These handles are scene-owned and are not renderer cell IDs.

`gx3de_object_create_brep_cylinder` adds an analytic positive-radius, positive-height cylinder on the source-local Z axis. `gx3de_brep_edge_geometry_get` reports an indexed edge's OCCT curve family, finite parameter range, arc length at a positive source-unit tolerance, source-local endpoints and unit endpoint tangents. `closed` compares those endpoints at that tolerance. `gx3de_brep_face_geometry_get` reports the indexed face's OCCT surface family, finite UV bounds and periodic closure flags. Both queries use zero-based indices of the exact immutable source shape and ignore the object's presentation transform. Face UV bounds are rectangular parameter limits and can contain positions outside a trimmed face. An edge with undefined endpoint derivatives, a nonfinite range or an unsupported degenerate length fails explicitly. These indices remain valid under object translation, rotation and duplication of the same shape, but are not stable identifiers across healing, Boolean operations, clipping, rebuilds or reimport. Neither query creates a persistent topology identity.

## Scientific objects and fields

The public `gx3de_scientific_create_image` constructor copies an in-memory image grid with inclusive integer extent, finite origin and nonzero spacing, invertible direction matrix, and named numeric point/cell arrays. It validates tuple counts, finite values, the existing point/cell limits, and an explicit input-data budget (256 MiB by default). The in-memory grid has a deterministic geometry-and-field SHA-256 fingerprint but no file-source SHA. It supports the same query and explicit isosurface operations as imported VTI.

`gx3de_scientific_create_unstructured` copies caller-owned points, ordered cells and named numeric point/cell arrays into an independent VTK unstructured grid. It supports vertices, lines, polylines, triangles, polygons, tetrahedra and hexahedra. Cell data follows the input cell order. Validation enforces finite coordinates/values, valid and nonrepeated cell point IDs, exact array tuple counts, the existing point/cell/reference limits, and a configurable estimated input-data budget (256 MiB by default). The result has a deterministic geometry-and-field SHA-256 fingerprint and no file-source SHA. These estimated input budgets are limits on the supplied geometry/array data, not measured peak process memory.

`gx3de_scientific_vector_samples` deterministically samples a selected three-component point array using source point IDs `0, stride, 2*stride, ...`, where `stride=ceil(point_count/max_samples)`. The size-tagged output records contain point IDs, positions, and vectors. World-space mode applies the object world transform to positions and its linear part to vectors. The required result count can be queried before copying; errors do not partly overwrite records. The renderer uses these samples for bounded vector-arrow presentation.

On Linux, `gx3de_engine_set_scientific_cache_root` enables a separate persistent cache for nonempty isosurfaces derived from imported VTI or in-memory image grids. The key includes the engine namespace, source geometry/field fingerprint, selected scalar, exact isovalue, contour algorithm tag and VTK version. The cache stores complete VTK polydata XML under a SHA-256 checked header, rejects incomplete/corrupt entries, and replaces them through same-directory temporary publication with file and directory `fsync`. Unsafe symlinks are rejected. `gx3de_engine_scientific_cache_stats` reports hits, misses, invalid rebuilds and store failures. Invalid entries are regenerated from the authoritative grid; a store failure leaves a successfully generated isosurface available. Empty isovalues are recalculated and not stored. The cache never contains camera, view, selection, working-plane or other mutable presentation state. This cache is a derived isosurface cache; imported scientific XML source data and in-memory source grids are not persisted by it.

The additive scientific API keeps native VTK datasets in scene-owned `gx3de_object` handles, with immutable source data shared by duplicates and independently mutable visibility, opacity, transform and field-role metadata. `gx3de_scientific_import` reads VTP polydata, VTU unstructured grids or VTI image grids. `gx3de_scientific_create_polydata` copies caller-owned points, vertex/line/polyline/triangle/polygon cells and numeric point/cell arrays into an independent native object. A point set may have zero cells. Cell-associated input tuples follow the caller's cell order; the native copy remaps them to VTK's canonical vertex, line, polygon order. Destroying a scene releases its scientific objects; no renderer or viewer process owns their data.

`gx3de_scientific_info_get`, `gx3de_scientific_grid_info_get`, `gx3de_scientific_point`, `gx3de_scientific_cell_info_get` and `gx3de_scientific_cell_point_id` expose counts, VTI extent/origin/spacing/direction, local or transformed world coordinates, and cell connectivity. Existing object bounds work for scientific objects. Numeric array descriptors enumerate point arrays before cell arrays and report association, name, tuple count, component count and component-based scalar/three-vector/other classification. `gx3de_scientific_array_find` requires the requested association and exact UTF-8 name; it never guesses an active array. `gx3de_scientific_array_values` copies a caller-bounded tuple range into doubles and reports the required value capacity. Source arrays remain unchanged.

`gx3de_scientific_field_roles_set/get` stores per-object indices for a selected scalar color field (point or cell, one component), point vector field (three components) and nonnegative point radius field (one component), plus a nonnegative tube radius for line/polyline data. `-1` means unbound. These roles are presentation metadata over authoritative arrays. The renderer builds sphere glyphs, tubes, vector arrows and scalar lookup tables from them without changing the source data. `gx3de_scientific_presentation_set/get` selects the colormap, optional scalar range, sphere glyphs and bounded vector arrows; `gx3de_scientific_opacity_array_set/get` optionally selects a point scalar in `[0,1]` for per-point opacity. Generic object opacity is independently set/get in `[0,1]`. Duplicates copy presentation state, while independent imports and scenes start with visible objects, opacity `1`, and unbound fields. Array identity is stable only within the immutable object; it is not a cross-import persistent ID.

`gx3de_scientific_isosurfaces` accepts one to 32 finite explicit isovalues and an exact named one-component **point** scalar on a three-dimensional imported VTI or in-memory image grid. It uses the legacy viewer's VTK contour path with `vtkContourFilter`, then triangulates each result without changing the source's active-scalar metadata or values. Each nonempty value produces a separate queryable scientific triangle object with its own isovalue/scalar metadata and SHA-256 operation fingerprint. An out-of-range value yields a `NULL` output slot under `GX3DE_OK`; all slots are assigned only after a successful batch. Derived objects retain the imported source SHA-256 when one exists. Their fingerprint includes the source fingerprint, selected field, value, VTK version and contour algorithm tag, so repeated calls with the same inputs are stable and different values are distinct. They share immutable data only inside the owning engine/cache namespace.

Scientific XML imports require an existing regular file with the matching `.vtp`, `.vtu` or `.vti` extension. The default source-byte limit is 256 MiB; the native backend also rejects more than 10 million points or cells, 30 million cell references, 256 arrays per association, invalid connectivity, non-finite coordinates/values, missing or duplicate numeric array names, tuple mismatches and numeric arrays outside 1–16 components. It SHA-256 checks the exact file before and after VTK reading. Before VTK array loading, the reader checks declared point/cell counts, array counts and a 256 MiB minimum decoded-data estimate from metadata. Immediately after the blocking VTK `Update()`, it checks VTK-reported data memory and validates the decoded dataset before making an independent copy. A decoded-data budget violation returns `GX3DE_RANGE`. VTK may transiently allocate more than this budget inside `Update()`; the limit is not a process RSS cap. Source scientific XML datasets are not persisted in the derived cache. The in-memory scientific cache is rebuildable from the object fingerprint and never shares mutable scene state. The legacy scientific capability comparison is in `docs/developer/NATIVE_3D_SCIENTIFIC_PARITY.md`.

## Import, source identity and cache

Synchronous VTK OBJ/STL import has a configurable source-byte limit (256 MiB default). Before VTK reads an OBJ, the golden viewer's indexed-record validation rejects missing, malformed, out-of-range and invalid relative vertex/texture/normal references, including line and point records. Binary STL length and finite coordinates are checked. Exact source bytes are SHA-256 hashed before and after import; changing inputs are rejected. Imported objects retain their source hash separately from the geometry fingerprint. The `gx3de_mesh_import_spec.max_memory_bytes` field occupies a former reserved slot without changing the ABI size. Zero selects 4096 MiB; explicit values must be 32..1048576 MiB. Full synchronous and job imports preflight binary STL at 640 bytes per triangle and OBJ at 16 times source bytes, including cache hits. ASCII STL uses the conservative 16 times source-byte estimate. This estimate guards VTK construction; it is not a measured resident-memory ceiling.

`gx3de_object_import_mesh_preview` can produce an early, queryable mesh before the blocking full VTK import. Binary STL previews sample by stride with the frozen viewer's target `min(100000, max(64, triangles/100), memory_budget/1024)`; all binary records are validated and the output has at most 100,000 triangles. OBJ previews use the viewer's positive absolute face-index scan, SplitMix64 face selection and target `min(30000, max(64, faces/100), max(64, memory_budget/4096))`, with at most 50,000 fan-triangulated preview triangles, 150,000 selected vertices and a 1 MiB line bound. Relative/unsupported OBJ indexing and ASCII STL return `GX3DE_UNSUPPORTED`; the full import remains available. Previews SHA-256 check exact source bytes before and after and retain source identity. The preview call is synchronous and independent of full import; a caller can publish it immediately and later replace it with the full object. Blocking VTK import remains uncancellable until `Update()` returns. `gx3de_mesh_lod` builds queryable, independently transformable derived mesh objects at the viewer's preview/low/medium/high/full fractions (1/5/20/50/100%). It ports the viewer's source-point quadric clustering for the two coarsest levels, volume-preserving decimation for medium/high, and 2% per-axis bounds-envelope fallback to clustering. The output inherits source identity and uses the engine's immutable mesh fingerprint cache. The GUI adapter publishes a preview first, then fuller geometry in its isolated worker. Renderer and child-process budgets are documented in `core/native3d/README.md` and the adapter manual.

STEP import uses native OCCT XDE. The dev-032 backend retains assembly/part occurrence hierarchy, names, label and definition IDs, parent indices, local/world transforms and shared part prototypes. The OCCT 7.8.1 repeated-occurrence transfer lookup fix is conservatively ported from the golden viewer. Callers can query nodes and instantiate part occurrences as independent B-Rep objects in any scene of the owning engine. `gx3de_step_instance_mesh_create` tessellates a deep copy of one shared prototype under explicit linear/angular deflection, weld tolerance, triangle and output-byte budgets. Occurrences retain their independent world transforms and source SHA; identical requests reuse the document's prototype mesh. On Linux, the same validated transactional mesh disk cache stores derived prototype meshes under the STEP source SHA, namespace, prototype ID, tolerances, budgets and OCCT version. Corruption causes a rebuild. OCCT's blocking mesher can allocate before the output budget is checked. No assembly flattening is presented as equivalent. The C API has a source-byte limit (256 MiB default), node budget (100,000 default), source SHA check and clean document lifetime. The renderer presents XDE occurrences with reusable prototype display data; the GUI adapter first publishes a coarse STEP presentation, then fuller geometry.

Each engine has an immutable in-memory mesh cache keyed by a SHA-256 geometry fingerprint and explicit namespace. On Linux, callers may select a separate persistent mesh cache root for synchronous STL/OBJ imports. Its key includes namespace, exact source hash, format, importer/schema version; the entry checks header, counts, exact length, finite geometry, indices and payload SHA before reuse. Invalid regular entries are rebuilt through a same-directory temporary file and atomic rename; unsafe symlinks or path traversal are rejected. Disk cache statistics expose hits, misses, invalid rebuilds and store failures. This is a derived mesh cache, not the viewer's display cache. A write failure leaves a successfully imported object available and increments `store_failures`. Persistent cache support is not advertised on Windows.

`gx3de_mesh_repeats_discover` snapshots a triangle mesh and its world transform and matches disconnected components congruent with the selected source triangle's component. It ports the frozen viewer's bounded geometry signature and 24 proper orthogonal rotations, with exact coincident-point connectivity corresponding to the viewer's pre-matching clean pass. The public result reports the selected triangle, triangles per component, match count, unmatched triangles, tolerance and a SHA-256 derived fingerprint. `gx3de_mesh_repeats_placement` yields world transforms for instances of the centered prototype mesh. Callers can create queryable prototype and unmatched remainder objects and destroy the result independently; a completely matched source has no remainder and returns `GX3DE_NOT_FOUND` for that query. The result remains valid if the source object is deleted, but destroying its owning scene invalidates it. Matching is bounded to one million source triangles, three million source points and 100,000 triangles in the selected component. On Linux, the optional mesh cache root also stores the complete prototype, placements and unmatched remainder as one versioned, SHA-256-validated payload under `<root>/repeats`. The key includes namespace, source geometry fingerprint, selected triangle and matching algorithm version. A single same-directory temporary file is fsynced and atomically published; corrupt or incomplete entries are rejected and rebuilt, unsafe symlinks are refused. `gx3de_engine_repeat_cache_stats` reports hits, misses, invalid rebuilds and store failures separately from the ordinary mesh cache. Camera, selection, visibility, object transform and other mutable state are never cached. `gx3de_mesh_repeats_presentation_set/get` presents a captured prototype at each placement with a shared mapper, plus unmatched remainder geometry, while leaving the authoritative source untouched.

## Measurements, constraints and jobs

First-class measurements retain anchors, planes and optional mesh surfaces. Implemented values include 3D point distance, signed XYZ deltas, distance projected on a plane, three-point angle, point-line/point-plane/line-line/line-plane/plane-plane angles or distances, and VTK point-to-triangle-surface distance. Angles are radians and unoriented where appropriate. `unit_known=0` unless a future source descriptor supplies a unit.

Basic constraints declare/evaluate/solve fixed pose, coincident point, target distance and point-on-plane. Extended constraints declare/evaluate angle, parallel and perpendicular lines, point-on-line, point-on-mesh-surface and aligned axes. Individual rigid-transform solves are available for angle, parallel, perpendicular, point-on-line and aligned axes. Point-on-surface uses the VTK nearest triangle point to translate one rigid object; it does not rotate that object or solve a surface normal alignment. Empty/degenerate surfaces fail explicitly. A solved but underconstrained relation reports `UNDERDETERMINED`; a proposal that violates an already-satisfied same-object constraint rolls back and reports `OVERCONSTRAINED`. `gx3de_constraint_system_solve` transactionally solves a selected set of up to 256 scene constraints across independent rigid objects in at most 128 passes (16 by default). It jointly aligns two or three or more congruent coincident-anchor pairs on one object and iterates dependencies between separate objects. All selected constraints and any other initially satisfied constraints on the same moving objects are checked before commit. Inconsistent, unsupported or unconverged systems restore all selected transforms. A fully determined status is claimed only for a fixed object or three noncollinear coincident anchors; other satisfied systems report `UNDERDETERMINED`. Selected objects in a parent-child relationship and general nonlinear CAD systems remain unsupported.

Asynchronous mesh import, mesh LOD and STEP/XDE import jobs are prepared, started, polled or waited, emit ordered state and stage-progress events (0–1000 permille), and can be cancelled. Mesh jobs yield one immutable object; an engine-owned STEP job yields one document through `gx3de_job_take_step` on the caller thread. `gx3de_job_progress` queries the latest stage and `gx3de_job_failure_text` returns UTF-8 failure information with the usual required-byte/capacity contract. Stage progress is monotonic, not a byte or time estimate. A LOD job snapshots immutable source geometry, placement, visibility, opacity and source SHA, so deletion of the source object does not invalidate the prepared job. STEP jobs enforce the same source-byte and node limits as synchronous import and compare source size and SHA-256 before and after transfer. Cancellation before start is deterministic; a running STEP job checks cancellation immediately before and after OCCT `STEPCAFControl_Reader::ReadFile` and `Transfer`, during XDE traversal, and after the final source check. Those two OCCT calls are blocking and cannot be interrupted. VTK's blocking `Update()` calls have the same limitation. Scene or engine destruction cancels and joins their jobs before freeing owner state. Jobs currently bypass persistent derived disk caches and have no generic scheduler or scientific job type.

Each view owns eight optional world-plane clipping descriptors and one temporary interaction descriptor, independent of other views on the same scene or target. A clip descriptor stores a normalized normal and side; clearing it uses `enabled=0`. Interaction mode is an explicit `NONE`, `POINT` or `DRAG` enum with world positions and pointer ID. The renderer applies enabled planes and an optional view-local world-space clip box non-destructively. VTK's mapper accepts at most six combined clipping planes, so an enabled six-face box cannot be combined with another plane; requests exceeding that limit fail explicitly with `GX3DE_UNSUPPORTED` and a render diagnostic.

## Renderer and Viewer Provider continuation

`gx3de_target_create_headless` now creates an offscreen pixel target; `gx3de_target_create_native` accepts a platform-neutral kind and integer native window ID for an interactive target. A target owns one or more viewport rectangles, each referencing a same-engine view. `gx3de_target_render` renders them together, and `gx3de_target_read_rgba` or `gx3de_target_write_png` copies the completed frame. `gx3de_view_render_rgba` and `gx3de_view_write_png` render one view at a caller-supplied resolution through a temporary offscreen target. Pixel capacity and target dimensions are checked before rendering; rendering never changes authoritative geometry. `gx3de_target_render_diagnostics` returns the most recent target error text, including OpenGL startup and clipping-limit failures.

Views hold independent camera, perspective/orthographic projection, background, lighting, clipping, working-plane, selection and interaction state. A set working plane appears as a bounded view-local grid and outline; clearing it removes the guide. Camera presets cover front/back/left/right/top/bottom/isometric and fit scene/object/selection. An object has independent visibility, opacity and display style: surface, wireframe, surface with edges, points, color, line/point size, scalar coloring and backface culling. Section and profile snapshots have their own curve styles and explicit source-refresh operations; projected meshes keep a source and plane link and can be refreshed explicitly. Scene or view markers resolve API anchors on each render; measurement styles show their endpoints and current value without modifying referenced geometry. A repeat result can display its captured shared prototype placements and unmatched remainder while leaving its source mesh intact.

Scientific presentation uses the source dataset and selected field roles: VTP/VTU/VTI point or cell scalars, colormap and optional scalar range, point/sphere glyphs with optional radius arrays, line/trajectory tubes, sampled vector arrows and independently visible explicit VTI isosurfaces. An optional point scalar in `[0,1]` supplies per-point opacity; object opacity remains separate. Render budgets bound pixels, displayed triangles, point/cell counts and costly glyph output. The exact limits and GLX/Mesa process caveats are recorded in `core/native3d/README.md`.

`gx3de_viewport_pick` returns a hit's borrowed object, world and object-local position, optional world normal and transient display cell/point indices. For a uniquely identified trimmed OCCT face it also returns an index and UV parameters of the immutable source shape. `gx3de_pick_make_anchor` converts a hit to a scene-owned API anchor; repeated-instance hits use a world-space snapshot when one source object represents several placements. Callers must persist their own stable object/layer and local-geometry references, not VTK display cell IDs. The `viewer.engine_3d` adapter maps Viewer Provider layers, Dataset variable IDs, source SHA, camera and presentation definitions into these C calls, presents images in a real Tk Viewer window, and stores compact scene definitions in Session metadata. The frozen `viewer.native_3d` remains installed as a compatibility reference.

`gx3de_view_axes_set/get` displays world axes, selected-object local axes and an anchor reference-axis indicator independently of an active manipulator. A view-owned gizmo attaches to an object with world or local space, object/explicit/anchor pivot, pixel-sized axis/plane/free translation handles and X/Y/Z rotation arcs. Hover and active state are view-local. `gx3de_gizmo_pick` identifies a rendered handle, while `gx3de_viewport_ray` and the screen begin/update helpers turn pointer pixels into rays; clients may also pass rays directly. Begin snapshots scene poses. Update computes the axis/plane translation or rotation and returns a proposed local transform, translation, angle and constraint status. In live mode it applies a temporary pose; end accepts or rolls it back. In `preview_only` mode update returns a proposal without mutating the scene and end never commits. Constraints referencing the dragged object are solved transactionally, with scene poses restored on failure. Local manipulation rejects sheared/nonorthogonal frames; no source geometry is changed. The Viewer Provider adapter forwards mouse input and persists only committed layer transforms, not transient handle IDs or drag state.

## Final generic presentation additions

`gx3de_plane_get/set` query and update an existing working-plane frame without
replacing its scene handle. `gx3de_view_manipulation_begin/update/end` use a
viewport pixel ray and current camera to drag working-plane origin or
orientation, clip-plane origin or orientation, and an individual clip-box face.
Translation may be free or constrained to an axis; rotation uses an X/Y/Z
axis. A drag snapshots its initial state and `end(accept=0)` restores it.
The GUI forwards pointer pixels and persists only returned plane/clip state.
The six-plane VTK clipping limit described above still applies.

`gx3de_view_lighting_preset` resolves scientific-neutral, high-contrast,
soft-diffuse, and flat-unlit choices into the normal editable lighting state.
`gx3de_image_output_info_get` reports RGBA channel order, 8-bit components,
straight alpha, sRGB transfer expectation, and the PNG encoder's untagged
color-space behavior. Consumers should not infer an embedded PNG sRGB/gAMA
chunk; PNG bytes use the same transfer expectation as RGBA readback.

## Explicit limits

The renderer additions use named, versioned capability groups via
`gx3de_get_capabilities`. CORE, renderer, animation and field each return four
capability words. The original `gx3de_info` layout and its assigned bits remain
ABI v1 compatible. The field and animation entry points have separate public
headers and a detailed contract in `NATIVE_3D_FIELD_ANIMATION_API_v1.md`.
Renderer additions include target/viewport resize and device-pixel ratio,
CORE camera navigation and orthographic scale, quality/supersampling controls,
render statistics and backend/adapter diagnostics. `gx3de_target_gpu_budget_set`
sets a per-target estimated GPU resource limit; `gx3de_target_render_resource_info_get`
reports the estimate, configured limit, last rejected estimate and explicitly
unavailable exact driver allocation. The limit is checked before backend
resource creation and returns `GX3DE_RANGE` when exceeded. The Linux/OpenGL
renderer reports the actual adapter and hardware/software execution. A
Windows-only D3D11 source path creates a hardware device/context, color/depth
targets, native swap chain when applicable and RGBA staging readback. It has
not been compiled or run on Windows; see `core/native3d/WINDOWS_RENDERER_ARCHITECTURE.md`.

Sampled B-Rep section profiles do not preserve exact analytic section curves; topology indices are valid only for one immutable B-Rep and cannot be made persistent across Boolean/rebuild/reimport. Nonuniform B-Rep placements are rejected by Boolean/clip paths. A mesh plane passing through vertices while crossing material is rejected when a safe cap cannot be proven, and seam bridging requires unique equal-size simple loops. OCCT ShapeFix publication is guarded; a damaged solid that is safely repairable has no controlled public STEP fixture yet, so that success path has not been claimed as validated. VTK/OCCT blocking calls cannot honor cancellation within the call. Estimated GPU and in-process data budgets do not measure exact VRAM or peak resident memory inside VTK or OCCT; the Linux GUI adapter separately enforces a child address-space limit and samples worker `VmRSS` during RPCs, terminating a worker that exceeds its configured budget. The Linux X11/Mesa path has been tested in software and once on the NVD9 hardware renderer; a real Windows build and GUI run require a Windows environment. The public ABI retains fixed-width C types, UTF-8 strings, opaque handles and Windows import/export annotations.


### Generic scientific figure capability (dev087 correction)

Additive header `native_3d_scientific_figure_api_v1.h` exposes
`gx3de_view_scientific_figure_set/get(view, spec)` and `gx3de_view_camera_roll(view, radians)`.
The copied view-owned fixed-size spec contains enabled/axes-grid/colorbar flags, world
box bounds, three linear increasing calibrated ranges and UTF-8 labels, title/legend,
scalar label/range and 2..256 exact RGB palette entries. It does not change source objects.
Scale/direction transformations belong to scientific preparation; nonlinear/reversed
mapping is not advertised. Invalid ranges, lengths/palettes reject atomically.

The existing VTK Native3D backend renders a calibrated `vtkCubeAxesActor` and original
lookup-table `vtkScalarBarActor`. Axes, ticks and major grids track the native camera
through roll as well as orbit. A reserved scalar rail and an expanded figure frustum
retain complete labels with the same world/pixel projection as the scientific scene.
Text scales with physical output resolution. Figure output has an opaque background;
legacy previews' rendering/alpha/cubes are unchanged. This capability requires the VTK
backend; D3D11 reports UNSUPPORTED rather than silently dropping scientific axes.

Native target resize and offscreen/supersampling use the same view/objects. Resize may
rebuild viewport presentation actors but never reimports scientific data. Camera/toggle
renders retain imported geometry. Direct-color binding now accepts validated cell RGB/
RGBA, preserving flat source cells without changing point scalars. Cell color combined
with a point-opacity role is currently UNSUPPORTED; point-colored glyphs are unchanged.

### dev109: clip-independent surface picking

The existing cell picker admits a radius of 0.75 viewport pixels measured at
the scientific camera focal plane. For perspective cameras the VTK tolerance
is scaled by focal distance divided by the midpoint clipping distance; an
orthographic view uses the pixel fraction directly. This preserves the public
ABI, original geometry, camera, projection and rendered pixels. It prevents a
distant far clip from admitting intersections on triangle-plane extensions
outside the retained source mesh. VTK9.3 measures its fractional tolerance at
the clipping-ray midpoint; see the primary implementations
[VTK Picker](https://github.com/Kitware/VTK/blob/v9.3.0/Rendering/Core/vtkPicker.cxx)
and [Cell Picker](https://github.com/Kitware/VTK/blob/v9.3.0/Rendering/Core/vtkCellPicker.cxx).

The focused native contract uses the unchanged GUI-authored box/cylinder STL
artifacts, their actual camera and three far-clip distances (100, 10000,
1000000). Independent source-facet checks qualify all nine retained/new
positive receipts; three background negatives remain misses. Original frame
pixels are unchanged. The original second target was in fact an occluded box
surface: its failed cylinder expectation is retained with an explicit QA
erratum. This native contract is separate from installed GUI acceptance.

Manipulator picking uses the same focal-plane conversion with a 3-pixel
radius, retaining the existing translation-before-rotation priority only at
actual handle overlaps. The old fixed `0.006` fraction could select X on an
isolated Z arrow, or even in the background, with distant clipping planes.
An exact captured 527×633 scene/pivot native comparison reproduces that
failure and verifies X/Y/Z/background admission at automatic clipping and
far distances 100, 10000 and 1000000, with byte-identical rendered PNGs.
Installed pointer/drag acceptance remains a separate requirement.
