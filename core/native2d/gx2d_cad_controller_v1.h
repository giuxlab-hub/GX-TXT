/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef GX2D_CAD_CONTROLLER_V1_H
#define GX2D_CAD_CONTROLLER_V1_H
#include "gx2d_sprite_scene_v1.h"
#ifdef __cplusplus
extern "C" {
#endif
/* The existing native adapter is called directly, never through Tcl eval.
 * It retains its original validation, scientific algorithms and result schemas. */
int gx2d_cad_controller_v1_create(Tcl_Interp *,gx2d_sprite_source_v1 *,uint64_t,gx2d_id,Tcl_ObjCmdProc *,ClientData);
#ifdef __cplusplus
}
#endif
#endif
