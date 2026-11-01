# GX-TXT Octave Modules

SPDX-License-Identifier: GPL-3.0-or-later

This directory contains scientific analysis modules, rerenderers, the module catalog, and the shared graphics API.

New analysis modules should keep numerical calculation separate from plotting. Save the numerical state required for rerendering in `render_cache.mat` and use the shared `gxtxt_plot_*` functions to generate plots.

See `../GRAPHICS_ARCHITECTURE.md` and `../MODULE_GUIDE.md`.
