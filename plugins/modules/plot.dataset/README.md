# Scientific Dataset Plot (plot.dataset)

SPDX-License-Identifier: GPL-3.0-or-later

For graph setup, Series editing, family curves, exact-value filters, and
export through the GUI, see the [GUI guide](GUI_MANUAL.md). This README
describes the scientific model, rendering behavior, and API boundaries.

`PLOT_DATASET_API_v3` is the complete public facade for PlotSpec v2,
graph lifecycle, detached snapshots and interactive 3D. A consumer may
activate this facade without separately activating earlier API versions. A persistent graph/Variant can
create multiple independent Viewer representations. Each records its source
fingerprint; changes report OUT OF SYNC until explicit Sync, and deleting the
source reports SOURCE MISSING without deleting an existing view. The Native
3D Viewer panel lists compatible graph/Variant identities alongside imported
3D Datasets. PlotSpec persistence remains `PLOT_DATASET_PLOTSPEC_v2`.

The public `PLOT_DATASET_3D_API_v1` supports interactive rendering of a
configured persistent XYZ Plot Variant through the shared Native 3D viewer.
Plot Dataset interprets the Dataset and emits Session-owned scene artifacts;
the viewer renders them. Seven existing XYZ types are supported. Static plots
and public APIs v1/v2/v3 remain available. See `PLOT_DATASET_3D_API_v1.md`.

The [Plot Dataset API v3](PLOT_DATASET_API_v3.md) handles detached HDF5
scientific snapshots and exact source-row indexes for displayed 2D points.
Public APIs v1 and v2 remain supported. PlotSpec v2 represents numeric 2D
families, reversible axis direction, Dataset-bound bars, histograms,
box/whisker plots, stable Graph Series, layouts, variants and 3D paths.

The renderer reconciles persistent PlotSpec presentation against current Graph Series before runtime generation. Removed scientific series are not revived from provider state, newly committed stable IDs receive neutral presentation in the first existing panel, and surviving panel/axis/style state is preserved. Missing, incompatible or unreadable derived runtime/cache is rebuilt by the normal rerender path without deleting variants. Explicit render/rerender operates on the requested graph without changing persistent USE, variant serialization preserves the base runtime, and summaries are regenerated for every selected graph.

The temporal-X runtime-unit contract is explicit. Canonical Dataset API v2 materializes HMS `elapsed_time` values as numeric seconds; `plot.dataset` normalizes every temporal 2-D X coordinate to seconds during preparation and performs `min`/`h`/`day` conversion only for display. The original declared unit is retained as source metadata. Incompatible prepared caches are rejected instead of silently reinterpreting time units.

The multi-panel renderer shares the standard X and Y Right behavior: X uses the merged PlotSpec X authority and normal axis-label resolver, right overlays are created through CORE `gxtxt_plot_dual_y_axes()`, all primary/right axes share one linked X group, and stacked margins/gaps grow from the actual native text/tick extents. The same scientific elapsed-time interpretation applies to single- and multi-panel rendering.

## 2-D scientific authority

Normal 2-D plots are defined exclusively by CORE Graph Series:

```text
dataset_id + x_variable_id + y_variable_id + axis + order
```

Graph Series IDs and canonical Variable IDs are scientific identity. Physical
CSV/HDF5 paths and physical storage-column names are not.

PlotSpec v2 remains presentation state: representation kind, line/marker style,
opacity, error/band variable bindings, annotations and non-overlapping plot
presentation. It does not create a second X/Y binding authority.


## Multi-panel shared-X plots

`plot.dataset.xy` may contain one or more vertically stacked PlotSpec v2 panels. Every series belongs to exactly one panel through its stable `series_id`; panel membership is presentation state and never changes the Graph Series scientific identity:

```text
dataset_id + x_variable_id + y_variable_id
```

All panels share one visible X range, X scale and compatible display domain. They do not need the same Dataset ID, X Variable ID, row count or stored X samples. Each series is converted independently into the shared display domain. Explicit conflicting panel X unit/scale/range declarations are rejected.

Each panel keeps independent Y-left/Y-right series, Y range/scale presentation, annotations and legend. Panel lifecycle and per-panel axes/titles are managed from the normal Graph configuration window. Series editors only assign a series to an existing panel while multi-panel mode is enabled. Base graphs and variants persist independent panel state, and variant duplication copies the complete panel layout.

`plot.dataset.xy_region` deliberately remains single-panel because rectangle selection has one Y domain. `plot.dataset.xy` X-range Region Selection represents one graph-wide interval across the shared X domain.

## Dataset-native reads

The 3.x 2-D preparation path opens each Graph Series through Table Stream API
v3 and Canonical Dataset API v2 using:

```text
runtime.session
+ dataset_id
+ variable_id(s)
```

The module contains no CSV/HDF5 read branch. CORE resolves the registered
storage provider and exposes typed chunks. This supports, through the same
module code:

- canonical CSV tables;
- canonical HDF5 tables;
- stored coordinates;
- uniform implicit coordinates.

For example an FFT spectrum may publish:

```text
dataset_id = wav.decoded.spectrum
x_variable_id = frequency
    axis_kind = uniform
    origin / step / count
    no physical HDF5 frequency dataset
y_variable_id = amplitude
    stored HDF5 variable
```

Table Stream v3 synthesizes only the current `frequency` chunk. `plot.dataset`
does not materialize the complete coordinate and does not require a physical
`frequency` column.

## Large 2-D datasets

Canonical data are never reduced or modified. The module builds a bounded
presentation representation for the renderer.

With `reduction_mode=auto`, series above `auto_reduce_threshold` use an
extrema-preserving bucket reduction. For each source bucket, the exact source
row containing the minimum and maximum Y value is retained in source order;
first and last valid source samples are also preserved. This keeps narrow peaks
and impulses that stride-only decimation can miss.

`target_points` is a graph display budget. The effective budget is also bounded
by raster width when `GXTXT_PLOT_WIDTH_PX` is available. Multiple Graph Series
share the graph budget. Chunk working memory is bounded by `chunk_rows` and the
selected variables; only the bounded display vectors accumulate in memory.

`stride` remains available as an explicit compatibility choice, but automatic
large-data preparation uses extrema-preserving reduction.

## Multi-panel configuration GUI

For `plot.dataset.xy`, **Configure...** contains an explicit **Multi-panel (vertically stacked, shared X)** toggle. When enabled, the same window owns panel creation, removal, ordering, optional panel title, and the panel-local Y Left/Y Right presentation fields (`label`, `display_unit`, `scale`, `min`, `max`). The graph title and X label remain graph-wide.

The standard Series Editor does not create or delete panels. When multi-panel mode is enabled it shows only a **Panel** selector for the selected stable `series_id`; when disabled that selector is hidden and the graph renders through the normal single-panel path. Saved panel membership is retained while disabled so the layout can be restored by re-enabling the mode.

## X-range preparation

When explicit X bounds are available and the canonical X variable is a uniform
coordinate, the dataset-native path maps the display interval back to the coordinate's source
unit and computes a Dataset `start/count` range before reading samples.

Random-access providers such as HDF5 can therefore read only the useful source
range. Sequential providers remain correct through the public CORE fallback.
For stored/non-uniform coordinates, CORE currently exposes no general
value-to-row search operation, so the module streams the canonical variable
normally rather than implementing a private backend-specific search.

A changed explicit X preparation window invalidates only the bounded 2-D
presentation cache; rerender can rebuild that 2-D preparation through the
public dataset-aware path.

## Axis authority

For overlapping 2-D axis properties, CORE is authoritative once plot-specific axis state has been saved. `Restore automatic` disables stale provider bounds/display-unit overrides; PlotSpec remains the fallback only where CORE axis state has not been declared. Axis authority is normalized deterministically at render time.

## Supported plotting capabilities

The current Plot Dataset graph model includes:

- one or more vertically stacked shared-X panels;
- multiple Graph Series;
- different Dataset/X bindings in one 2-D graph;
- Left/Right Y axes;
- Base and Variant isolation;
- PlotSpec per-series styles, error bars and uncertainty bands;
- Graph/variant Region Selection behavior supplied by current CORE;
- existing canonical CSV plots;
- existing 3-D X/Y/Z plus optional Family/Color workflow.

The 3-D reader uses the standard Module primary-source representation.

## Frozen API v1

`api/plot_dataset_api_v1.tcl` remains byte-identical to the protected API v1
entrypoint. SHA-256:

```text
90316f09f404b911f747ffc86c10d799b46bc80e51720d6b20e56e5712bd6e5c
```

## Validation

Integration tests for multi-panel state, Tk panels, renderer behavior,
variants, Dataset Selection and bounded reduction require a compatible
GX-TXT scientific runtime. Tests must report `SKIP` rather than `PASS`
when GNU Octave/GNUplot is unavailable.
### Region Selection compatibility

Region Selection remains an **X-range-only** display-domain operation. A graph
may contain heterogeneous Graph Series X bindings, but it still exposes **one X-selection domain** to the user. `plot.dataset` interprets the CORE selection
for each prepared series and **does not own a second selection registry**.

This is separate from source-range pre-reading: heterogeneous X
bindings deliberately disable pre-read X-window optimization so that a display
axis limit cannot be mistaken for one shared scientific source coordinate.
