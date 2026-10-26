# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root output mode input count
if {[file exists $output]} {error {Fresh private output required}}
file mkdir $output;set output [file normalize $output]
set profile $output
if {$mode eq {read}} {set f [open $input];set fixture [read $f];close $f;set profile [dict get $fixture profile]}
foreach {key dir} {HOME home XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $profile $dir];file mkdir $::env($key);file attributes $::env($key) -permissions 0700}
set started [clock microseconds];set argv0 __EXP01_MASS_DESCRIPTOR__;source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
set startup [expr {[clock microseconds]-$started}]
proc writeResult {output value} {set f [open [file join $output RESULT.tcldict] w];puts $f $value;close $f}
proc percentile {rows fraction} {set sorted [lsort -real $rows];return [lindex $sorted [expr {max(0,int(ceil([llength $sorted]*$fraction))-1)}]]}
proc rss {} {set f [open /proc/[pid]/status];try {set data [read $f]} finally {close $f};regexp -line {^VmRSS:\s+(\d+) kB} $data -> value;return $value}
if {$mode eq {prepare}} {
 ::GX::configurationSet storage.session_root [file join $output Sessions]
 ::GX::configurationSet storage.temp_dir [file join $output tmp]
 ::GX::configurationSet storage.cache_dir [file join $output cache]
 ::GX::configurationSave
 ::GX::projectCreate {EXP01 indexed mass admission} {One hundred synthetic scientific Documents}
 set session [::GX::createNewSession EXP01_indexed_mass {} 0]
 set f [open $input];set base [dict get [read $f] 1];close $f
 set documents {};set exact {};set rows {};set started [clock microseconds]
 for {set i 0} {$i<100} {incr i} {
  set model $base
  switch [expr {$i%3}] {0 {set plane {origin {0 0 0} normal {0 0 1} u_axis {1 0 0}}} 1 {set plane {origin {5 2 1} normal {1 0 0} u_axis {0 1 0}}} 2 {set plane {origin {2 5 3} normal {0 1 0} u_axis {1 0 0}}}}
  dict set model plane $plane
  set t [clock microseconds];set document [::GX::interactiveDocumentCreate core.native2d sketch gxtxt.native_cad_sketch.v1 1 [dict create model $model allocation_counter 1]]
  lappend rows [expr {[clock microseconds]-$t}];set id [dict get $document id];lappend documents $id;dict set exact $id $model
 }
 set elapsed [expr {[clock microseconds]-$started}]
 set f [open [file join $output FIXTURE.tcldict] w];puts $f [dict create profile $profile session $session documents $documents source_identity [::GX::interactiveDocumentSourceIdentities $documents]];close $f
 set f [open [file join $output EXACT.tcldict] w];puts $f $exact;close $f
 set rootCache [::GX::_nativeCadQuickRoot];set disk 0;foreach path [glob -nocomplain -directory $rootCache *] {incr disk [file size $path]}
 writeResult $output [dict create status PASS mode prepare startup_us $startup total_create_and_publish_us $elapsed samples_us $rows p50_us [percentile $rows .5] p95_us [percentile $rows .95] quick_open [::GX::nativeCadSketchQuickOpenStatus] disk_bytes $disk rss_kib [rss] documents 100]
} elseif {$mode eq {read}} {
 if {$count ni {10 50 100}} {error {Choose10,50,100}}
 set t [clock microseconds];::GX::openSessionPath [dict get $fixture session];set sessionOpen [expr {[clock microseconds]-$t}]
 set documents [lrange [dict get $fixture documents] 0 [expr {$count-1}]]
 set t [clock microseconds];set descriptors [::GX::nativeCadSketchQuickOpenList $documents mm 0];set listUs [expr {[clock microseconds]-$t}]
 dict for {id descriptor} $descriptors {if {[dict exists $descriptor unavailable]} {error {Expected existing indexed preview in new process}}}
 set rows {};set points 0;set payload 0;set started [clock microseconds]
 foreach id $documents {
  set t [clock microseconds];set snapshot [::GX::nativeCadSketchQuickOpenPresentation $id mm];lappend rows [expr {[clock microseconds]-$t}]
  incr points [dict get $snapshot descriptor points];incr payload [dict get $snapshot descriptor asset_bytes]
 }
 set elapsed [expr {[clock microseconds]-$started}]
 set warmStarted [clock microseconds];::GX::nativeCadSketchQuickOpenList $documents mm 0;set warmUs [expr {[clock microseconds]-$warmStarted}]
 if {[::GX::interactiveDocumentSourceIdentities $documents] ne [dict filter [dict get $fixture source_identity] key {*}$documents]} {error {Mass preview changed canonical source identity}}
 writeResult $output [dict create status PASS mode new_process_read documents $count startup_us $startup session_open_us $sessionOpen metadata_batch_us $listUs warm_metadata_batch_us $warmUs ready_preview_total_us $elapsed per_document_us $rows p50_us [percentile $rows .5] p95_us [percentile $rows .95] points $points descriptor_payload_bytes $payload cache [::GX::interactiveDocumentCacheStatus] rss_kib [rss] scientific_worker_started [expr {$::GX::Engine3D::worker ne {}}] os_cache_cold 0]
} else {error {Choose prepare or read}}
puts [dict create status PASS mode $mode result [file join $output RESULT.tcldict]]
