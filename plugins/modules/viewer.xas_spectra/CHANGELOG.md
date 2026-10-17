## 1.0.5

Declare distinct native-resolution scientific catalog artwork, short title and semantic group through the existing Viewer Provider descriptor.

# Changelog

## 1.0.4

- Open an inspectable source-selection shell without a Session or compatible spectrum. Keep direct compatible Dataset requests on the standard persistent graph editor path.

## 1.0.3

- Use Plot Dataset API v3 alone for live graphs, editor and detached snapshots.

## 1.0.2

- Use the public Session Inspection API for Dataset discovery and contract checks, removing private CORE registry access.
- Require GX-TXT 0.9.8.10 and retain the public Plot Dataset v2/v3 graph lifecycle.

## 1.0.1

- Clarified and implemented the current Plot Dataset API split used by GX-TXT 0.9.8.08.
- Live XAS graphs remain on the complete `PLOT_DATASET_API_v2` PlotSpec lifecycle and standard editor.
- The viewer now requires the shared v2 configuration capabilities used for family grouping, axes, panels, standard series/graph/axis editors, persistence, render/rerender, artifacts and export.
- Added explicit `PLOT_DATASET_API_v3` detached snapshot, detached render and source-row point-index operations.
- Kept all legend, axis, range, scale, unit, panel and export state owned by `plot.dataset`; no viewer-private presentation state was introduced.

## 1.0.0

- Initial XAS spectrum viewer for `spectrum.scientific` and `spectrum.family`.
- Delegated live rendering and persistence to `PLOT_DATASET_API_v2`.
