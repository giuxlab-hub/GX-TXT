# Optional Preview Component GUI API v1

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

Builder-generated panes attach their root grid to the existing
`uiFieldTabOverflowAttach` presentation owner. A mixed fixed/weighted-row layout
that exceeds the available pane height gains its shared native vertical viewport;
wheel input and native Tab focus reveal its controls. When it fits again, the
original grid returns. Resizing, caption wrapping and font changes preserve the
same opaque control/native handles, values, callbacks and source-bound host.
Anchored Plot panels retain their separate existing ViewportHost owner. This
adds no descriptor field, source-model requirement, renderer or GUI worker grant.
If a control just fits in a very short pane, the same shared viewport uses precise
focus alignment while retaining normal wheel distance. Its scrollbar arrows use
the finer increment until that viewport is removed when the layout fits again.

`callback` is a Tcl command prefix. CORE appends `(host, event)`; `event` contains
`control_id`, `type`, `event` (`invoke` or `changed`) and `value`. Callback dispatch
checks source/Session/pane identity and Module activation before entering module
code. Disabled controls do not dispatch. Value controls use their normal native
events and UI Field commit validation. No raw Tk callback is sent to a worker.

`ControlGet` validates field/choice drafts with the existing UI Field descriptor
and returns their canonical typed value or validation error. An invalid draft
cannot be consumed by an action as a valid number. Reading does not synthesize
a changed callback. Labels/status are presentation outputs, without a public
scalar Get operation.

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
The Tcl GUI API is not callable through the restricted native worker SDK.

Viewer Interface Builder supports an explicit Preview Module target in the same
`gxtxt.viewer_design.v1` authoring model. Its public design adapter validates the
supported UI Field subset and mounts through these operations; it never composes
a standalone Viewer shell or forges a `viewer.*` package identity. The existing
Module Builder packages a genuine `preview.*` service with editable design,
source callbacks, compatibility metadata, assets and checksums. See
[the target contract](VIEWER_GUI_DESIGN_v1.md#preview-module-project-target).
The design-time Builder display is a simulation; installed source/Session/module
lifecycle acceptance uses the genuine Dataset Preview host.

## Explicit source selection and windows (P028)

`datasetPreviewGuiSelectDataset host datasetId` delegates an explicit user action
to normal Dataset Browser/inspection activation in the same current Session.
Existing edit/cancel/switch guards remain authoritative. A successful switch
retires the old opaque host; it cannot be reused by the caller.

`datasetPreviewGuiSourceRequest host request` admits a bounded data dictionary:
required `mode=full|rows|time`, `x_variable_id`, `y_variable_id`. X/Y must be
explicit distinct enabled rank-one numeric canonical Variables. `rows` additionally
requires exact integer `start>=0`, `count>=1`, contained within the available
canonical row count. `time` requires `time_min<=time_max`, both finite in the
canonical X Variable's stored unit, and a time semantic role. Bounds are closed.
Extra mode-specific fields and requests over4096 UTF-8 bytes are refused.

This explicit request selects one canonical source in original order. Full/rows
are unfiltered; time uses the existing inclusive Transform predicate. Existing
saved grouping/sorting is not silently applied to a requested original-row
window. The standard configured/grouped path is unchanged when no explicit
source request is present. Both filtered time windows above2M rows and exact row
windows use the existing individual bounded Curve Source, never an increased
retained batch limit. The fixed display budget remains4096.

The existing Live Preview/Cache/Job/Curve Source/Plot owners retain preparation,
source/schema/Session/epoch checks, keys, cancellation and prior valid frames.
The return is `{dataset_id source_window key}`; it grants no data/plot handle.
The initiating host retires under the normal epoch guard. After successful
preparation a fresh GUI context contains `representation.source_window`; its
`row_count` describes the prepared selection, while registered acquisition
metadata remains the original full recording. Rejected/cancelled/error requests
cannot publish partial scientific data. This adds no Script Bridge operations,
reader/reducer, Dataset, persistent selection registry or renderer.

### Managed numeric C++ presentation (P032)

When a design places a single weighted notebook directly in its canvas, CORE
allocates that notebook to the live canvas size. Hidden pages do not enlarge the
whole Preview pane. Structural slots add no extra padding; authored toolbar,
footer, page controls and their shared overflow behavior remain available.
The toolbar/footer use zero default vertical gaps in this viewport composition;
explicit authored padding is preserved.
For a plot-only page whose weighted Plot explicitly declares layout padding zero,
CORE also removes duplicate default tab/Plot container insets.
Layouts with other canvas arrangements retain their existing allocation.

## Cache Bridge 022 (additive host operations)

`datasetPreviewGuiCachedCurvesRequest host callback` asynchronously delivers the
existing CORE retained native model. A ready receipt contains `dataset_id`,
`key`, `cache_hit`, `model`, `total_rows` and `displayed_points`. A cold request
subscribes to the existing Preview preparation owner; it does not read and group
canonical curves in the module. The ordinary scientific cache key, settings,
provider/package identity, options and source validation remain authoritative.

`datasetPreviewGuiCachedPageRequest host options callback` accepts exactly
`start`, `count` and `variable_ids`. Start is zero-based, count is 1..1000 and
there are 1..32 distinct variable IDs. Ready receipts contain the ordinary
canonical `page`; its source row identities remain one-based. Pages preserve
exact values and schema rather than formatted screen precision. They are
SHA-protected disposable subresources inside the existing Session Preview cache,
bounded to 4 MiB each, with full envelope/shape/unit/type validation.

Both return `status`, `key`, `cache_hit` and an opaque cancellation `ticket`.
Callbacks must be callable members of the mounted module namespace and execute
under that module's existing context. Errors are terminal `status=error`
receipts. An invalid/retired host receives no late data. Identical cold page
requests share preparation and notify their distinct subscribers; an identical
host/callback request is deduplicated. Tasks bind actual Session lifetime,
scientific key, preparation options and a unique generation, so a cancelled old
completion cannot consume a replacement request. At most 8 page tasks (including
draining requests), 32 subscribers per task, 256 page subscriptions globally and
8 subscriptions per host are admitted. Overflow refuses explicitly.

`datasetPreviewGuiCacheCancel host ticket` cancels only that host's subscription.
Shared work remains active for other subscribers; the final unsubscribe cancels
the owned worker. Closing, disabling, changing source or replacing a host drains
its subscriptions through existing lifecycle owners. Source/window/package and
complete scientific cache identity are checked again before delivery.

CORE-only page read/generation helpers and the fixed worker's additive
`gxtxt.preview_page_worker.v1` request reuse the existing cache, publication and
managed-process owners. No cache path, writer or new native/C++ permission is
granted to a module. Existing native SDK46/47 and the bounded scientific context
remain unchanged. Native widget creation still uses the existing synchronous
Plot v4 owner; these operations do not promise asynchronous widget creation.

The additive host operations `datasetPreviewGuiChoicesSet`,
`datasetPreviewGuiPlotCreate`, `datasetPreviewGuiPlotBind`,
`datasetPreviewGuiPlotView` and `datasetPreviewGuiTableSet` reuse the same current
Preview host. Plot creation accepts its title and ordinary layout options;
binding accepts actual `x_variable_id`, `y_variable_id` and optional `linear|log`
axis scales. Dataset identity is supplied by CORE. View operations are exactly
`fit|zoom_in|zoom_out`. Tables accept at most1000 read-only presentation rows
and4MiB, within their declared column count. Choice lists are bounded to4096
entries/1MiB. All operations recheck actual host lifetime/source admission.

The existing restricted C++ `Host.data()` provides a bounded64KiB JSON snapshot:
actual Dataset/contract/canonical/source SHA, rank-one variable IDs, canonical
names/display labels, dtype/units/roles/coordinates/shape, and a sample of at most
16 rows ×16 variables. Sample cells are strings preserving canonical scientific
nonfinite representations; `sample_only=true` explicitly distinguishes this
small table from full scientific access. Coordinate ID lists retain their
existing textual representation. No source path, Dataset writer or new cache
handle is exposed. C++ uses existing SDK presentation operations; API catalog
visibility grants no extra operations. Canonical Plot v4 and Table Stream remain
the scientific presentation/read owners; source changes retire the host normally.

P032 shared Preview control failures retain the previous scientific view and show
an explicit **Refused…** status. The existing status is keyboard focusable; hover
shows the full message, and click/Enter/Space opens a read-only, scrollable status
snapshot with Copy. Moving keyboard focus away or pressing Escape on the status
dismisses its tooltip through the existing shared tooltip owner. Ordinary long
status summaries use an explicit ellipsis; the
complete original message is preserved. Successful corrected controls clear the
refusal. No new action row consumes the scientific viewport, and status viewing
never acknowledges a scientific revision, changes selection or weakens a refusal.

When a primary Preview selector is available and all three generic host Plot
navigation buttons are disabled, CORE places the existing selector, Cancel and
focusable status in one compact header. A component's actual local Plot controls
remain unchanged. Enabling generic navigation or removing the selector restores
the original header. This changes layout only, without provider, source or Job
requests. The full selection label/reason remains in hover/keyboard-focus help
and the existing complete status snapshot/Copy, even when its inline summary
cannot fit. Widget identities, selection callbacks and lifecycle checks persist.

## P035 compact status presentation

The shared Preview `status` control keeps its complete original text in the
current admitted host and displays a measured single-line summary. Font, theme,
layout, icon padding and resize changes recompute only that presentation. Long
descriptive `label` controls retain their existing wrapping. Click, Enter or Space
opens the existing scrollable status snapshot with exact Copy; hover includes
the full status and its authored help. Disposed or invalidated hosts cannot
inspect or copy stale callbacks. `ControlSet` retains its full-value return and
`ControlGet` retains the existing refusal for output-only status controls.
No additional action row, scientific selection, cache state or authority is added.
