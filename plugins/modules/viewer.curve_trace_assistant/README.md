# GX-TXT Curve Trace Assistant 0.5.0

`viewer.curve_trace_assistant` is the native assisted-tracing companion for `viewer.curve_digitizer`.

The desktop runtime uses a native C/X11 backend while retaining the
GX-TXT Tcl/public-API integration. Tracing runs on a separate worker thread;
the canvas uses viewport-only image rendering and an image-pyramid cache,
so source images need not be fully resized during every pan/zoom event.

## Native architecture

```text
GX-TXT Viewer Provider
        |
        v
Tcl adapter / CURVE_TRACE_ASSISTANT_API_v1
        |
        v
native C desktop backend
   |                 |
   |                 +--> worker thread: tracing
   |
   +--> X11 UI + viewport-only image rendering
             + image pyramid cache
```

The tracing worker never calls X11. Pan, zoom, controls and cancellation remain available while tracing is running.

## Distribution modes

Two package forms are supported:

- **precompiled Linux x86-64 package**: contains `bin/gx_curve_trace_assistant` and starts immediately;
- **source package**: contains the same plugin plus C sources and `build_native.sh`. If the binary is missing, the desktop adapter attempts the native build on first viewer launch. The build can also be run manually.

The package does not execute build scripts during Plugin Install API installation.

## Build requirements

Required:

- C11 compiler (`cc`/GCC/Clang);
- X11 development headers/library;
- libpng development package;
- libjpeg development package;
- POSIX threads.

Optional decoders are enabled automatically when their development files are available:

- libtiff;
- libwebp;
- giflib.

BMP and PNM/PPM/PGM are decoded internally.

Build manually:

```sh
./build_native.sh
```

The resulting executable is written to:

```text
bin/gx_curve_trace_assistant
```

## Scientific behavior retained

The C tracing kernel preserves the 0.4.0 tracing modes and guards:

- one or two seed points;
- `both_x`, `positive_x`, `negative_x`, `seed_forward`;
- grayscale matching;
- RGB matching;
- Y/Cb/Cr luma/chroma matching;
- signed local contrast matching;
- bounded perpendicular search;
- tangent continuity;
- seed-relative thickness checks;
- competing-trace ambiguity stop;
- crossing/intersection broadening stop;
- bounded scan-noise gap lookahead;
- proposal and gap overlays.

Scientific point acceptance remains governed by the Curve Digitalizer companion API; this release does not create a second authoritative project format.

## CORE

No GX-TXT CORE modification is required by this rewrite.
