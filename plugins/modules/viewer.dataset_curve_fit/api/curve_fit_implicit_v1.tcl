# Implicit declaration/branch data adapter; Numeric and CORE own science.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_formulaEditorUnits {w kind} {
    variable state
    if {$kind in {formula rational}} {return [_componentUnits $w $state($w,orientation)]}
    if {$kind eq "complex_response"} {
        if {$state($w,orientation) ne "y_of_x"} {error {Complex responses require physical frequency on X}}
        set axes [dict get [_sourceProvenance $w] source_axes]
        return [dict create x_unit [dict get $axes x unit] y_unit [dict get $axes y unit]]
    }
    if {$kind ne "implicit"||$state($w,orientation) ni {y_of_x x_of_y}} {error {Implicit equations require a declared Y(X) or X(Y) response branch}}
    set axes [dict get [_sourceProvenance $w] source_axes]
    return [dict create x_unit [dict get $axes x unit] y_unit [dict get $axes y unit]]
}
proc ::GX::DatasetCurveFit::_implicitSettings {w} {_formulaSettings $w implicit}
proc ::GX::DatasetCurveFit::_implicitEditorControls {w d body} {
    variable state
    set recipe $state($w,implicitRecipe);set branch $state($w,implicitBranch)
    $body.help configure -text "The equation is f(x,y,p)=0. x and y retain physical X ([dict get $state($d,units) x_unit]) and Y ([dict get $state($d,units) y_unit]). Equation residuals are not vertical errors or ODR distances. Reference normalization is not measurement sigma. Declare one continuous response branch; local checks do not prove global uniqueness."
    set state($d,residualUnit) [::GX::datasetPublicationV2DictDefault [::GX::datasetPublicationV2DictDefault $recipe formula {}] response_unit [dict get $state($d,units) y_unit]]
    set state($d,residualMode) [::GX::datasetPublicationV2DictDefault $recipe residual_mode normalized_algebraic]
    set state($d,referenceScale) [::GX::datasetPublicationV2DictDefault [::GX::datasetPublicationV2DictDefault $recipe normalization {}] value 1]
    lassign [::GX::datasetPublicationV2DictDefault $branch bracket {-1 1}] state($d,responseLow) state($d,responseHigh)
    lassign [::GX::datasetPublicationV2DictDefault $branch independent_domain {0 1}] state($d,domainLow) state($d,domainHigh)
    set state($d,continuous) [::GX::datasetPublicationV2DictDefault $branch continuous_branch_declared 0]
    ttk::frame $body.implicit;pack $body.implicit -fill x -padx 8 -pady 6
    set row 0
    foreach {field label} {residualUnit {Equation residual unit} residualMode {Equation residual mode} referenceScale {Physical reference value in equation units} responseLow {Response bracket minimum} responseHigh {Response bracket maximum} domainLow {Independent domain minimum} domainHigh {Independent domain maximum}} {
        ttk::label $body.implicit.l_$field -text $label
        if {$field eq "residualMode"} {ttk::combobox $body.implicit.$field -state readonly -values {algebraic normalized_algebraic} -textvariable ::GX::DatasetCurveFit::state($d,$field)} else {ttk::entry $body.implicit.$field -textvariable ::GX::DatasetCurveFit::state($d,$field)}
        grid $body.implicit.l_$field -row $row -column 0 -sticky w -padx 4 -pady 2;grid $body.implicit.$field -row $row -column 1 -sticky ew -padx 4 -pady 2;incr row
    }
    grid columnconfigure $body.implicit 1 -weight 1
    ttk::checkbutton $body.implicit.continuous -text {I declare a continuous response branch in this bracket and domain} -variable ::GX::DatasetCurveFit::state($d,continuous)
    grid $body.implicit.continuous -row $row -columnspan 2 -sticky w -padx 4 -pady 6
    wm geometry $d 900x720
}
proc ::GX::DatasetCurveFit::_implicitEditorRecipe {w d} {
    variable state
    set recipe [dict create formula [_formulaRead $w $d] residual_mode $state($d,residualMode)]
    if {$state($d,residualMode) eq "normalized_algebraic"} {dict set recipe normalization [dict create value [_finite $state($d,referenceScale) {Physical reference normalization}] unit [string trim $state($d,residualUnit)] role reference_scale]}
    return $recipe
}
proc ::GX::DatasetCurveFit::_implicitEditorBranch {w d} {
    variable state
    set branch [dict create response_index [expr {$state($w,orientation) eq "y_of_x"?2:1}] bracket [list $state($d,responseLow) $state($d,responseHigh)] independent_domain [list $state($d,domainLow) $state($d,domainHigh)] continuous_branch_declared $state($d,continuous)]
    _implicitBranchNode $branch $state($w,orientation)
    return $branch
}
proc ::GX::DatasetCurveFit::_implicitRecipeNode {recipe} {
    foreach key [dict keys $recipe] {if {$key ni {formula residual_mode normalization}} {error "Unknown implicit recipe field: $key"}}
    set fields [dict create formula [_formulaRecipeNode [dict get $recipe formula]] residual_mode [::GX::ScientificTransportv1::text [dict get $recipe residual_mode]]]
    if {[dict exists $recipe normalization]} {
        set norm [dict get $recipe normalization];set nodes {}
        foreach key [dict keys $norm] {if {$key ni {value unit role}} {error "Unknown implicit normalization field: $key"}}
        foreach key {unit role} {dict set nodes $key [::GX::ScientificTransportv1::text [dict get $norm $key]]}
        dict set nodes value [::GX::ScientificTransportv1::array {1 1} [list [dict get $norm value]]]
        dict set fields normalization [::GX::ScientificTransportv1::struct $nodes]
    }
    return [::GX::ScientificTransportv1::struct $fields]
}
proc ::GX::DatasetCurveFit::_implicitBranchNode {branch orientation} {
    set allowed {response_index bracket continuous_branch_declared independent_domain x_tolerance response_tolerance max_iterations}
    foreach key [dict keys $branch] {if {$key ni $allowed} {error "Unknown implicit branch field: $key"}}
    set response [expr {$orientation eq "y_of_x"?2:1}]
    if {$orientation ni {y_of_x x_of_y}||[dict get $branch response_index]!=$response||![string is boolean -strict [dict get $branch continuous_branch_declared]]||![dict get $branch continuous_branch_declared]} {error {Declare a continuous implicit branch matching the selected response orientation}}
    set fields {}
    dict for {key value} $branch {
        if {$key eq "continuous_branch_declared"} {set value [expr {!!$value}]}
        foreach number $value {_finite $number "Implicit branch $key"}
        if {$key in {bracket independent_domain}} {
            if {[llength $value]!=2||[lindex $value 0]>=[lindex $value 1]} {error {Implicit branch intervals need two increasing physical values}}
        } elseif {[llength $value]!=1} {error "Implicit branch $key must be scalar"}
        if {$key in {x_tolerance response_tolerance}&&$value<=0} {error {Implicit root tolerances must be positive}}
        if {$key eq "max_iterations"&&(![string is integer -strict $value]||$value<1||$value>256)} {error {Implicit root budget must be1–256 iterations}}
        dict set fields $key [::GX::ScientificTransportv1::array [list [llength $value] 1] $value]
    }
    foreach key {response_index bracket continuous_branch_declared independent_domain} {if {![dict exists $fields $key]} {error "Implicit branch requires $key"}}
    return [::GX::ScientificTransportv1::struct $fields]
}
proc ::GX::DatasetCurveFit::_implicitCheckAxes {recipe axes} {
    set formula [dict get $recipe formula]
    if {[dict get $formula predictor_ids] ne {x y}||[dict get $formula predictor_units] ne [list [dict get $axes x unit] [dict get $axes y unit]]} {error {Implicit predictors x and y must retain the actual physical X/Y axis units}}
}
proc ::GX::DatasetCurveFit::_resolveImplicit {recipe} {
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    return [::GX::NumericAPIv1::callOperation implicit_model_compose [list [_implicitRecipeNode $recipe]]]
}
proc ::GX::DatasetCurveFit::_prepareImplicit {w options} {
    set source [_sourceProvenance $w]
    set recipe [dict get $options implicit_recipe];set orientation [_fitOrientation implicit $options]
    _implicitCheckAxes $recipe [dict get $source source_axes]
    _implicitBranchNode [dict get $options implicit_branch] $orientation
    if {[_smoothContext $source] ne {}||[_baselineContext $source] ne {}||[_logContext $source $orientation] ne {}} {error {Implicit equation uncertainty requires untransformed observations; smoothing, estimated baselines and log response are unsupported}}
    foreach axis {u v} {
        set translation [::GX::datasetPublicationV2DictDefault $options translation_$axis {mode off delta 0}]
        if {[dict get $translation mode] ne "off"||[dict get $translation delta]!=0} {error {Implicit models require physical coordinates with translation off}}
    }
    if {[dict get [_measurementOptions $options] kind] ne "none"||[::GX::datasetPublicationV2DictDefault $options covariance {}] ne {}} {error {Algebraic implicit residuals do not accept measurement sigma, precision, XY uncertainty or full covariance}}
    if {[::GX::datasetPublicationV2DictDefault $options noise_model unspecified] ni {unspecified independent_gaussian_estimated_variance}} {error {Implicit normalization is a reference scale, not known measurement sigma}}
    if {[::GX::datasetPublicationV2DictDefault $options prediction_band none] ne "none"||[::GX::datasetPublicationV2DictDefault $options bootstrap {}] ne {}||[::GX::datasetPublicationV2DictDefault $options influence_diagnostics 0]} {error {Implicit response bands, parameter bootstrap and linear influence require separate inference contracts}}
    set policy [::GX::datasetPublicationV2DictDefault $options solver_options {}]
    if {[::GX::datasetPublicationV2DictDefault $policy multistart_mode single] ne "single"} {error {Implicit fitting currently uses one explicitly declared bounded solver start}}
    return [_resolveImplicit $recipe]
}
proc ::GX::DatasetCurveFit::_implicitSavedNode {p} {
    _validateImplicitMetadata $p
    set model [dict get $p numeric_model_state];set summary [dict get $p statistical_results training context implicit]
    set fields [dict create schema [::GX::ScientificTransportv1::text gxtxt.implicit_branch_model.v1] kind [::GX::ScientificTransportv1::text implicit_branch] recipe [_implicitRecipeNode [dict get $p options implicit_recipe]] branch [_implicitBranchNode [dict get $p options implicit_branch] [dict get $p orientation]] parameters [::GX::ScientificTransportv1::array [list [llength [dict get $model parameters]] 1] [dict get $model parameters]]]
    foreach key {declaration_sha256 equation_source_sha256 equation_binding_sha256} {dict set fields $key [::GX::ScientificTransportv1::text [dict get $summary $key]]}
    return [::GX::ScientificTransportv1::struct $fields]
}
proc ::GX::DatasetCurveFit::_validateImplicitMetadata {p} {
    if {[dict get $p model] ne "implicit"} return
    set model [dict get $p numeric_model_state];set summary [dict get $p statistical_results training context implicit]
    foreach {field source} {source_sha256 equation_source_sha256 binding_sha256 equation_binding_sha256} {if {[dict get $model $field] ne [dict get $summary $source]} {error {Implicit equation identity differs from its statistical interpretation}}}
    set recipe [dict get $p options implicit_recipe]
    if {[dict get $model formula_declaration recipe] ne [dict get $recipe formula]} {error {Implicit formula recipe differs from the frozen physical equation}}
    if {[dict get $recipe residual_mode] ne [dict get $summary residual_mode]} {error {Implicit residual mode changed}}
    if {[dict get $recipe residual_mode] eq "algebraic"&&[dict exists $recipe normalization]} {error {Algebraic implicit residuals cannot acquire an undeclared normalization}}
    if {[dict get $recipe residual_mode] eq "normalized_algebraic"} {
        set norm [dict get $recipe normalization];set saved [dict get $summary normalization]
        if {[dict get $norm value]!=[dict get $saved value]||[dict get $norm unit] ne [dict get $saved unit]||[dict get $norm role] ne [dict get $saved role]} {error {Implicit physical normalization changed}}
    }
    _implicitBranchNode [dict get $p options implicit_branch] [dict get $p orientation]
    foreach axis {u v} {if {[dict get $p translation $axis delta]!=0||[dict get $p translation $axis mode] ne "off"} {error {Implicit coordinates lost their physical frame}}}
}
