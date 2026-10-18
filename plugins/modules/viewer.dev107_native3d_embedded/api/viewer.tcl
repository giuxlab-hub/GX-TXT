# Generated interface connector. Edit handlers.tcl for science.
# SPDX-License-Identifier: GPL-3.0-or-later
if {![llength [info commands ::GX::viewerGuiDesignCompose]]} {error {This Viewer requires the public CORE Viewer design capability.}}
namespace eval ::GX::Generated_viewer_dev107_native3d_embedded {variable root [file dirname [file dirname [info script]]]}
namespace eval ::GX::Generated_viewer_dev107_native3d_embedded::Handlers {}
if {![info exists ::GX::Generated_viewer_dev107_native3d_embedded::handlersLoaded]} {
    source [file join [set ::GX::Generated_viewer_dev107_native3d_embedded::root] generated handler_defaults.tcl]
    source [file join [set ::GX::Generated_viewer_dev107_native3d_embedded::root] handlers.tcl]
    set ::GX::Generated_viewer_dev107_native3d_embedded::handlersLoaded 1
}
foreach {api version} [dict get [::GX::viewerGuiDesignRead [file join [set ::GX::Generated_viewer_dev107_native3d_embedded::root] gui design.tcldict]] requirements] {::GX::workbenchExtensionRequireApi $api}
proc ::GX::Generated_viewer_dev107_native3d_embedded::design {} {return [::GX::viewerGuiDesignRead [file join [set ::GX::Generated_viewer_dev107_native3d_embedded::root] gui design.tcldict]]}
proc ::GX::Generated_viewer_dev107_native3d_embedded::handlers {} {
    set result {}
    dict for {id contract} [dict get [design] handlers] {dict set result $id [dict create command [list ::GX::Generated_viewer_dev107_native3d_embedded::Handlers::$id] enabled [list ::GX::Generated_viewer_dev107_native3d_embedded::Handlers::enabled]]}
    return $result
}
proc ::GX::Generated_viewer_dev107_native3d_embedded::open {{context {}}} {
    set window .viewer_dev107_native3d_embedded
    if {[winfo exists $window]} {
        set id [::GX::datasetPublicationV2DictDefault $context workspace_id {}]
        if {$id eq {}} {raise $window;return $window}
        if {[dict exists $::GX::SessionWorkspace::adapters $window] && ![::GX::sessionWorkspaceHostPrepare [dict get $::GX::SessionWorkspace::adapters $window] opening]} {return $window}
        destroy $window
    }
    ::GX::viewerGuiDesignCompose [design] $window viewer.dev107_native3d_embedded native3d_embedded runtime [handlers] $context
    return $window
}
proc ::GX::Generated_viewer_dev107_native3d_embedded::workspaceOpen {context} {return [::GX::viewerGuiDesignWorkspaceOpen viewer.dev107_native3d_embedded native3d_embedded [design] runtime [handlers] $context]}
proc ::GX::Generated_viewer_dev107_native3d_embedded::dispatch {operation scene} {return [open [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
::GX::viewerBackendRegister viewer_dev107_native3d_embedded_gui ::GX::Generated_viewer_dev107_native3d_embedded::dispatch
