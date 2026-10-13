# SPDX-License-Identifier: GPL-3.0-or-later
# Optional CORE Workspace context, with exact row lineage and no History.
proc ::GX::InteractiveCurveBuilder::_uiWorkspaceCurrent {w} {variable ui;return $ui($w,document)}
proc ::GX::InteractiveCurveBuilder::_uiWorkspacePayload {w} {
    variable ui;_uiScope $w
    set settings {}
    foreach key {dataset x y z t family family_value family_enabled member member_value member_enabled selection mode parameter_mode method degree samples range_min range_max result_id result_name open_plot auto_order display_scope} {dict set settings $key $ui($w,$key)}
    set lineage {}
    foreach id [$w.points.tree children {}] {
        set row [dict get $ui($w,rows) $id];set entry [dict create id $id]
        foreach key {dataset_id row x_id y_id z_id t_id family_id member_id source_sha256 source_schema_identity filter_binding} {if {[dict exists $row $key]} {dict set entry $key [dict get $row $key]}}
        if {![dict exists $entry member_id]} {dict set entry member_id {}}
        if {![dict exists $entry source_sha256]} {dict set entry source_sha256 [dict get [::GX::sessionInspectionDatasetPayload [dict get $row dataset_id]] sha256]}
        if {![dict exists $entry source_schema_identity]} {dict set entry source_schema_identity [dict get [::GX::curveSourceDatasetIdentity [_session] [dict get $row dataset_id]] schema_identity]}
        lappend lineage $entry
    }
    return [dict create version 1 settings $settings lineage $lineage selected [dict keys $ui($w,selected)] next $ui($w,next)]
}
proc ::GX::InteractiveCurveBuilder::_uiWorkspaceSave {w} {
    variable ui;_uiScope $w
    set payload [_uiWorkspacePayload $w]
    if {$ui($w,document) eq {}} {
        set name $ui($w,workspace_name)
        if {$name eq {}} {set name "Curve Builder [clock microseconds]"}
        set document [::GX::sessionWorkspaceCreate curve_builder $name $payload]
        set ui($w,document) [dict get $document workspace_id]
    } else {
        set current [::GX::sessionWorkspaceGet $ui($w,document)]
        set currentPayload [dict remove [dict get $current payload] workspace_metadata]
        if {[dict get $current generation] ne $ui($w,document_generation) || ([dict get $current revision] ne $ui($w,document_revision) && $currentPayload ne $ui($w,saved_payload))} {error {Builder Workspace changed in another window; reopen before saving}}
        if {$currentPayload ne $payload} {::GX::sessionWorkspaceUpdate $ui($w,document) $payload}
    }
    set current [::GX::sessionWorkspaceGet $ui($w,document)]
    set ui($w,document_generation) [dict get $current generation];set ui($w,document_revision) [dict get $current revision]
    set ui($w,saved_payload) [dict remove [dict get $current payload] workspace_metadata]
    ::GX::sessionWorkspaceViewerTitlesRefresh
    set ui($w,status) {Builder working context saved; source Datasets remain unchanged}
}
proc ::GX::InteractiveCurveBuilder::_uiWorkspaceAttach {w context} {
    variable ui
    set id [::GX::datasetPublicationV2DictDefault $context workspace_id {}]
    if {$id ni {{} new}} {
        set record [::GX::sessionWorkspaceGet $id]
        if {[dict get $record provider_id] ne "curve_builder"} {error {Workspace belongs to another Viewer}}
        ::GX::sessionWorkspaceValidate $id
        set payload [dict get $record payload];set settings [dict get $payload settings]
        set ui($w,dataset) [dict get $settings dataset]
        _uiVariables $w
        dict for {key value} $settings {set ui($w,$key) $value}
        set sources {};set restored {};set identities {}
        foreach entry [dict get $payload lineage] {
            set dataset [dict get $entry dataset_id]
            if {![dict exists $identities $dataset]} {dict set identities $dataset [::GX::curveSourceDatasetIdentity [_session] $dataset]}
            set identity [dict get $identities $dataset]
            if {[dict get $identity sha256] ne [dict get $entry source_sha256] || [dict get $identity schema_identity] ne [dict get $entry source_schema_identity]} {error {A saved Builder source or scientific schema changed; reload explicit rows before using this context}}
            set binding [list $dataset [dict get $entry x_id] [dict get $entry y_id] [dict get $entry z_id] [dict get $entry t_id] [dict get $entry family_id] [dict get $entry member_id]]
            if {![dict exists $sources $binding]} {
                lassign $binding ds x y z t family member
                set byRow {}
                foreach row [sourceRows $ds $x $y $z $t $family {} {} [dict create family_enabled 0 member_id $member member_enabled 0 progress [list ::GX::InteractiveCurveBuilder::_uiProgress $w $ui($w,epoch)]]] {dict set byRow [dict get $row row] $row}
                dict set sources $binding $byRow
            }
            if {![dict exists $sources $binding [dict get $entry row]]} {error {Saved canonical source row is no longer finite/available}}
            set row [dict get $sources $binding [dict get $entry row]]
            if {[dict exists $entry filter_binding]} {dict set row filter_binding [dict get $entry filter_binding]}
            dict set restored [dict get $entry id] $row
        }
        set ui($w,rows) $restored;set ui($w,selected) {};set ui($w,next) [dict get $payload next]
        dict for {point row} $restored {$w.points.tree insert {} end -id $point -values [_uiRowValues $row]}
        _uiMark $w [dict get $payload selected]
        set ui($w,document) $id;set ui($w,workspace_name) [dict get $record name]
        set ui($w,document_generation) [dict get $record generation];set ui($w,document_revision) [dict get $record revision];set ui($w,saved_payload) [dict remove $payload workspace_metadata]
    }
    ::GX::sessionWorkspaceViewerTitle $w {Interactive Curve Builder} [list ::GX::InteractiveCurveBuilder::_uiWorkspaceCurrent $w] [list set ::GX::InteractiveCurveBuilder::ui($w,workspace_name)]
}
proc ::GX::InteractiveCurveBuilder::_uiDispose {w} {
    variable ui
    if {[info exists ui($w,epoch)]} {set ui($w,epoch) [incr ::GX::InteractiveCurveBuilder::epoch]}
    if {[info exists ui($w,document)] && $ui($w,document) ne {} && ![catch {_uiScope $w}]} {_uiWorkspaceSave $w}
}
