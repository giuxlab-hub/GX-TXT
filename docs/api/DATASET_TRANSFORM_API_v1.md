# Dataset Transform API v1 and Manifest v1

`concat_rows` also accepts an owned `native_geometry` source: `xy_resource`
(`native2d.float64_xy_le_v1`), `x_variable`/`y_variable` descriptors, optional
`row_resource` (uint64 source-row ordinals; maximum uint64 means no source row),
and optional byte `gap_resource`. Caller filesystem paths are forbidden. CORE
validates ownership/hash/shape/lifetime, stages bounded resource chunks and uses
its existing disk-backed complete-tuple worker and Dataset publication APIs.

A geometry source bound to a real Dataset retrieves the complete immutable
source tuple for each row ordinal and replaces only XY with accepted geometry
coordinates. Unbound Native samples inherit the compatible Dataset schema when
mixed, without inventing a source Dataset ID. Mixed XY requires explicit
float64/equal units; incompatible complete schemas reject. Generated
`<lineage_prefix>auxiliary_valid` marks whether non-XY source values exist.
When0, zero/empty placeholders are explicitly absent values, never scientific
observations. Integer dtype/precision and text descriptors remain intact.
`<lineage_prefix>break_before` retains gaps/member boundaries, including reversed
direction. Geometry remains local until explicit publication; no technical
temporary Dataset is registered.

Owner: CORE. API ID `DATASET_TRANSFORM_API_v1`, provider `dataset_transform`.
Tcl commands are available after framework initialization; Python and
Octave/MATLAB use the same Script Bridge registration and scientific authority.
Callers supply Dataset/Variable IDs and dictionaries, never canonical file paths.

The common request, `DATASET_TRANSFORM_MANIFEST_v1`, is:

```json
{
  "api_version": 1,
  "operation": "project_variables",
  "sources": [{"dataset_id": "measurements", "variable_ids": ["x", "signal"]}],
  "output": {"dataset_id": "projected_measurements", "contract": "auto", "storage": "auto"},
  "options": {},
  "schema_policy": {},
  "metadata_policy": "inherit_single_source"
}
```

Output IDs are exact validated public IDs; collisions reject create-only
publication. Views may omit the output ID. An explicit `display_name` is separate
from the ID. `storage` accepts auto/csv/hdf5; auto uses the shared size-aware
publication policy. There is no caller-controlled destination path or overwrite.
`schema_policy` supports `dtype_policy=strict`, `unit_policy=explicit` defaults.

Sources may specify ordered `variable_ids`, `member_id`, `variable_map` mapping
source to output IDs, `start/count`, zero-based `rows` with `row_operation=keep`
or `exclude`, safe `row_filters`, explicit `convert_units`, or a compatible
Dataset `selection_id`. `selection_filters` carry a canonical interval/rectangle
separately from ordinary series filters; `selection_operation=exclude` complements
only that selection predicate. Curve sources specify `x_variable_id/y_variable_id`.
Family sources also specify `family_coordinates`. Source/member order is the
request order; ordinary row order is source order. Interpolation is never implicit.

Per-source `assume_units` maps undeclared numeric Variable IDs to explicitly
chosen input units. It cannot override a known unit or hide variable-specific
calibration. Combine it with `convert_units` to normalize otherwise undeclared
coordinates without editing the source Dataset schema. The effective report
contains `unit_assumptions` with source/member/variable identity, the assumed
unit, empty original unit and `source_schema_mutated=false`. Both Script Bridge
languages return these descriptors as typed nested records. Assumptions and
conversion definitions persist in the normal Transform provenance.

Per-source `order_variable_ids` explicitly sorts complete tuples by the supplied
keys, with stable original-row ties. Per-source boolean `reverse` reverses the
resulting complete order, including equal-key tie order. This composes ordering
and intended direction during concatenation/publication without GUI-side tuple
sorting or an intermediate Dataset. Numeric keys must be finite/non-null; uint64
keys retain exact integer precision. Ordered preprocessing with `reverse_range`
is rejected; express that as separate explicit transformations. Provenance stores
both per-source preprocessing choices.

| Operation | Options and semantics |
| --- | --- |
| project_variables | Ordered source or `options.variable_ids`; `rename` and `display_labels` dictionaries; preserve complete selected values and schema semantics. |
| subset_rows | Source start/count, explicit rows keep/exclude, Selection bounds or safe predicates. Filters use `filter_variable_id`, `predicate` and value/lower/upper/values; numeric inequalities, exact text matching, contains, finite/nonfinite and in-set are supported. |
| combine_selection | Shared Graph Selection/Extract operation. Compatible schemas use complete-row concat plus member/Dataset/SHA/source-row lineage; heterogeneous schemas use a long curve bundle. Compatibility conflicts and effective operation are recorded. |
| concat_rows | Ordered sources; ordered IDs, dtype, units, semantic roles, value kinds and dimensions must agree. Contracts must agree unless output explicitly requests `table.generic`. Conversion requires an explicit source `convert_units` map. |
| merge_columns | `mode=row_index` requires equal row counts; Variable ID collisions require explicit maps. `mode=exact_key` uses paired `keys` and requires complete equal unique key sets. |
| join_by_key | `keys` is a list of left/right source Variable ID pairs. `join=inner` or `left`; `duplicate_policy=error` by default, or explicit `all`. No fuzzy matching. Missing right-side numeric values use NaN, text uses empty string. Integer values requiring more than exact float64 precision reject left-join NaN promotion. |
| rename_reorder | `rename`, `display_labels`, and `reorder` (every output ID exactly once). Creates a derived Dataset; source schema is unchanged. |
| curve_bundle | `representation=wide` uses one X and one Y per member; equal point count, units and X values are required, with optional explicit nonnegative `x_tolerance`. `long/family` retains unequal grids/counts and explicit member, source Dataset/hash, source-row ordinal, source variable IDs and per-member units. |
| build_family | Long curve family with one or two explicit `family_axes`; source `family_coordinates`, optional `family_units`, ordered members. Duplicate combinations and incomplete rectangular 2-D coordinate grids reject planning. |
| extract_family_member | `member_variable_id` defaults to member_id; explicit `members`. Projection may omit the member variable. Produces an ordinary derived Dataset. |
| split_family | Explicit `output.member_outputs` maps every selected member to its requested Dataset ID. All member publications form one logical transaction; a failure rolls back newly created members and emits no catalog event. |
| convert_units | Explicit `target_units` or per-source `convert_units`. Uses public Unit Registry conversion plans, persisting the source/target definitions and applied formula/scale, including variable-specific canonical calibration. |
| transform_xy | Explicit X/Y output IDs and six finite `matrix` entries `{a b c d tx ty}`; computes `(a*x+b*y+tx,c*x+d*y+ty)`. Mixing coordinates requires equal units or explicit conversion. Ancillary tuple values remain intact. |
| reverse_rows / reverse_range | Complete tuples reverse together. Ranges are zero-based `{start count}` pairs, disjoint and bounded. `source_member_ids` or `member_id` scopes input sources. `members` with `member_variable_id` reverses only selected family members, preserving unrelated member positions/order. |
| reverse_sequence | A single source's ordered `steps={{start count} ...}` each reverse a span of the current complete tuple order. Later steps may overlap earlier steps because they are sequential transformations. Bounds are validated for the entire private recipe; source preprocessing order/reverse is applied first. A disk-backed integer permutation preserves all columns and original row lineage. It creates no Dataset unless explicitly materialized. |
| sort_rows | One source, explicit ordered `order_variable_ids`, optional boolean `descending`. Sorts complete selected tuples in a disk-backed index. Equal keys preserve original source order; text uses exact lexical ordering and uint64 keys retain integer precision. Numeric keys must be finite/non-null. Optional lineage maps every sorted tuple to its original source row. |

Metadata policy is `inherit_single_source`, explicit `inherit_primary`,
`merge_common`, or `explicit` (`options.metadata`). Conflicting multi-source
values are omitted and recorded as conflicts; source notes are not concatenated.
The persisted `transform.manifest` is the validated request and
`transform.effective` records output schema/mapping, exact source IDs and SHA-256,
conversions, member information, actual contract/provider/output ID, ordering and
bounded-read diagnostics. Producer/version and timestamp are also persisted.

Tcl services:

```tcl
datasetTransformOperations
datasetTransformDescribeOperation operation
datasetTransformValidate session manifest
datasetTransformPlan session manifest
datasetTransformReleasePlan plan_id
datasetTransformOpenView session manifest_or_plan ?split_member?
datasetTransformOpenViewStream view ?variable_ids? ?chunk_rows? ?options?
datasetTransformCloseView view
datasetTransformExecute session manifest_or_plan
datasetTransformExecuteResponsive session manifest_or_plan ?options?
datasetTransformCancel job_id
datasetTransformResponsiveApiInfo
datasetTransformProvenance session dataset_id
```

Planning validates actual data-dependent constraints and caches a private
disk-backed index and transformed row stream. It writes no Session Dataset or
Registry entry. Public results expose no scratch/provider file paths. Input reads
are bounded at 65536 rows, using public typed binary transport where available;
effective diagnostics record actual chunk size/count and binary columns. SQLite
cache is 4 MiB and disk-backed ordering avoids a
whole-Dataset Tcl list. Release an explicit plan when finished. A view opened
directly from a manifest owns and releases its plan; an explicit plan remains
caller-owned. `close_view` closes its streams. Script execution cleanup releases
all owned views/plans. Source payload SHA, schema and metadata are checked before
opening streams/materializing; stale plans reject use.

View streams use ordinary Table Stream v3 `metadata/next/diagnostics/close`.
Chunk rows are 1..65536; start/count select a bounded logical output range. Views
are read-only, process/Session-scoped logical tokens, never hidden Datasets.
Materialization publishes payload, schema and metadata through Publication v2.

For interactive single-output workflows, `datasetTransformExecuteResponsive`
uses the same validated manifest, exact disk-backed plan and canonical parent
publication authority. Planning runs as an owned process through public CORE
Parallel Execution. Materialization yields between complete bounded chunks;
default `chunk_rows` is 8192, configurable from 1..65536. It retains the complete
input and never publishes display-reduced data.

Options are `progress_command`, `cancel_command`, and `chunk_rows`.
`progress_command` receives a dictionary with `api_id`, `api_version`, opaque
`job_id`, `stage`, `current`, `total`, and `cancellable`. Stages are `planning`,
`planned`, `materializing`, and `precommit`; planning has an indeterminate total
and reports periodically while its worker runs. `cancel_command` is a command
prefix returning a boolean. Alternatively, pass the active receipt's `job_id`
to `datasetTransformCancel`. Cancellation reaps an owned planning process or
aborts a staged publication, returning error code `{GX DATASET_TRANSFORM
CANCELLED}`. No failed/cancelled Dataset or catalog revision is committed.
Progress/cancel callback errors are propagated explicitly and staged resources
are closed. Session lifetime is checked across every event boundary, including
A→B→A; source fingerprints are verified after the final boundary before commit.
Canonical commit does not yield and cannot be cancelled after registry writes.

Only one responsive Transform may run at a time in the current CORE interpreter.
Existing synchronous APIs and Script Bridge operations retain their behavior.
Responsive `split_family` is explicitly unsupported; use the existing atomic
bundle API. This limitation is reported by `datasetTransformResponsiveApiInfo`.

Script operations have the same snake-case names. `open_view_stream` takes
`view, variable_ids, chunk_rows, options`; then use `TABLE_STREAM_API_v3` to read.
`execute` returns the exact ID, count, contract, provider and digest, or explicit
`dataset_ids/datasets` for a split. Tokens are scoped to the current execution.

Long families record complete `member_descriptors`: source X/Y schema, labels,
units, value kinds, IDs and row count. A single-member extraction restores that
member's axis descriptors even when the original family has heterogeneous units.

`examples/scripts/dataset_transform_examples.py` and `.m` are runnable Script
Workspace examples for projection, compatible concatenation, long curve-family
publication and ordinary member extraction. Their headers specify the source
Dataset/Variable IDs to configure. Each example plans, publishes one explicit
create-only ID and releases its plan; both languages have been executed against
the same disposable CSV/HDF5 Session.

Standard Octave modules may use `gxtxt_dataset_transform_execute(config_path,
manifest)`, the public CORE JSON transport. CORE owns bootstrap, canonical reads,
scientific validation and transactional publication. The helper uses the normal
runtime's Session/owner; request/result paths are transport scratch files, never
physical Dataset destinations. An optional `selection_id` with
`selection_operation=keep|exclude` resolves a saved Selection before execution;
`selection_trace=true` projects each member's explicit X/Y bindings. Consumers
must not implement their own multi-source row join or Dataset writer.


## TASK-9 dev-052 final behavior

`concat_rows`, `curve_bundle` and `build_family` accept an optional `native_geometry` source containing CORE-owned `xy_resource`, optional `row_resource`/`gap_resource`, and scientific `x_variable`/`y_variable` descriptors. The public manifest contains resource receipts, never worker filesystem paths. CORE validates owner generation/revision and stages bounded binary chunks; Native XY must have finite float64 coordinates and explicit compatible length units. Real Dataset source-row lineage recovers complete original tuples with exact integer/string types. Unbound Native auxiliaries use an explicit `<lineage_prefix>auxiliary_valid` mask; zero/empty placeholders with mask0 are absent readings. `<lineage_prefix>break_before` preserves scientific gaps and reversal moves the flag with the same edge.

`preserve_auxiliary=1` requests complete per-member tuples in long/family or wide bundles. Long output adds member-prefixed original auxiliary schemas and `member_present_<id>` masks. Wide output adds independent Y, member auxiliary fields and source-row ordinals; exact shared X/count is required, with only explicitly requested X tolerance and no interpolation. Legacy bundle defaults retain their prior XY projection. `variable_mapping`, member descriptors and effective policies preserve provenance.

`polar_output` contains `representation=polar|both`, Native `frame`, explicit X/Y IDs and optional theta/radius/angle-defined IDs. Conversion is a bounded public Native bulk operation. Output declares deg/rad angle units, working-unit radius, frame/orientation, positive-full-turn normalization and explicit undefined-origin mask. Cartesian-only leaves input coordinates unchanged. Original Dataset payload/schema are immutable. Plans reject changed resource owners before commit; responsive progress/cancel boundaries preserve atomic publication.

## dev095 missing-cell read-only filters

The existing typed-tuple adapter recognizes canonical missing numeric cells from
Tcl value transport as null. Read-only subset/family views retain the row and
lineage when a different field matches; finite/nonfinite predicates recognize
absence, and explicit conversion preserves it. Numeric nulls use the existing
view transport's NaN representation. Canonical source cells/dtypes are unchanged.
