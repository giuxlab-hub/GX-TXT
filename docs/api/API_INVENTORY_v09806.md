# GX-TXT API Inventory — GX-TXT 0.9.8.10-dev-109

SPDX-License-Identifier: GPL-3.0-or-later

This is the current consolidated inventory for module authors and maintainers.
The current Script Bridge status and provider-owned operation coverage are in
[`SCRIPT_BRIDGE_COVERAGE_v1.json`](SCRIPT_BRIDGE_COVERAGE_v1.json).
It distinguishes public contracts from implementation details and retained
compatibility paths. Historical `API_INVENTORY_v*` files remain release deltas.

The dev109 coverage reconciliation records71 actual registered Script Bridge
families and1142 operations from the current Host/provider declarations. It
retains every previously reviewed host-only policy and does not change language
or SDK admission. Provider manifest and registration-source hashes identify the
inventory revision. Registration discovery is not evidence that all operations
were executed or that optional scientific runtimes are available.

Existing Module public declarations now carry inert, provider-owned host
documentation through `modulePublicApiDocumentation`, including the eight
Calibration methods. The common Development Browser shows exact Tcl formals,
parameter/result types and host context in the reference pane. Its two Generated
providers and ten Installed C++ connectors retain their separate namespaces.
The installed connectors can declare two, three or four callbacks; the current
official Export emits four. Use the selected provider's actual descriptor and
the [Restricted Viewer client reference](RESTRICTED_VIEWER_CLIENT_API_v1.md)
for its callback signatures and optional TeX context.
These declarations grant no Script Bridge or C++ SDK operation. Scientific and
installed GUI acceptance remain separate from documentation validation.
The Scientific Image Inspector now declares its existing `apiInfo` and `apiCall`
host signatures and result contracts. Its `apiInfo` result itself does not
include `api_version` or machine-readable argument/result schemas; the inert
descriptor and [Inspector manual](SCIENTIFIC_IMAGE_INSPECTOR_API_v1.md) provide
the operation-specific reference. These declarations do not execute the Inspector.
The existing Replicate graphics hooks have a [public function reference](../../plugins/modules/curve.replicate_analysis/GRAPHICS_API_v1.md).

Dev109 additive raster/panel contract: existing `NATIVE_2D_GEOMETRY_API_v1`
admits canonical `image.raster` through `raster_dataset_bind`; existing
`NATIVE2D_VIEWPORT_HOST_v1` adds `panel_target` for owned moving scientific
targets. Existing `INTERACTIVE_DOCUMENT_RESOURCE_API_v1` adds `reader_info`
for a verified live resource handle. See [raster source and ROI contracts](NATIVE2D_RASTER_COMPOSITION.md),
[semantic panel targets](NATIVE2D_VIEWPORT_HOST_v1.md) and
[resource lifetime](INTERACTIVE_DOCUMENT_RESOURCE_API_v1.md).
The shared Builder host now composes declared semantic raster context menus,
local tools and original UI Field controls in native anchored sections. Its
finite commands use the existing restricted SDK methods and original annotation
Resource/Document/History owners; see [the design contract](VIEWER_GUI_DESIGN_v1.md#raster-controls-anchored-to-scientific-targets).
Independent installed GUI acceptance remains required; typed owner coverage
does not constitute that acceptance.

## Current module-facing contracts

Activation is `CORE` when the command is available after framework initialization;
`modulePublicApiActivate <module> <API ID>` activates a module-owned API. A
headless-safe service may still have a separate GUI action. The API ID version
is independent of a persisted data format version.

| API ID / version | Owner | Purpose and major capabilities | Activation | Headless safe | GUI-specific | Documentation |
| --- | --- | --- | --- | --- | --- | --- |
| DATASET_API_v2 | CORE | Canonical Dataset access, identity, metadata, variable reads | CORE | Yes | No | [Canonical Dataset](CANONICAL_DATASET_API_v2.md) |
| GRAPH_NOTES_API_v1 | CORE | Stable graph/Variant/Clone Markdown notes and lifecycle | CORE | Yes | Notes editor | [Graph Notes](GRAPH_NOTES_API_v1.md) |
| GRAPH_METADATA_API_v1 | CORE | Stable graph/Variant/Clone namespaced metadata | CORE | Yes | Graph Info | [Graph Metadata](GRAPH_METADATA_API_v1.md) |
| PORTABLE_RESOURCE_API_v1 | CORE | Validated individual Dataset/Graph ZIP transport, staging, collision-safe import | CORE | Yes; host only | Review dialog | [Portable Resource](PORTABLE_RESOURCE_API_v1.md) |
| PLOT_ANNOTATION_API_v1 | CORE | Descriptor-enforced annotation CRUD and atomic layer state | CORE | Yes | Standard editor | [Annotation](PLOT_ANNOTATION_API_v1.md) |
| DATASET_METADATA_API_v1 | CORE | Namespaced Dataset metadata and shared portable text parsing | CORE | Yes | Metadata editor | [Dataset Metadata](DATASET_METADATA_API_v1.md) |
| CANONICAL_DATASET_API_v2 catalog extension | CORE | Committed revision, snapshot, changed-since receipts, host subscriptions and shared selector refresh | CORE | Yes | Selector adapter | [Dataset catalog](DATASET_CATALOG_v1.md) |
| DATASET_PREVIEW_API_v1 | CORE | Backend-neutral bounded table pages and exact source-row mapping | CORE | Yes | Reusable paged table | [Dataset Preview](DATASET_PREVIEW_API_v1.md) |
| NATIVE2D_API_v1 | CORE | Native planar geometry, selection, drag lifecycle, atomic point-selection replacement and requested/effective aspect-aware views | `native2DEnsure` | Yes | No | [Native2D](../../core/native2d/README.md) |
| NATIVE_2D_GEOMETRY_API_v1 | CORE | Document/Session-scoped opaque retained Native2D geometry, exact Source intake, coordinate conversion, nearest-vertex snap, flat groups, affine copies, bridges, bounded comparison/pages and resources | `native2DGeometryOpen` | Yes: Python and Octave | No | [Scoped Native2D geometry](NATIVE_2D_GEOMETRY_API_v1.md) |
| WORKBENCH_RECOVERY_API_v1 | CORE host | Bounded atomic saved/checkpoint journal, corruption detection, resource retention and explicit recovery choices | `workbenchRecoveryBegin` | Intentionally host-only: lifecycle/filesystem/dialog authority | No | [Recovery](WORKBENCH_RECOVERY_API_v1.md) |
| NATIVE_3D_GEOMETRY_API_v1 | CORE | Document/Session/worker-scoped retained profiles, solids and meshes, complete resources, transforms, constraints, measurements and groups | `native3DGeometryOpen` | Yes: Python and Octave | Shared Native3D host | [Scoped Native3D geometry](NATIVE_3D_GEOMETRY_API_v1.md) |
| CURVE_WORKBENCH_API_v1 | viewer.curve_workbench | Dataset-backed and local planar curve workspaces, selection, edits, explicit transactional publication and persistence | `modulePublicApiActivate viewer.curve_workbench CURVE_WORKBENCH_API_v1` | Data services yes | Workbench | [Curve Workbench](CURVE_WORKBENCH_API_v1.md) |
| DATASET_VARIABLE_SCHEMA_API_v3 | CORE | Stable variable/dimension IDs, units, roles, coordinates | CORE | Yes | No | [Variable Schema](DATASET_VARIABLE_SCHEMA_API_v3.md) |
| DATASET_SELECTION_API_v1 | CORE | Persistent x-range/rectangle Selection | CORE | Yes | Selector GUI only | [Selection](DATASET_SELECTION_API_v1.md) |
| SESSION_INSPECTION_API_v1 | CORE | Session/Dataset/Selection inspection, verified payload and resource resolution | CORE | Yes | No | [Session Inspection](SESSION_INSPECTION_API_v1.md) |
| SESSION_PERSISTENCE_API_v1 | CORE | Commit the current framework-owned Manifest state | CORE | Yes | No | [Session Persistence](SESSION_PERSISTENCE_API_v1.md) |
| ANALYSIS_SOURCE_MAP_API_v1 / ACCESS_RUNTIME_v2 | CORE | Configured Analysis Source and stable Dataset/variable bindings | CORE / runtime | Yes | No | [Source Map](ANALYSIS_SOURCE_MAP_API_v1.md), [Access](ANALYSIS_SOURCE_ACCESS_RUNTIME_v2.md) |
| DATASET_PUBLICATION_API_v2 / FILE_PUBLICATION_API_v1 | CORE | Transactional schema-first and completed-file Dataset publication | CORE | Yes | No | [Publication](DATASET_PUBLICATION_API_v2.md), [File Publication](DATASET_FILE_PUBLICATION_API_v1.md) |
| PLOT_DATASET_API_v3 | plot.dataset | Current PlotSpec v2 facade, graph/Variant identity, render/rerender, artifacts, panels, snapshots | `modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3` | Yes for service operations | Editor only | [Plot Dataset v3](PLOT_DATASET_API_v3.md) |
| PLOT_DATASET_3D_API_v1 / v3 interactive facade | plot.dataset | Persistent graph source, fingerprint, independent Viewer representation, explicit Sync | Dedicated activation or v3 activation | Scene build and status yes | Open action | [Interactive 3D](PLOT_DATASET_3D_API_v1.md) |
| GRAPH_PROVIDER_API_v1 | CORE | Graph type/provider discovery and configuration contracts | CORE | Yes | Graphs Window only | [Graph Provider](GRAPH_PROVIDER_API_v1.md) |
| VIEWER_PROVIDER_API_v1 | CORE | Persistent scenes/layers, source binding, presentation, backend dispatch | CORE | Scene services yes | Open/rerender backend dependent | [Viewer Provider](VIEWER_PROVIDER_API_v1.md) |
| NATIVE_3D_VIEWER_API_v1 | viewer.native_3d | Named renderer controls, source selection, screenshot, explicit external compatibility | `modulePublicApiActivate viewer.native_3d NATIVE_3D_VIEWER_API_v1` | Discovery yes | Rendering yes | [Native 3D](../../plugins/modules/viewer.native_3d/NATIVE_3D_VIEWER_API_v1.md) |
| CONFIGURATION_API_v1 | CORE | Typed user/module configuration and paths | CORE | Yes | Configuration page only | [Configuration](CONFIGURATION_API_v1.md) |
| PROGRESS_API_v1 / cancellation | CORE | Structured progress events and run cancellation | CORE/runtime | Yes | Display only | [Progress](PROGRESS_API_v1.md) |
| PARALLEL_EXECUTION_API_v1 | CORE | Controlled parallel execution resources and lifecycle | CORE/runtime | Yes | No | [Parallel Execution](PARALLEL_EXECUTION_API_v1.md) |
| TABLE_STREAM_API_v3 / TABULAR_TEXT_API_v1 | CORE | Bounded canonical Dataset streams and acquisition text inspection | CORE | Yes | No | [Table Stream](TABLE_STREAM_API_v3.md), [Tabular Text](TABULAR_TEXT_API_v1.md) |
| DATASET_CURVE_FIT_API_v1 | viewer.dataset_curve_fit | Dataset filters, Native2D fit selection, eleven models, CORE acceptance and explicit publication | `modulePublicApiActivate viewer.dataset_curve_fit DATASET_CURVE_FIT_API_v1` | Fit services yes | Viewer controls | [Curve Fit](DATASET_CURVE_FIT_API_v1.md) |
| NUMERIC_API_v1 | math.numeric | Typed numerical operations, Dataset computation, operation metadata | `modulePublicApiActivate math.numeric NUMERIC_API_v1` | Yes | No | [Numeric module](../../plugins/modules/math.numeric/README.md) |
| MODULE_API_v1 / PLUGIN_INSTALL_API_v1 | CORE | Descriptors, dependency activation, installation lifecycle | CORE | Discovery yes | Optional UI | [Module](MODULE_API_v1.md), [Plugin Install](PLUGIN_INSTALL_API_v1.md) |

Public services return values or validated handles. They do not expose mutable
Dataset registries, raw Manifest keys, private graph arrays, or Native 3D host
protocol strings.

This version retains prior public contracts and adds generic numerical array
operations, Tabular Text API v1, source-row Graph Series filtering and family
expansion, and [Octave Script Bridge API v1](OCTAVE_SCRIPT_BRIDGE_API_v1.md).
The bridge discovers provider-owned script-callable bindings without
API-specific dispatch in CORE.
It also adds the [Scientific Library Manager API v1](SCIENTIFIC_LIBRARY_MANAGER_API_v1.md)
for independently distributed scientific data libraries.

## Public APIs added or expanded in 0.9.8.06

- [Octave Script Bridge API v1](OCTAVE_SCRIPT_BRIDGE_API_v1.md) provides stable
  Octave discovery, generic registered operation calls, execution context,
  typed value transport, and lifecycle for user-authored `.m` scripts.
- [Tabular Text API v1](TABULAR_TEXT_API_v1.md) inspects and streams generic
  delimited or whitespace text tables for acquisition modules.
- [Graph Series API v1](GRAPH_SERIES_API_v1.md) adds persistent source-row
  predicates and public family expansion. Normal family plots use bounded
  group preparation in plot.dataset.
- [Scientific Library Manager API v1](SCIENTIFIC_LIBRARY_MANAGER_API_v1.md)
  registers Library Type Providers and manages versioned, verified data packages.
- `NUMERIC_API_v1`, documented by `math.numeric`, adds reusable element-wise
  array arithmetic, comparisons, masks, selection, reductions and Dataset
  counterparts. Version 1.10.0 adds real/complex `linear_matrix` inspection,
  solve, decomposition and matrix functions to both script languages. API-owned
  script-callable operations are documented there.

## Public data and schema APIs

- [Canonical Dataset API v2](CANONICAL_DATASET_API_v2.md) is the authoritative
  access surface for registered CSV and HDF5 Datasets, including bounded range
  reads, uniform coordinates and storage capabilities.
- [Dataset Variable Schema API v3](DATASET_VARIABLE_SCHEMA_API_v3.md) defines
  stable variable and dimension identities, roles, units, value kinds, Use and
  implicit/uniform coordinate metadata. The v2 document remains relevant to
  older schema resources.
- [Dataset Metadata API v1](DATASET_METADATA_API_v1.md) owns persistent,
  namespaced per-Dataset metadata. Standard Octave consumers use the public
  [Analysis Source Dataset Metadata runtime extension](ANALYSIS_SOURCE_DATASET_METADATA_RUNTIME_v1.md),
  including `gxtxt_analysis_source_dataset_metadata` and
  `gxtxt_analysis_source_dataset_metadata_get`.
- [Dataset Selection API v1](DATASET_SELECTION_API_v1.md) owns persistent
  `x_range` and rectangular selections with stable Dataset/variable bindings.
- [Temporal Set API v1](TEMPORAL_SET_API_v1.md) owns persistent arbitrary
  `segment_set` and compact regular `window_set` resources. Standard Octave
  consumers use `gxtxt_temporal_set_from_runtime` and
  `gxtxt_temporal_set_member`; range generation remains a CORE responsibility.

## Public module/runtime access

- [Analysis Source Map API v1](ANALYSIS_SOURCE_MAP_API_v1.md),
  [Analysis Source Access Runtime v2](ANALYSIS_SOURCE_ACCESS_RUNTIME_v2.md) and
  the metadata runtime extensions provide stable primary, additional and
  dynamic source access to `standard_octave` modules.
- [Module API v1](MODULE_API_v1.md) and the current
  plugin interface specification
  define descriptors, bindings, configuration and standard runners.
- `standard_octave` public helpers in `core/octave/` provide INI/runtime reads,
  source/schema lookup, Table Stream access, Unit conversion, Temporal Set
  resolution and Publication v2. Modules must not parse session registries.
- [Table Stream API v3](TABLE_STREAM_API_v3.md) is the current table-shaped
  streaming facade over Canonical Dataset API v2. It supports selected
  variables, bounded chunks, ranges, typed numeric transport and independent
  resources.

## Public units and elapsed time

- [Unit Registry API v1](UNIT_REGISTRY_API_v1.md) and
  [Unit Dimension API v1](UNIT_DIMENSION_API_v1.md) own explicit compatible
  conversions. Identity-only semantic units remain non-convertible unless a
  documented reference exists.
- [Elapsed Time Contract v1](ELAPSED_TIME_CONTRACT_v1.md) states that parsed
  numeric `value_kind=elapsed_time` values are canonical seconds.
- [Elapsed Time Requested-Unit API v1](ELAPSED_TIME_REQUESTED_UNIT_API_v1.md)
  provides explicit compatible conversion from canonical seconds without
  changing source metadata or stored Dataset values. Public Octave failures use
  `GXTXT:ElapsedTimeUnit` for an unknown/incompatible requested unit.

## Public publication and graph APIs

- [Dataset File Publication API v1](DATASET_FILE_PUBLICATION_API_v1.md) is the
  direct, transactional service-module operation for publishing a completed
  UTF-8 or binary file as a Canonical Dataset. CORE owns staging, SHA-256,
  Session placement, Registry/Metadata commit, provenance and rollback.
- [Dataset Publication API v2](DATASET_PUBLICATION_API_v2.md) is the current
  transactional, schema-first publication API with Storage Auto, typed HDF5,
  bounded writes and provenance. Its
  [standard Octave binding](DATASET_PUBLICATION_V2_OCTAVE_BINDING.md) exposes the
  same lifecycle. In 0.9.7.62, `replace_owned=true` permits explicit
  same-producer replacement of a stable derived ID with artifact/registry
  rollback; omission remains create-only.
- [Graph Series API v1](GRAPH_SERIES_API_v1.md) owns persistent stable bindings
  between graphs and Dataset variables. Plot variants, workflow state,
  presentation and provider configuration use the Plot Module, Graph Workflow,
  Graph Configuration Extension, Axis Configuration Extension, Series Editor
  Extension and `PLOT_DATASET_API_v1/v2` documents in this directory.
- `plot.dataset` consumes these public graph/runtime contracts. Panel
  assignment, axis/style/title/layout configuration and variants are
  authoritative persistent state; generated PlotSpec/runtime/cache is derived.
  PlotSpec API v2 additionally supports statistically complete `histogram` and
  `box_whisker` series kinds. They read the complete finite Y sample rather
  than a display-decimated trace.


## Public interactive Viewer/document APIs

- [Viewer Provider API v1](VIEWER_PROVIDER_API_v1.md) owns Viewer provider
  discovery, persistent scene/layer presentation state and backend dispatch.
  Since 0.9.7.78 an optional provider `activation_api` enables lazy, idempotent
  backend activation through the existing Standard Module public-API loader;
  headless provider discovery does not activate desktop code.
- [Interactive Document API v1](INTERACTIVE_DOCUMENT_API_v1.md) owns
  authoritative UTF-8 Session-scoped interactive scientific documents with
  stable IDs, module/provider ownership, format/version metadata, SHA-256
  integrity, CRUD, enumeration and explicit corruption diagnostics. It is
  separate from Viewer presentation state and derived runtime/cache.

## Public acquisition, installation and registration

- [Acquisition Handler Plugin API v1](ACQUISITION_HANDLER_PLUGIN_API_v1.md) and
  its capability document define source inspection/import, binary sources and
  structured metadata. The additive `variable_schema` result field lets a
  handler declare stable Dataset Variable Schema v3 identities through CORE's
  Acquisition transaction.
- [Audio Decode API v1](AUDIO_DECODE_API_v1.md) is the CORE FFmpeg-backed
  bounded audio transport used by `analysis.audio_decode`; modules do not own a
  decoder cache or private media parser.
- [Plugin Install API v1](PLUGIN_INSTALL_API_v1.md),
  [Plugin Bundle API v1](PLUGIN_BUNDLE_API_v1.md), CORE Plugin Class v1 and the
  module descriptor contracts define discovery, registration, version checks,
  protection and lifecycle. Packages cannot choose arbitrary install paths or
  run installer scripts.

## Internal/private implementation surfaces

The following are not module APIs and must not be opened or edited directly:

- session sidecars and registries, including `metadata/datasets/*.ini`, Interactive Document internal storage,
  Dataset/Selection/Temporal Set/Graph Series registry files and provider-owned
  persistence files;
- Tcl↔Octave bridge framing, process handles, provider handles, bridge command
  argument layouts and temporary typed-binary transport files;
- generated `runtime.ini`, PlotSpec files, render caches, materialization
  caches, publication staging/backup files and module output working paths;
- CORE arrays/procedures that are not named by a public API document.

Authoritative persistent state produces derived runtime/cache. Recoverable
derived inconsistency is regenerated; unrecoverable inconsistency produces an
explicit diagnostic and recovery path. Module Reset must not delete persistent
user state.

## Retained compatibility surfaces

- Dataset Publication API v1 remains available for established consumers;
  new large/typed output should use v2. It is retained, not declared deprecated.
- Bare-path Table Stream v1/v2 calls remain compatible. Registered Dataset IDs
  and new consumers should prefer v3. The v2 elapsed-time numeric helper now
  follows the canonical-seconds contract.
- Existing single-source runtime keys and older Analysis Source metadata views
  remain compatible alongside indexed source maps.
- `PLOT_DATASET_API_v1` remains available beside additive v2 PlotSpec support.

Compatibility does not grant permission to depend on registry layouts, bridge
protocols or cache paths. Only documented public entry points are stable.

## GX-TXT 0.9.7.79 Session portability/export additions

- [Portable Session API v1](PORTABLE_SESSION_API_v1.md) owns validated,
  SHA-256-inventoried, transactional Session transport and dependency
  diagnostics.
- [Session Inspection API v1](SESSION_INSPECTION_API_v1.md) provides a public
  read-only structured Session snapshot for exporters and archival tools.
- [Session Action Provider API v1](SESSION_ACTION_PROVIDER_API_v1.md) provides
  descriptor-driven lazy Session-level actions for external modules without
  hard-coded CORE plugin identities.

## dev-051 additions

GRAPH_WORKFLOW_API_v1 adds `presentation_set`; GRAPH_SERIES_API_v1 adds bounded cached `distinct_values`; DATASET_PUBLICATION_API_v2 adds `publish_series`; DATASET_FILE_PUBLICATION_API_v1 adds `publish_auto`; NUMERIC_API_v1 adds `curve_model_fit`, `curve_model_evaluate`, `curve_model_project`. Existing Dataset schema updates accept coherent V2/V3 scientific metadata atomically. The new Graph Notes/Metadata and operational Plot Annotation services are registered CORE providers. Portable Resource is intentionally host-only. See provider-owned Script Bridge coverage for both languages.


## TASK-9 dev-052 final behavior

Current release: GX-TXT0.9.8.10-dev-052. TASK-9 adds Dataset Catalog/Transform/Preview capabilities, Curve Source, shared UI Field, scoped Native2D/Native3D Geometry, Interactive Document Resources, Scientific Recipe and Workbench Extension/Recovery services. The provider-derived `SCRIPT_BRIDGE_COVERAGE_v1.json` contains the final registered operations, language parity, host-only exceptions and remaining SB-014. Native bulk polar and Source snapshot validation are script-callable; Native3D export snapshot/controller and raw destination operations remain explicitly host-owned. See `docs/reports/TASK9_dev052.md` for implementation and acceptance mapping.


## dev-053 CAD workspace

Current release GX-TXT0.9.8.10-dev-053. Native2D adds scoped construction/preview/from-fit/controls/checked reference/candidate-edit/constraint driving and location operations with Python/Octave parity. Host effective-view gestures/clipping and immutable Dataset conversion acceptance are explicitly documented exceptions; existing Numerical and Canonical APIs remain the science/publication authorities. See current provider-derived SCRIPT_BRIDGE_COVERAGE_v1.json. SB-014 remains deferred and unchanged.

## dev109 integrated extensions under acceptance

This additive inventory records implementations, not final release acceptance.

| Existing family | Authoritative change | Verification scope |
| --- | --- | --- |
| Viewer Development / restricted C++ runtime | Retained Build artifacts and packaged binary execution; explicit Workspace presentation-text review | Installed runtime/compiler-free and development lifecycle receipts; integrated final gates open |
| Scientific Execution / Plot v4 | Provider-declared independent circuit axis and actual canonical schema binding without prior Discover | Three first-click installed wire Probes; independent saved-Plot reopen; zero runtime compilers |
| Native3D / Plot v4 | Original graph-provider scientific geometry recognition, exact mesh edges/colors and strict prepared-source lifetime | Historical thermal source-grounded GUI; original user Session unavailable; hidden Preview retest open |
| Dataset Preview | Predicate/grouping guidance and validation, meaningful predicates retained; hidden same-source controller retained | Actual typed filters/Help/nine exact rows and stale-wheel checks; latest hidden-controller fix awaiting GUI |
| Viewer GUI Host / EM / Native3D v2 | Typed original model/Job/Workspace form and exact planar cell-field presentation | Same restricted author candidate874915 and actual CORE field contract; installed GUI pending |
| Viewer Provider | Descriptor deprecation/replacement and conditional single launcher; original EM model dispatcher | Source integration only; installed catalog/legacy identity QA pending |

See dev109 regression notes,
authority catalog and the private exact
requirements ledger for failures, scope qualifications and all unfinished criteria.
