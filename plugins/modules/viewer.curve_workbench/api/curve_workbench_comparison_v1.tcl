# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::CurveWorkbench::_geometricComparisonEvaluate {w reference derived budget} {
    variable st
    set a [_record $w $reference];set b [_record $w $derived]
    set units [_coordinateUnits $a]
    if {$units ne [_coordinateUnits $b]||[lindex $units 0] ne [lindex $units 1]} {error "Geometric comparison requires a common X/Y coordinate unit for both curves"}
    set receipt [::GX::Native2D::core compare_geometry $st($w,scene) [dict get $a native] [dict get $b native] $budget]
    dict set receipt unit [lindex $units 0]
    set fingerprints [dict create $reference [_measurementFingerprint $w $reference] $derived [_measurementFingerprint $w $derived]];set sources {}
    foreach record [list $a $b] id [list $reference $derived] {if {[dict get $record source] ne {}} {dict set sources $id [dict create dataset_id [dict get $record source] descriptor [::GX::datasetPublicationV2DictDefault $record source_descriptor {}]]}}
    return [dict create definition [dict create reference $reference derived $derived budget $budget] fingerprints $fingerprints sources $sources receipt $receipt]
}
rename ::GX::CurveWorkbench::_measurementEvaluate ::GX::CurveWorkbench::_measurementEvaluate_comparison_base
proc ::GX::CurveWorkbench::_measurementEvaluate {w definition} {
    set kind [dict get $definition kind]
    if {$kind ni {geometric_rmse hausdorff_sampled curve_length_difference curve_area_difference closest_curve_distance}} {set result [_measurementEvaluate_comparison_base $w [dict remove $definition sample_budget]];dict set result definition $definition;return $result}
    if {![dict exists $definition b]||[dict get $definition b] eq {}} {error "Geometric comparison requires Geometry B"}
    set record [_geometricComparisonEvaluate $w [dict get $definition a] [dict get $definition b] [::GX::datasetPublicationV2DictDefault $definition sample_budget 257]]
    set comparison [dict get $record receipt];set field [dict get {geometric_rmse rmse hausdorff_sampled hausdorff_sampled curve_length_difference length_difference curve_area_difference area_difference closest_curve_distance closest_distance} $kind]
    if {$kind eq "curve_area_difference"&&![dict get $comparison area_supported]} {error "Area comparison requires supported closed curves"}
    set unit [dict get $comparison unit];set power [expr {$kind eq "curve_area_difference" ? 2 : 1}]
    set exact [expr {$kind eq "closest_curve_distance"&&[dict get $comparison closest_exact]}]
    set receipt [dict create value [dict get $comparison $field] unit [expr {$unit eq {} ? {} : $power==2 ? "$unit^2" : $unit}] unit_power $power unit_declared [expr {$unit ne {}}] angular 0 exact $exact policy [dict get $comparison policy] point_a [dict get $comparison closest_a] point_b [dict get $comparison closest_b] comparison_summary [dict remove $comparison rows]]
    dict set record definition $definition;dict set record receipt $receipt;return $record
}
rename ::GX::CurveWorkbench::_compare ::GX::CurveWorkbench::_compare_geometric_base
proc ::GX::CurveWorkbench::_compare {w} {
    variable st
    if {$st($w,compareMethod) ne "geometry"} {return [_compare_geometric_base $w]}
    if {[info exists st($w,comparisonImplicit)]&&$st($w,comparisonImplicit)} {
        if {$st($w,lastGeometricComparison) ne {}&&[_measurementState $w $st($w,lastGeometricComparison)] eq "current"} {set st($w,residual) [dict get $st($w,lastGeometricComparison) receipt]} else {set st($w,residual) {}}
        return $st($w,residual)
    }
    set active [_active $w];set reference $st($w,reference)
    if {$reference eq {}||$reference eq $active} {error "Choose a different reference curve"}
    set record [_geometricComparisonEvaluate $w $reference $active 257]
    set before [_snapshotIds $w {}];set oldUndo $st($w,undo);set oldRedo $st($w,redo)
    set st($w,lastGeometricComparison) $record;set st($w,residual) [dict get $record receipt]
    try {_history $w $before {}} on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;return -options $options $message}
    set result [dict get $record receipt]
    set st($w,status) "Sampled geometric deviation ([dict get $result count_a]/[dict get $result count_b] scientific queries): RMS [format %.7g [dict get $result rmse]], sampled Hausdorff [format %.7g [dict get $result hausdorff_sampled]], closest [format %.7g [dict get $result closest_distance]] [dict get $result unit]. Policy is retained in the report."
    return $result
}
rename ::GX::CurveWorkbench::_drawResidual ::GX::CurveWorkbench::_drawResidual_comparison_base
proc ::GX::CurveWorkbench::_drawResidual {w} {
    variable st
    _drawResidual_comparison_base $w
    if {$st($w,compareMethod) ne "geometry"||![winfo exists $w.right.residual]} return
    foreach id [$w.right.residual find all] {if {[$w.right.residual type $id] ne "text"} continue;set text [$w.right.residual itemcget $id -text];if {$text eq "signed\nresidual"} {$w.right.residual itemconfigure $id -text "distance\nto curve"} elseif {$text eq "reference path distance"} {$w.right.residual itemconfigure $id -text "sampled reference path distance"}}
}
proc ::GX::CurveWorkbench::_comparisonPublishOpen {w} {
    variable st
    if {$st($w,lastGeometricComparison) eq {}} {error "Run a geometry comparison first"}
    ::GX::uiFieldFormCreate $w.comparisonReport "Publish geometric deviation samples" {dataset_id {type string required 1 label {New public Dataset ID}}} {dataset_id curve_deviation_report} [list ::GX::CurveWorkbench::_comparisonPublishApply $w $st($w,token)] $w
}
proc ::GX::CurveWorkbench::_comparisonPublishApply {w token values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen comparison publication"}
    set record $st($w,lastGeometricComparison)
    if {$record eq {}||[_measurementState $w $record] ne "current"} {error "Comparison geometry is stale or missing; explicitly Compare again before publishing"}
    set receipt [dict get $record receipt];set unit [dict get $receipt unit];set rows [dict get $receipt rows]
    set sources {};dict for {id source} [dict get $record sources] {lappend sources [dict get $source dataset_id]}
    set id [::GX::datasetPublicationV2RequestedId [dict get $values dataset_id]]
    set metadata [dict create geometry_comparison.definition [dict get $record definition] geometry_comparison.fingerprints [dict get $record fingerprints] geometry_comparison.policy [dict get $receipt policy] geometry_comparison.summary [dict remove $receipt rows] geometry_comparison.sources [dict get $record sources]]
    set definition [dict create dataset_id $id contract table.generic storage auto expected_rows [llength $rows] estimated_numeric_bytes [expr {48*[llength $rows]}] source_dataset_ids [lsort -unique $sources] source {Native2D geometric comparison} provenance [dict create api_id NATIVE_2D_GEOMETRY_API_v1 api_version 1 module_id viewer.curve_workbench policy [dict get $receipt policy]] structured_metadata $metadata]
    set writer {};set plan [::GX::datasetPublicationV2Prepare [_session] viewer.curve_workbench $definition]
    try {
        set writer [::GX::datasetPublicationV2OpenWriter $plan];::GX::datasetPublicationV2DeclareDimension $writer row 0 {extendible 1}
        foreach key {path distance reference_x reference_y projected_x projected_y} {_declare $writer $key $unit [expr {$key in {path reference_x projected_x} ? "coordinate" : "data"}]}
        _declare $writer sample_index {} data int64
        for {set start 0} {$start<[llength $rows]} {incr start 512} {
            set chunk {};foreach key {path distance reference_x reference_y projected_x projected_y sample_index} {dict set chunk $key {}}
            set index $start
            foreach row [lrange $rows $start [expr {$start+511}]] {
                dict lappend chunk path [lindex $row 0];dict lappend chunk distance [lindex $row 2]
                foreach key {reference_x reference_y projected_x projected_y} value [concat [lindex $row 3] [lindex $row 4]] {dict lappend chunk $key $value}
                dict lappend chunk sample_index $index;incr index
            }
            ::GX::datasetPublicationV2Append $writer row $chunk
        }
        set result [::GX::datasetPublicationV2Finalize $writer];set writer {}
    } finally {if {$writer ne {}} {::GX::datasetPublicationV2Abort $writer}}
    set st($w,status) "Published geometric deviation Dataset $id with explicit sampling/projection policy.";return $result
}
rename ::GX::CurveWorkbench::_changed ::GX::CurveWorkbench::_changed_comparison_base
proc ::GX::CurveWorkbench::_changed {w} {
    variable st
    set prior [::GX::datasetPublicationV2DictDefault [array get st "$w,comparisonImplicit"] "$w,comparisonImplicit" 0]
    set st($w,comparisonImplicit) 1
    try {_changed_comparison_base $w} finally {set st($w,comparisonImplicit) $prior}
    if {$st($w,compareMethod) eq "geometry"} {
        if {$st($w,lastGeometricComparison) ne {}&&[_measurementState $w $st($w,lastGeometricComparison)] eq "current"} {set st($w,residual) [dict get $st($w,lastGeometricComparison) receipt]} else {set st($w,residual) {}}
        _draw $w
    }
}
proc ::GX::CurveWorkbench::_buildComparison {w} {
    variable st
    $w.validation.method configure -values {x path geometry} -width 10
    ttk::button $w.validation.deviations -text "Publish deviations…" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_comparisonPublishOpen $w]]
    pack $w.validation.deviations -side left -padx 3
    bind $w.validation <Configure> [list ::GX::native2DToolbarLayout $w.validation %w]
}
# Pack the residual panel before the expanding main canvas so it cannot be
# clipped below the pane. Empty residuals need no reserved blank plot space.
proc ::GX::CurveWorkbench::_residualLayout {w} {
    variable st
    if {![winfo exists $w.right.residual]||![info exists st($w,residual)]} return
    set show [expr {(![info exists st($w,compareVisible)]||$st($w,compareVisible))&&$st($w,residual) ne {}&&[llength [dict get $st($w,residual) rows]]>=2}]
    if {[info exists st($w,residualPanelShown)]&&$st($w,residualPanelShown)==$show} return
    set st($w,residualPanelShown) $show
    # The scientific canvas stays in its dedicated viewport for its whole
    # lifetime. Residual visibility changes only its sibling widgets; repeated
    # unmanage/remanage cycles can leave Tk geometry-maintenance callbacks stale.
    pack forget $w.right.residual $w.right.residualLabel
    if {$show} {pack $w.right.residual -in $w.right -side bottom -fill x;pack $w.right.residualLabel -side bottom -fill x}
    # Shared viewport chrome retains its dedicated canvas host through both
    # residual changes and recovery/history restoration.
    set parent [expr {[winfo exists $w.right.viewport]?"$w.right.viewport":"$w.right"}]
    if {[winfo manager $w.right.viewport.canvas] eq {}} {pack $w.right.viewport.canvas -in $parent -side top -fill both -expand 1}
}
