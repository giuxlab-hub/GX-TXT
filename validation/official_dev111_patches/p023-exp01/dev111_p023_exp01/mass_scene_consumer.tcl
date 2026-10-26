# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root output fixtureFile
if {[file exists $output]} {error {Fresh private output required}}
file mkdir $output;set output [file normalize $output]
set f [open $fixtureFile];set fixture [read $f];close $f
set profile [dict get $fixture profile]
foreach {key dir} {HOME home XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $profile $dir]}
set argv0 __EXP01_MASS_SCENE_CONSUMER__;source [file join $root gxtxt_pipeline.tcl];::GX::defaults;::GX::loadModuleCatalog
::GX::openSessionPath [dict get $fixture session]
namespace eval ::MassDemo {variable bindings {};variable status Ready;variable surface;variable view;variable output;variable fixture;variable started}
set ::MassDemo::fixture $fixture;set ::MassDemo::output $output
wm title . {GX-TXT · EXP01 100 Sketch scene admission · REVIEW ONLY};wm geometry . 1150x800+80+40
tk appname gxtxt_pipeline.tcl-EXP01-mass
::ttk::frame .tools;pack .tools -side top -fill x
::ttk::label .status -textvariable ::MassDemo::status;pack .status -side bottom -fill x
::ttk::frame .body;pack .body -fill both -expand 1
set ::MassDemo::view [::GX::native3DViewportCreate .body.view];pack .body.view -fill both -expand 1
::GX::native3DViewportBind $::MassDemo::view {kind demo}
set ::MassDemo::surface [::GX::native3DViewportSurface $::MassDemo::view]
proc ::MassDemo::save {name value} {variable output;set f [open [file join $output $name.tcldict] w];puts $f $value;close $f}
proc ::MassDemo::admit {} {
 variable bindings;variable surface;variable fixture;variable started;variable status
 if {[llength $bindings]} return
 set started [clock microseconds]
 foreach id [dict get $fixture documents] {lappend bindings [::GX::nativeCadSketchSceneAttach $surface $id]}
 set status {Waiting for completed native frame};after 20 ::MassDemo::poll
}
proc ::MassDemo::poll {} {
 variable bindings;variable surface;variable started;variable status;variable fixture
 set ready 1;foreach b $bindings {if {![$b ready]} {set ready 0}}
 if {!$ready} {after 20 ::MassDemo::poll;return}
 set elapsed [expr {[clock microseconds]-$started}]
 set identity [::GX::interactiveDocumentSourceIdentities [dict get $fixture documents]]
 if {$identity ne [dict get $fixture source_identity]} {error {Mass scene display changed scientific source identity}}
 save ADMITTED [dict create status PASS elapsed_us $elapsed count [llength $bindings] native [$surface resourcesInfo] source_unchanged 1 canvas_items [llength [[$surface canvas] find all]]]
 set status {100 native Sketches admitted; canonical Documents unchanged}
}
proc ::MassDemo::detach {} {variable bindings;variable status;foreach b $bindings {$b detach};set bindings {};set status {Detached display resources; Documents preserved}}
proc ::MassDemo::quit {} {variable surface;variable view;detach;$surface dispose;::GX::native3DViewportRelease $view;save DISPOSAL $::GX::NativeCadSketchScene::bindings;destroy .}
foreach {id label command} {admit {Admit 100 Sketches} ::MassDemo::admit detach {Detach displays} ::MassDemo::detach} {::ttk::button .tools.$id -text $label -command $command;pack .tools.$id -side left}
wm protocol . WM_DELETE_WINDOW ::MassDemo::quit
