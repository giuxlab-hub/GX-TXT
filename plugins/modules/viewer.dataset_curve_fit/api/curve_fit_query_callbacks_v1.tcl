# Supervised retained callable queries; Numeric owns all model mathematics.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_queryRegisteredCleanup {document nonce token job} {
    if {[catch {::GX::interactiveDocumentSessionToken} current]||$current ne $token} return
    if {$job ne {}} {
        if {[catch {::GX::scriptJobDescribe $job} info]} return
        if {[dict get $info state] ni {COMPLETED FAILED CANCELLED INTERRUPTED}} {
            after 500 [list ::GX::DatasetCurveFit::_queryRegisteredCleanup $document $nonce $token $job];return
        }
    }
    if {![::GX::interactiveDocumentExists $document]} return
    set item [::GX::interactiveDocumentRead $document]
    if {[dict get $item module_id] ne "viewer.dataset_curve_fit"||[dict get $item format] ne "gxtxt.fitter_query_job.v1"||[dict get $item payload nonce] ne $nonce||[dict get $item payload purpose] ne "ephemeral_retained_query"} {error {Refusing to remove a different retained query owner}}
    ::GX::interactiveDocumentDelete $document
}
proc ::GX::DatasetCurveFit::_queryRegisteredCollect {} {
    foreach item [::GX::interactiveDocumentList viewer.dataset_curve_fit dataset_curve_fit.queries] {
        if {[dict get $item format] ne "gxtxt.fitter_query_job.v1"} continue
        set document [dict get $item id];set p [dict get [::GX::interactiveDocumentRead $document] payload]
        if {[dict get $p purpose] ne "ephemeral_retained_query"||![dict exists $p job_id]||![dict exists $p parent_job_id]||[dict get $p parent_job_id] eq {}} continue
        if {[catch {::GX::scriptJobDescribe [dict get $p parent_job_id]} parent]||[dict get $parent state] ni {COMPLETED FAILED CANCELLED INTERRUPTED}} continue
        if {[catch {::GX::scriptJobDescribe [dict get $p job_id]} child]||[dict get $child state] ni {COMPLETED FAILED CANCELLED INTERRUPTED}} continue
        if {![dict exists $child parent_job_id]||[dict get $child parent_job_id] ne [dict get $p parent_job_id]} continue
        _queryRegisteredCleanup $document [dict get $p nonce] [::GX::interactiveDocumentSessionToken] [dict get $p job_id]
    }
}
proc ::GX::DatasetCurveFit::_queryRegisteredExecute {reference action values bracket context host} {
    variable state
    _queryRegisteredCollect
    set p [dict get [_recipeResultRecord $reference] provenance]
    _validateRegisteredModelState $p
    set registered [_registeredModelValidate [dict get $p options registered_model]]
    set options {}
    dict for {key node} [dict get $context node fields] {
        switch -- [dict get $node kind] {
            text {dict set options $key [dict get $node value]}
            array {dict set options $key [dict get $node real]}
            default {error {Unsupported registered query coordinate frame}}
        }
    }
    set token [::GX::interactiveDocumentSessionToken];set nonce "query-[pid]-[clock clicks]"
    set parent {};if {[info exists ::env(GXTXT_JOB_ID)]} {set parent $::env(GXTXT_JOB_ID)}
    set ownership [dict create nonce $nonce purpose ephemeral_retained_query parent_job_id $parent]
    set document [dict get [::GX::interactiveDocumentCreate viewer.dataset_curve_fit dataset_curve_fit.queries gxtxt.fitter_query_job.v1 1 $ownership] id]
    set job {}
    try {
        set payload [::GX::scientificRecipeEncode [dict create format gxtxt.registered_query_job.v1 reference $reference action $action values $values bracket $bracket options $options document_id $document nonce $nonce]]
        dict set ownership request_sha256 [::GX::datasetStorageSha256Text $::GX::currentSession $payload]
        ::GX::interactiveDocumentUpdate $document $ownership
        set invocation [dict create callable_id [dict get $registered callable_id] source_sha256 [dict get $registered source_sha256] revision [dict get $registered revision] declaration_sha256 [dict get $registered declaration_sha256] consumer_api DATASET_CURVE_FIT_API_v1 consumer_operation registered_query_run payload_json [format {"%s"} $payload]]
        set submitted [::GX::scriptJobSubmit [dict get $registered reference] {} [dict create callable_invocation $invocation]];set job [dict get $submitted id]
        dict set ownership job_id $job;::GX::interactiveDocumentUpdate $document $ownership
        if {$host ne {}} {set state($host,queryJob) $job}
        set info [::GX::scriptJobWait $job 120 [list ::GX::DatasetCurveFit::_parameterRegisteredCancelRequested $host $token]]
        if {[::GX::interactiveDocumentSessionToken] ne $token} {error {Session changed during retained query}}
        if {[dict get $info wait_cancel_requested]||[dict get $info state] ne "COMPLETED"} {error "Retained query Job $job: [dict get $info state]; inspect its log"}
        set inspected [::GX::scriptJobInspect $job]
        if {[dict get $inspected callable_validation] ne "verified"} {error {Retained query callable receipt is not verified}}
        set result [dict get $inspected callable_result result]
        if {[dict get $result schema] ne "gxtxt.fitter_query_resource.v1"||[dict get $result document_id] ne $document||[dict get $result nonce] ne $nonce||[dict get $result action] ne $action} {error {Retained query response belongs to another request}}
        set resource [dict get $result resource]
        if {[dict get $resource document_id] ne $document} {error {Retained query resource has a different owner}}
        set page [::GX::managedResourceNumericPage $resource 0 [llength $values]]
        set columns {targets roots valid residual is_extrapolated iterations function_evaluations}
        if {$action eq "query"} {set columns {query x y predicted is_extrapolated derivative derivative_valid inverse_derivative inverse_derivative_valid tangent_x tangent_y model_response_derivative interpreted_derivative interpreted_inverse_derivative interpreted_derivative_valid interpreted_inverse_derivative_valid difference_step}}
        if {[dict get $page dtype] ne "float64"||[dict get $page columns] ne $columns||[dict get $page total_rows]!=[llength $values]||[dict get $page row_count]!=[llength $values]} {error {Retained query resource shape or identity differs from its request}}
        binary scan [dict get $page bytes] q* flat
        set output [dict get $result metadata]
        foreach field $columns {dict set output $field {}}
        set width [llength $columns]
        for {set i 0} {$i<[llength $flat]} {incr i $width} {
            foreach field $columns value [lrange $flat $i [expr {$i+$width-1}]] {dict lappend output $field $value}
        }
        if {$action eq "query"} {
            set points {};foreach x [dict get $output x] y [dict get $output y] {lappend points [list $x $y]}
            dict unset output x;dict unset output y;dict set output points $points
        }
        dict set output job_id $job
        return $output
    } finally {
        if {$host ne {}} {unset -nocomplain state($host,queryJob)}
        _queryRegisteredCleanup $document $nonce $token $job
    }
}
proc ::GX::DatasetCurveFit::_queryRegisteredPrepareJob {encoded identity} {
    set request [::GX::scientificRecipeDataDecode $encoded gxtxt.registered_query_job.v1]
    if {[dict get $identity consumer_api] ne "DATASET_CURVE_FIT_API_v1"||[dict get $identity consumer_operation] ne "registered_query_run"} {error {Callable invocation is not a retained query}}
    set p [dict get [_recipeResultRecord [dict get $request reference]] provenance]
    _validateRegisteredModelState $p
    set registered [_registeredModelValidate [dict get $p options registered_model]]
    foreach field {reference callable_id source_sha256 declaration_sha256 revision entrypoint language} {
        if {[dict get $registered $field] ne [dict get $identity $field]} {error "Retained query callable identity changed: $field"}
    }
    set document [dict get $request document_id];set item [::GX::interactiveDocumentRead $document]
    if {[dict get $item module_id] ne "viewer.dataset_curve_fit"||[dict get $item format] ne "gxtxt.fitter_query_job.v1"||[dict get $item payload purpose] ne "ephemeral_retained_query"||[dict get $item payload nonce] ne [dict get $request nonce]||[dict get $item payload request_sha256] ne [::GX::datasetStorageSha256Text $::GX::currentSession $encoded]} {error {Retained query owner or request changed}}
    set action [dict get $request action]
    if {$action ni {query inverse}} {error {Unknown retained callback action}}
    _queryNumbers [dict get $request values] [expr {$action eq "query"?4096:64}] {Exact query values}
    if {$action eq "inverse"&&[llength [dict get $request bracket]]!=2} {error {Inverse branch requires two endpoints}}
    dict set request model [dict get $p registered_model_state]
    return $request
}
