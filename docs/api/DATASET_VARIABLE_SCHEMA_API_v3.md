# Dataset Variable Schema API v3

SPDX-License-Identifier: GPL-3.0-or-later

Dataset Variable Schema API v3 adds typed and multidimensional metadata to the
stable `dataset_id + variable_id` model from API v2. The existing
`datasetVariableSchema` operation keeps its v2 result fields. New consumers use
`datasetVariableSchemaV3` and `datasetVariableV3ById`.

## Additive fields

| Field | Meaning |
| --- | --- |
| `dtype` | Logical numeric or string element type. |
| `rank` | Number of array dimensions; zero denotes a scalar. |
| `shape` | Semicolon separated dimension sizes in storage order. |
| `dimension_ids` | Stable logical dimension IDs in the same order. |
| `coordinate_variable_ids` | Stable coordinate variable relationships. |
| `coordinate_role` | `data`, `coordinate`, or `auxiliary`. |
| `axis_kind` | `explicit`, `uniform`, or `none`. |
| `axis_origin` | First value of a uniform coordinate. |
| `axis_step` | Nonzero increment of a uniform coordinate. |
| `axis_count` | Logical value count of a uniform coordinate. |
| `component_ids` | Stable variable IDs belonging to a vector/component set. |
| `group_id` | Logical group identity. |

Uniform axes require numeric origin and step plus a nonnegative integer count.
Shape and dimension lists must contain exactly `rank` entries. Relationships
reference stable variable IDs in the same logical dataset.

## Public operations

```tcl
set variables [::GX::datasetVariableSchemaV3 $datasetId]
set pressure [::GX::datasetVariableV3ById $datasetId v_pressure]
::GX::datasetVariableSchemaV3Update $datasetId [dict create \
    v_pressure [dict create dtype float32 rank 2 shape {100;5000} \
        dimension_ids {time;cell} coordinate_variable_ids {v_time}]]
```

API v3 metadata can describe tables, regular coordinates, matrices, fields,
mesh coordinates, trajectories and vector components. It does not assign CFD
meaning; domain plugins use the Semantic Registry for scientific roles.

CORE storage adapters may keep a private provider locator for each stable
variable ID. `datasetStorageMapVariable` is a CORE integration operation. The
locator is omitted from public schema and runtime records so an HDF5 path never
becomes scientific identity.

## Compatibility

Schema v2 consumers continue to receive the original v2 dictionary. Existing
CSV datasets acquire safe v3 defaults only when the v3 API is queried. `Use=no`
variables retain their stable variable IDs and may carry v3 metadata.

Acquisition Handler Plugin API v1 may now return an optional
`variable_schema` declaration with its canonical Dataset descriptor. CORE
validates and registers those stable IDs and v3 fields in the same Acquisition
transaction as the RAW source, canonical payload and structured metadata.
Without a declaration, the prior generated variable-ID behavior remains.

## Octave Script Bridge

Bridge API ID: `DATASET_VARIABLE_SCHEMA_API_v3`. `list` accepts
`{dataset_id}` and returns a cell of variable descriptor structs. `get`
accepts `{dataset_id, variable_id}` and returns one descriptor struct. Both
operations use the current Session and preserve the normal stable Dataset
variable identities. For example:

```octave
v = gxtxt_api_call('DATASET_VARIABLE_SCHEMA_API_v3', 'get', ...
                   {'sample', 'v0001'});
```

## Coherent scientific schema transaction (dev-051)

`::GX::datasetVariableSchemaUpdateCombined dataset_id changes` is the complete public mutation transaction. `changes` maps stable Variable IDs to mutable V2 scientific fields and V3 typed/dimensional fields. Both Script Bridge languages expose it as `DATASET_VARIABLE_SCHEMA_API_v3/update`; existing V2 and V3 compatibility Tcl entrypoints remain available.

Mutable scientific fields include enabled/canonical name, unit, canonical unit and both custom conversion formulas, display label, semantic role/source, value kind/format, decimal separator, time origin/reference and instrument associations. Typed fields include dtype/rank/shape/dimensions/coordinates/axis metadata/components/groups. Variable IDs, source header/column and provider-owned storage locators are immutable through this operation. Names, roles, kinds, relationships, dimensions and conversion syntax use the normal validators.

All typed validation precedes any CSV rewrite. One outer transaction backs up canonical payload, registry and Manifest, restores them and in-memory bindings/configuration on failure, and removes a newly created source snapshot if needed. CSV rename/Use changes retain the existing reversible schema-source snapshot. Metadata-only changes avoid scientific rewrites. Existing registries with omitted source-format defaults read with dot/elapsed defaults so they remain editable.

```python
gxtxt_api_call('DATASET_VARIABLE_SCHEMA_API_v3', 'update',
  ['sampled_curve', {'response': {'display_label':'Measured response',
      'semantic_role':'voltage', 'semantic_source':'user',
      'coordinate_role':'data'}}])
```

Semantic Registry strings and Unit Registry conversions remain separate public concepts. A per-variable custom relation is a restricted numerical formula, never an executable callback. Portable Dataset ZIPs preserve the complete scientific schema and reversible source snapshot.
