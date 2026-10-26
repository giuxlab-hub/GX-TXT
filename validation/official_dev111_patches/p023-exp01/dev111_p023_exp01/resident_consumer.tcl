# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root output
if {[file exists $output]} {error {Fresh consumer output required}}
file mkdir $output;set output [file normalize $output]
foreach {key dir} {HOME home XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $output $dir];file mkdir $::env($key);file attributes $::env($key) -permissions 0700}
set argv0 __EXP01_INDEPENDENT_CONSUMER__;source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
::GX::configurationSet storage.session_root [file join $output Sessions]
::GX::configurationSet storage.temp_dir [file join $output tmp]
::GX::configurationSet storage.cache_dir [file join $output cache]
::GX::configurationSave
::GX::projectCreate {EXP01 independent scene consumer} {Private synthetic science}
set session [::GX::createNewSession Resident_consumer {} 0]
::GX::native2DEnsure
namespace eval ::ResidentDemo {variable documents {};variable bindings {};variable editor {};variable selected {};variable status {Select a saved Sketch in the viewport, then Open picked};variable view;variable surface;variable output}
set ::ResidentDemo::output $output
set scene [::GX::Native2D::core scene]
try {
 set controls {};for {set i 0} {$i<=10} {incr i} {lappend controls [list [expr {-3+$i*.6}] [expr {.18*sin($i*.7)}]]}
 set object [::GX::Native2D::core sketch_create $scene [dict create family polyline controls $controls] 257]
 ::GX::Native2D::core object_style $scene $object {color {0.96 0.22 0.12 1} line_width 3}
 set entry [dict create definition [::GX::Native2D::core sketch_definition $scene $object] style [::GX::Native2D::core object_style $scene $object] direction [::GX::Native2D::core direction_marker $scene $object] role [::GX::Native2D::core identity_geometry_role $scene $object] name [::GX::Native2D::core identity_name $scene $object] attributes [::GX::Native2D::core identity_attributes $scene $object]]
 set planeIndex 0
 foreach plane {{origin {0 0 0} normal {0 0 1} u_axis {1 0 0}} {origin {0 0 0.8} normal {0 1 1} u_axis {1 0 0}} {origin {0 0 -1.3} normal {1 1 0} u_axis {0 0 1}}} {
  set model [dict create format gxtxt.native_cad_sketch.v1 working_unit mm plane $plane object/s1 $entry]
  if {[incr planeIndex]==3} {dict set model object/s1 style line_style 1}
  lappend ::ResidentDemo::documents [dict get [::GX::interactiveDocumentCreate core.native2d sketch gxtxt.native_cad_sketch.v1 1 [dict create model $model allocation_counter 1]] id]
 }
} finally {::GX::Native2D::core destroy $scene}
tk appname gxtxt_pipeline.tcl-EXP01-independent
wm title . {GX-TXT · EXP01 independent resident Sketch consumer · NOT FOR INSTALLATION}
wm geometry . 1240x850+60+60
wm minsize . 950 650
::ttk::frame .tools;pack .tools -side top -fill x
::ttk::label .status -textvariable ::ResidentDemo::status -anchor w;pack .status -side bottom -fill x
::ttk::frame .editor;pack .editor -side bottom -fill x
::ttk::frame .body;pack .body -fill both -expand 1
set ::ResidentDemo::view [::GX::native3DViewportCreate .body.view [dict create projection orthographic axes_world 1]]
pack .body.view -fill both -expand 1
::GX::native3DViewportBind $::ResidentDemo::view {kind demo}
set ::ResidentDemo::surface [::GX::native3DViewportSurface $::ResidentDemo::view]
proc ::ResidentDemo::receipt {name value} {variable output;set f [open [file join $output $name.tcldict] w];puts $f $value;close $f}
proc ::ResidentDemo::closeEditor {} {
 variable editor;variable status
 if {$editor ne {} && [llength [info commands $editor]]} {set result [$editor close];if {[dict get $result status] eq {cancelled}} {return 0};set editor {}}
 set status {Editor closed; saved Sketches remain resident and selectable}
 return 1
}
proc ::ResidentDemo::edit {request} {
 variable editor;variable view;variable status
 if {![closeEditor]} return
 set id [dict get $request document_id]
 set editor [::GX::nativeCadSketchCreate .editor [dict create document_id $id working_unit mm viewport $view]]
 pack [$editor widget] -fill x
 $editor canvasControls
 set status "Editing $id · shared Native2D tools · Space-drag navigates3D"
 receipt EDIT_OPEN [$editor state]
}
proc ::ResidentDemo::openIndex {index} {variable documents;edit [dict create document_id [lindex $documents $index]]}
proc ::ResidentDemo::picked {owner event detail} {
 variable surface;variable selected;variable status
 set receipt [::GX::nativeCadSketchSceneResolvePick $surface [dict get $detail native_pick]]
 if {$receipt ne {}} {set selected [dict get $receipt binding];set status "Picked exact Document [dict get $receipt document_id]; Open picked enters editing";receipt PICKED $receipt}
}
proc ::ResidentDemo::openPicked {} {variable selected;if {$selected ne {}} {$selected edit}}
proc ::ResidentDemo::save {} {variable editor;if {$editor ne {}} {receipt SAVE [$editor save]}}
proc ::ResidentDemo::project {projection} {variable view;::GX::native3DViewportCamera $view [dict create projection $projection]}
proc ::ResidentDemo::show {index visible} {variable bindings;[lindex $bindings $index] show $visible}
proc ::ResidentDemo::quit {} {
 variable bindings;variable surface;variable view
 if {![closeEditor]} return
 foreach binding $bindings {if {[llength [info commands $binding]]} {$binding detach}}
 $surface dispose;::GX::native3DViewportRelease $view
 receipt DISPOSAL [dict create bindings $::GX::NativeCadSketchScene::bindings source_documents [::GX::interactiveDocumentList core.native2d sketch]]
 destroy .
}
foreach {id label command} {
 editA {Edit A} {::ResidentDemo::openIndex 0}
 editB {Edit B} {::ResidentDemo::openIndex 1}
 editC {Edit C} {::ResidentDemo::openIndex 2}
 picked {Open picked} ::ResidentDemo::openPicked
 save Save ::ResidentDemo::save
 close {Close editor} ::ResidentDemo::closeEditor
 hideB {Hide B} {::ResidentDemo::show 1 0}
 showB {Show B} {::ResidentDemo::show 1 1}
 ortho Orthographic {::ResidentDemo::project orthographic}
 persp Perspective {::ResidentDemo::project perspective}
} {::ttk::button .tools.$id -text $label -command $command;pack .tools.$id -side left -padx 2 -pady 3}
foreach document $::ResidentDemo::documents {lappend ::ResidentDemo::bindings [::GX::nativeCadSketchSceneAttach $::ResidentDemo::surface $document [dict create working_unit mm edit_command ::ResidentDemo::edit]]}
::GX::native3DViewportSubscribe $::ResidentDemo::view selected ::ResidentDemo::picked
wm protocol . WM_DELETE_WINDOW ::ResidentDemo::quit
::ResidentDemo::receipt FIXTURE [dict create session $session documents $::ResidentDemo::documents source_identity [::GX::interactiveDocumentSourceIdentities $::ResidentDemo::documents] imported_workbench_procedures [info procs ::GX::Workbench3D::*]]
