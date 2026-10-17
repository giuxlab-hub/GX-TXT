# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::HTMLViewer {variable state}
proc ::GX::HTMLViewer::apiInfo {} {return [dict create api_id HTML_VIEWER_API_v1 api_version 1 native_renderer C scripts inactive external_resources inactive]}
proc ::GX::HTMLViewer::render {source} {return [::GX::documentRenderModel html $source]}
proc ::GX::HTMLViewer::open {{context {}}} {
    if {![::GX::viewerProviderEnabled viewer.html html]} {error {HTML Viewer presentation is disabled; its public rendering API remains available}}
    if {![dict exists $context dataset_id]} {error {Select a canonical HTML Dataset and use Open Dataset}}
    set id [dict get $context dataset_id]
    if {[::GX::datasetDocumentKind $id] ne {html}} {error {The Dataset is not an HTML document}}
    set design [::GX::viewerGuiDesignNew {HTML Document Viewer}]
    dict set design module_id viewer.html;dict set design provider_id html
    dict set design handlers view_source [dict create arguments {window action} effect presentation]
    dict set design components [list [dict create id source type action parent toolbar properties {label {View source} action view_source} layout {row 0 column 0}] [dict create id document type log parent canvas properties [dict create height 30] layout [dict create row 0 column 0 weight 1 sticky nsew]]]
    set w .gxtxt_html
    if {[winfo exists $w]} {destroy $w}
    ::GX::viewerGuiDesignCompose $design $w viewer.html html runtime [dict create view_source [dict create command ::GX::HTMLViewer::action]] {}
    set ::GX::HTMLViewer::state($w,dataset) $id
    set widget [dict get [::GX::viewerGuiRuntimeInspect $w] components document widget]
    ::GX::datasetDocumentRender $widget $id
    return $w
}
proc ::GX::HTMLViewer::action {w action} {if {![::GX::viewerGuiDesignGuard $w]} {error {Session changed; reopen this document}};return [::GX::datasetDocumentSourceOpen $::GX::HTMLViewer::state($w,dataset) [::GX::interactiveDocumentSessionToken]]}
proc ::GX::HTMLViewer::dispatch {operation scene} {return [open [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
::GX::viewerBackendRegister gxtxt_html ::GX::HTMLViewer::dispatch
