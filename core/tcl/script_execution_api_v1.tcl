# GX-TXT CORE Script Registry and Execution API v1.
# SPDX-License-Identifier: GPL-3.0-or-later
# User and Session scripts share one format. A Session copy is a physical
# snapshot, so later user-library edits cannot alter a historical experiment.
namespace eval ::GX {
    variable scriptExecutionApiVersion 1
}
source [file join [file dirname [info script]] script_callable_v1.tcl]

proc ::GX::scriptExecutionApiInfo {} {
    return [dict create api_name SCRIPT_EXECUTION_API_v1 api_version 1 language Octave languages {Octave Python} operations {list describe run callable_list callable_describe current_callable job_submit job_wait}]
}

proc ::GX::scriptRegistrySourceName {language} {
    switch -- $language {
        Octave { return source.m }
        Python { return source.py }
        default { error "Unsupported script language '$language'." }
    }
}

proc ::GX::scriptAnalysisModule {language} {
    switch -- $language {
        Octave { return analysis.octave_script }
        Python { return analysis.python_script }
        default { error "Unsupported script language '$language'." }
    }
}

proc ::GX::scriptRegistryRoot {scope {session ""}} {
    switch -- $scope {
        user { return [file normalize [configurationGet scripts.user_root]] }
        session {
            if {$session eq ""} { set session $::GX::currentSession }
            if {$session eq "" || ![file isdirectory $session]} { error "Open a Session before using Session scripts." }
            return [file join [file normalize $session] scripts registered]
        }
        default { error "Script scope must be user or session." }
    }
}

proc ::GX::scriptRegistryId {id} {
    if {![regexp {^[A-Za-z][A-Za-z0-9_.-]*$} $id]} { error "Invalid script ID '$id'." }
    return $id
}

proc ::GX::scriptRegistryPath {scope id {session ""}} {
    scriptRegistryId $id
    return [file join [scriptRegistryRoot $scope $session] $id]
}

proc ::GX::scriptRegistryDefaults {} {
    return [dict create id "" name "" language Octave scope "" description "" version 1.0.0 \
        revision 1 sha256 "" required_apis "" declared_apis "" explicit_apis "" source_scope "" source_id "" source_sha256 "" \
        created_at "" updated_at "" parameters [dict create] callables [dict create]]
}

proc ::GX::scriptRegistryValidate {metadata} {
    if {[catch {dict size $metadata}]} { error "Script metadata must be a dictionary." }
    set m [dict merge [scriptRegistryDefaults] $metadata]
    scriptRegistryId [dict get $m id]
    scriptRegistrySourceName [dict get $m language]
    if {[dict get $m scope] ni {user session}} { error "Script scope must be user or session." }
    if {[string trim [dict get $m name]] eq ""} { error "Script display name is required." }
    if {![regexp {^[0-9]+\.[0-9]+\.[0-9]+$} [dict get $m version]]} { error "Script version must be major.minor.patch." }
    if {![string is integer -strict [dict get $m revision]] || [dict get $m revision] < 1} { error "Script revision must be >= 1." }
    foreach key {name description required_apis declared_apis explicit_apis source_scope source_id source_sha256} {
        if {[regexp {[\r\n]} [dict get $m $key]]} { error "Script $key must be one line." }
    }
    set params [dict get $m parameters]
    if {[catch {dict size $params}]} { error "Script parameter schema must be a dictionary." }
    dict for {name descriptor} $params {
        if {![regexp {^[A-Za-z_][A-Za-z0-9_]*$} $name]} { error "Invalid script parameter name '$name'." }
        if {[catch {dict size $descriptor}]} { error "Script parameter '$name' must be a dictionary." }
        set descriptor [dict merge [dict create type string required 0 default "" description ""] $descriptor]
        if {[dict get $descriptor type] ni {string integer double number boolean choice color path file command}} { error "Unsupported type for parameter '$name'." }
        if {![string is boolean -strict [dict get $descriptor required]]} { error "Invalid required flag for parameter '$name'." }
        if {[regexp {[\r\n]} [dict get $descriptor description]]} { error "Parameter description must be one line." }
        dict set params $name $descriptor
    }
    dict set m parameters $params
    dict set m callables [scriptRegistryCallablesValidate [dict get $m callables]]
    return $m
}

proc ::GX::scriptRegistryHash {path} {
    set code {import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())}
    return [string trim [exec [runtimeToolResolve python] -c $code $path]]
}

proc ::GX::scriptRegistryDeclaredApis {language source} {
    set parser [file join $::GX::scriptDir core python script_api_declarations.py]
    return [string trim [exec [runtimeToolResolve python] -B $parser $language $source]]
}

proc ::GX::scriptRegistryWrite {metadata code {session ""}} {
    set m [scriptRegistryValidate $metadata]
    set dir [scriptRegistryPath [dict get $m scope] [dict get $m id] $session]
    set target $dir
    set isNew [expr {![file exists $target]}]
    if {$isNew} {set dir "${target}.[pid].[clock clicks].pending"}
    file mkdir $dir
    try {
    set source [file join $dir [scriptRegistrySourceName [dict get $m language]]]
    set temp "${source}.[pid].tmp"
    set ch [open $temp w]
    fconfigure $ch -encoding utf-8 -translation lf
    try { puts -nonewline $ch $code } finally { close $ch }
    set hash [scriptRegistryHash $temp]
    set declared [scriptRegistryDeclaredApis [dict get $m language] $temp]
    dict set m declared_apis $declared
    dict set m required_apis [join [lsort -unique [concat \
        [splitList [dict get $m explicit_apis]] [splitList $declared]]] {;}]
    file rename -force -- $temp $source
    dict set m sha256 $hash
    set now [clock format [clock seconds] -gmt 1 -format {%Y-%m-%dT%H:%M:%SZ}]
    if {[dict get $m created_at] eq ""} { dict set m created_at $now }
    dict set m updated_at $now
    set path [file join $dir script.ini]
    set temp "${path}.[pid].tmp"
    set ch [open $temp w]
    fconfigure $ch -encoding utf-8 -translation lf
    try {
        puts $ch "; GX-TXT CORE Script Registry v1"
        puts $ch "\[script\]"
        foreach key {id name language scope description version revision sha256 required_apis declared_apis explicit_apis source_scope source_id source_sha256 created_at updated_at} {
            putKV $ch $key [dict get $m $key]
        }
        putKV $ch parameter_ids [join [lsort -dictionary [dict keys [dict get $m parameters]]] {;}]
        putKV $ch callable_ids [join [lsort -dictionary [dict keys [dict get $m callables]]] {;}]
        dict for {name declaration} [dict get $m callables] {
            puts $ch "\n\[callable.$name\]"
            foreach key {entrypoint contract declaration} {putKV $ch $key [dict get $declaration $key]}
        }
        dict for {name descriptor} [dict get $m parameters] {
            puts $ch "\n\[parameter.$name\]"
            foreach key {type required default description values min max alpha allow_inherit} {if {[dict exists $descriptor $key]} {putKV $ch $key [dict get $descriptor $key]}}
        }
    } finally { close $ch }
    file rename -force -- $temp $path
    if {$isNew} {if {[file exists $target]} {error {Script identity appeared during registration}};file rename -- $dir $target}
    return $m
    } on error {reason options} {if {$isNew} {catch {file delete -force -- $dir}};return -options $options $reason}
}

proc ::GX::scriptRegistryRead {scope id {session ""}} {
    set dir [scriptRegistryPath $scope $id $session]
    set path [file join $dir script.ini]
    if {![file isfile $path]} { error "Registered script '$scope:$id' is incomplete." }
    set ini [parseIni $path]
    set m [scriptRegistryDefaults]
    foreach key {id name language scope description version revision sha256 required_apis declared_apis explicit_apis source_scope source_id source_sha256 created_at updated_at} {
        if {[dict exists $ini script.$key]} { dict set m $key [dict get $ini script.$key] }
    }
    if {![dict exists $ini script.explicit_apis]} { dict set m explicit_apis [dict get $m required_apis] }
    set params [dict create]
    foreach name [splitList [expr {[dict exists $ini script.parameter_ids] ? [dict get $ini script.parameter_ids] : ""}]] {
        set descriptor [dict create]
        foreach key {type required default description values min max alpha allow_inherit} {
            if {[dict exists $ini parameter.$name.$key]} { dict set descriptor $key [dict get $ini parameter.$name.$key] }
        }
        dict set params $name $descriptor
    }
    dict set m parameters $params
    set callables {}
    foreach name [splitList [expr {[dict exists $ini script.callable_ids] ? [dict get $ini script.callable_ids] : ""}]] {
        set declaration {}
        foreach key {entrypoint contract declaration} {
            if {![dict exists $ini callable.$name.$key]} {error {Registered callable metadata is incomplete}}
            dict set declaration $key [dict get $ini callable.$name.$key]
        }
        if {[dict exists $callables $name]} {error {Duplicate registered callable ID}}
        dict set callables $name $declaration
    }
    dict set m callables $callables
    set m [scriptRegistryValidate $m]
    set source [file join $dir [scriptRegistrySourceName [dict get $m language]]]
    if {![file isfile $source]} { error "Registered script '$scope:$id' is incomplete." }
    if {[dict get $m id] ne $id || [dict get $m scope] ne $scope} { error "Registered script identity disagrees with its storage path." }
    if {[string tolower [dict get $m sha256]] ne [scriptRegistryHash $source]} { error "Registered script '$scope:$id' failed SHA-256 verification." }
    dict set m source_path $source
    set policy [_scriptLegacyPreviewPolicy $m]
    if {$policy eq {verified_legacy_private}} {return -code error -errorcode {GXTXT SCRIPT CORE_PRIVATE} {Verified legacy CORE Preview service is not a user script; original source and historical Jobs are retained}}
    if {$policy ne {user}} {dict set m access_policy $policy;dict set m diagnostic {Legacy CORE identity has modified or unverifiable source. Preserve and review before running or changing it.}}
    return $m
}

proc ::GX::scriptRegistrySave {scope id name code {options {}} {session ""}} {
    if {[catch {dict size $options}]} { error "Script options must be a dictionary." }
    set dir [scriptRegistryPath $scope $id $session]
    if {[file exists $dir]} { error "Registered script '$scope:$id' already exists; update it explicitly." }
    set m [dict merge [scriptRegistryDefaults] $options [dict create id $id name $name scope $scope]]
    dict set m explicit_apis [dict get $m required_apis]
    return [scriptRegistryWrite $m $code $session]
}

proc ::GX::scriptRegistryUpdate {scope id expectedSha metadata code {session ""}} {
    set current [scriptRegistryRead $scope $id $session]
    if {[dict exists $current access_policy]} {error [dict get $current diagnostic]}
    if {[string tolower [dict get $current sha256]] ne [string tolower $expectedSha]} { error "Script changed since it was opened; reload before editing." }
    foreach immutable {id scope language source_scope source_id source_sha256 created_at} {
        if {[dict exists $metadata $immutable] && [dict get $metadata $immutable] ne [dict get $current $immutable]} {
            error "Script $immutable cannot be changed by an edit."
        }
    }
    set m [dict merge $current $metadata]
    if {[dict exists $metadata required_apis]} { dict set m explicit_apis [dict get $metadata required_apis] }
    dict set m revision [expr {[dict get $current revision] + 1}]
    return [scriptRegistryWrite $m $code $session]
}

proc ::GX::scriptRegistryList {{scope all} {session ""}} {
    set scopes [expr {$scope eq "all" ? {user session} : [list $scope]}]
    set out {}
    foreach one $scopes {
        if {$one eq "session" && $session eq "" && (![info exists ::GX::currentSession] || $::GX::currentSession eq "")} continue
        set root [scriptRegistryRoot $one $session]
        foreach dir [glob -nocomplain -directory $root *] {
            if {![file isdirectory $dir]} continue
            set id [file tail $dir]
            if {[catch {set m [scriptRegistryRead $one $id $session]}]} continue
            lappend out $m
        }
    }
    return [lsort -command ::GX::scriptRegistryCompare $out]
}

proc ::GX::scriptRegistryCompare {a b} {
    return [string compare "[dict get $a scope]:[dict get $a id]" "[dict get $b scope]:[dict get $b id]"]
}

proc ::GX::scriptRegistryDescribe {reference {session ""}} {
    if {![regexp {^(user|session):(.+)$} $reference -> scope id]} { error "Use a qualified script ID such as user:my_script or session:my_script." }
    set m [scriptRegistryRead $scope $id $session]
    if {[dict exists $m access_policy]} {error [dict get $m diagnostic]}
    return $m
}

proc ::GX::scriptRegistryAssignToSession {userId {session ""}} {
    set source [scriptRegistryRead user $userId]
    if {$session eq ""} { set session $::GX::currentSession }
    set id [dict get $source id]
    if {[file exists [scriptRegistryPath session $id $session]]} { error "Session already owns a script with ID '$id'." }
    set ch [open [dict get $source source_path] r]
    fconfigure $ch -encoding utf-8
    try { set code [read $ch] } finally { close $ch }
    dict set source source_scope user
    dict set source source_id $id
    dict set source source_sha256 [dict get $source sha256]
    dict set source scope session
    dict set source revision 1
    return [scriptRegistryWrite $source $code $session]
}

proc ::GX::scriptRegistryRemove {reference {session ""}} {
    set m [scriptRegistryDescribe $reference $session]
    set dir [scriptRegistryPath [dict get $m scope] [dict get $m id] $session]
    # A registered script owns precisely these two files. Refuse to remove a
    # directory with unexpected content, rather than deleting recursively.
    set contents [lsort [lmap p [glob -nocomplain -directory $dir * .*] {
        set name [file tail $p]
        if {$name in {. ..}} continue
        set name
    }]]
    set sourceName [scriptRegistrySourceName [dict get $m language]]
    if {$contents ne [lsort [list script.ini $sourceName]]} {
        error "Script directory contains unexpected files; remove them explicitly before unregistering."
    }
    file delete -- [file join $dir script.ini] [file join $dir $sourceName]
    file delete -- $dir
}

proc ::GX::scriptExecutionParameters {metadata supplied} {
    if {[catch {dict size $supplied}]} { error "Script parameters must be a dictionary." }
    set schema [dict get $metadata parameters]
    foreach key [dict keys $supplied] { if {![dict exists $schema $key]} { error "Unknown script parameter '$key'." } }
    set out [dict create]
    dict for {key descriptor} $schema {
        if {[dict exists $supplied $key]} {
            set value [dict get $supplied $key]
        } elseif {[dict get $descriptor default] ne ""} {
            set value [dict get $descriptor default]
        } elseif {[dict get $descriptor required]} {
            error "Required script parameter '$key' is missing."
        } else {
            continue
        }
        set value [uiFieldNormalize $descriptor $value]
        dict set out $key $value
    }
    return $out
}

proc ::GX::scriptExecutionPrepare {reference parameters {session ""} {runtimeTemplate ""} {moduleOutputDir ""} {invocation {}} {coreService {}}} {
    if {$session eq ""} { set session $::GX::currentSession }
    if {$session eq "" || ![file isdirectory $session]} { error "Open a Session before running a registered script." }
    set session [file normalize $session]
    if {$coreService ne {}} {
        if {$reference ne "core-service:$coreService"} {error {CORE service identity mismatch}}
        set m [_scriptCoreServiceMetadata $coreService]
    } else {set m [scriptRegistryDescribe $reference $session]}
    if {$invocation ne {}} {set invocation [scriptCallableInvocationValidate $reference $invocation $session]}
    set language [dict get $m language]
    set moduleId [scriptAnalysisModule $language]
    set extension [expr {$language eq "Python" ? ".py" : ".m"}]
    set values [scriptExecutionParameters $m $parameters]
    set runId "script-[clock format [clock seconds] -gmt 1 -format %Y%m%dT%H%M%SZ]-[pid]-[clock clicks]"
    set outDir [file join $session analysis scripts $runId]
    if {[file exists $outDir]} { error "Script execution path already exists: $outDir" }
    file mkdir $outDir
    if {$runtimeTemplate eq "" && [llength [info commands ::GX::writeStandardRuntimeConfig]] &&
        [moduleField $moduleId descriptor ""] ne ""} {
        set ::GX::scriptRuntimeOutputOverride [dict create module $moduleId path [file join $outDir template]]
        try {
            if {![catch {writeStandardRuntimeConfig $moduleId} candidate]} {set runtimeTemplate $candidate}
        } finally {unset ::GX::scriptRuntimeOutputOverride}
    }
    set extraApis ""
    set argumentsRaw ""
    set workingDirectory $session
    if {$runtimeTemplate ne ""} {
        if {![file isfile $runtimeTemplate]} { error "Script runtime template is missing: $runtimeTemplate" }
        set templateIni [parseIni $runtimeTemplate]
        if {$moduleOutputDir ne ""} {
            if {[dict exists $templateIni config.required_apis]} { set extraApis [dict get $templateIni config.required_apis] }
            if {[dict exists $templateIni config.arguments]} { set argumentsRaw [dict get $templateIni config.arguments] }
            if {[dict exists $templateIni config.working_directory] && [string trim [dict get $templateIni config.working_directory]] ne ""} {
                set workingDirectory [dict get $templateIni config.working_directory]
            }
        }
    }
    set requiredApis [join [lsort -unique [concat [splitList [dict get $m required_apis]] [splitList $extraApis]]] {;}]
    if {$invocation ne {}} {set requiredApis [join [lsort -unique [concat [splitList $requiredApis] [list [dict get $invocation consumer_api]]]] {;}]}
    set snapshot [file join $outDir registered_script$extension]
    file copy -- [dict get $m source_path] $snapshot
    if {[scriptRegistryHash $snapshot] ne [dict get $m sha256]} { error "Script snapshot changed during execution preparation." }
    set runtime [file join $outDir runtime.ini]
    if {$runtimeTemplate ne ""} { file copy -- $runtimeTemplate $runtime }
    set ch [open $runtime [expr {$runtimeTemplate eq "" ? "w" : "a"}]]
    fconfigure $ch -encoding utf-8 -translation lf
    try {
        puts $ch "; GX-TXT CORE Script Execution API v1"
        puts $ch "\[runtime\]"
        foreach {key value} [list api_version 1 module_id $moduleId session $session output_dir $outDir \
            run_id $runId operation script_execution python_cmd [runtimeToolResolve python]] {
            putKV $ch $key $value
        }
        puts $ch "\n\[config\]"
        foreach {key value} [list source_mode [expr {$coreService eq {}?{registered_script}:{core_service}}] registered_script $reference script_file $snapshot \
            script_id [dict get $m id] script_scope [dict get $m scope] script_name [dict get $m name] \
            script_version [dict get $m version] script_revision [dict get $m revision] \
            script_sha256 [dict get $m sha256] script_language $language working_directory $workingDirectory \
            include_script_directory 0 arguments $argumentsRaw required_apis $requiredApis] {
            putKV $ch $key $value
        }
        foreach key [lsort -dictionary [dict keys $values]] {
            puts $ch "\n\[script_parameter.$key\]"
            putKV $ch type [dict get [dict get $m parameters $key] type]
            putKV $ch value [dict get $values $key]
        }
        if {$invocation ne {}} {
            puts $ch "\n\[registered_callable\]"
            dict for {key value} $invocation {putKV $ch $key $value}
        }
    } finally { close $ch }
    if {$language eq "Python"} {
        set executable [runtimeToolResolve python]
        if {$executable eq ""} { error "Python runtime is not configured." }
        set runner [file join $::GX::scriptDir core python gxtxt_python_script_execution.py]
        set command [list $executable -B $runner --config $runtime]
    } else {
        set executable [runtimeToolResolve octave]
        if {$executable eq ""} { error "Octave CLI is not configured." }
        set runner [file join $::GX::scriptDir core octave gxtxt_script_execution.m]
        set command [list $executable --quiet --no-gui $runner --config $runtime]
    }
    return [dict create session $session m $m values $values language $language moduleId $moduleId requiredApis $requiredApis runId $runId outDir $outDir snapshot $snapshot runtime $runtime command $command moduleOutputDir $moduleOutputDir]
}

proc ::GX::scriptExecutionRun {reference parameters {session ""} {runtimeTemplate ""} {moduleOutputDir ""}} {
    set prepared [scriptExecutionPrepare $reference $parameters $session $runtimeTemplate $moduleOutputDir]
    dict for {key value} $prepared {set $key $value}
    if {$requiredApis ne ""} {
        set preflight [file join $::GX::scriptDir core python script_api_preflight.py]
        if {[catch {exec [runtimeToolResolve python] -B $preflight $runtime 2>@1} reason]} {
            error "$moduleId: $reason"
        }
    }
    set started [clock seconds]
    set rc [catch {exec {*}$command 2>@1} output options]
    set pythonExecutable ""
    set pythonVersion ""
    if {$language eq "Python" && [file isfile [file join $outDir python_runtime.ini]]} {
        set actualRuntime [parseIni [file join $outDir python_runtime.ini]]
        set pythonExecutable [dict get $actualRuntime runtime.python_executable]
        set pythonVersion [dict get $actualRuntime runtime.python_version]
    }
    set report [file join $outDir execution.ini]
    set ch [open $report w]
    fconfigure $ch -encoding utf-8 -translation lf
    try {
        puts $ch "; GX-TXT registered script execution provenance"
        puts $ch "\[execution\]"
        foreach {key value} [list run_id $runId script_id [dict get $m id] script_name [dict get $m name] script_scope [dict get $m scope] \
            script_version [dict get $m version] script_revision [dict get $m revision] language $language \
            script_sha256 [dict get $m sha256] required_apis $requiredApis \
            source_scope [dict get $m source_scope] source_id [dict get $m source_id] \
            source_sha256 [dict get $m source_sha256] \
            python_executable $pythonExecutable python_version $pythonVersion \
            script_reference $reference module_version [moduleField $moduleId version ""] \
            status [expr {$rc ? "FAILED" : "PASS"}] \
            started_at $started finished_at [clock seconds] source_snapshot $snapshot output_dir $outDir] {
            putKV $ch $key $value
        }
        puts $ch "\n\[parameters\]"
        dict for {key value} $values { putKV $ch $key $value }
    } finally { close $ch }
    set logName [expr {$language eq "Python" ? "python.log" : "octave.log"}]
    set log [open [file join $outDir $logName] w]
    fconfigure $log -encoding utf-8 -translation lf
    try { puts $log $output } finally { close $log }
    if {$moduleOutputDir ne ""} {
        file mkdir $moduleOutputDir
        set names [expr {$language eq "Python" ? {python_script_run_report.txt executed_script.py execution.ini python.log} : {octave_script_run_report.txt executed_script.m execution.ini octave.log}}]
        foreach name $names {
            set source [file join $outDir $name]
            if {[file isfile $source]} { file copy -force -- $source [file join $moduleOutputDir $name] }
        }
    }
    # Bridge hosts commit through the normal Dataset authority in a separate
    # process. Reconcile those committed changes at execution completion so
    # host consumers/subscribers do not retain their pre-execution registry.
    loadDatasetRegistry $session
    if {$rc} { return -options $options "Registered script '$reference' failed: $output" }
    return [dict create status PASS run_id $runId output_dir $outDir script $m parameters $values]
}

proc ::GX::scriptAnalysisBuildQueueItem {id} {
    variable moduleCfg
    variable currentSession
    set mode [string trim $moduleCfg($id,source_mode)]
    if {$mode ne "registered_script"} { error "$id: unsupported registered source mode '$mode'." }
    set reference [string trim $moduleCfg($id,registered_script)]
    if {![regexp {^session:[A-Za-z][A-Za-z0-9_.-]*$} $reference]} {
        error "$id: select a registered Session script."
    }
    set script [scriptRegistryDescribe $reference $currentSession]
    if {[scriptAnalysisModule [dict get $script language]] ne $id} {
        error "$id: selected Session script is [dict get $script language], not the module language."
    }
    set requestId [progressNewRunId $id analysis]
    set output [file join $currentSession analysis [sanitize $id]]
    file mkdir $output
    set ::GX::scriptRuntimeOutputOverride [dict create module $id path [file join $currentSession analysis scripts request-$requestId]]
    try {set runtime [writeStandardRuntimeConfig $id]} finally {unset ::GX::scriptRuntimeOutputOverride}
    set statusPath [file join $output .registered_queue_status]
    set statusFile [open $statusPath w]
    try { puts $statusFile RUNNING } finally { close $statusFile }
    set runId [progressNewRunId $id analysis]
    set command [list tclsh [file join $::GX::scriptDir core tcl script_execution_cli.tcl] \
        $::GX::scriptDir $currentSession $reference $runtime $output $statusPath]
    return [list "Analysis - [moduleField $id name $id]" $command $id $runId]
}

# Installed immutable CORE service source is never a Session Script Registry item.
proc ::GX::_scriptCoreServiceMetadata {service} {
    if {$service eq {scientific-provider}} {
        set source [file join $::GX::scriptDir core python gxtxt_core_scientific_service.py]
        return [dict merge [scriptRegistryDefaults] [dict create id scientific-provider name {Scientific provider execution} language Python scope core version 1.0.0 revision 1 source_path $source sha256 [sha256File $source] parameters [dict create request {type string required 1}]]]
    }
    if {$service ne {dataset-preview}} {error {Unknown private CORE service}}
    set source [file join $::GX::scriptDir core python gxtxt_core_preview_service.py]
    return [dict merge [scriptRegistryDefaults] [dict create id dataset-preview name {CORE Dataset Preview preparation} language Python scope core version 1.0.0 revision 1 source_path $source sha256 [sha256File $source] required_apis DATASET_PREVIEW_API_v1 parameters [dict create dataset_id {type string required 1} options {type string default {}} expected_key {type string required 1}]]]
}
proc ::GX::_scriptLegacyPreviewPolicy {metadata} {
    if {[dict get $metadata id] ne {gx-core-dataset-preview} || [dict get $metadata name] ne {CORE Dataset Preview preparation} || [dict get $metadata language] ne {Python}} {return user}
    set trusted [_scriptCoreServiceMetadata dataset-preview]
    if {[dict get $metadata version] eq {1.0.0} && [dict get $metadata revision]==1 && [dict get $metadata source_scope] eq {} && [dict get $metadata source_sha256] eq {} && [dict get $metadata sha256] eq [dict get $trusted sha256] && [lsort [dict keys [dict get $metadata parameters]]] eq {dataset_id expected_key options}} {return verified_legacy_private}
    return legacy_conflict_requires_review
}

proc ::GX::scriptRegistryImportSource {session path id name language {provenance {}}} {
    set session [_sessionInspectionRequire $session]
    scriptRegistryId $id
    if {$language ni {Python Octave}} {error {Session script import requires Python or explicitly confirmed GNU Octave language}}
    if {![file isfile $path] || [file type $path] eq {link} || [file size $path]>4194304} {error {Script import requires a regular source file up to 4 MiB}}
    set ch [open $path rb];try {set raw [read $ch]} finally {close $ch}
    set bytes $raw
    if {[string range $bytes 0 2] eq [binary format H* efbbbf]} {set bytes [string range $bytes 3 end]}
    set code [encoding convertfrom utf-8 $bytes]
    if {[encoding convertto utf-8 $code] ne $bytes} {error {Script Registry import requires UTF-8. Choose Dataset destination to preserve a different source encoding.}}
    set original [sha256File $path]
    set options [dict create language $language source_scope import source_id [file tail $path] source_sha256 $original description {Imported inert source. UTF-8 BOM is removed if present; no code was executed.}]
    if {$provenance ne {}} {dict set options description $provenance}
    set result [scriptRegistrySave session $id $name $code $options $session]
    return [dict create outcome registered_session_script reference session:$id language $language revision [dict get $result revision] sha256 [dict get $result sha256] original_sha256 $original session $session executed 0]
}
