# SPDX-License-Identifier: GPL-3.0-or-later
# Viewer host projections; CORE owns commands, History, cache and persistence.
proc ::GX::CurveViewer::_ready {w} {
    variable st
    if {![info exists st($w,scene)] || [catch {_scope $w}]} {return 0}
    return [expr {$st($w,sourceJob) eq {} && (![info exists st($w,restoring)] || !$st($w,restoring)) && (![info exists st($w,incomplete)] || !$st($w,incomplete))}]
}
proc ::GX::CurveViewer::_enabled {w id} {
    variable st
    if {$id in {cancel workspace_close workspace_open workspace_manager}} {return 1}
    if {![_historyGuard $w]} {return 0}
    if {$id in {undo redo previous next latest branch timeline}} {
        if {![dict exists $::GX::ScientificHistory::viewers $w]} {return 0}
        set adapter [dict get $::GX::ScientificHistory::viewers $w];set record [dict get $adapter record]
        set n [llength [dict get $record steps]];set cursor [dict get $record cursor]
        switch $id {
            undo {return [expr {![dict get $adapter browsing] && $cursor>0}]}
            redo {return [expr {![dict get $adapter browsing] && $cursor<$n}]}
            branch {return [expr {[dict get $adapter browse_cursor]<$n}]}
            default {return [expr {$n>0}]}
        }
    }
    if {$id in {configuration strip history_details}} {return 1}
    if {![::GX::scientificHistoryViewerEditable $w]} {return 0}
    set selected {};if {[winfo exists $w.sources]} {set selected [$w.sources selection]}
    if {$id in {filters preview properties label publish} && [llength $selected]!=1} {return 0}
    if {$id in {show hide remove fit_selected} && $selected eq {}} {return 0}
    if {$id eq "fit_all" && $st($w,records) eq {}} {return 0}
    if {$id eq "publish" && [::GX::workbenchExtensionProviderList viewer.curve_viewer utility] eq {}} {return 0}
    if {$id in {workspace_duplicate workspace_rename workspace_delete clear_history} && $st($w,document) eq {}} {return 0}
    if {$id eq "clear_history"} {
        set record [::GX::scientificHistoryViewerSummary $w]
        return [expr {[dict get $record steps] ne {} && [dict get $record cursor]==[llength [dict get $record steps]]}]
    }
    return 1
}
proc ::GX::CurveViewer::_invoke {w id} {
    variable st
    if {$id eq "save"} {return [::GX::sessionWorkspaceViewerAction curve_viewer [_workspaceCallbacks $w] $w save]}
    if {$id in {undo redo previous next latest branch}} {return [::GX::scientificHistoryViewerNavigate $w $id]}
    if {$id eq "timeline"} {return [::GX::scientificHistoryViewerStripSet $w {mode History visible 1}]}
    if {$id eq "strip"} {return [::GX::scientificHistoryViewerStripToggle $w]}
    if {$id eq "history_details"} {return [::GX::scientificHistoryViewerDetails $w]}
    if {$id eq "clear_history"} {return [::GX::scientificHistoryViewerClear $w $st($w,document)]}
    if {$id eq "configuration"} {return [::GX::configurationModuleDialog viewer.curve_viewer $w]}
    if {$id eq "cancel"} {return [_sourceCancel $w]}
    if {$id eq "label"} {return [_labelDialog $w [lindex [$w.sources selection] 0]]}
    if {[string match workspace_* $id]} {
        set callbacks [_workspaceCallbacks $w]
        return [::GX::sessionWorkspaceViewerAction curve_viewer $callbacks $w [string range $id 10 end]]
    }
    if {$id eq "publish"} {return [_safe $w [list ::GX::CurveViewer::_publish $w]]}
    return [uplevel #0 [$w.toolbar.$id cget -command]]
}
proc ::GX::CurveViewer::_menus {w} {
    foreach widget [winfo children $w.toolbar] {pack forget $widget}
    set handlers {}
    dict for {id label} [_commands] {dict set handlers $id [dict create command [list ::GX::CurveViewer::_invoke $w $id] enabled [list ::GX::CurveViewer::_enabled $w $id]]}
    foreach id {strip history_details} {dict set handlers $id [dict create command [list ::GX::CurveViewer::_invoke $w $id] enabled [list ::GX::CurveViewer::_enabled $w $id]]}
    ::GX::viewerCommandsAttach $w viewer.curve_viewer $handlers
    foreach {group ids} {Sources {add filters preview cancel} Curves {label properties show hide remove} View {fit_selected fit_all presentation configuration strip history_details} Export {export publish} Edit {undo redo previous next latest branch timeline}} {
        set button $w.toolbar.[string tolower $group]Menu;set menu $button.menu
        ttk::menubutton $button -text $group -menu $menu
        menu $menu -tearoff 0 -postcommand [list ::GX::viewerCommandMenusRefresh $w]
        foreach id $ids {::GX::viewerCommandMenuAdd $w $menu $id}
        pack $button -side left -padx 3
    }
    set index 0
    foreach id {workspace_new workspace_open save workspace_duplicate workspace_rename workspace_manager workspace_close workspace_delete} {::GX::viewerCommandMenuTrack $w $w.toolbar.workspace.menu $index $id;incr index}
    $w.toolbar.workspace.menu add separator
    ::GX::viewerCommandMenuAdd $w $w.toolbar.workspace.menu clear_history
    $w.toolbar.workspace.menu configure -postcommand "[list ::GX::viewerCommandMenusRefresh $w];[list ::GX::sessionWorkspaceViewerMenuRefresh $w.toolbar.workspace.menu]"
    pack $w.toolbar.workspace -side left -padx 3
    ::GX::uiMenuRowAttach $w.toolbar [pack slaves $w.toolbar]
}
proc ::GX::CurveViewer::_configurationChanged {w id} {
    if {![winfo exists $w] || $id ni {{} modules.curve_viewer.labels} || ![_ready $w] || ![::GX::scientificHistoryViewerEditable $w]} return
    _safe $w [list ::GX::CurveViewer::_labelPreferencesApply $w]
}
proc ::GX::CurveViewer::_labelPreferencesApply {w} {
    variable st
    set values [_labelValidate [dict get [::GX::configurationResolve modules.curve_viewer.labels] effective]]
    if {$values eq $st($w,labelPreferences)} return
    set st($w,labelPreferences) $values;_refresh $w;_redraw $w;_save $w {Configure legend and automatic labels}
}
proc ::GX::CurveViewer::_canonicalToken {w id} {
    variable st;_scope $w
    set record [dict get $st($w,records) $id]
    if {[dict get $record token] eq {}} {
        set token [::GX::curveSourceOpen $::GX::currentSession [dict get $record request]]
        try {
            if {[dict get [::GX::curveSourceDescribe $token] source_id] ne [dict get $record source_id]} {error {Source changed after display preparation; reopen before exact access}}
            dict set st($w,records) $id token $token;set token {}
        } finally {if {$token ne {}} {::GX::curveSourceClose $token}}
    }
    return [dict get $st($w,records) $id token]
}
proc ::GX::CurveViewer::_restoreStart {w payload} {
    variable st
    set st($w,labelPreferences) [_labelValidate [::GX::datasetPublicationV2DictDefault $payload label_preferences [dict get [::GX::configurationResolve modules.curve_viewer.labels] effective]]]
    set st($w,restoring) 1;set st($w,incomplete) 0;set st($w,restorePayload) $payload
    set st($w,restoreQueue) [dict get $payload records]
    set st($w,restoreStarted) [clock milliseconds];set st($w,firstReady) {}
    set st($w,restoreEpoch) [incr ::GX::CurveViewer::sourceEpoch]
    set st($w,restoreAfter) [after idle [list ::GX::CurveViewer::_restoreNext $w $st($w,restoreEpoch)]]
}
proc ::GX::CurveViewer::_restoreNext {w epoch} {
    variable st
    if {![winfo exists $w] || ![info exists st($w,restoreEpoch)] || $epoch!=$st($w,restoreEpoch)} return
    if {[catch {_scope $w} message]} {set st($w,incomplete) 1;set st($w,restoring) 0;set st($w,status) $message;return}
    set st($w,restoreAfter) {}
    if {$st($w,restoreQueue) eq {}} {
        set payload $st($w,restorePayload);set st($w,next) [dict get $payload next]
        ::GX::Native2D::core presentation $st($w,scene) [dict get $payload presentation]
        ::GX::Native2D::core view $st($w,scene) [dict get $payload view_requested]
        _refresh $w
        foreach id [::GX::datasetPublicationV2DictDefault $payload selected_ids {}] {if {[$w.sources exists $id]} {$w.sources selection add $id}}
        _select $w;_redraw $w
        set st($w,restoring) 0
        if {![dict exists $::GX::ScientificHistory::viewers $w]} {_historyAttach $w}
        set st($w,status) "Workspace loaded: [dict size $st($w,records)] source records. Exact publication uses canonical rows."
        ::GX::viewerCommandMenusRefresh $w
        return
    }
    set record [lindex $st($w,restoreQueue) 0];set st($w,restoreQueue) [lrange $st($w,restoreQueue) 1 end]
    if {[dict exists $record display_cache] && ![catch {
        set prepared [::GX::curveSourceDisplayCacheRestore $::GX::currentSession $st($w,document) [dict get $record display_cache] [dict get $record id] [dict get $record request] $st($w,scene)]
    }]} {
        if {[catch {add $w $record {} $prepared} message]} {_restoreUnavailable $w $record $message}
        _restoreAdvance $w $epoch
        return
    }
    dict unset record display_cache
    set token {}
    if {[catch {
        set token [::GX::curveSourceOpen $::GX::currentSession [dict get $record request] [list ::GX::CurveViewer::_restoreOpenProgress $w $epoch]]
        if {![winfo exists $w] || $epoch!=$st($w,restoreEpoch) || !$st($w,restoring)} {error {Opening interrupted}}
        if {[info exists st($w,historyRestore)] && $st($w,historyRestore) && [dict exists $record source_id] && [dict get [::GX::curveSourceDescribe $token] source_id] ne [dict get $record source_id]} {error {Archived source changed; historical binding remains unavailable}}
        set st($w,sourceJob) [::GX::curveSourceDisplayAsync $token [list ::GX::CurveViewer::_restoreDone $w $epoch $record $token] [list ::GX::CurveViewer::_sourceProgress $w]]
        set token {}
    } message]} {
        if {$token ne {}} {::GX::curveSourceClose $token}
        if {![winfo exists $w] || $epoch!=$st($w,restoreEpoch)} return
        _restoreUnavailable $w $record $message
        _restoreAdvance $w $epoch
    }
}
proc ::GX::CurveViewer::_restoreOpenProgress {w epoch receipt} {
    variable st
    if {![winfo exists $w] || $epoch!=$st($w,restoreEpoch) || !$st($w,restoring)} {error {Opening interrupted}}
    _scope $w
    set st($w,status) "Preparing source: [dict get $receipt completed_rows] rows"
}
proc ::GX::CurveViewer::_restoreUnavailable {w record message} {
    variable st
        if {[dict exists $record descriptor]} {
            dict set record native {};dict set record token {};dict set record status {unavailable: re-add source}
            dict set st($w,records) [dict get $record id] $record
        }
        set st($w,status) $message
}
proc ::GX::CurveViewer::_restoreDone {w epoch record token result} {
    variable st
    if {![winfo exists $w] || ![info exists st($w,restoreEpoch)] || $epoch!=$st($w,restoreEpoch)} {catch {::GX::curveSourceClose $token};return}
    set st($w,sourceJob) {}
    if {[dict get $result status] eq "ok" && ![catch {_scope $w}]} {
        if {[catch {add $w $record $token [dict get $result display]} message]} {_restoreUnavailable $w $record $message}
    } else {
        ::GX::curveSourceClose $token
        _restoreUnavailable $w $record [::GX::datasetPublicationV2DictDefault $result message {Source loading cancelled}]
    }
    _restoreAdvance $w $epoch
}
proc ::GX::CurveViewer::_restoreAdvance {w epoch} {
    variable st
    if {$st($w,firstReady) eq {}} {set st($w,firstReady) [expr {[clock milliseconds]-$st($w,restoreStarted)}]}
    _refresh $w
    set loaded [dict size $st($w,records)]
    if {$loaded>0 && ($loaded & ($loaded-1))==0} {_redraw $w}
    set st($w,restoreAfter) [after idle [list ::GX::CurveViewer::_restoreNext $w $epoch]]
}
proc ::GX::CurveViewer::_historyValidate {record} {workspaceValidate [dict get $record base];return 1}
proc ::GX::CurveViewer::_historyReplay {record} {::GX::scientificHistoryState $record}
::GX::scientificRecipeHostRegister viewer.curve_viewer [dict create capture ::GX::CurveViewer::_payload validate ::GX::CurveViewer::_historyValidate replay ::GX::CurveViewer::_historyReplay]
proc ::GX::CurveViewer::_historyCommit {w record} {
    set payload [::GX::scientificHistoryState $record];dict set payload scientific_history $record
    _writePayload $w $payload
}
proc ::GX::CurveViewer::_historyRestore {w payload} {
    variable st
    dict for {id record} $st($w,records) {
        if {[dict get $record token] ne {}} {::GX::curveSourceClose [dict get $record token]}
        if {[dict get $record native] ne {}} {::GX::Native2D::core delete $st($w,scene) [dict get $record native]}
    }
    set st($w,records) {};set st($w,historyRestore) 1
    try {
        _restoreStart $w $payload
        while {$st($w,restoring)} {vwait ::GX::CurveViewer::st($w,restoring)}
        if {$st($w,incomplete)} {error {History restore was interrupted}}
    } finally {set st($w,historyRestore) 0}
}
proc ::GX::CurveViewer::_historyGuard {w} {
    variable st
    return [expr {[_ready $w] && (![info exists st($w,pan)] || $st($w,pan) eq {})}]
}
proc ::GX::CurveViewer::_historyAttach {w} {
    variable st
    set record {}
    if {$st($w,document) ne {}} {set record [::GX::datasetPublicationV2DictDefault [dict get [::GX::interactiveDocumentRead $st($w,document)] payload] scientific_history {}]}
    ::GX::scientificHistoryViewerAttach $w viewer.curve_viewer [dict create document_id $st($w,document) capture [list ::GX::CurveViewer::_payload $w] restore [list ::GX::CurveViewer::_historyRestore $w] commit [list ::GX::CurveViewer::_historyCommit $w] guard [list ::GX::CurveViewer::_historyGuard $w]] $record
    if {![winfo exists $w.historyStrip]} {::GX::scientificHistoryViewerStrip $w $w $w.status modules.curve_viewer.history_strip [list -side bottom -fill x -before $w.coordinates]}
    set st($w,configurationSubscription) [::GX::configurationSubscribe [list ::GX::CurveViewer::_configurationChanged $w]]
    ::GX::viewerCommandMenusRefresh $w
}
proc ::GX::CurveViewer::_legendRecord {w x y} {
    variable st
    set hit [::GX::native2DLegendHit $w.canvas $x $y]
    if {![dict get $hit hit]} {return {}}
    dict for {id record} $st($w,records) {if {[dict get $record native] eq [dict get $hit object_id]} {return $id}}
    return {}
}
proc ::GX::CurveViewer::_legendPress {w x y bits} {
    variable st
    focus $w.canvas
    set id [_legendRecord $w $x $y]
    if {$id eq {}} {if {[_ready $w] && [::GX::scientificHistoryViewerEditable $w]} {_panDown $w $x $y};return}
    if {$bits&0x4} {if {$id in [$w.sources selection]} {$w.sources selection remove $id} else {$w.sources selection add $id}} else {$w.sources selection set $id}
    $w.sources focus $id;$w.sources see $id;_select $w;_redraw $w
    set st($w,status) "Selected curve $id — [dict get $st($w,records) $id request dataset_id]"
    set st($w,legendPressed) 1
}
proc ::GX::CurveViewer::_legendContext {w x y rootx rooty} {
    variable st
    set id [_legendRecord $w $x $y]
    if {$id eq {}} {if {[_ready $w] && [::GX::scientificHistoryViewerEditable $w]} {_presentation $w};return}
    $w.sources selection set $id;$w.sources focus $id;$w.sources see $id;_select $w;_redraw $w
    set menu $w.legendContext;catch {destroy $menu};menu $menu -tearoff 0
    foreach action {label properties show hide fit_selected remove} {
        $menu add command -label [dict get [_commands] $action] -command [list ::GX::CurveViewer::_legendAction $w $st($w,session_token) $st($w,document) $id $action] -state [expr {[_enabled $w $action] ? "normal" : "disabled"}]
    }
    ::GX::uiMenuPopup $menu $rootx $rooty
}
proc ::GX::CurveViewer::_legendAction {w token document id action} {
    variable st
    _scope $w
    if {$token ne $st($w,session_token) || $document ne $st($w,document) || ![dict exists $st($w,records) $id]} {error {Legend target changed; reopen the menu}}
    $w.sources selection set $id
    ::GX::viewerCommandInvoke $w $action
}
proc ::GX::CurveViewer::_labelDialog {w id} {
    variable st
    set values [dict create label [::GX::datasetPublicationV2DictDefault [dict get $st($w,records) $id] presentation_label {}]]
    ::GX::uiFieldFormCreate $w.label {Presentation label — blank uses automatic label} {label {type string label {Display label}}} $values [list ::GX::CurveViewer::_labelApply $w $id] $w
}
proc ::GX::CurveViewer::_labelApply {w id values} {
    variable st;_scope $w
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    dict set st($w,records) $id presentation_label [dict get $values label]
    _refresh $w;_redraw $w;_save $w "Change display label: $id"
}

# Optional shared-host callbacks; the existing scientific History remains the
# autosave owner. Querying dirty state must not commit a draft or replay a scene.
proc ::GX::CurveViewer::_workspaceCallbacks {w} {
    return [dict create current [list ::GX::CurveViewer::_currentWorkspace $w] save [list ::GX::CurveViewer::_save $w] close [list ::GX::CurveViewer::_close $w] open ::GX::CurveViewer::open dirty [list ::GX::CurveViewer::_workspaceDirty $w] prepare [list ::GX::CurveViewer::_workspacePrepare $w] discard [list ::GX::CurveViewer::_close $w 0]]
}
proc ::GX::CurveViewer::_workspacePrepare {w action} {
    _scope $w
    if {![_ready $w]} {error {Finish or cancel the active Curve Viewer source operation first.}}
}
proc ::GX::CurveViewer::_workspaceDirty {w} {
    variable st
    _scope $w
    if {$st($w,document) eq {}} {return 1}
    return [expr {[_payload $w 0] ne [dict remove $st($w,savedPayload) scientific_history]}]
}
