# SPDX-License-Identifier: GPL-3.0-or-later
# Built-in CORE Print composition Workspace. PDF/CUPS remain derived services.
::GX::nativeWorkspaceShapeRegister print_recipe {record {
    schema text title text page {record {paper text orientation text rows int columns int margin_mm real gap_mm real captions bool layout_mode text background text}}
    items {array {record {id text source_kind text source_id text presentation text source_signature text caption text text text
        options {record {variables {array text} start int count int x_variable_id text y_variable_id text pdf_pages text}}
        frame {record {page int x_mm real y_mm real width_mm real height_mm real}}
        style {record {foreground text background text border text border_pt real padding_mm real font_size real weight text align text}}}}}
}}
proc ::GX::_printWorkspaceEncode {payload} {
    set fields {};dict for {key value} [dict remove $payload workspace_metadata] {
        switch -- $key {
            schema {set typed [list text $value]}
            recipe {set typed [nativeWorkspaceEncode {named print_recipe} $value]}
            history {set typed [nativeWorkspaceHistoryEncode $value [list ::GX::nativeWorkspaceEncode {named print_recipe}]]}
            default {error "Undeclared Print Workspace field '$key'"}
        };dict set fields $key $typed
    };return [list object $fields]
}
proc ::GX::_printWorkspaceValidate {payload} {
    if {[dict get $payload schema] ne {gxtxt.print_composition.v1}} {error {Incompatible Print composition Workspace}}
    printRecipeValidate [dict get $payload recipe];scientificHistoryValidate framework.printing [dict get $payload history]
    _printWorkspaceEncode $payload
}
proc ::GX::_printWorkspaceProviderEnsure {} {
    if {[dict exists $::GX::SessionWorkspace::providers print_composition]} {return}
    sessionWorkspaceProviderRegister print_composition [dict create module_id framework.printing type {Print Composition} schema gxtxt.print_composition.v1 version 1 native_contract NATIVE_WORKSPACE_API_v1 native_required_fields {schema text recipe object history object} encode ::GX::_printWorkspaceEncode decode ::GX::nativeWorkspaceDecode validate ::GX::_printWorkspaceValidate open ::GX::printStudioOpenWorkspace]
}
