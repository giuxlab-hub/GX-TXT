# PLOT_DATASET_API_v2 — declarative scientific PlotSpec

## Exact selected rows and source continuity

The optional `source_row_ordinals` series field contains unique zero-based
canonical row identities. Graph Series remains its scientific authority; both
base and Variant runtime configuration carry the same exact list. Preparation
retains those measured rows without resampling and includes the list in cache
identity. Omitting the field retains the existing complete-source behavior.

The optional boolean `source_row_continuity` is PlotSpec presentation state.
When enabled, a line breaks between nonconsecutive canonical rows, including
gaps left by selection or nonfinite filtering. It survives Graph Series/PlotSpec
reconciliation, editor reopening and rendering. It does not alter canonical
values, source-row identities or the chosen fitting input.

## Purpose

`PLOT_DATASET_API_v2` is the high-level public CORE rendering facade hosted by the protected
`plot.dataset` module.  It lets another GX-TXT module describe **what data must
be plotted and how it should be represented** without driving the GUI, writing
private runtime files, invoking Octave directly, or duplicating plotting code.

The consumer remains responsible for producing scientifically meaningful
GX-TXT datasets.  `plot.dataset` owns rendering, unit/display handling, Graph
Series integration, dual-Y axes, variants, cache/rerender and plot artifacts.
The API does **not** interpolate, resample, align, fit or otherwise transform
scientific data merely to make it plottable.

## Version and compatibility

API name: `PLOT_DATASET_API_v2`  
API version: `2`  
PlotSpec schema: `PLOT_DATASET_PLOTSPEC_v2`  
Current module release: `plot.dataset 3.13.1`; package minimum framework: GX-TXT `0.9.8.07`. Public API v1 and v2 contracts remain supported.

### Persistent-state and derived-runtime reconciliation

Before runtime generation, PlotSpec series are reconciled by stable series_id with current Graph Series. Graph Series remains the scientific identity authority; PlotSpec preserves panel membership and presentation for matching IDs. Stale presentation-only series are removed and newly committed Graph Series receive neutral presentation in the first existing panel. Missing, incompatible or unreadable runtime/cache is rebuilt from persistent state through normal rerender without removing variants. Explicit render/rerender selects the requested base plot or variant without changing persistent USE; variant serialization preserves the base runtime, and the summary is regenerated for every selected graph.

### Elapsed-time runtime-unit normalization

For 2-D plots, temporal X coordinates are normalized internally to seconds immediately after data preparation. This matches Canonical Dataset API v2, which materializes HMS `elapsed_time` values as seconds, and prevents the original declared unit (`h`/`min`) from being applied a second time. Display-unit selection remains presentation-only and may render the canonical seconds as `s`, `min`, `h`, or `day`.

### Panel-local Y compatibility

In a shared-X multi-panel plot, Y compatibility is evaluated independently for each `panel.id` and Y side (`left` / `right`). Different panels may therefore use unrelated Y quantities and units. X compatibility remains graph-wide. The renderer also anchors each right-Y label on the right overlay explicitly.

### Stale-reference reconciliation and Series-table usability

The current Plot Dataset service treats deletion of a canonical dataset or referenced X/Y variable as a normal session lifecycle event. Persisted PlotSpec series with missing scientific bindings are pruned; surviving series retain the exact `dataset_id + x_variable_id + y_variable_id`. Invalid error/uncertainty auxiliary bindings are removed independently. If no valid series remain, the persisted PlotSpec and stale graph/cache/summary artifacts are removed.

The standard CORE Graph Series editor is scrollable for long lists. Through the public Series Editor Extension API v1 table-column hook, plot.dataset adds a read-only `Panel` column so panel membership is visible without opening each series.

### Shared Axes-dialog integration

The public service supports the `axis_config_extension` capability. For any multi-panel artifact recognized by `plotRefForArtifact(path)`, `plot.dataset` can append provider-specific panel title, Y Left/Y Right label, display-unit and scale controls to the shared CORE **Axes / grid / 3D / color** dialog through GX-TXT 0.9.7.41 Axis Configuration Extension API v1. CORE panel-local numeric range/tick/grid state remains authoritative and is not duplicated by the provider extension.

### Multi-panel geometry and artifact discovery

The public PlotSpec v2 multi-panel presentation geometry is as follows: the graph-wide title now follows the configured GX-TXT title typography and finalized top-panel geometry, and panel legends are created after stacked layout so their positions are derived from the final panel axes. Manual legend placement is translated from the graph-level setting into the corresponding panel-local position.

The public API also adds `plotRefForArtifact path` and `panelIdsForArtifact path`. These calls resolve a rendered `plot.dataset` artifact back to its public plot reference/persisted panel order without exposing private PlotSpec files. GX-TXT CORE uses this public discovery in `stackedGraphPanels(path)` before its legacy stacked-plot fallback.

### Panel configuration lifecycle

Normal 2-D Graph Series are read by stable Dataset/Variable identity through Table Stream API v3 / Canonical Dataset API v2. Physical storage paths and column names are not part of the v2 scientific binding contract. Uniform implicit coordinates are valid X variables and are synthesized chunk-by-chunk by CORE. Large canonical series may be reduced only into bounded presentation data; canonical datasets are not modified.

The panel-shaped PlotSpec schema for `plot.dataset.xy` supports an optional `multi_panel` state and per-panel `title`. Multi-panel lifecycle is configured from the normal Graph configuration window through GX-TXT 0.9.7.39 Graph Configuration Extension API v1. Each panel has independent Y Left/Y Right presentation while all panels share one visible X domain. Panel membership remains presentation state keyed by `series_id`; it never changes `dataset_id`, `x_variable_id`, or `y_variable_id`. `plot.dataset.xy_region` remains single-panel because its rectangle selection has one Y domain.

For backward compatibility, a persisted/pre-3.2 PlotSpec with no `multi_panel` field and more than one panel is interpreted as enabled. An explicit `multi_panel=0` preserves the saved panel layout but renders through the established single-panel path; re-enabling restores that layout.

`PLOT_DATASET_API_v1` remains a separate, stable public surface. v2 is additive; consumers written for v1 do not need to migrate. For 2D scientific rendering, bindings use Graph Series only: obsolete X/Y/Y2/Additional-series session fields are not used as a renderer fallback. The dedicated current 3D binding model remains separate.

## Discovery and capabilities

Do not hard-code the API path. Discover `plot.dataset` through the normal
Standard Module API descriptor, read `[public_apis]`, then resolve:

```ini
[public_api.PLOT_DATASET_API_v2]
api_version=2
entrypoint=api/plot_dataset_api_v2.tcl
namespace=::GX::PlotDatasetAPIv2
```

After sourcing the entrypoint:

```tcl
set info [::GX::PlotDatasetAPIv2::apiInfo]
set caps [::GX::PlotDatasetAPIv2::capabilities]
if {![::GX::PlotDatasetAPIv2::supports uncertainty_band]} {
    error "plot.dataset cannot render uncertainty bands"
}
::GX::PlotDatasetAPIv2::requireCapability series_kind_scatter
```

Capabilities are explicit.  An absent capability means **not supported**; a
consumer must not silently substitute another representation.

The protected CORE descriptor advertises both v1 and v2 when the user-facing
`plot.dataset` module has Enabled=0 as well as Enabled=1. Consumers should
discover the API from `[public_apis]` and must not use the module Enabled
switch as an API availability check. Both render and rerender work with
Enabled=0; direct interactive module use remains controlled by Enabled.
For Graph Series with no preselected primary source, the preserved v1 CORE
bridge temporarily uses the first active Series dataset during command
preparation and then restores the source state.

The current v2 implementation advertises Cartesian 2D, the panel schema,
vertically stacked multi-panel rendering with one shared X domain, panel
assignment/order, Graph Series, variants, multi-dataset, dual Y, per-series
style, line, scatter, line+marker, step, error bars, uncertainty bands,
numeric bar plots, axes, reference annotations, render/rerender, artifact
retrieval and public artifact-to-panel discovery. Histogram, pie and independent-X panel layouts are deliberately not
advertised.

## PlotSpec model

The v2 data model is panel-shaped and accepts one or more panels for `plot.dataset.xy`:

```text
PlotSpec
 ├─ schema
 ├─ graph_type
 ├─ graph_id
 ├─ title                  (global graph title)
 ├─ multi_panel            (optional; absent keeps legacy inference)
 ├─ defaults
 │   └─ style
 ├─ panels[]
 │   └─ Panel
 │       ├─ id
 │       ├─ title           (optional panel title)
 │       ├─ axes
 │       ├─ series[]
 │       │   ├─ stable bindings
 │       │   ├─ kind
 │       │   ├─ style
 │       │   ├─ x_error / y_error
 │       │   └─ band
 │       └─ annotations[]
 └─ output                 (reserved for future v2-compatible output options)
```

`graph_type` is currently `cartesian_2d`. `graph_id` is either
`plot.dataset.xy` or `plot.dataset.xy_region`.

Use `newSpec` to get a correctly shaped starting object:

```tcl
set spec [::GX::PlotDatasetAPIv2::newSpec \
    -graph_id plot.dataset.xy \
    -title "Experiment"]
```

A one-panel PlotSpec remains fully compatible with earlier v2 consumers. For
`plot.dataset.xy`, `panels` may contain multiple panels. For
`plot.dataset.xy_region`, exactly one panel is still required.

## Lifecycle

A normal consumer lifecycle is:

```text
publish/register datasets
        ↓
construct PlotSpec
        ↓
validateSpec
        ↓
createPlotFromSpec   or   open existing plot + applySpec
        ↓
render
        ↓
artifacts
        ↓
change presentation only
        ↓
rerender
```

Public entry points:

| Procedure | Purpose |
|---|---|
| `apiInfo` | API/module version and capabilities |
| `capabilities` / `supports` / `requireCapability` | capability discovery |
| `newSpec` | create a minimal PlotSpec dictionary |
| `validateSpec spec` | validate 2D or 3D bindings and v2 structure; return `1` on success, raise the existing Tcl error on failure |
| `createPlotFromSpec spec ?base\|variant? ?sourceVariant?` | create/configure a plot |
| `applySpec plotRef spec` | synchronize PlotSpec with authoritative Graph Series |
| `saveSpec plotRef spec` | persist v2 presentation state |
| `loadSpec plotRef ?deriveIfMissing?` | read persisted or v1-derived PlotSpec |
| `deriveSpec plotRef` | represent an existing Graph-Series plot as a basic v2 spec |
| `removeSpec plotRef` | remove only the v2 sidecar; Graph Series remain |
| `readPlot plotRef` | current v1 state + PlotSpec + artifact state |
| `setSeriesPresentation plotRef seriesId fields` | change kind/style/error/band only |
| `multiPanelEnabled plotRef` | return effective multi-panel state |
| `setMultiPanel plotRef state` | explicitly enable/disable multi-panel rendering without destroying saved panel state |
| `panelIds plotRef` | return panel IDs in render order |
| `plotRefForArtifact path` | resolve a rendered plot.dataset graph artifact to its public plot reference, or `{}` when not owned by plot.dataset |
| `panelIdsForArtifact path` | return persisted panel IDs for a recognized plot.dataset graph artifact, or `{}` when not recognized |
| `panelInfo plotRef panelId` | return one panel presentation dictionary |
| `setPanelTitle plotRef panelId title` | set/clear the optional panel title (`auto` displays the panel ID) |
| `setPanelAxis plotRef panelId axis fields` | set panel axis presentation fields; Graph configuration uses Y Left/Y Right |
| `addPanel plotRef panelId` | append an empty panel |
| `removePanel plotRef panelId` | remove an empty non-final panel |
| `movePanel plotRef panelId delta` | change panel order |
| `setSeriesPanel plotRef seriesId panelId` | move a series between panels without changing its scientific binding |
| `render plotRef` | full analysis/preparation/render |
| `rerender plotRef` | render from valid cache |
| `artifacts plotRef` | output paths and existing artifacts |
| `openEditor plotRef` | open the module-owned v2 series/style editor |

All errors from this surface start with `plot.dataset API v2:` when they are
raised by the Tcl API.

## Multi-panel public-API example

The following uses only `PLOT_DATASET_API_v2`; it does not drive the GUI:

```tcl
set spec [::GX::PlotDatasetAPIv2::newSpec \
    -graph_id plot.dataset.xy \
    -title "Experiment" \
    -multi_panel 1]

set p1 [dict create id electrical title "Electrical" \
    axes [dict create y_left [dict create label "Voltage" display_unit V]] \
    annotations {} series [list \
        [dict create id voltage dataset_id dA x_variable_id v0001 y_variable_id v0002 axis left]]]

set p2 [dict create id chemistry title "Chemistry" \
    axes [dict create y_left [dict create label "Concentration" display_unit ppm]] \
    annotations {} series [list \
        [dict create id nitrate dataset_id dB x_variable_id v0004 y_variable_id v0007 axis left]]]

dict set spec panels [list $p1 $p2]
set ref [::GX::PlotDatasetAPIv2::createPlotFromSpec $spec base]
::GX::PlotDatasetAPIv2::render $ref
```

The two X variables may have different stable identities and stored samples; they remain untouched and are only required to resolve into the compatible shared display domain.

## Stable variable identity

Every data binding uses the framework identity:

```text
dataset_id + variable_id
```

For example:

```tcl
set s [dict create \
    id measured \
    dataset_id experiment \
    x_variable_id v0001 \
    y_variable_id v0004 \
    axis left]
```

Display names such as `time`, `Cl-` or `pH` are not persistent identities.
Auxiliary uncertainty/band variables use the same rule and must belong to the
same dataset as their series in v2.0.0.

## Graph Series model

v2 does **not** create a second series registry.  `applySpec` projects these
fields into the existing CORE Graph Series API through `PLOT_DATASET_API_v1`:

```text
id
dataset_id
x_variable_id
y_variable_id
axis
label
enabled
order
```

Graph Series remains authoritative for data identity and ordering.  v2 stores
only plot.dataset-owned presentation information (kind/style/error/band/axes
and reference annotations) in its public PlotSpec state.  If a persisted
PlotSpec binding no longer matches the authoritative Graph Series binding,
rendering fails explicitly instead of guessing.

## Multi-panel shared-X semantics

For `plot.dataset.xy`, each series belongs to exactly one PlotSpec panel. The
panel assignment is keyed by the stable Graph Series `series_id` and is
presentation state only. Moving a series between panels never rewrites its
Dataset or Variable IDs.

All panels share one visible X domain:

```text
same visible X min/max
same X scale

Axis dictionaries may additionally declare `direction=normal|reverse`; `auto` leaves renderer direction unchanged. This is persistent shared plotting state, not module-private rendering behavior.
same compatible display unit/domain
```

Shared X does **not** require the same source Dataset, X Variable ID, row count,
or stored X samples. A panel may use `Dataset A / X_A` while another uses
`Dataset B / X_B`; every series is converted independently into the common
display domain. Conflicting explicit `axis.x` unit/scale/range declarations
across panels are rejected rather than silently choosing one panel as
authority.

For 2D plots, `axis.x.major_step` is a positive number or blank. On a log10 X
axis, `1` places major ticks one decade apart (`0.01`, `0.1`, `1`, `10`, ...);
on a linear axis it is a linear display-unit step. `axis.x.minor_grid` is
`off` or `auto`; log10 `auto` draws light dotted subdivisions at `2` through
`9` times each power of ten, without minor labels. The same saved PlotSpec
fields are edited by Plot Dataset graph settings and the framework Plots tab.
`sharedXAxisGet(plotRef)` reads their common values, and
`sharedXAxisSet(plotRef, fields)` writes `scale`, `major_step`, and/or
`minor_grid` to every panel of one persistent 2D plot. Multi-panel rendering
uses identical logarithmic X grid positions in every panel.

Each panel owns its Y-left/Y-right series, Y presentation, annotations and
legend content. The renderer uses the existing stacked-layout and axis-override
surfaces; no second Graph Series registry or independent panel-X state exists.

## Series kinds

`kind` describes geometry/representation. It is distinct from `style`.
Supported values in 2.0.0 are:

| Kind | Meaning |
|---|---|
| `auto` | inherit the graph's normal line/scatter choice |
| `line` | connected line |
| `scatter` | marker-only observations |
| `line_marker` | line plus markers |
| `step` | staircase line; `step_mode=pre|post|mid` |
| `errorbar` | error-bar-oriented trace; x/y error binding required |
| `band` | filled lower/upper envelope; `band` binding required |
| `bar` | numeric-X bar plot; optional `bar_width`, `bar_baseline`, and exact Dataset-bound X intervals via `bar_bounds` |
| `histogram` | bins the complete finite Y-variable sample; optional `histogram_bins` and `histogram_normalization` |
| `box_whisker` | box/median/IQR whiskers over the complete finite Y-variable sample; optional IQR multiplier and outlier display |

Error bars and bands are also orthogonal features: a `scatter` can carry
`y_error`, and a `line` can carry a `band`.  `kind=errorbar` and `kind=band`
are convenience primary representations, not separate data stores.

`histogram` and `box_whisker` are whole-panel distribution representations.
They are available for a single-panel `plot.dataset.xy` PlotSpec, use only the
left axis, and cannot be mixed with each other or with Cartesian trace kinds.
The stable Graph Series X binding remains the row-coordinate identity, while
the complete finite Y-variable sample supplies the distribution values. CORE
does not publish fake binned Variables or quartile Datasets.

Histogram options are:

```text
histogram_bins             auto | integer 2..512
histogram_normalization    count | probability | density
```

Box/whisker options are:

```text
box_whisker_iqr            positive number (default 1.5)
box_show_outliers          boolean
```

Distribution preparation always reads the complete selected sample with
`reduction=none`; line/scatter display reduction is never reused for bins or
quartiles. Pie remains deferred because it requires a non-Cartesian binding
model rather than an X/Y trace interpretation.


### Exact X-interval bars

A `kind=bar` series may bind each bar to explicit lower/upper X variables from the same Dataset:

```tcl
bar_bounds [dict create \
    lower_variable_id lower_frequency \
    upper_variable_id upper_frequency]
bar_baseline -90
```

`bar_bounds` is presentation binding state, not a second data model. Both variables are prepared with the owning Graph Series and converted through the normal X-unit/display-unit path. This is intended for interval-valued bars such as spectral bands or binned scientific results where a single scalar `bar_width` would alter the actual X support. `bar_baseline` is optional (`auto` means display zero) and, when numeric, is expressed in the owning Y variable's source unit before normal display-unit and level-scale conversion. The converted explicit baseline must be finite. Scalar-width and interval bars follow the same baseline policy. On a logarithmic Y axis a non-positive baseline is replaced by half the smallest positive plotted value (or that value if halving would underflow). The final panel/axis scale determines this fallback. Bar-specific fields may remain persisted while a user temporarily changes the series kind to line/scatter; they are ignored until the representation is changed back to `bar`.


### 2-D family grouping

A normal 2-D series may optionally declare `family_variable_id` and `family_label_prefix`.
The family variable may contain text or finite numeric values in the same Dataset. `plot.dataset` then
renders one trace per distinct family value while preserving the original Dataset
rows. This is intended for curve/spectral families already represented in long-form
canonical Datasets; consumers must not create private per-curve renderers or duplicate
curve payloads merely to obtain a family overlay.

Family grouping applies to `line`, `scatter`, `line_marker`, and `step` series
in both single and stacked panels, including right Y axes. Each group retains
its own trace, label and explicit series style; no edge crosses family boundaries.

For a filtered and ordered long-form Dataset, a PlotSpec v2 series may also
declare `row_filters`, `secondary_variable_id`, and `ordering_variable_id`:

```tcl
dict create id contour dataset_id corrected_contour \
    x_variable_id v0005 y_variable_id v0006 axis left kind line \
    family_variable_id v0002 secondary_variable_id v0003 \
    ordering_variable_id v0004 \
    row_filters [list [dict create filter_variable_id v0001 \
        predicate exact_equal value internal]]
```

The family and secondary fields accept canonical text or numeric values.
`row_filters` use the public Graph Series predicates, so a text value such as
`internal` is selected directly. The ordering variable must be numeric; points
within each family are sorted by it, with source row ordinal breaking ties.
The secondary variable remains available in the prepared data even when it
does not control styling. These bindings survive Session save and reopen.

## Style inheritance

Style is resolved in this order:

```text
framework/global defaults
        ↓
graph defaults already supported by plot.dataset
        ↓
PlotSpec defaults.style
        ↓
series.style
```

Available style fields:

```text
color         auto | #RRGGBB
line_style    auto | inherit | solid | dashed | dotted | dashdot | none
line_width    auto | inherit | positive number
marker        auto | inherit | none | circle | square | diamond |
              triangle_up | triangle_down | plus | x | star
marker_size   auto | inherit | positive number
marker_fill   auto | inherit | none | full
opacity       auto | inherit | 0..1
```

**Missing**, `inherit`, and `auto` are not the same concept:

- missing field: do not override the parent layer;
- `inherit`: explicitly keep the parent layer;
- `auto`: ask the renderer for its automatic value at that level;
- concrete value: explicit override.

The persisted PlotSpec records field presence separately, so a missing field
is not collapsed into an explicit `auto`.

`opacity` is primarily meaningful for filled primitives such as bands, bars
and reference regions. Line transparency depends on the graphics toolkit and
is not used as a hidden color transformation.

## Error bars

Error magnitudes are variable bindings, never vectors embedded in a config.
A symmetric Y uncertainty:

```tcl
dict create \
    mode symmetric \
    variable_id v0005
```

An asymmetric uncertainty:

```tcl
dict create \
    mode asymmetric \
    lower_variable_id v0005 \
    upper_variable_id v0006
```

Attach them as `x_error` and/or `y_error` to a series.  Error variables are
read from the same original rows as X/Y. Large-dataset reduction carries the
auxiliary values from the exact selected source rows; it does not interpolate
errors.

Error magnitudes are converted through the Unit API as **deltas**.  For a
non-linear Level Scale, Y lower/upper endpoints are formed in linear display
coordinates and then transformed, rather than incorrectly scaling an error
magnitude as though it were an absolute value.

Example:

```tcl
set measured [dict create \
    id measured \
    dataset_id fit_result \
    x_variable_id v0001 \
    y_variable_id v0002 \
    axis left \
    kind scatter \
    y_error [dict create mode symmetric variable_id v0004]]
```

## Uncertainty bands

A band uses absolute lower/upper variables from the same dataset:

```tcl
band [dict create \
    lower_variable_id v0005 \
    upper_variable_id v0006 \
    draw_center 1]
```

The normal scientific fitting case can therefore be represented without
copying vectors into plot configuration:

```text
measurements    scatter + error bars
fit             line
confidence      band
```

The lower/upper variables are unit-converted and Level-Scale transformed as
absolute endpoints. No interpolation is introduced.

## Axes

Each panel may contain:

```text
axes.x
axes.y_left
axes.y_right
```

For multi-panel `plot.dataset.xy`, `axes.x` is a graph-wide shared declaration.
A compatible declaration may appear on any panel, but explicit X
`display_unit`, `scale`, `direction`, `min`, `max`, and custom X tick values must not conflict across
panels. Y-left and Y-right remain panel-local.

Each axis accepts any subset of:

```text
label
display_unit
scale          auto | linear | log
direction      auto | normal | reverse
min
max
tick_positions ; separated finite numeric X positions (X axis only)
tick_labels    ; separated nonempty labels paired with tick_positions
```

Example:

```tcl
dict set panel axes x [dict create \
    label "Elapsed time" \
    display_unit h \
    scale linear \
    direction reverse \
    min 0 \
    max 8]
```

`display_unit` uses the framework Unit API. Incompatible units fail; v2 does
not invent scientific conversions.

For categorical positions such as a protocol ranking, set both X tick fields:

```tcl
dict set panel axes x tick_positions "1;2;3" \
    tick_labels "NEC family;RC5;Sony SIRC"
```

The labels are presentation state in the persistent Plot Variant; the numeric
X coordinate remains in the canonical Dataset. Semicolons separate labels.

### Axis authority

PlotSpec axis fields remain part of `PLOT_DATASET_PLOTSPEC_v2`, but overlapping
presentation state is no longer maintained as an independent final override.
For X/Y-left/Y-right display units and manual `min`/`max` bounds, a saved CORE
**Axes...** state is authoritative for that exact graph or variant. If CORE
Axes has been restored to automatic, PlotSpec display-unit and bound values are
ignored for effective rendering. If no CORE axis state has been declared, the
PlotSpec values remain the compatibility/API fallback.

PlotSpec `scale=linear|log` remains authoritative for 2D X/Y scale in this
release because GX-TXT 0.9.7.21 exposes no overlapping 2D X/Y scale control.
PlotSpec `direction=normal|reverse` is likewise persistent provider-owned
presentation state and is applied after normal axis-range resolution. `auto`
leaves the renderer direction unchanged.
For labels, an explicit descriptor graph label wins; a PlotSpec label is used
when the descriptor graph label is `auto`/blank. Existing persisted PlotSpecs
are not rewritten: authority is normalized deterministically at render time.
This removes renderer-precedence ambiguity without creating a second axis
registry or a third state layer.

## Annotations

PlotSpec reference annotations belong to the panel, **not** to `series[]`.
This avoids polluting series ordering, legends and variable semantics.

Supported types:

```text
reference_line
reference_region
text
```

`axis` is `x`, `left`, or `right`. Constant `value`, `min`, and `max` are in
the corresponding **display-axis coordinates**. A `text` annotation requires
numeric `x`, numeric `y` and a single-line `label`; X and Y are display-axis
coordinates, and `axis=right` selects Y Right. Example:

```tcl
dict set panel annotations [list \
    [dict create type reference_line axis x value 3.0 \
        label "Lamp on" line_style dashed] \
    [dict create type reference_region axis left min 6.8 max 7.2 \
        label "target" opacity 0.12] \
    [dict create type text axis left x 4.5 y 7.1 label "event A"]]
```

These coexist with the framework's existing interactive/data annotations;
they do not replace CORE annotation APIs.

## Base graph and variants

For the base graph:

```tcl
set ref [::GX::PlotDatasetAPIv2::createPlotFromSpec $spec base]
```

For a new variant:

```tcl
set ref [::GX::PlotDatasetAPIv2::createPlotFromSpec $spec variant]
```

or clone from a known source variant where supported by the underlying v1/
CORE variant service:

```tcl
set ref [::GX::PlotDatasetAPIv2::createPlotFromSpec $spec variant p0001]
```

Each variant has separate Graph Series and a separate PlotSpec v2 sidecar.
`readPlot` returns `graph_id`, `variant_id`, configuration, series, PlotSpec
and artifact state.

## Left/right Y axes

Every Cartesian series declares:

```text
axis = left | right
```

Multiple compatible series may share either side. The existing
`plot.dataset` scientific unit checks remain active.  v2 does not silently
place incompatible quantities on the same axis.  Dual-Y layout and final
renderer geometry remain the responsibility of the framework Multi-Y Axis
Plot API used by `plot.dataset`.

## Render and rerender

Full render:

```tcl
set result [::GX::PlotDatasetAPIv2::render $ref]
```

This delegates to the normal GX-TXT analysis queue, so the consumer does not
construct `runtime.ini`, call Octave or know output paths.

Cache-only rerender:

```tcl
set result [::GX::PlotDatasetAPIv2::rerender $ref]
```

Style, title, axes and reference-annotation changes can be refreshed from the
current PlotSpec during rerender. Changing an error/band variable binding is a
data-preparation change and invalidates the preparation fingerprint; the API
then requires a full render instead of reusing an incompatible cache.

## Artifacts

```tcl
set a [::GX::PlotDatasetAPIv2::artifacts $ref]
puts [dict get $a graph_artifact]
puts [dict get $a render_cache]
puts [dict get $a summary]
```

The returned paths come from the existing plot.dataset/v1/CORE artifact
mechanisms.  v2 does not create a parallel artifact registry.

## Errors

Examples of explicit failures include:

- unknown `dataset_id` or `variable_id`;
- `Use=no` auxiliary variable;
- unsupported series kind/capability;
- malformed asymmetric error binding;
- `kind=errorbar` without an X or Y error;
- `kind=band` without lower/upper variables;
- conflicting shared-X declarations across panels;
- more than one panel for `plot.dataset.xy_region`;
- unsupported graph type such as v2 3D;
- stale PlotSpec bindings that disagree with Graph Series;
- incompatible units or X semantics detected by the renderer.

There is no silent name fallback and no silent representation fallback.

## GUI integration

GX-TXT 0.9.7.41 retains Graph Configuration Extension API v1 and adds Axis Configuration Extension API v1. `plot.dataset` registers `plot.dataset.graph_configuration` for `plot.dataset.xy`, so the normal **Configure...** window contains:

- **Multi-panel (vertically stacked, shared X)** toggle;
- panel selector and `Add`, `Remove`, `Up`, `Down` lifecycle controls;
- optional panel title;
- panel-local Y Left and Y Right `label`, `display_unit`, `scale`, `min`, and `max` fields.

The global plot title and X label remain the normal graph-wide configuration fields. No independent panel X controls are exposed.

In 3.12.7, the same Graph configuration extension shows **Single-panel Y
scales** while multi-panel mode is off. Y Left has Auto, Linear and Log;
Y Right has the same choices when a right-axis series exists. The controls
write the first panel's existing `axes.y_left.scale` and `axes.y_right.scale`
fields. Enabling multi-panel mode hides these controls and retains the
per-panel Y configuration above. CORE Axes overrides still take precedence
when explicitly selected.

In 3.12.8, common **Axes** is the ordinary editor for graph-wide X scale,
major step and minor grid. It reads and writes the shared PlotSpec X fields
through `sharedXAxisGet`/`sharedXAxisSet` for both base plots and Variants.
The public API retains `scale`, `major_step` and `minor_grid`; `major_step`
means a linear tick interval on linear X and a number of decades on log X.
The previous Plots-page shared-X strip and provider duplicate X controls are
removed. Historical CORE X scale/step overrides are shown on first open and
are migrated to PlotSpec on Save so they cannot shadow later API writes.

The standard CORE **Series...** editor keeps Graph Series identity authoritative. When multi-panel mode is enabled, the provider area shows only a **Panel** selector for assigning the selected stable `series_id` to an already existing panel. When multi-panel mode is disabled, that selector is hidden and panel assignment is automatic from the user's point of view. Panel creation/removal/order never belongs to the Series editor.

The optional public `openEditor` remains available for advanced per-series PlotSpec presentation. It likewise does not own panel lifecycle in 3.2.0.

## Legacy and API v1 compatibility

Nothing in v2 removes:

- `PLOT_DATASET_API_v1`;
- Graph Series v1 behavior;
- base graph / variants;
- no Graph-Series row/group predicate for automatic 2D family expansion;
- Level Scale;
- region selection;
- render cache/rerender;
- current 3D implementation.

If a 2D graph has no PlotSpec v2 sidecar, rendering follows the existing
v1 Graph-Series semantics.  `deriveSpec` can create a basic v2 in-memory
representation of an existing Graph-Series plot without changing it.

## 3D status

The user's current 3D path has not yet been validated end-to-end.  For that
reason **PLOT_DATASET_API_v2 does not expose or redesign 3D in release 2.0.0**.
The existing `plot.dataset.xyz` renderer and dedicated 3D descriptor configuration
are preserved unchanged.  `validateSpec` rejects a v2 `graph_type` other than
`cartesian_2d` rather than pretending that an untested feature is supported.

## Minimal example

```tcl
set spec [::GX::PlotDatasetAPIv2::newSpec -title "Temperature"]
set panel [lindex [dict get $spec panels] 0]

dict set panel series [list [dict create \
    id temperature \
    dataset_id reactor \
    x_variable_id v0001 \
    y_variable_id v0002 \
    axis left \
    kind line \
    label "Temperature"]]

dict set spec panels [list $panel]
set ref [::GX::PlotDatasetAPIv2::createPlotFromSpec $spec base]
set result [::GX::PlotDatasetAPIv2::render $ref]
```

## Multi-series example

```tcl
set spec [::GX::PlotDatasetAPIv2::newSpec -title "Ion concentrations"]
set p [lindex [dict get $spec panels] 0]
dict set p series [list \
    [dict create id cl dataset_id concentrations \
        x_variable_id v0001 y_variable_id v0002 axis left \
        kind line_marker label "Cl-"] \
    [dict create id no2 dataset_id concentrations \
        x_variable_id v0001 y_variable_id v0003 axis left \
        kind scatter label "NO2-"] \
    [dict create id no3 dataset_id concentrations \
        x_variable_id v0001 y_variable_id v0004 axis left \
        kind line label "NO3-"]]
dict set spec panels [list $p]
set ref [::GX::PlotDatasetAPIv2::createPlotFromSpec $spec base]
```

## Dual-Y example

Different datasets may share X when their metadata make the X scientifically
compatible and their units are convertible:

```tcl
set spec [::GX::PlotDatasetAPIv2::newSpec -title "Chemistry and current"]
set p [lindex [dict get $spec panels] 0]
dict set p axes x [dict create display_unit h label "Elapsed time"]
dict set p series [list \
    [dict create id cl dataset_id concentrations \
        x_variable_id v0001 y_variable_id v0002 axis left kind line] \
    [dict create id current dataset_id sequence.joined \
        x_variable_id v0002 y_variable_id v0003 axis right kind step]]
dict set spec panels [list $p]
set ref [::GX::PlotDatasetAPIv2::createPlotFromSpec $spec base]
```

If one X is HMS elapsed time in hours and the other is numeric elapsed time in
seconds, the renderer uses semantic metadata and the Unit API; it does not
resample either series.

## Multi-panel external-consumer example

This example uses only `PLOT_DATASET_API_v2`. The panels share a visible X
domain even though their series come from different canonical datasets and X
Variable IDs:

```tcl
set spec [::GX::PlotDatasetAPIv2::newSpec \
    -graph_id plot.dataset.xy \
    -title "Reactor overview"]

set electrical [dict create \
    id electrical \
    axes [dict create \
        x [dict create display_unit h min 0 max 8] \
        y_left [dict create display_unit V] \
        y_right [dict create display_unit A]] \
    series [list \
        [dict create id voltage dataset_id reactor.electrical \
            x_variable_id elapsed y_variable_id voltage axis left kind line] \
        [dict create id current dataset_id reactor.electrical \
            x_variable_id elapsed y_variable_id current axis right kind line]] \
    annotations {}]

set chemistry [dict create \
    id chemistry \
    axes [dict create \
        x [dict create display_unit h min 0 max 8] \
        y_left [dict create display_unit ppm]] \
    series [list \
        [dict create id chloride dataset_id reactor.chemistry \
            x_variable_id sample_time y_variable_id chloride axis left \
            kind line_marker]] \
    annotations {}]

dict set spec panels [list $electrical $chemistry]
::GX::PlotDatasetAPIv2::validateSpec $spec
set ref [::GX::PlotDatasetAPIv2::createPlotFromSpec $spec base]
set result [::GX::PlotDatasetAPIv2::render $ref]
```

`elapsed` and `sample_time` remain distinct stable X identities. The renderer
only synchronizes their compatible display-domain X range.

## Consumer module example

A fitting module can centralize all graphics in `plot.dataset`:

```tcl
namespace eval ::GX::MyFittingModule {}

proc ::GX::MyFittingModule::publishPlot {} {
    # The fitting module has already published dataset "fit_result".
    set spec [::GX::PlotDatasetAPIv2::newSpec \
        -title "Measured data and nonlinear fit"]
    set p [lindex [dict get $spec panels] 0]

    dict set p axes x [dict create label "Anode voltage"]
    dict set p axes y_left [dict create label "Anode current"]

    dict set p series [list \
        [dict create \
            id measured \
            dataset_id fit_result \
            x_variable_id v0001 \
            y_variable_id v0002 \
            axis left \
            kind scatter \
            label "Measured" \
            style [dict create marker circle] \
            y_error [dict create mode symmetric variable_id v0004]] \
        [dict create \
            id fit \
            dataset_id fit_result \
            x_variable_id v0001 \
            y_variable_id v0003 \
            axis left \
            kind line \
            label "Fit" \
            style [dict create line_width 2]]]

    dict set spec panels [list $p]
    set ref [::GX::PlotDatasetAPIv2::createPlotFromSpec $spec base]
    return [::GX::PlotDatasetAPIv2::render $ref]
}
```

The consumer does not know how Graph Series are persisted, how units are
converted, how GNU Octave is launched, where `runtime.ini` lives, how the cache
is stored, or how the PNG path is constructed.  That orchestration belongs to
`plot.dataset`.
