# SPDX-License-Identifier: GPL-3.0-or-later
# Public log-response meaning and eligibility; Numeric owns all calculations.
proc ::GX::StatisticsV1::_validateLogResponseContext {context} {
    set facts [dict get $context response_transform]
    _keys $facts {schema base reference source_dataset_id source_sha256 source_variable_id source_unit variable_id inverse_eligible inverse_reason} response_transform
    foreach key {schema base reference source_dataset_id source_sha256 source_variable_id source_unit variable_id inverse_eligible inverse_reason} {if {![dict exists $facts $key]} {_error "Log-response context requires $key"}}
    if {[dict get $facts schema] ne "gxtxt.log_response_context.v1"||[dict get $facts base] ne "natural"||![_finite [dict get $facts reference]]||[dict get $facts reference]<=0||![regexp {^[0-9a-f]{64}$} [dict get $facts source_sha256]]||![string is boolean -strict [dict get $facts inverse_eligible]]} {_error {Invalid captured logarithmic response transform}}
    foreach key {source_dataset_id source_variable_id variable_id} {if {[string trim [dict get $facts $key]] eq {}} {_error {Log response requires exact source and Variable identities}}}
    if {![dict get $facts inverse_eligible]&&[string trim [dict get $facts inverse_reason]] eq {}} {_error {Ineligible log retransformation requires its recorded reason}}
    set orientation [_get $context orientation y_of_x]
    if {$orientation ni {y_of_x x_of_y}} {_error {A logarithmic response requires one explicitly oriented scalar response}}
    set axis [expr {$orientation eq "x_of_y"?"x":"y"}]
    if {([dict get $facts inverse_eligible]&&[_get $context ${axis}_unit {}] ne "1")||[_get $context ${axis}_variable_id {}] ne [dict get $facts variable_id]} {_error {Log-response context differs from the current response Variable}}
}
proc ::GX::StatisticsV1::_logResponseAssumptions {} {
    return {{Fitting targets the natural logarithm of response divided by its recorded same-unit positive reference; residuals and fit scores describe that dimensionless transformed response} {The transformed objective assumes additive errors in log space; it is not an original-response least-squares exponential fit} {Exponentiating the fitted log response gives a conditional median only under the declared Gaussian log-error model; without that model it is a back-transformed fitted value} {The Gaussian log-variance correction gives a plug-in arithmetic mean estimate, not an unbiased finite-sample estimate; variance-estimation uncertainty is not included} {Exponentiated log-mean confidence limits concern the conditional physical median, not the arithmetic mean; exponentiated future-observation limits retain their pointwise prediction meaning}}
}
proc ::GX::StatisticsV1::_logResponseContextAssumptions {context} {
    if {[dict get $context response_transform inverse_eligible]} {return [_logResponseAssumptions]}
    return [list {Residuals and fit scores describe the current response coordinates after a recorded logarithmic transform and a subsequent numerical change} "Automatic physical retransformation is unavailable: [dict get $context response_transform inverse_reason]"]
}
proc ::GX::StatisticsV1::logResponsePlan {source} {
    validate $source
    if {[_get $source schema {}] ne "gxtxt.statistical_result.v1"||![dict exists $source context response_transform]} {_error {Log retransformation requires a captured fitted logarithmic response}}
    set context [dict get $source context];_validateLogResponseContext $context
    set transform [dict get $context response_transform]
    set gaussian [expr {[_get $context noise_model unspecified] in {independent_gaussian_estimated_variance independent_gaussian_known_sigma}}]
    set plan [dict create api_id STATISTICAL_LOG_RESPONSE_PLAN_v1 api_version 1 status value reason {} transform $transform reference [dict get $transform reference] response_unit [dict get $transform source_unit] center_role [expr {$gaussian?"conditional_median":"back_transformed_fit"}] mean_status unavailable mean_reason {An arithmetic mean correction requires independent equal-variance Gaussian log errors and a captured residual scale} log_standard_deviation {} assumptions [_logResponseContextAssumptions $context]]
    if {![dict get $transform inverse_eligible]} {dict set plan status unavailable;dict set plan reason [dict get $transform inverse_reason];return $plan}
    if {[dict get $source model profile] ni {regression nonlinear_regression smoother interpolation}||[_get $context fit_geometry vertical_response] ne "vertical_response"} {dict set plan status unavailable;dict set plan reason {Retransformation requires a functional scalar log-response fit};return $plan}
    if {[_get $context noise_model unspecified] eq "independent_gaussian_estimated_variance"&&[_get $context weight_semantics unweighted] eq "unweighted"&&[_get $context sample_role training] eq "training"} {
        set scale [dict get $source quantities residual_standard_deviation]
        if {[dict get $scale status] eq "value"} {dict set plan mean_status value;dict set plan mean_reason {};dict set plan log_standard_deviation [dict get $scale value]}
    }
    return $plan
}
proc ::GX::StatisticsV1::logResponseInterpretation {source raw {prediction {}}} {
    set plan [logResponsePlan $source]
    if {[dict get $plan status] ne "value"} {_error [dict get $plan reason]}
    # Accept only bounded Numeric facts; callers retain vectors in typed resources.
    set fields {schema n reference base mean_available log_standard_deviation log_bias_correction interval_kind confidence interval_available_count method}
    _keys $raw $fields log_response_numeric
    foreach field $fields {if {![dict exists $raw $field]} {_error "Log retransformation receipt lacks $field"}}
    if {[dict get $raw schema] ne "gxtxt.log_response_retransform.v1"||[dict get $raw base] ne "natural"||[dict get $raw reference]!=[dict get $plan reference]||[dict get $raw method] ne "monotone_exponential_of_dimensionless_log_response"} {_error {Numeric log retransformation differs from its captured transform}}
    foreach field {n interval_available_count} {set n [dict get $raw $field];if {![_finite $n]||$n<0||$n>1000000||$n!=floor($n)} {_error {Log retransformation row counts must be bounded nonnegative integers}}}
    set n [dict get $raw n];set available [dict get $raw interval_available_count]
    if {$available>$n||![string is boolean -strict [dict get $raw mean_available]]} {_error {Invalid log retransformation availability facts}}
    if {[dict get $raw mean_available]} {
        if {[dict get $plan mean_status] ne "value"||[dict get $raw log_standard_deviation]!=[dict get $plan log_standard_deviation]||![_finite [dict get $raw log_bias_correction]]||[dict get $raw log_bias_correction]<0} {_error {Mean retransformation requires the captured eligible Gaussian log scale}}
    } elseif {[dict get $raw log_standard_deviation] ne {}||[dict get $raw log_bias_correction] ne {}} {_error {Unavailable mean must not claim a variance correction}}
    set kind [dict get $raw interval_kind];set intervalStatus unavailable;set intervalLabel {No captured intervals};set predictionRequest {}
    if {$kind eq "none"} {
        if {$prediction ne {}||$available!=0||[dict get $raw confidence] ne {}} {_error {Absent log intervals cannot claim prediction inference facts}}
    } else {
        validate $prediction
        if {[_get $prediction schema {}] ne "gxtxt.statistical_result.v1"||[dict get $prediction model id] ne "math.numeric.prediction_uncertainty"} {_error {Log bounds require their public captured prediction interpretation}}
        if {[dict get $prediction provenance prediction_source_request] ne [dict remove [dict get $source request] parameter_uncertainty]} {_error {Log bounds belong to a different fitted source}}
        set original [dict get $prediction provenance prediction_plan kind]
        set expected [expr {$original eq "mean_confidence"?"log_mean_confidence":"log_new_observation"}]
        if {$kind ne $expected||[dict get $raw confidence]!=[dict get $prediction context confidence]||$n!=[dict get $prediction quantities prediction_query_count value]||$available!=[dict get $prediction quantities prediction_available_count value]} {_error {Retransformed bounds differ from the captured log intervals}}
        set intervalLabel [expr {$kind eq "log_mean_confidence"?"Pointwise conditional-median confidence limits":"Pointwise future-observation prediction limits"}]
        set intervalStatus value;set predictionRequest [dict get $prediction request]
    }
    set centerLabel [expr {[dict get $plan center_role] eq "conditional_median"?"Conditional median":"Back-transformed fitted value"}]
    set unit [dict get $plan response_unit];if {$unit eq {}} {set unit unspecified}
    set columns [dict create median [dict create label $centerLabel role [dict get $plan center_role] unit $unit status value reason {} definition {Reference times the exponential of the fitted dimensionless log response}]]
    dict set columns mean [dict create label {Arithmetic mean estimate (Gaussian log-variance plug-in)} role arithmetic_mean_plugin unit $unit status [expr {[dict get $raw mean_available]?"value":"unavailable"}] reason [expr {[dict get $raw mean_available]?"":"No eligible Gaussian variance correction was applied"}] definition {Reference times exp(fitted log response plus captured log variance divided by two); variance uncertainty is excluded}]
    foreach field {lower upper} {dict set columns $field [dict create label "$intervalLabel: $field" role $kind unit $unit status $intervalStatus reason [expr {$kind eq "none"?"No captured log-space intervals":""}] definition {Monotone exponential transformation of the original captured bound; paired unavailable rows remain gaps}]}
    return [dict create api_id STATISTICAL_RESULT_SEMANTICS_API_v1 api_version 1 schema gxtxt.log_response_interpretation.v1 request [dict create source_request [dict remove [dict get $source request] parameter_uncertainty] numeric $raw prediction_request $predictionRequest] plan $plan row_count $n interval_available_count $available confidence [dict get $raw confidence] columns $columns assumptions [_logResponseAssumptions]]
}
proc ::GX::StatisticsV1::_logResponseReinterpret {request} {
    _keys $request {source_request numeric prediction_request} log_response_request
    set prediction {};if {[dict get $request prediction_request] ne {}} {set prediction [interpret [dict get $request prediction_request]]}
    return [logResponseInterpretation [interpret [dict get $request source_request]] [dict get $request numeric] $prediction]
}
proc ::GX::StatisticsV1::_logResponseReport {result} {
    validate $result;set lines [list "Log-response retransformation: [dict get $result row_count] rows"]
    dict for {field column} [dict get $result columns] {
        lappend lines "[dict get $column label] ([dict get $column unit]): [dict get $column status][expr {[dict get $column reason] eq {}?{}:" — [dict get $column reason]"}]"
    }
    lappend lines "Finite interval rows: [dict get $result interval_available_count]"
    return [join [concat $lines [dict get $result assumptions]] \n]
}
