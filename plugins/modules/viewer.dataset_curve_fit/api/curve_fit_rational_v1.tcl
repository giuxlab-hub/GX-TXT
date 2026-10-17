# Physical rational data/UI adapter. Numeric owns domain checks and computation.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_rationalRecipeNode {recipe} {
    foreach key [dict keys $recipe] {if {$key ni {numerator_degree denominator_degree x_unit y_unit parameters domain pole_tolerance}} {error "Unknown rational recipe field: $key"}}
    set formula [dict create expression 0 predictor_ids x predictor_units [list [dict get $recipe x_unit]] response_unit [dict get $recipe y_unit] parameters [dict get $recipe parameters]]
    set fields [dict create parameters [dict get [_formulaRecipeNode $formula] fields parameters]]
    foreach key {x_unit y_unit} {dict set fields $key [::GX::ScientificTransportv1::text [dict get $recipe $key]]}
    foreach key {numerator_degree denominator_degree domain pole_tolerance} {
        if {![dict exists $recipe $key]} {if {$key eq "pole_tolerance"} continue;error "Rational recipe requires $key"}
        set values [dict get $recipe $key];dict set fields $key [::GX::ScientificTransportv1::array [list 1 [llength $values]] $values]
    }
    return [::GX::ScientificTransportv1::struct $fields]
}
proc ::GX::DatasetCurveFit::_resolveRational {recipe} {
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    return [::GX::NumericAPIv1::callOperation rational_model_compose [list [_rationalRecipeNode $recipe]]]
}
proc ::GX::DatasetCurveFit::_rationalCheckAxes {recipe axes orientation} {
    if {$orientation ni {y_of_x x_of_y}} {error {Rational response requires Y(X) or X(Y)}}
    set independent [expr {$orientation eq "y_of_x"?"x":"y"}];set response [expr {$orientation eq "y_of_x"?"y":"x"}]
    if {[dict get $recipe x_unit] ne [dict get $axes $independent unit]||[dict get $recipe y_unit] ne [dict get $axes $response unit]} {error {Rational predictor and response units differ from the actual physical axes}}
}
proc ::GX::DatasetCurveFit::_prepareRational {w options} {
    if {![dict exists $options rational_recipe]} {error {Configure the rational model first}}
    set source [_sourceProvenance $w];set orientation [_fitOrientation rational $options]
    set recipe [dict get $options rational_recipe];_rationalCheckAxes $recipe [dict get $source source_axes] $orientation
    if {[_smoothContext $source] ne {}||[_baselineContext $source] ne {}||[_logContext $source $orientation] ne {}} {error {Rational inference requires untransformed observations; preprocessing uncertainty needs its own declared contract}}
    foreach axis {u v} {set t [::GX::datasetPublicationV2DictDefault $options translation_$axis {mode off delta 0}];if {[dict get $t mode] ne "off"||[dict get $t delta]!=0} {error {Rational fitting requires physical coordinates with translation off}}}
    if {[dict get [_measurementOptions $options] kind] eq "sigma_xy"||[::GX::datasetPublicationV2DictDefault $options covariance {}] ne {}} {error {Rational fitting accepts independent response uncertainty; XY and full observation covariance need separate contracts}}
    if {[::GX::datasetPublicationV2DictDefault $options prediction_band none] ne "none"||[::GX::datasetPublicationV2DictDefault $options bootstrap {}] ne {}||[::GX::datasetPublicationV2DictDefault $options influence_diagnostics 0]} {error {Rational prediction bands, parameter refit bootstrap and linear influence require separate domain-qualified contracts}}
    set policy [::GX::datasetPublicationV2DictDefault $options solver_options {}]
    if {[::GX::datasetPublicationV2DictDefault $policy loss linear] ne "linear"||[::GX::datasetPublicationV2DictDefault $policy multistart_mode single] ne "single"} {error {Rational fitting uses one declared quadratic-response solver start}}
    foreach field {lower_bounds upper_bounds fixed_mask} {if {[::GX::datasetPublicationV2DictDefault $policy $field {}] ne {}} {error {Set rational bounds and fixed flags in the physical coefficient declaration}}}
    if {[::GX::datasetPublicationV2DictDefault $options rational_extrapolation error] ni {error allow}} {error {Rational extrapolation must be error or explicit allow}}
    return [_resolveRational $recipe]
}
proc ::GX::DatasetCurveFit::_rationalState {p} {
    set summary [dict get $p statistical_results training context rational];set domain [dict get $summary domain_receipt]
    set state [dict create schema gxtxt.rational_state.v1 recipe [dict get $p options rational_recipe] parameters [dict get $p numeric_model_state parameters] observation_domain [dict get $summary observation_domain]]
    foreach key {declaration_sha256 source_sha256 binding_sha256} {dict set state $key [dict get $domain $key]}
    return $state
}
proc ::GX::DatasetCurveFit::_rationalSavedNode {p} {
    _validateRationalMetadata $p
    set saved [_rationalState $p];set fields [dict create recipe [_rationalRecipeNode [dict get $saved recipe]]]
    foreach key {schema declaration_sha256 source_sha256 binding_sha256} {dict set fields $key [::GX::ScientificTransportv1::text [dict get $saved $key]]}
    foreach key {parameters observation_domain} {set values [dict get $saved $key];dict set fields $key [::GX::ScientificTransportv1::array [list 1 [llength $values]] $values]}
    return [::GX::ScientificTransportv1::struct $fields]
}
proc ::GX::DatasetCurveFit::_validateRationalMetadata {p} {
    if {[dict get $p model] ne "rational"} return
    if {![dict exists $p rational_state_sha256]||[_numericStateDigest [_rationalState $p]] ne [dict get $p rational_state_sha256]} {error {Retained rational recipe, physical state or domain identity changed}}
    set model [dict get $p numeric_model_state];set receipt [dict get $p statistical_results training context rational domain_receipt]
    foreach key {source_sha256 binding_sha256} {if {[dict get $model $key] ne [dict get $receipt $key]} {error {Retained rational formula identity differs from its interpretation}}}
    foreach axis {u v} {if {[dict get $p translation $axis delta]!=0||[dict get $p translation $axis mode] ne "off"} {error {Retained rational model lost its physical coordinate frame}}}
}
proc ::GX::DatasetCurveFit::_rationalSettings {w} {_formulaSettings $w rational}
proc ::GX::DatasetCurveFit::_rationalEditorControls {w d body} {
    variable state
    set recipe $state($w,rationalRecipe)
    set state($d,numeratorDegree) [::GX::datasetPublicationV2DictDefault $recipe numerator_degree 1];set state($d,denominatorDegree) [::GX::datasetPublicationV2DictDefault $recipe denominator_degree 1]
    set bounds [expr {[info exists state($w,fullBounds)]?$state($w,fullBounds):{0 1 0 1}}];set offset [expr {$state($w,orientation) eq "y_of_x"?0:2}]
    lassign [::GX::datasetPublicationV2DictDefault $recipe domain [lrange $bounds $offset [expr {$offset+1}]]] state($d,rationalLow) state($d,rationalHigh)
    set state($d,poleTolerance) [::GX::datasetPublicationV2DictDefault $recipe pole_tolerance 1e-10]
    set state($d,rationalExtrapolation) $state($w,rationalExtrapolation)
    $body.help configure -text "Physical rational response: numerator / denominator. The denominator constant is one; power coefficient identities remain a0…aM and b1…bN. Declare a pole-free domain. No factor is cancelled. Explicit extrapolation must pass a whole-interval check. These are rational least-squares coefficients, not Taylor-series Padé coefficients."
    pack forget $body.expression
    ttk::frame $body.rational;pack $body.rational -fill x -padx 8 -pady 6
    set row 0
    foreach {field label} {numeratorDegree {Numerator degree (0–8)} denominatorDegree {Denominator degree (1–8)} rationalLow {Declared predictor minimum} rationalHigh {Declared predictor maximum} poleTolerance {Relative denominator separation tolerance}} {
        ttk::label $body.rational.l_$field -text $label;ttk::entry $body.rational.$field -textvariable ::GX::DatasetCurveFit::state($d,$field)
        grid $body.rational.l_$field -row $row -column 0 -sticky w -padx 4 -pady 2;grid $body.rational.$field -row $row -column 1 -sticky ew -padx 4 -pady 2;incr row
    }
    ttk::button $body.rational.degrees -text {Apply degrees to coefficient controls} -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_rationalEditorDegrees $w $d]]
    grid $body.rational.degrees -row $row -columnspan 2 -sticky w -padx 4 -pady 4;incr row
    ttk::checkbutton $body.rational.extrapolate -text {Allow source/output evaluation beyond fitted observations after checking the whole interval} -variable ::GX::DatasetCurveFit::state($d,rationalExtrapolation) -onvalue allow -offvalue error
    grid $body.rational.extrapolate -row $row -columnspan 2 -sticky w -padx 4 -pady 4;grid columnconfigure $body.rational 1 -weight 1
    $d.actions.validate configure -text {Validate rational declaration};$d.actions.apply configure -text {Apply rational model};wm geometry $d 950x720
}
proc ::GX::DatasetCurveFit::_rationalEditorDegrees {w d} {
    variable state
    set m $state($d,numeratorDegree);set n $state($d,denominatorDegree)
    if {![string is integer -strict $m]||$m<0||$m>8||![string is integer -strict $n]||$n<1||$n>8} {error {Use numerator degree0–8 and denominator degree1–8}}
    set existing {};foreach row $state($d,rows) {set item {};foreach key {id unit initial lower upper fixed} {dict set item $key $state($d,$row,$key)};dict set existing [dict get $item id] $item}
    foreach row $state($d,rows) {_formulaRemove $d $row}
    set ids {};for {set k 0} {$k<=$m} {incr k} {lappend ids a$k};for {set k 1} {$k<=$n} {incr k} {lappend ids b$k}
    foreach id $ids {
        set parameter [::GX::datasetPublicationV2DictDefault $existing $id [dict create id $id initial [expr {$id eq "a1"?1:0}]]]
        _formulaAdd $d $parameter;set row [lindex $state($d,rows) end];$state($d,body).parameters.id$row configure -state readonly;$state($d,body).parameters.remove$row configure -state disabled
    }
    set state($d,status) {Coefficient controls reflect the declared powers. Review physical initial values, units, bounds and fixed flags before applying.}
}
proc ::GX::DatasetCurveFit::_rationalEditorRecipe {w d} {
    variable state
    set formula [_formulaRead $w $d]
    return [dict create numerator_degree $state($d,numeratorDegree) denominator_degree $state($d,denominatorDegree) x_unit [dict get $state($d,units) x_unit] y_unit [dict get $state($d,units) y_unit] parameters [dict get $formula parameters] domain [list [_finite $state($d,rationalLow) {Rational domain minimum}] [_finite $state($d,rationalHigh) {Rational domain maximum}]] pole_tolerance [_finite $state($d,poleTolerance) {Pole tolerance}]]
}
