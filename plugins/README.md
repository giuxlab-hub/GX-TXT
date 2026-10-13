# Plugins

Discoverable extension points for GX-TXT Pipeline.

- `modules/<stable-id>/module.ini` + optional `runtime/`
- `models/<stable-id>/model.ini` + optional `runtime/`
- `instruments/<stable-id>/instrument.ini`
- `analysis_definitions/<stable-id>/analysis.ini`
- `modules/<module-id>/analysis_definitions/<stable-id>/analysis.ini` for module-private definitions

A mathematical model describes model mathematics. A Scientific Analysis Definition describes a declarative data-flow assembled from framework operations. They are separate resource types.

Adding a conforming plugin or definition must not require editing the framework core.

The current development inventory of managed external modules is
`plugin_packages/external_plugins.tsv`. Entries with `core=0` in their module
descriptor are removable through Plugin Install API v1 when registered. A
bundled module is not automatically CORE.
