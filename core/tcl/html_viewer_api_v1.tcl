# SPDX-License-Identifier: GPL-3.0-or-later
# Compatibility facade retained when the existing HTML Viewer is rebuilt with
# the official C++ Workspace. The shared document owner remains authoritative.
namespace eval ::GX::HTMLViewer {}
proc ::GX::HTMLViewer::apiInfo {} {return [dict create api_id HTML_VIEWER_API_v1 api_version 1 native_renderer C scripts inactive external_resources inactive text_zoom {50 300 25} text_zoom_scope widget]}
proc ::GX::HTMLViewer::render {source} {return [::GX::documentRenderModel html $source]}
proc ::GX::HTMLViewer::open {{context {}}} {
    if {![::GX::viewerProviderEnabled viewer.html html]} {error {HTML Viewer presentation is disabled; its public rendering API remains available}}
    if {[dict exists $context dataset_id] && [::GX::datasetDocumentKind [dict get $context dataset_id]] ne {html}} {error {The Dataset is not an HTML document}}
    return [::GX::viewerOpen viewer.html html $context]
}
