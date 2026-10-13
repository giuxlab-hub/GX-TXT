# CORE Dataset Scientific Profile API v1 — dev075

Dev075 extends the existing profile authority. API version 1, categorical
`profile_revision 2`, persisted metadata key, old commands, Preview/Graph Series
behavior and all existing module contracts are preserved. Descriptive summaries
use additive `summary_revision 1`; there is no second profile store or registry.

## Public additive Tcl operations

All commands are in `::GX`. Queries are headless-safe, nonmutating and never start
a scientific payload scan. They reuse registered canonical hashes and the existing
opaque scientific schema stamp, which includes storage/schema identity.

| Command | Behavior |
| --- | --- |
| `datasetProfileApiInfo` | Existing authority identity plus extension capabilities/budgets. |
| `datasetProfileDescribe session dataset` | Existing `current|absent|stale` record, Schema v3 `structure`, measured availability, and any persisted `summaries` keyed by stable Variable ID. |
| `datasetProfileVariable session dataset variableId` | Public structure plus available summary, or `status absent|unsupported`. Uniform coordinate metadata may add a separate `declared_axis` range/order/count computed without samples. |
| `datasetProfileDistinct session dataset variableId ?options?` | Exact provider values in encounter order, explicit dtype/completeness/coverage/cardinality, bounded pagination. Options `start`, `limit 1..1024`, `require_complete 0|1`. It may use the preserved categorical inventory when no descriptive summary exists. |
| `datasetProfileRequest session dataset ?options?` | Explicit CORE/user backfill; returns an opaque request token immediately. Options `variable_ids`, `row_budget`, `value_budget`. Services are cooperative Tcl event-loop jobs. |
| `datasetProfileProgress token` | `building|complete|failed|cancelled`, observed elements, summary results, timing and failure reason. |
| `datasetProfileCancel token` | Cancels at the next chunk boundary, closes access handles, and leaves the prior committed profile intact. |
| `datasetProfileRelease token` | Idempotent release; also cancels an active request. |

`row_budget` is the **shared total variable-element budget** (1..100000000), default
1000000; it is consumed across selected variables. At most 32 distinct variables,
4 active jobs and 32 retained request handles. Read chunks are at most 2048 elements.
Each variable retains at most 1024 distinct values, 1024 bytes/value and 64 KiB of
value text; oversized/high-cardinality inventories are explicitly incomplete. Release
completed requests to bound retained result memory. Existing categorical budgets
remain unchanged. Metadata decode/summary sizes and integrity/version are bounded
and validated before reuse; descriptive bodies carry a CRC32 corruption checksum.
Canonical SHA-256 remains source identity, not a statistical authenticity claim.

## Scientific semantics

Numeric summaries: observed, finite, missing, NaN, positive/negative infinity and
invalid counts, finite min/max, population mean/variance through Welford, ordering
across chunk boundaries, strictness and exact distinct inventory when it fits.
Integer extrema compare using Tcl integer/bignum arithmetic, preserving int64 above
2^53. Means/variance use approximate float64; overflow makes moments unavailable.
Floating extrema are over the provider's values; no calibration is invented.

`complete` is exact coverage, independent of `distinct_complete`. Full covered
extrema use `extrema_status exact`; partial extrema use `sample`. An empty finite
domain has empty min/max. Ordering is `constant|increasing|decreasing|nonmonotone`
only for full rank-one numeric coverage without gaps; otherwise `unknown`. Text
and bool variables have exact bounded membership/coverage, without numeric moments.
Empty text remains a valid filter value. Empty numeric fields are missing; NaN and
infinities are separate. Provider null masks are not universally exposed, and invalid
CSV numeric tokens may already be represented as NaN by the existing provider.
Those distinctions cannot be recovered by this profile.

Equality values retain the existing provider's lexical transport and dtype. The
profile itself does not trim, normalize, case-fold, sort or round values. CSV's
existing provider tokenization and HDF5's dtype decoding remain their authorities;
this API cannot reconstruct discarded raw lexical whitespace. Python/JSON bridge
values remain strings with explicit dtype, avoiding a forced JSON double for int64.

Rank>1 measurements and scalar membership currently return `unsupported`; their
full scientific structure is available. Implicit uniform axes return a **declared**
endpoint range/order, with float64 arithmetic rounding explicitly identified,
without materializing millions of coordinates. Stored values are not conflated
with those schema-derived declarations.

## Lifecycle, construction and compatibility

Requests run one bounded range per scheduled turn through Canonical Dataset Access;
CSV retains its sequential provider file position, HDF5 uses direct ranges. Selected
variables may require separate passes. The event loop must run (`vwait`/normal Tk);
request completion is not a promise of a separate process. Provider startup/open and
individual range calls remain synchronous. There is no whole-Dataset Tcl array.

Session lifetime and registered content/schema identity are checked each turn,
including a registry reload to catch replacement from another process. Persistence
uses the existing atomic framework metadata update after all requested summaries
finish. Failed/cancelled work never installs an incomplete record as complete.
Concurrent same-process builds of one Dataset are refused. Across processes, source
identity checks prevent obsolete content/schema commits; same-identity concurrent
builds can retain the last writer's property set (there is no distributed merge lock).
The schema/content commit path invalidates old summaries using existing profile
refresh; it preserves the original categorical publication behavior and rollback.

Numeric summaries are an explicit backfill in this release. There is no new hot-path
streaming writer profiler, background auto-build on getter, approximate cardinality
sketch, quantile engine or multidimensional scan. The existing bounded categorical
publication scan is retained. These are documented limits, not invented statistics.

Existing Preview filters and Graph Series read the same categorical profile; another
consumer uses the descriptive queries. The real Script Bridge registers the existing
`DATASET_SCIENTIFIC_PROFILE_API_v1` for read-only `describe|variable|distinct`, each
accepting `{dataset_id, variable_id?, options?}`. Requests/persistence are deliberately
not exposed as implicit headless script work.

```tcl
set token [::GX::datasetProfileRequest $session $id \
    {variable_ids {x y member_id} row_budget 500000 value_budget 128}]
# Normal Tk event loop drives the request; check Progress or cancel explicitly.
set info [::GX::datasetProfileVariable $session $id x]
set choices [::GX::datasetProfileDistinct $session $id member_id \
    {start 0 limit 100 require_complete 1}]
::GX::datasetProfileRelease $token
```

Validation: CSV/HDF5 int64/text equivalence, actual numeric ranges/moments, 102400
rows with bounded high cardinality and GUI heartbeat, zero repeated range/stream
reads through two consumers, fresh-interpreter reopen, partial coverage, corruption,
mid-build cancellation, replacement races, metadata-failure rollback, high-rank
unsupported state, and a ten-million-element implicit axis with zero data reads.
These checks exercise bounded resource use, numerical equivalence and cancellation without altering the original Dataset.

# Legacy categorical component (dev073/dev074; preserved)

This bounded categorical profile is a derived field in the existing Dataset
Metadata API v1 resource, under `_gxtxt.framework.scientific_profile`. No database,
plugin sidecar or new fingerprint authority is introduced. Stable Variable IDs
identify genuine family/member/group, trace/sweep, replicate and declared text
source-category variables, including declared numeric category codes. Text source `kind` is distinct from a contract or dtype.

Public Tcl operations:

- `datasetScientificProfileRead session datasetId`: read-only; returns current,
  absent or stale. A stale profile exposes no usable values.
- `datasetScientificProfileDiscover session datasetId ?rowBudget? ?valueBudget?`:
  controlled bounded read-only legacy discovery. Cached once per Session lifetime,
  Dataset identity and budgets; no metadata or scientific bytes are written.
- `datasetScientificProfileBuild session datasetId`: explicit CORE/user operation
  that persists current discovered values through the existing transactional Metadata
  API. Existing current profiles are reused; public module contexts cannot acquire
  framework metadata authority through this operation.
- `datasetScientificProfileApiInfo`: identity, operations and bounds.

Records include registered content identity (`canonical_sha256`, `sha256` and
Dataset ID), the existing Graph Series scientific preparation identity, per-variable
label/unit/type, exact distinct source values in encounter order, scanned_rows,
complete and truncated. Values are never relabelled, normalized or sorted. Numeric
nonfinite/missing values are omitted from choices and retained in scientific data.

Bounds: 100,000 rows, 1,024 distinct values per variable, 1,024 bytes per value,
32 scanned variables and 2 MiB retained value bytes. Exceeded bounds yield explicit
incompleteness; oversize values are omitted from the profile rather than modified.
Incomplete inventories cannot enable an All members claim. Extra relevant variables
carry empty/incomplete entries with the discovery-budget reason. An in-memory
legacy cache retains at most 32 Dataset/budget identities, with obsolete identities
removed. Persistence is base64-encoded structured Tcl data in the ordinary metadata
INI, protected from generic user/module metadata editing.

Normal registry commits detect changed scientific fields and generate/update profiles
for acquisitions, imports, generation, publication and replacement. The bounded
scan happens after source processing, inside the existing registry/metadata commit
and its backups, rather than in a second processing engine. A streaming accumulator
is intentionally outside this minimal extension. Scientific schema rollback also
restores the affected metadata resource. Namespace/notes/display-only metadata changes
do not trigger row scans. Profiles reuse the registered integrity fingerprints;
unauthorized external file changes are still rejected by canonical payload integrity
checks in rendering rather than normalized or silently committed by consultation.

Preview consults persisted profiles first. Graph Series reuses complete profiles
without changing its return contract; incomplete values do not masquerade as its
complete inventory. Older Datasets remain compatible through the bounded cached
read-only discovery path; callers may explicitly Build for reuse across processes.
Only a supported canonical content/schema commit invalidates/regenerates a profile.

The profile avoids repeated categorical-inventory scans. Rendering an XY plot still
reads its requested scientific rows through the existing Curve Source facilities.

Legacy cache eviction after more than 32 Dataset/budget identities can require another
bounded discovery. Explicit Build avoids repeated discovery across eviction/processes.

The profile scope is enabled rank-one categorical/grouping Variables supported by
the existing row-filter facilities, including variables on independent dimensions.
Scalar and multidimensional categorical inventories are outside this focused profile;
their existing scientific schema and Dataset Access APIs remain available.

Dev074 derived profile revision 2 retains empty text values exactly, matching the
existing Graph Series distinct-value contract. Selectors display `(empty text)`
but requests still use the original empty string. Earlier inventory revisions
are stale and expose no usable values; normal scientific commits or explicit Build
regenerate them through the same metadata transaction. No scientific values change.

## Dev076 categorical inventory compatibility

A current complete categorical inventory in `variables` is retained when descriptive
backfill has incomplete coverage or a smaller value budget. Source/schema identity is
validated before merging, so obsolete inventories cannot cross a Dataset replacement.
`datasetProfileDistinct` prefers an available complete categorical inventory over an
incomplete descriptive distinct sample. `datasetProfileVariable` still reports the
actual requested summary's partial coverage: complete membership does not imply
complete numeric statistics. Existing API identity, metadata key and signatures stay
unchanged. The public contract applies consistently to CSV/HDF5 sources,
Preview and Graph Series consumers.

### Explicit filter binding (dev094)

`scientificDatasetFilterDimensions id ?rowBudget=100000? ?valueBudget=1024?
?manualFamily={}? ?semanticOnly=0?` retains existing discovery budgets and typed
values. A manual family is an enabled rank-one public Variable ID. With
`semanticOnly=1`, automatic categorical dimensions must have declared semantic
roles; legacy column-name inference alone cannot select a family. Curve Viewer
uses this mode and requires manual disambiguation when several family variables
exist. Other existing consumers keep the compatible default.
`scientificDatasetFilterControls parent id array prefix ?reset=0?
?manualFamily={}? ?semanticOnly=0?` exposes the same options. Requests still use
public Curve Source/Graph Series predicates; no filter evaluator was added.
