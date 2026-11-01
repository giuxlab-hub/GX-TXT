# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted generated facade; author logic is restricted C++ in a separate worker.
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_viewer_ir_spectroscopy {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_viewer_ir_spectroscopy::handlers {} {return [::GX::viewerDevelopmentInstalledBindings viewer.ir_spectroscopy ir_spectroscopy [set ::GX::Restricted_viewer_ir_spectroscopy::root]]}
proc ::GX::Restricted_viewer_ir_spectroscopy::dispatch {operation scene} {return [::GX::viewerDevelopmentInstalledOpen viewer.ir_spectroscopy ir_spectroscopy [set ::GX::Restricted_viewer_ir_spectroscopy::root] [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
proc ::GX::Restricted_viewer_ir_spectroscopy::workspaceOpen {context} {return [::GX::viewerDevelopmentInstalledOpen viewer.ir_spectroscopy ir_spectroscopy [set ::GX::Restricted_viewer_ir_spectroscopy::root] $context]}
proc ::GX::Restricted_viewer_ir_spectroscopy::texOpen {document} {return [::GX::viewerDevelopmentInstalledOpen viewer.ir_spectroscopy ir_spectroscopy [set ::GX::Restricted_viewer_ir_spectroscopy::root] [dict create tex_document_id $document]]}
::GX::viewerBackendRegister viewer_ir_spectroscopy_restricted_cpp_v1 ::GX::Restricted_viewer_ir_spectroscopy::dispatch
