# P010 public API contracts

P010 extends existing authorities. This document is a current functional contract;
the owner withdrew the earlier pre-implementation API-inventory requirement.
Retrospective documentation is not evidence of that withdrawn temporal rule.
Independent executed coverage is in the accompanying candidate/release matrices.

| Contract | Surface and ownership |
| --- | --- |
| DATASET_EXPORT_PROVIDER_API_v1 | CORE host list/describe/check/invoke; metadata-only enabled-provider discovery, canonical schema/capability admission and create-only File Publication. No Script Bridge writer. |
| SKETCH_DXF_EXPORT_API_v1 | Enabled export.sketch_dxf provider, exact geometry.sketch v1 through original Sketch/Unit owners. Source preserved, explicit physical output scale, finite reference intent; unsupported geometry/units fail. |
| PLOT_RENDER_SETTINGS_API_v1 | CORE info/status/read host and original Python/Octave Bridge; typed nested producer snapshot bound to exact successful PNG. No configuration writer. |
| PLOT_RENDER_SETTINGS_SNAPSHOT_v1 | Per-provider-graph/Variant last-render evidence from original v3/Native2D/Native3D producers; separate from authoritative mutable PlotSpec. |
| PLOT_CLONE_RENDER_SETTINGS_v1 | Distinct Clone source/capture/last-render lifecycle. Missing/partial/rendered-only evidence remains explicit. |
| PLOT_PRESENTATION_PROFILE_v1 | Bounded trusted-host/GUI graphics/legend/layout and compatible positional series styles; named Session presets/JSON. Original target configuration/PlotSpec owners commit. No Bridge writer or portable numeric-axis transfer. |
| MATHEMATICS_EXPLORER_API_v1 | Existing binding extended consistently for schema2 while preserving schema1 operations and execution/source/lifetime guards. |

Mathematics `initialState2` returns inert named declarations. Existing
`validateState`, `calculate`, persistence and publication dispatch schema1/2.
`integralOfSelected` consumes an execution-held computed ID in Bridge;
`analyzeSelected` accepts selected scope, mode, explicit partner and optional study
subinterval. Numeric arrays retain original SDK column-array contracts. Empty
text/arrays, numeric and Boolean fields use the original typed JSON authority.
Computed IDs and source receipts cannot be forged from caller dictionaries or
reused across changed declarations, source revisions, executions or Sessions.

Schema2 uses distinct native Workspace provider `mathematics_explorer_v2`, format
version2. Provider1/schema1 is neither weakened nor silently migrated. Declarations
are separate from transient sample buffers. Publication preflights create-only IDs
and creates one canonical Dataset per admitted connected component through
Publicationv2; later failure reports already committed receipts. Original Plotv4
owns graph output. Unit context changes require recomputation.

Expression grammar/functions/dimensions, grid/mask/selection, matrix solving and
numerical calculus belong to existing Numeric/Unit owners. No private evaluator,
solver, renderer, fit engine or executable callback is introduced. Host Tk/window,
raw directory and callback operations stay host-only. New Plot settings Bridge
operations remain strictly read-only; existing permitted Plot APIs keep their
original write contracts.

See detailed [Mathematics model](docs/api/MATHEMATICS_EXPLORER_MODEL_v2.md),
[Mathematics API](docs/api/MATHEMATICS_EXPLORER_API_v1.md),
[Dataset export](docs/api/DATASET_EXPORT_PROVIDER_API_v1.md),
[render settings](docs/api/PLOT_RENDER_SETTINGS_API_v1.md) and
[portable presentation](docs/api/PLOT_PRESENTATION_PROFILE_v1.md) manuals.
