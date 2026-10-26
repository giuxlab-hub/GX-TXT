# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv framework output
if {[file exists $output]} {error {Fresh private output required}}
file mkdir $output
foreach {key dir} {XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $output $dir];file mkdir $::env($key)}
set argv0 __p021_sprite_alpha__
source [file join $framework gxtxt_pipeline.tcl];::GX::defaults
package require Tk
wm geometry . 210x210+0+0
canvas .c -width 210 -height 210 -background blue -highlightthickness 0
pack .c -fill both -expand 1
# Actual unchanged Native3D renderer frames, not a substitute opaque CAD layer.
unset -nocomplain ::env(LIBGL_ALWAYS_INDIRECT)
set ::env(LIBGL_ALWAYS_SOFTWARE) 1;set ::env(GALLIUM_DRIVER) llvmpipe
load [file join $framework core native3d bin libgx3de_viewer_tcl.so] Gx3deviewer
set view [::GX::viewerSceneDefaults]
dict set view navigation_cube_visible 0;dict set view background_rgb {0;0;1}
dict set view camera_position {0;0;5};dict set view camera_target {0;0;0};dict set view camera_up {0;1;0}
dict set view projection orthographic;dict set view orthographic_height 4;dict set view lighting 0
set solid [dict create layer_order 0 source_mode memory_geometry visible 1 opacity 1 representation surface base_color {1;0;0} line_width 1 point_size 2 backface_culling 0 scalar_coloring 0 vertices {{-2 -2 0} {0 -2 0} {0 2 0} {-2 2 0}} triangles {{0 1 2} {0 2 3}}]
set scene [dict create view $view layers [dict create solid $solid] graphics_policy [::GX::native3dGraphicsPolicy]]
dict set scene graphics_policy execution Software
::GX3DEViewer::render $scene [file join $output red-native-frame.png] 210 210 full
set photo [image create photo -file [file join $output red-native-frame.png]]
set frame [.c create image 0 0 -anchor nw -image $photo -tags native_frame]
dict set scene view background_rgb {1;1;1}
::GX3DEViewer::render $scene [file join $output white-native-frame.png] 210 210 full
::GX::native2DEnsure
set errors {};set checks {};set pixels {}
proc bgerror {message} {lappend ::errors $message;puts stderr $::errorInfo}
proc check {condition label} {if {![uplevel 1 [list expr $condition]]} {error "FAIL $label"};lappend ::checks $label;puts "PASS $label";flush stdout}
proc rect {fill a b c d} {return [dict create kind rectangle points [list [list $a $b] [list $c $d]] fill $fill stroke {}]}
proc pixel {image x y expected} {
    set raw [exec convert $image -format [format {%%[pixel:p{%d,%d}]} $x $y] info:]
    if {![regexp {s?rgb\(([0-9]+),([0-9]+),([0-9]+)\)} $raw -> r g b]} {error "Unexpected native screenshot pixel: $raw"}
    set actual [list $r $g $b];lappend ::pixels [dict create image $image x $x y $y actual $actual expected $expected]
    foreach got $actual want $expected {if {abs($got-$want)>2} {error "Pixel mismatch actual=$actual expected=$expected"}}
}
set rows [list [dict create id alpha geometry [list [rect {rgb #00ff00 alpha 0.5} 20 20 90 90]]] [dict create id legacy geometry [list [rect {light blue} 110 20 180 90]]] [dict create id invisible geometry [list [rect {rgb #00ff00 alpha 0} 20 150 90 190]]] [dict create id backgroundAlpha geometry [list [rect {rgb #00ff00 alpha 0.5} 110 150 180 190]]] [dict create id stroke geometry [list [dict create kind line points {{20 120} {180 120}} stroke {rgb #0000ff alpha 0.25} width 10]]]]
::GX::native2DSpriteSceneBatch .c $rows
update
exec import -silent -window [winfo id .] [file join $output red-frame.png]
pixel [file join $output red-frame.png] 50 50 {127 128 0}
pixel [file join $output red-frame.png] 140 50 {173 216 230}
pixel [file join $output red-frame.png] 100 120 {191 0 64}
pixel [file join $output red-frame.png] 50 170 {255 0 0}
pixel [file join $output red-frame.png] 140 170 {0 128 127}
pixel [file join $output red-frame.png] 160 120 {0 0 255}
check {1} actual_alpha_composites_over_red_frame
check {[::GX::native2DSpriteSceneHit .c {50 170} 0] eq {}} alpha_zero_not_painted_or_hit
check {[::GX::native2DSpriteSceneHit .c {50 50} 0] eq {alpha}} visible_alpha_remains_hit_testable
$photo configure -file [file join $output white-native-frame.png]
.c configure -background white
update
exec import -silent -window [winfo id .] [file join $output white-frame.png]
pixel [file join $output white-frame.png] 50 50 {127 128 0}
pixel [file join $output white-frame.png] 100 120 {191 0 64}
pixel [file join $output white-frame.png] 50 170 {255 0 0}
pixel [file join $output white-frame.png] 140 170 {127 255 127}
pixel [file join $output white-frame.png] 160 120 {191 191 255}
check {1} unchanged_sprite_blends_over_changed_frame_pixels
set before [::GX::native2DSpriteSceneDescribe .c]
foreach color {{rgb red alpha -0.1} {rgb red alpha 1.1} {rgb red alpha NaN} {rgb red alpha invalid} {alpha 0.5} {rgb red alpha 0.5 unknown 1}} {
    set row [dict create id invalid geometry [list [rect $color 0 0 10 10]]]
    check {[catch {::GX::native2DSpriteSceneBatch .c [list [dict create id alpha position {20 20}] $row]}]} invalid_descriptor_rejects_atomic_batch
    check {[dict get [::GX::native2DSpriteSceneDescribe .c alpha] position] eq {0.0 0.0}} rejected_batch_preserves_existing_sprite
}
# Named legacy strings that happen to parse as a two-word Tcl dictionary retain
# their Tk meaning; the rgb descriptor does not contaminate the legacy cache.
::GX::native2DSpriteSceneBatch .c [list [dict create id cached geometry [list [rect #00ff00 110 150 180 190]]]]
update
exec import -silent -window [winfo id .] [file join $output legacy-cache.png]
pixel [file join $output legacy-cache.png] 140 170 {0 255 0}
check {[llength [.c find all]]==2 && [.c find withtag native_frame] eq $frame} single_retained_item_preserves_frame
check {$errors eq {}} no_background_errors
set f [open [file join $output RESULT.tcldict] w]
puts $f [dict create checks $checks pixels $pixels errors $errors native_binary_sha256 [lindex [exec sha256sum [file join $framework core native2d bin gx2dtcl.so]] 0] source_sha256 [lindex [exec sha256sum [file join $framework core native2d gx2d_sprite_scene_v1.cpp]] 0]]
close $f
::GX::native2DSpriteSceneDispose .c
check {[winfo exists .c] && [.c find withtag native_frame] eq $frame} disposal_preserves_canvas_frame
::GX3DEViewer::close
destroy .
