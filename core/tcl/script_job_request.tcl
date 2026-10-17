#!/usr/bin/env tclsh
# SPDX-License-Identifier: GPL-3.0-or-later
set framework [lindex $argv 0]
set request [read stdin]
set argv0 __not_main__
source [file join $framework gxtxt_pipeline.tcl]
if {[catch {
    ::GX::defaults
    ::GX::loadModuleCatalog
    set session [dict get $request session]
    set ::GX::currentSession $session
    if {[file isfile [file join $session metadata manifest.ini]]} {::GX::loadManifest [file join $session metadata manifest.ini]}
    set ::GX::currentSession $session
    set ::env(GXTXT_JOB_ROOT) [dict get $request root]
    ::GX::loadDatasetRegistry $session
    if {[dict exists $request module_config]} {dict for {key value} [dict get $request module_config] {set ::GX::moduleCfg($key) $value}}
    set reference [dict get $request reference]
    set inputs [dict get $request inputs]
    set namespace [::GX::datasetNamespaceCurrentGet $session]
    if {[dict exists $request namespace]} {set namespace [dict get $request namespace]}
    dict for {alias binding} $inputs {
        if {![regexp {^[A-Za-z_][A-Za-z0-9_]*$} $alias]} {error "Invalid semantic input alias '$alias'"}
        set id [dict get $binding dataset_id]
        if {[::GX::datasetField $id id {}] eq {}} {error "Input Dataset '$id' is no longer available"}
        if {[::GX::datasetNamespaceGet $session $id] ne $namespace} {error "Input Dataset '$id' is outside the selected current namespace"}
        set revision [::GX::datasetRevisionToken $id $session]
        dict set binding revision $revision
        dict set binding revision_base64 [binary encode base64 -maxlen 0 [encoding convertto utf-8 $revision]]
        dict set binding namespace $namespace
        dict set inputs $alias $binding
    }
    set invocation [expr {[dict exists $request callable_invocation] ? [dict get $request callable_invocation] : {}}]
    set service [::GX::datasetPublicationV2DictDefault $request core_service {}]
    set prepared [::GX::scriptExecutionPrepare $reference [dict get $request parameters] $session [dict get $request runtime_template] [dict get $request module_output] $invocation $service]
    dict for {key value} $prepared {set $key $value}
    if {$language eq {Python} && $service eq {}} {
        set priorDirectory [pwd]
        set effectiveWorking [::GX::datasetPublicationV2DictDefault [::GX::parseIni $runtime] config.working_directory $session]
        try {cd $effectiveWorking;set preflight [::GX::pythonEnvironmentPreflight $snapshot [file join $outDir python_import_preflight.json]]} finally {cd $priorDirectory}
        set policy [::GX::datasetPublicationV2DictDefault $request import_policy strict]
        if {$policy ni {strict continue}} {error {Python import policy must be strict or explicit continue}}
        if {[dict get $preflight status] eq {ERROR} || ([dict get $preflight status] eq {MISSING} && $policy ne {continue})} {
            return -code error -errorcode {GXTXT PYTHON IMPORT_PREFLIGHT} "Python import preflight: [dict get $preflight status] — [dict get $preflight issues]. No user code was launched. Review missing imports; cancel or explicitly continue."
        }
    }
    set debug [::GX::datasetPublicationV2DictDefault $request debug 0]
    if {$debug} {
        if {$service ne {} || ![string match session:* $reference]} {error {Debug requires a registered user Session script}}
        set breakpoints [::GX::datasetPublicationV2DictDefault $request debug_breakpoints {}]
        foreach line $breakpoints {if {![string is integer -strict $line] || $line<1} {error {Breakpoints must use positive physical source lines}}}
        set ch [open $runtime a];try {puts $ch "\n\[debug\]";::GX::putKV $ch enabled 1;::GX::putKV $ch breakpoints [join $breakpoints {;}]} finally {close $ch}
        if {$language eq {Octave}} {set command [list [::GX::runtimeToolRequired python] -B [file join $::GX::scriptDir core python gxtxt_octave_debug.py] $runtime {*}$command]}
    }
    set output [dict get $request output]
    if {[dict exists $output dataset_id] && [dict get $output dataset_id] ne {}} {
        set id [dict get $output dataset_id]
        if {![regexp {^[A-Za-z][A-Za-z0-9_.-]*$} $id]} {error {Output Dataset ID must use letters, digits, dots, underscores or hyphens}}
        if {[::GX::datasetField $id id {}] ne {}} {
            if {![dict exists $output replace_owned] || ![dict get $output replace_owned]} {error "Output Dataset '$id' already exists (create-only)"}
            ::GX::_datasetNamespaceRequireModuleWrite $session $moduleId $id
            if {[::GX::datasetField $id producer_module {}] ne $moduleId} {error {Output belongs to another producer}}
        }
    }
    set ch [open $runtime a]
    try {
        dict for {alias binding} $inputs {
            puts $ch "\n\[job_input.$alias\]"
            dict for {key value} $binding {::GX::putKV $ch $key $value}
        }
        if {[dict size $output]} {
            puts $ch "\n\[job_output\]"
            dict for {key value} $output {::GX::putKV $ch $key $value}
        }
    } finally {close $ch}
    set effective [dict create language $language runtime_executable [lindex $command 0]]
    if {$invocation ne {}} {dict set effective registered_callable $invocation}
    set runtimeFields [::GX::parseIni $runtime]
    dict for {key value} $runtimeFields {
        if {[string match config.* $key] && $key ni {config.script_file config.script_name}} {dict set effective $key $value}
        if {[string match analysis_source.* $key]} {dict set effective $key $value}
    }
    # The parsed scientific settings above define execution identity. A template's
    # generated run/output paths are incidental and must not defeat deduplication.
    set environment [dict create GXTXT_RESOURCE_ROOT [::GX::resourceManagementRoot] GXTXT_RESOURCE_STORAGE [file join [::GX::configurationTempDirectory] resources-v1]]
    foreach key {GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME} {
        if {[info exists ::env($key)]} {dict set environment $key $::env($key)}
    }
    set envelope [dict create session $session reference $reference source_sha256 [dict get $m sha256] script_revision [dict get $m revision] language $language script_name [dict get $m name] parameters $values inputs $inputs output $output execution_inputs $effective command $command run_id $runId output_dir $outDir snapshot $snapshot runtime $runtime required_apis $requiredApis module_output $moduleOutputDir log_path [file join $outDir [expr {$language eq "Python" ? "python.log" : "octave.log"}]] environment $environment]
    dict set envelope debug $debug
    dict set envelope origin [expr {$service eq {} ? {user_script} : ($service eq {dataset-preview}?{core_service}:{scientific_provider})}]
    dict set envelope service_id $service
    dict set envelope script_id [dict get $m id]
    dict set envelope script_version [dict get $m version]
    dict set envelope session_name [::GX::currentSessionDisplayName]
    if {$service ne {}} {
        set ch [open $runtime a];try {puts $ch "\n\[job_origin\]";::GX::putKV $ch classification core_service;::GX::putKV $ch service_id $service} finally {close $ch}
    }
    set response [exec {*}[::GX::scriptJobCommand submit] << $envelope]
    if {![dict get $response ok]} {error [dict get $response error]}
} reason options]} {
    puts [dict create ok 0 error $reason error_code [::GX::datasetPublicationV2DictDefault $options -errorcode {}]]
} else {puts $response}
exit 0
