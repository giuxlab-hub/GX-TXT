# Interpretation of captured implicit-equation facts; no numerical estimation.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::StatisticsV1::_implicitSummary {raw} {
    set fields {schema numeric_api operation declaration_sha256 residual_mode residual_unit objective_unit_rule normalization fit_geometry residual_definition measurement_error_distance observation_count parameter_ids parameter_units predictor_ids predictor_units equation_source_sha256 equation_binding_sha256 response_branch uncertainty_scope normalization_is_measurement_sigma}
    _keys $raw $fields implicit_numeric_summary
    foreach field $fields {if {![dict exists $raw $field]} {_error "Implicit numerical summary requires $field"}}
    foreach {field expected} {schema gxtxt.implicit_fit_summary.v1 numeric_api NUMERIC_API_v1 operation implicit_fit fit_geometry implicit_algebraic residual_definition zero_minus_equation_value_at_observed_coordinates response_branch not_declared uncertainty_scope conditional_on_observed_coordinates_and_declared_equation_error} {
        if {[dict get $raw $field] ne $expected} {_error "Unsupported implicit summary $field"}
    }
    foreach field {declaration_sha256 equation_source_sha256 equation_binding_sha256} {if {![regexp {^[0-9a-f]{64}$} [dict get $raw $field]]} {_error {Implicit result requires captured declaration/expression identities}}}
    foreach field {measurement_error_distance normalization_is_measurement_sigma} {
        if {![_finite [dict get $raw $field]]||[dict get $raw $field]!=0} {_error {Algebraic equation residuals cannot claim ODR distances or known measurement sigma}}
        dict set raw $field 0
    }
    set n [dict get $raw observation_count]
    if {![_finite $n]||$n<2||$n>65536||$n!=floor($n)} {_error {Implicit observation count is outside its captured contract}}
    dict set raw observation_count [expr {int($n)}]
    foreach {ids units minimum maximum} {parameter_ids parameter_units 1 32 predictor_ids predictor_units 2 2} {
        set names [dict get $raw $ids];set labels [dict get $raw $units]
        if {[llength $names]<$minimum||[llength $names]>$maximum||[llength $names]!=[llength $labels]||[llength [lsort -unique $names]]!=[llength $names]} {_error {Implicit identities and units have inconsistent dimensions}}
        foreach id $names unit $labels {
            if {![regexp {^[A-Za-z_][A-Za-z0-9_]{0,63}$} $id]} {_error {Invalid implicit symbol identity}}
            _physicalText $unit implicit_unit 256;if {$unit eq {}} {_error {Implicit symbols require explicit physical units}}
        }
    }
    set unit [dict get $raw residual_unit];_physicalText $unit implicit_residual_unit 256
    if {$unit eq {}} {_error {Implicit residual unit is required}}
    set norm [dict get $raw normalization];_keys $norm {value unit role} implicit_normalization
    if {[dict get $norm role] ne "reference_scale"||[dict get $norm unit] ne $unit||![_finite [dict get $norm value]]||[dict get $norm value]<=0} {_error {Implicit normalization requires its positive physical reference scale}}
    dict set norm value [format %.17g [dict get $norm value]];dict set raw normalization $norm
    set mode [dict get $raw residual_mode]
    if {$mode ni {algebraic normalized_algebraic}} {_error {Unknown implicit residual mode}}
    set rule [expr {$mode eq "algebraic"?"square_residual_unit":"dimensionless"}]
    if {[dict get $raw objective_unit_rule] ne $rule||($mode eq "algebraic"&&[dict get $norm value]!=1)} {_error {Implicit objective units differ from their declared normalization}}
    return $raw
}
proc ::GX::StatisticsV1::_implicitAssumptions {} {
    return {{Residuals are zero minus the declared equation evaluated at the observed coordinate pairs} {Physical reference normalization changes the objective scale and is not a measurement standard uncertainty} {Parameter covariance is local and conditional on the observed coordinates, equation and declared equation-error model} {Algebraic equation residuals are not orthogonal distances or corrections for uncertainty in both coordinates} {No Y(X) or X(Y) response branch is inferred by fitting; explicit checked branch queries are separate} {Ordinary response R squared and likelihood comparisons are not defined by this implicit equation contract}}
}
proc ::GX::StatisticsV1::_implicitContext {summary context} {
    set summary [_implicitSummary $summary]
    foreach {field expected} [list orientation implicit_residual fit_geometry implicit_algebraic x_unit [lindex [dict get $summary predictor_units] 0] y_unit [lindex [dict get $summary predictor_units] 1]] {
        if {[dict exists $context $field]&&[dict get $context $field] ne $expected} {_error "Implicit context conflicts with captured $field"}
        dict set context $field $expected
    }
    if {[_get $context noise_model unspecified] ni {unspecified independent_gaussian_estimated_variance}} {_error {Implicit reference normalization does not establish known measurement-error covariance}}
    foreach field {response_transform smoothing baseline_correction gls} {if {[dict exists $context $field]} {_error {Implicit equation uncertainty requires an explicit compatible preprocessing contract}}}
    dict set context implicit $summary
    foreach assumption [_implicitAssumptions] {if {$assumption ni [_get $context assumptions {}]} {dict lappend context assumptions $assumption}}
    return $context
}
proc ::GX::StatisticsV1::_implicitValidate {modelId context numerical parameters provenance profile} {
    set summary [_implicitSummary [dict get $context implicit]]
    if {$modelId ne "math.numeric.implicit"||$profile ne "nonlinear_regression"||[_get $provenance operation {}] ne "implicit_fit"||[_get $context orientation {}] ne "implicit_residual"||[_get $context fit_geometry {}] ne "implicit_algebraic"} {_error {Implicit equation statistics require their exact registered model, operation and residual geometry}}
    if {[_get $context sample_role training] eq "training"&&[_get $numerical n {}]!=[dict get $summary observation_count]} {_error {Implicit training count differs from its captured coordinate pairs}}
    if {[_get $context weight_semantics {}] ne "relative"||[_get $context covariance_scaling {}] ne "estimated_residual_variance"} {_error {Implicit reference-scaled covariance requires estimated equation-error variance}}
    if {[_get $context noise_model unspecified] ni {unspecified independent_gaussian_estimated_variance}} {_error {Implicit equation inference has no known measurement-sigma contract}}
    if {[dict get $context x_unit] ne [lindex [dict get $summary predictor_units] 0]||[dict get $context y_unit] ne [lindex [dict get $summary predictor_units] 1]} {_error {Implicit coordinate units changed}}
    if {[llength $parameters]!=[llength [dict get $summary parameter_ids]]} {_error {Implicit parameter count changed}}
    foreach p $parameters id [dict get $summary parameter_ids] unit [dict get $summary parameter_units] {
        if {[dict get $p id] ne $id||[dict get $p unit] ne $unit} {_error {Implicit parameter identities or units changed}}
    }
    foreach assumption [_implicitAssumptions] {if {$assumption ni [_get $context assumptions {}]} {_error {Implicit uncertainty qualifications were removed}}}
    if {[_get $context sample_role training] eq "training"&&[_get [_get $provenance observation_signature {}] predictor_count {}]!=2} {_error {Implicit results require the exact two-coordinate observation signature}}
}
proc ::GX::StatisticsV1::_implicitQuantity {quantity item context} {
    set summary [dict get $context implicit]
    if {$quantity eq "sse"} {
        if {[dict get $summary objective_unit_rule] eq "dimensionless"} {dict set item unit [list power 1 2]}
        dict set item label {Equation objective}
        dict set item definition {Sum of squared equation residuals divided by the square of the explicitly declared physical reference normalization; no coordinate projection is performed}
    }
    if {$quantity eq "weighted_residual_standard_deviation"} {
        if {[dict get $summary objective_unit_rule] eq "dimensionless"} {dict set item unit 1}
        dict set item label {Reference-normalized equation residual scale}
    }
    if {$quantity in {covariance standard_errors}} {dict set item definition {Local Gauss-Newton parameter uncertainty conditional on the observed coordinate pairs and declared equation-error model; reference normalization is not measurement sigma}}
    return $item
}
