# Additive Viewer GUI and Development contracts — P020

SPDX-License-Identifier: GPL-3.0-or-later

These additions preserve `gxtxt.viewer_design.v1`, SDK v1 Event/State/Host storage,
the original native entry point and existing method bodies. Previously admitted
non-opt-in Viewers keep their existing contracts and precompiled execution.

## Declared Sketch

Builder component `cad_sketch` requires `NATIVE2D_API_v1@1`. Properties are
`title`, `working_unit` (default `mm`), `plane` (origin/normal/u_axis dictionary)
and `presentation` (`viewer` or `canvas`). An active Session is required for its
exact Interactive Document. The existing Native3D plane-frame operation validates
the frame; scientific coordinates are never computed by authored Viewer code.

Action property `cad_action {sketch_component action_id}` binds enabled/checked
presentation to the same managed controller used by `Host::cad_command`.
Viewer-owned menus/toolbars may contain those actions beside domain actions.
`context_menu` property `cad_context sketch_component` binds the declared Viewer
popup to the actual edit Canvas. It uses the existing menu owner and may include
the same shared actions and Viewer-specific actions. A Canvas-owned tools panel
remains available when the modes are combined; the declared Viewer popup replaces
the default Canvas popup, without creating another CAD controller.

The Canvas mode uses the existing collapsible ViewportHost panel, shared stock
icons, tooltips and command state. **All CAD actions…** exposes its full catalog.
`viewerGuiDesignCadCommand window component action` and
`viewerGuiDesignCadState window component ?action?` are host-mediated operations.
Workspace state references the exact Sketch Document, not sampled geometry.
Sketch **Save** flushes that Document; the Viewer **Workspace → Save** also saves
its host-state association. Closing/replacing widgets disposes their owned native
resources; it does not delete the saved scientific Document.
Builder's synthetic `demo` mode displays a layout placeholder instead of creating
a canonical Sketch or History. Use Preview in an isolated Session for exact
scientific editing; runtime uses the same managed component.

## Immutable event inputs and bounded output

The admitted C++17 SDK adds these nonvirtual operations:

```cpp
const char* Host::input(unsigned component) const;
const char* Host::data() const;
void Host::cad_command(unsigned component, const char* action) const;
void Host::diagnostics_command(unsigned form, const char* operation,
                               const char* request_json = "{}") const;
void Host::text_runs(unsigned log, const char* runs_json) const;
void Host::table(unsigned table, const char* rows_json) const;
```

Indices are the ordinary one-based declaration ordinals. Inputs are immutable
UTF-8 snapshots for the current event (up to512 fields,4096 bytes each,1MiB
combined; embedded NUL is rejected). Returned pointers remain valid until the
next event. Table input is its selected zero-based row-index list; the authored
Viewer maps those rows to its actual retained record identities. `data()` contains
only the typed public event payload supplied by the CORE owner, up to1MiB.
It is not a Tcl evaluator, generic file reader or scientific snapshot interface.

`value_get`, `cad_command`, `diagnostics_command`, `text_runs` and `table_set`
require explicit `VIEWER_GUI_HOST_API_v1` grants. CAD and diagnostics also require
their exact service grants. Native data/getters use an optional additive context
entry; old Event/State/Host layout and original event entry are unchanged.

Text runs use `{replace, autoscroll, runs:[{text,style}]}`. Up to512 runs and
131072 encoded bytes are admitted per output operation. Styles are `normal`,
`muted`, `info`, `warning`, `error`, `heading`, `match`; CORE reuses
`sourceSurfacePalette`, without repeatedly lexing logs. The visible text is capped
at1MiB. Tables contain at most1000 rows,32 columns and4096 characters per cell,
also within the131072-byte operation limit. Ordinary UI Field owns the widgets.

The managed compiled event transport opts into a2MiB pending-output budget;
other managed requests retain their65536-byte default. JSON encoding counts
toward that transport budget. The native callback lifetime is reserved before
the exchange, including its Tk event loop; typed notifications resume after
completion rather than entering the worker recursively or polling while busy.

## Diagnostics consultation form

A section declares `diagnostics_owner stderr`, `diagnostics_log`,
`diagnostics_records`, `diagnostics_status` and `diagnostics_changed`. The first
three identify declared log/table/status components; `diagnostics_changed`
names the typed data event delivered to the native `on_event` callback at that
section ordinal. Its design requires
`STDERR_DIAGNOSTICS_API_v1@1`. The project requests the corresponding explicit
consultation grants. Capture enable/disable belongs to Configuration, never to
the Viewer opening/closing contract.

`diagnostics_command` admits `info`, `status`, `meta`, `read`, `export`, `copy`,
`subscribe`, `unsubscribe`, `cancel`. Requests may contain an opaque `cursor`,
`limit`, `max_bytes`, stable `record_ids`, an author correlation `request_id` and
a boolean `follow`. No authored path or Tk command is admitted. The CORE owns
the user Save dialog for export and its clipboard operation for selected text.
Export preserves original binary payloads in structured records; clipboard text
is a UTF-8 presentation. Existing destinations are refused by the native export
owner; choose a new filename.

Completion is an ordinary `changed` event at the declared section ordinal:

```json
{"operation":"read","request_id":"viewer-1","result":{
  "records":[],"cursor":"opaque","eof":1,"bytes":0}}
```

Records use the native JSON schema and reversible `payload_base64`. Read EOF is
0/1. The same envelope carries status, metadata, export/copy results and truthful
errors. Cancellation completes the original operation with `status: cancelled`.
One archive operation per form is pending; conflicting requests get a correlated
`REQUEST_PENDING` error. Latest status notifications coalesce independently of
terminal results. Subscriptions/readers are released on closure or stale host
lifetime. Viewer filtering, search, ordering, inferred classification and cache
presentation remain authored C++ responsibilities.
