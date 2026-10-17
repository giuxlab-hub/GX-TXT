# SPDX-License-Identifier: GPL-3.0-or-later
# The Standard Analysis queue remains the sole process/progress owner. These
# receipts describe invocations; they are not a second scheduler or Job store.
namespace eval ::GX {variable targetedAnalysisActive {};variable targetedAnalysisTimer {}}
proc ::GX::moduleAnalysisCapabilities {module} {
    set reason {}
    if {[moduleField $module descriptor {}] eq {}} {set reason {Unknown module}}
    if {$reason eq {} && (![moduleIsRunnableAnalysis $module] || [moduleField $module runner {}] ne "standard_octave")} {set reason {Target requires a runnable Standard Octave Analysis module}}
    foreach dependency [splitList [moduleField $module depends {}]] {
        if {$reason eq {} && [moduleField $dependency descriptor {}] eq {}} {set reason "Required module '$dependency' is not installed"}
    }
    return [dict create api_id MODULE_API_v1 operation targeted_analysis module_id $module available [expr {$reason eq {}}] reason $reason runner [moduleField $module runner {}] request_fields {session_token sources config tables bindings document_id document_revision document_generation} execution_owner standard_analysis_queue mutation_scope invocation_only host_only 1]
}
proc ::GX::_moduleAnalysisCaller {caller {admission 1}} {
    if {[moduleField $caller kind {}] ne "viewer"} {error {An installed registered Viewer is required for targeted Analysis admission}}
}
proc ::GX::_moduleAnalysisReceiptPath {module run} {
    if {[moduleField $module descriptor {}] eq {} || ![regexp {^[A-Za-z0-9_.-]+$} $run]} {error {Invalid Analysis receipt identity}}
    return [file join $::GX::currentSession analysis [sanitize $module] targeted_runs $run.ini]
}
proc ::GX::_moduleAnalysisWriteReceipt {receipt} {
    set path [dict get $receipt receipt_path];file mkdir [file dirname $path]
    set f [open $path w];fconfigure $f -encoding utf-8 -translation lf
    try {puts $f "\[targeted_analysis\]";dict for {key value} $receipt {putKV $f $key $value}} finally {close $f}
}
proc ::GX::moduleAnalysisFinish {state reason} {
    variable targetedAnalysisActive;variable targetedAnalysisTimer
    if {$targetedAnalysisActive eq {}} return
    if {$targetedAnalysisTimer ne {}} {after cancel $targetedAnalysisTimer;set targetedAnalysisTimer {}}
    dict set targetedAnalysisActive state $state;dict set targetedAnalysisActive reason $reason
    dict set targetedAnalysisActive finished_utc [clock format [clock seconds] -gmt 1 -format {%Y-%m-%dT%H:%M:%SZ}]
    _moduleAnalysisWriteReceipt $targetedAnalysisActive
    set targetedAnalysisActive {}
}
proc ::GX::moduleAnalysisScopeValid {{verifySources 1}} {
    variable targetedAnalysisActive
    if {$targetedAnalysisActive eq {}} {return 1}
    if {[catch {interactiveDocumentSessionToken} token] || $token ne [dict get $targetedAnalysisActive session_token]} {return 0}
    if {[dict exists $targetedAnalysisActive document_id] && [dict get $targetedAnalysisActive document_id] ne {}} {
        if {[catch {interactiveDocumentRead [dict get $targetedAnalysisActive document_id]} document] || [dict get $document revision] ne [dict get $targetedAnalysisActive document_revision] || [dict get $document generation] ne [dict get $targetedAnalysisActive document_generation]} {return 0}
    }
    if {$verifySources} {dict for {id identity} [dict get $targetedAnalysisActive source_identities] {
        if {[catch {_curveSourceIdentity $::GX::currentSession $id} actual] || $actual ne $identity} {return 0}
    }
    }
    return 1
}
proc ::GX::_moduleAnalysisGuard {} {
    variable targetedAnalysisActive;variable targetedAnalysisTimer
    set targetedAnalysisTimer {}
    if {$targetedAnalysisActive eq {}} return
    # Full scientific identity checks belong to admission/completion, not the
    # GUI heartbeat: hashing a large Dataset repeatedly would block Tk.
    if {![moduleAnalysisScopeValid 0]} {
        moduleAnalysisFinish FAILED {Session, document or scientific source changed during invocation}
        stopAnalysis 0
    } else {set targetedAnalysisTimer [after 250 ::GX::_moduleAnalysisGuard]}
}
proc ::GX::moduleAnalysisSubmit {caller module request} {
    variable targetedAnalysisActive
    _moduleAnalysisCaller $caller
    set capability [moduleAnalysisCapabilities $module]
    if {![dict get $capability available]} {error [dict get $capability reason]}
    foreach key [dict keys $request] {if {$key ni [dict get $capability request_fields]} {error "Unknown targeted Analysis request field '$key'"}}
    set token [interactiveDocumentSessionToken]
    if {![dict exists $request session_token] || [dict get $request session_token] ne $token} {error {Stale or missing Session token}}
    if {$targetedAnalysisActive ne {} || $::GX::analysisPipe ne {} || [llength $::GX::analysisQueue]} {return -code error -errorcode {GXTXT ANALYSIS BUSY} {Analysis queue is busy}}
    if {[dict exists $request document_id]} {
        set document [interactiveDocumentRead [dict get $request document_id]]
        if {[dict get $document module_id] ne $caller || ![dict exists $request document_revision] || [dict get $document revision] ne [dict get $request document_revision] || ![dict exists $request document_generation] || [dict get $document generation] ne [dict get $request document_generation]} {error {Viewer document ownership, generation or revision mismatch}}
    }
    # Snapshot only this module's established configuration authorities. No Run
    # checkbox changes, Manifest write or event-loop turn occurs during binding.
    set snapshots {}
    foreach owner {moduleCfg moduleBinding moduleAnalysisSource moduleAnalysisSourceCount repeatableRows repeatableValue repeatableNext analysisParamValue analysisParamDefinition} {
        upvar #0 ::GX::$owner state
        set values {};if {[array exists state]} {foreach k [array names state] {if {$k eq $module || [string first "$module," $k]==0} {dict set values $k $state($k)}}}
        dict set snapshots $owner $values
    }
    try {
        if {[dict exists $request sources]} {
            dict for {source dataset} [dict get $request sources] {
                if {![analysisSourceIsDeclared $module $source] && ![moduleAnalysisSourcesDynamic $module]} {error "Undeclared Analysis source '$source'"}
                set row [analysisSourceFindRow $module $source]
                if {!$row} {set row [analysisSourceAppendRow $module $source $dataset]} else {set ::GX::moduleAnalysisSource($module,$row,dataset_id) $dataset}
            }
        }
        analysisSourceValidateModule $module
        if {[dict exists $request config]} {
            dict for {key value} [dict get $request config] {
                if {$key ni [moduleConfigKeys $module]} {error "Unknown module parameter '$key'"}
                set type [moduleConfigField $module $key type string]
                if {$type eq {variable}} {
                    if {$value ne {}} {
                        set source [moduleConfigField $module $key source primary]
                        set row [analysisSourceFindRow $module $source]
                        set dataset [analysisSourceRowDataset $module $row]
                        set variable [datasetVariableV3ById $dataset $value]
                        if {![dict get $variable enabled]} {error "Variable '$value' is disabled in the canonical source schema"}
                    }
                    set ::GX::moduleCfg($module,$key) $value
                    continue
                }
                if {$type eq {selection}} {
                    set ::GX::moduleCfg($module,$key) $value
                    datasetSelectionValidateConfig $module $key
                    continue
                }
                if {$type ni [dict get [uiFieldApiInfo] types]} {error "Parameter '$key' requires its typed Configuration authority"}
                set descriptor [dict create type $type label [moduleConfigField $module $key label $key]]
                foreach field {required min max} {set v [moduleConfigField $module $key $field {}];if {$v ne {}} {dict set descriptor $field $v}}
                if {$type eq "choice"} {dict set descriptor values [splitList [moduleConfigField $module $key values {}]]}
                set ::GX::moduleCfg($module,$key) [uiFieldNormalize $descriptor $value]
            }
        }
        if {[dict exists $request tables]} {dict for {key snapshot} [dict get $request tables] {if {![repeatableConfigIsTable $module $key]} {error "Unknown configuration table '$key'"};repeatableConfigApplySnapshot $module $key $snapshot}}
        if {[dict exists $request bindings]} {dict for {role value} [dict get $request bindings] {if {$role ni [moduleBindingRoles $module]} {error "Unknown input role '$role'"};set ::GX::moduleBinding($module,$role) $value}}
        set identities {};foreach row [analysisSourceRows $module] {set ds [analysisSourceRowDataset $module $row];if {$ds ne {}} {dict set identities $ds [_curveSourceIdentity $::GX::currentSession $ds]}}
        set queue [buildStandardAnalysisQueue_before_plot_variant $module]
        foreach graph [moduleGraphIds $module] {foreach variant [plotVariantIds $module $graph] {if {[plotVariantField $module $graph $variant enabled 1] && [graphUseStateGet $module $graph $variant]} {lappend queue [plotVariantCommand $module $graph $variant analysis]}}}
    } finally {
        dict for {owner values} $snapshots {
            upvar #0 ::GX::$owner state
            if {[array exists state]} {foreach k [array names state] {if {$k eq $module || [string first "$module," $k]==0} {unset state($k)}}}
            dict for {k value} $values {set state($k) $value}
        }
        foreach key [repeatableConfigTableKeys $module] {repeatableConfigRefreshWidget $module $key}
    }
    if {![llength $queue]} {error {Target did not produce a runnable Analysis queue}}
    set run [lindex [lindex $queue 0] 3]
    set receipt [dict create api_id MODULE_API_v1 caller_id $caller module_id $module run_id $run session_token $token state RUNNING reason {} source_identities $identities expected_outputs [moduleExpectedOutputs $module] output_directory [file join $::GX::currentSession analysis [sanitize $module]] receipt_path [_moduleAnalysisReceiptPath $module $run]]
    foreach key {document_id document_revision document_generation} {if {[dict exists $request $key]} {dict set receipt $key [dict get $request $key]}}
    set targetedAnalysisActive $receipt;_moduleAnalysisWriteReceipt $receipt
    startPreparedQueue $queue {Targeted analysis}
    set ::GX::targetedAnalysisTimer [after 250 ::GX::_moduleAnalysisGuard]
    return $receipt
}
proc ::GX::moduleAnalysisStatus {caller module run} {
    _moduleAnalysisCaller $caller 0
    set path [_moduleAnalysisReceiptPath $module $run]
    if {![file isfile $path]} {error {Analysis receipt is unavailable in this Session}}
    set result {};dict for {key value} [parseIni $path] {if {[string first targeted_analysis. $key]==0} {dict set result [string range $key 18 end] $value}}
    if {[dict get $result caller_id] ne $caller} {error {Analysis receipt belongs to another Viewer}}
    if {[dict get $result state] eq "RUNNING" && ($::GX::targetedAnalysisActive eq {} || [dict get $::GX::targetedAnalysisActive run_id] ne $run)} {dict set result state INTERRUPTED;dict set result reason {The admitting process is no longer running this invocation}}
    return $result
}
proc ::GX::moduleAnalysisCancel {caller module run} {
    set receipt [moduleAnalysisStatus $caller $module $run]
    if {[dict get $receipt state] ne "RUNNING"} {return $receipt}
    if {$::GX::targetedAnalysisActive eq {} || [dict get $::GX::targetedAnalysisActive run_id] ne $run} {error {Invocation is not owned by this running queue}}
    stopAnalysis 1
    return [moduleAnalysisStatus $caller $module $run]
}
