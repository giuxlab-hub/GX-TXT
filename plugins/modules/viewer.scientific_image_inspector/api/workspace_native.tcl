# SPDX-License-Identifier: GPL-3.0-or-later
# The original image/figure owners and their independent P017 channels remain.
namespace eval ::GX::SII {}
if {![llength [info commands ::GX::SII::catalogGet]]} {source [file join [file dirname [info script]] .. runtime catalog.tcl]}
::GX::nativeWorkspaceShapeRegister image_inspector_annotation {record {
    kind text id text x1 int y1 int x2 int y2 int stroke int size int box_width int box_height int font_dpi int
    rotation real pivot_x real pivot_y real color text text text name text font_family text font_unit text font_value real
}}
proc ::GX::SII::workspaceStepShape {step} {
    set params {}
    foreach definition [dict get [catalogGet [dict get $step op]] params] {
        lassign $definition name type
        switch -- $type {int {set shape int} number - percent {set shape real} enum - geometry {set shape text} default {error "Undeclared image operation parameter type '$type'"}}
        dict set params $name $shape
    }
    return [list record [dict create op text params [list record $params] scope text roi {array int}]]
}
proc ::GX::SII::workspaceStepEncode {step} {tailcall ::GX::nativeWorkspaceEncode [workspaceStepShape $step] $step}
proc ::GX::SII::workspaceStepDecode {typed} {tailcall ::GX::nativeWorkspaceShapeDecode [workspaceStepShape [::GX::nativeWorkspaceDecode $typed]] $typed}
::GX::nativeWorkspaceCodecDecodeRegister ::GX::SII::workspaceStepEncode ::GX::SII::workspaceStepDecode
::GX::nativeWorkspaceShapeRegister image_inspector_state {record {
    schema text source_id text source_sha text steps {array {codec ::GX::SII::workspaceStepEncode}}
    panels {array {record {source_id text source_sha text steps {array {codec ::GX::SII::workspaceStepEncode}}}}}
    figure_settings {record {width int height int margin int gutter int layout text background text}}
    annotations {array {named image_inspector_annotation}} image_annotations {array {named image_inspector_annotation}} figure_annotations {array {named image_inspector_annotation}}
    annotation_layers_json text canvas_mode text sidebar_sections {array text} history_channels {map int}
    image_reset_previous {named image_inspector_state} reset_previous {named image_inspector_state} reset_state {named image_inspector_state}
    domain_history {codec ::GX::SII::workspaceDomainsEncode}
}}
proc ::GX::SII::workspaceEncode {payload} {tailcall ::GX::nativeWorkspaceShapePayloadEncode [dict get $::GX::WorkspaceScientificCodec::shapes image_inspector_state] $payload}
proc ::GX::SII::workspaceDecode {typed} {tailcall ::GX::nativeWorkspaceShapeDecode [dict get $::GX::WorkspaceScientificCodec::shapes image_inspector_state] $typed}
proc ::GX::SII::workspaceDomainsEncode {domains} {
    set fields {};dict for {channel record} $domains {
        if {$channel ni {image figure}} {error {Unknown Image Inspector History channel}}
        dict set fields $channel [::GX::nativeWorkspaceHistoryEncode $record ::GX::SII::workspaceEncode]
    };return [list object $fields]
}
proc ::GX::SII::workspaceDomainsDecode {typed} {
    set domains {};dict for {channel record} [lindex $typed 1] {dict set domains $channel [::GX::nativeWorkspaceHistoryDecode $record ::GX::SII::workspaceDecode]};return $domains
}
::GX::nativeWorkspaceCodecDecodeRegister ::GX::SII::workspaceDomainsEncode ::GX::SII::workspaceDomainsDecode
