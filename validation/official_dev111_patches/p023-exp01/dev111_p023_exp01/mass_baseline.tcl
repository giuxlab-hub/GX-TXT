# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root output modelsFile
if {[file exists $output]} {error {Fresh private output required}}
file mkdir $output;set output [file normalize $output]
foreach {key dir} {HOME home XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $output $dir];file mkdir $::env($key);file attributes $::env($key) -permissions 0700}
set argv0 __EXP01_MASS_PROFILE__;source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
::GX::configurationSet storage.session_root [file join $output Sessions]
::GX::configurationSet storage.temp_dir [file join $output tmp]
::GX::configurationSet storage.cache_dir [file join $output cache]
::GX::configurationSave
set project [::GX::projectCreate {EXP01 quick-open study} {Isolated synthetic scientific Documents only}]
set session [::GX::createNewSession EXP01_mass {} 0]
::GX::native2DEnsure
if {![llength [info commands ::GX::nativeCadSketchCreate]]} {source [file join $root core tcl native_cad_sketch_v1.tcl]}
set f [open $modelsFile r];set models [read $f];close $f
set base [dict get $models 1];set documents {};set exact {};set result {};set started [clock seconds]
for {set i 0} {$i<100} {incr i} {
 set model $base
 switch [expr {$i%3}] {
  0 {set frame {origin {0 0 0} normal {0 0 1} u_axis {1 0 0}}}
  1 {set frame {origin {5 2 1} normal {1 0 0} u_axis {0 1 0}}}
  2 {set frame {origin {2 5 3} normal {0 1 0} u_axis {1 0 0}}}
 }
 dict set model plane $frame
 set receipt [::GX::interactiveDocumentCreate core.native2d sketch gxtxt.native_cad_sketch.v1 1 [dict create model $model allocation_counter 1]]
 set id [dict get $receipt id];lappend documents $id;dict set exact $id $model
}
set f [open [file join $output EXACT.tcldict] w];puts $f $exact;close $f
foreach count {10 50 100} {
 set begin [clock microseconds];set metadata [::GX::interactiveDocumentList core.native2d sketch];set metadataUs [expr {[clock microseconds]-$begin}]
 set rows {};set totalPoints 0
 foreach id [lrange $documents 0 [expr {$count-1}]] {
  if {[clock seconds]-$started>300} {error {Bounded mass baseline deadline exceeded}}
  set start [clock microseconds];set snapshot [::GX::nativeCadSketchDocumentPresentation $id mm];set elapsed [expr {[clock microseconds]-$start}]
  set points 0;dict for {layer record} [dict get $snapshot layers] {incr points [llength [dict get $record vertices]]}
  incr totalPoints $points;lappend rows [dict create id $id display_us $elapsed points $points]
 }
 dict set result $count [dict create metadata_batch_us $metadataUs registry_documents [llength $metadata] full_display_rows $rows total_points $totalPoints]
 set f [open [file join $output RESULT.tcldict] w];puts $f $result;close $f
}
foreach id $documents {if {[dict get [::GX::interactiveDocumentRead $id] payload model] ne [dict get $exact $id]} {error {Display modified authoritative geometry}}}
set f [open [file join $output FIXTURE.tcldict] w];puts $f [dict create status PASS scope {API scientific/display benchmark; not GUI acceptance} session $session documents $documents source_models_sha256 [::GX::sha256File [file join $output EXACT.tcldict]] seconds [expr {[clock seconds]-$started}]];close $f
puts [dict create status PASS documents [llength $documents] seconds [expr {[clock seconds]-$started}]]
