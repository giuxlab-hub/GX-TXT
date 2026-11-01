# SPDX-License-Identifier: GPL-3.0-or-later
# Metadata discovery does not activate rendering or numerical runtimes.
namespace eval ::GX::CurveViewer {}
::GX::nativeWorkspaceShapeRegister curve_viewer {record {
    version int next int presentation {named presentation2d} view_requested {tuple {real real real real real real {array real}}}
    selected_ids {array text} label_preferences {record {strategy text max_length real legend_visible bool}}
    records {array {record {
        id text request {named curve_request} name text visible bool color text width real direction {named native_direction}
        manual_family text presentation_label text line_style int marker int descriptor {named curve_descriptor} source_id text
        display_cache {record {version int record_id text receipt {resource {named resource_metadata}} geometry {resource {named resource_metadata}}}}
    }}}
}}
proc ::GX::CurveViewer::workspaceEncode {payload} {tailcall ::GX::nativeWorkspaceShapePayloadEncode [dict get $::GX::WorkspaceScientificCodec::shapes curve_viewer] $payload}
proc ::GX::CurveViewer::workspaceValidate {payload} {
    foreach key {version records next presentation view_requested} {if {![dict exists $payload $key]} {error "Viewer Workspace requires $key"}}
    if {[dict get $payload version] != 1} {error {Unsupported viewer Workspace version}}
}
proc ::GX::CurveViewer::workspaceOpen {id} {
    ::GX::modulePublicApiActivate viewer.curve_viewer CURVE_VIEWER_API_v1
    return [::GX::CurveViewer::open [dict create workspace_id $id]]
}
