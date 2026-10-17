# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root out mode
if {[llength $argv] ni {2 3}||[file exists $out]||$mode ni {{} reporting}} {error {Usage: FRAMEWORK NEW_OUTPUT ?reporting?}}
set root [file normalize $root];set out [file normalize $out];file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out $key]}
set argv0 __replicate_module102__;source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog;set ::GX::cfg(output_root) [file join $out sessions]
set checks 0
proc check {e label} {if {![uplevel 1 [list expr $e]]} {error "FAIL $label"};incr ::checks;puts "PASS $label"}
proc drain {channel log} {while {[gets $channel line]>=0} {puts $log $line};if {![eof $channel]} return;fileevent $channel readable {};fconfigure $channel -blocking 1;set ::jobStatus [catch {close $channel} ::jobError];set ::jobDone 1}
proc runReplicate {runtime tag rerender} {
    set entry [expr {$rerender?"curve_replicate_rerender.m":"curve_replicate_analysis.m"}]
    set command [list octave --quiet --no-gui [file join $::root plugins modules curve.replicate_analysis runtime $entry] --config $runtime]
    set log [open [file join $::out $tag.log] {WRONLY CREAT EXCL}];set ::jobDone 0
    try {set channel [open [concat | $command [list 2>@1]] r];fconfigure $channel -blocking 0 -buffering line;fileevent $channel readable [list drain $channel $log];vwait ::jobDone;if {$::jobStatus} {error "Replicate $tag failed: $::jobError; inspect $tag.log"}} finally {close $log}
}
try {
    set session [::GX::createNewSession replicate_module102];::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    set sourceReceipts {}
    foreach source {1 2} {
        set x {};set y {};set replicate {}
        foreach rep {1 2} {for {set i 0} {$i<11} {incr i} {
            lappend x [expr {$source==1?$i:$i*1000}]
            lappend y [expr {($i+($source==1?($rep==1?1:3):($rep==1?5:7)))*($source==1?1:1000)}]
            lappend replicate $rep
        }}
        set request [dict create dataset_id source_$source contract table.generic storage hdf5 x_values $x y_values $y x_variable [dict create variable_id x unit [expr {$source==1?"s":"ms"}] semantic_role independent] y_variable [dict create variable_id y unit [expr {$source==1?"V":"mV"}] semantic_role dependent] extra_variables [list [dict create descriptor {variable_id replicate_id unit 1 semantic_role replicate} values $replicate]]]
        dict set sourceReceipts source_$source [::GX::datasetPublicationV2PublishSeries $session viewer.curve_digitizer $request]
    }
    set module curve.replicate_analysis;::GX::analysisSourcesResetModule $module
    ::GX::analysisSourceAppendRow $module primary source_1;::GX::analysisSourceAppendRow $module second source_2
    foreach {role variable} {x x y y replicate replicate_id family {}} {unset -nocomplain ::GX::moduleBindingIdentity($module,$role);set ::GX::moduleBinding($module,$role) [expr {$variable eq {}?{}:"primary.$variable"}]}
    foreach {key value} {replicate_handling automatic sampling_model independent_traces common_grid pooled_x min_trace_points 5 consensus_center mean} {set ::GX::moduleCfg($module,$key) $value}
    if {$mode eq "reporting"} {foreach graph {curve.replicate.overlay curve.replicate.consensus_uncertainty curve.replicate.uncertainty_components curve.replicate.family_summary} {::GX::graphUseStateSet $module $graph {} 0}}
    ::GX::writeManifest [file join $session metadata manifest.ini];set runtime [::GX::writeStandardRuntimeConfig $module]
    runReplicate $runtime labelled 0
    ::GX::loadDatasetRegistry $session
    foreach id {curve.replicate.traces curve.replicate.profiles curve.replicate.family_summary} {
        set metadata [::GX::datasetMetadataRead $session $id]
        check {[dict get [::GX::StatisticsV1::validateMetadata $metadata] result_count]>0} "$id publishes validated CORE interpretation"
    }
    set profile [::GX::StatisticsV1::bindingTable $session curve.replicate.profiles profile_1 0 11]
    set values [::GX::StatisticsV1::tableValues $profile {replicate_mean replicate_total replicate_sem}]
    check {[lindex [dict get $values replicate_mean] 0]==4&&[lindex [dict get $values replicate_mean] end]==14} {Source time and response prefixes normalize before curve alignment}
    check {abs([lindex [dict get $values replicate_total] 0]-3)<1e-12&&abs([lindex [dict get $values replicate_sem] 0]-sqrt(5.0/3))<1e-12} {Published grouped moments and explicit SEM match the analytical source data}
    check {[dict get [::GX::datasetVariableV3ById curve.replicate.profiles x] unit] eq "s"&&[dict get [::GX::datasetVariableV3ById curve.replicate.profiles mean] unit] eq "V"} {Actual output coordinate and response units persist}
    set folder [file join $session analysis $module]
    set f [open [file join $folder replicate_statistics.csv]];set lines [split [string trim [read $f]] \n];close $f
    set fields [split [lindex $lines 1] ,]
    check {[llength $fields]==14&&[lindex $fields 8]==6&&abs([lindex $fields 9]-sqrt(11))<1e-12} {Trace CSV preserves its column layout and CORE-formatted numerical fields}
    set f [open [file join $folder source_statistics.csv]];set lines [split [string trim [read $f]] \n];close $f;set fields [split [lindex $lines 1] ,]
    check {[llength $fields]==9&&[lindex $fields 5]==-2&&[lindex $fields 6]==2&&[lindex $fields 7]==2} {Source CSV reuses captured bias RMS and maximum absolute deviation}
    if {$mode ne "reporting"} {
    foreach file {01_replicate_overlay.png 02_consensus_uncertainty.png 03_uncertainty_components.png 04_family_uncertainty_summary.png} {check {[file size [file join $folder $file]]>1000} "$file renders through public Plot Dataset";file copy [file join $folder $file] $out}
    set cache [::GX::sha256File [file join $folder render_cache.mat]];set payload [dict get [::GX::sessionInspectionDatasetPayload curve.replicate.profiles $session] sha256]
    runReplicate $runtime rerender 1
    check {[::GX::sha256File [file join $folder render_cache.mat]] eq $cache&&[dict get [::GX::sessionInspectionDatasetPayload curve.replicate.profiles $session] sha256] eq $payload} {Cache-only rerender preserves captured cache and scientific payload}
    }
    dict for {id receipt} $sourceReceipts {check {[dict get [::GX::sessionInspectionDatasetPayload $id $session] sha256] eq [dict get $receipt sha256]} "$id remains byte-identical"}
    set csvPaths {}
    foreach id {curve.replicate.traces curve.replicate.profiles curve.replicate.family_summary} {
        set metadata [::GX::datasetMetadataRead $session $id]
        set schema [::GX::datasetVariableSchemaV3 $id]
        set stream [::GX::tableStreamOpenDataset $session $id {} 4096]
        try {set data [dict get [::GX::tableStreamNext $stream] values]} finally {::GX::tableStreamClose $stream}
        ::GX::datasetDelete $session $id
        set writer [::GX::datasetPublicationV2OpenWriter [::GX::datasetPublicationV2Prepare $session curve.replicate_analysis [dict create dataset_id $id contract table.generic storage csv structured_metadata $metadata]]]
        ::GX::datasetPublicationV2DeclareDimension $writer row 0 {extendible 1}
        foreach variable $schema {set variable [dict remove $variable shape maxshape];dict set variable dimension_ids row;::GX::datasetPublicationV2DeclareVariable $writer [dict get $variable variable_id] $variable}
        ::GX::datasetPublicationV2Append $writer row $data
        dict set csvPaths $id [dict get [::GX::datasetPublicationV2Finalize $writer] path]
    }
    runReplicate $runtime owned_csv_auto_replacement 0
    ::GX::loadDatasetRegistry $session
    dict for {id path} $csvPaths {check {[::GX::datasetField $id storage_provider {}] eq "csv" && [::GX::datasetField $id path {}] eq $path} "Actual retained legacy Replicate auto replacement preserves $id CSV target"}
    set f [open [file join $out receipt.tcldict] {WRONLY CREAT EXCL}];puts $f [dict create status PASS checks $checks session $session];close $f
    puts "DEV102_LEGACY_REPLICATE_PASS checks=$checks"
} on error {message options} {puts stderr [dict get $options -errorinfo];exit 1}
exit 0
