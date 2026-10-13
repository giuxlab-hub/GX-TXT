# GX-TXT dataset.extract 1.3.0

SPDX-License-Identifier: GPL-3.0-or-later

## Purpose

Dataset Extract uses CORE Dataset Transform to publish one new derived Dataset from a canonical source or a saved multi-source Selection. Its requested public Dataset ID is validated and collision-checked. All/Selected/Unselected and All/Trace are explicit row/column policies; compatible sources preserve complete typed tuples, and heterogeneous curves produce long families with explicit member lineage. Every original source remains read-only. A multi-source Selection stores independent source rows and explicit X/Y bindings, never reuses one source's bounds on another.

This version requires GX-TXT0.9.8.10-dev-052 and its public Dataset Transform transport. No scientific join/filter/publication implementation is duplicated in the plugin.

## User controls

The standard module UI contains:

```text
Source dataset
Rows:       All | Selected | Unselected
Selection:  Dataset Selection resource
Variables:  All | Trace
Trace X
Trace Y
Output Dataset ID
```

`Selection` is required only for `Selected` and `Unselected` rows.

`Trace X` and `Trace Y` are required only when `Variables=Trace`.

Standard Module API v1 currently has no public conditional enable/hide rule for fields or bindings, so these conditional controls are labelled explicitly rather than implemented with private Tk code. See `CORE_STANDARD_MODULE_CONDITIONAL_UI_GAP.md`.

## Row modes

### All

Every source row is retained. No Dataset Selection is required or read by the runtime operation.

### Selected

Only rows inside the selected Dataset Selection are retained.

### Unselected

Only rows outside the selected Dataset Selection are retained.

Selection semantics remain entirely owned by Dataset Selection API v1. The module validates that the resource belongs to the selected source Dataset ID and delegates membership to `gxtxt_selection_mask()`.

The output row order is always the original source order.

## Variable modes

### All

All active canonical columns of the source dataset are published in canonical-table order.

A source variable with `Use=no` is not a physical column in the canonical table and is therefore not materialized. `dataset.extract` does not reach behind the canonical dataset into RAW or excluded data.

When all active canonical variables are preserved, the source dataset contract is retained.

### Trace

Only the chosen standard X/Y bindings are published. Bindings are resolved through stable GX-TXT dataset-scoped variable identity.

If X and Y resolve to the same canonical variable, that variable is emitted exactly once and the schema-inheritance mapping contains exactly one source variable ID.

Trace projection is published as `table.generic`, because removing other columns can invalidate a more specific source contract.

## Dataset Selection support

`dataset.extract` consumes Dataset Selection API v1 resources and does not depend on the graph viewer.

Dataset Selection API v1 currently defines:

```text
x_range
rectangle
```

The module advertises those API-defined types and invents none.

Every non-`All` operation validates:

```text
selection.source_dataset_id == source dataset_id
```

A selection from another dataset is rejected. `row_mode=all` deliberately ignores selection runtime state.

## Output Dataset ID

The output Dataset ID must be valid and must differ from the source Dataset ID.

Dataset Publication API v1 permits the owner module to republish a Dataset ID that it already owns. GX-TXT 0.9.7.19 does not expose a create-only publication option, and this module does not inspect private Dataset Registry state to emulate one.

## Dataset Publication schema inheritance

GX-TXT 0.9.7.19 extends Dataset Publication API v1 with two optional fields:

```text
schema_source_dataset_id
schema_source_variable_ids
```

Dataset publication uses both fields.

For each output CSV column, `dataset.extract` sends the source identity:

```text
source_dataset_id + source_variable_id
```

in exactly the same order as:

```text
meta.variables
CSV header columns
```

The mapping is one-to-one. Missing or duplicate source variable IDs are rejected by the module before publication, and CORE performs its own authoritative validation.

CORE then creates fresh dataset-scoped identities in output-column order:

```text
source:   source_dataset_id + source_variable_id
                          |
                          | schema inheritance
                          v
derived:  new_dataset_id + new_variable_id
```

Source variable IDs remain lineage references only. They never become the identities of the derived dataset.

## Preserved schema interpretation

`dataset.extract` continues to publish canonical variable names, units, and semantic roles explicitly. Dataset Publication API v1 schema inheritance then preserves the source interpretation fields implemented by GX-TXT 0.9.7.19:

```text
unit
canonical_unit
to_canonical
from_canonical
display_label
semantic_role
semantic_source
semantic_reason
instrument_id
instrument_channel
value_kind
value_format
decimal_separator
time_reference
time_origin
```

The output file owns its physical layout. CORE rebuilds:

```text
source_column
canonical_position
original_header
canonical output name
canonical delimiter
```

from the generated CSV. Source physical-column provenance is not copied when it no longer describes the derived file.

No row values are transformed by schema inheritance. In particular, schema inheritance performs no unit conversion.

## Zero-row and one-row outputs

A derived CSV always contains its header. Therefore a valid extraction may contain:

```text
header + one row
```

or:

```text
header only
```

GX-TXT 0.9.7.19 schema inheritance preserves the same explicit scientific interpretation in normal, one-row, and zero-row outputs. Metadata preservation no longer depends on value inference.

## Provenance

Every successful run writes:

```text
extract_report.txt
extract_provenance.ini
```

and publishes a compact provenance summary with the derived canonical dataset.

The provenance records source/output Dataset IDs, row and variable modes, selection identity/type/bounds, trace X/Y identities, source/output row counts, ordered source variable IDs corresponding to output columns, and the schema source mapping used by Dataset Publication API v1.

It also records these explicit scientific-operation policies:

```text
row_order=preserved
interpolation=none
resampling=none
alignment=none
unit_conversion=none
averaging=none
sorting=none
synthetic_points=none
source_mutation=none
```

## Multi-source policy

Selected/Unselected resolves each saved member through the common Selection and Transform APIs. All uses the configured primary Dataset. One run produces one explicit Dataset and complete request/effective-operation provenance; no implicit interpolation or source mutation occurs. See the final workflow below.

## Framework APIs used

- Standard Module API v1
- Analysis Source Map API v1
- Analysis Source Metadata Runtime v1
- Dataset Selection API v1
- Dataset Variable Schema API v2
- Table Stream API v2
- Dataset Publication API v1, including GX-TXT 0.9.7.19 schema inheritance
- Plugin Progress API v1
- Plugin Install API v1
- Documentation API v1

## Tests

See `tests/README.md` and `TEST_REPORT.md`.

## Shared Transform and multi-source Selections

Dataset Extract provides All/Selected/Unselected and All/Trace controls. Selected/Unselected accepts a saved multi-source Selection from
Graphs → Select data → Save Selection. One run publishes exactly one output
Dataset using the entered public Dataset ID. Each source/member keeps its own
row selection and filters. Compatible tables retain every selected column;
heterogeneous curves become a long family with complete lineage. Trace projects
each member's explicit X/Y binding. All rows uses the configured primary Dataset
and ignores a stale Selection. A primary source is optional when a saved
multi-source Selection supplies the sources.

The Octave entrypoint delegates all scientific data operations to the public
CORE Dataset Transform authority. It emits `extract_report.txt` and
`extract_provenance.ini`; the output Dataset's structured `transform.manifest`
and `transform.effective` metadata contain the complete request, source hashes,
variable mapping, compatibility decisions and actual storage provider. Source
Datasets remain unchanged. Collisions reject publication with the requested ID.
