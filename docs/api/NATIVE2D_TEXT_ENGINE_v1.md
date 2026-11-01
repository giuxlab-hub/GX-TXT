# Native2D opt-in shaped text v1

Existing primitives retain the default Cairo toy text painter. An explicit text
primitive may request `text_engine PangoCairo text_engine_version 1`; rotation
must be zero. The existing C++ Native2D painter resolves the installed stable
PangoCairo C ABI through its fixed OS library name. There is no executable,
Java/JavaScript, markup, include, remote service or second pixel renderer.

`::gx::native2d::text_engine_info` reports actual runtime availability, version,
plain-text restriction and missing-glyph refusal. `text_metrics family pixelSize
plainText` returns the same engine's pixel width/height. Both measurement and
painting use absolute pixel sizes, plain UTF-8, fallback/direction/shaping, and
explicit Cairo grayscale antialiasing/slight hinting/hinted metrics across image,
live and vector contexts. Each layout owns/releases its Pango objects; the loaded
OS ABI remains bound for the process lifetime. Portable designs carry no library
path, callback or Pango pointer.

A line is at most 64 KiB without NUL/newline, font size 1..256 pixels and plain
family name at most 128 UTF-8 bytes without path separators. Metrics are bounded
to 16384 by 4096 pixels. Invalid UTF-8, unavailable runtime/symbols/version,
unsupported angle/engine version and unknown glyphs explicitly refuse. Selecting
another installed font with coverage may resolve glyph refusal; no font is
installed automatically. Exact UML source remains available when visual display
cannot be admitted.

The matching normal CMake build receipt is
`core/native2d/bin/BUILD_RECEIPT_P031.json`. It records source/header/binary SHA,
compiler/flags and a scoped default-painter PNG comparison against the accepted
preimage. The author probe also checks shaped Latin/Greek/Arabic/CJK PNG/SVG,
metrics, missing ABI and glyph/version/angle refusals. These checks are not a
scientific Plot regression suite or independent GUI acceptance. Historical P028
receipts and immutable native module packages remain unchanged.

Primary ABI references consulted 2026-10-29:
[PangoCairo create layout](https://docs.gtk.org/PangoCairo/func.create_layout.html),
[paint layout](https://docs.gtk.org/PangoCairo/func.show_layout.html),
[plain text](https://docs.gtk.org/Pango/method.Layout.set_text.html),
[pixel metrics](https://docs.gtk.org/Pango/method.Layout.get_pixel_size.html),
[unknown glyphs](https://docs.gtk.org/Pango/method.Layout.get_unknown_glyphs_count.html),
[absolute size](https://docs.gtk.org/Pango/method.FontDescription.set_absolute_size.html),
[UTF-8 validation](https://docs.gtk.org/glib/func.utf8_validate.html),
[object lifetime](https://docs.gtk.org/gobject/method.Object.unref.html), and
[Cairo font options](https://www.cairographics.org/manual/cairo-cairo-font-options-t.html).
Only public declarations were used; no third-party implementation was copied.
