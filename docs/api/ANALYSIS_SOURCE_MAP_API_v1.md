# GX-TXT Analysis Source Map API v1

**Introduced:** GX-TXT Pipeline v0.8.5  
**Status:** public additive extension of Standard Module API v1  
**Manifest format:** 2 (additive sections)  
**Scientific alignment policy:** never implicit

## Purpose

Analysis Source Map API v1 lets one analysis module consume **N canonical datasets** without hard-coding file paths and without creating a second dataset-binding system.

A module works with stable source IDs such as:

```text
primary
uncertainty
stats
reference
```

Each source ID is mapped by the framework to a Dataset API ID already registered in the current session. The framework resolves the corresponding canonical path, contract and columns and writes them to `runtime.ini`.

The API does **not** join, interpolate, resample, sort, align or otherwise modify scientific data. Those remain explicit Scientific Analysis Definition operations.

---

## 1. Opting a module into N-source mode

A module opts in through its `module.ini`:

```ini
[analysis_sources]
api_version=1
ids=primary
dynamic=1
```

`primary` is mandatory because legacy unqualified bindings are defined as aliases of `primary.<variable>`.

`ids=` declares the rows that exist by default. More than one may be declared:

```ini
[analysis_sources]
api_version=1
ids=primary;uncertainty;stats
dynamic=1
```

`dynamic=1` allows the user to add/remove additional source rows from the framework-owned Analysis GUI.

If `[analysis_sources]` is absent, the module remains a historical single-dataset module and the existing `dataset_id` path is unchanged.

---

## 2. Declaring source requirements

Optional per-source sections describe required/optional status and accepted dataset contracts:

```ini
[analysis_source.primary]
required=1
contracts=curve_family.table

[analysis_source.uncertainty]
required=0
contracts=table.generic

[analysis_source.stats]
required=0
contracts=table.generic
```

Supported fields:

| Field | Meaning |
|---|---|
| `required` | `1` means a Dataset ID must be selected before runtime generation |
| `contracts` | semicolon/comma separated accepted Dataset API contracts |
| `dataset_id` | optional default Dataset ID |

For `primary`, if `contracts=` is omitted, the module `[inputs] contracts=` declaration is used as the compatibility constraint.

A dynamically added source with no matching `[analysis_source.<id>]` section accepts any registered dataset contract.

---

## 3. Framework-owned GUI

For an opted-in analysis module the Analysis panel contains a framework-generated table:

```text
Source ID       Dataset ID
primary         2d21-consensus
uncertainty     2d21-uncertainty
stats           2d21-stats
```

When `dynamic=1`, the table exposes `+ Add source` and `Remove` controls.

The module must not implement its own source-selection GUI.

Dataset selectors show only canonical Dataset API entries from the current session. A dataset configured in the acquisition/import page becomes selectable only after it has actually been imported and registered.

---

## 4. Qualified bindings

Bindings may use the namespace:

```text
source.variable
```

Example:

```text
x=primary.Vg1_V
y=primary.Ig1_mA
family=primary.Ib_mA
sigma_y=uncertainty.sigma_total
```

The framework binding chooser displays qualified variables from all configured sources.

### Backward compatibility

An old unqualified binding remains valid:

```text
x=Vg1_V
```

and is interpreted exactly as:

```text
x=primary.Vg1_V
```

Existing single-source modules keep their historical unqualified runtime bindings and do not enter this namespace unless they opt into `[analysis_sources]`.

Canonical variable names may contain dots. The framework treats the prefix before the first dot as a source qualifier **only when it matches a configured source ID**. Otherwise the full name is treated as a legacy primary variable name.

---

## 5. Runtime contract

For an N-source module the framework preserves the historical `[dataset]` section as a compatibility alias for the `primary` dataset and adds:

```ini
[analysis_sources]
api_version=1
ids=primary;uncertainty;stats

[analysis_source.primary]
dataset_id=2d21-consensus
path=/absolute/runtime/path/to/2d21-consensus.csv
kind=curve_family.table
columns=Vg1_V,Ig1_mA,Ib_mA

[analysis_source.uncertainty]
dataset_id=2d21-uncertainty
path=/absolute/runtime/path/to/2d21-uncertainty.csv
kind=table.generic
columns=sigma_total
```

Bindings are emitted in the established section:

```ini
[bindings]
x=primary.Vg1_V
y=primary.Ig1_mA
family=primary.Ib_mA
sigma_y=uncertainty.sigma_total
```

Runtime paths are resolved by the framework from `metadata/datasets.ini`; plugin code must not reconstruct session dataset paths.

---

## 6. Building the Scientific Analysis source map

Public helper:

```octave
sources = gxtxt_analysis_source_map_from_runtime(runtime_cfg)
```

It returns the `source_map` structure expected by:

```octave
result = gxtxt_analysis_run(definition_path, source_map, output_dir, options)
```

For example:

```octave
cfg = gxtxt_ini_read(config_path);
opts = struct('runtime_cfg', cfg);
sources = gxtxt_analysis_source_map_from_runtime(cfg);
result = gxtxt_analysis_run(definition_path, sources, output_dir, opts);
```

`gxtxt_analysis_run()` can also derive the source map automatically when an empty struct is passed together with `options.runtime_cfg`:

```octave
opts = struct('runtime_cfg', cfg);
result = gxtxt_analysis_run(definition_path, struct(), output_dir, opts);
```

Backward compatibility: if `[analysis_sources]` is absent, the helper returns:

```text
sources.primary = runtime.dataset.path
```

---

## 7. Scientific Analysis Definition bindings

A Scientific Analysis Definition may continue to use `binding=` rather than hard-coded column names:

```ini
[sources]
roles=primary;uncertainty

[source.primary]
required=1

[source.uncertainty]
required=0

[variables]
ids=x;y;family;sigma_y

[variable.x]
binding=x
type=numeric

[variable.y]
binding=y
type=numeric

[variable.family]
binding=family
type=numeric

[variable.sigma_y]
binding=sigma_y
type=numeric
role=uncertainty
required=0
```

If runtime contains:

```ini
sigma_y=uncertainty.sigma_total
```

then the Analysis engine reads `sigma_total` from source `uncertainty`.

If runtime contains:

```ini
x=Vg1_V
```

then the Analysis engine reads `Vg1_V` from `primary`.

A qualified binding may therefore override the source that would otherwise have been supplied by a variable's static `source=` declaration.

---

## 8. No implicit alignment

Source datasets may have different row counts, grids and sampling times.

Analysis Source Map API does not attempt to reconcile them.

For example:

```text
primary        500 curve-family rows
uncertainty    500 uncertainty rows
chemistry       12 sampling rows
sensor        3600 time-series rows
```

If scientific alignment is needed it must be declared explicitly through Scientific Analysis Definition API operations such as:

```text
align
join
resample
interpolate
```

This separation is intentional: dataset selection is infrastructure; alignment is scientific methodology.

---

## 9. Manifest Format 2 persistence

The GUI state is persisted additively:

```ini
[analysis_source_map_api]
version=1

[module_analysis_sources.curve.family_transform]
ids=primary;uncertainty;stats

[module_analysis_source.curve.family_transform.primary]
dataset_id=2d21-consensus

[module_analysis_source.curve.family_transform.uncertainty]
dataset_id=2d21-uncertainty
```

Old manifests without these sections remain loadable. For an opted-in module, the framework falls back to descriptor defaults and, when available, the historical `dataset_id` as the `primary` selection.
The legacy value is read from the saved `module_config.<module_id>.dataset_id`
Manifest section even when the module's new descriptor no longer declares
`config.dataset_id`. This permits a module to replace its old selector with
Analysis Source Map without losing existing Session bindings.

---

## 10. Source ID rules

Source IDs must match:

```text
^[A-Za-z][A-Za-z0-9_]*$
```

Examples:

```text
primary
uncertainty
stats
reference_2
```

Do not use dots in source IDs because dot is the `source.variable` namespace separator.

---

## 11. Minimal module descriptor example

```ini
[meta]
api_version=1
id=curve.family_transform
kind=analysis
name=Curve Family Transform
version=1
runner=standard_octave

[inputs]
contracts=curve_family.table

[analysis_sources]
api_version=1
ids=primary;uncertainty
dynamic=1

[analysis_source.primary]
required=1
contracts=curve_family.table

[analysis_source.uncertainty]
required=0
contracts=table.generic

[bindings]
roles=x;y;family;sigma_y

[binding.x]
label=Independent X
required=1

[binding.y]
label=Measured Y
required=1

[binding.family]
label=Family
required=1

[binding.sigma_y]
label=Y uncertainty
required=0
```

The module runtime should consume `runtime.ini`; it should not contain a second source registry, second column-mapping system, or automatic alignment layer.

---

## 12. Compatibility summary

- Existing `dataset_id` modules: unchanged.
- Existing unqualified bindings: unchanged and interpreted as primary in N-source modules.
- Existing Manifest Format 2 files: loadable.
- Existing Scientific Analysis Definition API v1 definitions: loadable.
- Mathematical Model Plugin API: unchanged.
- Graph Provider / shared graphics / Render Cache APIs: unchanged.
- No automatic join/interpolation/resampling is introduced by this API.

---

## v0.9.1 variable metadata runtime extension

GX-TXT v0.9.1 keeps Analysis Source Map API v1 path semantics unchanged and additively exposes Dataset Registry variable metadata in `runtime.ini`.

In addition to `dataset_id/path/kind/columns`, each source may now contain:

```ini
variables=time_s;current_A
units=s;A
semantic_roles=independent;measured
variable_count=2
```

and authoritative indexed variable sections:

```ini
[analysis_source.primary.variable.1]
name=time_s
unit=s
semantic_role=independent
original_header=Time
source_column=1
```

See `ANALYSIS_SOURCE_METADATA_RUNTIME_v1.md`.

`gxtxt_analysis_source_map_from_runtime()` still returns source-role -> path strings, so existing modules remain compatible. Use `gxtxt_analysis_source_variable_meta()` when variable metadata are needed.


## Source reassignment and stable input bindings (0.9.7.12)

Changing a logical source such as `primary` to another Dataset does not
carry its old dataset-scoped `variable_id` into the replacement Dataset.
Base Standard Module bindings persist `source_id|dataset_id|variable_id`
through Dataset Variable Schema API v2. When the stored Dataset differs
from the source's current Dataset, resolution fails and the user must choose
a new variable. The runtime source map and `[bindings]` are written only
after binding preflight succeeds.

## Dataset-level structured metadata bridge (GX-TXT 0.9.7.57)

Analysis Source Map API v1 remains the source-ID-to-Dataset/path contract. The
additive [Analysis Source Dataset Metadata Runtime Extension v1](ANALYSIS_SOURCE_DATASET_METADATA_RUNTIME_v1.md)
serializes the public Dataset Metadata API v1 resource for each selected source
when `runtime.ini` is generated.

The existing source map return type is unchanged. Modules that need arbitrary
Dataset-level metadata use:

```octave
meta = gxtxt_analysis_source_dataset_metadata(runtime_cfg, source_id);
[value, found] = gxtxt_analysis_source_dataset_metadata_get( ...
    runtime_cfg, source_id, exact_dataset_metadata_key);
```

Dataset Metadata keys remain exact strings rather than Octave field names.
