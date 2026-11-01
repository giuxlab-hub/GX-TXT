# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted generated facade; author logic is restricted C++ in a separate worker.
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_viewer_stderr_diagnostics {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_viewer_stderr_diagnostics::handlers {} {return [::GX::viewerDevelopmentInstalledBindings viewer.stderr_diagnostics stderr_diagnostics [set ::GX::Restricted_viewer_stderr_diagnostics::root]]}
proc ::GX::Restricted_viewer_stderr_diagnostics::dispatch {operation scene} {return [::GX::viewerDevelopmentInstalledOpen viewer.stderr_diagnostics stderr_diagnostics [set ::GX::Restricted_viewer_stderr_diagnostics::root] [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
proc ::GX::Restricted_viewer_stderr_diagnostics::workspaceOpen {context} {return [::GX::viewerDevelopmentInstalledOpen viewer.stderr_diagnostics stderr_diagnostics [set ::GX::Restricted_viewer_stderr_diagnostics::root] $context]}
proc ::GX::Restricted_viewer_stderr_diagnostics::texOpen {document} {return [::GX::viewerDevelopmentInstalledOpen viewer.stderr_diagnostics stderr_diagnostics [set ::GX::Restricted_viewer_stderr_diagnostics::root] [dict create tex_document_id $document]]}
::GX::viewerBackendRegister viewer_stderr_diagnostics_restricted_cpp_v1 ::GX::Restricted_viewer_stderr_diagnostics::dispatch
