# GX-TXT Graphics Inheritance API v1

SPDX-License-Identifier: GPL-3.0-or-later

## Purpose

Provide one coherent graphics profile for every native module while allowing deliberate exceptions without hard-coded renderer branches.

## Resolution order

```text
1. [graphics] global defaults
2. [module_graphics.<module-id>] optional module-wide override
3. per-plot common override, e.g. [plot.legend.<graph-id>]
```

A lower layer wins only for fields it explicitly sets. Blank or `inherit` values fall through to the parent layer.

## Global profile

The global profile owns output dimensions, DPI, common font sizes and units, line/grid/background defaults and legend defaults. It is configured from **Plots -> Global graphics...**.

`plot_font_unit` is `px` or `pt`. `plot_legend_font_unit` is `inherit`, `px` or `pt`; `inherit` follows the global plot font unit.

## Module override

Modules that offer graphs receive **Module graphics...** in the Graph Provider section. The override is disabled by default. When enabled it can replace only the desired common fields. It does not alter scientific graph semantics such as title, selected data, residual definition, etc.

Example:

```ini
[module_graphics.curvefit.family_global]
enabled=1
dpi=300
font_unit=pt
font_size=9
legend_font_unit=px
legend_font_size=10
grid_mode=inherit
```

## Plot-specific layer

Common plot editors can apply a final override to one graph. The legend editor, for example, can select placement/layout, font size and `inherit / px / pt` independently for that plot.

## Runtime

The resolved values are exported to the renderer process and recorded under `[graphics_effective]` in the module `runtime.ini`. This makes rerenders reproducible and debuggable.

## Graph Provider relationship

Graphics inheritance does not define which graphs exist. Graph offerings are declared by the module through Graph Provider API v1. A module can add arbitrary graph IDs without changing the framework core.

## v0.9.3.3 — 3D view and color presentation

The same inheritance chain now also covers the generic fields:

```text
view_azimuth
view_elevation
projection
colormap
colorbar_visible
colorbar_label
color_unit
color_min
color_max
```

Global values are stored in `[graphics_3d]`; module values remain in the existing `[module_graphics.<module-id>]`; the final graph layer is transported in `[axis.<graph-id>]`. No plugin-specific graphics branch is required.

Z-axis fields are graph-specific because they describe an actual plotted coordinate: `z_unit`, `z_label`, `z_min`, `z_max`, `z_step`, `z_format`, `z_scale`, `zgrid`.

## GX-TXT 0.9.7.11 plot variants

The global and module graphics settings remain shared defaults. An opted-in Plot Module variant can store an override for any module graphics field through plotVariantGraphicsSet/Get. Its job receives those values after the shared inheritance is resolved; other variants and the base are unaffected. Axis, legend and Level Scale remain separate per-graph/per-variant services.
