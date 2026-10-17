#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
cd "$(dirname "$0")/.."
tclsh tests/documentation_version.tcl
tclsh tests/engine_integration.tcl
tclsh tests/presets_integration.tcl
tclsh tests/figure_integration.tcl
tclsh tests/workspace_model.tcl
if [ -n "${GXTXT_TEST_CORE_DIR:-}" ]; then
    if command -v xvfb-run >/dev/null 2>&1; then
        xvfb-run -a tclsh tests/gui_smoke.tcl
        xvfb-run -a tclsh tests/article_gui_smoke.tcl
    else
        echo 'SKIP: Native2D GUI smoke requires xvfb-run or an active X11 display'
    fi
else
    echo 'SKIP: Native2D GUI tests require GXTXT_TEST_CORE_DIR pointing to a read-only GX-TXT core test tree'
fi
