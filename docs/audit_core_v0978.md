# GX-TXT CORE audit — 0.9.7.8

SPDX-License-Identifier: GPL-3.0-or-later

## Y1/Y2

Multi-Y Axis Plot API v1 provides independent left/right Octave axes via
`gxtxt_plot_dual_y_axes`. `series_axes` assigns generic analysis
series to an axis. The common Axes/Grid API persists separate
`y_min/max/step/format` and `y2_min/max/step/format`, plus `y_unit`
and `y2_unit`. `gxtxt_plot_axis_overrides` applies left overrides
to the primary axis and right overrides to the overlay. Labels and units
are independently set by providers. `gxtxt_print_png_atomic`
synchronizes only X/geometry at finalization, and cache rerender retains
the graph settings.

A new synthetic `plot.dataset` integration regression produced
independent Y1=[0,5] A and Y2=[0,8]/[0,9] pH limits in the geometry
sidecar, with cache-only rerender. Thus the general CORE Y2 contract
and this module path work for that case. The user's observed dual-axis
failure is not reproduced by this fixture; its exact data/configuration
trigger has not been established. No plot.dataset algorithm was changed.

## Multi-dataset

Graph Provider API v1 could declare graphs, and Analysis Source Map could
name multiple datasets, but the generic plot renderer requires
primary-row-aligned series. It did not expose an independent
`dataset_id + x_variable_id + y_variable_id + axis` series binding.
Graph Series API v1 now provides this public minimum and a Table Stream
loader with no row alignment. Existing `plot.dataset` remains
primary-dataset-only until that module adopts the API.

## 3D Graph/Viewer

Plot 3D API v2 already has X/Y/Z line/scatter, gridded surface/mesh,
contour and triangulated surface, optional scalar color C, colorbar,
Z limits, azimuth/elevation and best-effort projection persistence.
A trajectory can be drawn as a line3 path. Graph Provider supports
plugin-defined graph IDs and cache rerender.

There is no public typed provider contract for STL geometry, pathline/
streamline data resources, opacity, clipping planes/sections, full
camera state, or interactive 3D viewing. These are wider than the
existing static Graph Provider contract. No CFD algorithm or provisional
Viewer Provider was inserted. See
`docs/api/VIEWER_PROVIDER_CONTRACT_PROPOSAL.md`.

## Temporal contract

Dataset Variable Schema v2 carries elapsed-time HMS parsing, source
decimal, time reference and origin. Table Stream v2 produces numeric
elapsed values in the declared unit. Graph Series API v1 carries those
fields and optional alignment intent for none/common elapsed zero/
absolute origin/manual offset. The loader leaves points and offsets
untouched. Explicit unit conversion (such as minutes to seconds)
works without interpolation. Applying absolute origins and offsets to
a shared axis remains future graph/viewer behavior.

## Level scales

FS, dB and dBFS are currently opaque, identity-preserved unit labels.
Unit/Dimension API rejects cross-conversion. The graph APIs do not
specify amplitude-versus-power quantity, positive reference, full-scale
value, or zero/negative policy. Consequently no numerical
linear→dB/dBFS/FS scale can be claimed; the safe default remains
linear. Synthetic regression confirms identity and rejects
reference-free transforms. See
`docs/api/LEVEL_SCALE_CONTRACT_PROPOSAL.md`.
