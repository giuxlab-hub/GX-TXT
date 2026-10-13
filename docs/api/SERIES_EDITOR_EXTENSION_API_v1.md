# Series Editor Extension API v1

SPDX-License-Identifier: GPL-3.0-or-later

Introduced in GX-TXT 0.9.7.21. GX-TXT 0.9.7.42 adds optional provider-owned read-only table columns without changing the API version.

## Purpose

Series Editor Extension API v1 lets a graph provider add provider-owned controls
to the standard CORE **Series...** editor. The standard editor remains
authoritative for Graph Series identity, ordering, enablement, dataset and stable
X/Y variable bindings, axis and label. The extension appears in a **Provider
details** area below those generic controls.

The API does not add fields to Graph Series API v1, create another series
registry, or define provider properties. A provider owns the loading, display,
validation, persistence and interpretation of every value shown in its area.

A graph with no registered extension uses the same Series Editor controls and
behavior as before 0.9.7.21.

## Registration

Define the callbacks first, then register one provider for one or more declared
graphs:

```tcl
::GX::seriesEditorExtensionRegister my.renderer [dict create \
    module_id my.renderer \
    graph_ids {my.renderer.xy my.renderer.band} \
    build_proc ::MyRenderer::seriesBuild \
    load_proc ::MyRenderer::seriesLoad \
    validate_proc ::MyRenderer::seriesValidate \
    save_proc ::MyRenderer::seriesSave \
    close_proc ::MyRenderer::seriesClose]
```

`provider_id`, `module_id` and every graph ID use stable GX-TXT identifier
syntax. `table_columns` and `table_values_proc` are optional and are described below. A registration must contain at least one graph. Two providers cannot
register for the same module/graph scope. `close_proc` is optional; the other
four callbacks are required and must be callable when registration occurs.

Public inspection and removal operations are:

```tcl
::GX::seriesEditorExtensionDefinition provider_id
::GX::seriesEditorExtensionFor module_id graph_id
::GX::seriesEditorExtensionUnregister provider_id
```

Unregistering is intended for provider teardown and tests. It does not delete
provider-owned persisted state.

## Context

Every callback receives one read-only context dictionary:

```text
api_version
provider_id
module_id
graph_id
variant_id
series_id
parent
generic_series
```

`parent` is the only widget container in which the provider may create
controls. The provider must not inspect the editor's private widgets.

`variant_id` is empty for a base graph and contains the stable variant ID for a
variant. CORE does not define inheritance or copying rules for provider state.

`series_id` is empty during initial construction and when no series is
selected. For a selected or proposed series it is the stable Graph Series ID.

`generic_series` is empty when no series is selected. Otherwise it is a
read-only snapshot containing:

```text
module_id
graph_id
variant_id
series_id
dataset_id
x_variable_id
y_variable_id
axis
label
enabled
order
alignment_mode
manual_offset_seconds
```

The current implementation may add compatible generic Graph Series fields in a
future release. Providers should read named keys and ignore unknown keys.

The same snapshot is available without editor internals:

```tcl
set snapshot [::GX::graphSeriesSnapshot module_id graph_id series_id ?variant_id?]
```

Scientific variable identity remains `dataset_id + variable_id`.
Provider-specific state should use at least
`module_id + graph_id + variant_id + series_id` as its scope.


## Optional read-only table columns (GX-TXT 0.9.7.42)

A provider may add informational columns to the standard Graph Series table without adding fields to Graph Series API v1:

```tcl
table_columns [list [dict create id panel heading Panel width 90]]
table_values_proc ::MyRenderer::seriesTableValues
```

`table_columns` is optional. Each entry is a dict containing `id`, `heading`, and integer `width` (at least 20 pixels). When columns are declared, `table_values_proc` is required. It receives a read-only context containing `api_version`, `provider_id`, `module_id`, `graph_id`, `variant_id`, `series_id`, and `generic_series`, and returns a dict keyed by the declared column IDs.

These columns are display-only. They must not become a second Graph Series registry or change scientific identity. CORE owns the table and scrolling; the provider owns the meaning of its values. `plot.dataset` uses this hook only to display panel membership.

## Callback lifecycle

### Build

```tcl
proc ::MyRenderer::seriesBuild {context} {
    set parent [dict get $context parent]
    ttk::entry $parent.width -textvariable ::MyRenderer::width
    pack $parent.width
}
```

`build_proc context` runs once when an editor instance is built. Its
`series_id` and `generic_series` are empty. The callback creates controls only
under `parent`.

### Load and selected-series change

```tcl
proc ::MyRenderer::seriesLoad {context} {
    set seriesId [dict get $context series_id]
    # Load provider-owned state for this exact graph/variant/series scope.
}
```

`load_proc context` runs whenever the selected series changes, after the
generic controls have loaded. It also runs after a successful save and with an
empty series ID when a selected series is removed. Controls must be refreshed
from provider-owned state each time; editor-local values must not leak between
series.

### Validate

```tcl
proc ::MyRenderer::seriesValidate {context} {
    if {$::MyRenderer::width <= 0} {
        error "Line width must be greater than zero."
    }
    return [dict create line_width $::MyRenderer::width]
}
```

`validate_proc context` runs before Graph Series state or provider state is
committed. The snapshot describes the normalized proposed generic values. The
callback returns an opaque validated value that CORE passes unchanged to
`save_proc`. An error rejects the operation, preserves the existing generic
series, and is shown through the normal Series Editor error path.

### Save

```tcl
proc ::MyRenderer::seriesSave {context validatedState} {
    # Persist atomically using the provider's own public state mechanism.
}
```

After both generic and provider validation succeed, CORE commits the generic
Graph Series and calls `save_proc context validatedState`. The save context
contains the committed generic snapshot.

If `save_proc` fails, CORE restores the previous generic Graph Series or
removes a newly proposed series. The provider owns its storage and must make
its own save operation atomic so a callback error cannot leave partial
provider state.

### Close

```tcl
proc ::MyRenderer::seriesClose {context} {
    # Release editor-instance resources.
}
```

The optional `close_proc context` runs once when the editor container is
destroyed. It does not delete persisted provider state.

## Base graphs and variants

The same lifecycle serves base graphs and variants. Providers must include
`variant_id` in their state key. Editing a variant receives that exact ID and
does not change the base graph's generic state. CORE supplies context only; it
does not copy, inherit or merge provider state during Clone or Variant
Duplicate operations.

## Failure behavior

If `build_proc` or `load_proc` fails, the provider area displays
**Provider extension unavailable** with the callback error. The standard editor
remains open, but Add/update is rejected for that editor instance so GX-TXT
cannot imply that provider-specific state was saved.

Validation and save failures remain retryable and are displayed explicitly.
A missing registration is different from a failed extension: no provider area
is created and the legacy standard editor behavior is preserved.

A cleanup error is written to the normal diagnostic stream because the editor
widget no longer exists.

## Ownership boundaries

CORE owns:

- the standard Series Editor and generic Graph Series state;
- callback ordering and context;
- the approved provider widget container;
- normal validation/error integration;
- rollback of generic Graph Series state after a provider save failure.

The provider owns:

- its controls and editor-local values;
- provider-specific meanings and defaults;
- validation rules;
- persistent per-series state;
- atomic provider save behavior;
- state reload and cleanup.

Providers must not inspect private Tcl arrays, private widgets, session files,
or Graph Series storage. They must not store provider properties through
`graphSeriesSet`.

## GX-TXT 0.9.7.22 clean-start activation

Before lookup, CORE inspects the target module descriptor and activates public
APIs whose capability list contains series_editor_extension. Successful
activation is cached by module and API ID. Repeated editor opens are idempotent;
failed activation is not cached and appears as an explicit unavailable provider
area. The build/load/validate/save/close callback lifecycle is unchanged.

### Host widget path

Since GX-TXT 0.9.7.43 the shared plotting dialogs may place provider UI inside a scrollable canvas body. Extension providers must treat the `parent` widget supplied by CORE as opaque and build only beneath that widget; they must not hard-code `.axiscfg` or `.graphseriesbase` child paths. This is a GUI-hosting change only and does not change the API version.

