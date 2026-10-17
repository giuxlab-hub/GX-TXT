# SPDX-License-Identifier: GPL-3.0-or-later
# Meaning and receipt validation only; Numeric owns every smoothing calculation.
apply {{} {
    variable quantities
    foreach {id label unit definition} {
        smoothing_lambda {Smoothing penalty lambda} cubic_predictor {Physical multiplier of the integrated squared second derivative in the unweighted residual objective}
        smoothing_gcv_score {Generalized cross-validation score} squared_response {Numeric n times residual sum of squares divided by the square of n minus trace(S); undefined at exact interpolation}
        residual_mean_dof {Residual mean trace} count {Trace(I-S), equal to n minus effective model degrees of freedom; not residual-variance degrees of freedom}
        residual_variance_dof {Residual variance degrees of freedom} count {Trace((I-S)^T(I-S)) for fixed lambda and independent equal-variance observations; smoothing bias is excluded}
        smoother_trace_squared {Squared smoother trace} count {Trace(S^T S), distinct from the square of trace(S)}
    } {dict set quantities $id [dict create label $label unit $unit kind scalar policy smoothing_fact definition $definition]}
} ::GX::StatisticsV1}
proc ::GX::StatisticsV1::_smoothingFields {} {return {smoothing_lambda smoothing_lambda gcv_score smoothing_gcv_score edf edf residual_mean_dof residual_mean_dof residual_variance_dof residual_variance_dof smoother_trace_squared smoother_trace_squared}}
proc ::GX::StatisticsV1::_smoothingAssumptions {} {
    return {{Natural cubic smoothing minimizes unweighted squared response residuals plus lambda times integrated squared curvature; lambda has the cube of the predictor unit} {EDF is trace(S). Residual mean trace and residual-variance degrees of freedom have different definitions; retained nodal values are not independent regression parameters} {Residual-variance degrees of freedom condition on fixed lambda and independent equal-variance observations; smoothing bias and uncertainty from data-driven lambda selection are not propagated} {GCV is a predictive selection criterion, not a goodness-of-fit probability or a confidence interval; the bounded search does not certify a global optimum} {Lambda zero interpolates and has undefined GCV; exact knot agreement does not establish scientific model validity}}
}
proc ::GX::StatisticsV1::_smoothingPolicy {quantity profile numerical context} {
    if {$profile ne "smoother"} {return {not_applicable {Quantity belongs to a declared linear smoother}}}
    if {[_get $context sample_role training] ne "training"} {return {not_applicable {Smoother trace and selection facts belong to the original training observations}}}
    if {$quantity eq "smoothing_gcv_score"&&[dict exists $numerical smoothing_lambda]&&[dict get $numerical smoothing_lambda]==0} {return {undefined {Lambda zero interpolates; its GCV ratio is zero divided by zero}}}
    return {value {}}
}
proc ::GX::StatisticsV1::_smoothingAdapt {raw context} {
    set numerical {}
    dict for {field quantity} [_smoothingFields] {if {![dict exists $raw $field]} {_error "Smoother receipt lacks $field"};if {[dict get $raw $field] ne {}} {dict set numerical $quantity [dict get $raw $field]}}
    dict set numerical dof [dict get $raw residual_variance_dof]
    dict set context smoother_dof_convention [dict get $raw smoother_dof_convention]
    foreach assumption [_smoothingAssumptions] {if {[lsearch -exact [_get $context assumptions {}] $assumption]<0} {dict lappend context assumptions $assumption}}
    set receipt [dict create schema gxtxt.smoothing_diagnostics.v1]
    foreach field {solver trace_method precision workspace_bytes_bound smoothing_selection} {dict set receipt $field [dict get $raw $field]}
    return [dict create numerical $numerical context $context receipt $receipt]
}
proc ::GX::StatisticsV1::_validateSmoothing {request} {
    set numerical [dict get $request numerical];set context [dict get $request context]
    if {![dict exists $request provenance smoothing]} return
    set receipt [dict get $request provenance smoothing]
    if {[_get $context sample_role training] ne "training"||[_get $context weight_semantics unweighted] ne "unweighted"} {_error {Captured natural cubic smoothing requires its unweighted training observations}}
    _keys $receipt {schema solver trace_method precision workspace_bytes_bound smoothing_selection} smoothing
    foreach {key expected} {schema gxtxt.smoothing_diagnostics.v1 solver native_banded_ldl_selected_inverse trace_method analytic_differentiated_selected_inverse precision long_double_internal_binary64_result} {if {[_get $receipt $key {}] ne $expected} {_error "Unknown smoothing $key"}}
    foreach key {n smoothing_lambda edf residual_mean_dof residual_variance_dof smoother_trace_squared sse dof} {if {![_finite [_get $numerical $key {}]]||[dict get $numerical $key]<0} {_error "Invalid smoothing fact $key"}}
    set n [dict get $numerical n];set lambda [dict get $numerical smoothing_lambda]
    if {$n<3||$n>1000000||$n!=floor($n)||[dict get $numerical edf]<2||[dict get $numerical edf]>$n||[dict get $numerical residual_mean_dof]>$n-2||[dict get $numerical residual_variance_dof]>$n-2||[dict get $numerical smoother_trace_squared]>$n||[dict get $numerical dof]!=[dict get $numerical residual_variance_dof]} {_error {Smoother dimensions or trace identities are inconsistent}}
    if {[_get $context smoother_dof_convention {}] ne {trace((I-S)^T*(I-S)); fixed lambda, independent equal-variance observations; smoothing bias excluded}} {_error {Smoother residual variance convention changed}}
    foreach assumption [_smoothingAssumptions] {if {[lsearch -exact [_get $context assumptions {}] $assumption]<0} {_error {Smoothing interpretation must retain CORE assumptions}}
    }
    if {$lambda==0} {
        if {[dict get $numerical edf]!=$n||[dict get $numerical residual_mean_dof]!=0||[dict get $numerical residual_variance_dof]!=0||[dict exists $numerical smoothing_gcv_score]} {_error {Interpolating lambda zero must retain unavailable GCV and zero residual traces}}
    } elseif {![_finite [_get $numerical smoothing_gcv_score {}]]||[dict get $numerical smoothing_gcv_score]<0} {_error {Positive smoothing lambda requires a finite nonnegative GCV fact}}
    if {![_finite [_get $receipt workspace_bytes_bound {}]]||[dict get $receipt workspace_bytes_bound]<=0||[dict get $receipt workspace_bytes_bound]>536870912} {_error {Smoothing workspace bound is invalid}}
    set selection [dict get $receipt smoothing_selection];set method [_get $selection method {}]
    _keys $selection {method evaluations criterion selected_lambda selected_edf selected_gcv boundary_optimum lambda_bounds grid_count refinement_budget candidate_columns candidates guarantee} smoothing_selection
    if {[_get $selection criterion {}] ne "gcv_n_rss_over_n_minus_edf_squared"||[_get $selection selected_lambda {}]!=$lambda||[_get $selection selected_edf {}]!=[dict get $numerical edf]} {_error {Smoothing selection differs from the fitted result}}
    if {[_get $selection selected_gcv {}] ne [_get $numerical smoothing_gcv_score {}]} {_error {Selected GCV fact differs from the result}}
    if {![string is boolean -strict [_get $selection boundary_optimum {}]]} {_error {Invalid smoothing boundary flag}}
    if {$method eq "manual"} {
        if {[_get $selection evaluations {}]!=1||[dict get $selection boundary_optimum]} {_error {Invalid manual smoothing receipt}}
        return
    }
    if {$method ne "bounded_log_grid_golden_section"||[dict get $selection candidate_columns] ne {lambda edf sse gcv_score}} {_error {Unsupported GCV selection method or columns}}
    lassign [dict get $selection lambda_bounds] lower upper
    foreach value [list $lower $upper] {if {![_finite $value]||$value<=0} {_error {Invalid GCV bounds}}}
    if {[llength [dict get $selection lambda_bounds]]!=2||$lower>=$upper||$lambda<$lower||$lambda>$upper||[dict get $selection boundary_optimum]!=($lambda==$lower||$lambda==$upper)} {_error {GCV boundary receipt differs from its requested domain}}
    set grid [dict get $selection grid_count];set refine [dict get $selection refinement_budget];set count [dict get $selection evaluations]
    foreach value [list $grid $refine $count] {if {![_finite $value]||$value!=floor($value)} {_error {Invalid GCV evaluation count}}}
    if {$grid<3||$grid>65||$refine<0||$refine>64||$count!=$grid+$refine||[llength [dict get $selection candidates]]!=$count} {_error {GCV search exceeded or contradicted its recorded budget}}
    set matched 0;foreach row [dict get $selection candidates] {
        if {[llength $row]!=4} {_error {GCV candidate row shape changed}}
        lassign $row at edf sse score
        foreach value $row {if {![_finite $value]||$value<0} {_error {Invalid GCV candidate fact}}}
        if {$at<$lower||$at>$upper||$edf<2||$edf>$n||$score<[dict get $numerical smoothing_gcv_score]} {_error {GCV selected candidate is inconsistent with its search receipt}}
        if {$at==$lambda&&$edf==[dict get $numerical edf]&&$sse==[dict get $numerical sse]&&$score==[dict get $numerical smoothing_gcv_score]} {set matched 1}
    }
    if {!$matched} {_error {Selected smoother is absent from its candidate receipt}}
}
