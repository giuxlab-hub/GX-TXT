# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root output
if {[file exists $output]} {error {Fresh isolated output required}}
file mkdir $output
namespace eval ::GX {}
source [file join $root core tcl native3d_gui_host_v2.tcl]
set checks {};set mode Auto;set stops 0;set starts 0;set valid 1
proc check {condition label} {
    if {![uplevel 1 [list expr $condition]]} {error "FAIL $label"}
    lappend ::checks $label;puts "PASS $label"
}
proc ::GX::native3dGraphicsPolicy {} {return [dict create execution $::mode]}
proc ::GX::datasetPublicationV2DictDefault {d k value} {if {[dict exists $d $k]} {return [dict get $d $k]};return $value}
rename ::GX::_native3DViewportStop ::GX::_native3DViewportStop_real
proc ::GX::_native3DViewportStop {h} {incr ::stops;dict set ::GX::Native3DCanvas::instances $h queue {};dict set ::GX::Native3DCanvas::instances $h worker {}}
rename ::GX::_native3DViewportStart ::GX::_native3DViewportStart_real
proc ::GX::_native3DViewportStart {h args} {incr ::starts}
rename ::GX::_native3DViewportValid ::GX::_native3DViewportValid_real
proc ::GX::_native3DViewportValid {h} {return $::valid}
proc .fixture.status {args} {}
set log [file join $output worker.log];set f [open $log w];puts -nonewline $f "[string repeat X 9000]TAIL OpenGL unavailable";close $f
set request [list render [dict create scientific_id native-17 geometry {exact unchanged} graphics_policy {execution Auto msaa 4x}] frame.png 640 480 full]
set pending [list [list navigate [list navigate orbit 7 3 frame.png]]]
set base [dict create software_retry 0 frame_presented 0 ready 1 busy render worker owned queue $pending source {kind demo} widget .fixture active_request $request worker_log $log projection_users 1]
set ::GX::Native3DCanvas::instances [dict create h $base]
check {[::GX::_native3DViewportSoftwareRetry h {Native3D renderer exited} 1]==1} initialAutoDeathRetries
set r [dict get $::GX::Native3DCanvas::instances h]
check {$stops==1 && $starts==1 && [dict get $r software_retry]==1} exactlyOneOwnedRestart
check {[dict get $r queue] eq [concat [list [list projection {projection enable 1}] [list render $request]] $pending]} exactFrameQualityAndOrderedPendingInput
check {[string length [dict get $r hardware_error]]<4200 && [string match {*TAIL OpenGL unavailable} [dict get $r hardware_error]]} boundedTailRetained
check {[::GX::_native3DViewportSoftwareRetry h again 1]==0 && $starts==1} noRepeatedRetry
foreach execution {Software Hardware} {
    set mode $execution;dict set ::GX::Native3DCanvas::instances h $base
    check {[::GX::_native3DViewportSoftwareRetry h failure 1]==0} "explicit${execution}NeverOverridden"
}
set mode Auto
foreach {key value label} {frame_presented 1 completedFrame ready 0 noGreeting busy camera cameraCommand software_retry 1 secondFailure} {
    set r $base;dict set r $key $value;dict set ::GX::Native3DCanvas::instances h $r
    check {[::GX::_native3DViewportSoftwareRetry h failure 1]==0} "noReplay_$label"
}
dict set ::GX::Native3DCanvas::instances h $base
check {[::GX::_native3DViewportSoftwareRetry h {Native renderer: Invalid native source identity} 0]==0} scientificErrorNotRetried
check {[::GX::_native3DViewportSoftwareRetry h {Native renderer: render scene: UNSUPPORTED; requested MSAA 4x unavailable on framebuffer} 0]==1} structuredGraphicsInitializationFailureRetries
set r $base;dict set r source {kind cell_field};dict set r projection_users 0;dict set ::GX::Native3DCanvas::instances h $r
check {[::GX::_native3DViewportSoftwareRetry h {Native renderer exited} 1]==1} cellFieldRecovery
check {[lindex [dict get $::GX::Native3DCanvas::instances h queue] 0] eq {capabilities capabilities}} capabilitiesRechecked
set count $starts;set valid 0;dict set ::GX::Native3DCanvas::instances h $base
check {[::GX::_native3DViewportSoftwareRetry h failure 1]==1 && $starts==$count} staleSourceHandledWithoutRestart
rename ::GX::_native3DViewportFail ::GX::_native3DViewportFail_real
proc ::GX::_native3DViewportFail {h message args} {set ::failure $message}
set bad [file join $output malformed-reply.txt]
set f [open $bad w];puts $f "error \{";close $f
set f [open $bad r];set r $base;dict set r generation 1;dict set r timer {};dict set r worker $f
dict set ::GX::Native3DCanvas::instances h $r
set failure {};set outcome [catch {::GX::_native3DViewportReadable h 1} problem];close $f
check {$outcome==0 && [string match {Invalid Native3D worker response*} $failure]} malformedReplyFailsWithoutTclException
set f [open [file join $output CHECKS.tcllist] w];puts $f $checks;close $f
puts "PASS [llength $checks] graphics recovery contract checks; GUI qualification separate"
