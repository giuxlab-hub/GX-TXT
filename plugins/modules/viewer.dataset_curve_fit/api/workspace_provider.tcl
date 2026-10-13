# SPDX-License-Identifier: GPL-3.0-or-later
# Metadata discovery does not activate rendering or numerical runtimes.
namespace eval ::GX::DatasetCurveFit {}
proc ::GX::DatasetCurveFit::workspaceValidate {payload} {
    if {[dict exists $payload version] && [dict get $payload version]==1} {
        foreach key {dataset x y filters selected records view_bounds} {if {![dict exists $payload $key]} {error "Legacy Viewer Workspace requires $key"}}
        return
    }
    foreach key {version workspace_sources active_source next_source records presentation view_bounds} {if {![dict exists $payload $key]} {error "Viewer Workspace requires $key"}}
    if {[dict get $payload version] != 2} {error {Unsupported viewer Workspace version}}
}
proc ::GX::DatasetCurveFit::workspaceOpen {id} {
    ::GX::modulePublicApiActivate viewer.dataset_curve_fit DATASET_CURVE_FIT_API_v1
    return [::GX::DatasetCurveFit::open [dict create workspace_id $id]]
}
