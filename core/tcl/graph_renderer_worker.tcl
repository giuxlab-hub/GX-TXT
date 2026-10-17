# SPDX-License-Identifier: GPL-3.0-or-later
# Existing Analysis queue owns this process, progress, cancellation and logging.
lassign $argv framework session reference
set framework [file normalize $framework];set session [file normalize $session]
set argv0 __gxtxt_native_graph_renderer__
source [file join $framework gxtxt_pipeline.tcl]
try {
    ::GX::defaults;::GX::loadModuleCatalog
    if {![file isfile [file join $session metadata manifest.ini]]} {error {Captured Graph Session is unavailable}}
    set ::GX::currentSession $session
    ::GX::loadManifest [file join $session metadata manifest.ini]
    set reference [::GX::graphResourceRef $reference]
    if {[::GX::graphRendererOwner $reference] ne {PLOT_DATASET_API_v4}} {error {Captured Graph renderer ownership changed}}
    ::GX::graphNativeRendererRequire
    if {[dict get $reference kind] eq {clone}} {
        set path [file join [::GX::PlotClone::root] [dict get $reference clone_id] graph.png]
        set info [::GX::PlotClone::infoForPath $path]
        ::GX::PlotDatasetAPIv4::renderSnapshot [file dirname $path] [dict get $info clone.snapshot_graph]
    } else {
        ::GX::PlotDatasetAPIv4::render $reference
    }
    puts {Native Plot Dataset render complete.}
} on error {message options} {
    puts stderr [dict get $options -errorinfo]
    exit 1
}
exit 0
