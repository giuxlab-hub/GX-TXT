# Generated interface connector. Edit handlers.tcl for science.
# SPDX-License-Identifier: GPL-3.0-or-later
if {![llength [info commands ::GX::viewerGuiDesignCompose]]} {error {This Viewer requires the dev104 CORE Viewer design capability.}}
namespace eval ::GX::Generated_viewer_dev104_demo_a {variable root [file dirname [file dirname [info script]]]}
namespace eval ::GX::Generated_viewer_dev104_demo_a::Handlers {}
if {![info exists ::GX::Generated_viewer_dev104_demo_a::handlersLoaded]} {
    source [file join [set ::GX::Generated_viewer_dev104_demo_a::root] generated handler_defaults.tcl]
    source [file join [set ::GX::Generated_viewer_dev104_demo_a::root] handlers.tcl]
    set ::GX::Generated_viewer_dev104_demo_a::handlersLoaded 1
}
proc ::GX::Generated_viewer_dev104_demo_a::design {} {return [::GX::viewerGuiDesignRead [file join [set ::GX::Generated_viewer_dev104_demo_a::root] gui design.tcldict]]}
proc ::GX::Generated_viewer_dev104_demo_a::handlers {} {
    set result {}
    dict for {id contract} [dict get [design] handlers] {dict set result $id [dict create command [list ::GX::Generated_viewer_dev104_demo_a::Handlers::$id] enabled [list ::GX::Generated_viewer_dev104_demo_a::Handlers::enabled]]}
    return $result
}
proc ::GX::Generated_viewer_dev104_demo_a::open {{context {}}} {
    set window .viewer_dev104_demo_a
    if {[winfo exists $window]} {
        set id [::GX::datasetPublicationV2DictDefault $context workspace_id {}]
        if {$id eq {}} {raise $window;return $window}
        if {[dict exists $::GX::SessionWorkspace::adapters $window] && ![::GX::sessionWorkspaceHostPrepare [dict get $::GX::SessionWorkspace::adapters $window] opening]} {return $window}
        destroy $window
    }
    ::GX::viewerGuiDesignCompose [design] $window viewer.dev104_demo_a dev104_demo_a runtime [handlers] $context
    return $window
}
proc ::GX::Generated_viewer_dev104_demo_a::workspaceOpen {context} {return [::GX::viewerGuiDesignWorkspaceOpen viewer.dev104_demo_a dev104_demo_a [design] runtime [handlers] $context]}
proc ::GX::Generated_viewer_dev104_demo_a::dispatch {operation scene} {return [open [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
::GX::viewerBackendRegister viewer_dev104_demo_a_gui ::GX::Generated_viewer_dev104_demo_a::dispatch
