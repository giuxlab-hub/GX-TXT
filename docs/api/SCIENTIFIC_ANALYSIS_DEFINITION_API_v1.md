# Scientific Analysis Definition API v1

SPDX-License-Identifier: GPL-3.0-or-later

**Introduced:** GX-TXT Pipeline v0.8.1  
**Expanded:** v0.8.3 and v0.8.4  
**API version:** 1  
**Compatibility:** additive; v0.8.1-v0.8.3 definitions remain valid

## 1. Purpose and architecture

Scientific Analysis Definition API v1 is the declarative scientific data-flow layer of GX-TXT.

```text
canonical dataset(s)
        -> Standard Module API bindings
        -> Scientific Analysis Definition
        -> gxtxt_analysis_run()
        -> generic operation registry/kernels
        -> transformed series / features / status / provenance
        -> exports / generic plots
```

Keep these resources separate:

```text
module                executable job boundary
analysis definition   declarative scientific data-flow
mathematical model    mathematical function/model resource
render cache           optional rerender lifecycle/storage
shared graphics        presentation/rendering
```

A module must not implement a second expression evaluator, dependency graph, generic crossing/interpolation engine, dataset binding system, or private grid/legend system.

## 2. Public entry points

### Execute

```octave
result = gxtxt_analysis_run(definition_path, source_map, output_dir, options)
```

Arguments:

- `definition_path`: resolved `analysis.ini` path;
- `source_map`: struct mapping source-role IDs to trusted CSV paths;
- `output_dir`: output directory;
- `options`: optional struct.

Supported options:

```text
runtime_cfg   parsed runtime.ini struct; supplies bindings, model, parameters
parameters    struct of parameter overrides
render        true/false, default true
```

### Result/context contract

Return fields:

```text
result.definition_id
result.definition_path
result.context
result.exports
result.plots
result.operation_order
```

Important `result.context` fields:

```text
series          data/result series by ID
types           numeric/logical/string metadata
origins         source/operation provenance label
roles           semantic role metadata
units           unit metadata
status          row-aligned status metadata
reason          row-aligned machine-readable reason
features        compact per-group/global features + broadcast representation
parameters      effective Analysis Definition parameters
bindings        resolved variable binding metadata
lengths         series lengths
row_aligned     primary-row alignment flags
provenance      align/join/interpolate provenance
fit_results     fit diagnostics/results
source_rows     row count by source role
source_paths    resolved source paths
optional_missing optional variables that were not available
row_count       primary-source row count
```

### Validate/introspect

```octave
report = gxtxt_analysis_validate_definition(definition_path)
```

Fields include:

```text
valid
errors
warnings
meta
required_bindings
optional_bindings
operations
```

The GUI also provides descriptor-level **Preflight...** next to an Analysis Definition selector. It checks selection compatibility, declared bindings, dataset contracts when available, parameters, and basic dependency structure without executing scientific calculations. Octave validation remains authoritative at runtime.

## 3. Discovery

Global definitions:

```text
plugins/analysis_definitions/*/analysis.ini
```

Module-private definitions:

```text
plugins/modules/<module-id>/analysis_definitions/*/analysis.ini
```

Header:

```ini
[meta]
api_version=1
id=my.analysis_v1
kind=curve_family
name=My analysis
version=1
capabilities=expression;crossing;mask;plot;export
```

`kind` and `capabilities` are discovery/filter metadata. They do not hard-code scientific meaning into the framework.

Every new/updated Analysis Definition plugin must also implement Documentation API v1; see `DOCUMENTATION_API_v1.md`.

## 4. Module selector

A Standard Module API descriptor selects a definition with:

```ini
[config.analysis_definition_id]
type=analysis_definition
label=Analysis definition
required=1
scope=all
kind=curve_family
capabilities=expression;crossing;mask;plot;export
```

GX-TXT generates the selector and, in v0.8.4, adds:

```text
Parameters...
Preflight...
```

The runtime contains:

```ini
[scientific_analysis_api]
api_version=1

[analysis_definition.analysis_definition_id]
id=my.analysis_v1
api_version=1
kind=curve_family
capabilities=...
scope=global
descriptor_path=/resolved/path/analysis.ini
plugin_dir=/resolved/path
```

Use `descriptor_path`; do not rediscover definitions by filename.

## 5. Sources and row alignment

Declare source roles:

```ini
[sources]
roles=primary;chemistry

[source.primary]
type=table
required=1

[source.chemistry]
type=table
required=0
```

`source_map.primary`, `source_map.chemistry`, etc. provide the CSV paths.

The first source role is the **primary row set**. Ordinary row-preserving operations, CSV export and generic plots operate on the primary row set unless data are explicitly aligned/resampled.

v0.8.4 permits variables from sources with different row counts. It never silently aligns them. Use `align`, `join`, `resample`, or `interpolate` explicitly.

## 6. Variables

### Direct column

```ini
[variables]
ids=x;y;family

[variable.x]
source=primary
column=Vg_V
type=numeric
role=independent
unit=V
```

### Standard Module API binding

Preferred for generic modules:

```ini
[variable.x]
source=primary
binding=x
type=numeric
role=independent
unit=V
```

The binding resolves from standard runtime:

```ini
[bindings]
x=Vg_V
```

Resolution order:

1. non-empty Standard Module API binding;
2. `column=` fallback if declared;
3. variable ID as column name only when no binding/column was declared;
4. fail when required and unresolved/missing;
5. record as optional missing when `required=0`.

There is no second column-mapping API.

### Optional variable

```ini
[variable.sigma_y]
source=primary
binding=sigma_y
type=numeric
role=uncertainty
required=0
```

Missing optional IDs are listed in:

```octave
result.context.optional_missing
```

## 7. Parameters and v0.8.4 GUI

Declare scalar parameters:

```ini
[parameters]
ids=target;method_name;enabled

[parameter.target]
type=numeric
label=Crossing target
default=0.005
required=0
min=-1
max=1
unit=1

[parameter.method_name]
type=choice
label=Method
default=linear
choices=linear;nearest

[parameter.enabled]
type=bool
default=1
```

Supported types:

```text
numeric / number / double
string / text
bool / boolean / logical
choice
```

v0.8.4 generates parameter controls from these declarations. No module-specific Tcl is required.

Parameter values are persisted in Manifest Format 2 and emitted to:

```ini
[analysis_parameters]
target=0.005
method_name=linear
enabled=1
```

Override precedence at execution:

1. `options.parameters.<id>`;
2. runtime `[analysis_parameters]`;
3. definition `default=`.

Parameters are also scalar symbols visible to the expression engine. Operations with targets/bounds may use parameter references such as:

```ini
target_parameter=target
min_parameter=min_x
max_parameter=max_x
```

`choice` values are runtime-validated against `choices=`. Numeric `min=`/`max=` are also enforced.

## 8. Dependency graph and status propagation

Operations declare dependencies by **operation ID**:

```ini
[operation.normalized]
...
depends=zero;scale
```

GX-TXT:

- sorts operations topologically;
- rejects unknown dependencies;
- rejects dependency cycles;
- propagates `unavailable`/`failed` dependencies to dependent outputs as:

```text
status=unavailable
reason=dependency_unavailable
```

Do not build another dependency graph in a plugin.

### Status vocabulary

```text
valid
warning
unavailable
failed
```

Reasons are machine-readable. Current operations may emit, among others:

```text
target_not_reached
insufficient_data
ambiguous_crossing
ambiguous_match
unmatched
no_match_within_tolerance
outside_domain
invalid_input
duplicate_x
zero_variance
dependency_unavailable
group_not_found
optimizer_not_converged
```

A local scientific failure should not silently become a plausible number.

## 9. Operation registry

v0.8.4 uses an internal operation registry and numerical-kernel dispatcher. Descriptor syntax remains API v1.

Public operation types:

```text
expression
compare
normalize
aggregate
filter
select
crossing
mask
align
join
resample
interpolate
peak
extrema
integrate
area
derivative
slope
window
correlate
regress
fit
convert_unit
```

Aliases (`area`, `slope`, `peak`, `resample`) keep distinct descriptor meaning while reusing registered numerical kernels.

## 10. Core operations

### `expression`

```ini
[operation.ratio]
type=expression
expression=y / family
output=ratio
unit=1
```

Allowed arithmetic is provided by the framework expression evaluator. Operation outputs from earlier dependencies may be referenced directly by ID.

Strict dimensions are optional:

```ini
strict_units=1
```

See `UNIT_DIMENSION_API_v1.md`.

### `compare`

```ini
[operation.relative]
type=compare
value=amplitude
group=trace
reference=VIR
reference_aggregate=median
method=ratio
output=relative
```

### `normalize`

```ini
[operation.norm]
type=normalize
value=y
method=maxabs
output=y_norm
```

### `aggregate`

```ini
[operation.avg]
type=aggregate
value=y
method=mean
group=family
output=y_mean
```

Grouped aggregate values are broadcast back to their group rows so later expressions can reuse them.

### `filter` - historical destructive operation

```ini
[operation.keep]
type=filter
value=x
operator=ge
target=0
output=filtered
```

`filter` removes rows from the working primary-row context. It is retained for backward compatibility.

For reusable plotting/scientific domains, prefer non-destructive `mask`.

### `mask`

```ini
[operation.negative]
type=mask
value=x
operator=le
target_series=X0
depends=zero
output=negative_domain
```

Target forms:

```text
target=<literal>
target_series=<row-aligned series>
target_parameter=<declared parameter>
```

The output is a row-preserving logical series.

### `crossing`

```ini
[operation.zero]
type=crossing
x=x
y=y
target=0
group=family
interpolation=linear
extrapolation=forbid
output=X0
```

v0.8.4 supports linear interpolation and forbidden extrapolation for this feature API. Crossing follows the data order **within each group**; it does not silently sort X because that could destroy branch/loop/ hysteresis meaning.

One exact or interpolated crossing gives a valid feature. Multiple crossings are `unavailable / ambiguous_crossing`. Missing target is `unavailable / target_not_reached`.

Features exist simultaneously as:

```text
result.context.features.X0     compact per-group object
result.context.series.X0       row-aligned broadcast value
```

This lets later expressions use `X0` directly while feature-table export remains compact.

## 11. Non-row-aligned multi-source operations - v0.8.4

### `align`

Align a foreign numeric value series to a target numeric key/dimension:

```ini
[operation.chem_on_electrical]
type=align
target_x=time_fast
source_x=time_chem
value=ammonia
method=nearest
tolerance=30
output=ammonia_aligned
```

Supported methods:

```text
exact
nearest
linear
```

Extrapolation:

```text
forbid
nearest
linear
```

Default `align` method is `exact`.

Optional group isolation prevents interpolation across unrelated families:

```ini
target_group=experiment_fast
source_group=experiment_chem
```

Both group fields must be supplied together.

Provenance includes source row indices under:

```octave
result.context.provenance.<output>
```

### `resample`

`resample` uses the same contract as `align` but defaults to:

```text
method=linear
```

Example:

```ini
[operation.temperature_fast]
type=resample
target_x=time_fast
source_x=time_temperature
value=temperature
extrapolation=forbid
output=temperature_fast
```

### `join`

Exact left join by key:

```ini
[operation.batch_name]
type=join
left_key=sample_id
right_key=metadata_sample_id
value=metadata_label
output=sample_label
```

Keys may be numeric/logical or strings. Duplicate right keys produce `ambiguous_match`; unmatched left keys remain unavailable. Join does not silently select the first duplicate.

## 12. Generic interpolation

### `interpolate`

```ini
[operation.y_query]
type=interpolate
x=x_source
y=y_source
query=x_query
extrapolation=forbid
output=y_query
```

Linear interpolation is used.

Per-group interpolation:

```ini
group=source_family
query_group=query_family
```

If `query_group` is omitted and query length equals group length, the source `group` is reused as query grouping.

Source row provenance is preserved.

## 13. Feature extraction - v0.8.4

### `peak` / `extrema`

```ini
[operation.peak_x]
type=peak
x=wavenumber
y=absorbance
group=sample
mode=max
return=x
output=peak_position
```

`mode=max|min`; `return=x|y`.

Optional:

```ini
domain=some_mask
```

When `domain=` is present, only rows where the row-aligned logical mask is true participate in the feature calculation. The original dataset is not modified.

A tied extremum is reported as `ambiguous_extremum` rather than selecting one silently.

### `integrate` / `area`

```ini
[operation.band_area]
type=integrate
x=wavenumber
y=absorbance
group=sample
output=band_area
```

Uses trapezoidal integration and preserves supplied row order. Optional `domain=<mask>` restricts the points participating in the integral without destructively filtering the dataset. If an ascending X axis is scientifically required, prepare/order the source accordingly; the framework does not silently reorder curve traversal.

### `derivative` / `slope`

```ini
[operation.local_slope]
type=derivative
x=x
y=y
group=family
output=dydx
```

Produces a row-aligned numerical derivative independently per group. Optional `domain=<mask>` restricts the points used to compute the derivative; rows outside the domain are returned as `unavailable / outside_domain`.

### `window`

Create a reusable numeric domain mask:

```ini
[operation.band]
type=window
value=wavenumber
min=1300
max=1500
inclusive=1
output=band_domain
```

Bounds may instead be supplied as:

```text
min_series / max_series
min_parameter / max_parameter
```

Missing min/max means unbounded on that side.

## 14. Correlation, regression and fit - v0.8.4

### `correlate`

Pearson correlation:

```ini
[operation.r]
type=correlate
x=energy
y=ammonia
group=experiment
output=energy_ammonia_r
```

The result is a per-group feature and is dimensionless. Optional `domain=<mask>` restricts the observations participating in each correlation.

### `regress`

Linear least squares:

```ini
[operation.cal]
type=regress
x=band_area
y=concentration
group=batch
output=concentration_hat
```

Model:

```text
y = intercept + slope*x
```

Optional `domain=<mask>` restricts the observations used to estimate the regression. Predictions outside the domain are returned as `unavailable / outside_domain`.

Primary output is the row-aligned predicted series. Additional features are created automatically:

```text
<output>_slope
<output>_intercept
<output>_r2
```

### `fit`

`fit` bridges Scientific Analysis API v1 to the already-selected Mathematical Model Plugin resource in runtime `[model]`:

```ini
[operation.model_fit]
type=fit
x=x
y=y
family=family
max_iter=400
tolerance=1e-8
output=y_hat
```

It does **not** replace Mathematical Model Plugin API.

Current model function contracts accepted by the bridge are:

```octave
y = f(theta,x)
y = f(theta,x,family)
```

The runtime model section supplies `function`, `script`, `param_names`, `param_initial`, `param_lower`, and `param_upper`.

The operation produces predicted values plus features:

```text
<output>_<parameter-name>
<output>_rmse
<output>_mae
<output>_r2
```

The v0.8.4 generic fit bridge uses Octave `fminsearch` with bound transformation. Specialized optimizers remain separate future extensions.

## 15. Units and explicit conversion - v0.8.4

Explicit conversion:

```ini
[operation.current_A]
type=convert_unit
value=current_mA
to_unit=A
output=current_A
```

`from_unit=` may override input metadata.

For strict expression checking, see `UNIT_DIMENSION_API_v1.md`.

## 16. Exports

### Row-aligned CSV

```ini
[export.transformed]
type=csv
file=transformed.csv
columns=x;y;family;X0;DeltaX;domain
```

A non-primary-row-aligned series is rejected. Align/join/resample it first.

### Feature table

```ini
[export.features]
type=feature_table
file=features.csv
features=X0;band_area
```

The selected features must share one grouping. Output columns are:

```text
<group>,feature,feature_status,feature_reason,...
```

### Text summary

```ini
[export.summary]
type=text_summary
file=summary.txt
```

The summary reports series/status, features and available provenance entries.

## 17. Generic plots

```ini
[plots]
ids=normalized

[plot.normalized]
type=line
file=03_normalized.png
x=DeltaX
series=y
group=family
domain=negative_domain
title=Normalized family
x_label=Delta X
y_label=Y
```

Supported generic plot types:

```text
bar
line
scatter
```

For line/scatter, `group=` creates one graphical series per distinct group in stable first-occurrence order. `domain=` applies a row-preserving logical mask. X, Y, group and domain must be aligned to the primary row set.

Descriptor shorthand:

```text
group=<series>
domain=<logical-mask-series>
```

Generic analysis plots use shared GX-TXT graphics. Per-graph Axes/Grid overrides are applied centrally by `gxtxt_print_png_atomic()`/the framework finalizer. Modules must not add private Grid workarounds.

## 18. Features

A per-group feature object contains conceptually:

```text
group_values
group_kind
values
status
reason
broadcast
broadcast_status
broadcast_reason
group_id
output
operation_id
```

The compact values are for diagnostics/export. Broadcast series are for expressions/masks/plots.

## 19. Provenance

`align`, `join`, `resample`, and `interpolate` add provenance under:

```octave
result.context.provenance.<output>
```

The structure records operation kind, source/target IDs, method/policy and source row indices where available.

## 20. Render Cache integration

Scientific Analysis API results can be placed in a standard optional Render Cache API v1 envelope:

```octave
meta = gxtxt_render_cache_standard_meta(module_id,module_version,definition_path,sources,result.context.parameters);
cache = gxtxt_render_cache_from_analysis(result,meta);
gxtxt_render_cache_save(outdir,cache);
```

Legacy module-owned `render_cache.mat` layouts remain supported. See `RENDER_CACHE_API_v1.md`.

## 21. Uncertainty

Uncertainty inputs may be declared with `role=uncertainty` and are preserved when alignment permits. GX-TXT v0.8.4 deliberately does not invent general propagation formulas. See `UNCERTAINTY_POLICY_v1.md` and `TODO_v085.md`.

## 22. Internal operation registry

Plugin authors do not call the registry directly. The implementation uses:

```octave
gxtxt_analysis_operation_registry(...)
gxtxt_analysis_dispatch_kernel(...)
```

for operation discovery/kernel dispatch. This is an internal maintainability mechanism; the public descriptor syntax remains Scientific Analysis Definition API v1.

## 23. Backward compatibility

v0.8.4 is additive:

- Standard Module API remains v1;
- Scientific Analysis Definition API remains v1;
- Manifest Format remains 2;
- old definitions need no new keys;
- `filter` keeps historical destructive behavior;
- unit checking is opt-in;
- non-row-aligned sources require explicit alignment rather than new implicit behavior;
- existing module-owned render caches remain valid;
- shared graphics/legend/grid APIs remain authoritative.

## v0.8.5: source-qualified Standard Module bindings

When a Standard Module API v1 module uses Analysis Source Map API v1, runtime bindings may be source-qualified:

```ini
[bindings]
x=primary.Vg1_V
y=primary.Ig1_mA
family=primary.Ib_mA
sigma_y=uncertainty.sigma_total
```

A variable declared with `binding=` resolves both the source and column from the runtime binding. An unqualified binding remains backward-compatible and means `primary.<column>`.

Example:

```ini
[sources]
roles=primary;uncertainty

[variables]
ids=x;y;family;sigma_y

[variable.x]
binding=x
type=numeric

[variable.sigma_y]
binding=sigma_y
type=numeric
role=uncertainty
required=0
```

The framework helper:

```octave
sources = gxtxt_analysis_source_map_from_runtime(runtime_cfg);
```

constructs the `source_map` expected by `gxtxt_analysis_run()`. If `gxtxt_analysis_run()` receives an empty source map together with `options.runtime_cfg`, it derives the map through the same helper.

No implicit join/interpolation/resampling is performed. Source row relationships remain an explicit part of the Scientific Analysis Definition.

See `ANALYSIS_SOURCE_MAP_API_v1.md` for the complete module/runtime/manifest contract.

## v0.8.7 grouped plot empty-series semantics

For generic `line` and `scatter` plots, each grouped graphics primitive is created only after the renderer applies the group selection, optional `domain` mask, series validity/status, and finite X/Y filtering.

Rows whose relevant series status is `unavailable` or `failed` are not drawable. If one group has zero remaining points, the renderer skips that group. It does not create a graphics handle or legend label for it. Other groups remain valid and are rendered normally. If all groups are empty, the PNG is still produced and no legend is created.

This behavior is presentation-only and does not reinterpret `unavailable`, `failed`, feature status, or domain semantics.

---

# GX-TXT v0.9.1 plotting extensions

These are additive extensions of Scientific Analysis Definition API v1.

## Dual Y axes

A `line` or `scatter` plot may route each series to the left or right Y axis:

```ini
[plot.current_ph]
type=line
x=time
series=current;pH
series_axes=left;right
series_labels=Current;pH
y_label=Current
y2_label=pH
auto_units=1
```

If `series_axes=` is absent, every series remains on the historical left axis.

See `MULTI_Y_AXIS_PLOT_API_v1.md`.

## Unit-aware presentation

`auto_units=1` uses the unit metadata already attached to analysis series. Scaling affects only plotted values/labels, never `result.context.series`.

Source-variable metadata may be inherited automatically from the Dataset Registry through the v0.9.1 Analysis Source Metadata runtime extension when the Analysis Definition leaves `unit=`/`role=` blank.

## 3D line/scatter

```ini
[plot.xyz]
type=scatter3
x=current
y=pH
z=concentration
group=experiment
domain=valid
auto_units=1
z_label=Concentration
view_azimuth=-37.5
view_elevation=30
```

Supported types are `line3` and `scatter3`. See `PLOT_3D_API_v1.md`.
