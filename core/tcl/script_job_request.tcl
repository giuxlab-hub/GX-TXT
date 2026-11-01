#!/usr/bin/env tclsh
# SPDX-License-Identifier: GPL-3.0-or-later
set framework [lindex $argv 0]
set request [read stdin]
set argv0 __not_main__
source [file join $framework gxtxt_pipeline.tcl]
if {[catch {
    set reference [dict get $request reference]
    set service [::GX::datasetPublicationV2DictDefault $request core_service {}]
    if {$service eq {dataset-preview}} {
        if {$reference ne {core-service:dataset-preview}} {error {Preview preparation requires the matching private CORE service}}
        # Catalogue opening can notify derived observers before execution is
        # prepared. This same Preview worker must not enqueue another Preview
        # of its inputs while bootstrapping the Session.
        set ::GX::PreviewCache::worker 1
    }
    ::GX::defaults
    ::GX::loadModuleCatalog
    set session [dict get $request session]
    set ::GX::currentSession $session
    if {[file isfile [file join $session metadata manifest.ini]]} {::GX::loadManifest [file join $session metadata manifest.ini]}
    set ::GX::currentSession $session
    set ::env(GXTXT_JOB_ROOT) [dict get $request root]
    ::GX::loadDatasetRegistry $session
    if {[dict exists $request module_config]} {dict for {key value} [dict get $request module_config] {set ::GX::moduleCfg($key) $value}}
    if {[dict exists $request preview_activation]} {
        if {$service ne {dataset-preview} || $reference ne {core-service:dataset-preview}} {error {Preview activation transport requires the private CORE Preview service}}
        ::GX::_datasetPreviewActivationApply [dict get $request preview_activation]
    }
    set inputs [dict get $request inputs]
    set namespace [::GX::datasetNamespaceCurrentGet $session]
    if {[dict exists $request namespace]} {set namespace [dict get $request namespace]}
    set inputs [::GX::scriptJobInputsResolve $session $inputs $namespace]
    # A GUI's review identity is checked again in this fresh preparation process,
    # closing the async admission window without trusting presentation state.
    if {[dict exists $request reviewed_script]} {
        set current [::GX::scriptRegistryDescribe $reference $session]
        foreach key {sha256 revision parameters} {
            if {[dict get $current $key] ne [dict get $request reviewed_script $key]} {error {Registered Script changed since review; reopen Script Runner}}
        }
    }
    set parameterDataset [::GX::datasetPublicationV2DictDefault $request parameter_dataset {}]
    if {$parameterDataset ne {}} {
        set loaded [::GX::scriptParameterDatasetLoad $session $reference [dict get $parameterDataset dataset_id]]
        foreach key {revision sha256 variable_ids} {
            if {[dict get $loaded $key] ne [dict get $parameterDataset $key]} {error {Parameter Dataset changed since review; load it again}}
        }
        # Effective per-Job values may be deliberately edited after loading.
        # Preserve the original canonical preset identity as provenance only.
        set parameterDataset [dict remove $loaded parameters]
    }
    set invocation [expr {[dict exists $request callable_invocation] ? [dict get $request callable_invocation] : {}}]
    set service [::GX::datasetPublicationV2DictDefault $request core_service {}]
    set invocationSchema [::GX::datasetPublicationV2DictDefault $request invocation_parameters {}]
    set packageInvocation [::GX::datasetPublicationV2DictDefault $request package_invocation {}]
    set prepared [::GX::scriptExecutionPrepare $reference [dict get $request parameters] $session [dict get $request runtime_template] [dict get $request module_output] $invocation $service $invocationSchema $packageInvocation]
    dict for {key value} $prepared {set $key $value}
    if {[dict exists $request reviewed_script]} {
        foreach key {sha256 revision parameters} {
            if {[dict get $m $key] ne [dict get $request reviewed_script $key]} {error {Registered Script changed during snapshot preparation; reopen Script Runner}}
        }
    }
    if {$language eq {Python} && $service eq {}} {
        set priorDirectory [pwd]
        set effectiveWorking [::GX::datasetPublicationV2DictDefault [::GX::parseIni $runtime] config.working_directory $session]
        try {
            cd $effectiveWorking
            if {$packageInvocation ne {}} {
                set preflight [::GX::_scriptProvidedPythonSnapshotAudit $projectSnapshot $reference [file join $outDir python_import_preflight.json]]
            } elseif {[::GX::datasetPublicationV2DictDefault $m kind script] eq {project}} {
                set auditPlan [::GX::_pythonEnvironmentAuditPlan [dict create scope project reference $reference]]
                if {[dict get $auditPlan scope_identity] ne [list $reference [dict get $m revision] [dict get $m sha256]]} {error {Script Project changed before whole-project import preflight}}
                set preflight [::GX::_pythonEnvironmentAuditSync $auditPlan [file join $outDir python_import_preflight.json]]
            } else {set preflight [::GX::pythonEnvironmentPreflight $snapshot [file join $outDir python_import_preflight.json]]}
        } finally {cd $priorDirectory}
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
        set projectBreakpoints {}
        if {[dict get $m kind] eq {project}} {
            dict for {path lines} $breakpoints {
                if {![dict exists $m project_files $path]} {error {Breakpoint file is not admitted by project manifest}}
                foreach line $lines {if {![string is integer -strict $line] || $line<1} {error {Breakpoint lines must be positive}}}
                dict set projectBreakpoints $path $lines
            }
            set breakpoints {}
        } else {foreach line $breakpoints {if {![string is integer -strict $line] || $line<1} {error {Breakpoints must use positive physical source lines}}}}
        set ch [open $runtime a];try {
            puts $ch "\n\[debug\]";::GX::putKV $ch enabled 1;::GX::putKV $ch breakpoints [join $breakpoints {;}]
            set n 0
            dict for {path lines} $projectBreakpoints {puts $ch "\n\[debug_file.[incr n]\]";::GX::putKV $ch path $path;::GX::putKV $ch lines [join $lines {;}]}
        } finally {close $ch}
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
        if {$parameterDataset ne {}} {
            puts $ch "\n\[job_parameter_dataset\]"
            dict for {key value} $parameterDataset {
                if {$key eq {revision}} {set key revision_base64;set value [binary encode base64 -maxlen 0 [encoding convertto utf-8 $value]]}
                ::GX::putKV $ch $key $value
            }
        }
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
    if {$packageInvocation ne {}} {dict set effective provided_api $packageInvocation}
    set runtimeFields [::GX::parseIni $runtime]
    dict for {key value} $runtimeFields {
        if {[string match config.* $key] && $key ni {config.script_file config.script_name}} {dict set effective $key $value}
        if {[string match analysis_source.* $key]} {dict set effective $key $value}
    }
    # The parsed scientific settings above define execution identity. A template's
    # generated run/output paths are incidental and must not defeat deduplication.
    set environment [dict create GXTXT_RESOURCE_ROOT [::GX::resourceManagementRoot] GXTXT_RESOURCE_STORAGE [file join [::GX::configurationTempDirectory] resources-v1]]
    foreach key {GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_STDERR_DIAGNOSTICS_DESCRIPTOR GXTXT_STDERR_DIAGNOSTICS_LIBRARY XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME} {
        if {[info exists ::env($key)]} {dict set environment $key $::env($key)}
    }
    set envelope [dict create session $session reference $reference source_sha256 [dict get $m sha256] script_revision [dict get $m revision] language $language script_name [dict get $m name] parameters $values inputs $inputs output $output execution_inputs $effective command $command run_id $runId output_dir $outDir snapshot $snapshot runtime $runtime required_apis $requiredApis module_output $moduleOutputDir log_path [file join $outDir [expr {$language eq "Python" ? "python.log" : "octave.log"}]] environment $environment]
    dict set envelope parameter_dataset $parameterDataset
    dict set envelope parameter_schema $effectiveSchema
    if {[dict get $m kind] eq {project}} {
        dict set envelope project_manifest [dict get $projectSnapshot project_manifest]
        dict set envelope project_sha256 [dict get $m sha256]
        dict set envelope entrypoint_sha256 [dict get $m entrypoint_sha256]
    }
    dict set envelope debug $debug
    dict set envelope origin [expr {$service eq {} ? {user_script} : ($service eq {dataset-preview}?{core_service}:{scientific_provider})}]
    dict set envelope service_id $service
    dict set envelope script_id [dict get $m id]
    dict set envelope script_version [dict get $m version]
    dict set envelope session_name [::GX::currentSessionDisplayName]
    if {$service ne {}} {
        set ch [open $runtime a]
        try {
            puts $ch "\n\[job_origin\]";::GX::putKV $ch classification core_service;::GX::putKV $ch service_id $service
            if {[dict exists $request preview_activation]} {puts $ch "\n\[preview_activation\]";::GX::putKV $ch snapshot [dict get $request preview_activation]}
        } finally {close $ch}
    }
    set response [exec {*}[::GX::scriptJobCommand submit] << $envelope]
    if {![dict get $response ok]} {error [dict get $response error]}
} reason options]} {
    puts [dict create ok 0 error $reason error_code [::GX::datasetPublicationV2DictDefault $options -errorcode {}]]
} else {puts $response}
exit 0
