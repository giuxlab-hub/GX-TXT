# SPDX-License-Identifier: GPL-3.0-or-later
# Explicit representation workflows; common Native2D, Numerical, Unit Registry,
# Dataset Publication and Interactive Documents remain the only authorities.
proc ::GX::CurveWorkbench::_primitivePublishOpen {w} {
    variable st
    set id [_active $w];set record [_record $w $id]
    if {![dict exists $record sketch_definition]} {error "Select a retained primitive; ordinary point curves use Publish selected curves"}
    set unit [lindex [_coordinateUnits $record] 0]
    ::GX::uiFieldFormCreate $w.primitivePublish "Publish retained primitive — finite Dataset; original preserved" [dict create dataset_id {type string label {New Canonical Dataset ID}} first {type number label {First normalized parameter}} last {type number label {Last normalized parameter}} total {type integer min 1 max 65536 label {Uniform parameter samples (complete finite Dataset)}}] [dict create dataset_id $st($w,resultId) first 0 last 1 total 257] [list ::GX::CurveWorkbench::_primitivePublishApply $w $st($w,token) $id] $w
}
proc ::GX::CurveWorkbench::_primitivePublishApply {w token id values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen publication"}
    set record [_record $w $id];set unit [lindex [_coordinateUnits $record] 0]
    set definition [::GX::Native2D::core sketch_definition $st($w,scene) [dict get $record native]]
    set result [::GX::native2DPrimitivePublish [_session] [dict get $values dataset_id] $definition $unit [dict remove $values dataset_id] $id [dict get $record name] viewer.curve_workbench]
    set st($w,status) "Published [dict get $values dataset_id] with [dict get $values total] explicit uniform-parameter samples and exact retained provenance. $id is unchanged."
    return $result
}
rename ::GX::CurveWorkbench::_publishSelected ::GX::CurveWorkbench::_publishSelected_representation_base
proc ::GX::CurveWorkbench::_publishSelected {w} {
    variable st
    set ids [_cadSelected $w]
    if {[llength $ids]==1&&[dict exists [_record $w [lindex $ids 0]] sketch_definition]} {return [_primitivePublishOpen $w]}
    _publishSelected_representation_base $w
}
proc ::GX::CurveWorkbench::_reconstructPrimitive {w} {
    variable st
    set id [_active $w];set source [_record $w $id]
    if {[dict get $source source] eq {}||[dict get $source edited]} {error "Select an immutable Dataset source curve"}
    _sourceSnapshotRequire $w $source
    set receipt [::GX::native2DPrimitiveReconstruct [_session] [dict get $source source] [dict get $source x] [dict get $source y]]
    return [_commitDefinition $w [dict get $receipt definition] [dict get $receipt working_unit] "[string totitle [dict get $receipt definition family]] reconstructed" $receipt [list $id]]
}
proc ::GX::CurveWorkbench::_fitPrimitiveOpen {w} {
    variable st
    set id [_active $w];set record [_record $w $id]
    if {[dict exists $record sketch_definition]} {error "This object is already retained. Select a Dataset or Native point curve for fitting"}
    set units [_coordinateUnits $record]
    if {[lindex $units 0] eq {}||[lindex $units 0] ne [lindex $units 1]} {error "Fitting geometric primitives requires declared common X/Y working units. Use Working units first."}
    set total [_pointCount $record]
    ::GX::uiFieldFormCreate $w.fitPrimitive "Scientific primitive fitting — Preview, review error, then Accept" [dict create family {type choice values {circle arc quadratic_bezier cubic_bezier} label {Retained family}} start [dict create type integer min 0 max [expr {$total-1}] label {First complete source point}] count [dict create type integer min 3 max [expr {min(65536,$total)}] label {Complete fitting points (no display reduction)}]] [dict create family circle start 0 count [expr {min(65536,$total)}]] [list ::GX::CurveWorkbench::_fitPrimitivePreview $w $st($w,token) $id] $w
    $w.fitPrimitive.actions.apply configure -text Preview
    ttk::button $w.fitPrimitive.actions.accept -text {Accept retained fit} -state disabled -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_fitPrimitiveAccept $w]]
    pack $w.fitPrimitive.actions.accept -side left -padx 4
    set st($w,fitReceipt) {}
    set st($w,fitQuality) {The original source is preserved. A fit is an approximation, even when measured residual is small.}
    ttk::label $w.fitPrimitive.quality -textvariable ::GX::CurveWorkbench::st($w,fitQuality) -wraplength 550 -padding 8
    pack $w.fitPrimitive.quality -side top -fill x -before $w.fitPrimitive.viewport
    wm protocol $w.fitPrimitive WM_DELETE_WINDOW [list ::GX::CurveWorkbench::_fitPrimitiveClose $w]
    $w.fitPrimitive.actions.close configure -command [list ::GX::CurveWorkbench::_fitPrimitiveClose $w]
    bind $w.fitPrimitive <Escape> [list ::GX::CurveWorkbench::_fitPrimitiveClose $w]
}
proc ::GX::CurveWorkbench::_fitPrimitivePreview {w token id values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen primitive fitting"}
    set record [_record $w $id];_sourceSnapshotRequire $w $record
    set start [dict get $values start];set count [dict get $values count]
    if {$start+$count>[_pointCount $record]} {error "Fitting range exceeds the complete source curve"}
    foreach cut [dict get $record breaks] {if {$cut>=$start&&$cut<$start+$count-1} {error "Fit one continuous range; this range crosses a gap"}}
    set points [::GX::Native2D::core points_page $st($w,scene) [dict get $record native] $start $count]
    set unit [lindex [_coordinateUnits $record] 0]
    ::GX::modulePublicApiActivate viewer.dataset_curve_fit DATASET_CURVE_FIT_API_v1
    set frozen [_cadFreeze $w]
    try {set receipt [::GX::DatasetCurveFit::fitPrimitive $points [dict get $values family] $unit]} finally {_cadThaw $w $frozen}
    if {$token ne [::GX::interactiveDocumentSessionToken]||![dict exists $st($w,curves) $id]||[::GX::Native2D::core points_page $st($w,scene) [dict get [_record $w $id] native] $start $count] ne $points} {error "Fitting source changed; preview again"}
    dict set receipt source_logical_identity $id;dict set receipt source_dataset_id [dict get $record source];dict set receipt source_snapshot [::GX::datasetPublicationV2DictDefault $record source_descriptor {}]
    dict set receipt source_points $points;dict set receipt range [dict create start $start count $count]
    set st($w,fitReceipt) $receipt
    _toolPreview $w [dict get $receipt definition]
    set quality [dict get $receipt quality]
    set st($w,fitQuality) "Approximate [dict get $values family] fit · $count complete points\n[::GX::StatisticsV1::report [dict get $quality statistical_results training] {rmse max_abs_error geometric_dispersion_score}]\nAccept creates a separate retained primitive."
    $w.fitPrimitive.actions.accept state !disabled;_draw $w
}
proc ::GX::CurveWorkbench::_fitPrimitiveAccept {w} {
    variable st
    if {$st($w,fitReceipt) eq {}} {error "Preview a fit first"}
    set receipt $st($w,fitReceipt);set source [dict get $receipt source_logical_identity];set record [_record $w $source]
    _sourceSnapshotRequire $w $record
    set range [dict get $receipt range]
    if {[::GX::Native2D::core points_page $st($w,scene) [dict get $record native] [dict get $range start] [dict get $range count]] ne [dict get $receipt source_points]} {error "Source changed; preview again before Accept"}
    set operation [dict remove $receipt source_points definition working_unit]
    _toolPreviewClear $w
    set id [_commitDefinition $w [dict get $receipt definition] [dict get $receipt working_unit] "[string totitle [dict get $receipt definition family]] fitted" $operation [list $source]]
    set st($w,fitReceipt) {};destroy $w.fitPrimitive;return $id
}
proc ::GX::CurveWorkbench::_fitPrimitiveClose {w} {
    variable st
    _toolPreviewClear $w;set st($w,fitReceipt) {};destroy $w.fitPrimitive;_draw $w
}
