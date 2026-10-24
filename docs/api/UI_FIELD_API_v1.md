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
Non-color compact typed-field captions span the whole field, including its
Reset/Inherit area. When the entry and those buttons cannot fit side by side at
their actual font sizes, the existing buttons move below the full-width entry.
Widening restores their original inline layout. This does not replace widgets,
change values, validation, disabled/readonly state, callbacks or focus order.

Host presentation helpers `uiFieldColorToRGBA`, `uiFieldColorFromRGBA` and
`uiFieldColorComposite` convert canonical RGB/alpha descriptors and composite
against an explicit background. Numeric components remain in [0,1].
`uiFieldFormCreate` builds a shared scrollable typed form with bottom-anchored
Apply/Close, keyboard focus scrolling and visible validation status.
`uiFieldFormApply` validates all fields before invoking its one apply callback;
invalid input never invokes the callback. The host remains responsible for
making that callback's domain changes atomic.
Callback errors remain inline while their form exists. If a normal callback
closes its form or parent before failing, the shared owner instead shows the
error in an **Action failed** dialog attached to the surviving application
root. Closing a form does not make a later callback failure disappear.
`uiFieldFormSectionEnabled window section boolean` enables or disables an existing
named notebook section without removing its fields or changing their values.
The domain callback must still reject unsupported combinations on Apply; disabling
a tab is a presentation affordance, not domain validation.

CORE owns one descriptor/value/widget authority for modules, Configuration,
viewer and Workbench settings, and provider forms. API `UI_FIELD_API_v1`,
Script provider `ui_field`. Types: string, integer, double/number, boolean,
choice, color, path, file and command. Special Dataset/Selection/scientific
controls keep their existing authority and dispatch.

Declarative `dataset_selector` accepts boolean `allow_empty` (default false).
When true, its finite canonical choices include one empty choice and a native
**Clear selection** button. Clearing commits the same `changed` notification as
choosing a Dataset; it does not select another Dataset, accept arbitrary text,
or modify canonical data. The optional empty choice remains available with no
Session or no compatible Dataset. `uiFieldComponentEnabled` disables both the
selector and Clear. `uiFieldDatasetChoices ?content_kind? ?allow_empty=0?`
returns these same finite identities; invalid boolean values are rejected.
Existing nonoptional selectors retain their choices and behavior.

Declarative read-only `table` components accept `columns` and optional
`scrollbars=none|vertical|horizontal|both` (default `none`). The default retains
the existing Treeview widget identity. Scrollable tables return their containing
frame; `uiFieldComponentTableWidget component` resolves either representation to
the same native Treeview. Horizontal scrolling fits column widths to actual
headings and page values after `viewerGuiDesignTableSet`, using the existing
inspection-column owner. Vertical scrolling reaches the remaining rows.
`uiFieldComponentTableRead component ?selectedOnly=0?` (also
`uiFieldComponentRead component table`) returns `columns`, `rows`, `selection`
and `read_only=1`, bounded to 1000 rows / 4 MiB. Native Ctrl+C or the host operation
`uiFieldComponentTableCopy component` copies selected rows as tab-separated
text. Embedded tab/newline characters become spaces in the clipboard projection;
the stored values remain exact. No selection copies nothing. These controls
never edit cells or change scientific data; they are distinct from Worksheet.

`uiFieldNormalize descriptor value` validates without Tk. Descriptors carry
`type`, optional `label`, `required`, `default`, numeric `min/max`, choice
`values` (ordered list), color `alpha`, and `allow_inherit`. Empty values mean
inherit only where declared. Errors are explicit; numeric values must be finite.
Paths/commands are single-line values and normalization never executes them.

Declarative `field` components with `datatype color` may expose the same
descriptor option as `alpha 1`. Canonical `{rgb #RRGGBB alpha VALUE}` values
retain opacity through public programmatic ValueSet, the visible RGB entry,
normal validation and `uiFieldComponentRead widget field`. Programmatic updates
synchronize the existing RGB mirror before committing; reading the entry alone
would lose opacity. Fields without the option retain their existing RGB-only
contract. Other field datatypes cannot declare alpha.

Finite `number`/`double` fields use Tcl's shortest round-tripping decimal text.
For example, `0.04` remains readable rather than acquiring an expanded formatting
tail. Binary-double precision, finite-value validation and declared bounds are
preserved. This does not change scientific Numeric APIs or rewrite Datasets.

Declarative `tabs` accepts `tab_position=north|west` (default `north`). `west`
uses the native notebook's vertical tab layout for narrow sidebars. Page IDs,
selection, native hit testing and page contents retain the same owner.
North-facing headers that cannot fit use a native readonly page selector with
the original tab font and full page titles. It selects the same notebook pages;
disabled pages remain unavailable and hidden pages are omitted. Widening restores
the original native headers, style and padding. No scientific action is submitted
for local page selection. The shared Builder shell also wraps overflowing
single-row action bars, including declared nested panels, through
`uiFieldControlsLayout`, retaining each original
widget, command, enabled state and declared layout when it fits again.
`uiFieldComponentEnabled widget type boolean` changes an existing value
component's enabled state, including its entry/reset controls, preserving the
value, validators and a combobox's readonly policy. Disabled presentation does
not replace domain validation.

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
each label beside its input when the pair fits, and changes grid placement only
when needed. A single pair wider than its container flows onto full-width rows;
the existing entry can shrink and retain its ordinary native text scrolling.
The fallback temporarily weights its grid column and restores the caller's
original weight when the normal arrangement fits again.
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

`uiFieldScrollSee viewport content widget` scrolls any shared canvas sidebar/form to reveal a focused nested widget, using root-coordinate differences that also work with geometry-managed children. `uiFieldFormSee` delegates to it. Curve Workbench uses a true canvas-child content frame with a persistent vertical scrollbar and focus scrolling for point tables, numeric editors and composition. `uiFieldControlsLayout` uses actual required widths to maximize groups per row and keeps each label/input pair adjacent, flowing vertically if necessary; it has no arbitrary six-group limit.

`uiFieldViewerShellCreate` interprets its declared inspector width as the existing
font10 nominal width. At initial mapping a larger actual TkDefaultFont preserves
its approximate character capacity using the same font family's measured digits
at size10. Expansion is bounded by the mapped body: the nominal width remains
available and additional space uses at most two thirds of the body. Narrowing
clamps an oversized split to that bound, while growing does not reset the user's
split. Native sash movement, vertical scrolling and page/field identity remain
owned by the same native widgets. There is no module-specific inspector size or
change to drawing/scientific coordinates.

The pane stays bounded by that same policy when a native action caption needs
more room. The inspector content keeps its natural width and the requested width
of mapped native actions, including actions inside nested scrolling pages. A
native horizontal scrollbar appears only when this content exceeds the viewport;
it makes both caption ends reachable without widening the pane, reducing fonts
or changing child grid policies. The bar disappears and horizontal position
resets when the content fits again. Existing vertical scrolling remains available.

Deferred inspector layout reveals a fully offscreen focused control horizontally.
A partly visible focus target stays still between its native press and release;
the horizontal scrollbar provides access to its remaining caption. Closing the
inspector cancels its pending layout. The existing InspectorFocus/Wheel procedures
and `uiFieldScrollSee` vertical behavior are unchanged. Labels, command bindings,
enablement, values and scientific/Workspace data keep their original owners.

The focused dev109 caption356 evidence is **component-only**: the same no-Session
Tk fixture gives baseline29PASS/1FAIL and candidate30PASS, with six additional
focus/scroll-command/close controls passing. Five complete font10 observation
dictionaries match the baseline; wide and normal font restoration also pass.
Inert counter actions and the captured pane allocation are constructed component
inputs. They do not establish installed human-input or scientific acceptance.
At this documentation cut, originalQA335's cold missing-caption/access-to-existing-
commands retest remains pending after MAIN integration. See the
focused delivery and qualifications.

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

The shell returns the same dictionary paths:

| Key | Returned path |
| --- | --- |
| `window` | `$window` |
| `toolbar` | `$window.toolbar` |
| `inspector` | `$window.body.inspector.scroll.content` |
| `canvas` | `$window.body.canvas` |
| `footer` | `$window.footer` |
| `status` | `$window.footer.status` |

The conditional inspector scrollbar is private presentation, not a new returned
region or public operation. Existing consumers keep these component paths,
commands and data bindings; the shell creates no scientific state store.

An overflowing single-row action bar wraps through the existing shared controls
layout. A multirow action bar with full-width status headers uses a native
**Actions…** menu at narrow widths, preserving room for its scientific viewport.
The menu reads the original buttons' current captions, icons and enabled states
when opened and invokes those same buttons. It owns no scientific state or Job.
Status headers use their available row width in this compact mode; widening
restores the declared buttons, grid policies and text wrapping. Mixed input
forms are excluded from this toolbar fallback.

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

Declarative `tab` pages with both weighted content rows and fixed descriptive
rows retain their ordinary grid while it fits. If their natural content height
exceeds the allocated page, the shared native vertical scroll area preserves
the content's requested height and makes the explanation and controls reachable.
This prevents a tall wrapped label from taking the whole weighted viewport.
Resizing or restoring the font removes the scroll area when the original grid
fits again. Child widget paths, bindings, values and row/column policies survive
this transition. Tab selection and disabled controls stay native; focus reveals
the actual control, nested editors/plots retain their wheel behavior, and a
scrolling tab owns its wheel rather than also scrolling the outer inspector.
No Viewer-specific dimensions, scientific state or font reduction are involved.

## Optional Preview host adapter (DEV111-P006)

[Preview Component GUI API v1](PREVIEW_COMPONENT_GUI_API_v1.md) lets opted-in
Preview modules use these same components/layout/values and `uiFieldIconApply`
in host-owned panes and viewport panels. It adds no widget/icon system.
