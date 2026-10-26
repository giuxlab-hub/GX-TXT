# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv framework output nativeFixtures nativeCase
if {[file exists $output]} {error {Fresh isolated output required}}
file mkdir $output
foreach {key dir} {XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $output $dir];file mkdir $::env($key)}
set argv0 __p021_projection_component__
set pins {}
foreach path {core/tcl/native2d_cad_canvas_v1.tcl core/tcl/native2d_cad_tools_v1.tcl core/tcl/native2d_cad_tools_constraints_v1.tcl core/tcl/native2d_cad_projection_v1.tcl core/native2d/bin/gx2dtcl.so} {dict set pins $path [lindex [exec sha256sum [file join $framework $path]] 0]}
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults
if {[llength [info commands ::GX::native2DCadProjectionAttach]]==0} {source [file join $framework core tcl native2d_cad_projection_v1.tcl]}
# The source loader above uses only public CORE, never Workbench private runtime.
# Main integration may already load the same adapter; do not redefine its class.
package require Tk
wm geometry . 900x700
set errors {}
proc bgerror {message} {lappend ::errors $message;puts stderr $::errorInfo}
proc check {condition label} {if {![uplevel 1 [list expr $condition]]} {error "FAIL $label"};puts "PASS $label";flush stdout}
# Contract fixture, explicitly not a Native3D camera acceptance test.
proc affineMapper {operation args} {
 switch -- $operation {
  info {return {frame_id 1 revision 1 width 900 height 650}}
  scale {return {valid 1 maximum_pixels_per_unit 80 domain visible_convex_plane_quad}}
  map {lassign $args direction rows;set points {};foreach point $rows {lassign $point x y;if {$direction eq {to_screen}} {lappend points [list [expr {450+60*$x+15*$y}] [expr {325-50*$y}]]} else {set ly [expr {(325-$y)/50.}];lappend points [list [expr {($x-450-15*$ly)/60.}] $ly]}};return [dict create points $points]}
 }
}
set mapping affineMapper;set nativeFrame {};set mapperHash {}
if {$nativeFixtures ne {}} {
    load [file join $nativeFixtures gx3de_projection_tcl_v1.so] Gx3deprojection
    set mapperHash [lindex [exec sha256sum [file join $nativeFixtures gx3de_projection_tcl_v1.so]] 0]
    set f [open [file join $nativeFixtures RECEIPT.tcldict]];set nativeReceipt [read $f];close $f
    set snapshot [dict get [lindex [dict get $nativeReceipt receipts] $nativeCase] snapshot]
    set mapping [::GX3DEProjection::create $snapshot [dict get $snapshot working_plane]]
    set nativeFrame [image create photo -file [file join $nativeFixtures frame-[expr {$nativeCase+1}].png]]
    wm geometry . [dict get $snapshot width]x[dict get $snapshot height]
}
::GX::native2DEnsure
set scene [::GX::Native2D::core scene]
set line [::GX::Native2D::core sketch_create $scene {family line controls {{-2 -1} {2 1}}} 257]
::GX::Native2D::core grid $scene {enabled 1 visible 1 spacing_x 1 spacing_y 1}
set spline [::GX::Native2D::core sketch_create $scene {family spline controls {{-3 2} {-1 3} {1 2} {3 3}}} 257]
canvas .c -background #21374d -width 900 -height 650 -highlightthickness 0
pack .c -fill both -expand 1
update
if {$nativeFrame eq {}} {set frame [.c create rectangle 0 0 900 700 -fill #21374d -tags native_frame]} else {set frame [.c create image 0 0 -anchor nw -image $nativeFrame -tags native_frame]}
set host [::GX::native2DCadCanvasAttach .c $scene {bind_events 1}]
set projection [::GX::native2DCadProjectionAttach $host $mapping]
$host render
update
lassign [$host world [$host device {1.25 -0.5}]] roundX roundY
check {abs($roundX-1.25)<1e-10 && abs($roundY+0.5)<1e-10} coordinate_roundtrip
set ref [$host pick [$host device {-2 -1}] detail]
check {[dict get $ref object]==$line && [dict get $ref semantic_kind] eq {control}} scientific_control_identity
set ref [$host pick [$host device {0 0}] detail]
check {[dict get $ref object]==$line && [dict get $ref semantic_kind] eq {segment}} scientific_segment_identity
check {[.c find withtag native_frame] eq $frame} native_frame_preserved
check {[.c cget -background] eq {#21374d}} background_preserved
check {[llength [.c find withtag native_sprite_scene]]==1 && [llength [.c find all]]<300} retained_geometry_with_bounded_axis_labels
check {[dict get [$projection info] ready]} adapter_ready
$host advanced
$host render
update
set inputs {}
proc pause {{milliseconds 80}} {set ::wait 1;after $milliseconds {set ::wait 0};vwait ::wait}
proc xt {args} {lappend ::inputs [list [clock microseconds] {*}$args];exec xdotool {*}$args}
proc point {xy} {lassign $xy x y;xt mousemove [expr {[winfo rootx .c]+int($x)}] [expr {[winfo rooty .c]+int($y)}];pause 40}
point [$host device {-2 -1}]
xt mousedown 1;pause
point [$host device {-1 0}]
xt mouseup 1;pause 150
set definition [::GX::Native2D::core sketch_definition $scene $line]
lassign [dict get [lindex [::GX::Native2D::core interaction_controls $scene $line] 0] point] editX editY
check {abs($editX+1)<0.04 && abs($editY)<0.04} actual_pointer_control_edit
check {![::GX::Native2D::core drag_active $scene] && ![dict get [$host state] active]} pointer_transaction_released
set before $definition
point [$host device {-1 0}];xt mousedown 1;pause
point [$host device {0 1}];xt key Escape;xt mouseup 1;pause
check {[::GX::Native2D::core sketch_definition $scene $line] eq $before} actual_escape_preserves_definition
set advanced [$host advanced];set cad [$host context]
$advanced dimension start distance [list [$cad selection reference $line object 0]]
set proposal [$advanced dimension preview [$host device {0 -1.5}]]
set dim [$advanced dimension apply 0 [dict get $proposal specification] 1 [dict get $proposal annotation]]
$host cancel completed_dimension;$host render;update
check {[llength [.c find withtag constraint_marker]]>=3} projected_dimension_drawn
set region [$advanced constraint present .c [list [dict get $dim id]]]
set label [dict get [$cad relationship dimension_geometry [dict get $dim id]] label]
set screen [$host projectNativePoint $label]
check {[$advanced constraint pick $screen $region]==[dict get $dim id]} projected_dimension_hit
check {[llength [.c find withtag native_frame]]==1} same_frame_after_dimensions
# Exercise the real native drag transaction, not just control-preview editing.
$host select [list [dict create kind object id $line index 0]]
$host activate [list $line]
$host tool translate;$host render;update
set nativeGizmo [::GX::Native2D::core render_gizmo $scene]
foreach primitive $nativeGizmo {
 if {[dict get $primitive handle] eq {free}} {lassign [dict get $primitive a] ax ay;lassign [dict get $primitive b] bx by;set handle [$host projectNativePoint [list [expr {($ax+$bx)/2}] [expr {($ay+$by)/2}]]];break}
}
set beforeMove [::GX::Native2D::core sketch_definition $scene $line]
set expectedStart [$host world [lmap value $handle {expr {int($value)}}]]
set expectedEnd [$host world [list [expr {int([lindex $handle 0]+60)}] [expr {int([lindex $handle 1])}]]]
set beforeMovePoint [dict get [lindex [::GX::Native2D::core interaction_controls $scene $line] 0] point]
point $handle;xt mousedown 1;pause
check {[::GX::Native2D::core drag_active $scene]} actual_native_drag_begin
lassign $handle hx hy
point [list [expr {$hx+60}] [expr {$hy}]];pause
xt mouseup 1;pause
set afterMove [::GX::Native2D::core sketch_definition $scene $line]
set afterMovePoint [dict get [lindex [::GX::Native2D::core interaction_controls $scene $line] 0] point]
set movedX [expr {[lindex $afterMovePoint 0]-[lindex $beforeMovePoint 0]}]
check {abs($movedX-([lindex $expectedEnd 0]-[lindex $expectedStart 0]))<0.025 && ![::GX::Native2D::core drag_active $scene]} projected_native_translate_commit
$host tool rotate;$host render;update
set ring {}
foreach primitive [::GX::Native2D::core render_gizmo $scene] {if {[dict get $primitive handle] eq {rotate} && [dict get $primitive kind] eq {line}} {set ring [dict get $primitive a];break}}
check {$ring ne {}} native_rotation_ring
set beforeRotate [::GX::Native2D::core sketch_definition $scene $line]
point [$host projectNativePoint $ring];xt mousedown 1;pause
check {[::GX::Native2D::core drag_active $scene]} projected_rotation_transaction_begin
set center [::GX::Native2D::core device $scene [dict get [::GX::Native2D::core pivot $scene] point]]
lassign $ring rx ry;lassign $center cx cy
point [$host projectNativePoint [list [expr {$cx-($ry-$cy)}] [expr {$cy-($rx-$cx)}]]];pause
xt mouseup 1;pause
check {[::GX::Native2D::core sketch_definition $scene $line] ne $beforeRotate && ![::GX::Native2D::core drag_active $scene]} projected_native_rotate_commit
# Public construction action on an actual mapped button and pointer events.
button .c.construct -text {Construct line} -command [list $advanced construction start line]
place .c.construct -x 8 -y 8
$host tool select;update
set canonicalBefore [::GX::Native2D::core ids $scene]
xt mousemove [expr {[winfo rootx .c.construct]+20}] [expr {[winfo rooty .c.construct]+10}] click 1;pause
point [$host device {-3 -2}];xt click 1;pause
point [$host device {-1 -2}];xt click 1;pause
set created {}
foreach id [::GX::Native2D::core ids $scene] {if {$id ni $canonicalBefore && $id ni [$host feedbackObjects]} {lappend created $id}}
check {[llength $created]==1 && [dict get [::GX::Native2D::core sketch_definition $scene [lindex $created 0]] family] eq {line}} actual_shared_construction
xt key Escape;pause
check {[dict get [$advanced state] construction] eq {}} actual_construction_cancel_returns_to_selection
set preserved [::GX::Native2D::core ids $scene]
xt mousemove [expr {[winfo rootx .c.construct]+20}] [expr {[winfo rooty .c.construct]+10}] click 1;pause
point [$host device {-2 -3}];xt click 1;pause
point [$host device {0 -3}];pause
xt key Escape;pause
check {[::GX::Native2D::core ids $scene] eq $preserved && [$host feedbackObjects] eq {}} cancelled_construction_has_no_scientific_object
check {[dict get [$projection info] cached_objects]<10} preview_cache_bounded
# Native screenshot of this actual mapped X11 Canvas, not a fabricated image.
destroy .c.construct
exec import -window [winfo id .] [file join $output component.png]
set stableIds [::GX::Native2D::core ids $scene]
proc invalidMapper {operation args} {
 switch -- $operation {
  info {return {frame_id invalid revision 2 width 640 height 480}}
  scale {return {valid 0 reason horizon}}
  map {return [dict create points [lmap row [lindex $args 1] {list}]]}
 }
}
$projection configure {mapping invalidMapper};$host render;update
check {![dict get [$projection info] ready] && [.c find withtag native_frame] eq $frame} horizon_rejection_preserves_native_frame
point {100 100};xt click 1;pause
check {[dict get [$host state] receipt status] eq {rejected} && [::GX::Native2D::core ids $scene] eq $stableIds && ![::GX::Native2D::core drag_active $scene]} actual_invalid_plane_input_rejected_without_mutation
$projection configure [dict create mapping $mapping];$host render;update
check {[dict get [$projection info] ready]} valid_plane_restores_after_rejection
check {$errors eq {}} no_background_errors
set image [image create photo]
# Native sprite Cairo item is inspected by MAIN2 screenshots in integrated GUI.
foreach path [dict keys $pins] {check {[lindex [exec sha256sum [file join $framework $path]] 0] eq [dict get $pins $path]} source_unchanged_during_component_test}
set f [open [file join $output result.tcllist] w]
puts $f [dict create source_files $pins mapper_sha256 $mapperHash source [exec git -C $framework rev-parse HEAD] host [$host state] projection [$projection info] native_case $nativeCase native_fixture $nativeFixtures inputs $inputs definition $definition errors $errors canvas_items [llength [.c find all]]]
close $f
set beforeDisposal [::GX::Native2D::core ids $scene]
$host dispose
check {[::GX::Native2D::core ids $scene] eq $beforeDisposal} consumer_science_survives_host_disposal
::GX::Native2D::core destroy $scene
destroy .
