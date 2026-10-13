# GX-TXT Plot Region Selection API v1

SPDX-License-Identifier: GPL-3.0-or-later

**Introduced:** GX-TXT Pipeline v0.9.1  
**Status:** optional Graph Provider capability

## Purpose

Let the user drag a rectangular area on a rendered plot and deliver the selected **data-coordinate bounds** to a plugin. The capability is optional; plots that do not declare support are unchanged.

The framework owns selection UI, coordinate conversion, persistence and runtime delivery. The plugin decides the scientific meaning of the selected area.

## Descriptor opt-in

```ini
[graph.my.analysis.plot]
file=01_plot.png
supports_region_selection=1
region_selection=rectangle
```

No plugin-specific Tcl widget is required.

## GUI

In **Plots**, select an opted-in plot and press:

```text
Select area...
```

Drag inside the primary data axes. The framework stores the rectangle in data coordinates. `Clear area` disables the current selection.

The selection is an input state. Selecting an area does not silently rerun scientific calculations. The plugin receives it on its next run/rerender and may choose how to use it.

## Runtime contract

```ini
[plot_region_selection_api]
api_version=1

[plot.region.my.analysis.plot]
api_version=1
enabled=1
space=data
axis=primary
x_min=12.5
x_max=48.0
y_min=0.20
y_max=0.85
```

Public Octave reader:

```octave
R = gxtxt_plot_region_from_runtime(runtime_cfg,'my.analysis.plot');
```

`R.enabled` is false if no region is active.

## Manifest persistence

State is stored additively under:

```ini
[module_plot_region.<module-id>.<graph-id>]
```

Old manifests remain valid.

## Geometry metadata

Every PNG exported through `gxtxt_print_png_atomic()` gets a framework geometry sidecar under:

```text
<plot-directory>/.gxtxt_plotmeta/<plot-name>.ini
```

The sidecar records final normalized axes geometry, limits, scale and direction after plot layout/finalization. Plugins do not write or parse this file themselves.

This allows the GUI to convert preview pixels to data coordinates without guessing plot margins.

## Supported coordinate mapping in v1

- one primary 2D data axes;
- linear or logarithmic X/Y scale;
- normal or reversed X/Y direction;
- dual-Y plots: selection maps to the **primary/left** Y axis.

Not supported in v1:

- stacked/multi-panel plot selection;
- 3D data-coordinate region mapping;
- arbitrary polygon/lasso regions;
- multiple simultaneous regions.

For unsupported geometry the framework refuses selection rather than returning ambiguous coordinates.

`plot.dataset.xy` has a dedicated shared-X `x_range` extension for stacked
panels. Its main `.gxtxt_plotmeta` sidecar reports the real multi-panel axes
and `selection_topology_supported=0`. A separate `<plot>.xrange.ini` sidecar
contains the calibrated synthetic X-only selection surface. The framework
uses that sidecar only for a descriptor-defined `x_range` graph; rectangular
selection remains unsupported across multiple panels.

## v0.9.2 additive extension: `x_range` and Dataset Selection resources

The original v0.9.1 rectangle contract remains valid. v0.9.2 additionally accepts:

```ini
supports_region_selection=1
region_selection=x_range
```

`x_range` draws a full-height vertical band and only X bounds have scientific meaning. The legacy `[plot.region.<graph>]` runtime section remains available to the producer module.

When the graph also supplies canonical mapping fields (`region_source`, `region_x_binding` and, for rectangles, `region_y_binding`), the framework promotes the region to Dataset Selection API v1. The reusable selection is stored in canonical dataset units and can then be consumed by other modules through a standard `type=selection` config field. See `DATASET_SELECTION_API_v1.md`.

## GX-TXT 0.9.7.11 plot variants

For a graph that opts into Plot Module variants, the selected region is indexed by the persistent variant ID as well as the declared module/graph. The base keeps its historical module_plot_region section. Variant regions are saved under plot_variant_region.<module>.<graph>.<variant> in Manifest Format 2. The variant runtime projects only its own region into the existing plot.region.<graph> section, so plugins continue to use gxtxt_plot_region_from_runtime(runtime_cfg, graph_id) unchanged. A region from p0001 cannot replace p0002's region. Dataset Selection API v1 records the optional producer_variant and stable variable IDs when promoting a region.

## Exported-raster calibration (GX-TXT 0.9.7.19)

For selectable single-panel 2D plots, the framework now measures the
actual inner data frame in the exported PNG and records its zero-based
pixel edges in `axis.1.pixel_rect`. The sidecar also records
`plot_metadata.image_width` and `image_height`. Preview selection
scales these pixel coordinates to the fitted image and then applies the
existing axis-limit, logarithmic/reverse-axis, and display-unit
conversion rules. This avoids the GNUplot discrepancy between the
in-memory normalized axes position and the rendered data rectangle.
If a reliable four-edge frame cannot be measured, graphical selection
is unavailable rather than silently using incorrect coordinates.
Rerender older PNGs to create calibrated metadata.
