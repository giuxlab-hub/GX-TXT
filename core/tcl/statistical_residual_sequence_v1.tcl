# SPDX-License-Identifier: GPL-3.0-or-later
# CORE interprets captured Numeric facts; it never recomputes sequence statistics.
proc ::GX::StatisticsV1::_sequenceFields {} {
    return {numeric_api operation schema input_count n omitted_count nonfinite_policy ordering key_storage_class generated_input_positions tie_count tie_policy input_residual_sha256 input_order_sha256 ordered_residual_sha256 ordered_keys_sha256 positive_count negative_count zero_count sign_zero_policy runs runs_expected runs_variance runs_z runs_reference runs_continuity_correction durbin_watson durbin_watson_definition lags lag_pair_count autocorrelation autocorrelation_definition constant_sequence zero_sequence work_units p_values_computed}
}
proc ::GX::StatisticsV1::_sequenceNumber {value} {
    if {[string equal -nocase $value NaN]} {return NaN}
    if {![_finite $value]} {_error {Residual sequence fact must be finite or explicitly undefined}}
    return [format %.17g $value]
}
proc ::GX::StatisticsV1::_sequenceRaw {raw} {
    _keys $raw [_sequenceFields] residual_sequence_numeric
    set result {}
    foreach key [_sequenceFields] {
        if {![dict exists $raw $key]} {_error "Residual sequence receipt lacks $key"}
        set value [dict get $raw $key]
        if {$key in {input_count n omitted_count tie_count positive_count negative_count zero_count runs work_units}} {
            if {![_finite $value]||$value<0||$value!=floor($value)||$value>64000000} {_error "Invalid sequence count $key"}
            set value [expr {wide($value)}]
        } elseif {$key in {generated_input_positions constant_sequence zero_sequence p_values_computed}} {
            if {![string is boolean -strict $value]} {_error "Invalid sequence boolean $key"}
            set value [expr {!!$value}]
        } elseif {$key in {runs_expected runs_variance runs_z durbin_watson}} {
            set value [_sequenceNumber $value]
        } elseif {$key in {lags lag_pair_count autocorrelation}} {
            if {[llength $value]<1||[llength $value]>64} {_error {Sequence lag vectors require 1..64 elements}}
            set value [lmap element $value {_sequenceNumber $element}]
        }
        dict set result $key $value
    }
    return $result
}
proc ::GX::StatisticsV1::_sequenceContext {context} {
    set names {residual_unit coordinate_space population order_label residual_convention source_sha256}
    _keys $context $names residual_sequence_context
    set result {}
    foreach key $names {
        if {![dict exists $context $key]||[string trim [dict get $context $key]] eq {}||[string length [dict get $context $key]]>1024} {_error "Explicit sequence context requires $key"}
        dict set result $key [dict get $context $key]
    }
    if {[dict get $result population] ni {fitted_residuals independent_observations unspecified_dependence}} {_error {Declare fitted_residuals, independent_observations or unspecified_dependence explicitly}}
    if {![regexp {^[0-9a-f]{64}$} [dict get $result source_sha256]]} {_error {Sequence context requires the source content SHA256}}
    return $result
}
proc ::GX::StatisticsV1::residualSequenceInterpretation {numeric context} {
    set raw [_sequenceRaw $numeric];set context [_sequenceContext $context]
    foreach {key expected} {
        numeric_api NUMERIC_API_v1 operation residual_sequence schema gxtxt.residual_sequence_numeric.v1
        tie_policy stable_input_order sign_zero_policy exclude_exact_zeros_from_runs_only
        runs_reference uniform_permutation_conditional_on_nonzero_sign_counts runs_continuity_correction none
        durbin_watson_definition successive_squared_differences_over_uncentered_squared_residuals
        autocorrelation_definition globally_centered_lag_product_over_complete_centered_sum_squares
        p_values_computed 0
    } {if {[dict get $raw $key] ne $expected} {_error "Unrecognized residual sequence $key contract"}}
    set n [dict get $raw n];set count [dict get $raw input_count]
    if {$n<2||$n>1000000||$count>1000000||$n+[dict get $raw omitted_count]!=$count||[dict get $raw positive_count]+[dict get $raw negative_count]+[dict get $raw zero_count]!=$n} {_error {Sequence population counts are inconsistent}}
    if {[dict get $raw nonfinite_policy] ni {error omit}||([dict get $raw omitted_count]>0&&[dict get $raw nonfinite_policy] ne "omit")||[dict get $raw ordering] ni {input ascending}} {_error {Sequence ordering or omission policy is inconsistent}}
    if {[dict get $raw key_storage_class] ni {double single int8 uint8 int16 uint16 int32 uint32 int64 uint64}||([dict get $raw generated_input_positions]&&[dict get $raw ordering] ne "input")||[dict get $raw tie_count]>=$n||([dict get $raw ordering] eq "input"&&[dict get $raw tie_count]!=0)} {_error {Sequence key storage or ordering receipt is inconsistent}}
    foreach key {input_residual_sha256 input_order_sha256 ordered_residual_sha256 ordered_keys_sha256} {if {![regexp {^[0-9a-f]{64}$} [dict get $raw $key]]} {_error "Invalid sequence fingerprint $key"}}
    set nonzero [expr {$n-[dict get $raw zero_count]}];set runs [dict get $raw runs]
    if {($nonzero==0&&$runs!=0)||($nonzero>0&&($runs<1||$runs>$nonzero))||[dict get $raw zero_sequence]!=($nonzero==0)||([dict get $raw zero_sequence]&&![dict get $raw constant_sequence])} {_error {Sequence sign or zero-state receipt is inconsistent}}
    set both [expr {[dict get $raw positive_count]>0&&[dict get $raw negative_count]>0}]
    if {$both} {
        foreach key {runs_expected runs_variance} {if {![_finite [dict get $raw $key]]||[dict get $raw $key]<0} {_error "Undefined conditional runs $key with both signs present"}}
        if {[dict get $raw runs_expected]<1||[dict get $raw runs_expected]>$nonzero} {_error {Conditional expected runs is outside its population}}
        if {[dict get $raw runs_variance]>0} {if {![_finite [dict get $raw runs_z]]} {_error {Positive conditional runs variance requires a finite standardized deviation}}} elseif {[dict get $raw runs_z] ne "NaN"} {_error {Degenerate conditional runs variance requires undefined standardized deviation}}
    } else {foreach key {runs_expected runs_variance runs_z} {if {[dict get $raw $key] ne "NaN"} {_error {One-sign or zero sequence has no conditional runs reference}}}}
    set dw [dict get $raw durbin_watson]
    if {[dict get $raw zero_sequence]} {if {$dw ne "NaN"} {_error {Zero residual norm requires undefined Durbin-Watson}}} elseif {![_finite $dw]||$dw<0||$dw>4} {_error {Durbin-Watson must lie between zero and four}}
    set lag [llength [dict get $raw lags]]
    if {$lag>=$n||[llength [dict get $raw autocorrelation]]!=$lag||[llength [dict get $raw lag_pair_count]]!=$lag||[dict get $raw work_units]!=$n*$lag} {_error {Sequence lag dimensions or work receipt disagree}}
    set k 0
    foreach index [dict get $raw lags] pairs [dict get $raw lag_pair_count] value [dict get $raw autocorrelation] {
        incr k
        if {![_finite $index]||![_finite $pairs]||$index!=$k||$pairs!=$n-$k} {_error {Sequence lag positions or pair counts disagree}}
        if {[dict get $raw constant_sequence]} {if {$value ne "NaN"} {_error {Constant sequence requires undefined centered autocorrelation}}} elseif {![_finite $value]||abs($value)>1} {_error {Sequence autocorrelation must lie between minus one and one}}
    }
    set metrics {}
    foreach {key label definition} {
        runs {Sign runs} {Number of constant-sign groups after removing exact zero residuals}
        runs_expected {Conditional expected runs} {Expected runs under uniform permutation conditional on the nonzero positive and negative counts}
        runs_variance {Conditional runs variance} {Variance of runs under the same conditional sign permutation reference}
        runs_z {Conditional runs standardized deviation} {Deviation from conditional expected runs divided by its standard deviation; no continuity correction or p value}
        durbin_watson {Durbin-Watson statistic} {Sum of squared successive residual differences divided by the uncentered residual sum of squares}
    } {
        set value [dict get $raw $key];set status value;set reason {}
        if {$value eq "NaN"} {set status unavailable;set reason {Degenerate sign counts, zero conditional variance or zero residual norm}}
        dict set metrics $key [dict create label $label unit 1 definition $definition status $status value $value reason $reason]
    }
    set assumptions [list {Descriptive order-dependent diagnostics; no p values, significance thresholds or automatic outlier deletion are supplied} {Fitted residuals depend on the fitted model and are generally dependent even when measurement errors are independent; these statistics do not prove independence or validate an uncertainty model} {Runs use signs relative to zero, remove exact zeros for that calculation only and use a conditional sign permutation reference; the standardized deviation is not a general regression hypothesis test} {Lag autocorrelation uses globally centered residual products and the complete centered sum of squares; it is descriptive and uses observation lags, not elapsed-time lags} {Durbin-Watson uses uncentered residuals; interpret with the explicitly declared row order, fitted design and noise assumptions} {Ascending keys retain original order within ties; omitted nonfinite pairs join surviving observations and change adjacency}]
    return [dict create api_id STATISTICAL_RESULT_SEMANTICS_API_v1 api_version 1 schema gxtxt.residual_sequence_interpretation.v1 request [dict create numeric $raw context $context] row_count $n metrics $metrics autocorrelation_label {Residual lag autocorrelation} autocorrelation_unit 1 assumptions $assumptions]
}
proc ::GX::StatisticsV1::_sequenceValidate {result} {
    set expected [residualSequenceInterpretation [dict get $result request numeric] [dict get $result request context]]
    set canonical $result
    dict set canonical request [dict get $expected request]
    if {[lsort [dict keys [dict get $result request]]] ne {context numeric}} {_error {Sequence request has unvalidated fields}}
    if {![dict exists $result row_count]||![_finite [dict get $result row_count]]||[dict get $result row_count]!=[dict get $expected row_count]} {_error {Sequence row count changed}}
    dict set canonical row_count [dict get $expected row_count]
    set metrics {}
    if {[lsort [dict keys [dict get $result metrics]]] ne [lsort [dict keys [dict get $expected metrics]]]} {_error {Sequence metric identities changed}}
    dict for {key metric} [dict get $expected metrics] {
        set actual [dict get $result metrics $key]
        if {[lsort [dict keys $actual]] ne [lsort [dict keys $metric]]} {_error {Sequence metric fields changed}}
        set item {};dict for {field value} $metric {
            set found [dict get $actual $field];if {$field eq "value"} {set found [_sequenceNumber $found]}
            if {$found ne $value} {_error "Sequence metric '$key' bypasses CORE interpretation"}
            dict set item $field $found
        };dict set metrics $key $item
    }
    dict set canonical metrics $metrics
    if {[lsort [dict keys $canonical]] ne [lsort [dict keys $expected]]} {_error {Sequence result has unvalidated fields}}
    dict for {key value} $expected {if {[dict get $canonical $key] ne $value} {_error "Sequence field '$key' bypasses CORE interpretation"}}
    return [dict create valid 1 api_id STATISTICAL_RESULT_SEMANTICS_API_v1]
}
proc ::GX::StatisticsV1::_sequenceReport {result} {
    validate $result;set raw [dict get $result request numeric];set context [dict get $result request context]
    set lines [list "Residual sequence: [dict get $result row_count] rows; [dict get $context population]" "Order: [dict get $context order_label] ([dict get $raw ordering]); ties [dict get $raw tie_count]; omitted [dict get $raw omitted_count]" "Residuals: [dict get $context residual_convention]; unit [dict get $context residual_unit]; coordinates [dict get $context coordinate_space]"]
    dict for {id item} [dict get $result metrics] {lappend lines "[dict get $item label]: [dict get $item value] ([dict get $item status]); [dict get $item definition]"}
    foreach lag [dict get $raw lags] pairs [dict get $raw lag_pair_count] value [dict get $raw autocorrelation] {lappend lines "[dict get $result autocorrelation_label], lag $lag: $value; pairs $pairs"}
    return [join [concat $lines [dict get $result assumptions]] \n]
}
