lassign $argv framework output
if {[file exists $output]} {error {Fresh private output required}}
file mkdir $output;set output [file normalize $output]
foreach {key dir} {XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $output $dir];file mkdir $::env($key)}
set argv0 __p018_responsibility__
source [file join $framework gxtxt_pipeline.tcl];::GX::defaults
::GX::configurationSet storage.session_root [file join $output Sessions]
::GX::configurationSet storage.temp_dir [file join $output tmp]
::GX::configurationSave {storage.session_root storage.temp_dir}
::GX::loadModuleCatalog
set session [::GX::createNewSession p018_responsibility {} 0]
package require Tk;wm withdraw .
set sourceStack {};set sourceOrder {};set owners {};set renames {}
proc sourceTrace {args} {
 set cmd [lindex $args 0];set op [lindex $args end]
 if {$op eq {enter}} {set file [file normalize [lindex $cmd end]];lappend ::sourceStack $file;lappend ::sourceOrder $file} else {set ::sourceStack [lrange $::sourceStack 0 end-1]}
}
proc procTrace {cmd op} {
 set name [lindex $cmd 1]
 if {![string match ::GX::CurveWorkbench::* $name]} return
 dict set ::owners $name [lindex $::sourceStack end]
}
proc renameTrace {cmd op} {
 lassign $cmd ignore from to
 if {![string match ::GX::CurveWorkbench::* $from]} return
 lappend ::renames [list $from $to [lindex $::sourceStack end]]
 if {[dict exists $::owners $from]} {if {$to ne {}} {dict set ::owners $to [dict get $::owners $from]};dict unset ::owners $from}
}
trace add execution ::source {enter leave} sourceTrace
trace add execution ::proc enter procTrace
trace add execution ::rename enter renameTrace
set w [::GX::viewerOpen viewer.curve_workbench curve_workbench {workspace_id new workspace_name {P018 active responsibility audit}}]
trace remove execution ::source {enter leave} sourceTrace
trace remove execution ::proc enter procTrace
trace remove execution ::rename enter renameTrace
set f [open [file join $output source-order.tcllist] w];puts $f $sourceOrder;close $f
set f [open [file join $output rename-chains.tcllist] w];puts $f $renames;close $f
set selected {_mouseDown _mouseMove _mouseUp _pointerDownSelection _pointerMoveSelection _pointerUpSelection _sketchPick _semanticApply _pointSyncApply _cadGestureBegin _cadGestureMove _cadGestureCommit _cadCancel _pointerDownRetained _pointerMoveControl _pointerUpControl _sketchIdle _cancelGesture _constructionPlacement _constructionPreview _createCommit _constraintStart _constraintCommit _dimensionDraw _inlineOpen _inlineCommit _constraintCoordinateGuard _partHit _partAction _pointerDownPart _joinSource _split _separate _draw _history _restoreSnapshot _wheel _middlePan _cadCanvas _cadCanvasAdmit}
set records {}
foreach short $selected {
 set name ::GX::CurveWorkbench::$short
 if {![llength [info procs $name]]} {dict set records $short unavailable;continue}
 set callers {}
 foreach proc [info procs ::GX::CurveWorkbench::*] {if {[string first $short [info body $proc]]>=0} {lappend callers $proc}}
 dict set records $short [dict create owner [dict get $owners $name] arguments [info args $name] body [info body $name] callers $callers]
}
set f [open [file join $output active-procedures.tcldict] w];puts $f $records;close $f
set f [open [file join $output RESULT.txt] w];puts $f {PASS source/load-order audit only; no GUI operation claim};close $f
puts {PASS actual source chain and final procedure ownership recorded}
exit 0
