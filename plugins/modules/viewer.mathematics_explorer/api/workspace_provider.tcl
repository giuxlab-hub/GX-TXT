# SPDX-License-Identifier: GPL-3.0-or-later
# Independent model declarations; discovery does not open a plot or run Numeric.
namespace eval ::GX::MathematicsExplorer {}
if {![llength [info commands ::GX::MathematicsExplorer::validateState]]} {
    source [file join [file dirname [info script]] .. lib expression.tcl]
    source [file join [file dirname [info script]] .. lib science.tcl]
}
::GX::nativeWorkspaceShapeRegister mathematics_explorer {record {
    schema int title text xmin real xmax real samples int symbol_units {map text} output_unit text parameters {map real}
    derivative bool functions {array {record {id text label text preset text enabled bool expression text}}}
    view_axes {array {record {panel_id text axis text limits {array real} plot_rect {array real} scale text direction text aspect text
        ticks {array {record {value real display_value real label text device real}}}}}}
}}
proc ::GX::MathematicsExplorer::workspaceEncode {payload} {tailcall ::GX::nativeWorkspaceEncode {named mathematics_explorer} [dict remove $payload workspace_metadata]}
proc ::GX::MathematicsExplorer::workspaceOpen {id} {
    ::GX::modulePublicApiActivate viewer.mathematics_explorer MATHEMATICS_EXPLORER_API_v1
    return [open [dict create document_id $id]]
}
