# XAS spectra viewer — Manual

Open the viewer from **Viewers** or from a compatible Dataset.

The Viewers action opens a source selector even when no Session or compatible Dataset exists. The empty message remains visible, and graph opening is disabled until a compatible source is available. Opening a compatible Dataset directly still opens the standard Plot Dataset editor. From the viewer shell, select a source and choose **Open persistent XAS graph**.

Supported contracts:

- `spectrum.scientific`;
- `spectrum.family`.

For a family, `parameter_value` is passed to the public Plot Dataset family
mechanism. One normal `plot.dataset` graph can therefore display the complete
spectral family without a private renderer or one duplicated file per member.

## Live graph and configuration

Normal live viewing uses `PLOT_DATASET_API_v3`, the public PlotSpec lifecycle
used by current GX-TXT scientific modules. After creating and rendering the
plot, the viewer opens the standard Plot Dataset editor.

Use the standard framework controls for all presentation settings, including:

- legend content;
- legend placement: inside, above, below, left, right or manual;
- inside legend preset;
- legend layout, alignment and columns;
- legend font, background, border and margin;
- X and Y axis labels, direction, range and scale;
- display units and engineering formatting where supported;
- series styles and enabled/order state;
- annotations;
- multi-panel configuration;
- save/reopen, variants, rerender and export.

The XAS viewer does not maintain a parallel copy of any of this state.

## Plot Dataset API v3

The same v3 facade also supplies:

- capture a detached scientific snapshot from a live Plot Dataset artifact;
- render such a detached snapshot;
- write a displayed-point index carrying canonical source-row identity.

Snapshot capture is explicit. Opening an XAS spectrum does not create a hidden
duplicate of the Dataset.

Dataset discovery and contract checks read the open Session through the public Session Inspection API v1.
