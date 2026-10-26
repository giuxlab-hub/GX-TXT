# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root output
set root [file normalize $root];set output [file normalize $output]
if {[file exists $output]} {error {Use a new private output}}
file mkdir $output
foreach kind {CONFIG DATA CACHE STATE} {set ::env(XDG_${kind}_HOME) [file join $output [string tolower $kind]]}
set ::env(LIBGL_ALWAYS_SOFTWARE) 1
set ::env(LIBGL_ALWAYS_INDIRECT) 0
set ::env(GALLIUM_DRIVER) llvmpipe
set argv0 __P021_NATIVE_PROJECTION_TEST__
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults
load [file join $root core native3d bin libgx3de_viewer_tcl.so] Gx3deviewer
load [file join $root core native3d bin gx3de_projection_tcl_v1.so] Gx3deprojection
proc assert {condition message} {if {![uplevel 1 [list expr $condition]]} {error $message};puts "PASS $message"}
proc world {plane xy} {
    lassign [dict get $plane origin] ox oy oz;lassign [dict get $plane u_axis] ux uy uz;lassign [dict get $plane v_axis] vx vy vz;lassign $xy x y
    return [list [expr {$ox+$x*$ux+$y*$vx}] [expr {$oy+$x*$uy+$y*$vy}] [expr {$oz+$x*$uz+$y*$vz}]]
}
proc maxError {a b} {set error 0.0;foreach x $a y $b {set error [expr {max($error,abs($x-$y))}]};return $error}
set view [::GX::viewerSceneDefaults]
foreach {key value} {camera_position {5;7;9} camera_target {0;0;0} camera_up {0;0;1} vertical_fov_degrees 40 near_clip 0.01 far_clip 10000 working_plane_visible 1 working_plane_origin {0.7;-0.3;0.2} working_plane_u_axis {1;0;0}} {dict set view $key $value}
set scene [dict create view $view layers {} graphics_policy [::GX::native3dGraphicsPolicy]]
dict set scene graphics_policy execution Software
set initial [::GX3DEViewer::projection enable 1]
assert {![dict get $initial ready]} {Opt-in before render is bounded and does not create an engine}
set receipts {};set cases 0;set maxScreen 0;set maxLocal 0;set prior {}
foreach projection {perspective orthographic} {
    foreach normal {{0;0;1} {0.2;0.6;0.8}} {
        foreach figure {0 1} {
            dict set scene view projection $projection;dict set scene view working_plane_normal $normal
            dict set scene view orthographic_height 8
            if {$figure} {
                dict set scene scientific_figure [dict create axes_grid_visible 1 colorbar_visible 0 bounds_min {-2;-2;-2} bounds_max {2;2;2} axis_min {-2;-2;-2} axis_max {2;2;2} title {Projection margins} legend {Native scientific figure} scalar_label {} x_label X y_label Y z_label Z native_style {margin_left 0.17 margin_right 0.12 margin_top 0.22 margin_bottom 0.19}]
            } else {dict unset scene scientific_figure}
            incr cases
            set reply [::GX3DEViewer::render $scene [file join $output frame-$cases.png] 640 480 full]
            set snapshot [dict get $reply projection_snapshot];set plane [dict get $snapshot working_plane]
            set map [::GX3DEProjection::create $snapshot $plane]
            set rows {};for {set i 0} {$i<20} {incr i} {lappend rows [list [expr {($i%5-2)*0.37}] [expr {(int($i/5)-1.5)*0.41}]]}
            set worlds {};foreach xy $rows {lappend worlds [world $plane $xy]}
            set golden [::GX3DEViewer::projection world_to_screen $worlds]
            set actual [$map map to_screen $rows [dict create frame_id [dict get $snapshot frame_id] width 640 height 480]]
            foreach native $golden xy [dict get $actual points] valid [dict get $actual valid] {
                assert {[dict get $native valid] && $valid} {Native and cached mappings agree on front-facing validity}
                set maxScreen [expr {max($maxScreen,[maxError $xy [lrange [dict get $native point] 0 1]])}]
            }
            set inverse [$map map to_plane [dict get $actual points]]
            foreach original $rows xy [dict get $inverse points] valid [dict get $inverse valid] {
                assert {$valid} {Cached native ray intersects its normalized working plane}
                set maxLocal [expr {max($maxLocal,[maxError $xy $original])}]
            }
            set scale [$map scale]
            assert {[dict get $scale valid] && [dict get $scale maximum_pixels_per_unit]>0 && [llength [dict get $scale local_polygon]]==4} {Native visible-plane derivative bound and local domain are available}
            set tiny [$map map to_screen {{0 0} {0.000001 0} {0 0.000001}}]
            lassign [dict get $tiny points] p0 px py
            foreach p [list $px $py] {
                set observed [expr {hypot([lindex $p 0]-[lindex $p0 0],[lindex $p 1]-[lindex $p0 1])/0.000001}]
                assert {$observed<=[dict get $scale maximum_pixels_per_unit]*(1+1e-5)} {Conservative derivative bound covers local projected motion}
            }
            assert {[catch {$map map to_plane {{10 20}} {width 641}} reason] && [string first STALE_PROJECTION $reason]>=0} {Stale viewport size is rejected}
            assert {[catch {$map map to_plane {{10 20}} {frame_id invalid}} reason] && [string first STALE_PROJECTION $reason]>=0} {Stale camera/frame identity is rejected}
            assert {[catch {$map map to_plane {{NaN 0}}}]} {Malformed nonfinite coordinates are rejected}
            lappend receipts [dict create projection $projection figure $figure frame [dict get $snapshot frame_id] snapshot $snapshot]
            if {$prior ne {}} {assert {[dict get $snapshot frame_id] ne $prior} {Actual rendered frames receive distinct identities}}
            set prior [dict get $snapshot frame_id]
            $map dispose;assert {![llength [info commands $map]]} {Mapping resource disposal removes its native command}
        }
    }
}
assert {$maxScreen<1e-8 && $maxLocal<1e-10} {Native projection and cached plane inverse meet numerical equivalence}
set moved [::GX3DEViewer::navigate orbit 9 -4 [file join $output navigate.png]]
assert {[dict exists $moved projection_snapshot] && [dict get $moved projection_snapshot frame_id] ne $prior} {Native navigation frame carries matching projection metadata}
set sized [::GX3DEViewer::viewport 720 520 [file join $output resize.png]]
assert {[dict get $sized projection_snapshot width]==720 && [dict get $sized projection_snapshot height]==520} {Native resize receipt has actual target dimensions}
set currentPlane [dict get $sized projection_snapshot working_plane]
set fitted [::GX3DEViewer::projection fit_plane $currentPlane {-2 -1 2 1} [file join $output fit.png]]
assert {[dict get $fitted retained_extent_objects]==0 && [dict exists $fitted projection_snapshot]} {Native fit uses bounded temporary extent and retires it before rendering}
set height [dict get $fitted orthographic_height]
set zoomed [::GX3DEViewer::navigate zoom 1 0 [file join $output ortho-zoom.png]]
assert {[dict get $zoomed projection_snapshot orthographic_height]<$height} {Opt-in orthographic zoom retains the existing native zoom authority after fit}
set camera {};foreach key {camera_position camera_target camera_up projection near_clip far_clip vertical_fov_degrees orthographic_height} {dict set camera $key [dict get $fitted $key]}
foreach key {camera_position camera_target camera_up} {dict set camera $key [join [dict get $camera $key] {;}]}
set restored [::GX3DEViewer::camera $camera [file join $output restore-height.png]]
assert {abs([dict get $restored projection_snapshot orthographic_height]-$height)<1e-12} {Optional camera height roundtrip preserves the projected scale}
dict unset camera orthographic_height
set oldCamera [::GX3DEViewer::camera $camera [file join $output old-camera.png]]
assert {[dict exists $oldCamera projection_snapshot]} {Original seven-field camera request remains admitted}
::GX3DEViewer::projection disable
set old [::GX3DEViewer::navigate orbit -9 4 [file join $output disabled.png]]
assert {![dict exists $old projection_snapshot]} {Non-opt-in operation preserves original reply fields and skips sampling}
set snapshot [dict get [::GX3DEViewer::projection snapshot] projection_snapshot]
set normalPlane [dict get $snapshot working_plane]
set invalid $normalPlane;dict set invalid v_axis {1 0 0}
assert {[catch {::GX3DEProjection::create $snapshot $invalid}]} {Unnormalized or inconsistent plane frames are rejected}
set map [::GX3DEProjection::create $snapshot $normalPlane]
set batch {};for {set i 0} {$i<10000} {incr i} {lappend batch [list [expr {($i%100)*0.001}] [expr {(int($i/100))*0.001}]]}
set started [clock microseconds];set result [$map map to_screen $batch];set elapsed [expr {[clock microseconds]-$started}]
assert {[llength [dict get $result points]]==10000} {One native batch evaluates ten thousand points without worker RPC}
$map dispose
set f [open [file join $output RECEIPT.tcldict] w]
puts $f [dict create status PASS cases $cases maximum_screen_error $maxScreen maximum_local_error $maxLocal batch_points 10000 batch_microseconds $elapsed receipts $receipts real_gui_acceptance 0]
close $f
::GX3DEViewer::close
puts "PASS $cases native projection cases; maxscreen=$maxScreen maxlocal=$maxLocal batch_us=$elapsed"
