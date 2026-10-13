# Plot 3D API v2

SPDX-License-Identifier: GPL-3.0-or-later

**Introduced:** GX-TXT Pipeline v0.9.3.3  
**Extends:** Plot 3D API v1 from v0.9.1  
**Status:** additive public graphics API

## Scope

Plot 3D API v2 keeps `line3` and `scatter3` and adds public gridded and scattered surface primitives plus framework-owned Z-axis, view and color presentation. It does not define scientific interpolation or 3D selection.

## Coordinate contract

A 3D plot has three geometric coordinates:

```text
X, Y, Z
```

An optional fourth numeric variable:

```text
C
```

is a color variable only. C is not Z and must not be used as a substitute geometric coordinate. Group/Family is orthogonal metadata used by a plugin to organize series.

## Public primitives

Existing:

```octave
plot3(...)
% or the Scientific Analysis Definition line3/scatter3 contract
```

New helpers under `core/octave/graphics/`:

```octave
h = gxtxt_plot_surface(ax,X,Y,Z)
h = gxtxt_plot_surface(ax,X,Y,Z,C)
h = gxtxt_plot_mesh(ax,X,Y,Z)
h = gxtxt_plot_mesh(ax,X,Y,Z,C)
h = gxtxt_plot_contour3(ax,X,Y,Z)
h = gxtxt_plot_contour3(ax,X,Y,Z,levels)
[h,tri] = gxtxt_plot_trisurf(ax,x,y,z)
[h,tri] = gxtxt_plot_trisurf(ax,x,y,z,C)
[h,tri] = gxtxt_plot_trisurf(ax,x,y,z,C,tri)
```

### Gridded XYZ

`surface`, `mesh`, and `contour3` require either:

- X and Y matrices with the same size as Z; or
- X and Y vectors whose lengths match the columns and rows of the Z matrix.

They reject scattered vectors that do not satisfy this grid contract. The framework does not interpolate scattered points onto a grid.

### Scattered XYZ

`gxtxt_plot_trisurf` accepts equal-length x/y/z vectors. An explicit N×3 triangle-index matrix can be supplied. If omitted, the helper may create Delaunay connectivity from x/y coordinates. That creates topology only; it does not interpolate values onto a grid.

## Axis metadata

Plugins publish canonical/display mappings through:

```octave
gxtxt_plot_set_axis_metadata(ax,'x',variable,source_unit,display_unit,factor,offset)
gxtxt_plot_set_axis_metadata(ax,'y',...)
gxtxt_plot_set_axis_metadata(ax,'z',...)
gxtxt_plot_set_axis_metadata(ax,'c',...)
```

`factor` means `display = source * factor + offset`. The plot geometry sidecar records the inverse display→source mapping. This is used for reproducible metadata and preserves the existing 2D Selection API behavior.

## Z axis

The common per-plot runtime section supports:

```ini
[axis.my.graph]
z_unit=mV
z_label=Response
z_min=
z_max=
z_step=
z_format=inherit
z_scale=linear
zgrid=on
```

`z_unit` is presentation-only. Data conversion is performed by the renderer using the Unit/Dimension API before drawing. `z_min/max/step` are expressed in displayed units.

## Persistent view

Global/module/plot inheritance supports:

```text
view_azimuth
view_elevation
projection = orthographic | perspective
```

The common Axes/3D editor stores plot-specific values in Manifest Format 2 and runtime. A cache-aware renderer can apply them during rerender without recomputing scientific data. Projection is best-effort because support depends on the Octave graphics toolkit; unsupported toolkit properties are ignored without changing the data.

## Persistent 3D aspect policy

Global, module and plot or Plot Variant presentation settings inherit in the same order as the camera controls. The public fields are `aspect_mode` and `aspect_ratio` in `[axis.<graph-id>]`, and `plot_3d_aspect_mode` and `plot_3d_aspect_ratio` in `[graphics_3d]`. The GUI exposes them in **Graphics...**, module graphics, and **Axes / grid / 3D / color**. `aspect_ratio` uses three positive finite values separated by semicolons, commas or spaces.

- `auto`: retain Octave's automatic data and plot-box aspect.
- `xy_equal`: equal visual scale for one X and one Y data unit; Z retains its independently determined automatic scale. This is appropriate when X and Y share physical units, such as the thermal surface's millimetres.
- `data_equal`: equal visual scale for a data unit on X, Y and Z when their ranges are comparable. For an extreme Z range, the renderer limits its projected height to 1.5 times the larger horizontal extent so the graph remains usable in the canvas; X:Y equality is retained.
- `manual`: apply the explicit X;Y;Z data-aspect ratio, subject to the same extreme-Z framing limit. Invalid, non-positive or non-finite ratios are rejected.

The Octave implementation is `gxtxt_plot_apply_aspect3d`. It runs after colorbar/layout changes on rerender. It does not alter azimuth, elevation or projection. The `.gxtxt_plotmeta` sidecar records the selected mode and actual `data_aspect_ratio` for inspection.

## Color variable and colorbar

Common fields:

```text
colormap
colorbar_visible
colorbar_label
color_unit
color_min
color_max
```

`color_min/max` are displayed-unit CLim values. Use:

```octave
[Cdisplay,cunit,cfactor] = gxtxt_plot_color_scale(C,source_unit,mode);
gxtxt_plot_set_axis_metadata(ax,'c',c_name,source_unit,cunit,cfactor,0);
s = gxtxt_plot_color_settings(runtime_cfg,graph_id,p);
gxtxt_plot_apply_color_settings(ax,s,label);
```

The default colorbar state is off so ordinary `line3`/`scatter3` plots do not acquire an irrelevant colorbar.

## Common style / final overrides

```octave
gxtxt_plot_apply_axes3d(ax,p)
gxtxt_plot_axis_overrides(ax,graph_id,{},p,runtime_cfg)
```

The second call is the plot-specific final layer. Existing 2D Multi-Y remains a separate semantic contract and is not combined with XYZ.

## Selection

Plot Region / Dataset Selection API v1 remains 2D-only (`x_range`, `rectangle`). `gxtxt_plot_write_metadata` marks a 3D primary axes as not selectable. No 3D box/lasso/picking resource is introduced in this release.

## Limitations v2

- no scientific interpolation of scattered points;
- no 3D selection;
- no volumetric rendering;
- no guarantee that every Octave toolkit exposes perspective projection identically;
- no plotter-specific reduction algorithm in the framework.

## `plot.dataset` gridded XYZ preparation

The current `plot.dataset` gridded surface, mesh and contour path scans a
canonical long-form XYZ table twice and retains coordinate axes, one logical
source-cell validation map, and a bounded display matrix. It never constructs
the full source-value matrix. The default `auto` display reduction keeps the
maximum Z in each display bucket, preserving narrow positive peaks that a
stride could miss. Explicit `minmax` keeps the largest absolute magnitude,
including narrow negative extrema. `stride` and `none` retain their stated
semantics. The canonical Dataset is never rewritten or downsampled.

The implementation currently rejects more than 100 million source cells, more
than 100,000 coordinates on either axis, or more than 8 million displayed
cells. These are explicit resource limits, not claims of arbitrary-size
support. Strict numeric CSV sources can use the public Table Stream numeric
specialization; other storage/schema forms use the general Table Stream.
