# SPDX-License-Identifier: GPL-3.0-or-later
# Owning-thread SDK projections. No paths or native pointers enter the worker.
proc ::GX::_viewerWorkspaceTypedJson {typed} {
    lassign $typed kind value
    switch -- $kind {
        null {return null}
        text {return [viewerDevelopmentJsonString $value]}
        int {if {![string is entier -strict $value]} {error {Invalid typed integer}};return [expr {entier($value)}]}
        bool {return [expr {$value?{true}:{false}}]}
        real {return [uiFieldNormalize {type number} $value]}
        object - resource {set fields {};dict for {key item} $value {lappend fields "[viewerDevelopmentJsonString $key]:[_viewerWorkspaceTypedJson $item]"};return \{[join $fields ,]\}}
        array {set fields {};foreach item $value {lappend fields [_viewerWorkspaceTypedJson $item]};return \[[join $fields ,]\]}
        default {error {Unknown typed Workspace value kind}}
    }
}
proc ::GX::_viewerWorkspaceSdkValue {record {depth 0}} {
    if {$depth>64} {error {Workspace command nesting exceeds bound}}
    set kind [dict get $record kind];set value [dict get $record value]
    if {$kind in {object resource}} {set fields {};dict for {key child} $value {dict set fields $key [_viewerWorkspaceSdkValue $child [expr {$depth+1}]]};return [list $kind $fields]}
    if {$kind eq {array}} {set fields {};foreach child $value {lappend fields [_viewerWorkspaceSdkValue $child [expr {$depth+1}]]};return [list array $fields]}
    return [list $kind $value]
}
proc ::GX::_viewerWorkspaceTypedTransportJson {typed} {
    lassign $typed kind value
    if {$kind in {object resource}} {
        set fields {};dict for {key child} $value {lappend fields "[viewerDevelopmentJsonString $key]:[_viewerWorkspaceTypedTransportJson $child]"}
        set data \{[join $fields ,]\}
    } elseif {$kind eq {array}} {
        set fields {};foreach child $value {lappend fields [_viewerWorkspaceTypedTransportJson $child]};set data \[[join $fields ,]\]
    } else {set data [_viewerWorkspaceTypedJson $typed]}
    return [format {{"kind":%s,"value":%s}} [viewerDevelopmentJsonString $kind] $data]
}
proc ::GX::_viewerWorkspaceSdkSnapshot {window {acknowledgement {}} {restoring {}}} {
    set instance [dict get $::GX::ViewerGui::instances $window];set id [dict get $instance workspace_id]
    set properties [datasetPublicationV2DictDefault [lindex [dict get $instance workspace_properties] 1] viewer_properties {object {}}]
    set fields [dict create id [list text $id] generation {text {}} revision {int 0} durable_revision {int 0} dirty [list bool [viewerGuiDesignDirty $window]] pending {bool 0} failed {bool 0} error {text {}} state [datasetPublicationV2DictDefault $instance cpp_workspace_state {object {}}] properties $properties entries {array {}}]
    if {$id ne {}} {
        set status [nativeWorkspaceStatus $id]
        foreach key {generation error} {dict set fields $key [list text [dict get $status $key]]}
        foreach key {revision durable_revision} {dict set fields $key [list int [dict get $status $key]]}
        foreach key {pending failed} {dict set fields $key [list bool [dict get $status $key]]}
    }
    if {[dict exists $instance workspace_provider]} {
        set entries {};foreach entry [nativeWorkspaceQuery [dict get $instance workspace_provider] {} {} 0 1000] {lappend entries [list object [dict create id [list text [dict get $entry id]] name [list text [dict get $entry name]] provider [list text [dict get $entry provider_id]] revision [list int [dict get $entry revision]]]]};dict set fields entries [list array $entries]
    }
    if {$acknowledgement ne {}} {
        foreach key {id generation error} {dict set fields $key [list text [dict get $acknowledgement $key]]}
        dict set fields revision [list int [dict get $acknowledgement accepted_revision]]
        dict set fields durable_revision [list int [dict get $acknowledgement durable_revision]]
        foreach key {pending dirty failed} {dict set fields $key [list bool [dict get $acknowledgement $key]]}
    }
    if {$restoring ne {}} {dict set fields state $restoring}
    set result {};dict for {key value} $fields {
        if {$key in {state properties}} {set encoded [_viewerWorkspaceTypedTransportJson $value]} else {set encoded [_viewerWorkspaceTypedJson $value]}
        lappend result "[viewerDevelopmentJsonString $key]:$encoded"
    }
    return \{[join $result ,]\}
}
proc ::GX::_viewerWorkspaceCppRestore {window state} {
    if {![dict exists $::GX::ViewerDevelopment::windows $window] || !([datasetPublicationV2DictDefault [dict get $::GX::ViewerDevelopment::windows $window] workspace_hook_mask 0]&4) || ![dict exists $state custom_state]} {return}
    set record [dict get $::GX::ViewerDevelopment::windows $window];set service [_viewerDevelopmentCompiledService $window]
    set nativeState [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $state domain_state {}] restricted_cpp {}] state [dict get $record state]]
    set payload [format {{"event":{"kind":5,"component":0,"value":0},"state":%s,"workspace_hook":"restore","context":{"workspace":%s}}} [viewerDevelopmentStateJson $nativeState] [_viewerWorkspaceSdkSnapshot $window {} [dict get $state custom_state]]]
    set response [encoding convertfrom utf-8 [binary decode base64 [scriptJobRequestExchange $service $payload]]]
    if {![dict get $response ok] || [dict get $response result status] ne {COMPLETED}} {return -code error -errorcode {GX WORKSPACE CPP_RESTORE_REJECTED} "C++ Workspace restoration failed: $response"}
    dict set ::GX::ViewerDevelopment::windows $window state $nativeState
}
proc ::GX::_viewerWorkspaceCppCommitted {window receipt} {
    if {![dict exists $::GX::ViewerDevelopment::windows $window] || !([datasetPublicationV2DictDefault [dict get $::GX::ViewerDevelopment::windows $window] workspace_hook_mask 0]&8)} {return $receipt}
    if {[dict get $receipt pending] || [dict get $receipt durable_revision]<[dict get $receipt accepted_revision]} {error {Native C++ committed hook requires durable state}}
    set incarnation [winfo id $window];set record [dict get $::GX::ViewerDevelopment::windows $window]
    set service [_viewerDevelopmentCompiledService $window]
    set payload [format {{"event":{"kind":5,"component":0,"value":0},"state":%s,"workspace_hook":"committed","context":{"workspace":%s}}} [viewerDevelopmentStateJson [dict get $record state]] [_viewerWorkspaceSdkSnapshot $window $receipt]]
    set response [encoding convertfrom utf-8 [binary decode base64 [scriptJobRequestExchange $service $payload]]]
    if {![dict exists $::GX::ViewerDevelopment::windows $window] || ![winfo exists $window] || [winfo id $window] ne $incarnation} {return $receipt}
    dict set ::GX::ViewerDevelopment::windows $window workspace_last_commit $response
    if {![dict get $response ok] || [dict get $response result status] ne {COMPLETED}} {
        return -code error -errorcode {GX WORKSPACE POST_COMMIT_HOOK_FAILED} "Workspace is durable; C++ completion hook failed: $response"
    }
    return $receipt
}
proc ::GX::_viewerGuiWorkspaceSdkCommand {window request} {
    if {![viewerGuiDesignGuard $window]} {error {Viewer or Session lifetime changed}}
    set instance [dict get $::GX::ViewerGui::instances $window]
    if {![dict exists $instance workspace_provider]} {error {Declare a Workspace component before using its facade}}
    set command [dict get $request command];set typed [_viewerWorkspaceSdkValue [dict get $request value]];set value [nativeWorkspaceDecode $typed]
    switch -- $command {
        set_state {
            if {[lindex $typed 0] ne {object}} {error {Custom Viewer state must be a typed object}}
            if {[dict exists [datasetPublicationV2DictDefault $instance workspace_hooks {}] capture]} {error {Custom state already has a capture hook owner}}
            if {[dict exists $::GX::ViewerDevelopment::windows $window] && ([datasetPublicationV2DictDefault [dict get $::GX::ViewerDevelopment::windows $window] workspace_hook_mask 0]&1)} {error {Custom state already has a C++ capture hook owner}}
            dict set ::GX::ViewerGui::instances $window cpp_workspace_state $typed
        }
        set_property {
            set fields [lindex $typed 1];set name [nativeWorkspaceDecode [dict get $fields name]]
            if {$name eq {} || [string length $name]>160 || [string first \x00 $name]>=0} {error {Invalid Viewer property name}}
            set properties [lindex [dict get $instance workspace_properties] 1]
            set user [lindex [datasetPublicationV2DictDefault $properties viewer_properties {object {}}] 1]
            dict set user $name [dict get $fields value];dict set properties viewer_properties [list object $user]
            dict set ::GX::ViewerGui::instances $window workspace_properties [list object $properties]
        }
        save {viewerGuiDesignWorkspaceSave $window $value}
        save_as {
            if {[dict exists $instance workspace_restore_failure]} {error {Recover the retained prior snapshot or reopen the saved Workspace before Save As}}
            set incarnation [winfo id $window]
            set payload [viewerGuiDesignCapture $window];dict set payload design [dict get $instance design]
            if {[dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerFlush $window;dict set payload history [scientificHistoryViewerRecord $window]}
            set original [dict get $instance workspace_id]
            if {$original eq {}} {
                set copy [sessionWorkspaceCreate [dict get $instance workspace_provider] $value $payload 0 [dict get $instance workspace_properties]]
            } else {
                nativeWorkspaceFlush $original
                set current [sessionWorkspaceGet $original]
                if {[dict get $instance workspace_stamp] ne [list [dict get $current generation] [dict get $current revision] [dict get $current sha256]]} {error {Workspace changed in another window; reopen it before Save As}}
                # Native duplication retains notes, named History archives and
                # their resources. Save the unsaved live payload only into the
                # new identity; the original Workspace remains untouched.
                set duplicate [nativeWorkspaceSaveAs $original [_workspaceName $value]]
                set newId [dict get $duplicate id]
                if {[catch {set copy [sessionWorkspaceUpdate $newId $payload [sessionWorkspaceGet $newId] 0 [dict get $instance workspace_properties]]} reason options]} {
                    return -options $options "Save As created Workspace $newId, but its current draft could not be saved: $reason. The original and the live draft are retained; review the new copy before continuing."
                }
            }
            if {![viewerGuiDesignGuard $window] || [winfo id $window] ne $incarnation} {error {Viewer or Session changed during Save As; the new Workspace is retained without adopting it}}
            dict set ::GX::ViewerGui::instances $window workspace_id [dict get $copy id]
            dict set ::GX::ViewerGui::instances $window workspace_stamp [list [dict get $copy generation] [dict get $copy revision] [dict get $copy sha256]]
            if {[dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerBindDocument $window [dict get $copy id];dict set ::GX::ViewerGui::instances $window saved_history_revision [dict get [scientificHistoryViewerStatus $window] revision]}
            dict set ::GX::ViewerGui::instances $window saved [viewerGuiDesignCapture $window]
            dict set ::GX::ViewerGui::instances $window saved_workspace_properties [dict get $instance workspace_properties]
            set receipt [nativeWorkspaceStatus [dict get $copy id]]
            set hooks [datasetPublicationV2DictDefault $instance workspace_hooks {}]
            if {[dict exists $hooks committed]} {uplevel #0 [list {*}[dict get $hooks committed] $window $receipt]}
            _viewerWorkspaceCppCommitted $window $receipt
        }
        rename {viewerGuiDesignWorkspaceRename $window [dict get $instance workspace_id] $value}
        open {
            set context [dict get $::GX::SessionWorkspace::adapters $window];set target [sessionWorkspaceGet $value]
            if {[dict get $target provider_id] ne [dict get $instance workspace_provider]} {error {Workspace belongs to another Viewer provider}}
            if {![sessionWorkspaceHostPrepare $context opening]} {return [dict create status cancelled]}
            _workspaceHostClose $context;uplevel #0 [list {*}[dict get $instance workspace_callbacks open] [dict create workspace_id $value]]
        }
        close {viewerGuiDesignWorkspaceClose $window}
        default {error {Unknown typed Viewer Workspace operation}}
    }
    return [dict create status accepted operation $command]
}
proc ::GX::viewerGuiDesignWorkspaceRename {window id name} {
    if {![viewerGuiDesignGuard $window]} {error {Viewer or Session lifetime changed}}
    set instance [dict get $::GX::ViewerGui::instances $window];set current [sessionWorkspaceGet $id]
    if {[dict get $instance workspace_id] ne $id || [dict get $instance workspace_stamp] ne [list [dict get $current generation] [dict get $current revision] [dict get $current sha256]]} {error {Workspace changed before Rename}}
    nativeWorkspaceRename $current [_workspaceName $name $id];set item [sessionWorkspaceGet $id]
    dict set ::GX::ViewerGui::instances $window workspace_stamp [list [dict get $item generation] [dict get $item revision] [dict get $item sha256]]
    sessionWorkspaceViewsChanged;return $item
}
proc ::GX::viewerGuiDesignWorkspaceSaveAs {window name} {
    # Primary Workspace menus and the finite C++ facade share one copy path.
    _viewerGuiWorkspaceSdkCommand $window [dict create command save_as value [dict create kind text value $name]]
    return [viewerGuiDesignCurrent $window]
}
proc ::GX::_viewerWorkspaceSaveWatchStart {window} {
    if {![dict exists $::GX::ViewerGui::instances $window workspace_save_watch]} {dict set ::GX::ViewerGui::instances $window workspace_save_watch [after 25 [list ::GX::_viewerWorkspaceSaveWatch $window [winfo id $window]]]}
}
proc ::GX::_viewerWorkspaceSaveWatch {window incarnation} {
    if {![dict exists $::GX::ViewerGui::instances $window] || ![winfo exists $window] || [winfo id $window] ne $incarnation} return
    dict unset ::GX::ViewerGui::instances $window workspace_save_watch
    if {![viewerGuiDesignGuard $window]} return
    set instance [dict get $::GX::ViewerGui::instances $window];set remaining {}
    set hooks [datasetPublicationV2DictDefault $instance workspace_hooks {}]
    foreach receipt [datasetPublicationV2DictDefault $instance workspace_pending_saves {}] {
        set status [nativeWorkspaceStatus [dict get $receipt id]]
        if {[dict get $status generation] ne [dict get $receipt generation]} {error {Async Save owner generation changed}}
        if {[dict get $status failed]} {
            [dict get $instance slots status] configure -text "Workspace persistence failed: [dict get $status error]"
            if {[dict exists $hooks error]} {uplevel #0 [list {*}[dict get $hooks error] $window $status]}
        } elseif {[dict get $status durable_revision]>=[dict get $receipt accepted_revision]} {
            dict set receipt durable_revision [dict get $status durable_revision];dict set receipt pending 0;dict set receipt dirty 0;dict set receipt status durable
            if {[dict exists $hooks committed]} {uplevel #0 [list {*}[dict get $hooks committed] $window $receipt]}
            if {![winfo exists $window] || [winfo id $window] ne $incarnation} {return}
            _viewerWorkspaceCppCommitted $window $receipt
        } else {lappend remaining $receipt}
    }
    if {[dict exists $::GX::ViewerGui::instances $window] && [winfo exists $window] && [winfo id $window] eq $incarnation} {
        dict set ::GX::ViewerGui::instances $window workspace_pending_saves $remaining
        if {$remaining ne {}} {_viewerWorkspaceSaveWatchStart $window}
    }
}
