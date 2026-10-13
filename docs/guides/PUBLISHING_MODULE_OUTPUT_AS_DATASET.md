# Publishing module output as a dataset

Use Dataset Publication API v1 when an analysis module already generates a
complete file that another module should consume through the normal Dataset
Registry / Analysis Source Map APIs.

For a new producer that needs bounded chunks, append, typed HDF5 output,
multidimensional variables, or hyperslabs, use
[Dataset Publication API v2](../api/DATASET_PUBLICATION_API_v2.md). Declare
Dataset, Variable, and Dimension IDs and write through the generic CORE
writer. Do not select backend objects or edit `metadata/datasets.ini`.

Do not write `metadata/datasets.ini` from plugin code.

Minimal Octave flow:

```octave
% 1. calculate data
% 2. write output file under output_dir
% 3. request publication
meta=struct('variables',{{'x','y'}}, ...
            'units',{{'V','mA'}}, ...
            'semantic_roles',{{'independent','measure'}}, ...
            'source','module calculation', ...
            'provenance','derived from primary source');
gxtxt_dataset_publish_request(output_dir,'my.derived.dataset','table.generic','csv','derived.csv',meta);
```

After the module exits successfully, GX-TXT validates the request, computes SHA-256, registers the dataset, saves `metadata/datasets.ini`, and refreshes dataset-aware GUI controls.

See `docs/api/DATASET_PUBLICATION_API_v1.md` for the normative contract.


## Rendering the published result

After publication, a new analysis module can use the CORE `PLOT_DATASET_API_v2` service to create Graph Series from the resulting stable `dataset_id + variable_id` pairs, render them, and retrieve artifacts. This service remains available when the `plot.dataset` user interface is disabled. See [the API manual](../api/PLOT_DATASET_API_v2.md). Use a custom renderer only when the visualization is not sufficiently supported by the standard API.

## Preserve source variable interpretation on pure subsets

When a module only filters rows or projects columns, pass source
Dataset ID and stable variable IDs through Dataset Publication API v1:

```octave
meta.variables = {'voltage','elapsed'};
meta.units = {'mV','s'};
meta.semantic_roles = {'measured','elapsed_time'};
meta.schema_source_dataset_id = 'capture.original';
meta.schema_source_variable_ids = {'v0004','v0001'};
gxtxt_dataset_publish_request(output_dir, 'capture.filtered',
    'timeseries.table', 'csv', 'filtered.csv', meta);
```

The order must match the output CSV header. CORE validates the mapping
and preserves interpretation metadata, including elapsed/absolute time,
text, decimal convention, canonical-unit formulas, display labels, and
semantic provenance. The derived dataset receives its own variable IDs
and output physical-column metadata. This mechanism is for value-preserving
subsets; a module performing scientific conversion must declare its new
schema explicitly.

## Series and completed files (dev-051)

Use public `datasetPublicationV2PublishSeries` / Bridge `DATASET_PUBLICATION_API_v2/publish_series` for X/Y results with stable Variable IDs, full scientific declarations and structured metadata. Storage may be CSV or HDF5. The full schema-first API remains appropriate for other shapes. Complete V2 declaration fields and V3 scientific fields are validated and committed together.

Use `datasetFilePublicationPublishAuto` / Bridge `DATASET_FILE_PUBLICATION_API_v1/publish_auto` for an already completed PNG, PDF, audio, mesh/CAD/chemistry or other file. Contract is explicit; extension/MIME and supported registries provide actual format metadata. A script source must belong to that execution's output directory. Opaque files are not flattened into CSV. See the API documents for runnable declarations.

Built-in Curve Fit samples, accepted CORE curves, Session Datasets and explicitly published fit/sample Datasets have distinct identities. Accepting a fit does not publish a Dataset. Publication is an explicit action with scientific model/source/filter/output-grid metadata. Export CSV has a `.metadata.ini` provenance sidecar.
