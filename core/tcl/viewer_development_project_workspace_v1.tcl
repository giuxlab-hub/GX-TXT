# SPDX-License-Identifier: GPL-3.0-or-later
# Local Development drafts use the existing native Workspace store/codecs.
# A project draft is neither a Session nor a canonical scientific Dataset.
proc ::GX::_viewerDevelopmentProjectDraftPath {{create 0}} {
    set parent [file join [file dirname [configurationPath]] development_project_drafts]
    foreach path [list $parent [file join $parent workspaces.sqlite]] {
        if {![catch {file lstat $path st}] && $st(type) eq {link}} {error {Project draft storage must not be a symbolic link}}
    }
    if {$create && ![file exists $parent]} {file mkdir $parent;file attributes $parent -permissions 0700}
    if {[file exists $parent] && ![file isdirectory $parent]} {error {Project draft storage is not a directory}}
    return [file join $parent workspaces.sqlite]
}
proc ::GX::_viewerDevelopmentProjectDraftCheck {window context} {
    if {$::GX::currentSession ne {} || ![dict exists $::GX::ViewerDevelopment::windows $window]} {error {Local project draft belongs to its original non-Session Development window}}
    set record [dict get $::GX::ViewerDevelopment::windows $window]
    if {[dict exists $record runtime_module_root] || [dict get $record lifetime] ne [dict get $context lifetime]
        || [dict get $record project] ne [dict get $context project]
        || [dict get $record validated_snapshot] ne [dict get $context snapshot]
        || [_viewerDevelopmentSnapshot [dict get $record project]] ne [dict get $context snapshot]} {error {Project source or Development lifetime changed; draft is retained, reopen the matching project}}
    return $record
}
proc ::GX::_viewerDevelopmentProjectDraftStore {context {create 0}} {
    set path [_viewerDevelopmentProjectDraftPath $create]
    if {!$create && ![file exists $path]} {return {}}
    if {[file exists $path]} {
        file lstat $path st
        if {$st(type) ne {file} || $st(nlink)!=1} {error {Project draft database must be a regular unlinked file}}
    }
    _nativeWorkspaceLibraryRequire
    set handle [workspaceNative open $path]
    try {_nativeWorkspaceRegisterOn $handle [dict get $context provider] [dict get $context descriptor]} on error {message options} {workspaceNative close $handle;return -options $options $message}
    return $handle
}
proc ::GX::_viewerDevelopmentProjectDraftOrigin {context} {
    return [dict create schema gxtxt.development_project_draft.v1 project [dict get $context project] module [dict get $context module] provider [dict get $context provider]]
}
proc ::GX::_viewerDevelopmentProjectDraftItem {handle context} {
    set rows [workspaceNative query $handle [dict get $context provider] [dict get $context module] {} 0 2]
    if {[llength $rows]>1} {error {Project draft identity is ambiguous; saved drafts are retained}}
    if {![llength $rows]} {return {}}
    set item [workspaceNative get $handle [dict get [lindex $rows 0] id]]
    set origin [nativeWorkspaceDecode [dict get $item provenance]]
    set expectedOrigin [_viewerDevelopmentProjectDraftOrigin $context]
    if {[lsort [dict keys $origin]] ne [lsort [dict keys $expectedOrigin]]} {error {Saved draft has an unknown project identity}}
    dict for {key value} $expectedOrigin {if {[dict get $origin $key] ne $value} {error {Saved draft belongs to another project; no state was adopted}}}
    set payload [viewerGuiWorkspaceDecode [dict get $item state]]
    viewerGuiDesignStateValidate $payload
    if {![dict exists $payload domain_state restricted_cpp]} {error {Saved project draft lacks its native source identity}}
    set cpp [dict get $payload domain_state restricted_cpp]
    if {[dict get $cpp snapshot] ne [dict get $context snapshot] || [dict get $cpp callback_contract] ne [dict get $context callback_contract]} {error {Saved project draft source/design differs; retain it and reopen its matching project}}
    viewerDevelopmentStateJson [dict get $cpp state]
    dict set item payload $payload
    return $item
}
proc ::GX::_viewerDevelopmentProjectDraftPrepare {window context} {
    set record [dict get $::GX::ViewerDevelopment::windows $window]
    set provider [dict get $context workspace_provider]
    set result [dict create project [dict get $record project] module [dict get $record module] lifetime [dict get $record lifetime] snapshot [dict get $record validated_snapshot] callback_contract [dict get $record workspace_callback_contract] provider $provider descriptor [dict get $::GX::NativeWorkspace::providers $provider] item {}]
    _viewerDevelopmentProjectDraftCheck $window $result
    set handle [_viewerDevelopmentProjectDraftStore $result]
    if {$handle ne {}} {
        try {dict set result item [_viewerDevelopmentProjectDraftItem $handle $result]} finally {workspaceNative close $handle}
    }
    return $result
}
proc ::GX::_viewerDevelopmentProjectDraftAttach {window context} {
    _viewerDevelopmentProjectDraftCheck $window $context
    set item [dict get $context item]
    dict set ::GX::ViewerGui::instances $window project_draft $context
    if {$item ne {}} {viewerGuiDesignRestore $window [dict get $item payload]}
    dict set ::GX::ViewerGui::instances $window saved [viewerGuiDesignCapture $window]
    set menu $window.menus.workspace
    if {![winfo exists $menu]} {
        menu $menu -tearoff 0
        $window.menus add cascade -label Workspace -menu $menu
    }
    $menu add command -label {Save project draft} -command [list ::GX::_viewerDevelopmentProjectDraftSaveUi $window]
    wm protocol $window WM_DELETE_WINDOW [list ::GX::_viewerDevelopmentProjectDraftClose $window]
    [dict get $::GX::ViewerGui::instances $window slots status] configure -text {Local project draft. Workspace Save retains it without creating a Dataset.}
}
proc ::GX::_viewerDevelopmentProjectDraftSave {window} {
    set context [dict get $::GX::ViewerGui::instances $window project_draft]
    set record [_viewerDevelopmentProjectDraftCheck $window $context]
    if {[dict get $record busy] ne {} || [dict get $record status] eq {RUNNING}} {error {Native action is still running; wait for Ready, then save the project draft}}
    if {[dict exists $::GX::ViewerGui::instances $window workspace_restore_failure]} {error {Recover or reopen the retained project draft before saving}}
    set payload [viewerGuiDesignCapture $window]
    dict set payload design [dict get $::GX::ViewerGui::instances $window design]
    set typed [viewerGuiWorkspaceEncode $payload]
    _nativeWorkspaceWriteAllowed
    set handle [_viewerDevelopmentProjectDraftStore $context 1]
    try {
        _nativeWorkspaceScientificOwnersAdmit $handle $typed
        set current [_viewerDevelopmentProjectDraftItem $handle $context]
        set expected [dict get $context item]
        if {$expected eq {}} {
            if {$current ne {}} {error {Project draft changed in another window; unsaved draft retained}}
            set origin [nativeWorkspaceEncode {map text} [_viewerDevelopmentProjectDraftOrigin $context]]
            set receipt [workspaceNative create $handle [dict get $context provider] "Project draft — [dict get $context provider]" $typed {object {}} $origin]
        } else {
            foreach key {id generation revision} {if {$current eq {} || [dict get $expected $key] ne [dict get $current $key]} {error {Project draft changed in another window; unsaved draft retained}}}
            set receipt [workspaceNative save $handle [dict get $current id] [dict get $current generation] [dict get $current revision] $typed {object {}}]
        }
        workspaceNative flush $handle [dict get $receipt id]
        set item [_viewerDevelopmentProjectDraftItem $handle $context]
    } finally {workspaceNative close $handle}
    dict set context item $item
    dict set ::GX::ViewerGui::instances $window project_draft $context
    dict set ::GX::ViewerGui::instances $window saved [dict remove $payload design]
    [dict get $::GX::ViewerGui::instances $window slots status] configure -text {Project draft saved. No canonical Dataset was created.}
    return [dict create status durable scope development_project workspace_id [dict get $item id] generation [dict get $item generation] revision [dict get $item revision]]
}
proc ::GX::_viewerDevelopmentProjectDraftSaveUi {window} {
    if {[catch {_viewerDevelopmentProjectDraftSave $window} result]} {tk_messageBox -parent $window -icon error -message $result;return 0}
    return 1
}
proc ::GX::_viewerDevelopmentProjectDraftClose {window} {
    if {![_viewerGuiLibraryCanClose $window]} {return}
    if {[catch {set dirty [viewerGuiDesignDirty $window]} message]} {tk_messageBox -parent $window -icon error -message $message;return}
    if {$dirty} {
        set choice [tk_messageBox -parent $window -type yesnocancel -icon question -title {Project draft} -message {Save the local project draft before closing?}]
        if {$choice eq {cancel}} {return}
        if {$choice eq {yes} && ![_viewerDevelopmentProjectDraftSaveUi $window]} {return}
    }
    viewerGuiDesignWorkspaceDiscard $window
}
