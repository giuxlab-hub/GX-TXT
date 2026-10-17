# Captured rational-domain interpretation; all polynomial/fit computation is Numeric.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::StatisticsV1::_rationalAssumptions {{operation rational_fit}} {
    set result {{The response is a rational least-squares model with fixed numerator and denominator degrees; it is not Taylor-series Pade coefficient matching} {The denominator constant is fixed at one; no common numerator/denominator factor is silently cancelled} {The bounded binary64 interval guard reports a separated denominator on the declared physical domain; diagnostic polynomial roots are not certified pole locations} {Parameter covariance and likelihood comparisons are local and conditional on the declared degrees, domain, exact predictor values and response-noise model} {Extrapolation requires explicit permission and a whole-interval denominator check; finite endpoint values do not permit crossing a pole}}
    if {$operation eq "rational_residuals"} {lappend result {Residual evaluation uses captured parameters without fitting and supplies no training degrees of freedom or parameter inference}}
    return $result
}
proc ::GX::StatisticsV1::_rationalSummary {raw} {
    set fields {schema numeric_api operation domain_receipt observation_domain parameter_ids parameter_units predictor_unit response_unit fit_geometry normalization approximation inference_scope}
    if {[_get $raw operation {}] eq "rational_residuals"} {lappend fields evaluation_count evaluation_domain}
    _keys $raw $fields rational_summary
    foreach key $fields {if {![dict exists $raw $key]} {_error "Rational summary requires $key"}}
    foreach {key expected} {numeric_api NUMERIC_API_v1 fit_geometry vertical_response normalization denominator_constant_one approximation rational_least_squares_not_Taylor_Pade_matching} {
        if {[dict get $raw $key] ne $expected} {_error "Unsupported rational $key"}
    }
    set operation [dict get $raw operation]
    if {$operation eq "rational_fit"} {set schema gxtxt.rational_fit_summary.v1;set scope local_conditional_on_fixed_degrees_domain_and_response_noise
    } elseif {$operation eq "rational_residuals"} {
        set schema gxtxt.rational_residual_summary.v1;set scope descriptive_evaluation_at_captured_parameters_no_parameter_inference
        set n [dict get $raw evaluation_count];set d [dict get $raw evaluation_domain]
        if {![_finite $n]||$n<1||$n>1000000||$n!=floor($n)||[llength $d]!=2||![_finite [lindex $d 0]]||![_finite [lindex $d 1]]||[lindex $d 0]>[lindex $d 1]} {_error {Invalid rational evaluation extent or count}}
    } else {_error {Unknown rational operation}}
    if {[dict get $raw schema] ne $schema||[dict get $raw inference_scope] ne $scope} {_error {Rational evaluation cannot acquire training meaning}}
    set receipt [dict get $raw domain_receipt]
    set fields {schema status reason domain coordinate_unit denominator_constant numerator_degree denominator_degree denominator_coefficients_descending denominator_coefficient_bound relative_margin_lower_bound pole_tolerance interval_nodes method root_method poles_real_imag possible_common_factor cancellation_policy parameters declaration_sha256 source_sha256 binding_sha256}
    _keys $receipt $fields rational_domain
    foreach key $fields {if {![dict exists $receipt $key]} {_error "Rational domain requires $key"}}
    foreach {key expected} {schema gxtxt.rational_domain.v1 status safe method bounded_binary64_Bernstein_sign_guard root_method Octave_roots_diagnostic_only cancellation_policy no_automatic_factor_cancellation} {
        if {[dict get $receipt $key] ne $expected} {_error "Rational inference requires captured $key=$expected"}
    }
    _physicalText [dict get $receipt reason] rational_domain_reason 2048
    foreach {key lo hi} {numerator_degree 0 8 denominator_degree 1 8 interval_nodes 1 4096} {
        set n [dict get $receipt $key];if {![_finite $n]||$n!=floor($n)||$n<$lo||$n>$hi} {_error {Invalid bounded rational degree or domain-work count}}
        dict set receipt $key [expr {int($n)}]
    }
    foreach key {predictor_unit response_unit} {_physicalText [dict get $raw $key] rational_unit 256;if {[dict get $raw $key] eq {}} {_error {Rational coordinates require physical units}}}
    if {[dict get $receipt coordinate_unit] ne [dict get $raw predictor_unit]} {_error {Rational domain unit differs from its predictor}}
    foreach key {declaration_sha256 source_sha256 binding_sha256} {if {![regexp {^[0-9a-f]{64}$} [dict get $receipt $key]]} {_error {Rational declaration and expression identities are required}}}
    foreach d [list [dict get $receipt domain] [dict get $raw observation_domain]] {
        if {[llength $d]!=2||![_finite [lindex $d 0]]||![_finite [lindex $d 1]]||[lindex $d 0]>=[lindex $d 1]} {_error {Rational bounds must retain their finite increasing interval}}
    }
    lassign [dict get $receipt domain] lo hi;lassign [dict get $raw observation_domain] first last
    if {$operation eq "rational_residuals"&&([lindex [dict get $raw evaluation_domain] 0]<$lo||[lindex [dict get $raw evaluation_domain] 1]>$hi)} {_error {Rational evaluation exceeds the guarded domain}}
    if {$first<$lo||$last>$hi} {_error {Rational observations exceed the guarded declared domain}}
    foreach key {denominator_constant denominator_coefficient_bound relative_margin_lower_bound pole_tolerance possible_common_factor} {if {![_finite [dict get $receipt $key]]} {_error {Rational domain facts must be finite}}}
    if {[dict get $receipt denominator_constant]!=1||[dict get $receipt denominator_coefficient_bound]<=0||[dict get $receipt pole_tolerance]<1e-12||[dict get $receipt pole_tolerance]>1e-2||[dict get $receipt relative_margin_lower_bound]<=[dict get $receipt pole_tolerance]||[dict get $receipt relative_margin_lower_bound]>1.000001||[dict get $receipt possible_common_factor] ni {0 1 0.0 1.0}} {_error {Rational denominator separation facts are inconsistent}}
    dict set receipt possible_common_factor [expr {int([dict get $receipt possible_common_factor])}]
    set count [expr {[dict get $receipt numerator_degree]+[dict get $receipt denominator_degree]+1}]
    if {[llength [dict get $raw parameter_ids]]!=$count||[llength [dict get $raw parameter_units]]!=$count||[llength [dict get $receipt parameters]]!=$count} {_error {Rational coefficient identities differ from declared powers}}
    set expected {};for {set k 0} {$k<=[dict get $receipt numerator_degree]} {incr k} {lappend expected a$k};for {set k 1} {$k<=[dict get $receipt denominator_degree]} {incr k} {lappend expected b$k}
    if {[dict get $raw parameter_ids] ne $expected} {_error {Rational coefficient order cannot change}}
    foreach unit [dict get $raw parameter_units] value [dict get $receipt parameters] {_physicalText $unit rational_parameter_unit 256;if {$unit eq {}||![_finite $value]} {_error {Rational parameters need finite values and physical units}}}
    set coefficients [dict get $receipt denominator_coefficients_descending]
    if {[llength $coefficients]!=[dict get $receipt denominator_degree]+1||[lindex $coefficients end]!=1} {_error {Rational denominator normalization changed}}
    foreach value $coefficients {if {![_finite $value]} {_error {Rational denominator coefficient must be finite}}}
    set roots [dict get $receipt poles_real_imag]
    if {[llength $roots]>[dict get $receipt denominator_degree]} {_error {Too many rational pole diagnostics}}
    foreach row $roots {if {[llength $row]!=2||![_finite [lindex $row 0]]||![_finite [lindex $row 1]]} {_error {Rational roots require explicit real/imaginary pairs}}}
    dict set raw domain_receipt $receipt;return $raw
}
proc ::GX::StatisticsV1::_rationalContext {summary context} {
    set summary [_rationalSummary $summary]
    set role [expr {[dict get $summary operation] eq "rational_fit"?"training":"evaluation"}]
    set orientation [_get $context orientation y_of_x]
    if {$orientation ni {y_of_x x_of_y}} {_error {Rational response requires one physical independent coordinate}}
    set x [dict get $summary predictor_unit];set y [dict get $summary response_unit]
    if {$orientation eq "x_of_y"} {set x [dict get $summary response_unit];set y [dict get $summary predictor_unit]}
    foreach {key expected} [list orientation $orientation x_unit $x y_unit $y fit_geometry vertical_response sample_role $role] {
        if {[dict exists $context $key]&&[dict get $context $key] ne $expected} {_error "Rational context conflicts with captured $key"};dict set context $key $expected
    }
    foreach key {surface complex implicit gls smoothing baseline_correction response_transform} {if {[dict exists $context $key]} {_error {Rational inference cannot acquire another residual or preprocessing contract}}}
    if {[dict exists $context rational]&&[dict get $context rational] ne $summary} {_error {A consumer cannot replace captured rational-domain facts}}
    dict set context rational $summary
    foreach assumption [_rationalAssumptions [dict get $summary operation]] {if {$assumption ni [_get $context assumptions {}]} {dict lappend context assumptions $assumption}}
    return $context
}
proc ::GX::StatisticsV1::_rationalValidate {modelId context numerical parameters provenance profile} {
    set summary [_rationalSummary [dict get $context rational]];set receipt [dict get $summary domain_receipt]
    set operation [dict get $summary operation];set role [expr {$operation eq "rational_fit"?"training":"evaluation"}]
    if {$modelId ne "math.numeric.rational"||$profile ne "nonlinear_regression"||[_get $provenance operation {}] ne $operation||[_get $context fit_geometry {}] ne "vertical_response"||[_get $context sample_role training] ne $role} {_error {Rational statistics require the registered physical response and domain interpretation}}
    if {[llength $parameters]!=[llength [dict get $summary parameter_ids]]} {_error {Rational parameter count changed}}
    foreach parameter $parameters id [dict get $summary parameter_ids] unit [dict get $summary parameter_units] value [dict get $receipt parameters] {
        if {[dict get $parameter id] ne $id||[dict get $parameter unit] ne $unit||![dict exists $parameter value]||[dict get $parameter value]!=$value} {_error {Rational physical parameters differ from the checked denominator}}
    }
    foreach key {source_sha256 binding_sha256} {if {[_get $provenance model_$key {}] ne [dict get $receipt $key]} {_error {Rational formula differs from its captured solver identity}}}
    set expected [_rationalContext $summary [dict remove $context rational assumptions]]
    foreach key {orientation x_unit y_unit fit_geometry sample_role} {if {[_get $context $key {}] ne [dict get $expected $key]} {_error {Rational physical coordinate semantics changed}}}
    if {$role eq "evaluation"} {
        if {[_get $numerical n {}]!=[dict get $summary evaluation_count]} {_error {Rational evaluation count changed}}
        foreach key {rank dof covariance standard_errors reduced_chi_squared} {if {[dict exists $numerical $key]} {_error {Rational evaluation cannot acquire training inference}}}
    } elseif {[_get [_get $provenance observation_signature {}] predictor_count {}]!=1} {_error {Rational inference requires its exact single-predictor observation signature}}
    foreach assumption [_rationalAssumptions [dict get $summary operation]] {if {$assumption ni [_get $context assumptions {}]} {_error {Rational inference qualifications were removed}}}
}
