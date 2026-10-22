# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted generated facade; author logic is restricted C++ in a separate worker.
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_viewer_pdf_reader {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_viewer_pdf_reader::handlers {} {return [::GX::viewerDevelopmentInstalledBindings viewer.pdf_reader pdf_reader [set ::GX::Restricted_viewer_pdf_reader::root]]}
proc ::GX::Restricted_viewer_pdf_reader::dispatch {operation scene} {return [::GX::viewerDevelopmentInstalledOpen viewer.pdf_reader pdf_reader [set ::GX::Restricted_viewer_pdf_reader::root] [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
proc ::GX::Restricted_viewer_pdf_reader::workspaceOpen {context} {return [::GX::viewerDevelopmentInstalledOpen viewer.pdf_reader pdf_reader [set ::GX::Restricted_viewer_pdf_reader::root] $context]}
proc ::GX::Restricted_viewer_pdf_reader::texOpen {document} {return [::GX::viewerDevelopmentInstalledOpen viewer.pdf_reader pdf_reader [set ::GX::Restricted_viewer_pdf_reader::root] [dict create tex_document_id $document]]}
::GX::viewerBackendRegister viewer_pdf_reader_restricted_cpp_v1 ::GX::Restricted_viewer_pdf_reader::dispatch
