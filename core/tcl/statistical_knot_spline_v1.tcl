# Shared interpretation of captured knot models; no fitting or spline arithmetic.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::StatisticsV1::_knotSplineAssumptions {name} {
    set values {{Exact declared knots and boundary conditions are part of the retained scientific model} {A boundary-polynomial extrapolation requires explicit permission and does not extend the observed support} {Descriptive residuals do not establish parameter covariance, confidence intervals or a likelihood model}}
    if {$name eq "akima"} {lappend values {Akima interpolates the supplied observations with C1 continuity; zero knot residuals do not establish regression quality or uncertainty}
    } else {lappend values {The B-spline is an unweighted fixed-knot least-squares approximation with no roughness penalty; basis dimension is not a validated inferential degrees-of-freedom estimate}}
    return $values
}
proc ::GX::StatisticsV1::_knotSplineSummary {s} {
    set fields {schema numeric_api model method_class degree continuity_order boundary_condition knot_count domain source_count basis_dimension state_sha256 predictor_unit response_unit inference_scope}
    _keys $s $fields knot_summary
    foreach key $fields {if {![dict exists $s $key]} {_error "Knot summary requires $key"}}
    foreach {key expected} {schema gxtxt.knot_spline_summary.v1 numeric_api NUMERIC_API_v1 inference_scope descriptive_no_parameter_inference} {if {[dict get $s $key] ne $expected} {_error "Invalid knot summary $key"}}
    set name [dict get $s model]
    if {$name ni {akima bspline}} {_error {Unknown canonical knot model}}
    foreach {key lo hi} {degree 1 3 continuity_order 0 2 knot_count 2 65536 source_count 2 65536 basis_dimension 1 65536} {
        set v [dict get $s $key];if {![_finite $v]||$v<$lo||$v>$hi||$v!=floor($v)} {_error "Invalid knot fact $key"};dict set s $key [expr {int($v)}]
    }
    set degree [dict get $s degree];set boundary [dict get $s boundary_condition]
    if {$name eq "akima"} {
        if {$degree!=3||[dict get $s continuity_order]!=1||[dict get $s knot_count]!=[dict get $s source_count]||[dict get $s source_count]<5||[dict get $s basis_dimension]!=[dict get $s source_count]||[dict get $s method_class] ne "interpolation"||$boundary ni {extrapolated_slopes clamped}} {_error {Akima interpolation identity changed}}
    } else {
        set dimension [expr {[dict get $s knot_count]-1+$degree}]
        if {$boundary eq "periodic"} {set dimension [expr {[dict get $s knot_count]-1}]} elseif {$boundary in {natural clamped}} {incr dimension -2;if {$degree!=3} {_error {Constrained spline boundary requires cubic degree}}}
        if {[dict get $s knot_count]>257||[dict get $s continuity_order]!=$degree-1||[dict get $s basis_dimension]!=$dimension||[dict get $s method_class] ne "least_squares_approximation"||$boundary ni {free natural clamped periodic}} {_error {Fixed-knot B-spline approximation identity changed}}
    }
    lassign [dict get $s domain] lo hi
    if {[llength [dict get $s domain]]!=2||![_finite $lo]||![_finite $hi]||$lo>=$hi||![regexp {^[0-9a-f]{64}$} [dict get $s state_sha256]]} {_error {Knot domain or retained identity is invalid}}
    foreach key {predictor_unit response_unit} {_physicalText [dict get $s $key] knot_unit 256;if {[dict get $s $key] eq {}} {_error {Knot coordinates require units}}}
    return $s
}
proc ::GX::StatisticsV1::_knotSplineContext {s context} {
    set s [_knotSplineSummary $s];set orientation [_get $context orientation y_of_x]
    if {$orientation ni {y_of_x x_of_y}} {_error {Knot models require a scalar physical response}}
    set x [dict get $s predictor_unit];set y [dict get $s response_unit];if {$orientation eq "x_of_y"} {set x [dict get $s response_unit];set y [dict get $s predictor_unit]}
    foreach {key value} [list orientation $orientation x_unit $x y_unit $y fit_geometry vertical_response weight_semantics unweighted] {
        if {[dict exists $context $key]&&[dict get $context $key] ne $value} {_error "Knot model conflicts with captured $key"};dict set context $key $value
    }
    if {[dict exists $context knot_spline]&&[dict get $context knot_spline] ne $s} {_error {Knot facts cannot be replaced by the consumer}}
    dict set context knot_spline $s
    foreach a [_knotSplineAssumptions [dict get $s model]] {if {$a ni [_get $context assumptions {}]} {dict lappend context assumptions $a}}
    return $context
}
proc ::GX::StatisticsV1::_knotSplineValidate {id context numerical parameters provenance profile} {
    set s [_knotSplineSummary [dict get $context knot_spline]];set name [dict get $s model]
    set wanted [expr {$name eq "akima"?"interpolation":"smoother"}]
    if {$id ne "math.numeric.$name"||$profile ne $wanted||[llength $parameters]||[_get $provenance operation {}] ni {curve_model_fit residual_metrics}} {_error {Knot semantics require their actual registered model and operation}}
    set role [_get $context sample_role training];set operation [dict get $provenance operation]
    if {($operation eq "curve_model_fit"&&$role ne "training")||($operation eq "residual_metrics"&&$role ne "evaluation")} {_error {Knot interpretation must distinguish construction from source evaluation}}
    foreach key {rank dof covariance standard_errors reduced_chi_squared edf residual_variance_dof} {if {[dict exists $numerical $key]} {_error {Descriptive knot models cannot acquire unvalidated parameter inference}}}
    if {[_get $context sample_role training] eq "training"&&[_get $numerical n {}]!=[dict get $s source_count]} {_error {Knot training count changed}}
    set expected [_knotSplineContext $s [dict remove $context knot_spline assumptions]]
    foreach key {orientation x_unit y_unit fit_geometry weight_semantics} {if {[_get $context $key {}] ne [dict get $expected $key]} {_error {Physical knot coordinate meaning changed}}}
    foreach a [_knotSplineAssumptions $name] {if {$a ni [_get $context assumptions {}]} {_error {Knot interpretation qualifications were removed}}}
}
