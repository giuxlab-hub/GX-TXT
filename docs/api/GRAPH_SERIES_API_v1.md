# Graph Series API v1

SPDX-License-Identifier: GPL-3.0-or-later

The dev096 candidate adds optional `source_row_ordinals`: a sorted set of at
most 200000 distinct exact nonnegative row integers through 2^53−1. Empty means
unrestricted. This field persists with a series and restricts its prepared
display after normal CORE row filters. It never derives scientific rows from
a display proxy. `graphSeriesExpandGroups` accepts `dry_run=1` and the same
exact row restriction to return validated observed tuple plans without creating
series or touching a manifest. Its optional ninth host argument is a cooperative
progress callback; the existing eight-argument Script Bridge exposes data only.

Introduced in GX-TXT 0.9.7.8. This is an additive Graph Provider binding
contract for independent series from different canonical datasets. It does
not change Graph Provider IDs or run scientific analysis.

## Public Tcl API

```tcl
::GX::graphSeriesSet module_id graph_id series_id [dict create \
    dataset_id d2 x_variable_id v0001 y_variable_id v0002 \
    axis right label "pH" enabled 1 alignment_mode none]
::GX::graphSeriesList module_id graph_id
::GX::graphSeriesResolve module_id graph_id series_id
::GX::graphSeriesRemove module_id graph_id series_id
```

Each series binds one dataset and two stable, dataset-scoped variable IDs.
`axis` is `left` or `right`. Missing or unknown IDs fail. Enabled
series cannot use an excluded Use=no variable; disabled series preserve its ID. Names are resolved at use time, so renames do not change
bindings. Module/Graph IDs remain descriptor-declared Graph Provider IDs.
Manifest Format 2 stores numbered `[graph_series.N]` sections and a
`[graph_series_api]` count/version section. A configuration-only manifest
can load before the session; IDs resolve when dataset metadata is available.

Standard module runtime includes `[graph_series]` and numbered
`[graph_series.N]` sections with dataset ID, canonical path, variable
IDs, current names, X/Y units, axis, label and temporal metadata.

## Octave consumer

```octave
series = gxtxt_graph_series_load(runtime_cfg,graph_id,chunk_rows)
```

The CORE helper uses Table Stream API v2 for each source independently,
selecting by stable variable ID. Each result has its own `x` and `y`
vectors, source units, dataset ID, axis and temporal metadata. Dataset
lengths and sample grids may differ. No interpolation, resampling,
index-based joining or implicit time alignment occurs. A provider can
convert a series' X unit explicitly with `gxtxt_unit_convert`, then
draw its original points on the shared axis.

CORE exposes the contract to consumers. Scientific validation and the
base-graph series preparation path in `plot.dataset` are separate plugin work.

## Temporal readiness

X-variable schema provides `value_kind`, `value_format`,
`time_reference`, `time_origin`, and unit. A graph series additionally
persists `alignment_mode=none|common_elapsed_zero|absolute_origin|manual_offset`
and `manual_offset_seconds` (default zero). These fields declare a
future explicit alignment choice. The loader reports them without
applying a shift. Different time units are converted by the existing
Unit API when requested. This keeps original points intact.

## GX-TXT 0.9.7.11 optional variant argument

The final variant_id argument is optional in graphSeriesSet, graphSeriesRemove, graphSeriesIds, graphSeriesResolve and graphSeriesList. Empty/omitted means the original base graph. A nonempty ID must name an existing Plot Module variant of the declared graph; one series ID may occur in different variants without collision. Manifest and runtime add optional variant_id to each graph_series.N section. Older records load as base series.

~~~tcl
::GX::graphSeriesSet plot.dataset plot.dataset.xy s001 [dict create \
    dataset_id d3 x_variable_id v0001 y_variable_id v0009 axis right] p0002
::GX::graphSeriesList plot.dataset plot.dataset.xy p0002
~~~

The Octave helper accepts gxtxt_graph_series_load(runtime_cfg, graph_id, chunk_rows, variant_id). The fourth argument defaults to empty for the base. plot.dataset now consumes this public helper for opted-in 2D variants, including series from different datasets. Original points are not interpolated, resampled or joined.

For base calls, setting an excluded Use=no variable retains the historical rejection. For a variant, the stable ID binding can be saved while Use=no; resolving/rendering reports that it is unavailable. Re-enabling recoverable data makes the same ID usable again. No binding is changed into a name binding.

## GX-TXT 0.9.7.13: enabled state, order and shared editor

`enabled=1` is the default for old manifests and for a new series. `enabled=0`
retains dataset/variable IDs, axis, label and alignment configuration in the
manifest and runtime. `graphSeriesList` returns active series by default;
pass `includeDisabled=1` as its fourth argument to inspect all configured
series. The Octave loader omits disabled rows without opening their data.
Re-enabling uses the same IDs. `graphSeriesMove module graph series_id
-1|1 ?variant_id?` changes persistent `order` without changing IDs.
Unordered legacy entries keep deterministic ID ordering.

The CORE Graphs configuration shows **Series...** for graphs declaring
`series_editor=standard`; existing graphs with `supports_variants=1` also
expose it without changing their descriptors. The same `graphSeriesEditorBuild` implementation
edits the base graph (`variant_id=""`) and each variant. It exposes Enabled,
Dataset, X/Y variable IDs, Axis and Label, plus add/update, remove and
Up/Down controls. Variants remain isolated; duplication copies their series.

Resolved series/runtime entries include for each X and Y:
`variable_id`, current `name`, `unit`, `semantic_role`,
`value_kind`, `value_format`, `decimal_separator`,
`time_reference` and `time_origin`. The values come from the Dataset
Variable Schema at resolution time. The Octave helper returns them on each
active series, including the existing temporal alignment intent. It does
not infer scientific compatibility or apply alignment. Renaming a variable
changes the resolved name while its dataset-scoped ID remains stable.

## GX-TXT 0.9.7.21: read-only snapshot and editor extensions

`graphSeriesSnapshot module graph series_id ?variant_id?` returns the persistent
generic Graph Series fields plus stable module, graph, variant and series
identity without exposing CORE storage or resolving provider-specific state.

A graph provider can extend the standard Series editor through
[Series Editor Extension API v1](SERIES_EDITOR_EXTENSION_API_v1.md). The
extension receives this generic snapshot but stores all provider-specific
properties independently. Graph Series API v1 has no new provider fields and
remains authoritative for its existing generic fields.

## GX-TXT 0.9.8.06: source row filters and family expansion

`row_filters` is an optional list of dictionaries on a Graph Series. Each
filter binds a stable `filter_variable_id` in the same Dataset and has one
`predicate`. Filters combine with AND semantics. The supported predicates
are `exact_equal`, `not_equal`, `less_than`, `less_equal`, `greater_than`,
`greater_equal`, `between_inclusive`, `in_set`, `is_finite`, and
`is_nonfinite`. Ordered and finite predicates require numeric variables.
`in_set` accepts `values` as a Tcl list; `between_inclusive` accepts `lower`
and `upper`; the other comparison predicates accept `value`. Exact source
values are stored separately from labels and display formats.

```tcl
set member [dict create filter_variable_id v0003 predicate exact_equal value 7]
set quality [dict create filter_variable_id v0004 \
    predicate between_inclusive lower 0.4 upper 0.9]
::GX::graphSeriesSet plot.dataset plot.dataset.xy sample [dict create \
    dataset_id family x_variable_id v0001 y_variable_id v0002 \
    axis left label "Sample 7" row_filters [list $member $quality]]
```

The filters persist in the Session manifest, copy with Plot Variants, and
are applied by Table Stream based rendering and rerendering. A missing filter
variable or changed dtype produces an explicit stale binding error. The
standard Series editor displays the filter count and exposes the public Tcl
list in its **Row filters** field.

`graphSeriesExpandGroups module graph dataset x_variable y_variable
group_variable ?options? ?variant_id?` scans the Dataset in bounded chunks
and creates one ordinary exact-value filtered Graph Series per member. It
uses source encounter order by default. Options are `chunk_rows` (default
4096), `max_members` (1000), `series_prefix` (`family`), `label_template`
(`{member}`), `label_variable_id`, and explicit `member_order`. Labels may
contain `{member}` and `{label}` placeholders. `member_order` must name every
encountered member exactly once. The helper returns a list of dictionaries
with `series_id`, `member_value`, and `label`.

```tcl
set series [::GX::graphSeriesExpandGroups plot.dataset plot.dataset.xy \
    family v0001 v0002 v0003 \
    [dict create series_prefix spectrum label_template {Spectrum {member}}]]
```

For a normal family of pure X/Y Series with one distinct exact member
filter each, `plot.dataset` prepares all members in two bounded Dataset
passes. Other presentation modes keep the general per-Series path. An
explicit `none` reduction can retain the full selected data in memory;
`auto`, `minmax`, and `stride` provide bounded display reduction. No member
CSV files are created.

## Script Bridge operations (GX-TXT dev-037)

Graph Series bindings use stable module/graph/Variant and Series IDs. `variant_id` is optional and defaults to the base graph; `list` also accepts optional `include_disabled`, default `0` (active Series only). `expand_groups` defaults `options` to an empty dictionary. Mutations persist in the Session Manifest. Resolved results from `set`, `list`, `resolve`, and `snapshot` omit the private canonical Dataset `path`; the Dataset identity and public variable IDs remain. `expand_groups` creates ordinary persistent Series using the public grouped-Series API. Both Octave/MATLAB and Python call these names through `gxtxt_api_call(API_ID, operation, arguments)`. Arguments are positional and are passed to the named public Tcl procedure.

| Script operation | Public Tcl mapping | Positional arguments | Result |
| --- | --- | --- | --- |
| `set` | `::GX::graphSeriesSet` | `module_id`, `graph_id`, `series_id`, `fields`, `variant_id` (optional) | series struct |
| `list` | `::GX::graphSeriesList` | `module_id`, `graph_id`, `variant_id` (optional), `include_disabled` (optional) | cell of series structs |
| `resolve` | `::GX::graphSeriesResolve` | `module_id`, `graph_id`, `series_id`, `variant_id` (optional) | series struct |
| `remove` | `::GX::graphSeriesRemove` | `module_id`, `graph_id`, `series_id`, `variant_id` (optional) | empty |
| `ids` | `::GX::graphSeriesIds` | `module_id`, `graph_id`, `variant_id` (optional) | cell of IDs |
| `move` | `::GX::graphSeriesMove` | `module_id`, `graph_id`, `series_id`, `delta`, `variant_id` (optional) | cell of IDs |
| `snapshot` | `::GX::graphSeriesSnapshot` | `module_id`, `graph_id`, `series_id`, `variant_id` (optional) | series struct |
| `expand_groups` | `::GX::graphSeriesExpandGroups` | `module_id`, `graph_id`, `dataset_id`, `x_variable_id`, `y_variable_id`, `group_variable_id`, `options` (optional), `variant_id` (optional) | cell of member structs |

`set` accepts public Graph Series fields; `move` accepts `-1` or `1`; `remove` returns an empty string. The Series editor remains a host GUI action. Nested Tcl dictionaries and lists are converted recursively for script clients.

## Unbound preparation (dev077)

A disabled series with an empty Dataset ID is reusable preparation, retained through
pruning, save and reopen. Resolve/list-with-disabled returns a descriptor with empty
scientific paths/units and `available=0, binding_status=unbound`. Normal runtime lists
exclude it. Existing Set can bind it to a newly acquired Dataset; nonempty stale
Dataset/Variable IDs retain their established rejection/pruning behavior.
