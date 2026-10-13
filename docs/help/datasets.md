# Datasets

Each imported or computed Dataset has a stable ID, scientific contract, variable schema and provenance. Acquisition preserves the RAW source and publishes canonical data; analysis modules publish further Datasets through the Dataset Publication API.

Inspect and edit variable labels, units, semantic roles and Use flags through the Dataset view. These interpretation changes do not rewrite the original source. Attach scientific notes to a Dataset when needed; they remain separate from producer metadata.

Analysis modules select Datasets by ID, and modules with several inputs use a source map. A source map selects inputs; scientific alignment, joins and resampling remain explicit operations.

See [Acquisition / Import](acquisition.md) and [Analysis modules](analysis.md).

## Explicit publication and Dataset ZIP (dev-051)

Dataset ZIP... exports/imports one canonical Dataset, preserving payload format, scientific schema, metadata and notes. Import reviews integrity and collisions; choose a new ID to retain both resources. Fitter samples do not appear here until explicitly published. Curve Fit Publish as Dataset creates a new result Dataset; accepting a CORE curve is a separate operation. See [publication guide](../guides/PUBLISHING_MODULE_OUTPUT_AS_DATASET.md).
