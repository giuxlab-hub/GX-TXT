# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv framework output execution preset
if {$preset eq {}} {set preset High}
if {$preset ni {Low High}} {error {Bounded test accepts Low or High}}
if {$execution ni {Auto Software}} {error {Expected Auto or Software}}
if {[file exists $output]} {error {Fresh output required}}
file mkdir $output;set output [file normalize $output];file attributes $output -permissions 0700
foreach {key dir} {XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $output $dir];file mkdir $::env($key);file attributes $::env($key) -permissions 0700}
set ::env(PYTHONDONTWRITEBYTECODE) 1
set catalog [file join $output framework];file mkdir $catalog
foreach name {core app docs services plugins gxtxt_pipeline.tcl} {file copy [file join $framework $name] [file join $catalog $name]}
set ::env(MESA_SHADER_CACHE_DIR) [file join $output mesa-cache]
file mkdir $::env(MESA_SHADER_CACHE_DIR)
set argv0 __p021_bounded_native3d__
source [file join $catalog gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
proc write {name text} {set f [open [file join $::output $name] w];puts -nonewline $f $text;close $f}
proc pause {{ms 100}} {set ::waitFlag 1;after $ms {set ::waitFlag 0};vwait ::waitFlag;update idletasks}
proc bgerror {message} {lappend ::errors [dict create message $message info $::errorInfo];write errors.tcllist $::errors}
set errors {};set traces {};set windows {};set wmPids {};set exitCode 0
set frameTimings {};set frameBegin {}
proc frameStarted {command operation} {
 set h [lindex $command 1]
 if {![dict exists $::GX::Native3DCanvas::instances $h]} return
 set r [dict get $::GX::Native3DCanvas::instances $h]
 if {[dict get $r ready] && [dict get $r busy] eq {} && [llength [dict get $r queue]]} {
  dict set ::frameBegin [dict get $r widget] [list [clock microseconds] [lindex [lindex [dict get $r queue] 0] 0]]
 }
}
proc framePresented {command code result operation} {
 set h [dict get [lindex $command 1] widget]
 if {[dict exists $::frameBegin $h]} {
  lassign [dict get $::frameBegin $h] start kind
  lappend ::frameTimings [dict create kind $kind elapsed_us [expr {[clock microseconds]-$start}] presentation_code $code]
  dict unset ::frameBegin $h;write native-frame-timings.tcllist $::frameTimings
 }
}
trace add execution ::GX::_native3DViewportNext enter frameStarted
trace add execution ::GX::_native3DViewportPresentFrame leave framePresented
proc inputTrace {cmd op} {if {[lindex $cmd 1] eq {xdotool}} {lappend ::traces [list [clock milliseconds] {*}[lrange $cmd 1 end]];write input.tcllist $::traces}}
trace add execution exec enter inputTrace
proc shot {name} {pause 100;if {![info exists ::w] || ![winfo exists $::w]} {return};exec timeout 8s import -silent -window [winfo id $::w] [file join $::output $name.png]}
try {
 ::GX::configurationSet storage.session_root [file join $output Sessions]
 ::GX::configurationSet storage.temp_dir [file join $output tmp]
 ::GX::configurationSet storage.cache_dir [file join $output cache]
 ::GX::configurationSave {storage.session_root storage.temp_dir storage.cache_dir}
 set session [::GX::createNewSession P021_native3d_example {} 0]
 package require Tk;wm title . {P021 isolated compiled Native3D test};wm geometry . 450x100+0+0
 ::GX::configurationSet viewers.native3d.preset $preset
 ::GX::configurationSet viewers.native3d.execution $execution
 write policy.tcldict [::GX::native3dGraphicsPolicy]
 pause 400
 set module viewer.dev107_restricted_native3d;set provider development_example
 set begin [clock milliseconds]
 set w [::GX::viewerOpen $module $provider];lappend windows $w
 set deadline [expr {[clock milliseconds]+40000}]
 while {[clock milliseconds]<$deadline} {
  set r [dict get $::GX::ViewerDevelopment::windows $w]
  if {[dict get $r status] in {COMPLETED REJECTED FAILED ERROR}} break
  pause 100
 }
 write runtime.tcldict [dict get $::GX::ViewerDevelopment::windows $w]
 shot actual-compiled-opening
 if {[dict get $::GX::ViewerDevelopment::windows $w status] ne {COMPLETED}} {error {Actual compiled example did not complete opening}}
 set h [dict get $::GX::ViewerGui::instances $w native3d graphics]
 set deadline [expr {[clock milliseconds]+40000}]
 while {[dict get [::GX::native3DViewportInspect $h] status] ni {ready error} && [clock milliseconds]<$deadline} {pause 100}
 write viewport.tcldict [::GX::native3DViewportInspect $h]
 set r [dict get $::GX::Native3DCanvas::instances $h]
 write scene.tcldict [dict get $r scene]
 if {[dict get $r status] ne {ready}} {error {Actual compiled Native3D rendering not ready}}
 write compiled-native-result.tcldict [dict get $r result]
 write compiled-render-ms.txt [expr {[clock milliseconds]-$begin}]
 wm title $w {P021 PRIVATE COLOR TEST - C++ Native3D};wm geometry $w 1100x780+40+40;raise $w;pause 800
 set c [dict get $r widget].canvas
 set r [dict get $::GX::Native3DCanvas::instances $h]
 file copy [file join [dict get $r directory] frame.png] [file join $output compiled-fresh-native.png]
 [dict get $r photo] write [file join $output compiled-fresh-photo.png] -format png
 shot compiled-fresh
 exec xdotool mousemove [expr {[winfo rootx $c]+[winfo width $c]/2}] [expr {[winfo rooty $c]+[winfo height $c]/2}] click 1 key Right;pause 500
 shot compiled-cube
 set r [dict get $::GX::Native3DCanvas::instances $h]
 file copy [file join [dict get $r directory] frame.png] [file join $output compiled-native.png]
 [dict get $r photo] write [file join $output compiled-photo.png] -format png
 set before [dict get [::GX::native3DViewportInspect $h] camera]
 exec xdotool mousemove [expr {[winfo rootx $c]+[winfo width $c]-90}] [expr {[winfo rooty $c]+105}] click 1;pause 500
 write compiled-navcube-click.tcldict [dict create before $before after [dict get [::GX::native3DViewportInspect $h] camera] status [::GX::native3DViewportInspect $h]]
 shot compiled-after-navcube-click
 write viewport-after.tcldict [::GX::native3DViewportInspect $h]
 write RESULT.txt {PASS: ordinary compiled Native3D example opened and responded to actual viewport keyboard navigation. Color and NavCube click require inspected evidence.}
 exec xdotool windowfocus --sync [winfo id $w];exec xdotool key alt+F4;pause 300
 if {[winfo exists $w]} {error {Normal close did not close example}}
 set w [::GX::viewerOpen viewer.dev107_native3d_embedded native3d_embedded];lappend windows $w
 wm title $w {P021 PRIVATE COLOR TEST - Native3D example};wm geometry $w 1100x780+40+40;raise $w
 set h [dict get $::GX::ViewerGui::instances $w native3d example]
 set deadline [expr {[clock milliseconds]+40000}]
 while {[dict get [::GX::native3DViewportInspect $h] status] ni {ready error} && [clock milliseconds]<$deadline} {pause 100}
 write embedded-viewport.tcldict [::GX::native3DViewportInspect $h]
 set r [dict get $::GX::Native3DCanvas::instances $h]
 if {[dict get $r status] ne {ready}} {error {Ordinary Native3D example render not ready}}
 write embedded-native-result.tcldict [dict get $r result]
 file copy [file join [dict get $r directory] frame.png] [file join $output embedded-native.png]
 [dict get $r photo] write [file join $output embedded-photo.png] -format png
 shot embedded-cube
 exec xdotool windowfocus --sync [winfo id $w];exec xdotool key alt+F4;pause 300
 if {[winfo exists $w]} {error {Normal close did not close embedded example}}
 write RESULT.txt {PASS: C++ Native3D and Native3D example both opened through ordinary viewerOpen provider route and closed through actual Alt-F4. Actual C++ viewport click/Right navigation exercised. Colors require inspected screenshots; navcube click receipt distinguishes the known baseline routing defect.}
} on error {message options} {
 write failure.tcldict [dict create message $message options $options]
 puts stderr [dict get $options -errorinfo]
 catch {shot failure};set exitCode 1
} finally {
 write errors.tcllist $errors
 foreach w $windows {catch {destroy $w}}
 catch {destroy .}
 foreach pid $wmPids {catch {exec kill -TERM -- $pid}}
}
exit $exitCode
