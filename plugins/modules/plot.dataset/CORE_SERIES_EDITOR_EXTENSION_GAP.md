# Known non-blocking CORE gap — extending the standard Graph Series editor

## Scope

`plot.dataset` 2.0.0 adds per-series presentation fields through
`PLOT_DATASET_API_v2` and provides a module-owned `openEditor` GUI that edits
those fields. The existing GX-TXT standard Graph Series editor continues to own
and edit the generic CORE fields:

- series ID;
- enabled;
- dataset;
- X variable;
- Y variable;
- left/right axis;
- label;
- order.

## Why the existing `Series...` window is not modified by the plugin

In the inspected GX-TXT public interface, `series_editor=standard` causes CORE
to open `graphSeriesEditorBase`/`graphSeriesEditorBuild`. The Graph Series API
v1 validates a fixed generic field set. There is no descriptor/public hook for
a provider to:

- append provider-owned columns/controls to that window;
- attach provider-owned series attributes;
- supply a secondary details editor callback.

Changing those CORE Tcl procedures from `plot.dataset` would be a monkey patch
and would couple the plugin to private GUI implementation. Extending Graph
Series itself with plotting-specific style keys would also be wrong because
not every graph provider needs plot.dataset styling.

## Correct future CORE extension

A small generic editor-extension mechanism would be sufficient. Conceptually,
a graph descriptor could declare an optional public callback/capability such as
`series_details_editor=<public command>` or an equivalent registered provider
hook. CORE would keep Graph Series identity/binding fields authoritative and
would offer an `Advanced...`/`Details...` action for provider-owned state.

The hook should receive only stable context:

```text
module_id
graph_id
variant_id
series_id
parent/toplevel context
```

The provider would persist its own public state. No provider-specific style
keys need to be added to Graph Series API v1.

## Current behavior

Until such a CORE hook exists:

- the standard `Series...` window remains unchanged and fully compatible;
- `::GX::PlotDatasetAPIv2::openEditor $plotRef` is the supported expanded
  plot.dataset editor;
- API consumers use the PlotSpec directly;
- no CORE file is modified by the 2.0.0 plugin package.

GX-TXT 0.9.7.17 intentionally leaves this editor extension open. PlotSpec v2 and the standalone API editor are available without modifying the standard Series editor. The optional Tk editor is loaded only by openEditor; headless API calls do not load it.

## Status update — GX-TXT 0.9.7.21

The generic callback/lifecycle gap described above is resolved by CORE
**Series Editor Extension API v1**. The API supplies provider registration,
base/variant/series context, build/load/validate/save/close callbacks, generic
Graph Series snapshots, pre-commit validation, and generic-state rollback if a
provider save fails.

`plot.dataset` 2.1.0 implements the extension callbacks/registration, but still cannot activate them in the normal clean
startup path because GX-TXT 0.9.7.21 does not expose a public provider
activation/bootstrap mechanism that loads descriptor-based provider code before
the standard Series editor resolves registered extensions. That separate,
reproducible integration blocker is documented in
`CORE_SERIES_EDITOR_EXTENSION_ACTIVATION_GAP.md`. The historical description
above is retained to preserve the record of the original requirement.
