# Plot Dataset API v4

Native Plot v4 is an additive public API. PlotSpec v2, Graph Series, Variants, Dataset schemas, canonical values and physical units retain their existing public authorities. Activate `PLOT_DATASET_API_v4` through the Module API; the namespace is `::GX::PlotDatasetAPIv4`. APIs v1/v2/v3 remain available with their original implementation.

The v4 facade preserves the public v3 lifecycle/specification operations and exposes native `widgetCreate path spec ?context?`, `widgetConfigure`, `widgetDraw`, `widgetHit`, `widgetView`, `widgetEdit`, `widgetExport`, `widgetDestroy` and `widgetReceipt`. Native2D C++ retains a disposable typed view and projects through CORE C geometry to the shared native Cairo/Tk surface. Source access uses bounded public Curve Source/Table Stream services; full source extrema remain independent of display reduction. Hit receipts retain exact source-row strings, including uint64 values above 2^53.

A widget context containing `prepared_model 1` accepts an explicit disposable native presentation model; it does not publish scientific data. Canonical plot publication requires actual Dataset identities. Wheel zoom, middle-button pan and double-click complete fit change presentation only. Grid lines and labels use the same numeric ticks from the existing CORE axis authority.

Public Graph Metadata records `renderer_owner=PLOT_DATASET_API_v4` and `renderer_owner_api_version=1`. This selects native render, capture and portable dispatch without rebinding legacy sources.

`captureForArtifact artifact directory` captures complete public portable Dataset archives and a data-only `native_v4_snapshot.tcldict` manifest. `snapshotValidate`, `snapshotCopy`, `renderSnapshot`, `snapshotPresentationFields` and `snapshotPresentationSet` preserve the scientific capture after source deletion. Rendering imports into a newly owned disposable Session; no caller Session is changed. SHA and public ZIP validation precede use.

Python and Octave use the existing `gxtxt_api_call` interface under `PLOT_DATASET_API_v4`, with the same operation names and argument/result conventions as v3. No additional SDK is required. The finite parity matrix and focused receipts document actual verification; unsupported or unverified work is never reported as PASS.

## Exact cell-associated triangular fields

`cellFieldSpec cellDatasetId centroidXVariableId centroidYVariableId binding ?title?` constructs a canonical PlotSpec with an explicit `cell_field` extension on its stable series ID. Python and Octave call `cell_field_spec` with the same five operands (title optional). The binding is an inert dictionary with exactly these fields:

```
schema GXTXT_CELL_FIELD_BINDING_v1
nodes_dataset_id canonicalNodeDataset
node_id_variable_id stableIntegerNodeId
x_variable_id nodeCoordinateX
y_variable_id nodeCoordinateY
cell_id_variable_id stableIntegerCellId
node_variable_ids {firstNodeId secondNodeId thirdNodeId}
scalar_variable_id cellAssociatedScalar
```

All names resolve through actual Variable Schema v3; no physical column positions or producer-specific headers are assumed. Connectivity contains three distinct existing node IDs. Node and cell identities are unique, coordinates and scalar values finite, triangles nondegenerate. Clockwise and counterclockwise source orientation are both retained. Node coordinate units are converted through the existing public coordinate context. The complete exact node domain determines bounds independently of scalar samples or display reduction. Colors are constant within each source cell; there is no Delaunay triangulation, nodal interpolation or implicit averaging of unrelated values. Picking returns the actual cell ID, source-row ordinal, scalar variable ID, value and unit.

Canonical Graph Metadata retains the binding by stable series identity alongside the renderer-owner marker. A missing required binding fails explicitly; it cannot silently become a scatter plot. Complete scientific snapshots, Clones and portable graphs include both canonical node and cell Datasets and their exact role dependencies. Current bounded projection supports at most 60,000 nodes and 30,000 cells. Filters, grouping and row selection on this extension require an explicitly published canonical submesh; unsupported selections fail rather than changing topology silently. Other native plot kinds retain their existing behavior. A host without the `native_cell_field` capability rejects the binding.
