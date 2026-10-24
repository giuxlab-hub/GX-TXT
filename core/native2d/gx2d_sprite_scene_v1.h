/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef GX2D_SPRITE_SCENE_V1_H
#define GX2D_SPRITE_SCENE_V1_H
#include <tcl.h>
#include "gx2d.h"
#ifdef __cplusplus
extern "C" {
#endif
int gx2d_sprite_scene_v1_controls(Tcl_Interp *,const gx2d_scene *,gx2d_id,Tcl_Obj *,Tcl_Obj *);
int gx2d_sprite_scene_v1_init(Tcl_Interp *interp);
#ifdef __cplusplus
}
#endif
#endif
