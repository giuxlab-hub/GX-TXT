/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef GX2D_PRESENTATION_BATCH_H
#define GX2D_PRESENTATION_BATCH_H
#include "gx2d.h"
#include <tcl.h>
#ifdef __cplusplus
extern "C" {
#endif
int gx2d_grid_presentation(Tcl_Interp *, const gx2d_scene *, double);
int gx2d_canvas_clip(Tcl_Interp *, const gx2d_scene *, Tcl_Obj *, Tcl_Obj *, Tcl_Obj *, Tcl_Obj *);
#ifdef __cplusplus
}
#endif
#endif
