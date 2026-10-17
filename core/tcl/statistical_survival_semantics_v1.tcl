# Meaning of captured Kaplan-Meier product-limit facts; no estimator here.
# SPDX-License-Identifier: GPL-3.0-or-later
apply {{} {
    variable quantities
    foreach {id label unit definition} {
        survival_time {Observed event or censoring coordinate} predictor {Sorted distinct observed coordinates, including times with censoring only; the estimate is reported after events at that coordinate}
        survival_probability {Kaplan-Meier survival estimate} dimensionless {Product of one minus events divided by the risk set at each observed coordinate up to and including this coordinate; censoring at tied coordinates is withdrawn after the event fraction}
        survival_at_risk {Risk set before the coordinate} count {Observations remaining immediately before events and censoring at this coordinate; no delayed entry is modeled}
        survival_events {Events at the coordinate} count {Observations at this coordinate whose supplied indicator is one}
        survival_censored {Censored at the coordinate} count {Observations at this coordinate whose supplied indicator is zero}
    } {dict set quantities $id [dict create label $label unit $unit kind scalar policy survival definition $definition]}
} ::GX::StatisticsV1}
proc ::GX::StatisticsV1::_survivalFieldMap {} {return {n n time survival_time survival survival_probability at_risk survival_at_risk events survival_events censored survival_censored}}
proc ::GX::StatisticsV1::_survivalAssumptions {} {
    return {{Product-limit interpretation assumes independent observations and noninformative right censoring} {Event indicators are one for events and zero for censoring; all observations enter before the first reported coordinate, with no left truncation} {Tied events use the risk set before either events or censoring are withdrawn; censor-only coordinates are retained} {The curve is descriptive under the supplied data; no confidence interval, standard error or causal effect is supplied}}
}
proc ::GX::StatisticsV1::_survivalAdapt {raw context} {
    if {[_get $raw method {}] ne "Kaplan-Meier"} {_error {Survival result must retain its actual Kaplan-Meier method}}
    set numerical {}
    dict for {field quantity} [_survivalFieldMap] {
        if {![dict exists $raw $field]||[llength [dict get $raw $field]]!=1} {_error {Survival adaptation needs scalar row facts; use fromNumericColumns for a curve}}
        dict set numerical $quantity [dict get $raw $field]
    }
    dict set context method Kaplan-Meier;dict set context assumptions [_survivalAssumptions]
    return [list $numerical $context]
}
proc ::GX::StatisticsV1::_validateSurvival {numerical context} {
    if {[_get $context method {}] ne "Kaplan-Meier"||[_get $context assumptions {}] ne [_survivalAssumptions]||![dict exists $context x_unit]} {_error {Survival requires its actual method, coordinate unit and CORE assumptions}}
    foreach key {n survival_at_risk survival_events survival_censored} {set v [_get $numerical $key {}];if {![_finite $v]||$v<0||$v!=floor($v)} {_error {Survival counts must be actual nonnegative integers}}}
    set risk [dict get $numerical survival_at_risk];set removed [expr {[dict get $numerical survival_events]+[dict get $numerical survival_censored]}]
    if {$risk<1||$risk>[dict get $numerical n]||$removed<1||$removed>$risk} {_error {Survival event/censor counts exceed their actual risk set}}
    set p [_get $numerical survival_probability {}]
    if {![_finite $p]||$p<0||$p>1||![_finite [_get $numerical survival_time {}]]} {_error {Survival requires a finite coordinate and probability in zero to one}}
}
proc ::GX::StatisticsV1::_survivalPolicy {quantity profile numerical context} {
    if {$profile ne "survival"} {return {not_applicable {Quantity requires a registered Kaplan-Meier estimator}}}
    return {value {}}
}
