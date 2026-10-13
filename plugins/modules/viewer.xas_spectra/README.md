# viewer.xas_spectra

A deliberately thin XAS Viewer Provider for GX-TXT 0.9.8.10+.

The viewer does not own scientific rendering or presentation state.

For a normal live graph it uses `PLOT_DATASET_API_v3`, which is the current
public PlotSpec lifecycle/configuration API used by production scientific
modules in GX-TXT 0.9.8.10. The viewer creates a persistent Plot Dataset graph,
uses public numeric family grouping for `spectrum.family`, renders it and opens
the standard Plot Dataset editor.

The standard editor/framework therefore owns the complete shared graph
configuration, including legend content and placement, legend layout/alignment,
axes, ranges, scales, display units, series presentation, annotations, panels,
persistence, rerender and export.

The same v3 facade provides detached scientific snapshots and displayed-point source-row identity. Its normal PlotSpecs still use the stable v2 persistence schema.

Dataset selection and contract inspection use the public Session Inspection API v1.
