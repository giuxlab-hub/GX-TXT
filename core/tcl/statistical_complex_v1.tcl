# Captured complex-response interpretation. Numeric owns all calculations.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::StatisticsV1::_complexSummary {raw} {
    set fields {schema numeric_api operation declaration_sha256 parameter_ids parameter_units channel_ids channel_units component_ids component_units component_order predictor_id predictor_unit observation_rows response_count residual_component_count covariance_semantics covariance_layout covariance_sha256 effective_covariance_sha256 whitening independence objective phase_policy physical_predictor_sha256 physical_observation_sha256 normalized_formula_source_sha256 normalized_formula_binding_sha256 regularization uncertainty_scope}
    _keys $raw $fields complex_numeric_summary
    foreach field $fields {if {![dict exists $raw $field]} {_error "Complex summary requires $field"}}
    foreach {field expected} {
        numeric_api NUMERIC_API_v1
        component_order channel_interleaved_real_imaginary covariance_semantics absolute
        whitening lower_cholesky_per_observation independence independent_observation_rows_correlated_response_components
        objective cartesian_mahalanobis phase_policy wrapped_principal_radians_diagnostic_only_zero_magnitude_unavailable
        regularization none
    } {if {[dict get $raw $field] ne $expected} {_error "Unsupported complex summary $field"}}
    set operation [dict get $raw operation]
    if {$operation eq "complex_fit"} {
        set schema gxtxt.complex_fit_summary.v1;set scope local_conditional_on_predictors_model_and_absolute_cartesian_covariance;set minimum 2
    } elseif {$operation eq "complex_residuals"} {
        set schema gxtxt.complex_residual_summary.v1;set scope descriptive_evaluation_at_captured_parameters_no_parameter_inference;set minimum 1
    } else {_error {Unknown complex summary operation}}
    if {[dict get $raw schema] ne $schema||[dict get $raw uncertainty_scope] ne $scope} {_error {Complex fit and evaluation semantics cannot be interchanged}}
    if {[dict get $raw covariance_layout] ni {shared per_observation}} {_error {Unknown complex covariance layout}}
    foreach field {declaration_sha256 covariance_sha256 effective_covariance_sha256 physical_predictor_sha256 physical_observation_sha256 normalized_formula_source_sha256 normalized_formula_binding_sha256} {
        if {![regexp {^[0-9a-f]{64}$} [dict get $raw $field]]} {_error {Complex fitting requires exact equation and input identities}}
    }
    foreach {field lo hi} [list observation_rows $minimum 65536 response_count 2 6 residual_component_count [expr {2*$minimum}] 393216] {
        set value [dict get $raw $field]
        if {![_finite $value]||$value!=floor($value)||$value<$lo||$value>$hi} {_error "Invalid captured complex $field"}
        dict set raw $field [expr {int($value)}]
    }
    foreach {ids units minimum maximum} {parameter_ids parameter_units 1 32 channel_ids channel_units 1 3 component_ids component_units 2 6} {
        set names [dict get $raw $ids];set labels [dict get $raw $units]
        if {[llength $names]<$minimum||[llength $names]>$maximum||[llength $names]!=[llength $labels]||[llength [lsort -unique $names]]!=[llength $names]} {_error {Complex identities and units disagree}}
        foreach id $names unit $labels {
            if {![regexp {^[A-Za-z_][A-Za-z0-9_]{0,74}$} $id]} {_error {Invalid complex identity}}
            _physicalText $unit complex_unit 256;if {$unit eq {}} {_error {Complex symbols require physical units}}
        }
    }
    set components {};set units {}
    foreach id [dict get $raw channel_ids] unit [dict get $raw channel_units] {lappend components ${id}_real ${id}_imaginary;lappend units $unit $unit}
    set m [dict get $raw response_count]
    if {$components ne [dict get $raw component_ids]||$units ne [dict get $raw component_units]||$m!=[llength $components]||[dict get $raw residual_component_count]!=[dict get $raw observation_rows]*$m} {_error {Complex component ordering or counts changed}}
    if {![regexp {^[A-Za-z_][A-Za-z0-9_]{0,63}$} [dict get $raw predictor_id]]} {_error {Invalid complex predictor identity}}
    _physicalText [dict get $raw predictor_unit] complex_predictor_unit 256
    if {[dict get $raw predictor_unit] eq {}} {_error {Complex predictor unit is required}}
    return $raw
}
proc ::GX::StatisticsV1::_complexAssumptions {{operation complex_fit}} {
    set assumptions {{The objective is the Cartesian real/imaginary Mahalanobis distance using the declared absolute response covariance} {Response components may be correlated within an observed frequency row; distinct rows are assumed independent} {Residual components are lower-Cholesky innovations in captured physical channel order; no jitter or covariance regularization is applied} {Phase residuals are wrapped principal radians for diagnostics only; zero-amplitude phase is unavailable and phase is not added to magnitude in the objective} {Polar observation conversion does not transform or estimate covariance; a Cartesian measurement covariance must be supplied explicitly}}
    if {$operation eq "complex_residuals"} {set qualification {Evaluation uses captured parameters without fitting; normalized residual RMSE is descriptive and no training DOF, parameter covariance or inference is established}} else {set qualification {Parameter covariance and Gaussian intervals are local linearizations conditional on the model, fixed predictors and supplied Cartesian covariance}}
    return [linsert $assumptions 4 $qualification]
}
proc ::GX::StatisticsV1::_complexContext {summary context} {
    set summary [_complexSummary $summary]
    if {[dict get $summary operation] eq "complex_residuals"} {
        if {[dict exists $context sample_role]&&[dict get $context sample_role] ne "evaluation"} {_error {Complex residual diagnostics require evaluation sample role}}
        dict set context sample_role evaluation
    }
    foreach {field expected} [list orientation joint_responses fit_geometry vertical_response x_unit [dict get $summary predictor_unit] y_unit 1] {
        if {[dict exists $context $field]&&[dict get $context $field] ne $expected} {_error "Complex context conflicts with captured $field"}
        dict set context $field $expected
    }
    foreach field {gls implicit smoothing baseline_correction response_transform} {if {[dict exists $context $field]} {_error {Complex response covariance cannot acquire an unrelated preprocessing or inference contract}}}
    dict set context complex $summary
    foreach assumption [_complexAssumptions [dict get $summary operation]] {if {$assumption ni [_get $context assumptions {}]} {dict lappend context assumptions $assumption}}
    return $context
}
proc ::GX::StatisticsV1::_complexValidate {modelId context numerical parameters provenance profile} {
    set summary [_complexSummary [dict get $context complex]]
    set operation [dict get $summary operation];set role [expr {$operation eq "complex_fit"?"training":"evaluation"}]
    if {$modelId ne "math.numeric.complex_response"||$profile ne "nonlinear_regression"||[_get $provenance operation {}] ne $operation||[_get $context orientation {}] ne "joint_responses"||[_get $context fit_geometry {}] ne "vertical_response"||[_get $context sample_role training] ne $role} {_error {Complex statistics require their registered operation, sample role and Cartesian metric}}
    if {$operation eq "complex_residuals"} {foreach field {rank dof covariance standard_errors reduced_chi_squared} {if {[dict exists $numerical $field]} {_error {Complex evaluation cannot acquire training inference facts}}}}
    if {[_get $numerical n {}]!=[dict get $summary residual_component_count]} {_error {Complex residual count differs from the captured observation rows and channels}}
    if {[_get $context weight_semantics {}] ne "inverse_variance"||[_get $context covariance_scaling {}] ne "absolute_measurement_variance"||[_get $context noise_model unspecified] ni {unspecified independent_gaussian_known_sigma}} {_error {Complex inference requires its captured absolute Cartesian covariance and declared innovation noise model}}
    if {[_get $context x_unit {}] ne [dict get $summary predictor_unit]||[_get $context y_unit {}] ne "1"} {_error {Complex predictor or normalized residual unit changed}}
    if {[llength $parameters]!=[llength [dict get $summary parameter_ids]]} {_error {Complex parameter count changed}}
    foreach p $parameters id [dict get $summary parameter_ids] unit [dict get $summary parameter_units] {if {[dict get $p id] ne $id||[dict get $p unit] ne $unit} {_error {Complex physical parameter identity changed}}}
    foreach assumption [_complexAssumptions $operation] {if {$assumption ni [_get $context assumptions {}]} {_error {Complex uncertainty qualifications were removed}}}
}
proc ::GX::StatisticsV1::_complexQuantity {quantity item} {
    if {$quantity eq "n"} {dict set item label {Real residual components};dict set item definition {Observed frequency rows times twice the number of complex channels}}
    if {$quantity eq "sse"} {dict set item label {Cartesian covariance objective};dict set item unit [list power 1 2];dict set item definition {Sum of squared lower-Cholesky normalized real/imaginary residual components using the declared absolute covariance}}
    if {$quantity in {covariance standard_errors}} {dict set item definition {Local physical parameter covariance conditional on the fixed frequencies and absolute Cartesian response covariance}}
    return $item
}
