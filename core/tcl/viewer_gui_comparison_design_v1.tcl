# SPDX-License-Identifier: GPL-3.0-or-later
# Declarative profile only. Source admission, math and runtime belong to CORE.
proc ::GX::viewerGuiComparisonCommands {} {
    return {discover add_dataset add_library add_browser add_opened remove up down prepare clear inspect plot_fit plot_zoom_in plot_zoom_out plot_cursor plot_clear_cursor plot_reverse_x plot_properties plot_legend plot_style plot_copy plot_export plot_save_variant plot_load_variant}
}
proc ::GX::_viewerGuiComparisonDesignValidate {design} {
    set definitions {};foreach c [dict get $design components] {dict set definitions [dict get $c id] $c}
    set keys {comparison_target comparison_dataset comparison_x comparison_y comparison_mode comparison_normalization comparison_offset comparison_floor comparison_sources comparison_source comparison_status}
    set used {};set targets {};set commands {}
    foreach c [dict get $design components] {
        set p [dict get $c properties];set present 0
        foreach key [concat $keys comparison_library comparison_entry comparison_commands comparison_library_browser_group comparison_single_source] {if {[dict exists $p $key]} {set present 1}}
        if {!$present} continue
        if {[dict get $c type] ne {section}} {error {Comparison properties require a declared section}}
        if {[datasetPublicationV2DictDefault $design target viewer] ne {viewer}} {error {Comparison form requires a Viewer target}}
        foreach key $keys {if {![dict exists $p $key]} {error "Incomplete Comparison profile: $key"}}
        if {[dict exists $p comparison_single_source] && ![string is boolean -strict [dict get $p comparison_single_source]]} {error {Single-source consultation profile requires an explicit boolean}}
        set legacyLibrary [expr {![dict exists $p comparison_library_browser_group] || {add_library} in [dict values [datasetPublicationV2DictDefault $p comparison_commands {}]]}]
        if {$legacyLibrary || [dict exists $p comparison_library] || [dict exists $p comparison_entry]} {
            foreach key {comparison_library comparison_entry} {if {![dict exists $p $key]} {error "Legacy Library selection requires $key"}}
        }
        foreach {api version} {COMPARISON_PLOT_API_v1 1 PLOT_DATASET_API_v4 4 NUMERIC_API_v1 1} {
            if {![dict exists $design requirements $api] || [dict get $design requirements $api] ne $version} {error "Comparison profile requires $api@$version"}
        }
        foreach {key types} {
            comparison_target plot comparison_dataset dataset_selector
            comparison_x {choice combobox} comparison_y {choice combobox}
            comparison_library {choice combobox} comparison_entry {choice combobox}
            comparison_mode {choice combobox} comparison_normalization {choice combobox}
            comparison_offset {field entry} comparison_floor {field entry}
            comparison_sources table comparison_source {choice combobox} comparison_status log
        } {
            if {$key in {comparison_library comparison_entry} && ![dict exists $p $key]} continue
            set id [dict get $p $key]
            if {![dict exists $definitions $id] || [dict get $definitions $id type] ni $types || [dict exists $definitions $id properties change_action]} {error "Invalid inert Comparison control: $key"}
            if {$id in $used} {error {Comparison controls and targets must be distinct across forms}}
            lappend used $id
            if {$key in {comparison_offset comparison_floor} && [dict get $definitions $id type] eq {field} && [datasetPublicationV2DictDefault [dict get $definitions $id properties] datatype string] ni {number double integer}} {error {Comparison offset and floor require numeric fields}}
        }
        set target [dict get $p comparison_target];set plot [dict get $definitions $target]
        if {[dict exists $plot properties plot_form] || [datasetPublicationV2DictDefault [dict get $plot properties] comparison_form {}] ne [dict get $c id]} {error {Comparison Plot requires one reciprocal comparison_form without plot_form}}
        foreach other [dict get $design components] {
            foreach property {transform_plot scientific_probe_plot em_field_plot em_profile_plot} {if {[datasetPublicationV2DictDefault [dict get $other properties] $property {}] eq $target} {error {Comparison Plot cannot have a second scientific binding owner}}}
        }
        dict set targets $target [dict get $c id]
        foreach {key expected} {comparison_mode {overlay top_bottom stacked difference ratio} comparison_normalization {none minmax}} {
            set properties [dict get $definitions [dict get $p $key] properties]
            if {[datasetPublicationV2DictDefault $properties choices {}] ne $expected} {error "Comparison choice $key requires the declared finite choices"}
        }
        foreach key {comparison_offset comparison_floor} {
            set value [datasetPublicationV2DictDefault [dict get $definitions [dict get $p $key] properties] default 0]
            if {![string is double -strict $value] || [catch {expr {abs(double($value))<Inf}} finite] || !$finite || ($key eq {comparison_floor} && $value<0)} {error {Comparison numeric defaults must be finite; floor must be nonnegative}}
        }
        if {[dict exists $p comparison_library_browser_group]} {
            set group [dict get $p comparison_library_browser_group]
            if {![dict exists [_viewerGuiLibraryDefinitions $design 1] $group]} {error {Comparison Browser group requires all three shared Library Browser pages}}
        }
        set operations {}
        dict for {action operation} [datasetPublicationV2DictDefault $p comparison_commands {}] {
            if {$operation ni [viewerGuiComparisonCommands] || $action in $commands || $action in {undo redo fit zoom_in zoom_out} || ![dict exists $design handlers $action] || [dict get $design handlers $action effect] ne {presentation}} {error {Comparison commands require distinct presentation handlers and finite operations}}
            if {$operation in $operations} {error {Comparison operations cannot be duplicated within a profile}}
            lappend operations $operation
            # Existing trusted presentation profiles must not intercept the same action.
            foreach other [dict get $design components] {
                foreach property {plot_series_commands transform_commands pcb_commands visibility_commands} {if {[dict exists $other properties $property $action]} {error {Comparison action conflicts with another presentation profile}}}
                if {[datasetPublicationV2DictDefault [dict get $other properties] scientific_netlist_action {}] eq $action} {error {Comparison action conflicts with a netlist action}}
            }
            lappend commands $action
            if {$operation in {add_library add_browser add_opened} && (![dict exists $design requirements SCIENTIFIC_LIBRARY_MANAGER_API_v1] || [dict get $design requirements SCIENTIFIC_LIBRARY_MANAGER_API_v1] ne {1})} {error {Library comparison action requires its separate Library Manager API declaration}}
            if {$operation in {add_browser add_opened} && ![dict exists $p comparison_library_browser_group]} {error {Add Browser requires its declared shared Browser group}}
        }
    }
    foreach c [dict get $design components] {
        if {![dict exists $c properties comparison_form]} continue
        if {[dict get $c type] ne {plot} || ![dict exists $targets [dict get $c id]] || [dict get $targets [dict get $c id]] ne [dict get $c properties comparison_form]} {error {Orphan Comparison Plot form reference}}
    }
}
proc ::GX::_viewerGuiComparisonTemplate {title} {
    set design [viewerGuiDesignNew $title]
    foreach {api version} {COMPARISON_PLOT_API_v1 1 PLOT_DATASET_API_v4 4 NUMERIC_API_v1 1 SCIENTIFIC_LIBRARY_MANAGER_API_v1 1 SESSION_WORKSPACE_API_v1 1 SCIENTIFIC_RECIPE_API_v1 1 DOCUMENTATION_BROWSER_API_v1 1 CONFIGURATION_API_v1 1} {dict set design requirements $api $version}
    set commands {}
    foreach {operation label} {discover {Discover sources} add_dataset {Add Dataset source} add_library {Add Library entry} remove {Remove selected source} up {Move source up} down {Move source down} prepare {Prepare comparison} clear {Clear comparison} inspect {Inspect selected source}} {
        dict set commands comparison_$operation $operation
        dict set design handlers comparison_$operation [dict create arguments {window action} effect presentation label $label]
    }
    set sourceActions [dict keys $commands]
    set plotActions {}
    foreach {operation label} {plot_fit Fit plot_zoom_in {Zoom in} plot_zoom_out {Zoom out} plot_cursor {Pick display value} plot_clear_cursor {Clear cursor} plot_reverse_x {Reverse X} plot_properties {Properties…} plot_legend Legend plot_style {Series style…} plot_copy {Copy plot} plot_export {Export PNG…} plot_save_variant {Save Plot Variant…} plot_load_variant {Load Plot Variant…}} {
        set action comparison_$operation
        dict set commands $action $operation
        lappend plotActions $action
        dict set design handlers $action [dict create arguments {window action} effect presentation label $label]
    }
    set profile [dict create title Comparison comparison_target comparison_plot comparison_dataset comparison_dataset comparison_x comparison_x comparison_y comparison_y comparison_library comparison_library comparison_entry comparison_entry comparison_mode comparison_mode comparison_normalization comparison_normalization comparison_offset comparison_offset comparison_floor comparison_floor comparison_sources comparison_sources comparison_source comparison_source comparison_status comparison_status comparison_commands $commands]
    set components {}
    foreach {id type parent properties row column weight} [list \
        comparison_form section canvas $profile 0 0 1 \
        comparison_tabs tabs comparison_form {} 0 0 1 \
        comparison_plot_page tab comparison_tabs {title Plot} 0 0 1 \
        comparison_sources_page tab comparison_tabs {title Sources} 1 0 1 \
        comparison_method_page tab comparison_tabs {title Method} 2 0 1 \
        comparison_status_page tab comparison_tabs {title {Source and result}} 3 0 1 \
        comparison_plot plot comparison_plot_page {title {Comparison Plot} comparison_form comparison_form} 0 0 1 \
        comparison_dataset dataset_selector comparison_sources_page {label Dataset} 0 0 0 \
        comparison_x choice comparison_sources_page {label {X Variable} choices {} default {}} 1 0 0 \
        comparison_y choice comparison_sources_page {label {Y Variable} choices {} default {}} 2 0 0 \
        comparison_library choice comparison_sources_page {label Library choices {} default {}} 3 0 0 \
        comparison_entry choice comparison_sources_page {label {Library entry} choices {} default {}} 4 0 0 \
        comparison_sources table comparison_sources_page {columns {Index Kind Source {X unit} {Y unit} State} scrollbars both} 5 0 1 \
        comparison_source choice comparison_sources_page {label {Selected source} choices {} default {}} 6 0 0 \
        comparison_mode choice comparison_method_page {label Mode choices {overlay top_bottom stacked difference ratio} default overlay} 0 0 0 \
        comparison_normalization choice comparison_method_page {label {Display normalization} choices {none minmax} default none} 1 0 0 \
        comparison_offset field comparison_method_page {label {Display offset} datatype number default 0} 2 0 0 \
        comparison_floor field comparison_method_page {label {Denominator floor} datatype number default 0 min 0} 3 0 0 \
        comparison_status log comparison_status_page {text {Select two compatible sources, then Prepare.}} 0 0 1 \
        comparison_menu menu menubar [dict create label Compare actions $sourceActions] 0 0 0 \
        comparison_workspace workspace footer {} 0 0 0 \
        comparison_history history footer {} 0 1 0 \
        comparison_help help footer {} 0 2 0 \
        comparison_plot_menu menu menubar [dict create label Plot actions $plotActions] 0 1 0] {
        lappend components [dict create id $id type $type parent $parent properties $properties layout [dict create row $row column $column weight $weight sticky nsew padding 0]]
    }
    dict set design components $components
    return $design
}
proc ::GX::viewerGuiDesignComparisonNew {{title {Comparison Plot Viewer}}} {
    return [viewerGuiDesignValidate [_viewerGuiComparisonTemplate $title]]
}
