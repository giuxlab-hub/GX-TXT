/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef GXTXT_PREVIEW_COORDINATES_V1_H
#define GXTXT_PREVIEW_COORDINATES_V1_H
#ifdef __cplusplus
extern "C" {
#endif
struct Tcl_Interp;
/* Internal bounded affine presentation; public coordinate owner supplies plans. */
int gx2d_preview_coordinates_v1_init(struct Tcl_Interp *interp);
#ifdef __cplusplus
}
#endif
#endif
