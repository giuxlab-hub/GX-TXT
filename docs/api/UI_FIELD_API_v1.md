# Declarative UI Field API v1

Dev108 native label/status components that stretch horizontally (weighted grid
columns with east/west sticky, or pack fill x/both) wrap to the smaller of their
declared positive `wraplength` (default400) and current allocated text width.
The text width excludes horizontal padding and an adjacent image. Their constant
minimum width request prevents wrapped text from repeatedly resizing its own
container. Natural, unweighted or unfilled labels retain their natural width
request and declared wrapping maximum. Explicit zero preserves intentional
no-wrap behavior. Native Configure bindings own
presentation only; field values, commands and scientific state are unchanged.
Captions of typed field/toggle/choice and Dataset-selector controls also wrap
within their allocated native width (maximum400px). Long descriptive labels
remain readable in narrow inspectors without changing the author's label,
component identity or bound value; ordinary focus scrolling reveals later rows.

Host presentation helpers `uiFieldColorToRGBA`, `uiFieldColorFromRGBA` and
`uiFieldColorComposite` convert canonical RGB/alpha descriptors and composite
against an explicit background. Numeric components remain in [0,1].
`uiFieldFormCreate` builds a shared scrollable typed form with bottom-anchored
Apply/Close, keyboard focus scrolling and visible validation status.
`uiFieldFormApply` validates all fields before invoking its one apply callback;
invalid input never invokes the callback. The host remains responsible for
making that callback's domain changes atomic.
`uiFieldFormSectionEnabled window section boolean` enables or disables an existing
named notebook section without removing its fields or changing their values.
The domain callback must still reject unsupported combinations on Apply; disabling
a tab is a presentation affordance, not domain validation.

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

`uiFieldControlsAppend frame widget` appends a native control owned by that
frame to the shared grid layout, including later layouts supplied with an
explicit child list. It preserves existing child order and puts appended
controls last. The transient registration is removed with its frame. It does
not own the appended control's actions, menu or scientific state.

`uiFieldInspectionColumnsFit tree` measures current heading and row text using
the actual Tk fonts, including visible tree-column `#0` identities. It updates
native column widths and font-based row height without changing row data,
selection, callbacks or scientific state. Long cells use the caller's ordinary
horizontal scrollbar. It is a presentation operation on an existing Treeview.
Call `uiFieldInspectionColumnsSchedule tree` after asynchronous row population;
it coalesces repeated requests into one idle fit and tolerates widget destruction.
Fitting only the initial empty table cannot account for later stack, variable,
API-catalog or diagnostic text. Existing script tables retain this same owner.


## Inspector scrolling

`uiFieldScrollSee viewport content widget` scrolls any shared canvas sidebar/form to reveal a focused nested widget, using root-coordinate differences that also work with geometry-managed children. `uiFieldFormSee` delegates to it. Curve Workbench uses a true canvas-child content frame with a persistent vertical scrollbar and focus scrolling for point tables, numeric editors and composition. `uiFieldControlsLayout` uses actual required widths to maximize groups per row and keeps each label/input pair together; it has no arbitrary six-group limit.
## Window placement

`uiFieldWindowFit window ?width height?` is a host/UI-only helper. Explicit sizes
start at +20+20; mapped windows are clamped to the screen with 40 pixels of
horizontal and 100 pixels of vertical allowance for native decorations and an
unknown remote taskbar. X11 does not expose the Windows working area to Tk.
`uiFieldWindowMapped` applies it only to ordinary toplevel Map events, preserving
override-redirect menus/tooltips. Reflow and scrolling remain owned by each UI;
this helper never changes scientific view state or data. These helpers are not
Script Bridge operations.

Gridded toplevels (`wm grid` nonempty) retain their native geometry owner.
Tk interprets their `wm geometry` and minimum-size dimensions as grid units,
so the pixel mapper does not resize them. This includes Tk's standard error
Details dialog. See the [Tk window-manager contract](https://www.tcl-lang.org/man/tcl8.5/TkCmd/wm.htm).


Placement sets the X11 user-position hint (USPosition), so multiwindow X servers honor the position as well as the size. Viewers with explicit initial dimensions call the helper before mapping; ordinary mapped windows use the global hook.

## Native context menus and grouped forms

The `::GX::uiMenuRowAttach frame ordered_buttons ?trailing=1?`
keeps a native action/menu row at one height. On a narrow window or enlarged
font it moves overflow into native `More` entries while retaining the final
`trailing` buttons (normally Workspace; Builder retains Options and Workspace).
Native menubuttons reuse their existing menus, live commands and accelerators.
Ordinary Button/TButton overflow invokes the original widget, with its current
command and disabled state; no callback copy or second action registry exists.
Configure events coalesce and pending callbacks are cancelled on destruction.
This is a host-only presentation operation; no new settings store is created.

`uiMenuRowAppend frame button` appends or moves one existing native action to
the end of a row already registered by `uiMenuRowAttach`, preserving its
overflow owner and original commands. It validates native parent ownership.
For grid-managed rows use `uiFieldControlsAppend` instead.

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

## Focused text editing

Host-only `uiTextEditingAttach window widgets` attaches standard editor bindings
to specified native Text/Entry controls. `uiTextEdit window operation` and
`uiTextEditCan window operation` dispatch/enable `select_all`, `copy`, `cut`,
`paste`, `undo`, `redo` against the focused attached control. Menu posting retains
the last attached edit target; unrelated controls, disabled widgets, gutters and
unattached reference panes are excluded. Text undo requires the widget's own
undo stack. Entries retain native Entry editing behavior.

Ctrl+A selects the entire focused buffer. Text paste replaces its selection as
one local undo transaction on X11 and other Tk platforms. The helper preserves
native clipboard and Text modified events, creates no Registry/scientific history
entry, installs no global binding, and releases widget bindtags on destruction.
The existing Viewer shortcut configuration reserves standard text chords and
excludes text controls; editor bindings do not add a second shortcut registry.
These native widget helpers are host-only, not Script Job operations.

## Viewer regions and dialog lifecycle

`uiFieldViewerShellCreate window title ?geometry? ?inspectorWidth?` creates a
resizable scientific canvas beside a scrollable inspector with a native sash,
adaptive toolbar and bottom status/History region. `uiFieldViewerSection parent
id title` creates a consistently padded inspector section.

`uiFieldDialogCreate dialog parent title ?geometry?` creates a withdrawn transient
dialog; populate domain controls, then call `uiFieldDialogPresent dialog ?focus?
?modal?`. `uiFieldFocusWhenMapped container target ?modal?` defers focus and grab
until both widgets are viewable. Unmapping releases the owned grab; closing or
destroying before mapping safely retires the request. `uiFieldDialogClose dialog`
releases the owned grab, destroys the dialog and restores its parent's focus.
These are host-only operations; domain validation remains with the consumer.

Shared dialogs without explicit dimensions size to their negotiated content request after mapping, then clamp placement to the screen. The global work-area mapper does not leave them frozen at Tk's provisional size. Explicit caller dimensions remain supported. Focus/grab acquisition checks both owner and target visibility; unmapping releases only that dialog's owned grab.

## Dynamic typed choices (dev108)

`uiFieldChoicesSet field_widget choices` updates both the existing typed choice descriptor and its native selector, bounded to4096 choices/1MiB without NULs. Current value is preserved and marked invalid when absent; ordinary selection, commit and Reset use the updated descriptor. `viewerGuiDesignChoicesSet` delegates to this owner for choice and choice-field controls, retaining plain combobox support.
## Project icon state images and relative spacing (dev108)

Compatible `action/label/status/checkbutton/toggle` properties now include
`icon_disabled`, `icon_hover`, `icon_selected`, each an optional existing project
resource ID. A nonempty state ID requires a normal `icon`. Empty IDs retain native
normal-image behavior. These are presentation only; they never change command
IDs, callbacks, enablement, values, scientific data or Workspace identity.

`uiFieldIconApply widget properties normalAsset ?projectCatalog?` retains its
original three-argument use. The optional catalog resolves only declared state
IDs; Ttk's existing image state list owns selection, with disabled before selected
before active/hover. Native checkbuttons/toggles have real selected states. A
plain action does not become a toggle merely because it has a selected image;
its domain owner must actually select it. Passive labels do not acquire invented
interactive hover behavior. Image-only controls retain accessible text and get a
native tooltip fallback; missing both text and tooltip is rejected by the design.

`icon_spacing` is the actual image/text gap in logical pixels, independent of
outside control padding. Existing Ttk `Button/Checkbutton/Label.label` elements
expose `-space`; a derived style preserves the caller's base style, layout, colors,
font and enablement while setting that native option. No padded replacement
bitmap, second renderer or command binding is needed. Theme changes reapply
presentation through the same owner; display photos and gap follow Tk scaling
within the existing bounded icon raster size. A runtime widget cache is destroyed
with its widget and contains presentation references only, not another asset store.

The Builder's existing Icon Library provides typed state-resource choices and
normal/disabled/hover/selected previews. Its existing scrollable UI Field inspector
keeps controls reachable at narrow sizes. Assign is one ordinary model transaction;
rename preserves all four logical bindings and Remove binding clears them together.
Legacy designs without icons/state properties retain their existing appearance.
Native command containers declare `command_icons`, a dictionary from an existing
container command ID to the same project icon presentation fields. The Builder
Icon Library exposes a typed Command target selector. Command IDs, callbacks and
true Configuration-owned enablement remain unchanged. Toolbar buttons reuse
`uiFieldIconApply`; existing native tooltips are retained without a second tooltip.
Menus/context menus use `uiFieldMenuIconApply menu index properties asset catalog`
and refresh their normal/disabled image with the existing command state owner.
They support image+text/text, left/right/top/bottom and logical sizes16/24/32/48.
Native Tk command menus expose no hover/selected image variant, custom image/text
spacing or icon-only tooltip contract; those requests reject explicitly. Their
typed inspector limits presentation choices and explains the restriction.
Nested rename/Remove-reference checking, model Undo/Redo and ordinary Module
packaging retain the same owned catalog bytes and stable command bindings.

Wrapped declarative labels and field/Dataset captions use the actual allocated
width. Horizontally stretched weighted-grid or fill-x/both labels keep a stable
one-character width request so wrapping changes height without causing nested
notebook geometry feedback. Natural-size/unweighted labels retain their declared
wrap maximum and natural width request. Side-by-side icons reserve their actual
image width/spacing. Interactive sash resizing continues through the existing
layout owner. Inspector/scroll-frame FocusIn handlers reveal only the actual
focused control, ignoring ancestor FocusIn notifications that could move a
visible checkbox between its pointer press and release. These are presentation
corrections; field values, source identity, callbacks and History are unchanged.
