# SPDX-License-Identifier: GPL-3.0-or-later
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_preview_scientific_frame {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_preview_scientific_frame::preview {context} {return [::GX::viewerDevelopmentPreviewTabs preview.scientific_frame [set ::GX::Restricted_preview_scientific_frame::root] $context]}
proc ::GX::Restricted_preview_scientific_frame::guiMount {host context} {return [::GX::viewerDevelopmentPreviewMount preview.scientific_frame [set ::GX::Restricted_preview_scientific_frame::root] $host $context]}
proc ::GX::Restricted_preview_scientific_frame::guiDispose {host context reason} {::GX::viewerDevelopmentPreviewDispose $host}
