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
