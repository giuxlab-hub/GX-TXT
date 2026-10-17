# SPDX-License-Identifier: GPL-3.0-or-later
# Public likelihood meaning and constrained-search policy. Numeric owns refits.
proc ::GX::StatisticsV1::profileEligibility {modelId operation context} {
    set descriptor [model $modelId]
    set result [dict create api_id STATISTICAL_PROFILE_ELIGIBILITY_v1 api_version 1 status unavailable reason {Profile likelihood requires a declared scalar nonlinear least-squares response model with linear loss and independent errors}]
    if {$operation ne "nonlinear_fit"||[dict get $descriptor profile] ni {regression nonlinear_regression}||[_get $context sample_role training] ne "training"||[_get $context fit_geometry vertical_response] ne "vertical_response"||[_get $context loss linear] ne "linear"||[dict exists $context smoothing]} {return $result}
    dict set result status eligible
    dict set result reason {Model and residual geometry support a profile adapter; an actual captured converged fit, explicit Gaussian noise, exact observations and bounded settings must still pass profilePlan}
    return $result
}
proc ::GX::StatisticsV1::profileSettings {settings} {
    _keys $settings {parameter_id confidence search_lower search_upper initial_step parameter_tolerance max_refits max_seconds} profile_settings
    set settings [dict merge {confidence .95 max_refits 128 max_seconds 60} $settings]
    foreach key {parameter_id search_lower search_upper initial_step parameter_tolerance} {if {![dict exists $settings $key]} {_error "Profile settings require $key"}}
    _physicalText [dict get $settings parameter_id] parameter_id 128
    foreach key {confidence search_lower search_upper initial_step parameter_tolerance max_refits max_seconds} {if {![_finite [dict get $settings $key]]} {_error "Profile $key must be finite"}}
    if {[dict get $settings confidence]<=0||[dict get $settings confidence]>=1||[dict get $settings search_lower]>=[dict get $settings search_upper]||[dict get $settings initial_step]<=0||[dict get $settings parameter_tolerance]<=0||[dict get $settings max_seconds]<=0||[dict get $settings max_seconds]>3600} {_error {Invalid profile confidence, physical search interval, step, tolerance or time budget}}
    set count [dict get $settings max_refits]
    if {$count!=floor($count)||$count<4||$count>256} {_error {Profile max_refits must be an integer from 4 to 256}}
    dict set settings max_refits [expr {int($count)}];return $settings
}
proc ::GX::StatisticsV1::profilePlan {source settings} {
    validate $source;set settings [profileSettings $settings]
    if {[_get $source schema {}] ne "gxtxt.statistical_result.v1"} {_error {Profile likelihood requires one retained fitted statistical result}}
    set c [dict get $source context];set facts [dict get $source request numerical];set provenance [dict get $source provenance]
    set plan [dict merge [dict create api_id STATISTICAL_FIT_PROFILE_PLAN_v1 api_version 1 status unavailable reason {Profile likelihood requires a converged declared scalar Gaussian nonlinear least-squares fit} source_operation [_get $provenance operation {}] source_model_id [dict get $source model id] coefficient_space [_get $c coefficient_space original_physical] response_unit [dict get $source residual unit] weight_semantics [_get $c weight_semantics unweighted] noise_model [_get $c noise_model unspecified] objective none threshold_distribution chi_square_1 threshold_method two_erfinv_confidence_squared interval_policy connected_local_profile_component execution_policy sequential_one_thread_per_refit original_fit_count 0 n [_get $facts n 0] p [_get $facts p 0] free_parameter_count [_get $facts free_parameter_count 0] baseline_sse [_get $facts sse NaN] parameter_index 0 source_parameters {} parameter_ids {} parameter_units {} parameter_roles {} solver_policy {} observation_signature {} model_source_sha256 [_get $provenance model_source_sha256 {}] model_binding_sha256 [_get $provenance model_binding_sha256 {}] workspace_bytes_max 536870912 work_units_max 128000000] $settings]
    set eligibility [profileEligibility [dict get $source model id] [dict get $plan source_operation] $c]
    if {[dict get $eligibility status] ne "eligible"||![dict exists $source request solver_receipt]} {return $plan}
    set receipt [dict get $source request solver_receipt]
    if {[_get $receipt schema {}] ne "gxtxt.numeric_solver_receipt.v1"||[_get $receipt method {}] ne "ceres"||![_get $receipt converged 0]||[_get $facts response_count 1]!=1} {return $plan}
    set n [dict get $plan n];set p [dict get $plan p];set free [dict get $plan free_parameter_count]
    foreach value [list $n $p $free] {if {![_finite $value]||$value!=floor($value)} {_error {Invalid captured profile dimensions}}}
    if {$n<2||$p<1||$p>128||$free<1||$free>$p||$n>1000000||$n*$p*[dict get $plan max_refits]>128000000} {dict set plan reason {Profile dimensions or refit work exceed the bounded contract};return $plan}
    if {[dict get $plan weight_semantics] eq "inverse_variance"&&[dict get $plan noise_model] eq "independent_gaussian_known_sigma"} {
        dict set plan objective delta_weighted_sse
    } elseif {[dict get $plan weight_semantics] in {unweighted relative}&&[dict get $plan noise_model] eq "independent_gaussian_estimated_variance"} {
        dict set plan objective n_log_sse_ratio
    } else {dict set plan reason {Declare independent Gaussian errors with either known absolute precision or an unknown common variance scale};return $plan}
    set sse [dict get $plan baseline_sse]
    if {![_finite $sse]||$sse<0||($sse==0&&[dict get $plan objective] eq "n_log_sse_ratio")} {dict set plan reason {The retained Gaussian objective is invalid or its estimated variance is zero};return $plan}
    if {![dict exists $provenance observation_signature predictors_sha256]} {dict set plan reason {Exact original predictor, response and precision signatures are required};return $plan}
    dict set plan observation_signature [_fitObservationSignature [dict get $provenance observation_signature]]
    foreach key {model_source_sha256 model_binding_sha256} {if {![regexp {^[a-f0-9]{64}$} [dict get $plan $key]]} {dict set plan reason {The retained declared model lacks its source and binding hashes};return $plan}}
    foreach parameter [dict get $source parameters] {
        foreach {from to} {id parameter_ids unit parameter_units role parameter_roles value source_parameters} {dict lappend plan $to [dict get $parameter $from]}
    }
    if {[llength [dict get $plan parameter_ids]]!=$p} {_error {Profile parameter count changed}}
    set index [lsearch -exact [dict get $plan parameter_ids] [dict get $settings parameter_id]]
    if {$index<0} {_error {Choose a retained parameter identity}}
    dict set plan parameter_index [expr {$index+1}]
    if {[lindex [dict get $plan parameter_roles] $index] ne "free"} {dict set plan reason {A parameter declared fixed has no estimated profile interval};return $plan}
    set estimate [lindex [dict get $plan source_parameters] $index]
    foreach key {lower_bounds upper_bounds fixed_mask parameter_scales loss loss_scale strategy function_tolerance gradient_tolerance parameter_tolerance max_iterations} {dict set plan solver_policy $key [dict get $receipt $key]}
    set lower [lindex [dict get $receipt lower_bounds] $index];set upper [lindex [dict get $receipt upper_bounds] $index]
    if {[dict get $settings search_lower]>$estimate||[dict get $settings search_upper]<$estimate||[dict get $settings search_lower]<$lower||[dict get $settings search_upper]>$upper} {_error {Physical search limits must contain the fitted estimate and respect all original parameter bounds}}
    dict set plan status value;dict set plan reason {};return $plan
}
proc ::GX::StatisticsV1::profileInterpretation {source raw} {
    set fields {schema settings n p baseline_sse objective threshold threshold_distribution threshold_method interval_policy execution_policy original_fit_count attempted_count successful_count failed_count max_refits elapsed_seconds workspace_bytes_bound source_parameters parameter_ids observation_signature source_model_sha256 source_binding_sha256 lower upper baseline_improved ledger_sha256}
    _keys $raw $fields profile_numeric
    foreach key $fields {if {![dict exists $raw $key]} {_error "Profile receipt lacks $key"}}
    set plan [profilePlan $source [dict get $raw settings]]
    if {[dict get $plan status] ne "value"} {_error [dict get $plan reason]}
    if {[dict get $raw schema] ne "gxtxt.fit_profile_numeric.v1"||[dict get $raw original_fit_count]!=0} {_error {Invalid profile schema or repeated original fit}}
    foreach key {objective threshold_distribution threshold_method interval_policy execution_policy} {if {[dict get $raw $key] ne [dict get $plan $key]} {_error "Profile $key differs from its public plan"}}
    foreach key {n p baseline_sse max_refits} {_bootstrapCompare number [dict get $plan $key] [dict get $raw $key]}
    foreach key {source_parameters parameter_ids} {if {$key eq "source_parameters"} {_bootstrapCompare vector [dict get $plan $key] [dict get $raw $key]} elseif {[dict get $raw $key] ne [dict get $plan $key]} {_error {Profile parameter identities changed}}}
    _bootstrapCompare signature [dict get $plan observation_signature] [dict get $raw observation_signature]
    foreach {actual expected} {source_model_sha256 model_source_sha256 source_binding_sha256 model_binding_sha256} {if {[dict get $raw $actual] ne [dict get $plan $expected]} {_error {Profile model identity changed}}}
    foreach key {attempted_count successful_count failed_count} {set v [dict get $raw $key];if {![_finite $v]||$v<0||$v!=floor($v)||$v>[dict get $plan max_refits]} {_error {Invalid profile trial accounting}}}
    if {[dict get $raw attempted_count]!=[dict get $raw successful_count]+[dict get $raw failed_count]} {_error {Profile trials do not reconcile}}
    foreach key {threshold elapsed_seconds workspace_bytes_bound} {set v [dict get $raw $key];if {![_finite $v]||$v<0} {_error "Invalid profile $key"}}
    if {[dict get $raw threshold]<=0||[dict get $raw workspace_bytes_bound]>536870912||[dict get $raw baseline_improved] ni {0 1}||![regexp {^[a-f0-9]{64}$} [dict get $raw ledger_sha256]]} {_error {Invalid profile threshold, ledger or bounded execution facts}}
    set index [expr {[dict get $plan parameter_index]-1}];set estimate [lindex [dict get $plan source_parameters] $index];set available 1
    foreach side {lower upper} {
        set endpoint [dict get $raw $side];_keys $endpoint {status value searched_value likelihood_ratio bracket_inside bracket_outside message} profile_endpoint
        foreach key {status value searched_value likelihood_ratio bracket_inside bracket_outside message} {if {![dict exists $endpoint $key]} {_error "Profile endpoint lacks $key"}}
        set status [dict get $endpoint status];set value [dict get $endpoint value];set searched [dict get $endpoint searched_value];set ratio [dict get $endpoint likelihood_ratio]
        if {$status ni {threshold_crossing constraint_bound open_search_limit refit_budget time_budget solver_failure baseline_improved resolution_limit}} {_error {Unknown profile endpoint status}}
        _physicalText [dict get $endpoint message] profile_message 512
        if {![_finite $searched]||$searched<[dict get $plan search_lower]||$searched>[dict get $plan search_upper]||($side eq "lower"&&$searched>$estimate)||($side eq "upper"&&$searched<$estimate)} {_error {Profile endpoint changed physical search coordinates}}
        if {$status in {threshold_crossing constraint_bound}} {
            if {![_finite $value]||$value<[dict get $plan search_lower]||$value>[dict get $plan search_upper]||![_finite $ratio]||$ratio<0} {_error {Available profile endpoint requires its actual finite objective and coordinate}}
            if {$status eq "threshold_crossing"} {
                set inside [dict get $endpoint bracket_inside];set outside [dict get $endpoint bracket_outside]
                if {![_finite $inside]||![_finite $outside]||abs($outside-$inside)>[dict get $plan parameter_tolerance]||$value!=$inside+($outside-$inside)/2.0} {_error {Profile crossing must retain its refined physical bracket}}
            } else {
                set expected [lindex [dict get $plan solver_policy ${side}_bounds] $index]
                if {$value!=$expected||$ratio>=[dict get $raw threshold]} {_error {Constraint endpoint must be the original bound below the likelihood threshold}}
            }
        } elseif {$status eq "open_search_limit"} {
            if {![string equal -nocase $value [expr {$side eq "lower"?"-Inf":"Inf"}]]||$searched!=[dict get $plan search_$side]||![_finite $ratio]||$ratio<0||$ratio>=[dict get $raw threshold]} {_error {An open endpoint must retain the actual finite search limit and objective}}
        } else {set available 0;if {![string equal -nocase $value NaN]} {_error {Unresolved profile endpoints must not publish finite confidence limits}}}
    }
    if {[dict get $raw baseline_improved]} {set available 0}
    set status [expr {$available?"qualified":"unavailable"}]
    set assumptions {{Likelihood-ratio thresholds use the asymptotic chi-square law with one profiled parameter; finite-sample coverage is not established} {Active boundaries and weak or failed identifiability can violate that approximation; the retained objective and search evidence require scientific review} {Every constrained fit uses the recorded local Ceres solver and starts from the captured solution; disconnected regions or lower remote minima may be missed} {The interval describes the connected explored profile component around the retained estimate, conditional on its model and Gaussian noise declaration} {An open endpoint means no crossing was found within the explicit finite search limits; global unboundedness is not proved} {A declared constraint endpoint is a parameter-domain boundary, not a likelihood crossing} {Covariance-based Wald intervals remain a separately labelled local approximation and are not substituted for profile intervals}}
    set interval [dict create parameter_id [dict get $plan parameter_id] unit [lindex [dict get $plan parameter_units] $index] estimate $estimate confidence [dict get $plan confidence] lower [dict get $raw lower] upper [dict get $raw upper]]
    return [dict create schema gxtxt.fit_profile_interpretation.v1 api_id STATISTICAL_RESULT_SEMANTICS_API_v1 api_version 1 status $status plan $plan interval $interval assumptions $assumptions request [dict create source_request [dict get $source request] numeric $raw]]
}
proc ::GX::StatisticsV1::_profileValidate {result} {
    set r [dict get $result request];set expected [profileInterpretation [interpret [dict get $r source_request]] [dict get $r numeric]]
    _profileCompare $expected $result
    return [dict create valid 1 api_id STATISTICAL_RESULT_SEMANTICS_API_v1]
}
proc ::GX::StatisticsV1::_profileCompare {expected actual} {
    if {[lsort [dict keys $expected]] ne [lsort [dict keys $actual]]} {_error {Profile interpretation fields changed}}
    set numbers {api_version confidence search_lower search_upper initial_step parameter_tolerance max_refits max_seconds original_fit_count n p free_parameter_count baseline_sse parameter_index workspace_bytes_max work_units_max estimate value searched_value likelihood_ratio bracket_inside bracket_outside}
    dict for {key value} $expected {
        set other [dict get $actual $key]
        if {$key in $numbers} {_bootstrapCompare number $value $other} elseif {$key in {plan interval lower upper}} {_profileCompare $value $other} elseif {$key eq "source_parameters"} {_bootstrapCompare vector $value $other} elseif {$key eq "solver_policy"} {_bootstrapCompare solver_policy $value $other} elseif {$key eq "observation_signature"} {_bootstrapCompare signature $value $other} elseif {$value ne $other} {_error "Profile interpretation changed: $key"}
    }
}
proc ::GX::StatisticsV1::profileReport {meaning} {
    _profileValidate $meaning;set plan [dict get $meaning plan];set raw [dict get $meaning request numeric];set interval [dict get $meaning interval]
    set text "Profile likelihood: [dict get $meaning status]\nParameter: [dict get $interval parameter_id] ([dict get $interval unit]); estimate [dict get $interval estimate]\nParameter coordinates: [dict get $plan coefficient_space]\nSearch: [dict get $plan search_lower] to [dict get $plan search_upper]; absolute parameter tolerance [dict get $plan parameter_tolerance]\nGaussian objective: [dict get $plan objective]; retained SSE [dict get $plan baseline_sse]\nConfidence [dict get $plan confidence]; chi-square(1) threshold [dict get $raw threshold]\nRefits: [dict get $raw attempted_count]; successful [dict get $raw successful_count]; failed [dict get $raw failed_count]"
    foreach side {lower upper} {set e [dict get $interval $side];append text "\n$side: [dict get $e status]; endpoint [dict get $e value]; searched [dict get $e searched_value]; likelihood ratio [dict get $e likelihood_ratio]"}
    foreach assumption [dict get $meaning assumptions] {append text "\n$assumption"};return $text
}
proc ::GX::StatisticsV1::_profileDataFields {meaning} {
    set plan [dict get $meaning plan];set n [dict get $meaning request numeric attempted_count];set p [dict get $plan p]
    set unit [dict get $meaning interval unit];set sseUnit 1
    if {[dict get $plan objective] ne "delta_weighted_sse"} {set sseUnit "([dict get $plan response_unit])^2"}
    set fields [dict create trial_values [dict create label {Constrained profile trials} kind matrix value_kind real unit per_column shape [list $n 4] column_ids {parameter_value weighted_sse likelihood_ratio direction} column_units [list $unit $sseUnit 1 1] definition {Actual constrained parameter, captured weighted SSE, Gaussian likelihood ratio and search direction (-1 lower, +1 upper); incomplete numerical fields retain NaN} nonfinite_status unavailable nonfinite_reason {Constrained trial did not yield a valid likelihood ratio}]]
    dict set fields trial_parameters [dict create label {Constrained physical parameters} kind matrix value_kind real unit per_parameter shape [list $n $p] parameter_ids [dict get $plan parameter_ids] parameter_units [dict get $plan parameter_units] definition {Physical parameters for each actual constrained refit; failed trials retain NaN} nonfinite_status unavailable nonfinite_reason {Constrained trial failed}]
    dict set fields trial_status [dict create label {Constrained trial status} kind vector value_kind integer unit 1 shape [list $n 1] minimum 1 maximum 3 definition {1 converged trial; 2 solver failure; 3 improved baseline requiring original-fit review}]
    return $fields
}
