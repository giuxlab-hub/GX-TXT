# GX-TXT public Image Inspector API and viewer activation (headless on source).
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::SII {
    variable moduleId viewer.scientific_image_inspector
    variable viewerId scientific_image_inspector
    variable version 0.4.1
    variable root [file normalize [file join [file dirname [info script]] ..]]
}
source [file join $::GX::SII::root runtime catalog.tcl]
source [file join $::GX::SII::root runtime engine.tcl]
source [file join $::GX::SII::root runtime article.tcl]
source [file join $::GX::SII::root runtime annotations_json.tcl]
source [file join $::GX::SII::root runtime manifest.tcl]
source [file join $::GX::SII::root runtime local_sources.tcl]

proc ::GX::SII::dispatch {action scene} {
    variable root
    if {![llength [info commands ::GX::SII::guiOpen]]} {source [file join $root runtime gui.tcl]}
    if {![llength [info commands ::GX::SII::historyStripCreate]]} {source [file join $root runtime history_strip.tcl]}
    if {![llength [info commands ::GX::SII::lodReset]]} {source [file join $root runtime lod.tcl]}
    if {![llength [info commands ::GX::SII::nativeCanvasCreate]]} {source [file join $root runtime native_canvas.tcl]}
    if {![llength [info commands ::GX::SII::buildSimpleTab]]} {source [file join $root runtime article_gui.tcl];source [file join $root runtime annotation_tools.tcl];source [file join $root runtime editor_controls.tcl];source [file join $root runtime roi_context.tcl]}
    return [guiOpen $action $scene]
}
::GX::viewerBackendRegister scientific_image_inspector_tk [list ::GX::SII::dispatch]
