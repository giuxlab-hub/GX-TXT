# SPDX-License-Identifier: GPL-3.0-or-later
# Fitter selects bindings; Numeric computes and CORE owns publication/meaning.
proc ::GX::DatasetCurveFit::_smoothLineage {dataset x y} {
    set p [::GX::datasetTransformProvenance $::GX::currentSession $dataset];set result {}
    foreach binding [::GX::datasetPublicationV2DictDefault $p smoothing_lineage {}] {
        if {[dict get $binding variable_id] in [list $x $y]} {lappend result $binding}
    }
    return $result
}
proc ::GX::DatasetCurveFit::_smoothContext {source} {
    set bindings {}
    foreach item [::GX::datasetPublicationV2DictDefault $source smoothing_lineage {}] {
        set binding [dict create variable_id [dict get $item variable_id]]
        foreach field {method source_dataset_id source_sha256 original_y_variable_id smoothed_variable_id uncertainty_policy} {dict set binding $field [dict get $item smoothing $field]}
        lappend bindings $binding
    }
    if {$bindings eq {}} {return {}}
    return [dict create schema gxtxt.smoothing_context.v1 bindings $bindings]
}
proc ::GX::DatasetCurveFit::_smoothStatisticsValidate {result} {
    set training [dict get $result statistical_results training]
    if {[dict exists $result source_kind]} {set source $result} else {set source [dict get $training provenance source_identity]}
    set expected [_smoothContext $source]
    foreach role {training evaluation} {
        set context [dict get $result statistical_results $role context]
        if {[::GX::datasetPublicationV2DictDefault $context smoothing {}] ne $expected} {error {Smoothing interpretation differs from the captured source lineage}}
    }
}
proc ::GX::DatasetCurveFit::_smoothRecipeValidate {source} {
    set current [_smoothLineage [dict get $source source_dataset_id] [dict get $source source_x_variable_id] [dict get $source source_y_variable_id]]
    if {$current ne [::GX::datasetPublicationV2DictDefault $source smoothing_lineage {}]} {error {Smoothing source lineage changed; review and capture a new recipe}}
}
proc ::GX::DatasetCurveFit::_smoothTemplateSignature {source} {
    set result {}
    foreach item [::GX::datasetPublicationV2DictDefault $source smoothing_lineage {}] {
        set signature {};set receipt [dict get $item smoothing]
        foreach field {method window degree robust_iterations endpoint_policy} {dict set signature $field [::GX::datasetPublicationV2DictDefault [dict get $receipt estimator] $field {}]}
        set axes {};foreach axis {x y} {if {[dict get $source source_${axis}_variable_id] eq [dict get $item variable_id]} {lappend axes $axis}}
        dict set signature axes $axes;lappend result $signature
    }
    return $result
}
proc ::GX::DatasetCurveFit::_smoothTemplateBind {prior source} {
    set current [_smoothLineage [dict get $source source_dataset_id] [dict get $source source_x_variable_id] [dict get $source source_y_variable_id]]
    if {$current eq {}} {dict unset source smoothing_lineage} else {dict set source smoothing_lineage $current}
    if {[_smoothTemplateSignature $prior] ne [_smoothTemplateSignature $source]} {error {Template mapping cannot silently change smoothing method, settings or affected axes}}
    return $source
}
proc ::GX::DatasetCurveFit::_smoothSettings {w} {
    variable state
    _assertLoaded $w
    if {$state($w,sourceKind) ne "dataset"||$state($w,sourceTransformManifest) ne {}} {error {Smoothing requires a canonical Dataset curve; materialize edited coordinates first}}
    set fields [dict create output [dict create type string label {New Dataset ID} required 1] method [dict create type choice label {Smoothing method} values {savitzky_golay lowess loess}] window [dict create type number label {Odd window / nearest-neighbor count} required 1] degree [dict create type number label {Local polynomial degree (LOWESS: 1 or 2)} required 1] robust_iterations [dict create type number label {LOWESS robust reweightings (0–10; ignored for Savitzky–Golay)} required 1] nonfinite [dict create type choice label {Nonfinite pairs} values {error omit}]]
    set values [dict create output $state($w,dataset)_smooth method savitzky_golay window 9 degree 2 robust_iterations 2 nonfinite error]
    set owner [list $state($w,activeSource) $state($w,loadedBinding) $state($w,sourceSha)]
    ::GX::uiFieldFormCreate $w.smoothSettings {Smooth into a separate Dataset} $fields $values [list ::GX::DatasetCurveFit::_smoothApply $w $owner] $w
    ttk::label $w.smoothSettings.viewport.content.help -text {Keeps original columns, smoothed Y, removed component and exact source rows in a new Dataset. Uses Dataset filters; fit rectangles are not smoothing masks. X must increase without duplicates. Smoothing induces correlated errors: later fits retain coefficients and descriptive residuals, while independent-error intervals and likelihood comparisons are unavailable.} -wraplength 520 -justify left
    grid $w.smoothSettings.viewport.content.help -row 20 -column 0 -sticky ew -padx 5 -pady 8
}
proc ::GX::DatasetCurveFit::_smoothProgress {w progress} {variable state;set state($w,status) {Creating a separate smoothed Dataset…}}
proc ::GX::DatasetCurveFit::_smoothApply {w owner values} {
    variable state
    _assertLoaded $w
    if {$owner ne [list $state($w,activeSource) $state($w,loadedBinding) $state($w,sourceSha)]} {error {Active source or binding changed; reopen smoothing settings}}
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    set options [dict create method [dict get $values method] nonfinite [dict get $values nonfinite]]
    foreach k {window degree} {dict set options $k [_finite [dict get $values $k] $k]}
    if {[dict get $values method] in {lowess loess}} {dict set options robust_iterations [_finite [dict get $values robust_iterations] robust_iterations]}
    set filters {};set mapping [dict create = exact_equal != not_equal < less_than <= less_equal > greater_than >= greater_equal contains contains LIKE like]
    foreach filter $state($w,filters) {
        set operator [dict get $filter operator];set item [dict create filter_variable_id [dict get $filter variable]]
        if {$operator eq "between"} {lassign [dict get $filter value] lower upper;dict set item predicate between_inclusive;dict set item lower $lower;dict set item upper $upper} else {dict set item predicate [dict get $mapping $operator];dict set item value [dict get $filter value]}
        lappend filters $item
    }
    set names {};foreach v [::GX::datasetVariableSchemaV3 $state($w,dataset)] {lappend names [dict get $v variable_id]}
    set outputs {};foreach {k base} {smoothed smoothed_y residual smoothing_residual row smoothing_source_row_ordinal} {
        set name $base;set suffix 1;while {$name in $names} {set name ${base}_[incr suffix]};lappend names $name;dict set outputs ${k}_variable_id $name
    }
    set x $state($w,x)
    set manifest [dict create api_version 1 operation smooth_curve sources [list [dict create dataset_id $state($w,dataset) row_filters $filters]] options [dict merge $outputs [dict create x_variable_id $x y_variable_id $state($w,y) smoothing_options $options]] output [dict create dataset_id [dict get $values output] display_name "$state($w,dataset): smoothed $state($w,y)"]]
    set controls [_operationBegin $w]
    try {
        set result [::GX::datasetTransformExecuteResponsive $::GX::currentSession $manifest [dict create progress_command [list ::GX::DatasetCurveFit::_smoothProgress $w] cancel_command [list ::GX::DatasetCurveFit::_baselineCancelled $w]]]
        loadSource $w [dict get $result dataset_id] $x [dict get $outputs smoothed_variable_id] {}
        _logFocusSource $w
        set state($w,translationUMode) off;set state($w,translationVMode) off
        set state($w,status) {Smoothed source created. Original data and removed component remain available; independent-error inference is withheld after smoothing.}
    } finally {_operationEnd $w $controls}
    _refreshFits $w;_saveState $w;redraw $w
    if {[winfo exists $w.smoothSettings]} {destroy $w.smoothSettings}
}
