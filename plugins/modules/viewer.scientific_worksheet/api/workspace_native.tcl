# SPDX-License-Identifier: GPL-3.0-or-later
# Independent Worksheet model adapter. Formula/input source and expression
# options remain lexical; computed containers retain their declared cell kinds.
namespace eval ::GX::WorksheetWorkspace {}
::GX::nativeWorkspaceShapeRegister worksheet_lineage {record {
    dataset_id text variable_id text source_row int selection_id text transform text source_cell text
    operation text field text output_index int operation_destination text source_unit text target_unit text
    source_lineage {array {named worksheet_lineage}} original_lineage {named worksheet_lineage}
}}
::GX::nativeWorkspaceShapeRegister worksheet_cell {codec ::GX::WorksheetWorkspace::cellEncode}
proc ::GX::WorksheetWorkspace::cellShape {cell} {
    set source text
    switch -- [dict get $cell kind] {
        scalar {set source real}
        derived {set source scientific_real}
        boolean {set source bool}
        complex {set source {record {shape {array int} real {array scientific_real} imaginary {array scientific_real}}}}
        vector - matrix {set source {array scientific_real}}
    }
    return [list record [dict create source $source kind text unit text lineage {named worksheet_lineage} dependencies {array text} \
        shape {array int} statistical_sources {array {named statistical_result}} source_lineage {array {named worksheet_lineage}} \
        statistical_result {named statistical_result} statistical_field text statistical_element int statistical_window {record {start int count int}}]]
}
proc ::GX::WorksheetWorkspace::cellEncode {cell} {tailcall ::GX::nativeWorkspaceEncode [cellShape $cell] $cell}
proc ::GX::WorksheetWorkspace::cellDecode {typed} {tailcall ::GX::nativeWorkspaceShapeDecode [cellShape [::GX::nativeWorkspaceDecode $typed]] $typed}
::GX::nativeWorkspaceCodecDecodeRegister ::GX::WorksheetWorkspace::cellEncode ::GX::WorksheetWorkspace::cellDecode
::GX::nativeWorkspaceShapeRegister worksheet_style {record {
    align text valign text wrap bool bold bool italic bool underline bool grouping bool foreground text background text border_color text
    font_family text font_size int rotation real border_width real border_style text border_edges {array text} category text decimals int custom text
}}
::GX::nativeWorkspaceShapeRegister worksheet_identity {record {workbook_id text session_token text owner_generation text document_revision int document_id text revision int active_sheet text}}
::GX::nativeWorkspaceShapeRegister worksheet_operation {record {
    status text stale_reason text operation text inputs {array text} options {map text} model {map text} destination text field text rows int columns int
    field_window {record {start int count int}} statistical_sources {array {named statistical_result}} source_lineage {array {named worksheet_lineage}}
    captured_statistics {named statistical_result} captured_data_values {array scientific_real} captured_data_companions {map {array scientific_real}}
}}
::GX::nativeWorkspaceShapeRegister worksheet_sheet {record {
    cells {map {named worksheet_cell}} columns {map text} ranges {map {array text}}
    bindings {map {record {dataset_id text variable_id text unit text selection_id text source_revision text first_row int row_count int}}}
    column_metadata {map {record {name text unit text unit_state text actual_units {array text}}}}
    row_identity {map int} row_order {map int} hidden_rows {map bool} operations {map {named worksheet_operation}}
    styles {map {named worksheet_style}} range_styles {array {record {bounds {array int} style {named worksheet_style} borders text}}}
    merges {map {array int}} row_heights {map int} column_widths {map int}
    filter_views {map {record {first int last int predicates {array {codec ::GX::WorksheetWorkspace::predicateEncode}} combine text binding_revisions {map text} sheet text source_revision int evaluated_revision int visible_rows {array int} visible_count int invalid_reason text}}}
    active_filter text filter_hidden_rows {map bool}
    scripts {map {record {reference text script_id text sha256 text language text source_resource {resource {named resource_metadata}}}}}
}}
proc ::GX::WorksheetWorkspace::predicateShape {predicate} {
    return [list record [dict create column text op text unit text value [expr {[dict get $predicate op] eq {in}?{array text}:{text}}]]]
}
proc ::GX::WorksheetWorkspace::predicateEncode {predicate} {tailcall ::GX::nativeWorkspaceEncode [predicateShape $predicate] $predicate}
proc ::GX::WorksheetWorkspace::predicateDecode {typed} {tailcall ::GX::nativeWorkspaceShapeDecode [predicateShape [::GX::nativeWorkspaceDecode $typed]] $typed}
::GX::nativeWorkspaceCodecDecodeRegister ::GX::WorksheetWorkspace::predicateEncode ::GX::WorksheetWorkspace::predicateDecode
set ::GX::WorksheetWorkspace::fields [dict merge [lindex [dict get $::GX::WorkspaceScientificCodec::shapes worksheet_sheet] 1] {
    format text document_id text name text revision int workbook_uuid text active_sheet text sheet_order {array text} sheets {map {named worksheet_sheet}}
    active_sheet_cache_omitted bool options {record {display_digits int calculation_mode text}}
    presentation {record {visible_rows int first_row int display_columns {array text} first_column int}}
    charts {map {record {id text sheet text x_column text y_columns {array text} right_columns {array text} first int last int kind text title text
        style {named plot_style} axes {map {named plot_axis}} legend text annotations {array {named plot_annotation}} annotation text panels text geometry {array real} revision int}}}
    history_resource {resource {named resource_metadata}}
    captured_formula_resources {map {map {array {resource {named resource_metadata}}}}}
    last_script {record {job_id text source {record {reference text script_id text sha256 text language text source_resource {resource {named resource_metadata}}}}
        selection {record {first text last text visible_only bool exact_row_ids {array int}}}}}
}]
::GX::nativeWorkspaceShapeRegister worksheet_book [list record $::GX::WorksheetWorkspace::fields]
unset ::GX::WorksheetWorkspace::fields
proc ::GX::WorksheetWorkspace::encode {payload} {tailcall ::GX::nativeWorkspaceShapePayloadEncode [dict get $::GX::WorkspaceScientificCodec::shapes worksheet_book] $payload}
proc ::GX::WorksheetWorkspace::decode {typed} {tailcall ::GX::nativeWorkspaceShapeDecode [dict get $::GX::WorkspaceScientificCodec::shapes worksheet_book] $typed}
