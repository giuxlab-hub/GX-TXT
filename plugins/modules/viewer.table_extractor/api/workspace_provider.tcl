# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::TableExtractor {}
proc ::GX::TableExtractor::workspaceValidate {payload} {::GX::nativeWorkspaceJsonValidate gxtxt.table_extractor.workspace 1.0 $payload}
proc ::GX::TableExtractor::workspaceOpen {id} {
    ::GX::sessionWorkspaceValidate $id
    ::GX::modulePublicApiActivate viewer.table_extractor TABLE_EXTRACTOR_VIEWER_API_v1
    return [_launch [dict create workspace_id $id]]
}
