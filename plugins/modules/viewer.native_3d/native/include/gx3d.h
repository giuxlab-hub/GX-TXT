/* SPDX-License-Identifier: GPL-3.0-or-later
 * Stable C ABI for the GX-TXT native 3D engine.
 */
#ifndef GX3D_H
#define GX3D_H
#include <stddef.h>
#include <stdint.h>
#ifdef _WIN32
# ifdef GX3D_BUILD
#  define GX3D_API __declspec(dllexport)
# else
#  define GX3D_API __declspec(dllimport)
# endif
#else
# define GX3D_API __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif

#define GX3D_ABI_VERSION 1u

typedef struct gx3d_context gx3d_context;
typedef struct gx3d_job gx3d_job;
typedef struct gx3d_model gx3d_model;
typedef struct gx3d_view gx3d_view;

typedef enum gx3d_result {
    GX3D_OK = 0, GX3D_E_INVALID = 1, GX3D_E_IO = 2, GX3D_E_FORMAT = 3,
    GX3D_E_CANCELLED = 4, GX3D_E_NOT_READY = 5, GX3D_E_UNSUPPORTED = 6,
    GX3D_E_INTERNAL = 100
} gx3d_result;

typedef enum gx3d_lod {
    GX3D_LOD_PREVIEW = 0, GX3D_LOD_LOW = 1, GX3D_LOD_MEDIUM = 2,
    GX3D_LOD_HIGH = 3, GX3D_LOD_FULL = 4, GX3D_LOD_AUTO = 5
} gx3d_lod;

typedef enum gx3d_projection { GX3D_PERSPECTIVE = 0, GX3D_ORTHOGRAPHIC = 1 } gx3d_projection;
typedef enum gx3d_display_mode { GX3D_SURFACE = 0, GX3D_WIREFRAME = 1, GX3D_SURFACE_EDGES = 2 } gx3d_display_mode;

typedef struct gx3d_import_options {
    uint32_t struct_size;
    double step_linear_deflection;
    double step_angular_deflection_rad;
    uint64_t interactive_triangle_budget;
    uint64_t memory_budget_bytes;
    uint32_t generate_lod_mask;
    uint32_t flags;
} gx3d_import_options;

typedef struct gx3d_event {
    uint32_t struct_size;
    uint32_t type;
    uint64_t sequence;
    double progress_0_1;
    uint64_t triangles;
    uint64_t bytes;
    double elapsed_seconds;
    char message_utf8[512];
} gx3d_event;

enum {
    GX3D_EVENT_PROGRESS = 1,
    GX3D_EVENT_PREVIEW_READY = 2,
    GX3D_EVENT_COMPLETE = 3,
    GX3D_EVENT_ERROR = 4
};

typedef struct gx3d_camera {
    double position[3], target[3], up[3];
    double parallel_scale, view_angle_deg;
    gx3d_projection projection;
} gx3d_camera;

typedef struct gx3d_pick_result {
    uint32_t struct_size;
    int hit;
    uint64_t object_id, cell_id, point_id;
    double world[3];
} gx3d_pick_result;

GX3D_API uint32_t gx3d_abi_version(void);
GX3D_API const char *gx3d_version_utf8(void);
GX3D_API gx3d_result gx3d_context_create(gx3d_context **out_context);
GX3D_API void gx3d_context_destroy(gx3d_context *context);
GX3D_API const char *gx3d_last_error_utf8(gx3d_context *context);

/* Long operations return immediately. Events are polled; no callback enters Tcl from a worker thread. */
GX3D_API gx3d_result gx3d_import_start(gx3d_context *context, const char *source_utf8,
    const char *cache_root_utf8, const gx3d_import_options *options, gx3d_job **out_job);
GX3D_API gx3d_result gx3d_job_cancel(gx3d_job *job);
GX3D_API gx3d_result gx3d_job_poll(gx3d_job *job, gx3d_event *event_out);
GX3D_API gx3d_result gx3d_job_get_model(gx3d_job *job, gx3d_model **out_model);
GX3D_API void gx3d_job_destroy(gx3d_job *job);

GX3D_API gx3d_result gx3d_cache_open(gx3d_context *context, const char *cache_manifest_utf8, gx3d_model **out_model);
GX3D_API void gx3d_model_destroy(gx3d_model *model);
GX3D_API gx3d_result gx3d_model_set_lod(gx3d_model *model, gx3d_lod lod);
GX3D_API gx3d_result gx3d_model_get_lod(gx3d_model *model, gx3d_lod *lod_out);

GX3D_API gx3d_result gx3d_view_create(gx3d_context *context, gx3d_model *model, gx3d_view **out_view);
GX3D_API void gx3d_view_destroy(gx3d_view *view);
GX3D_API gx3d_result gx3d_view_show(gx3d_view *view);
GX3D_API gx3d_result gx3d_view_focus(gx3d_view *view);
GX3D_API gx3d_result gx3d_view_set_camera(gx3d_view *view, const gx3d_camera *camera);
GX3D_API gx3d_result gx3d_view_get_camera(gx3d_view *view, gx3d_camera *camera_out);
GX3D_API gx3d_result gx3d_view_fit(gx3d_view *view);
GX3D_API gx3d_result gx3d_view_set_preset(gx3d_view *view, const char *preset_utf8);
GX3D_API gx3d_result gx3d_view_set_display_mode(gx3d_view *view, gx3d_display_mode mode);
GX3D_API gx3d_result gx3d_view_set_background(gx3d_view *view, float r, float g, float b);
GX3D_API gx3d_result gx3d_view_pick(gx3d_view *view, int x_px, int y_px, gx3d_pick_result *out_pick);

#ifdef __cplusplus
}
#endif
#endif
