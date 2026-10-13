# Curve Trace Assistant 0.5.0 Manual

## Purpose

Curve Trace Assistant helps follow a visible plotted curve in a Curve Digitalizer source image. It operates against an existing Curve Digitalizer configuration and never replaces the authoritative configuration with a private project file.

## Opening the viewer

Open GX-TXT **Viewers**, select **Curve Trace Assistant**, and open the viewer. The module discovers Curve Digitalizer configurations through `CURVE_DIGITIZER_COMPANION_API_v1`.

## Configuration and curve

Use the `<` and `>` controls next to the configuration and curve names. Changing only the curve does not reload or rescale the source image.

## Navigation

- Mouse wheel: zoom at the pointer.
- Middle or right button drag: pan.
- **Fit image**: fit the image into the current viewport.
- `F`: fit image.

The viewer renders only the visible viewport. Reduced pyramid levels are cached and selected automatically when zoomed out.

## Seed points

Choose **Set seed 1** or **Set seed 2**, then left-click the curve in the image.

One seed is sufficient for X-oriented tracing. Two seeds also provide an initial direction and can be preferable on steep or curved segments.

Keyboard shortcuts:

- `1`: set seed 1 mode;
- `2`: set seed 2 mode.

## Trace settings

The native viewer exposes the same scientific controls as the previous implementation:

- direction mode;
- match mode;
- step size;
- perpendicular search radius;
- match tolerance;
- sample radius;
- contrast ring radius;
- ambiguity margin;
- thickness factor;
- bounded noise-gap lookahead;
- maximum steps.

Click the displayed direction or match mode to cycle through available values. Use `-` and `+` for numerical settings.

## Tracing and responsiveness

Press **Trace from seed** or `T`.

Tracing runs on a worker thread. The X11 event loop remains responsive, so the image can still be panned or zoomed while the trace is being computed.

Press **Cancel** or `Esc` to request cancellation. Cancellation is checked during the native tracing loop and produces a partial proposal when available.

## Appearance modes

### gray

Matches local grayscale/luminance values.

### rgb

Matches local median RGB values.

### luma_chroma

Transforms the local median RGB signature to Y/Cb/Cr and weights luma/chroma distance.

### contrast

Uses signed local contrast and distinguishes dark-on-light from light-on-dark curves.

## Continuity and ambiguity

The tracer searches only inside a bounded perpendicular corridor. It applies a continuity penalty, estimates seed-relative line thickness, and stops when competing traces or intersection broadening make the continuation ambiguous.

Noise-gap lookahead is bounded and is not allowed to cross an ambiguous intersection.

## Image formats

The mandatory native build supports PNG and JPEG. BMP and PNM-family images are implemented directly. TIFF, WebP and GIF support are enabled when the corresponding development/runtime libraries are available at build time.

## Source integrity

Source resolution and SHA-256 verification remain delegated to the Curve Digitalizer Companion API. A stale or missing source is rejected before the native viewer receives a usable source path.

## Build from source

Run:

```sh
./build_native.sh
```

The adapter also attempts this build automatically on first launch when no executable is installed.

## Precompiled package

The Linux x86-64 package contains the already-built executable. The executable runs `--self-test` before the adapter accepts it as usable.

## Known limitations

- Version 0.5.0 preserves the proposal-only workflow of 0.4.0. Controlled point generation/simplification is a separate scientific workflow step.
- The native UI intentionally uses X11 directly rather than adding a new GUI framework dependency.
- Optional image decoders depend on build-time libraries.
