# Native2D virtual grid and device surface

These presentation extensions belong to the existing shared Native2D host and
`gx2dtcl` module. They do not own scientific cells, Datasets, Plot state,
History, Workspace documents or persistent configuration. The geometry C ABI
remains independent of Tcl, Tk, Cairo and this presentation extension.

`::GX::native2DVirtualGridCreate path options` creates one real Tk window of
class `GXNativeGrid`. Options are a dictionary with ordinary `-option` keys.
The C++ host draws visible rows **and** columns through the shared Cairo device
painter. There are no per-cell Tk windows or Canvas items. The optional single
consumer-owned edit entry supplies standard Tk caret, IME and clipboard behavior.

Supported options include `-rows` (1–1000000), `-columns` (1–702),
`-rowheight` (16–200), `-columnwidth` (35–2000), `-columnwidths` (column-index
to width dictionary), `-hiddenrows` (up to 20000 exact source row IDs),
`-columnlabels` (column-index to bounded display-label dictionary),
`-fontsize` (6–72), `-fontfamily`, `-background`, `-generation`, `-revision`,
`-fetchcommand`, `-command`, `-xscrollcommand` and `-yscrollcommand`.

A fetch callback receives `widget receipt`, where the receipt contains
`row_ids`, `first_row`, `last_row`, `first_column`, `last_column`,
`generation` and `revision`. `row_ids` contains the bounded visible source rows,
including bounded overscan; hidden scientific rows are never renumbered. Return
a dictionary keyed by `{sourceRow columnIndex}`, each value containing `text`
and `kind`. Fetch through public scientific access APIs and validate the current
Dataset/Workbook/Session authority before returning. Results from a changed
generation or revision are not adopted. The native host retains only this page.

The interaction callback receives `widget receipt`, including `action`, `row`,
`column`, `anchor_row`, `anchor_column`, `generation`, `revision` and
`phase` (`press`, `drag`, `release`, `key` or `programmatic`).
Actions are `select`, `row`, `column`, `edit`, `fill` and `resize`; resize also
provides `width`. Scientific edits and one-step gesture History belong to the
consumer. Native scrolling uses signed, clamped pixel positions; one idle redraw
coalesces rapid wheel/key/scrollbar changes. Each coalesced invalidation or
Expose repaints the complete bounded visible viewport into one backing pixmap;
offscreen cells remain virtualized. Arrow, PageUp/Down, Home/End,
Ctrl+Home/End, Shift selection and F2 use native exact address hit/navigation.

Widget operations are `configure`, `xview`, `yview`, `hit x y`,
`bbox row column`, `select row column ?anchorRow anchorColumn?`,
`see row column`, `reference ?row1 column1 row2 column2?`, `invalidate`,
and `receipt`/`viewport`. `reference` clears or sets an ephemeral native reference
highlight without changing the active scientific selection. Receipts include exact
row IDs, signed pixel positions, draw/fetch/coalescing counts and bounded retained
cell count. Destroying the Tk window cancels pending redraws and releases native
window/display resources and callback references. No persistent store is created.

`::GX::native2DDeviceSurfaceCreate path` creates a `GXNativeSurface` sharing the
same native painter. `$path draw primitiveList` accepts bounded device-coordinate
`line`, `polyline`, `polygon`, `rectangle`, `oval` and `text` dictionaries.
Fields include `coords`, `stroke`, `fill`, `width`, `dash`, `opacity`,
`clip {left top right bottom}`, and text's `text`, `font_size`, `font_family`,
`angle` and `anchor`. Canonical scientific identity remains in the producing
Native2D/Plot model; display primitives never substitute for source data.

`$path export destination width height` and the headless-safe
`::gx::native2d::render destination width height primitiveList` use the identical
Cairo painter for PNG, PDF and SVG (selected by extension). Export dimensions
must match the producer's projection; each dimension is at most 16384 and the
image area at most 100 million pixels. Exports do not invoke another plotting
engine. Headless geometry and export operations do not initialize Tk or a display.

Debian source builds need C/C++17, Tcl/Tk development files, X11 development files
and Cairo development headers/library. `GXTXT_CAIRO_INCLUDE` and
`GXTXT_CAIRO_LIBRARY` CMake cache paths permit isolated development dependencies.
The existing shared host loader supports its controlled `GX2D_TCL_LIBRARY`
override. A production package includes its matching compiled module.
