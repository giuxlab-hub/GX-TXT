# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted generated facade; author logic is restricted C++ in a separate worker.
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_viewer_scientific_3d_workbench {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_viewer_scientific_3d_workbench::handlers {} {return [::GX::viewerDevelopmentInstalledBindings viewer.scientific_3d_workbench scientific_3d_workbench [set ::GX::Restricted_viewer_scientific_3d_workbench::root]]}
proc ::GX::Restricted_viewer_scientific_3d_workbench::dispatch {operation scene} {return [::GX::viewerDevelopmentInstalledOpen viewer.scientific_3d_workbench scientific_3d_workbench [set ::GX::Restricted_viewer_scientific_3d_workbench::root] [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
proc ::GX::Restricted_viewer_scientific_3d_workbench::workspaceOpen {context} {return [::GX::viewerDevelopmentInstalledOpen viewer.scientific_3d_workbench scientific_3d_workbench [set ::GX::Restricted_viewer_scientific_3d_workbench::root] $context]}
proc ::GX::Restricted_viewer_scientific_3d_workbench::texOpen {document} {return [::GX::viewerDevelopmentInstalledOpen viewer.scientific_3d_workbench scientific_3d_workbench [set ::GX::Restricted_viewer_scientific_3d_workbench::root] [dict create tex_document_id $document]]}
::GX::viewerBackendRegister viewer_scientific_3d_workbench_restricted_cpp_v1 ::GX::Restricted_viewer_scientific_3d_workbench::dispatch
