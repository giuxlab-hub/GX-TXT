# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted generated facade; author logic is restricted C++ in a separate worker.
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_viewer_dataset_table_next {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_viewer_dataset_table_next::handlers {} {return [::GX::viewerDevelopmentInstalledBindings viewer.dataset_table_next dataset_table [set ::GX::Restricted_viewer_dataset_table_next::root]]}
proc ::GX::Restricted_viewer_dataset_table_next::dispatch {operation scene} {return [::GX::viewerDevelopmentInstalledOpen viewer.dataset_table_next dataset_table [set ::GX::Restricted_viewer_dataset_table_next::root] [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
proc ::GX::Restricted_viewer_dataset_table_next::workspaceOpen {context} {return [::GX::viewerDevelopmentInstalledOpen viewer.dataset_table_next dataset_table [set ::GX::Restricted_viewer_dataset_table_next::root] $context]}
proc ::GX::Restricted_viewer_dataset_table_next::texOpen {document} {return [::GX::viewerDevelopmentInstalledOpen viewer.dataset_table_next dataset_table [set ::GX::Restricted_viewer_dataset_table_next::root] [dict create tex_document_id $document]]}
::GX::viewerBackendRegister viewer_dataset_table_next_restricted_cpp_v1 ::GX::Restricted_viewer_dataset_table_next::dispatch
