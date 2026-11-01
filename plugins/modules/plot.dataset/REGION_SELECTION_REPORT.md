# Region Selection status — `plot.dataset` 3.3.0

SPDX-License-Identifier: GPL-3.0-or-later

GX-TXT 0.9.7.38 supports X-range Dataset Selection for heterogeneous active
Graph Series X bindings by preserving one shared display-domain interval plus
the stable source binding set.

For a single-panel `plot.dataset.xy`, release 3.3.0 preserves the established
Region Selection path unchanged.

For a multi-panel `plot.dataset.xy`, the module renders vertically stacked data
axes and publishes their real topology in the normal plot metadata. A separate
`<plot>.xrange.ini` sidecar holds the synthetic calibrated selection geometry
spanning the shared-X stack. That geometry contains the graph-wide X display range;
Dataset Selection still derives the real source Dataset/X bindings from CORE
Graph Series. No panel-specific X selection state and no second selection
registry are introduced.

`plot.dataset.xy_region` remains single-panel because rectangle selection has
one Y domain and is intentionally outside this multi-panel feature.

The Tcl Dataset Selection contract is covered by regression tests. Real
PNG/GNUplot calibration for the multi-panel synthetic selection surface is
covered by `tests/test_v310_multipanel_render.tcl`; that test reports `SKIP`
when Octave/GNUplot is unavailable and must not be reported as executed in such
an environment.
