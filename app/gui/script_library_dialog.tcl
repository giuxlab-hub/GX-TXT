# SPDX-License-Identifier: GPL-3.0-or-later
# Compatibility entrypoint names, one genuine compiled production Viewer.
proc ::GX::scriptLibraryDialog {{reference {}}} {
    if {[catch {scriptLibraryOpen $reference} window]} {
        tk_messageBox -parent . -icon warning -title {Script Library unavailable} -message $window
        return {}
    }
    return $window
}
proc ::GX::scriptLibraryRefresh {} {
    if {![info exists ::GX::ScriptLibraryHost::bindings]} return
    set windows {}
    dict for {key binding} $::GX::ScriptLibraryHost::bindings {
        lassign $key window form
        if {$window in $windows || ![winfo exists $window] || [catch {_viewerGuiScriptLibraryGuard $window $form snapshot}]} continue
        lappend windows $window
        if {[dict get $::GX::ViewerDevelopment::windows $window status] eq {COMPLETED} && [dict get $::GX::ViewerDevelopment::windows $window busy] eq {}} {viewerGuiDesignAction $window refresh}
    }
}
proc ::GX::scriptLibraryClose {} {
    set pending $::GX::ScriptLibraryLaunch::pending
    if {$pending ne {} && [winfo exists [lindex $pending 0]]} {return [viewerGuiDesignAction [lindex $pending 0] close]}
}
