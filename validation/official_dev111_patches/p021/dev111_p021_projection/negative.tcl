# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root successful output
if {[file exists $output]} {error {Use a new private output}}
file mkdir $output
set f [open $successful];set receipt [read $f];close $f
set original [dict get [lindex [dict get $receipt receipts] end] snapshot]
load [file join $root core native3d bin gx3de_projection_tcl_v1.so] Gx3deprojection
proc assert {condition message} {if {![uplevel 1 [list expr $condition]]} {error $message};puts "PASS $message"}
proc subtract {a b} {set result {};foreach x $a y $b {lappend result [expr {$x-$y}]};return $result}
proc normalized {a} {lassign $a x y z;set length [expr {sqrt($x*$x+$y*$y+$z*$z)}];return [list [expr {$x/$length}] [expr {$y/$length}] [expr {$z/$length}]]}
proc cross {a b} {lassign $a x y z;lassign $b u v w;return [list [expr {$y*$w-$z*$v}] [expr {$z*$u-$x*$w}] [expr {$x*$v-$y*$u}]]}
set plane [dict get $original working_plane];set camera [dict get $original camera_origin];set behind {}
foreach c $camera p [dict get $plane origin] {lappend behind [expr {2*$c-$p}]}
dict set plane origin $behind
set map [::GX3DEProjection::create $original $plane]
foreach direction {to_screen to_plane} {
    set value [$map map $direction {{0 0}}]
    assert {![lindex [dict get $value valid] 0] && [lindex [dict get $value reason] 0] eq {behind_camera}} {Behind-camera geometry/input is explicitly unavailable}
}
$map dispose
set n [normalized [dict get $original depth1_dx]];set u [normalized [dict get $original depth1_dy]];set v [cross $n $u]
set edgePlane [dict create origin [dict get $original depth1_origin] normal $n u_axis $u v_axis $v]
set map [::GX3DEProjection::create $original $edgePlane]
set value [$map map to_plane {{0 0}}]
assert {![lindex [dict get $value valid] 0] && [lindex [dict get $value reason] 0] eq {edge_on}} {Edge-on ray-plane intersection is rejected without fabricated coordinates}
set scale [$map scale]
assert {![dict get $scale valid]} {Edge-on presentation has no fabricated finite density bound}
$map dispose
set plane [dict get $original working_plane]
foreach {key value} [list width 0 frame_id "bad\x00identity" revision -1] {
    set invalid $original;dict set invalid $key $value
    assert {[catch {::GX3DEProjection::create $invalid $plane}]} {Malformed snapshot fields are refused}
}
set map [::GX3DEProjection::create $original $plane]
assert {[catch {$map map to_screen [lrepeat 262145 {0 0}]}]} {Excessive batch count is refused before point conversion}
assert {[catch {$map map to_screen {{0 0}} [dict create frame_id "[dict get $original frame_id]\x00suffix"]}]} {Opaque frame guard does not truncate embedded NUL}
$map dispose
set f [open [file join $output RECEIPT.tcldict] w];puts $f [dict create status PASS behind_camera 1 edge_on 1 malformed_frames 3 batch_limit 262144 frame_nul_guard 1 real_gui_acceptance 0];close $f
