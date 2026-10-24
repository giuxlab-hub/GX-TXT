# SPDX-License-Identifier: GPL-3.0-or-later
# Host-neutral History operations over Scientific Recipe's existing patches.
# Scientific hosts supply validation/restoration; Document owns durable commits.
proc ::GX::scientificHistoryCreate {owner snapshot} {
    set record [dict create format gxtxt.scientific_recipe.v1 workbench_id $owner required_apis {SCIENTIFIC_RECIPE_API_v1} \
        plugin_versions {} sources {} retention complete base $snapshot steps {} cursor 0]
    scientificHistoryValidate $owner $record
    return $record
}
proc ::GX::scientificHistoryValidate {owner record} {
    if {[datasetPublicationV2DictDefault $record legacy_import 0]} {
        if {[string bytelength $record]>8392704} {error {Imported History exceeds its preserved-data and envelope allowance}}
    } else {scientificRecipeEncode $record}
    if {![dict exists $record format] || [dict get $record format] ne {gxtxt.scientific_recipe.v1}} {error {Unsupported History record format}}
    foreach field {base steps cursor workbench_id retention} {if {![dict exists $record $field]} {error "History requires $field"}}
    if {[dict get $record workbench_id] ne $owner || ![dict exists $::GX::ScientificRecipe::hosts $owner]} {error {History owner is unavailable or mismatched}}
    set steps [dict get $record steps];set cursor [dict get $record cursor]
    if {[llength $steps]>4096 || ![string is entier -strict $cursor] || $cursor<0 || $cursor>[llength $steps]} {error {Invalid History cursor or step limit}}
    if {[catch {dict size [dict get $record base]}]} {error {History checkpoint must be an inert dictionary}}
    foreach step $steps {
        foreach field {api_id api_version operation parameters targets result_ids working_unit patch} {if {![dict exists $step $field]} {error "History step requires $field"}}
        if {[dict get $step api_id] ni {SCIENTIFIC_RECIPE_API_v1 NATIVE_2D_GEOMETRY_API_v1 NATIVE_3D_GEOMETRY_API_v1} || [dict get $step api_version]!=1 || [catch {dict size [dict get $step patch]}]} {error {Invalid scientific History step}}
        if {[dict exists $step timestamp] && ![string is entier -strict [dict get $step timestamp]]} {error {Invalid History timestamp}}
    }
    uplevel #0 [list {*}[dict get $::GX::ScientificRecipe::hosts $owner validate] $record]
    return [dict create owner $owner count [llength $steps] cursor $cursor]
}
proc ::GX::scientificHistoryState {record {index -1}} {
    set steps [dict get $record steps]
    if {$index==-1} {set index [dict get $record cursor]}
    if {![string is entier -strict $index] || $index<0 || $index>[llength $steps]} {error {History index is outside the retained timeline}}
    set state [dict get $record base]
    for {set i 0} {$i<$index} {incr i} {set state [scientificRecipeApplyPatch $state [dict get [lindex $steps $i] patch]]}
    return $state
}
proc ::GX::scientificHistoryAppend {owner record snapshot description} {
    scientificHistoryValidate $owner $record
    if {[dict get $record cursor]!=[llength [dict get $record steps]]} {error {Confirm an explicit History branch before editing an older state}}
    set semantic [dict create api_id SCIENTIFIC_RECIPE_API_v1 api_version 1 operation workspace_state \
        parameters {} targets {} result_ids {} working_unit {} description $description timestamp [clock seconds]]
    set candidate [scientificRecipeAppend $record [scientificHistoryState $record] $snapshot $semantic]
    dict set candidate cursor [llength [dict get $candidate steps]]
    scientificHistoryValidate $owner $candidate
    return $candidate
}
proc ::GX::scientificHistoryNavigate {owner record index} {
    scientificHistoryValidate $owner $record
    scientificHistoryState $record $index
    dict set record cursor $index
    scientificHistoryValidate $owner $record
    return $record
}
proc ::GX::scientificHistoryBranch {owner record index} {
    scientificHistoryValidate $owner $record
    scientificHistoryState $record $index
    dict set record steps [lrange [dict get $record steps] 0 [expr {$index-1}]]
    dict set record cursor $index
    scientificHistoryValidate $owner $record
    return $record
}

source [file join [file dirname [info script]] scientific_history_native.tcl]
namespace eval ::GX::ScientificHistory {variable viewers {};variable strip}
proc ::GX::scientificHistoryViewerAttach {window owner callbacks {record {}}} {
    foreach field {capture restore commit guard} {if {![dict exists $callbacks $field]} {error "History host requires $field"}}
    if {[dict exists $::GX::ScientificHistory::viewers $window]} {error {History is already attached to this window}}
    set snapshot [uplevel #0 [dict get $callbacks capture]]
    if {[dict exists $callbacks capture_aux] && ![dict exists $callbacks auxiliary]} {dict set callbacks auxiliary [uplevel #0 [dict get $callbacks capture_aux]]}
    if {$record eq {}} {set record [scientificHistoryCreate $owner $snapshot]}
    scientificHistoryValidate $owner $record
    set document [datasetPublicationV2DictDefault $callbacks document_id {}]
    lassign [_historyOpen $window $owner $record $document $callbacks] handle path
    dict set ::GX::ScientificHistory::viewers $window [dict create owner $owner callbacks $callbacks handle $handle path $path document_id $document session [_interactiveDocumentRequireSession] record [historyNative summary $handle] dirty [expr {[historyNative record $handle] ne $record || ([dict exists $callbacks auxiliary] && [historyNative auxiliary $handle] ne [dict get $callbacks auxiliary])}] browsing 0 browse_cursor [dict get [historyNative status $handle] cursor] restoring 0 token [interactiveDocumentSessionToken]]
    if {[dict exists $callbacks describe]} {
        set imported [historyNative record $handle];set index 0;set rows {}
        foreach row [dict get [historyNative summary $handle] steps] semantic [dict get $imported steps] {
            dict set row index [incr index]
            lappend rows [_historyPresentationRow $window $row $semantic]
        }
        dict set ::GX::ScientificHistory::viewers $window record steps $rows
    }
    dict set ::GX::ScientificHistory::viewers $window accepted_revision [dict get [historyNative status $handle] revision]
    if {$document ne {}} {dict set ::GX::ScientificHistory::viewers $window document_generation [dict get [interactiveDocumentMetadata $document] generation]}
    if {[catch {
        if {[historyNative state $handle] ne $snapshot} {_historyRestore $window [historyNative state $handle] recovery} elseif {[dict exists $callbacks restore_aux] && [dict exists $callbacks auxiliary] && [historyNative auxiliary $handle] ne [dict get $callbacks auxiliary]} {_historyRestoreAuxiliary $window [historyNative auxiliary $handle]}
    } message options]} {
        catch {_scientificHistoryDestroyed $window $window}
        return -options $options $message
    }
    if {[llength [info commands winfo]] && [winfo exists $window]} {bind $window <Destroy> +[list ::GX::_scientificHistoryDestroyed $window %W]}
    _historyMonitorSchedule $window
    return [historyNative record $handle]
}
proc ::GX::_scientificHistoryDestroyed {window destroyed} {
    if {$window ne $destroyed || ![dict exists $::GX::ScientificHistory::viewers $window]} return
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    scientificHistoryHookCancel $window
    foreach field {refresh_timer persistence_timer} {if {[dict exists $adapter $field]} {after cancel [dict get $adapter $field]}}
    if {[dict exists $adapter strip_subscription]} {configurationUnsubscribe [dict get $adapter strip_subscription]}
    # Destruction cannot call Viewer hooks after its scientific widgets vanish.
    # Explicit Close projects first; abrupt destruction retains the native journal.
    set failed [catch {historyNative close [dict get $adapter handle]} message options]
    if {!$failed && [dict exists $adapter discard_on_close]} {_historyRetirePath [dict get $adapter path] discarded}
    dict unset ::GX::ScientificHistory::viewers $window
    array unset ::GX::ScientificHistory::strip "$window,*"
    if {$failed} {dict set ::GX::HistoryService::failures $window [dict create error $message handle [dict get $adapter handle] path [dict get $adapter path] session [dict get $adapter session]];return -options $options $message}
}
proc ::GX::_scientificHistoryGuard {window} {
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    if {[dict get $adapter token] ne [interactiveDocumentSessionToken]} {error {Session changed; reopen this Workspace}}
    if {[dict get $adapter document_id] ne {}} {
        set metadata [interactiveDocumentMetadata [dict get $adapter document_id]]
        if {[dict get $metadata generation] ne [dict get $adapter document_generation]} {error {History Document owner was replaced; reopen this Workspace}}
    }
    if {![uplevel #0 [dict get $adapter callbacks guard]]} {error {Finish or cancel the active operation before navigating History}}
    return $adapter
}
proc ::GX::scientificHistoryViewerRecord {window} {return [historyNative record [_historyHandle $window]]}
proc ::GX::scientificHistoryViewerState {window} {
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    return [historyNative state [dict get $adapter handle] [expr {[dict get $adapter browsing] ? [dict get $adapter browse_cursor] : -1}]]
}
proc ::GX::scientificHistoryViewerEditable {window} {
    if {![dict exists $::GX::ScientificHistory::viewers $window]} {return 1}
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    return [expr {![dict get $adapter browsing] && ![dict get $adapter restoring] && ![dict exists $adapter hook_pending]}]
}
proc ::GX::scientificHistoryViewerPrepareEdit {window} {
    set adapter [_scientificHistoryGuard $window]
    if {[dict get $adapter browsing]} {error {History browsing is read-only. Return to latest or explicitly restart here.}}
    if {![scientificHistoryViewerEditable $window]} {error {History preparation or restoration is pending}}
    set record [dict get $adapter record];set cursor [dict get $record cursor]
    if {$cursor<[llength [dict get $record steps]]} {
        if {[tk_messageBox -parent [_historyDialogParent $window] -type okcancel -default cancel -icon warning -title {Branch Workspace History} -message {Editing here discards later local History steps. Published Datasets and exported files remain. Restart editing here?}] ne {ok}} {return 0}
        _historyAccepted $window [historyNative branch [dict get $adapter handle] $cursor]
    }
    return 1
}
proc ::GX::_scientificHistoryCommit {window record {restoreSnapshot 1}} {
    # Legacy explicit replacement boundary (clear/rebase). Normal submission and
    # navigation never call this full-record compatibility operation.
    set adapter [_scientificHistoryGuard $window]
    scientificHistoryValidate [dict get $adapter owner] $record
    set state [scientificHistoryState $record]
    if {$restoreSnapshot} {_historyRestore $window $state clear}
    set receipt [historyNative clear [dict get $adapter handle] $state]
    dict set ::GX::ScientificHistory::viewers $window record [historyNative summary [dict get $adapter handle]]
    _historyAccepted $window $receipt
}
proc ::GX::scientificHistoryViewerChanged {window description} {
    scientificHistoryViewerRecordOperation $window $description
    scientificHistoryViewerFlush $window
    return [scientificHistoryViewerRecord $window]
}
proc ::GX::scientificHistoryViewerNavigate {window action} {
    set adapter [_scientificHistoryGuard $window];set record [dict get $adapter record]
    if {[dict exists $adapter hook_pending]} {error {Finish or cancel the pending History hook before navigation}}
    set count [llength [dict get $record steps]];set cursor [dict get $record cursor];set h [dict get $adapter handle]
    switch $action {
        undo {if {[dict get $adapter browsing] || $cursor==0} return;set index [expr {$cursor-1}]}
        redo {if {[dict get $adapter browsing] || $cursor==$count} return;set index [expr {$cursor+1}]}
        previous {return [scientificHistoryViewerBrowse $window [expr {max(0,[dict get $adapter browse_cursor]-1)}] index]}
        next {return [scientificHistoryViewerBrowse $window [expr {min($count,[dict get $adapter browse_cursor]+1)}] index]}
        latest {return [scientificHistoryViewerBrowse $window $count latest]}
        branch {
            set index [dict get $adapter browse_cursor]
            if {$index==$count && $cursor==$count} return
            if {[tk_messageBox -parent [_historyDialogParent $window] -type okcancel -default cancel -icon warning -message "Discard later local History and restart at step $index? External published/exported results remain."] ne {ok}} return
        }
        default {error {Unknown History action}}
    }
    set prior [historyNative state $h];set target [historyNative state $h $index]
    dict set ::GX::ScientificHistory::viewers $window restoring 1
    try {
        _historyRestore $window $target $action
        set receipt [historyNative [expr {$action eq {branch} ? {branch} : {navigate}}] $h $index]
    } on error {message options} {
        _historyRestore $window $prior rollback
        return -options $options $message
    } finally {dict set ::GX::ScientificHistory::viewers $window restoring 0}
    dict set receipt transition $action
    set receipt [_historyAccepted $window $receipt]
    _historySyncAuxiliary $window $action
    return [dict merge $receipt [scientificHistoryViewerStatus $window]]
}
proc ::GX::scientificHistoryViewerBrowse {window index {mode legacy}} {
    if {$mode ni {legacy index latest}} {error {Unknown History browse mode}}
    set adapter [_scientificHistoryGuard $window];set record [dict get $adapter record]
    if {[dict exists $adapter hook_pending]} {error {Finish or cancel the pending History hook before browsing}}
    set count [llength [dict get $record steps]]
    set previous [uplevel #0 [dict get $adapter callbacks capture]]
    set latest [expr {$mode eq {latest} || ($mode eq {legacy} && $index==$count) || ($mode eq {index} && $index==$count && [dict get $record cursor]==$count)}]
    set desired [historyNative state [dict get $adapter handle] [expr {$latest ? [dict get $record cursor] : $index}]]
    dict set ::GX::ScientificHistory::viewers $window restoring 1
    try {_historyRestore $window $desired [expr {$latest ? {latest} : {browse}}]} on error {message options} {
        _historyRestore $window $previous rollback
        return -options $options $message
    } finally {dict set ::GX::ScientificHistory::viewers $window restoring 0}
    dict set ::GX::ScientificHistory::viewers $window browsing [expr {!$latest}]
    dict set ::GX::ScientificHistory::viewers $window browse_cursor [expr {$latest ? [dict get $record cursor] : $index}]
    _historyRefreshSchedule $window
}
proc ::GX::scientificHistoryViewerClear {window workspace} {
    set adapter [_scientificHistoryGuard $window];set record [dict get $adapter record]
    if {[dict get $adapter browsing] || [dict get $record cursor]!=[llength [dict get $record steps]]} {error {Return to latest before clearing History}}
    if {[dict get $record steps] eq {}} return
    if {[dict get $adapter document_id] ne $workspace} {error {History clear requested for a different Document owner}}
    set metadata [interactiveDocumentMetadata $workspace]
    set registered [expr {[dict exists $::GX::SessionWorkspace::providers [dict get $metadata provider_id]]}]
    if {$registered} {set name [dict get [sessionWorkspaceGet $workspace] name];set backupKind Workspace} else {set name "Document $workspace";set backupKind Session}
    set decision [tk_messageBox -parent [_historyDialogParent $window] -type yesnocancel -default cancel -icon warning -title {Clear History} -message "Clear historical steps for '$name', preserving all current state?\nYes: save a protected $backupKind backup first.\nNo: clear without backup.\nCancel: keep all History."]
    if {$decision eq {cancel}} return
    if {$decision eq {yes}} {
        set destination [workspaceSaveFile export_dir -parent [_historyDialogParent $window] -title "Save protected $backupKind backup" -defaultextension .zip -filetypes {{{Protected ZIP} {.zip}}}]
        if {$destination eq {}} return
        scientificHistoryViewerFlush $window
        if {$registered} {
            set package [sessionWorkspaceExport $workspace]
            filePublicationPublishBundle [list [dict create id history_backup destination $destination writer [list ::GX::_scientificHistoryBackupWriter $package]]]
        } else {scientificHistoryFlushAll;sessionPortableExport [_interactiveDocumentRequireSession] $destination}
    }
    set receipt [historyNative clear [dict get $adapter handle] [uplevel #0 [dict get $adapter callbacks capture]]]
    dict set ::GX::ScientificHistory::viewers $window record [historyNative summary [dict get $adapter handle]]
    dict set receipt transition clear
    _historyAccepted $window $receipt
    _historySyncAuxiliary $window clear
    scientificHistoryViewerFlush $window
}
proc ::GX::_scientificHistoryBackupWriter {resource channel context} {
    set reader [interactiveDocumentResourceOpenReader $resource]
    try {
        while 1 {
            set block [interactiveDocumentResourceNext $reader]
            puts -nonewline $channel [dict get $block bytes]
            if {[dict get $block eof]} break
        }
    } finally {interactiveDocumentResourceCloseReader $reader}
}
proc ::GX::scientificHistoryStripFields {} {
    return [dict create visible [dict create type boolean label {Show Description / History strip} default 1] mode [dict create type choice label {Strip mode} values {Description History} default Description] grouped [dict create type boolean label {Group consecutive related operations} default 1]]
}
proc ::GX::scientificHistoryStripValidate {values} {
    set result {}
    dict for {key field} [scientificHistoryStripFields] {dict set result $key [uiFieldNormalize $field [datasetPublicationV2DictDefault $values $key [dict get $field default]]]}
    foreach key [dict keys $values] {if {![dict exists $result $key]} {error {Unknown History strip preference}}}
    return $result
}
proc ::GX::scientificHistoryViewerStripGet {window} {
    return [datasetPublicationV2DictDefault [dict get $::GX::ScientificHistory::viewers $window] strip_settings [scientificHistoryStripValidate {}]]
}
proc ::GX::scientificHistoryViewerStripSet {window values} {
    # Choosing a presentation mode does not restore or edit scientific state.
    # A retained window may still display its own History after a Session
    # switch, or while its owner is busy. Never persist into the new Session.
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    set settings [scientificHistoryStripValidate [dict merge [dict get $adapter strip_settings] $values]]
    set id [dict get $adapter strip_configuration]
    if {$id ne {} && $::GX::currentSession ne {} && [dict get $adapter token] eq [interactiveDocumentSessionToken]} {
        configurationCommit [list [dict create id $id scope session value $settings session_token [_configurationSessionToken]]]
    } else {_scientificHistoryStripApply $window $settings}
}
proc ::GX::scientificHistoryViewerStripToggle {window} {
    set settings [dict get $::GX::ScientificHistory::viewers $window strip_settings]
    scientificHistoryViewerStripSet $window [dict create visible [expr {![dict get $settings visible]}]]
}
proc ::GX::_scientificHistoryStripChanged {window id} {
    if {![dict exists $::GX::ScientificHistory::viewers $window] || ![winfo exists [_historyDialogParent $window]]} return
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    if {[dict get $adapter token] ne [interactiveDocumentSessionToken]} return
    set config [dict get $adapter strip_configuration]
    if {$id ni [list {} $config]} return
    _scientificHistoryStripApply $window [scientificHistoryStripValidate [dict get [configurationResolve $config] effective]]
}
proc ::GX::_scientificHistoryStripApply {window settings} {
    if {![dict exists $::GX::ScientificHistory::viewers $window] || ![winfo exists [_historyDialogParent $window]]} return
    set adapter [dict get $::GX::ScientificHistory::viewers $window];set frame [dict get $adapter strip]
    dict set ::GX::ScientificHistory::viewers $window strip_settings $settings
    set ::GX::ScientificHistory::strip($window,mode) [dict get $settings mode]
    _scientificHistoryStripSwitch $window 0
    if {[dict get $settings visible]} {
        if {[winfo manager $frame] eq {}} {pack $frame {*}[dict get $adapter strip_layout]}
    } else {pack forget $frame}
    scientificHistoryViewerRefresh $window
}
proc ::GX::scientificHistoryDemoCreate {widget callback} {
    ttk::labelframe $widget -text {DEMO / simulated local History · no canonical record} -padding 8
    ttk::notebook $widget.pages
    ttk::frame $widget.pages.description;ttk::frame $widget.pages.history
    $widget.pages add $widget.pages.description -text Description
    $widget.pages add $widget.pages.history -text History
    ttk::label $widget.pages.description.text -text {Synthetic instrument layout · presentation changes only} -wraplength 500
    pack $widget.pages.description.text -fill x -padx 6 -pady 8
    listbox $widget.pages.history.list -height 3 -exportselection 0
    $widget.pages.history.list insert end {0 · Synthetic baseline} {1 · Synthetic view position} {2 · Synthetic label change}
    pack $widget.pages.history.list -fill both -expand 1
    bind $widget.pages.history.list <<ListboxSelect>> [list {*}$callback simulated_history_selection]
    bind $widget.pages <<NotebookTabChanged>> [list {*}$callback simulated_history_page]
    pack $widget.pages -fill both -expand 1
    return $widget
}
proc ::GX::scientificHistoryViewerStrip {window parent status {configurationId {}} {layout {-fill x}}} {
    set frame $parent.historyStrip
    ttk::frame $frame -height [expr {max(32,[font metrics TkDefaultFont -linespace]+12)}]
    pack propagate $frame 0
    set ::GX::ScientificHistory::strip($window,mode) Description
    ttk::combobox $frame.choice -state readonly -values {Description History} -width 12 -textvariable ::GX::ScientificHistory::strip($window,mode)
    uiFieldSelectorWithinViewer $frame.choice [_historyDialogParent $window]
    pack $frame.choice -side left -fill y
    pack forget $status
    pack $status -in $frame -side left -fill x -expand 1;raise $status
    canvas $frame.timeline -height 30 -background #edf1f5 -highlightthickness 0 -xscrollincrement 24
    bind $frame.choice <<ComboboxSelected>> [list ::GX::_scientificHistoryStripSwitch $window]
    bind $frame.timeline <Button-1> [list ::GX::_scientificHistoryStripClick $window %x %y]
    bind $frame.timeline <Button-3> [list ::GX::_scientificHistoryStripContext $window %X %Y]
    bind $frame.timeline <Button-4> [list $frame.timeline xview scroll -3 units]
    bind $frame.timeline <Button-5> [list $frame.timeline xview scroll 3 units]
    ttk::button $frame.details -text Details -command [list ::GX::scientificHistoryViewerDetails $window]
    pack $frame.details -side right
    bind $frame <Configure> [list ::GX::_scientificHistoryStripSize $window]
    bind $frame.choice <Configure> [list ::GX::_scientificHistoryStripSize $window]
    dict set ::GX::ScientificHistory::viewers $window strip $frame
    dict set ::GX::ScientificHistory::viewers $window status $status
    dict set ::GX::ScientificHistory::viewers $window strip_configuration $configurationId
    dict set ::GX::ScientificHistory::viewers $window strip_layout $layout
    set settings [scientificHistoryStripValidate {}]
    if {$configurationId ne {}} {
        set settings [scientificHistoryStripValidate [dict get [configurationResolve $configurationId] effective]]
        dict set ::GX::ScientificHistory::viewers $window strip_subscription [configurationSubscribe [list ::GX::_scientificHistoryStripChanged $window]]
    }
    _scientificHistoryStripApply $window $settings
    scientificHistoryViewerRefresh $window
    return $frame
}
proc ::GX::_scientificHistoryStripSize {window} {
    if {![dict exists $::GX::ScientificHistory::viewers $window strip]} return
    set frame [dict get $::GX::ScientificHistory::viewers $window strip]
    if {![winfo exists $frame]} return
    set height [expr {max(32,[font metrics TkDefaultFont -linespace]+12,[winfo reqheight $frame.choice],[winfo reqheight $frame.details])}]
    if {[$frame cget -height]!=$height} {$frame configure -height $height}
    $frame.timeline configure -height $height
    scientificHistoryViewerRefresh $window
}
proc ::GX::_scientificHistoryStripSwitch {window {persist 1}} {
    if {$persist} {return [scientificHistoryViewerStripSet $window [dict create mode $::GX::ScientificHistory::strip($window,mode)]]}
    set adapter [dict get $::GX::ScientificHistory::viewers $window];set frame [dict get $adapter strip]
    pack forget [dict get $adapter status] $frame.timeline
    if {$::GX::ScientificHistory::strip($window,mode) eq "History"} {pack $frame.timeline -side left -fill both -expand 1} else {pack [dict get $adapter status] -in $frame -side left -fill x -expand 1}
}
proc ::GX::_scientificHistoryStripClick {window x y} {
    set frame [dict get $::GX::ScientificHistory::viewers $window strip]
    foreach item [$frame.timeline find overlapping [$frame.timeline canvasx $x] [$frame.timeline canvasy $y] [$frame.timeline canvasx $x] [$frame.timeline canvasy $y]] {
        foreach tag [$frame.timeline gettags $item] {if {[regexp {^history_step_([0-9]+)$} $tag -> index]} {scientificHistoryViewerBrowse $window $index index;return}}
    }
}
proc ::GX::_scientificHistoryStripContext {window x y} {
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    set cursor [dict get $adapter record cursor];set count [llength [dict get $adapter record steps]]
    set browsing [dict get $adapter browsing];set selected [dict get $adapter browse_cursor]
    set menu [_historyDialogParent $window].historyContext
    if {![winfo exists $menu]} {menu $menu -tearoff 0}
    $menu delete 0 end
    foreach {action label} {undo Undo redo Redo previous {Previous history step} next {Next history step} latest {Return to latest} branch {Restart here / discard later local history…}} {
        if {[dict exists $::GX::ViewerCommands::windows $window handlers $action]} {viewerCommandMenuAdd $window $menu $action} else {$menu add command -label $label -command [list ::GX::scientificHistoryViewerNavigate $window $action]}
        set enabled 1
        switch $action {
            undo {set enabled [expr {!$browsing && $cursor>0}]}
            redo {set enabled [expr {!$browsing && $cursor<$count}]}
            previous {set enabled [expr {$selected>0}]}
            next {set enabled [expr {$selected<$count}]}
            branch {set enabled [expr {$selected<$count || ($browsing && $cursor<$count)}]}
            latest {set enabled $browsing}
        }
        if {!$enabled} {$menu entryconfigure end -state disabled}
    }
    foreach row [scientificHistoryGroupedEntries [dict get $adapter record] 1] {
        if {$selected>=[dict get $row first] && $selected<=[dict get $row last] && [dict get $row count]>1} {
            $menu add command -label {Expand / collapse individual operations} -command [list ::GX::scientificHistoryViewerGroupExpand $window [dict get $row first]]
        }
    }
    if {[dict exists $adapter callbacks context]} {uplevel #0 [list {*}[dict get $adapter callbacks context] $menu $selected]}
    $menu add separator
    $menu add command -label {History details…} -command [list ::GX::scientificHistoryViewerDetails $window]
    $menu add command -label {Hide Description / History strip} -command [list ::GX::scientificHistoryViewerStripToggle $window]
    set document [dict get $adapter document_id]
    if {$document ne {}} {$menu add command -label {Clear History…} -state [expr {!$browsing && $cursor==$count && $count>0 ? {normal} : {disabled}}] -command [list ::GX::scientificHistoryViewerClear $window $document]}
    scientificHistoryPopup $window $menu $x $y
}
proc ::GX::scientificHistoryGroupedEntries {record {grouped 1}} {
    set result [list [dict create first 0 last 0 count 1 description Baseline timestamp {} operation baseline api_id {}]];set index 0
    foreach step [dict get $record steps] {
        incr index
        set entry [dict create first $index last $index count 1]
        foreach key {description timestamp operation api_id} {dict set entry $key [datasetPublicationV2DictDefault $step $key [expr {$key eq {timestamp} ? 0 : ($key eq {description} ? [dict get $step operation] : {})}]]}
        foreach key {kind group group_id group_label} {if {[dict exists $step $key]} {dict set entry $key [dict get $step $key]}}
        set previous [lindex $result end];set merge $grouped
        set identity [expr {[dict exists $entry group_id] && [dict exists $previous group_id] && [dict get $entry group_id] ne {}}]
        set keys [expr {$identity ? {group_id operation api_id} : {description operation api_id}}]
        foreach key $keys {if {[dict get $entry $key] ne [dict get $previous $key]} {set merge 0}}
        if {[dict get $previous timestamp] eq {} || abs([dict get $entry timestamp]-[dict get $previous timestamp])>60} {set merge 0}
        if {$merge} {dict set previous last $index;dict incr previous count;dict set previous timestamp [dict get $entry timestamp];lset result end $previous} else {lappend result $entry}
    }
    return $result
}
proc ::GX::scientificHistoryViewerDetails {window} {
    set adapter [dict get $::GX::ScientificHistory::viewers $window];set text {}
    if {$::GX::ScientificHistory::strip($window,mode) eq "Description"} {
        set status [dict get $adapter status];set variable [$status cget -textvariable]
        set text [expr {$variable eq {} ? [$status cget -text] : [uplevel #0 [list set $variable]]}]
    } else {
        set record [dict get $adapter record];set index 0
        append text "History cursor: [dict get $adapter browse_cursor] / [llength [dict get $record steps]]\n\n0: Baseline\n"
        foreach step [dict get $record steps] {append text "[incr index]: [dict get $step description]\n  [expr {[dict get $step timestamp]==0 ? {Timestamp unavailable in imported History} : [clock format [dict get $step timestamp] -format {%Y-%m-%d %H:%M:%S}]}]\n"}
    }
    set uiWindow [_historyDialogParent $window]
    set dialog $uiWindow.historyDetails
    if {[winfo exists $dialog]} {destroy $dialog}
    toplevel $dialog;wm title $dialog "[wm title $uiWindow] — $::GX::ScientificHistory::strip($window,mode) details"
    text $dialog.text -width 90 -height 22 -wrap word -yscrollcommand [list $dialog.scroll set]
    ttk::scrollbar $dialog.scroll -command [list $dialog.text yview]
    $dialog.text insert end $text;$dialog.text configure -state disabled
    pack $dialog.scroll -side right -fill y;pack $dialog.text -fill both -expand 1
    update idletasks
    set width [expr {min([winfo reqwidth $dialog],[winfo width $uiWindow])}]
    set height [expr {min([winfo reqheight $dialog],max(100,[winfo height $uiWindow]-24))}]
    wm transient $dialog $uiWindow
    wm geometry $dialog ${width}x${height}+[winfo rootx $uiWindow]+[expr {[winfo rooty $uiWindow]+24}]
    bind $dialog <Escape> [list destroy $dialog]
}
proc ::GX::scientificHistoryViewerRefresh {window} {
    if {![dict exists $::GX::ScientificHistory::viewers $window]} return
    if {![llength [info commands winfo]] || ![winfo exists [_historyDialogParent $window]]} return
    set adapter [dict get $::GX::ScientificHistory::viewers $window]
    if {[dict exists $adapter strip] && [winfo exists [dict get $adapter strip].timeline] && [dict get $adapter strip_settings visible] && [dict get $adapter strip_settings mode] eq {History}} {
        set canvas [dict get $adapter strip].timeline;$canvas delete all
        set record [dict get $adapter record];set x 3;set index 0
        set height [[dict get $adapter strip] cget -height]
        set grouped [dict get $adapter strip_settings grouped]
        foreach step [_historyEntries $window] {
            set index [dict get $step last];set first [dict get $step first]
            set label [expr {$index==0 ? "Baseline" : "$index: [dict get $step description]"}]
            if {[dict get $step count]>1} {set label "$first–$index: [datasetPublicationV2DictDefault $step group_label [dict get $step description]] ×[dict get $step count]"}
            if {[dict get $step timestamp] ni {{} 0}} {append label " · [clock format [dict get $step timestamp] -format %H:%M:%S]"}
            set cursor [dict get $adapter browse_cursor]
            set fill [expr {$cursor>=$first && $cursor<=$index ? "#c5dff4" : "#edf1f5"}]
            set tag history_step_$index
            set text [$canvas create text [expr {$x+6}] [expr {$height/2.0}] -anchor w -text $label -tags $tag]
            set bounds [$canvas bbox $text];set right [expr {[lindex $bounds 2]+6}]
            if {$right<$x+40} {set right [expr {$x+40}]}
            set rectangle [$canvas create rectangle $x 1 $right [expr {$height-1}] -fill $fill -outline #c7cdd5 -tags $tag]
            $canvas lower $rectangle $text
            set x [expr {$right+4}]
        }
        $canvas configure -scrollregion [list 0 0 $x $height]
    }
    viewerCommandMenusRefresh [_historyDialogParent $window]
}
