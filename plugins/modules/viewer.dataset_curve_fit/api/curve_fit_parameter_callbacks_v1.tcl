# Manual registered-callable evaluation through existing supervised Job ownership.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_parameterRegisteredDefinitionNode {definition} {
    set definition [_registeredDefinition $definition];set fields {};set ids {}
    foreach id [dict get $definition parameter_ids] {lappend ids [::GX::ScientificTransportv1::text $id]}
    dict set fields parameter_ids [dict create kind cell items $ids]
    set count [llength $ids]
    foreach field {lower_bounds upper_bounds} {dict set fields $field [::GX::ScientificTransportv1::array [list $count 1] [dict get $definition $field]]}
    dict set fields fixed_mask [::GX::ScientificTransportv1::array [list $count 1] [::GX::datasetPublicationV2DictDefault $definition fixed_mask [lrepeat $count 0]]]
    return [::GX::ScientificTransportv1::struct $fields]
}
proc ::GX::DatasetCurveFit::_parameterRegisteredCollect {} {
    # Abruptly stopped Script clients cannot run their Tcl finally blocks.
    # Recover only explicitly temporary owners whose parent and child Jobs are
    # both terminal; never infer that a live GUI has consumed its result.
    foreach item [::GX::interactiveDocumentList viewer.dataset_curve_fit dataset_curve_fit.parameters] {
        if {[dict get $item format] ne "gxtxt.fitter_parameter_job.v1"} continue
        set document [dict get $item id];set payload [dict get [::GX::interactiveDocumentRead $document] payload]
        if {![dict exists $payload parent_job_id]||[dict get $payload parent_job_id] eq {}||![dict exists $payload job_id]||[dict get $payload purpose] ne "ephemeral_manual_evaluation"} continue
        if {[catch {::GX::scriptJobDescribe [dict get $payload parent_job_id]} parent]||[dict get $parent state] ni {COMPLETED FAILED CANCELLED INTERRUPTED}} continue
        if {[catch {::GX::scriptJobDescribe [dict get $payload job_id]} child]||[dict get $child state] ni {COMPLETED FAILED CANCELLED INTERRUPTED}} continue
        if {![dict exists $child parent_job_id]||[dict get $child parent_job_id] ne [dict get $payload parent_job_id]} continue
        _parameterRegisteredCleanup $document [dict get $payload nonce] [::GX::interactiveDocumentSessionToken] [dict get $payload job_id]
    }
}
proc ::GX::DatasetCurveFit::_parameterRegisteredCleanup {document nonce token job} {
    if {[catch {::GX::interactiveDocumentSessionToken} current]||$current ne $token} {return}
    if {$job ne {}} {
        if {[catch {::GX::scriptJobDescribe $job} result]} {return}
        if {[dict get $result state] ni {COMPLETED FAILED CANCELLED INTERRUPTED}} {
            after 500 [list ::GX::DatasetCurveFit::_parameterRegisteredCleanup $document $nonce $token $job];return
        }
    }
    if {![::GX::interactiveDocumentExists $document]} return
    set item [::GX::interactiveDocumentRead $document]
    if {[dict get $item module_id] ne "viewer.dataset_curve_fit"||[dict get $item format] ne "gxtxt.fitter_parameter_job.v1"||[dict get $item payload nonce] ne $nonce} {error {Refusing to delete a different parameter Job owner}}
    ::GX::interactiveDocumentDelete $document
}
proc ::GX::DatasetCurveFit::_parameterRegisteredEvaluate {key parameters} {
    variable state
    set fingerprint $state($key,parameterFingerprint)
    set contextFile [file join $state($key,parameterDirectory) context.ini]
    set context [dict get [::GX::ScientificTransportv1::readResult $contextFile] values context]
    foreach value $parameters initial [dict get $context initial] lower [dict get $context lower] upper [dict get $context upper] fixed [dict get $context fixed] {
        if {$value<$lower||$value>$upper||($fixed&&$value!=$initial)} {error {Manual parameters violate registered bounds or fixed values}}
    }
    set options [_uiFitOptions $key];dict unset options bootstrap;dict set options prediction_band none;dict set options influence_diagnostics 0
    set domain source;if {$state($key,domain) eq "range"} {set domain [list $state($key,min) $state($key,max) $state($key,samples)]}
    set recipe [_registeredUiRecipe $key $domain [dict get $context initial] $options]
    set registered [dict get [_recipeDecode $recipe] fit options registered_model]
    set token [::GX::interactiveDocumentSessionToken];set nonce "manual-[pid]-[clock clicks]"
    set parent {};if {[info exists ::env(GXTXT_JOB_ID)]} {set parent $::env(GXTXT_JOB_ID)}
    set ownership [dict create nonce $nonce purpose ephemeral_manual_evaluation parent_job_id $parent]
    set document [dict get [::GX::interactiveDocumentCreate viewer.dataset_curve_fit dataset_curve_fit.parameters gxtxt.fitter_parameter_job.v1 1 $ownership] id]
    set job {};set writer {};set channel {}
    try {
        set writer [::GX::interactiveDocumentResourceOpenWriter $document [dict create format gxtxt.fitter_parameter_context.v1 purpose ephemeral_manual_evaluation]]
        set channel [::open $contextFile rb]
        while {![eof $channel]} {::GX::interactiveDocumentResourceAppend $writer [read $channel 65536]}
        ::close $channel;set channel {};set resource [::GX::interactiveDocumentResourceFinalize $writer];set writer {}
        set payload [::GX::scientificRecipeEncode [dict create format gxtxt.registered_parameter_job.v1 recipe $recipe context $resource parameters $parameters document_id $document nonce $nonce]]
        set invocation [dict create callable_id [dict get $registered callable_id] source_sha256 [dict get $registered source_sha256] revision [dict get $registered revision] declaration_sha256 [dict get $registered declaration_sha256] consumer_api DATASET_CURVE_FIT_API_v1 consumer_operation registered_parameter_run payload_json [format {"%s"} $payload]]
        set submitted [::GX::scriptJobSubmit [dict get $registered reference] {} [dict create callable_invocation $invocation]];set job [dict get $submitted id]
        dict set ownership job_id $job;::GX::interactiveDocumentUpdate $document $ownership
        set state($key,parameterJob) $job
        set info [::GX::scriptJobWait $job 60 [list ::GX::DatasetCurveFit::_parameterRegisteredCancelRequested $key $token]]
        if {[::GX::interactiveDocumentSessionToken] ne $token} {error {Session changed during registered parameter evaluation}}
        if {[dict get $info wait_cancel_requested]||[dict get $info state] ne "COMPLETED"} {error "Registered parameter Job $job: [dict get $info state]; inspect its log"}
        set inspected [::GX::scriptJobInspect $job]
        if {[dict get $inspected callable_validation] ne "verified"} {error {Registered parameter Job receipt is not verified}}
        set result [dict get $inspected callable_result result]
        if {[dict get $result schema] ne "gxtxt.fitter_parameter_resource.v1"||[dict get $result nonce] ne $nonce||[dict get $result document_id] ne $document} {error {Registered parameter result belongs to another request}}
        set reference [dict get $result points]
        if {[dict get $reference document_id] ne $document} {error {Registered manual points belong to another Document}}
        set page [::GX::managedResourceNumericPage $reference 0 1024]
        if {[dict get $page dtype] ne "float64"||[dict get $page columns] ne {x y}||[dict get $page total_rows]!=[dict get $state($key,parameterView) display_count]} {error {Registered manual output shape differs from its prepared display}}
        binary scan [dict get $page bytes] q* flat;set points {};foreach {x y} $flat {lappend points [list [_finite $x {Manual X}] [_finite $y {Manual Y}]]}
        if {$fingerprint ne [_parameterFingerprint $key]} {error {Source or settings changed during registered evaluation}}
        return [dict create schema gxtxt.fitter_parameter_curve.v1 parameters $parameters points $points display_count [llength $points] nonlinear_optimization 0 accepted 0 job_id $job]
    } finally {
        if {$channel ne {}} {::close $channel};if {$writer ne {}} {::GX::interactiveDocumentResourceAbort $writer}
        unset -nocomplain state($key,parameterJob)
        _parameterRegisteredCleanup $document $nonce $token $job
    }
}
proc ::GX::DatasetCurveFit::_parameterRegisteredCancelRequested {key token} {
    variable state
    if {[catch {::GX::interactiveDocumentSessionToken} current]||$current ne $token} {return 1}
    return [expr {[info exists state($key,sourceCancelled)]&&$state($key,sourceCancelled)}]
}
proc ::GX::DatasetCurveFit::_parameterRegisteredPrepareJob {encoded identity} {
    set payload [::GX::scientificRecipeDataDecode $encoded gxtxt.registered_parameter_job.v1]
    if {[dict get $identity consumer_api] ne "DATASET_CURVE_FIT_API_v1"||[dict get $identity consumer_operation] ne "registered_parameter_run"} {error {This callable Job is not a registered parameter request}}
    recipeValidate [dict get $payload recipe];set recipe [_recipeDecode [dict get $payload recipe]]
    set registered [_registeredFitValidate [dict get $recipe source] [dict get $recipe fit]]
    foreach field {reference callable_id source_sha256 declaration_sha256 revision entrypoint language} {
        if {[dict get $registered $field] ne [dict get $identity $field]} {error "Registered parameter callable identity changed: $field"}
    }
    set document [dict get $payload document_id];set item [::GX::interactiveDocumentRead $document]
    if {[dict get $item module_id] ne "viewer.dataset_curve_fit"||[dict get $item format] ne "gxtxt.fitter_parameter_job.v1"||[dict get $item payload nonce] ne [dict get $payload nonce]} {error {Registered parameter owner changed}}
    set resource [dict get $payload context]
    if {[dict get $resource document_id] ne $document||[dict get $resource metadata format] ne "gxtxt.fitter_parameter_context.v1"||[dict get $resource size_bytes]>1048576} {error {Invalid bounded parameter context owner}}
    set channel [file tempfile temporary]
    try {
        fconfigure $channel -translation binary -encoding binary;puts -nonewline $channel [::GX::interactiveDocumentResourceReadChunk $resource 0 [dict get $resource size_bytes]]
        ::close $channel;set channel {}
        set context [dict get [::GX::ScientificTransportv1::readResult $temporary] values context]
    } finally {if {$channel ne {}} {::close $channel};file delete -- $temporary}
    set count [llength [dict get $context query]]
    if {[dict get $context declaration_kind] ne "registered"||$count<2||$count>1024||[dict get $context orientation] ni {y_of_x x_of_y}} {error {Invalid registered manual context shape or orientation}}
    if {[dict get $context model parameter_ids] ne [dict get $registered definition parameter_ids]||[llength [dict get $context initial]]!=[llength [dict get $recipe fit initial]]} {error {Registered context parameter identity changed}}
    foreach actual [dict get $context initial] expected [dict get $recipe fit initial] {if {$actual!=$expected} {error {Registered context initial values changed}}}
    return [dict create document_id $document nonce [dict get $payload nonce] registered $registered context $context parameters [dict get $payload parameters]]
}
