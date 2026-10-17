/* Public native binding of NUMERIC_API_v1: bounded streaming residual facts.
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Header-only C99/C++ API; no allocation, platform handles or scientific policy.
 * Initialize through gx_numeric_residual_init_v1; accumulator fields are opaque.
 */
#ifndef GXTXT_NUMERIC_REDUCTIONS_V1_H
#define GXTXT_NUMERIC_REDUCTIONS_V1_H
#include <stdint.h>
#include <stddef.h>
#include <math.h>
#include <string.h>
#define GXTXT_NUMERIC_REDUCTIONS_API_VERSION 1
#define GXTXT_NUMERIC_REDUCTIONS_AUTHORITY "NUMERIC_API_v1"
typedef enum { GX_NUMERIC_OK_V1=0, GX_NUMERIC_INVALID_V1=1,
    GX_NUMERIC_EMPTY_V1=2, GX_NUMERIC_RANGE_V1=3 } gx_numeric_status_v1;
typedef struct {
    uint64_t count, max_index;
    double scale;
    long double absolute_scaled_sum, square_scaled_sum;
} gx_numeric_residual_accumulator_v1;
typedef struct {
    uint64_t count, max_index;
    double max_absolute, mean_absolute, rmse;
} gx_numeric_residual_result_v1;
static inline void gx_numeric_residual_init_v1(gx_numeric_residual_accumulator_v1 *a) {
    if(a) memset(a,0,sizeof(*a));
}
static inline int gx_numeric_residual_valid_v1(const gx_numeric_residual_accumulator_v1 *a) {
    return a && isfinite(a->scale) && a->scale>=0 &&
        isfinite(a->absolute_scaled_sum) && a->absolute_scaled_sum>=0 &&
        isfinite(a->square_scaled_sum) && a->square_scaled_sum>=0 &&
        (a->count ? a->max_index<a->count : (!a->max_index && !a->scale && !a->absolute_scaled_sum && !a->square_scaled_sum));
}
static inline gx_numeric_status_v1 gx_numeric_residual_push_v1(gx_numeric_residual_accumulator_v1 *a,double value) {
    gx_numeric_residual_accumulator_v1 next;long double ratio;double magnitude;
    if(!gx_numeric_residual_valid_v1(a)||!isfinite(value))return GX_NUMERIC_INVALID_V1;
    if(a->count==UINT64_MAX)return GX_NUMERIC_RANGE_V1;
    next=*a;magnitude=fabs(value);
    if(magnitude>next.scale){
        ratio=(long double)next.scale/magnitude;
        next.absolute_scaled_sum=next.absolute_scaled_sum*ratio+1;
        next.square_scaled_sum=next.square_scaled_sum*ratio*ratio+1;
        next.scale=magnitude;next.max_index=next.count;
    }else if(next.scale){
        ratio=(long double)magnitude/next.scale;
        next.absolute_scaled_sum+=ratio;next.square_scaled_sum+=ratio*ratio;
    }
    ++next.count;*a=next;return GX_NUMERIC_OK_V1;
}
/* Concatenate two sample sequences; ties retain the first maximum identity.
 * out may alias either operand. No publication occurs on a rejected call. */
static inline gx_numeric_status_v1 gx_numeric_residual_merge_v1(const gx_numeric_residual_accumulator_v1 *a,const gx_numeric_residual_accumulator_v1 *b,gx_numeric_residual_accumulator_v1 *out) {
    gx_numeric_residual_accumulator_v1 next;long double ra,rb;
    if(!out||!gx_numeric_residual_valid_v1(a)||!gx_numeric_residual_valid_v1(b))return GX_NUMERIC_INVALID_V1;
    if(UINT64_MAX-a->count<b->count)return GX_NUMERIC_RANGE_V1;
    if(!a->count){*out=*b;return GX_NUMERIC_OK_V1;}if(!b->count){*out=*a;return GX_NUMERIC_OK_V1;}
    next=*a;next.count=a->count+b->count;
    if(b->scale>a->scale){next.scale=b->scale;next.max_index=a->count+b->max_index;}
    if(next.scale){
        ra=(long double)a->scale/next.scale;rb=(long double)b->scale/next.scale;
        next.absolute_scaled_sum=a->absolute_scaled_sum*ra+b->absolute_scaled_sum*rb;
        next.square_scaled_sum=a->square_scaled_sum*ra*ra+b->square_scaled_sum*rb*rb;
    }
    *out=next;return GX_NUMERIC_OK_V1;
}
static inline gx_numeric_status_v1 gx_numeric_residual_finish_v1(const gx_numeric_residual_accumulator_v1 *a,gx_numeric_residual_result_v1 *out) {
    gx_numeric_residual_result_v1 result;
    if(!out||!gx_numeric_residual_valid_v1(a))return GX_NUMERIC_INVALID_V1;
    if(!a->count)return GX_NUMERIC_EMPTY_V1;
    result.count=a->count;result.max_index=a->max_index;result.max_absolute=a->scale;
    result.mean_absolute=(double)((long double)a->scale*(a->absolute_scaled_sum/a->count));
    result.rmse=(double)((long double)a->scale*sqrtl(a->square_scaled_sum/a->count));
    if(!isfinite(result.mean_absolute)||!isfinite(result.rmse))return GX_NUMERIC_RANGE_V1;
    *out=result;return GX_NUMERIC_OK_V1;
}
#endif
