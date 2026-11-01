# CORE integration notes — plot.dataset 3.9.0

Plot Dataset 3D API v1 is additive to public APIs v1/v2/v3. Plot Dataset
owns scientific Dataset binding, preparation, graph family choice and static
rendering. It publishes derived, Session-owned VTP artifacts through Viewer
Provider API v1 with source Dataset ID and digest. Native 3D owns interactive
rendering only. No analysis module should call the Native 3D host protocol or
read Plot Dataset's prepared cache directly.

SPDX-License-Identifier: GPL-3.0-or-later

Integration baseline: **GX-TXT Pipeline 0.9.7.56**. plot.dataset remains a bundled core=1 Standard Module and is developed/tested directly in the framework source tree; it is not installed through Plugin Install API.

## GX-TXT 0.9.7.56 layout persistence

The final 3D-aware CORE runtime writer now carries the existing per-graph layout fields even when the independent Axes override is disabled. This is required because the Plot layout surface owns those fields separately from the Axes dialog. The change introduces no public API or schema. Plot geometry, external-legend bands, title placement and label positioning remain module-owned.



## GX-TXT 0.9.7.48 runtime lifecycle

Before runtime serialization, CORE activates the declared provider and asks plot.dataset to reconcile PlotSpec presentation with current Graph Series stable IDs. Runtime and render cache remain derived state: normal rerender regenerates a missing cache and the module rebuilds an incompatible, incomplete or unreadable cache from persistent configuration. Explicit render requests select the requested base/variant even when USE is off without modifying persistent USE. Variant serialization restores the base runtime, and summaries are rewritten for the selected graph on every render/rerender. This path never deletes or recreates variants.

## GX-TXT 0.9.7.43 plotting-dialog additions

0.9.7.43 adds one generic reusable scrollable-dialog body used by the shared Axes dialog and standalone Graph Series editor. The change is presentation-only and exists because multi-panel/provider controls can exceed notebook-height displays. The existing Level Scale button resolves the new scroll-body button frame with a legacy-layout fallback.

`plot.dataset` 3.3.4 keeps CORE data immutable and establishes one module-internal temporal-X contract: seconds. Canonical Dataset API v2 already emits HMS elapsed-time values as numeric seconds; the module now normalizes other elapsed-time representations to the same coordinate before any display conversion. The original declared unit remains descriptive source metadata.

## GX-TXT 0.9.7.42 lifecycle / Series-editor additions

0.9.7.42 adds only generic CORE support required by the dataset-deletion and large-Series failure cases exposed by `plot.dataset`:

- Graph Series records whose dataset or stable X/Y variable no longer exists are pruned rather than causing every consumer to fail.
- Dataset deletion immediately removes the declared graph artifact when that deletion removes the last Graph Series in a graph/variant scope.
- The standard Series table is vertically scrollable.
- Series Editor Extension API v1 accepts optional provider-owned read-only table columns; `plot.dataset` uses one `Panel` column.

Provider-owned PlotSpec reconciliation remains inside `plot.dataset`; CORE does not inspect PlotSpec or panel state.


## Minimal CORE change

GX-TXT 0.9.7.39 adds **Graph Configuration Extension API v1**. The API gives a descriptor-declared graph provider one provider-owned widget container inside the normal Graph configuration surface and inside the Variant editor Plot tab. CORE passes stable `module_id`, `graph_id`, and `variant_id`; it does not know about panels or `plot.dataset` state.

GX-TXT 0.9.7.41 adds **Axis Configuration Extension API v1** and re-exposes the already-existing CORE per-panel Y/Y2 override state in the shared Axes dialog only for real stacked artifacts. The new hook is artifact-based so `plot.dataset` API consumers receive the same extended panel presentation controls.

The CORE source points added/changed for the 0.9.7.39–0.9.7.41 multi-panel integration are:

```text
core/tcl/graph_config_extension_api_v1.tcl
core/tcl/axis_config_extension_api_v1.tcl
core/tcl/scientific_plot_framework_api_v1.tcl
gxtxt_pipeline.tcl
core/tcl/graph_workflow_api_v1.tcl
```

Those points carry short `plot.dataset multi-panel` comments identifying why the hook exists and what it adds. The public API manual is `docs/api/GRAPH_CONFIG_EXTENSION_API_v1.md`.

## Module ownership

`plot.dataset` owns all multi-panel semantics through PLOT_DATASET_API_v2 / PlotSpec v2:

- explicit `multi_panel` state;
- panel create/remove/order;
- optional panel title;
- panel-local Y Left/Y Right presentation;
- series-to-panel assignment keyed by stable `series_id`.

Graph Series scientific identity remains:

```text
dataset_id + x_variable_id + y_variable_id
```

Panel state never enters Graph Series and never creates a second series registry.

## GUI ownership

The normal **Graph configuration** window owns multi-panel enablement and panel lifecycle. The standard **Series...** editor shows only an existing-panel selector while multi-panel mode is enabled and hides it when disabled.

The graph title and X domain remain graph-wide. Each panel may have an optional title and independent Y Left/Y Right presentation. `plot.dataset.xy_region` remains single-panel.

## Preserved data path

The CORE hook does not modify Canonical Dataset, Table Stream, Dataset Selection, typed-binary transport, FFT, storage or graphics data preparation. `plot.dataset` continues to consume:

```text
Canonical Dataset API v2
→ Table Stream API v3
→ typed-binary numeric transport when available
→ bounded presentation reduction
→ renderer
```

Implicit coordinates remain virtual and canonical scientific datasets are not modified.

## API compatibility

- `PLOT_DATASET_API_v1` remains byte-identical.
- `PLOT_DATASET_API_v2` remains API version 2 and is extended additively.
- Pre-3.2 multi-panel PlotSpecs without an explicit `multi_panel` field remain multi-panel when they contain more than one panel.
- Explicitly disabling multi-panel preserves saved panel presentation for later re-enable while rendering through the established single-panel path.

GX-TXT 0.9.7.41 keeps artifact discovery public and additionally makes `stackedGraphPanels(path)` honor the effective `multiPanelEnabled` state before exposing panels. The shared Axes dialog then shows generic per-panel CORE overrides and activates the public Axis Configuration Extension API v1 for provider-specific presentation; no private PlotSpec file is inspected.

## Notebook-size GUI behavior

GX-TXT 0.9.7.43 provides a reusable scrollable dialog body used by the shared Axes dialog and standalone Graph Series editor. This is a CORE presentation facility only; panel scientific identity and PlotSpec state remain module-owned.
