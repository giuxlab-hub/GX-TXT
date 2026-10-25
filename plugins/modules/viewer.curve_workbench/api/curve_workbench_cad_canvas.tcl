# SPDX-License-Identifier: GPL-3.0-or-later
# Domain adapter only: CORE owns common input/selection/gesture sequencing.
proc ::GX::CurveWorkbench::_cadCanvas {w} {
    variable st
    if {![info exists st($w,selectionShape)]} {set st($w,selectionShape) click}
    set cad [_cadController $w]
    if {![info exists st($w,cadCanvas)] || ![llength [info commands $st($w,cadCanvas)]]} {
        set callbacks {}
        foreach {key suffix} {guard Guard scope Scope targets Targets admit Admit begin Begin selected Selected preview Preview committed Committed cancelled Cancelled rollback Rollback refresh Refresh navigation Navigation error Error advanced Advanced} {dict set callbacks $key [list ::GX::CurveWorkbench::_cadCanvas$suffix $w]}
        set st($w,cadCanvas) [::GX::native2DCadCanvasAttach $w.right.viewport.canvas $st($w,scene) [dict create context $cad bind_events 0 advanced_dispatch 0 external_render 1 callbacks $callbacks]]
    } elseif {[dict get [$st($w,cadCanvas) state] context] ne $cad} {$st($w,cadCanvas) associate $st($w,scene) [dict create context $cad]}
    $st($w,cadCanvas) configure [dict create selection_target $st($w,selectionTarget) object_snap $st($w,cadObjectSnap)]
    return $st($w,cadCanvas)
}
proc ::GX::CurveWorkbench::_cadCanvasGuard {w event} {
    variable st
    if {![info exists st($w,scene)] || ![winfo exists $w] || $st($w,token) ne [::GX::interactiveDocumentSessionToken] || $st($w,publishBusy)} {return 0}
    if {[dict exists $event scene] && [dict get $event scene]!=$st($w,scene)} {return 0}
    if {[dict exists $event host] && [info exists st($w,cadCanvas)] && [dict get $event host] ne $st($w,cadCanvas)} {return 0}
    if {$st($w,document) ne {} && [info exists st($w,ownerGeneration)]} {
        if {[catch {set actual [::GX::interactiveDocumentMetadata $st($w,document)]}]} {return 0}
        if {[dict get $actual generation] ne $st($w,ownerGeneration)} {return 0}
    }
    return 1
}
proc ::GX::CurveWorkbench::_cadCanvasScope {w event} {return [_selectionScope $w]}
proc ::GX::CurveWorkbench::_cadCanvasTargets {w event} {
    return [lmap id [_cadTargets $w] {dict get [_record $w $id] native}]
}
proc ::GX::CurveWorkbench::_cadCanvasLogical {w natives} {
    set reverse [_logicalNativeMap $w];set ids {}
    foreach native $natives {if {![dict exists $reverse $native]} {error {CAD target no longer belongs to this Workspace}};lappend ids [dict get $reverse $native]}
    return $ids
}
proc ::GX::CurveWorkbench::_cadCanvasMetricAdmit {w ids} {
    foreach id $ids {
        set record [_record $w $id];set units [_coordinateUnits $record]
        if {[_coordinateSourceRelations $record] ne {}} {error {Physical CAD operations require an explicitly normalized common coordinate frame}}
        set frame [::GX::native2DComparisonFrame geometry $units $units]
        set matrix [dict get $frame reference_matrix]
        if {[lindex $matrix 0]!=[lindex $matrix 3]} {error {Normalize X/Y to one common working unit before a metric CAD transformation}}
    }
}
proc ::GX::CurveWorkbench::_cadCanvasAdmit {w event} {
    variable st
    if {![_cadCanvasGuard $w $event]} {error {Session or Document changed; reopen Curve Workbench}}
    if {[_historyBrowsing $w]} {error {Return to the latest editable History state before editing}}
    set ids [_cadCanvasLogical $w [dict get $event objects]];set operation [dict get $event operation]
    _coordinatePlaneAdmit $w $ids
    foreach id $ids {
        set r [_record $w $id]
        if {[dict get $r locked] || [_bulkRecord $r] || ($operation eq {points} && ![dict get $r edited] && [dict get $r source] ne {})} {
            if {$operation in {control points}} {return 0}
            error {Unlock the targets or Convert to Native before a CAD drag}
        }
    }
    if {$operation in {rotate mirror}} {_cadCanvasMetricAdmit $w $ids}
    if {[dict get $event phase] ne {begin}} {
        set drag [expr {$operation eq {control}?$st($w,handleDrag):$operation eq {points}?$st($w,semanticPointDrag):$st($w,cadDrag)}]
        if {[dict exists $drag coordinate_key]} {_coordinateControlCheck $w $ids [dict get $drag coordinate_key]}
        if {[dict exists $event proposal snap_target]} {
            set candidate [dict get $event proposal snap_target]
            set target [lindex [_cadCanvasLogical $w [list [dict get $candidate object]]] 0]
            _coordinatePlaneAdmit $w [concat $ids [list $target]]
            set st($w,status) "Object snap: [dict get [_record $w $target] name], original Native point [dict get $candidate index]"
        }
    }
    return 1
}
proc ::GX::CurveWorkbench::_cadCanvasBegin {w event} {
    variable st
    set ids [_cadCanvasLogical $w [dict get $event objects]];set op [dict get $event operation]
    _pointSyncApply $w
    set before [_snapshotIds $w $ids];set st($w,cadCanvasBefore) $before
    set common [dict create before $before ids $ids coordinate_key [_coordinateControlKey $w $ids]]
    if {$op eq {control}} {
        set st($w,handleDrag) [dict merge $common [dict create reference [dict get $event reference] target {}]]
    } elseif {$op eq {points}} {
        set st($w,semanticPointDrag) [dict merge $common [dict create moved 0]]
    } else {
        set st($w,cadDrag) [dict merge $common [dict create handle [dict get $event handle] active $st($w,active) selected_indices [_selected $w] delta {} widgets [_cadFreeze $w]]]
        set st($w,cadSelectionPending) {}
    }
    return $op
}
proc ::GX::CurveWorkbench::_cadCanvasSelected {w event} {
    variable st
    # Adopt CORE's native set ID before any legacy projection helper is called.
    set st($w,semanticSet) [dict get $event selection id]
    _semanticSync $w;_planarSelectionChanged $w
    set ref [dict get $event reference]
    if {$ref ne {}} {
        set id [lindex [_cadCanvasLogical $w [list [dict get $ref object]]] 0]
        set changed [expr {$st($w,active) ne $id}];set st($w,active) $id
        if {$changed || $st($w,selectionObject) ne [dict get $ref object]} {_selectionScene $w}
        if {[dict get $ref semantic_kind] eq {point}} {set st($w,pointPageStart) [expr {200*([dict get $ref index]/200)}]}
    }
    _curveList $w;_pointList $w
}
proc ::GX::CurveWorkbench::_cadCanvasPreview {w event} {
    variable st
    if {[dict get $event definition] eq {}} {_toolPreviewClear $w;return}
    _toolPreview $w [dict get $event definition]
    dict set st($w,handleDrag) target [dict get $event target]
}
proc ::GX::CurveWorkbench::_cadCanvasCommitted {w event} {
    variable st
    set op [dict get $event operation]
    if {$op eq {control}} {set drag $st($w,handleDrag);set st($w,handleDrag) {};_toolPreviewClear $w;set st($w,snapCandidate) {}} elseif {$op eq {points}} {set drag $st($w,semanticPointDrag);set st($w,semanticPointDrag) {}} else {set drag $st($w,cadDrag);set st($w,cadDrag) {};_cadThaw $w [dict get $drag widgets]}
    set ids [dict get $drag ids]
    foreach logical [dict keys [dict get $drag before]] {if {[dict exists $st($w,curves) $logical] && $logical ni $ids} {lappend ids $logical}}
    set changed [expr {$op eq {pivot} && [dict get $event changed]}]
    foreach id $ids {
        _syncSamples $w $id
        if {[dict get [_record $w $id] samples] ne [dict get $drag before $id samples]} {set changed 1}
    }
    if {$changed} {
        if {$op ni {control points pivot}} {
            set operation [dict create operation gizmo_[dict get $event handle] api_id NATIVE2D_API_v1 targets $ids parameters [dict get $event proposal] lifecycle absolute_native_drag]
            foreach id $ids {set r [_record $w $id];dict lappend r operations $operation;dict set st($w,curves) $id $r}
        }
        _selectionScene $w
        _history $w [dict get $drag before] $ids
    }
    _pointSyncApply $w;_cadApplyQueuedSelection $w
    set st($w,status) {Native CAD operation committed through the shared Canvas Host.}
    unset -nocomplain st($w,cadCanvasBefore)
    if {$st($w,historyReady)} {return [::GX::scientificHistoryViewerStatus $w]}
    return {}
}
proc ::GX::CurveWorkbench::_cadCanvasCancelled {w event} {
    variable st
    switch -- [dict get $event operation] {
        control {set st($w,handleDrag) {};_toolPreviewClear $w;set st($w,snapCandidate) {}}
        points {set st($w,semanticPointDrag) {};_pointSyncCancel $w}
        pan {set st($w,drag) {}}
        default {if {$st($w,cadDrag) ne {}} {set saved [dict get $st($w,cadDrag) widgets];set st($w,cadDrag) {};_cadThaw $w $saved;_cadApplyQueuedSelection $w}}
    }
    unset -nocomplain st($w,cadCanvasBefore)
    set st($w,status) {Native CAD gesture cancelled; original scientific state retained.}
}
proc ::GX::CurveWorkbench::_cadCanvasRollback {w event} {
    variable st
    # Commit hooks own scientific recovery if their Document/History update fails.
    if {[info exists st($w,cadCanvasBefore)]} {_restoreSnapshot $w $st($w,cadCanvasBefore)}
}
proc ::GX::CurveWorkbench::_cadCanvasRefresh {w event} {
    if {[dict get $event final]} {_draw $w} elseif {[dict get $event reason] in {navigation resize}} {_viewportDrawLater $w} else {_viewDrawLater $w}
}
proc ::GX::CurveWorkbench::_cadCanvasNavigation {w event} {variable st;if {[dict get $event phase] eq {finished}} {set st($w,drag) {}};_viewPersistLater $w}
proc ::GX::CurveWorkbench::_cadCanvasError {w event} {variable st;set st($w,status) [dict get $event error];_notice $w [dict get $event error];_draw $w}
