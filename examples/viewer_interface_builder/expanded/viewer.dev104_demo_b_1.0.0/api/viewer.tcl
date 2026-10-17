# Generated interface connector. Edit handlers.tcl for science.
# SPDX-License-Identifier: GPL-3.0-or-later
if {![llength [info commands ::GX::viewerGuiDesignCompose]]} {error {This Viewer requires the dev104 CORE Viewer design capability.}}
namespace eval ::GX::Generated_viewer_dev104_demo_b {variable root [file dirname [file dirname [info script]]]}
namespace eval ::GX::Generated_viewer_dev104_demo_b::Handlers {}
if {![info exists ::GX::Generated_viewer_dev104_demo_b::handlersLoaded]} {
    source [file join [set ::GX::Generated_viewer_dev104_demo_b::root] generated handler_defaults.tcl]
    source [file join [set ::GX::Generated_viewer_dev104_demo_b::root] handlers.tcl]
    set ::GX::Generated_viewer_dev104_demo_b::handlersLoaded 1
}
proc ::GX::Generated_viewer_dev104_demo_b::design {} {return [::GX::viewerGuiDesignRead [file join [set ::GX::Generated_viewer_dev104_demo_b::root] gui design.tcldict]]}
proc ::GX::Generated_viewer_dev104_demo_b::handlers {} {
    set result {}
    dict for {id contract} [dict get [design] handlers] {dict set result $id [dict create command [list ::GX::Generated_viewer_dev104_demo_b::Handlers::$id] enabled [list ::GX::Generated_viewer_dev104_demo_b::Handlers::enabled]]}
    return $result
}
proc ::GX::Generated_viewer_dev104_demo_b::open {{context {}}} {
    set window .viewer_dev104_demo_b
    if {[winfo exists $window]} {
        set id [::GX::datasetPublicationV2DictDefault $context workspace_id {}]
        if {$id eq {}} {raise $window;return $window}
        if {[dict exists $::GX::SessionWorkspace::adapters $window] && ![::GX::sessionWorkspaceHostPrepare [dict get $::GX::SessionWorkspace::adapters $window] opening]} {return $window}
        destroy $window
    }
    ::GX::viewerGuiDesignCompose [design] $window viewer.dev104_demo_b dev104_demo_b runtime [handlers] $context
    return $window
}
proc ::GX::Generated_viewer_dev104_demo_b::workspaceOpen {context} {return [::GX::viewerGuiDesignWorkspaceOpen viewer.dev104_demo_b dev104_demo_b [design] runtime [handlers] $context]}
proc ::GX::Generated_viewer_dev104_demo_b::dispatch {operation scene} {return [open [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
::GX::viewerBackendRegister viewer_dev104_demo_b_gui ::GX::Generated_viewer_dev104_demo_b::dispatch
