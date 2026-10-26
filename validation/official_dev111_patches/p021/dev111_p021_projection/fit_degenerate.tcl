# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root output
if {[file exists $output]} {error {Use a new private output}}
file mkdir $output
foreach kind {CONFIG DATA CACHE STATE} {set ::env(XDG_${kind}_HOME) [file join $output [string tolower $kind]]}
set ::env(LIBGL_ALWAYS_SOFTWARE) 1
set ::env(LIBGL_ALWAYS_INDIRECT) 0
set ::env(GALLIUM_DRIVER) llvmpipe
set argv0 __P021_DEGENERATE_FIT_TEST__
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults
load [file join $root core native3d bin libgx3de_viewer_tcl.so] Gx3deviewer
set view [::GX::viewerSceneDefaults]
foreach {key value} {projection orthographic camera_position {5;7;9} camera_target {0;0;0} camera_up {0;0;1} working_plane_visible 1 working_plane_origin {0;0;0} working_plane_normal {0;0;1} working_plane_u_axis {1;0;0}} {dict set view $key $value}
set policy [::GX::native3dGraphicsPolicy];dict set policy execution Software
::GX3DEViewer::projection enable 1
set reply [::GX3DEViewer::render [dict create view $view layers {} graphics_policy $policy] [file join $output initial.png] 640 480 full]
set plane [dict get $reply projection_snapshot working_plane]
set results {}
foreach {name bounds} {horizontal {-2 0 2 0} vertical {0 -2 0 2} point {0 0 0 0}} {
    set fit [::GX3DEViewer::projection fit_plane $plane $bounds [file join $output $name.png]]
    if {[dict get $fit retained_extent_objects]!=0 || [dict get $fit orthographic_height]<=0} {error {Native degenerate fit failed}}
    lappend results [dict create name $name bounds $bounds orthographic_height [dict get $fit orthographic_height] retired_objects [dict get $fit retained_extent_objects]]
    puts "PASS native FitObject admits $name extent without Viewer camera formulas"
}
::GX3DEViewer::close
set f [open [file join $output RECEIPT.tcldict] w];puts $f [dict create status PASS results $results real_gui_acceptance 0];close $f
