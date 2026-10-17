lassign $argv root out
set root [file normalize $root];set out [file normalize $out]
if {[file exists $out] || ![string match */_private_dev106/* $out]} {error {Fresh private output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out $key]}
set argv0 __signal_negative__;source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog;set ::GX::cfg(output_root) [file join $out Sessions];::GX::createNewSession signal_negative
::GX::datasetPreviewCacheInit;::GX::configurationSet preview.cache_enabled 0
::GX::modulePublicApiActivate viewer.signal_analysis SIGNAL_ANALYSIS_VIEWER_API_v1
set receipts {}
foreach fault {nonuniform nonfinite normal} {
 set n 16385;set p [::GX::datasetPublicationV2Prepare $::GX::currentSession math.signal [dict create dataset_id $fault contract table.generic storage hdf5]];set w [::GX::datasetPublicationV2OpenWriter $p]
 ::GX::datasetPublicationV2DeclareDimension $w row $n
 foreach {id unit} {t s x V} {::GX::datasetPublicationV2DeclareVariable $w $id [dict create dtype float64 unit $unit dimension_ids row]}
 set times {};set xs {}
 for {set i 0} {$i<$n} {incr i} {lappend times [expr {$i/1000.0}];lappend xs [expr {sin($i*.1)}]}
 if {$fault eq {nonuniform}} {lset times end 16.386}
 if {$fault eq {nonfinite}} {lset xs end NaN}
 ::GX::datasetPublicationV2WriteRange $w t 0 $times;::GX::datasetPublicationV2WriteRange $w x 0 $xs;::GX::datasetPublicationV2Finalize $w
 set original [::GX::datasetRevisionToken $fault]
 set params [dict create dataset_id $fault primary x secondary {} time t operation spectral.welch sample_rate 0 window 256 overlap .5 normalization coefficient cutoff 10 order 3 decimation 2]
 set receipt [::GX::SignalAnalysisViewer::submit $params];set id [dict get $receipt job_id]
 if {$fault eq {normal}} {::GX::SignalAnalysisViewer::cancel $id}
 set job [::GX::scriptJobWait $id 90];set expected [expr {$fault eq {normal}?{CANCELLED}:{FAILED}}]
 if {[dict get $job state] ne $expected} {error "Signal $fault state [dict get $job state], expected $expected"}
 if {[::GX::datasetRevisionToken $fault] ne $original} {error {Signal failure/cancel changed canonical source}}
 dict set receipts $fault [dict create job_id $id state $expected stderr [::GX::scriptJobStreamRead $id stderr] unchanged_source $original]
 puts "PASS actual full-record Signal $fault $expected";flush stdout
}
if {[llength [::GX::datasetRegistryIds]]!=3} {error {Failed/cancelled Signal unexpectedly published a Dataset}}
set f [open [file join $out result.tcldict] w];puts $f [dict create status PASS rows 16385 receipts $receipts];close $f
