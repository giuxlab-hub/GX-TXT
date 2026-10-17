# SPDX-License-Identifier: GPL-3.0-or-later
# CORE owns eligibility and meaning; Numeric owns every influence calculation.
proc ::GX::StatisticsV1::_influenceAssumptions {} {
    return {{Exact deletion formulas apply to a full-rank unconstrained model linear in its fitted coefficients, using the same fixed design and positive fitting weights} {Leverage measures design geometry; Cook's distance measures the change in all fitted responses after deleting one training observation} {Cook's distance and internally studentized residuals use the captured estimated weighted residual mean square, including when measurement precisions are absolute} {A deletion that loses rank or lies within the recorded near-one leverage tolerance is unavailable; a zero or unavailable residual scale does not produce a zero Cook's distance} {Leverage above 2p/n and Cook's distance above 4/n are heuristic review flags, not hypothesis tests, proof of an outlier or permission to discard scientific data} {Leave-one-out residuals retain the observed-minus-predicted convention in the fitted response coordinate system, including any explicitly recorded logarithmic transform} {Input row indices are exact one-based positions in the caller's original input before explicit omission and zero-weight removal; Dataset consumers must map them through their original-row identity resource}}
}
proc ::GX::StatisticsV1::_influenceFields {} {
    return {schema method n p rank dof input_count weight_semantics scale_method residual_scale near_one_tolerance leverage_roundoff_count deletion_available_count scaled_available_count maximum_leverage leverage_sum maximum_cook_distance leverage_review_threshold cook_review_threshold high_leverage_count high_cook_count row_identity factorization_reused fit_count block_rows}
}
proc ::GX::StatisticsV1::influencePlan {source} {
    validate $source
    if {[_get $source schema {}] ne "gxtxt.statistical_result.v1"} {_error {Influence requires one captured fitted statistical result}}
    set context [dict get $source context];set numeric [dict get $source request numerical]
    set plan [dict create api_id STATISTICAL_REGRESSION_INFLUENCE_PLAN_v1 api_version 1 status not_applicable reason {Exact linear deletion diagnostics require an unconstrained ordinary or weighted linear-design regression} response_unit [dict get $source residual unit] coordinate_space [dict get $source residual coordinate_space] weight_semantics [_get $context weight_semantics unweighted] assumptions [_influenceAssumptions]]
    foreach field {n p rank dof} {dict set plan $field [_get $numeric $field {}]}
    if {[dict get $plan response_unit] eq {}} {dict set plan response_unit unspecified}
    if {[dict get $source model profile] ne "regression"||[_get [dict get $source provenance] operation {}] ni {least_squares linear_regression polynomial_fit dataset_polynomial_fit}||[_get $context fit_geometry vertical_response] ne "vertical_response"||[_get $context loss linear] ne "linear"||[_get $context constraints unknown] ne "none"} {return $plan}
    if {[_get $context sample_role training] ne "training"} {dict set plan reason {Influence requires the actual fitted training population};return $plan}
    foreach field {n p rank dof} {if {![_finite [dict get $plan $field]]} {dict set plan status unavailable;dict set plan reason "Captured fit lacks $field";return $plan}}
    if {[dict get $plan rank]!=[dict get $plan p]||[dict get $plan p]<1||[dict get $plan p]>128||[dict get $plan n]>1000000} {dict set plan status unavailable;dict set plan reason {Influence requires full rank, at most 128 parameters and at most one million retained rows};return $plan}
    if {[dict get $plan weight_semantics] ni {unweighted relative inverse_variance}} {dict set plan reason {Influence requires a declared least-squares weight meaning};return $plan}
    dict set plan status value;dict set plan reason {};return $plan
}
proc ::GX::StatisticsV1::influenceInterpretation {source raw} {
    set plan [influencePlan $source]
    if {[dict get $plan status] ne "value"} {_error [dict get $plan reason]}
    _keys $raw [_influenceFields] influence_numeric
    foreach field [_influenceFields] {if {![dict exists $raw $field]} {_error "Influence receipt lacks $field"}}
    if {[dict get $raw schema] ne "gxtxt.linear_influence_numeric.v1"||[dict get $raw method] ne "existing_column_scaled_qr_svd_exact_linear_deletion"||[dict get $raw scale_method] ne "estimated_weighted_residual_mean_square"||[dict get $raw row_identity] ne "one_based_input_position_after_explicit_omission"||[dict get $raw weight_semantics] ne [dict get $plan weight_semantics]} {_error {Influence method/weight/row contract differs from the fitted source}}
    foreach field {n p rank dof} {if {[dict get $raw $field]!=[dict get $plan $field]} {_error "Influence $field differs from its fitted source"}}
    set n [dict get $raw n]
    foreach field {input_count leverage_roundoff_count deletion_available_count scaled_available_count high_leverage_count high_cook_count fit_count block_rows} {
        set value [dict get $raw $field]
        if {![_finite $value]||$value!=floor($value)||$value<0||$value>1000000} {_error "Invalid influence count $field"}
    }
    if {[dict get $raw input_count]<$n||[dict get $raw deletion_available_count]>$n||[dict get $raw scaled_available_count]>[dict get $raw deletion_available_count]||[dict get $raw high_leverage_count]>$n||[dict get $raw high_cook_count]>[dict get $raw scaled_available_count]||[dict get $raw leverage_roundoff_count]>$n||[dict get $raw fit_count]!=1||[dict get $raw block_rows]!=4096||![string is boolean -strict [dict get $raw factorization_reused]]||![dict get $raw factorization_reused]} {_error {Influence counts or single-fit factor reuse receipt is inconsistent}}
    foreach field {near_one_tolerance maximum_leverage leverage_sum leverage_review_threshold cook_review_threshold} {if {![_finite [dict get $raw $field]]||[dict get $raw $field]<0} {_error "Influence $field must be finite and nonnegative"}}
    if {[dict get $raw near_one_tolerance]<=0||[dict get $raw near_one_tolerance]>1e-6||[dict get $raw maximum_leverage]>1||abs([dict get $raw leverage_sum]-[dict get $raw p])>1e-7*max(1,[dict get $raw p])||[dict get $raw leverage_review_threshold]<=0||[dict get $raw cook_review_threshold]<=0} {_error {Invalid projection range or recorded diagnostic thresholds}}
    if {abs([dict get $raw leverage_review_threshold]*$n-2*[dict get $raw p])>1e-12*max(1,[dict get $raw p])||abs([dict get $raw cook_review_threshold]*$n-4)>1e-12} {_error {Recorded influence thresholds differ from their declared review rules}}
    set count [dict get $raw scaled_available_count];set maximum [dict get $raw maximum_cook_distance];set scale [dict get $raw residual_scale]
    set captured [dict get $source quantities weighted_residual_standard_deviation]
    if {[dict get $captured status] eq "value"&&[_finite [dict get $captured value]]&&[dict get $captured value]>0} {
        if {![_finite $scale]||$scale!=[dict get $captured value]} {_error {Influence residual scale differs from the captured fit}}
    } elseif {![string equal -nocase $scale NaN]} {_error {Unavailable influence scale must retain its undefined value}}
    if {$count>0} {
        if {![_finite $maximum]||$maximum<0||![_finite $scale]||$scale<=0} {_error {Available Cook diagnostics require a finite positive captured scale}}
    } elseif {![string equal -nocase $maximum NaN]} {_error {Unavailable Cook diagnostics cannot claim a finite maximum}}
    set unit [dict get $plan response_unit];set columns {}
    foreach {name label kind columnUnit definition} [list \
        input_row_index {Original input row} integer 1 {Exact one-based original input position before explicit omission or zero-weight removal} \
        leverage {Leverage} real 1 {Diagonal of the projection onto the original weighted linear design} \
        deleted_residual {Leave-one-out residual} real $unit {Observed response minus its prediction after deleting that training observation} \
        loo_prediction {Leave-one-out prediction} real $unit {Prediction at the deleted training coordinate from the remaining linear-design observations} \
        studentized_residual {Internally studentized residual} real 1 {Weighted residual divided by the captured estimated residual scale and square root of one minus leverage} \
        cooks_distance {Cook's distance} real 1 {Weighted squared change of all fitted responses divided by parameter count and captured estimated residual mean square} \
        deletion_available {Deletion available} integer 1 {One when deletion preserves rank and both leave-one-out values are representable} \
        scaled_available {Scaled diagnostics available} integer 1 {One when deletion, captured residual scale and both scaled diagnostic values are available}] {
        dict set columns $name [dict create label $label value_kind $kind unit $columnUnit definition $definition]
    }
    foreach name {deleted_residual loo_prediction} {dict set columns $name availability_field deletion_available}
    foreach name {studentized_residual cooks_distance} {dict set columns $name availability_field scaled_available}
    return [dict create api_id STATISTICAL_RESULT_SEMANTICS_API_v1 api_version 1 schema gxtxt.regression_influence_interpretation.v1 request [dict create source_request [dict remove [dict get $source request] parameter_uncertainty] numeric $raw] plan $plan row_count $n columns $columns assumptions [_influenceAssumptions]]
}
proc ::GX::StatisticsV1::_influenceReinterpret {request} {
    _keys $request {source_request numeric} influence_request
    return [influenceInterpretation [interpret [dict get $request source_request]] [dict get $request numeric]]
}
proc ::GX::StatisticsV1::_influenceReport {result} {
    validate $result;set raw [dict get $result request numeric]
    set lines [list "Linear regression influence: [dict get $result row_count] fitted rows" "Available deletions: [dict get $raw deletion_available_count]; scaled diagnostics: [dict get $raw scaled_available_count]" "Maximum leverage: [dict get $raw maximum_leverage]; maximum Cook's distance: [dict get $raw maximum_cook_distance]" "Review flags: [dict get $raw high_leverage_count] leverage above [dict get $raw leverage_review_threshold]; [dict get $raw high_cook_count] Cook's distance above [dict get $raw cook_review_threshold]"]
    return [join [concat $lines [dict get $result assumptions]] \n]
}
proc ::GX::StatisticsV1::_influenceDataFields {result} {
    set fields {};set n [dict get $result row_count]
    dict for {name column} [dict get $result columns] {
        set field [dict merge $column [dict create kind vector shape [list [expr {int($n)}] 1]]]
        if {$name eq "input_row_index"} {dict set field minimum 1;dict set field maximum [dict get $result request numeric input_count]} elseif {[dict get $column value_kind] eq "integer"} {dict set field minimum 0;dict set field maximum 1}
        if {[dict exists $column availability_field]} {dict set field nonfinite_status unavailable;dict set field nonfinite_reason {Deletion loses rank, the captured scale is unavailable, or this diagnostic is not finite};dict set field unavailable_reason [dict get $field nonfinite_reason]}
        dict set fields $name $field
    }
    return $fields
}
