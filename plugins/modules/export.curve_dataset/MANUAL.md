# Scientific Curve Dataset Publisher

SPDX-License-Identifier: GPL-3.0-or-later

Select exactly one shown source/member in Curve Viewer, then **Publish Dataset…**.
The common extension dialog identifies its Dataset, X/Y Variable IDs, exact
scientific request and filters. Enter a new canonical Dataset ID (letters,
digits, underscores, dots or dashes), optionally a display name, then Apply.
Cancel/close before submission creates nothing. A collision rejects explicitly.
Disable/uninstall this optional module through the normal Module/Plugin tools to
remove the action; presentation PNG/SVG **Export…** remains separate.

The result is an independent registered `table.generic` Dataset containing the
exact X/Y rows and original dtypes/units plus an int64 original-row Variable ID
`published_source_row` (collision-safe suffix when necessary). Normal Dataset
Preview and Curve Viewer can open it after saving/reopening the Session.
Display budgets, zoom, visibility and later source-view edits do not change it.

CORE Curve Source owns the immutable selection and exact bounded1000-row pages.
Its source descriptor is validated at submission and again before commit.
Publication v2 owns staging, schema, create-only collision/transaction handling,
registry registration and rollback. Zero rows, bad identity, unsupported units,
stale source/Session/Workspace, failed writer or collision leave no partial
Dataset. Nonfinite scientific values are preserved exactly; the metadata declares
this policy. Original source row identities declare `source_row_adjacency` so
reopening a filtered plot does not join nonadjacent source segments, including
when the renderer resamples the published Dataset.

Structured metadata under `curve_publication.*` records producer ID/version,
frozen request, original Dataset/source identities and fingerprints, complete
X/Y variable schema, exact-page method, request order and finite policy.
`curve_source.continuity_*` declares the public CORE display continuity contract.
No private scientific registry, row evaluator or plotting engine exists.

## Public module API

`CURVE_DATASET_EXPORT_API_v1` exposes `::GX::CurveDatasetExport::publish context`.
Use the existing `workbenchExtensionInvoke export.curve_dataset publish context`
for extension discovery/typed arguments/lifecycle checks. Context contains
`workbench_id=viewer.curve_viewer`, `document_id`, its `revision`,
`selection={kind curve_source request … descriptor … session_token … document_generation …}`, and
`parameters={dataset_id … display_name …}`. The descriptor comes from public
`curveSourceDescribe`, not a renderer token. The receipt contains Dataset ID,
exact row count, Publication v2 receipt and scientific provenance. This API is a
module invocation façade; all reusable scientific services remain in CORE.
Capture `session_token` from `interactiveDocumentSessionToken` and the document's
`generation` at submission. Both are checked before publication; a Session
A→B→A switch rejects the old frozen submission even if source bytes match.
