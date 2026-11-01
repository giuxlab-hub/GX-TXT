# SPDX-License-Identifier: GPL-3.0-or-later
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval ::GX::Restricted_preview_scientific_trace {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Restricted_preview_scientific_trace::preview {context} {return [::GX::viewerDevelopmentPreviewTabs preview.scientific_trace [set ::GX::Restricted_preview_scientific_trace::root] $context]}
proc ::GX::Restricted_preview_scientific_trace::guiMount {host context} {return [::GX::viewerDevelopmentPreviewMount preview.scientific_trace [set ::GX::Restricted_preview_scientific_trace::root] $host $context]}
proc ::GX::Restricted_preview_scientific_trace::guiDispose {host context reason} {::GX::viewerDevelopmentPreviewDispose $host}
