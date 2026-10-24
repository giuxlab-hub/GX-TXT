# SPDX-License-Identifier: GPL-3.0-or-later
# Ordinary view changes submit bounded domain state; explicit boundaries project.
proc ::GX::CurveWorkbench::_save {w} {
    variable st
    foreach flag {importTransaction historyRecording historyRestoring} {if {[info exists st($w,$flag)] && $st($w,$flag)} return}
    if {![info exists st($w,historyReady)] || !$st($w,historyReady) || [_historyBrowsing $w]} return

    if {[info exists st($w,restoreFailed)] && $st($w,restoreFailed)} {error {Saved workspace preserved after an incomplete restore. Restore its source and reopen.}}
    if {[info exists st($w,viewSavePending)]} {after cancel $st($w,viewSavePending);set st($w,viewSavePending) {}}
    set prior [dict get [::GX::scientificHistoryViewerStatus $w] accepted_revision]
    set receipt [::GX::scientificHistoryViewerAuxiliary $w [_historyAuxCapture $w]]
    if {[dict get $receipt accepted] && [dict get $receipt revision]>$prior} {set st($w,historyDirty) 1}
    return $receipt
}
proc ::GX::CurveWorkbench::_historyProject {w record} {
    variable st
    if {$st($w,token) ne [::GX::interactiveDocumentSessionToken]} {error {Session changed; refusing Workspace projection}}
    if {[_historyBrowsing $w]} {error {Return to Latest before projecting the Workspace}}
    if {$st($w,document) ne {} && [info exists st($w,ownerGeneration)] && [dict get [::GX::interactiveDocumentMetadata $st($w,document)] generation] ne $st($w,ownerGeneration)} {error {Workspace owner was replaced}}
    set result [_writeWorkspace $w $record]
    set owner [::GX::interactiveDocumentRead $st($w,document) stored]
    set st($w,ownerGeneration) [dict get $owner generation]
    set st($w,ownerRevision) [dict get $owner revision]
    if {![info exists st($w,lifecycleSubscription)]} {set st($w,lifecycleSubscription) [::GX::interactiveDocumentLifecycleSubscribe [list ::GX::CurveWorkbench::_documentOwnerInvalidated $w] $w $st($w,document)]}
    _parameterPersistBindings $w
    return $result
}
# Explicit owner/interop barrier; this does not mark an unsaved draft Saved.
proc ::GX::CurveWorkbench::_flushWorkspace {w} {
    variable st
    if {[_historyBrowsing $w]} {error {Return to Latest before saving or exporting the Workspace}}
    set receipt [_save $w]
    if {$receipt ne {} && [dict exists $receipt accepted] && ![dict get $receipt accepted]} {error "Presentation state was not accepted: [::GX::datasetPublicationV2DictDefault $receipt error {retry Save}]"}
    if {$st($w,document) eq {}} {
        ::GX::scientificHistoryViewerFlush $w 30000 0
        _historyProject $w [::GX::scientificHistoryViewerRecord $w]
        ::GX::scientificHistoryViewerBindDocument $w $st($w,document)
        set st($w,historyDocument) $st($w,document)
        ::GX::scientificHistoryViewerFlush $w 30000 0
    } else {
        if {$st($w,historyDocument) ne $st($w,document)} {::GX::scientificHistoryViewerBindDocument $w $st($w,document);set st($w,historyDocument) $st($w,document)}
        ::GX::scientificHistoryViewerFlush $w
    }
    return [::GX::scientificHistoryViewerStatus $w]
}
proc ::GX::CurveWorkbench::_saveExplicit {w} {
    variable st
    if {[info exists st($w,closingFailedRestore)]} return
    if {[_historyBrowsing $w]} {error {Historical state is read-only. Return to latest or explicitly restart here before saving.}}
    _flushWorkspace $w
    if {[dict get [::GX::workbenchRecoveryInspect $st($w,document)] status] eq {absent}} {::GX::workbenchRecoveryBegin $st($w,document)}
    set result [::GX::workbenchRecoveryMarkSaved $st($w,document)]
    if {[dict get $result status] eq {corrupt}} {error "Workspace saved; recovery checkpoint unavailable: [dict get $result reason]"}
    set st($w,historyDirty) 0;set st($w,recoveryNotice) {};set st($w,status) {Workspace saved; accepted History is durable and projected.}
    return [::GX::scientificHistoryViewerStatus $w]
}

proc ::GX::CurveWorkbench::_close {w} {
    variable st
    if {[_historyBrowsing $w]} {::GX::scientificHistoryViewerNavigate $w latest}
    if {[info exists st($w,restoreFailed)]&&$st($w,restoreFailed)} {set st($w,closingFailedRestore) 1}
    foreach key {viewDrawPending viewSavePending} {
        if {[info exists st($w,$key)]} {after cancel $st($w,$key);set st($w,$key) {}}
    }
    if {$st($w,publishBusy)} {_publicationCancel $w;return}
    set subscription [expr {[info exists st($w,lifecycleSubscription)] ? $st($w,lifecycleSubscription) : ""}]
    if {$st($w,token) eq [::GX::interactiveDocumentSessionToken] && ![info exists st($w,historyDiscard)]} {
        _cancelGesture $w;_pointSyncApply $w;_saveExplicit $w
    } else {_pointSyncCancel $w;_cancelPointDrag $w;_cancelDirectionDrag $w}
    if {[info exists st($w,historyReady)] && $st($w,historyReady)} {::GX::scientificHistoryViewerDetach $w 0;set st($w,historyReady) 0}
    _wheelDrawDispose $w
    if {[info exists st($w,configurationSubscription)]} {::GX::configurationUnsubscribe $st($w,configurationSubscription)}
    set scene $st($w,scene)
    _coordinateDispose $w
    if {$st($w,token) eq [::GX::interactiveDocumentSessionToken] && $st($w,document) ne {}} {::GX::interactiveDocumentResourceCollect $st($w,document)}
    dict for {id record} $st($w,curves) {
        if {[dict exists $record source_token]&&[dict get $record source_token] ne {}} {::GX::curveSourceClose [dict get $record source_token]}
    }
    _cancelDirectionDrag $w
    _cancelPointDrag $w
    _pointSyncApply $w
    _pointSyncCancel $w
    if {$st($w,selectionScene) ne ""&&$st($w,selectionScene)!=$st($w,scene)} {catch {::GX::Native2D::core destroy $st($w,selectionScene)}}
    _residualDispose $w
    catch {::GX::Native2D::core destroy $st($w,scene)}
    if {[info exists st($w,planarFocusJob)]} {after cancel $st($w,planarFocusJob)}
    if {[info exists st($w,planarToken)]} {catch {::GX::native3DPlanarEditCancel $st($w,planarToken)}}
    foreach key [array names st "$w,*"] {unset st($key)}
    destroy $w
    if {$subscription ne ""} {::GX::interactiveDocumentLifecycleUnsubscribe $subscription}
    if {![winfo exists $w]} {::GX::native2DRasterSceneDispose $scene}
}

# Serialize through existing Dataset bindings and document resources.
proc ::GX::CurveWorkbench::_writeWorkspace {w {history {}}} {
    variable st
    if {$st($w,selectionScene) ne "" && [::GX::Native2D::core drag_active $st($w,selectionScene)]} {error "Finish or cancel the point drag before saving the workspace"}
    _pointSyncApply $w
    if {$st($w,token) ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen Curve Workbench"}
    set curves [dict create]
    dict for {id record} $st($w,curves) {
        dict set record direction [::GX::Native2D::core direction_marker $st($w,scene) [dict get $record native]]
        dict set st($w,curves) $id $record
        dict set curves $id [_persistCurve $w $record]
    }
    set payload [dict create version 2 curves $curves next $st($w,next) active $st($w,active) selected_indices [_selected $w] view [::GX::Native2D::core view $st($w,scene)] reference $st($w,reference) target $st($w,target) external_feedback $st($w,externalFeedback) view_requested [::GX::Native2D::core view_requested $st($w,scene)] aspect [::GX::Native2D::core aspect $st($w,scene)] grid [::GX::Native2D::core grid $st($w,scene)] background [::GX::Native2D::core background $st($w,scene)]]
    dict set payload presentation [::GX::Native2D::core presentation $st($w,scene)]
    dict set payload composition_settings [dict create bridge_kind $st($w,bridgeKind) subdivisions $st($w,bridgeSubdivisions) tolerance $st($w,bridgeTolerance)]
    dict set payload cad_workspace [_cadState $w]
    if {$history ne {}} {dict set payload cad_workspace scientific_recipe $history}
    if {[info exists st($w,historyReady)] && $st($w,historyReady)} {dict set payload cad_workspace history_auxiliary [::GX::scientificHistoryViewerAuxiliary $w]}
    if {$st($w,active) ne ""&&[_bulkRecord [_record $w $st($w,active)]]} {dict set payload selection_descriptor [_pointSelectionDescriptor $w]}
    if {$st($w,document) eq ""} {
        set name [expr {[info exists st($w,workspaceName)]?$st($w,workspaceName):"Curve Workbench [expr {[llength [::GX::sessionWorkspaceList]]+1}]"}]
        set doc [::GX::sessionWorkspaceCreate curve_workbench $name $payload]
        set st($w,document) [dict get $doc id]
    } else {::GX::sessionWorkspacePromote $st($w,document);::GX::sessionWorkspaceUpdate $st($w,document) $payload}
}
