# SPDX-License-Identifier: GPL-3.0-or-later
# A declared editor for the existing canonical PlotSpec; no second trace model.
proc ::GX::_viewerGuiPlotSeriesDesignValidate {design} {
    set ids {};foreach c [dict get $design components] {dict set ids [dict get $c id] $c}
    set commands {}
    foreach c [dict get $design components] {
        set p [dict get $c properties];set present 0
        set keys {plot_series plot_series_label plot_series_axis plot_series_enabled plot_panel plot_panel_title plot_series_commands plot_series_target}
        foreach key $keys {if {[dict exists $p $key]} {incr present}}
        if {!$present} continue
        if {$present!=[llength $keys] || [dict get $c type] ne {section} || ![dict exists $p plot_dataset]} {error {Series editing requires a complete declared canonical Plot form}}
        foreach {key types} {plot_series {choice combobox} plot_series_label {field entry} plot_series_axis {choice combobox} plot_series_enabled {toggle checkbutton} plot_panel {choice combobox} plot_panel_title {field entry}} {
            if {![dict exists $ids [dict get $p $key]] || [dict get $ids [dict get $p $key] type] ni $types || [dict exists $ids [dict get $p $key] properties change_action]} {error "Invalid inert series editor control $key"}
        }
        set controls {};set base {}
        foreach key {plot_dataset plot_x plot_y plot_probe plot_x_scale plot_y_scale} {if {[dict exists $p $key]} {lappend base [dict get $p $key]}}
        foreach key {plot_series plot_series_label plot_series_axis plot_series_enabled plot_panel plot_panel_title plot_series_status} {
            if {![dict exists $p $key]} continue
            set id [dict get $p $key]
            if {$id in $controls || $id in $base} {error {Series editor controls must be distinct from each other and the canonical source controls}}
            lappend controls $id
        }
        foreach key {plot_series_label plot_panel_title} {
            set field [dict get $ids [dict get $p $key]]
            if {[dict get $field type] eq {field} && [datasetPublicationV2DictDefault [dict get $field properties] datatype string] ne {string}} {error {Series labels and panel titles require string fields}}
        }
        set target [dict get $p plot_series_target]
        if {![dict exists $ids $target] || [dict get $ids $target type] ne {plot} || ![dict exists $ids $target properties plot_form] || [dict get $ids $target properties plot_form] ne [dict get $c id]} {error {Series target must reference this form's declared canonical Plot}}
        if {[dict get $ids [dict get $p plot_series_axis] properties choices] ne {left right}} {error {Series axis choice must be left/right}}
        set used {}
        dict for {action operation} [dict get $p plot_series_commands] {
            if {$operation ni {refresh load add update remove up down panel_add panel_remove panel_up panel_down} || $operation in $used || $action in $commands || $action in {undo redo fit zoom_in zoom_out} || [dict exists [viewerGuiDesignVisibilityCommands $design] $action] || ![dict exists $design handlers $action] || [dict get $design handlers $action effect] ne {presentation}} {error {Series commands require unique fixed operations and distinct presentation handlers}}
            foreach other [dict get $design components] {if {[datasetPublicationV2DictDefault [dict get $other properties] scientific_netlist_action {}] eq $action} {error {Series and netlist commands must be distinct}}}
            lappend commands $action;lappend used $operation
        }
        if {![llength $used]} {error {Declare at least one series editor operation}}
        if {[dict exists $p plot_series_status] && (![dict exists $ids [dict get $p plot_series_status]] || [dict get $ids [dict get $p plot_series_status] type] ni {log label status})} {error {Series status needs a declared read-only text control}}
    }
}
proc ::GX::_viewerGuiPlotSeriesAction {window action} {
    foreach c [dict get $::GX::ViewerGui::instances $window design components] {
        if {[dict exists $c properties plot_series_commands $action]} {return [list [dict get $c id] [dict get $c properties plot_series_commands $action]]}
    }
    return {}
}
proc ::GX::_viewerGuiPlotSeriesSummary {window form spec {selected {}}} {
    set p [_viewerGuiPlotForm $window $form];set series {};set panels {};set text {}
    foreach panel [dict get $spec panels] {
        lappend panels [dict get $panel id]
        append text "Panel [dict get $panel id]: [datasetPublicationV2DictDefault $panel title {}]\n"
        foreach s [dict get $panel series] {
            set id [dict get $s id];lappend series $id
            append text "  $id | [datasetPublicationV2DictDefault $s label $id] | [dict get $s dataset_id] | [dict get $s x_variable_id] / [dict get $s y_variable_id] | [dict get $s axis] | enabled=[datasetPublicationV2DictDefault $s enabled 1]\n"
        }
    }
    viewerGuiDesignChoicesSet $window [dict get $p plot_series] $series
    viewerGuiDesignChoicesSet $window [dict get $p plot_panel] $panels
    set values [viewerGuiDesignValues $window]
    if {$selected ni $series} {set selected [dict get $values [dict get $p plot_series]]}
    if {$selected ni $series} {set selected [lindex $series 0]}
    viewerGuiDesignValueSet $window [dict get $p plot_series] $selected
    if {[dict get $values [dict get $p plot_panel]] ni $panels} {viewerGuiDesignValueSet $window [dict get $p plot_panel] [lindex $panels 0]}
    if {[dict exists $p plot_series_status]} {viewerGuiDesignTextSet $window [dict get $p plot_series_status] $text}
    return [dict create series $series panels $panels selected $selected]
}
proc ::GX::viewerGuiDesignPlotSeries {window form operation} {
    set p [_viewerGuiPlotForm $window $form]
    if {![dict exists $p plot_series_target] || $operation ni {refresh load add update remove up down panel_add panel_remove panel_up panel_down}} {error {Select a declared bounded series-editor operation}}
    set component [dict get $p plot_series_target]
    if {![dict exists $::GX::ViewerGui::instances $window bindings $component] || [dict get $::GX::ViewerGui::instances $window bindings $component kind] ne {plot}} {error {Bind the canonical Plot before editing its series}}
    set binding [dict get $::GX::ViewerGui::instances $window bindings $component];set spec [dict get $binding spec]
    set values [viewerGuiDesignValues $window];set selected [dict get $values [dict get $p plot_series]];set target [dict get $values [dict get $p plot_panel]]
    set panels [dict get $spec panels];set found {};set sourcePanel -1;set sourceIndex -1;set panelIndex -1;set count 0;set ids {}
    set pi 0
    foreach panel $panels {
        if {[dict get $panel id] eq $target} {set panelIndex $pi}
        set si 0
        foreach s [dict get $panel series] {
            lappend ids [dict get $s id];incr count
            if {[dict get $s id] eq $selected} {set found $s;set sourcePanel $pi;set sourceIndex $si}
            incr si
        }
        incr pi
    }
    if {$count>32 || [llength $panels]>8} {error {Declared series editor supports at most32 series and8 panels}}
    if {$operation eq {refresh}} {
        set result [_viewerGuiPlotSeriesSummary $window $form $spec]
        if {[dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerRecordOperation $window {Refresh canonical series controls}}
        return $result
    }
    if {$operation eq {load}} {
        if {$found eq {}} {error {Select an existing canonical series}}
        # Preflight the retained source BEFORE touching any displayed controls.
        set variables [datasetVariableSchemaV3 [dict get $found dataset_id]];set choices {}
        foreach variable $variables {if {[dict get $variable dtype] in {float64 float32 int64 int32 uint64 uint32 int16 uint16 int8 uint8}} {lappend choices [dict get $variable variable_id]}}
        if {[llength $choices]>4096 || [dict get $found x_variable_id] ni $choices || [dict get $found y_variable_id] ni $choices} {error {Retained series source is unavailable or not numeric}}
        # Dataset and variable discovery remain the existing public owner.
        viewerGuiDesignValueSet $window [dict get $p plot_dataset] [dict get $found dataset_id]
        viewerGuiDesignPlotDiscover $window $form
        foreach {key field} {plot_x x_variable_id plot_y y_variable_id plot_series_axis axis} {viewerGuiDesignValueSet $window [dict get $p $key] [dict get $found $field]}
        viewerGuiDesignValueSet $window [dict get $p plot_series_label] [datasetPublicationV2DictDefault $found label $selected]
        viewerGuiDesignValueSet $window [dict get $p plot_series_enabled] [datasetPublicationV2DictDefault $found enabled 1]
        viewerGuiDesignValueSet $window [dict get $p plot_panel] [dict get [lindex $panels $sourcePanel] id]
        viewerGuiDesignValueSet $window [dict get $p plot_panel_title] [datasetPublicationV2DictDefault [lindex $panels $sourcePanel] title {}]
        if {[dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerRecordOperation $window "Load series controls $selected"}
        return [dict create status loaded series_id $selected]
    }
    if {$operation in {add update}} {
        if {$panelIndex<0} {error {Select an existing canonical panel}}
        if {$operation eq {add}} {
            if {$count>=32} {error {Declared Plot series limit32 reached}}
            set n 1;while {"trace_$n" in $ids} {incr n};set selected trace_$n
            set updated [dict create id $selected kind line]
        } else {if {$found eq {}} {error {Select an existing canonical series}};set updated $found}
        foreach {key field} {plot_dataset dataset_id plot_x x_variable_id plot_y y_variable_id plot_series_label label plot_series_axis axis plot_series_enabled enabled} {dict set updated $field [dict get $values [dict get $p $key]]}
        if {[string length [dict get $updated label]]>160 || [regexp {[\r\n\x00]} [dict get $updated label]]} {error {Series label must be a single line of at most160 characters}}
        set variable [datasetVariableV3ById [dict get $updated dataset_id] [dict get $updated y_variable_id]]
        datasetVariableV3ById [dict get $updated dataset_id] [dict get $updated x_variable_id]
        if {[dict exists $variable shape] && [dict get $variable shape] eq {1} && [dict get $updated kind] eq {line}} {dict set updated kind line_marker;dict set updated style marker circle}
        if {$operation eq {update}} {
            set panel [lindex $panels $sourcePanel];dict set panel series [lreplace [dict get $panel series] $sourceIndex $sourceIndex];lset panels $sourcePanel $panel
        }
        set panel [lindex $panels $panelIndex]
        set list [dict get $panel series]
        if {$operation eq {update} && $sourcePanel==$panelIndex} {set list [linsert $list $sourceIndex $updated]} else {lappend list $updated}
        dict set panel series $list;lset panels $panelIndex $panel
    } elseif {$operation in {remove up down}} {
        if {$found eq {}} {error {Select an existing canonical series}}
        set panel [lindex $panels $sourcePanel];set list [dict get $panel series]
        if {$operation eq {remove}} {
            if {$count<=1} {error {The final canonical series cannot be removed}}
            set list [lreplace $list $sourceIndex $sourceIndex];set selected {}
        } else {
            set next [expr {$sourceIndex+($operation eq {up}?-1:1)}]
            if {$next<0 || $next>=[llength $list]} {error {Series is already at that panel boundary}}
            lset list $sourceIndex [lindex $list $next];lset list $next $found
        }
        dict set panel series $list;lset panels $sourcePanel $panel
    } elseif {$operation eq {panel_add}} {
        if {[llength $panels]>=8} {error {Declared panel limit8 reached}}
        set n 1;set names {};foreach panel $panels {lappend names [dict get $panel id]};while {"panel_$n" in $names} {incr n}
        set target panel_$n
        set title [dict get $values [dict get $p plot_panel_title]]
        if {[string length $title]>160 || [regexp {[\r\n\x00]} $title]} {error {Panel title must be a single line of at most160 characters}}
        lappend panels [dict create id $target title $title axes {} series {} annotations {}]
    } elseif {$operation in {panel_remove panel_up panel_down}} {
        if {$panelIndex<0} {error {Select an existing canonical panel}}
        set panel [lindex $panels $panelIndex]
        if {$operation eq {panel_remove}} {
            if {[llength $panels]<=1 || [llength [dict get $panel series]] || [llength [datasetPublicationV2DictDefault $panel annotations {}]]} {error {Only an empty, unannotated non-final panel may be removed}}
            set panels [lreplace $panels $panelIndex $panelIndex]
        } else {
            set next [expr {$panelIndex+($operation eq {panel_up}?-1:1)}]
            if {$next<0 || $next>=[llength $panels]} {error {Panel is already at that boundary}}
            lset panels $panelIndex [lindex $panels $next];lset panels $next $panel
        }
    }
    set normalized {}
    foreach panel $panels {
        set series {};set order 0
        foreach s [dict get $panel series] {dict set s order [incr order];lappend series $s}
        dict set panel series $series;lappend normalized $panel
    }
    dict set spec panels $normalized
    if {[dict exists $spec multi_panel]} {dict set spec multi_panel [expr {[llength $normalized]>1}]}
    # Existing Plot v4 validates all references, unit conversion, semantic X
    # compatibility and native model BEFORE replacing the accepted binding.
    set restoring [dict get $::GX::ViewerGui::instances $window restoring]
    dict set ::GX::ViewerGui::instances $window restoring 1
    try {
        viewerGuiDesignPlotSet $window $component $spec [datasetPublicationV2DictDefault $binding context {}]
        set receipt [_viewerGuiPlotSeriesSummary $window $form $spec $selected]
        if {$operation eq {panel_add}} {viewerGuiDesignValueSet $window [dict get $p plot_panel] $target}
    } finally {dict set ::GX::ViewerGui::instances $window restoring $restoring}
    if {!$restoring && [dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerRecordOperation $window "Plot series $operation"}
    return [dict merge [dict create status completed operation $operation owner PLOT_DATASET_API_v4] $receipt]
}
