# XAS Spectra Viewer API v1

The module registers Viewer Provider backend `xas_plot_dataset` and exposes a
small XAS-specific facade over the public Plot Dataset APIs.

## Architecture

```text
spectrum.scientific / spectrum.family
        ↓
viewer.xas_spectra
        ↓
PLOT_DATASET_API_v3
live PlotSpec lifecycle + complete standard editor/configuration
        ↓
same PLOT_DATASET_API_v3
snapshot / detached rendering / source-row point identity
```

The module contains no renderer and no private legend/axis/panel persistence.

## Live operations

`createPlot dataset_id`

Creates a persistent Plot Dataset graph through `PLOT_DATASET_API_v3`. For a
`spectrum.family` Dataset the series uses:

```text
family_variable_id = parameter_value
x_variable_id      = spectral_x
y_variable_id      = spectral_y
```

`openDataset dataset_id`

Creates the graph, invokes the normal v3 render lifecycle and opens the standard
Plot Dataset editor. The standard framework editor owns legend, axes, ranges,
scales, units, series presentation, annotations, panels, persistence, variants,
rerender and export.

## Additive v3 operations

`captureDetachedSnapshot artifact destination_dir`

Delegates to `PLOT_DATASET_API_v3::captureForArtifact`, returning a dictionary
with `graph_id`, `source_variant` and `snapshot`.

`writePointIndex artifact destination`

Delegates to `PLOT_DATASET_API_v3::writePointIndex`, returning the newly written
destination path. An existing destination, unowned artifact or 3D source rejects.

`renderDetachedSnapshot clone_dir graph_id`

Delegates to `PLOT_DATASET_API_v3::renderSnapshot`, returning the
`clone_dir/graph.png` path after verifying the rendered output.

These operations do not redefine live graph configuration. Current GX-TXT v3
is explicitly additive to v2 and normal module publishing remains PlotSpec v2.

Dataset discovery and contract checks use `SESSION_INSPECTION_API_v1`; only records whose explicit `id` matches are accepted.
Session discovery is optional for the viewer shell. When no compatible Dataset is present, the source selector and graph action are disabled. A direct Viewer Provider request with a compatible `dataset_id` retains the existing immediate Plot Dataset editor path.
