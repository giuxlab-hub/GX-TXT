# SPDX-License-Identifier: GPL-3.0-or-later
# Weak lifecycle transport for existing separately authored desktop processes.
# Saved models, revisions, resources and persistence remain the native service's.
namespace eval ::GX::WorkspaceExternal {variable clients {};variable pending {};variable serial 0;variable replies}
proc ::GX::workspaceExternalHostRegister {module provider channel} {
    dict set ::GX::WorkspaceExternal::clients $module [dict create module $module provider $provider channel $channel token [interactiveDocumentSessionToken] incarnation [incr ::GX::WorkspaceExternal::serial]]
}
proc ::GX::workspaceExternalHostCheck {module channel} {
    if {![dict exists $::GX::WorkspaceExternal::clients $module]} {error {Workspace desktop has no active host context}}
    set context [dict get $::GX::WorkspaceExternal::clients $module]
    if {[dict get $context channel] ne $channel || [dict get $context token] ne [interactiveDocumentSessionToken]} {error {Workspace desktop belongs to another Session lifetime}}
}
proc ::GX::workspaceExternalHostClosed {channel} {
    dict for {module context} $::GX::WorkspaceExternal::clients {
        if {[dict get $context channel] eq $channel} {dict unset ::GX::WorkspaceExternal::clients $module}
    }
    dict for {request context} $::GX::WorkspaceExternal::pending {
        if {[dict get $context channel] eq $channel} {set ::GX::WorkspaceExternal::replies($request) [list ERR {Workspace desktop connection closed}]}
    }
}
proc ::GX::workspaceExternalHostReply {channel line} {
    set fields [split $line \t]
    if {[lindex $fields 0] ne {WORKSPACE_RESULT}} {return 0}
    if {[llength $fields]!=4} {error {Malformed Workspace desktop lifecycle reply}}
    lassign $fields marker request status encoded
    if {![dict exists $::GX::WorkspaceExternal::pending $request]} {return 1}
    set context [dict get $::GX::WorkspaceExternal::pending $request]
    if {[dict get $context channel] ne $channel || [dict get $context token] ne [interactiveDocumentSessionToken]} {error {Foreign or stale Workspace desktop reply}}
    set ::GX::WorkspaceExternal::replies($request) [list $status [encoding convertfrom utf-8 [binary decode base64 -strict $encoded]]]
    return 1
}
proc ::GX::workspaceExternalHostRequest {context action args} {
    set module [dict get $context module]
    if {[dict get $context token] ne [interactiveDocumentSessionToken] || ![dict exists $::GX::WorkspaceExternal::clients $module] || [dict get $::GX::WorkspaceExternal::clients $module] ne $context} {error {Workspace desktop belongs to a stale Session or process}}
    set request external-[incr ::GX::WorkspaceExternal::serial]
    set channel [dict get $context channel]
    dict set ::GX::WorkspaceExternal::pending $request $context
    set fields [list CONTROL WORKSPACE $request $action]
    foreach argument $args {lappend fields [binary encode base64 -maxlen 0 [encoding convertto utf-8 $argument]]}
    set timer {}
    try {
        puts $channel [join $fields \t];flush $channel
        set timer [after 30000 [list set ::GX::WorkspaceExternal::replies($request) [list ERR {Workspace desktop is busy or did not answer; finish its current action and retry}]]]
        vwait ::GX::WorkspaceExternal::replies($request)
        lassign $::GX::WorkspaceExternal::replies($request) status result
        if {$status ne {OK}} {error $result}
        return $result
    } finally {
        if {$timer ne {}} {after cancel $timer}
        unset -nocomplain ::GX::WorkspaceExternal::replies($request)
        dict unset ::GX::WorkspaceExternal::pending $request
    }
}
proc ::GX::workspaceExternalHostReview {action} {
    set reviewed {}
    dict for {module context} $::GX::WorkspaceExternal::clients {
        if {[dict get $context token] ne [interactiveDocumentSessionToken]} {error {Close the stale Workspace desktop before changing Session}}
        if {[workspaceExternalHostRequest $context REVIEW $action] ne {accepted}} {return [list 0 {}]}
        lappend reviewed $context
    }
    return [list 1 $reviewed]
}
proc ::GX::workspaceExternalHostClose {reviewed} {
    foreach context $reviewed {workspaceExternalHostRequest $context CLOSE}
}
proc ::GX::workspaceExternalHostOpen {module id} {
    return [workspaceExternalHostRequest [dict get $::GX::WorkspaceExternal::clients $module] OPEN $id]
}
proc ::GX::workspaceExternalMetadataAdvanced {before after} {
    dict for {module context} $::GX::WorkspaceExternal::clients {
        if {[dict get $context token] ne [interactiveDocumentSessionToken]} continue
        set fields [list CONTROL WORKSPACE notice META]
        foreach value [list [dict get $before id] [dict get $before generation] [dict get $before revision] [dict get $after revision] [dict get $after name]] {lappend fields [binary encode base64 -maxlen 0 [encoding convertto utf-8 $value]]}
        puts [dict get $context channel] [join $fields \t];flush [dict get $context channel]
    }
}
