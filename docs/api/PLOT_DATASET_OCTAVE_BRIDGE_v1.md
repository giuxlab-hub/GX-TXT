# Plot Dataset Octave Bridge v1

`gxtxt_plot_dataset_v2` is the public CORE bridge for `standard_octave`
modules that need `PLOT_DATASET_API_v2`.  A module does not source
`gxtxt_pipeline.tcl`, load Tk, write plot.dataset private state, or invoke the
renderer directly.

```octave
r = gxtxt_plot_dataset_v2(session_path, plotspec, struct( ...
  'action','create', 'kind','variant', 'source_variant','', 'render',true));
disp(r.graph_id); disp(r.variant_id); disp(r.artifact);
```

The PlotSpec is an Octave scalar `struct`; nested dictionaries are scalar
structs and PlotSpec arrays (`panels`, `series`, `annotations`) are cell arrays
or struct arrays.  Scalars may be text, numeric or logical.

Options:

- `action=create` creates a persistent base plot or variant from `plotspec`.
- `action=render` renders an existing `graph_id`/`variant_id`; a non-empty
  PlotSpec is applied and persisted first.
- `action=rerender` performs the cache-only v2 rerender; a non-empty PlotSpec
  may contain presentation changes applied before rerender.
- `kind=base|variant`, `source_variant`, and `render=true|false` control create.

The returned struct always contains `graph_id`, `variant_id`, `artifact`,
`output_dir`, `render_cache`, and `summary`.  State is committed through
`PLOT_DATASET_API_v2` and the Session manifest before rendering.

