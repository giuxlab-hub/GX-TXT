// SPDX-License-Identifier: GPL-3.0-or-later
// Additive, view-owned scientific presentation; no geometry/data mutation.
#ifndef GX3DE_SCIENTIFIC_FIGURE_API_V1_H
#define GX3DE_SCIENTIFIC_FIGURE_API_V1_H
#include "native_3d_engine_api_v1.h"
#ifdef __cplusplus
extern "C" {
#endif
typedef struct gx3de_scientific_figure {
    uint32_t struct_size, enabled, axes_grid_visible, colorbar_visible;
    gx3de_bounds world_bounds;
    double axis_min[3], axis_max[3];
    // Linear increasing calibration only; mapping applied by scientific client.
    char axis_labels_utf8[3][256];
    char title_utf8[1024], legend_utf8[1024], scalar_label_utf8[256];
    double scalar_min, scalar_max;
    uint32_t palette_count;
    gx3de_rgb palette[256];
} gx3de_scientific_figure;
GX3DE_API gx3de_result gx3de_view_scientific_figure_set(gx3de_view*,const gx3de_scientific_figure*);
GX3DE_API gx3de_result gx3de_view_scientific_figure_get(gx3de_view*,gx3de_scientific_figure*);
/* Export the current native target using the same VTK scene/camera. */
GX3DE_API gx3de_result gx3de_view_scientific_style_set(gx3de_view*,const char* key,double value);
GX3DE_API gx3de_result gx3de_view_scientific_axis_labels_set(gx3de_view*,uint32_t axis,const char*const* labels,uint32_t count);
GX3DE_API gx3de_result gx3de_target_write_vector(gx3de_target*,const char* path,const char* format);
GX3DE_API gx3de_result gx3de_view_camera_roll(gx3de_view*,double radians);
#ifdef __cplusplus
}
#endif
#endif
