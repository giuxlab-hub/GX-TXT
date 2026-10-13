# Generic module configuration example

SPDX-License-Identifier: GPL-3.0-or-later

Install this folder through the normal Plugin Install API in a disposable
installation. CORE discovers its four descriptor fields without activating an
analysis or Viewer. It starts disabled and configuration does not enable it.

`persistent_default=1` exposes User defaults plus Session overrides. An ordinary
field retains Session-only scope. `application` declares immediate or
next-invocation timing. Types, labels, bounds and choices use UI Field API v1.

Both the central Modules pane and a module-local surface use:

```tcl
::GX::configurationModuleFields example.configuration
::GX::configurationResolve module.example.configuration.level
::GX::configurationModuleDialog example.configuration .
```

The dialog is the generic module-local client; a plugin can expose it from its
own Settings menu. Neither surface stores settings. A custom client captures
`configurationScopedValue` and submits `configurationCommit` changes containing
`id`, `scope=user|session`, `value`, `expected`, and the resolve receipt's
`session_token` for Session changes. Conflicts reject before mutation. An
explicit Session `clear=1` falls back to the User default.

Complex settings may declare `[configuration] entrypoint=api/settings.tcl`, with
lightweight validators/schema callbacks only, and field `validator` and
`structured_fields` command prefixes. The latter returns UI Field descriptors
keyed by structured member ID; the validator normalizes the whole dictionary.
Curve Workbench uses this contract for shortcuts, with no plugin-specific CORE
branches. No global or CORE code changes are required to author this module.

The fourth field, Session coefficients, uses `type=table` with stable Repeatable
Config row IDs and string/number/boolean columns. Its changes remain drafts until
Save Session overrides; the existing repeatable Manifest sections persist it.
Its coefficient bounds are enforced before any save. No script or module runtime
is needed to use this rich editor.
