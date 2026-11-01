# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted generated facade; author logic is restricted C++ in a separate worker.
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_viewer_markdown_documents {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_viewer_markdown_documents::handlers {} {return [::GX::viewerDevelopmentInstalledBindings viewer.markdown_documents markdown_documents [set ::GX::Restricted_viewer_markdown_documents::root]]}
proc ::GX::Restricted_viewer_markdown_documents::dispatch {operation scene} {return [::GX::viewerDevelopmentInstalledOpen viewer.markdown_documents markdown_documents [set ::GX::Restricted_viewer_markdown_documents::root] [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
proc ::GX::Restricted_viewer_markdown_documents::workspaceOpen {context} {return [::GX::viewerDevelopmentInstalledOpen viewer.markdown_documents markdown_documents [set ::GX::Restricted_viewer_markdown_documents::root] $context]}
proc ::GX::Restricted_viewer_markdown_documents::texOpen {document} {return [::GX::viewerDevelopmentInstalledOpen viewer.markdown_documents markdown_documents [set ::GX::Restricted_viewer_markdown_documents::root] [dict create tex_document_id $document]]}
::GX::viewerBackendRegister viewer_markdown_documents_restricted_cpp_v1 ::GX::Restricted_viewer_markdown_documents::dispatch
