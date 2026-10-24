# Optional Preview Component GUI API v1 (DEV111-P006)

This is a trusted **Tk host-only** extension of `PREVIEW_COMPONENT_GUI_API_v1`.
It embeds existing `UI_FIELD_API_v1` controls inside a pane of Dataset Preview.
The Preview host owns the pane, dispatch, current Dataset/Session binding and
cleanup. It creates no Viewer window, independent icon catalog or renderer.
Existing descriptor-only modules remain unchanged.

## Opt-in and callbacks

Keep the ordinary selectable `kind=preview`, `runner=service` Module and existing
`PREVIEW_COMPONENT_GUI_API_v1` public entrypoint/namespace. Add:

```ini
[preview_provider]
gui_api_version=1
```

The default is `0`; no callbacks or GUI resources are created without opt-in.
The existing `preview context` callback can return a GUI pane alongside its old
metadata/artifact/table/native descriptors:

```tcl
proc ::GX::MyPreview::preview {context} {
    return [dict create tabs [list [dict create id tools label Tools kind gui]]]
}
proc ::GX::MyPreview::guiMount {host context} {
    ::GX::datasetPreviewGuiControlCreate $host fit action \
        {label Fit tooltip {Fit complete source bounds}} \
        [dict create callback [list ::GX::MyPreview::fit] layout {row 0 column 0}]
}
proc ::GX::MyPreview::fit {host event} {
    ::GX::datasetPreviewGuiView $host fit
}
proc ::GX::MyPreview::guiDispose {host context reason} {
    # Release only module-owned transient subscriptions/timers/resources.
}
```

Both `guiMount` and `guiDispose` must exist in the declared public namespace.
The module never supplies a renderer script or arbitrary mount command in a tab.
Mount/callback/dispose execute under the existing installed Module ownership
context. Failures use existing component diagnostics or Preview status; they do
not remove the standard view. Mount/dispose are presentation operations: do not
publish Datasets, alter metadata or implicitly execute scientific work there.
Deliberate user callbacks may invoke the module's existing authorized CORE services.

## Public operations (all in `::GX`)

| Operation | Arguments and result |
| --- | --- |
| `datasetPreviewGuiApiInfo` | No arguments; returns API identity, operations and owners. |
| `datasetPreviewGuiContext` | `host` → current bounded Preview context. |
| `datasetPreviewGuiControlCreate` | `host id type properties ?options?` → child widget path. |
| `datasetPreviewGuiControlGet` | `host id` → existing UI Field value/read-only inspection result. |
| `datasetPreviewGuiControlSet` | `host id value` → value; changes presentation, without invoking its callback. |
| `datasetPreviewGuiControlConfigure` | `host id properties` → widget; updates labels/text/tooltips/icon presentation. |
| `datasetPreviewGuiControlState` | `host id ?state?` → `{enabled BOOLEAN selected BOOLEAN}`; optional `enabled`/`selected` boolean updates. |
| `datasetPreviewGuiPanelCreate` | `host id title ?anchor=top-right? ?options?` → parent ID for a shared viewport panel. |
| `datasetPreviewGuiPanelShow` | `host id visible` → show/hide through ViewportHost. |
| `datasetPreviewGuiView` | `host fit\|zoom_in\|zoom_out` → invokes the existing Plot controller. |

IDs are local to one mounted pane: lowercase letter followed by at most 47
lowercase letters, digits or underscores. Reuse across different components is
safe. IDs cannot replace parent frames, sibling controls or scene objects.

`type` is an existing `uiFieldComponentCapabilities` type. Properties are the
existing UI Field properties, not a second widget descriptor system. Creation
options are `parent` (another container/panel ID, default the host pane), `layout`
(existing `uiFieldComponentLayout` grid/pack dictionary), `callback`, `icons` and
`command_icons`. Notebook/splitter parents use their existing native child-page
operations. Layout and field validation stay with UI Field. Use distinct grid
positions or one consistent pack layout in each parent.

`callback` is a Tcl command prefix. CORE appends `(host, event)`; `event` contains
`control_id`, `type`, `event` (`invoke` or `changed`) and `value`. Callback dispatch
checks source/Session/pane identity and Module activation before entering module
code. Disabled controls do not dispatch. Value controls use their normal native
events and UI Field commit validation. No raw Tk callback is sent to a worker.

`ControlSet` supports boolean controls, fields/choices, entries/comboboxes,
Dataset selectors, progress, bounded read-only list items and label/status text.
Typed fields/choices use `uiFieldNormalize`. Table/log/container writes are not
added by this API. `ControlConfigure` accepts `label`, `text`, `tooltip` and the
shared icon presentation keys below. `ControlState` uses existing UI Field/ttk
enablement. Selection is supported only for `checkbutton`/`toggle`; setting it
updates their boolean variable, so icon styling never becomes a second state owner.

## Icons, stock resources and toolbars

Use the existing public `viewerGuiIconCatalog` to discover semantic stock assets,
and `viewerGuiIconImport path title category license` to admit an asset. Existing
project/module PNG/SVG assets use the same import; imported project asset records
can be reused directly. No Viewer Interface Builder needs to be opened.

```tcl
set row [dict get [::GX::viewerGuiIconCatalog] icons fit]
set icons [dict create fit [::GX::viewerGuiIconImport \
    [dict get $row path] [dict get $row title] \
    [dict get $row category] [dict get $row license]]]
::GX::datasetPreviewGuiControlCreate $host fit action \
    {label Fit tooltip {Fit complete source bounds} icon fit \
     presentation icon_only icon_size 24 icon_spacing 4} \
    [dict create icons $icons callback [list ::GX::MyPreview::fit]]
```

`icons` is the existing validated asset dictionary (64 icons / 2 MiB bound),
passed as transient presentation data. The existing resource owner validates and
caches it. Child controls inherit their container's dictionary; `options.icons`
can supply an explicit dictionary. This API adds no asset registry/import format.

Supported shared properties: `icon`, `icon_disabled`, `icon_hover`, `icon_selected`,
`presentation=icon_only|icon_text|text_only`, `icon_position=left|right|top|bottom`,
`icon_size=16|24|32|48`, `icon_spacing=0|2|4|6|8|12`. They bind through
`uiFieldIconApply`, with its DPI scaling, themed image/text gap and native ttk
state precedence: disabled, selected, active/hover, normal. Missing variants use
normal native presentation. Actions/labels/status/checkbuttons/toggles support
icons; selected variants are admitted only on boolean controls. An icon-only
control requires a label or tooltip. Tooltips use the shared ViewportHost tooltip
owner. Shared photo caches retain their normal CORE lifetime after a pane closes;
bindings and module-owned controls are released.

A UI Field `panel` provides a responsive toolbar. Its creation options may contain
the existing `command_icons` convention: a dictionary mapping local child action
IDs to these same icon presentation properties. Child controls inherit those
properties; explicit child properties override them. Callbacks, values and command
enablement are still the control's ordinary authorities. No command/shortcut or
scientific-state registry is created.

## Controls over the Preview graphical area

`PanelCreate` is available when `context.viewport_available` is true: the current
standard Preview has a live Plot v4 surface. The existing shared ViewportHost
places real Tk chrome over that surface, respecting its first native plot rectangle.
On multi-panel plots, this adapter anchors panels to that first rectangle.
Nine semantic anchors, collisions, font-scaled margins, collapse, scrolling and
narrow layout remain with ViewportHost. Options are its existing `margin`,
`orientation`, `priority`, `max_width`, `max_height`, `min_width`, `close`, `scroll`.

```tcl
set panel [::GX::datasetPreviewGuiPanelCreate $host navigation Navigation top-right]
::GX::datasetPreviewGuiControlCreate $host fit action \
    {label Fit icon fit presentation icon_only tooltip {Fit complete source bounds}} \
    [dict create parent $panel icons $icons callback [list ::GX::MyPreview::fit]]
```

These controls are GUI widgets, not scientific objects drawn into the scene.
`datasetPreviewGuiView` delegates fit/zoom to Plot v4; existing pan, selection and
rendering remain unchanged. Modules may present their own existing authorized
annotation/inspection commands, but this patch implements no new scientific tools.
Unsupported media/Native3D/custom surfaces report no Plot viewport; their modules
can still use ordinary GUI panes. This is not a claim of a new generic 3D overlay.

The additive lower-level adapter is
`::GX::PlotDatasetAPIv4::widgetChrome path` → existing ViewportHost identity.
`native2DViewportHostCreate container surface scene changed ?options?` accepts an
empty scene for chrome-only layout; optional `presentation_bounds` is a trusted
host callback returning `{width height leftMargin topMargin rightMargin bottomMargin}`.
`native2DViewportPanelDestroy host id` releases a panel without touching its surface.
No dummy scene, alternate renderer or changed native camera is introduced.

## Lifecycle and native processing boundary

CORE creates an opaque `host` per GUI pane. It is bound to the actual parent XID,
Dataset scientific identity, Session token, Module descriptor/activation and current
Preview composition. Replacing/destroying the pane, closing Preview, changing the
Session, invalidating the source or disabling/updating the module retires its
handle. Catalog/Session owners and the existing live Preview refresh drive this;
no new polling or execution system is added. A stale API call cannot dispatch.
`guiDispose host oldContext reason` runs once after invalidation, then CORE removes
owned panels/widgets/values and subscriptions. The parent remains host-owned.
Do not use the expired handle from dispose or keep it across Dataset changes.

Native components opt in through the **same installed Module's Tcl public
entrypoint**, independently of their unchanged C++ processing library. After the
existing native worker returns and CORE admits its source-bound prepared result,
the GUI host invokes `guiMount` and receives callbacks. C++ keeps the restricted
Provider v1 / worker contract; it receives no Tk paths, callbacks or GUI authority.
There is no ABI/header/SDK change and no new native provider in P006. No claim is
made that Tcl GUI APIs are callable through the restricted native SDK.

Viewer Builder `gxtxt.viewer_design.v1`, `viewerGuiDesignValidate/Compose`,
Viewer package generation and the native Viewer SDK are unchanged. A GUI pane is
not a Viewer design and never uses a forged `viewer.*` module identity.
