# GX-TXT Multi-Y Axis Plot API v1

SPDX-License-Identifier: GPL-3.0-or-later

**Introduced:** GX-TXT Pipeline v0.9.1  
**Status:** public additive graphics API  
**Maximum axes in v1:** two Y axes (`left`, `right`)

## Horizontal grid source in GX-TXT 0.9.7.23

The existing per-graph Axes/Grid state includes the additive field
`ygrid_source=inherit|left|right|none`. It uses the same base/variant graph
identity and persistence as the other axis overrides.

- `inherit` preserves the earlier behavior exactly: existing `ygrid` applies
  to the primary left axis and the right overlay remains off.
- `left` enables the horizontal grid on the left axis and disables it on the
  right overlay.
- `right` disables the left horizontal grid and enables the right overlay grid,
  using right-axis ticks.
- `none` disables horizontal grids on both Y axes.

For a single-Y graph, `right` normalizes to the available left axis. `xgrid`
remains independent in every mode. The field is available in the existing
Axes/Grid dialog and in runtime.ini and TSV fallback transport. No new grid API
or plot.dataset-private state is introduced.

## Purpose

Use two scientifically different Y quantities on the same 2D plot without a plugin implementing its own overlay-axis mechanics.

Typical use:

```text
X = elapsed time
left Y  = current [mA]
right Y = pH
```

The framework owns creation/synchronization of the overlay axes. Legend, Grid/Axes finalization, PNG export and Graph Provider behavior remain the existing shared services.

## Octave helper

```octave
[ax_left,ax_right] = gxtxt_plot_dual_y_axes(fig,plot_config)
```

The returned axes are synchronized in X. `ax_left` is tagged as the primary data axis; `ax_right` is tagged as a framework overlay axis. `gxtxt_print_png_atomic()` automatically re-synchronizes their geometry after external legend/layout changes.

A conforming plugin should plot by passing the target axes explicitly:

```octave
p = gxtxt_plot_config();
fig = gxtxt_plot_new_figure(p);
[ax1,ax2] = gxtxt_plot_dual_y_axes(fig,p);
h1 = plot(ax1,t,current,'-');
h2 = plot(ax2,t,pH,'-');
xlabel(ax1,'Time [min]');
ylabel(ax1,'Current [mA]');
ylabel(ax2,'pH');
gxtxt_plot_legend([h1 h2],{'Current','pH'},p,graph_id,runtime_cfg);
gxtxt_print_png_atomic(fig,target,p.dpi);
```

Do not create a second local legend/grid/finalizer implementation.

## Scientific Analysis Definition syntax

For generic line/scatter plots:

```ini
[plot.reactor_current_ph]
type=line
x=time
series=current;pH
series_axes=left;right
series_labels=Current;pH
y_label=Current
y2_label=pH
auto_units=1
file=01_current_ph.png
```

`series_axes=` is aligned with `series=` and accepts only `left` or `right` in API v1. If omitted, every series uses `left`, preserving historical behavior.

`bar` does not support a right axis in API v1.

## Automatic display units

`auto_units=1` requests presentation-only scaling using series unit metadata. Scientific values in the analysis context are not modified.

Examples:

```text
s  -> ns/us/ms/s/min/h/day as appropriate
A  -> pA/nA/uA/mA/A/kA/... as appropriate
V  -> uV/mV/V/kV/...
Hz -> Hz/kHz/MHz/...
```

Automatic scaling is applied only when the unit metadata are known and compatible for all series sharing one Y axis. Unknown/domain-specific units remain unchanged.

Public helper:

```octave
[display_values,display_unit,factor] = gxtxt_plot_display_scale(values,unit,'auto')
```

An explicit display unit may replace `auto`.

## Third scientific quantity

API v1 deliberately stops at two Y axes. Three unrelated Y scales on the same 2D frame are difficult to read and require toolkit-specific outward-axis rendering. GX-TXT v0.9.1 instead also introduces the 3D Plot API v1 for cases where three numerical coordinates are scientifically meaningful. A true tertiary 2D Y axis is reserved for later evidence-driven work.

## GNUplot inner-area synchronization since 0.9.7.15

Octave 9.4 exposes `position`, `innerposition`, `outerposition` and
`positionconstraint`. With two axes both constrained by `outerposition`,
GNUplot exported different data rectangles for left and right labels/ticks
even when their reported normalized `position` and `innerposition` were
identical. This could shift or compress a right-axis series without changing
the scientific values, limits or metadata.

The shared CORE helper sets `positionconstraint=innerposition` on both
axes (falling back to `activepositionproperty=position` on older Octave),
then synchronizes the normalized inner position and X properties. Export
flushes automatic layout and synchronizes once more immediately before
`print()`. Right Y limits, ticks, units and labels remain independent.
Plugins continue to use the existing Multi-Y helper and PNG exporter.

The GNUplot raster regression compares the actual left/right trace geometry
for similar and widely different Y ranges, short and long right labels,
standard/resized figures and repeat export. The old output fails the
pixel comparison even though both axes report equal `position`; the fixed
output agrees to within the 2.5-pixel test tolerance. A real
`plot.dataset` 1.1.1 base and variant render additionally verifies
concentration [ppm] against pH (5–11), shared X extent, full-height Y2,
and byte-identical PNGs on cache rerender.
