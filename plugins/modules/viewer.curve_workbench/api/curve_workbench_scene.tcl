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
    if {$st($w,cadTool) ne "none"&&$st($w,cadDrag) eq {}&&![::GX::Native2D::core drag_active $st($w,scene)]} {_cadSelectNative $w}
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
    set canvas $w.right.viewport.canvas
    # Paint selected details last: coincident controls from another constituent
    # or an image/annotation must not hide the actual selected point.
    foreach ref $st($w,sketchSelection) {
        if {[info exists st($w,partTarget)]&&$st($w,partTarget) ne {}&&[lindex $st($w,partTarget) 0] eq [dict get $ref logical]} continue
        set record [_record $w [dict get $ref logical]]
        if {![_curveVisible $w $record]} continue
        if {[dict get $ref semantic_kind] eq "object"} {
            # Active is property focus. Only actual object membership paints the
            # whole geometry, using the existing Native presentation snapshot.
            set object [::GX::native2DPresentationObjectSnapshot $st($w,scene) [dict get $ref object] 4096]
            if {$object ne {}} {
                dict set object style color {0.847 0.529 0 1};dict set object style line_width 5
                if {[dict get $object kind] eq "curve"} {dict set object style marker 0}
                if {[::GX::datasetPublicationV2DictDefault $record display_style straight] eq "points"} {
                    set paths {};foreach path [dict get $object paths] {foreach point $path {lappend paths [list $point]}}
                    dict set object paths $paths;dict set object style marker 2
                }
                dict unset object marker
                dict unset object part_markers
                ::GX::native2DCanvasDrawObject $canvas $object [$canvas cget -background] semantic_object_selection
            }
        } elseif {[dict get $ref semantic_kind] eq "segment"} {
            set points [::GX::Native2D::core interaction_render $st($w,scene) $ref]
            if {[llength $points]>=2} {$canvas create line {*}[concat {*}$points] -fill #d88700 -width 5 -tags semantic_segment_selection}
        }
    }
    foreach ref $st($w,sketchSelection) {
        if {[info exists st($w,partTarget)]&&$st($w,partTarget) ne {}&&[lindex $st($w,partTarget) 0] eq [dict get $ref logical]} continue
        if {[dict get $ref semantic_kind] ni {control point}} continue
        set record [_record $w [dict get $ref logical]]
        if {![_curveVisible $w $record]} continue
        lassign [::GX::Native2D::core device $st($w,scene) [::GX::Native2D::core interaction_resolve $st($w,scene) $ref]] x y
        $canvas create rectangle [expr {$x-6}] [expr {$y-6}] [expr {$x+6}] [expr {$y+6}] -fill #ffbd3a -outline #573700 -width 2 -tags semantic_point_selection
    }
    ::GX::native2DCanvasViewportClip $canvas $st($w,scene)
}
