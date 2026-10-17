# Shared meaning of public Numeric location estimates; no numerical recomputation.
# SPDX-License-Identifier: GPL-3.0-or-later
apply {{} {
    variable quantities
    foreach {id label unit definition} {
        location_estimate {Location estimate} response {Arithmetic sample mean for the Student-t mean interval, or the converged fixed-scale Huber location under the recorded method}
        location_lower {Lower mean confidence limit} response {Sample mean minus the two-sided Student-t critical value times sample standard deviation divided by square root of the observation count}
        location_upper {Upper mean confidence limit} response {Sample mean plus the two-sided Student-t critical value times sample standard deviation divided by square root of the observation count}
        location_confidence {Nominal mean confidence level} dimensionless {One minus the requested two-sided alpha; a repeated-sampling level under the recorded assumptions}
        location_standard_error {Mean standard error} response {Sample standard deviation with denominator n minus one, divided by square root of n; not a prediction interval or measurement calibration uncertainty}
        location_degrees_of_freedom {Mean interval degrees of freedom} count {Observation count minus one for the Student-t mean interval}
        location_scale {Fixed Huber residual scale} response {1.4826 times the initial median absolute deviation from the initial median, floored at absolute machine epsilon; held fixed during iteration, not a standard error}
        location_iterations {Huber iterations} count {Actual completed reweighting iterations, bounded by the existing limit of 100}
        location_huber_constant {Huber tuning constant} dimensionless {Positive residual cutoff in units of the fixed robust scale}
        location_converged {Huber stopping criterion met} dimensionless {One only when the absolute location update is less than 1e-10 times the fixed scale; does not establish statistical coverage}
    } {dict set quantities $id [dict create label $label unit $unit kind scalar policy location_estimate definition $definition]}
} ::GX::StatisticsV1}
proc ::GX::StatisticsV1::_locationFieldMap {operation} {
    switch -- $operation {
        foundation.statistics.confidence_interval {return {n n estimate location_estimate lower location_lower upper location_upper confidence location_confidence standard_error location_standard_error degrees_of_freedom location_degrees_of_freedom}}
        foundation.statistics.robust_location {return {n n location location_estimate scale location_scale iterations location_iterations huber_constant location_huber_constant converged location_converged}}
        default {_error {Unknown public location estimate}}
    }
}
proc ::GX::StatisticsV1::_locationAssumptions {method} {
    switch -- $method {
        student_t_mean {return {{The observations are modeled as independent and identically distributed with finite variance} {Student-t mean coverage is exact for a normal population; the nominal level alone does not verify normality or independence} {The interval describes the population mean, not individual observations or calibrated measurement uncertainty}}}
        Huber {return {{The estimator uses a median start, a fixed initial MAD scale and Huber residual weights} {The absolute machine-epsilon floor is expressed in raw numeric units; rescaling observations can change its effect} {No standard error, confidence interval, robustness guarantee or repeated-sampling coverage is inferred from convergence}}}
        default {_error {Unknown location method}}
    }
}
proc ::GX::StatisticsV1::_locationAdapt {operation raw context} {
    set numerical {}
    dict for {field quantity} [_locationFieldMap $operation] {
        if {![dict exists $raw $field]||[llength [dict get $raw $field]]!=1} {_error {Location interpretation requires its actual scalar Numeric facts}}
        dict set numerical $quantity [dict get $raw $field]
    }
    set method [_get $raw method {}]
    if {($operation eq "foundation.statistics.confidence_interval"&&$method ne "student_t_mean")||($operation eq "foundation.statistics.robust_location"&&$method ne "Huber")} {_error {Location operation differs from its numerical method}}
    if {$method eq "Huber"&&[_get $raw scale_method {}] ne "initial_median_MAD_1.4826_with_absolute_eps_floor"} {_error {Unknown Huber scale method}}
    dict set context method $method;dict set context assumptions [_locationAssumptions $method]
    return [list $numerical $context]
}
proc ::GX::StatisticsV1::_validateLocation {numerical context} {
    set method [_get $context method {}]
    if {![dict exists $context y_unit]||[_get $context assumptions {}] ne [_locationAssumptions $method]} {_error {Location estimates require actual source units and their CORE assumptions}}
    set n [_get $numerical n {}]
    if {![_finite $n]||$n<1||$n!=floor($n)} {_error {Location estimate requires a positive integer observation count}}
    if {$method eq "student_t_mean"} {
        set confidence [_get $numerical location_confidence {}]
        if {![_finite $confidence]||$confidence<=0||$confidence>=1||[_get $numerical location_degrees_of_freedom {}]!=$n-1} {_error {Mean interval confidence or degrees of freedom disagree with the actual estimator}}
        set se [_get $numerical location_standard_error {}]
        if {[_finite $se]&&$se<0} {_error {Mean standard error cannot be negative}}
        foreach key {location_lower location_upper location_standard_error} {
            if {![dict exists $numerical $key]} {_error {Mean interval is missing a numerical fact}}
            if {$n==1&&[_finite [dict get $numerical $key]]} {_error {A singleton cannot have finite sample mean uncertainty}}
        }
        set lo [dict get $numerical location_lower];set hi [dict get $numerical location_upper];set mean [_get $numerical location_estimate NaN]
        if {[_finite $lo]&&[_finite $hi]&&[_finite $mean]&&($lo>$mean||$mean>$hi)} {_error {Mean confidence endpoints do not bracket the estimate}}
    } else {
        foreach key {location_scale location_huber_constant} {set v [_get $numerical $key {}];if {![_finite $v]||$v<=0} {_error {Huber location needs its actual positive scale and tuning constant}}}
        set count [_get $numerical location_iterations {}];set converged [_get $numerical location_converged {}]
        if {![_finite $count]||$count<1||$count>100||$count!=floor($count)||$converged ni {0 1}} {_error {Invalid actual Huber iteration or convergence facts}}
        if {!$converged&&$count!=100} {_error {Unconverged Huber estimate must retain its exhausted iteration limit}}
    }
}
proc ::GX::StatisticsV1::_locationPolicy {quantity profile numerical context} {
    if {$profile ne "location_estimate"} {return {not_applicable {Quantity requires a registered location estimator}}}
    set method [dict get $context method]
    if {$quantity in {location_lower location_upper location_standard_error location_confidence location_degrees_of_freedom}&&$method ne "student_t_mean"} {return {not_applicable {Huber location does not supply mean-interval inference}}}
    if {$quantity in {location_scale location_iterations location_huber_constant location_converged}&&$method ne "Huber"} {return {not_applicable {Quantity requires the fixed-scale Huber estimator}}}
    if {$quantity in {location_lower location_upper location_standard_error}&&[dict get $numerical n]<2} {return {undefined {At least two observations are required for sample mean uncertainty}}}
    if {$quantity eq "location_estimate"&&$method eq "Huber"&&![dict get $numerical location_converged]} {return {unavailable {The Huber iteration limit was exhausted without satisfying the stopping criterion}}}
    return {value {}}
}
