# Scientific Image Inspector domain hooks for CORE-owned native History.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::SII {}
proc ::GX::SII::historyAttached {} {
    variable ui
    return [expr {[info exists ui(historyAttached)] && $ui(historyAttached)}]
}
proc ::GX::SII::historyGuard {} {
    variable ui
    checkSession
    return [expr {![info exists ui(pending)] || !$ui(pending)}]
}
proc ::GX::SII::historySnapshot {} {
    variable ui
    if {![info exists ui(info)]} {return {}}
    set composed $ui(figurePreviewActive)
    set image [expr {$composed ? $ui(imageAnnotations) : $ui(annotations)}]
    set figure [expr {$composed ? $ui(annotations) : $ui(figureAnnotations)}]
    set value [dict create steps $ui(steps) panels $ui(panels) image_annotations $image figure_annotations $figure canvas_mode [expr {$composed ? "figure" : "image"}] figure_settings [figureSettings]]
    set channels [dict create image [llength $ui(steps)] figure 0]
    foreach channel {image figure} {if {[info exists ui(history-$channel)]} {dict set channels $channel [dict get [::GX::scientificHistoryViewerStatus $ui(history-$channel)] cursor]}}
    dict set value history_channels $channels
    if {[info exists ui(restoreSnapshot)]} {dict set value image_reset_previous $ui(restoreSnapshot)}
    dict set value source_id $ui(sourceId)
    dict set value source_sha [dict get $ui(info) sha256]
    return $value
}
proc ::GX::SII::historyImageSnapshot {} {
    variable ui
    set value [dict create steps $ui(steps)]
    if {[info exists ui(restoreSnapshot)]} {dict set value reset_previous $ui(restoreSnapshot);dict set value reset_state [dict remove [historySnapshot] history_channels source_id source_sha]}
    return $value
}
proc ::GX::SII::historyFigureSnapshot {} {
    return [dict remove [historySnapshot] steps history_channels figure_settings source_id source_sha image_reset_previous]
}
proc ::GX::SII::historyValidate {record} {
    set state [dict get $record base]
    if {[catch {dict size $state}]} {error {Image History state must be inert}}
    foreach step [dict get $record steps] {if {[catch {dict size [dict get $step patch]}]} {error {Image History patch must be inert}}}
    return 1
}
proc ::GX::SII::historyCaptureRecipe {context} {
    variable ui
    if {![historyAttached]} {error {No active Image Inspector History}}
    return [::GX::scientificHistoryViewerRecord $ui(window)]
}
proc ::GX::SII::historyReplay {context record} {error {Image Inspector recipes open through their Workspace source validation}}
proc ::GX::SII::historyNoCommit {record} {}
proc ::GX::SII::historyError {receipt} {
    variable ui
    set ui(status) "History persistence failed; accepted edits remain in RAM: [dict get $receipt error]"
}
proc ::GX::SII::historyDomainAccepted {channel receipt} {
    variable ui
    if {![info exists ui(historyUpdating)] || !$ui(historyUpdating)} {
        historyObserve
    }
}
proc ::GX::SII::historyAccepted {receipt} {
    variable ui
    set ui(historyCursor) [dict get $receipt cursor]
    set ui(historyBrowsing) 0
    historyBrowsingLock 0
    set transition [get $receipt transition {}]
    set decreased [expr {[info exists ui(historyMainCount)] && [dict get $receipt count]<$ui(historyMainCount)}]
    set ui(historyMainCount) [dict get $receipt count]
    # A main restart explicitly clears the former figure Undo context while
    # image Undo remains available for the retained accepted processing recipe.
    # Clear resets both domains to the protected current scientific checkpoint.
    if {$transition in {branch clear} || ($transition eq {} && $decreased)} {
        set priorUpdating $ui(historyUpdating)
        set ui(historyUpdating) 1
        try {
            foreach channel {image figure} {
                if {![info exists ui(history-$channel)]} continue
                if {$transition eq "clear"} {::GX::scientificHistoryViewerReset $ui(history-$channel) [history[string totitle $channel]Snapshot]} else {historyResetDomain $channel}
            }
            if {$transition eq "clear"} {
                # Cursor markers are small control state. Keep Clear at zero
                # steps after subordinate contexts have reached their bases.
                ::GX::scientificHistoryViewerReset $ui(window) [historySnapshot]
            } elseif {[historySnapshot] ne [::GX::scientificHistoryViewerState $ui(window)]} {
                ::GX::scientificHistoryViewerRecordOperation $ui(window) {Restart domain Undo controls} [historySnapshot]
            }
        } finally {set ui(historyUpdating) $priorUpdating}
    }
}
proc ::GX::SII::historyRestore {state} {
    variable ui
    set mode [dict get [::GX::scientificHistoryViewerRestoreContext $ui(window)] mode]
    set priorUpdating $ui(historyUpdating)
    set ui(historyUpdating) 1
    try {
        historyDisplayState $state
        if {$mode ni {browse latest recovery}} {
            foreach channel {image figure} {
                if {![info exists ui(history-$channel)] || ![dict exists $state history_channels $channel]} continue
                set key $ui(history-$channel)
                set index [dict get $state history_channels $channel]
                # An earlier domain branch can no longer be addressed by its
                # numeric cursor. Keep the selected full scientific checkpoint;
                # the explicit main restart will reset those domain contexts.
                if {[catch {::GX::scientificHistoryViewerSeek $key $index 0}]} {historyResetDomain $channel}
            }
        }
    } finally {set ui(historyUpdating) $priorUpdating}
    set ui(historyBrowsing) [expr {$mode eq "browse"}]
    historyBrowsingLock $ui(historyBrowsing)
}
proc ::GX::SII::historyResetDomain {channel} {
    variable ui
    set key $ui(history-$channel)
    if {$channel eq "figure"} {::GX::scientificHistoryViewerReset $key [historyFigureSnapshot];return}
    set snapshot [historyImageSnapshot]
    ::GX::scientificHistoryViewerReset $key [dict create steps {}]
    set steps [dict get $snapshot steps]
    if {[dict exists $snapshot reset_previous]} {set steps [dict get $snapshot reset_previous steps]}
    set retained {}
    foreach step $steps {lappend retained $step;::GX::scientificHistoryViewerRecordOperation $key {Retained image recipe operation} [dict create steps $retained]}
    if {[dict exists $snapshot reset_previous]} {::GX::scientificHistoryViewerRecordOperation $key {Restore original image} $snapshot}
}
proc ::GX::SII::historyImageRestore {value} {
    variable ui
    set mode [dict get [::GX::scientificHistoryViewerRestoreContext $ui(history-image)] mode]
    set current [::GX::scientificHistoryViewerState $ui(history-image)]
    if {$mode eq "undo" && [dict exists $current reset_previous]} {
        set state [dict get $current reset_previous]
        if {[dict exists $state annotations]} {
            dict set state [expr {[dict get $state canvas_mode] eq "figure" ? "figure_annotations" : "image_annotations"}] [dict get $state annotations]
            dict unset state annotations
        }
    } elseif {$mode eq "redo" && [dict exists $value reset_state]} {set state [dict get $value reset_state]} else {
        set state [historySnapshot]
        dict set state steps [dict get $value steps]
    }
    if {[dict exists $value reset_previous]} {dict set state image_reset_previous [dict get $value reset_previous]} elseif {[dict exists $state image_reset_previous]} {dict unset state image_reset_previous}
    historyDisplayState $state
}
proc ::GX::SII::historyFigureRestore {value} {
    set state [dict merge [historySnapshot] $value]
    historyDisplayState $state
}
proc ::GX::SII::historyStripCreate {w} {
    variable ui
    set ui(historyAttached) 0
    set ui(historyUpdating) 0
}
proc ::GX::SII::historyAttach {{record {}} {domains {}}} {
    variable ui
    if {![info exists ui(info)]} return
    set ui(historyUpdating) 1
    try {
        set callbacks [dict create capture ::GX::SII::historySnapshot restore ::GX::SII::historyRestore commit ::GX::SII::historyCommit guard ::GX::SII::historyGuard document_id $ui(documentId) accepted ::GX::SII::historyAccepted error ::GX::SII::historyError]
        ::GX::scientificHistoryViewerAttach $ui(window) viewer.scientific_image_inspector $callbacks $record
        set ui(historyAttached) 1
        set ui(projectionDirty) [expr {$ui(documentId) eq {}}]
        foreach channel {image figure} {
            set child [get $domains $channel {}]
            if {$child eq {}} {
                set snapshot [history[string totitle $channel]Snapshot]
                if {$channel eq "image"} {
                    set steps [dict get $snapshot steps]
                    set child [::GX::scientificHistoryCreate viewer.scientific_image_inspector [dict create steps {}]]
                    set retained {}
                    foreach step $steps {lappend retained $step;set child [::GX::scientificHistoryAppend viewer.scientific_image_inspector $child [dict create steps $retained] {Imported image operation}]}
                } else {set child [::GX::scientificHistoryCreate viewer.scientific_image_inspector $snapshot]}
            }
            set beforeDomain [history[string totitle $channel]Snapshot]
            set beforeScientific [historySnapshot]
            set hooks [dict create parent $ui(window) channel $channel document_id $ui(documentId) capture ::GX::SII::history[string totitle $channel]Snapshot restore ::GX::SII::history[string totitle $channel]Restore commit ::GX::SII::historyNoCommit guard ::GX::SII::historyGuard accepted [list ::GX::SII::historyDomainAccepted $channel] error ::GX::SII::historyError]
            set ui(history-$channel) [::GX::scientificHistoryContextAttach viewer.scientific_image_inspector $hooks $child]
            if {[history[string totitle $channel]Snapshot] ne $beforeDomain} {
                set choice [tk_messageBox -parent $ui(window) -type yesnocancel -default cancel -icon warning -title {Reconcile Image History} -message "The recovered $channel Undo state differs from the selected general History checkpoint.\nYes: use the recovered $channel state and record the reconciliation.\nNo: keep the general checkpoint and explicitly restart this domain's Undo controls.\nCancel: preserve both journals without accepting further edits."]
                if {$choice eq "cancel"} {error {Image History reconciliation cancelled; journals retained}}
                if {$choice eq "no"} {historyDisplayState $beforeScientific;historyResetDomain $channel}
            }
        }
        if {[historySnapshot] ne [::GX::scientificHistoryViewerState $ui(window)]} {::GX::scientificHistoryViewerRecordOperation $ui(window) {Reconcile recovered domain History} [historySnapshot]}
        set ui(historyMainCount) [dict get [::GX::scientificHistoryViewerStatus $ui(window)] count]
        set frame [::GX::scientificHistoryViewerStrip $ui(window) $ui(window) $ui(window).footer {} {-side bottom -fill x}]
        ::GX::scientificHistoryViewerStripSet $ui(window) [dict create visible $ui(historyStripVisible) mode $ui(historyStripView)]
    } on error {message options} {
        foreach channel {image figure} {if {[info exists ui(history-$channel)]} {catch {::GX::scientificHistoryContextClose $ui(history-$channel) 0};unset ui(history-$channel)}}
        if {[historyAttached]} {catch {::GX::scientificHistoryViewerDetach $ui(window) 0}}
        set ui(historyAttached) 0
        set ui(historyBrowsing) 1
        historyBrowsingLock 1
        return -options $options $message
    } finally {set ui(historyUpdating) 0}
}
proc ::GX::SII::historyDetach {{project 1}} {
    variable ui
    if {![historyAttached]} return
    if {$project} {historySaveExplicit}
    set presentation [::GX::scientificHistoryViewerStripGet $ui(window)]
    set ui(historyStripVisible) [dict get $presentation visible]
    set ui(historyStripView) [dict get $presentation mode]
    foreach channel {image figure} {if {[info exists ui(history-$channel)]} {::GX::scientificHistoryContextClose $ui(history-$channel) 0;unset ui(history-$channel)}}
    ::GX::scientificHistoryViewerDetach $ui(window) 0
    if {[winfo exists $ui(window).historyStrip]} {destroy $ui(window).historyStrip}
    set ui(historyAttached) 0
    pack $ui(window).footer -side bottom -fill x
}
proc ::GX::SII::historyStripReset {} {variable ui;if {[info exists ui(historyLoading)] && $ui(historyLoading)} return;historyDetach 0;historyAttach}
proc ::GX::SII::historyStripRestore {saved {record {}} {domains {}}} {
    variable ui
    historyDetach 0
    if {$record eq {} && $saved ne {}} {
        set first [lindex $saved 0]
        set record [::GX::scientificHistoryCreate viewer.scientific_image_inspector [dict get $first state]]
        foreach item [lrange $saved 1 end] {set record [::GX::scientificHistoryAppend viewer.scientific_image_inspector $record [dict get $item state] [dict get $item label]]}
        if {[dict remove [::GX::scientificHistoryState $record] history_channels source_id source_sha] ne [dict remove [historySnapshot] history_channels source_id source_sha]} {error {Saved image timeline does not match its scientific Workspace state}}
    }
    historyAttach $record $domains
}
proc ::GX::SII::historyObserve {} {
    variable ui
    if {![historyAttached] || $ui(historyUpdating) || $ui(historyBrowsing)} return
    if {![::GX::scientificHistoryViewerPrepareEdit $ui(window)]} {return 0}
    set ui(historyUpdating) 1
    try {
        set description {Edit image Workspace}
        foreach channel {image figure} {
            set key $ui(history-$channel)
            set snapshot [history[string totitle $channel]Snapshot]
            if {$snapshot ne [::GX::scientificHistoryViewerState $key]} {
                if {![::GX::scientificHistoryViewerPrepareEdit $key]} {return 0}
                set description [expr {$channel eq "image" ? "Edit image recipe" : "Edit figure or annotation"}]
                ::GX::scientificHistoryViewerRecordOperation $key $description $snapshot
            }
        }
        ::GX::scientificHistoryViewerRecordOperation $ui(window) $description [historySnapshot]
    } finally {set ui(historyUpdating) 0}
    return 1
}
proc ::GX::SII::historyResumeForEditing {} {
    variable ui
    if {![historyGuard]} {set ui(status) {Accept or discard the image adjustment before editing.};return 0}
    if {$ui(historyBrowsing)} {::GX::scientificHistoryViewerNavigate $ui(window) latest}
    if {[historyAttached]} {return [::GX::scientificHistoryViewerPrepareEdit $ui(window)]}
    return 1
}
proc ::GX::SII::historyReadOnly {} {
    variable ui
    if {$ui(historyBrowsing)} {set ui(status) {History inspection is read-only; return to Latest or explicitly restart here.};return 1}
    return 0
}
proc ::GX::SII::historyStripShow {} {variable ui;if {[historyAttached]} {::GX::scientificHistoryViewerStripSet $ui(window) [dict create visible $ui(historyStripVisible)]}}
proc ::GX::SII::historyStripSwitch {} {variable ui;if {[historyAttached]} {::GX::scientificHistoryViewerStripSet $ui(window) [dict create mode $ui(historyStripView)]}}
proc ::GX::SII::historyStripRender {} {variable ui;if {[historyAttached]} {::GX::scientificHistoryViewerRefresh $ui(window)}}
proc ::GX::SII::historyBrowse {index} {variable ui;::GX::scientificHistoryViewerBrowse $ui(window) $index}
proc ::GX::SII::historyDomainAvailable {channel direction} {
    variable ui
    if {![historyAttached] || ![info exists ui(history-$channel)]} {return 0}
    set status [::GX::scientificHistoryViewerStatus $ui(history-$channel)]
    return [expr {$direction eq "undo" ? [dict get $status cursor]>0 : [dict get $status cursor]<[dict get $status count]}]
}
proc ::GX::SII::historyUndoRedo {channel direction} {
    variable ui
    if {[historyReadOnly] || ![historyGuard] || ![historyAttached]} return
    if {![::GX::scientificHistoryViewerPrepareEdit $ui(window)]} return
    ::GX::scientificHistoryViewerNavigate $ui(history-$channel) $direction
}
proc ::GX::SII::historyRecords {} {
    variable ui
    set records {}
    foreach channel {image figure} {dict set records $channel [::GX::scientificHistoryViewerRecord $ui(history-$channel)]}
    return $records
}
proc ::GX::SII::historyCommit {record} {
    variable ui
    foreach channel {image figure} {::GX::scientificHistoryViewerFlush $ui(history-$channel) 30000 0}
    set payload [workspacePayload $record [historyRecords]]
    if {$ui(documentId) eq {}} {
        set name [expr {$ui(workspaceName) eq {} ? "Image Inspector — $ui(sourceId) [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]" : $ui(workspaceName)}]
        set receipt [::GX::sessionWorkspaceCreate scientific_image_inspector $name $payload]
        set ui(documentId) [dict get $receipt workspace_id]
    } else {set receipt [::GX::sessionWorkspaceUpdate $ui(documentId) $payload]}
    set ui(workspaceName) [dict get $receipt name]
    set ui(workspaceDraft) 0
    set ui(projectionDirty) 0
}
proc ::GX::SII::historySaveExplicit {} {
    variable ui
    if {![historyAttached]} {return 1}
    if {$ui(historyBrowsing)} {error {Return to Latest before saving the Workspace}}
    historyObserve
    # Explicit Save includes presentation/sidebar changes even if no scientific
    # snapshot delta was needed. Domains are materialized only at this boundary.
    ::GX::scientificHistoryViewerFlush $ui(window)
    if {$ui(documentId) eq {} || $ui(projectionDirty)} {historyCommit [::GX::scientificHistoryViewerRecord $ui(window)]}
    foreach key [list $ui(window) $ui(history-image) $ui(history-figure)] {::GX::scientificHistoryViewerBindDocument $key $ui(documentId)}
    if {[llength [info commands ::GX::sessionWorkspaceViewerTitlesRefresh]]} {::GX::sessionWorkspaceViewerTitlesRefresh}
    set ui(status) "Workspace saved: $ui(workspaceName)"
    return 1
}
::GX::scientificRecipeHostRegister viewer.scientific_image_inspector [dict create capture ::GX::SII::historyCaptureRecipe validate ::GX::SII::historyValidate replay ::GX::SII::historyReplay]

proc ::GX::SII::historyDisplayState {state} {
    variable ui
    if {[dict exists $state source_id] && [dict get $state source_id] ne $ui(sourceId)} {
        set info [inspect [dict get $state source_id]]
        if {[dict get $info sha256] ne [dict get $state source_sha]} {error {History source Dataset fingerprint changed}}
        set ui(sourceId) [dict get $state source_id]
        set ui(info) $info
        set ui(originalFile) [dict get $info path]
        set ui(workingFile) $ui(originalFile)
        set ui(processedFile) $ui(originalFile)
    }
    if {[dict exists $state source_sha] && [dict get $state source_sha] ne [dict get $ui(info) sha256]} {error {History source fingerprint mismatch}}
    if {[dict exists $state image_reset_previous]} {set ui(restoreSnapshot) [dict get $state image_reset_previous]} else {unset -nocomplain ui(restoreSnapshot)}
    set mode [dict get $state canvas_mode]
    # Exactly the same non-destructive source/recipe/overlay separation as the
    # normal editor. No sessionWorkspaceUpdate is called during inspection.
    set ui(figurePreviewActive) 0
    set ui(steps) [dict get $state steps]
    set ui(panels) [dict get $state panels]
    set ui(imageAnnotations) [dict get $state image_annotations]
    set ui(figureAnnotations) [dict get $state figure_annotations]
    set ui(annotations) $ui(imageAnnotations)
    set ui(annotationActiveId) {}
    set ui(selectedAnnotationIds) {}
    dict for {field value} [dict get $state figure_settings] {set ui(figure-$field) $value}
    refreshSteps
    refreshPanels
    if {![renderImages]} {error {Could not render historical image preview}}
    if {$mode eq "figure" && [llength $ui(panels)]} {previewFigure}
    refreshAnnotations
    annotationToolbarSync
}
proc ::GX::SII::historyBrowsingLock {enabled} {
    variable ui
    set w $ui(window)
    # A historic preview is read-only. Unlike a filter preview, navigation of
    # the History strip remains available to return to the latest state.
    foreach name {file edit image analyze operations workspace configuration} {
        catch {$w.menu entryconfigure [string totitle $name] -state [expr {$enabled ? "disabled" : "normal"}]}
    }
    foreach widget [list $w.head.ds $w.head.refresh $w.head.preview] {
        if {$enabled} {catch {$widget state disabled}} else {catch {$widget state !disabled}}
    }
    pendingSetChildren $w.layout.inspector.tabs $enabled
    if {$enabled} {set ui(annotating) 0;set ui(canvasMode) view;set ui(annotationTransform) none}
}
