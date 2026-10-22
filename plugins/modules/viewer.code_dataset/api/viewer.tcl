# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted generated facade; author logic is restricted C++ in a separate worker.
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_viewer_code_dataset {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_viewer_code_dataset::handlers {} {return [::GX::viewerDevelopmentInstalledBindings viewer.code_dataset code_dataset [set ::GX::Restricted_viewer_code_dataset::root]]}
proc ::GX::Restricted_viewer_code_dataset::dispatch {operation scene} {return [::GX::viewerDevelopmentInstalledOpen viewer.code_dataset code_dataset [set ::GX::Restricted_viewer_code_dataset::root] [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
proc ::GX::Restricted_viewer_code_dataset::workspaceOpen {context} {return [::GX::viewerDevelopmentInstalledOpen viewer.code_dataset code_dataset [set ::GX::Restricted_viewer_code_dataset::root] $context]}
proc ::GX::Restricted_viewer_code_dataset::texOpen {document} {return [::GX::viewerDevelopmentInstalledOpen viewer.code_dataset code_dataset [set ::GX::Restricted_viewer_code_dataset::root] [dict create tex_document_id $document]]}
::GX::viewerBackendRegister viewer_code_dataset_restricted_cpp_v1 ::GX::Restricted_viewer_code_dataset::dispatch
