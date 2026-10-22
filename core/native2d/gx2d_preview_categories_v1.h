/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef GXTXT_PREVIEW_CATEGORIES_V1_H
#define GXTXT_PREVIEW_CATEGORIES_V1_H
#ifdef __cplusplus
extern "C" {
#endif
struct Tcl_Interp;
/* Internal collector only; Graph Series remains numeric validation authority. */
int gx2d_preview_categories_v1_init(struct Tcl_Interp *interp);
#ifdef __cplusplus
}
#endif
#endif
