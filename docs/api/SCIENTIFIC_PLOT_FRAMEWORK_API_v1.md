# Scientific Plot Framework API v1

SPDX-License-Identifier: GPL-3.0-or-later

**Introduced:** GX-TXT Pipeline v0.9.3.3

This document is the integration map for generic scientific plot plugins. It does not define a `plot.dataset` implementation.

## dev-047 graph presentation additions

The same per-graph Axes override state now includes `background=#RRGGBB` or
blank to inherit the global/module plot background. The ordinary Axes dialog
offers an editable color, chooser, and Inherit action for base graphs and
Variants. GNUplot PNG export applies the effective background to the rendered
image without changing the scientific data or legend background setting.

Plot layout persists `layout_ylabel_allow_negative` per graph. The checkbox
is off by default; turning it on exposes a signed `layout_ylabel_dist` range
of -30..30 percent. Turning it off clamps an active negative value to zero.
The final CORE export normalizes displayed signed zero tick labels on X/Y/Z
axes while leaving numeric tick positions and nonzero scientific labels intact.

## dev-046 additive 2D aspect and axis scales

The existing per-graph CORE Axes contract now has `x_scale`, `y_scale`, and
`y2_scale`, each `inherit|linear|log`. The common Axes dialog exposes the
selectors for X, Y Left and Y Right. A chosen CORE scale is applied at final
render to primary and right overlay axes; `inherit` retains the provider's
PlotSpec scale. Explicit log bounds must be positive. Metadata records the
effective native `xscale`/`yscale` on primary and overlay axes.

Ordinary 2D axes have a separate `xy_aspect_mode=inherit|auto|xy_equal` field.
`gxtxt_plot_apply_aspect2d(ax,mode)` is the public CORE graphics helper:
`auto` retains automatic aspect; `xy_equal` sets equal X and Y data-unit screen
lengths for linear axes while allowing the plot box to adapt. Log axes reject
`xy_equal`. The selection persists in the existing graph axis override state,
including Variants, and metadata records `xy_aspect_mode`, `aspect_mode` and
the effective `data_aspect_ratio`. Existing 3D `aspect_mode` and its modes are
unchanged. For compatibility, the additive fields use the existing
`plot.axis3d.<graph>` persistence extension and common runtime axis section;
no older field changes meaning.

## Existing APIs reused unchanged

A conforming plot plugin should reuse: Graph Provider API v1, Graphics Inheritance API v1, Plot Annotation API v1, Multi-Y Axis Plot API v1, Render Cache API v1, Dataset Selection API v1, Progress API v1, Dataset/Analysis Source metadata, Unit/Dimension API v1, Plugin Install API v1 and Plugin Bundle API v1.

## New/additive pieces in v0.9.3.3

- Unit Selector API v1 (`type=unit`).
- Plot 3D API v2 (`surface`, `mesh`, `contour3`, `trisurf`; Z/view/color state).
- Table Stream API v1 for selected-column chunked CSV reading.
- public plot-axis metadata helper for X/Y/Z/C.
- source metadata helper now includes `source_id` and canonical `dataset_id`.

## Graphics precedence

```text
global graphics
  -> module graphics override
      -> graph-specific Axes / 3D view / Color override
```

Blank/`inherit` falls through. Scientific data/bindings remain module-owned; presentation state is framework-owned.

## Runtime graph section

The common section is additive:

```ini
[axis.<graph-id>]
enabled=1
x_unit=inherit
y_unit=inherit
y2_unit=inherit
x_scale=inherit
y_scale=inherit
y2_scale=inherit
xy_aspect_mode=inherit
z_unit=inherit
x_min=
x_max=
y_min=
y_max=
y2_min=
y2_max=
z_min=
z_max=
z_scale=inherit
zgrid=inherit
view_azimuth=
view_elevation=
projection=inherit
aspect_mode=inherit
aspect_ratio=
colormap=inherit
colorbar_visible=inherit
colorbar_label=
color_unit=inherit
color_min=
color_max=
```

Historical fields remain valid and unchanged.

## Manifest additions

```ini
[scientific_plot_framework_api]
version=1

[unit_selector_api]
version=1

[graphics_3d]
plot_3d_azimuth=-37.5
plot_3d_elevation=30
plot_3d_projection=orthographic
plot_3d_aspect_mode=auto
plot_3d_aspect_ratio=
plot_colormap=viridis
plot_colorbar_visible=0
plot_colorbar_label=
plot_color_unit=auto
plot_color_min=
plot_color_max=

[plot.axis3d.<graph-id>]
...
```

Module-wide values use the existing `[module_graphics.<module-id>]` persistence and normal inheritance.

## Rerender contract

A plugin that declares Render Cache API v1 may cache prepared 2D/3D scientific arrays in its standard cache. Display units, axis limits, grid, legend, annotations, Z settings, view, colormap and colorbar are presentation state and may be reapplied during cache-only rerender. The framework does not define a second 3D cache format.

## CORE status

A future CORE plotting module remains a normal plugin under `plugins/modules/<id>/`. CORE means shipped with GX-TXT, not embedded scientific logic in `gxtxt_pipeline.tcl`.

## v0.9.4 CORE plotter integration

`plot.dataset` v1.0.0 is the bundled CORE scientific dataset plotter. CORE means shipped under `plugins/modules/plot.dataset/`; no scientific plotting implementation is embedded in `gxtxt_pipeline.tcl`. Dataset contracts derived from `table.generic` through Contract Registry parent declarations are accepted by the standard source selector. `plot.dataset_xy` is legacy/deprecated and is not bundled as an active module.

## Computed scientific annotation layer (v0.9.4.1)

Framework plotters may consume Computed Data Annotation API v1 sidecars attached to canonical datasets. These annotations use canonical data coordinates and source units, and are distinct from the interactive `figure_norm` Plot Annotation API. `plot.dataset` v1.0.1 renders the v1 2D types and converts them to active display units through Unit/Dimension API.
## Multi-panel Axes dialog (GX-TXT 0.9.7.41)

When `stackedGraphPanels(path)` returns more than one panel, the shared **Axes / grid / 3D / color** dialog exposes panel-local CORE overrides for Y Left/Y Right numeric range, tick step/format, grid mode/source/color and Y-label alignment position. X remains graph-wide and synchronized. The panel controls are omitted for single-panel artifacts.

Artifact providers may append non-overlapping presentation controls through [Axis Configuration Extension API v1](AXIS_CONFIG_EXTENSION_API_v1.md). Generic CORE axis state remains authoritative for overlapping numeric/grid controls.
