# Generated Dataset Preview connector; no standalone Viewer host.
# SPDX-License-Identifier: GPL-3.0-or-later
if {![llength [info commands ::GX::viewerGuiDesignPreviewMount]]} {error {This module requires the public Builder Preview Module target capability}}
namespace eval ::GX::Generated_preview_oscilloscope_waveform {variable root [file dirname [file dirname [info script]]]}
namespace eval ::GX::Generated_preview_oscilloscope_waveform::Handlers {}
source [file join [set ::GX::Generated_preview_oscilloscope_waveform::root] generated handler_defaults.tcl]
source [file join [set ::GX::Generated_preview_oscilloscope_waveform::root] handlers.tcl]
proc ::GX::Generated_preview_oscilloscope_waveform::design {} {return [::GX::viewerGuiDesignRead [file join [set ::GX::Generated_preview_oscilloscope_waveform::root] gui design.tcldict]]}
proc ::GX::Generated_preview_oscilloscope_waveform::preview {context} {
    return [dict create tabs [list [dict create id controls label [dict get [design] title] kind gui role complementary]]]
}
proc ::GX::Generated_preview_oscilloscope_waveform::guiMount {host context} {
    set d [design]
    ::GX::viewerGuiDesignPreviewMount $d $host [list ::GX::Generated_preview_oscilloscope_waveform::dispatchControl]
    foreach c [dict get $d components] {
        if {[dict get $c type] ne {action}} continue
        set contract [dict get $d handlers [dict get $c properties action]]
        if {[dict exists $contract available] && ![dict get $contract available]} {::GX::datasetPreviewGuiControlState $host [dict get $c id] {enabled 0}}
    }
}
proc ::GX::Generated_preview_oscilloscope_waveform::dispatchControl {host event} {
    # Resolve only declared bindings; the public dispatcher checks the actual
    # current host/source/activation before this callback can run.
    set d [design];set id [dict get $event control_id]
    foreach c [dict get $d components] {
        if {[dict get $c id] ne $id} continue
        set p [dict get $c properties]
        if {[dict exists $p preview_operation]} {return [::GX::datasetPreviewGuiView $host [dict get $p preview_operation]]}
        set key [expr {[dict get $event event] eq {invoke} ? {action} : {change_action}}]
        if {![dict exists $p $key]} return
        set action [dict get $p $key]
        set contract [dict get $d handlers $action]
        if {[dict exists $contract available] && ![dict get $contract available]} {error {This Preview action is unavailable}}
        return [::GX::Generated_preview_oscilloscope_waveform::Handlers::$action $host $event]
    }
}
proc ::GX::Generated_preview_oscilloscope_waveform::guiDispose {host context reason} {
    # CORE retires controls/panels/subscriptions. Author cleanup receives the
    # expired identity only; it cannot reuse this host after source switching.
    if {[llength [info commands ::GX::Generated_preview_oscilloscope_waveform::Handlers::dispose]]} {::GX::Generated_preview_oscilloscope_waveform::Handlers::dispose $context $reason}
}
