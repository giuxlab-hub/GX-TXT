#!/bin/sh
# Build the native Curve Trace Assistant desktop backend.
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CC=${CC:-cc}
OUT="$ROOT/bin/gx_curve_trace_assistant"
mkdir -p "$ROOT/bin"

command -v "$CC" >/dev/null 2>&1 || { echo "C compiler not found (set CC or install build-essential)." >&2; exit 2; }

CFLAGS="-std=c11 -O3 -Wall -Wextra -Wno-deprecated-declarations -Wno-misleading-indentation -I$ROOT/src"
DEFS=""
LIBS="-lX11 -lpng -ljpeg -lpthread -lm"

if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libtiff-4; then
    CFLAGS="$CFLAGS $(pkg-config --cflags libtiff-4)"
    LIBS="$LIBS $(pkg-config --libs libtiff-4)"
    DEFS="$DEFS -DHAVE_TIFF"
fi
if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libwebp; then
    CFLAGS="$CFLAGS $(pkg-config --cflags libwebp)"
    LIBS="$LIBS $(pkg-config --libs libwebp)"
    DEFS="$DEFS -DHAVE_WEBP"
fi
if [ -f /usr/include/gif_lib.h ]; then
    DEFS="$DEFS -DHAVE_GIF"
    LIBS="$LIBS -lgif"
fi

"$CC" $CFLAGS $DEFS \
    "$ROOT/src/main.c" \
    "$ROOT/src/native_trace.c" \
    "$ROOT/src/image_io.c" \
    "$ROOT/src/json_min.c" \
    -o "$OUT" $LIBS
chmod 0755 "$OUT"
"$OUT" --self-test
printf '%s\n' "Built $OUT"
