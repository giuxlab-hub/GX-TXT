/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef GX2D_GRID_PRESENTER_V1_H
#define GX2D_GRID_PRESENTER_V1_H
#include "gx2d.h"
#include <tcl.h>
#ifdef __cplusplus
extern "C" {
#endif
int gx2d_grid_presenter_v1_init(Tcl_Interp *);
int gx2d_grid_presenter_v1_controls(Tcl_Interp *,const gx2d_scene *,Tcl_Obj *,gx2d_id,Tcl_Obj *,Tcl_Obj *);
int gx2d_grid_presenter_v1_update(Tcl_Interp *,const gx2d_scene *,Tcl_Obj *,Tcl_Obj *);
#ifdef __cplusplus
}
#endif
#endif
