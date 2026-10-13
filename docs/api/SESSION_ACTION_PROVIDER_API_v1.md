# GX-TXT Session Action Provider API v1

License: GPL-3.0-or-later

## Purpose

Session Action Provider API v1 lets an installed module advertise a small
Session-level command without hard-coding the module inside GX-TXT CORE. The
provider is descriptor-driven and lazily activates the module's declared
public API only when the action is invoked.

Example descriptor:

```ini
[session_actions]
api_version=1
ids=export_html

[session_action.export_html]
name=Export Session to HTML...
public_api=SESSION_HTML_EXPORT_API_v1
command=::SessionHtmlExport::guiExport
requires_session=1
order=500
```

`public_api` must also be declared by the module under `[public_apis]`.
Discovery does not source the module entrypoint and therefore remains
host-independent. Invocation uses the existing Standard Module public-API
loader and is idempotent.

Public entry points:

```tcl
::GX::sessionActionProviderList
::GX::sessionActionInvoke moduleId actionId
```

The standard GUI presents discovered actions under `Session Tools`.

## Integrated dev-065 extension

See [CORE Parameter Service](CORE_PARAMETER_SERVICE_v1.md) for automatic Workspace contexts and descriptor Workspace actions, and [Native2D Geometry API](NATIVE_2D_GEOMETRY_API_v1.md) for exact topology/reference/constraint semantics.
