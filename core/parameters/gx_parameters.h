/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef GX_PARAMETERS_H
#define GX_PARAMETERS_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct gp_context gp_context;
/* Parent is a borrowed Session context. Name is stable identity within context.
 * define/remove stage changes; recalculate validates a complete batch. Hosts
 * publish a candidate context only on success, retaining the prior on failure. */
gp_context *gp_create(gp_context *session);
void gp_destroy(gp_context *);
int gp_define(gp_context *,const char *name,const char *formula);
int gp_remove(gp_context *,const char *name);
int gp_recalculate(gp_context *);
int gp_evaluate(gp_context *,const char *expression,double *value);
int gp_lookup(gp_context *,const char *name,double *value);
size_t gp_count(const gp_context *);
const char *gp_name(const gp_context *,size_t);
const char *gp_formula(const gp_context *,size_t);
const char *gp_dependencies(const gp_context *,size_t);
const char *gp_diagnostic(const gp_context *);
#ifdef __cplusplus
}
#endif
#endif
