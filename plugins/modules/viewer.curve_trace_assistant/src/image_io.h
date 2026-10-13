#ifndef GX_IMAGE_IO_H
#define GX_IMAGE_IO_H
#include "native_trace.h"
#include <stddef.h>

typedef struct {
    GXImage *levels;
    int count;
} GXPyramid;

int gx_image_load(const char *path, GXImage *out, char *err, size_t errcap);
void gx_image_free(GXImage *im);
int gx_pyramid_build(const GXImage *base, GXPyramid *p, char *err, size_t errcap);
void gx_pyramid_free(GXPyramid *p);

#endif
