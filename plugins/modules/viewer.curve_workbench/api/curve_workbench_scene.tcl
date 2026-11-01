# SPDX-License-Identifier: GPL-3.0-or-later
# Scene presentation order is explicit. Each stage paints its own feature and
# cannot delegate to an earlier version of the complete renderer. The existing
# 16 ms scheduler owns frame timing; rendering does not save workspace state.
proc ::GX::CurveWorkbench::_draw {w} {
    variable st
    if {![info exists st($w,scene)]||![winfo exists $w.right.viewport.canvas]} return
    if {[_coordinateFrameSync $w]} {_curveList $w}
    _semanticSync $w
    # Gizmo drawing and hit testing use complete CAD target bounds. Point and
    # control membership remain owned by the shared semantic selection set.
    if {$st($w,cadTool) ne "none" && $st($w,cadDrag) eq {} && [dict get [[_cadCanvas $w] state] target_flags_mutable]} {_cadSelectNative $w}
    set feedback {}
    foreach key {toolPreview mirrorPreview previewNative} {
        if {[info exists st($w,$key)]&&$st($w,$key) ne {}} {lappend feedback $st($w,$key)}
    }
    ::GX::native2DSceneFeedback $st($w,scene) $feedback
    _coordinatePolicy $w
    _coordinateMetricPolicy $w
    _residualLayout $w
    _drawScene $w
    _drawGizmo $w
    _drawJoinTarget $w
    _drawMeasurements $w
    _drawCreationPreview $w
    _drawRelationships $w
    _drawConstructionPlaces $w
    _drawTangentHandles $w
    _drawReferenceImages $w
    _partDraw $w
    _toolStates $w
    _drawSemanticSelection $w
    if {[info exists st($w,cadCanvas)] && [llength [info commands $st($w,cadCanvas)]]} {$st($w,cadCanvas) overlays}
    set controls [::GX::native2DViewportPanelWidget $w.right.viewport.canvas controls]
    if {[winfo exists $controls.body.fit_selected]} {
        $controls.body.fit_selected state [expr {[dict exists $st($w,curves) $st($w,active)]?"!disabled":"disabled"}]
        set ::GX::ViewportHost::toggles($w.right.viewport.canvas,object_snap) $st($w,cadObjectSnap)
    }
    if {[info exists st($w,polygonVertices)]&&$st($w,polygonVertices) ne {}} {
        set points {}
        foreach p $st($w,polygonVertices) {lappend points {*}[::GX::Native2D::core device $st($w,scene) $p]}
        if {[llength $points]>=4} {$w.right.viewport.canvas create line {*}$points -fill #536fc1 -width 2 -dash {4 3} -tags selection_polygon}
        foreach {x y} $points {$w.right.viewport.canvas create oval [expr {$x-3}] [expr {$y-3}] [expr {$x+3}] [expr {$y+3}] -fill #536fc1 -tags selection_polygon}
    }
}

proc ::GX::CurveWorkbench::_drawSemanticSelection {w} {
    variable st
    set exclude {};set points {}
    if {[info exists st($w,partTarget)] && $st($w,partTarget) ne {} && [dict exists $st($w,curves) [lindex $st($w,partTarget) 0]]} {lappend exclude [dict get [_record $w [lindex $st($w,partTarget) 0]] native]}
    dict for {id record} $st($w,curves) {if {[::GX::datasetPublicationV2DictDefault $record display_style straight] eq {points}} {lappend points [dict get $record native]}}
    ::GX::native2DCadSelectionPresent [_cadController $w] $w.right.viewport.canvas [dict create exclude_objects $exclude point_objects $points]
}
