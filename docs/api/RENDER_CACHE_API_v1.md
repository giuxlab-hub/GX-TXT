# Render Cache API v1

SPDX-License-Identifier: GPL-3.0-or-later

**Introduced:** GX-TXT Pipeline v0.8.3  
**Expanded:** GX-TXT Pipeline v0.8.4  
**API version:** 1  
**Status:** optional framework API; legacy module-owned caches remain supported

## Purpose

Render Cache API v1 standardizes cache lifecycle/provenance without taking ownership of module-specific scientific meaning.

```text
legacy module
    -> may continue using its historical render_cache.mat layout

opt-in module
    -> standard path / atomic save / load / validation
    -> source + analysis + parameter fingerprints
    -> optional Scientific Analysis result envelope
    -> cache-only rerender when declared by the module
```

No existing module is required to migrate merely because the API exists.

## Module descriptor

```ini
[render_cache]
api_version=1
rerender_from_cache=1
```

Standard runtime then includes:

```ini
[render_cache_api]
api_version=1
path=/session/analysis/<module-id>/render_cache.mat
rerender_from_cache=1
```

Absence of `[render_cache]` preserves historical behavior.

## Public helper location

```text
core/octave/cache/
```

## Path

```octave
path = gxtxt_render_cache_path(output_dir)
```

returns:

```text
<output_dir>/render_cache.mat
```

## Atomic save/load

```octave
path = gxtxt_render_cache_save(output_dir_or_mat_path, cache)
cache = gxtxt_render_cache_load(output_dir_or_mat_path)
```

A standard cache is one MAT variable named `cache` with:

```text
cache.meta.api_version = 1
```

The standard loader intentionally rejects a historical module-owned MAT file that lacks the envelope. Such a module keeps using its own loader.

## Validation

```octave
report = gxtxt_render_cache_validate(cache, expected)
```

`expected` may contain any metadata fields. Common fields:

```text
module_id
module_version
definition_id
definition_version
source_fingerprint
parameter_fingerprint
analysis_fingerprint
```

Result:

```text
report.valid
report.errors
```

## Generic fingerprint

```octave
fp = gxtxt_render_cache_fingerprint(parts)
```

The helper creates a stable SHA-256 over an ordered list of scalar values.

## File fingerprint

```octave
fp = gxtxt_render_cache_file_fingerprint(path)
```

## Source-map fingerprint - v0.8.4

```octave
fp = gxtxt_render_cache_source_fingerprint(source_map)
```

`source_map` is the same role-to-path struct passed to `gxtxt_analysis_run()`. Field order is normalized, and each local source file is fingerprinted.

## Parameter fingerprint - v0.8.4

```octave
fp = gxtxt_render_cache_parameter_fingerprint(parameters)
```

`parameters` is a struct of effective scalar Analysis Definition parameter values. Field order is normalized.

## Analysis fingerprint - v0.8.4

```octave
fp = gxtxt_render_cache_analysis_fingerprint(definition_path, parameters)
```

This combines the Analysis Definition file fingerprint with the parameter fingerprint.

## Standard metadata constructor - v0.8.4

```octave
meta = gxtxt_render_cache_standard_meta( ...
    module_id, module_version, definition_path, source_map, parameters);
```

Generated fields include:

```text
api_version
module_id
module_version
definition_id
definition_version
source_fingerprint
parameter_fingerprint
analysis_fingerprint
created_utc
```

Recommended use:

```octave
meta = gxtxt_render_cache_standard_meta( ...
    'curve.family_transform','1',def_path,sources,result.context.parameters);
```

## Scientific Analysis result envelope - v0.8.4

```octave
cache = gxtxt_render_cache_from_analysis(result, meta)
```

The framework creates:

```text
cache.meta
cache.data.definition_id
cache.data.definition_path
cache.data.context
cache.data.operation_order
cache.data.exports
cache.graphics.plots
cache.module
```

A thin module therefore does not have to manually copy every standard Scientific Analysis result field.

Example:

```octave
r = gxtxt_analysis_run(def_path,sources,outdir,opts);
meta = gxtxt_render_cache_standard_meta( ...
    module_id,module_version,def_path,sources,r.context.parameters);
cache = gxtxt_render_cache_from_analysis(r,meta);
gxtxt_render_cache_save(outdir,cache);
```

## Cache validity before rerender

A module can rebuild the expected metadata from the currently selected source(s), definition and parameters, then check:

```octave
rep = gxtxt_render_cache_validate(cache, expected);
if(!rep.valid)
  % recompute or report stale cache
endif
```

Do not rerender a stale scientific cache merely because the MAT file exists.

## Rerender flow

```text
runtime.ini
    -> resolve standard/legacy cache path
    -> load cache
    -> validate provenance when available
    -> render only
    -> shared gxtxt_plot_* API
    -> gxtxt_print_png_atomic()
```

Rerender should not repeat scientific computation when a valid cache contains all needed data.

## Compatibility guarantee

Render Cache API v1 is additive. Existing IR, curve-fit, replicate-analysis, SPICE-validation or third-party module-owned caches may retain their current layout and direct `save/load` code.

The standard API is recommended for new modules because it reduces repeated boilerplate and makes cache validity auditable.

## v0.9.3.3 — 3D presentation and rerender

No second cache API is introduced for 3D. A module may place prepared gridded/scattered X/Y/Z/C arrays and grouping metadata in its normal module-defined `cache` payload. The standard envelope/fingerprint rules remain unchanged.

Pure presentation changes — X/Y/Y2/Z display units, limits/ticks, grid, legend, annotation, azimuth/elevation, supported projection, colormap, colorbar and CLim — are expected to be read from the current runtime/graphics state during a cache-only rerender. A module must not rerun scientific preparation merely because one of those values changed.
