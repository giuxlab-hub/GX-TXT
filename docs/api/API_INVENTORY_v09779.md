# GX-TXT API Inventory — v0.9.7.79

SPDX-License-Identifier: GPL-3.0-or-later

This is the current consolidated inventory for module authors and maintainers.
It distinguishes public contracts from implementation details and retained
compatibility paths. Historical `API_INVENTORY_v*` files remain release deltas.

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
  [plugin interface specification](GXTXT_PLUGIN_MODULE_INTERFACE_SPEC_v092.md)
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
  structured metadata.
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
