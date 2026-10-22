# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted generated facade; author logic is restricted C++ in a separate worker.
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_viewer_html {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_viewer_html::handlers {} {return [::GX::viewerDevelopmentInstalledBindings viewer.html html [set ::GX::Restricted_viewer_html::root]]}
proc ::GX::Restricted_viewer_html::dispatch {operation scene} {return [::GX::viewerDevelopmentInstalledOpen viewer.html html [set ::GX::Restricted_viewer_html::root] [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
proc ::GX::Restricted_viewer_html::workspaceOpen {context} {return [::GX::viewerDevelopmentInstalledOpen viewer.html html [set ::GX::Restricted_viewer_html::root] $context]}
proc ::GX::Restricted_viewer_html::texOpen {document} {return [::GX::viewerDevelopmentInstalledOpen viewer.html html [set ::GX::Restricted_viewer_html::root] [dict create tex_document_id $document]]}
::GX::viewerBackendRegister viewer_html_restricted_cpp_v1 ::GX::Restricted_viewer_html::dispatch
