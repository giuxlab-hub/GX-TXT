# Changelog

## 0.5.0

- Replaced the Python/Tk desktop adapter and tracing runtime with a native C/X11 backend.
- Moved tracing out of the GUI thread into a cancellable POSIX worker thread.
- Replaced full-image resize-on-every-event rendering with viewport-only rendering.
- Added a multilevel image pyramid for efficient zoomed-out display.
- Ported grayscale, RGB, Y/Cb/Cr and signed local-contrast tracing to C.
- Preserved continuity penalties, thickness checks, competing-trace ambiguity detection, crossing stop behavior and bounded scan-noise gaps.
- Replaced repeated local sort-based medians with fixed 256-bin histogram medians over uint8 image samples.
- Added native PNG/JPEG loading plus internal BMP/PNM support; TIFF/WebP/GIF are enabled when their libraries are available.
- Added two supported distribution modes: precompiled Linux x86-64 and source-build package.
- Added native executable self-test and source-package first-launch build path.
- Kept GX-TXT integration in the existing Tcl/public API layer and made no CORE changes.

## 0.4.0

- Python/Tk seed-guided local tracing baseline from which the native implementation was ported.
