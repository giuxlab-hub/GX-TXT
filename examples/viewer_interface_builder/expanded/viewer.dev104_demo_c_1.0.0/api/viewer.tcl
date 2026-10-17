# Generated interface connector. Edit handlers.tcl for science.
# SPDX-License-Identifier: GPL-3.0-or-later
if {![llength [info commands ::GX::viewerGuiDesignCompose]]} {error {This Viewer requires the dev104 CORE Viewer design capability.}}
namespace eval ::GX::Generated_viewer_dev104_demo_c {variable root [file dirname [file dirname [info script]]]}
namespace eval ::GX::Generated_viewer_dev104_demo_c::Handlers {}
if {![info exists ::GX::Generated_viewer_dev104_demo_c::handlersLoaded]} {
    source [file join [set ::GX::Generated_viewer_dev104_demo_c::root] generated handler_defaults.tcl]
    source [file join [set ::GX::Generated_viewer_dev104_demo_c::root] handlers.tcl]
    set ::GX::Generated_viewer_dev104_demo_c::handlersLoaded 1
}
proc ::GX::Generated_viewer_dev104_demo_c::design {} {return [::GX::viewerGuiDesignRead [file join [set ::GX::Generated_viewer_dev104_demo_c::root] gui design.tcldict]]}
proc ::GX::Generated_viewer_dev104_demo_c::handlers {} {
    set result {}
    dict for {id contract} [dict get [design] handlers] {dict set result $id [dict create command [list ::GX::Generated_viewer_dev104_demo_c::Handlers::$id] enabled [list ::GX::Generated_viewer_dev104_demo_c::Handlers::enabled]]}
    return $result
}
proc ::GX::Generated_viewer_dev104_demo_c::open {{context {}}} {
    set window .viewer_dev104_demo_c
    if {[winfo exists $window]} {
        set id [::GX::datasetPublicationV2DictDefault $context workspace_id {}]
        if {$id eq {}} {raise $window;return $window}
        if {[dict exists $::GX::SessionWorkspace::adapters $window] && ![::GX::sessionWorkspaceHostPrepare [dict get $::GX::SessionWorkspace::adapters $window] opening]} {return $window}
        destroy $window
    }
    ::GX::viewerGuiDesignCompose [design] $window viewer.dev104_demo_c dev104_demo_c runtime [handlers] $context
    return $window
}
proc ::GX::Generated_viewer_dev104_demo_c::workspaceOpen {context} {return [::GX::viewerGuiDesignWorkspaceOpen viewer.dev104_demo_c dev104_demo_c [design] runtime [handlers] $context]}
proc ::GX::Generated_viewer_dev104_demo_c::dispatch {operation scene} {return [open [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
::GX::viewerBackendRegister viewer_dev104_demo_c_gui ::GX::Generated_viewer_dev104_demo_c::dispatch
