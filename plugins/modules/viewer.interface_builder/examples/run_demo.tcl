# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv framework example
if {$example ni {toolbar_inspector table_selection native2d_interaction native3d_embedded}} {error {Choose one of the four documented synthetic examples}}
set here [file dirname [file normalize [info script]]]
set argv0 __gxtxt_synthetic_example__
source [file join [file normalize $framework] gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
wm withdraw .
set design [::GX::viewerGuiDesignRead [file join $here $example.gxtxt-viewer]]
::GX::viewerGuiDesignCompose $design .example viewer.interface_builder interface_builder demo
# Native controls own RAM state; table data are explicitly demonstration-only.
if {$example eq {table_selection}} {::GX::viewerGuiDesignTableSet .example example {{{Synthetic A} 23.5 demo} {{Synthetic B} 24.1 demo} {Reference 20.0 demo}}}
wm protocol .example WM_DELETE_WINDOW {destroy .example;destroy .}
