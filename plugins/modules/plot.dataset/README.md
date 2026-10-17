# Scientific Dataset Plot (plot.dataset) 3.18.0

## Dataset coordinate presentation

Use **Dataset coordinates…** in Dataset Preview to choose each Variable's display
unit, persistent view factor and source-unit pivot. Render or rerender the Plot to
use the current settings. Plot preparation retains canonical values and exact row
identity. Numerical calibration is not applied by plotting; materialize an explicit
Derived Dataset first when calibrated numerical values are intended.

A non-default Dataset display unit supplies the automatic graph unit choice.
Explicit graph units take precedence. Explicit graph bounds, including a bound on
any shared-X panel, take precedence over Dataset magnification for that axis.
Choosing **source** preserves original numbers/units even with a declared sensor
relation. Missing coordinate settings retain the previous automatic-unit behavior.
Axes with several series need compatible physical units. Conflicting Dataset unit
preferences require an explicit graph unit; conflicting magnification/pivots require
matching policies, separate axes/panels, or explicit graph bounds.

Single/dual-Y plots, linked panels, distribution value axes and XYZ plots share
these rules. Magnification changes fitted limits once; it never scales points or
error bars. Repeated rerender starts from retained canonical buffers. Error and
band Variables keep their own declared relations; uncertainty displacement requires
an affine relation. Level magnitudes do not have a unique signed inverse: combine
nonidentity Dataset magnification with a linear level scale, or set explicit graph
limits. Logarithmic axes reject a magnified range crossing zero.

Affine coordinate offsets are retained in region-selection metadata. A nonlinear
coordinate graph remains viewable, but source region selection explicitly refuses
an unavailable scalar inverse. Per-Variable relations disable the old source-row
range optimization so that a different inverse cannot silently discard rows.

Detached Clones capture coordinate snapshots with their canonical data. Later
source policy changes do not alter them; relocated rendering needs no source
Session. Native3D Plot preview uses the same displayed XYZ points, limits and
aspect as the static graph. Its caption reports Dataset factors/pivots and unapplied
calibration. A metadata-only policy edit requires static rerender before preview.
Independent retained Viewer representations continue to own their canonical
geometry and separate presentation state.

SPDX-License-Identifier: GPL-3.0-or-later

For graph setup, Series editing, family curves, exact-value filters, and
export through the GUI, see the [GUI guide](GUI_MANUAL.md). This README
describes the scientific model, rendering behavior, and API boundaries.

Finite X/Y observations remain available when optional uncertainty bounds
or error magnitudes are unavailable. Missing bounds remain missing; they are
never replaced by zero. Bands split at missing-bound runs, including gaps whose
rows were omitted by display reduction. Run identities follow the same selected
source rows through canonical streaming, filtered batches, CSV compatibility,
explicit row selection and point ordering. Storage remains proportional to the
displayed rows; reduction stays enabled. Family, ordering and bar geometry remain
required when the same variable also has one of those roles.

Integer family identities retain their declared dtype throughout ordinary filters
and grouped preparation, including adjacent int64/uint64 values above 2^53.

Existing PlotSpec v2, Graph Series, Dataset and Variable identities are retained.
The internal series preparation fingerprint is version 2; graph preparation also
records uncertainty roles. Normal rerender rebuilds incompatible derived caches
from persisted bindings. A detached old uncertainty cache without source access
asks for recalculation. These changes do not modify source Dataset payloads.

[Plot Dataset API v3](PLOT_DATASET_API_v3.md) is the current facade for PlotSpec
operations, graph lifecycle, detached HDF5 snapshots and interactive 3D. A consumer
activates v3. Public v1/v2 remain available. Persistent graphs/Variants may have
independent Viewer representations with explicit source fingerprints and Sync.
Changes report OUT OF SYNC; deleted sources report SOURCE MISSING without
silently deleting existing views. PlotSpec persistence remains
`PLOT_DATASET_PLOTSPEC_v2`.

The [3D API](PLOT_DATASET_3D_API_v1.md) renders configured XYZ Variants through
shared Native3D. Plot Dataset owns canonical data preparation and Session scene
artifacts; Native3D owns rendering. Static outputs remain available.

Persistent PlotSpec presentation is reconciled against current Graph Series:
removed scientific series stay removed, new stable IDs receive neutral
presentation, and surviving panel/axis/style state remains. Rerender rebuilds
incompatible derived caches from current sources without deleting Variants.
Explicit render/rerender does not change persistent USE.

Temporal 2D X coordinates are prepared in seconds, with min/h/day conversion
only for display; original declared units remain source metadata. Shared-X
panels use merged X authority, CORE dual-Y axes and native text/tick extents
for margins. Canonical Dataset IDs and scientific units remain authoritative.

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

The 2-D preparation path opens each Graph Series through Table Stream API
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

The plot model supports Graph-configuration-owned shared-X panels:

- one or more vertically stacked shared-X panels;
- multiple Graph Series;
- different Dataset/X bindings in one 2-D graph;
- Left/Right Y axes;
- Base and Variant isolation;
- PlotSpec per-series styles, error bars and uncertainty bands;
- Graph/variant Region Selection behavior supplied by current CORE;
- existing canonical CSV plots;
- existing 3-D X/Y/Z plus optional Family/Color workflow.

## Canonical matrix surfaces

For surface, mesh, contour3 and heatmap, rank-two Z may bind an explicit Y-by-X
matrix with rank-one X/Y axes. Dimension IDs, shapes and units must agree exactly.
Axes are strictly monotonic, increasing or decreasing; no sorting/transposition
is inferred. Public canonical hyperslabs read at most65,536 cells per chunk and
validate every cell. Missing/nonfinite cells and unsafe int64/uint64 narrowing
are explicit errors; the renderer does not fill holes.

At most100 million source cells and100,000 coordinates per axis are supported.
The displayed grid is bounded to8 million cells. Auto/stride reduction selects
actual cells and retains their zero-based column-major source indices. Minmax
is refused for this matrix lane because moving a Z value to another physical
coordinate would misrepresent the surface. Optional color shares exact Z dimensions;
Family is unavailable for one matrix surface. The existing rank-one XYZ table
lane keeps its separate complete-rectangular-grid and reduction contracts.

[Physical surface fitting](../../../docs/api/FITTER_SURFACE_v1.md) can publish
an explicitly sampled model grid for this reader. The source observations and
the sampled model remain separate canonical Datasets with qualified provenance.

## Frozen API v1

`api/plot_dataset_api_v1.tcl` remains byte-identical to the protected API v1
entrypoint in the accepted framework archive. SHA-256:

```text
acdaabbf3a1d68c8ee99435ad7ee28b69e2eb695b83bc8f0cbc7d7f0220f78d7
```

## Validation

The package includes focused tests for multi-panel API/persistence, real Tk panel editing, renderer structure, variant isolation, Dataset Selection contracts, dataset-native access and bounded reduction. Real Octave/GNUplot integration tests report `SKIP` rather than `PASS` when Octave is unavailable.
### Region Selection compatibility

Region Selection remains an **X-range-only** display-domain operation. A graph
may contain heterogeneous Graph Series X bindings, but it still exposes **one X-selection domain** to the user. `plot.dataset` interprets the CORE selection
for each prepared series and **does not own a second selection registry**.

This is separate from source-range pre-reading: heterogeneous X
bindings deliberately disable pre-read X-window optimization so that a display
axis limit cannot be mistaken for one shared scientific source coordinate.
