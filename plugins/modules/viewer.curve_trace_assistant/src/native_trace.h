#ifndef GX_NATIVE_TRACE_H
#define GX_NATIVE_TRACE_H

#include <stddef.h>
#include <stdint.h>
#include <stdatomic.h>

typedef struct {
    int width;
    int height;
    int stride;
    uint8_t *rgb;
} GXImage;

typedef enum {
    GX_MATCH_GRAY = 0,
    GX_MATCH_RGB = 1,
    GX_MATCH_LUMA_CHROMA = 2,
    GX_MATCH_CONTRAST = 3
} GXMatchMode;

typedef enum {
    GX_DIR_BOTH_X = 0,
    GX_DIR_POSITIVE_X = 1,
    GX_DIR_NEGATIVE_X = 2,
    GX_DIR_SEED_FORWARD = 3
} GXDirectionMode;

typedef struct {
    double step_px;
    int search_radius_px;
    double match_tolerance;
    int sample_radius_px;
    int contrast_ring_px;
    double ambiguity_margin;
    double thickness_factor;
    int noise_gap_steps;
    int max_steps;
    GXDirectionMode direction_mode;
    GXMatchMode match_mode;
} GXTraceSettings;

typedef struct { double x, y; } GXPoint;
typedef struct { GXPoint a, b; } GXGap;

typedef struct {
    GXPoint *points;
    size_t point_count;
    size_t point_capacity;
    GXGap *gaps;
    size_t gap_count;
    size_t gap_capacity;
    char target_description[160];
    char stop_left[96];
    char stop_right[96];
    int cancelled;
} GXTraceResult;

void gx_trace_settings_default(GXTraceSettings *s);
int gx_trace_settings_validate(const GXTraceSettings *s, char *err, size_t errcap);
void gx_trace_result_init(GXTraceResult *r);
void gx_trace_result_free(GXTraceResult *r);
int gx_trace_seed_guided(const GXImage *image, GXPoint seed1, const GXPoint *seed2,
                         const GXTraceSettings *settings, const atomic_int *cancel_flag,
                         GXTraceResult *out, char *err, size_t errcap);

#endif
