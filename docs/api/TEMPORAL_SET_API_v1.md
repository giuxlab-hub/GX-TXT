# GX-TXT Temporal Set API v1

**Introduced:** GX-TXT Pipeline v0.9.7.58  
**License:** GPL-3.0-or-later

## Purpose and terminology

Temporal Set API v1 is the public, persistent, runtime-independent CORE facility for reusable temporal portions of canonical time-series Datasets. It deliberately avoids the word **chunk**, which already has Table Stream and storage meanings.

The API has two resource types:

- **Temporal Segment Set** (`segment_set`): an ordered collection of arbitrary, possibly non-contiguous user-authored intervals with stable segment IDs and optional labels.
- **Temporal Window Set** (`window_set`): a compact regular generator definition using sample counts or durations. Generated members are derived state and are not persisted one-by-one.

Both are views over source data. Creating or resolving a Temporal Set does not create a Dataset, copy/concatenate samples, write per-window files, or modify source values.

## Resource identity and persistence

Temporal Sets use stable IDs such as `tset_001`. Segment members use stable IDs such as `seg_001`. Definitions are stored in the session resource registry:

```text
metadata/temporal_sets.ini
```

This file is CORE-owned persistent state. Analysis modules do not open it. Regular member IDs such as `win_000001` are deterministic derived identities reconstructed from the generator and current authoritative source state.

The persistence invariant is:

```text
authoritative Temporal Set definition
        ↓
validation + range resolution
        ↓
derived runtime representation
```

Deleting or rebuilding runtime never deletes Temporal Set definitions. `temporalSetDelete` is the explicit operation that deletes a Temporal Set resource.

## Common associations

Every Temporal Set identifies:

```text
source_dataset_id
 temporal_variable_id
```

The temporal variable is a stable Dataset Variable Schema v3 variable ID. It must be one-dimensional, numeric/elapsed-time capable, and have a temporal unit compatible with seconds.

A Temporal Set may also specify:

```text
parent_selection_id
```

The parent must be an existing Dataset Selection API v1 `x_range` over the same Dataset and temporal variable in canonical source coordinates. The Selection restricts the effective row interval; it does not become a copied subset.

## Boundary contract

Temporal Set intervals use:

```text
start_inclusive_end_exclusive
```

That is, `[start,end)`. Source ranges use zero-based `row_start` plus `row_count`, matching Canonical Dataset API v2 bounded range reads.

Dataset Selection API v1 itself is unchanged. Its existing `x_range` upper bound remains inclusive when CORE maps the Selection into the effective parent row range. Temporal members are then generated/resolved within that row range.

## Arbitrary Temporal Segment Sets

Create:

```tcl
set setId [::GX::temporalSetCreate [dict create \
    type segment_set \
    source_dataset_id reactor.run \
    temporal_variable_id time \
    label {Experiment phases} \
    segments [list \
        [dict create label {warm-up} start 0 end 20] \
        [dict create label {stable region} start 35 end 80] \
        [dict create label {reaction phase 1} start 120 end 145]]]]
```

The start/end values use the Temporal Set's canonical numeric temporal unit. The returned definition exposes the generated stable member IDs. When editing or reordering existing segments, pass those IDs back to `temporalSetUpdate` to preserve member identity.

Read/update/enumerate/delete:

```tcl
set definition [::GX::temporalSetRead $setId]
set all [::GX::temporalSetList]
set forDataset [::GX::temporalSetList reactor.run]
::GX::temporalSetUpdate $setId [dict create label {Reviewed phases} segments $segments]
::GX::temporalSetDelete $setId
```

Separated intervals stay separate. CORE does not concatenate them or create a materialized Dataset.

## Regular Temporal Window Sets

### Sample-based

```tcl
set setId [::GX::temporalSetCreate [dict create \
    type window_set \
    source_dataset_id audio.run \
    temporal_variable_id time \
    generator_basis samples \
    window_size 4096 \
    step 2048 \
    partial_policy drop]]
```

`window_size` and `step` are positive integer row/sample counts. `step < window_size` overlaps; equality produces adjacent windows; `step > window_size` leaves gaps.

### Duration-based

For a canonical **uniform** temporal axis:

```tcl
set setId [::GX::temporalSetCreate [dict create \
    type window_set \
    source_dataset_id experiment.run \
    temporal_variable_id time \
    generator_basis duration \
    window_size 10 \
    step 5 \
    duration_unit s \
    partial_policy drop]]
```

`duration_unit` may be omitted; it then defaults to the temporal variable's current numeric unit. For `value_kind=elapsed_time` / `value_format=hms`, that numeric unit is the public elapsed-time base unit `s`, as defined by [Elapsed Time Contract v1](ELAPSED_TIME_CONTRACT_v1.md). Conversion uses the existing GX-TXT Unit/Dimension infrastructure. [Elapsed Time Requested-Unit API v1](ELAPSED_TIME_REQUESTED_UNIT_API_v1.md) is a separate consumer-view API and does not change Temporal Set persistence or internal window resolution.

A duration window and step must map to exact positive integral sample counts on the uniform axis. The API reports an explicit diagnostic instead of silently rounding a non-integral mapping.

## Final-window policy

The conservative default is:

```text
partial_policy=drop
```

A final member that would extend beyond the effective parent interval is omitted.

A caller may explicitly request:

```text
partial_policy=include
```

In that case the final member is truncated deterministically to the remaining rows. Partial windows are therefore never created silently.

## Resolution and iteration

Resolution validates the current Dataset, temporal variable and parent Selection every time derived state is built.

```tcl
set info [::GX::temporalSetResolveInfo $setId]
set member [::GX::temporalSetResolveMember $setId 1]
set complete [::GX::temporalSetResolve $setId]
::GX::temporalSetIterate $setId myConsumerCallback
```

A resolved member provides, where meaningful:

```text
index
member_id
label
requested_time_start
requested_time_end
time_start
time_end
row_start
row_count
```

`row_start` is zero-based. Segment IDs are persistent. Regular-window IDs are deterministic (`win_000001`, `win_000002`, ...).

`temporalSetResolveInfo` is preferable when a consumer only needs generator/range metadata. `temporalSetResolve` intentionally materializes the member list in memory and should not be used for enormous generated window counts. `temporalSetIterate` resolves the definition once and yields members one at a time.

## Large-data behavior

Uniform temporal axes are resolved using Dataset Variable Schema metadata:

```text
axis_origin
axis_step
axis_count
```

No Dataset payload read is required merely to define or resolve regular windows on such axes.

For an explicit temporal coordinate, arbitrary time boundaries are mapped by bounded Canonical Dataset API v2 range reads of **only the temporal variable**, in finite chunks. CORE does not load/copy the complete multi-variable Dataset merely to resolve a Temporal Set.

## Parent Dataset Selection

Example:

```text
Dataset
  ↓
Dataset Selection x_range: 20 s ... 200 s
  ↓
Temporal Window Set: size 10 s, step 5 s
```

The effective parent row range is first derived from the Selection. Every generated member is then constrained to that range. Consumers do not need to know whether the parent Selection was created graphically or programmatically.

## Stale-reference behavior

A Temporal Set is not allowed to look valid while silently losing inputs.

Resolution reports an explicit error when any authoritative reference is missing or incompatible, including:

- source Dataset;
- temporal variable;
- parent Dataset Selection;
- wrong parent Dataset/variable;
- unsupported axis/unit;
- invalid generator values.

Dataset deletion is prevented while a Temporal Set still references that Dataset. If another resource is removed by a path that CORE cannot prevent, the next Temporal Set resolution fails explicitly and identifies the broken reference.

## Descriptor integration

A Standard Module may select a Temporal Set with a normal descriptor field:

```ini
[config.windows]
type=temporal_set
label=Windows
required=1
source_role=primary
temporal_types=window_set
```

`temporal_types` may contain `segment_set`, `window_set`, or both. The standard selector filters resources by the Dataset currently assigned to the requested Analysis Source role.

This GUI binding is optional. The semantic Temporal Set API is usable from headless Tcl and does not require Tk.

## `standard_octave` runtime transport

Runtime generation validates and resolves the selected resource and adds:

```ini
[temporal_set_api]
api_version=1

[temporal_set.windows]
api_version=1
id=tset_006
enabled=1
type=window_set
source_dataset_id=temporal.series
temporal_variable_id=time
temporal_unit=s
parent_selection_id=sel_001
boundary_policy=start_inclusive_end_exclusive
effective_row_start=20
effective_row_count=181
member_count=35
generator_basis=duration
window_size=10
step=5
duration_unit=s
partial_policy=drop
resolved_window_rows=10
resolved_step_rows=5
```

Regular windows remain compact in runtime; thousands or millions of member sections are not emitted.

Segment Sets additionally contain one section per persistent segment because those members are authoritative user-created definitions:

```ini
[temporal_set.segments.member.1]
index=1
member_id=seg_001
label=warm-up
requested_time_start=0
requested_time_end=20
time_start=0
time_end=20
row_start=0
row_count=20
```

No private Dataset or Temporal Set metadata path is part of the public Octave API.

## Public Octave helpers

```octave
S = gxtxt_temporal_set_from_runtime(runtime_cfg, 'windows');
M = gxtxt_temporal_set_member(S, 1);
```

`gxtxt_temporal_set_from_runtime` reconstructs the public Temporal Set runtime representation. For a Segment Set, `S.members` contains its resolved persistent members. For a Window Set, `S` keeps the compact generator and resolved row parameters.

`gxtxt_temporal_set_member` resolves one 1-based member. Returned `row_start` remains zero-based so it can feed the framework range-read APIs without an implicit indexing conversion.

## Compatibility and non-goals

Temporal Set API v1 is additive. It does not alter:

- Dataset Selection API v1 (`x_range` / `rectangle`);
- Canonical Dataset API;
- Analysis Source APIs;
- Table Stream chunk semantics;
- Dataset Metadata runtime transport;
- existing `standard_octave` modules;
- `analysis.fft_spectrum`;
- `analysis.spectrogram`;
- `plot.dataset`;
- scientific Dataset values.

Temporal Set API v1 was introduced as shared infrastructure in GX-TXT 0.9.7.58. Consumer adoption and the Variables-workspace editor are additive; the editor is available from GX-TXT 0.9.7.75 and does not change the resource model.

## Variables-workspace editor (GX-TXT 0.9.7.75)

GX-TXT 0.9.7.75 exposes Temporal Set API v1 through a Dataset-scoped stacked editor in **Variables → Temporal Sets...**. The Dataset selector remains visible and authoritative. The editor supports creation, editing and deletion of `window_set` and `segment_set` resources using the same public API and the same `metadata/temporal_sets.ini` persistence used by headless callers.

The GUI deliberately distinguishes semantic meaning from representation. Eligibility is based on the explicit Variable Schema temporal semantic contract, not on a column name, a time-looking unit, or `value_kind` alone. In particular, an explicitly declared `semantic_role=elapsed_time` may use either an ordinary numeric representation (`value_kind=number`) or the elapsed-time-specific representation (`value_kind=elapsed_time`). A numeric variable named `time`, or one whose unit is `s`, is not automatically promoted to elapsed-time semantics.

Duration controls enumerate registered units through Unit Registry API v1 and validate them through Elapsed Time Requested-Unit API v1. Display/requested units therefore remain separate from source representation and from the canonical elapsed-time value. Changing `500 ms` to display as `0.5 s` does not change the physical Temporal Set definition and does not rewrite Dataset Variable Schema.

`Parent Selection = All dataset` is represented by an empty `parent_selection_id`; it never creates a synthetic Dataset Selection. Existing compatible `x_range` Selections are listed by stable Selection ID.

The list panel uses `temporalSetResolveInfo` for its resolution summary rather than duplicating window-generation logic. Live standard-module `type=temporal_set` selectors are refreshed after create/update/delete operations.

See [Temporal Set Editor](../guides/TEMPORAL_SET_EDITOR.md) for the user workflow, duration-unit behavior and practical examples.

### Selector fallback correction (GX-TXT 0.9.7.76)

The generic `type=temporal_set` standard configuration widget treats an unset display value and the explicit `None` choice as an empty module binding. The fallback is handled with normal Tcl control flow rather than expression barewords, so modules can open and change an unbound Temporal Set selector safely. Stable Temporal Set IDs remain the persisted module value.

## Script Bridge operations (GX-TXT dev-037)

These calls use the Session-owned persistent Temporal Set registry. `create` accepts the same definition dictionary as `temporalSetCreate`; `update` accepts its public changes dictionary and preserves member IDs when supplied. `resolve_info`, `resolve_member`, and `resolve` return nested dictionaries and member lists with numeric row identities; `resolve_member` uses a one-based member index; `list` defaults to all Sets when `dataset_id` is omitted. A Set created by one script is visible to other scripts and modules. Both Octave/MATLAB and Python call these names through `gxtxt_api_call(API_ID, operation, arguments)`. Arguments are positional and are passed to the named public Tcl procedure.

| Script operation | Public Tcl mapping | Positional arguments | Result |
| --- | --- | --- | --- |
| `create` | `::GX::temporalSetCreate` | `definition` | Set ID |
| `list` | `::GX::temporalSetList` | `dataset_id` (optional) | cell of Set descriptors |
| `read` | `::GX::temporalSetRead` | `set_id` | Set struct |
| `resolve_info` | `::GX::temporalSetResolveInfo` | `set_id` | resolution struct |
| `resolve_member` | `::GX::temporalSetResolveMember` | `set_id`, `index` | member struct |
| `update` | `::GX::temporalSetUpdate` | `set_id`, `changes` | Set struct |
| `delete` | `::GX::temporalSetDelete` | `set_id` | Set ID |
| `resolve` | `::GX::temporalSetResolve` | `set_id` | resolution struct |

`temporalSetIterate` executes a Tcl callback and remains host-only. `create`, `update`, and `delete` persist the Temporal Set registry; they do not create or modify a Dataset. Nested Tcl dictionaries and lists are converted recursively for script clients.
