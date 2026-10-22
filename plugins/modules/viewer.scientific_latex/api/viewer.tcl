# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted generated facade; author logic is restricted C++ in a separate worker.
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_viewer_scientific_latex {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_viewer_scientific_latex::handlers {} {return [::GX::viewerDevelopmentInstalledBindings viewer.scientific_latex scientific_latex [set ::GX::Restricted_viewer_scientific_latex::root]]}
proc ::GX::Restricted_viewer_scientific_latex::dispatch {operation scene} {return [::GX::viewerDevelopmentInstalledOpen viewer.scientific_latex scientific_latex [set ::GX::Restricted_viewer_scientific_latex::root] [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
proc ::GX::Restricted_viewer_scientific_latex::workspaceOpen {context} {return [::GX::viewerDevelopmentInstalledOpen viewer.scientific_latex scientific_latex [set ::GX::Restricted_viewer_scientific_latex::root] $context]}
proc ::GX::Restricted_viewer_scientific_latex::texOpen {document} {return [::GX::viewerDevelopmentInstalledOpen viewer.scientific_latex scientific_latex [set ::GX::Restricted_viewer_scientific_latex::root] [dict create tex_document_id $document]]}
::GX::viewerBackendRegister viewer_scientific_latex_restricted_cpp_v1 ::GX::Restricted_viewer_scientific_latex::dispatch
