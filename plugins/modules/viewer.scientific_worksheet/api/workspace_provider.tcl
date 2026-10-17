# SPDX-License-Identifier: GPL-3.0-or-later
# Metadata discovery does not load GUI/rendering/scientific runtimes.
namespace eval ::GX::WorksheetWorkspace {}
proc ::GX::WorksheetWorkspace::validate {payload} {
    ::GX::modulePublicApiActivate viewer.scientific_worksheet SCIENTIFIC_WORKSHEET_API_v1
    return [::GX::ScientificWorksheet::workspaceValidate $payload]
}
proc ::GX::WorksheetWorkspace::open {id} {
    ::GX::modulePublicApiActivate viewer.scientific_worksheet SCIENTIFIC_WORKSHEET_API_v1
    return [::GX::ScientificWorksheet::workspaceOpen $id]
}
