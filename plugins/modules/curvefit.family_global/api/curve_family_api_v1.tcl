# Public adapter to the existing standard Curve Family runtime.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::CurveFamilyV1 {variable moduleId curvefit.family_global}
proc ::GX::CurveFamilyV1::_error {text} {return -code error -errorcode {GXTXT CURVE_FAMILY CONTRACT} $text}
proc ::GX::CurveFamilyV1::apiInfo {} {
    return [dict create api_id CURVE_FAMILY_API_v1 api_version 1 operations {api_info models run result_info recipe recipe_validate recipe_run submit job_result results} scope complete_canonical_dataset]
}
proc ::GX::CurveFamilyV1::_session {} {
    if {![info exists ::GX::currentSession]||$::GX::currentSession eq {}||![file isdirectory $::GX::currentSession]} {_error {Open a Session before running Curve Family}}
    return [file normalize $::GX::currentSession]
}
proc ::GX::CurveFamilyV1::models {} {
    set result {}
    foreach id $::GX::modelOrder {
        if {[::GX::modelField $id function {}] eq {}} continue
        lappend result [dict create model_id $id name [::GX::modelField $id name $id] parameter_ids [::GX::splitList [::GX::modelField $id param_names]] parameter_units [::GX::modelField $id param_units {}]]
    }
    return $result
}
proc ::GX::CurveFamilyV1::_validate {dataset model bindings config} {
    variable moduleId
    set session [_session];::GX::loadDatasetRegistry $session
    if {[catch {dict size $bindings}]||[lsort [dict keys $bindings]] ne {family x y}} {_error {Bindings must contain exactly the canonical Variable IDs x, family and y}}
    if {[::GX::modelField $model descriptor {}] eq {}||[::GX::modelField $model function {}] eq {}} {_error {Select a registered callable mathematical model}}
    set shape {};set dimensions {}
    foreach role {x family y} {
        set spec [::GX::datasetVariableV3ById $dataset [dict get $bindings $role]]
        if {![dict get $spec enabled]||[dict get $spec rank]!=1||[dict get $spec dtype] ni {bool int8 uint8 int16 uint16 int32 uint32 int64 uint64 float32 float64}} {_error {Family model bindings require enabled real rank-one Variables}}
        if {$role eq "x"} {set shape [dict get $spec shape];set dimensions [dict get $spec dimension_ids]}
        if {[dict get $spec shape] ne $shape||[dict get $spec dimension_ids] ne $dimensions} {_error {Family model Variables must share the same observation dimension}}
    }
    if {[catch {dict size $config}]} {_error {Configuration must be a dictionary of scalar fields}}
    dict for {name value} $config {
        if {$name in {dataset_id model_id}||$name ni [::GX::moduleConfigKeys $moduleId]} {_error "Unknown or reserved Curve Family configuration field '$name'"}
        if {[string bytelength $value]>32768||[regexp {[\x00-\x1f\x7f]} $value]} {_error "Configuration field '$name' exceeds scalar text limits"}
    }
    return [::GX::curveSourceDatasetIdentity $session $dataset]
}
proc ::GX::CurveFamilyV1::_prepare {dataset model bindings config} {
    variable moduleId
    set identity [_validate $dataset $model $bindings $config];set session [_session]
    set runId "family-[clock microseconds]-[pid]"
    set output [file join $session analysis curvefit_family_global runs $runId]
    if {[file exists $output]} {_error {Refusing to reuse an existing family result directory}}
    file mkdir $output
    set saved {};set arrays {moduleCfg moduleBinding moduleAnalysisSource moduleAnalysisSourceCount modelParamValue}
    foreach name $arrays {
        upvar #0 ::GX::$name values
        set part {};foreach key [array names values] {if {$key eq $moduleId||[string match "$moduleId,*" $key]} {dict set part $key $values($key)}}
        dict set saved $name $part
    }
    set hadOverride [info exists ::GX::scriptRuntimeOutputOverride]
    if {$hadOverride} {set priorOverride $::GX::scriptRuntimeOutputOverride}
    try {
        foreach key [::GX::moduleConfigKeys $moduleId] {set ::GX::moduleCfg($moduleId,$key) [::GX::moduleConfigField $moduleId $key default {}]}
        set ::GX::moduleCfg($moduleId,dataset_id) $dataset;set ::GX::moduleCfg($moduleId,model_id) $model
        dict for {key value} $config {set ::GX::moduleCfg($moduleId,$key) $value}
        ::GX::analysisSourcesResetModule $moduleId
        ::GX::analysisSourceAppendRow $moduleId primary $dataset
        dict for {role variable} $bindings {set ::GX::moduleBinding($moduleId,$role) "primary.$variable"}
        ::GX::modelResourceParametersReset $moduleId model_id $model
        set ::GX::scriptRuntimeOutputOverride [dict create module $moduleId path $output]
        set runtime [::GX::writeStandardRuntimeConfig $moduleId]
        set f [open $runtime a];fconfigure $f -encoding utf-8 -translation lf
        try {puts $f "\n\[graph_provider\]\nenabled=\n"} finally {close $f}
    } finally {
        foreach name $arrays {
            upvar #0 ::GX::$name values
            foreach key [array names values] {if {$key eq $moduleId||[string match "$moduleId,*" $key]} {unset values($key)}}
            dict for {key value} [dict get $saved $name] {set values($key) $value}
        }
        if {$hadOverride} {set ::GX::scriptRuntimeOutputOverride $priorOverride} else {unset -nocomplain ::GX::scriptRuntimeOutputOverride}
    }
    return [dict create api_id CURVE_FAMILY_API_v1 api_version 1 run_id $runId output_dir $output runtime_path $runtime runtime_sha256 [::GX::sha256File $runtime] source_identity $identity model_id $model scope complete_canonical_dataset]
}
proc ::GX::CurveFamilyV1::run {dataset model bindings config} {
    return [_run $dataset $model $bindings $config {}]
}
proc ::GX::CurveFamilyV1::_run {dataset model bindings config expected} {
    variable moduleId
    set plan [_prepare $dataset $model $bindings $config];set output [dict get $plan output_dir]
    set runtime [dict get $plan runtime_path];set executable [::GX::runtimeToolResolve octave]
    set source [dict get $plan source_identity];set modelIdentity [_modelIdentity $model]
    if {$expected ne {}} {
        if {$source ne [dict get $expected source_identity]||$modelIdentity ne [dict get $expected model_identity]} {_error {Queued family source/model changed while preparing execution}}
    }
    set f [open $runtime a];fconfigure $f -encoding utf-8 -translation lf
    try {
        puts $f "\n\[family_recipe\]"
        foreach key {sha256 schema_identity} {::GX::putKV $f source_$key [dict get $source $key]}
        foreach key {descriptor_sha256 source_sha256} {::GX::putKV $f model_$key [dict get $modelIdentity $key]}
        if {$expected ne {}&&[dict get $expected frozen_files] ne {}} {
            dict for {name reference} [dict get $expected frozen_files] {
                ::GX::putKV $f ${name}_path [_fileResolve $reference]
                ::GX::putKV $f ${name}_exists [dict get $reference exists]
                ::GX::putKV $f ${name}_sha256 [dict get $reference sha256]
            }
        }
    } finally {close $f}
    dict set plan runtime_sha256 [::GX::sha256File $runtime]
    if {$executable eq {}} {_error {GNU Octave runtime is not configured}}
    set runner [file join [file dirname [::GX::moduleField $moduleId descriptor]] runtime curvefit_family_global.m]
    if {[catch {exec -- $executable --no-gui --quiet $runner --config $runtime >[file join $output execution.log] 2>@1} message options]} {
        return -options $options "Curve Family failed; retained execution log: [file join $output execution.log]. $message"
    }
    if {[::GX::sha256File $runtime] ne [dict get $plan runtime_sha256]} {_error {Runtime changed during family execution}}
    ::GX::loadDatasetRegistry [_session]
    if {[::GX::curveSourceDatasetIdentity [_session] $dataset] ne [dict get $plan source_identity]} {_error {Scientific source changed during family execution}}
    set files {};foreach name [::GX::splitList [::GX::moduleField $moduleId outputs {}]] {
        set path [file join $output $name]
        if {![file isfile $path]||[file type $path] eq "link"} {_error "Family runtime did not produce required output '$name'"}
        dict set files $name [::GX::sha256File $path]
    }
    if {$files eq {}} {_error {Family provider has no declared output contract}}
    dict set files runtime.ini [::GX::sha256File $runtime]
    if {[file isfile [file join $output fit_domain.csv]]} {dict set files fit_domain.csv [::GX::sha256File [file join $output fit_domain.csv]]}
    set publications {};foreach name {result identity metrics parameters} {
        set path [file join $output publication_$name.tcldict]
        set f [open $path];fconfigure $f -encoding utf-8;try {set committed [read $f]} finally {close $f}
        if {[dict get $committed dataset_id] ne "curvefit.family.$name"||![regexp {^[0-9a-f]{64}$} [dict get $committed sha256]]} {_error {Invalid CORE publication receipt}}
        dict set publications curvefit.family.$name $committed
        dict set files publication_$name.tcldict [::GX::sha256File $path]
    }
    set receipt [dict merge $plan [dict create schema gxtxt.family_run.v1 module_version [::GX::moduleField $moduleId version] files $files publications $publications publication_identity_policy core_commit_receipt]]
    set path [file join $output result.tcldict];set f [open $path {WRONLY CREAT EXCL}];fconfigure $f -encoding utf-8 -translation lf
    try {puts $f $receipt} finally {close $f}
    set reference [dict create schema gxtxt.family_reference.v1 run_id [dict get $plan run_id] receipt_sha256 [::GX::sha256File $path]]
    return [resultInfo $reference]
}
proc ::GX::CurveFamilyV1::resultInfo {reference} {
    if {[catch {dict get $reference schema} schema]||$schema ne "gxtxt.family_reference.v1"||![dict exists $reference run_id]||![dict exists $reference receipt_sha256]} {_error {Invalid family result reference}}
    set id [dict get $reference run_id]
    if {![regexp {^family-[0-9]+-[0-9]+$} $id]} {_error {Invalid family run identity}}
    set output [file join [_session] analysis curvefit_family_global runs $id];set path [file join $output result.tcldict]
    if {![file isfile $path]||[file type $path] eq "link"||[::GX::sha256File $path] ne [dict get $reference receipt_sha256]} {_error {Family result receipt changed or is unavailable}}
    set f [open $path];fconfigure $f -encoding utf-8;try {set receipt [read $f]} finally {close $f}
    if {[dict get $receipt schema] ne "gxtxt.family_run.v1"||[dict get $receipt run_id] ne $id} {_error {Family result identity mismatch}}
    set files {};dict for {name sha} [dict get $receipt files] {
        if {![regexp {^[A-Za-z][A-Za-z0-9_.-]*$} $name]} {_error {Invalid retained output name}}
        set file [file join $output $name]
        if {![file isfile $file]||[file type $file] eq "link"||[::GX::sha256File $file] ne $sha} {_error "Retained family output '$name' changed or is unavailable"}
        dict set files $name $file
    }
    set f [open [dict get $files fit_statistics.tcldict]];fconfigure $f -encoding utf-8;try {set metadata [read $f]} finally {close $f}
    ::GX::StatisticsV1::validateMetadata $metadata
    set statistics [dict get $metadata analysis.statistical_results]
    set policy registry_observed_after_run
    if {[dict exists $receipt publication_identity_policy]} {set policy [dict get $receipt publication_identity_policy]}
    return [dict create api_id CURVE_FAMILY_API_v1 api_version 1 reference $reference model_id [dict get $receipt model_id] scope [dict get $receipt scope] source_identity [dict get $receipt source_identity] dataset_ids [dict keys [dict get $receipt publications]] publications [dict get $receipt publications] publication_identity_policy $policy files $files statistical_results $statistics parameter_map [dict get $statistics global provenance parameter_map]]
}
source [file join [file dirname [info script]] curve_family_recipe_v1.tcl]
