# GX-TXT Session Action Provider API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# Descriptor-driven, lazily activated Session actions supplied by modules.

namespace eval ::GX { variable sessionActionProviderApiVersion 1 }

proc ::GX::sessionActionProviderList {} {
    variable moduleOrder
    set sortable {}
    foreach moduleId $moduleOrder {
        set descriptor [moduleField $moduleId descriptor ""]
        if {$descriptor eq "" || ![file isfile $descriptor]} continue
        set d [parseIni $descriptor]
        set ids [splitList [descriptorValue $d session_actions ids ""]]
        if {![llength $ids]} continue
        set api [string trim [descriptorValue $d session_actions api_version ""]]
        if {$api ne "1"} { error "$moduleId declares unsupported Session Action Provider API version '$api'." }
        set publicIds [splitList [descriptorValue $d public_apis ids ""]]
        foreach id $ids {
            if {![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $id]} { error "$moduleId declares invalid Session action ID '$id'." }
            set sec "session_action.$id"
            set name [string trim [descriptorValue $d $sec name $id]]
            set publicApi [string trim [descriptorValue $d $sec public_api ""]]
            set command [string trim [descriptorValue $d $sec command ""]]
            set requires [string tolower [string trim [descriptorValue $d $sec requires_session 1]]]
            set order [descriptorValue $d $sec order 1000]
            if {$publicApi eq "" || $publicApi ni $publicIds} { error "$moduleId/$id declares an invalid public_api '$publicApi'." }
            if {$command eq "" || ![regexp {^::[A-Za-z_][A-Za-z0-9_:]*$} $command]} { error "$moduleId/$id declares invalid Session action command '$command'." }
            if {$requires ni {0 1 false true no yes off on}} { error "$moduleId/$id has invalid requires_session '$requires'." }
            if {![string is integer -strict $order]} { set order 1000 }
            set req [expr {$requires in {1 true yes on} ? 1 : 0}]
            lappend sortable [list $order $moduleId $id [dict create module_id $moduleId action_id $id name $name public_api $publicApi command $command requires_session $req order $order]]
        }
    }
    set out {}
    foreach row [lsort -integer -index 0 $sortable] { lappend out [lindex $row 3] }
    return $out
}

proc ::GX::sessionActionInvoke {moduleId actionId} {
    variable currentSession
    set found ""
    foreach action [sessionActionProviderList] {
        if {[dict get $action module_id] eq $moduleId && [dict get $action action_id] eq $actionId} { set found $action; break }
    }
    if {$found eq ""} { error "Unknown Session action '$moduleId/$actionId'." }
    if {[dict get $found requires_session] && ($currentSession eq "" || ![file isdirectory $currentSession])} { error "This Session action requires an open Session." }
    set api [dict get $found public_api]
    modulePublicApiActivate $moduleId $api
    set command [dict get $found command]
    if {![llength [info commands $command]]} { error "Session action '$moduleId/$actionId' activated '$api' but command '$command' is unavailable." }
    return [uplevel #0 [list $command]]
}

proc ::GX::sessionActionGuiInvoke {moduleId actionId} {
    if {[catch {sessionActionInvoke $moduleId $actionId} err]} { tk_messageBox -icon error -title "Session action failed" -message $err }
}

proc ::GX::sessionActionGuiRefresh {} {
    set w .top.sessionbar.tools
    if {![winfo exists .top.sessionbar]} return
    if {[winfo exists $w]} { destroy $w }
    set actions [sessionActionProviderList]
    if {![llength $actions]} return
    ttk::menubutton $w -text "Session Tools" -menu $w.menu
    menu $w.menu -tearoff 0
    foreach action $actions {
        $w.menu add command -label [dict get $action name] -command [list ::GX::sessionActionGuiInvoke [dict get $action module_id] [dict get $action action_id]]
    }
    pack $w -side left -padx 3
}

proc ::GX::launchGui_before_projects_gui_v1 {} {
    ::GX::launchGui_before_session_actions
    sessionActionGuiRefresh
}

# Workspace actions reuse descriptor discovery, public API activation and trusted
# module dispatch from Session actions. Their additional target is canonical ID.
proc ::GX::sessionWorkspaceActions {id} {
    set workspace [sessionWorkspaceGet $id];set module [dict get $workspace module_id]
    set descriptor [parseIni [moduleField $module descriptor]];set out {}
    set ids [splitList [descriptorValue $descriptor workspace_actions ids {}]]
    if {[llength $ids] && [descriptorValue $descriptor workspace_actions api_version {}] ne "1"} {error {Unsupported Workspace action API version}}
    foreach action $ids {
        if {![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $action]} {error {Invalid Workspace action ID}}
        set section workspace_action.$action
        set provider [descriptorValue $descriptor $section provider {}]
        if {$provider ne [dict get $workspace provider_id]} continue
        set api [descriptorValue $descriptor $section public_api {}];set command [descriptorValue $descriptor $section command {}]
        if {$api ni [modulePublicApiIds $module]||![regexp {^::[A-Za-z_][A-Za-z0-9_:]*$} $command]} {error {Invalid Workspace action descriptor}}
        lappend out [dict create action_id $action module_id $module provider_id $provider workspace_id $id public_api $api command $command name [descriptorValue $descriptor $section name $action]]
    }
    return $out
}
proc ::GX::sessionWorkspaceActionInvoke {id actionId} {
    foreach action [sessionWorkspaceActions $id] {
        if {[dict get $action action_id] ne $actionId} continue
        set module [dict get $action module_id];modulePublicApiActivate $module [dict get $action public_api]
        set capability [dict get [_datasetPrivateModuleContext $module] capability]
        set context [parameterContext $capability $id]
        return [_datasetPrivateWithModule $module [list [dict get $action command] $id $context]]
    }
    error "Unknown Workspace action '$actionId'"
}
proc ::GX::sessionWorkspaceActionMenu {frame menu} {
    $menu delete 0 end;set selected [$frame.tree selection]
    if {[llength $selected]!=1} {$menu add command -label {Select a Workspace} -state disabled;return}
    foreach action [sessionWorkspaceActions [lindex $selected 0]] {$menu add command -label [dict get $action name] -command [list ::GX::sessionWorkspaceActionGuiInvoke [lindex $selected 0] [dict get $action action_id]]}
}
proc ::GX::sessionWorkspaceActionGuiInvoke {id action} {if {[catch {sessionWorkspaceActionInvoke $id $action} message]} {tk_messageBox -icon error -message $message}}
