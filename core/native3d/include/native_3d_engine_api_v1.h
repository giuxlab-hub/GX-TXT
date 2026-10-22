/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef NATIVE_3D_ENGINE_API_V1_H
#define NATIVE_3D_ENGINE_API_V1_H
#include <stdint.h>
#include <stddef.h>
#if defined(_WIN32) && defined(GX3DE_BUILD)
#define GX3DE_API __declspec(dllexport)
#elif defined(_WIN32)
#define GX3DE_API __declspec(dllimport)
#else
#define GX3DE_API __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif

#define GX3DE_ABI_VERSION 1u
#define GX3DE_CAP_SCENE 1ull
#define GX3DE_CAP_MESH 2ull
#define GX3DE_CAP_PLANE 4ull
#define GX3DE_CAP_MEASUREMENT 8ull
#define GX3DE_CAP_HEADLESS_TARGET 16ull
#define GX3DE_CAP_HIERARCHY 32ull
#define GX3DE_CAP_MESH_DIAGNOSTICS 64ull
#define GX3DE_CAP_MESH_APPEND 128ull
#define GX3DE_CAP_MESH_SECTION 256ull
#define GX3DE_CAP_BREP 512ull
#define GX3DE_CAP_MESH_PREP 1024ull
#define GX3DE_CAP_CONSTRAINT_BASIC 2048ull
#define GX3DE_CAP_CACHE_FINGERPRINT 4096ull
#define GX3DE_CAP_EXTENDED_ANCHOR 8192ull
#define GX3DE_CAP_EXTENDED_MEASUREMENT 16384ull
#define GX3DE_CAP_MESH_CLIP 32768ull
#define GX3DE_CAP_MESH_BOUNDARY 65536ull
#define GX3DE_CAP_GROUP 131072ull
#define GX3DE_CAP_CHAINED_PROFILE 262144ull
#define GX3DE_CAP_MESH_IMPORT 524288ull
#define GX3DE_CAP_MESH_LOOPS 1048576ull
#define GX3DE_CAP_MESH_STITCH 2097152ull
#define GX3DE_CAP_MESH_ORIENT 4194304ull
#define GX3DE_CAP_BREP_CLIP 8388608ull
#define GX3DE_CAP_BREP_ANCHOR 16777216ull
#define GX3DE_CAP_MESH_SELF_INTERSECTION 33554432ull
#define GX3DE_CAP_RIGID_ALIGNMENT 67108864ull
#define GX3DE_CAP_STEP_XDE_STRUCTURE 134217728ull
#define GX3DE_CAP_PERSISTENT_MESH_CACHE 268435456ull
#define GX3DE_CAP_ASYNC_MESH_IMPORT 536870912ull
#define GX3DE_CAP_EXTENDED_CONSTRAINTS 1073741824ull
#define GX3DE_CAP_MESH_CAPPED_CLIP 2147483648ull
#define GX3DE_CAP_SCIENTIFIC_DATA 4294967296ull
#define GX3DE_CAP_SCIENTIFIC_XML_IMPORT 8589934592ull
#define GX3DE_CAP_SCIENTIFIC_ISOSURFACE 17179869184ull
#define GX3DE_CAP_SCIENTIFIC_POLYDATA_CREATE 34359738368ull
#define GX3DE_CAP_SCIENTIFIC_VECTOR_SAMPLING 68719476736ull
#define GX3DE_CAP_SCIENTIFIC_IMAGE_CREATE 137438953472ull
#define GX3DE_CAP_SCIENTIFIC_UNSTRUCTURED_CREATE 17592186044416ull
#define GX3DE_CAP_PERSISTENT_SCIENTIFIC_CACHE 562949953421312ull
#define GX3DE_CAP_MESH_LOD 274877906944ull
#define GX3DE_CAP_MESH_INTERSECTION_PAIRS 549755813888ull
#define GX3DE_CAP_VIEW_LOCAL_STATE 1099511627776ull
#define GX3DE_CAP_JOB_PROGRESS 2199023255552ull
#define GX3DE_CAP_BREP_VALIDATION 4398046511104ull
#define GX3DE_CAP_MESH_REPEATS 8796093022208ull
#define GX3DE_CAP_STEP_PROTOTYPE_MESH 35184372088832ull
#define GX3DE_CAP_MESH_PREVIEW 70368744177664ull
#define GX3DE_CAP_MESH_MEMORY_BUDGET 140737488355328ull
#define GX3DE_CAP_CONSTRAINT_SYSTEM 281474976710656ull
#define GX3DE_CAP_LINE_OBJECT_ANCHORS 1125899906842624ull
#define GX3DE_CAP_ASYNC_MESH_LOD 2251799813685248ull
#define GX3DE_CAP_BREP_FINGERPRINT 9007199254740992ull
#define GX3DE_CAP_PERSISTENT_REPEAT_CACHE 4503599627370496ull
#define GX3DE_CAP_BREP_HEAL 18014398509481984ull
#define GX3DE_CAP_ASYNC_STEP_IMPORT 144115188075855872ull
#define GX3DE_CAP_MESH_BRIDGE 36028797018963968ull
#define GX3DE_CAP_BREP_CURVE_QUERY 72057594037927936ull
#define GX3DE_CAP_PIXEL_RENDER 288230376151711744ull
#define GX3DE_CAP_RENDER_PICK 576460752303423488ull
#define GX3DE_CAP_NATIVE_WINDOW_TARGET 1152921504606846976ull
#define GX3DE_CAP_SCIENTIFIC_PRESENTATION 2305843009213693952ull
#define GX3DE_CAP_VIEW_PRESENTATION 4611686018427387904ull
#define GX3DE_CAP_BREP_MESH_CONVERSION 9223372036854775808ull
/* The first 64 capability bits are allocated. gx3de_info.reserved[0] is a
 * second capability word in ABI v1; other reserved words remain zero. */
#define GX3DE_CAP2_RENDER_MARKERS 1ull
#define GX3DE_CAP2_TRANSFORM_GIZMO 2ull
#define GX3DE_CAP2_TARGET_RESIZE 4ull
#define GX3DE_CAP2_CAMERA_NAVIGATION 8ull
#define GX3DE_CAP2_RENDER_QUALITY 16ull
#define GX3DE_CAP2_RENDERER_DIAGNOSTICS 32ull
#define GX3DE_CAP2_CAPABILITY_GROUPS 64ull
#define GX3DE_CAP2_GRAPHICS_POLICY 128ull
#define GX3DE_CAP2_PLANAR_TEXTURE 256ull
#define GX3DE_CAP2_SHADOWS 512ull
#define GX3DE_CAP2_PLANAR_GIZMO 1024ull
#define GX3DE_CAP2_PLANAR_MANIPULATION 2048ull
#define GX3DE_CAP2_NAVIGATION_CUBE 4096ull
#define GX3DE_CAP2_CHECKERBOARD_BACKGROUND 8192ull
#define GX3DE_CAP2_CURVED_TEXTURE 16384ull
#define GX3DE_CAP2_SHADOW_POLICY 32768ull
#define GX3DE_CAP2_PARTICLE_CLOUD 65536ull
#define GX3DE_CAP2_POSITIONAL_LIGHT 131072ull
#define GX3DE_CAP2_SCIENTIFIC_DIRECT_COLOR 262144ull
#define GX3DE_CAP2_SCIENTIFIC_LIGHT_SOURCES 524288ull
#define GX3DE_CAP2_INPUT_PROFILE 1048576ull
#define GX3DE_CAP2_PROFILE_EXTRUDE 2097152ull
#define GX3DE_CAP2_GEOMETRY_EXPORT 4194304ull
#define GX3DE_MAX_VIEW_CLIP_PLANES 8u
#define GX3DE_API_GROUP_CORE 1u
#define GX3DE_API_GROUP_RENDERER 2u
#define GX3DE_API_GROUP_ANIMATION 3u
#define GX3DE_API_GROUP_FIELD 4u

typedef struct gx3de_engine gx3de_engine;
typedef struct gx3de_scene gx3de_scene;
typedef struct gx3de_object gx3de_object;
typedef struct gx3de_particle_cloud gx3de_particle_cloud;
typedef struct gx3de_scientific_light gx3de_scientific_light;
typedef struct gx3de_group gx3de_group;
typedef struct gx3de_plane gx3de_plane;
typedef struct gx3de_anchor gx3de_anchor;
typedef struct gx3de_measurement gx3de_measurement;
typedef struct gx3de_section gx3de_section;
typedef struct gx3de_profile gx3de_profile;
typedef struct gx3de_marker gx3de_marker;
typedef struct gx3de_mesh_loops gx3de_mesh_loops;
typedef struct gx3de_repeat_result gx3de_repeat_result;
typedef struct gx3de_constraint gx3de_constraint;
typedef struct gx3de_target gx3de_target;
typedef struct gx3de_view gx3de_view;
typedef struct gx3de_viewport gx3de_viewport;
typedef struct gx3de_gizmo gx3de_gizmo;
typedef struct gx3de_view_manipulation gx3de_view_manipulation;
typedef struct gx3de_job gx3de_job;
typedef struct gx3de_step_document gx3de_step_document;
typedef enum gx3de_result {
    GX3DE_OK=0, GX3DE_INVALID_ARGUMENT=1, GX3DE_OUT_OF_MEMORY=2,
    GX3DE_NOT_FOUND=3, GX3DE_UNSUPPORTED=4, GX3DE_RANGE=5,
    GX3DE_WRONG_OWNER=6, GX3DE_DEGENERATE=7
} gx3de_result;
typedef struct gx3de_info {
    uint32_t struct_size;
    uint32_t abi_version;
    uint64_t capabilities;
    uint64_t reserved[4];
} gx3de_info;
/* Four capability words per named API group; ABI v1's gx3de_info remains
 * unchanged. An unsupported group reports api_version=0 and zero words. */
typedef struct gx3de_capability_set {
    uint32_t struct_size,api_group,api_version,word_count;
    uint64_t words[4];
    uint64_t reserved[4];
} gx3de_capability_set;
typedef enum gx3de_render_backend {
    GX3DE_RENDER_BACKEND_AUTO=0,GX3DE_RENDER_BACKEND_UNKNOWN=0,
    GX3DE_RENDER_BACKEND_OPENGL=1,
    GX3DE_RENDER_BACKEND_D3D11=2
} gx3de_render_backend;
typedef enum gx3de_render_execution {
    GX3DE_RENDER_EXECUTION_UNKNOWN=0,GX3DE_RENDER_EXECUTION_HARDWARE=1,
    GX3DE_RENDER_EXECUTION_SOFTWARE=2
} gx3de_render_execution;
typedef struct gx3de_renderer_device_info {
    uint32_t struct_size,backend,execution,context_lost;
    char adapter[128],driver[128],fallback_reason[256],last_error[256];
    uint64_t features[4];
} gx3de_renderer_device_info;
typedef struct gx3de_vec3 { double x,y,z; } gx3de_vec3;
typedef struct gx3de_mesh_intersection_pair {
    uint32_t struct_size;
    uint32_t reserved32;
    uint64_t triangle_a, triangle_b; /* source triangle indices, a < b */
    gx3de_vec3 world_witness; /* contact or midpoint of a near contact */
    uint64_t reserved[2];
} gx3de_mesh_intersection_pair;
typedef struct gx3de_mat4 { double m[16]; } gx3de_mat4; /* column major, affine */
typedef struct gx3de_bounds { gx3de_vec3 min,max; } gx3de_bounds;
typedef struct gx3de_mesh_diagnostics {
    uint32_t struct_size;
    uint32_t closed_manifold;
    uint64_t boundary_edges, nonmanifold_edges, orientation_conflicts, disconnected_components;
    double surface_area, enclosed_volume;
    uint32_t volume_defined;
    uint32_t reserved32;
    uint64_t reserved[4];
} gx3de_mesh_diagnostics;
typedef struct gx3de_repeat_info {
    uint32_t struct_size;
    uint32_t reserved32;
    uint64_t source_triangle,triangles_per_component,match_count,remainder_triangles;
    double tolerance;
    char fingerprint_sha256[65];
    uint64_t reserved[4];
} gx3de_repeat_info;
typedef struct gx3de_brep_diagnostics {
    uint32_t struct_size;
    uint32_t volume_defined;
    double surface_area,enclosed_volume;
    uint64_t reserved[4];
} gx3de_brep_diagnostics;
typedef struct gx3de_brep_topology {
    uint32_t struct_size;
    uint32_t reserved32;
    uint64_t vertices,edges,faces;
    uint64_t reserved[4];
} gx3de_brep_topology;
typedef struct gx3de_brep_validation {
    uint32_t struct_size;
    uint32_t topology_valid; /* OCCT BRepCheck_Analyzer on immutable source shape */
    uint32_t closed_oriented_solids; /* no stray faces/open or unoriented shells */
    uint32_t reserved32;
    uint64_t solids, shells, faces;
    uint64_t reserved[4];
} gx3de_brep_validation;
typedef enum gx3de_brep_curve_type {
    GX3DE_BREP_CURVE_UNKNOWN=0,GX3DE_BREP_CURVE_LINE=1,
    GX3DE_BREP_CURVE_CIRCLE=2,GX3DE_BREP_CURVE_ELLIPSE=3,
    GX3DE_BREP_CURVE_HYPERBOLA=4,GX3DE_BREP_CURVE_PARABOLA=5,
    GX3DE_BREP_CURVE_BEZIER=6,GX3DE_BREP_CURVE_BSPLINE=7,
    GX3DE_BREP_CURVE_OFFSET=8,GX3DE_BREP_CURVE_OTHER=255
} gx3de_brep_curve_type;
typedef enum gx3de_brep_surface_type {
    GX3DE_BREP_SURFACE_UNKNOWN=0,GX3DE_BREP_SURFACE_PLANE=1,
    GX3DE_BREP_SURFACE_CYLINDER=2,GX3DE_BREP_SURFACE_CONE=3,
    GX3DE_BREP_SURFACE_SPHERE=4,GX3DE_BREP_SURFACE_TORUS=5,
    GX3DE_BREP_SURFACE_BEZIER=6,GX3DE_BREP_SURFACE_BSPLINE=7,
    GX3DE_BREP_SURFACE_REVOLUTION=8,GX3DE_BREP_SURFACE_EXTRUSION=9,
    GX3DE_BREP_SURFACE_OFFSET=10,GX3DE_BREP_SURFACE_OTHER=255
} gx3de_brep_surface_type;
typedef struct gx3de_brep_edge_geometry {
    uint32_t struct_size;
    uint32_t curve_type; /* gx3de_brep_curve_type */
    uint32_t closed;
    uint32_t reserved32;
    double first_parameter,last_parameter,length;
    gx3de_vec3 start,end,start_tangent,end_tangent; /* source-local */
    uint64_t reserved[4];
} gx3de_brep_edge_geometry;
typedef struct gx3de_brep_face_geometry {
    uint32_t struct_size;
    uint32_t surface_type; /* gx3de_brep_surface_type */
    uint32_t u_closed,v_closed;
    double u_min,u_max,v_min,v_max; /* source-local OCCT UV coordinates */
    uint64_t reserved[4];
} gx3de_brep_face_geometry;
typedef struct gx3de_segment3 { gx3de_vec3 a,b; } gx3de_segment3;
typedef struct gx3de_segment2 { double au,av,bu,bv; } gx3de_segment2;
typedef struct gx3de_contour_info {
    uint32_t struct_size;
    uint32_t closed;
    uint64_t point_count;
    double length,planar_area; /* area is zero for an open contour */
    uint64_t reserved[4];
} gx3de_contour_info;
typedef struct gx3de_point2 { double u,v; } gx3de_point2;
typedef struct gx3de_profile_contour_spec {
    uint32_t struct_size,closed;
    const gx3de_point2 *points;
    uint64_t point_count;
    uint64_t reserved[4];
} gx3de_profile_contour_spec;
typedef struct gx3de_cache_stats {
    uint32_t struct_size;
    uint32_t reserved32;
    uint64_t entries,hits,misses;
    uint64_t reserved[4];
} gx3de_cache_stats;
typedef struct gx3de_disk_cache_stats {
    uint32_t struct_size;
    uint32_t enabled;
    uint64_t hits,misses,invalid_rebuilt,store_failures;
    uint64_t reserved[4];
} gx3de_disk_cache_stats;
typedef enum gx3de_job_state { GX3DE_JOB_READY=1,GX3DE_JOB_RUNNING=2,GX3DE_JOB_COMPLETED=3,GX3DE_JOB_CANCELED=4,GX3DE_JOB_FAILED=5 } gx3de_job_state;
typedef struct gx3de_job_event {
    uint32_t struct_size;
    uint32_t state;
    uint64_t sequence;
    uint64_t progress_permille; /* valid when GX3DE_CAP_JOB_PROGRESS is set */
    uint64_t reserved[3];
} gx3de_job_event;
typedef enum gx3de_mesh_import_format { GX3DE_IMPORT_OBJ=1,GX3DE_IMPORT_STL=2 } gx3de_mesh_import_format;
typedef enum gx3de_mesh_lod_level {
    GX3DE_LOD_PREVIEW=1, GX3DE_LOD_LOW=2, GX3DE_LOD_MEDIUM=3,
    GX3DE_LOD_HIGH=4, GX3DE_LOD_FULL=5
} gx3de_mesh_lod_level;
typedef struct gx3de_mesh_import_spec {
    uint32_t struct_size;
    uint32_t format;
    const char *path_utf8;
    uint64_t max_source_bytes; /* 0 selects the documented 256 MiB limit */
    uint64_t max_memory_bytes; /* 0: 4096 MiB; explicit: 32..1048576 MiB */
    uint64_t reserved[3];
} gx3de_mesh_import_spec;
typedef enum gx3de_scientific_kind {
    GX3DE_SCIENTIFIC_VTP=1, GX3DE_SCIENTIFIC_VTU=2,
    GX3DE_SCIENTIFIC_VTI=3, GX3DE_SCIENTIFIC_ISOSURFACE=4,
    GX3DE_SCIENTIFIC_POLYDATA_MEMORY=5,
    GX3DE_SCIENTIFIC_IMAGE_MEMORY=6,
    GX3DE_SCIENTIFIC_UNSTRUCTURED_MEMORY=7
} gx3de_scientific_kind;
typedef enum gx3de_scientific_association {
    GX3DE_SCI_ASSOC_POINT=1, GX3DE_SCI_ASSOC_CELL=2
} gx3de_scientific_association;
typedef enum gx3de_scientific_array_class {
    GX3DE_SCI_ARRAY_SCALAR=1, GX3DE_SCI_ARRAY_VECTOR3=2,
    GX3DE_SCI_ARRAY_OTHER=3
} gx3de_scientific_array_class;
typedef enum gx3de_scientific_cell_type {
    GX3DE_SCI_CELL_VERTEX=1, GX3DE_SCI_CELL_LINE=2,
    GX3DE_SCI_CELL_POLYLINE=3, GX3DE_SCI_CELL_TRIANGLE=4,
    GX3DE_SCI_CELL_POLYGON=5, GX3DE_SCI_CELL_TETRA=6,
    GX3DE_SCI_CELL_HEXAHEDRON=7,
    GX3DE_SCI_CELL_OTHER=255
} gx3de_scientific_cell_type;
typedef struct gx3de_scientific_import_spec {
    uint32_t struct_size;
    uint32_t format; /* VTP, VTU or VTI */
    const char *path_utf8;
    uint64_t max_source_bytes; /* 0 selects 256 MiB */
    uint64_t reserved[4];
} gx3de_scientific_import_spec;
typedef struct gx3de_scientific_cell_input {
    uint32_t struct_size;
    uint32_t type; /* VERTEX, LINE, POLYLINE, TRIANGLE, POLYGON */
    const uint64_t *point_ids;
    uint64_t point_count;
    uint64_t reserved[2];
} gx3de_scientific_cell_input;
typedef struct gx3de_scientific_array_input {
    uint32_t struct_size;
    uint32_t association; /* POINT or CELL */
    uint32_t components; /* 1..16 */
    uint32_t reserved32;
    const char *name_utf8;
    const double *values; /* tuple_count * components, row major */
    uint64_t tuple_count;
    uint64_t reserved[2];
} gx3de_scientific_array_input;
typedef struct gx3de_scientific_polydata_spec {
    uint32_t struct_size;
    uint32_t reserved32;
    const gx3de_vec3 *points;
    uint64_t point_count;
    const gx3de_scientific_cell_input *cells;
    uint64_t cell_count;
    const gx3de_scientific_array_input *arrays;
    uint64_t array_count;
    uint64_t reserved[4];
} gx3de_scientific_polydata_spec;
typedef struct gx3de_scientific_image_spec {
    uint32_t struct_size;
    uint32_t reserved32;
    int32_t extent[6]; /* inclusive point extent */
    gx3de_vec3 origin,spacing;
    double direction[9]; /* row-major, invertible */
    const gx3de_scientific_array_input *arrays;
    uint64_t array_count;
    uint64_t max_data_bytes; /* zero selects 256 MiB input budget */
    uint64_t reserved[3];
} gx3de_scientific_image_spec;
typedef struct gx3de_scientific_unstructured_spec {
    uint32_t struct_size;
    uint32_t reserved32;
    const gx3de_vec3 *points;
    uint64_t point_count;
    const gx3de_scientific_cell_input *cells;
    uint64_t cell_count;
    const gx3de_scientific_array_input *arrays;
    uint64_t array_count;
    uint64_t max_data_bytes; /* zero selects 256 MiB input budget */
    uint64_t reserved[3];
} gx3de_scientific_unstructured_spec;
typedef struct gx3de_scientific_info {
    uint32_t struct_size;
    uint32_t kind; /* gx3de_scientific_kind */
    uint64_t point_count,cell_count,array_count;
    uint32_t grid_dimensions[3]; /* nonzero for imported VTI and in-memory image */
    uint32_t derived;
    double isovalue; /* valid when derived */
    char selected_scalar_utf8[256]; /* empty unless derived */
    uint64_t reserved[4];
} gx3de_scientific_info;
typedef struct gx3de_scientific_grid_info {
    uint32_t struct_size;
    uint32_t reserved32;
    int32_t extent[6]; /* inclusive I/J/K point extent */
    gx3de_vec3 origin,spacing;
    double direction[9]; /* row major 3x3 */
    uint64_t reserved[4];
} gx3de_scientific_grid_info;
typedef struct gx3de_scientific_array_info {
    uint32_t struct_size;
    uint32_t association;
    uint32_t components;
    uint32_t classification; /* based on component count */
    uint64_t tuple_count;
    char name_utf8[256]; /* empty if source array is unnamed; index is identity */
    uint64_t reserved[4];
} gx3de_scientific_array_info;
typedef struct gx3de_scientific_cell_info {
    uint32_t struct_size;
    uint32_t type; /* gx3de_scientific_cell_type */
    uint64_t point_count;
    uint64_t reserved[4];
} gx3de_scientific_cell_info;
typedef struct gx3de_scientific_field_roles {
    uint32_t struct_size;
    uint32_t reserved32;
    int64_t scalar_array,vector_array,radius_array; /* -1 means unbound */
    double tube_radius; /* zero disables future tube presentation */
    uint64_t reserved[4];
} gx3de_scientific_field_roles;
typedef struct gx3de_scientific_vector_sample {
    uint32_t struct_size;
    uint32_t reserved32;
    uint64_t point_id;
    gx3de_vec3 position,vector;
    uint64_t reserved[2];
} gx3de_scientific_vector_sample;
typedef struct gx3de_step_import_spec {
    uint32_t struct_size;
    uint32_t reserved32;
    const char *path_utf8;
    uint64_t max_source_bytes; /* 0 selects 256 MiB */
    uint64_t max_nodes; /* 0 selects 100000 */
    uint64_t reserved[4];
} gx3de_step_import_spec;
typedef struct gx3de_step_mesh_spec {
    uint32_t struct_size;
    uint32_t reserved32;
    double linear_deflection,angular_deflection,weld_tolerance;
    uint64_t max_triangles,max_output_bytes;
    uint64_t reserved[4];
} gx3de_step_mesh_spec;
/* Identical quality and budget contract for any B-Rep object, including a
 * programmatically created solid and a STEP occurrence. */
typedef gx3de_step_mesh_spec gx3de_brep_mesh_spec;
typedef struct gx3de_geometry_comparison_spec {
    uint32_t struct_size,sample_budget; /*6..4096 vertices per direction */
    gx3de_brep_mesh_spec tessellation;
    uint64_t reserved[4];
} gx3de_geometry_comparison_spec;
typedef struct gx3de_geometry_deviation {
    uint64_t source_vertex;
    uint32_t direction,reserved32; /*0 reference->target;1 target->reference */
    gx3de_vec3 source,projected;
    double distance;
} gx3de_geometry_deviation;
typedef struct gx3de_geometry_comparison {
    uint32_t struct_size,volume_defined,reference_tessellated,target_tessellated;
    uint64_t reference_vertices,target_vertices,reference_samples,target_samples;
    double reference_rms,reference_mean,reference_max,symmetric_rms,hausdorff_sampled;
    double closest_sampled,area_difference,volume_difference;
    gx3de_vec3 closest_source,closest_target,bounds_min_difference,bounds_max_difference;
    uint64_t reserved[4];
} gx3de_geometry_comparison;
/* Full target triangles; bounded deterministic vertex queries. Hausdorff and
 * closest distances are sampled bounds, not continuous-surface extrema. Output
 * remains unchanged on failure; row capacity must be2*sample_budget. */
GX3DE_API gx3de_result gx3de_compare_geometry(gx3de_object *reference,gx3de_object *target,
    const gx3de_geometry_comparison_spec *spec,gx3de_geometry_comparison *summary,
    gx3de_geometry_deviation *rows,uint64_t capacity,uint64_t *row_count);
typedef struct gx3de_step_summary {
    uint32_t struct_size;
    uint32_t reserved32;
    uint64_t roots,nodes,assemblies,references,part_occurrences,unique_parts;
    uint64_t reserved[4];
} gx3de_step_summary;
typedef enum gx3de_step_node_kind {
    GX3DE_STEP_ASSEMBLY=1,
    GX3DE_STEP_PART_OCCURRENCE=2
} gx3de_step_node_kind;
typedef struct gx3de_step_node {
    uint32_t struct_size;
    uint32_t kind; /* gx3de_step_node_kind */
    uint64_t parent_index,prototype_index; /* UINT64_MAX when absent */
    uint32_t is_reference;
    uint32_t reserved32;
    gx3de_mat4 local_transform,world_transform;
    uint64_t reserved[4];
} gx3de_step_node;
typedef enum gx3de_step_text_field { GX3DE_STEP_NODE_ID=1,GX3DE_STEP_NODE_NAME=2,GX3DE_STEP_DEFINITION_ID=3,GX3DE_STEP_PROTOTYPE_ID=4,GX3DE_STEP_PROTOTYPE_NAME=5 } gx3de_step_text_field;
typedef struct gx3de_camera {
    uint32_t struct_size;
    uint32_t orthographic;
    gx3de_vec3 position,target,up;
    double near_clip,far_clip,vertical_fov_degrees;
    uint64_t reserved[4];
} gx3de_camera;
typedef struct gx3de_target_geometry {
    uint32_t struct_size,physical_width,physical_height,logical_width,logical_height;
    double device_pixel_ratio_x,device_pixel_ratio_y;
    uint64_t reserved[4];
} gx3de_target_geometry;
typedef enum gx3de_transparency_mode {
    GX3DE_TRANSPARENCY_DEPTH_PEEL=1,GX3DE_TRANSPARENCY_ALPHA_FALLBACK=2
} gx3de_transparency_mode;
typedef struct gx3de_render_quality {
    uint32_t struct_size,msaa_samples,transparency_mode,reserved32;
    uint64_t reserved[4];
} gx3de_render_quality;
typedef enum gx3de_graphics_execution {
    GX3DE_GRAPHICS_AUTO=0,GX3DE_GRAPHICS_HARDWARE=1,GX3DE_GRAPHICS_SOFTWARE=2
} gx3de_graphics_execution;
typedef enum gx3de_shadow_policy {
    GX3DE_SHADOW_OFF=0, GX3DE_SHADOW_OPAQUE_ONLY=1, GX3DE_SHADOW_FULL=2
} gx3de_shadow_policy;
/* Engine-owned default for all present and future targets. Geometry LOD is a
 * display choice; source objects and Session state remain unchanged. Worker
 * limits are returned for framework process supervision, not enforced by the
 * in-process renderer. gpu_budget_bytes=0 means unlimited. */
typedef struct gx3de_graphics_policy {
    uint32_t struct_size,execution,normal_lod,interaction_lod_enabled;
    uint32_t interaction_lod,interaction_active,export_supersampling,shadow_policy;
    uint64_t display_triangle_budget,gpu_budget_bytes;
    uint64_t worker_rss_budget_bytes,worker_address_space_budget_bytes;
    gx3de_render_quality quality;
    uint64_t reserved[4];
} gx3de_graphics_policy;
typedef struct gx3de_render_stats {
    uint32_t struct_size,reserved32;
    uint64_t completed_frames,geometry_rebuild_frames,geometry_reuse_frames;
    uint64_t reserved[4];
} gx3de_render_stats;
typedef enum gx3de_resource_accounting {
    GX3DE_RESOURCE_UNAVAILABLE=0,GX3DE_RESOURCE_ESTIMATED=1,
    GX3DE_RESOURCE_MEASURED=2
} gx3de_resource_accounting;
typedef struct gx3de_render_resource_info {
    uint32_t struct_size;
    uint32_t gpu_accounting; /* ESTIMATED on OpenGL; no exact GPU allocation query */
    uint32_t measured_accounting; /* UNAVAILABLE when driver allocation is unknown */
    uint32_t budget_enforced;
    uint64_t gpu_budget_bytes; /* zero disables this explicit limit */
    uint64_t gpu_estimated_bytes; /* conservative preflight, last attempt */
    uint64_t gpu_measured_bytes; /* zero unless a backend reports measurement */
    uint64_t last_rejected_estimate_bytes;
    uint64_t reserved[4];
} gx3de_render_resource_info;
typedef struct gx3de_view_clip_plane {
    uint32_t struct_size;
    uint32_t enabled;
    gx3de_vec3 origin,normal; /* world coordinates; normal is normalized on set */
    uint32_t keep_positive;
    uint32_t reserved32;
    uint64_t reserved[4];
} gx3de_view_clip_plane;
typedef enum gx3de_interaction_mode {
    GX3DE_INTERACTION_NONE=0,
    GX3DE_INTERACTION_POINT=1,
    GX3DE_INTERACTION_DRAG=2
} gx3de_interaction_mode;
typedef struct gx3de_view_interaction {
    uint32_t struct_size;
    uint32_t mode; /* gx3de_interaction_mode */
    gx3de_vec3 start_world,current_world;
    uint64_t pointer_id;
    uint64_t reserved[4];
} gx3de_view_interaction;
typedef enum gx3de_gizmo_handle {
    GX3DE_GIZMO_TRANSLATE_X=1,GX3DE_GIZMO_TRANSLATE_Y=2,GX3DE_GIZMO_TRANSLATE_Z=3,
    GX3DE_GIZMO_TRANSLATE_XY=4,GX3DE_GIZMO_TRANSLATE_YZ=5,GX3DE_GIZMO_TRANSLATE_ZX=6,
    GX3DE_GIZMO_TRANSLATE_FREE=7,
    GX3DE_GIZMO_ROTATE_X=8,GX3DE_GIZMO_ROTATE_Y=9,GX3DE_GIZMO_ROTATE_Z=10
} gx3de_gizmo_handle;
#define GX3DE_GIZMO_FAMILY_AXIS 1u
#define GX3DE_GIZMO_FAMILY_PLANE 2u
#define GX3DE_GIZMO_FAMILY_FREE 4u
#define GX3DE_GIZMO_FAMILY_ROTATE 8u
#define GX3DE_GIZMO_SPACE_WORLD 1u
#define GX3DE_GIZMO_SPACE_LOCAL 2u
#define GX3DE_GIZMO_PIVOT_OBJECT 1u
#define GX3DE_GIZMO_PIVOT_EXPLICIT 2u
#define GX3DE_GIZMO_PIVOT_ANCHOR 3u
typedef struct gx3de_ray {uint32_t struct_size;uint32_t reserved32;gx3de_vec3 origin,direction;uint64_t reserved[4];} gx3de_ray;
typedef struct gx3de_gizmo_spec {
    uint32_t struct_size,visible,space,families,preview_only,pivot_mode;
    gx3de_object *object;gx3de_anchor *anchor;
    gx3de_vec3 world_pivot;double size_pixels;
    uint64_t reserved[4];
} gx3de_gizmo_spec;
typedef struct gx3de_gizmo_result {
    uint32_t struct_size,active_handle,constraint_status,reserved32;
    gx3de_vec3 translation_world;double angle_radians;
    gx3de_mat4 proposed_local_transform;
    uint64_t reserved[4];
} gx3de_gizmo_result;
typedef struct gx3de_view_axes {
    uint32_t struct_size,show_world,show_local,show_reference;
    gx3de_object *local_object;gx3de_anchor *reference_axis;
    double size_pixels;uint64_t reserved[4];
} gx3de_view_axes;
typedef struct gx3de_rgb {double r,g,b;} gx3de_rgb;
typedef struct gx3de_view_background {
    uint32_t struct_size;
    uint32_t gradient;
    gx3de_rgb top,bottom; /* solid uses top */
    uint64_t reserved[4];
} gx3de_view_background;
typedef struct gx3de_checkerboard_background {
    uint32_t struct_size,enabled,checker_pixels,reserved32;
    gx3de_rgb first,second;
    uint64_t reserved[4];
} gx3de_checkerboard_background;
typedef enum gx3de_navcube_corner {
    GX3DE_NAVCUBE_TOP_LEFT=0,GX3DE_NAVCUBE_TOP_RIGHT=1,
    GX3DE_NAVCUBE_BOTTOM_LEFT=2,GX3DE_NAVCUBE_BOTTOM_RIGHT=3
} gx3de_navcube_corner;
/* Region encodes x,y,z in base three: -1 -> 0, 0 -> 1, +1 -> 2.
 * Region zero means no hit; the all-zero-axis center code (14) is unused.
 * Front is negative Y, top is positive Z. Every other nonzero combination
 * denotes one of the twelve edges or eight corners. */
#define GX3DE_NAVCUBE_REGION(x,y,z) (1u+9u*((x)+1u)+3u*((y)+1u)+((z)+1u))
#define GX3DE_NAVCUBE_FRONT 11u
#define GX3DE_NAVCUBE_BACK 17u
#define GX3DE_NAVCUBE_LEFT 5u
#define GX3DE_NAVCUBE_RIGHT 23u
#define GX3DE_NAVCUBE_TOP 15u
#define GX3DE_NAVCUBE_BOTTOM 13u
typedef struct gx3de_navcube_state {
    uint32_t struct_size,visible,corner,size_pixels;
    uint32_t margin_pixels,hover_region,active_region,synced_region;
    uint64_t reserved[4];
} gx3de_navcube_state;
/* Screen-space camera orientation; never a world-origin or interaction pivot.
 * Corner uses gx3de_navcube_corner. No scientific geometry/units are changed. */
typedef struct gx3de_orientation_indicator {
    uint32_t struct_size,visible,corner,size_pixels,margin_pixels,reserved32;
    uint64_t reserved[4];
} gx3de_orientation_indicator;
typedef enum gx3de_camera_preset {
    GX3DE_CAMERA_FRONT=1,GX3DE_CAMERA_BACK=2,
    GX3DE_CAMERA_LEFT=3,GX3DE_CAMERA_RIGHT=4,
    GX3DE_CAMERA_TOP=5,GX3DE_CAMERA_BOTTOM=6,
    GX3DE_CAMERA_ISOMETRIC=7,GX3DE_CAMERA_FIT_SCENE=8,
    GX3DE_CAMERA_FIT_OBJECT=9,GX3DE_CAMERA_FIT_SELECTION=10
} gx3de_camera_preset;
typedef struct gx3de_directional_light {
    gx3de_vec3 direction; /* world vector from light toward the scene */
    gx3de_rgb color;
    double intensity;
} gx3de_directional_light;
typedef struct gx3de_view_lighting {
    uint32_t struct_size;
    uint32_t enabled;
    double ambient,diffuse,specular; /* nonnegative, at most 1 */
    uint32_t light_count; /* 0..4; disabled lighting uses ambient only */
    uint32_t reserved32;
    gx3de_directional_light lights[4];
    uint64_t reserved[4];
} gx3de_view_lighting;
/* A positional light replaces one directional slot while enabled. The slot
 * must be below view_lighting.light_count. Constant/linear/quadratic terms
 * use world-distance units; at least one term must be positive. */
typedef struct gx3de_positional_light {
    uint32_t struct_size,enabled;
    gx3de_vec3 position;
    gx3de_rgb color;
    double intensity;
    double attenuation_constant,attenuation_linear,attenuation_quadratic;
    uint64_t reserved[4];
} gx3de_positional_light;
/* Scene-owned spectral spotlight, separate from view presentation lights.
 * direction is normalized on set. cone_angle_degrees is the VTK spotlight
 * half-angle, 1..85; beam_range bounds the scientific centerline query and
 * evidence beam, while VTK lighting uses the attenuation terms. Wavelength
 * is canonical in vacuum nanometres. Visible-display RGB is derived only. */
typedef struct gx3de_scientific_light_spec {
    uint32_t struct_size,enabled,shadows_enabled,beam_visible;
    gx3de_vec3 position,direction;
    double wavelength_nm,intensity,cone_angle_degrees,beam_range;
    double attenuation_constant,attenuation_linear,attenuation_quadratic;
    double falloff_exponent,beam_radius;
    uint64_t reserved[4];
} gx3de_scientific_light_spec;
/* Centerline sample only: optical_factor is the product of completed closed
 * mesh traversals with explicitly bound scientific transmittance. It is
 * independent of object visual opacity and renderer shadow maps. */
typedef struct gx3de_scientific_beam_sample {
    uint32_t struct_size,completed_traversals;
    gx3de_vec3 position;
    double distance,geometric_factor,optical_factor,intensity;
    uint64_t reserved[4];
} gx3de_scientific_beam_sample;
/* Omitted particle color/radius use the cloud style. Particle positions are
 * object-local. This data is copied on submission. */
#define GX3DE_PARTICLE_RADIUS 1u
#define GX3DE_PARTICLE_COLOR 2u
typedef struct gx3de_particle {
    gx3de_vec3 position;
    double radius;
    gx3de_rgb color;
    uint32_t flags,reserved32;
} gx3de_particle;
typedef struct gx3de_particle_cloud_style {
    uint32_t struct_size;
    double radius;
    gx3de_rgb color;
    double opacity;
    uint64_t reserved[4];
} gx3de_particle_cloud_style;
typedef enum gx3de_lighting_preset {
    GX3DE_LIGHT_SCIENTIFIC_NEUTRAL=1,
    GX3DE_LIGHT_HIGH_CONTRAST=2,
    GX3DE_LIGHT_SOFT_DIFFUSE=3,
    GX3DE_LIGHT_FLAT_UNLIT=4
} gx3de_lighting_preset;
/* A preset is copied into the ordinary editable lighting state. */
GX3DE_API gx3de_result gx3de_view_lighting_preset(gx3de_view *view,uint32_t preset);
typedef enum gx3de_image_transfer {
    GX3DE_IMAGE_TRANSFER_SRGB=1
} gx3de_image_transfer;
typedef enum gx3de_alpha_convention {
    GX3DE_ALPHA_STRAIGHT=1
} gx3de_alpha_convention;
typedef enum gx3de_png_color_tag {
    GX3DE_PNG_COLOR_UNTAGGED=1 /* RGB byte values expect sRGB transfer */
} gx3de_png_color_tag;
typedef struct gx3de_image_output_info {
    uint32_t struct_size;
    uint32_t component_count; /* 4 */
    uint32_t bits_per_component; /* 8 */
    uint32_t alpha_convention; /* gx3de_alpha_convention */
    uint32_t transfer; /* gx3de_image_transfer */
    uint32_t png_transfer; /* same transfer expectation as RGBA readback */
    uint32_t png_color_tag; /* gx3de_png_color_tag */
    char component_order[8]; /* "RGBA" */
    uint64_t reserved[4];
} gx3de_image_output_info;
GX3DE_API gx3de_result gx3de_image_output_info_get(gx3de_image_output_info *out);
typedef struct gx3de_view_clip_box {
    uint32_t struct_size;
    uint32_t enabled;
    gx3de_bounds world_bounds;
    uint64_t reserved[4];
} gx3de_view_clip_box;
typedef enum gx3de_view_manipulation_target {
    GX3DE_MANIP_WORKING_PLANE=1,GX3DE_MANIP_CLIP_PLANE=2,GX3DE_MANIP_CLIP_BOX=3
} gx3de_view_manipulation_target;
typedef enum gx3de_view_manipulation_action {
    GX3DE_MANIP_TRANSLATE=1,GX3DE_MANIP_ROTATE=2
} gx3de_view_manipulation_action;
typedef enum gx3de_view_manipulation_handle {
    GX3DE_MANIP_FREE=0,GX3DE_MANIP_X=1,GX3DE_MANIP_Y=2,GX3DE_MANIP_Z=3,
    GX3DE_MANIP_BOX_MIN_X=4,GX3DE_MANIP_BOX_MIN_Y=5,GX3DE_MANIP_BOX_MIN_Z=6,
    GX3DE_MANIP_BOX_MAX_X=7,GX3DE_MANIP_BOX_MAX_Y=8,GX3DE_MANIP_BOX_MAX_Z=9
} gx3de_view_manipulation_handle;
typedef struct gx3de_view_manipulation_result {
    uint32_t struct_size,target,action,handle;
    gx3de_vec3 origin,normal,u_axis;
    gx3de_view_clip_box box;
    uint64_t reserved[4];
} gx3de_view_manipulation_result;
typedef enum gx3de_display_mode {
    GX3DE_DISPLAY_SURFACE=1,GX3DE_DISPLAY_WIREFRAME=2,
    GX3DE_DISPLAY_SURFACE_EDGES=3,GX3DE_DISPLAY_POINTS=4
} gx3de_display_mode;
typedef struct gx3de_object_style {
    uint32_t struct_size;
    uint32_t mode;
    gx3de_rgb color;
    double line_width,point_size;
    uint32_t backface_culling,scalar_coloring;
    uint64_t reserved[4];
} gx3de_object_style;
typedef struct gx3de_texture gx3de_texture;
typedef struct gx3de_planar_texture gx3de_planar_texture;
typedef struct gx3de_curved_texture gx3de_curved_texture;
typedef struct gx3de_texture_info {
    uint32_t struct_size,width,height,channels;
    uint64_t reserved[4];
} gx3de_texture_info;
/* Source triangle IDs refer to the immutable mesh, not a transient display
 * LOD or rendered pick cell. local_anchor is a point on the selected connected
 * coplanar region, in object-local coordinates. Image V=0 is the lower edge.
 * Width and height are positive object-local lengths. Rotation is radians
 * about the outward source-face normal. */
typedef struct gx3de_planar_texture_spec {
    uint32_t struct_size;
    uint64_t source_triangle;
    gx3de_vec3 local_anchor;
    double anchor_u,anchor_v,width,height,rotation_radians;
    uint32_t flip_u,flip_v;
    uint64_t reserved[4];
} gx3de_planar_texture_spec;
/* Source triangle and anchor are object-local. Propagation is edge-connected,
 * bounded by unfolded distance, per-edge normal change, and normal change
 * from the seed face. Image V=0 is the lower edge. Positive limits are required.
 * The chart may have a seam around closed or high-curvature topology. */
typedef struct gx3de_curved_texture_spec {
    uint32_t struct_size;
    uint64_t source_triangle;
    gx3de_vec3 local_anchor;
    double anchor_u,anchor_v,width,height,rotation_radians;
    double max_distance,max_edge_angle_radians,max_seed_angle_radians;
    uint32_t flip_u,flip_v;
    uint64_t reserved[4];
} gx3de_curved_texture_spec;
typedef enum gx3de_curved_wrap_flags {
    GX3DE_CURVED_WRAP_SEAM=1u,
    GX3DE_CURVED_WRAP_DISTANCE_LIMIT=2u,
    GX3DE_CURVED_WRAP_ANGLE_LIMIT=4u,
    GX3DE_CURVED_WRAP_CHART_LIMIT=8u,
    GX3DE_CURVED_WRAP_OPEN_BOUNDARY=16u,
    GX3DE_CURVED_WRAP_NONMANIFOLD=32u
} gx3de_curved_wrap_flags;
/* Diagnostic counts and limits belong to this assignment, in object-local
 * topology. A seam is an edge whose two transported UV charts disagree. */
typedef struct gx3de_curved_texture_status {
    uint32_t struct_size;
    uint32_t flags;
    uint64_t chart_triangles,rendered_triangles,seam_edges;
    uint64_t distance_stops,angle_stops,chart_stops,open_edges,nonmanifold_edges;
    uint64_t reserved[4];
} gx3de_curved_texture_status;
typedef enum gx3de_planar_resize_mode {
    GX3DE_PLANAR_RESIZE_PROPORTIONAL=1,
    GX3DE_PLANAR_RESIZE_STRETCH=2
} gx3de_planar_resize_mode;
typedef enum gx3de_planar_gizmo_handle {
    GX3DE_PLANAR_HANDLE_ANCHOR=1,
    GX3DE_PLANAR_HANDLE_CORNER_00=2,GX3DE_PLANAR_HANDLE_CORNER_10=3,
    GX3DE_PLANAR_HANDLE_CORNER_11=4,GX3DE_PLANAR_HANDLE_CORNER_01=5,
    GX3DE_PLANAR_HANDLE_WIDTH=6,GX3DE_PLANAR_HANDLE_HEIGHT=7,
    GX3DE_PLANAR_HANDLE_ROTATION=8
} gx3de_planar_gizmo_handle;
typedef enum gx3de_marker_kind {
    GX3DE_MARKER_POINT=1,GX3DE_MARKER_CROSS=2,
    GX3DE_MARKER_NORMAL=3,GX3DE_MARKER_TANGENT=4
} gx3de_marker_kind;
typedef struct gx3de_marker_style {
    uint32_t struct_size;
    uint32_t visible;
    uint32_t kind;
    uint32_t highlighted;
    gx3de_rgb color;
    double size_pixels,line_width;
    uint64_t reserved[4];
} gx3de_marker_style;
typedef struct gx3de_measurement_style {
    uint32_t struct_size;
    uint32_t visible;
    uint32_t show_value;
    uint32_t reserved32;
    gx3de_rgb color;
    double marker_size_pixels,line_width;
    uint64_t reserved[4];
} gx3de_measurement_style;
typedef struct gx3de_curve_style {
    uint32_t struct_size;
    uint32_t visible;
    gx3de_rgb color;
    double line_width,opacity;
    uint64_t reserved[4];
} gx3de_curve_style;
typedef enum gx3de_native_window_kind {
    GX3DE_NATIVE_WINDOW_X11=1,
    GX3DE_NATIVE_WINDOW_WIN32=2
} gx3de_native_window_kind;
typedef enum gx3de_pick_geometry_kind {
    GX3DE_PICK_MESH=1,GX3DE_PICK_BREP_DISPLAY=2,GX3DE_PICK_SCIENTIFIC=3,
    GX3DE_PICK_REPEAT=4
} gx3de_pick_geometry_kind;
typedef struct gx3de_pick_hit {
    uint32_t struct_size;
    uint32_t geometry_kind; /* gx3de_pick_geometry_kind */
    gx3de_object *object; /* borrowed; valid while object and scene live */
    uint64_t cell_index,point_index; /* UINT64_MAX if unavailable; renderer IDs are transient */
    gx3de_vec3 world_point,local_point,world_normal;
    uint32_t has_surface_normal;
    uint32_t reserved32;
    uint64_t topology_index; /* zero-based face of exact immutable B-Rep, if available */
    double topology_u,topology_v; /* normalized face parameters */
    uint32_t has_topology;
    uint32_t reserved32_2;
    uint64_t reserved[2];
} gx3de_pick_hit;
typedef enum gx3de_colormap {
    GX3DE_COLORMAP_VIRIDIS=1,GX3DE_COLORMAP_COOL_WARM=2,
    GX3DE_COLORMAP_GRAYSCALE=3
} gx3de_colormap;
typedef struct gx3de_scientific_presentation {
    uint32_t struct_size;
    uint32_t colormap; /* gx3de_colormap */
    double scalar_min,scalar_max; /* finite and min < max if use_scalar_range */
    uint32_t use_scalar_range;
    uint32_t sphere_glyphs;
    uint32_t show_vectors;
    uint32_t reserved32;
    uint64_t max_vector_glyphs; /* 0 selects 2000; upper limit 20000 */
    uint64_t reserved[4];
} gx3de_scientific_presentation;
typedef enum gx3de_measure_kind {
    GX3DE_DISTANCE=1, GX3DE_DELTA_X=2, GX3DE_DELTA_Y=3,
    GX3DE_DELTA_Z=4, GX3DE_ANGLE_THREE_POINTS=5,
    GX3DE_DISTANCE_ON_PLANE=6,
    GX3DE_POINT_LINE_DISTANCE=7, GX3DE_POINT_PLANE_DISTANCE=8,
    GX3DE_LINE_LINE_ANGLE=9, GX3DE_LINE_PLANE_ANGLE=10,
    GX3DE_PLANE_PLANE_ANGLE=11, GX3DE_POINT_SURFACE_DISTANCE=12
} gx3de_measure_kind;
typedef struct gx3de_measure_spec {
    uint32_t struct_size;
    uint32_t kind;
    gx3de_anchor *anchors[4];
    gx3de_plane *planes[2];
    gx3de_object *surface_object; /* triangle mesh for point-to-surface distance */
    uint64_t reserved[4];
} gx3de_measure_spec;
typedef struct gx3de_measure_value {
    uint32_t struct_size;
    uint32_t kind;
    double value;
    uint32_t unit_known; /* 0 means no source unit was asserted */
    uint32_t reserved32;
    uint64_t reserved[4];
} gx3de_measure_value;
typedef enum gx3de_anchor_kind {
    GX3DE_ANCHOR_FREE=1, GX3DE_ANCHOR_VERTEX=2,
    GX3DE_ANCHOR_OBJECT_POINT=3, GX3DE_ANCHOR_EDGE=4,
    GX3DE_ANCHOR_FACE=5, GX3DE_ANCHOR_CENTER=6,
    GX3DE_ANCHOR_BREP_VERTEX=7, GX3DE_ANCHOR_BREP_EDGE=8,
    GX3DE_ANCHOR_BREP_FACE=9,
    GX3DE_ANCHOR_LINE=10,
    GX3DE_ANCHOR_OBJECT_AXIS=11,
    GX3DE_ANCHOR_OBJECT_REFERENCE=12
} gx3de_anchor_kind;
typedef enum gx3de_plane_preset { GX3DE_PLANE_XY=1,GX3DE_PLANE_XZ=2,GX3DE_PLANE_YZ=3 } gx3de_plane_preset;
typedef enum gx3de_boolean_kind { GX3DE_BOOLEAN_UNION=1,GX3DE_BOOLEAN_INTERSECTION=2,GX3DE_BOOLEAN_DIFFERENCE=3 } gx3de_boolean_kind;
typedef enum gx3de_constraint_kind { GX3DE_CONSTRAINT_FIXED=1,GX3DE_CONSTRAINT_COINCIDENT=2,GX3DE_CONSTRAINT_DISTANCE=3,GX3DE_CONSTRAINT_POINT_ON_PLANE=4,
    GX3DE_CONSTRAINT_ANGLE_LINES=5,GX3DE_CONSTRAINT_PARALLEL_LINES=6,GX3DE_CONSTRAINT_PERPENDICULAR_LINES=7,
    GX3DE_CONSTRAINT_POINT_ON_LINE=8,GX3DE_CONSTRAINT_POINT_ON_SURFACE=9,GX3DE_CONSTRAINT_ALIGNED_AXES=10 } gx3de_constraint_kind;
typedef enum gx3de_constraint_status { GX3DE_CONSTRAINT_SATISFIED=1,GX3DE_CONSTRAINT_VIOLATED=2,GX3DE_CONSTRAINT_UNDERDETERMINED=3,GX3DE_CONSTRAINT_OVERCONSTRAINED=4,GX3DE_CONSTRAINT_UNSUPPORTED=5 } gx3de_constraint_status;
typedef struct gx3de_constraint_spec {
    uint32_t struct_size;
    uint32_t kind;
    gx3de_object *moving_object;
    gx3de_anchor *a,*b;
    gx3de_plane *plane;
    double target,tolerance;
    uint64_t reserved[4];
} gx3de_constraint_spec;
typedef struct gx3de_constraint_value {
    uint32_t struct_size;
    uint32_t status;
    double residual,tolerance;
    uint64_t reserved[4];
} gx3de_constraint_value;
typedef struct gx3de_constraint_system_result {
    uint32_t struct_size;
    uint32_t status; /* gx3de_constraint_status */
    uint64_t constraint_count, satisfied_count, moving_object_count;
    uint32_t passes;
    uint32_t reserved32;
    double maximum_residual; /* absolute units differ by constraint kind */
    uint64_t reserved[4];
} gx3de_constraint_system_result;
typedef struct gx3de_constraint_spec_ex {
    uint32_t struct_size;
    uint32_t kind;
    gx3de_object *moving_object;
    gx3de_anchor *anchors[4]; /* lines: moving [0,1], target [2,3]; point-on-line: point [0], line [1,2] */
    gx3de_object *surface_object; /* point-on-surface: fixed triangle mesh */
    double target,tolerance; /* angle target in radians */
    uint64_t reserved[4];
} gx3de_constraint_spec_ex;
typedef struct gx3de_alignment_spec {
    uint32_t struct_size;
    uint32_t reserved32;
    gx3de_object *moving_object;
    gx3de_anchor *moving_points[3];
    gx3de_anchor *target_points[3];
    double tolerance;
    uint64_t reserved[4];
} gx3de_alignment_spec;

GX3DE_API gx3de_result gx3de_get_info(gx3de_info *info);
GX3DE_API const char *gx3de_result_name(gx3de_result result);
GX3DE_API gx3de_result gx3de_engine_create(gx3de_engine **out);
GX3DE_API void gx3de_engine_destroy(gx3de_engine *engine);
GX3DE_API gx3de_result gx3de_engine_set_cache_namespace(gx3de_engine *engine,const char *namespace_utf8);
GX3DE_API gx3de_result gx3de_engine_cache_stats(gx3de_engine *engine,gx3de_cache_stats *out);
GX3DE_API gx3de_result gx3de_engine_set_mesh_cache_root(gx3de_engine *engine,const char *path_utf8); /* NULL disables */
GX3DE_API gx3de_result gx3de_engine_disk_cache_stats(gx3de_engine *engine,gx3de_disk_cache_stats *out);
/* Repeat derived data uses <mesh-cache-root>/repeats and independent stats. */
GX3DE_API gx3de_result gx3de_engine_repeat_cache_stats(gx3de_engine *engine,gx3de_disk_cache_stats *out);
GX3DE_API gx3de_result gx3de_engine_set_scientific_cache_root(gx3de_engine *engine,const char *path_utf8); /* NULL disables */
GX3DE_API gx3de_result gx3de_engine_scientific_cache_stats(gx3de_engine *engine,gx3de_disk_cache_stats *out);
GX3DE_API gx3de_result gx3de_scene_create(gx3de_engine *engine,gx3de_scene **out);
GX3DE_API gx3de_result gx3de_scene_destroy(gx3de_scene *scene);
GX3DE_API gx3de_result gx3de_group_create(gx3de_scene *scene,gx3de_group **out);
GX3DE_API gx3de_result gx3de_group_destroy(gx3de_group *group);
GX3DE_API gx3de_result gx3de_group_add(gx3de_group *group,gx3de_object *object);
GX3DE_API gx3de_result gx3de_group_remove(gx3de_group *group,gx3de_object *object);
GX3DE_API gx3de_result gx3de_group_set_transform(gx3de_group *group,const gx3de_mat4 *matrix);
GX3DE_API gx3de_result gx3de_group_get_transform(gx3de_group *group,gx3de_mat4 *matrix);
GX3DE_API gx3de_result gx3de_group_translate(gx3de_group *group,gx3de_vec3 delta,uint32_t world_space);
GX3DE_API gx3de_result gx3de_group_rotate(gx3de_group *group,gx3de_vec3 axis,double radians,gx3de_vec3 pivot,uint32_t world_space);
GX3DE_API gx3de_result gx3de_group_scale(gx3de_group *group,gx3de_vec3 factors,gx3de_vec3 pivot,uint32_t world_space);
/* Source-preserving atomic subtree copy; geometry remains shared immutable
 * storage, placement/style/group nodes are independent. No source is moved. */
GX3DE_API gx3de_result gx3de_group_duplicate(gx3de_group *source,gx3de_group **out);
/* Direct children, including nested group nodes, in stable scene order. */
GX3DE_API gx3de_result gx3de_group_member_count(gx3de_group *group,uint64_t *out);
GX3DE_API gx3de_result gx3de_group_member_get(gx3de_group *group,uint64_t index,gx3de_object **out);
GX3DE_API gx3de_result gx3de_group_bounds(gx3de_group *group,gx3de_bounds *out);
GX3DE_API gx3de_result gx3de_object_create_mesh(gx3de_scene *scene,const gx3de_vec3 *vertices,uint64_t vertex_count,const uint32_t *triangle_indices,uint64_t triangle_count,gx3de_object **out);
GX3DE_API gx3de_result gx3de_object_import_mesh(gx3de_scene *scene,const gx3de_mesh_import_spec *spec,gx3de_object **out);
/* Streaming, bounded source preview. Binary STL is sampled by stride; OBJ
 * supports positive absolute face indices. Unsupported OBJ indexing returns
 * GX3DE_UNSUPPORTED so a caller may use full import. */
GX3DE_API gx3de_result gx3de_object_import_mesh_preview(gx3de_scene *scene,const gx3de_mesh_import_spec *spec,gx3de_object **out);
/* Builds a reusable derived mesh at the legacy viewer's 1/5/20/50/100 percent
 * levels. The output owns an independent transform and keeps source identity. */
GX3DE_API gx3de_result gx3de_mesh_lod(gx3de_object *source,gx3de_mesh_lod_level level,gx3de_object **out);
/* A repeat result snapshots source geometry and world transform. Placements
 * map its centered prototype mesh into world space. An empty unmatched
 * remainder is reported by GX3DE_NOT_FOUND. Caller destroys created objects. */
GX3DE_API gx3de_result gx3de_mesh_repeats_discover(gx3de_object *source,uint64_t selected_triangle,gx3de_repeat_result **out);
GX3DE_API gx3de_result gx3de_mesh_repeats_info(gx3de_repeat_result *result,gx3de_repeat_info *out);
GX3DE_API gx3de_result gx3de_mesh_repeats_placement(gx3de_repeat_result *result,uint64_t index,gx3de_mat4 *world_from_prototype);
GX3DE_API gx3de_result gx3de_mesh_repeats_prototype(gx3de_repeat_result *result,gx3de_object **out);
GX3DE_API gx3de_result gx3de_mesh_repeats_remainder(gx3de_repeat_result *result,gx3de_object **out);
/* Opt-in shared-mapper display of all captured placements plus remainder.
 * The source is hidden only for this presentation; source visibility itself
 * remains unchanged. Rediscover after source geometry/pose changes. */
GX3DE_API gx3de_result gx3de_mesh_repeats_presentation_set(gx3de_repeat_result *result,uint32_t enabled);
GX3DE_API gx3de_result gx3de_mesh_repeats_presentation_get(gx3de_repeat_result *result,uint32_t *enabled);
GX3DE_API gx3de_result gx3de_mesh_repeats_destroy(gx3de_repeat_result *result);
GX3DE_API gx3de_result gx3de_object_source_sha256(gx3de_object *object,char out_hex65[65]);
GX3DE_API gx3de_result gx3de_scientific_import(gx3de_scene *scene,const gx3de_scientific_import_spec *spec,gx3de_object **out);
/* Explicit-mask row-major surface: omit an entire quad if any corner is absent.
 * No interpolation. At most 1,000,000 input points. Retains source point/quad IDs.
 * Callers declare physical units at the owning document boundary. */
GX3DE_API gx3de_result gx3de_scientific_masked_surface(gx3de_scene *scene,const gx3de_vec3 *grid,const uint8_t *present,uint64_t rows,uint64_t columns,gx3de_object **out);
/* Persistent triangulated circular sweep with rotation-minimizing parallel
 * transport, positive per-vertex radii, 3..256 sides and explicit caps (0/1).
 * Rejects zero-length segments, reversals and an initial U parallel to tangent.
 * Source point/segment arrays survive VTP; cap source_cell_id values are -1/-2.
 * Sampling approximation; self-intersection is not repaired. <=1M ring vertices. */
GX3DE_API gx3de_result gx3de_scientific_sweep(gx3de_scene *scene,const gx3de_vec3 *path,const double *radii,uint64_t count,uint32_t sides,uint32_t caps,gx3de_vec3 initial_u,gx3de_object **out);
/* Lossless PolyData connectivity/arrays export in world coordinates; refuses overwrite. */
/* Durable caller numeric IDs stored in logical_point_id/logical_cell_id arrays.
 * IDs are exact nonnegative integers <= 2^53-1; missing identity is NOT_FOUND. */
GX3DE_API gx3de_result gx3de_scientific_logical_id(gx3de_object *object,uint32_t association,uint64_t index,uint64_t *logical_id);
GX3DE_API gx3de_result gx3de_scientific_write_vtp(gx3de_object *object,const char *path_utf8);
GX3DE_API gx3de_result gx3de_scientific_create_polydata(gx3de_scene *scene,const gx3de_scientific_polydata_spec *spec,gx3de_object **out);
GX3DE_API gx3de_result gx3de_scientific_create_image(gx3de_scene *scene,const gx3de_scientific_image_spec *spec,gx3de_object **out);
GX3DE_API gx3de_result gx3de_scientific_create_unstructured(gx3de_scene *scene,const gx3de_scientific_unstructured_spec *spec,gx3de_object **out);
GX3DE_API gx3de_result gx3de_scientific_info_get(gx3de_object *object,gx3de_scientific_info *out);
GX3DE_API gx3de_result gx3de_scientific_grid_info_get(gx3de_object *object,gx3de_scientific_grid_info *out);
GX3DE_API gx3de_result gx3de_scientific_point(gx3de_object *object,uint64_t index,uint32_t world_space,gx3de_vec3 *out);
GX3DE_API gx3de_result gx3de_scientific_cell_info_get(gx3de_object *object,uint64_t index,gx3de_scientific_cell_info *out);
GX3DE_API gx3de_result gx3de_scientific_cell_point_id(gx3de_object *object,uint64_t cell,uint64_t position,uint64_t *point_id);
GX3DE_API gx3de_result gx3de_scientific_array_info_get(gx3de_object *object,uint64_t index,gx3de_scientific_array_info *out);
GX3DE_API gx3de_result gx3de_scientific_array_find(gx3de_object *object,uint32_t association,const char *name_utf8,uint64_t *index);
GX3DE_API gx3de_result gx3de_scientific_array_values(gx3de_object *object,uint64_t array,uint64_t first_tuple,uint64_t tuple_count,double *out_values,uint64_t value_capacity,uint64_t *required_values);
GX3DE_API gx3de_result gx3de_scientific_field_roles_set(gx3de_object *object,const gx3de_scientific_field_roles *roles);
GX3DE_API gx3de_result gx3de_scientific_field_roles_get(gx3de_object *object,gx3de_scientific_field_roles *roles);
GX3DE_API gx3de_result gx3de_scientific_presentation_set(gx3de_object *object,const gx3de_scientific_presentation *presentation);
GX3DE_API gx3de_result gx3de_scientific_presentation_get(gx3de_object *object,gx3de_scientific_presentation *presentation);
/* Optional point-scalar opacity role: -1 disables; values must lie in [0,1].
 * Combined with object opacity at render time, without mutating source data. */
GX3DE_API gx3de_result gx3de_scientific_opacity_array_set(gx3de_object *object,int64_t array_index);
GX3DE_API gx3de_result gx3de_scientific_opacity_array_get(gx3de_object *object,int64_t *array_index);
/* Bind a point-associated normalized direct RGB (3) or RGBA (4) array.
 * -1 clears the binding. Direct color takes precedence over scalar coloring;
 * final alpha is object opacity * opacity-array * direct RGBA alpha. */
GX3DE_API gx3de_result gx3de_scientific_color_array_set(gx3de_object *object,int64_t array_index);
GX3DE_API gx3de_result gx3de_scientific_color_array_get(gx3de_object *object,int64_t *array_index);
/* Samples a named point-vector array by source point ID in deterministic order.
 * stride=ceil(point_count/max_samples), starting at ID zero. The result count
 * never exceeds max_samples. With capacity zero, returns the required count.
 * world_space transforms positions affinely and vectors by the linear part. */
GX3DE_API gx3de_result gx3de_scientific_vector_samples(gx3de_object *object,uint64_t vector_array,uint64_t max_samples,uint32_t world_space,gx3de_scientific_vector_sample *samples,uint64_t capacity,uint64_t *required_samples);
GX3DE_API gx3de_result gx3de_scientific_isosurfaces(gx3de_object *grid,const char *scalar_name_utf8,const double *isovalues,uint32_t value_count,gx3de_object **out_objects); /* array of value_count slots; NULL means empty result */
/* Explicit geometry-only conversion of a pure polygon/triangle-strip polydata
 * surface to an independent complete indexed triangle mesh. The scientific
 * source and its fields remain unchanged; fields are not transferred to mesh.
 * Lines/vertices/mixed non-surface cells are rejected. Budgets are nonzero;
 * output and scene stay unchanged on failure. Placement is retained separately. */
GX3DE_API gx3de_result gx3de_scientific_triangle_mesh_create(gx3de_object *source,
    uint64_t max_triangles,uint64_t max_output_bytes,gx3de_object **out);
GX3DE_API gx3de_result gx3de_job_prepare_mesh_import(gx3de_scene *scene,const gx3de_mesh_import_spec *spec,gx3de_job **out);
GX3DE_API gx3de_result gx3de_job_prepare_mesh_lod(gx3de_object *source,gx3de_mesh_lod_level level,gx3de_job **out);
GX3DE_API gx3de_result gx3de_job_prepare_step_import(gx3de_engine *engine,const gx3de_step_import_spec *spec,gx3de_job **out);
/* OCCT meshing itself can block. Cancellation is honored before and directly
 * after that call; the immutable source shape is retained by the job. */
GX3DE_API gx3de_result gx3de_job_prepare_brep_mesh(gx3de_object *source,const gx3de_brep_mesh_spec *spec,gx3de_job **out);
GX3DE_API gx3de_result gx3de_job_start(gx3de_job *job);
GX3DE_API gx3de_result gx3de_job_cancel(gx3de_job *job);
GX3DE_API gx3de_result gx3de_job_poll(gx3de_job *job,gx3de_job_state *out);
GX3DE_API gx3de_result gx3de_job_wait(gx3de_job *job,uint64_t timeout_ms,gx3de_job_state *out);
GX3DE_API gx3de_result gx3de_job_next_event(gx3de_job *job,gx3de_job_event *out);
GX3DE_API gx3de_result gx3de_job_progress(gx3de_job *job,uint64_t *progress_permille);
GX3DE_API gx3de_result gx3de_job_failure_text(gx3de_job *job,char *buffer,uint64_t capacity,uint64_t *required_bytes);
GX3DE_API gx3de_result gx3de_job_take_mesh(gx3de_job *job,gx3de_object **out);
GX3DE_API gx3de_result gx3de_job_take_step(gx3de_job *job,gx3de_step_document **out);
GX3DE_API gx3de_result gx3de_job_destroy(gx3de_job *job);
GX3DE_API gx3de_result gx3de_step_open(gx3de_engine *engine,const gx3de_step_import_spec *spec,gx3de_step_document **out);
GX3DE_API gx3de_result gx3de_step_summary_get(gx3de_step_document *document,gx3de_step_summary *out);
GX3DE_API gx3de_result gx3de_step_node_get(gx3de_step_document *document,uint64_t index,gx3de_step_node *out);
GX3DE_API gx3de_result gx3de_step_text_get(gx3de_step_document *document,uint32_t field,uint64_t index,char *buffer,uint64_t capacity,uint64_t *required_bytes);
GX3DE_API gx3de_result gx3de_step_source_sha256(gx3de_step_document *document,char out_hex65[65]);
GX3DE_API gx3de_result gx3de_step_instance_create(gx3de_scene *scene,gx3de_step_document *document,uint64_t node_index,gx3de_object **out);
/* Explicitly collect all STEP part occurrences into one immutable B-Rep
 * compound, preserving their world placements without Boolean fusion.
 * Intended for rehydrating a previously saved single multi-solid object.
 * Ordinary assembly intake continues to use distinct instance identities. */
GX3DE_API gx3de_result gx3de_step_compound_create(gx3de_scene *scene,gx3de_step_document *document,gx3de_object **out);
GX3DE_API gx3de_result gx3de_step_instance_mesh_create(gx3de_scene *scene,gx3de_step_document *document,uint64_t node_index,const gx3de_step_mesh_spec *spec,gx3de_object **out);
GX3DE_API gx3de_result gx3de_object_brep_mesh_create(gx3de_object *source,const gx3de_brep_mesh_spec *spec,gx3de_object **out);
/* Explicit world-space tolerance and identity-placement mesh derivation. */
GX3DE_API gx3de_result gx3de_object_brep_mesh_create_world(gx3de_object *source,const gx3de_brep_mesh_spec *spec,gx3de_object **out);
/* Fingerprint of the immutable source geometry used to derive a mesh. This
 * is independent of the mesh fingerprint and survives source object deletion. */
GX3DE_API gx3de_result gx3de_object_derivation_fingerprint(gx3de_object *object,char out_hex65[65]);
GX3DE_API gx3de_result gx3de_step_close(gx3de_step_document *document);
GX3DE_API gx3de_result gx3de_object_duplicate(gx3de_object *source,gx3de_object **out);
GX3DE_API gx3de_result gx3de_object_destroy(gx3de_object *object);
GX3DE_API gx3de_result gx3de_object_set_parent(gx3de_object *object,gx3de_object *parent);
GX3DE_API gx3de_result gx3de_object_set_visible(gx3de_object *object,uint32_t visible);
GX3DE_API gx3de_result gx3de_object_get_visible(gx3de_object *object,uint32_t *visible);
/* Scientific geometry participation; presentation does not alter this role. */
typedef enum gx3de_geometry_role {
    GX3DE_GEOMETRY_REGULAR=0, GX3DE_GEOMETRY_CONSTRUCTION=1,
    GX3DE_GEOMETRY_REFERENCE=2
} gx3de_geometry_role;
GX3DE_API gx3de_result gx3de_object_geometry_role_set(gx3de_object *object,uint32_t role);
GX3DE_API gx3de_result gx3de_object_geometry_role_get(gx3de_object *object,uint32_t *role);
GX3DE_API gx3de_result gx3de_object_set_opacity(gx3de_object *object,double opacity);
GX3DE_API gx3de_result gx3de_object_get_opacity(gx3de_object *object,double *opacity);
/* -1 removes the optical binding; [0,1] is flat scientific transmittance for
 * one completed centerline traversal of this mesh. Visual alpha is separate. */
GX3DE_API gx3de_result gx3de_object_scientific_transmittance_set(gx3de_object *object,double transmittance);
GX3DE_API gx3de_result gx3de_object_scientific_transmittance_get(gx3de_object *object,double *transmittance);
GX3DE_API gx3de_result gx3de_object_style_set(gx3de_object *object,const gx3de_object_style *style);
GX3DE_API gx3de_result gx3de_object_style_get(gx3de_object *object,gx3de_object_style *style);
/* Loaded image resources belong to the engine. An assignment retains its
 * decoded pixels after the public texture handle is destroyed. JPEG and PNG
 * are accepted; no source image file is modified. */
GX3DE_API gx3de_result gx3de_texture_load_file(gx3de_engine *engine,const char *path_utf8,gx3de_texture **out);
GX3DE_API gx3de_result gx3de_texture_info_get(gx3de_texture *texture,gx3de_texture_info *out);
GX3DE_API gx3de_result gx3de_texture_destroy(gx3de_texture *texture);
/* The selected region is the edge-connected, consistently oriented coplanar
 * patch containing source_triangle. The image rectangle is clipped to that
 * patch, so it cannot spill onto adjacent faces. Multiple assignments per
 * object may target distinct regions. Overlapping assignments do not define
 * image-layer compositing order. */
GX3DE_API gx3de_result gx3de_object_planar_texture_add(gx3de_object *object,gx3de_texture *texture,const gx3de_planar_texture_spec *spec,gx3de_planar_texture **out);
/* Resolves a transient rendered pick to its source triangle using the local
 * hit point and world normal. The returned assignment stores the resolved
 * source_triangle and picked local_anchor; other placement fields come from
 * placement. It never trusts the display cell ID. A pick displaced away from
 * every source face by an approximate display LOD returns NOT_FOUND. */
GX3DE_API gx3de_result gx3de_object_planar_texture_add_from_pick(gx3de_texture *texture,const gx3de_pick_hit *hit,const gx3de_planar_texture_spec *placement,gx3de_planar_texture **out);
GX3DE_API gx3de_result gx3de_planar_texture_update(gx3de_planar_texture *assignment,const gx3de_planar_texture_spec *spec);
GX3DE_API gx3de_result gx3de_planar_texture_get(gx3de_planar_texture *assignment,gx3de_planar_texture_spec *out);
/* All edits preserve the normalized image anchor. Proportional resize uses
 * width and retains the current aspect ratio; stretch uses both dimensions. */
GX3DE_API gx3de_result gx3de_planar_texture_move(gx3de_planar_texture *assignment,gx3de_vec3 local_anchor);
GX3DE_API gx3de_result gx3de_planar_texture_rotate(gx3de_planar_texture *assignment,double radians);
GX3DE_API gx3de_result gx3de_planar_texture_resize(gx3de_planar_texture *assignment,uint32_t mode,double width,double height);
GX3DE_API gx3de_result gx3de_planar_texture_gizmo_visible_set(gx3de_planar_texture *assignment,uint32_t visible);
GX3DE_API gx3de_result gx3de_planar_texture_gizmo_visible_get(gx3de_planar_texture *assignment,uint32_t *visible);
GX3DE_API gx3de_result gx3de_planar_texture_gizmo_handle_world(gx3de_planar_texture *assignment,uint32_t handle,gx3de_vec3 *point);
GX3DE_API gx3de_result gx3de_planar_texture_gizmo_pick(gx3de_viewport *viewport,gx3de_planar_texture *assignment,double x,double y,double radius_pixels,uint32_t *handle);
GX3DE_API gx3de_result gx3de_planar_texture_destroy(gx3de_planar_texture *assignment);
GX3DE_API gx3de_result gx3de_object_curved_texture_add(gx3de_object *object,gx3de_texture *texture,const gx3de_curved_texture_spec *spec,gx3de_curved_texture **out);
GX3DE_API gx3de_result gx3de_object_curved_texture_add_from_pick(gx3de_texture *texture,const gx3de_pick_hit *hit,const gx3de_curved_texture_spec *placement,gx3de_curved_texture **out);
GX3DE_API gx3de_result gx3de_curved_texture_update(gx3de_curved_texture *assignment,const gx3de_curved_texture_spec *spec);
GX3DE_API gx3de_result gx3de_curved_texture_get(gx3de_curved_texture *assignment,gx3de_curved_texture_spec *out);
GX3DE_API gx3de_result gx3de_curved_texture_move(gx3de_curved_texture *assignment,gx3de_vec3 local_anchor);
GX3DE_API gx3de_result gx3de_curved_texture_rotate(gx3de_curved_texture *assignment,double radians);
GX3DE_API gx3de_result gx3de_curved_texture_resize(gx3de_curved_texture *assignment,uint32_t mode,double width,double height);
GX3DE_API gx3de_result gx3de_curved_texture_gizmo_visible_set(gx3de_curved_texture *assignment,uint32_t visible);
GX3DE_API gx3de_result gx3de_curved_texture_gizmo_visible_get(gx3de_curved_texture *assignment,uint32_t *visible);
/* Handle IDs and resize modes are shared with the planar texture API.
 * Footprint segments are object-local; transform them with the source object. */
GX3DE_API gx3de_result gx3de_curved_texture_gizmo_handle_world(gx3de_curved_texture *assignment,uint32_t handle,gx3de_vec3 *point);
GX3DE_API gx3de_result gx3de_curved_texture_gizmo_pick(gx3de_viewport *viewport,gx3de_curved_texture *assignment,double x,double y,double radius_pixels,uint32_t *handle);
GX3DE_API gx3de_result gx3de_curved_texture_footprint_get(gx3de_curved_texture *assignment,gx3de_segment3 *segments,uint64_t capacity,uint64_t *count);
GX3DE_API gx3de_result gx3de_curved_texture_status_get(gx3de_curved_texture *assignment,gx3de_curved_texture_status *status);
GX3DE_API gx3de_result gx3de_curved_texture_seams_get(gx3de_curved_texture *assignment,gx3de_segment3 *segments,uint64_t capacity,uint64_t *count);
GX3DE_API gx3de_result gx3de_curved_texture_destroy(gx3de_curved_texture *assignment);
/* The engine graphics shadow policy caps these scene controls. The scene
 * switch is off by default; each object casts and receives by default.
 * Light slots follow view lighting. */
GX3DE_API gx3de_result gx3de_scene_shadows_set(gx3de_scene *scene,uint32_t enabled);
/* Scene-owned shaded sphere cloud. Up to 100,000 particles per cloud.
 * A zero count is valid; nonzero count requires a particle array. */
GX3DE_API gx3de_result gx3de_particle_cloud_create(gx3de_scene *scene,const gx3de_particle_cloud_style *style,const gx3de_particle *particles,uint64_t count,gx3de_particle_cloud **out);
GX3DE_API gx3de_result gx3de_particle_cloud_destroy(gx3de_particle_cloud *cloud);
GX3DE_API gx3de_result gx3de_particle_cloud_particles_set(gx3de_particle_cloud *cloud,const gx3de_particle *particles,uint64_t count);
GX3DE_API gx3de_result gx3de_particle_cloud_count_get(gx3de_particle_cloud *cloud,uint64_t *count);
GX3DE_API gx3de_result gx3de_particle_cloud_style_set(gx3de_particle_cloud *cloud,const gx3de_particle_cloud_style *style);
GX3DE_API gx3de_result gx3de_particle_cloud_style_get(gx3de_particle_cloud *cloud,gx3de_particle_cloud_style *style);
GX3DE_API gx3de_result gx3de_particle_cloud_transform_set(gx3de_particle_cloud *cloud,const gx3de_mat4 *transform);
GX3DE_API gx3de_result gx3de_particle_cloud_transform_get(gx3de_particle_cloud *cloud,gx3de_mat4 *transform);
GX3DE_API gx3de_result gx3de_particle_cloud_visible_set(gx3de_particle_cloud *cloud,uint32_t visible);
GX3DE_API gx3de_result gx3de_particle_cloud_visible_get(gx3de_particle_cloud *cloud,uint32_t *visible);
GX3DE_API gx3de_result gx3de_scene_shadows_get(gx3de_scene *scene,uint32_t *enabled);
GX3DE_API gx3de_result gx3de_object_shadow_flags_set(gx3de_object *object,uint32_t casts,uint32_t receives);
GX3DE_API gx3de_result gx3de_object_shadow_flags_get(gx3de_object *object,uint32_t *casts,uint32_t *receives);
GX3DE_API gx3de_result gx3de_view_light_shadow_set(gx3de_view *view,uint32_t light_index,uint32_t enabled);
GX3DE_API gx3de_result gx3de_view_light_shadow_get(gx3de_view *view,uint32_t light_index,uint32_t *enabled);
GX3DE_API gx3de_result gx3de_object_set_transform(gx3de_object *object,const gx3de_mat4 *matrix);
GX3DE_API gx3de_result gx3de_object_get_transform(gx3de_object *object,gx3de_mat4 *matrix);
/* Explicit source-preserving normalization into world geometry with identity
 * placement. Supports mesh/B-Rep without texture assignments. */
GX3DE_API gx3de_result gx3de_object_bake_transform(gx3de_object *source,gx3de_object **out);
/* Coordinate-unit change: rescale local geometry and world translation,
 * preserving dimensionless rotation/physical scale independently. */
GX3DE_API gx3de_result gx3de_object_rescale_coordinates(gx3de_object *source,double factor,gx3de_object **out);
/* Borrowed owner handle for cross-scene validation; no ownership transfer. */
GX3DE_API gx3de_result gx3de_object_scene_get(gx3de_object *object,gx3de_scene **scene);
GX3DE_API gx3de_result gx3de_object_world_transform_get(gx3de_object *object,gx3de_mat4 *matrix);
GX3DE_API gx3de_result gx3de_object_reset_transform(gx3de_object *object);
GX3DE_API gx3de_result gx3de_object_translate(gx3de_object *object,gx3de_vec3 delta,uint32_t world_space);
GX3DE_API gx3de_result gx3de_object_rotate(gx3de_object *object,gx3de_vec3 axis,double radians,gx3de_vec3 pivot,uint32_t world_space);
GX3DE_API gx3de_result gx3de_object_scale(gx3de_object *object,gx3de_vec3 factors,gx3de_vec3 pivot,uint32_t world_space);
GX3DE_API gx3de_result gx3de_object_align_three_points(const gx3de_alignment_spec *spec);
GX3DE_API gx3de_result gx3de_object_bounds(gx3de_object *object,uint32_t world_space,gx3de_bounds *out);
GX3DE_API gx3de_result gx3de_object_counts(gx3de_object *object,uint64_t *vertices,uint64_t *triangles);
GX3DE_API gx3de_result gx3de_object_vertex(gx3de_object *object,uint64_t index,uint32_t world_space,gx3de_vec3 *out);
GX3DE_API gx3de_result gx3de_mesh_diagnose(gx3de_object *object,gx3de_mesh_diagnostics *out);
/* Same topology checks with area and volume measured after the complete world
 * placement. The local-space diagnostic API remains unchanged. */
GX3DE_API gx3de_result gx3de_mesh_diagnose_world(gx3de_object *object,gx3de_mesh_diagnostics *out);
GX3DE_API gx3de_result gx3de_mesh_boundary_edges(gx3de_object *object,uint32_t *index_pairs,uint64_t pair_capacity,uint64_t *required_pairs);
/* Deterministic source-index boundary page. Count <= 65536; short final
 * pages return their copied count and full exact total. Coordinates are queried
 * separately through the captured world boundary-loop API. */
GX3DE_API gx3de_result gx3de_mesh_boundary_edges_range(gx3de_object *object,uint64_t start,uint64_t count,uint32_t *index_pairs,uint64_t pair_capacity,uint64_t *copied_pairs,uint64_t *total_pairs);
GX3DE_API gx3de_result gx3de_mesh_loops_create(gx3de_object *object,gx3de_mesh_loops **out);
GX3DE_API gx3de_result gx3de_mesh_loops_count(gx3de_mesh_loops *loops,uint64_t *out);
GX3DE_API gx3de_result gx3de_mesh_loops_size(gx3de_mesh_loops *loops,uint64_t loop,uint64_t *out);
GX3DE_API gx3de_result gx3de_mesh_loops_vertex(gx3de_mesh_loops *loops,uint64_t loop,uint64_t vertex,uint32_t *source_index,gx3de_vec3 *captured_world_point);
GX3DE_API gx3de_result gx3de_mesh_loops_destroy(gx3de_mesh_loops *loops);
GX3DE_API gx3de_result gx3de_mesh_append(gx3de_object *a,gx3de_object *b,gx3de_object **out);
GX3DE_API gx3de_result gx3de_mesh_merge(gx3de_object *a,gx3de_object *b,double weld_tolerance,gx3de_object **out);
GX3DE_API gx3de_result gx3de_mesh_stitch(gx3de_object *a,gx3de_object *b,double tolerance,gx3de_object **out);
/* Bridge one simple open boundary per mesh, allowing a positive world-space gap.
 * Both meshes must be in the same scene. Only unique, safe boundary pairings
 * that form a closed non-self-intersecting mesh are published. */
GX3DE_API gx3de_result gx3de_mesh_bridge(gx3de_object *a,gx3de_object *b,double max_gap,gx3de_object **out);
/* Close exactly two compatible open boundaries of one mesh in world space. */
GX3DE_API gx3de_result gx3de_mesh_heal_seam(gx3de_object *source,double max_gap,gx3de_object **out);
GX3DE_API gx3de_result gx3de_mesh_orient_normals(gx3de_object *object,gx3de_object **out);
GX3DE_API gx3de_result gx3de_mesh_self_intersections(gx3de_object *object,double tolerance,uint64_t *intersecting_pairs);
/* Counts all nonadjacent pairs. Copies the first pair_capacity pairs in deterministic
 * order; returns GX3DE_RANGE when the buffer is short and sets required_pairs.
 * Every supplied output element must have struct_size initialized. With zero
 * capacity, pairs may be NULL. Witness coordinates are captured in world space. */
GX3DE_API gx3de_result gx3de_mesh_intersection_pairs(gx3de_object *object,double tolerance,gx3de_mesh_intersection_pair *pairs,uint64_t pair_capacity,uint64_t *required_pairs);
GX3DE_API gx3de_result gx3de_mesh_weld(gx3de_object *object,double tolerance,gx3de_object **out);
GX3DE_API gx3de_result gx3de_mesh_clean_duplicates(gx3de_object *object,gx3de_object **out);
GX3DE_API gx3de_result gx3de_object_project_mesh(gx3de_object *object,gx3de_plane *plane,gx3de_object **out);
/* Queryable world-space projection of mesh, B-Rep or scientific geometry.
 * Mesh and B-Rep sources yield an immutable triangle mesh; scientific sources
 * yield immutable projected polydata with retained point/cell arrays. A B-Rep
 * requires a size-tagged tessellation spec with explicit tolerances/budgets;
 * pass NULL for mesh or scientific sources. The returned object is scene-owned
 * until destroyed and can be queried independently of its source. The source
 * link supports projection_source/refresh; destroying the source or plane
 * leaves the projected geometry intact and makes refresh return NOT_FOUND. */
GX3DE_API gx3de_result gx3de_object_project(gx3de_object *object,gx3de_plane *plane,
    const gx3de_brep_mesh_spec *brep_tessellation,gx3de_object **out);
GX3DE_API gx3de_result gx3de_object_projection_source(gx3de_object *projection,gx3de_object **source,gx3de_plane **plane);
GX3DE_API gx3de_result gx3de_object_projection_refresh(gx3de_object *projection);
GX3DE_API gx3de_result gx3de_mesh_clip(gx3de_object *object,gx3de_plane *plane,uint32_t keep_positive,gx3de_object **out);
GX3DE_API gx3de_result gx3de_mesh_clip_capped(gx3de_object *object,gx3de_plane *plane,uint32_t keep_positive,double join_tolerance,gx3de_object **out);
GX3DE_API gx3de_result gx3de_object_geometry_fingerprint(gx3de_object *object,char out_hex65[65]);
GX3DE_API gx3de_result gx3de_object_create_brep_box(gx3de_scene *scene,gx3de_vec3 lengths,gx3de_object **out);
GX3DE_API gx3de_result gx3de_object_create_brep_cylinder(gx3de_scene *scene,double radius,double height,gx3de_object **out);
GX3DE_API gx3de_result gx3de_brep_boolean(gx3de_object *a,gx3de_object *b,gx3de_boolean_kind kind,gx3de_object **out);
GX3DE_API gx3de_result gx3de_brep_diagnose(gx3de_object *object,gx3de_brep_diagnostics *out);
GX3DE_API gx3de_result gx3de_brep_validate(gx3de_object *object,gx3de_brep_validation *out);
/* Conservative closed-solid healing. Tolerance is finite and positive; the
 * source is immutable. A valid solid is copied as an independent object.
 * Invalid input publishes only if OCCT ShapeFix yields validated closed
 * oriented solids with bounded changes to solid count, area, volume and bounds. */
GX3DE_API gx3de_result gx3de_brep_heal(gx3de_object *object,double tolerance,gx3de_object **out);
GX3DE_API gx3de_result gx3de_brep_clip(gx3de_object *object,gx3de_plane *plane,uint32_t keep_positive,gx3de_object **out);
GX3DE_API gx3de_result gx3de_brep_topology_counts(gx3de_object *object,gx3de_brep_topology *out);
/* Zero-based indices of this exact immutable source shape. Edge tolerances
 * are positive source-coordinate lengths. Queries do not apply object pose. */
GX3DE_API gx3de_result gx3de_brep_edge_geometry_get(gx3de_object *object,uint64_t edge_index,double length_tolerance,gx3de_brep_edge_geometry *out);
GX3DE_API gx3de_result gx3de_brep_face_geometry_get(gx3de_object *object,uint64_t face_index,gx3de_brep_face_geometry *out);
GX3DE_API gx3de_result gx3de_anchor_brep_vertex(gx3de_object *object,uint64_t vertex_index,gx3de_anchor **out);
GX3DE_API gx3de_result gx3de_anchor_brep_edge(gx3de_object *object,uint64_t edge_index,double curve_fraction,gx3de_anchor **out);
GX3DE_API gx3de_result gx3de_anchor_brep_face(gx3de_object *object,uint64_t face_index,double u_fraction,double v_fraction,gx3de_anchor **out);

GX3DE_API gx3de_result gx3de_plane_create(gx3de_scene *scene,gx3de_vec3 origin,gx3de_vec3 normal,gx3de_vec3 u_axis,gx3de_plane **out);
GX3DE_API gx3de_result gx3de_plane_from_points(gx3de_scene *scene,gx3de_vec3 a,gx3de_vec3 b,gx3de_vec3 c,gx3de_plane **out);
GX3DE_API gx3de_result gx3de_plane_create_preset(gx3de_scene *scene,gx3de_plane_preset preset,gx3de_vec3 origin,gx3de_plane **out);
GX3DE_API gx3de_result gx3de_plane_destroy(gx3de_plane *plane);
GX3DE_API gx3de_result gx3de_plane_get(gx3de_plane *plane,gx3de_vec3 *origin,gx3de_vec3 *normal,gx3de_vec3 *u_axis);
GX3DE_API gx3de_result gx3de_plane_set(gx3de_plane *plane,gx3de_vec3 origin,gx3de_vec3 normal,gx3de_vec3 u_axis);
GX3DE_API gx3de_result gx3de_plane_coordinates(gx3de_plane *plane,gx3de_vec3 world,gx3de_vec3 *uvw);
GX3DE_API gx3de_result gx3de_plane_world(gx3de_plane *plane,gx3de_vec3 uvw,gx3de_vec3 *world);
GX3DE_API gx3de_result gx3de_plane_project_point(gx3de_plane *plane,gx3de_vec3 point,gx3de_vec3 *out);
GX3DE_API gx3de_result gx3de_plane_project_vector(gx3de_plane *plane,gx3de_vec3 vector,gx3de_vec3 *out);
GX3DE_API gx3de_result gx3de_section_create(gx3de_object *object,gx3de_plane *plane,gx3de_section **out);
GX3DE_API gx3de_result gx3de_section_count(gx3de_section *section,uint64_t *segments);
GX3DE_API gx3de_result gx3de_section_segment(gx3de_section *section,uint64_t index,gx3de_segment3 *out);
GX3DE_API gx3de_result gx3de_section_profile_segment(gx3de_section *section,uint64_t index,gx3de_segment2 *out);
GX3DE_API gx3de_result gx3de_section_destroy(gx3de_section *section);
GX3DE_API gx3de_result gx3de_section_source(gx3de_section *section,gx3de_object **source,gx3de_plane **plane);
GX3DE_API gx3de_result gx3de_section_refresh(gx3de_section *section);
GX3DE_API gx3de_result gx3de_section_style_set(gx3de_section *section,const gx3de_curve_style *style);
GX3DE_API gx3de_result gx3de_section_style_get(gx3de_section *section,gx3de_curve_style *style);
GX3DE_API gx3de_result gx3de_profile_create(gx3de_section *section,double join_tolerance,gx3de_profile **out);
/* Copy ordered contours in the working plane's U/V frame. Explicit closed=1
 * adds the closing edge; a repeated last/start point within join_tolerance is
 * accepted and removed. Open contours stay open. No point sorting, resampling,
 * axis/unit conversion or implicit Dataset publication occurs. Reject collapsed
 * edges, crossings, overlapping/touching contours and ambiguous joins before
 * retaining the profile. Up to 4096 contours and one million total points.
 * The resulting profile snapshots the plane and has no section source. */
GX3DE_API gx3de_result gx3de_profile_create_contours(gx3de_scene *scene,
    gx3de_plane *plane,const gx3de_profile_contour_spec *contours,
    uint64_t contour_count,double join_tolerance,gx3de_profile **out);
/* Exact OCCT prism along the captured plane normal. signed_distance is finite
 * and nonzero, in the asserted working coordinate unit. All contours must be
 * closed, simple and non-touching. Even containment depth means material;
 * immediate odd-depth children are holes. Multiple islands/nested islands are
 * preserved. The profile remains immutable; output placement is world identity.
 * Preview and acceptance retain this same CORE result. */
GX3DE_API gx3de_result gx3de_profile_extrude(gx3de_profile *profile,
    double signed_distance,gx3de_object **out);
/* Explicit staged export, not Dataset publication. Caller supplies a new owned
 * temporary path, then uses normal File Publication APIs. B-Rep STEP preserves
 * world placement and exact topology; mesh STL/VTP use complete world geometry,
 * not display LOD. No source or scene mutation. format: 1 binary STL, 2 VTP. */
GX3DE_API gx3de_result gx3de_brep_write_step(gx3de_object *object,const char *path_utf8,
    double millimeters_per_working_unit);
GX3DE_API gx3de_result gx3de_mesh_write_file(gx3de_object *object,uint32_t format,const char *path_utf8);
GX3DE_API gx3de_result gx3de_profile_contour_count(gx3de_profile *profile,uint64_t *out);
GX3DE_API gx3de_result gx3de_profile_contour_info(gx3de_profile *profile,uint64_t contour,gx3de_contour_info *out);
GX3DE_API gx3de_result gx3de_profile_point3(gx3de_profile *profile,uint64_t contour,uint64_t point,gx3de_vec3 *out);
GX3DE_API gx3de_result gx3de_profile_point2(gx3de_profile *profile,uint64_t contour,uint64_t point,double *u,double *v);
GX3DE_API gx3de_result gx3de_profile_frame_get(gx3de_profile *profile,gx3de_vec3 *origin,gx3de_vec3 *normal,gx3de_vec3 *u_axis);
/* Explicit coordinate-unit rescale; preserves topology and the source profile. */
GX3DE_API gx3de_result gx3de_profile_rescale(gx3de_profile *source,double factor,gx3de_profile **out);
/* Complete world-coordinate profile lines; no display reduction. */
GX3DE_API gx3de_result gx3de_profile_write_vtp(gx3de_profile *profile,const char *path_utf8);
GX3DE_API gx3de_result gx3de_profile_destroy(gx3de_profile *profile);
GX3DE_API gx3de_result gx3de_profile_source(gx3de_profile *profile,gx3de_section **section);
GX3DE_API gx3de_result gx3de_profile_refresh(gx3de_profile *profile);
GX3DE_API gx3de_result gx3de_profile_style_set(gx3de_profile *profile,const gx3de_curve_style *style);
GX3DE_API gx3de_result gx3de_profile_style_get(gx3de_profile *profile,gx3de_curve_style *style);
GX3DE_API gx3de_result gx3de_anchor_free(gx3de_scene *scene,gx3de_vec3 point,gx3de_anchor **out);
GX3DE_API gx3de_result gx3de_anchor_line(gx3de_scene *scene,gx3de_vec3 point,gx3de_vec3 direction,gx3de_anchor **out);
GX3DE_API gx3de_result gx3de_anchor_object_axis(gx3de_object *object,gx3de_vec3 local_point,gx3de_vec3 local_direction,gx3de_anchor **out);
GX3DE_API gx3de_result gx3de_anchor_object_reference(gx3de_object *object,gx3de_anchor **out);
GX3DE_API gx3de_result gx3de_anchor_object_vertex(gx3de_object *object,uint64_t vertex_index,gx3de_anchor **out);
GX3DE_API gx3de_result gx3de_anchor_object_point(gx3de_object *object,gx3de_vec3 local_point,gx3de_anchor **out);
GX3DE_API gx3de_result gx3de_anchor_object_edge(gx3de_object *object,uint32_t vertex_a,uint32_t vertex_b,double t,gx3de_anchor **out);
GX3DE_API gx3de_result gx3de_anchor_object_face(gx3de_object *object,uint64_t triangle_index,double u,double v,gx3de_anchor **out);
GX3DE_API gx3de_result gx3de_anchor_object_center(gx3de_object *object,gx3de_anchor **out);
GX3DE_API gx3de_result gx3de_anchor_get_kind(gx3de_anchor *anchor,gx3de_anchor_kind *out);
GX3DE_API gx3de_result gx3de_anchor_normal(gx3de_anchor *anchor,gx3de_vec3 *out);
GX3DE_API gx3de_result gx3de_anchor_tangent(gx3de_anchor *anchor,gx3de_vec3 *out);
GX3DE_API gx3de_result gx3de_anchor_position(gx3de_anchor *anchor,gx3de_vec3 *out);
GX3DE_API gx3de_result gx3de_anchor_destroy(gx3de_anchor *anchor);
GX3DE_API gx3de_result gx3de_marker_create_scene(gx3de_scene *scene,gx3de_anchor *anchor,const gx3de_marker_style *style,gx3de_marker **out);
GX3DE_API gx3de_result gx3de_marker_create_view(gx3de_view *view,gx3de_anchor *anchor,const gx3de_marker_style *style,gx3de_marker **out);
GX3DE_API gx3de_result gx3de_marker_style_set(gx3de_marker *marker,const gx3de_marker_style *style);
GX3DE_API gx3de_result gx3de_marker_style_get(gx3de_marker *marker,gx3de_marker_style *style);
GX3DE_API gx3de_result gx3de_marker_destroy(gx3de_marker *marker);
GX3DE_API gx3de_result gx3de_measure_create(gx3de_scene *scene,gx3de_measure_kind kind,gx3de_anchor *a,gx3de_anchor *b,gx3de_anchor *c,gx3de_plane *plane,gx3de_measurement **out);
GX3DE_API gx3de_result gx3de_measure_create_ex(gx3de_scene *scene,const gx3de_measure_spec *spec,gx3de_measurement **out);
GX3DE_API gx3de_result gx3de_measure_get_spec(gx3de_measurement *measurement,gx3de_measure_spec *out);
GX3DE_API gx3de_result gx3de_measure_evaluate(gx3de_measurement *measurement,gx3de_measure_value *out);
GX3DE_API gx3de_result gx3de_measure_destroy(gx3de_measurement *measurement);
GX3DE_API gx3de_result gx3de_measurement_style_set(gx3de_measurement *measurement,const gx3de_measurement_style *style);
GX3DE_API gx3de_result gx3de_measurement_style_get(gx3de_measurement *measurement,gx3de_measurement_style *style);
GX3DE_API gx3de_result gx3de_constraint_create(gx3de_scene *scene,const gx3de_constraint_spec *spec,gx3de_constraint **out);
GX3DE_API gx3de_result gx3de_constraint_create_ex(gx3de_scene *scene,const gx3de_constraint_spec_ex *spec,gx3de_constraint **out);
GX3DE_API gx3de_result gx3de_constraint_evaluate(gx3de_constraint *constraint,gx3de_constraint_value *out);
GX3DE_API gx3de_result gx3de_constraint_solve(gx3de_constraint *constraint,gx3de_constraint_value *out);
/* Transactionally solve 1..256 listed constraints in one scene. max_passes=0
 * selects 16; accepted range is 1..128. Other initially satisfied constraints
 * on the same moving objects are preserved. Unsupported, inconsistent or
 * unconverged systems restore all selected object transforms. */
GX3DE_API gx3de_result gx3de_constraint_system_solve(gx3de_scene *scene,gx3de_constraint *const *constraints,uint64_t constraint_count,uint32_t max_passes,gx3de_constraint_system_result *out);
GX3DE_API gx3de_result gx3de_constraint_destroy(gx3de_constraint *constraint);

GX3DE_API gx3de_result gx3de_target_create_headless(gx3de_engine *engine,uint32_t width,uint32_t height,gx3de_target **out);
/* The native window ID is an opaque integer at the C boundary. X11 uses a
 * Window XID; Win32 uses an HWND cast through uintptr_t. The caller owns it. */
GX3DE_API gx3de_result gx3de_target_create_native(gx3de_engine *engine,uint32_t window_kind,uint64_t native_window_id,uint32_t width,uint32_t height,gx3de_target **out);
GX3DE_API gx3de_result gx3de_target_destroy(gx3de_target *target);
GX3DE_API gx3de_result gx3de_get_capabilities(uint32_t api_group,gx3de_capability_set *out);
GX3DE_API gx3de_result gx3de_target_renderer_backend_set(gx3de_target *target,uint32_t backend);
GX3DE_API gx3de_result gx3de_target_renderer_info(gx3de_target *target,gx3de_renderer_device_info *out);
/* Physical render pixels and logical GUI units are separate. Resize is
 * rejected if an existing viewport would extend outside the new target. */
GX3DE_API gx3de_result gx3de_target_resize(gx3de_target *target,uint32_t physical_width,uint32_t physical_height,uint32_t logical_width,uint32_t logical_height);
GX3DE_API gx3de_result gx3de_target_geometry_get(gx3de_target *target,gx3de_target_geometry *out);
GX3DE_API gx3de_result gx3de_viewport_rect_set(gx3de_viewport *viewport,uint32_t x,uint32_t y,uint32_t width,uint32_t height);
GX3DE_API gx3de_result gx3de_target_render_quality_set(gx3de_target *target,const gx3de_render_quality *quality);
GX3DE_API gx3de_result gx3de_target_render_quality_get(gx3de_target *target,gx3de_render_quality *quality);
GX3DE_API gx3de_result gx3de_engine_graphics_policy_set(gx3de_engine *engine,const gx3de_graphics_policy *policy);
GX3DE_API gx3de_result gx3de_engine_graphics_policy_get(gx3de_engine *engine,gx3de_graphics_policy *policy);
/* Return the target's effective policy, including explicit target quality/GPU overrides. */
GX3DE_API gx3de_result gx3de_target_graphics_policy_get(gx3de_target *target,gx3de_graphics_policy *policy);
GX3DE_API gx3de_result gx3de_target_interaction_set(gx3de_target *target,uint32_t active);
GX3DE_API gx3de_result gx3de_target_render_stats_get(gx3de_target *target,gx3de_render_stats *out);
/* Estimated GPU resources include color/depth targets and per-viewport scene
 * geometry. The estimate is a conservative bound for planned uploads, not
 * measured VRAM. A nonzero budget rejects over-budget renders before backend
 * resource creation with GX3DE_RANGE and queryable diagnostics. */
GX3DE_API gx3de_result gx3de_target_gpu_budget_set(gx3de_target *target,uint64_t bytes);
GX3DE_API gx3de_result gx3de_target_render_resource_info_get(gx3de_target *target,
    gx3de_render_resource_info *out);
GX3DE_API gx3de_result gx3de_target_render(gx3de_target *target);
/* Selective presentation refresh for one already-rendered object. Reuses every
 * unrelated mapper, camera, selection and target. Scene must match its last
 * render; unsupported texture/volume/repeat presentations return UNSUPPORTED.
 * Only color/line/point sizes, visibility and opacity may change here. */
GX3DE_API gx3de_result gx3de_target_object_presentation_set(gx3de_target *target,gx3de_object *object,const gx3de_object_style *style,uint32_t visible,double opacity);

/* Last render startup/result diagnostics, including backend capability text
 * after success. For requested OpenGL MSAA, diagnostics distinguish effective
 * VTK render-FBO samples from host/default framebuffer samples; the latter
 * need not be multisampled for a Native X11 target. Query required_bytes with
 * capacity zero. */
GX3DE_API gx3de_result gx3de_target_render_diagnostics(gx3de_target *target,char *buffer,uint64_t capacity,uint64_t *required_bytes);
/* Pixels are tightly packed top-left-first RGBA8. Query with capacity zero.
 * Render must succeed first; the pixels are target-local and overwritten by
 * the next render; any failed render invalidates the prior pixels. A short
 * buffer returns GX3DE_RANGE and required_bytes. */
GX3DE_API gx3de_result gx3de_target_read_rgba(gx3de_target *target,uint8_t *pixels,uint64_t capacity,uint64_t *required_bytes);
GX3DE_API gx3de_result gx3de_target_write_png(gx3de_target *target,const char *path_utf8);
GX3DE_API gx3de_result gx3de_view_render_rgba(gx3de_view *view,uint32_t width,uint32_t height,uint8_t *pixels,uint64_t capacity,uint64_t *required_bytes);
/* Render at factor times the requested physical resolution and box-filter to
 * RGBA8. factor is 1..4; both intermediate and output obey the 256 MiB pixel
 * budget. A zero-capacity query returns output bytes without rendering. */
GX3DE_API gx3de_result gx3de_view_render_rgba_supersampled(gx3de_view *view,uint32_t width,uint32_t height,uint32_t factor,uint8_t *pixels,uint64_t capacity,uint64_t *required_bytes);
GX3DE_API gx3de_result gx3de_view_write_png(gx3de_view *view,uint32_t width,uint32_t height,const char *path_utf8);
GX3DE_API gx3de_result gx3de_view_write_png_supersampled(gx3de_view *view,uint32_t width,uint32_t height,uint32_t factor,const char *path_utf8);
GX3DE_API gx3de_result gx3de_view_create(gx3de_scene *scene,gx3de_view **out);
/* Borrowed owner handle for cross-scene validation; no ownership transfer. */
GX3DE_API gx3de_result gx3de_view_scene_get(gx3de_view *view,gx3de_scene **scene);
GX3DE_API gx3de_result gx3de_view_destroy(gx3de_view *view);
GX3DE_API gx3de_result gx3de_view_set_camera(gx3de_view *view,const gx3de_camera *camera);
GX3DE_API gx3de_result gx3de_view_get_camera(gx3de_view *view,gx3de_camera *camera);
GX3DE_API gx3de_result gx3de_view_camera_preset(gx3de_view *view,uint32_t preset,gx3de_object *fit_object);
/* Explicit orthographic world-space height. Zero before first set retains the
 * legacy height derived from camera distance and vertical FOV. */
GX3DE_API gx3de_result gx3de_view_orthographic_height_set(gx3de_view *view,double height);
GX3DE_API gx3de_result gx3de_view_orthographic_height_get(gx3de_view *view,double *height);
GX3DE_API gx3de_result gx3de_view_camera_orbit(gx3de_view *view,double yaw_radians,double pitch_radians,const gx3de_vec3 *pivot);
GX3DE_API gx3de_result gx3de_view_camera_pan(gx3de_viewport *viewport,double dx_pixels,double dy_pixels);
GX3DE_API gx3de_result gx3de_view_camera_dolly(gx3de_view *view,double factor);
GX3DE_API gx3de_result gx3de_view_camera_zoom(gx3de_view *view,double factor);
/* Viewport-local top-left physical pixel coordinates; depth is signed world
 * distance along the camera forward axis, positive in front of camera. */
GX3DE_API gx3de_result gx3de_viewport_world_to_screen(gx3de_viewport *viewport,gx3de_vec3 world,double *x,double *y,double *depth);
GX3DE_API gx3de_result gx3de_viewport_screen_to_world(gx3de_viewport *viewport,double x,double y,double depth,gx3de_vec3 *world);
GX3DE_API gx3de_result gx3de_view_background_set(gx3de_view *view,const gx3de_view_background *background);
GX3DE_API gx3de_result gx3de_view_background_get(gx3de_view *view,gx3de_view_background *background);
GX3DE_API gx3de_result gx3de_view_checkerboard_set(gx3de_view *view,const gx3de_checkerboard_background *checkerboard);
GX3DE_API gx3de_result gx3de_view_checkerboard_get(gx3de_view *view,gx3de_checkerboard_background *checkerboard);
GX3DE_API gx3de_result gx3de_view_navcube_set(gx3de_view *view,const gx3de_navcube_state *state);
GX3DE_API gx3de_result gx3de_view_orientation_indicator_set(gx3de_view *view,const gx3de_orientation_indicator *state);
GX3DE_API gx3de_result gx3de_view_orientation_indicator_get(gx3de_view *view,gx3de_orientation_indicator *state);
GX3DE_API gx3de_result gx3de_view_navcube_get(gx3de_view *view,gx3de_navcube_state *state);
GX3DE_API gx3de_result gx3de_viewport_navcube_pick(gx3de_viewport *viewport,uint32_t x,uint32_t y,uint32_t *region);
GX3DE_API gx3de_result gx3de_view_navcube_hover_set(gx3de_view *view,uint32_t region);
GX3DE_API gx3de_result gx3de_view_navcube_select(gx3de_view *view,uint32_t region);
GX3DE_API gx3de_result gx3de_viewport_navcube_click(gx3de_viewport *viewport,uint32_t x,uint32_t y,uint32_t *region);
GX3DE_API gx3de_result gx3de_view_lighting_set(gx3de_view *view,const gx3de_view_lighting *lighting);
GX3DE_API gx3de_result gx3de_view_lighting_get(gx3de_view *view,gx3de_view_lighting *lighting);
GX3DE_API gx3de_result gx3de_view_positional_light_set(gx3de_view *view,uint32_t slot,const gx3de_positional_light *light);
GX3DE_API gx3de_result gx3de_view_positional_light_get(gx3de_view *view,uint32_t slot,gx3de_positional_light *light);
GX3DE_API gx3de_result gx3de_scientific_light_create(gx3de_scene *scene,const gx3de_scientific_light_spec *spec,gx3de_scientific_light **out);
GX3DE_API gx3de_result gx3de_scientific_light_set(gx3de_scientific_light *light,const gx3de_scientific_light_spec *spec);
GX3DE_API gx3de_result gx3de_scientific_light_get(gx3de_scientific_light *light,gx3de_scientific_light_spec *spec);
GX3DE_API gx3de_result gx3de_scientific_light_destroy(gx3de_scientific_light *light);
GX3DE_API gx3de_result gx3de_scientific_light_count(gx3de_scene *scene,uint32_t *count);
GX3DE_API gx3de_result gx3de_scientific_light_frequency_hz(gx3de_scientific_light *light,double *frequency_hz);
GX3DE_API gx3de_result gx3de_scientific_light_display_rgb(gx3de_scientific_light *light,gx3de_rgb *rgb);
GX3DE_API gx3de_result gx3de_scientific_light_beam_sample(gx3de_scientific_light *light,double distance,gx3de_scientific_beam_sample *sample);
GX3DE_API gx3de_result gx3de_view_clip_box_set(gx3de_view *view,const gx3de_view_clip_box *clip_box);
GX3DE_API gx3de_result gx3de_view_clip_box_get(gx3de_view *view,gx3de_view_clip_box *clip_box);
GX3DE_API gx3de_result gx3de_view_set_working_plane(gx3de_view *view,gx3de_plane *plane);
GX3DE_API gx3de_result gx3de_view_get_working_plane(gx3de_view *view,gx3de_plane **plane);
GX3DE_API gx3de_result gx3de_view_set_selection(gx3de_view *view,gx3de_anchor *anchor);
GX3DE_API gx3de_result gx3de_view_get_selection(gx3de_view *view,gx3de_anchor **anchor);
GX3DE_API gx3de_result gx3de_view_clip_plane_set(gx3de_view *view,uint32_t slot,const gx3de_view_clip_plane *clip);
GX3DE_API gx3de_result gx3de_view_clip_plane_get(gx3de_view *view,uint32_t slot,gx3de_view_clip_plane *clip);
GX3DE_API gx3de_result gx3de_view_interaction_set(gx3de_view *view,const gx3de_view_interaction *interaction);
GX3DE_API gx3de_result gx3de_view_interaction_get(gx3de_view *view,gx3de_view_interaction *interaction);
GX3DE_API gx3de_result gx3de_view_axes_set(gx3de_view *view,const gx3de_view_axes *axes);
GX3DE_API gx3de_result gx3de_view_axes_get(gx3de_view *view,gx3de_view_axes *axes);
GX3DE_API gx3de_result gx3de_gizmo_create(gx3de_view *view,const gx3de_gizmo_spec *spec,gx3de_gizmo **out);
GX3DE_API gx3de_result gx3de_gizmo_destroy(gx3de_gizmo *gizmo);
GX3DE_API gx3de_result gx3de_gizmo_set(gx3de_gizmo *gizmo,const gx3de_gizmo_spec *spec);
GX3DE_API gx3de_result gx3de_gizmo_get(gx3de_gizmo *gizmo,gx3de_gizmo_spec *spec);
GX3DE_API gx3de_result gx3de_gizmo_hover_set(gx3de_gizmo *gizmo,uint32_t handle);
/* Ray operations contain the drag math and do not require a render target.
 * Screen operations use top-left viewport-local pixels. begin snapshots all
 * scene poses; update is relative to that snapshot and solves every scene
 * constraint referencing the dragged object. With preview_only=0, update
 * temporarily applies the solved pose for live render; end(0) restores every
 * snapshot and end(1) commits. With preview_only=1, update returns the
 * proposed pose but restores the scene before returning; end never commits.
 * Unsupported, incompatible and unsolved constraints roll back atomically.
 * Local mode requires an orthogonal object frame; sheared frames are rejected. */
GX3DE_API gx3de_result gx3de_gizmo_begin(gx3de_gizmo *gizmo,uint32_t handle,const gx3de_ray *ray);
GX3DE_API gx3de_result gx3de_gizmo_update(gx3de_gizmo *gizmo,const gx3de_ray *ray,gx3de_gizmo_result *out);
GX3DE_API gx3de_result gx3de_gizmo_end(gx3de_gizmo *gizmo,uint32_t accept);
GX3DE_API gx3de_result gx3de_viewport_ray(gx3de_viewport *viewport,uint32_t x,uint32_t y,gx3de_ray *out);
/* Begin/update/end use public viewport rays and the camera-facing drag plane.
 * Updates are relative to the begin snapshot; end(0) rolls back. For clip
 * boxes, the six face handles move one face along its normal. */
GX3DE_API gx3de_result gx3de_view_manipulation_begin(gx3de_viewport *viewport,uint32_t target,uint32_t slot,
    uint32_t action,uint32_t handle,uint32_t x,uint32_t y,gx3de_view_manipulation **out);
GX3DE_API gx3de_result gx3de_view_manipulation_update(gx3de_view_manipulation *manipulation,uint32_t x,uint32_t y,
    gx3de_view_manipulation_result *out);
GX3DE_API gx3de_result gx3de_view_manipulation_end(gx3de_view_manipulation *manipulation,uint32_t accept);
GX3DE_API gx3de_result gx3de_gizmo_pick(gx3de_viewport *viewport,uint32_t x,uint32_t y,gx3de_gizmo **gizmo,uint32_t *handle);
GX3DE_API gx3de_result gx3de_gizmo_begin_screen(gx3de_gizmo *gizmo,gx3de_viewport *viewport,uint32_t handle,uint32_t x,uint32_t y);
GX3DE_API gx3de_result gx3de_gizmo_update_screen(gx3de_gizmo *gizmo,gx3de_viewport *viewport,uint32_t x,uint32_t y,gx3de_gizmo_result *out);
GX3DE_API gx3de_result gx3de_viewport_create(gx3de_target *target,gx3de_view *view,uint32_t x,uint32_t y,uint32_t width,uint32_t height,gx3de_viewport **out);
GX3DE_API gx3de_result gx3de_viewport_destroy(gx3de_viewport *viewport);
GX3DE_API gx3de_result gx3de_viewport_size(gx3de_viewport *viewport,uint32_t *x,uint32_t *y,uint32_t *width,uint32_t *height);
/* x/y are local top-left viewport pixel coordinates. Picking renders the
 * current scene before hit testing. Cell/point IDs identify only this render.
 * Use pick_make_anchor for a persistent mesh face or object-local point. */
GX3DE_API gx3de_result gx3de_viewport_pick(gx3de_viewport *viewport,uint32_t x,uint32_t y,gx3de_pick_hit *hit);
GX3DE_API gx3de_result gx3de_pick_make_anchor(gx3de_viewport *viewport,const gx3de_pick_hit *hit,gx3de_anchor **out);
#ifdef __cplusplus
}
#endif
#endif
