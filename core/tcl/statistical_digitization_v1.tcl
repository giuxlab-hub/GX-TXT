# Shared pixel/calibration interpretation; Numeric owns propagation and covariance.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::StatisticsV1::_digitizationSummary {s} {
    set fields {schema numeric_api operation point_count calibration_input_count coordinate_units mode pixel_distribution propagation has_shared_calibration has_xy_correlation maximum_absolute_xy_correlation correlation_roundoff_tolerance source_linearization_sha256 rationale state_sha256}
    _keys $s $fields digitization_summary
    foreach key $fields {if {![dict exists $s $key]} {_error "Digitization summary requires $key"}}
    foreach {key value} {schema gxtxt.digitization_uncertainty_summary.v1 numeric_api NUMERIC_API_v1 operation digitization_uncertainty propagation first_order_linear_propagation} {if {[dict get $s $key] ne $value} {_error "Invalid digitization $key"}}
    foreach {key maximum} {point_count 4096 calibration_input_count 32} {set value [dict get $s $key];if {![_finite $value]||$value<1||$value>$maximum||$value!=floor($value)} {_error "Invalid digitization $key"};dict set s $key [expr {int($value)}]}
    foreach key {has_shared_calibration has_xy_correlation} {set value [dict get $s $key];if {$value ni {0 1}} {_error {Digitization correlation facts must be boolean}}}
    if {[llength [dict get $s coordinate_units]]!=2} {_error {Digitization requires physical X/Y units}}
    foreach unit [dict get $s coordinate_units] {_physicalText $unit digitization_unit 256;if {$unit eq {}} {_error {Digitization units must be explicit}}}
    set mode [dict get $s mode];set distribution [dict get $s pixel_distribution]
    if {$mode eq "pixel_calibration"} {
        if {$distribution ni {rectangular_full_width normal_standard_uncertainty}} {_error {Pixel resolution needs an explicit distribution before it becomes standard uncertainty}}
    } elseif {$mode eq "physical_override"} {
        if {$distribution ne "declared_independent_physical_standard_uncertainty"||[dict get $s has_shared_calibration]||[dict get $s has_xy_correlation]} {_error {Physical override must retain its declared independent error model}}
    } else {_error {Unknown digitization uncertainty model}}
    set correlation [dict get $s maximum_absolute_xy_correlation];set tolerance [dict get $s correlation_roundoff_tolerance]
    if {![_finite $correlation]||$correlation<0||$correlation>1.0000000000001||![_finite $tolerance]||$tolerance<=0||$tolerance>1e-12||([dict get $s has_xy_correlation] != ($correlation>$tolerance))} {_error {Digitization XY covariance qualification is inconsistent}}
    foreach key {state_sha256 source_linearization_sha256} {if {![regexp {^[a-f0-9]{64}$} [dict get $s $key]]} {_error {Digitization state requires exact retained identities}}}
    _physicalText [dict get $s rationale] digitization_rationale 2048
    if {[string trim [dict get $s rationale]] eq {}} {_error {Pixel/calibration evidence or override rationale is required}}
    return $s
}
proc ::GX::StatisticsV1::digitizationInterpretation {summary {context {}}} {
    set summary [_digitizationSummary $summary]
    _keys $context {source_document_id source_document_sha256 source_dataset_id source_sha256 row_identity point_ids_sha256} digitization_context
    dict for {key value} $context {
        if {[string match *sha256 $key]} {if {![regexp {^[a-f0-9]{64}$} $value]} {_error {Digitization source binding requires a SHA256}}} else {_physicalText $value digitization_identity 256}
    }
    set assumptions {{Standard uncertainty is conditional on the stated distribution and calibration evidence; image resolution alone does not validate it} {Propagation is a first-order linearization at the actual physical coordinates; no coverage probability or confidence interval is implied} {Independent point errors and shared calibration inputs are distinct; shared factors retain cross-point covariance} {A response-only fit ignores predictor uncertainty; both-axis uncertainty requires an actual errors-in-variables solver} {Projective or rotated calibration may correlate X and Y; marginal sigmas alone cannot represent this correlation}}
    if {[dict get $summary mode] eq "physical_override"} {lappend assumptions {The documented physical override replaces the pixel/calibration error model with user-declared independent standard uncertainties}}
    lassign [dict get $summary coordinate_units] x y
    set columns [dict create sigma_x [dict create quantity standard_uncertainty axis x unit $x] sigma_y [dict create quantity standard_uncertainty axis y unit $y] covariance_xy [dict create quantity covariance axes xy unit "($x)*($y)"]]
    return [dict create schema gxtxt.digitization_interpretation.v1 api_id STATISTICAL_RESULT_SEMANTICS_API_v1 api_version 1 status value summary $summary context $context columns $columns assumptions $assumptions]
}
proc ::GX::StatisticsV1::_digitizationValidated {meaning} {
    _keys $meaning {schema api_id api_version status summary context columns assumptions} digitization_interpretation
    set expected [digitizationInterpretation [dict get $meaning summary] [dict get $meaning context]]
    foreach key [dict keys $expected] {if {![dict exists $meaning $key]||[dict get $meaning $key] ne [dict get $expected $key]} {_error "Digitization interpretation changed: $key"}}
    return $expected
}
proc ::GX::StatisticsV1::digitizationFitPlan {meaning kind orientation} {
    set meaning [_digitizationValidated $meaning];set s [dict get $meaning summary]
    if {$kind ni {sigma sigma_xy full_response_covariance}||$orientation ni {y_of_x x_of_y}} {_error {Choose response sigma, actual XY ODR, or full response covariance and a physical orientation}}
    set response [expr {$orientation eq "y_of_x"?"y":"x"}];set predictor [expr {$response eq "y"?"x":"y"}]
    set status value;set reason {Declared marginal response standard uncertainty; predictor uncertainty is ignored}
    if {$kind eq "sigma_xy"} {
        set reason {Both declared coordinate standard uncertainties require the actual diagonal XY ODR backend}
        if {[dict get $s has_shared_calibration]||[dict get $s has_xy_correlation]} {set status unavailable;set reason {Diagonal XY ODR cannot represent shared calibration or within-point XY covariance; preserve the full covariance or explicitly review and replace the uncertainty model}}
    } elseif {$kind eq "sigma"&&[dict get $s has_shared_calibration]} {set status unavailable;set reason {Shared calibration creates cross-point covariance; marginal response sigma cannot be used as independent measurement noise}}
    if {$kind eq "full_response_covariance"} {set reason {Use the full original-order response covariance with the shared GLS owner; predictor uncertainty is ignored}}
    return [dict create schema gxtxt.digitization_fit_plan.v1 api_id STATISTICAL_RESULT_SEMANTICS_API_v1 api_version 1 status $status reason $reason kind $kind orientation $orientation response_axis $response predictor_axis $predictor source_state_sha256 [dict get $s state_sha256] source_linearization_sha256 [dict get $s source_linearization_sha256] assumptions [dict get $meaning assumptions]]
}
proc ::GX::StatisticsV1::digitizationReport {meaning} {
    set meaning [_digitizationValidated $meaning];set s [dict get $meaning summary]
    set text "Digitization uncertainty: [dict get $s mode]\nPixel distribution: [dict get $s pixel_distribution]\nOriginal points: [dict get $s point_count]\nShared calibration covariance: [dict get $s has_shared_calibration]\nWithin-point XY correlation: [dict get $s has_xy_correlation]\nRationale: [dict get $s rationale]"
    foreach assumption [dict get $meaning assumptions] {append text "\n$assumption"}
    return $text
}
