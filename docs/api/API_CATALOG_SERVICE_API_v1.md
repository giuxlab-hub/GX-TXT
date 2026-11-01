# API Catalog Service v1

The catalog is a derived C++/SQLite index of installed public declarations. It is
metadata, never execution permission. Its packaged database, portable source
manifest, native implementation and matching binary supply the initial process
snapshot. Indexed reload/search performs bounded native queries without source
discovery or worker processes.

All host commands below are qualified with `::GX::`. No scientific Session is
required.

| Public Tcl operation | Contract |
| --- | --- |
| `apiCatalogRequest CALLBACK` | Initialize/read the process snapshot asynchronously; return a consumer ticket. Callback contains `ok` and `result` status or `error`. |
| `apiCatalogQuery FILTERS` | Bounded page containing rows/total/offset/limit/generation/fingerprint/freshness/error. |
| `apiCatalogGet RECORD_ID` | Exact API/provider/operation record; unknown identity is an explicit error. |
| `apiCatalogStatus` | Loaded identity/count/generation, framework identity, freshness, progress, request activity, target fingerprint, pending metadata and last error. |
| `apiCatalogRefresh CALLBACK` | Public manual validation/reconciliation API. Preserve the running immutable snapshot; use the same ticket/callback contract. |
| `apiCatalogCancel TICKET` | Detach this consumer while other consumers/shared reconciliation continue. |
| `apiCatalogInvalidate` | Trusted Plugin Manager lifecycle notification; coalesce automatic reconciliation. |
| `apiCatalogProviderState PROVIDER` | Current installed/enabled/active/pending projection from existing module/lifecycle owners; grant no execution access. |
| `apiCatalogDiagnostics ?verify_sources?` | Host inspection of packaged/loaded/staged identities. Boolean verification defaults to false; explicit true checks current source and file hashes. |
| `apiCatalogManualInspect RECORD_ID ?PROVIDER? ?WINDOW?` | Bounded read-only inspection of one exact API/provider manual and optional correlated presentation result. |
| `apiCatalogManualOpen RECORD_ID ?PROVIDER? ?PARENT?` | Open the normal Documentation Browser manual host and return its current inspection, including `window` when opened. |

Queries accept exact `api_id`/`provider_id`, exact declaring `source_ref`/
`source_sha256`, `surface` (family/host/script_bridge/cpp_sdk), `language`
(Python/Octave/Cpp), literal `query`, `offset` and `limit` (1–1000).
`family:API_ID` selects an aggregate API detail; other returned record IDs select
exact provider/operation records. For example:

```tcl
::GX::apiCatalogQuery {source_ref core/tcl/workbench_recovery_api_v1.tcl limit 100}
::GX::apiCatalogManualInspect family:CURVE_DIGITIZER_QUALITY_API_v2 viewer.curve_digitizer
```

Provider/source provenance, arguments, results, deprecation, documentation status
and independent Python/Octave visibility reside in indexed native relations.
A Browser page never needs a full-catalog transfer. A family with several
providers requires an explicit provider for manual inspection.

## Database identity and reconciliation

The source manifest drives a native content identity check over exact shipped
source/documentation identities and current plugin declaration roots. It does
not rediscover CORE contracts during ordinary startup. Missing, corrupt or
incompatible packaged indexes fail explicitly. Packaged seeds use DELETE journal
mode and create no installation sidecars. Native contention waits are bounded
to 100 ms.

Private snapshots/stages reside under
`$XDG_CACHE_HOME/gxtxt/api-catalog-v2/`, falling back to `~/.cache`, and are bound
to executed framework and configuration identities. The installation is never a
cache target. Each process retains one definition snapshot. Successful runtime
updates stage a complete next-process database and report `pending_restart`.
First initialization may adopt a valid matching stage before a Browser sees it.
Failed/interrupted staging preserves the previous good snapshot and diagnostic
evidence. Consumer cancellation does not discard another consumer's work.

Normal plugin reconciliation reads inert descriptors/Tcl data and literal Python
AST metadata. It never imports plugin code, executes installers, constructs a
scientific Host, invokes scientific operations or builds authored C++. Exact
unchanged binding sources retain their trusted inventory; safely parsed literal
updates can replace it. Dynamic changed metadata that cannot be established by
inert parsing is reported as `pending_metadata` and omitted from the staged
snapshot. Invalid contracts and conflicting Bridge providers fail refresh.
Public provider/version conflicts remain visible per owner.

Trusted distribution building runs existing CORE contracts, registered Bridge
metadata discovery and exact SDK/policy projection. `gxtxt_api_catalog.py build`
creates a complete reproducible index in a fresh stage, checking source identity,
SQLite integrity and provenance. Root checksum manifests and generated catalog
files are excluded from input identity to avoid circular hashes.

Configuration → Framework Maintenance exposes the public reconciliation action
inside its API Catalog section. Editor Browser reload controls reload their
indexed view. Automatic startup and plugin installation/update reconciliation
use the same service.

## Host diagnostics

`apiCatalogDiagnostics` returns `gxtxt.api_catalog.diagnostics.v1` with `status`,
`framework_root`, `framework_identity`, `packaged`, `loaded`, `active_stage`,
`pending_stage`, `counts` and `source_verification`. Packaged fields identify
physical database/manifest paths, loaded expected database checksum and manifest
fingerprint. Loaded fields identify the private snapshot/cache, fingerprint and
generation. Stage fields distinguish a managed active/failed worker location
from a published next-process candidate and its pending metadata/errors. Counts
are one bounded native SQLite grouping for surfaces and exact indexed providers,
without repeated per-provider queries or declaration-payload transfer. Both
groupings share a read transaction and are cached by immutable snapshot
fingerprint/generation, including providers removed from the current installation.

Ordinary diagnostics report file presence/type/size without hashing every source.
Explicit verification adds actual packaged/loaded/staged file SHA-256 values,
current packaged manifest/database agreement and a source fingerprint result
(`current`, `catalog_stale` or `failed`). A failed verification retains its actual
bounded error. Diagnostics do not mutate or regenerate a catalog.

## Manual inspection and presentation

The manual inspection result uses `gxtxt.api_catalog.manual_inspection.v1` and
retains `record_id`, `api_id`, `provider_id`, executed root, loaded catalog
fingerprint/generation, `declaration`, `indexed_document`, `installed_document`,
`resolver`, `runtime_state` and `presentation`. Declaration data includes indexed
and current source identity and explicit descriptor reference. File evidence
includes actual confined path, type, presence, size and bounded SHA-256. Resolver
evidence comes from the normal Documentation Browser owner; no replacement
manual is guessed and no guide is copied into a second store. A registered
Bridge source can own a different manual from its host descriptor or common API
family. An exact unchanged declaring-source SHA retains that binding reference;
a changed source is explicitly `requires_reconciliation` rather than reimported
or guessed. A valid different family document is reported as
`resolver.relation=different_family_reference`, not a wrong-reference error.
Opening such a selected reference uses the same public confined Documentation
manual window owner.

| Status/reason | Observable condition |
| --- | --- |
| `file_missing` | The confined declared document is absent. |
| `wrong_reference` | An omitted declaration falls back to a missing API document, or the installed declaring descriptor no longer provides this API. |
| `catalog_stale` | Current declaring source or known document hash differs from the immutable indexed identity. |
| `invalid_path` | Absolute/traversing/encoded/linked/unsupported/oversized document path is refused. |
| `module_disabled_or_missing` | Existing lifecycle owners report the provider unavailable or disabled. |
| `document_viewer_error` | An actual normal opening/presentation attempt fails; retained renderer error is separate from file availability. |
| `available` | The declared file is available through the existing confined documentation owner; the common family resolver can represent a different surface. This alone certifies no rendered pixels. |

`reasons` preserves secondary conditions, such as a missing file with a stale
indexed source. There is no claim to infer a document's scientific correctness
from its filename or existence. The normal manual owner supplies an optional
source-correlated receipt: window incarnation, path, source SHA and positive
presentation generation must match. A reused window showing another source is
explicitly uncorrelated. `presentation.state=not_attempted` is distinct from
loading, ready or error. `rendering_verified=0` remains explicit: independent
real GUI observation supplies visual evidence, rather than a fabricated renderer
success flag. HTML state/errors come from the existing HTML Viewer public receipt;
Markdown/text use the existing GX-Markup owner.

These diagnostics/manual operations are host-only: they expose physical
installation/cache paths and Tk/renderer lifetimes. They grant no additional
Script Bridge, restricted SDK or scientific execution capability. Existing
public Documentation Browser Script list/read contracts remain available.

## Maintenance panel integration

`::GX::frameworkMaintenanceCatalogBuild parent` builds the API Catalog section
inside an existing empty Framework Maintenance content frame. The host sources
`app/gui/framework_maintenance_catalog.tcl`; it owns no new catalog state or
scientific context. The Database status tab provides **Update status**, explicit
**Verify sources and checksums**, and **Refresh / Reconcile**. Refresh reports
actual progress, preserved errors and next-process restart guidance.

The Manual inspection tab offers literal Search, exact API ID/Provider and
surface filters, 50-record native pages, **Inspect selected**, **Inspect page**
and **Open manual**. Indexed status is labeled separately until actual inspection;
page inspection yields between bounded records. Opening uses the normal manual
owner and reports source-correlated presentation state. Closing the panel cancels
only its own consumer ticket and timers when its owned tab is destroyed, including
sidebar section replacement in a surviving content frame. Shared reconciliation, other
consumers and independently opened manual windows remain under their existing owners.

## Browser and Builder consumers

Viewer Interface Builder exposes `api_catalog` with `title`, `language`
(Public/Python/Octave/Cpp), `surface`, `query`, exact `api_filter`/`provider_filter`,
`presentation` (full/compact) and `enabled`. Normal containers/grid/pack/splitters/
tabs, keyboard selection, scrolling, bounded paging, empty/error/status views,
manual navigation and clean disposal remain supported. Selection/manual events
are `selection_changed`/`manual_opened`; captured presentation state retains query,
surface, page and selected record, with no native handles or project grants.
A useful full view is at least 320 × 360 px; smaller panes retain scrollbars and a
resizable list/detail sash.

Octave/Python editor consumers use only registered Script Bridge operations.
C++ defaults to public documentation plus exact finite SDK methods; saved-project
admission is computed separately and never treated as a global grant. Generic
components can present a source-neutral public reference with labeled surfaces.
The regenerable private example is `examples/api_catalog_navigation/`.

### Compact Browser composition

The existing `presentation compact` factory keeps its declared title, filters,
project context and enabled state. An explicitly empty `title` lets a containing
notebook supply the label. Search/surface controls and the responsive
Manual/Previous/Next footer use the same Browser operations. Healthy nonempty
`current` results release redundant status space; pending, stale/unknown, empty
and error states retain visible feedback. Coalesced compact resize callbacks
clamp the list/detail sash to measured three-row/four-line minima and are
cancelled on disposal. A containing Workspace must provide that measured height;
regular presentation retains its existing chrome and split behavior.

API Browser family and method rows use the existing shared UI Field inspection
font and row padding. The native row height follows the saved Appearance font,
and the three-row minimum uses those actual rows. This does not autosize the
Browser's declared columns on queries or replace a deliberate horizontal pan.

### Acquisition project references (P032)

Saved `gxtxt.acquisition_development_project.v1` projects use their registered
source/helper roster and `acquisition_v1` policy for reference context. They do
not require or manufacture a Viewer design. `apiCatalogProjectContext` reports
`target acquisition`; capability status still means saved request admission,
with source validation and active runtime grants explicitly unchecked.

The eight `AcquisitionHost` method records retain their actual Acquisition SDK
header reference/SHA and `required_target acquisition`. A Viewer project cannot
admit these methods merely by naming the same API. Malformed typed declarations,
unregistered/traversing source paths and unavailable providers refuse reference
admission. Metadata lookup never executes helpers or grants filesystem, source,
Publication or administrative access. Existing Viewer SDK records keep their
original header, profile and capability rules.

Host reference rows retain both earlier `signature` metadata and the more
explicit provider documentation with `command`/`arguments`/result `type`.
The Browser displays either form without inferring an undeclared host command
or result type. Partial or malformed reference fields produce visible metadata
diagnostics instead of a selection-event error. This is inert documentation:
selecting a family or method does not invoke it or grant Script Bridge/native
runtime capabilities, and registration/admission validation remains unchanged.
