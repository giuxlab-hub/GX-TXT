# Dataset Variable Schema API v2

SPDX-License-Identifier: GPL-3.0-or-later

Introduced in GX-TXT 0.9.7.3. This is an additive extension of Canonical Dataset API v1 and Dataset Inspection / Variable Mapping API v1. Dataset ID, contract, Module IDs, RAW provenance, and existing name-based bindings remain valid.

## Identity and state

Every source variable, including `enabled=0` / Use=no, has a dataset-scoped immutable `variable_id`. The registry stores `varN_variable_id` for every source slot; `v0001`, `v0002`, etc. are assigned to legacy datasets on migration and retained across save/reopen and canonical rename. Callers must pair a `variable_id` with its Dataset ID. Variable names remain a compatibility lookup, never permanent identity.

Public Tcl API:

```tcl
::GX::datasetVariableSchema dataset_id
::GX::datasetVariableById dataset_id variable_id
::GX::datasetVariableResolve dataset_id variable_id_or_legacy_name
::GX::datasetVariableSchemaUpdate dataset_id {variable_id {field value ...} ...}
```

`datasetVariableSchema` returns ordered dictionaries for all source variables. `canonical_position` is derived: it is the 1-based physical column in the current canonical CSV for enabled variables, and empty for excluded variables.

Read-only provenance: `source_raw`, `source_sha256`, source acquisition metadata, `source_column`, `source_channel`, `original_header`, and `variable_id`. Editable schema: `enabled`, `canonical`, `unit`, `semantic_role`, instrument associations, `value_kind`, `value_format`, `decimal_separator`, `time_reference`, and `time_origin`.

`value_kind=number|text|elapsed_time`. For elapsed time, `value_format=hms` accepts `HH:MM:SS[.fraction]` or `HH:MM:SS[,fraction]`; hours may exceed 23. At the public numeric boundary, every supported HMS elapsed-time value is normalized to **seconds**, regardless of whether the compatible source declaration is `unit=s`, `min`, or `h`. The source unit remains schema metadata and does not rescale the normalized elapsed-time number. Consumers that need another temporal representation use [Elapsed Time Requested-Unit API v1](ELAPSED_TIME_REQUESTED_UNIT_API_v1.md), which converts explicitly from canonical seconds without mutating this schema. `time_reference=elapsed` means duration from the dataset's own origin. `time_origin` is an optional declared origin for future cross-dataset alignment. `time_reference=absolute` and a declared origin are metadata only in v2; this API does not align, resample, join, or change scientific algorithms. See [Elapsed Time Contract v1](ELAPSED_TIME_CONTRACT_v1.md).

`ppm` and `pH` are identity-only semantic units in the Unit/Dimension API; v2 does not infer concentration bases or logarithmic pH transforms.

`decimal_separator=.` or `,` controls strict numeric parsing. The migration infers HMS only when sampled values consistently match HMS and the unit is s/min/h. It infers decimal comma only when sampled values make decimal interpretation unambiguous (a fractional width other than exactly three digits). Ambiguous legacy values yield NaN until explicitly configured; they are never silently read as thousands-grouped numbers.

## Persistence and migration

`metadata/datasets.ini` remains registry `api_version=1` and adds `variable_schema_api_version=2`, variable fields, `canonical_delimiter`, `source_delimiter`, and `source_header_rows` where known. Old records are accepted and enriched in memory. The next schema save or module runtime generation persists the additive fields. Legacy name bindings are resolved to IDs and written to additive Manifest Format 2 sections `[module_binding_variable_id.<module>]`, `[variable_reference_id.<module>]`, and `[repeatable_variable_id.<module>.<table>.<row>]`. The existing name fields are retained for old consumers. Runtime source-variable sections expose `variable_id` and typed-value metadata; `gxtxt_analysis_source_variable_meta` resolves either ID or legacy name.

The imported Variables GUI edits canonical schema on any selected dataset. RAW provenance fields are read-only. `RAW #` is the physical source column; `Canonical #` is the current canonical position. Excluded RAW fields remain available with Use=no and never count as active canonical variables or duplicate names.

## Mutation and integrity

Unit, semantic role, and interpretation edits update registry metadata without rewriting the canonical file. Rename or Use changes regenerate a CSV canonical dataset with a new checksum. For generic CSV, regeneration reads the verified RAW snapshot using saved source delimiter and header-row count. Other CSV datasets retain an immutable, checksum-verified `schema_source_snapshot` of their current canonical columns before the first structural edit. This derived snapshot supports rename, exclude and later re-enable of columns that were active at snapshot creation, including published datasets without a RAW provider. It is not RAW provenance and cannot restore a column already omitted before the snapshot. Importers that can reconstruct omitted variables from their RAW format register a CORE callback:

```tcl
::GX::datasetSchemaRegisterRegenerator source_module command_prefix
```

The callback receives `dataset_id raw_path temporary_output delimiter header_rows active_map`, where `active_map` is a list of `{source_column canonical_name}` pairs. It writes only the temporary canonical output; CORE verifies RAW/canonical checksums, commits the result and persists metadata. `acq.generic_csv` registers its existing canonicalizer through this API. Re-enabling a column absent from both the snapshot and current canonical file without a registered provider is rejected explicitly. Before a rewrite the existing canonical checksum and, when used, RAW checksum are verified. Failed validation rolls back registry, manifest, bindings, and canonical bytes.

The API rejects duplicate active names, invalid canonical identifiers, edits to provenance, non-CSV structural edits, and structural updates that would leave no active variable. Published binary datasets have no variable rows unless their provider declares variables.

## v0.9.7.4 reversible canonical snapshot

A snapshot lives under `metadata/schema_sources/<dataset-id>.csv`. The registry persists `schema_source_snapshot`, `schema_source_snapshot_sha256` and each captured variable's `varN_schema_snapshot_column`. Snapshot bytes are immutable; every rewrite verifies its checksum. CORE creates the snapshot only when a structural edit cannot use a registered RAW provider. A failed edit removes a newly created snapshot and restores the previous canonical, registry and manifest files. RAW source paths and hashes remain unchanged.

## v0.9.7.6 semantic provenance and contextual GUI

Each source variable, including Use=no, also persists `semantic_source` and
`semantic_reason` by stable ID. A nonempty legacy/importer role is preserved;
Auto applies explainable inference. User overrides remain authoritative across
subsequent unit/name/kind changes and plugin unavailability. Consumers should
use `datasetVariableSemantic` and `datasetVariablesBySemanticRole` from
Semantic Registry API v1, rather than inspect registry internals.

In imported Variables, Semantic role is an editable combo with current
registered roles and custom input. The source and inference/choice explanation
are visible. Time reference, origin and HMS format are active only for enabled
elapsed-time variables. `Source decimal` denotes the serialized source value
separator; CORE numeric values always use a dot decimal internally.

## v0.9.7.7 custom unit relation

The schema adds `canonical_unit`, `to_canonical`,
`from_canonical`, and `display_label` to each variable. An optional
canonical unit requires both safely parsed formulas. Unit and role remain
editable independently. Variables contains an integrated help panel that
explains all schema, provenance, decimal, semantic and temporal fields.

For a practical Variables-window and plugin workflow, including Use=no/Use=yes, RAW vs canonical positions, stable bindings and an Octave typed-read example, see [GX-TXT Variables Guide](../guides/VARIABLES_GUIDE.md).


## GX-TXT 0.9.7.12 base module binding identity

For Standard Module input bindings, the additive
`[module_binding_variable_id.<module_id>]` manifest section stores
`source_id|dataset_id|variable_id`. The source ID is a logical route; the
Dataset ID is part of variable identity and must not be inferred from the
source at resolution time. The visible `source.name` binding remains for
legacy consumers and presentation. Runtime `[bindings]` names are resolved
from the stored Dataset ID and variable ID before writing `runtime.ini`.

If a source is mapped to a different Dataset, the old binding is unresolved
until the user explicitly selects a variable. An equal variable ID in the new
Dataset is never sufficient. Rename follows the stored ID; Use=no preserves
the identity but resolution reports the unavailable variable. The framework
preflights bindings before opening `runtime.ini`, so a failed resolution
does not leave a partially rewritten runtime file.

Legacy `source_id|variable_id` entries are read. Migration is conservative:
the current Dataset, variable ID and historical visible name (or original
header) must identify one candidate among known datasets. Otherwise the
binding stays unresolved and requires an explicit selection. Old name-only
records remain readable through the existing compatibility path; new
bindings are persisted with Dataset-qualified IDs.
