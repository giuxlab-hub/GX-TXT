# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::ReplicateWorkspace {}
proc ::GX::ReplicateWorkspace::validate {payload} {
    foreach key {format request hidden} {if {![dict exists $payload $key]} {error "Replicate Workspace requires '$key'"}}
    if {[dict get $payload format] ne "gxtxt.replicate_viewer.v1"} {error {Unsupported Replicate Workspace schema}}
    return 1
}
proc ::GX::ReplicateWorkspace::open {id} {
    ::GX::modulePublicApiActivate viewer.replicate_curve_analysis REPLICATE_VIEWER_API_v1
    return [::GX::ReplicateViewer::open [dict create workspace_id $id]]
}
