> **Historical note:** superseded by `GRAPHICS_V15_IMPLEMENTATION.md` in v15.

# GX-TXT Replicate Curve Analysis — Complete Plot Dataset v3 Integration Procedure

SPDX-License-Identifier: GPL-3.0-or-later

## 1. Purpose

This document defines the required graphics architecture for `curve.replicate_analysis` on GX-TXT 0.9.8.10-dev-031 and later compatible builds.

The objective is not merely to generate PNG files. The four scientific result graphs must:

- retain producer identity as `curve.replicate_analysis`;
- use the complete public `plot.dataset` rendering stack rather than a private Octave renderer;
- expose every applicable shared graph feature provided by the framework;
- survive save/reopen and rerender without duplicating graph state;
- inherit future generic `plot.dataset` improvements without module-specific reimplementation.

This document records both the module-side procedure and the public-API gap found in dev-031 that currently prevents satisfying all of these requirements simultaneously.

## 2. Required graph identities

The producer-visible graph identities are fixed and module-owned:

```text
curve.replicate_analysis / curve.replicate.overlay
curve.replicate_analysis / curve.replicate.consensus_uncertainty
curve.replicate_analysis / curve.replicate.uncertainty_components
curve.replicate_analysis / curve.replicate.family_summary
```

The Graphs window must present these graphs under the `Replicate Curve Analysis` module. `plot.dataset` is the renderer/provider implementation and must not replace the scientific producer identity shown to the user.

## 3. The two defects that must be solved independently

### 3.1 Wrong ownership when using persistent Plot Dataset variants

Calling `PLOT_DATASET_API_v2/v3` to create or upsert a persistent graph produces a real `plot.dataset` plot reference. The public implementation enforces this in `PlotDatasetAPIv1::_normalizePlotRef`:

```text
module_id must equal plot.dataset
```

Therefore a persistent graph created by `PlotDatasetAPIv3::upsertPlotFromSpec()` is owned by `plot.dataset`, even when `producerModuleId=curve.replicate_analysis` is supplied in the provider key.

The producer key gives stable producer-scoped lookup; it does not transfer graph ownership.

### 3.2 Incomplete shared functionality when rendering module-owned PNGs privately

Keeping the graph under `curve.replicate_analysis` while rendering it directly in Octave fixes the visible owner, but bypasses substantial `plot.dataset` functionality.

A private renderer may use `gxtxt_plot_legend()`, `gxtxt_plot_apply_graph_axes()` and `gxtxt_print_png_atomic()`, but that is still not equivalent to the current Plot Dataset stack. In particular, it does not automatically inherit the complete persistent model for:

- Graph Series;
- per-series representation and style;
- row filters and family expansion;
- multi-panel layout and panel assignment;
- panel title and panel-local axis presentation;
- display units and scale configuration;
- the Plot Dataset Graph Configuration Extension;
- the Plot Dataset Series Editor Extension;
- the Plot Dataset Axis Configuration Extension;
- PlotSpec v2 reconciliation;
- Plot Dataset cache and rerender semantics.

These are separate from the generic legend and axis helpers.

## 4. Authoritative framework rule

The framework file `GX-TXT_PLOT_DATASET_MIGRATION_TODO_v09804.md` states the mandatory architecture for scientific result plots:

```text
module scientific computation
        ↓
Dataset / derived Dataset / Publication
        ↓
PLOT_DATASET_PLOTSPEC_v2 / supported public plot contract
        ↓
plot.dataset
        ↓
Graph Provider / shared graphics infrastructure
        ↓
rendering, configuration, persistence and rerender
```

It explicitly identifies `curve.replicate_analysis` as a migration target and forbids retaining a private renderer merely because direct Octave plotting is convenient.

It also establishes the missing-functionality rule: if the current public Plot Dataset API cannot represent a required generic workflow, extend the shared API instead of bypassing it in the module.

## 5. Public APIs that belong in the final architecture

The final module should consume the following public GX-TXT contracts where applicable:

```text
MODULE_API_v1
ANALYSIS_SOURCE_MAP_API_v1
ANALYSIS_SOURCE_METADATA_RUNTIME_v1
ANALYSIS_SOURCE_ACCESS_RUNTIME_v2
DATASET_VARIABLE_SCHEMA_API_v3
TABLE_STREAM_API_v3
DATASET_PUBLICATION_API_v2
DATASET_PUBLICATION_V2_OCTAVE_BINDING
NUMERIC_API_v1
GRAPH_PROVIDER_API_v1
PLOT_MODULE_API_v1
GRAPH_WORKFLOW_API_v1
GRAPH_SERIES_API_v1
GRAPHICS_INHERITANCE_API_v1
PLOT_ANNOTATION_API_v1
PLOT_REGION_SELECTION_API_v1          when a graph opts into selection
DATASET_SELECTION_API_v1              when a graph produces a selection
PLOT_DATASET_API_v3
PLOT_DATASET_OCTAVE_BRIDGE_v1         until a v3 standard-Octave bridge supersedes it
PROGRESS_API_v1
DOCUMENTATION_API_v1
```

The Plot Dataset implementation itself additionally uses the public extension contracts:

```text
SERIES_EDITOR_EXTENSION_API_v1
GRAPH_CONFIG_EXTENSION_API_v1
AXIS_CONFIG_EXTENSION_API_v1
```

A consumer should not copy Plot Dataset's private Tcl arrays, PlotSpec files, runtime files or renderer implementation.

## 6. Scientific Dataset publication remains module-owned

`curve.replicate_analysis` should continue to publish a small number of canonical derived Datasets rather than one Dataset per trace.

The current aggregate model is appropriate:

```text
curve.replicate.traces
curve.replicate.profiles
curve.replicate.family_summary
```

Recommended logical content:

### `curve.replicate.traces`

Long-form trace data suitable for family/filter grouping:

```text
x
y
trace_index
source_index
replicate_index
family_value
```

Optional future additions may include stable text labels if they are scientifically useful, but display labels must not replace numeric family coordinates.

### `curve.replicate.profiles`

Long-form statistical profiles containing at least:

```text
x
family_value
mean
median
std
sem
sigma_within
sigma_between
sigma_total
lower_std
upper_std
lower_sem
upper_sem
lower_sigma_total
upper_sigma_total
```

### `curve.replicate.family_summary`

Family-level summary values for bar plots, with stable numeric family identity plus the selected summary statistics.

Publication must continue through Dataset Publication API v2 with `replace_owned=true` for stable derived IDs.

## 7. Required Plot Dataset representations

All four graphs are representable with existing PlotSpec v2 primitives.

### 7.1 Replicate overlay

Data source:

```text
curve.replicate.traces
```

Representation:

- X = `x`;
- Y = `y`;
- line / line-marker / scatter as appropriate;
- one series per trace or a family-grouped representation using stable filters;
- optional family filtering through Graph Series row filters;
- no private `plot()` calls.

### 7.2 Consensus and uncertainty

Data source:

```text
curve.replicate.profiles
```

Representation:

- center line = `mean` (or configured supported center);
- uncertainty `band` using one of:
  - `lower_std` / `upper_std`;
  - `lower_sem` / `upper_sem`;
  - `lower_sigma_total` / `upper_sigma_total`;
- series grouped or filtered by `family_value`;
- all style and axis presentation delegated to Plot Dataset.

### 7.3 Uncertainty components

Data source:

```text
curve.replicate.profiles
```

Representation:

- `sigma_within`;
- `sigma_between`;
- `sigma_total`;
- line series with stable family filtering/grouping;
- missing/non-identifiable components are omitted from drawable series instead of replaced by invented values.

### 7.4 Family uncertainty summary

Data source:

```text
curve.replicate.family_summary
```

Representation:

- numeric `bar` series;
- within / between / total summaries;
- stable family coordinate/labels;
- no module-private `bar()` implementation.

## 8. Functionality that must come from the shared stack

A successful migration must make the following available through the normal Graphs workflow, not through module-specific replacements.

### 8.1 Graph Provider / Plot Module

- enable/disable graph offering;
- stable graph ID;
- persistent graph configuration;
- output contract;
- variants / clone;
- USE / NON USE;
- save/reopen;
- rerender.

### 8.2 Graph Series

- Dataset selection;
- stable X/Y Variable IDs;
- left/right axis assignment;
- label;
- enable/disable;
- ordering;
- primary family variable;
- secondary parameter variable;
- exact row filters;
- explicit ordering variable;
- family expansion where scientifically meaningful.

### 8.3 Plot Dataset series presentation

Where applicable:

- representation kind;
- line/scatter/line-marker/step;
- error bars;
- uncertainty bands;
- bar geometry;
- line style;
- line width;
- marker;
- marker size;
- marker fill;
- opacity;
- automatic color policy.

### 8.4 Axes and units

- X/Y/Y2 ranges;
- automatic/manual bounds;
- tick step and formatting;
- linear/log scaling where scientifically valid;
- display units;
- grid mode/source/color;
- Y-label alignment;
- panel-local axes in multi-panel mode.

### 8.5 Layout and panels

- single/multi-panel mode;
- add/remove/reorder panels;
- assign series to panels;
- shared-X behavior;
- panel titles;
- panel-local Y Left/Y Right presentation;
- persistent layout geometry.

### 8.6 Legend

- inside / above / below / left / right / manual;
- row / stacked / wrapped;
- alignment;
- columns;
- background;
- border;
- font settings;
- manual placement.

### 8.7 Other shared graph services

- annotations;
- export / print;
- region selection when declared;
- standard graphics inheritance;
- cache-aware rerender;
- plot geometry metadata.

## 9. Why `variant_data_model=module_cache` is insufficient

`module_cache` is useful for graphs whose scientific series are entirely module-defined and where variants need presentation-only Plot/Graphics controls.

It intentionally omits bindings and the Series editor. Therefore it cannot provide full Plot Dataset behavior for a graph that must expose editable series, family/filter state, advanced per-series presentation and panel assignment.

For this module's complete migration, `module_cache` is not the final architecture.

## 10. Why direct use of `PLOT_DATASET_API_v3` currently changes ownership

The current Plot Dataset v1/v2/v3 facade is module-specific by design.

`PlotDatasetAPIv1::_normalizePlotRef` validates:

```text
plotRef.module_id == plot.dataset
```

All v2/v3 persistent operations delegate through that identity.

Consequences:

- `createPlotFromSpec()` creates `plot.dataset` base/variant state;
- `upsertPlotFromSpec()` creates/reuses a `plot.dataset` variant;
- `setSeriesPresentation()` operates on a `plot.dataset` plot reference;
- panel APIs operate on a `plot.dataset` plot reference;
- `openEditor()` opens the Plot Dataset-owned editor state.

`producerModuleId` in `upsertPlotFromSpec()` scopes the provider key. It does not change `module_id` ownership.

## 11. Why the current `automatic_graphs.ini` bridge does not solve ownership

The current Graph Workflow code recognizes `automatic_graphs.ini` records whose provider is `plot.dataset`.

Its behavior is alias-oriented:

- module output PNG may be retained as an output-contract copy;
- when the provider artifact exists, the module PNG is hidden from Graphs;
- the canonical editable graph is the `plot.dataset` variant.

This prevents duplicate editable graphs, but visible ownership remains `plot.dataset`.

The bridge has no public producer-owned graph reference and no ownership delegation record.

## 12. Why transient v3 rendering does not solve the problem

`renderTransientOverlay`, `renderTransientCurves2D` and related v3 operations are intentionally non-persistent preview APIs.

They do not create:

- Graph Series;
- PlotSpec persistent state;
- plot variants;
- complete Graph Workflow state.

They therefore cannot provide the required save/reopen/editor/variant behavior for production scientific result graphs.

## 13. Public API gap in GX-TXT 0.9.8.10-dev-031

The missing generic capability is:

> Delegate the complete Plot Dataset renderer and persistent presentation model to a graph whose authoritative producer identity is another Graph Provider module.

In other words, the framework needs a producer-owned graph reference whose rendering provider is `plot.dataset`.

This is not a `curve.replicate_analysis` special case. It is a generic requirement for every scientific module listed in the Plot Dataset migration TODO.

## 14. Recommended generic framework extension

The smallest robust solution is a public delegated-render graph contract. The exact API name may follow project conventions; the semantics should be equivalent to the following.

### 14.1 Producer identity

Authoritative graph identity:

```text
producer_module_id
producer_graph_id
producer_variant_id
```

Example:

```text
curve.replicate_analysis
curve.replicate.consensus_uncertainty
p0001
```

### 14.2 Renderer identity

Delegated renderer reference:

```text
renderer_module_id=plot.dataset
renderer_graph_id=plot.dataset.xy
renderer_variant_id=<framework-owned backend identity>
```

The renderer identity must be an implementation detail of the delegation and must not replace the producer identity in the Graphs UI or producer metadata.

### 14.3 Required operations

A generic public operation should support at least:

```text
upsert delegated graph from PlotSpec
apply/update PlotSpec
render
rerender
open full editor
resolve artifacts
remove delegated graph
```

The operation should preserve stable producer graph identity across reruns.

A possible API shape is conceptually:

```tcl
set ref [::GX::PlotDatasetAPIv3::upsertProducerPlotFromSpec \
    curve.replicate_analysis \
    curve.replicate.consensus_uncertainty \
    $producerVariantId \
    $providerKey \
    $plotSpec]
```

The actual naming is less important than preserving the ownership contract.

### 14.4 Standard-Octave bridge

`standard_octave` also needs a public bridge operation for the delegated call. Modules must not source `gxtxt_pipeline.tcl`, inspect private Tcl arrays, or write Plot Dataset state files directly.

A v3 bridge should expose the delegated upsert/render lifecycle rather than forcing consumers to invoke private Tcl.

### 14.5 Persistence

Manifest state should distinguish producer and renderer identity explicitly.

Conceptually:

```ini
[delegated_graph.1]
producer_module_id=curve.replicate_analysis
producer_graph_id=curve.replicate.consensus_uncertainty
producer_variant_id=
renderer_module_id=plot.dataset
renderer_graph_id=plot.dataset.xy
renderer_variant_id=p0123
provider_key=curve.replicate_analysis:curve.replicate.consensus_uncertainty
```

This is illustrative. The final schema should be owned by the framework API and must not be written directly by modules.

### 14.6 Graphs-window behavior

The Graphs window must display:

```text
Module: Replicate Curve Analysis
Plot:   02_consensus_uncertainty.png
```

while routing supported editor/render actions through the delegated Plot Dataset reference.

All of the following must operate on the producer-visible graph:

- Configure;
- Series;
- Axes/grid;
- Legend;
- Variants/clone;
- USE/NON USE;
- annotations;
- rerender;
- export/print.

The user must not see a duplicate renderer-owned `Scientific Dataset Plot` row for the same producer graph.

## 15. Module-side procedure after the delegated-render API exists

Once the generic delegation capability is available, `curve.replicate_analysis` should be simplified substantially.

### Step 1 — keep numerical analysis unchanged

Preserve the verified replicate grouping, common-grid construction, interpolation, consensus, uncertainty and ANOVA logic.

### Step 2 — keep canonical Dataset publication

Publish only the aggregate reusable result Datasets through Dataset Publication API v2.

### Step 3 — remove all private graph rendering

Delete production use of:

```text
plot(...)
bar(...)
xlim(...)
ylim(...)
gxtxt_plot_new_figure(...)
gxtxt_print_png_atomic(...)
private legend/layout code
```

The module must not own a replacement renderer.

### Step 4 — build PlotSpec v2 objects only

For each graph, create a declarative PlotSpec referencing the published Dataset and stable Variable IDs.

### Step 5 — upsert delegated producer graphs

Call the delegated public Plot Dataset API using the producer graph identity.

### Step 6 — persist only through framework APIs

Do not write:

```text
runtime.ini
PlotSpec files
Graph Series registries
plot.dataset variant directories
manifest graph sections
```

directly.

### Step 7 — let Graph Workflow own presentation lifecycle

The module should no longer contain a scientific graph rerender implementation. Rerender should resolve the delegated provider state through the framework.

## 16. PlotSpec construction for the four graphs

### Overlay

Use the aggregate trace Dataset. Prefer stable Graph Series IDs and row filters rather than materializing one Dataset per trace.

Representative series state:

```text
dataset_id=curve.replicate.traces
x_variable_id=x
y_variable_id=y
filter_variable_id=trace_index
predicate=exact_equal
value=<trace>
```

`family_value` remains available for family filtering/grouping.

### Consensus and uncertainty

Use `curve.replicate.profiles`.

Representative PlotSpec series:

```text
kind=band
x_variable_id=x
y_variable_id=mean
band.lower_variable_id=lower_std
band.upper_variable_id=upper_std
band.draw_center=1
```

Equivalent variables are selected for SEM or total uncertainty.

### Uncertainty components

Use three line series against the same profile Dataset:

```text
sigma_within
sigma_between
sigma_total
```

Family filtering is expressed through stable row filters.

### Family summary

Use numeric bar series from `curve.replicate.family_summary`.

## 17. Required module descriptor state

The producer should continue declaring its four stable graph offerings through Graph Provider API v1.

The descriptor should advertise all actual public API dependencies used by the final implementation. Do not claim `module_cache` as the final solution if the complete Plot Dataset editor is expected.

Once delegated rendering is authoritative, any module graph fields duplicated by Plot Dataset should be minimized so that one framework authority owns each presentation concept.

## 18. Migration cleanup

After the final architecture is active:

- remove `curve_replicate_render_public.m` private drawing logic;
- remove cache-only private graphics metadata that exists only for direct drawing;
- remove old `automatic_graphs.ini` compatibility generation if superseded by the delegated graph API;
- retain only scientific cache/output required by analysis itself;
- retain old Session compatibility only where it does not create a second graphics authority.

Historical `plot.dataset` variants from development runs are Session cleanup, not part of the production module migration.

## 19. Minimum acceptance checks

A real GUI check is required. A successful PNG alone is insufficient.

For each of the four graphs verify:

1. Graphs shows `Replicate Curve Analysis` as the producer module.
2. No duplicate visible `Scientific Dataset Plot` graph represents the same result.
3. Legend placement changes and rerenders correctly.
4. Axes/ranges/grid/display-unit controls work and persist.
5. Series representation/style controls work where applicable.
6. Family/filter/order state is persistent where applicable.
7. Variant clone/edit/rerender is isolated from the base graph.
8. Save, close, reopen and rerender preserve presentation state.
9. Numerical CSV/Dataset outputs are unchanged by graphics-only edits.
10. No module-private direct scientific result plotting remains.

## 20. Current dev-031 conclusion

GX-TXT 0.9.8.10-dev-031 already contains nearly all required pieces, but its Plot Dataset persistent facade owns only `plot.dataset` plot references.

The following combination is therefore not yet exposed as one public operation:

```text
producer owner = curve.replicate_analysis
renderer       = plot.dataset v3
full v3 editor = yes
persistent     = yes
single visible graph identity = yes
```

Attempting to solve this solely inside `curve.replicate_analysis` produces one of two known defects:

- complete Plot Dataset behavior with the wrong visible owner; or
- correct module owner with an incomplete/private graphics implementation.

The correct next step is the generic delegated-render API described above. After that shared capability exists, the module migration is straightforward and should remove, rather than add, graphics code.

## 21. Rule for future module work

For scientific result plots:

```text
Publish scientific Datasets.
Describe plots declaratively.
Use the shared Plot Dataset renderer.
Keep producer identity separate from renderer implementation.
Do not redraw framework functionality inside the module.
```

That is the architecture this module should follow before its final HTML documentation is produced.
