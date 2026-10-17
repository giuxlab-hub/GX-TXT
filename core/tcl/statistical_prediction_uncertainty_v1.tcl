# Pointwise response inference plans; numerical propagation remains in Numeric.
# SPDX-License-Identifier: GPL-3.0-or-later
apply {{} {
    variable quantities
    foreach {id label unit definition} {
        prediction_query_count {Prediction query rows} count {Actual number of requested response predictions; not a training observation count}
        prediction_available_count {Finite interval rows} count {Query rows with two finite representable bounds and finite selected response standard error}
        prediction_unavailable_count {Unavailable interval rows} count {Query rows whose requested interval is not representable as two finite bounds}
        prediction_critical_value {Pointwise interval critical value} dimensionless {Normal or Student-t critical value from the eligible CORE plan and its confidence level}
        prediction_critical_reused {Existing critical value reused} dimensionless {One when Numeric reused the same captured parameter-interval critical value without computing it again}
        prediction_covariance_roundoff_count {Covariance roundoff corrections} count {Number of tiny negative correlation eigenvalues clipped to zero within the recorded numerical roundoff threshold; larger violations reject}
    } {dict set quantities $id [dict create label $label unit $unit kind scalar policy prediction_uncertainty definition $definition]}
} ::GX::StatisticsV1}
proc ::GX::StatisticsV1::_predictionFields {} {
    return {query_count prediction_query_count available_count prediction_available_count unavailable_count prediction_unavailable_count critical_value prediction_critical_value critical_value_reused prediction_critical_reused covariance_roundoff_eigenvalues_clipped prediction_covariance_roundoff_count}
}
proc ::GX::StatisticsV1::_polynomialPropagationBasis {basis count {requireFiniteCovariance 1}} {
    if {[lsort [dict keys $basis]] ne [lsort {api_id api_version kind source_parameters source_covariance query_center query_scale}]||[dict get $basis api_id] ne "STATISTICAL_POLYNOMIAL_PROPAGATION_BASIS_v1"||[dict get $basis api_version]!=1||[dict get $basis kind] ne "centered_scaled_descending_power"} {_error {Invalid captured polynomial propagation basis}}
    if {$count<1||$count>128||[llength [dict get $basis source_parameters]]!=$count||[llength [dict get $basis source_covariance]]!=$count} {_error {Polynomial propagation basis shape differs from the fitted model}}
    foreach value [concat [dict get $basis source_parameters] [list [dict get $basis query_center] [dict get $basis query_scale]]] {if {![_finite $value]} {_error {Polynomial propagation coordinates must be finite}}}
    if {[dict get $basis query_scale]<=0} {_error {Polynomial propagation scale must be positive}}
    foreach row [dict get $basis source_covariance] {
        if {[llength $row]!=$count} {_error {Polynomial propagation covariance must be square}}
        if {$requireFiniteCovariance} {foreach value $row {if {![_finite $value]} {_error {Polynomial propagation covariance must be finite}}}}
    }
    return $basis
}
proc ::GX::StatisticsV1::predictionInferencePlan {result {kind mean_confidence} {confidence 0.95}} {
    validate $result
    if {[dict get $result schema] ne "gxtxt.statistical_result.v1"} {_error {Prediction inference requires one captured fitted model}}
    if {$kind ni {mean_confidence new_observation}} {_error {Prediction inference kind must be mean_confidence or new_observation}}
    set parameterPlan [_parameterInferencePlan $result $confidence]
    set context [dict get $result context]
    set plan [dict create api_id STATISTICAL_PREDICTION_INFERENCE_PLAN_v1 api_version 1 \
        kind $kind status [dict get $parameterPlan interval_status] reason [dict get $parameterPlan interval_reason] \
        parameter_plan $parameterPlan all_parameter_ids {} all_parameter_values {} free_parameter_indices {} \
        response_unit [dict get $result residual unit] orientation [_get $context orientation y_of_x] \
        source_operation [_get [dict get $result provenance] operation {}] \
        model_source_sha256 [_get [dict get $result provenance] model_source_sha256 {}] \
        model_binding_sha256 [_get [dict get $result provenance] model_binding_sha256 {}] \
        observation_noise_policy none observation_scale {} critical_value {} \
        coverage pointwise assumption {Each interval is for one specified query; it is not a simultaneous confidence region}]
    if {[dict get $plan response_unit] eq {}} {dict set plan response_unit unspecified}
    if {[_get $context fit_geometry vertical_response] eq "orthogonal_xy"} {
        dict set plan fit_geometry orthogonal_xy
        dict set plan response_unit [_get $context [expr {[dict get $plan orientation] eq "x_of_y"?"x_unit":"y_unit"}] unspecified]
        dict set plan assumption {Each interval is conditional on one fixed true query coordinate; uncertainty in a future measured query coordinate is not included, and coverage is pointwise}
    }
    if {[dict get $plan status] ne "value"} {return $plan}
    if {[dict get $result model profile] ni {regression nonlinear_regression}||[dict get $plan orientation] ni {y_of_x x_of_y r_of_theta}} {
        dict set plan status not_applicable
        dict set plan reason {Scalar response bands require an identified functional regression; projected geometry and joint response components need their explicit response covariance model}
        return $plan
    }
    if {[dict get $plan source_operation] ni {linear_regression polynomial_fit nonlinear_fit dataset_polynomial_fit dataset_nonlinear_fit}} {
        dict set plan status unavailable;dict set plan reason {Prediction bands require a recorded evaluable fit model; an arbitrary design matrix does not identify its query basis}
        return $plan
    }
    if {[dict get $result model id] ni {math.numeric.linear math.numeric.linear_origin math.numeric.polynomial math.numeric.exponential math.numeric.power_law math.numeric.gaussian}&&([dict get $plan model_source_sha256] eq {}||[dict get $plan model_binding_sha256] eq {})} {
        dict set plan status unavailable;dict set plan reason {Declared-model prediction needs the fitted source and parameter-binding digests}
        return $plan
    }
    set index 0
    foreach parameter [dict get $result parameters] {
        incr index
        if {![dict exists $parameter value]} {_error {Prediction inference requires every fitted and fixed parameter value}}
        dict lappend plan all_parameter_ids [dict get $parameter id]
        dict lappend plan all_parameter_values [dict get $parameter value]
        if {[dict get $parameter role] eq "free"} {dict lappend plan free_parameter_indices $index}
    }
    if {[llength [dict get $plan all_parameter_ids]]>128} {
        dict set plan status unavailable;dict set plan reason {The compiled prediction backend supports at most 128 parameters}
        return $plan
    }
    if {[dict exists $result provenance polynomial_propagation_basis]} {
        if {[dict get $result model id] ne "math.numeric.polynomial"||[dict get $plan source_operation] ni {polynomial_fit dataset_polynomial_fit}||[llength [dict get $plan free_parameter_indices]]!=[llength [dict get $plan all_parameter_ids]]} {_error {Captured polynomial propagation coordinates require the matching unrestricted polynomial fit}}
        dict set plan propagation_basis [_polynomialPropagationBasis [dict get $result provenance polynomial_propagation_basis] [llength [dict get $plan all_parameter_ids]]]
    } elseif {[dict get $result model id] eq "math.numeric.polynomial"&&[_get $context fit_geometry vertical_response] ne "orthogonal_xy"} {
        dict set plan status unavailable;dict set plan reason {Polynomial response propagation requires the captured scaled coefficients and covariance from the original fit}
        return $plan
    }
    if {[dict exists $result parameter_uncertainty intervals]} {
        set intervals [dict get $result parameter_uncertainty intervals]
        if {[dict get $intervals status] eq "value"&&[dict get $intervals confidence]==$confidence} {dict set plan critical_value [dict get $intervals critical_value]}
    }
    if {$kind eq "new_observation"} {
        set weight [_get $context weight_semantics unweighted]
        if {[dict get $parameterPlan distribution] eq "normal"} {
            dict set plan observation_noise_policy explicit_absolute_sigma
        } else {
            set quantity [expr {$weight eq "relative"?"weighted_residual_standard_deviation":"residual_standard_deviation"}]
            set scale [dict get $result quantities $quantity]
            if {[dict get $scale status] ne "value"||![dict exists $scale value]||[dict get $scale value]<=0} {
                dict set plan status unavailable
                dict set plan reason {Prediction intervals require the captured positive residual scale consistent with the fitted weight model}
                return $plan
            }
            dict set plan observation_scale [dict get $scale value]
            dict set plan observation_noise_policy [expr {$weight eq "relative"?"explicit_relative_precision":"homoscedastic_training_scale"}]
        }
        dict set plan assumption {Each interval concerns one independent future observation under the declared response model and its specified noise; it is not simultaneous coverage}
        if {[_get $context fit_geometry vertical_response] eq "orthogonal_xy"} {
            dict set plan assumption {Each interval concerns one independent future response at a fixed true query coordinate, with its explicit absolute response sigma; future query-coordinate measurement uncertainty and simultaneous coverage are not included}
        }
    }
    return $plan
}
proc ::GX::StatisticsV1::_samePredictionPlan {expected actual} {
    if {[lsort [dict keys $expected]] ne [lsort [dict keys $actual]]} {_error {Prediction receipt has an incompatible plan}}
    dict for {key value} $expected {
        set other [dict get $actual $key]
        if {$key in {parameter_plan propagation_basis}} {_sameInferencePlan $value $other;continue}
        if {$key in {api_version all_parameter_values free_parameter_indices observation_scale critical_value}} {
            if {[llength $value]!=[llength $other]} {_error {Prediction plan numerical shape changed}}
            foreach a $value b $other {
                if {![_finite $a]||![_finite $b]||abs($a-$b)>4*2.2204460492503131e-16*max(abs($a),abs($b))} {_error "Prediction plan changed $key"}
            }
        } elseif {$key eq "all_parameter_ids"} {
            if {[llength $value]!=[llength $other]} {_error {Prediction parameter identities changed}}
            foreach a $value b $other {if {$a ne $b} {_error {Prediction parameter identities changed}}}
        } elseif {$value ne $other} {_error "Prediction plan changed $key"}
    }
}
proc ::GX::StatisticsV1::_predictionMethod {evaluation} {
    switch $evaluation {
        native_model {return native_jacobian_covariance_propagation}
        registered_callback {return registered_callback_bounded_finite_difference_covariance_propagation}
        default {_error {Unsupported prediction model evaluation kind}}
    }
}
proc ::GX::StatisticsV1::_predictionAssumptions {plan {evaluation native_model}} {
    set inference [dict get $plan parameter_plan]
    set assumptions [list [dict get $plan assumption] \
        "Distribution: [dict get $inference distribution]; approximation: [dict get $inference approximation]; future noise: [dict get $plan observation_noise_policy]." \
        {Covariance propagation uses the fitted parameter coordinates and the existing native model Jacobian; no refit is performed} \
        {A fitted-model interval is conditional on the recorded measurement model, covariance eligibility and model identity; extrapolation does not establish physical model validity} \
        {Unavailable bounds are retained as unavailable; no substitute finite confidence claim is made}]
    if {$evaluation eq "registered_callback"} {lset assumptions 2 {Covariance propagation uses the fitted parameter coordinates and the Numeric bounded central finite-difference Jacobian of the live registered callback; no refit is performed}}
    if {[dict exists $plan propagation_basis]} {lappend assumptions {Polynomial response propagation uses the captured coefficients and covariance in z=(query-center)/scale; the reported physical coefficient identities and covariance remain unchanged}}
    return $assumptions
}
proc ::GX::StatisticsV1::predictionInterpretation {source raw} {
    validate $source
    if {[_get $raw numeric_api {}] ne "NUMERIC_API_v1"||[_get $raw operation {}] ne "prediction_uncertainty"} {_error {Prediction interpretation requires the actual public Numeric receipt}}
    set plan [_get $raw plan {}]
    set expected [predictionInferencePlan $source [_get $plan kind {}] [_get [_get $plan parameter_plan {}] confidence {}]]
    _samePredictionPlan $expected $plan
    if {[dict get $expected status] ne "value"} {_error {Numeric supplied intervals for an ineligible prediction plan}}
    set numerical {};dict for {field quantity} [_predictionFields] {
        if {![dict exists $raw $field]} {_error "Prediction receipt lacks $field"}
        dict set numerical $quantity [dict get $raw $field]
    }
    foreach key {model_source_sha256 model_binding_sha256} {
        if {![regexp {^[0-9a-f]{64}$} [_get $raw $key {}]]} {_error {Prediction result has no exact compiled model identity}}
        if {[dict get $plan $key] ne {}&&[dict get $plan $key] ne [dict get $raw $key]} {_error {Prediction result model identity differs from the fit}}
    }
    set evaluation [_get $raw model_evaluation_kind native_model]
    set context [dict create y_unit [dict get $plan response_unit] method [_predictionMethod $evaluation] \
        confidence [dict get $plan parameter_plan confidence] inference [dict get $plan kind] \
        approximation [dict get $plan parameter_plan approximation] assumptions [_predictionAssumptions $plan $evaluation]]
    # Retain the bounded fitting request once, without its independently captured
    # parameter-interval arrays. Its original covariance and model facts remain.
    set provenance [dict create producer math.numeric numeric_api NUMERIC_API_v1 operation prediction_uncertainty \
        prediction_source_request [dict remove [dict get $source request] parameter_uncertainty] \
        prediction_plan $plan model_source_sha256 [dict get $raw model_source_sha256] model_binding_sha256 [dict get $raw model_binding_sha256]]
    if {$evaluation ne "native_model"} {dict set provenance model_evaluation_kind $evaluation}
    return [interpret [dict create model_id math.numeric.prediction_uncertainty context $context numerical $numerical provenance $provenance]]
}
proc ::GX::StatisticsV1::_validatePrediction {request} {
    set numerical [dict get $request numerical];set context [dict get $request context];set provenance [dict get $request provenance]
    set plan [_get $provenance prediction_plan {}]
    set sourceRequest [_get $provenance prediction_source_request {}]
    if {[_get $sourceRequest model_id {}] eq "math.numeric.prediction_uncertainty"} {_error {A prediction summary cannot become its own fitted source}}
    set source [interpret $sourceRequest]
    set expected [predictionInferencePlan $source [_get $plan kind {}] [_get [_get $plan parameter_plan {}] confidence {}]]
    # The stored source need not repeat an earlier parameter-interval receipt.
    # Critical values are Numeric facts; all distribution/eligibility facts are
    # regenerated from the original fitted request, without estimating a quantile.
    set capturedCritical [_get $plan critical_value {}]
    if {$capturedCritical ne {}&&(![_finite $capturedCritical]||$capturedCritical<=0)} {_error {Invalid reused prediction critical value}}
    dict set expected critical_value $capturedCritical
    _samePredictionPlan $expected $plan
    set evaluation [_get $provenance model_evaluation_kind native_model]
    if {[dict get $plan status] ne "value"||[_get $context assumptions {}] ne [_predictionAssumptions $plan $evaluation]||[_get $context method {}] ne [_predictionMethod $evaluation]||[_get $context inference {}] ne [dict get $plan kind]||[_get $context y_unit {}] ne [dict get $plan response_unit]||[_get $context confidence {}]!=[dict get $plan parameter_plan confidence]||[_get $context approximation {}] ne [dict get $plan parameter_plan approximation]} {_error {Prediction interpretation differs from its captured eligible plan}}
    foreach key {prediction_query_count prediction_available_count prediction_unavailable_count prediction_covariance_roundoff_count} {set v [_get $numerical $key {}];if {![_finite $v]||$v<0||$v!=floor($v)} {_error {Prediction counts must be nonnegative integers}}}
    set n [dict get $numerical prediction_query_count]
    if {$n<1||[dict get $numerical prediction_available_count]+[dict get $numerical prediction_unavailable_count]!=$n||[dict get $numerical prediction_covariance_roundoff_count]>[llength [dict get $plan free_parameter_indices]]} {_error {Prediction availability or covariance counts are inconsistent}}
    set critical [_get $numerical prediction_critical_value {}];set reused [_get $numerical prediction_critical_reused {}]
    if {![_finite $critical]||$critical<=0||![_finite $reused]||($reused!=0&&$reused!=1)||$reused!=($capturedCritical ne {})} {_error {Invalid actual prediction critical-value facts}}
    if {$reused&&abs($critical-$capturedCritical)>4*2.2204460492503131e-16*max(abs($critical),abs($capturedCritical))} {_error {Reused prediction critical value changed}}
    foreach key {model_source_sha256 model_binding_sha256} {
        if {![regexp {^[0-9a-f]{64}$} [_get $provenance $key {}]]||([dict get $plan $key] ne {}&&[dict get $plan $key] ne [dict get $provenance $key])} {_error {Compiled prediction identity changed}}
    }
}
proc ::GX::StatisticsV1::_predictionDataFields {result} {
    set n [expr {int([dict get $result quantities prediction_query_count value])}]
    set plan [dict get $result provenance prediction_plan];set unit [dict get $plan response_unit]
    set description [expr {[dict get $plan kind] eq "mean_confidence"?"pointwise mean confidence":"pointwise future-observation prediction"}]
    set confidence [format %.6g [dict get $plan parameter_plan confidence]];set fields {}
    foreach {field label definition} {
        predicted {Predicted response} {Response from the exact recorded model and fitted parameters at each query row}
        mean_standard_error {Mean response standard error} {First-order propagation of the captured parameter covariance through the native model Jacobian}
        observation_standard_deviation {Future observation noise scale} {Actual declared or training-estimated future noise scale; zero for a mean-confidence interval}
        standard_error {Selected response standard error} {Quadrature combination of mean-response and included future-observation scales}
        lower {Lower interval bound} {Lower bound of the recorded pointwise interval, conditional on the shared plan}
        upper {Upper interval bound} {Upper bound of the same recorded pointwise interval}
    } {
        if {$field eq "mean_standard_error"&&[_get [dict get $result provenance] model_evaluation_kind native_model] eq "registered_callback"} {set definition {First-order propagation of the captured parameter covariance through the registered callback's bounded central finite-difference Jacobian}}
        set contract [dict create kind vector value_kind real unit $unit shape [list $n 1] label $label definition $definition nonfinite_status undefined nonfinite_reason {The numerical result is not finitely representable}]
        if {$field in {mean_standard_error observation_standard_deviation standard_error}} {dict set contract minimum 0}
        if {$field in {lower upper}} {
            dict set contract label "$label ($description, confidence $confidence)"
            dict set contract availability_field bounds_available
            dict set contract unavailable_reason {The requested two-sided interval has no pair of finite representable bounds}
        }
        dict set fields $field $contract
    }
    dict set fields bounds_available [dict create kind vector value_kind integer unit 1 shape [list $n 1] minimum 0 maximum 1 label {Finite interval available} definition {One means both bounds and the selected response standard error are finite}]
    dict set fields query_index [dict create kind vector value_kind integer unit 1 shape [list $n 1] minimum 1 maximum $n label {Original query row} definition {One-based position in the supplied prediction coordinates; not a training observation identity}]
    return $fields
}
