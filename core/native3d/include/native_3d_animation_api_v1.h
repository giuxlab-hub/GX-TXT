/* Native 3D Animation API v1: deterministic scientific frames. */
#ifndef NATIVE_3D_ANIMATION_API_V1_H
#define NATIVE_3D_ANIMATION_API_V1_H
#include "native_3d_engine_api_v1.h"
#include "native_3d_field_api_v1.h"
#ifdef __cplusplus
extern "C" {
#endif
#define GX3DE_ANIMATION_API_VERSION 1u
/* GX3DE_API_GROUP_ANIMATION, capability word zero. */
#define GX3DE_ANIM_CAP_TIMELINE (1ull<<0)
#define GX3DE_ANIM_CAP_LAZY_FRAMES (1ull<<1)
#define GX3DE_ANIM_CAP_PNG_SEQUENCE (1ull<<2)
#define GX3DE_ANIM_CAP_MULTILAYER (1ull<<3)
#define GX3DE_ANIM_CAP_DERIVED_FIELD (1ull<<4)
typedef struct gx3de_animation gx3de_animation;
typedef struct gx3de_animation_layer gx3de_animation_layer;
typedef enum gx3de_animation_interpolation {
    GX3DE_ANIM_NEAREST=1,GX3DE_ANIM_LINEAR=2
} gx3de_animation_interpolation;
typedef enum gx3de_animation_loop {
    GX3DE_ANIM_ONCE=1,GX3DE_ANIM_LOOP=2,GX3DE_ANIM_PING_PONG=3
} gx3de_animation_loop;
typedef enum gx3de_animation_state {
    GX3DE_ANIM_STOPPED=1,GX3DE_ANIM_PAUSED=2,GX3DE_ANIM_PLAYING=3
} gx3de_animation_state;
/* Loader creates a fresh scientific/mesh object in scene. Any non-NULL
 * returned object in that scene is handed to the timeline for cleanup even on
 * failure. A wrong-scene object is rejected and remains caller-owned.
 * It may run synchronously on the caller thread;
 * it must not destroy the scene/timeline or recursively seek. */
typedef gx3de_result (*gx3de_animation_frame_loader)(gx3de_scene *scene,uint64_t frame_index,
                                                       double time_value,void *user,
                                                       gx3de_object **out_object);
typedef struct gx3de_animation_info {
    uint32_t struct_size;
    uint32_t state;
    uint32_t interpolation;
    uint32_t loop_mode;
    uint64_t frame_count,current_frame,resident_frames,max_resident_frames;
    double current_time,start_time,end_time,playback_rate;
    uint64_t resident_estimated_bytes,max_resident_bytes;
    uint64_t reserved[4];
} gx3de_animation_info;
/* Timeline lifetime is nested in scene lifetime. Referenced external objects
 * must outlive timeline. Destroy timeline before scene. Unit is UTF-8 text.
 * No wall-clock or event loop is required; advance() takes caller elapsed time. */
GX3DE_API gx3de_result gx3de_animation_create(gx3de_scene *scene,const char *time_unit_utf8,gx3de_animation **out);
GX3DE_API gx3de_result gx3de_animation_destroy(gx3de_animation *timeline);
/* Times must be strictly increasing; source object is borrowed. A NULL source
 * requires a loader. Lazy loaded objects are timeline-owned and LRU-evicted. */
GX3DE_API gx3de_result gx3de_animation_frame_add(gx3de_animation *timeline,double time_value,
            gx3de_object *source_object,gx3de_animation_frame_loader loader,void *loader_user,uint64_t *frame_index);
/* A time-only frame supports timelines whose content lives in named layers. */
GX3DE_API gx3de_result gx3de_animation_time_add(gx3de_animation *timeline,double time_value,uint64_t *frame_index);
/* UTF-8 layer IDs are stable logical identities. Sources can be supplied or
 * loaded lazily; borrowed sources must outlive the timeline. Frame slots can
 * be sparse. All sources remain immutable. */
GX3DE_API gx3de_result gx3de_animation_layer_create(gx3de_animation *timeline,const char *id_utf8,gx3de_animation_layer **out);
GX3DE_API gx3de_result gx3de_animation_layer_id(gx3de_animation_layer *layer,char *buffer,uint64_t capacity,uint64_t *required_bytes);
GX3DE_API gx3de_result gx3de_animation_layer_frame_set(gx3de_animation_layer *layer,uint64_t frame_index,
            gx3de_object *source_object,gx3de_animation_frame_loader loader,void *loader_user);
GX3DE_API gx3de_result gx3de_animation_layer_active_object_get(gx3de_animation_layer *layer,gx3de_object **out);
/* Native derived layers rebuild on active frame changes. Their source layer
 * must precede them; seed arrays are copied when the binding is set. */
GX3DE_API gx3de_result gx3de_animation_layer_bind_lines(gx3de_animation_layer *layer,
            gx3de_animation_layer *source,const gx3de_field_line_spec *spec);
GX3DE_API gx3de_result gx3de_animation_layer_bind_slice(gx3de_animation_layer *layer,
            gx3de_animation_layer *source,const gx3de_field_slice_spec *spec);
GX3DE_API gx3de_result gx3de_animation_layer_bind_isosurface(gx3de_animation_layer *layer,
            gx3de_animation_layer *source,const char *scalar_name_utf8,double value);
/* Bind pathlines to successive source-track frames. At active frame i the
 * derived object contains the trajectory through samples [0,i]; frame zero
 * intentionally has no line. The source track must provide every frame.
 * The binding copies seeds and integration settings; times and source frames
 * come from the parent timeline. Derived objects participate in normal LRU,
 * resident-frame and estimated-memory limits. */
GX3DE_API gx3de_result gx3de_animation_layer_bind_pathlines(gx3de_animation_layer *layer,
            gx3de_animation_layer *source,const gx3de_field_pathline_spec *spec);
GX3DE_API gx3de_result gx3de_animation_set_resident_limit(gx3de_animation *timeline,uint64_t max_frames);
GX3DE_API gx3de_result gx3de_animation_set_memory_limit(gx3de_animation *timeline,uint64_t max_bytes);
GX3DE_API gx3de_result gx3de_animation_mode_set(gx3de_animation *timeline,uint32_t interpolation,uint32_t loop_mode,double playback_rate);
/* Inclusive playback frame range. Explicit seek/render may still address all
 * frames; play, stop, step and advance use this sub-range. */
GX3DE_API gx3de_result gx3de_animation_playback_range_set(gx3de_animation *timeline,uint64_t first_frame,uint64_t last_frame);
GX3DE_API gx3de_result gx3de_animation_playback_range_get(gx3de_animation *timeline,uint64_t *first_frame,uint64_t *last_frame);
GX3DE_API gx3de_result gx3de_animation_info_get(gx3de_animation *timeline,gx3de_animation_info *out);
GX3DE_API gx3de_result gx3de_animation_time_unit(gx3de_animation *timeline,char *buffer,uint64_t capacity,uint64_t *required_bytes);
GX3DE_API gx3de_result gx3de_animation_frame_time(gx3de_animation *timeline,uint64_t index,double *time_value);
/* Borrowed current source for inspection/provenance; may change on seek and
 * must never be retained across a seek or timeline destruction. */
GX3DE_API gx3de_result gx3de_animation_active_object_get(gx3de_animation *timeline,gx3de_object **out);
/* A keyed object track controls local pose, visibility and opacity. Each key
 * belongs to one frame; linear policy interpolates opacity/translation only
 * when adjacent rotation/scale matrices match. Visibility remains discrete. */
GX3DE_API gx3de_result gx3de_animation_object_key_set(gx3de_animation *timeline,uint64_t frame_index,
            gx3de_object *object,const gx3de_mat4 *local_pose,uint32_t visible,double opacity);
GX3DE_API gx3de_result gx3de_animation_camera_key_set(gx3de_animation *timeline,uint64_t frame_index,
            gx3de_view *view,const gx3de_camera *camera);
GX3DE_API gx3de_result gx3de_animation_seek_frame(gx3de_animation *timeline,uint64_t index);
GX3DE_API gx3de_result gx3de_animation_seek_time(gx3de_animation *timeline,double time_value);
GX3DE_API gx3de_result gx3de_animation_play(gx3de_animation *timeline);
GX3DE_API gx3de_result gx3de_animation_pause(gx3de_animation *timeline);
GX3DE_API gx3de_result gx3de_animation_stop(gx3de_animation *timeline);
GX3DE_API gx3de_result gx3de_animation_step(gx3de_animation *timeline,int32_t direction);
GX3DE_API gx3de_result gx3de_animation_advance(gx3de_animation *timeline,double elapsed_seconds);
/* Sets a cancellation flag checked before/after a lazy loader and between
 * sequence frames. A blocking loader must implement its own finer cancellation. */
GX3DE_API gx3de_result gx3de_animation_cancel(gx3de_animation *timeline);
GX3DE_API gx3de_result gx3de_animation_reset_cancel(gx3de_animation *timeline);
/* Safe to call from a synchronous frame loader to cooperate with cancellation. */
GX3DE_API gx3de_result gx3de_animation_cancel_requested(gx3de_animation *timeline,uint32_t *requested);
/* Seeks exactly before ordinary explicit-resolution rendering. PNG sequence
 * names are prefix + zero-padded 6-digit frame index + ".png". Caller owns
 * target directory. On failure, subsequent frames are not attempted. */
GX3DE_API gx3de_result gx3de_animation_render_frame_rgba(gx3de_animation *timeline,gx3de_view *view,
            uint64_t frame_index,uint32_t width,uint32_t height,uint8_t *pixels,uint64_t capacity,uint64_t *required_bytes);
GX3DE_API gx3de_result gx3de_animation_render_frame_png(gx3de_animation *timeline,gx3de_view *view,
            uint64_t frame_index,uint32_t width,uint32_t height,const char *path_utf8);
GX3DE_API gx3de_result gx3de_animation_write_png_sequence(gx3de_animation *timeline,gx3de_view *view,
            uint64_t first_frame,uint64_t frame_count,uint32_t width,uint32_t height,const char *prefix_utf8);
#ifdef __cplusplus
}
#endif
#endif
