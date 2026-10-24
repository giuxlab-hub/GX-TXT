# viewer.curve_workbench 2.21.12

SPDX-License-Identifier: GPL-3.0-or-later

Scientific Curve Workbench with exact source bindings, independent physical
axis declarations, compatible display conversions and retained geometry/history.
Original Datasets stay unchanged; public CORE owns units, storage and numerical
geometry. Coordinate controls show independent display units and preserve native
constraint/parameter meaning. New scientific point curves preserve explicit meaning and provenance.

See [MANUAL.md](MANUAL.md), [CHANGELOG.md](CHANGELOG.md) and
[TEST_RESULTS.md](TEST_RESULTS.md). Install this normal module package through
the existing Plugin Manager; dependencies and public API entrypoints are declared
in module.ini.

DEV111-P012 requires the cumulative framework through P012 and its public
`GUI_UPDATE_SCHEDULER_API_v1`. Only wheel redraws adopt the opt-in CORE service;
Native zoom, normal editing timers and350ms view persistence remain unchanged.

DEV111-P013 requires the matching CORE native adapter shipped with the patch.
Existing shared grid/clipping calls use its C++ presentation batches automatically;
no Viewer-specific algorithm or switch is needed. P012 scheduling is unchanged.
