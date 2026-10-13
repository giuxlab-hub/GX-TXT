/* Generic Native 3D field tracing. Public C ABI; no VTK or window types. */
#ifndef NATIVE_3D_FIELD_API_V1_H
#define NATIVE_3D_FIELD_API_V1_H
#include "native_3d_engine_api_v1.h"
#ifdef __cplusplus
extern "C" {
#endif
#define GX3DE_FIELD_API_VERSION 1u
/* GX3DE_API_GROUP_FIELD, capability word zero. */
#define GX3DE_FIELD_CAP_LINES (1ull<<0)
#define GX3DE_FIELD_CAP_SLICE (1ull<<1)
#define GX3DE_FIELD_CAP_VOLUME_TRANSFER (1ull<<2)
#define GX3DE_FIELD_CAP_PATHLINES (1ull<<3)
#define GX3DE_FIELD_CAP_UNSTRUCTURED (1ull<<4)
typedef struct gx3de_field_source_info {
    uint32_t struct_size;
    uint32_t scientific_kind;
    uint64_t supported_cells,unsupported_cells;
    uint32_t first_unsupported_cell_type; /* 0 when all cells are supported */
    uint32_t reserved32;
    uint64_t reserved[4];
} gx3de_field_source_info;
/* Reports interpolation support without reading or changing source arrays. */
GX3DE_API gx3de_result gx3de_field_source_info_get(gx3de_object *field,gx3de_field_source_info *out);
typedef enum gx3de_field_seed_kind {
    GX3DE_FIELD_SEED_POINTS=1, GX3DE_FIELD_SEED_LINE=2,
    GX3DE_FIELD_SEED_PLANE=3
} gx3de_field_seed_kind;
typedef enum gx3de_field_direction {
    GX3DE_FIELD_FORWARD=1, GX3DE_FIELD_BACKWARD=2,
    GX3DE_FIELD_BOTH=3
} gx3de_field_direction;
typedef struct gx3de_field_line_spec {
    uint32_t struct_size;
    uint32_t seed_kind; /* gx3de_field_seed_kind; seed positions are field-local */
    gx3de_object *field; /* immutable image or tetra/hexa unstructured field */
    uint64_t vector_array; /* point-associated 3-component array */
    int64_t scalar_array; /* point-associated scalar array, -1 disables */
    const gx3de_vec3 *seed_points;
    uint64_t seed_count; /* POINTS: count, LINE/PLANE: ignored */
    gx3de_vec3 seed_origin,seed_u,seed_v;
    uint32_t seed_u_count,seed_v_count; /* LINE uses u count, PLANE uses both */
    uint32_t direction; /* gx3de_field_direction */
    uint32_t reserved32;
    double step_size; /* local distance per normalized-vector RK4 step */
    double min_vector_magnitude; /* below this, line terminates */
    double tube_radius; /* 0: line; >0: rendered tube */
    uint64_t max_steps_per_direction; /* 1..100000 */
    uint64_t max_output_points; /* 2..1000000 */
    uint64_t max_memory_bytes; /* temporary grid + output, at most 512 MiB */
    uint64_t reserved[4];
} gx3de_field_line_spec;
typedef struct gx3de_field_line_info {
    uint32_t struct_size;
    uint32_t reserved32;
    uint64_t requested_seeds,created_lines,output_points;
    uint64_t boundary_stops,low_magnitude_stops,step_limit_stops;
    uint64_t reserved[4];
} gx3de_field_line_info;
/* Creates a queryable scientific polyline object in the field scene. Derived
 * points are immutable and parented to the source field for hierarchy pose;
 * regenerate when field data or seeds change. No partial object is published
 * on budget or input failure. */
GX3DE_API gx3de_result gx3de_field_lines_create(gx3de_scene *scene,
                                                 const gx3de_field_line_spec *spec,
                                                 gx3de_object **out_lines,
                                                 gx3de_field_line_info *out_info);
typedef struct gx3de_field_slice_spec {
    uint32_t struct_size,reserved32;
    gx3de_object *field; /* immutable structured image scalar field */
    uint64_t scalar_array; /* point-associated scalar array */
    gx3de_vec3 origin,u_step,v_step; /* field-local grid-plane samples */
    uint32_t u_count,v_count; /* 2..1024 each, at most 1M points */
    uint64_t max_memory_bytes; /* input + output, at most 512 MiB */
    uint64_t reserved[4];
} gx3de_field_slice_spec;
/* A fully in-domain slice, sampled bilinearly/trilinearly from the supplied
 * grid, returned as an ordinary scalar-colored scientific triangle surface.
 * Out-of-domain samples reject the entire slice, with no partial publication. */
GX3DE_API gx3de_result gx3de_field_slice_create(gx3de_scene *scene,
                                                 const gx3de_field_slice_spec *spec,
                                                 gx3de_object **out_slice);
/* Loader returns a fresh image or unstructured vector field owned by the pathline call;
 * source objects in frames[] are borrowed instead. Wrong-scene objects are
 * rejected and remain caller-owned. At most two grids are resident at a
 * time, and loader objects are released after copying arrays. */
typedef gx3de_result (*gx3de_field_frame_loader)(gx3de_scene *scene,uint64_t frame_index,
                                                  double time_value,void *user,
                                                  gx3de_object **out_field);
typedef struct gx3de_field_pathline_spec {
    uint32_t struct_size,reserved32;
    const double *times; /* strictly increasing, at least two samples */
    const gx3de_object *const *frames; /* optional; each entry may be NULL if loader is set */
    uint64_t frame_count;
    gx3de_field_frame_loader loader;
    void *loader_user;
    uint64_t vector_array; /* point-associated 3-component */
    int64_t scalar_array; /* point-associated 1-component, -1 disables */
    const gx3de_vec3 *seed_points; /* local coordinates; seed at times[0] */
    uint64_t seed_count;
    double time_step; /* positive maximum integration interval */
    double min_vector_magnitude; /* stop when below this threshold */
    double tube_radius;
    uint64_t max_steps_per_seed,max_output_points,max_memory_bytes;
    uint64_t reserved[4];
} gx3de_field_pathline_spec;
typedef struct gx3de_field_pathline_info {
    uint32_t struct_size,reserved32;
    uint64_t requested_seeds,created_lines,output_points;
    uint64_t boundary_stops,low_magnitude_stops,step_limit_stops;
    uint64_t loaded_frames; /* loader calls; static frames do not count */
    uint64_t reserved[4];
} gx3de_field_pathline_info;
/* Pathline coordinates satisfy dx/dt = v(x,t), unlike stationary streamlines.
 * Time interpolation is linear between immutable input vector samples.
 * Output has point array "field_scalar" if supplied and "time_value". */
GX3DE_API gx3de_result gx3de_field_pathlines_create(gx3de_scene *scene,
                                                     const gx3de_field_pathline_spec *spec,
                                                     gx3de_object **out_lines,
                                                     gx3de_field_pathline_info *out_info);
typedef struct gx3de_field_transfer_point {
    double scalar,red,green,blue,opacity;
} gx3de_field_transfer_point;
#define GX3DE_MAX_FIELD_TRANSFER_POINTS 16u
typedef struct gx3de_field_volume_style {
    uint32_t struct_size,enabled;
    uint64_t scalar_array; /* point scalar on VTI/image object */
    double sample_distance; /* >0 world units between ray samples */
    uint32_t transfer_count,reserved32;
    gx3de_field_transfer_point transfer[GX3DE_MAX_FIELD_TRANSFER_POINTS];
    uint64_t reserved[4];
} gx3de_field_volume_style;
/* Rendering presentation state only; the image array remains immutable.
 * Isosurfaces, slices, clouds, and volume can coexist as separate layers. */
GX3DE_API gx3de_result gx3de_field_volume_style_set(gx3de_object *image,
                                                     const gx3de_field_volume_style *style);
GX3DE_API gx3de_result gx3de_field_volume_style_get(gx3de_object *image,
                                                     gx3de_field_volume_style *style);
#ifdef __cplusplus
}
#endif
#endif
