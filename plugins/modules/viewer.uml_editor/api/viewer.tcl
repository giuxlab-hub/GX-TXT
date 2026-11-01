# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted generated facade; author logic is restricted C++ in a separate worker.
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_viewer_uml_editor {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_viewer_uml_editor::handlers {} {return [::GX::viewerDevelopmentInstalledBindings viewer.uml_editor uml_editor [set ::GX::Restricted_viewer_uml_editor::root]]}
proc ::GX::Restricted_viewer_uml_editor::dispatch {operation scene} {return [::GX::viewerDevelopmentInstalledOpen viewer.uml_editor uml_editor [set ::GX::Restricted_viewer_uml_editor::root] [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
proc ::GX::Restricted_viewer_uml_editor::workspaceOpen {context} {return [::GX::viewerDevelopmentInstalledOpen viewer.uml_editor uml_editor [set ::GX::Restricted_viewer_uml_editor::root] $context]}
proc ::GX::Restricted_viewer_uml_editor::texOpen {document} {return [::GX::viewerDevelopmentInstalledOpen viewer.uml_editor uml_editor [set ::GX::Restricted_viewer_uml_editor::root] [dict create tex_document_id $document]]}
::GX::viewerBackendRegister viewer_uml_editor_restricted_cpp_v1 ::GX::Restricted_viewer_uml_editor::dispatch
