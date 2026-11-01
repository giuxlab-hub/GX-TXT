# SPDX-License-Identifier: GPL-3.0-or-later
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_preview_scientific_spectrum {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_preview_scientific_spectrum::preview {context} {return [::GX::viewerDevelopmentPreviewTabs preview.scientific_spectrum [set ::GX::Restricted_preview_scientific_spectrum::root] $context]}
proc ::GX::Restricted_preview_scientific_spectrum::guiMount {host context} {return [::GX::viewerDevelopmentPreviewMount preview.scientific_spectrum [set ::GX::Restricted_preview_scientific_spectrum::root] $host $context]}
proc ::GX::Restricted_preview_scientific_spectrum::guiDispose {host context reason} {::GX::viewerDevelopmentPreviewDispose $host}
