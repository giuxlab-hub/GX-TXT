/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef GXTXT_CSV_PROVIDER_V1_H
#define GXTXT_CSV_PROVIDER_V1_H

/* Internal acceleration of the canonical CSV provider, not a data access API.
 * The provider owns and configures every borrowed Tcl channel. */
#ifdef __cplusplus
extern "C" {
#endif
struct Tcl_Interp;
int gx2d_csv_provider_v1_init(struct Tcl_Interp *interp);
#ifdef __cplusplus
}
#endif
#endif
