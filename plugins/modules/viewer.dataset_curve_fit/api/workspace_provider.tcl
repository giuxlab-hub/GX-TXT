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
proc ::GX::DatasetCurveFit::templateWorkspaceValidate {payload} {
    foreach field {format recipe requirements} {if {![dict exists $payload $field]} {error "Fit template requires $field"}}
    if {[dict get $payload format] ne "gxtxt.fit_template.v1"||[dict size [dict get $payload requirements]]<2||[dict size [dict get $payload requirements]]>128} {error {Invalid fit template schema or variable binding count}}
    # Metadata discovery validates inert structure; availability of the captured
    # producer is checked only when explicitly binding/running the template.
    ::GX::scientificRecipeDataDecode [dict get $payload recipe] gxtxt.fit_recipe.v1
    dict for {id requirement} [dict get $payload requirements] {
        foreach field {unit value_kind rank dtype} {if {![dict exists $requirement $field]} {error "Fit template Variable $id requires $field"}}
    }
}
proc ::GX::DatasetCurveFit::templateWorkspaceOpen {id} {
    ::GX::modulePublicApiActivate viewer.dataset_curve_fit DATASET_CURVE_FIT_API_v1
    return [::GX::DatasetCurveFit::_templateDialog {} $id]
}
proc ::GX::DatasetCurveFit::surfaceWorkspaceValidate {payload} {
    foreach field {version source recipe settings preview records} {if {![dict exists $payload $field]} {error "Surface Workspace requires $field"}}
    if {[dict get $payload version]!=1||[llength [dict get $payload records]]>4096} {error {Invalid surface Workspace version or record count}}
    foreach field {source recipe settings preview} {dict size [dict get $payload $field]}
    foreach record [dict get $payload records] {if {[dict get $record schema] ne "gxtxt.fitter_surface_result.v1"||[dict get $record id] eq {}} {error {Invalid saved surface result identity}}}
}
proc ::GX::DatasetCurveFit::surfaceWorkspaceOpen {id} {
    ::GX::modulePublicApiActivate viewer.dataset_curve_fit DATASET_CURVE_FIT_API_v1
    return [::GX::DatasetCurveFit::openSurface [dict create workspace_id $id]]
}
