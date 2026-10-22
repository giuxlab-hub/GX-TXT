# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted generated facade; author logic is restricted C++ in a separate worker.
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_viewer_electromagnetics_studio {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_viewer_electromagnetics_studio::handlers {} {return [::GX::viewerDevelopmentInstalledBindings viewer.electromagnetics_studio electromagnetics_studio [set ::GX::Restricted_viewer_electromagnetics_studio::root]]}
proc ::GX::Restricted_viewer_electromagnetics_studio::dispatch {operation scene} {return [::GX::viewerDevelopmentInstalledOpen viewer.electromagnetics_studio electromagnetics_studio [set ::GX::Restricted_viewer_electromagnetics_studio::root] [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
proc ::GX::Restricted_viewer_electromagnetics_studio::workspaceOpen {context} {return [::GX::viewerDevelopmentInstalledOpen viewer.electromagnetics_studio electromagnetics_studio [set ::GX::Restricted_viewer_electromagnetics_studio::root] $context]}
proc ::GX::Restricted_viewer_electromagnetics_studio::texOpen {document} {return [::GX::viewerDevelopmentInstalledOpen viewer.electromagnetics_studio electromagnetics_studio [set ::GX::Restricted_viewer_electromagnetics_studio::root] [dict create tex_document_id $document]]}
::GX::viewerBackendRegister viewer_electromagnetics_studio_restricted_cpp_v1 ::GX::Restricted_viewer_electromagnetics_studio::dispatch
