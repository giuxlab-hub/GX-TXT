# GX-TXT 0.9.8.10-dev-075 — technical handoff

Delivered CORE foundation candidate; **manual acceptance pending. Stop here.**
Baseline is the verified published **0.9.8.10-dev-074**, archive SHA-256
`7cb7a7ff88280ad5361665b78b3a7e1d43f63f73219d9d097c8e291e902b6d99`.
Archive/expanded parity and every internal SHA manifest entry were verified before
creating a fresh dev075 candidate. The old handoff's expanded dev073 reference was
incorrect; the actual dev074 published artifacts were authoritative. No intermediate
worktree or dev073 framework was used as the baseline.

## Status by API

| Capability | Delivered and verified | Real limits |
| --- | --- | --- |
| Dataset Profile | **Implemented/validated:** extension of existing Scientific Profile v1 and metadata authority; structural/declared axes, numeric counts/ranges/moments/order, bounded exact distinct pages, durable cooperative requests, cancellation, corruption and source-identity checks, read-only Script Bridge. | Explicit numeric backfill; existing categorical publication unchanged. Rank>1 measured summaries, universal provider null masks and distributed same-identity property merges are unavailable. Moments are approximate float64; membership completeness is independent of coverage. |
| Geometry Exchange | **Implemented/validated:** saved-source exact definitions, dependency closure/rejection, units, parameters/constraints, Native semantic construction role, grouping, new local IDs/lineage, independent staged scene, cancellation/rollback and persistent reconstruction. Workbench→another owner uses the same contract. | 4 MiB inline selection, 32 MiB document, 1024 whole retained objects, same active Session. Mixed bulk/Dataset-backed Workbench needs an owner reader; general expression/constraint frame conversion and inter-Session transport are declined. No authenticity beyond current framework authority. |
| Scientific Multiview Host | **Implemented/validated:** real independent Native2D/raster and Native3D worker views, explicit bidirectional identity-map selection, actual camera controls, revision/epoch refresh, layout/tab/resize, two-instance isolation, unavailable backend status and cleanup. | Tk desktop only for GUI. Explicit synchronous owner regeneration procedure; no automatic reconstruction/external Dataset subscriptions or full SEM application. STEP actual normalized unit exposure remains an existing CORE limitation. |

These are working bounded v1 contracts, not a claim that every suggestion in the
brief or future provider/solver capability has been implemented. No public API
major version changed. Profile extension uses summary revision 1 beside the retained
categorical revision 2. Existing modules do not need migration.

## Compatibility and architecture

All plugins, all app/GUI files, all Native2D/Native3D C/C++ sources and compiled
libraries, all packaged external plugins and Session Generators retain baseline bytes.
Only additive CORE files, the existing Scientific Profile file, optional CORE
Workbench capability discovery, and root loader/version/documentation changed.
`CHANGED_FILES_dev075.txt` is the full inventory. Existing Profile `read/discover/build`
commands and categorical shapes remain usable; new measured data is an additional
field in the same reserved metadata record. No extra scientific store, renderer,
Session architecture or event bus was introduced.

Geometry's saved-source reader verifies caller definitions against the document
model and refuses omitted/extra dependencies. Import stages a completely independent
scene and checkpoints a compatible owner payload once. Failure never mutates the
pre-existing target scene/document. Restored copies retain exact controls, scientific
roles, constraints/groups and source lineage without needing the source to survive.
The generic target payload keeps each copy's IDs/groups/parameter scope in its own
receipt; other owners prepare their established payload through an explicit adapter.

The host reuses existing presentation and the renderer-worker protocol. Native2D
uses requested-view bounds on resize; repeated drawing does not inflate the camera
range. Layout swaps preserve sibling viewport instances and explicitly raise them,
so real X11 stacking remains correct. Workers use established Software policy and
resource budgets. Epoch checks reject older model images; owner commits remain the
only scientific editing authority. A renderer failure leaves the document intact.

References: [Profile](../api/DATASET_SCIENTIFIC_PROFILE_API_v1.md),
[Geometry](../api/GEOMETRY_EXCHANGE_API_v1.md),
[Multiview](../api/SCIENTIFIC_MULTIVIEW_HOST_API_v1.md),
[identity and revision flow](../api/CORE_FOUNDATION_FLOW_dev075.md).

## Focused acceptance evidence

- CSV/HDF5 int64 beyond 2^53, exact empty/Unicode/`01` text identities, finite ranges,
  moments/order, zero repeated source reads through independent consumers and a fresh
  process. Numeric nonfinite/missing policy is separately tested.
- 102400 HDF5 rows, 204800 variable-elements: 1.778 s measured build, bounded 16-value
  inventory, exact full coverage and explicit incomplete cardinality. Whole fixture
  wall time 4.15 s and peak parent RSS 80392 KiB; this includes publication/CORE load,
  not a isolated profiler RSS or worker-wide measurement. Profile body <30 KiB.
- Mid-build cancel, replacement races, metadata failure and corruption reject new
  invalid results while preserving prior committed metadata. Rank-two measurements
  are unsupported; a ten-million-element uniform axis needs zero sample reads.
- Native Bezier/line/external-reference reconstruction evaluated at five parameter
  points per primitive; physical mm→m scaling, real constraints/group/topology,
  source untouched after target change/delete, checksum/version/budget/stale rejection,
  cancellation, injected late commit failure, real Native identity and fresh reopen.
- Unchanged Workbench opened through existing `viewerOpen`; independent SEM-like
  host shows a calibrated image and exact transferred geometry plus explicitly
  sampled 2 mm extrusion. Actual desktop picks both directions, actual orbit/zoom,
  1366×768/1920×1080 resize/reorder/notebook, accepted Native dimension change,
  cancelled owner proposal, obsolete worker frame, two hosts, worker unavailable,
  Session cleanup, process termination and no Tk background errors.
- Existing dev074 categorical profile fixture and existing Workbench transaction/
  publication/migration/history regression pass against this candidate. Headless
  API discovery and real Script Bridge registration/query pass without Tk loaded.

Logs, parent timing/RSS and reviewed PNGs are in `docs/evidence/dev075`. All scientific
inputs are newly generated disposable fixtures. No user's Session, source library,
original measurement or published prior release was opened for mutation. GUI evidence
uses authenticated local Linux Xorg `:1`, seat0, actual X mouse input; it is not a mock
renderer or an exhaustive GUI suite. The fixture is not a full SEM viewer.

## Delivery and review

Immutable artifact: `framework/archives/gxtxt_pipeline_v09810dev_075.tar.gz` under
`/home/giu/electronics-server/scripts/GXTXT`, with SHA sidecar and expanded counterpart
`framework/expanded/gxtxt_pipeline_v09810dev_075`. Internal `SHA256SUMS` covers every
file. The restore archive is byte-identical. Active runtime remains at its established
path `/home/giu/script-ag/current/gxtxt`, with `/home/giu/ag-script/current` alias;
the complete old active dev074 tree is preserved in the workspace backup.

A machine acceptance receipt accompanies this report. Publication verification
records full archive/expanded/active/alias/restore parity and paired ordered-section
counts; unchanged external-plugin and generator sections are verified against their
pre-task inventory. The workspace/compito current handoff records the archive's exact
SHA after publication, avoiding an archive hash embedded recursively inside itself.

The unfinished-only TODO removes superseded acceptance work and lists manual dev075
acceptance plus real API limits and pre-existing open tasks. Restart GX-TXT to review
the new release; no running user application is forcibly restarted. Stop for manual
acceptance before beginning another feature phase.
