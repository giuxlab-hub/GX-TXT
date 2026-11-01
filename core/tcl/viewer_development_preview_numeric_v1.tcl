# SPDX-License-Identifier: GPL-3.0-or-later
# Actual numeric Preview pane; existing compiled SDK, canonical Plot and UI Field
# owners. No fabricated Viewer shell, importer dependency or publication engine.
proc ::GX::_previewCppNumericTabs {module design context} {
    if {[_previewScientificDeclared $design]} {
        if {![catch {set actual [_previewScientificVariables [dict get $context dataset_id]]}] && [llength $actual]} {return [dict create tabs [list [dict create id numeric label [dict get $design title] kind gui]]]}
        return {tabs {}}
    }
    if {[catch {set variables [_viewerGuiPlotVariables [dict get $context dataset_id]]}]} {return {tabs {}}}
    foreach variable [dict get $variables variables] {
        if {[datasetPublicationV2DictDefault $variable enabled 1] && [dict get $variable rank]==1 && [dict get $variable variable_id] in [dict get $variables choices]} {
            return [dict create tabs [list [dict create id numeric label [dict get $design title] kind gui]]]
        }
    }
    return {tabs {}}
}
proc ::GX::_previewCppNumericComponent {host id {type {}}} {
    _datasetPreviewGuiRequire $host
    foreach component [dict get $::GX::PreviewCpp::mounts $host design components] {
        if {[dict get $component id] eq $id} {
            if {$type ne {} && [dict get $component type] ne $type} {error {Compiled Preview targets another component type}}
            return $component
        }
    }
    error {Compiled Preview targets an undeclared component}
}
proc ::GX::_previewCppNumericVariables {host} {
    set result {};set variables [_viewerGuiPlotVariables [dict get [datasetPreviewGuiContext $host] dataset_id]]
    foreach variable [dict get $variables variables] {
        if {[datasetPublicationV2DictDefault $variable enabled 1] && [dict get $variable variable_id] in [dict get $variables choices] && [dict get $variable rank]==1} {lappend result $variable}
    }
    if {$result eq {}} {error {Numeric Preview requires actual rank1 numeric Variables}}
    return $result
}
proc ::GX::_previewCppNumericDataJson {host} {
    set dataset [dict get [datasetPreviewGuiContext $host] dataset_id]
    if {[datasetPublicationV2DictDefault [dict get $::GX::PreviewCpp::mounts $host] scientific_client 0]} {return {{}}}
    set descriptions {};set ids {}
    foreach variable [_previewCppNumericVariables $host] {
        set fields {}
        foreach key {variable_id canonical display_label dtype unit semantic_role coordinate_role coordinate_variable_ids} {lappend fields "[viewerDevelopmentJsonString $key]:[viewerDevelopmentJsonString [datasetPublicationV2DictDefault $variable $key {}]]"}
        set shape [dict get $variable shape]
        foreach size $shape {if {![string is wideinteger -strict $size] || $size<0} {error {Invalid canonical numeric shape}}}
        lappend fields {"rank":1} "\"shape\":\[[join $shape ,]\]"
        lappend descriptions "\{[join $fields ,]\}"
        if {[llength $ids]<16} {lappend ids [dict get $variable variable_id]}
    }
    set available [datasetField $dataset row_count [lindex [dict get [lindex [_previewCppNumericVariables $host] 0] shape] 0]]
    if {![string is wideinteger -strict $available] || $available<0} {error {Numeric Preview requires an exact canonical row count}}
    set count [expr {min(16,$available)}]
    if {$count} {
        set stream [tableStreamOpenDataset $::GX::currentSession $dataset $ids $count [dict create start 0 count $count numeric_transport values]]
        try {set chunk [tableStreamNext $stream]} finally {tableStreamClose $stream}
    } else {set chunk {nrows 0 values {}}}
    set rows {}
    for {set row 0} {$row<[dict get $chunk nrows]} {incr row} {
        set cells {};foreach id $ids {lappend cells [viewerDevelopmentJsonString [lindex [dict get $chunk values $id] $row]]}
        lappend rows "\[[join $cells ,]\]"
    }
    set names {};foreach id $ids {lappend names [viewerDevelopmentJsonString $id]}
    set fields {}
    foreach {key value} [list dataset_id $dataset contract [datasetField $dataset kind {}] canonical_sha256 [datasetField $dataset canonical_sha256 {}] source_sha256 [datasetField $dataset source_sha256 {}]] {lappend fields "[viewerDevelopmentJsonString $key]:[viewerDevelopmentJsonString $value]"}
    lappend fields "\"variables\":\[[join $descriptions ,]\]" "\"sample\":\{\"start\":0,\"count\":[dict get $chunk nrows],\"sample_only\":true,\"variable_ids\":\[[join $names ,]\],\"rows\":\[[join $rows ,]\]\}"
    set result "\{[join $fields ,]\}"
    if {[string length [encoding convertto utf-8 $result]]>65536} {error {Canonical Preview context exceeds64KiB}}
    datasetPreviewGuiContext $host
    return $result
}
proc ::GX::_previewCppNumericForm {host id} {
    set p [dict get [_previewCppNumericComponent $host $id section] properties]
    foreach key {plot_dataset plot_x plot_y} {if {![dict exists $p $key]} {error {Compiled Plot requires a complete canonical form}}}
    if {[datasetPreviewGuiControlGet $host [dict get $p plot_dataset]] ne [dict get [datasetPreviewGuiContext $host] dataset_id]} {error {Numeric Preview cannot change its canonical source}}
    return $p
}
proc ::GX::_previewCppNumericDiscover {host form} {
    set p [_previewCppNumericForm $host $form];set choices {}
    foreach variable [_previewCppNumericVariables $host] {lappend choices [dict get $variable variable_id]}
    set scientific [datasetPublicationV2DictDefault [dict get $::GX::PreviewCpp::mounts $host] scientific_client 0]
    set defaults {}
    if {$scientific} {
        set defaults [_previewScientificPlotDefaults [dict get [datasetPreviewGuiContext $host] dataset_id]]
        set first [expr {![dict exists $::GX::PreviewCpp::mounts $host scientific_plot_initialized $form]}]
        set allowed [linsert $choices 0 {}]
    } else {set allowed $choices}
    foreach key {plot_x plot_y} {
        set id [dict get $p $key];set previous [datasetPreviewGuiControlGet $host $id]
        datasetPreviewGuiChoicesSet $host $id $allowed
        if {$scientific} {
            if {$first} {datasetPreviewGuiControlSet $host $id [datasetPublicationV2DictDefault $defaults $key {}]
            } elseif {$previous ni $choices} {datasetPreviewGuiControlSet $host $id {}}
        } elseif {$previous ni $choices} {datasetPreviewGuiControlSet $host $id [lindex $choices [expr {$key eq {plot_y} && [llength $choices]>1?1:0}]]}
    }
    if {$scientific} {dict set ::GX::PreviewCpp::mounts $host scientific_plot_initialized $form 1}
}
proc ::GX::_previewCppNumericApply {host operations} {
    if {[llength $operations]>64} {error {Compiled Preview exceeded its presentation operation bound}}
    foreach operation $operations {
        set id [dict get $operation component];set name [dict get $operation operation]
        set component [_previewCppNumericComponent $host $id];set type [dict get $component type];set value [dict get $operation value]
        switch $name {
            text_set - number_set - flag_set {
                if {$type ni {label status}} {error {Compiled values target read-only labels/status only}}
                datasetPreviewGuiControlSet $host $id $value
            }
            table_set {
                _previewCppNumericComponent $host $id table
                dict for {form roles} [_viewerGuiClientRoleMapsValidate [dict get $::GX::PreviewCpp::mounts $host design]] {
                    if {![dict exists $roles scientific_preview_components]} continue
                    foreach role {values metadata source} {if {$id eq [dict get $roles scientific_preview_components $role]} {error {Scientific role tables accept canonical CORE projections only}}}
                }
                datasetPreviewGuiTableSet $host $id $value
            }
            scientific_preview_command {_previewScientificCommand $host $id $value}
            scientific_frame_bind {_previewScientificFrameBind $host $id $value}
            plot_discover {_previewCppNumericDiscover $host $id}
            plot_bind {
                set p [_previewCppNumericForm $host $id];_previewCppNumericComponent $host $value plot
                set selection [dict create x_variable_id [datasetPreviewGuiControlGet $host [dict get $p plot_x]] y_variable_id [datasetPreviewGuiControlGet $host [dict get $p plot_y]]]
                if {[datasetPublicationV2DictDefault [dict get $::GX::PreviewCpp::mounts $host] scientific_client 0] && ([dict get $selection x_variable_id] eq {} || [dict get $selection y_variable_id] eq {})} {continue}
                foreach {key field} {x_scale plot_x_scale y_scale plot_y_scale} {if {[dict exists $p $field]} {dict set selection $key [datasetPreviewGuiControlGet $host [dict get $p $field]]}}
                datasetPreviewGuiPlotBind $host $value $selection
            }
            default {error {Numeric Preview requested an unavailable capability}}
        }
    }
}
proc ::GX::_previewCppNumericEvent {host event} {
    variable ::GX::PreviewCpp::mounts
    _datasetPreviewGuiRequire $host
    if {![dict exists $mounts $host] || [dict get $mounts $host busy]} {error {Compiled Preview is closed or busy}}
    set record [dict get $mounts $host];set design [dict get $record design]
    if {[_previewCppDesign [dict get $record module] [dict get $record root]] ne $design} {error {Compiled Preview package changed}}
    set ordinal 0;set selected 0;set kind 0;set inputs {};set selectedComponent {}
    foreach component [dict get $design components] {
        incr ordinal;set id [dict get $component id];set type [dict get $component type];set text {}
        if {$type in {choice combobox dataset_selector field}} {set text [datasetPreviewGuiControlGet $host $id]}
        lappend inputs [viewerDevelopmentJsonString $text]
        if {[datasetPublicationV2DictDefault $event control_id {}] eq $id} {set selected $ordinal;set selectedComponent $component;set kind [expr {[datasetPublicationV2DictDefault $event event {}] eq {invoke}?1:2}]}
    }
    if {$selected && [dict exists $selectedComponent properties action]} {
        set action [dict get $selectedComponent properties action]
        if {$action in {fit zoom_in zoom_out}} {
            foreach component [dict get $design components] {if {[dict get $component type] eq {plot}} {datasetPreviewGuiPlotView $host [dict get $component id] $action}}
            return
        }
    }
    if {[datasetPublicationV2DictDefault $record scientific_client 0]} {
        # This is the pinned declared action, never display text. New scientific
        # clients obtain canonical pages through their admitted typed receipt;
        # legacy numeric clients retain their existing sample JSON transport.
        set data {}
        if {$kind==1 && [dict exists $selectedComponent properties action]} {
            set data [dict get $selectedComponent properties action]
            if {![dict exists $design handlers $data]} {error {Scientific Preview invoked an undeclared action}}
        }
    } else {set data [_previewCppNumericDataJson $host]}
    set generation [expr {[datasetPublicationV2DictDefault $record generation 0]+1}]
    dict set mounts $host generation $generation
    dict set mounts $host scientific_scope [list [dict get $record request] $generation]
    set contextFields [list [format {"data":%s} [viewerDevelopmentJsonString $data]] [format {"inputs":[%s]} [join $inputs ,]]]
    if {[datasetPublicationV2DictDefault $record scientific_client 0]} {lappend contextFields [format {"scientific_preview_result":%s} [_previewScientificSnapshot $host]]}
    set payload [format {{"event":%s,"state":%s,"context":{%s}}} [viewerDevelopmentEventJson [dict create kind $kind component $selected value 0.0]] [viewerDevelopmentStateJson [dict get $record state]] [join $contextFields ,]]
    dict set mounts $host busy 1
    try {
        set reply [encoding convertfrom utf-8 [binary decode base64 [scriptJobRequestExchange [dict get $record request] $payload 12000]]]
        _datasetPreviewGuiRequire $host
        if {![dict get $reply ok] || [dict get $reply result status] ne {COMPLETED}} {error {Compiled numeric Preview presentation failed}}
        set result [dict get $reply result]
        if {[dict get $result binary_sha256] ne [dict get $record binary_sha256]} {error {Compiled Preview binary identity differs}}
        _previewCppNumericApply $host [dict get $result operations]
        dict set mounts $host state [dict get $result state]
        dict set mounts $host receipt [dict create execution compiled_cpp runtime_compilation 0 source_sha256 [dict get $result source_sha256] binary_sha256 [dict get $result binary_sha256] context_dataset [dict get [datasetPreviewGuiContext $host] dataset_id] sample_only [expr {![datasetPublicationV2DictDefault $record scientific_client 0]}] bounded_page_only [datasetPublicationV2DictDefault $record scientific_client 0]]
    } on error {message options} {
        catch {_previewScientificFailed $host $message}
        return -options $options $message
    } finally {if {[dict exists $mounts $host]} {dict set mounts $host busy 0;catch {dict unset mounts $host scientific_scope}}}
}
proc ::GX::_previewCppNumericMount {module root host context design} {
    variable ::GX::PreviewCpp::mounts;variable ::GX::PreviewCpp::serial
    if {[dict get $context tab_id] ne {numeric}} {error {Numeric Preview tab identity differs}}
    set allocation [resourceManagementAllocate compiled_preview_runtime [dict create category temporary lifetime viewer retention_seconds 0]]
    dict set mounts $host [dict create allocation $allocation module $module root $root request {} design $design busy 0 state [dict create values [lrepeat 16 0.0] counter 0]]
    set variable ::GX::PreviewCpp::replies(reply[incr serial])
    try {
        set script [file join $::GX::scriptDir core python gxtxt_viewer_development.py]
        set command [list /usr/bin/python3 -I -B $script runtime_inspect $root --runtime-work [dict get $allocation path] --tcl]
        set request [scriptJobAsync $command {} [list ::GX::_previewCppReply $variable] {timeout_ms 30000 max_bytes 4194304 process_group 1 ui_lifetime 1 label {Numeric Preview admission}}]
        dict set mounts $host request $request
        vwait $variable;set reply [set $variable];unset $variable
        if {![dict get $reply ok] || [dict get $reply result status] ne {PASS}} {error {Numeric Preview package admission failed}}
        set admission [dict get $reply result];_datasetPreviewGuiRequire $host
        if {[_previewCppDesign $module $root] ne $design} {error {Numeric Preview changed during admission}}
        set command [list /usr/bin/python3 -I -B $script runtime_serve $root --runtime-work [dict get $allocation path]]
        set request [scriptJobAsync $command {} [list ::GX::_previewCppEnded $host] {duplex 1 send_pending_bytes 2097152 max_bytes 4194304 process_group 1 ui_lifetime 1 label {Compiled numeric Preview lifetime}}]
        dict set mounts $host request $request
        set ready [encoding convertfrom utf-8 [binary decode base64 [scriptJobRequestExchange $request {} 5000]]]
        if {![dict get $ready ok] || [dict get $ready result status] ne {READY} || [dict get $ready result binary_sha256] ne [dict get $admission binary_sha256]} {error {Numeric Preview worker identity differs}}
        dict set mounts $host binary_sha256 [dict get $admission binary_sha256]
        set grants [datasetPublicationV2DictDefault $admission native_client_grants {}]
        dict set mounts $host native_client_module [datasetPublicationV2DictDefault $admission native_client_module {}]
        dict set mounts $host native_client_grants $grants
        set scientific [expr {{scientific_preview_command} in [datasetPublicationV2DictDefault $grants PREVIEW_COMPONENT_GUI_API_v1 {}]}]
        dict set mounts $host scientific_client $scientific
        if {$scientific} {
            if {[dict get $admission native_client_module] ne $module} {error {Scientific Preview admitted another module}}
            dict set mounts $host scientific_package_snapshot [_viewerNativeClientPackageSnapshot $root]
        }
        viewerGuiDesignPreviewMount $design $host ::GX::_previewCppNumericEvent
        _previewCppNumericEvent $host {}
        return [dict get $mounts $host receipt]
    } on error {message options} {
        viewerDevelopmentPreviewDispose $host
        return -options $options $message
    }
}

source [file join $::GX::scriptDir core tcl viewer_scientific_preview_v1.tcl]
