/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef GX2D_PRESENTATION_VISIT_V1_H
#define GX2D_PRESENTATION_VISIT_V1_H
#include "gx2d.h"
#ifdef __cplusplus
extern "C" {
#endif
/* Read-only exact presentation-state observation, not a geometry serializer.
 * Borrowed slices are valid only during the callback. A zero callback result
 * stops visiting successfully. Callbacks must not mutate/reenter the scene.
 * Pointer identities are normalized; no scientific calculation is duplicated. */
typedef int (*gx2d_presentation_visitor_v1)(void *,const void *,size_t);
GX2D_API gx2d_status gx2d_presentation_visit_v1(const gx2d_scene *,gx2d_id,gx2d_presentation_visitor_v1,void *);
#ifdef __cplusplus
}
#endif
#endif
