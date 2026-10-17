# SPDX-License-Identifier: GPL-3.0-or-later
# Likelihood eligibility and comparison meaning. All scores belong to Numeric.
proc ::GX::StatisticsV1::_fitObservationSignature {signature} {
    _keys $signature {schema n encoding response_sha256 weights_sha256 log_weight_sum response_offset fit_response_sha256 predictor_count predictors_sha256} {fit observation signature}
    foreach field {schema n encoding response_sha256 weights_sha256 log_weight_sum} {
        if {![dict exists $signature $field]} {_error "Fit observation signature requires $field"}
    }
    if {[dict get $signature schema] ne "gxtxt.fit_observations.v1"||[dict get $signature encoding] ne "float64_le_ordered"} {_error {Unknown fit observation encoding}}
    foreach field {response_sha256 weights_sha256} {if {![regexp {^[0-9a-f]{64}$} [dict get $signature $field]]} {_error {Malformed fit observation digest}}}
    set n [dict get $signature n]
    if {![_finite $n]||$n<1||$n!=floor($n)||![_finite [dict get $signature log_weight_sum]]} {_error {Invalid fit observation count or normalization}}
    if {[dict exists $signature response_offset]||[dict exists $signature fit_response_sha256]} {
        if {![dict exists $signature response_offset]||![dict exists $signature fit_response_sha256]||![_finite [dict get $signature response_offset]]||![regexp {^[0-9a-f]{64}$} [dict get $signature fit_response_sha256]]} {_error {Incomplete physical-to-fit observation binding}}
    }
    if {[dict exists $signature predictor_count]||[dict exists $signature predictors_sha256]} {
        if {![dict exists $signature predictor_count]||![dict exists $signature predictors_sha256]||![_finite [dict get $signature predictor_count]]||[dict get $signature predictor_count]<1||[dict get $signature predictor_count]!=floor([dict get $signature predictor_count])||![regexp {^[0-9a-f]{64}$} [dict get $signature predictors_sha256]]} {_error {Incomplete fitted predictor binding}}
    }
    return $signature
}
proc ::GX::StatisticsV1::_observationBinding {binding} {
    _keys $binding {schema source_id source_sha256 rows_sha256} {observation binding}
    foreach field {schema source_id source_sha256 rows_sha256} {if {![dict exists $binding $field]} {_error "Observation binding requires $field"}}
    if {[dict get $binding schema] ne "gxtxt.observation_binding.v1"||[string trim [dict get $binding source_id]] eq {}||[string length [dict get $binding source_id]]>1024} {_error {Invalid observation binding identity}}
    foreach field {source_sha256 rows_sha256} {if {![regexp {^[0-9a-f]{64}$} [dict get $binding $field]]} {_error {Observation binding requires exact source and ordered-row SHA-256}}}
    return $binding
}
proc ::GX::StatisticsV1::modelSelectionPlan {result binding} {
    validate $result;_observationBinding $binding
    if {[_get $result schema {}] ne "gxtxt.statistical_result.v1"} {_error {Model selection requires an individual fitted statistical result}}
    set context [dict get $result context];set raw [dict get $result request numerical]
    set plan [dict create api_id STATISTICAL_MODEL_SELECTION_PLAN_v1 api_version 1 status unavailable reason {} observation_status unavailable \
        source_model_id [dict get $result model id] source_id [dict get $binding source_id] source_sha256 [dict get $binding source_sha256] rows_sha256 [dict get $binding rows_sha256] \
        n {} free_parameter_count {} weighted_sse {} log_weight_sum {} response_sha256 {} weights_sha256 {} \
        x_variable_id [_get $context x_variable_id {}] y_variable_id [_get $context y_variable_id {}] \
        x_unit [_get $context x_unit {}] y_unit [_get $context y_unit {}] orientation [_get $context orientation y_of_x] \
        noise_model [_get $context noise_model unspecified] weight_semantics [_get $context weight_semantics unweighted] \
        scale_model {} approximation unavailable]
    if {[dict exists $context rational domain_receipt possible_common_factor]&&[dict get $context rational domain_receipt possible_common_factor]} {dict set plan reason {Possible rational numerator/denominator cancellation requires identifiability review before regular likelihood comparison};return $plan}
    if {[dict exists $context implicit]} {dict set plan reason {Equation-error normalization and conditioning need their own declared likelihood; ordinary functional-response information scores do not apply};return $plan}
    if {[dict exists $context gls]} {dict set plan reason {Full observation covariance needs its own determinant and constrained-support likelihood; diagonal information scores do not apply};return $plan}
    if {[_get $context sample_role training] ne "training"} {dict set plan reason {Information criteria require the actual fitted training observations};return $plan}
    if {[_get $context fit_geometry vertical_response] ne "vertical_response"||[dict get $plan orientation] ni {y_of_x x_of_y}} {dict set plan reason {This likelihood requires one vertical physical response; geometric, radial, XY-error and joint-response fits need their own likelihood};return $plan}
    if {![dict exists $result provenance observation_signature]} {dict set plan reason {The fit lacks a captured ordered observation signature; legacy results remain unverified};return $plan}
    set signature [_fitObservationSignature [dict get $result provenance observation_signature]]
    if {![dict exists $raw n]||[dict get $raw n]!=[dict get $signature n]} {_error {Fit observation signature count differs from the interpreted training count}}
    set offset 0
    if {[dict exists $context translation]} {
        if {![dict exists $context translation v delta]||![_finite [dict get $context translation v delta]]} {_error {Comparison requires the captured additive response translation}}
        set offset [dict get $context translation v delta]
    }
    if {[dict exists $result provenance physical_observation_signature]} {
        set physical [_fitObservationSignature [dict get $result provenance physical_observation_signature]]
        if {![dict exists $physical response_offset]||[dict get $physical response_offset]!=$offset||[dict get $physical fit_response_sha256] ne [dict get $signature response_sha256]||[dict get $physical n]!=[dict get $signature n]||[dict get $physical weights_sha256] ne [dict get $signature weights_sha256]||[dict get $physical log_weight_sum]!=[dict get $signature log_weight_sum]} {_error {Physical observation receipt differs from the actual fitted response or weights}}
        set signature $physical
    } elseif {$offset!=0} {dict set plan reason {Translated fitting requires a Numeric physical-to-fit observation signature};return $plan}
    foreach field {n response_sha256 weights_sha256 log_weight_sum} {dict set plan $field [dict get $signature $field]}
    if {[dict get $plan x_variable_id] eq {}||[dict get $plan y_variable_id] eq {}} {dict set plan reason {Canonical predictor and response identities are required};return $plan}
    dict set plan observation_status value
    if {[dict get $result model profile] ni {regression nonlinear_regression}} {dict set plan reason {The model has no registered ordinary Gaussian regression likelihood};return $plan}
    if {[_get $context loss linear] ne "linear"} {dict set plan reason {Robust objectives are not Gaussian maximum likelihood scores};return $plan}
    if {[_get $context constraints unknown] ni {none inactive_bounds fixed_parameters}} {dict set plan reason {Active or undeclared constraints do not support these regular likelihood criteria};return $plan}
    if {[dict exists $raw converged]&&![dict get $raw converged]} {dict set plan reason {The numerical fit did not converge};return $plan}
    if {[dict get $result model profile] eq "nonlinear_regression"&&![dict exists $raw converged]} {dict set plan reason {Nonlinear likelihood requires captured solver convergence};return $plan}
    set p 0;foreach parameter [dict get $result parameters] {if {[dict get $parameter role] eq "free"} {incr p}}
    if {![dict exists $raw rank]||[dict get $raw rank]!=$p||$p>=[dict get $plan n]} {dict set plan reason {Likelihood criteria require identified free parameters and more observations than parameters};return $plan}
    if {![dict exists $raw sse]||![_finite [dict get $raw sse]]||[dict get $raw sse]<0} {dict set plan reason {The fit lacks a finite nonnegative Numeric weighted SSE};return $plan}
    dict set plan free_parameter_count $p;dict set plan weighted_sse [dict get $raw sse]
    set noise [dict get $plan noise_model];set weights [dict get $plan weight_semantics]
    if {$noise eq "independent_gaussian_known_sigma"&&$weights eq "inverse_variance"} {
        dict set plan scale_model known
    } elseif {$noise eq "independent_gaussian_estimated_variance"&&$weights in {unweighted relative}} {
        dict set plan scale_model estimated
        if {[dict get $plan weighted_sse]==0} {dict set plan status undefined;dict set plan reason {A perfect fit has zero estimated Gaussian scale and no finite maximized log likelihood};return $plan}
    } else {dict set plan reason {Declare an independent Gaussian noise model consistent with the actual fit weights};return $plan}
    if {[dict exists $context smoothing]} {dict set plan reason {Smoothing-induced correlations and effective complexity are not included in this likelihood};return $plan}
    if {[dict exists $context baseline_correction]} {dict set plan reason {Estimated baseline uncertainty, induced correlations and effective complexity are not included in this likelihood};return $plan}
    dict set plan approximation [expr {[dict get $result model profile] eq "regression" ? "linear_gaussian" : "nonlinear_local_asymptotic"}]
    if {[dict exists $context regional_fit]&&[dict get $result quantities covariance status] ne "value"} {
        dict set plan reason "Regional information criteria require an identified, supported and locally regular joint fit: [dict get $result quantities covariance reason]"
        return $plan
    }
    dict set plan status value;dict set plan reason {}
    return $plan
}
proc ::GX::StatisticsV1::_sameModelSelectionPlan {expected actual} {
    if {[lsort [dict keys $expected]] ne [lsort [dict keys $actual]]} {_error {Model selection receipt plan fields changed}}
    dict for {key value} $expected {
        set other [dict get $actual $key]
        if {$key in {api_version n free_parameter_count weighted_sse log_weight_sum}&&$value ne {}} {
            if {![_finite $other]||$value!=$other} {_error "Model selection receipt plan changed: $key ($value -> $other)"}
        } elseif {$value ne $other} {_error "Model selection receipt plan changed: $key"}
    }
}
proc ::GX::StatisticsV1::modelComparison {entries {criterion aicc}} {
    if {$criterion ni {rmse aic aicc bic}} {_error {Comparison criterion must be rmse, aic, aicc or bic}}
    if {[llength $entries]<1||[llength $entries]>64} {_error {Interpret one to 64 explicit fitted candidates; ranking alternatives requires at least two}}
    set rationalComparison 0;set predictorReference {}
    foreach entry $entries {if {[_get [dict get $entry result] model {}] ne {}&&[_get [dict get $entry result model] id {}] eq "math.numeric.rational"} {set rationalComparison 1}}
    set rows {};set issues {};set ids {};set reference {};set order {};set index 0
    foreach entry $entries {
        _keys $entry {id result binding numeric} {comparison entry}
        foreach key {id result binding} {if {![dict exists $entry $key]} {_error "Comparison entry requires $key"}}
        set id [dict get $entry id]
        if {![regexp {^[A-Za-z0-9_.-]{1,128}$} $id]||$id in $ids} {_error {Comparison model IDs must be unique canonical identifiers}}
        lappend ids $id;set result [dict get $entry result];set plan [modelSelectionPlan $result [dict get $entry binding]]
        set row [dict create id $id model_id [dict get $result model id] plan $plan status unavailable reason {} value {} n [dict get $plan n] free_parameter_count [dict get $plan free_parameter_count]]
        dict set row unit [expr {$criterion eq "rmse" ? [dict get $result quantities rmse unit] : "1"}]
        set comparable [dict get $plan observation_status]
        if {$comparable ne "value"} {dict set row reason [dict get $plan reason]} else {
            set keys {source_id source_sha256 rows_sha256 n response_sha256 weights_sha256 x_variable_id y_variable_id x_unit y_unit orientation weight_semantics}
            if {$criterion ne "rmse"} {lappend keys noise_model scale_model}
            set identity {};foreach key $keys {set value [dict get $plan $key];if {$key eq "n"} {set value [expr {wide($value)}]};lappend identity $value}
            if {$reference eq {}} {set reference $identity} elseif {$reference ne $identity} {dict set row reason {Observation rows, response frame, weights or likelihood definition differ};set comparable unavailable}
        }
        if {$comparable eq "value"&&$rationalComparison} {
            set signature [_get [dict get $result provenance] observation_signature {}]
            if {(![_finite [_get $signature predictor_count {}]]||[dict get $signature predictor_count]!=1)||[_get $signature predictors_sha256 {}] eq {}} {
                dict set row reason {Rational comparison requires captured exact single-predictor values for every candidate};set comparable unavailable
            } else {
                set identity [dict get $signature predictors_sha256]
                if {$predictorReference eq {}} {set predictorReference $identity} elseif {$identity ne $predictorReference} {dict set row reason {Rational comparison requires identical captured predictor values and coordinate frame};set comparable unavailable}
            }
        }
        if {$comparable eq "value"} {
            if {$criterion eq "rmse"} {
                set metric [dict get $result quantities rmse];dict set row status [dict get $metric status];dict set row reason [dict get $metric reason];dict set row value [_get $metric value {}]
            } elseif {[dict get $plan status] ne "value"} {dict set row status [dict get $plan status];dict set row reason [dict get $plan reason]} elseif {![dict exists $entry numeric]} {dict set row reason {Numeric information criteria have not been computed}} else {
                set numeric [dict get $entry numeric]
                _keys $numeric {numeric_api operation plan n free_parameter_count likelihood_parameter_count log_likelihood aic aicc bic aicc_computed variance_mle} {Numeric information criteria}
                if {[_get $numeric numeric_api {}] ne "NUMERIC_API_v1"||[_get $numeric operation {}] ne "fit_information_criteria"||![dict exists $numeric plan]} {_error {Comparison requires the public Numeric information-criteria receipt}}
                _sameModelSelectionPlan $plan [dict get $numeric plan]
                foreach key {n free_parameter_count likelihood_parameter_count log_likelihood aic bic} {if {![dict exists $numeric $key]||![_finite [dict get $numeric $key]]} {_error "Invalid Numeric information criterion: $key"}}
                set k [expr {[dict get $plan free_parameter_count]+([dict get $plan scale_model] eq "estimated")}]
                if {[dict get $numeric n]!=[dict get $plan n]||[dict get $numeric free_parameter_count]!=[dict get $plan free_parameter_count]||[dict get $numeric likelihood_parameter_count]!=$k} {_error {Numeric likelihood parameter counting differs from CORE policy}}
                set corrected [expr {[dict get $plan scale_model] eq "estimated"&&[dict get $plan n]>$k+1}]
                if {![dict exists $numeric aicc_computed]||![string is boolean -strict [dict get $numeric aicc_computed]]||!![dict get $numeric aicc_computed]!=$corrected||![dict exists $numeric aicc]||($corrected&&![_finite [dict get $numeric aicc]])||(!$corrected&&![string equal -nocase [dict get $numeric aicc] NaN])} {_error {Numeric AICc availability differs from CORE policy}}
                if {![dict exists $numeric variance_mle]||([dict get $plan scale_model] eq "known"&&![string equal -nocase [dict get $numeric variance_mle] NaN])||([dict get $plan scale_model] eq "estimated"&&(![_finite [dict get $numeric variance_mle]]||[dict get $numeric variance_mle]<0))} {_error {Invalid captured Gaussian ML scale}}
                if {$criterion eq "aicc"&&([dict get $plan scale_model] ne "estimated"||[dict get $plan n]<=$k+1)} {
                    dict set row reason {This AICc correction requires estimated Gaussian scale and N greater than K+1}
                } else {
                    if {![dict exists $numeric $criterion]||![_finite [dict get $numeric $criterion]]} {_error {Requested Numeric criterion is not finite}}
                    dict set row status value;dict set row value [dict get $numeric $criterion]
                }
                dict set row numeric $numeric
            }
        }
        if {[dict get $row status] ne "value"} {lappend issues "$id: [dict get $row reason]"} else {lappend order [list [dict get $row value] $index $id]}
        lappend rows $row;incr index
    }
    set ranked {};if {![llength $issues]} {foreach item [lsort -real -index 0 $order] {lappend ranked [lindex $item 2]}}
    return [dict create api_id STATISTICAL_RESULT_SEMANTICS_API_v1 api_version 1 schema gxtxt.model_comparison.v1 \
        criterion $criterion status [expr {[llength $issues]?"unavailable":"value"}] reasons $issues rows $rows ranked_ids $ranked \
        request [dict create entries $entries criterion $criterion] \
        assumptions {{Lower criteria rank only the supplied comparable candidate models; no model is automatically accepted} {AIC and BIC require the declared Gaussian likelihood and identified fitted parameters; estimated scale counts as one parameter} {AICc uses the Gaussian estimated-scale correction; nonlinear use is a local asymptotic approximation} {RMSE is descriptive and does not penalize model complexity}}]
}
proc ::GX::StatisticsV1::_modelComparisonReport {result} {
    validate $result
    set lines [list "Model criterion: [string toupper [dict get $result criterion]]"]
    foreach row [dict get $result rows] {
        set description "[dict get $row id]: [dict get $row status]"
        if {[dict get $row status] eq "value"} {append description " [format %.10g [dict get $row value]] ([dict get $row unit]); N=[dict get $row n], free p=[dict get $row free_parameter_count]"} else {append description " — [dict get $row reason]"}
        lappend lines $description
    }
    if {[dict get $result status] eq "value"} {lappend lines "Order: [join [dict get $result ranked_ids] {, }]"} else {lappend lines {No comparable ranking}}
    return [join [concat $lines [dict get $result assumptions]] \n]
}
