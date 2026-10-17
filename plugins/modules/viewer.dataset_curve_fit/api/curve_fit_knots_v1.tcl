# Fitter settings and retained identity; Numeric/CORE own spline algorithms/meaning.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_knotDefaults {model} {
    if {$model eq "akima"} {return {boundary extrapolated_slopes endpoint_slopes {} extrapolation error}}
    if {$model eq "bspline"} {return {degree 3 knots {} boundary free endpoint_slopes {} extrapolation error}}
    error {Choose Akima or B-spline first}
}
proc ::GX::DatasetCurveFit::_knotSettingsValues {model supplied} {
    set defaults [_knotDefaults $model]
    foreach key [dict keys $supplied] {if {![dict exists $defaults $key]&&$key ni {x_unit y_unit}} {error "Unknown $model setting: $key"}}
    set settings [dict merge $defaults $supplied];set boundary [dict get $settings boundary]
    set boundaries [expr {$model eq "akima"?{extrapolated_slopes clamped}:{free natural clamped periodic}}]
    if {$boundary ni $boundaries} {error "Choose a supported $model boundary condition"}
    if {[dict get $settings extrapolation] ni {error allow}} {error {Choose error or explicit allow extrapolation}}
    if {$model eq "bspline"} {
        set degree [dict get $settings degree]
        if {![string is integer -strict $degree]||$degree<1||$degree>3} {error {B-spline degree must be1,2 or3}}
        if {$boundary in {natural clamped}&&$degree!=3} {error {Natural and clamped boundaries require cubic B-splines}}
        set knots [_queryNumbers [dict get $settings knots] 257 {Explicit simple knots}]
        if {[llength $knots]<2} {error {Include both observed domain endpoints in the knot list}}
        set previous [lindex $knots 0];foreach value [lrange $knots 1 end] {if {$value<=$previous} {error {Simple knots must strictly increase; repeated knots are unsupported}};set previous $value}
        dict set settings knots $knots
    }
    set slopes [dict get $settings endpoint_slopes]
    if {$boundary eq "clamped"} {if {[llength $slopes]!=2} {error {Clamped boundary requires two physical response/predictor slopes}};dict set settings endpoint_slopes [_queryNumbers $slopes 2 {Endpoint slopes}]
    } elseif {$slopes ne {}} {error {Endpoint slopes apply only to a clamped boundary}}
    foreach key {x_unit y_unit} {if {[dict exists $settings $key]&&[string trim [dict get $settings $key]] eq {}} {error {Physical knot units must be explicit}}}
    return $settings
}
proc ::GX::DatasetCurveFit::_knotOptionNodes {model options} {
    set settings [_knotSettingsValues $model [::GX::datasetPublicationV2DictDefault $options knot_options {}]];set fields {}
    dict for {key value} $settings {
        if {$key in {boundary extrapolation x_unit y_unit}} {dict set fields $key [::GX::ScientificTransportv1::text $value]
        } elseif {$value ne {}} {dict set fields $key [::GX::ScientificTransportv1::array [list 1 [llength $value]] $value]}
    }
    return [::GX::ScientificTransportv1::struct $fields]
}
proc ::GX::DatasetCurveFit::_prepareKnots {key model options} {
    set settings [_knotSettingsValues $model [::GX::datasetPublicationV2DictDefault $options knot_options {}]]
    set orientation [_fitOrientation $model $options];if {$orientation ni {y_of_x x_of_y}} {error {Knot models require Y(X) or X(Y)}}
    set source [_sourceProvenance $key];set axes [dict get $source source_axes]
    if {[_smoothContext $source] ne {}||[_baselineContext $source] ne {}||[_logContext $source $orientation] ne {}} {error {Physical knot declaration requires untransformed observations}}
    foreach axis {u v} {set value [::GX::datasetPublicationV2DictDefault $options translation_$axis {mode off delta 0}];if {[dict get $value mode] ne "off"||[dict get $value delta]!=0} {error {Physical knot declarations require translations off}}}
    if {[dict get [_measurementOptions $options] kind] ne "none"||[::GX::datasetPublicationV2DictDefault $options covariance {}] ne {}||[::GX::datasetPublicationV2DictDefault $options solver_options {}] ne {}} {error {Knot models use their declared interpolation or unweighted B-spline solver; measurement weighting and nonlinear solver controls have no contract}}
    if {[::GX::datasetPublicationV2DictDefault $options prediction_band none] ne "none"||[::GX::datasetPublicationV2DictDefault $options bootstrap {}] ne {}||[::GX::datasetPublicationV2DictDefault $options influence_diagnostics 0]} {error {Knot models do not supply parameter inference, bands, bootstrap or linear influence}}
    set independent [expr {$orientation eq "y_of_x"?"x":"y"}];set response [expr {$orientation eq "y_of_x"?"y":"x"}]
    foreach field {x_unit y_unit} axis [list $independent $response] {
        set unit [dict get $axes $axis unit]
        if {[dict exists $settings $field]&&[dict get $settings $field] ne $unit} {error {Knot declaration units differ from actual source axes}}
        dict set settings $field $unit
    }
    return $settings
}
proc ::GX::DatasetCurveFit::_knotSettings {w} {
    variable state
    set model $state($w,model);set defaults [_knotDefaults $model]
    set boundaries [expr {$model eq "akima"?{extrapolated_slopes clamped}:{free natural clamped periodic}}]
    set fields {}
    if {$model eq "bspline"} {
        dict set fields degree [dict create type choice label {Polynomial degree (1=C0, 2=C1, 3=C2 interior continuity)} values {1 2 3}]
        dict set fields knots [dict create type string label {Explicit simple knots, including both observed endpoints} required 1]
    }
    dict set fields boundary [dict create type choice label {Boundary condition} values $boundaries]
    dict set fields endpoint_slopes [dict create type string label {Clamped endpoint slopes: response unit / predictor unit; otherwise leave blank}]
    dict set fields extrapolation [dict create type choice label {Outside fitted support (allow uses the boundary polynomial)} values {error allow}]
    set values [dict remove [dict merge $defaults [::GX::datasetPublicationV2DictDefault $state($w,knotSettings) $model {}]] x_unit y_unit]
    ::GX::uiFieldFormCreate $w.knotSettings "$model: physical knots and boundary conditions" $fields $values [list ::GX::DatasetCurveFit::_knotApply $w $state($w,activeSource) $model] $w
}
proc ::GX::DatasetCurveFit::_knotApply {w owner model values} {
    variable state
    if {$owner ne $state($w,activeSource)||$model ne $state($w,model)} {error {Active source or model changed; reopen knot settings}}
    set settings [_knotSettingsValues $model $values]
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    dict set state($w,knotSettings) $model $settings
    foreach axis {U V} {set state($w,translation${axis}Mode) off;set state($w,translation${axis}Delta) 0}
    _invalidateSettings $w;_workspaceCapture $w;_saveState $w
    set state($w,status) {Physical knot settings saved. Preview uses original rows and preserves interpolation or approximation meaning.}
}
proc ::GX::DatasetCurveFit::_knotResultIdentity {p} {
    set parts [dict create settings [dict get $p options knot_options] summary [dict get $p statistical_results training context knot_spline]]
    if {[dict exists $p model_state_resource]} {
        set resource [::GX::interactiveDocumentResourceInfo [dict get $p model_state_resource]]
        dict set parts resource_sha256 [dict get $resource sha256]
    } elseif {[dict exists $p model_state_json]} {dict set parts model_json [dict get $p model_state_json]
    } else {error {Knot result is missing its exact retained state}}
    return [_numericStateDigest $parts]
}
proc ::GX::DatasetCurveFit::_validateKnotMetadata {p} {
    set hasKnot [dict exists $p statistical_results training context knot_spline]
    if {[dict get $p model] ni {akima bspline}} {if {$hasKnot} {error {Captured knot model cannot be relabelled}};return}
    if {![dict exists $p knot_binding_sha256]||[_knotResultIdentity $p] ne [dict get $p knot_binding_sha256]} {error {Knot recipe, boundary or retained state identity changed}}
    set context [dict get $p statistical_results training context];set summary [dict get $context knot_spline]
    if {[dict get $summary model] ne [dict get $p model]||[dict get $context orientation] ne [dict get $p orientation]} {error {Captured knot model or physical orientation changed}}
    set settings [_knotSettingsValues [dict get $p model] [dict get $p options knot_options]]
    if {[dict get $settings x_unit] ne [dict get $summary predictor_unit]||[dict get $settings y_unit] ne [dict get $summary response_unit]} {error {Captured knot coordinate units changed}}
    set axes [dict get $p statistical_results training provenance source_identity source_axes]
    if {[dict exists $p source_axes]} {set axes [dict get $p source_axes]}
    foreach axis {x y} {if {[dict get $axes $axis unit] ne [dict get $context ${axis}_unit]} {error {Captured knot source units changed}}}
    set domain [split [dict get $p training_domain] ,];set expected [dict get $summary domain]
    if {[llength $domain]!=2||[lindex $domain 0]!=[lindex $expected 0]||[lindex $domain 1]!=[lindex $expected 1]} {error {Captured knot support changed}}
    set evaluation [dict get $p statistical_results evaluation context]
    if {[dict get $evaluation knot_spline] ne $summary||[dict get $evaluation orientation] ne [dict get $context orientation]} {error {Knot source evaluation belongs to another captured model}}
    foreach axis {u v} {if {[dict get $p translation $axis mode] ne "off"||[dict get $p translation $axis delta]!=0} {error {Retained knot physical coordinate frame changed}}}
}
