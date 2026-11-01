# SPDX-License-Identifier: GPL-3.0-or-later
# Local SourceSurface edits participate in the existing Viewer History owner.
# This adapter adds neither a Registry writer nor another source/history store.
proc ::GX::_viewerGuiScriptLibraryHistoryCancel {window} {
    if {![dict exists $::GX::ViewerGui::instances $window script_library_history_pending]} return
    set timer [dict get $::GX::ViewerGui::instances $window script_library_history_pending]
    if {$timer ne {}} {after cancel $timer}
    dict unset ::GX::ViewerGui::instances $window script_library_history_pending
}
proc ::GX::_viewerGuiScriptLibraryHistorySchedule {window} {
    if {![dict exists $::GX::ScientificHistory::viewers $window] || ![scientificHistoryViewerEditable $window]} return
    _viewerGuiScriptLibraryHistoryCancel $window
    dict set ::GX::ViewerGui::instances $window script_library_history_pending [after 450 [list ::GX::_viewerGuiScriptLibraryHistoryTimer $window [winfo id $window]]]
}
proc ::GX::_viewerGuiScriptLibraryHistoryTimer {window identity} {
    if {![winfo exists $window] || [winfo id $window] ne $identity || ![dict exists $::GX::ViewerGui::instances $window]} return
    if {[catch {_viewerGuiScriptLibraryHistoryFlush $window} message]} {
        # A failed append must retain the local source and remain retryable.
        # Explicit navigation/Save/Close will refuse until it can be captured.
        foreach key [dict keys $::GX::ScriptLibraryHost::bindings] {
            if {[lindex $key 0] ne $window} continue
            catch {_scriptLibraryHostStatus $window [dict get $::GX::ScriptLibraryHost::bindings $key context] "History capture failed; local source retained. $message"}
        }
    }
}
proc ::GX::_viewerGuiScriptLibraryHistoryProjection {snapshot} {
    set drafts [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $snapshot domain_state {}] script_library_drafts {}]
    set result {}
    foreach form [lsort [dict keys $drafts]] {
        set body [_viewerGuiScriptLibraryWorkspaceRead [dict get $drafts $form]]
        set baseline {}
        foreach key {scope id kind language version revision sha256 record_sha256 source_sha256 source_id source_scope} {
            dict set baseline $key [datasetPublicationV2DictDefault [dict get $body baseline] $key {}]
        }
        set metadata {};foreach key [lsort [dict keys [dict get $body metadata_fields]]] {dict set metadata $key [dict get $body metadata_fields $key]}
        set sources {}
        foreach relative [lsort [dict keys [dict get $body sources]]] {
            set source [dict get $body sources $relative]
            if {[dict get $source text] ne [dict get $source baseline_text]} {dict set sources $relative [list [dict get $source text] [dict get $source baseline_text]]}
        }
        set roster {}
        foreach relative [lsort [dict keys [dict get $body roster]]] {dict set roster $relative [dict get $body roster $relative sha256]}
        # A restore can emit a deferred Tk Modified event. Cursor, selection,
        # scroll, filter and active-file presentation changes are not new source
        # edits and must not request a branch from an older accepted state.
        dict set result $form [list [dict get $body reference] $baseline $metadata $sources $roster [dict get $body parameter_text] [dict get $body parameter_baseline]]
    }
    return $result
}
proc ::GX::_viewerGuiScriptLibraryHistoryFlush {window} {
    if {![dict exists $::GX::ViewerGui::instances $window] || [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] script_library_history_flushing 0]} return
    if {![dict exists $::GX::ScientificHistory::viewers $window]} {_viewerGuiScriptLibraryHistoryCancel $window;return}
    if {![dict exists $::GX::ViewerGui::instances $window script_library_history_pending] && ![scientificHistoryViewerEditable $window]} return
    set ownsDraft 0
    foreach key [dict keys $::GX::ScriptLibraryHost::bindings] {if {[lindex $key 0] eq $window} {set ownsDraft 1;break}}
    if {!$ownsDraft} {_viewerGuiScriptLibraryHistoryCancel $window;return}
    # Also inspect actual text before a transition whose Modified event has not
    # arrived yet. Compare semantic buffers even when a timer is already pending:
    # an Undo restore or focus-only event must never cause a branch review.
    set current [viewerGuiDesignCapture $window]
    set accepted [scientificHistoryViewerState $window]
    if {[_viewerGuiScriptLibraryHistoryProjection $current] eq [_viewerGuiScriptLibraryHistoryProjection $accepted]} {_viewerGuiScriptLibraryHistoryCancel $window;return}
    if {![dict exists $::GX::ViewerGui::instances $window script_library_history_pending]} {dict set ::GX::ViewerGui::instances $window script_library_history_pending {}}
    set timer [dict get $::GX::ViewerGui::instances $window script_library_history_pending]
    if {$timer ne {}} {after cancel $timer}
    dict set ::GX::ViewerGui::instances $window script_library_history_pending {}
    dict set ::GX::ViewerGui::instances $window script_library_history_flushing 1
    try {
        if {![scientificHistoryViewerPrepareEdit $window]} {
            viewerGuiDesignRestore $window [scientificHistoryViewerState $window]
            _viewerGuiScriptLibraryHistoryCancel $window
            return
        }
        set snapshot [viewerGuiDesignCapture $window]
        try {scientificHistoryViewerRecordOperation $window {Edit registered source draft} $snapshot} on error {message options} {
            # The standard owner compensates a failed append. Restore the
            # exact unaccepted local draft so no typed source is lost.
            viewerGuiDesignRestore $window $snapshot
            return -options $options $message
        }
        _viewerGuiScriptLibraryHistoryCancel $window
    } finally {
        if {[dict exists $::GX::ViewerGui::instances $window]} {dict unset ::GX::ViewerGui::instances $window script_library_history_flushing}
    }
}
