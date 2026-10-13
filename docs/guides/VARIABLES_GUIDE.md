# GX-TXT Variables Guide
## Dataset variables, IDs, units, semantics and plugin bindings

SPDX-License-Identifier: GPL-3.0-or-later

This is the practical entry point for the **Variables** window and for new plugins. The formal contracts remain in [Dataset Variable Schema API v2](../api/DATASET_VARIABLE_SCHEMA_API_v2.md), [Table Stream API v2](../api/TABLE_STREAM_API_v2.md), [Unit Registry API v1](../api/UNIT_REGISTRY_API_v1.md), [Semantic Registry API v1](../api/SEMANTIC_REGISTRY_API_v1.md), [Graph Series API v1](../api/GRAPH_SERIES_API_v1.md), and [Dataset Selection API v1](../api/DATASET_SELECTION_API_v1.md).

## The key to a variable

Persist **dataset_id + variable_id**. For example, d3 + v0009 identifies one source variable even when its display/canonical name changes from pH to reactor_pH. A name is for presentation and legacy lookup. A variable_id is stable within its dataset, including for Use=no variables.

Four notions that are easy to confuse:

| Field | Meaning | Changes after a rename or exclusion? |
|---|---|---|
| source_column | Original physical column in the RAW source. | No; provenance. |
| canonical_position | Current 1-based physical column in the canonical CSV. | Yes; empty when excluded. |
| variable_id | Persistent dataset-scoped identity (v0001, etc.). | No. |
| canonical / visible name | Current column name shown to users and name-based legacy code. | Yes. |

The imported Variables window shows RAW and canonical positions separately. Use=no removes the variable from the active canonical table but retains its ID and metadata. Use=yes restores it when CORE can reconstruct its values from the verified RAW source, a registered importer regenerator, or the immutable canonical snapshot. If no source contains the omitted column, CORE reports an error instead of silently changing the binding. RAW files remain untouched.

## Modern recommended path

In Tcl, inspect a dataset without reading private registry arrays:

~~~tcl
set variables [::GX::datasetVariableSchema d3]
set ph [::GX::datasetVariableById d3 v0009]
puts [dict get $ph canonical]
puts [dict get $ph enabled]
puts [dict get $ph canonical_position]
~~~

datasetVariableSchema returns every source variable, including Use=no. datasetVariableById is the ID lookup. For an existing module role, persist a stable pair:

~~~tcl
::GX::plotVariantBindingSet plot.dataset plot.dataset.xy p0002 y d3 v0009
~~~

For a series, the public Graph Series API stores the same identity:

~~~tcl
::GX::graphSeriesSet plot.dataset plot.dataset.xy s001 [dict create \
    dataset_id d3 x_variable_id v0001 y_variable_id v0009 \
    axis left label "pH"] p0002
~~~

Here plot.dataset is the module, plot.dataset.xy is the declared graph **type**, p0002 is one persistent plot configuration, and s001 is one series within it. A different variant can use another pair without replacing this graph. Omitting the final variant argument addresses the legacy base graph.

Rename pH to reactor_pH with Dataset Variable Schema API v2. The saved d3/v0009 binding still resolves; the current name is read at runtime. Changing its unit or semantic role also leaves the ID unchanged. Use=no preserves the pair, while rendering clearly reports that the value is unavailable. Use=yes can make it usable again if reconstruction succeeds.

### An Octave plugin reads typed values by ID

A Standard Module runtime exposes a source ID, Dataset ID and canonical path through Analysis Source Map API v1, and variable metadata through [Analysis Source Metadata Runtime v1](../api/ANALYSIS_SOURCE_METADATA_RUNTIME_v1.md). This example matches the public calls exercised by tests/test_v09711_variables_guide.m:

~~~octave
cfg = gxtxt_ini_read(config_path);
dataset_id = gxtxt_ini_get(cfg, 'analysis_source.primary.dataset_id', '');
path = gxtxt_ini_get(cfg, 'analysis_source.primary.path', '');
variable_id = 'v0003';  % supplied by a stable module or Graph Series binding

S = gxtxt_table_stream_open(path, {variable_id}, 5000);
values = [];
unwind_protect
  while (true)
    [S, chunk] = gxtxt_table_stream_next(S);
    values = [values; gxtxt_table_chunk_numeric(chunk, variable_id)];
    if (chunk.eof), break; endif
  endwhile
unwind_protect_cleanup
  S = gxtxt_table_stream_close(S);
end_unwind_protect
[unit, semantic_role, meta] = ...
    gxtxt_analysis_source_variable_meta(cfg, 'primary', variable_id);
assert(strcmp(meta.dataset_id, dataset_id));
~~~

New large-data-aware consumers can open the registered source directly:

~~~octave
opts = struct('start', 0, 'count', -1, 'require_direct', false);
S = gxtxt_table_stream_open_source(cfg, 'primary', ...
      {'v0001','v0002'}, 5000, opts);
[S, chunk] = gxtxt_table_stream_next(S);
x = gxtxt_table_chunk_column(chunk, 'v0001');
S = gxtxt_table_stream_close(S);
~~~

This Table Stream v3 path dispatches through Canonical Dataset API v2 for
registered CSV or table-shaped HDF5 data. Use the Canonical Dataset API
directly for n-dimensional variables.

The primary source ID is the module's declared source role; another declared role uses its own runtime section. Check that the runtime's Dataset ID equals the intended stable binding's Dataset ID. For Graph Series from several datasets, use each resolved graph_series.N entry or gxtxt_graph_series_load(cfg, graph_id, chunk_rows, variant_id): each entry carries its own Dataset ID, path, variable IDs and original X/Y vectors. The loader never aligns, interpolates or resamples them.

The runtime metadata helper returns unit, semantic role, current name, variable ID, semantic provenance, source column, value kind, decimal convention and time metadata where exported. The full mutable schema, including canonical_unit and display_label, is available through Dataset Variable Schema API v2 in Tcl. A plugin does not parse metadata/datasets.ini directly.

## Parsing, numbers and time

The source can declare decimal comma or decimal point. Table Stream reads the registered schema, detects or uses the canonical delimiter, interprets the declared decimal convention and returns numeric values with an internal **decimal point**. Scientific plugins should call gxtxt_table_chunk_numeric, not add a comma parser. gxtxt_table_chunk_column returns the original serialized text when needed. Invalid or ambiguous values become NaN.

For a variable with `value_kind=elapsed_time` and `value_format=hms`, the text `00:57:00` becomes numeric `3420` and `02:02:00` becomes `7320`. Those numbers are elapsed **seconds** even when the compatible source schema declares `unit=h` or `unit=min`. The declared source unit remains metadata; Elapsed Time Requested-Unit API v1 can explicitly convert the normalized seconds for a consumer, but consumers must not infer or reapply the original textual representation. `time_reference=elapsed` means a duration relative to that dataset's origin. `time_reference=absolute` with `time_origin` records an explicit origin for future alignment. No automatic cross-dataset time shift occurs. The editable Dataset Variable Schema currently accepts `value_kind=number|text|elapsed_time`; `absolute_time` is a semantic role/reference concept and is not an editable value kind in this version. Semantic Registry definitions can describe `absolute_time`, but that wider definition does not change the schema parser.

## Value kind, unit and scientific meaning

These fields answer different questions:

- value_kind: how serialized values are interpreted (number, text, elapsed_time);
- unit: how a numeric value is expressed (h, s, ppm, pH, etc.);
- semantic_role: what it means (elapsed_time, concentration, ph, etc.).

For example, d3/v0001 may be named t, use hours and mean elapsed time; d3/v0002 may be named Cl-, use ppm and mean concentration. Another concentration variable may use mmol/L. A role does not prescribe one unit, and a unit does not determine one role.

canonical_unit and the optional to_canonical/from_canonical formulas define an explicit reversible relation for a custom variable. display_label controls presentation. They do not rename the variable or change its ID.

### Units

Use a known unit when the existing registry already expresses the conversion. CORE supports V ↔ mV and h ↔ s by intrinsic conversion; °C ↔ K by an affine relation; and mmol/L → mol/L by the registered scale 0.001. A plugin can register a new scale, affine, formula, identity or opaque unit through ::GX::unitRegistryRegister or descriptor [units]; consult [Unit Registry API v1](../api/UNIT_REGISTRY_API_v1.md) for validation and exact fields.

Leave a custom unit opaque when only equality to itself is scientifically justified. ppm and pH are opaque identity units here. GX-TXT does **not** infer ppm → mg/L or pH → [H+]; those require explicit scientific meaning and conversion supplied by the responsible plugin/user. Do not hide such transformations in a graph or a name heuristic. A missing unit provider leaves the persisted unit string and per-variable relation intact; the definition becomes opaque until the provider returns.

### Semantic roles

Query a variable with ::GX::datasetVariableSemantic d3 v0002; find all variables with a role using ::GX::datasetVariablesBySemanticRole concentration or add a Dataset ID argument to limit the search. A plugin can register its role via ::GX::semanticRegistryRegister or descriptor [semantic_roles], with suggested units and allowed value kinds. Suggested units guide the GUI and inference; they are not constraints.

semantic_source records user, importer, plugin, inferred, or default. Inference stores semantic_reason, such as a name alias or unambiguous unit hint; default records that no clear hint existed. A user choice remains authoritative when name or unit changes. If a provider is disabled or removed, the saved role string remains on the variable and can still be searched; the definition becomes available again if that provider returns.

## Selection resources

A plot region can become a persistent Dataset Selection. For example, a rectangle covering t = 1…3 h and pH = 6…8 is stored as canonical coordinate bounds; an analysis plugin may use the public Selection runtime to build a mask. It does not copy or alter the dataset. The resource records producer_module, producer_graph, optional producer_variant, source Dataset ID, X/Y variable IDs where available, current names for compatibility, and canonical units. Two variants of the same graph therefore produce separate selections. Legacy selections without producer_variant remain the base producer. Dual-Y selection remains limited to the primary/left Y axis.

## Legacy compatibility path

Old manifests, plugin bindings and Selection resources may use current names. ::GX::datasetVariableResolve dataset_id token accepts an ID first and a canonical name as a fallback. Table Stream and the Analysis Source metadata helper also accept names. New plugin state should persist Dataset ID + variable ID; name lookup is only a compatibility bridge. A renamed name can no longer identify the same variable in an old name-only record unless the framework already captured a stable ID for that binding.

For importer workflows and RAW mapping, see [Dataset Inspection / Variable Mapping API v1](../api/DATASET_INSPECTION_VARIABLE_MAPPING_API_v1.md) and [Multi-dataset import and inspection](MULTI_DATASET_IMPORT_AND_INSPECTION.md).

## Published and portable scientific schemas (dev-051)

Publication accepts units, kinds, semantic roles, formats, elapsed-time/date-time semantics, decimal separator, display labels, canonical unit and restricted conversion pairs, plus V3 dtype/rank/shape/dimensions/coordinates/components/groups. Omitted decimal separator defaults to `.`; omitted time reference defaults to `elapsed`. A combined V2/V3 update is one transaction, so invalid formulas or shapes leave prior schema and bytes intact. Variable IDs remain independent of display/canonical names and storage locators. Portable Dataset ZIP retains the schema-source snapshot so disabling/re-enabling CSV variables remains reversible; missing semantic/unit plugins do not erase Dataset-owned declarations or register new global providers.
