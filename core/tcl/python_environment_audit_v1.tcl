# SPDX-License-Identifier: GPL-3.0-or-later
# Additive host-only scopes on the existing Python Environment scanner.
proc ::GX::_pythonAuditJsonObject {fields} {
    set result {}
    dict for {key value} $fields {lappend result "[viewerDevelopmentJsonString $key]:[viewerDevelopmentJsonString $value]"}
    return \{[join $result ,]\}
}
proc ::GX::_pythonAuditWalk {root maximum} {
    set root [file normalize $root];set pending [list $root];set result {};set directories 0
    while {$pending ne {} && [llength $result]<$maximum && $directories<500} {
        set directory [lindex $pending 0];set pending [lrange $pending 1 end];incr directories
        foreach path [lsort [glob -nocomplain -directory $directory *]] {
            if {[file type $path] eq {link}} continue
            if {[file isdirectory $path]} {
                if {[file tail $path] ni {__pycache__ venv .venv archives expanded validation tests third_party}} {lappend pending $path}
            } elseif {[file extension $path] eq {.py}} {
                lappend result [file normalize $path]
                if {[llength $result]>=$maximum} break
            }
        }
    }
    return [dict create paths $result truncated [expr {$pending ne {} || [llength $result]>=$maximum}]]
}
proc ::GX::_pythonEnvironmentAuditPlan {request} {
    if {$::GX::DatasetPrivate::activeContext ne {}} {error {Python import audit scopes require the user/admin host}}
    foreach key [dict keys $request] {if {$key ni {scope reference}} {error "Unsupported Python audit scope field '$key'"}}
    set scope [datasetPublicationV2DictDefault $request scope {}]
    if {$scope ni {script project framework}} {error {Choose a registered Python Script/Project or installed framework scope}}
    set files {};set truncated 0
    if {$scope in {script project}} {
        if {![dict exists $request reference]} {error {Choose a registered Python source identity}}
        set metadata [scriptRegistryDescribe [dict get $request reference]]
        if {[dict get $metadata language] ne {Python}} {error {Python dependency audit requires a Python Script or Project}}
        set kind [datasetPublicationV2DictDefault $metadata kind script]
        if {$scope eq {project} && $kind ne {project}} {error {The selected Registry record is not a Script Project}}
        if {$kind eq {project}} {
            set scope project;set root [dict get $metadata project_root];set paths [dict get $metadata admitted_sources]
        } else {set root [file dirname [dict get $metadata source_path]];set paths [list [dict get $metadata source_path]]}
        set reference [dict get $request reference]
        set scopeIdentity [list $reference [dict get $metadata revision] [dict get $metadata sha256]]
        foreach path $paths {lappend files [_pythonAuditJsonObject [dict create path $path root $root sha256 [sha256File $path] logical_id $reference]]}
    } else {
        set scopeIdentity [list framework [file normalize $::GX::scriptDir]]
        set roots [list [list core [file join $::GX::scriptDir core python]]]
        foreach id $::GX::moduleOrder {
            if {[moduleIsEnabled $id]} {lappend roots [list $id [file dirname [moduleField $id descriptor {}]]];lappend scopeIdentity $id [moduleField $id version {}]}
        }
        set seen {};set totalBytes 0
        foreach pair $roots {
            lassign $pair logical root
            if {![file isdirectory $root]} continue
            set walked [_pythonAuditWalk $root [expr {1000-[llength $files]}]]
            if {[dict get $walked truncated]} {set truncated 1}
            foreach path [dict get $walked paths] {
                if {[dict exists $seen $path]} continue
                dict set seen $path 1
                set bytes [file size $path]
                if {$bytes>4194304 || $totalBytes+$bytes>33554432} {set truncated 1;continue}
                incr totalBytes $bytes
                lappend files [_pythonAuditJsonObject [dict create path $path root $root sha256 [sha256File $path] logical_id $logical]]
            }
            if {[llength $files]>=1000} {set truncated 1;break}
        }
    }
    if {$files eq {}} {error {No admitted Python source files are available in this scope}}
    set sessionIdentity [expr {[info exists ::GX::currentSession]?$::GX::currentSession:{}}]
    if {[dict exists $::GX::datasetCatalogState session_token]} {lappend sessionIdentity [dict get $::GX::datasetCatalogState session_token]}
    set json [format {{"schema":"gxtxt.python_import_audit_request.v1","scope":%s,"scope_identity":%s,"session_identity":%s,"truncated":%s,"sources":[%s]}} \
        [viewerDevelopmentJsonString $scope] [viewerDevelopmentJsonString $scopeIdentity] [viewerDevelopmentJsonString $sessionIdentity] [expr {$truncated?{true}:{false}}] [join $files ,]]
    if {[string bytelength $json]>2097152} {error {Python source admission exceeds 2 MiB; choose a smaller scope}}
    set interpreter [runtimeToolRequired python]
    return [dict create request $request scope $scope scope_identity $scopeIdentity file_count [llength $files] admission_json $json interpreter $interpreter interpreter_sha256 [sha256File $interpreter]]
}
proc ::GX::pythonEnvironmentAuditImports {request {callback {}}} {
    set plan [_pythonEnvironmentAuditPlan $request]
    set command [pythonEnvironmentCommand audit]
    if {$callback eq {}} {
        return [_pythonEnvironmentAuditSync $plan]
    }
    return [scriptJobAsync $command [dict get $plan admission_json] \
        [list ::GX::_pythonEnvironmentAuditFinished $plan $callback] \
        {timeout_ms 120000 max_bytes 16777216 process_group 1 ui_lifetime 1 label {Python source import availability audit}}]
}
proc ::GX::_pythonEnvironmentAuditSync {plan {report {}}} {
    set command [pythonEnvironmentCommand audit]
    if {$report ne {}} {lappend command --report $report}
    set response [exec {*}$command << [dict get $plan admission_json]]
    if {![dict get $response ok]} {error [dict get $response error]}
    return [dict get $response result]
}
proc ::GX::_pythonEnvironmentAuditFinished {plan callback response} {
    if {[dict get $response ok]} {
        if {[catch {set current [_pythonEnvironmentAuditPlan [dict get $plan request]]} reason]} {
            set response [dict create ok 0 error "Python audit source scope is no longer available: $reason"]
        } elseif {[dict get $plan admission_json] ne [dict get $current admission_json] || [dict get $plan interpreter] ne [dict get $current interpreter] || [dict get $plan interpreter_sha256] ne [dict get $current interpreter_sha256]} {
            set response [dict create ok 0 error {Python audit source or configured interpreter changed; refresh the review}]
        }
    }
    uplevel #0 [list {*}$callback $response]
}
proc ::GX::pythonEnvironmentAuditCancel {requestId} {scriptJobRequestCancel $requestId}
