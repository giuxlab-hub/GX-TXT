# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted generated facade; author logic is restricted C++ in a separate worker.
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_viewer_scientific_library_workspace {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_viewer_scientific_library_workspace::handlers {} {return [::GX::viewerDevelopmentInstalledBindings viewer.scientific_library_workspace scientific_library_workspace [set ::GX::Restricted_viewer_scientific_library_workspace::root]]}
proc ::GX::Restricted_viewer_scientific_library_workspace::dispatch {operation scene} {return [::GX::viewerDevelopmentInstalledOpen viewer.scientific_library_workspace scientific_library_workspace [set ::GX::Restricted_viewer_scientific_library_workspace::root] [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
proc ::GX::Restricted_viewer_scientific_library_workspace::workspaceOpen {context} {return [::GX::viewerDevelopmentInstalledOpen viewer.scientific_library_workspace scientific_library_workspace [set ::GX::Restricted_viewer_scientific_library_workspace::root] $context]}
proc ::GX::Restricted_viewer_scientific_library_workspace::texOpen {document} {return [::GX::viewerDevelopmentInstalledOpen viewer.scientific_library_workspace scientific_library_workspace [set ::GX::Restricted_viewer_scientific_library_workspace::root] [dict create tex_document_id $document]]}
::GX::viewerBackendRegister viewer_scientific_library_workspace_restricted_cpp_v1 ::GX::Restricted_viewer_scientific_library_workspace::dispatch
