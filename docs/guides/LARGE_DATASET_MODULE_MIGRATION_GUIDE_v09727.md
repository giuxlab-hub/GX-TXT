# Large Dataset module migration guide

Read registered data with Canonical Dataset API v2 using Dataset and Variable IDs. Use Table Stream API v3 for selected columns and bounded chunks of a flat table. Use Canonical range or hyperslab calls for n-dimensional data.

Publish new scientific results with Dataset Publication API v2. Declare hard storage capabilities and optional preferences; let Storage Auto choose the provider. A module must not choose HDF5 as scientific policy, implement CSV to HDF5 conversion, or create its own acceleration cache.

Request selected variables explicitly. Request row ranges through Canonical Dataset or Table Stream. For direct range access, request random_access through datasetAccessRequest; CORE reuses the current provider or a valid materialization.

Use Schema v3 rank, shape, dimensions, coordinates, groups and components for n-dimensional data. Do not flatten it for Table Stream.

Legacy CSV workflows remain supported through bare-path Table Stream v1/v2 and whole-table helpers. A legacy executable that truly requires a CSV path may use datasetCompatibilityCsv only for a lossless flat table. Modern migrations should use Dataset and Variable IDs.

## standard_octave publication

Use the gxtxt_publication_v2 helpers documented in DATASET_PUBLICATION_V2_OCTAVE_BINDING.md. The persistent bridge exposes the existing Publication v2 lifecycle and Storage Auto. Do not assemble a full output table or create an intermediate CSV.

## Generic audio decode

Use Audio Decode API v1 and its Octave helpers for codec probing and bounded frames. Scientific amplitude, variable selection and dataset publication remain module decisions.

## GX-TXT 0.9.7.30 note

Modules using the standard Octave Publication v2 binding receive typed numeric transport automatically. Keep using bounded chunks and the existing full, range, append, or hyperslab operations. No module-side encoding or API migration is required.
