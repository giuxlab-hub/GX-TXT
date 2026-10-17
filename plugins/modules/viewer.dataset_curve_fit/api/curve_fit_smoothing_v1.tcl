# SPDX-License-Identifier: GPL-3.0-or-later
# Numeric owns the smoother and selection; CORE owns statistical meaning.
proc ::GX::DatasetCurveFit::_smoothingDefaults {} {
    return {smoothing_selection manual gcv_lambda_bounds {} gcv_grid_count 17 gcv_refinement_evaluations 24}
}
proc ::GX::DatasetCurveFit::_smoothingOptionNodes {model options} {
    set supplied [::GX::datasetPublicationV2DictDefault $options smoothing_options {}]
    if {$supplied ne {}&&$model ne "smoothing_spline"} {error {Smoothing settings require the smoothing spline model}}
    set defaults [_smoothingDefaults]
    dict for {key value} $supplied {if {![dict exists $defaults $key]} {error "Unknown smoothing setting: $key"}}
    set settings [dict merge $defaults $supplied];set mode [dict get $settings smoothing_selection]
    if {$mode ni {manual gcv}} {error {Smoothing selection must be manual or gcv}}
    set nodes [dict create smoothing_selection [::GX::ScientificTransportv1::text $mode]]
    if {$mode eq "manual"} {return [::GX::ScientificTransportv1::struct $nodes]}
    set bounds [dict get $settings gcv_lambda_bounds]
    if {[llength $bounds]!=2} {error {GCV requires two explicit positive lambda bounds}}
    lassign $bounds lower upper
    if {[_finite $lower {Lower lambda bound}]<=0||[_finite $upper {Upper lambda bound}]<=$lower} {error {GCV requires increasing positive lambda bounds}}
    dict set nodes gcv_lambda_bounds [::GX::ScientificTransportv1::array {1 2} $bounds]
    foreach key {gcv_grid_count gcv_refinement_evaluations} minimum {3 0} maximum {65 64} {
        set value [dict get $settings $key]
        if {![string is integer -strict $value]||$value<$minimum||$value>$maximum} {error "$key must be an integer from $minimum to $maximum"}
        dict set nodes $key [::GX::ScientificTransportv1::array {1 1} [list $value]]
    }
    return [::GX::ScientificTransportv1::struct $nodes]
}
proc ::GX::DatasetCurveFit::_smoothingSettings {w} {
    variable state
    if {$state($w,model) ne "smoothing_spline"} {error {Choose a smoothing spline first}}
    set fields [dict create smoothing_selection [dict create type choice label {Lambda selection} values {manual gcv}] gcv_lambda_bounds [dict create type string label {GCV lambda bounds (two positive values in predictor units cubed)}] gcv_grid_count [dict create type number label {Log-grid candidates (3–65)} required 1] gcv_refinement_evaluations [dict create type number label {Refinement evaluations (0–64)} required 1]]
    set values [dict merge [_smoothingDefaults] $state($w,smoothingSettings)]
    ::GX::uiFieldFormCreate $w.smoothingSettings {Smoothing selection; manual lambda stays in the main panel} $fields $values [list ::GX::DatasetCurveFit::_smoothingApply $w $state($w,activeSource)] $w
}
proc ::GX::DatasetCurveFit::_smoothingApply {w owner values} {
    variable state
    if {$owner ne $state($w,activeSource)||$state($w,model) ne "smoothing_spline"} {error {Active source or model changed; reopen smoothing settings}}
    _smoothingOptionNodes smoothing_spline [dict create smoothing_options $values]
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    set state($w,smoothingSettings) $values
    _invalidateSettings $w;_workspaceCapture $w;_saveState $w
    set state($w,status) {Smoothing selection saved. Preview again; Results → Smoothing diagnostics explains EDF, GCV and search limits.}
}
proc ::GX::DatasetCurveFit::_smoothingDetails {w} {
    variable state
    if {$state($w,preview) eq {}||![dict exists $state($w,preview) statistical_results training provenance smoothing]} {error {Preview a smoothing spline with diagnostics first}}
    set statistics [dict get $state($w,preview) statistical_results training]
    set content [::GX::StatisticsV1::report $statistics {n edf residual_mean_dof residual_variance_dof smoother_trace_squared smoothing_lambda smoothing_gcv_score}]
    set search [dict get $statistics provenance smoothing smoothing_selection]
    append content "\n\nSelection: [dict get $search method]; evaluations: [dict get $search evaluations]."
    if {[dict exists $search lambda_bounds]} {append content "\nLambda bounds: [dict get $search lambda_bounds]; endpoint selected: [dict get $search boundary_optimum].\n\n[dict get $search candidate_columns]\n";foreach row [dict get $search candidates] {append content "[join $row {  }]\n"}}
    set dialog $w.smoothingDetails
    if {[winfo exists $dialog]} {destroy $dialog}
    toplevel $dialog;wm title $dialog {Smoothing diagnostics};wm transient $dialog $w
    text $dialog.text -wrap word -width 86 -height 24 -yscrollcommand [list $dialog.scroll set]
    ttk::scrollbar $dialog.scroll -command [list $dialog.text yview]
    grid $dialog.text -row 0 -column 0 -sticky nsew;grid $dialog.scroll -row 0 -column 1 -sticky ns
    grid rowconfigure $dialog 0 -weight 1;grid columnconfigure $dialog 0 -weight 1
    $dialog.text insert end $content;$dialog.text configure -state disabled
    bind $dialog <Escape> [list destroy $dialog];focus $dialog.text
}
