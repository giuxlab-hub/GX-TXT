# Documentation API v1

SPDX-License-Identifier: GPL-3.0-or-later

**Introduced:** GX-TXT Pipeline v0.8.4  
**API version:** 1  
**Policy:** mandatory for plugin authors; v0.8.4 keeps legacy descriptors loadable for backward compatibility.

## Purpose

Documentation is part of the public plugin contract. A plugin must declare where a developer/user can find its guide, relevant framework API specifications, examples, and optional changelog.

The design goal is explicit:

> A developer integrating a conforming GX-TXT plugin should not need to inspect framework or plugin source code to discover its public contract.

Documentation API v1 applies to:

- Standard Module API plugins (`plugins/modules/*/module.ini`);
- Mathematical Model plugins (`plugins/models/*/model.ini`);
- Scientific Analysis Definitions (`plugins/analysis_definitions/*/analysis.ini` and module-local definitions);
- Instrument descriptors (`plugins/instruments/*/instrument.ini`).

## Mandatory descriptor section

New or updated plugins **MUST** declare:

```ini
[documentation]
api_version=1
guide=README.md
api_refs=MODULE_API_v1;DATASET_API_v1
examples=
changelog=
```

### `api_version`

Required. Must be:

```text
1
```

### `guide`

Required. Path relative to the directory containing the plugin descriptor.

Example:

```ini
guide=README.md
```

The file must exist.

### `api_refs`

Optional semicolon/comma-separated list of normative GX-TXT API documents.

A bare name resolves under:

```text
docs/api/<name>.md
```

Example:

```ini
api_refs=MODULE_API_v1;SCIENTIFIC_ANALYSIS_DEFINITION_API_v1;RENDER_CACHE_API_v1
```

A reference containing a slash is resolved relative to the GX-TXT installation root.

### `examples`

Optional list of example files relative to the plugin directory.

Example:

```ini
examples=examples/minimal.ini;examples/demo.csv
```

Every declared file must exist.

### `changelog`

Optional path relative to the plugin directory.

Example:

```ini
changelog=CHANGELOG.md
```

## Validation states

The framework Documentation Registry reports one of:

```text
valid
legacy_missing
invalid
missing
```

Meaning:

- `valid`: Documentation API v1 is declared and all declared files/references resolve;
- `legacy_missing`: no `[documentation]` section; accepted only for backward compatibility in v0.8.4;
- `invalid`: the section exists but is malformed or refers to missing resources;
- `missing`: descriptor itself is unavailable to the registry.

## v0.8.4 compatibility and future enforcement

GX-TXT v0.8.4 does **not** break an older plugin solely because `[documentation]` is absent. It is registered with status `legacy_missing` and a warning.

This is a compatibility window, not permission for new plugins to omit documentation.

Plugin authors must treat Documentation API v1 as required. Future GX-TXT versions may enforce the requirement without an interactive prompt; for example they may omit a non-conforming plugin from normal discovery, execution, or GUI exposure while retaining an explicit compatibility/recovery path.

Do not depend on `legacy_missing` behavior for new code.

## Registry

The framework builds a Documentation Registry during plugin discovery.

GUI:

```text
Help -> Documentation registry...
```

The registry records:

```text
kind
stable ID
name
descriptor path
status
guide
api_refs
examples
changelog
validation errors/warnings
```

The normal Module Help text also includes Documentation API status.

## Generated installed reference

GX-TXT can generate an installation-specific reference from installed descriptors:

```bash
tclsh tools/generate_framework_reference.tcl
```

Default output:

```text
docs/reference/INSTALLED_PLUGIN_REFERENCE.md
```

An alternative output path may be passed as the first argument.

The generated reference includes dataset contracts, modules, bindings, Analysis Definitions, Mathematical Models, Render Cache declarations, and documentation status.

The generated document is **informative**. It complements but never replaces the normative Markdown specifications under `docs/api/`.

## Plugin author checklist

Before distributing a plugin:

1. add `[documentation] api_version=1`;
2. provide `guide=`;
3. list every framework API the plugin relies on in `api_refs=`;
4. provide small examples when useful;
5. ensure all listed paths exist;
6. run the GX-TXT test suite or Documentation Registry validation;
7. regenerate the installed reference when preparing a framework distribution.

## Backward compatibility

Documentation API v1 adds metadata only. It does not alter Standard Module API v1, Manifest Format 2, Dataset API, graphics behavior, or scientific execution semantics.

## v0.8.5 status

GX-TXT v0.8.5 keeps the v0.8.4 compatibility window: a legacy plugin without `[documentation]` is still loadable as `legacy_missing`. This does not weaken the authoring requirement. New or updated plugins must use Documentation API v1, and a future release may enforce normal-mode conformance without an interactive prompt while retaining an explicit recovery/compatibility path.

## v0.9.3.3 plot-plugin references

A new/updated generic scientific plot plugin should list every public contract it consumes. For a full 2D/3D dataset plotter the expected references normally include `SCIENTIFIC_PLOT_FRAMEWORK_API_v1`, `PLOT_3D_API_v2`, `UNIT_SELECTOR_API_v1`, `TABLE_STREAM_API_v1`, `GRAPH_PROVIDER_API_v1`, `GRAPHICS_INHERITANCE_API_v1`, `RENDER_CACHE_API_v1`, `DATASET_SELECTION_API_v1`, and the Dataset/Source Metadata specifications actually used. This documentation requirement remains part of the plugin contract.
