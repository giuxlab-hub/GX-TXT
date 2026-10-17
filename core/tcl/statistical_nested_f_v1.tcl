# SPDX-License-Identifier: GPL-3.0-or-later
# CORE proves supported nesting and owns meaning. Numeric computes the test.
proc ::GX::StatisticsV1::nestedFPlan {reduced full} {
    set plan [dict create api_id STATISTICAL_NESTED_F_PLAN_v1 api_version 1 status unavailable reason {} method complete_polynomial_spaces \
        reduced_id {} full_id {} n {} reduced_p {} full_p {} reduced_sse {} full_sse {} numerator_df {} denominator_df {} \
        source_id {} source_sha256 {} rows_sha256 {} response_sha256 {} weights_sha256 {} predictors_sha256 {} \
        x_variable_id {} y_variable_id {} x_unit {} y_unit {} orientation {} noise_model {} weight_semantics {}]
    set selections {};set predictors {}
    foreach entry [list $reduced $full] role {reduced full} {
        _keys $entry {id result binding} {nested F entry}
        foreach field {id result binding} {if {![dict exists $entry $field]} {_error "Nested F entry requires $field"}}
        if {![regexp {^[A-Za-z0-9_.-]{1,128}$} [dict get $entry id]]} {_error {Nested F entry requires a canonical result identifier}}
        dict set plan ${role}_id [dict get $entry id]
        set source [dict get $entry result];set selection [modelSelectionPlan $source [dict get $entry binding]]
        if {[dict get $selection status] ne "value"} {dict set plan status [dict get $selection status];dict set plan reason "$role: [dict get $selection reason]";return $plan}
        set context [dict get $source context];set model [dict get $source model id];set p [dict get $selection free_parameter_count]
        if {$model ni {math.numeric.polynomial math.numeric.linear}||[_get $context constraints unknown] ne "none"||[llength [dict get $source parameters]]!=$p||($model eq "math.numeric.linear"&&$p!=2)} {
            dict set plan reason {Exact nesting is supported for unconstrained complete polynomial spaces, including a line with intercept; arbitrary, nonlinear and fixed-parameter models need an explicit design-space proof. Use eligible AIC/BIC for non-nested comparisons};return $plan
        }
        if {[dict get $selection scale_model] ne "estimated"} {dict set plan reason {This F test requires a common Gaussian variance estimated from residuals; known absolute variance needs its own hypothesis test};return $plan}
        set signature [dict get $source provenance observation_signature]
        if {![dict exists $signature predictors_sha256]||[_get $signature predictor_count 0]!=1} {dict set plan reason {Exact ordered single-predictor evidence is missing; explicitly refit a legacy result before testing nesting};return $plan}
        lappend predictors [dict get $signature predictors_sha256]
        lappend selections $selection
        dict set plan ${role}_p $p;dict set plan ${role}_sse [dict get $selection weighted_sse]
    }
    if {[dict get $plan reduced_id] eq [dict get $plan full_id]} {_error {Select two distinct fitted result identities}}
    lassign $selections a b
    foreach key {source_id source_sha256 rows_sha256 n response_sha256 weights_sha256 x_variable_id y_variable_id x_unit y_unit orientation noise_model weight_semantics scale_model} {
        if {[dict get $a $key] ne [dict get $b $key]&&($key ne "n"||[dict get $a n]!=[dict get $b n])} {dict set plan reason "Matched fitted observations are required; $key differs";return $plan}
        if {$key ne "scale_model"} {dict set plan $key [dict get $a $key]}
    }
    if {[lindex $predictors 0] ne [lindex $predictors 1]} {dict set plan reason {Exact fitted predictor coordinates differ; match predictor translations and source rows before testing};return $plan}
    dict set plan predictors_sha256 [lindex $predictors 0]
    if {[dict get $plan reduced_p]>=[dict get $plan full_p]} {dict set plan reason {The reduced model must have strictly fewer polynomial coefficients than the full model};return $plan}
    dict set plan numerator_df [expr {[dict get $plan full_p]-[dict get $plan reduced_p]}]
    dict set plan denominator_df [expr {[dict get $plan n]-[dict get $plan full_p]}]
    dict set plan status value;return $plan
}
proc ::GX::StatisticsV1::_nestedFPlanSame {expected actual} {
    if {[lsort [dict keys $expected]] ne [lsort [dict keys $actual]]} {_error {Nested F Numeric plan fields differ from CORE}}
    dict for {field value} $expected {
        set other [dict get $actual $field]
        if {$field in {api_version n reduced_p full_p reduced_sse full_sse numerator_df denominator_df}&&$value ne {}} {
            if {![_finite $other]||$other!=$value} {_error "Nested F Numeric plan differs: $field"}
        } elseif {$other ne $value} {_error "Nested F Numeric plan differs: $field"}
    }
}
proc ::GX::StatisticsV1::nestedFInterpretation {reduced full {numeric {}}} {
    set plan [nestedFPlan $reduced $full];set status [dict get $plan status];set reason [dict get $plan reason]
    set quantities {};set request [dict create reduced $reduced full $full numeric $numeric]
    if {$status eq "value"} {
        if {$numeric eq {}} {set status unavailable;set reason {The public Numeric nested F calculation has not been supplied}} else {
            set fields {numeric_api operation plan status reason f_statistic p_value numerator_df denominator_df sse_reduction sse_roundoff_clamped}
            _keys $numeric $fields {nested F Numeric receipt}
            foreach field $fields {if {![dict exists $numeric $field]} {_error "Nested F receipt lacks $field"}}
            if {[dict get $numeric numeric_api] ne "NUMERIC_API_v1"||[dict get $numeric operation] ne "nested_f_test"} {_error {Nested F requires its public Numeric receipt}}
            _nestedFPlanSame $plan [dict get $numeric plan]
            foreach field {numerator_df denominator_df} {if {![_finite [dict get $numeric $field]]||[dict get $numeric $field]!=[dict get $plan $field]} {_error {Nested F degrees of freedom differ from CORE}}}
            if {![string is boolean -strict [dict get $numeric sse_roundoff_clamped]]} {_error {Invalid nested F roundoff flag}}
            set status [dict get $numeric status];set reason [dict get $numeric reason]
            if {$status ni {value undefined}} {_error {Unknown nested F Numeric availability}}
            if {$status eq "value"} {
                foreach field {f_statistic p_value sse_reduction} {if {![_finite [dict get $numeric $field]]||[dict get $numeric $field]<0} {_error "Invalid nested F fact: $field"}}
                if {[dict get $numeric p_value]>1} {_error {Nested F probability exceeds one}}
            } else {
                if {$reason eq {}} {_error {Unavailable nested F requires a reason}}
                foreach field {f_statistic p_value} {if {![string equal -nocase [dict get $numeric $field] NaN]} {_error {Undefined nested F cannot claim finite inference}}}
            }
        }
    } elseif {$numeric ne {}} {_error {An ineligible nested pair cannot carry a computed F test}}
    foreach {id label unit definition} {
        f_statistic {Nested-model F statistic} 1 {Weighted SSE reduction per additional coefficient divided by full-model weighted SSE per residual degree of freedom}
        p_value {Upper-tail F p-value} 1 {Probability under the specified reduced-model null of a statistic at least as large, conditional on the declared fixed designs and independent Gaussian errors}
        numerator_df {Additional polynomial coefficients} count {Full minus reduced fitted coefficient count}
        denominator_df {Full-model residual degrees of freedom} count {Matched observation count minus full fitted coefficient count}
    } {
        set item [dict create label $label unit $unit status $status reason $reason definition $definition]
        if {$status eq "value"} {dict set item value [dict get $numeric $id]}
        dict set quantities $id $item
    }
    return [dict create api_id STATISTICAL_RESULT_SEMANTICS_API_v1 api_version 1 schema gxtxt.nested_f_interpretation.v1 \
        status $status reason $reason plan $plan quantities $quantities request $request \
        assumptions {{The reduced complete polynomial space is contained in the full space; the null sets every additional higher-order coefficient to zero} {Inference conditions on the selected predictors, matched observations and positive fixed relative precisions, with independent Gaussian errors and one unknown common variance scale} {Models and degrees must be specified independently of these observations for the nominal p-value; searching many model pairs requires a separate selection or multiplicity policy} {A small p-value concerns the declared additional terms; it is not a probability that a model is true or proof of physical adequacy} {No model is automatically selected or accepted; non-nested candidates may use eligible information criteria instead}}]
}
proc ::GX::StatisticsV1::_nestedFReport {result} {
    validate $result
    set plan [dict get $result plan];set lines [list "Nested F: [dict get $plan reduced_id] (reduced) → [dict get $plan full_id] (full)"]
    dict for {id item} [dict get $result quantities] {
        set line "[dict get $item label]: [dict get $item status]"
        if {[dict get $item status] eq "value"} {set line "[dict get $item label]: [format %.10g [dict get $item value]] ([dict get $item unit])"} else {append line " — [dict get $item reason]"}
        lappend lines $line
    }
    if {[dict exists $result request numeric sse_roundoff_clamped]&&[dict get $result request numeric sse_roundoff_clamped]} {lappend lines {A negative SSE reduction within the recorded binary64 roundoff tolerance was clamped to zero}}
    return [join [concat $lines [dict get $result assumptions]] \n]
}
