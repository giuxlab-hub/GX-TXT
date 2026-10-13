# SPDX-License-Identifier: GPL-3.0-or-later
# Metadata discovery does not activate rendering or numerical runtimes.
namespace eval ::GX::CurveViewer {}
proc ::GX::CurveViewer::workspaceValidate {payload} {
    foreach key {version records next presentation view_requested} {if {![dict exists $payload $key]} {error "Viewer Workspace requires $key"}}
    if {[dict get $payload version] != 1} {error {Unsupported viewer Workspace version}}
}
proc ::GX::CurveViewer::workspaceOpen {id} {
    ::GX::modulePublicApiActivate viewer.curve_viewer CURVE_VIEWER_API_v1
    return [::GX::CurveViewer::open [dict create workspace_id $id]]
}
