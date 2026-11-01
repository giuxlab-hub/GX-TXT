# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::SpectralLibraryViewer {}
::GX::nativeWorkspaceShapeRegister spectral_library_workspace {record {libraryId text entityId text mode text reversed bool selectedIds {array text} sessionDataset text rankingDataset text viewport {array real}}}
proc ::GX::SpectralLibraryViewer::workspaceEncode {payload} {tailcall ::GX::nativeWorkspaceEncode {named spectral_library_workspace} [dict remove $payload workspace_metadata]}
proc ::GX::SpectralLibraryViewer::workspaceValidate {payload} {
    foreach field {libraryId entityId mode reversed selectedIds sessionDataset rankingDataset viewport} {if {![dict exists $payload $field]} {error "Spectral Workspace requires $field"}}
    if {[dict get $payload mode] ni {overlay top_bottom stacked difference ratio} || ![string is boolean -strict [dict get $payload reversed]] || [llength [dict get $payload viewport]] ni {0 2}} {error {Invalid Spectral Workspace presentation}}
}
proc ::GX::SpectralLibraryViewer::workspaceOpen {id} {
    ::GX::modulePublicApiActivate viewer.spectral_library SPECTRAL_LIBRARY_VIEWER_API_v1
    return [_open [dict create workspace_id $id]]
}
