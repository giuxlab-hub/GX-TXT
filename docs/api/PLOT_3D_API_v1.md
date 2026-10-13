# GX-TXT 3D Plot API v1

SPDX-License-Identifier: GPL-3.0-or-later

**Introduced:** GX-TXT Pipeline v0.9.1

## Scope

The generic Scientific Analysis renderer supports basic three-coordinate plots:

```text
line3
scatter3
```

This is separate from the dual-Y API. A 3D plot is appropriate when `x`, `y`, and `z` are three coordinates of one scientific relationship. It is not automatically a substitute for time plus three independent measurements, which is four-dimensional information.

## Definition

```ini
[plot.reactor_3d]
type=scatter3
x=current
y=pH
z=electrolyte_concentration
group=experiment
domain=valid_region
auto_units=1
x_label=Current
y_label=pH
z_label=Electrolyte concentration
view_azimuth=-37.5
view_elevation=30
file=03_reactor_3d.png
```

`group=` and `domain=` use the same row-preserving semantics as 2D line/scatter plots. Empty/unavailable groups are skipped.

The generic renderer applies status/validity and finite-value filtering to all three coordinates.

## Public styling helper

```octave
gxtxt_plot_apply_axes3d(ax,plot_config)
```

It extends the common axes style to the Z grid without replacing existing graphics APIs.

## Current limitations

- no interactive rotation is persisted in the manifest;
- no fourth-variable color map contract yet;
- no 3D region-selection mapping in Plot Region Selection API v1;
- per-plot Axes/grid editor remains primarily 2D (X/Y) oriented.
