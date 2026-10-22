# SPDX-License-Identifier: GPL-3.0-or-later
# Save/close sequencing belongs here. CORE continues to own document identity,
# resources, recovery journals and lifecycle subscriptions.
proc ::GX::CurveWorkbench::_save {w} {
    variable st
    if {[info exists st($w,importTransaction)]&&$st($w,importTransaction)} return
    if {[info exists st($w,historyBrowsing)]&&$st($w,historyBrowsing)} return
    # A partial source restore must never replace the saved binding-only payload.
    if {[info exists st($w,restoreFailed)]&&$st($w,restoreFailed)} {
        if {[info exists st($w,closingFailedRestore)]} return
        error {Saved workspace preserved after an incomplete restore; restore its source and reopen before saving.}
    }
    if {[info exists st($w,viewSavePending)]} {after cancel $st($w,viewSavePending);set st($w,viewSavePending) {}}
    if {$st($w,document) ne ""&&[info exists st($w,ownerGeneration)]} {
        set owner {}
        foreach metadata [::GX::interactiveDocumentList] {
            if {[dict get $metadata id] eq $st($w,document)} {set owner $metadata;break}
        }
        if {$owner eq {}||[dict get $owner generation] ne $st($w,ownerGeneration)} {
            error "Document owner was deleted or replaced; the stale workspace was not saved. Reopen Curve Workbench."
        }
    }
    # Saving an unsaved workspace establishes its existing Document owner.
    # Capture only the current public view before that legitimate transition.
    set residualAxes {}
    if {$st($w,document) eq {} && [info exists st($w,residualWidget)] && $st($w,residualWidget) ne {}} {
        catch {set residualAxes [dict get [::GX::PlotDatasetAPIv4::widgetReceipt $st($w,residualWidget)] axes]}
    }
    set result [_writeWorkspace $w]
    if {[dict get [::GX::workbenchRecoveryInspect $st($w,document)] status] eq "absent"} {
        if {[catch {::GX::workbenchRecoveryBegin $st($w,document)} message]} {
            set st($w,recoveryNotice) "Workspace committed; recovery journal unavailable: $message"
        }
    }
    set owner [::GX::interactiveDocumentRead $st($w,document)]
    set st($w,ownerGeneration) [dict get $owner generation]
    set st($w,ownerRevision) [dict get $owner revision]
    set st($w,ownerPayload) [dict remove [dict get $owner payload] workspace_metadata]
    if {![info exists st($w,lifecycleSubscription)]} {
        set st($w,lifecycleSubscription) [::GX::interactiveDocumentLifecycleSubscribe [list ::GX::CurveWorkbench::_documentOwnerInvalidated $w] $w $st($w,document)]
    }
    _parameterPersistBindings $w
    if {[info exists st($w,residualWidget)] && $st($w,residualWidget) ne {}} {
        # A committed Workspace save does not depend on display preparation.
        # Rebinding is explicit presentation work; a rejected view stays stale.
        if {[catch {
            _drawResidual $w
            if {$residualAxes ne {} && $st($w,residualWidget) ne {}} {::GX::PlotDatasetAPIv4::widgetView $st($w,residualWidget) restore $residualAxes}
        } message]} {set st($w,comparisonText) "Previous comparison display — $message Select Compare to refresh."}
    }
    return $result
}

proc ::GX::CurveWorkbench::_saveExplicit {w} {
    variable st
    if {[info exists st($w,closingFailedRestore)]} return
    if {[info exists st($w,historyBrowsing)]&&$st($w,historyBrowsing)} {set st($w,status) {Historical state is read-only. Return to latest or explicitly restart here before saving.};return}
    _save $w
    if {[catch {set result [::GX::workbenchRecoveryMarkSaved $st($w,document)]} message]} {set result [dict create status corrupt reason $message]}
    if {[dict get $result status] eq "corrupt"} {
        set st($w,recoveryNotice) "Workspace saved; recovery journal remains unavailable: [dict get $result reason]"
        set st($w,status) "Workspace saved."
    } else {
        set st($w,recoveryNotice) ""
        set st($w,status) "Workspace saved; recovery journal compacted and marked clean."
    }
}

proc ::GX::CurveWorkbench::_close {w} {
    variable st
    if {[info exists st($w,historyBrowsing)]&&$st($w,historyBrowsing)} {_timelineBrowse $w $st($w,historyCount)}
    if {[info exists st($w,restoreFailed)]&&$st($w,restoreFailed)} {set st($w,closingFailedRestore) 1}
    foreach key {viewDrawPending viewSavePending} {
        if {[info exists st($w,$key)]} {after cancel $st($w,$key);set st($w,$key) {}}
    }
    if {[info exists st($w,configurationSubscription)]} {::GX::configurationUnsubscribe $st($w,configurationSubscription)}
    set scene $st($w,scene)
    if {$st($w,publishBusy)} {_publicationCancel $w;return}
    _coordinateDispose $w
    set subscription [expr {[info exists st($w,lifecycleSubscription)] ? $st($w,lifecycleSubscription) : ""}]
    # Preserve dev-057's explicit recovery checkpoint followed by resource
    # collection and final payload commit. Resource ownership is still CORE's.
    if {$st($w,token) eq [::GX::interactiveDocumentSessionToken]} {
        _cancelGesture $w;_saveExplicit $w
    }
    if {$st($w,token) eq [::GX::interactiveDocumentSessionToken]} {
        _cancelGesture $w;_pointSyncApply $w;_save $w
        if {$st($w,document) ne ""} {::GX::interactiveDocumentResourceCollect $st($w,document)}
    } else {_pointSyncCancel $w;_cancelPointDrag $w;_cancelDirectionDrag $w}
    dict for {id record} $st($w,curves) {
        if {[dict exists $record source_token]&&[dict get $record source_token] ne {}} {::GX::curveSourceClose [dict get $record source_token]}
    }
    _cancelDirectionDrag $w
    _cancelPointDrag $w
    _pointSyncApply $w
    _pointSyncCancel $w
    if {$st($w,token) eq [::GX::interactiveDocumentSessionToken]} {_save $w}
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
proc ::GX::CurveWorkbench::_writeWorkspace {w} {
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
    if {$st($w,active) ne ""&&[_bulkRecord [_record $w $st($w,active)]]} {dict set payload selection_descriptor [_pointSelectionDescriptor $w]}
    if {$st($w,document) eq ""} {
        set name [expr {[info exists st($w,workspaceName)]?$st($w,workspaceName):"Curve Workbench [expr {[llength [::GX::sessionWorkspaceList]]+1}]"}]
        set doc [::GX::sessionWorkspaceCreate curve_workbench $name $payload]
        set st($w,document) [dict get $doc id]
    } else {::GX::sessionWorkspacePromote $st($w,document);::GX::sessionWorkspaceUpdate $st($w,document) $payload}
}
