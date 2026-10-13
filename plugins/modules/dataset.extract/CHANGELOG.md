# dataset.extract changelog

## 1.3.0 — GX-TXT0.9.8.10-dev-052

Common Dataset Transform/selection authority with complete multi-source tuples/lineage and exact public ID publication.

# Changelog — dataset.extract

SPDX-License-Identifier: GPL-3.0-or-later

## 1.2.0

- Raised the minimum framework version to GX-TXT 0.9.7.19.
- Adopted the actual Dataset Publication API v1 schema-inheritance interface implemented by GX-TXT 0.9.7.19: `schema_source_dataset_id` plus ordered `schema_source_variable_ids`.
- Added a one-to-one source-variable mapping for every emitted CSV column in both `Variables=All` and `Variables=Trace` modes.
- Preserved the X == Y trace case as one output column with one source-variable mapping entry.
- Kept canonical variable names, units, and semantic roles explicitly declared while CORE inherits value, temporal, custom-unit, display, semantic-provenance, and instrument/channel interpretation.
- Kept source variable IDs strictly as lineage references; CORE assigns fresh dataset-scoped variable identities to the derived dataset in output-column order.
- Updated structured and published provenance with the schema source Dataset ID and ordered source variable IDs.
- Added explicit `unit_conversion=none` and `averaging=none` provenance flags in addition to the existing no-interpolation/no-resampling/no-alignment/no-sorting/no-synthetic-points policy.
- Replaced the former schema-gap reproduction test with positive GX-TXT 0.9.7.19 inheritance regressions covering normal, one-row, zero-row, reordered trace projection, X == Y projection, temporal/text/custom-unit/display/semantic/instrument metadata, and rebuilt output physical-column provenance.
- Marked the Dataset Publication schema-preservation CORE request from 1.1.0 as resolved by GX-TXT 0.9.7.19 without rewriting the historical 1.1.0 changelog.
- Kept one canonical source per run, Dataset Selection API v1 semantics, source read-only behavior, and all six row/variable workflows unchanged.
- No interpolation, resampling, alignment, sorting, join, averaging, consensus operation, unit conversion, or synthetic-point generation was added.

## 1.1.0

- Kept the 1.0.0 scientific architecture unchanged: canonical source -> row filter -> column projection -> new canonical derived dataset.
- Made `row_mode=all` fully independent of Dataset Selection state; no selection is parsed or required for this mode.
- Kept Dataset Selection support aligned with all current Dataset Selection API v1 row-filter types (`x_range` and `rectangle`) and delegated membership semantics to the public selection helper.
- Added structured `extract_provenance.ini` output.
- Expanded published provenance with source/output Dataset IDs, row/variable modes, selection identity/type/bounds, trace variable IDs, source/output row counts, row-order policy, and explicit no-interpolation/no-resampling/no-alignment/no-sorting/no-synthetic-points/no-source-mutation flags.
- Recorded source variable IDs and source runtime interpretation metadata for output variables as provenance without pretending that Dataset Publication API v1 can install them into the derived Dataset Variable Schema.
- Simplified the standard GUI by removing the streaming chunk-size control; the runtime keeps an internal/default compatibility value.
- Added one-row and zero-row regression coverage.
- Added exact six-mode row/projection regression coverage and wrong-dataset/missing-selection checks.
- Added a reproducible CORE test documenting Dataset Publication API v1 schema-transport loss for normal, one-row, and zero-row outputs.
- Refined the CORE request to a minimal backward-compatible Dataset Publication API v1 schema-inheritance mechanism.
- Documented the Standard Module API conditional-field presentation gap without adding host-specific GUI code.
- No interpolation, resampling, alignment, sorting, join, consensus operation, unit conversion, or synthetic-point generation was added.

## 1.0.0

- Initial release.
- Added materialization of Dataset Selection API v1 `x_range` and `rectangle` resources.
- Added row modes `all`, `selected`, and `unselected`.
- Added variable modes `all` and `trace`.
- Added standard X/Y bindings for trace-only export.
- Added Table Stream API v2 streaming reads and typed selection-coordinate handling.
- Added Dataset Publication API v1 output as a new canonical dataset.
- Added explicit no-in-place-mutation policy.
- Added provenance report and source-order preservation.
- No interpolation, resampling, sorting, join, alignment, or unit conversion is performed.
