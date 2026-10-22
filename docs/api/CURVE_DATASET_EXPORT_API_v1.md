# CURVE_DATASET_EXPORT_API_v1

Version 1, installed provider `export.curve_dataset` version 1.0.0, namespace
`::GX::CurveDatasetExport`. Its normal entrypoint is
`api/curve_dataset_export_api_v1.tcl`. This utility publishes the exact frozen
Curve Source selection into one new canonical Dataset; graphical PNG/SVG export
is the separate Native2D presentation exporter.

## Complete public calls

| Exact Tcl signature | Result / effect |
|---|---|
| `::GX::CurveDatasetExport::apiInfo` | API/version/provider/version, `operations=publish`, authorities Curve Source and Dataset Publication v2 |
| `::GX::CurveDatasetExport::publish context` | `status=ok`, dataset_id, canonical publication receipt, exact_rows, provenance; creates a new Dataset in the current Session |

The module declares extension `publish`, category `utility`, for
`viewer.curve_viewer`, selection kind `curve_source`. Its `mutates=0` means the
Viewer transaction/geometry is not edited; canonical publication is a real
write. Parameters: required string dataset_id, optional display_name default
empty (effective default is output ID). Normal Workbench Extension validation
owns action admission, current Document owner/revision and parameter schema.
The adapter also rechecks captured lifetime/generation/revision/source identity.

No direct Python/Octave registration or typed C++ SDK method for this family
exists at this checkpoint. Use the actual admitted Extension workflow where
available; catalog presence does not create arbitrary Script/C++ invocation.

## Context and retained source

The context contains current `document_id,workbench_id,revision,parameters` and
`selection`. Selection requires `kind=curve_source`, frozen Curve Source
`descriptor`, original `request`, captured `session_token` and
`document_generation`. Normal Viewer/Extension owners construct it from the
selected source. Do not substitute display polylines, Native IDs or a hand-built
label for scientific identity.

CORE Curve Source must advertise continuity policy source_row_adjacency. The
adapter checks current Session lifetime, Document generation, frozen snapshot
validity and new output ID; opens the exact source request; then requires the
new descriptor source_id to match the frozen one and row_count at least one.
Units are checked through Unit Registry: registered opaque scientific unit
labels are allowed; unregistered expressions require understood intrinsic scale
and a valid identity conversion plan. No numerical conversion is applied.

The source's X/Y Variable descriptors are declared as rank-one explicit row
Variables. Copied available fields include dtype, canonical/name/display_label,
unit, value_kind, semantic_role/source, coordinate_role, value_format,
decimal_separator, time_origin/reference, canonical_unit/to_canonical/
from_canonical, instrument_id/channel. This preserves actual source meaning;
it does not claim to export every unrelated Variable in the source Dataset.

One auxiliary int64, unit-empty lineage Variable starts as
`published_source_row`, appending underscores until distinct from source IDs.
Its values are original zero-based canonical row identities supplied by CORE.
The output records curve_source.continuity_policy=source_row_adjacency and its
actual continuity_variable_id. Gaps/nonfinite/row-filter semantics remain CORE's
exact scientific-source contract; no renderer path or local row evaluator is
used to reconstruct them.

## Materialization, result and failures

The adapter prepares normal create-only Canonical Publication with
contract=table.generic, storage=auto, expected_rows from the exact descriptor,
an extendible row dimension and a heuristic estimated_numeric_bytes=24*rows.
It streams exact pages of at most 1000 rows using curveSourcePage and appends
X/Y plus lineage. There is no total display-budget row cap here; the estimate
is not a promised final byte size. Publication owns storage choice, schema,
writer validation, atomic commit and collision errors.

Before finalization the adapter rechecks Session lifetime/path, describes the
live source again, and verifies Document module owner, revision and generation.
Any failure aborts a still-open writer and closes the source in finally.
Success returns the canonical receipt and exact_rows, with metadata/provenance:
producer/version, source_dataset_id, source_id/source_identities, complete
source_request and copied variable_schema, method exact_curve_source_pages,
finite_policy preserve_all_exact_rows, and order_policy curve_source_request_order.
Original Dataset/Viewer geometry/Document is not overwritten.

Missing/malformed captured context, wrong kind, stale source/Session/Document,
empty or colliding output, invalid unit/schema, no matching rows, stream errors
and commit failures raise errors. `status=ok` is returned only after finalize.
Canonical row identity and provenance do not establish calibration accuracy,
uncertainty or a new scientific model.

## Source-backed host usage

With an already captured live Curve Viewer Extension context:

```tcl
set description [::GX::CurveDatasetExport::apiInfo]
# The existing host supplies selection/Document/lifetime and output parameters.
set receipt [::GX::workbenchExtensionInvoke export.curve_dataset publish $context]
```

This illustrates existing public contracts; it is not an executed test or an
instruction to manufacture a frozen selection. See [Curve Source](CURVE_SOURCE_API_v1.md),
[Publication v2](DATASET_PUBLICATION_API_v2.md) and
[Workbench Extension](WORKBENCH_EXTENSION_API_v1.md).
