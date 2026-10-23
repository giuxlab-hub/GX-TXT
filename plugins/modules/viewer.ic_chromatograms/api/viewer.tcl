# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted generated facade; author logic is restricted C++ in a separate worker.
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_viewer_ic_chromatograms {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_viewer_ic_chromatograms::handlers {} {return [::GX::viewerDevelopmentInstalledBindings viewer.ic_chromatograms ic_chromatograms [set ::GX::Restricted_viewer_ic_chromatograms::root]]}
proc ::GX::Restricted_viewer_ic_chromatograms::dispatch {operation scene} {return [::GX::viewerDevelopmentInstalledOpen viewer.ic_chromatograms ic_chromatograms [set ::GX::Restricted_viewer_ic_chromatograms::root] [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
proc ::GX::Restricted_viewer_ic_chromatograms::workspaceOpen {context} {return [::GX::viewerDevelopmentInstalledOpen viewer.ic_chromatograms ic_chromatograms [set ::GX::Restricted_viewer_ic_chromatograms::root] $context]}
proc ::GX::Restricted_viewer_ic_chromatograms::texOpen {document} {return [::GX::viewerDevelopmentInstalledOpen viewer.ic_chromatograms ic_chromatograms [set ::GX::Restricted_viewer_ic_chromatograms::root] [dict create tex_document_id $document]]}
::GX::viewerBackendRegister viewer_ic_chromatograms_restricted_cpp_v1 ::GX::Restricted_viewer_ic_chromatograms::dispatch
