# SPDX-License-Identifier: GPL-3.0-or-later
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_preview_uml_document {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_preview_uml_document::preview {context} {return [::GX::viewerDevelopmentPreviewTabs preview.uml_document [set ::GX::Restricted_preview_uml_document::root] $context]}
proc ::GX::Restricted_preview_uml_document::guiMount {host context} {return [::GX::viewerDevelopmentPreviewMount preview.uml_document [set ::GX::Restricted_preview_uml_document::root] $host $context]}
proc ::GX::Restricted_preview_uml_document::guiDispose {host context reason} {::GX::viewerDevelopmentPreviewDispose $host}
