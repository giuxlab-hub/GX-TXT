# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::CurveWorkbench::_documentOwnerInvalidated {w event} {
    variable st
    if {![info exists st($w,document)]||$st($w,document) ne [dict get $event document_id]||$st($w,token) ne [dict get $event session_token]} return
    _pointSyncCancel $w
    set st($w,ownerInvalidated) 1
    set st($w,token) "invalidated:[dict get $event owner_generation]"
    if {$st($w,publishBusy)} {
        # The existing cooperative Source/Transform checks cancel this request
        # at its next bounded boundary. Keep the owned Native scene alive until
        # the operation's finally block releases its worker and controls.
        set st($w,publishCancelled) 1
        set st($w,status) "Document owner removed; cancelling its active operation before closing the view."
    }
    _disposeInvalidated $w
}
proc ::GX::CurveWorkbench::_closeSources {sources} {
    set failures {}
    foreach source [lsort -unique $sources] {
        # A restored missing Dataset has owned cached geometry but no live
        # Curve Source handle. It cannot acquire or release a source token.
        if {$source eq {}} continue
        if {[catch {::GX::curveSourceClose $source} message]} {lappend failures $message}
    }
    if {$failures ne {}} {error "Workspace closed; source cleanup failed: [join $failures {; }]"}
}
proc ::GX::CurveWorkbench::_ownedSources {w} {
    variable st
    set result {};dict for {id record} $st($w,curves) {if {[dict exists $record source_token]} {lappend result [dict get $record source_token]}}
    return $result
}
proc ::GX::CurveWorkbench::_disposeInvalidated {w} {
    variable st
    if {![info exists st($w,ownerInvalidated)]} return
    if {$st($w,publishBusy)} {set st($w,disposeAfter) [after 50 [list ::GX::CurveWorkbench::_disposeInvalidated $w]];return}
    set sources [_ownedSources $w];set failures {}
    set disposed {}
    foreach property {selectionScene residualScene scene} {
        if {$st($w,$property) eq ""||$st($w,$property) in $disposed} continue
        lappend disposed $st($w,$property)
        if {[catch {
            if {[::GX::Native2D::core drag_active $st($w,$property)]} {::GX::Native2D::core drag_cancel $st($w,$property)}
            ::GX::Native2D::core destroy $st($w,$property)
        } message]} {lappend failures $message}
    }
    if {[info exists st($w,lifecycleSubscription)]} {::GX::interactiveDocumentLifecycleUnsubscribe $st($w,lifecycleSubscription)}
    _coordinateDispose $w
    foreach key [array names st "$w,*"] {unset st($key)}
    if {[winfo exists $w]} {destroy $w}
    if {[catch {_closeSources $sources} message]} {lappend failures $message}
    if {$failures ne {}} {error "Document view closed; cleanup failed: [join $failures {; }]"}
}
rename ::GX::CurveWorkbench::_load ::GX::CurveWorkbench::_load_lifecycle_base
proc ::GX::CurveWorkbench::_load {w} {
    variable st
    set result [_load_lifecycle_base $w]
    if {$st($w,document) ne ""} {_parameterBind $w}
    if {$st($w,document) ne ""} {set st($w,ownerGeneration) [dict get [::GX::interactiveDocumentRead $st($w,document)] generation]}
    if {$st($w,document) ne ""&&! [info exists st($w,lifecycleSubscription)]} {set st($w,lifecycleSubscription) [::GX::interactiveDocumentLifecycleSubscribe [list ::GX::CurveWorkbench::_documentOwnerInvalidated $w] $w $st($w,document)]}
    return $result
}
proc ::GX::CurveWorkbench::_buildDocuments {w} {
    
    ttk::button $w.cad.documents -text "Documents…" -command [list ::GX::interactiveDocumentManagerDialog $w]
    pack $w.cad.documents -side left -padx 3
}
