# GX-TXT Shared Graphics Architecture

SPDX-License-Identifier: GPL-3.0-or-later

## Purpose

The GX-TXT graphics layer is a reusable Octave plotting API. Scientific modules calculate quantities; the graphics layer handles presentation, overrides, legends, axes, font scaling, and reliable PNG export.

The intended data flow is:

```text
acquisition data
    -> scientific analysis module
    -> numerical results + render_cache.mat
    -> module renderer
    -> shared gxtxt_plot_* API
    -> PNG files
```

This separation is important because future modules such as Bode analysis, filter characterization, transformer measurements, or impedance measurements should reuse the same visual system instead of reimplementing plot logic.

## Core functions

- `gxtxt_setup_graphics.m` — selects the requested toolkit/visibility and initializes local Qt with direct GLX, preventing inherited remote indirect-GL settings from crashing export. It logs the effective context policy.
- `gxtxt_plot_config.m` — loads global graphics configuration from the environment.
- `gxtxt_plot_new_figure.m` — creates a figure with the requested pixel dimensions.
- `gxtxt_plot_font_to_points.m` — converts the configured font unit to the Octave point value required for export.
- `gxtxt_plot_apply_axes.m` — applies shared axis style, tick fonts, and global grid defaults.
- `gxtxt_plot_apply_graph_axes.m` — graph-aware helper retained for compatibility and explicit use; it combines base axes styling with graph/panel override application.
- `gxtxt_plot_text.m` — creates title, X label, and Y label using common font rules.
- `gxtxt_plot_node_label.m` — resolves the display alias of a logical node.
- `gxtxt_plot_node_color.m` — resolves the base color of a logical node.
- `gxtxt_plot_legend.m` — creates and positions legends using global or local settings.
- `gxtxt_plot_legend_override.m` — resolves per-plot legend overrides.
- `gxtxt_plot_axis_overrides.m` — applies per-plot and per-panel axis/grid overrides.
- `gxtxt_plot_align_ylabel.m` — aligns stacked Y labels independently of tick-label width.
- `gxtxt_plot_finalize_stacked.m` — finalizes stacked layouts, shared X behavior, margins, spacing, and Y-label alignment.
- `gxtxt_print_png_atomic.m` — exports to a temporary PNG and atomically replaces the target file.

## Configuration precedence

Graphics settings use inheritance:

```text
GLOBAL
  -> PLOT
      -> STACKED PANEL
```

A blank or `inherit` value preserves the higher-level setting. This makes the automatic default useful for new plots while still allowing detailed tuning after inspection.

## Standard renderer for new modules (GX-TXT 0.9.7.17+)

For graphs supported by `plot.dataset`, analysis modules publish canonical data and use the public CORE [PLOT_DATASET_API_v2](../api/PLOT_DATASET_API_v2.md) to configure Graph Series, render, and obtain artifacts. The service remains available with the user-facing module Enabled=0. This is the required path for new modules when standard capabilities suffice. Capability checks fail explicitly when a feature is unavailable.

A module may retain or add a custom renderer when its scientific visualization cannot be represented sufficiently through the standard API. Existing renderer implementations remain compatible.

## Custom renderer contract


A new module renderer should:

1. load numerical data from the module's `render_cache.mat`;
2. obtain `pstyle = gxtxt_plot_config()`;
3. create figures with `gxtxt_plot_new_figure(pstyle)`;
4. draw scientific data only;
5. set scientific labels/titles;
6. apply ordinary shared axes styling with `gxtxt_plot_apply_axes(...)` (or the graph-aware helper when explicitly useful);
7. use `gxtxt_plot_legend` when a legend is needed;
8. finalize stacked figures with `gxtxt_plot_finalize_stacked`;
9. export with `gxtxt_print_png_atomic`;
10. let the common PNG finalizer apply the current per-graph/per-panel Axes/Grid override from the framework mapping.

## Minimal example

```octave
pstyle = gxtxt_plot_config();
f = gxtxt_plot_new_figure(pstyle);

plot(t, y, 'linewidth', pstyle.line_width);
gxtxt_plot_text('xlabel', 'Time [s]');
gxtxt_plot_text('ylabel', 'Output voltage [V]');
gxtxt_plot_text('title', 'Example measurement');
gxtxt_plot_apply_axes(gca, pstyle);
gxtxt_print_png_atomic(f, fullfile(outDir, '01_example.png'), pngDPI);
% Final per-graph/per-panel Axes/Grid overrides are applied centrally by the PNG finalizer.
close(f);
```

## Stable IDs

Plot override IDs should be stable and semantic, for example:

```text
bode.magnitude
bode.phase
transformer.transfer
filter.step_response
```

Do not use translated display text as an internal ID.

## Language

All user-visible default titles, axis labels, legends, and report text must be English. Internal variable names and comments may remain unchanged.

## Time-unit contract

Analysis and cache data keep time in SI seconds. Display conversion is performed only by the graphics layer. Renderers that draw a time axis should use `gxtxt_plot_time_values.m` and `gxtxt_plot_time_label.m` rather than scaling the scientific data permanently.

Supported display units are `auto`, `s`, `ms`, `us`, and `ns`. The effective value follows global -> plot/clone override precedence.

## Grid contract

The global grid mode is explicit (`both`, `vertical`, `horizontal`, `none`). Plot and stacked-panel overrides may additionally use `inherit`. In this terminology:

- `vertical` controls grid lines at X ticks;
- `horizontal` controls grid lines at Y ticks;
- X/Y tick step controls the corresponding grid spacing;
- grid color follows global -> plot -> panel precedence.

A renderer should never embed its own unrelated grid policy when the shared API can express the desired result.

## Plot clones

Publication-oriented clones reuse the module `render_cache.mat`; they do not create a second scientific analysis. The Stage Comparison clone renderer demonstrates the intended pattern: select cached node data, apply a clone-specific plot type and overlay/stacked layout, then resolve normal graphics overrides and export atomically.
\n\n## Legend geometry model (v0.6.9)\n\nThe shared legend API treats placement and entry arrangement as separate state. `below` no longer implies horizontal layout, and `northeast` is never interpreted as the position of an external legend.\n\n```text\nplacement = inside | above | below | left | right | manual | none\nlayout    = row | stacked | wrapped | auto\nalignment = start | center | end\nlocation  = inside preset only\n```\n\nUnder GNUplot the shared renderer uses a dedicated figure-normalized legend axes. This avoids GNUplot reapplying native legend presets during PNG export. External placement may shrink the data axes to reserve the required band; manual placement overlays the data at the clicked legend center. The same renderer is available to every module that declares `legend_editor=standard`.\n

## Non-destructive annotation layer

From v0.7.0, annotations sit above the module renderer:

```text
render_cache -> module renderer -> base PNG
                               + annotation JSON
                               -> Tk preview overlay
                               -> annotated export / Print-PDF compositor
```

Rerender never flattens annotations into the base PNG. This separation keeps scientific output reproducible while allowing publication-oriented labels and simple vector markup.


## Global -> module -> plot inheritance

As of v0.7.4, common presentation values are resolved in this order:

```text
Global graphics profile
  -> optional module-wide graphics override
     -> plot-specific common editor override
```

This keeps different modules visually homogeneous by default while permitting deliberate exceptions without duplicating the whole style profile. Output DPI is global unless a module override explicitly changes it.


## GNUplot custom legend background/frame (v0.7.4)

For an opaque legend, the dedicated legend axes owns the background color. The frame is drawn independently as four inset line objects. This is intentional: using a filled patch on a transparent overlay axes allowed GNUplot export ordering to leave data-grid lines visible through the legend and made frame edges vulnerable to clipping. Transparent legends continue to use an axes color of `none`.


## v0.8.1 per-plot axes/grid transport

`Axes / grid...` is per-graph state. The global graphics profile remains only the inherited default. v0.8.1 serializes active graph state into `[axis.<graph-id>]` sections of native `runtime.ini`; stacked-panel state is stored in numbered `panelN_*` keys. The session-local `.plot_axis_overrides.tsv` is still exported through `GXTXT_PLOT_AXIS_OVERRIDE_FILE` as a compatibility fallback.

`Grid = none` is represented explicitly as `xgrid=off` and `ygrid=off`. Empty/`inherit` values preserve the parent setting. Renderers must not hard-code a graph-specific grid workaround.


## v0.8.3 current renderer contract

Renderers should use shared `gxtxt_plot_*` APIs for ordinary styling and `gxtxt_plot_legend()` for standard legends, then export with `gxtxt_print_png_atomic()`. Since v0.8.2 the PNG export path calls `gxtxt_plot_finalize_output()`, which resolves the Graph Provider output mapping and applies current per-plot/per-panel Axes/Grid overrides centrally.

`gxtxt_plot_apply_graph_axes()` remains public and valid, but it is not required merely to make the GUI Grid/Axes editor work. Modules must not add local `grid on/off` workarounds for this purpose.


## Retained raster annotation ownership (dev109)

Image-local text/style definitions reside in the existing Native2D image
identity attribute `gx.image.annotations`, beside the existing ROI state.
Ordinary Native2D Resource export and canonical Document checkpoints carry
these definitions. Native `image_map` and `world_to_device` retain coordinate
authority. The original Native2D text painter, clipping and tagged-text picking
render the projected definitions; viewport panels capture annotation identity
generations and follow the same source-to-device mapping. No renderer, model
database or annotation cache is introduced. See the scoped Tcl host contract
in [NATIVE_2D_GEOMETRY_API_v1](../api/NATIVE_2D_GEOMETRY_API_v1.md).

The current extension supplies tested native persistence, rendering and panel
target substrate. Declared Builder editing controls, restricted SDK dispatch
and installed GUI03/GUI04 acceptance remain separate integration requirements.
The unchanged Script Bridge registration does not expose these four operations.
