/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef GX2D_PREVIEW_PLANE_V1_H
#define GX2D_PREVIEW_PLANE_V1_H
#include <tcl.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Internal adapter registration in the shared Native2D library, not a provider ABI. */
int gx2d_preview_plane_v1_init(Tcl_Interp *);
#ifdef __cplusplus
}
#endif
#endif
