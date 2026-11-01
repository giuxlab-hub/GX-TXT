# SPDX-License-Identifier: GPL-3.0-or-later
# Named complete workflows around the existing P017 engine.
proc ::GX::_workspaceArchiveContext {window} {
    set adapter [_scientificHistoryGuard $window]
    set parent [_historyDialogParent $window]
    if {![dict exists $::GX::SessionWorkspace::adapters $parent]} {error {Save/open this Viewer through its Workspace menu first}}
    set context [dict get $::GX::SessionWorkspace::adapters $parent]
    set id [_workspaceHostCurrent $context]
    if {$id eq {}} {error {Save this Workspace before archiving History}}
    set meta [sessionWorkspaceMetadata $id]
    if {![dict get $meta native_workspace] || ![dict get $meta compatible]} {error {Named History requires an available native Workspace}}
    return [list $adapter $context $id]
}
proc ::GX::_workspaceArchiveHistoryPath {adapter state} {
    set channel [datasetPublicationV2DictDefault [dict get $adapter callbacks] channel {}]
    set fields [lindex $state 1]
    if {$channel ne {}} {return [list domain_history $channel]}
    if {[dict get $adapter owner] eq {viewer.curve_workbench}} {return {cad_workspace scientific_recipe}}
    foreach key {history scientific_history} {if {[dict exists $fields $key]} {return [list $key]}}
    error {Provider has no declared complete History projection in this Workspace}
}
proc ::GX::_workspaceArchiveTypedAt {state path} {foreach key $path {if {[lindex $state 0] ne {object}} {error {Invalid declared History projection}};set state [dict get [lindex $state 1] $key]};return $state}
proc ::GX::_workspaceArchiveAuxiliaryEncode {adapter auxiliary} {
    if {[dict get $adapter owner] eq {viewer.curve_workbench}} {return [nativeWorkspaceEncode {named cwb_auxiliary} $auxiliary]}
    if {[dict exists $adapter callbacks archive_auxiliary_encode]} {return [uplevel #0 [list {*}[dict get $adapter callbacks archive_auxiliary_encode] $auxiliary]]}
    if {$auxiliary ne {}} {error {This History owner must declare its typed archive auxiliary codec}}
    return {object {}}
}
proc ::GX::scientificHistoryArchiveSave {window name} {
    lassign [_workspaceArchiveContext $window] adapter context id
    if {[dict get $adapter browsing] || [dict exists $adapter hook_pending]} {error {Finish History browsing or pending work before saving a named workflow}}
    # Typing and direct editor controls need not append on every keystroke.
    # This explicit snapshot must nevertheless include the current live state.
    # The existing engine emits no entry when its declared capture is unchanged.
    scientificHistoryViewerRecordOperation $window "Named History snapshot: $name"
    # The existing host Save projects the live P017 record through its provider.
    # No archive is replayed during this Save or an ordinary close.
    _historyWorkspaceSave $context
    set adapter [_scientificHistoryGuard $window]
    set snapshot [nativeWorkspaceGet $id]
    set path [_workspaceArchiveHistoryPath $adapter [dict get $snapshot state]]
    set record [_workspaceArchiveTypedAt [dict get $snapshot state] $path]
    scientificHistoryValidate [dict get $adapter owner] [nativeWorkspaceScientificDecode $record]
    set auxiliary [_workspaceArchiveAuxiliaryEncode $adapter [historyNative auxiliary [dict get $adapter handle]]]
    set archiveContext [list object [dict create workspace_state [dict get $snapshot state] workspace_properties [dict get $snapshot properties] history_projection [nativeWorkspaceEncode {array text} $path] channel [list text [datasetPublicationV2DictDefault [dict get $adapter callbacks] channel {}]]]]
    return [nativeWorkspaceHistorySave $snapshot $name $record $auxiliary $archiveContext]
}
proc ::GX::_workspaceArchiveSourceGuard {provider typedState} {
    nativeWorkspaceScriptValidate $provider $typedState
    set refs {};_nativeWorkspaceTypedReferences $typedState refs
    dict for {key reference} $refs {interactiveDocumentResourceInfo $reference}
}
proc ::GX::scientificHistoryArchiveRestore {window archive {review 1}} {
    lassign [_workspaceArchiveContext $window] adapter context id
    set held [nativeWorkspaceMetadata $id]
    if {$review} {
        # Review without Discard side effects. Cancel preserves both timelines.
        set cb [dict get $context callbacks]
        set dirty [expr {[dict get $adapter dirty] || ([dict exists $cb dirty] && [uplevel #0 [dict get $cb dirty]])}]
        if {$dirty} {
            if {[dict exists $cb review]} {uplevel #0 [list {*}[dict get $cb review] 1]}
            try {set answer [tk_messageBox -parent [_historyDialogParent $window] -title {Restore named History} -icon question -type yesnocancel -default cancel -message {Save the current Workspace before restoring this workflow? Yes: Save. No: replace the unsaved draft. Cancel: keep editing.}]} finally {if {[dict exists $cb review]} {uplevel #0 [list {*}[dict get $cb review] 0]}}
            if {$answer eq {cancel}} {return cancelled}
            if {$answer eq {yes}} {_historyWorkspaceSave $context;set held [nativeWorkspaceMetadata $id]}
        }
    }
    lassign [_workspaceArchiveContext $window] adapter context id
    if {[dict exists $adapter hook_pending] || [dict get $adapter browsing]} {error {Finish pending History work/browsing before restoring an archive}}
    set before [nativeWorkspaceGet $id]
    if {[dict get $before id] ne [dict get $held id] || [dict get $before generation] ne [dict get $held generation] || [dict get $before revision] ne [dict get $held revision]} {error {Workspace changed during History review}}
    set typed [nativeWorkspaceHistoryGet $id $archive];set fields [lindex $typed 1]
    set savedContext [lindex [dict get $fields context] 1]
    set channel [datasetPublicationV2DictDefault [dict get $adapter callbacks] channel {}]
    if {[dict get $savedContext channel] ne [list text $channel]} {error {Named History belongs to a different active channel}}
    set targetState [dict get $savedContext workspace_state];set targetProperties [dict get $savedContext workspace_properties]
    set projection [nativeWorkspaceDecode [dict get $savedContext history_projection]]
    if {$projection ne [_workspaceArchiveHistoryPath $adapter $targetState] || ![workspaceNative typed_equal [_workspaceArchiveTypedAt $targetState $projection] [dict get $fields record]]} {error {Named History differs from its retained Workspace projection}}
    _workspaceArchiveSourceGuard [dict get $before provider_id] $targetState
    set propertyReferences {};_nativeWorkspaceTypedReferences $targetProperties propertyReferences
    dict for {key reference} $propertyReferences {interactiveDocumentResourceInfo $reference}
    set targetRecord [nativeWorkspaceScientificDecode [dict get $fields record]]
    scientificHistoryValidate [dict get $adapter owner] $targetRecord
    scientificRecipeValidate [scientificRecipeEncode $targetRecord]
    set targetAuxiliary [nativeWorkspaceScientificDecode [dict get $fields auxiliary]]
    set h [dict get $adapter handle];set priorRecord [historyNative record $h];set priorAuxiliary [historyNative auxiliary $h]
    # Encode the old active record with the SAME explicit provider projection.
    # Unsaved active work is retained in the intent for prepared-phase rollback.
    set oldRecord [_workspaceArchiveEncodeLive $adapter $before $priorRecord]
    set oldAuxiliary [_workspaceArchiveAuxiliaryEncode $adapter $priorAuxiliary]
    set identity [_historyIdentity [dict get $adapter owner] $id $channel]
    set relative [file join metadata history [file tail [dict get $adapter path]]]
    set intent [list object [dict create owner [list text [dict get $adapter owner]] history_relative [list text $relative] history_identity [list text $identity] old_record $oldRecord target_record [dict get $fields record] old_auxiliary $oldAuxiliary target_auxiliary [dict get $fields auxiliary]]]
    set handle [_nativeWorkspaceRequire]
    # A cold native store has no in-process scientific-owner admissions yet.
    # Reconsult the existing resource authority (including retired carriers)
    # before the native transition checks these retained typed references.
    foreach typed [list $targetState $targetProperties $intent] {_nativeWorkspaceScientificOwnersAdmit $handle $typed}
    set token [workspaceNative transition_prepare $handle $id [dict get $before generation] [dict get $before revision] $intent]
    set committed 0;set commitStarted 0
    dict set ::GX::ScientificHistory::viewers $window restoring 1
    try {
        # Owner validation/restoration occurs before either durable authority is
        # committed. Its existing guard prevents ordinary edits during restore.
        _historyRestore $window [scientificHistoryState $targetRecord] archive
        _historyRestoreAuxiliary $window $targetAuxiliary
        set status [historyNative status $h]
        historyNative replace $h $targetRecord $targetAuxiliary [dict get $status revision]
        historyNative flush $h 30000
        set commitStarted 1
        workspaceNative transition_commit $handle $token $id [dict get $before generation] [dict get $before revision] $targetState $targetProperties
        set result [workspaceNative flush $handle $id]
        set committed 1
        workspaceNative transition_finish $handle $token
        dict set ::GX::ScientificHistory::viewers $window record [historyNative summary $h]
        dict set ::GX::ScientificHistory::viewers $window accepted_revision [dict get [historyNative status $h] revision]
        dict set ::GX::ScientificHistory::viewers $window browse_cursor [dict get $targetRecord cursor]
        dict set ::GX::ScientificHistory::viewers $window browsing 0
        dict set ::GX::ScientificHistory::viewers $window dirty 0
        # Update only owner projection caches after both authorities are durable.
        # commit may be a native no-op when its projection is already identical.
        _nativeWorkspaceMetadataAdvanced $before [nativeWorkspaceMetadata $id]
        _historyWorkspaceSave $context
        _historyRefreshSchedule $window
        return $result
    } on error {message options} {
        if {!$committed && !$commitStarted} {
            if {![catch {
                historyNative replace $h $priorRecord $priorAuxiliary [dict get [historyNative status $h] revision]
                historyNative flush $h 30000
                _historyRestore $window [scientificHistoryState $priorRecord] rollback
                _historyRestoreAuxiliary $window $priorAuxiliary
                dict set ::GX::ScientificHistory::viewers $window record [historyNative summary $h]
                dict set ::GX::ScientificHistory::viewers $window accepted_revision [dict get [historyNative status $h] revision]
                dict set ::GX::ScientificHistory::viewers $window browse_cursor [dict get $priorRecord cursor]
                dict set ::GX::ScientificHistory::viewers $window dirty [dict get $adapter dirty]
                workspaceNative transition_finish $handle $token
            } rollback]} {} else {append message "\nRecovery intent retained: $rollback"}
        }
        return -options $options $message
    } finally {dict set ::GX::ScientificHistory::viewers $window restoring 0}
}
proc ::GX::_workspaceArchiveEncodeLive {adapter snapshot record} {
    set provider [_workspaceProvider [dict get $snapshot provider_id]]
    set decode [datasetPublicationV2DictDefault $provider decode ::GX::nativeWorkspaceDecode]
    set payload [uplevel #0 [list {*}$decode [dict get $snapshot state]]]
    set path [_workspaceArchiveHistoryPath $adapter [dict get $snapshot state]]
    dict set payload {*}$path $record
    set typed [uplevel #0 [list {*}[dict get $provider encode] $payload]]
    return [_workspaceArchiveTypedAt $typed $path]
}
proc ::GX::_nativeWorkspaceTransitionRecover {handle} {
    foreach typed [lindex [workspaceNative transition_list $handle] 1] {
        set entry [nativeWorkspaceDecode $typed];set fields [lindex [dict get [lindex $typed 1] content] 1]
        set root [_interactiveDocumentRequireSession];set relative [lindex [dict get $fields history_relative] 1]
        if {![regexp {^metadata/history/idoc_[0-9]+(?:\.[A-Za-z][A-Za-z0-9_]*)?\.gxh$} $relative]} {error {Unsafe interrupted History transition path}}
        set family [file join $root {*}[split $relative /]]
        foreach part [list $root [file join $root metadata] [file join $root metadata history] $family "$family.checkpoint" "$family.lock"] {if {![catch {file lstat $part status}] && $status(type) eq {link}} {error {Interrupted History transition contains a symlink}}}
        set phase [dict get $entry phase];if {$phase ni {prepared committed}} {error {Unknown interrupted History transition phase}}
        set prefix [expr {$phase eq {committed}?{target}:{old}}]
        set owner [lindex [dict get $fields owner] 1]
        set identity [lindex [dict get $fields history_identity] 1]
        file stat $root rootStatus
        if {[lrange $identity 0 2] ne [list [file normalize $root] $rootStatus(dev) $rootStatus(ino)] || [lindex $identity 3] ne $owner || [lindex $identity 4] ne [dict get $entry workspace] || [lindex $identity 5] ne [dict get $entry generation]} {error {Interrupted History transition belongs to a foreign Session/owner}}
        set record [nativeWorkspaceScientificDecode [dict get $fields ${prefix}_record]]
        set auxiliary [nativeWorkspaceScientificDecode [dict get $fields ${prefix}_auxiliary]]
        _historyNativeRequire
        # Open the verified actual journal before selecting the coordinator's
        # resolution. P017 correctly rejects opening an existing journal with a
        # different desired initial record; replacement is its supported API.
        set recovered [historyNative recover $family $identity]
        set actualRecord [dict get $recovered record]
        set actualAuxiliary [datasetPublicationV2DictDefault $recovered auxiliary {}]
        set h [historyNative open $owner $actualRecord $family $identity $actualAuxiliary]
        try {historyNative replace $h $record $auxiliary [dict get [historyNative status $h] revision];historyNative flush $h 30000} finally {historyNative close $h}
        workspaceNative transition_finish $handle [dict get $entry token]
    }
}
proc ::GX::scientificHistoryArchiveMenu {window menu} {
    if {![dict exists $::GX::ScientificHistory::viewers $window]} return
    set parent [_historyDialogParent $window]
    if {![info exists ::GX::SessionWorkspace::adapters] || ![dict exists $::GX::SessionWorkspace::adapters $parent]} return
    set channel [datasetPublicationV2DictDefault [dict get $::GX::ScientificHistory::viewers $window callbacks] channel {}]
    set suffix [expr {$channel eq {}?{}:" ($channel)"}]
    $menu add separator
    $menu add command -label "Save History As…$suffix" -command [list ::GX::_workspaceArchiveGui $window save]
    $menu add command -label "Named History…$suffix" -command [list ::GX::_workspaceArchiveGui $window browse]
}
proc ::GX::_workspaceArchiveMenuInstall {window} {
    if {![dict exists $::GX::ScientificHistory::viewers $window] || ![llength [info commands winfo]]} return
    set parent [_historyDialogParent $window]
    if {![winfo exists $parent] || ![info exists ::GX::SessionWorkspace::adapters] || ![dict exists $::GX::SessionWorkspace::adapters $parent]} return
    set menubar [$parent cget -menu];if {$menubar eq {}} return
    for {set i 0} {$i<=[$menubar index end]} {incr i} {
        if {[$menubar type $i] eq {cascade} && [string match -nocase *history* [$menubar entrycget $i -label]]} {scientificHistoryArchiveMenu $window [$menubar entrycget $i -menu];return}
    }
}
proc ::GX::_workspaceArchiveGui {window action {dialog {}}} {
    if {[catch {
        lassign [_workspaceArchiveContext $window] adapter context id
        switch $action {
            save {set form [_historyDialogParent $window].historyName;uiFieldFormCreate $form {Save History As} {name {type string required 1 label Name}} {name {New workflow}} [list ::GX::_workspaceArchiveNamed $window save {} $form {}] [_historyDialogParent $window]}
            browse {
                set dialog [_historyDialogParent $window].namedHistory
                if {[winfo exists $dialog]} {raise $dialog;return}
                toplevel $dialog;wm title $dialog {Named History};wm transient $dialog [_historyDialogParent $window]
                ttk::treeview $dialog.list -columns {name count cursor} -show headings -selectmode browse
                foreach key {name count cursor} {$dialog.list heading $key -text [string totitle $key]}
                text $dialog.inspect -height 6 -width 72 -wrap word -state disabled
                ttk::frame $dialog.actions
                foreach {command label} {inspect Inspect restore Restore rename Rename delete Delete} {ttk::button $dialog.actions.$command -text $label -command [list ::GX::_workspaceArchiveGui $window $command $dialog];pack $dialog.actions.$command -side left -padx 4}
                pack $dialog.list -fill both -expand 1;pack $dialog.inspect -fill x;pack $dialog.actions -fill x
                bind $dialog.list <<TreeviewSelect>> [list ::GX::_workspaceArchiveGui $window inspect $dialog]
                _workspaceArchiveGui $window refresh $dialog
            }
            refresh {$dialog.list delete [$dialog.list children {}];foreach typed [lindex [nativeWorkspaceHistoryList $id] 1] {set row [nativeWorkspaceDecode $typed];$dialog.list insert {} end -id [dict get $row id] -values [list [dict get $row name] [dict get $row count] [dict get $row cursor]]}}
            default {
                set archive [$dialog.list selection];if {[llength $archive]!=1} return
                set item [nativeWorkspaceDecode [nativeWorkspaceHistoryGet $id $archive]]
                switch $action {
                    inspect {$dialog.inspect configure -state normal;$dialog.inspect delete 1.0 end;$dialog.inspect insert end "[dict get $item name]\nOwner: [dict get $item owner]\nSchema: [dict get $item schema] / [dict get $item schema_version]\nSource revision: [dict get $item source_revision]\nOperations: [llength [dict get $item record steps]]; cursor: [dict get $item record cursor]\nSHA-256: [dict get $item sha256]";$dialog.inspect configure -state disabled}
                    restore {scientificHistoryArchiveRestore $window $archive}
                    rename {set form $dialog.name;uiFieldFormCreate $form {Rename History} {name {type string required 1 label Name}} [dict create name [dict get $item name]] [list ::GX::_workspaceArchiveNamed $window rename $archive $form $dialog] $dialog}
                    delete {if {[tk_messageBox -parent $dialog -type okcancel -default cancel -icon warning -message "Delete named workflow ‘[dict get $item name]’? Active History and scientific resources are preserved."] eq {ok}} {nativeWorkspaceHistoryDelete [nativeWorkspaceMetadata $id] $archive 1;_workspaceArchiveGui $window refresh $dialog}}
                }
            }
        }
    } message options]==1} {tk_messageBox -parent [_historyDialogParent $window] -icon error -title {Named History} -message $message}
}

proc ::GX::_workspaceArchiveNamed {window action archive form dialog values} {
    lassign [_workspaceArchiveContext $window] adapter context id
    set name [dict get $values name]
    if {$action eq {save}} {scientificHistoryArchiveSave $window $name} else {nativeWorkspaceHistoryRename [nativeWorkspaceMetadata $id] $archive $name;_workspaceArchiveGui $window refresh $dialog}
    if {[winfo exists $form]} {destroy $form}
}
