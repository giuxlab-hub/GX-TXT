# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted Script Library draft transport. Canonical scripts remain Registry-owned;
# bulk local drafts use the existing Document Resource and typed Workspace owners.
proc ::GX::_viewerWorkspaceScriptLibraryEncode {drafts} {
    if {[catch {dict size $drafts}] || [string length [encoding convertto utf-8 $drafts]]>134217728} {error {Script Library draft transport exceeds128MiB}}
    set fields {}
    dict for {form entry} $drafts {
        if {![regexp {^[a-z][a-z0-9_]{0,47}$} $form] || [lsort [dict keys $entry]] ne {payload reference schema transport} || [dict get $entry schema] ne {gxtxt.script_library_transport.v1}} {error {Invalid Script Library Workspace transport}}
        set kind [dict get $entry transport];set body [dict get $entry payload];set reference [dict get $entry reference]
        if {$kind eq {inline}} {
            if {$reference ne {} || [string length [encoding convertto utf-8 $body]]>100663296} {error {Invalid inline Script Library draft}}
            _scriptLibraryHostDraftValidate $body
            set resource {null {}}
        } elseif {$kind eq {managed_resource}} {
            if {$body ne {} || [dict get $reference api_id] ne {INTERACTIVE_DOCUMENT_RESOURCE_API_v1} || ![dict exists $reference owner_generation] || ![regexp {^[a-f0-9]{64}$} [dict get $reference sha256]] || ![string is entier -strict [dict get $reference size_bytes]] || [dict get $reference size_bytes]<1 || [dict get $reference size_bytes]>100663296 || [dict get $reference metadata format] ne {gxtxt.script_library_ui_draft.v1} || [dict get $reference metadata encoding] ne {utf-8}} {error {Invalid managed Script Library draft}}
            set resource [nativeWorkspaceEncode {resource {codec ::GX::_viewerWorkspaceMarkdownAssetMetadataEncode}} $reference]
        } else {error {Unknown Script Library draft transport}}
        dict set fields $form [list object [dict create schema [list text [dict get $entry schema]] transport [list text $kind] payload [list text $body] reference $resource]]
    }
    return [list object $fields]
}
::GX::viewerWorkspaceCodecRegister domains script_library_drafts ::GX::_viewerWorkspaceScriptLibraryEncode
proc ::GX::_viewerGuiScriptLibraryWorkspaceCapture {window} {
    if {![info exists ::GX::ScriptLibraryHost::bindings]} return
    set drafts {};set instance [dict get $::GX::ViewerGui::instances $window]
    foreach key [dict keys $::GX::ScriptLibraryHost::bindings] {
        if {[lindex $key 0] ne $window} continue
        set form [lindex $key 1];set body [_viewerGuiScriptLibraryCapture $window $form]
        set body [_viewerGuiScriptLibraryRecoveryViewsCapture $window $form $body]
        set cache [datasetPublicationV2DictDefault $instance script_library_transport_cache {}]
        if {[dict exists $cache $form] && [dict get $cache $form body] eq $body && [dict get $cache $form session] eq [_viewerNativeClientSessionToken]} {
            set entry [dict get $cache $form entry]
        } elseif {[_viewerNativeClientSessionToken] eq {}} {
            # No Session permits local User drafts, never an implicit Session or
            # unowned resource. Saving a scientific Workspace still needs one.
            set entry [dict create schema gxtxt.script_library_transport.v1 transport inline payload $body reference {}]
        } else {
            set bytes [encoding convertto utf-8 $body]
            if {[string length $bytes]>100663296} {error {Serialized Script Library draft exceeds96MiB}}
            set owner [datasetPublicationV2DictDefault $instance script_library_resource_owner {}]
            if {$owner eq {}} {
                set context [_viewerGuiScriptLibraryGuard $window $form capture]
                set owner [interactiveDocumentCreate [dict get $context module_id] script_library_draft_assets gxtxt.script_library_draft_assets.v1 1 [dict create schema gxtxt.script_library_draft_assets.v1 purpose local_source_draft_transport]]
                dict set ::GX::ViewerGui::instances $window script_library_resource_owner $owner
                dict set instance script_library_resource_owner $owner
            }
            set reference [managedResourceWrite [dict get $owner id] [dict create format gxtxt.script_library_ui_draft.v1 encoding utf-8 scientific_authority 0 disposable 0] $bytes]
            set entry [dict create schema gxtxt.script_library_transport.v1 transport managed_resource payload {} reference $reference]
        }
        dict set drafts $form $entry
        dict set ::GX::ViewerGui::instances $window script_library_transport_cache $form [dict create body $body entry $entry session [_viewerNativeClientSessionToken]]
    }
    if {$drafts ne {}} {
        _viewerWorkspaceScriptLibraryEncode $drafts
        dict set ::GX::ViewerGui::instances $window domain_state script_library_drafts $drafts
    }
}
proc ::GX::_viewerGuiScriptLibraryWorkspaceRead {entry} {
    if {[dict get $entry transport] eq {inline}} {return [_scriptLibraryHostDraftValidate [dict get $entry payload]]}
    set reference [dict get $entry reference];set bytes {};set reader [interactiveDocumentResourceOpenReader $reference]
    try {
        while {1} {set chunk [interactiveDocumentResourceNext $reader];append bytes [dict get $chunk bytes];if {[dict get $chunk eof]} break}
    } finally {interactiveDocumentResourceCloseReader $reader}
    set body [encoding convertfrom utf-8 $bytes]
    if {[encoding convertto utf-8 $body] ne $bytes} {error {Script Library resource is not exact UTF-8}}
    return [_scriptLibraryHostDraftValidate $body]
}
proc ::GX::_viewerGuiScriptLibraryWorkspaceCheck {window domains} {
    if {![dict exists $domains script_library_drafts]} return
    set drafts [dict get $domains script_library_drafts];_viewerWorkspaceScriptLibraryEncode $drafts
    set maps [_viewerGuiClientRoleMapsValidate [dict get $::GX::ViewerGui::instances $window design]]
    dict for {form entry} $drafts {
        if {![dict exists $maps $form script_library_components]} {error {Saved Script Library draft names an undeclared controller}}
        _viewerGuiScriptLibraryWorkspaceRead $entry
    }
}
proc ::GX::_viewerGuiScriptLibraryWorkspaceRestore {window domains} {
    set drafts [datasetPublicationV2DictDefault $domains script_library_drafts {}]
    # Restoring an earlier empty state (including compensation) must remove
    # controllers introduced only by the failed/requested later state.
    foreach key [dict keys $::GX::ScriptLibraryHost::bindings] {
        if {[lindex $key 0] eq $window && ![dict exists $drafts [lindex $key 1]]} {
            set form [lindex $key 1];viewerGuiScriptLibraryDispose $window $form
            if {[dict exists $::GX::ViewerGui::instances $window script_library_transport_cache $form]} {dict unset ::GX::ViewerGui::instances $window script_library_transport_cache $form}
        }
    }
    dict for {form entry} $drafts {
        set body [_viewerGuiScriptLibraryWorkspaceRead $entry]
        _viewerGuiScriptLibraryRestore $window $form $body
        dict set ::GX::ViewerGui::instances $window script_library_transport_cache $form [dict create body $body entry $entry session [_viewerNativeClientSessionToken]]
    }
}
# Workspace presentation may be newer than the last semantic History step.
# Keep it only across initial History attachment, and only when both the saved
# timeline and the journal actually recovered describe the same source state.
proc ::GX::_viewerGuiScriptLibraryRecoveryCapture {window history {workspace {}}} {
    if {$history eq {}} {return {}}
    # Other managed Viewers must not pay for an extra full Workspace capture.
    # Only a maintained controller belonging to this actual window can have
    # Source presentation to recover; another window's bindings do not qualify.
    set bound 0
    if {[info exists ::GX::ScriptLibraryHost::bindings]} {
        foreach key [dict keys $::GX::ScriptLibraryHost::bindings] {
            if {[lindex $key 0] eq $window} {set bound 1;break}
        }
    }
    if {!$bound} {return {}}
    set current [viewerGuiDesignCapture $window]
    if {![dict exists $current domain_state script_library_drafts]} {return {}}
    if {$workspace eq {}} {set workspace $current}
    _viewerGuiScriptLibraryWorkspaceCheck $window [datasetPublicationV2DictDefault $workspace domain_state {}]
    scientificHistoryValidate [dict get $::GX::ViewerGui::instances $window module] $history
    set projection [_viewerGuiScriptLibraryHistoryProjection $current]
    if {$projection ne [_viewerGuiScriptLibraryHistoryProjection [scientificHistoryState $history]] || $projection ne [_viewerGuiScriptLibraryHistoryProjection $workspace]} {return {}}
    set tabs {};set design [dict get $::GX::ViewerGui::instances $window design]
    dict for {form roles} [_viewerGuiClientRoleMapsValidate $design] {
        if {![dict exists $roles script_library_components]} continue
        foreach role {registered_source parameter_definitions} {
            set id [dict get $roles script_library_components $role]
            while {$id ni {canvas footer menubar toolbar}} {
                set definition [viewerGuiDesignComponent $window $id]
                if {[dict get $definition type] eq {tab}} {
                    set parent [dict get $definition parent]
                    if {[dict exists $workspace values $parent]} {
                        set selected [dict get $workspace values $parent]
                        if {$selected ne {}} {
                            set page [viewerGuiDesignComponent $window $selected]
                            if {[dict get $page type] ne {tab} || [dict get $page parent] ne $parent || [dict get [viewerGuiDesignComponent $window $parent] type] ne {tabs}} {error {Saved Library presentation has an invalid declared notebook page}}
                            dict set tabs $parent $selected
                        }
                    }
                }
                set id [dict get $definition parent]
            }
        }
    }
    return [dict create identity [winfo id $window] session [_viewerNativeClientSessionToken] projection $projection drafts [dict get $workspace domain_state script_library_drafts] tabs $tabs]
}
proc ::GX::_viewerGuiScriptLibraryRecoveryRestore {window saved} {
    if {$saved eq {} || ![winfo exists $window] || [winfo id $window] ne [dict get $saved identity] || [_viewerNativeClientSessionToken] ne [dict get $saved session]} {return 0}
    set current [viewerGuiDesignCapture $window]
    set projection [dict get $saved projection]
    if {[_viewerGuiScriptLibraryHistoryProjection $current] ne $projection || [_viewerGuiScriptLibraryHistoryProjection [scientificHistoryViewerState $window]] ne $projection} {return 0}
    # Build from the recovered state, never from saved root/writer authority.
    # Only equal common buffers and previously saved clean cached files qualify.
    set candidates {}
    dict for {form entry} [dict get $saved drafts] {
        set wanted [_viewerGuiScriptLibraryWorkspaceRead $entry]
        set candidate [_viewerGuiScriptLibraryWorkspaceRead [dict get $current domain_state script_library_drafts $form]]
        if {[dict get $candidate parameter_text] ne [dict get $wanted parameter_text] || [dict get $candidate parameter_baseline] ne [dict get $wanted parameter_baseline]} {return 0}
        dict for {relative source} [dict get $wanted sources] {
            if {[dict exists $candidate sources $relative]} {
                foreach field {text baseline_text} {if {[dict get $source $field] ne [dict get $candidate sources $relative $field]} {return 0}}
            } else {
                if {[dict get $source text] ne [dict get $source baseline_text] || [scriptRegistryHashBytes [encoding convertto utf-8 [dict get $source text]]] ne [dict get $candidate roster $relative sha256]} {return 0}
                dict set candidate sources $relative $source
            }
            dict set candidate sources $relative view [dict get $source view]
        }
        dict set candidate active_file [dict get $wanted active_file]
        dict set candidate parameter_view [dict get $wanted parameter_view]
        dict set candidates $form [_scriptLibraryHostDraftValidate $candidate]
    }
    dict for {form candidate} $candidates {
        _viewerGuiScriptLibraryRestore $window $form $candidate
        set record [_scriptLibraryHostGet [list $window $form]]
        set token [dict get $record draft_token]
        dict for {relative source} [dict get $candidate sources] {
            set text [dict get $record sources $relative text]
            _viewerGuiScriptLibraryRecoveryViewQueue $window $form $token $relative $text [dict get $source view]
        }
        _viewerGuiScriptLibraryRecoveryViewQueue $window $form $token {} [dict get $record parameter_text] [dict get $candidate parameter_view]
    }
    set restoring [dict get $::GX::ViewerGui::instances $window restoring]
    dict set ::GX::ViewerGui::instances $window restoring 1
    try {
        dict for {id selected} [dict get $saved tabs] {
            set page [viewerGuiDesignComponent $window $selected]
            if {[dict get [viewerGuiDesignComponent $window $id] type] ne {tabs} || [dict get $page type] ne {tab} || [dict get $page parent] ne $id} {error {Library notebook presentation no longer matches its design}}
            set widgets [dict get $::GX::ViewerGui::instances $window widgets]
            if {[viewerGuiDesignComponentVisibleGet $window $selected]} {[dict get $widgets $id] select [dict get $widgets $selected]}
        }
    } finally {dict set ::GX::ViewerGui::instances $window restoring $restoring}
    return 1
}
proc ::GX::_viewerGuiScriptLibraryRecoveryViewQueue {window form token relative text view} {
    set pending [dict create window_id [winfo id $window] widget_id [winfo id $text] token $token relative $relative view $view session [_viewerNativeClientSessionToken] source_sha256 [scriptRegistryHashBytes [encoding convertto utf-8 [sourceSurfaceGet $text]]]]
    dict set ::GX::ViewerGui::instances $window script_library_recovery_views $text $pending
    # Hidden cached files acquire their usable geometry only when really mapped.
    # This callback is inert after adoption, another restore, edit or destruction.
    set callback [list ::GX::_viewerGuiScriptLibraryRecoveryViewSchedule $window $form $text]
    if {[lsearch -exact [split [bind $text <Map>] \n] $callback]<0} {bind $text <Map> +$callback}
    _viewerGuiScriptLibraryRecoveryViewSchedule $window $form $text
}
proc ::GX::_viewerGuiScriptLibraryRecoveryViewSchedule {window form text} {
    after idle [list ::GX::_viewerGuiScriptLibraryRecoveryViewApply $window $form $text]
}
proc ::GX::_viewerGuiScriptLibraryRecoveryViewsCapture {window form body} {
    # An unopened cached Text has no usable viewport yet. Preserve only its
    # still-valid pending view in the existing Workspace body until first Map;
    # do not serialize a transient widget identity, token or callback.
    set pending [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] script_library_recovery_views {}]
    if {$pending eq {}} {return $body}
    set record [_scriptLibraryHostGet [list $window $form]]
    dict for {text saved} $pending {
        if {[dict get $saved window_id] ne [winfo id $window] || [dict get $saved session] ne [_viewerNativeClientSessionToken] || [dict get $saved token] ne [dict get $record draft_token] || ![winfo exists $text] || [dict get $saved widget_id] ne [winfo id $text]} continue
        set relative [dict get $saved relative]
        if {$relative eq {}} {set value [dict get $body parameter_text]} elseif {[dict exists $body sources $relative]} {set value [dict get $body sources $relative text]} else continue
        if {[scriptRegistryHashBytes [encoding convertto utf-8 $value]] ne [dict get $saved source_sha256]} continue
        if {$relative eq {}} {dict set body parameter_view [dict get $saved view]} else {dict set body sources $relative view [dict get $saved view]}
    }
    return $body
}
proc ::GX::_viewerGuiScriptLibraryRecoveryViewApply {window form text} {
    if {![winfo exists $window] || ![dict exists $::GX::ViewerGui::instances $window script_library_recovery_views $text]} return
    set pending [dict get $::GX::ViewerGui::instances $window script_library_recovery_views $text]
    if {![winfo exists $text] || [winfo id $window] ne [dict get $pending window_id] || [winfo id $text] ne [dict get $pending widget_id] || [_viewerNativeClientSessionToken] ne [dict get $pending session]} {dict unset ::GX::ViewerGui::instances $window script_library_recovery_views $text;return}
    if {[catch {set context [_viewerGuiScriptLibraryGuard $window $form capture];set record [_scriptLibraryHostGet [list $window $form]]}] || [dict get $record draft_token] ne [dict get $pending token] || [scriptRegistryHashBytes [encoding convertto utf-8 [sourceSurfaceGet $text]]] ne [dict get $pending source_sha256]} {dict unset ::GX::ViewerGui::instances $window script_library_recovery_views $text;return}
    if {![winfo ismapped $text] || [winfo width $text]<=1 || [winfo height $text]<=1} return
    dict unset ::GX::ViewerGui::instances $window script_library_recovery_views $text
    _scriptLibraryHostRestoreTextView $text [dict get $pending view]
}
proc ::GX::_viewerScriptLibraryResourceReferences {document} {
    set result {}
    dict for {window instance} $::GX::ViewerGui::instances {
        if {![viewerGuiDesignGuard $window]} continue
        set drafts [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $instance domain_state {}] script_library_drafts {}]
        dict for {form entry} $drafts {if {[dict get $entry transport] eq {managed_resource} && [dict get $entry reference document_id] eq $document} {lappend result [dict get $entry reference]}}
    }
    return $result
}

proc ::GX::_viewerGuiScriptLibraryCanClose {window} {
    foreach key [dict keys $::GX::ScriptLibraryHost::bindings] {
        if {[lindex $key 0] ne $window} continue
        set form [lindex $key 1];set record [_scriptLibraryHostGet $key]
        set context [dict get $record context]
        if {![_scriptLibraryHostDirty $key $context]} continue
        if {[catch {_viewerGuiScriptLibraryGuard $window $form review}]} {
            set answer [tk_messageBox -parent $window -title {Unavailable Script Library owner} -type yesnocancel -default cancel -icon question -message {This Viewer no longer has its admitted module or matching Session. No discards this local draft only. Cancel retains it. Save requires reopening the matching owner first.}]
            if {$answer ne {no}} {return 0}
            continue
        }
        set r [dict get $::GX::ViewerDevelopment::windows $window]
        set previous [datasetPublicationV2DictDefault $r native_client_event_scope {}]
        set scope [dict create incarnation [winfo id $window] lifetime [dict get $r lifetime] module [dict get $r module] generation [dict get $r generation] session_token [_viewerNativeClientSessionToken] action __host_close__ effect mutating user_action 1]
        dict set ::GX::ViewerDevelopment::windows $window native_client_event_scope $scope
        dict set ::GX::ScriptLibraryHost::bindings $key busy 1
        try {
            if {![_scriptLibraryHostReview $window $form $key $context]} {return 0}
        } finally {
            if {[dict exists $::GX::ViewerDevelopment::windows $window] && [datasetPublicationV2DictDefault [dict get $::GX::ViewerDevelopment::windows $window] native_client_event_scope {}] eq $scope} {dict set ::GX::ViewerDevelopment::windows $window native_client_event_scope $previous}
            if {[dict exists $::GX::ScriptLibraryHost::bindings $key]} {dict set ::GX::ScriptLibraryHost::bindings $key busy [dict get $record busy]}
        }
    }
    return 1
}
