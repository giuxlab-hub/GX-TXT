# Lightweight workspace provider: no GUI, ImageMagick or Native2D activation.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::SII {}
proc ::GX::SII::workspaceValidate {payload} {
    if {[catch {dict size $payload}]} {error {Image Inspector Workspace is not a Tcl dictionary}}
    foreach key {schema source_id source_sha steps panels figure_settings annotations} {
        if {![dict exists $payload $key]} {error "Missing Image Inspector Workspace field: $key"}
    }
    if {[dict get $payload schema] ne "scientific_image_inspector.recipe.v2"} {
        error {Unsupported Image Inspector Workspace recipe}
    }
    set sha [dict get $payload source_sha]
    if {![regexp -nocase {^[a-f0-9]{64}$} $sha]} {error {Invalid Workspace image SHA-256}}
    if {[string length [dict get $payload source_id]]>512} {error {Invalid Workspace source ID}}
    # Validate retained state container shapes without loading an editing engine.
    foreach key {steps panels annotations} {
        set entries [dict get $payload $key]
        if {[llength $entries]>10000} {error "Workspace $key exceeds safety limit"}
    }
    if {[catch {dict size [dict get $payload figure_settings]}]} {error {Invalid figure settings}}
    if {[dict exists $payload sidebar_sections]} {
        set valid {simple figure annotations source analyze history publish}
        set sections [dict get $payload sidebar_sections]
        if {![llength $sections]} {error {Workspace must display at least one sidebar section}}
        foreach id $sections {if {$id ni $valid} {error "Unknown Workspace sidebar section: $id"}}
        if {[llength [lsort -unique $sections]] != [llength $sections]} {error {Duplicate Workspace sidebar section}}
    }
    return 1
}
proc ::GX::SII::workspaceProviderOpen {id} {
    # CORE provider open contract passes an exact Workspace ID, not a GUI dict.
    ::GX::viewerOpen viewer.scientific_image_inspector scientific_image_inspector \
        [dict create workspace_id $id]
}
