/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef GX2D_SPRITE_SCENE_V1_H
#define GX2D_SPRITE_SCENE_V1_H
#include <tcl.h>
#include "gx2d.h"
#ifdef __cplusplus
extern "C" {
#endif
typedef struct gx2d_sprite_source_v1 gx2d_sprite_source_v1;
/* A source is a managed read-only lease. Its C scene owner closes it BEFORE
 * gx2d_destroy. Close invalidates attached presenters synchronously. */
gx2d_sprite_source_v1 *gx2d_sprite_source_v1_create(gx2d_scene *);
gx2d_scene *gx2d_sprite_source_v1_scene(gx2d_sprite_source_v1 *);
void gx2d_sprite_source_v1_listen(gx2d_sprite_source_v1 *,void *,void (*)(void *));
void gx2d_sprite_source_v1_unlisten(gx2d_sprite_source_v1 *,void *);
void gx2d_sprite_source_v1_close(gx2d_sprite_source_v1 *);
int gx2d_sprite_scene_v1_attach(Tcl_Interp *,Tcl_Obj *,gx2d_sprite_source_v1 *);
int gx2d_sprite_scene_v1_sync(Tcl_Interp *,Tcl_Obj *,gx2d_sprite_source_v1 *,Tcl_Obj *,Tcl_Obj *);
int gx2d_sprite_scene_v1_controls(Tcl_Interp *,const gx2d_scene *,gx2d_id,Tcl_Obj *,Tcl_Obj *);
uint64_t gx2d_sprite_diagnostic_clock(Tcl_Interp *);
void gx2d_sprite_diagnostic_record(Tcl_Interp *,const char *,uint64_t,uint64_t,uint64_t,uint64_t);
int gx2d_sprite_scene_v1_init(Tcl_Interp *interp);
#ifdef __cplusplus
}
#endif
#endif
