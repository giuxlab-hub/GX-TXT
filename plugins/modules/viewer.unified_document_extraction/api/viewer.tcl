# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted generated facade; author logic is restricted C++ in a separate worker.
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_viewer_unified_document_extraction {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_viewer_unified_document_extraction::handlers {} {return [::GX::viewerDevelopmentInstalledBindings viewer.unified_document_extraction unified_document_extraction [set ::GX::Restricted_viewer_unified_document_extraction::root]]}
proc ::GX::Restricted_viewer_unified_document_extraction::dispatch {operation scene} {return [::GX::viewerDevelopmentInstalledOpen viewer.unified_document_extraction unified_document_extraction [set ::GX::Restricted_viewer_unified_document_extraction::root] [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
proc ::GX::Restricted_viewer_unified_document_extraction::workspaceOpen {context} {return [::GX::viewerDevelopmentInstalledOpen viewer.unified_document_extraction unified_document_extraction [set ::GX::Restricted_viewer_unified_document_extraction::root] $context]}
proc ::GX::Restricted_viewer_unified_document_extraction::texOpen {document} {return [::GX::viewerDevelopmentInstalledOpen viewer.unified_document_extraction unified_document_extraction [set ::GX::Restricted_viewer_unified_document_extraction::root] [dict create tex_document_id $document]]}
::GX::viewerBackendRegister viewer_unified_document_extraction_restricted_cpp_v1 ::GX::Restricted_viewer_unified_document_extraction::dispatch
