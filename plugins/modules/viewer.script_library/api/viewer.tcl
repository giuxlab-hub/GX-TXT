# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted generated facade; author logic is restricted C++ in a separate worker.
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_viewer_script_library {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_viewer_script_library::handlers {} {return [::GX::viewerDevelopmentInstalledBindings viewer.script_library script_library [set ::GX::Restricted_viewer_script_library::root]]}
proc ::GX::Restricted_viewer_script_library::dispatch {operation scene} {return [::GX::viewerDevelopmentInstalledOpen viewer.script_library script_library [set ::GX::Restricted_viewer_script_library::root] [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
proc ::GX::Restricted_viewer_script_library::workspaceOpen {context} {return [::GX::viewerDevelopmentInstalledOpen viewer.script_library script_library [set ::GX::Restricted_viewer_script_library::root] $context]}
proc ::GX::Restricted_viewer_script_library::texOpen {document} {return [::GX::viewerDevelopmentInstalledOpen viewer.script_library script_library [set ::GX::Restricted_viewer_script_library::root] [dict create tex_document_id $document]]}
::GX::viewerBackendRegister viewer_script_library_restricted_cpp_v1 ::GX::Restricted_viewer_script_library::dispatch
