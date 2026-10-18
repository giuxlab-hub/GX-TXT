# Generated interface connector. Edit handlers.tcl for science.
# SPDX-License-Identifier: GPL-3.0-or-later
if {![llength [info commands ::GX::viewerGuiDesignCompose]]} {error {This Viewer requires the public CORE Viewer design capability.}}
namespace eval ::GX::Generated_viewer_dev107_scientific_xy {variable root [file dirname [file dirname [info script]]]}
namespace eval ::GX::Generated_viewer_dev107_scientific_xy::Handlers {}
if {![info exists ::GX::Generated_viewer_dev107_scientific_xy::handlersLoaded]} {
    source [file join [set ::GX::Generated_viewer_dev107_scientific_xy::root] generated handler_defaults.tcl]
    source [file join [set ::GX::Generated_viewer_dev107_scientific_xy::root] handlers.tcl]
    set ::GX::Generated_viewer_dev107_scientific_xy::handlersLoaded 1
}
foreach {api version} [dict get [::GX::viewerGuiDesignRead [file join [set ::GX::Generated_viewer_dev107_scientific_xy::root] gui design.tcldict]] requirements] {::GX::workbenchExtensionRequireApi $api}
proc ::GX::Generated_viewer_dev107_scientific_xy::design {} {return [::GX::viewerGuiDesignRead [file join [set ::GX::Generated_viewer_dev107_scientific_xy::root] gui design.tcldict]]}
proc ::GX::Generated_viewer_dev107_scientific_xy::handlers {} {
    set result {}
    dict for {id contract} [dict get [design] handlers] {dict set result $id [dict create command [list ::GX::Generated_viewer_dev107_scientific_xy::Handlers::$id] enabled [list ::GX::Generated_viewer_dev107_scientific_xy::Handlers::enabled]]}
    return $result
}
proc ::GX::Generated_viewer_dev107_scientific_xy::open {{context {}}} {
    set window .viewer_dev107_scientific_xy
    if {[winfo exists $window]} {
        set id [::GX::datasetPublicationV2DictDefault $context workspace_id {}]
        if {$id eq {}} {raise $window;return $window}
        if {[dict exists $::GX::SessionWorkspace::adapters $window] && ![::GX::sessionWorkspaceHostPrepare [dict get $::GX::SessionWorkspace::adapters $window] opening]} {return $window}
        destroy $window
    }
    ::GX::viewerGuiDesignCompose [design] $window viewer.dev107_scientific_xy scientific_xy runtime [handlers] $context
    return $window
}
proc ::GX::Generated_viewer_dev107_scientific_xy::workspaceOpen {context} {return [::GX::viewerGuiDesignWorkspaceOpen viewer.dev107_scientific_xy scientific_xy [design] runtime [handlers] $context]}
proc ::GX::Generated_viewer_dev107_scientific_xy::dispatch {operation scene} {return [open [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
::GX::viewerBackendRegister viewer_dev107_scientific_xy_gui ::GX::Generated_viewer_dev107_scientific_xy::dispatch
