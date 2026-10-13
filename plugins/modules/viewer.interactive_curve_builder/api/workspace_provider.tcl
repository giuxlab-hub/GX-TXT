# SPDX-License-Identifier: GPL-3.0-or-later
# Discovery-only, inert working context. No Recipe or numerical runtime.
namespace eval ::GX::InteractiveCurveBuilder {}
proc ::GX::InteractiveCurveBuilder::workspaceValidate {payload} {
    foreach key [dict keys $payload] {if {$key ni {version settings lineage selected next workspace_metadata}} {error {Unknown Builder context field}}}
    foreach key {version settings lineage selected next} {if {![dict exists $payload $key]} {error "Builder Workspace needs $key"}}
    if {[dict get $payload version]!=1 || [llength [dict get $payload lineage]]>200000 || ![string is entier -strict [dict get $payload next]] || [dict get $payload next]<0} {error {Invalid Builder working context}}
    if {[dict exists $payload scientific_history] || [dict exists $payload history]} {error {Builder context does not accept History}}
    foreach key [dict keys [dict get $payload settings]] {if {$key ni {dataset x y z t family family_value family_enabled member member_value member_enabled selection mode parameter_mode method degree samples range_min range_max result_id result_name open_plot auto_order display_scope}} {error {Unknown Builder context setting}}}
    set settings [dict get $payload settings]
    foreach key {family_enabled member_enabled open_plot auto_order} {if {[dict get $settings $key] ni {0 1}} {error {Invalid Builder Boolean setting}}}
    if {[dict get $settings mode] ni {2d 3d} || [dict get $settings parameter_mode] ni {variable arc_length} || [dict get $settings method] ni {nearest linear cubic spline pchip line polynomial} || [dict get $settings display_scope] ni {full selected}} {error {Invalid Builder numerical/display choice}}
    set ids {}
    foreach entry [dict get $payload lineage] {
        foreach key {id dataset_id row x_id y_id z_id t_id family_id member_id source_sha256 source_schema_identity} {if {![dict exists $entry $key]} {error "Builder lineage needs $key"}}
        if {![string is entier -strict [dict get $entry row]] || [dict get $entry row]<0 || ![regexp {^[a-f0-9]{64}$} [dict get $entry source_sha256]]} {error {Invalid canonical Builder row identity}}
        if {![regexp {^[a-f0-9]{64}$} [dict get $entry source_schema_identity]] || [dict exists $ids [dict get $entry id]]} {error {Invalid Builder scientific schema or duplicate point identity}}
        dict set ids [dict get $entry id] 1
    }
    foreach id [dict get $payload selected] {if {![dict exists $ids $id]} {error {Selected Builder point is absent from canonical lineage}}}
    return 1
}
proc ::GX::InteractiveCurveBuilder::workspaceOpen {id} {
    ::GX::modulePublicApiActivate viewer.interactive_curve_builder INTERACTIVE_CURVE_BUILDER_API_v1
    return [::GX::InteractiveCurveBuilder::open [dict create workspace_id $id]]
}
