# GX-TXT Dataset Selection API v1

**Introduced:** GX-TXT Pipeline v0.9.2  
**License:** GPL-3.0-or-later

## Purpose

A Dataset Selection is a reusable session resource describing a selected interval for one or more canonical dataset bindings **without copying, filtering or modifying dataset data**. It is built additively above Plot Region Selection API v1.

Selections are stored in `metadata/dataset_selections.ini` and receive stable IDs such as `sel_001`.
Read-only queries for any named Session are available through
`sessionInspectionSelectionIds ?session?` and
`sessionInspectionSelection selectionId ?session?`. These do not mutate the
current Selection registry.

## Resource model

```ini
[dataset_selection.sel_001]
api_version=1
id=sel_001
type=x_range
source_dataset_id=reactor.current.complete
source_role=primary
x_variable=time_s
x_unit=s
x_min=8280
x_max=16920
producer_module=plot.dataset_xy
producer_graph=plot.dataset.xy
```

For a rectangle, `y_variable`, `y_unit`, `y_min` and `y_max` are also present.

Supported v1 types:

- `x_range`
- `rectangle`

The ID identifies the selection resource. Re-selecting the same producer module/graph updates that resource instead of silently creating a new identity.

## Graph-provider descriptor mapping

A graph opts in through the existing Plot Region Selection API fields and may map axes to framework bindings:

```ini
[graph.plot.dataset.xy]
supports_region_selection=1
region_selection=x_range
region_source=primary
region_x_binding=x
```

For rectangles:

```ini
region_selection=rectangle
region_source=primary
region_x_binding=x
region_y_binding=y
```

The framework resolves the binding to the canonical Dataset ID and canonical variable. A provider may use `region_x_variable` / `region_y_variable` as an explicit fallback where a binding role is not available.

## Coordinate domains

For a selection with one source X binding, persisted x_min/x_max remain in that canonical source unit.

When enabled Graph Series use multiple X bindings, the selection is defined by the one shared displayed X interval. The resource sets x_coordinate_space=display and stores x_display_min, x_display_max, x_display_unit, x_binding_count, and x_bindings. Each x_bindings token is dataset_id:variable_id. The legacy singular source fields and canonical x_min/x_max retain the first displayed series projection for backward compatibility; consumers that support heterogeneous Graph Series use the display interval and complete binding list.

Example:

```text
dataset variable: time_s [s]
plot display:      h
user selection:    2 ... 4 h
selection stored:  7200 ... 14400 s
```

The plot geometry sidecar may publish:

```ini
x_source_variable=time_s
x_source_unit=s
x_display_unit=h
x_display_to_source_scale=3600
x_display_to_source_offset=0
```

and equivalent Y metadata. The inverse display-to-source conversion is framework-owned.

## Consumer descriptor field

A module can request a selection with a standard config field:

```ini
[config.selection]
type=selection
label=Data selection
required=0
source_role=primary
selection_types=x_range;rectangle
```

The GUI lists only resources compatible with the canonical dataset currently selected for the requested source role.

## Runtime transport

```ini
[dataset_selection_api]
api_version=1

[selection.selection]
api_version=1
id=sel_001
enabled=1
type=x_range
source_dataset_id=reactor.current.complete
source_role=primary
x_variable=time_s
x_unit=s
x_min=7200
x_max=14400
```

Rectangle selections additionally carry Y metadata.

Octave helpers:

```octave
S = gxtxt_selection_from_runtime(runtime_cfg, 'selection');
mask = gxtxt_selection_mask(S, x);
mask = gxtxt_selection_mask(S, x, y);  % rectangle
```

Coordinates passed to gxtxt_selection_mask use x_min/x_max and x_unit. For a heterogeneous Graph Series selection, consumers that operate on the shared axis use x_display_min/x_display_max and x_display_unit together with x_bindings.

## Non-goals of v1

The framework does **not**:

- create a CSV or derived dataset automatically;
- modify the source Dataset Registry entry;
- filter the original dataset;
- rerun analysis automatically after selection changes;
- provide multiple simultaneous regions, lasso/polygon or 3D selections.

A future generic `dataset.subset` module may materialize `dataset + selection -> new dataset`. FFT, fitting and statistics modules may consume the same selection directly.

## Compatibility

`[module_plot_region.<module>.<graph>]` remains valid and is still delivered to the producer plugin. Existing v0.9.1 plugins require no changes. Dataset Selection API v1 is an additional reusable-resource layer.

## GX-TXT 0.9.7.11 variant producer and variable IDs

New Selection records add optional producer_variant and x_variable_id/y_variable_id. The producer identity is producer_module + producer_graph + producer_variant; missing/empty variant means the legacy base graph. Re-selecting p0001 updates p0001's resource and cannot overwrite p0002's. Deleting a plot variant does not implicitly delete its independent Selection resource.

Single-binding selections keep canonical coordinate bounds and persist both stable variable IDs and current names. Consumers should prefer source_dataset_id + variable_id; names remain for older plugins and records. The public gxtxt_selection_from_runtime helper exposes the IDs and producer fields when present and still accepts old name-only sections. x_range needs X; rectangle needs X/Y and still maps Y only to the primary/left axis. No source dataset is copied.


## Graph Series resolution since 0.9.7.13

For both base graphs and variants, enabled Graph Series are the authoritative
source of selection coordinates. Disabled series are ignored. An X-range
uses the shared displayed X interval and records every distinct
dataset_id + x_variable_id binding. A single-binding selection retains the
canonical source-coordinate representation used by earlier releases.
For rectangles, Y is resolved from enabled left-axis series only when they
share one dataset_id + y_variable_id; rectangle X and Y still require one
canonical dataset. An ambiguous rectangle Y or missing left series raises an
explicit error. If no series is active, base graphs use their legacy module
bindings and variants use their stable-ID X/Y bindings. The saved resource
includes dataset-scoped variable IDs and, for a variant, producer_variant.

## Calibrated graphical selection and editing (GX-TXT 0.9.7.19)

The graphical tool maps Tk canvas coordinates through the displayed PNG
rectangle and the **measured inner data frame** of the exported PNG.
The frame is recorded in the ordinary plot geometry sidecar as
`axis.1.pixel_rect` plus the original image width and height.
This accounts for PNG resizing and renderer layout margins. The
in-memory GNUplot `axes.Position` alone is not an accurate raster
coordinate transform. A PNG from an older release without calibration
must be rerendered before making a new graphical selection.

Choose **Select area**, then drag anywhere inside the data frame to
create an X range or rectangle. A click at its visible border is accepted
within half a displayed pixel, accounting only for integer mouse event
rounding. To edit the existing selection, drag either X-range boundary or
its interior; for rectangles, drag an edge, corner, or interior. Motion
changes only the temporary overlay. Release validates and commits the
new bounds in the selection's declared coordinate domain to the same Dataset Selection registry resource.

A geometry edit retains selection_id, type, the singular source identity,
the complete x_bindings set, and y_variable_id where applicable. A changed
binding set is a different source identity and creates a new selection instead
of retargeting the previous one. Base graphs and
variants retain separate producer identities. The selected resource
survives session save and reopen, and ordinary `type=selection`
consumers receive the updated bounds on their next runtime generation.
## Temporal Set parenting since GX-TXT 0.9.7.58

[Temporal Set API v1](TEMPORAL_SET_API_v1.md) may use an existing `x_range` Dataset Selection as an optional parent interval. The Selection resource and its v1 semantics are unchanged: Temporal Set CORE validates that the parent refers to the same Dataset and temporal variable, maps the Selection to an effective source row range, and resolves all segment/window members inside that range. The source Dataset is not copied or concatenated.

## Additive multi-source members (dev-052)

`datasetSelectionCreateMembers session members ?producer?` saves a reusable
`type=members` resource. Each ordered member carries its own `member_id`, exact
`dataset_id`, X/Y Variable IDs, zero-based `rows`, `row_operation=keep|exclude`,
and optional independent Graph Series `row_filters`. Two series from the same
Dataset remain separate members. Empty row sets retain their meaning: keep
selects none; exclude retains every row passing that member's series filters.
The resource is metadata and creates no Dataset or hidden publication.

`datasetSelectionMembers session selection_id ?keep|exclude?` returns sources
for the common Dataset Transform authority. Legacy canonical X intervals and
rectangles become `selection_filters`; exclusion complements that selection
predicate, preserving independent series filters. Legacy display-domain bounds
require explicit per-source canonical bindings rather than guessing units.

A standard `type=selection` field opts in with `multiple_sources=1` and
`selection_types=x_range;rectangle;members`. Without this flag, the existing
single-source compatibility behavior applies. Dataset Extract opts in; unrelated
analysis modules retain their scalar Selection controls.

Graphs → Select data → **Save Selection** persists the chosen members for
Dataset Extract. **Create Dataset** remains an explicit, distinct publication.
Both point and area workflows preserve source row and member lineage.
The INI registry and Session manifest carry the complete member list, including
save/reopen. Producer fields are limited to module/graph/variant identity.

Python and Octave Script Bridge operations: `list`/`ids`, `describe`/`get`,
`create_members(members, producer)`, and `members(selection_id, operation)`.
Existing `list` and `describe` names remain available. Results contain logical
IDs, row ordinals and safe predicates, never canonical payload paths.
