lassign $argv root out mode rowCounts
if {$rowCounts eq {}} {set rowCounts {10 1000 20000}}
foreach rowCount $rowCounts {if {$rowCount ni {10 1000 20000}} {error {Only10,1000,20000 benchmark rows are authorized}}}
set root [file normalize $root];set out [file normalize $out]
if {$mode ni {baseline native} || [file exists $out] || $::env(DISPLAY) ne {:1}} {error {Expected framework, new output, baseline|native and actual leased DISPLAY :1}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out $key]}
unset -nocomplain ::env(GX2D_TCL_LIBRARY)
set argv0 __official_dev102_grid_benchmark__
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
source [file join [file dirname [info script]] .. official_dev100 worksheet_fixture.tcl]
set argv {};::GX::main
set records {};set background {}
proc pause {{ms 50}} {set ::wait 0;after $ms {set ::wait 1};vwait ::wait;update idletasks}
proc bgerror {message} {lappend ::background [list $message $::errorInfo]}
proc save {name value} {set f [open [file join $::out $name.tcldict] w];puts $f $value;close $f}
proc rss {} {set f [open /proc/[pid]/status r];set text [read $f];close $f;regexp {VmRSS:\s+([0-9]+)} $text unused k;return $k}
proc run {} {
 set ::GX::cfg(output_root) [file join $::out sessions]
 set session [::GX::createNewSession {Grid benchmark source}]
 ::GX::modulePublicApiActivate viewer.scientific_worksheet SCIENTIFIC_WORKSHEET_API_v1
 set publication [worksheetFixtureDataset $session grid_benchmark_source 20000]
 set source [dict get [::GX::sessionInspectionDatasetPayload grid_benchmark_source] path]
 set sourceSha [lindex [exec sha256sum $source] 0]
 foreach rows $::rowCounts {
  set w [::GX::ScientificWorksheet::open [dict create workspace_id new workspace_name "Grid $rows rows"]];raise $w;pause 100
  if {$::mode eq {native}} {::GX::ScientificWorksheet::UI::save $w;set book [::GX::ScientificWorksheet::UI::book $w];set g [::GX::ScientificWorksheet::UI::grid $w]} else {set book $::GX::ScientificWorksheet::ui($w,book);set g $w.grid.table}
  set start [clock microseconds]
  lassign [::GX::ScientificWorksheet::bindDataset $book grid_benchmark_source {A source_x B source_y C source_auxiliary} 1 $rows {}] candidate count
  set bindMs [expr {([clock microseconds]-$start)/1000.0}]
  if {$count!=$rows} {error {Public Dataset binding truncated benchmark source}}
  set start [clock microseconds]
  if {$::mode eq {native}} {::GX::ScientificWorksheet::UI::applyBook $w $candidate "Bind $rows benchmark rows"} else {set ::GX::ScientificWorksheet::ui($w,book) $candidate;::GX::ScientificWorksheet::_uiRefresh $w}
  update idletasks
  set adoptMs [expr {([clock microseconds]-$start)/1000.0}]
  set record [dict create rows $rows columns 3 bind_ms $bindMs adopt_and_first_render_ms $adoptMs rss_kib [rss] class [winfo class $g] source_sha256 $sourceSha]
  set value [::GX::ScientificWorksheet::value $candidate C$rows]
  if {abs([dict get $value value]-sin(($rows-1)*.01))>1e-12 || [dict get $value unit] ne {V}} {error {Canonical benchmark value/unit changed}}
  set beforeErrors [llength $::background]
  exec xdotool mousemove --sync [expr {[winfo rootx $g]+190}] [expr {[winfo rooty $g]+90}]
  set timings {}
  for {set run 0} {$run<5} {incr run} {set start [clock microseconds];exec xdotool click --repeat 30 --delay 0 5;pause 40;lappend timings [expr {([clock microseconds]-$start)/1000.0}]}
  set ordered [lsort -real $timings]
  dict set record burst_ms $timings;dict set record p50_ms [lindex $ordered 2];dict set record p95_ms [lindex $ordered 4]
  dict set record input_receipt {Each timing includes30 actual X11 wheel events, xdotool process and40ms event settle; identical on both products}
  dict set record new_background_error_count [expr {[llength $::background]-$beforeErrors}]
  if {$::mode eq {native}} {dict set record viewport [$g receipt];if {[llength $::background]!=$beforeErrors} {error {Native benchmark produced Tcl/Tk background errors}}} else {dict set record tree_rows [llength [$g children {}]];dict set record grid_children [llength [winfo children $w.grid]]}
  if {[lindex [exec sha256sum $source] 0] ne $sourceSha} {error {Canonical benchmark source bytes changed}}
  exec import -window [winfo id $w] [file join $::out grid-$rows.png]
  lappend ::records $record;save records $::records
  puts "MEASURED $::mode rows=$rows p50=[dict get $record p50_ms] p95=[dict get $record p95_ms] rss=[dict get $record rss_kib]KiB";flush stdout
  if {$::mode eq {native}} {::GX::ScientificWorksheet::UI::discard $w} else {destroy $w}
  pause
 }
 save background $::background
 save source [dict create path $source sha256 $sourceSha dataset_id grid_benchmark_source variables {source_x source_y source_auxiliary} units {V V V}]
 destroy .;puts COMPLETE
}
after 200 {if {[catch run e opts]} {save failure [list $e $opts];puts stderr "$e\n[dict get $opts -errorinfo]";destroy .;exit 1}}
