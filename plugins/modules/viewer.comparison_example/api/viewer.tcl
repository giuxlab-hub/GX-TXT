# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted generated facade; author logic is restricted C++ in a separate worker.
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_viewer_comparison_example {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_viewer_comparison_example::handlers {} {return [::GX::viewerDevelopmentInstalledBindings viewer.comparison_example comparison_example [set ::GX::Restricted_viewer_comparison_example::root]]}
proc ::GX::Restricted_viewer_comparison_example::dispatch {operation scene} {return [::GX::viewerDevelopmentInstalledOpen viewer.comparison_example comparison_example [set ::GX::Restricted_viewer_comparison_example::root] [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
proc ::GX::Restricted_viewer_comparison_example::workspaceOpen {context} {return [::GX::viewerDevelopmentInstalledOpen viewer.comparison_example comparison_example [set ::GX::Restricted_viewer_comparison_example::root] $context]}
proc ::GX::Restricted_viewer_comparison_example::texOpen {document} {return [::GX::viewerDevelopmentInstalledOpen viewer.comparison_example comparison_example [set ::GX::Restricted_viewer_comparison_example::root] [dict create tex_document_id $document]]}
::GX::viewerBackendRegister viewer_comparison_example_restricted_cpp_v1 ::GX::Restricted_viewer_comparison_example::dispatch
