# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted generated facade; author logic is restricted C++ in a separate worker.
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_viewer_test_cad_2 {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_viewer_test_cad_2::handlers {} {return [::GX::viewerDevelopmentInstalledBindings viewer.test_cad_2 test_cad_2 [set ::GX::Restricted_viewer_test_cad_2::root]]}
proc ::GX::Restricted_viewer_test_cad_2::dispatch {operation scene} {return [::GX::viewerDevelopmentInstalledOpen viewer.test_cad_2 test_cad_2 [set ::GX::Restricted_viewer_test_cad_2::root] [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
proc ::GX::Restricted_viewer_test_cad_2::workspaceOpen {context} {return [::GX::viewerDevelopmentInstalledOpen viewer.test_cad_2 test_cad_2 [set ::GX::Restricted_viewer_test_cad_2::root] $context]}
proc ::GX::Restricted_viewer_test_cad_2::texOpen {document} {return [::GX::viewerDevelopmentInstalledOpen viewer.test_cad_2 test_cad_2 [set ::GX::Restricted_viewer_test_cad_2::root] [dict create tex_document_id $document]]}
::GX::viewerBackendRegister viewer_test_cad_2_restricted_cpp_v1 ::GX::Restricted_viewer_test_cad_2::dispatch
