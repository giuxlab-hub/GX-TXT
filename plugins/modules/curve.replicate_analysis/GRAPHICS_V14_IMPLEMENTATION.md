> **Historical note:** superseded by `GRAPHICS_V15_IMPLEMENTATION.md` in v15.

# Replicate Curve Analysis v14 — Plot Dataset v3 Integration

SPDX-License-Identifier: GPL-3.0-or-later

## Objective

`curve.replicate_analysis` must own the scientific graph identity while delegating all scientific rendering to the public `plot.dataset` stack. The module must not implement private plotting primitives.

The producer-visible graph IDs are:

- `curve.replicate.overlay`
- `curve.replicate.consensus_uncertainty`
- `curve.replicate.uncertainty_components`
- `curve.replicate.family_summary`

## Architecture

The v14 path is:

```text
curve.replicate_analysis numerical computation
    -> Dataset Publication API v2
    -> module-owned Graph Series API v1 state
    -> PLOT_DATASET_PLOTSPEC_v2
    -> PLOT_DATASET_API_v3 backend variant
    -> public plot.dataset renderer
    -> producer-owned PNG + plot metadata copy
```

The backend `plot.dataset` variant is an implementation detail. Its rendered PNG and geometry sidecar are removed after a successful delegated render so the Graphs window exposes only the producer-owned artifact.

## Why v13 was incomplete

v13 used a module-owned cache renderer. That preserved the module name but bypassed part of the full Plot Dataset presentation lifecycle. In particular, Plot layout values were stored under the producer graph key while rendering occurred through a different backend graph key, so layout controls could not reliably affect the final graph.

v14 removes the private renderer entirely.

## Public APIs used

v14 uses only public framework surfaces:

- `GRAPH_PROVIDER_API_v1`
- `PLOT_MODULE_API_v1`
- `GRAPH_WORKFLOW_API_v1`
- `GRAPH_SERIES_API_v1`
- `SERIES_EDITOR_EXTENSION_API_v1`
- `PLOT_DATASET_API_v2`
- `PLOT_DATASET_API_v3`
- `PLOT_DATASET_PLOTSPEC_v2`
- `DATASET_PUBLICATION_API_v2`
- `RENDER_CACHE_API_v1`
- `SCIENTIFIC_PLOT_FRAMEWORK_API_v1`

## Graph Series ownership

Each declared graph uses:

```ini
supports_variants=1
variant_data_model=series
series_editor=standard
```

The standard Series editor therefore edits Graph Series owned by `curve.replicate_analysis`, not a second private series registry.

Default Series are created only after their derived Datasets exist. Existing user-edited Series are never overwritten merely because a rerender occurs.

## Derived Dataset mapping

### Replicate overlay

Dataset: `curve.replicate.traces`

Default Series:

- X: `x`
- Y: `y`
- family/group field: `trace_index`
- secondary field: `family_value`

### Consensus and uncertainty

Dataset: `curve.replicate.profiles`

Default Series:

- X: `x`
- Y: `mean`
- family/group field: `family_index`
- secondary field: `family_value`

The selected uncertainty band is represented with standard PlotSpec band bindings:

- `y_std` -> `lower_std` / `upper_std`
- `y_sem` -> `lower_sem` / `upper_sem`
- `sigma_total` -> `lower_sigma_total` / `upper_sigma_total`

### Uncertainty components

Dataset: `curve.replicate.profiles`

Default Series:

- `sigma_within`
- `sigma_between`
- `sigma_total`

All use X=`x` and group by `family_index`.

### Family summary

Dataset: `curve.replicate.family_summary`

Default bar Series:

- within: `x_within` / `within_rms`
- between: `x_between` / `between_rms`
- total: `x_total` / `total_rms`

The graph-level summary selector can switch the default Series to `*_mean` or `*_max` without changing custom Series added by the user.

## Presentation-state projection

Before asking `plot.dataset` for its public `renderCommand`, the bridge projects the producer graph presentation into the hidden backend variant.

### Axes / grid / Plot layout

The producer runtime `[axis.<producer-graph-id>]` section is copied into the backend graph key. This includes:

- X/Y/Y2 limits
- display units
- tick step and format
- grid mode/source/color
- panel-local overrides
- `layout_auto`
- `layout_margin_left`
- `layout_margin_right`
- `layout_margin_top`
- `layout_margin_bottom`
- `layout_gap`
- `layout_ylabel_dist`

This is the v14 fix for the Plot layout defect.

### Legend

The producer runtime `[legend.<producer-graph-id>]` state is projected into the backend graph key before rendering. Placement, manual coordinates, layout, alignment, columns, fonts and border settings therefore use the same renderer as normal Plot Dataset graphs.

### Level Scale

Y/Y2/Z Level Scale state is copied through the public Level Scale API before the backend runtime is generated.

### Graphics overrides

Resolved graphics settings are projected through Plot Module variant graphics setters. Width, height, DPI, typography, line defaults and related inherited graphics state are therefore applied by the standard renderer.

## Series presentation

The standard Series editor owns scientific bindings and ordering. A small provider extension adds presentation controls that are not fields of the generic Graph Series record:

- representation kind
- color
- line style
- line width
- marker
- marker size
- marker fill
- opacity

This state is stored under the module analysis directory and merged into the PlotSpec on each delegated render.

## Backend variant lifecycle

`PLOT_DATASET_API_v3::upsertPlotFromSpec()` is used with a stable producer key:

```text
curve.replicate_analysis:v14:<graph-id>:<base-or-producer-variant>
```

This guarantees that an existing backend variant receives the updated PlotSpec instead of silently retaining an older PlotSpec.

The backend variant is set to `Use=no` so it is never added to ordinary scheduled `plot.dataset` runs. Explicit API rendering remains available.

After a successful render:

1. the backend graph PNG is copied to the producer graph filename;
2. the matching `.gxtxt_plotmeta` sidecar is copied and renamed;
3. the backend PNG and sidecar are removed;
4. PlotSpec/cache/variant state remains available for the next delegated render.

## Rerender

A producer rerender reads `render_cache.mat`, regenerates the current producer runtime, then invokes the same v14 delegated-render path. No private plot code is used.

Because the PlotSpec is rebuilt from the producer Graph Series and current graph configuration every time, Series edits, graph configuration, layout, axes and legend changes are reflected on the next rerender.

## What the module must not do

The production runtime must not implement scientific result rendering with:

```text
plot()
bar()
errorbar()
semilogx()
semilogy()
loglog()
legend()
xlim()
ylim()
gxtxt_plot_new_figure()
gxtxt_print_png_atomic()
```

A static scan of the v14 runtime should return no such calls.

## Fresh-session acceptance test

1. Install v14 of `curve.replicate_analysis` only.
2. Start GX-TXT fresh and create/open a clean Session.
3. Import valid repeated-curve datasets.
4. Bind X, Y, optional Family and optional Replicate ID.
5. Run the analysis once.
6. Verify the four graphs appear under `curve.replicate_analysis`.
7. Open **Series...** and change a Series binding/style, then rerender.
8. Move the legend and rerender.
9. Change Axes/Grid settings and rerender.
10. Disable Automatic in **Plot layout**, move left/right/top/bottom sliders and Y-label spacing, then **Apply and rerender**.
11. Create a plot variant and repeat the same checks.
12. Save, close GX-TXT, reopen the Session and rerender again.

Acceptance requires that all edits persist and that no rendered duplicate `plot.dataset` graph appears in the Graphs window.

## Known independent framework issue

The GX-TXT `New Session` lifecycle observed during debugging can serialize stale in-memory Session state into a newly created manifest if a previous Session was open. That issue is independent from `curve.replicate_analysis` v14 and should be fixed in the Session lifecycle separately.
