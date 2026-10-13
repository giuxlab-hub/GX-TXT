# SPDX-License-Identifier: GPL-3.0-or-later
# Reusable menu adapter; Workspace identity/resources remain Session Workspace's.
namespace eval ::GX::SessionWorkspace {variable titles {}}
proc ::GX::sessionWorkspaceViewerTitle {window base current {draft {}}} {
    if {![winfo exists $window]} {error {Workspace Viewer window is unavailable}}
    dict set ::GX::SessionWorkspace::titles $window [dict create base $base current $current draft $draft token [interactiveDocumentSessionToken]]
    bind $window <Destroy> +[list ::GX::_workspaceViewerTitleDestroyed $window %W]
    sessionWorkspaceViewerTitlesRefresh
}
proc ::GX::_workspaceViewerTitleDestroyed {window destroyed} {
    if {$window eq $destroyed && [dict exists $::GX::SessionWorkspace::titles $window]} {dict unset ::GX::SessionWorkspace::titles $window}
}
proc ::GX::sessionWorkspaceViewerTitlesRefresh {} {
    dict for {window adapter} $::GX::SessionWorkspace::titles {
        if {![winfo exists $window]} {dict unset ::GX::SessionWorkspace::titles $window;continue}
        set name {None}
        if {![catch {interactiveDocumentSessionToken} token] && $token eq [dict get $adapter token]} {
            if {![catch {uplevel #0 [dict get $adapter current]} id]} {
                if {$id ne {} && ![catch {sessionWorkspaceGet $id} workspace]} {
                    set name [dict get $workspace name]
                } elseif {$id eq {}} {
                    set name {New (unsaved)}
                    if {[dict get $adapter draft] ne {} && ![catch {uplevel #0 [dict get $adapter draft]} draft] && $draft ne {}} {set name "$draft (unsaved)"}
                }
            }
        }
        wm title $window "[dict get $adapter base] — Workspace: $name"
    }
}
proc ::GX::sessionWorkspaceViewerMenu {menu provider callbacks parent} {
    foreach {label action} {{New workspace…} new {Open workspace…} open Save save {Save as / Duplicate…} duplicate Rename… rename {Session Workspaces…} manager Close close Delete… delete} {
        $menu add command -label $label -command [list ::GX::sessionWorkspaceViewerAction $provider $callbacks $parent $action]
    }
}
proc ::GX::sessionWorkspaceViewerAction {provider callbacks parent action} {
    # A cancelled action returns normally from the caught script (code 2).
    # Only actual Tcl errors should open an error dialog.
    if {[catch {
        switch $action {
            open - manager {sessionWorkspaceDialog $parent}
            save {uplevel #0 [dict get $callbacks save]}
            close {uplevel #0 [dict get $callbacks close]}
            new - duplicate - rename {
                if {$action eq "new"} {set name "New [dict get [_workspaceProvider $provider] type]"} else {
                    uplevel #0 [dict get $callbacks save]
                    set id [uplevel #0 [dict get $callbacks current]]
                    set name [dict get [sessionWorkspaceGet $id] name]
                    if {$action eq "duplicate"} {append name { copy}}
                }
                uiFieldFormCreate $parent.workspaceName "[string totitle $action] Workspace" {name {type string required 1 label Name}} [dict create name $name] [list ::GX::sessionWorkspaceViewerNamed $provider $callbacks $parent $action] $parent
            }
            delete {
                set id [uplevel #0 [dict get $callbacks current]]
                set workspace [sessionWorkspaceGet $id]
                if {[tk_messageBox -parent $parent -type okcancel -default cancel -icon warning -message "Delete Workspace '[dict get $workspace name]'? Its source and published Datasets are preserved."] ne "ok"} return
                uplevel #0 [dict get $callbacks close]
                sessionWorkspaceDelete $id
            }
        }
    } message] == 1} {tk_messageBox -parent [expr {[winfo exists $parent] ? $parent : "."}] -icon error -message $message}
}
proc ::GX::sessionWorkspaceViewerNamed {provider callbacks parent action values} {
    set name [dict get $values name]
    if {$action eq "new"} {
        _workspaceName $name
        uplevel #0 [list {*}[dict get $callbacks open] [dict create workspace_id new workspace_name $name]]
    } else {
        set id [uplevel #0 [dict get $callbacks current]]
        if {$action eq "rename"} {sessionWorkspaceRename $id $name} else {
            _workspaceName $name
            set package [sessionWorkspaceExport $id]
            set duplicate [sessionWorkspaceImport $package $name]
            uplevel #0 [list {*}[dict get $callbacks open] [dict create workspace_id [dict get $duplicate workspace_id]]]
        }
    }
    if {[winfo exists $parent.workspaceName]} {destroy $parent.workspaceName}
}
