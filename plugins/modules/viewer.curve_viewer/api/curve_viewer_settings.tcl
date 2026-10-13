# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::CurveViewer {}
proc ::GX::CurveViewer::_commands {} {
    return {add {Add curve…} filters {Source filters…} preview {Dataset Preview} show {Show selected} hide {Hide selected} remove {Remove from view} properties {Curve style…} label {Edit display label…} fit_selected {Fit selected view} fit_all {Fit all} presentation {Grid / view…} configuration {Labels / Configuration…} export {Export graphical presentation…} publish {Publish exact Dataset…} save {Save Workspace} undo Undo redo Redo previous {Previous History step} next {Next History step} latest {Return to latest} branch {Restart here…} timeline {Show History timeline} workspace_new {New Workspace…} workspace_open {Open Workspace…} workspace_duplicate {Save as / Duplicate…} workspace_rename {Rename Workspace…} workspace_manager {Session Workspaces…} workspace_close {Close Workspace} workspace_delete {Delete Workspace…} clear_history {Clear History…} cancel {Cancel source loading}}
}
set ::GX::CurveViewer::catalog {}
dict set ::GX::CurveViewer::catalog strip [dict create label {Show Description / History strip} default {}]
dict set ::GX::CurveViewer::catalog history_details [dict create label {Description / History details…} default {}]
dict for {id label} [::GX::CurveViewer::_commands] {
    set key [::GX::datasetPublicationV2DictDefault {undo Ctrl+z redo Ctrl+y save Ctrl+s} $id {}]
    dict set ::GX::CurveViewer::catalog $id [dict create label $label default $key]
}
::GX::viewerCommandCatalogRegister viewer.curve_viewer $::GX::CurveViewer::catalog modules.curve_viewer.shortcuts
proc ::GX::CurveViewer::_shortcutsValidate {values} {::GX::viewerShortcutsValidate viewer.curve_viewer $values}
proc ::GX::CurveViewer::_shortcutFields {} {::GX::viewerShortcutFields viewer.curve_viewer}
proc ::GX::CurveViewer::_labelFields {} {
    return [dict create strategy [dict create type choice label {Automatic presentation label} values {family source_name dataset} default family] max_length [dict create type number label {Automatic label character limit} min 8 max 160 default 32] legend_visible [dict create type boolean label {Show legend} default 1]]
}
proc ::GX::CurveViewer::_labelValidate {values} {
    if {[catch {dict size $values}]} {error {Labels must be a dictionary}}
    set result {}
    dict for {id field} [_labelFields] {dict set result $id [::GX::uiFieldNormalize $field [::GX::datasetPublicationV2DictDefault $values $id [dict get $field default]]]}
    foreach id [dict keys $values] {if {![dict exists $result $id]} {error {Unknown label configuration field}}}
    return $result
}
proc ::GX::CurveViewer::_displayLabel {record {preferences {}}} {
    set manual [::GX::datasetPublicationV2DictDefault $record presentation_label {}]
    if {$manual ne {}} {return $manual}
    if {$preferences eq {}} {set preferences [dict get [::GX::configurationResolve modules.curve_viewer.labels] effective]}
    set values [_labelValidate $preferences]
    set label [dict get $record name];set request [dict get $record request]
    if {[dict get $values strategy] eq "dataset"} {set label [dict get $request dataset_id]}
    if {[dict get $values strategy] eq "family"} {
        set labels {}
        foreach filter [::GX::datasetPublicationV2DictDefault $request filters {}] {
            set vid [dict get $filter filter_variable_id]
            if {[catch {::GX::datasetVariableV3ById [dict get $request dataset_id] $vid} variable]} continue
            if {$vid ne [::GX::datasetPublicationV2DictDefault $record manual_family {}] && [dict get $variable semantic_role] ni {member_identity family family_identity group_identity trace_identity trace_index sweep_identity}} continue
            if {[dict get $filter predicate] eq "in_set"} {set parts [dict get $filter values]} elseif {[dict get $filter predicate] eq "exact_equal"} {set parts [list [dict get $filter value]]} else continue
            if {[llength $parts]==1} {lappend labels [lindex $parts 0]} else {lappend labels "$vid: [llength $parts] values"}
        }
        if {$labels ne {}} {set label [join $labels { / }]}
    }
    set limit [expr {int([dict get $values max_length])}]
    if {[string length $label]>$limit} {set label "[string range $label 0 [expr {$limit-2}]]…"}
    return $label
}
proc ::GX::CurveViewer::_chosenLabels {w} {
    variable st
    set result {};set counts {};set indexes {}
    dict for {id record} $st($w,records) {
        set label [_displayLabel $record $st($w,labelPreferences)];dict set result $id $label
        if {[::GX::datasetPublicationV2DictDefault $record presentation_label {}] eq {}} {dict incr counts $label}
    }
    dict for {id record} $st($w,records) {
        set label [dict get $result $id]
        if {[::GX::datasetPublicationV2DictDefault $record presentation_label {}] eq {} && [dict get $counts $label]>1} {
            dict incr indexes $label;dict set result $id "$label · [dict get $indexes $label]"
        }
    }
    return $result
}
