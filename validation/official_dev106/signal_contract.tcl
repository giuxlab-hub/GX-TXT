# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root out requestedSamples
set root [file normalize $root];set out [file normalize $out]
if {![string match */_private_dev106/* $out] || [file exists $out]} {error {Fresh private output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out $key]}
set argv0 __signal_contract__;source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
set ::GX::cfg(output_root) [file join $out Sessions];::GX::createNewSession signal_full_record
::GX::datasetPreviewCacheInit;::GX::configurationSet preview.cache_enabled 0
::GX::modulePublicApiActivate viewer.signal_analysis SIGNAL_ANALYSIS_VIEWER_API_v1
set samples [expr {$requestedSamples eq {} ? 16385 : $requestedSamples}]
if {$samples<256 || $samples>262145} {error {Test record length must be 256..262145}}
set p [::GX::datasetPublicationV2Prepare $::GX::currentSession math.signal {dataset_id measured contract table.generic storage hdf5}]
set w [::GX::datasetPublicationV2OpenWriter $p];::GX::datasetPublicationV2DeclareDimension $w row $samples
foreach {id unit} {t s x V y V} {::GX::datasetPublicationV2DeclareVariable $w $id [dict create dtype float64 unit $unit dimension_ids row]}
set t {};set x {};set y {}
for {set n 0} {$n<$samples} {incr n} {lappend t [expr {$n/1000.0}];lappend x [expr {sin($n*.1)+.1*cos($n*.02)}];lappend y [expr {2*sin($n*.1)+.3*cos($n*.02)}]}
foreach id {t x y} values [list $t $x $y] {::GX::datasetPublicationV2WriteRange $w $id 0 $values}
::GX::datasetPublicationV2Finalize $w
set original [::GX::datasetRevisionToken measured];set receipts {}
foreach method [::GX::SignalAnalysisViewer::methods] {
    set parameters [dict create dataset_id measured primary x secondary y time t operation $method sample_rate 0 window 256 overlap .5 normalization coefficient cutoff 10 order 3 decimation 2]
    set receipt [::GX::SignalAnalysisViewer::submit $parameters];set job [dict get $receipt job_id]
    set result [::GX::scriptJobWait $job 120]
    set f [open [file join $out [string map {. _} $method].tcldict] w];puts $f $result;close $f
    if {[dict get $result state] ne {COMPLETED}} {puts stderr "FAIL $method: [dict get $result error]";exit 1}
    dict set receipts $method [dict create job $job output_dir [dict get $result output_dir] outputs [::GX::scientificExecutionOutputs $job]]
    puts "PASS $method full_input_rows=$samples";flush stdout
    if {[::GX::datasetRevisionToken measured] ne $original} {error {Canonical scientific input changed}}
}
set f [open [file join $out result.tcldict] w];puts $f [dict create status PASS rows $samples sources $original receipts $receipts];close $f
