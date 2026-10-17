# Interpretation of captured surface facts. Numeric owns all computation.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::StatisticsV1::_surfaceSummary {raw} {
    set fields {schema numeric_api operation declaration_sha256 formula_source_sha256 formula_binding_sha256 predictor_ids predictor_units response_id response_unit parameter_ids parameter_units observation_receipt retained_xy_sha256 retained_z_sha256 source_indices_sha256 observation_domain fit_geometry predictor_error_model interpolation_performed uncertainty_scope}
    _keys $raw $fields surface_numeric_summary
    foreach field $fields {if {![dict exists $raw $field]} {_error "Surface summary requires $field"}}
    foreach {field expected} {numeric_api NUMERIC_API_v1 predictor_ids {x y} response_id z fit_geometry vertical_response_z_at_exact_xy predictor_error_model exact_predictors} {
        if {[dict get $raw $field] ne $expected} {_error "Unsupported surface $field"}
    }
    set operation [dict get $raw operation]
    if {$operation eq "surface_fit"} {set schema gxtxt.surface_fit_summary.v1;set scope local_conditional_on_exact_predictors_formula_and_response_noise;set minimum 2
    } elseif {$operation eq "surface_residuals"} {set schema gxtxt.surface_residual_summary.v1;set scope descriptive_evaluation_at_captured_parameters_no_parameter_inference;set minimum 1
    } else {_error {Unknown surface summary operation}}
    if {[dict get $raw schema] ne $schema||[dict get $raw uncertainty_scope] ne $scope} {_error {Surface training and evaluation cannot be interchanged}}
    foreach key {declaration_sha256 formula_source_sha256 formula_binding_sha256 retained_xy_sha256 retained_z_sha256 source_indices_sha256} {
        if {![regexp {^[0-9a-f]{64}$} [dict get $raw $key]]} {_error {Surface input and formula identities must be captured}}
    }
    foreach {ids units lo hi} {predictor_ids predictor_units 2 2 parameter_ids parameter_units 1 32} {
        set names [dict get $raw $ids];set labels [dict get $raw $units]
        if {[llength $names]<$lo||[llength $names]>$hi||[llength $names]!=[llength $labels]||[llength [lsort -unique $names]]!=[llength $names]} {_error {Surface identities and physical units differ in length}}
        foreach id $names unit $labels {
            if {![regexp {^[A-Za-z_][A-Za-z0-9_]{0,63}$} $id]} {_error {Invalid surface symbol identity}}
            _physicalText $unit surface_unit 256;if {$unit eq {}} {_error {Surface symbols require explicit physical units}}
        }
    }
    _physicalText [dict get $raw response_unit] surface_response_unit 256
    if {[dict get $raw response_unit] eq {}} {_error {Surface response unit is required}}
    set receipt [dict get $raw observation_receipt]
    set keys {schema layout original_shape original_count retained_count nonfinite_count nonfinite_policy source_linear_index_base source_linear_order duplicate_policy sorting_performed interpolation_performed original_xy_sha256 original_z_sha256}
    _keys $receipt $keys surface_observations
    foreach key $keys {if {![dict exists $receipt $key]} {_error "Surface observation receipt requires $key"}}
    foreach {key expected} {schema gxtxt.surface_observations.v1 source_linear_order column_major duplicate_policy preserve_observations} {if {[dict get $receipt $key] ne $expected} {_error {Surface observation ordering cannot change}}}
    foreach key {source_linear_index_base sorting_performed interpolation_performed} {
        if {![_finite [dict get $receipt $key]]||[dict get $receipt $key]!=0} {_error {Surface observations cannot be sorted, interpolated or silently reindexed}}
        dict set receipt $key 0
    }
    if {![_finite [dict get $raw interpolation_performed]]||[dict get $raw interpolation_performed]!=0} {_error {Surface fit cannot imply data interpolation}}
    dict set raw interpolation_performed 0
    foreach {key lo} [list original_count $minimum retained_count $minimum nonfinite_count 0] {
        set value [dict get $receipt $key]
        if {![_finite $value]||$value<$lo||$value>65536||$value!=floor($value)} {_error {Invalid captured surface observation count}}
        dict set receipt $key [expr {int($value)}]
    }
    if {[dict get $receipt original_count]!=[dict get $receipt retained_count]+[dict get $receipt nonfinite_count]||[dict get $receipt nonfinite_policy] ni {error omit}||([dict get $receipt nonfinite_count]>0&&[dict get $receipt nonfinite_policy] ne "omit")} {_error {Surface missing-value policy disagrees with captured counts}}
    set shape [dict get $receipt original_shape]
    if {[llength $shape]!=2} {_error {Surface original shape must retain both dimensions}}
    set normalized {}
    foreach size $shape {if {![_finite $size]||$size<1||$size>65536||$size!=floor($size)} {_error {Invalid surface original dimension}};lappend normalized [expr {int($size)}]}
    if {[lindex $shape 0]*[lindex $shape 1]!=[dict get $receipt original_count]||[dict get $receipt layout] ni {points grid_yx}||([dict get $receipt layout] eq "points"&&[lindex $shape 1]!=1)} {_error {Surface original layout or shape changed}}
    dict set receipt original_shape $normalized
    foreach key {original_xy_sha256 original_z_sha256} {if {![regexp {^[0-9a-f]{64}$} [dict get $receipt $key]]} {_error {Original surface coordinates and observations require captured identities}}}
    dict set raw observation_receipt $receipt
    set domain [dict get $raw observation_domain];_keys $domain {bounds meaning} surface_observation_domain
    if {[_get $domain meaning {}] ne "axis_bounds_not_observation_coverage"||[llength [_get $domain bounds {}]]!=2} {_error {Surface domain bounds cannot imply observation coverage}}
    foreach pair [dict get $domain bounds] {if {[llength $pair]!=2||![_finite [lindex $pair 0]]||![_finite [lindex $pair 1]]||[lindex $pair 1]<[lindex $pair 0]} {_error {Invalid surface coordinate bounds}}}
    return $raw
}
proc ::GX::StatisticsV1::_surfaceAssumptions {{operation surface_fit}} {
    set result {{Residuals are observed Z minus the declared response at each exact physical X/Y pair} {Predictor coordinates are treated as exact; parameter uncertainty does not account for X/Y measurement error} {Explicitly omitted nonfinite observations retain original column-major indices; no source cell is interpolated or filled} {Coordinate bounds describe axis extrema and do not establish interior observation coverage} {Sampling a retained surface is model evaluation, not interpolation of missing observations}}
    if {$operation eq "surface_fit"} {lappend result {Parameter covariance and intervals are local and conditional on the formula, exact coordinates and declared response-noise model}
    } else {lappend result {Evaluation uses captured parameters without fitting; residual statistics are descriptive and provide no training degrees of freedom or parameter inference}}
    return $result
}
proc ::GX::StatisticsV1::_surfaceContext {summary context} {
    set summary [_surfaceSummary $summary]
    set role [expr {[dict get $summary operation] eq "surface_fit"?"training":"evaluation"}]
    foreach {key expected} [list orientation z_of_xy fit_geometry vertical_response_z_at_exact_xy sample_role $role x_unit [lindex [dict get $summary predictor_units] 0] y_unit [lindex [dict get $summary predictor_units] 1] z_unit [dict get $summary response_unit]] {
        if {[dict exists $context $key]&&[dict get $context $key] ne $expected} {_error "Surface context conflicts with captured $key"}
        dict set context $key $expected
    }
    foreach field {gls implicit complex smoothing baseline_correction response_transform} {if {[dict exists $context $field]} {_error {Surface interpretation cannot acquire unrelated preprocessing or error geometry}}}
    dict set context surface $summary
    foreach assumption [_surfaceAssumptions [dict get $summary operation]] {if {$assumption ni [_get $context assumptions {}]} {dict lappend context assumptions $assumption}}
    return $context
}
proc ::GX::StatisticsV1::_surfaceValidate {modelId context numerical parameters provenance profile} {
    set summary [_surfaceSummary [dict get $context surface]];set operation [dict get $summary operation]
    set role [expr {$operation eq "surface_fit"?"training":"evaluation"}]
    if {$modelId ne "math.numeric.surface"||$profile ne "nonlinear_regression"||[_get $provenance operation {}] ne $operation||[_get $context orientation {}] ne "z_of_xy"||[_get $context fit_geometry {}] ne "vertical_response_z_at_exact_xy"||[_get $context sample_role training] ne $role} {_error {Surface statistics require their exact registered operation and residual geometry}}
    if {[_get $numerical n {}]!=[dict get $summary observation_receipt retained_count]} {_error {Surface count differs from captured observations}}
    foreach {key expected} [list x_unit [lindex [dict get $summary predictor_units] 0] y_unit [lindex [dict get $summary predictor_units] 1] z_unit [dict get $summary response_unit]] {if {[_get $context $key {}] ne $expected} {_error {Surface coordinate units changed}}}
    if {[llength $parameters]!=[llength [dict get $summary parameter_ids]]} {_error {Surface parameter count changed}}
    foreach parameter $parameters id [dict get $summary parameter_ids] unit [dict get $summary parameter_units] {if {[dict get $parameter id] ne $id||[dict get $parameter unit] ne $unit} {_error {Surface physical parameter identities changed}}}
    foreach key {source_sha256 binding_sha256} {if {[_get $provenance model_$key {}] ne [dict get $summary formula_$key]} {_error {Surface formula identity differs from captured solver model}}}
    if {$role eq "training"} {
        if {[_get [_get $provenance observation_signature {}] predictor_count {}]!=2} {_error {Surface inference requires both predictors in the observation signature}}
    } else {foreach field {rank dof covariance standard_errors reduced_chi_squared} {if {[dict exists $numerical $field]} {_error {Surface evaluation cannot acquire training inference}}}}
    foreach assumption [_surfaceAssumptions $operation] {if {$assumption ni [_get $context assumptions {}]} {_error {Surface interpretation qualifications were removed}}}
}
