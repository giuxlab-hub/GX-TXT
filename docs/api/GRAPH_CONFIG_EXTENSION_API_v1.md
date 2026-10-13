# Graph Configuration Extension API v1

SPDX-License-Identifier: GPL-3.0-or-later

Introduced in GX-TXT 0.9.7.39 for the `plot.dataset` multi-panel configuration workflow.

## Purpose

Graph Configuration Extension API v1 lets a graph provider append provider-owned controls to the normal CORE **Graph configuration** surface without modifying generic descriptor `config_fields` or inspecting private CORE widgets.

CORE continues to own the graph configuration window and its normal graph fields. The provider owns the meaning, validation and persistence of the controls created inside the extension container.

A graph with no registered extension behaves exactly as before GX-TXT 0.9.7.39.

## Registration

Define the callbacks first, then register one provider for one or more graph IDs:

```tcl
::GX::graphConfigExtensionRegister my.renderer.graph_config [dict create \
    module_id my.renderer \
    graph_ids {my.renderer.xy} \
    build_proc ::MyRenderer::graphConfigBuild \
    close_proc ::MyRenderer::graphConfigClose]
```

Required fields:

```text
module_id
graph_ids
build_proc
```

`close_proc` is optional. Only one extension may own a given `module_id + graph_id` scope.

Inspection/removal:

```tcl
::GX::graphConfigExtensionDefinition provider_id
::GX::graphConfigExtensionFor module_id graph_id
::GX::graphConfigExtensionUnregister provider_id
```

## Context

`build_proc` and `close_proc` receive one read-only dictionary:

```text
api_version
provider_id
module_id
graph_id
variant_id
parent
```

`variant_id` is empty for the base graph and contains the stable variant ID when the provider surface is hosted inside the Variant editor.

`parent` is the only widget container in which the provider may create controls. Providers must not inspect or modify private CORE widgets.

## Lifecycle

### Build

```tcl
proc ::MyRenderer::graphConfigBuild {context} {
    set parent [dict get $context parent]
    ttk::checkbutton $parent.option -text "Provider option"
    pack $parent.option -anchor w
}
```

`build_proc context` runs when CORE builds the graph configuration surface. Provider state should be loaded through the provider's public/persistent state mechanism.

The v1 extension has no generic Save callback. Provider controls that edit persistent state commit through the provider's own validated public API as the user operates them, matching the existing immediate graph-configuration model.

### Close

```tcl
proc ::MyRenderer::graphConfigClose {context} {
    # Release editor-instance state only.
}
```

The optional `close_proc context` runs when the extension container is destroyed. It must not delete persistent graph state.

## Base graphs and variants

The same extension provider serves the base Graph configuration dialog and the Plot tab of the Variant editor. CORE supplies the exact `variant_id`; copying, inheritance and isolation of provider-owned state remain the provider's responsibility.

## Activation

A Standard Module public API advertises the capability:

```ini
capabilities=...;graph_config_extension
```

Before extension lookup, Graph Workflow API v1 activates the module public API surface when that capability is declared. Registration is therefore deterministic on a clean session and does not depend on a prior unrelated GUI action.

## Failure behavior

If activation or `build_proc` fails, CORE keeps the graph configuration window open and shows **Provider extension unavailable** in the provider area. A cleanup failure is written to the diagnostic stream.

A missing registration is not an error: CORE simply omits the provider area and preserves the legacy graph configuration layout.

## Ownership boundary

CORE owns:

- the normal Graph configuration and Variant Plot surfaces;
- generic descriptor `config_fields`;
- extension activation, container creation and context;
- extension cleanup.

The provider owns:

- all controls created below `parent`;
- provider-specific validation and persistence;
- base/variant provider-state isolation;
- the semantics of its settings.

The extension API does not add fields to Graph Series, Plot Module API, or generic graph descriptors.
