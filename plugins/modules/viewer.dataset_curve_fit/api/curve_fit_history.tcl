# SPDX-License-Identifier: GPL-3.0-or-later
# Host projections only. CORE Recipe owns History and Document owns persistence.
proc ::GX::DatasetCurveFit::_historyValidate {record} {
    workspaceValidate [dict get $record base]
    return 1
}
proc ::GX::DatasetCurveFit::_historyCapture {w} {return [_payload $w]}
proc ::GX::DatasetCurveFit::_historyReplay {record} {return [::GX::scientificHistoryState $record]}
::GX::scientificRecipeHostRegister viewer.dataset_curve_fit [dict create capture ::GX::DatasetCurveFit::_historyCapture validate ::GX::DatasetCurveFit::_historyValidate replay ::GX::DatasetCurveFit::_historyReplay]
proc ::GX::DatasetCurveFit::_historyGuard {w} {
    variable state
    return [expr {(![info exists state($w,loading)] || !$state($w,loading)) && ![info exists state($w,press)] && ![info exists state($w,pan)]}]
}
proc ::GX::DatasetCurveFit::_historyEditable {w} {
    return [expr {[_historyGuard $w] && [::GX::scientificHistoryViewerEditable $w]}]
}
proc ::GX::DatasetCurveFit::_historyCommit {w record} {
    set payload [::GX::scientificHistoryState $record]
    dict set payload scientific_history $record
    _writePayload $w $payload
}
proc ::GX::DatasetCurveFit::_historyRestore {w payload} {
    variable state
    set state($w,restoringWorkspace) 1
    try {
        _workspaceCapture $w
        foreach entry [dict values $state($w,sources)] {
            set source [dict get $entry state]
            if {[dict get $source sourceToken] ne {}} {::GX::curveSourceClose [dict get $source sourceToken]}
            if {[dict get $source selectionScene] ne $state($w,selectionScene)} {::GX::Native2D::core destroy [dict get $source selectionScene]}
        }
        ::GX::Native2D::core destroy $state($w,scene)
        ::GX::Native2D::core destroy $state($w,selectionScene)
        if {[info exists state($w,residualViewScene)]} {::GX::Native2D::core destroy $state($w,residualViewScene);unset state($w,residualViewScene)}
        set state($w,scene) [::GX::Native2D::core scene];set state($w,selectionScene) [::GX::Native2D::core scene]
        foreach field {source selectionObject accepted previewFitId sourceToken activeSource} {set state($w,$field) {}}
        foreach field {sources records preview rows filters loadedBinding rects sourceDescriptor} {set state($w,$field) {}}
        set state($w,previewAccepted) 0
        _applyPayload $w $payload
        if {$state($w,preview) ne {}} {
            set state($w,report) "[formula $state($w,preview)]\n[parameterReport $state($w,preview)]"
            _residualColumns $w $state($w,preview);_residualPageUi $w 0
        } else {set state($w,report) {}; $w.right.residuals.table delete [$w.right.residuals.table children {}]}
        _uiModelFields $w;_uiDomainFields $w
        $w.actions.accept configure -state [expr {$state($w,preview) ne {} && !$state($w,previewAccepted) ? "normal" : "disabled"}]
        $w.actions.publish configure -state [expr {$state($w,preview) ne {} ? "normal" : "disabled"}]
        $w.actions.export configure -state [expr {$state($w,records) ne {} ? "normal" : "disabled"}]
        redraw $w
    } finally {unset -nocomplain state($w,restoringWorkspace)}
}
proc ::GX::DatasetCurveFit::_historyAttach {w} {
    variable state
    if {$state($w,sessionToken) eq {}} return
    set record {}
    if {$state($w,documentId) ne {}} {set record [::GX::datasetPublicationV2DictDefault [dict get [::GX::interactiveDocumentRead $state($w,documentId)] payload] scientific_history {}]}
    ::GX::scientificHistoryViewerAttach $w viewer.dataset_curve_fit [dict create capture [list ::GX::DatasetCurveFit::_historyCapture $w] restore [list ::GX::DatasetCurveFit::_historyRestore $w] commit [list ::GX::DatasetCurveFit::_historyCommit $w] guard [list ::GX::DatasetCurveFit::_historyGuard $w]] $record
    ::GX::scientificHistoryViewerStrip $w $w.footer $w.footer.status modules.dataset_curve_fit.history_strip [list -fill x -before $w.footer.coordinateReadout]
    ::GX::viewerCommandMenusRefresh $w
}
proc ::GX::DatasetCurveFit::_commandEnabled {w id} {
    variable state
    if {$id eq "filter_cancel"} {return [expr {![ _historyGuard $w]}]}
    if {![_historyGuard $w]} {return 0}
    if {$id in {undo redo previous next latest branch}} {
        if {![dict exists $::GX::ScientificHistory::viewers $w]} {return 0}
        set adapter [dict get $::GX::ScientificHistory::viewers $w];set record [dict get $adapter record]
        set count [llength [dict get $record steps]];set cursor [dict get $record cursor]
        switch $id {
            undo {return [expr {![dict get $adapter browsing] && $cursor>0}]}
            redo {return [expr {![dict get $adapter browsing] && $cursor<$count}]}
            branch {return [expr {[dict get $adapter browse_cursor]<$count}]}
            default {return [expr {$count>0}]}
        }
    }
    if {$id in {timeline strip history_details workspace_close workspace_open workspace_manager}} {return 1}
    if {![_historyEditable $w]} {return 0}
    if {$id in {preview accept}} {return [expr {[$w.actions.$id cget -state] ne "disabled"}]}
    if {$id eq "workspace_clear_history"} {
        set record [::GX::scientificHistoryViewerRecord $w]
        return [expr {$state($w,documentId) ne {} && [dict get $record steps] ne {} && [dict get $record cursor]==[llength [dict get $record steps]]}]
    }
    if {$id in {workspace_duplicate workspace_rename workspace_delete workspace_clear_history}} {return [expr {$state($w,documentId) ne {}}]}
    dict for {name label} [_commandWidgets] {
        if {[string map {. _} $name] ne $id} continue
        set parts [split $name .];set widget [_widget $w [lindex $parts 0]].[join [lrange $parts 1 end] .]
        if {[$widget cget -state] eq "disabled"} {return 0}
        if {[string match workspace.actions.* $name] && $name ni {workspace.actions.reload workspace.actions.reverse workspace.actions.span}} {return [expr {[$w.left.viewport.content.sources.body.sources selection] ne {}}]}
        if {[string match accepted.* $name]} {return [expr {[$w.left.viewport.content.accepted.list curselection] ne {}}]}
        if {$name eq "filter.remove"} {return [expr {[$w.left.viewport.content.filters.list curselection] ne {}}]}
        if {[string match residualPager.* $name]} {return [expr {$state($w,preview) ne {}}]}
    }
    return 1
}
proc ::GX::DatasetCurveFit::_commandInvoke {w id} {
    if {$id in {undo redo previous next latest branch}} {return [::GX::scientificHistoryViewerNavigate $w $id]}
    if {$id eq "save"} {return [_saveState $w]}
    variable state
    if {$id eq "workspace_clear_history"} {return [::GX::scientificHistoryViewerClear $w $state($w,documentId)]}
    if {$id in {workspace_new workspace_open workspace_duplicate workspace_rename workspace_manager workspace_close workspace_delete}} {
        set callbacks [dict create current [list ::GX::DatasetCurveFit::_currentWorkspace $w] save [list ::GX::DatasetCurveFit::_saveState $w] close [list ::GX::DatasetCurveFit::_closeWindow $w] open ::GX::DatasetCurveFit::open]
        return [::GX::sessionWorkspaceViewerAction dataset_curve_fit $callbacks $w [string range $id 10 end]]
    }
    switch $id {
        configuration {return [::GX::configurationModuleDialog viewer.dataset_curve_fit $w]}
        panels_reset {return [_panelsReset $w]}
        translation {return [_uiSafe $w [list ::GX::DatasetCurveFit::_translationSettings $w]]}
        timeline {return [::GX::scientificHistoryViewerStripSet $w {mode History visible 1}]}
        strip {return [::GX::scientificHistoryViewerStripToggle $w]}
        history_details {return [::GX::scientificHistoryViewerDetails $w]}
        source_activate {return [_uiSafe $w [list ::GX::DatasetCurveFit::_workspaceSelect $w]]}
    }
    if {[string match selection_* $id] && $id in {selection_replace selection_add selection_subtract}} {set state($w,rectMode) [string totitle [string range $id 10 end]];return}
    if {$id in {preview accept}} {return [uplevel #0 [$w.actions.$id cget -command]]}
    dict for {name label} [_commandWidgets] {
        if {[string map {. _} $name] ne $id} continue
        set parts [split $name .];set widget [_widget $w [lindex $parts 0]].[join [lrange $parts 1 end] .]
        return [uplevel #0 [$widget cget -command]]
    }
}
proc ::GX::DatasetCurveFit::_commandsAttach {w} {
    set handlers {}
    dict for {id entry} [::GX::viewerCommandCatalog viewer.dataset_curve_fit] {
        dict set handlers $id [dict create command [list ::GX::DatasetCurveFit::_commandInvoke $w $id] enabled [list ::GX::DatasetCurveFit::_commandEnabled $w $id]]
    }
    ::GX::viewerCommandsAttach $w viewer.dataset_curve_fit $handlers
}
