# Declarative UI Field API v1

Host presentation helpers `uiFieldColorToRGBA`, `uiFieldColorFromRGBA` and
`uiFieldColorComposite` convert canonical RGB/alpha descriptors and composite
against an explicit background. Numeric components remain in [0,1].
`uiFieldFormCreate` builds a shared scrollable typed form with bottom-anchored
Apply/Close, keyboard focus scrolling and visible validation status.
`uiFieldFormApply` validates all fields before invoking its one apply callback;
invalid input never invokes the callback. The host remains responsible for
making that callback's domain changes atomic.

CORE owns one descriptor/value/widget authority for modules, Configuration,
viewer and Workbench settings, and provider forms. API `UI_FIELD_API_v1`,
Script provider `ui_field`. Types: string, integer, double/number, boolean,
choice, color, path, file and command. Special Dataset/Selection/scientific
controls keep their existing authority and dispatch.

`uiFieldNormalize descriptor value` validates without Tk. Descriptors carry
`type`, optional `label`, `required`, `default`, numeric `min/max`, choice
`values` (ordered list), color `alpha`, and `allow_inherit`. Empty values mean
inherit only where declared. Errors are explicit; numeric values must be finite.
Paths/commands are single-line values and normalization never executes them.

Colors use uppercase `#RRGGBB`; short hex and common basic color names normalize
to this form. Alpha-enabled values serialize as a Tcl dictionary
`rgb #RRGGBB alpha 0.5`. Opacity is a normalized finite number from zero to one,
and is presentation opacity, independent of scientific transmittance.
`uiFieldColorComponents value` returns a typed RGB/alpha descriptor.

`uiFieldCreate widget descriptor global_variable ?changed_callback?` creates a
shared control bound to the caller's state. Color controls include a hex entry,
text-labelled contrast-aware swatch button, keyboard-activated RGB chooser,
optional numeric opacity, and descriptor-declared Reset/Inherit. Cancel leaves
the prior value unchanged. Invalid input remains visible with an explicit
message and does not invoke the change callback. Destroy releases field state.
Other typed controls use an entry, checkbutton or readonly choice combobox.

Standard Module `type=color` descriptors use `alpha=1` when needed. Module
persistent defaults retain the same typed descriptor in Configuration, while
Session settings remain authoritative after manifest load. Script parameter
schemas accept the same ordinary types. The Script operations `api_info`,
`normalize(descriptor,value)` and `color_components(color)` provide the same
headless normalization for both Python and Octave; they do not expose widgets
or invoke a chooser.

`uiFieldControlsLayout frame width` is the shared adaptive GUI control-row
layout. It wraps as many groups as fit according to actual font/widget sizes, keeps
each label beside its input, and changes grid placement only when needed.
Native2D's existing `native2DToolbarLayout` delegates to this service. Dataset
Preview uses it for paging/goto controls so narrow windows keep the Go button
and input reachable. This is a Tcl GUI factory service; Script Bridge exposes
typed data normalization, rather than widget paths.


## TASK-9 dev-052 final behavior

`uiFieldScrollSee viewport content widget` scrolls any shared canvas sidebar/form to reveal a focused nested widget, using root-coordinate differences that also work with geometry-managed children. `uiFieldFormSee` delegates to it. Curve Workbench uses a true canvas-child content frame with a persistent vertical scrollbar and focus scrolling for point tables, numeric editors and composition. `uiFieldControlsLayout` uses actual required widths to maximize groups per row and keeps each label/input pair together; it has no arbitrary six-group limit.
## Remote window placement (dev-066)

`uiFieldWindowFit window ?width height?` is a host/UI-only helper. Explicit sizes
start at +20+20; mapped windows are clamped to the screen with 40 pixels of
horizontal and 100 pixels of vertical allowance for native decorations and an
unknown remote taskbar. X11 does not expose the Windows working area to Tk.
`uiFieldWindowMapped` applies it only to ordinary toplevel Map events, preserving
override-redirect menus/tooltips. Reflow and scrolling remain owned by each UI;
this helper never changes scientific view state or data. These helpers are not
Script Bridge operations.


Placement sets the X11 user-position hint (USPosition), so multiwindow X servers honor the position as well as the size. Viewers with explicit initial dimensions call the helper before mapping; ordinary mapped windows use the global hook.

## dev092 native context-menu positioning and grouped forms

`::GX::uiMenuPopup menu root_x root_y` posts a native Tk Menu in the pointer
monitor's usable rectangle. `uiMenuWorkarea widget root_x root_y` returns
`{left top width height}`. X11 monitor selection uses `xrandr --listmonitors` and
intersects the current EWMH desktop `_NET_WORKAREA` when available; fallback is
the Tk virtual root/screen. Neither a (0,0) origin nor a single monitor is assumed.
A six-pixel margin, measured populated size, and above/left preference keep the
popup accessible. Dynamic root `-postcommand` runs once before measuring, with
native posting guarded against a second execution. Commands, check/radio
variables, focus/grabs and keyboard traversal remain native Tk behavior.

Ordinary menus are posted directly. Oversized menus are projected into **native
Menu pages/cascades** sized to the workarea, retaining all entry callbacks and
variables; a tall cascade is recursively paged too. There is no alternate custom
menu renderer and no global `tk_popup` replacement. Native menubutton posting
and ordinary automatic cascades are unchanged. Call this service for mouse
context popups, not to replace a menubutton's native posting contract.

`uiFieldFormCreate window title fields initial apply ?parent? ?sections?` adds
an optional ordered dictionary of notebook section IDs/titles. A field's optional
`section` selects its page. Existing six-argument callers keep their layout and
validation. Sectioned fields use compact label/control columns, dynamic page
height, existing vertical scrolling and visible errors on invalid input. The
shared grid form groups all 35 existing options into six pages, retaining Apply,
field Reset, Reset grid, alpha/color and unit/precision behavior.
