# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root output
if {[file exists $output]} {error {Use a new private output}}
file mkdir $output
foreach kind {CONFIG DATA CACHE STATE} {set ::env(XDG_${kind}_HOME) [file join $output [string tolower $kind]]}
set ::env(LIBGL_ALWAYS_SOFTWARE) 1;set ::env(LIBGL_ALWAYS_INDIRECT) 0;set ::env(GALLIUM_DRIVER) llvmpipe
set argv0 __P021_RANDOM_PLANES_TEST__
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults
load [file join $root core native3d bin libgx3de_viewer_tcl.so] Gx3deviewer
load [file join $root core native3d bin gx3de_projection_tcl_v1.so] Gx3deprojection
expr {srand(21021)}
proc random {low high} {expr {$low+rand()*($high-$low)}}
set view [::GX::viewerSceneDefaults]
foreach {key value} {camera_position {5;7;9} camera_target {0;0;0} camera_up {0;0;1} near_clip 0.01 far_clip 10000 working_plane_visible 1 working_plane_u_axis {1;0;0}} {dict set view $key $value}
set policy [::GX::native3dGraphicsPolicy];dict set policy execution Software
::GX3DEViewer::projection enable 1
set maximum 0;set invmaximum 0;set count 0;set frames {}
for {set trial 0} {$trial<6} {incr trial} {
    dict set view projection [expr {$trial%2?"orthographic":"perspective"}]
    set origin [list [random -1 1] [random -1 1] [random -1 1]]
    set normal [list [random -0.7 0.7] [random -0.9 0.9] [random 0.3 1]]
    dict set view working_plane_origin [join $origin {;}];dict set view working_plane_normal [join $normal {;}]
    set receipt [::GX3DEViewer::render [dict create view $view layers {} graphics_policy $policy] [file join $output trial-$trial.png] [expr {511+$trial*13}] [expr {379+$trial*7}] full]
    set snapshot [dict get $receipt projection_snapshot];set plane [dict get $snapshot working_plane]
    set map [::GX3DEProjection::create $snapshot $plane]
    set xy {};set worlds {}
    for {set i 0} {$i<25} {incr i} {
        set x [random -2 2];set y [random -2 2];lappend xy [list $x $y]
        set world {};foreach o [dict get $plane origin] u [dict get $plane u_axis] v [dict get $plane v_axis] {lappend world [expr {$o+$x*$u+$y*$v}]};lappend worlds $world
    }
    set golden [::GX3DEViewer::projection world_to_screen $worlds];set actual [$map map to_screen $xy]
    set inverse [$map map to_plane [dict get $actual points]]
    foreach native $golden projected [dict get $actual points] original $xy back [dict get $inverse points] {
        if {![dict get $native valid]} {error {Expected native front-facing point}}
        foreach a [lrange [dict get $native point] 0 1] b $projected {set maximum [expr {max($maximum,abs($a-$b))}]}
        foreach a $original b $back {set invmaximum [expr {max($invmaximum,abs($a-$b))}]}
        incr count
    }
    lappend frames [dict get $snapshot frame_id];$map dispose
}
if {$maximum>1e-8 || $invmaximum>1e-9} {error {Random normalized planes differ from native projection}}
::GX3DEViewer::close
set f [open [file join $output RECEIPT.tcldict] w];puts $f [dict create status PASS seed 21021 planes 6 points $count maximum_screen_error $maximum maximum_inverse_error $invmaximum frames $frames real_gui_acceptance 0];close $f
puts "PASS six deterministic random tilted native planes; $count points, max screen=$maximum, inverse=$invmaximum"
