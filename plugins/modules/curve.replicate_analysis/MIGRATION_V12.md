# Replicate Curve Analysis v12 migration

## Scope

v12 changes only the graph lifecycle introduced by v11. The scientific algorithms, Table Stream v3 input path, semantic binding validation and compact derived Datasets are unchanged.

## Why v12 exists

v11 used a module-owned Tcl/Octave bridge to call Plot Dataset API v3. The plots rendered correctly, but the custom bridge duplicated lifecycle responsibilities already owned by GX-TXT Graph Workflow. Selective rerender could replace `automatic_graphs.ini` with only the selected graph, causing other module PNG aliases to reappear as independent graph targets. This could make legend/axis edits address the wrong object and could lead to extra Plot Variants.

## v12 behavior

- Uses `gxtxt_plot_provider_render_v1`, the framework-owned provider bridge.
- Retains the stable provider scope `replicate_v11` so existing valid provider variants can be reused.
- Calls the bridge with `append_existing=true`, so selective rerender preserves mappings for all other graphs.
- Removes the private `curve_replicate_plot_v3_bridge.tcl` and `curve_replicate_plot_v3_render.m`.
- Keeps PlotSpec v2 as the declarative schema, which is also the schema used by the current Plot Dataset v3 facade.
- Keeps Table Stream API v3, Dataset Variable Schema API v3 and the compact three-Dataset publication model from v11.

## Expected persistent graph model

Each module graph has one stable provider key:

- `curve.replicate_analysis:replicate_v11:overlay`
- `curve.replicate_analysis:replicate_v11:consensus_uncertainty`
- `curve.replicate_analysis:replicate_v11:uncertainty_components`
- `curve.replicate_analysis:replicate_v11:family_summary`

A module PNG such as `01_replicate_overlay.png` is only an alias/copy for the module output contract. The editable graph is the persistent `plot.dataset.xy` Variant referenced by `automatic_graphs.ini`.

Old duplicate Variants or Dataset artifacts created during v10/v11 testing are not deleted by this module.
