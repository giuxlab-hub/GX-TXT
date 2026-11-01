# Replicate Curve Analysis v13 migration

## Scope

v13 replaces the graph ownership and rerender architecture only. The scientific algorithms, Table Stream API v3 input, semantic binding correction, statistics, CSV outputs and compact three-Dataset publication model remain unchanged.

## The two v10-v12 defects

1. Graphs created as real `plot.dataset` Variants had the complete Plot Dataset editing lifecycle, but their persistent owner was `plot.dataset`, not `curve.replicate_analysis`.
2. PNGs exposed under `curve.replicate_analysis` had the correct visible owner but were aliases/copies, so they did not participate consistently in the same persistent graph lifecycle. Selective edits and rerenders could therefore address different graph objects and create additional Variants.

## v13 design

The four graph IDs are native Graph Provider outputs owned by `curve.replicate_analysis`. Each opts into Plot Module variants with:

```ini
supports_variants=1
variant_data_model=module_cache
```

`module_cache` is the framework model for plots whose scientific data is already present in a module render cache. Variants are presentation-only: they inherit the real analysis sources and use the base `render_cache.mat`, never synthesize X/Y Graph Series and never rerun scientific analysis.

The module renderer uses the standard shared graphics helpers for legend, axes/grid and final PNG output. Variant runtime state is projected onto the original module graph ID by CORE, so the unchanged renderer receives the selected Plot, Graphics, Legend and Axes settings.

## Ownership

Expected Graphs window identity is now:

```text
Module                   Plot
curve.replicate_analysis  01_replicate_overlay.png
curve.replicate_analysis  02_consensus_uncertainty.png
curve.replicate_analysis  03_uncertainty_components.png
curve.replicate_analysis  04_family_uncertainty_summary.png
```

No v13 graph is created under `plot.dataset`. Plot Dataset is not a dependency of v13.

## Existing Sessions

On the first v13 analysis run the module deletes its own stale `analysis/curve.replicate_analysis/automatic_graphs.ini` file left by the provider-alias implementations. Old `plot.dataset` Variants created by v10-v12 are not deleted; they may be removed separately if desired.

A v12 render cache does not contain the full trace/profile data required by the module-owned renderer. Run the v13 analysis once before attempting a v13 rerender or Variant render.
