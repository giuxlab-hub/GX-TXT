# Safe formula controls and data transport; CORE/Numeric own parsing and units.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_formulaRecipeNode {recipe} {
    set fields {}
    foreach key [dict keys $recipe] {if {$key ni {expression predictor_ids predictor_units response_unit parameters}} {error "Unknown formula recipe field: $key"}}
    foreach key {expression response_unit} {dict set fields $key [::GX::ScientificTransportv1::text [dict get $recipe $key]]}
    foreach key {predictor_ids predictor_units} {
        set items {};foreach value [dict get $recipe $key] {lappend items [::GX::ScientificTransportv1::text $value]}
        dict set fields $key [dict create kind cell items $items]
    }
    set items {}
    foreach parameter [dict get $recipe parameters] {
        set item {}
        dict for {key value} $parameter {
            if {$key in {id unit}} {set node [::GX::ScientificTransportv1::text $value]} elseif {$key in {initial lower upper fixed}} {
                set node [::GX::ScientificTransportv1::array {1 1} [list $value]]
            } else {error "Unknown formula parameter field: $key"}
            dict set item $key $node
        }
        lappend items [::GX::ScientificTransportv1::struct $item]
    }
    dict set fields parameters [dict create kind cell items $items]
    return [::GX::ScientificTransportv1::struct $fields]
}
proc ::GX::DatasetCurveFit::_resolveFormula {recipe} {
    if {[dict get $recipe predictor_ids] ne {x}||[llength [dict get $recipe predictor_units]]!=1} {error {Fitter formulas require one predictor named x; it denotes the independent axis for the chosen orientation}}
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    return [::GX::NumericAPIv1::callOperation fit_formula_compose [list [_formulaRecipeNode $recipe]]]
}
proc ::GX::DatasetCurveFit::_formulaCheckAxes {recipe axes orientation} {
    if {$orientation ni {y_of_x x_of_y}} {error {Formula fitting supports Y=f(X) or X=f(Y)}}
    set independent x;set response y
    if {$orientation eq "x_of_y"} {set independent y;set response x}
    if {[dict get $recipe predictor_units] ne [list [dict get $axes $independent unit]]||[dict get $recipe response_unit] ne [dict get $axes $response unit]} {error {Formula units differ from the current axes; review formula settings or explicitly convert the source units}}
}
proc ::GX::DatasetCurveFit::_prepareFormula {w options} {
    if {![dict exists $options formula_recipe]} {error {Configure the formula first}}
    set recipe [dict get $options formula_recipe]
    _formulaCheckAxes $recipe [dict get [_sourceProvenance $w] source_axes] [::GX::datasetPublicationV2DictDefault $options orientation y_of_x]
    return [_resolveFormula $recipe]
}
proc ::GX::DatasetCurveFit::_formulaSettings {w {kind formula}} {
    variable state
    _assertLoaded $w
    set units [_formulaEditorUnits $w $kind]
    set d $w.$kind
    if {[winfo exists $d]} {raise $d;return}
    set state($d,kind) $kind
    set state($d,owner) $state($w,activeSource);set state($d,orientation) $state($w,orientation)
    set state($d,units) $units;set state($d,rows) {};set state($d,serial) 0
    set recipe $state($w,formulaRecipe);set expression {a*x+b}
    if {$kind eq "implicit"} {set recipe [::GX::datasetPublicationV2DictDefault $state($w,implicitRecipe) formula {}];set expression {y-(a*x+b)}}
    if {$kind eq "rational"} {set recipe $state($w,rationalRecipe)}
    if {$kind eq "complex_response"} {set recipe $state($w,complexRecipe)}
    set state($d,expression) [::GX::datasetPublicationV2DictDefault $recipe expression $expression]
    set state($d,status) {Enter parameter units, or leave them blank for uniquely inferred canonical units. Initial values and bounds use those units.}
    toplevel $d;wm title $d [dict get {formula {Safe fit formula} rational {Physical rational / Padé model} implicit {Implicit equation and response branch} complex_response {Joint complex response model}} $kind];wm transient $d $w
    wm geometry $d 900x520;wm minsize $d 700 400
    ttk::frame $d.actions -padding 8;pack $d.actions -side bottom -fill x
    foreach {id label action} {validate {Validate units and formula} _formulaValidate apply {Apply formula} _formulaApply} {
        ttk::button $d.actions.$id -text $label -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::$action $w $d]]
        pack $d.actions.$id -side left -padx 4
    }
    ttk::button $d.actions.cancel -text Cancel -command [list destroy $d];pack $d.actions.cancel -side right
    set body [::GX::scrollableDialogBody $d]
    ttk::label $body.help -text "x is the independent axis ([dict get $units x_unit]); the formula returns [dict get $units y_unit]. Use physical coordinates with zero translation. The existing native expression engine supplies analytic derivatives within each function's domain." -wraplength 820 -justify left
    pack $body.help -fill x -padx 8 -pady 8
    ttk::entry $body.expression -textvariable ::GX::DatasetCurveFit::state($d,expression)
    pack $body.expression -fill x -padx 8 -pady 6
    if {$kind eq "rational"} {_rationalEditorControls $w $d $body}
    if {$kind eq "implicit"} {_implicitEditorControls $w $d $body}
    if {$kind eq "complex_response"} {_complexEditorControls $w $d $body;$d.actions.validate configure -text {Validate complex model};$d.actions.apply configure -text {Apply complex model}}
    ttk::frame $body.parameters;pack $body.parameters -fill x -padx 8
    set column 0
    foreach label {Parameter Unit Initial Lower Upper Fixed {}} {ttk::label $body.parameters.h$column -text $label;grid $body.parameters.h$column -row 0 -column $column -sticky w -padx 3;incr column}
    set state($d,body) $body
    if {$recipe eq {}} {set parameters [list [dict create id a initial 1] [dict create id b initial 0]]} else {set parameters [dict get $recipe parameters]}
    foreach parameter $parameters {_formulaAdd $d $parameter}
    ttk::button $body.add -text {Add parameter} -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_formulaAddRow $w $d]]
    pack $body.add -anchor w -padx 8 -pady 6
    if {$kind eq "rational"} {pack forget $body.add;_rationalEditorDegrees $w $d}
    ttk::label $body.status -textvariable ::GX::DatasetCurveFit::state($d,status) -wraplength 820 -justify left
    pack $body.status -fill x -padx 8 -pady 8
    bind $d.viewport.canvas <Configure> +[list ::GX::DatasetCurveFit::_formulaLayout $d %w]
}
proc ::GX::DatasetCurveFit::_formulaLayout {d width} {
    variable state
    if {![info exists state($d,body)]} return
    foreach name {help status} {$state($d,body).$name configure -wraplength [expr {max(250,$width-35)}]}
}
proc ::GX::DatasetCurveFit::_formulaAddRow {w d} {_formulaAdd $d [dict create id {} initial 1]}
proc ::GX::DatasetCurveFit::_formulaAdd {d parameter} {
    variable state
    if {[llength $state($d,rows)]>=128} {error {At most 128 formula parameters are supported}}
    set row [incr state($d,serial)];lappend state($d,rows) $row
    set parent $state($d,body).parameters;set column 0
    foreach field {id unit initial lower upper fixed} {
        set default {};if {$field eq "fixed"} {set default 0}
        set state($d,$row,$field) [::GX::datasetPublicationV2DictDefault $parameter $field $default]
        set widget $parent.${field}$row
        if {$field eq "fixed"} {ttk::checkbutton $widget -variable ::GX::DatasetCurveFit::state($d,$row,$field)} else {ttk::entry $widget -width 12 -textvariable ::GX::DatasetCurveFit::state($d,$row,$field)}
        grid $widget -row $row -column $column -sticky ew -padx 3 -pady 4;grid columnconfigure $parent $column -weight 1;incr column
    }
    ttk::button $parent.remove$row -text Remove -command [list ::GX::DatasetCurveFit::_formulaRemove $d $row]
    grid $parent.remove$row -row $row -column 6 -padx 3
}
proc ::GX::DatasetCurveFit::_formulaRemove {d row} {
    variable state
    set index [lsearch -exact $state($d,rows) $row];if {$index<0} return
    set state($d,rows) [lreplace $state($d,rows) $index $index]
    foreach field {id unit initial lower upper fixed remove} {destroy $state($d,body).parameters.${field}$row}
}
proc ::GX::DatasetCurveFit::_formulaRead {w d} {
    variable state
    _assertLoaded $w
    if {$state($d,owner) ne $state($w,activeSource)||$state($d,orientation) ne $state($w,orientation)||$state($d,units) ne [_formulaEditorUnits $w $state($d,kind)]} {error {Source, units or orientation changed; reopen formula settings}}
    set recipe [dict create expression [string trim $state($d,expression)] predictor_ids x predictor_units [list [dict get $state($d,units) x_unit]] response_unit [dict get $state($d,units) y_unit]]
    if {$state($d,kind) eq "implicit"} {
        dict set recipe predictor_ids {x y};dict set recipe predictor_units [list [dict get $state($d,units) x_unit] [dict get $state($d,units) y_unit]]
        dict set recipe response_unit [string trim $state($d,residualUnit)]
    }
    set parameters {}
    foreach row $state($d,rows) {
        set item [dict create id [string trim $state($d,$row,id)] unit [string trim $state($d,$row,unit)] initial [_finite $state($d,$row,initial) {Formula initial value}] fixed $state($d,$row,fixed)]
        foreach field {lower upper} {
            set value [string trim $state($d,$row,$field)];if {$value eq {}} continue
            if {!($field eq "lower"&&$value eq "-Inf"||$field eq "upper"&&$value in {Inf +Inf})} {_finite $value "Formula $field bound"}
            dict set item $field $value
        }
        lappend parameters $item
    }
    dict set recipe parameters $parameters
    return $recipe
}
proc ::GX::DatasetCurveFit::_formulaValidate {w d} {
    variable state
    if {$state($d,kind) eq "rational"} {
        set recipe [_rationalEditorRecipe $w $d];set model [_resolveRational $recipe]
        set receipt [::GX::NumericAPIv1::callOperation rational_domain [list [_rationalRecipeNode $recipe] [::GX::ScientificTransportv1::array {1 2} [dict get $recipe domain]]]]
        if {[dict get $receipt status] ne "safe"} {error "Initial rational denominator is [dict get $receipt status]: [dict get $receipt reason]. Review the coefficients or declared domain."}
    } elseif {$state($d,kind) eq "complex_response"} {set model [_complexEditorValidate $w $d]} elseif {$state($d,kind) eq "implicit"} {set model [_resolveImplicit [_implicitEditorRecipe $w $d]];_implicitEditorBranch $w $d} else {set model [_resolveFormula [_formulaRead $w $d]]}
    set labels {}
    foreach row $state($d,rows) id [dict get $model parameter_ids] unit [dict get $model parameter_units] {
        lappend labels "$id: $unit"
    }
    set state($d,status) "Valid formula. Parameter units: [join $labels {; }]. Initial values and bounds use these units. Analytic derivatives use the existing native expression engine; nonsmooth points and invalid domains can make fitting or uncertainty unavailable."
    if {$state($d,kind) eq "rational"} {append state($d,status) " Whole declared interval: denominator separated from zero; no factor cancellation."}
    return $model
}
proc ::GX::DatasetCurveFit::_formulaApply {w d} {
    variable state
    set model [_formulaValidate $w $d]
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    if {$state($d,kind) eq "rational"} {
        set state($w,rationalRecipe) [dict get $model recipe];set state($w,rationalExtrapolation) $state($d,rationalExtrapolation);set state($w,model) rational
        foreach axis {U V} {set state($w,translation${axis}Mode) off;set state($w,translation${axis}Delta) 0}
    } elseif {$state($d,kind) eq "complex_response"} {
        set state($w,complexRecipe) [dict get $model recipe];set state($w,complexData) [_complexEditorData $w $d]
        set state($w,model) complex_response;set state($w,orientation) y_of_x
        set state($w,noiseModel) [expr {$state($d,gaussian)?"independent_gaussian_known_sigma":"unspecified"}]
        foreach axis {U V} {set state($w,translation${axis}Mode) off;set state($w,translation${axis}Delta) 0}
    } elseif {$state($d,kind) eq "implicit"} {
        set state($w,implicitRecipe) [dict get $model recipe];set state($w,implicitBranch) [_implicitEditorBranch $w $d]
        set state($w,model) implicit
        foreach axis {U V} {set state($w,translation${axis}Mode) off;set state($w,translation${axis}Delta) 0}
        set state($w,domain) range;lassign [dict get $state($w,implicitBranch) independent_domain] state($w,min) state($w,max);set state($w,samples) 101
    } else {
        set state($w,formulaRecipe) [dict get $model formula_declaration recipe];set state($w,model) formula
    }
    _invalidateSettings $w;_uiModelFields $w;_workspaceCapture $w;_saveState $w
    set state($w,status) {Formula settings saved. Preview to fit the declared physical parameters.}
    destroy $d
}
