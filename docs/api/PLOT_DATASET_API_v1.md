# `PLOT_DATASET_API_v1`

SPDX-License-Identifier: GPL-3.0-or-later

## 1. Scope

CORE service guarantee: **GX-TXT Pipeline 0.9.7.16+**. API version: 1; bundled renderer version: 1.2.0.

`PLOT_DATASET_API_v1` is the public CORE rendering service, hosted by the protected plot.dataset module, for using `plot.dataset` as a scientific rendering engine from another GX-TXT module or service without driving the GUI, editing `runtime.ini`, reading private module files, or duplicating plotting code.

This is a single, versioned service exported by the protected CORE `plot.dataset` package through the existing Standard Module API descriptor. It is not a separate framework-wide Render API or registry. The package is always installed in this baseline; the user Enabled switch controls direct module use, not this service.

For new integrations the primary data model is **Graph Series API v1**. The legacy X/Y/Y2/Additional-series path remains supported by the renderer for old sessions but is not the recommended programmatic model.

Stable variable identity is always the pair:

```text
dataset_id + variable_id
```

A variable name is display/current-schema information only; it is never the persistent API identity.

## 2. API version

API name:

```text
PLOT_DATASET_API_v1
```

API version:

```text
1
```

Tcl namespace:

```tcl
::GX::PlotDatasetAPIv1
```

The module version and API version are independent. A compatible future `plot.dataset` release may continue exporting API v1.

## 3. Discovery

Do not hard-code the plugin directory. Discover `plot.dataset` through Standard Module API v1 and inspect its descriptor:

```tcl
set moduleId plot.dataset
set descriptor [::GX::moduleField $moduleId descriptor ""]
if {$descriptor eq ""} {
    error "required GX-TXT CORE service PLOT_DATASET_API_v1 is missing"
}
set d [::GX::parseIni $descriptor]
set ids [::GX::splitList [::GX::descriptorValue $d public_apis ids ""]]
if {"PLOT_DATASET_API_v1" ni $ids} {
    error "required GX-TXT CORE service PLOT_DATASET_API_v1 is missing"
}
set section public_api.PLOT_DATASET_API_v1
set version [::GX::descriptorValue $d $section api_version ""]
set entry [::GX::descriptorValue $d $section entrypoint ""]
source [file join [file dirname $descriptor] $entry]
```

The descriptor also publishes:

- namespace;
- documentation path;
- capability list.

No second registry is introduced: discovery starts from the existing GX-TXT module catalog and the protected CORE package descriptor. The descriptor advertises this API with Enabled=0 and Enabled=1. Consumers must not use moduleIsEnabled as an API availability check; absence of the descriptor or API entrypoint in 0.9.7.16+ indicates an incomplete/incompatible installation.

## 4. Lifecycle

Typical lifecycle for a consumer:

1. Standard Module API discovers the protected CORE `plot.dataset` descriptor, regardless of its Enabled state.
2. The consumer discovers and sources `PLOT_DATASET_API_v1` from the descriptor.
3. An open GX-TXT session supplies the canonical Dataset Registry. For a Graph Series plot with no selected primary source, the service temporarily uses the first active Series dataset as the standard runner's primary source while preparing render/rerender commands, then restores the unselected state. An existing primary selection is preserved. Legacy and 3D plots continue to require their normal source configuration.
4. `createPlot` or `openPlot` obtains an opaque plot-reference dict.
5. The consumer creates/updates Graph Series using stable dataset/variable IDs.
6. Optional plot configuration (for example title) is set through the API.
7. `render` performs a full analysis/render; `rerender` reuses the normal GX-TXT render cache when valid.
8. `artifacts` returns the produced artifact paths. Rendering through this API works while the user-facing plot.dataset module is disabled and preserves its Enabled state.
9. Session manifest persistence remains framework-owned. Graph Series, variants and graph configuration use their existing CORE persistence mechanisms.

A consumer must not edit `runtime.ini`, `render_cache.mat`, variant directories, Graph Series manifest sections, or private Octave files.

## 5. Plot reference

Functions operating on a plot use the dict returned by `createPlot` or `openPlot`:

```tcl
module_id  plot.dataset
graph_id   plot.dataset.xy
variant_id ""
plot_id    plot.dataset.xy
```

For a variant:

```tcl
variant_id p0001
plot_id    plot.dataset.xy/p0001
```

Consumers should treat this dict as an API value and should not synthesize private paths from it.

## 6. Public entry points

### `apiInfo`

```tcl
::GX::PlotDatasetAPIv1::apiInfo
```

Returns a dict containing API name/version, module ID/version and capabilities.

### `capabilities`

```tcl
::GX::PlotDatasetAPIv1::capabilities
```

Returns the capabilities declared by the installed module descriptor.

### `supports capability`

Returns `1` or `0`.

### `requireCapability capability`

Returns `1` if available; otherwise raises an explicit `plot.dataset API v1: capability ... is not supported` error. There is no silent fallback.

### `createPlot graphId ?kind? ?sourceVariant?`

`kind` is `base` (default) or `variant`.

Base example:

```tcl
set p [::GX::PlotDatasetAPIv1::createPlot plot.dataset.xy base]
```

Variant copied from the base graph:

```tcl
set p [::GX::PlotDatasetAPIv1::createPlot plot.dataset.xy variant]
```

Variant copied from another variant:

```tcl
set p2 [::GX::PlotDatasetAPIv1::createPlot plot.dataset.xy variant p0001]
```

Returns a plot-reference dict.

### `openPlot graphId ?variantId?`

Returns a validated plot reference for an existing base graph or variant.

### `deletePlot plotRef`

Deletes a variant. A base graph is not deletable; use `setPlotEnabled`.

### `setPlotEnabled plotRef state`

Enables/disables a base graph or variant through the existing CORE graph/variant state.

### `setConfig plotRef key value`

Sets a descriptor-declared graph configuration key such as `title`, `x_label`, `y_label`, `y2_label`, `plot_style`, etc. Unknown keys fail explicitly.

### `getConfig plotRef key`

Reads a descriptor-declared graph configuration value.

### `setTitle plotRef title`

Convenience wrapper for:

```tcl
setConfig $plotRef title $title
```

### `setSeries plotRef seriesId fields`

Creates or updates one Graph Series. New series require:

```text
dataset_id
x_variable_id
y_variable_id
axis
```

Optional Graph Series fields already supported by CORE may also be passed:

```text
label
enabled
order
alignment_mode
manual_offset_seconds
```

Example:

```tcl
::GX::PlotDatasetAPIv1::setSeries $p current [dict create \
    dataset_id sequence.joined \
    x_variable_id v0002 \
    y_variable_id v0003 \
    axis left \
    label "Current"]
```

Updates may contain only changed fields because the module API reads the current Graph Series and delegates the merged record back to Graph Series API v1.

### `getSeries plotRef seriesId`

Returns the resolved Graph Series dict, including current names/units/semantic metadata supplied by CORE.

### `listSeries plotRef ?includeDisabled?`

Returns Graph Series in persistent display order. `includeDisabled` defaults to `1`.

### `removeSeries plotRef seriesId`

Removes a Graph Series through Graph Series API v1.

### `setSeriesEnabled plotRef seriesId state`

Enables/disables a series without changing its stable dataset/variable identities.

### `moveSeries plotRef seriesId direction`

`direction` is `up` or `down`. Delegates ordering to Graph Series API v1.

### `setSeriesOrder plotRef orderedIds`

Sets the complete series order. `orderedIds` must contain every current series exactly once.

### `readPlot plotRef`

Returns a dict describing the current plot:

- graph and variant identity;
- enabled state;
- display name;
- descriptor-backed plot configuration;
- resolved Graph Series;
- artifact locations.

### `renderCommand plotRef ?operation?`

Returns the framework-built queue item for `render` or `rerender`. This is useful to a host that already owns process scheduling. It does not execute the process.

### `render plotRef`

Runs the normal GX-TXT standard renderer synchronously and returns:

```text
execution  -> label/output
artifacts  -> artifact dict
```

It uses the standard module runtime writer, standard Octave wrapper, Graph Series runtime and output-contract checks. It does not call the GUI.

### `rerender plotRef`

Runs the normal render-cache rerender path synchronously. If a valid base cache/runtime is unavailable, the API returns an explicit error. Variant rerender preserves the existing CORE fingerprint behavior, which may automatically fall back to full analysis when preparation data changed.

### `artifacts plotRef`

Returns:

```text
output_dir
graph_artifact
render_cache
summary
existing
```

`existing` contains only files currently present. The other paths identify the expected module artifacts.

## 7. Parameters and validation

### Graph IDs

Use graph IDs declared by the installed `plot.dataset` descriptor, currently including:

```text
plot.dataset.xy
plot.dataset.xy_region
plot.dataset.xyz
```

Graph Series operations are supported only where the graph declares the standard Series editor. In API v1 that is the 2D graphs. Calling a Series method for an unsupported graph produces an explicit error.

### Stable variables

Always supply:

```tcl
dataset_id      d1
x_variable_id   v0001
y_variable_id   v0002
```

Do not persist `time`, `pH`, `Cl-`, etc. as technical identities.

CORE resolves the current canonical names and rejects Use=no variables when an enabled series would use them.

### Axis

Graph Series API owns:

```text
axis=left
axis=right
```

`plot.dataset` permits multiple series on either axis, subject to scientific unit compatibility.

## 8. Errors

All module-API validation errors are prefixed:

```text
plot.dataset API v1:
```

Examples:

```text
plot.dataset API v1: unknown graph '...'
plot.dataset API v1: capability '...' is not supported
plot.dataset API v1: new series requires 'dataset_id'
plot.dataset API v1: graph 'plot.dataset.xyz' does not support Graph Series
plot.dataset API v1: unknown plot variant 'p9999'
```

Errors originating from a delegated CORE API are rethrown through the module API with the same prefix. No invalid dataset/variable reference is silently converted to a name-based binding.

## 9. Graph Series model

For new consumers, one plotted trace is one Graph Series. `PLOT_DATASET_API_v1` does not maintain a second Series registry. Create/update/remove/enable/order operations delegate to Graph Series API v1.

Multiple datasets are allowed because each series carries its own `dataset_id`.

`plot.dataset` only overlays datasets when the X coordinates are scientifically compatible. It does not join, interpolate or resample datasets merely to draw them.

## 10. Elapsed-time compatibility

An important API v1 scientific rule is that representation and semantics are distinct.

These X variables are compatible when their units are convertible:

```text
semantic_role=elapsed_time, value_kind=elapsed_time, value_format=hms, unit=h
semantic_role=elapsed_time, value_kind=number,                    unit=s
```

The first is an HMS field; the second is a numeric duration. They are the same scientific coordinate when they share the same elapsed-time origin. Unit Registry performs display conversion (for example seconds to hours); point locations are not interpolated.

Other explicit value-kind mismatches remain rejected.

## 11. Base graph and variants

Base graph and variants are distinct persistent configurations.

Base:

```tcl
set p [::GX::PlotDatasetAPIv1::createPlot plot.dataset.xy base]
```

Variant:

```tcl
set v [::GX::PlotDatasetAPIv1::createPlot plot.dataset.xy variant]
```

Series methods automatically address the proper Graph Series scope by using the plot reference's `variant_id`.

A variant created from base uses the existing CORE Plot Variant API behavior, including copying active Graph Series/configuration. The module API does not implement its own copy format.

## 12. Left/right Y axes

Dual-Y is selected per series:

```tcl
axis left
axis right
```

Series sharing one axis must have compatible Y units. `plot.dataset` rejects an ambiguous same-axis unit combination instead of silently scaling it.

The right axis uses the framework Multi-Y renderer and participates in normal graphics configuration, Level Scale, legend and rerender behavior.

## 13. Render and rerender

`render` executes the same standard runner used by GX-TXT interactive analysis. `rerender` executes the standard cache path.

The API does not invent a second renderer and does not bypass:

- Standard Module runtime writing;
- Graph Series runtime;
- Unit Registry;
- graphics environment/inheritance;
- Render Cache API;
- output-contract validation;
- variant runtime/fingerprints.

For asynchronous host scheduling use `renderCommand` and submit the returned queue item using the host's normal scheduling policy.

## 14. Artifacts

For a base graph the graph PNG is under the normal module output directory:

```text
<session>/analysis/plot.dataset/
```

For a variant it is under the existing Plot Variant directory:

```text
<session>/analysis/plot.dataset/variants/<graph_id>/<variant_id>/
```

Never construct these paths in a consumer. Use `artifacts`.

## 15. Capabilities

The installed descriptor publishes the API capabilities. API v1 currently declares:

```text
graph_series
base_graph
variants
multi_dataset
dual_y
series_enable
series_order
plot_config
render
rerender
artifacts
read_config
legacy_compatible
stable_variable_identity
```

Consumers should call `supports`/`requireCapability` rather than assume future or optional functions. Missing capabilities are explicit; there is no silent downgrade to legacy bindings.

## 16. Legacy compatibility

The legacy X/Y/Y2/Additional-series renderer remains present for existing sessions. It is not exposed as the preferred write model of API v1.

A new consumer should use Graph Series. `legacy_compatible` means that installing/using API v1 does not remove old-session rendering; it does **not** mean that the API converts new Series into legacy fields.

## 17. Minimal one-series example

```tcl
set p [::GX::PlotDatasetAPIv1::createPlot plot.dataset.xy base]
::GX::PlotDatasetAPIv1::setSeries $p current [dict create \
    dataset_id sequence.joined \
    x_variable_id v0002 \
    y_variable_id v0003 \
    axis left \
    label Current]
::GX::PlotDatasetAPIv1::setTitle $p "Current vs elapsed time"
set result [::GX::PlotDatasetAPIv1::render $p]
puts [dict get $result artifacts]
```

## 18. Multi-series example

```tcl
set p [::GX::PlotDatasetAPIv1::createPlot plot.dataset.xy base]
::GX::PlotDatasetAPIv1::setSeries $p chloride [dict create \
    dataset_id concentrazioni x_variable_id v0001 y_variable_id v0002 \
    axis left label Cl-]
::GX::PlotDatasetAPIv1::setSeries $p nitrate [dict create \
    dataset_id concentrazioni x_variable_id v0001 y_variable_id v0004 \
    axis left label NO3-]
::GX::PlotDatasetAPIv1::setSeriesOrder $p {chloride nitrate}
```

## 19. Dual-Y and multi-dataset example

```tcl
set p [::GX::PlotDatasetAPIv1::createPlot plot.dataset.xy base]

# Concentration: elapsed HMS/h.
::GX::PlotDatasetAPIv1::setSeries $p chloride [dict create \
    dataset_id concentrazioni \
    x_variable_id v0001 \
    y_variable_id v0002 \
    axis right \
    label Cl-]

# Current: numeric elapsed seconds.  Same scientific elapsed-time origin.
::GX::PlotDatasetAPIv1::setSeries $p current [dict create \
    dataset_id sequence.joined \
    x_variable_id v0002 \
    y_variable_id v0003 \
    axis left \
    label A]

set result [::GX::PlotDatasetAPIv1::render $p]
```

No table join is performed by the plotter. The two X units are converted to a common display unit only after semantic compatibility has been established.

## 20. Example consumer module

A consumer module should discover the API during runtime/initialization, source the advertised entrypoint, check capabilities, then call only the namespace above:

```tcl
namespace eval ::MyAnalysis {}

proc ::MyAnalysis::renderResult {} {
    set descriptor [::GX::moduleField plot.dataset descriptor ""]
    if {$descriptor eq ""} {error "required GX-TXT CORE service PLOT_DATASET_API_v1 is missing"}
    set d [::GX::parseIni $descriptor]
    set sec public_api.PLOT_DATASET_API_v1
    if {[::GX::descriptorValue $d $sec api_version ""] ne "1"} {
        error "PLOT_DATASET_API_v1 is required"
    }
    source [file join [file dirname $descriptor] \
        [::GX::descriptorValue $d $sec entrypoint ""]]

    ::GX::PlotDatasetAPIv1::requireCapability multi_dataset
    ::GX::PlotDatasetAPIv1::requireCapability render

    set p [::GX::PlotDatasetAPIv1::createPlot plot.dataset.xy variant]
    ::GX::PlotDatasetAPIv1::setSeries $p result [dict create \
        dataset_id my.analysis.output \
        x_variable_id v0001 \
        y_variable_id v0002 \
        axis left \
        label "Analysis result"]
    return [::GX::PlotDatasetAPIv1::render $p]
}
```

The consumer does not know the Octave entrypoint, runtime file format, cache layout, PNG path, Graph Series manifest format, or private implementation of `plot.dataset`.
