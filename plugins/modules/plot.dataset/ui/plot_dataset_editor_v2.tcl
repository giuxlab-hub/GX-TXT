# Optional Tk adapter for PLOT_DATASET_API_v2::openEditor and the
# Series Editor Extension API v1 provider area.
# SPDX-License-Identifier: GPL-3.0-or-later

namespace eval ::GX::PlotDatasetAPIv2 {
    variable editor
    variable seriesPresentationEditor
    variable graphConfigEditor
}

proc ::GX::PlotDatasetAPIv2::_presentationClearValues {arrayName key} {
    upvar #0 $arrayName values
    foreach field {
        panel_id kind color line_style line_width marker marker_size marker_fill opacity
        step_mode bar_width bar_baseline histogram_bins histogram_normalization box_whisker_iqr box_show_outliers
        x_error_mode x_error_variable_id x_error_lower_variable_id x_error_upper_variable_id
        y_error_mode y_error_variable_id y_error_lower_variable_id y_error_upper_variable_id
        band_lower_variable_id band_upper_variable_id band_draw_center
        bar_lower_variable_id bar_upper_variable_id
    } {
        set values($key,$field) ""
    }
    set values($key,kind) auto
    set values($key,x_error_mode) none
    set values($key,y_error_mode) none
    set values($key,band_draw_center) 1
    set values($key,histogram_bins) auto
    set values($key,histogram_normalization) count
    set values($key,box_whisker_iqr) 1.5
    set values($key,box_show_outliers) 1
}

proc ::GX::PlotDatasetAPIv2::_presentationLoadValues {arrayName key presentation} {
    upvar #0 $arrayName values
    _presentationClearValues $arrayName $key
    set values($key,kind) [expr {[dict exists $presentation kind] ? [dict get $presentation kind] : "auto"}]
    foreach field {color line_style line_width marker marker_size marker_fill opacity} {
        if {[dict exists $presentation style $field]} { set values($key,$field) [dict get $presentation style $field] }
    }
    foreach field {step_mode bar_width bar_baseline histogram_bins histogram_normalization box_whisker_iqr box_show_outliers} {
        if {[dict exists $presentation $field]} { set values($key,$field) [dict get $presentation $field] }
    }
    foreach e {x_error y_error} {
        if {[dict exists $presentation $e]} {
            set ed [dict get $presentation $e]
            foreach field {mode variable_id lower_variable_id upper_variable_id} {
                if {[dict exists $ed $field]} { set values($key,${e}_$field) [dict get $ed $field] }
            }
        }
    }
    if {[dict exists $presentation band]} {
        set band [dict get $presentation band]
        foreach field {lower_variable_id upper_variable_id} {
            if {[dict exists $band $field]} { set values($key,band_$field) [dict get $band $field] }
        }
        if {[dict exists $band draw_center]} { set values($key,band_draw_center) [dict get $band draw_center] }
    }
    if {[dict exists $presentation bar_bounds]} {
        set bounds [dict get $presentation bar_bounds]
        foreach field {lower_variable_id upper_variable_id} {
            if {[dict exists $bounds $field]} { set values($key,bar_$field) [dict get $bounds $field] }
        }
    }
}

proc ::GX::PlotDatasetAPIv2::_presentationCollectValues {arrayName key} {
    upvar #0 $arrayName values
    set kind [string trim $values($key,kind)]
    if {$kind eq ""} { set kind auto }
    set out [dict create kind $kind]

    set style [dict create]
    foreach field {color line_style line_width marker marker_size marker_fill opacity} {
        set value [string trim $values($key,$field)]
        if {$value ne ""} { dict set style $field $value }
    }
    if {[dict size $style]} { dict set out style $style }

    foreach field {step_mode bar_width bar_baseline histogram_bins histogram_normalization box_whisker_iqr box_show_outliers} {
        set value [string trim $values($key,$field)]
        if {$value ne ""} { dict set out $field $value }
    }

    foreach e {x_error y_error} {
        set mode [string tolower [string trim $values($key,${e}_mode)]]
        if {$mode eq ""} { set mode none }
        set ed [dict create]
        if {$mode ne "none"} { dict set ed mode $mode }
        foreach field {variable_id lower_variable_id upper_variable_id} {
            set value [string trim $values($key,${e}_$field)]
            if {$value ne ""} { dict set ed $field $value }
        }
        if {[dict size $ed]} {
            if {![dict exists $ed mode]} { dict set ed mode $mode }
            dict set out $e $ed
        }
    }

    set lower [string trim $values($key,band_lower_variable_id)]
    set upper [string trim $values($key,band_upper_variable_id)]
    if {$lower ne "" || $upper ne ""} {
        dict set out band [dict create \
            lower_variable_id $lower \
            upper_variable_id $upper \
            draw_center [expr {$values($key,band_draw_center) ? 1 : 0}]]
    }
    set barLower [string trim $values($key,bar_lower_variable_id)]
    set barUpper [string trim $values($key,bar_upper_variable_id)]
    if {$barLower ne "" || $barUpper ne ""} {
        dict set out bar_bounds [dict create lower_variable_id $barLower upper_variable_id $barUpper]
    }
    if {[info exists values($key,panel_id)] && [string trim $values($key,panel_id)] ne ""} {
        dict set out __panel_id [string trim $values($key,panel_id)]
    }
    return $out
}

proc ::GX::PlotDatasetAPIv2::_presentationVariableIds {datasetId} {
    set out {}
    set datasetId [string trim $datasetId]
    if {$datasetId eq "" || [::GX::datasetField $datasetId id ""] eq ""} { return $out }
    foreach v [::GX::datasetVariableSchema $datasetId] {
        if {[dict get $v enabled]} { lappend out [dict get $v variable_id] }
    }
    return $out
}

proc ::GX::PlotDatasetAPIv2::_presentationSetVariableChoices {uncFrame datasetId} {
    set values [_presentationVariableIds $datasetId]
    foreach field {
        y_error_variable_id y_error_lower_variable_id y_error_upper_variable_id
        x_error_variable_id x_error_lower_variable_id x_error_upper_variable_id
        band_lower_variable_id band_upper_variable_id
        bar_lower_variable_id bar_upper_variable_id
    } {
        if {[winfo exists $uncFrame.e$field]} { $uncFrame.e$field configure -values $values }
    }
}

proc ::GX::PlotDatasetAPIv2::_presentationBuildDetails {styleFrame uncFrame arrayName key} {
    upvar #0 $arrayName values
    ttk::labelframe $styleFrame -text "Series style (blank = inherit, auto = automatic)"
    set sr 0
    foreach {field label choices} [list \
        color Color {} \
        line_style "Line style" {auto inherit solid dashed dotted dashdot none} \
        line_width "Line width" {} \
        marker Marker {auto inherit none circle square diamond triangle_up triangle_down plus x star} \
        marker_size "Marker size" {} \
        marker_fill "Marker fill" {auto inherit none full} \
        opacity Opacity {} \
        step_mode "Step mode" {pre post mid} \
        bar_width "Bar width" {} \
        bar_baseline "Bar baseline" {} \
        histogram_bins "Histogram bins" {} \
        histogram_normalization "Histogram normalization" {count probability density} \
        box_whisker_iqr "Box whisker IQR" {} \
        box_show_outliers "Show box outliers" {0 1}] {
        ttk::label $styleFrame.l$field -text $label
        if {[llength $choices]} {
            ttk::combobox $styleFrame.e$field -textvariable ${arrayName}($key,$field) -values $choices -width 18
        } else {
            ttk::entry $styleFrame.e$field -textvariable ${arrayName}($key,$field) -width 20
        }
        grid $styleFrame.l$field -row $sr -column 0 -sticky w -padx 3 -pady 2
        grid $styleFrame.e$field -row $sr -column 1 -sticky ew -padx 3 -pady 2
        incr sr
    }

    ttk::labelframe $uncFrame -text "Auxiliary variable IDs (same dataset)"
    set ur 0
    foreach {field label choices} [list \
        y_error_mode "Y error mode" {none symmetric asymmetric} \
        y_error_variable_id "Y error" {} \
        y_error_lower_variable_id "Y error lower" {} \
        y_error_upper_variable_id "Y error upper" {} \
        x_error_mode "X error mode" {none symmetric asymmetric} \
        x_error_variable_id "X error" {} \
        x_error_lower_variable_id "X error lower" {} \
        x_error_upper_variable_id "X error upper" {} \
        band_lower_variable_id "Band lower" {} \
        band_upper_variable_id "Band upper" {} \
        bar_lower_variable_id "Bar X lower" {} \
        bar_upper_variable_id "Bar X upper" {}] {
        ttk::label $uncFrame.l$field -text $label
        if {[llength $choices]} {
            ttk::combobox $uncFrame.e$field -textvariable ${arrayName}($key,$field) -values $choices -width 20
        } else {
            ttk::combobox $uncFrame.e$field -textvariable ${arrayName}($key,$field) -values {} -width 20
        }
        set col [expr {($ur % 2) * 2}]
        set row [expr {$ur / 2}]
        grid $uncFrame.l$field -row $row -column $col -sticky w -padx 3 -pady 2
        grid $uncFrame.e$field -row $row -column [expr {$col + 1}] -sticky ew -padx 3 -pady 2
        incr ur
    }
    set row [expr {($ur + 1) / 2}]
    ttk::checkbutton $uncFrame.drawcenter -text "Draw center series with band" -variable ${arrayName}($key,band_draw_center)
    grid $uncFrame.drawcenter -row $row -column 0 -columnspan 4 -sticky w -padx 3 -pady 2
}

# -----------------------------------------------------------------------------
# Series Editor Extension API v1 adapter
# -----------------------------------------------------------------------------

proc ::GX::PlotDatasetAPIv2::_seriesExtensionBuildGui {context} {
    variable supportedKinds
    variable seriesPresentationEditor
    set parent [dict get $context parent]
    set key $parent
    _presentationClearValues ::GX::PlotDatasetAPIv2::seriesPresentationEditor $key

    set ref [_seriesExtensionPlotRef $context]
    set seriesPresentationEditor($key,plot_ref) $ref
    ttk::labelframe $parent.panel -text "Panel assignment"
    ttk::label $parent.panel.l -text "Panel"
    ttk::combobox $parent.panel.e -textvariable ::GX::PlotDatasetAPIv2::seriesPresentationEditor($key,panel_id) \
        -values [panelIds $ref] -state readonly -width 20
    grid $parent.panel.l -row 0 -column 0 -sticky w -padx 3 -pady 2
    grid $parent.panel.e -row 0 -column 1 -sticky w -padx 3 -pady 2

    ttk::frame $parent.representation
    ttk::label $parent.representation.lkind -text "Representation"
    ttk::combobox $parent.representation.ekind \
        -textvariable ::GX::PlotDatasetAPIv2::seriesPresentationEditor($key,kind) \
        -values $supportedKinds -state readonly -width 20
    grid $parent.representation.lkind -row 0 -column 0 -sticky w -padx 3 -pady 2
    grid $parent.representation.ekind -row 0 -column 1 -sticky w -padx 3 -pady 2
    pack $parent.representation -fill x -anchor w
    if {[multiPanelEnabled $ref]} {pack $parent.panel -fill x -anchor w -pady {0 4} -before $parent.representation}

    _presentationBuildDetails $parent.style $parent.unc ::GX::PlotDatasetAPIv2::seriesPresentationEditor $key
    pack $parent.style -side left -fill both -expand 1 -padx {0 5} -pady 4
    pack $parent.unc -side left -fill both -expand 1 -padx {5 0} -pady 4
    return $parent
}

proc ::GX::PlotDatasetAPIv2::_seriesExtensionPanelRefresh {context {select ""}} {
    variable seriesPresentationEditor
    set parent [dict get $context parent]
    set key $parent
    set ref [_seriesExtensionPlotRef $context]
    set ids [panelIds $ref]
    catch {$parent.panel.e configure -values $ids}
    if {$select eq "" && [info exists seriesPresentationEditor($key,panel_id)]} {set select [string trim $seriesPresentationEditor($key,panel_id)]}
    if {[lsearch -exact $ids $select] < 0} {
        set select [expr {[llength $ids] ? [lindex $ids 0] : ""}]
    }
    set seriesPresentationEditor($key,panel_id) $select
    return $ids
}

proc ::GX::PlotDatasetAPIv2::_seriesExtensionPanelVisibility {context {knownSpec ""}} {
    set parent [dict get $context parent]
    set enabled [expr {$knownSpec ne "" ? [llength [dict get $knownSpec panels]] > 1 : [multiPanelEnabled [_seriesExtensionPlotRef $context]]}]
    if {$enabled} {
        if {![winfo ismapped $parent.panel]} {pack $parent.panel -fill x -anchor w -pady {0 4} -before $parent.representation}
    } else {
        pack forget $parent.panel
        set ::GX::PlotDatasetAPIv2::seriesPresentationEditor($parent,panel_id) ""
    }
    return $enabled
}

proc ::GX::PlotDatasetAPIv2::_seriesExtensionRefreshOpenEditors {ref} {
    variable seriesPresentationEditor
    foreach name [array names seriesPresentationEditor "*,plot_ref"] {
        set key [string range $name 0 end-9]
        if {![info exists seriesPresentationEditor($key,plot_ref)]} continue
        set other $seriesPresentationEditor($key,plot_ref)
        if {[dict get $other graph_id] ne [dict get $ref graph_id] || [dict get $other variant_id] ne [dict get $ref variant_id]} continue
        if {![winfo exists $key.panel]} continue
        set context [dict create module_id plot.dataset graph_id [dict get $ref graph_id] variant_id [dict get $ref variant_id] parent $key]
        _seriesExtensionPanelRefresh $context
        _seriesExtensionPanelVisibility $context
    }
}

proc ::GX::PlotDatasetAPIv2::_seriesExtensionLoadGui {context} {
    set parent [dict get $context parent]
    set key $parent
    set generic [dict get $context generic_series]
    set presentation [dict create kind auto]
    set datasetId ""
    set sid [dict get $context series_id]
    set panelId ""
    set spec [loadSpec [_seriesExtensionPlotRef $context] 1]
    set ids {}
    foreach panel [dict get $spec panels] {lappend ids [dict get $panel id]}
    if {$generic ne ""} { set datasetId [dict get $generic dataset_id] }
    if {$sid ne ""} {
        set ref [_seriesExtensionPlotRef $context]
        foreach panel [dict get $spec panels] {
            foreach series [dict get $panel series] {
                if {[dict get $series id] eq $sid} {
                    set presentation [_presentationFromSeries $series]
                    set panelId [dict get $panel id]
                    break
                }
            }
            if {$panelId ne ""} break
        }
    }
    _presentationLoadValues ::GX::PlotDatasetAPIv2::seriesPresentationEditor $key $presentation
    if {$panelId eq ""} {
        if {[llength $ids]} {set panelId [lindex $ids 0]}
    }
    set ::GX::PlotDatasetAPIv2::seriesPresentationEditor($key,panel_id) $panelId
    catch {$parent.panel.e configure -values $ids}
    _seriesExtensionPanelVisibility $context $spec
    _presentationSetVariableChoices $parent.unc $datasetId
    return 1
}

proc ::GX::PlotDatasetAPIv2::_seriesExtensionCollectGui {context} {
    set key [dict get $context parent]
    return [_presentationCollectValues ::GX::PlotDatasetAPIv2::seriesPresentationEditor $key]
}
proc ::GX::PlotDatasetAPIv2::_seriesExtensionCloseGui {context} {
    variable seriesPresentationEditor
    set key [dict get $context parent]
    foreach name [array names seriesPresentationEditor "$key,*"] { unset seriesPresentationEditor($name) }
    return 1
}

# -----------------------------------------------------------------------------
# Graph Configuration Extension API v1 adapter
# -----------------------------------------------------------------------------

proc ::GX::PlotDatasetAPIv2::_sharedXAxisScale {ref} {
    return [string totitle [dict get [sharedXAxisGet $ref] scale]]
}

proc ::GX::PlotDatasetAPIv2::_sharedXAxisGrid {ref} {
    set values [sharedXAxisGet $ref]
    return [list [dict get $values major_step] [string totitle [dict get $values minor_grid]]]
}

proc ::GX::PlotDatasetAPIv2::_sharedXAxisApply {ref selected {majorStep __keep__} {minorGrid __keep__}} {
    set fields [dict create scale [string tolower $selected]]
    if {$majorStep ne "__keep__"} {dict set fields major_step $majorStep}
    if {$minorGrid ne "__keep__"} {dict set fields minor_grid [string tolower $minorGrid]}
    sharedXAxisSet $ref $fields
    return 1
}

proc ::GX::PlotDatasetAPIv2::_graphConfigError {context message} {
    if {[llength [info commands tk_messageBox]]} {tk_messageBox -parent [winfo toplevel [dict get $context parent]] -icon error -type ok -message $message}
    return 0
}

proc ::GX::PlotDatasetAPIv2::_graphConfigClearAxisValues {key prefix} {
    variable graphConfigEditor
    foreach field {label display_unit min max} {set graphConfigEditor($key,${prefix}_$field) ""}
    set graphConfigEditor($key,${prefix}_scale) auto
}

proc ::GX::PlotDatasetAPIv2::_graphConfigLoadPanel {context} {
    variable graphConfigEditor
    set parent [dict get $context parent]; set key $parent; set ref [_graphConfigPlotRef $context]
    set panelId [string trim $graphConfigEditor($key,panel_id)]
    _graphConfigClearAxisValues $key yl; _graphConfigClearAxisValues $key yr
    set graphConfigEditor($key,panel_title) ""
    if {$panelId eq ""} {return}
    set panel [panelInfo $ref $panelId]
    if {[dict exists $panel title]} {set graphConfigEditor($key,panel_title) [dict get $panel title]}
    foreach {axis prefix} {y_left yl y_right yr} {
        if {![dict exists $panel axes $axis]} continue
        set a [dict get $panel axes $axis]
        foreach field {label display_unit scale min max} {if {[dict exists $a $field]} {set graphConfigEditor($key,${prefix}_$field) [dict get $a $field]}}
    }
}

proc ::GX::PlotDatasetAPIv2::_graphConfigRefresh {context {select ""}} {
    variable graphConfigEditor
    set parent [dict get $context parent]; set key $parent; set ref [_graphConfigPlotRef $context]
    set graphConfigEditor($key,multi_panel) [multiPanelEnabled $ref]
    set graphConfigEditor($key,x_scale) [_sharedXAxisScale $ref]
    lassign [_sharedXAxisGrid $ref] graphConfigEditor($key,x_major_step) graphConfigEditor($key,x_minor_grid)
    set ids [panelIds $ref]
    $parent.panels.select configure -values $ids
    if {$select eq "" && [info exists graphConfigEditor($key,panel_id)]} {set select $graphConfigEditor($key,panel_id)}
    if {[lsearch -exact $ids $select] < 0} {
        set select [expr {[llength $ids] ? [lindex $ids 0] : ""}]
    }
    set graphConfigEditor($key,panel_id) $select
    _graphConfigLoadPanel $context
    _graphConfigLoadSingleAxis $context
    _graphConfigVisibility $context
}

proc ::GX::PlotDatasetAPIv2::_graphConfigLoadSingleAxis {context} {
    variable graphConfigEditor
    set key [dict get $context parent]; set ref [_graphConfigPlotRef $context]
    set spec [loadSpec $ref 1]
    set panels [dict get $spec panels]
    foreach {axis prefix} {y_left single_yl y_right single_yr} {
        set value auto
        if {[llength $panels] && [dict exists [lindex $panels 0] axes $axis scale]} {
            set value [dict get [lindex $panels 0] axes $axis scale]
        }
        set graphConfigEditor($key,${prefix}_scale) $value
    }
    set right 0
    if {[llength $panels]} {
        foreach series [dict get [lindex $panels 0] series] {
            if {[dict exists $series axis] && [dict get $series axis] eq "right"} {set right 1; break}
        }
    }
    [dict get $context parent].single_axes.right configure -state [expr {$right ? "readonly" : "disabled"}]
}

proc ::GX::PlotDatasetAPIv2::_graphConfigSingleAxisApply {context} {
    variable graphConfigEditor
    set key [dict get $context parent]; set ref [_graphConfigPlotRef $context]
    if {[multiPanelEnabled $ref]} {return [_graphConfigError $context "Use per-panel Y scales while Multi-panel is enabled."]}
    set ids [panelIds $ref]
    if {![llength $ids]} {return [_graphConfigError $context "No panel is available."]}
    set panelId [lindex $ids 0]
    foreach {axis prefix} {y_left single_yl y_right single_yr} {
        set scale [string tolower [string trim $graphConfigEditor($key,${prefix}_scale)]]
        if {$scale ni {auto linear log}} {return [_graphConfigError $context "Y scale must be Auto, Linear, or Log."]}
        set panel [panelInfo $ref $panelId]
        set fields [expr {[dict exists $panel axes $axis] ? [dict get $panel axes $axis] : [dict create]}]
        if {$scale eq "auto"} {catch {dict unset fields scale}} else {dict set fields scale $scale}
        if {[catch {setPanelAxis $ref $panelId $axis $fields} err]} {return [_graphConfigError $context $err]}
    }
    _graphConfigRefresh $context $panelId
    return 1
}

proc ::GX::PlotDatasetAPIv2::_graphConfigVisibility {context} {
    variable graphConfigEditor
    set parent [dict get $context parent]; set key $parent
    if {$graphConfigEditor($key,multi_panel)} {
        if {![winfo ismapped $parent.panels]} {pack $parent.panels -fill x -expand 1 -pady {5 0}}
    } else {
        pack forget $parent.panels
    }
    if {$graphConfigEditor($key,multi_panel)} {pack forget $parent.single_axes
    } elseif {![winfo ismapped $parent.single_axes]} {pack $parent.single_axes -fill x -pady {0 4} -after $parent.enable}
}

proc ::GX::PlotDatasetAPIv2::_graphConfigToggle {context} {
    variable graphConfigEditor
    set parent [dict get $context parent]; set key $parent; set ref [_graphConfigPlotRef $context]
    if {[catch {setMultiPanel $ref $graphConfigEditor($key,multi_panel)} err]} {
        set graphConfigEditor($key,multi_panel) [multiPanelEnabled $ref]
        return [_graphConfigError $context $err]
    }
    _graphConfigVisibility $context
    _seriesExtensionRefreshOpenEditors $ref
    return 1
}

proc ::GX::PlotDatasetAPIv2::_graphConfigPanelSelect {context} {_graphConfigLoadPanel $context}

proc ::GX::PlotDatasetAPIv2::_graphConfigXAxisApply {context} {
    variable graphConfigEditor
    set key [dict get $context parent]
    if {[catch {_sharedXAxisApply [_graphConfigPlotRef $context] $graphConfigEditor($key,x_scale) \
        $graphConfigEditor($key,x_major_step) $graphConfigEditor($key,x_minor_grid)} err]} {
        return [_graphConfigError $context $err]
    }
    return 1
}

proc ::GX::PlotDatasetAPIv2::_graphConfigPanelAdd {context} {
    variable graphConfigEditor
    set parent [dict get $context parent]; set key $parent; set ref [_graphConfigPlotRef $context]
    set panelId [string trim $graphConfigEditor($key,new_panel_id)]
    if {$panelId eq ""} {return [_graphConfigError $context "Enter a panel ID first."]}
    if {[catch {addPanel $ref $panelId} err]} {return [_graphConfigError $context $err]}
    set graphConfigEditor($key,new_panel_id) ""; set graphConfigEditor($key,multi_panel) 1
    _graphConfigRefresh $context $panelId; _seriesExtensionRefreshOpenEditors $ref; return 1
}

proc ::GX::PlotDatasetAPIv2::_graphConfigPanelRemove {context} {
    variable graphConfigEditor
    set parent [dict get $context parent]; set key $parent; set ref [_graphConfigPlotRef $context]
    set panelId [string trim $graphConfigEditor($key,panel_id)]
    if {$panelId eq ""} {return [_graphConfigError $context "Select a panel first."]}
    set before [panelIds $ref]; set idx [lsearch -exact $before $panelId]
    if {[catch {removePanel $ref $panelId} err]} {return [_graphConfigError $context $err]}
    set after [panelIds $ref]; if {$idx >= [llength $after]} {set idx [expr {[llength $after]-1}]}
    set next [expr {[llength $after] ? [lindex $after [expr {max(0,$idx)}]] : ""}]
    _graphConfigRefresh $context $next; _seriesExtensionRefreshOpenEditors $ref; return 1
}

proc ::GX::PlotDatasetAPIv2::_graphConfigPanelMove {context delta} {
    variable graphConfigEditor
    set parent [dict get $context parent]; set key $parent; set ref [_graphConfigPlotRef $context]
    set panelId [string trim $graphConfigEditor($key,panel_id)]
    if {$panelId eq ""} {return [_graphConfigError $context "Select a panel first."]}
    if {[catch {movePanel $ref $panelId $delta} err]} {return [_graphConfigError $context $err]}
    _graphConfigRefresh $context $panelId; return 1
}

proc ::GX::PlotDatasetAPIv2::_graphConfigAxisDict {key prefix} {
    variable graphConfigEditor
    set out [dict create]
    foreach field {label display_unit scale min max} {
        set value [string trim $graphConfigEditor($key,${prefix}_$field)]
        if {$value ne "" && !($field eq "scale" && [string equal -nocase $value auto])} {dict set out $field $value}
    }
    return $out
}

proc ::GX::PlotDatasetAPIv2::_graphConfigPanelApply {context} {
    variable graphConfigEditor
    set parent [dict get $context parent]; set key $parent; set ref [_graphConfigPlotRef $context]
    set panelId [string trim $graphConfigEditor($key,panel_id)]
    if {$panelId eq ""} {return [_graphConfigError $context "Select a panel first."]}
    if {[catch {
        setPanelTitle $ref $panelId $graphConfigEditor($key,panel_title)
        setPanelAxis $ref $panelId y_left [_graphConfigAxisDict $key yl]
        setPanelAxis $ref $panelId y_right [_graphConfigAxisDict $key yr]
    } err]} {return [_graphConfigError $context $err]}
    _graphConfigRefresh $context $panelId; return 1
}

proc ::GX::PlotDatasetAPIv2::_graphConfigBuildAxisFrame {frame title arrayName key prefix} {
    ttk::labelframe $frame -text $title
    set row 0
    foreach {field label} {label Label display_unit "Display unit" scale Scale min Min max Max} {
        ttk::label $frame.l$field -text $label
        if {$field eq "scale"} {
            ttk::combobox $frame.e$field -textvariable ${arrayName}($key,${prefix}_$field) -values {auto linear log} -state readonly -width 16
        } else {
            ttk::entry $frame.e$field -textvariable ${arrayName}($key,${prefix}_$field) -width 18
        }
        grid $frame.l$field -row $row -column 0 -sticky w -padx 3 -pady 2
        grid $frame.e$field -row $row -column 1 -sticky ew -padx 3 -pady 2
        incr row
    }
}

proc ::GX::PlotDatasetAPIv2::_graphConfigBuildGui {context} {
    variable graphConfigEditor
    set parent [dict get $context parent]; set key $parent; set ref [_graphConfigPlotRef $context]
    set graphConfigEditor($key,new_panel_id) ""; set graphConfigEditor($key,panel_id) ""; set graphConfigEditor($key,panel_title) ""
    _graphConfigClearAxisValues $key yl; _graphConfigClearAxisValues $key yr
    set graphConfigEditor($key,multi_panel) [multiPanelEnabled $ref]

    ttk::checkbutton $parent.enable -text "Multi-panel (vertically stacked, shared X)" \
        -variable ::GX::PlotDatasetAPIv2::graphConfigEditor($key,multi_panel) \
        -command [list ::GX::PlotDatasetAPIv2::_graphConfigToggle $context]
    pack $parent.enable -anchor w -pady {0 4}

    ttk::labelframe $parent.single_axes -text "Single-panel Y scales"
    ttk::label $parent.single_axes.ll -text "Y Left scale"
    ttk::combobox $parent.single_axes.left -textvariable ::GX::PlotDatasetAPIv2::graphConfigEditor($key,single_yl_scale) -values {auto linear log} -state readonly -width 12
    ttk::label $parent.single_axes.rl -text "Y Right scale"
    ttk::combobox $parent.single_axes.right -textvariable ::GX::PlotDatasetAPIv2::graphConfigEditor($key,single_yr_scale) -values {auto linear log} -state readonly -width 12
    ttk::button $parent.single_axes.apply -text "Apply Y scales" -command [list ::GX::PlotDatasetAPIv2::_graphConfigSingleAxisApply $context]
    pack $parent.single_axes.ll $parent.single_axes.left $parent.single_axes.rl $parent.single_axes.right $parent.single_axes.apply -side left -padx 3 -pady 4
    pack $parent.single_axes -fill x -pady {0 4}

    ttk::labelframe $parent.panels -text "Panels"
    ttk::label $parent.panels.lsel -text "Panel"
    ttk::combobox $parent.panels.select -textvariable ::GX::PlotDatasetAPIv2::graphConfigEditor($key,panel_id) -state readonly -width 18
    bind $parent.panels.select <<ComboboxSelected>> [list ::GX::PlotDatasetAPIv2::_graphConfigPanelSelect $context]
    ttk::label $parent.panels.lnew -text "New panel ID"
    ttk::entry $parent.panels.new -textvariable ::GX::PlotDatasetAPIv2::graphConfigEditor($key,new_panel_id) -width 16
    ttk::button $parent.panels.add -text "Add" -command [list ::GX::PlotDatasetAPIv2::_graphConfigPanelAdd $context]
    ttk::button $parent.panels.remove -text "Remove" -command [list ::GX::PlotDatasetAPIv2::_graphConfigPanelRemove $context]
    ttk::button $parent.panels.up -text "Up" -command [list ::GX::PlotDatasetAPIv2::_graphConfigPanelMove $context -1]
    ttk::button $parent.panels.down -text "Down" -command [list ::GX::PlotDatasetAPIv2::_graphConfigPanelMove $context 1]
    grid $parent.panels.lsel -row 0 -column 0 -sticky w -padx 3 -pady 2
    grid $parent.panels.select -row 0 -column 1 -sticky w -padx 3 -pady 2
    grid $parent.panels.lnew -row 0 -column 2 -sticky w -padx {12 3} -pady 2
    grid $parent.panels.new -row 0 -column 3 -sticky w -padx 3 -pady 2
    grid $parent.panels.add -row 0 -column 4 -padx 2; grid $parent.panels.remove -row 0 -column 5 -padx 2
    grid $parent.panels.up -row 0 -column 6 -padx 2; grid $parent.panels.down -row 0 -column 7 -padx 2

    ttk::label $parent.panels.lt -text "Panel title (blank = none, auto = panel ID)"
    ttk::entry $parent.panels.title -textvariable ::GX::PlotDatasetAPIv2::graphConfigEditor($key,panel_title) -width 42
    grid $parent.panels.lt -row 1 -column 0 -columnspan 2 -sticky w -padx 3 -pady {6 2}
    grid $parent.panels.title -row 1 -column 2 -columnspan 6 -sticky ew -padx 3 -pady {6 2}

    ttk::frame $parent.panels.axes
    _graphConfigBuildAxisFrame $parent.panels.axes.left "Y Left" ::GX::PlotDatasetAPIv2::graphConfigEditor $key yl
    _graphConfigBuildAxisFrame $parent.panels.axes.right "Y Right" ::GX::PlotDatasetAPIv2::graphConfigEditor $key yr
    pack $parent.panels.axes.left $parent.panels.axes.right -side left -fill both -expand 1 -padx 4 -pady 4
    grid $parent.panels.axes -row 2 -column 0 -columnspan 8 -sticky ew -padx 2 -pady 2
    ttk::button $parent.panels.apply -text "Apply panel settings" -command [list ::GX::PlotDatasetAPIv2::_graphConfigPanelApply $context]
    grid $parent.panels.apply -row 3 -column 0 -columnspan 8 -sticky e -padx 3 -pady 4
    ttk::label $parent.panels.note -text "Panel membership is presentation state only. All panels share the graph-wide X domain; explicit CORE Axes settings remain authoritative for overlapping unit/range controls." -wraplength 680 -justify left
    grid $parent.panels.note -row 4 -column 0 -columnspan 8 -sticky ew -padx 3 -pady {2 4}
    grid columnconfigure $parent.panels 7 -weight 1
    pack $parent.panels -fill x -expand 1 -pady {5 0}
    _graphConfigRefresh $context
    return $parent
}

proc ::GX::PlotDatasetAPIv2::_graphConfigCloseGui {context} {
    variable graphConfigEditor
    set key [dict get $context parent]
    foreach name [array names graphConfigEditor "$key,*"] {unset graphConfigEditor($name)}
    return 1
}

# -----------------------------------------------------------------------------
# Shared Axes dialog extension for plot.dataset multi-panel presentation
# -----------------------------------------------------------------------------
proc ::GX::PlotDatasetAPIv2::_axisConfigRef {context} {
    set ref [plotRefForArtifact [dict get $context artifact_path]]
    if {$ref eq ""} {_error "selected artifact is not owned by plot.dataset"}
    return $ref
}

proc ::GX::PlotDatasetAPIv2::_axisConfigClearValues {key prefix} {
    variable axisConfigEditor
    foreach field {label display_unit scale} {set axisConfigEditor($key,${prefix}_$field) ""}
    set axisConfigEditor($key,${prefix}_scale) auto
}

proc ::GX::PlotDatasetAPIv2::_axisConfigLoadPanel {context} {
    variable axisConfigEditor
    set key [dict get $context parent]; set ref [_axisConfigRef $context]
    set pid [string trim $axisConfigEditor($key,panel_id)]
    if {$pid eq ""} {return}
    set p [panelInfo $ref $pid]
    set axisConfigEditor($key,panel_title) [expr {[dict exists $p title] ? [dict get $p title] : ""}]
    foreach {axis prefix} {y_left yl y_right yr} {
        _axisConfigClearValues $key $prefix
        if {[dict exists $p axes $axis]} {
            set a [dict get $p axes $axis]
            foreach field {label display_unit scale} {
                if {[dict exists $a $field]} {set axisConfigEditor($key,${prefix}_$field) [dict get $a $field]}
            }
        }
        if {[string trim $axisConfigEditor($key,${prefix}_scale)] eq ""} {set axisConfigEditor($key,${prefix}_scale) auto}
    }
}

proc ::GX::PlotDatasetAPIv2::_axisConfigPanelSelect {context} {_axisConfigLoadPanel $context}

proc ::GX::PlotDatasetAPIv2::_axisConfigMergedAxis {panel axis key prefix} {
    variable axisConfigEditor
    set out [dict create]
    if {[dict exists $panel axes $axis]} {set out [dict get $panel axes $axis]}
    foreach field {label display_unit scale} {
        set value [string trim $axisConfigEditor($key,${prefix}_$field)]
        if {$field eq "scale" && [string equal -nocase $value auto]} {set value ""}
        if {$value eq ""} {catch {dict unset out $field}} else {dict set out $field $value}
    }
    return $out
}

proc ::GX::PlotDatasetAPIv2::_axisConfigApply {context} {
    variable axisConfigEditor
    set parent [dict get $context parent]; set key $parent; set ref [_axisConfigRef $context]
    set pid [string trim $axisConfigEditor($key,panel_id)]
    if {$pid eq ""} {return [tk_messageBox -parent [winfo toplevel $parent] -icon error -message "Select a panel first."]}
    if {[catch {
        set p [panelInfo $ref $pid]
        setPanelTitle $ref $pid $axisConfigEditor($key,panel_title)
        setPanelAxis $ref $pid y_left [_axisConfigMergedAxis $p y_left $key yl]
        set p [panelInfo $ref $pid]
        setPanelAxis $ref $pid y_right [_axisConfigMergedAxis $p y_right $key yr]
    } err]} {
        tk_messageBox -parent [winfo toplevel $parent] -icon error -message $err
        return 0
    }
    _axisConfigLoadPanel $context
    return 1
}

proc ::GX::PlotDatasetAPIv2::_axisConfigAxisFrame {frame title key prefix} {
    variable axisConfigEditor
    ttk::labelframe $frame -text $title
    foreach {row field label} {0 label Label 1 display_unit "Display unit" 2 scale Scale} {
        ttk::label $frame.l$field -text $label
        if {$field eq "scale"} {
            ttk::combobox $frame.e$field -textvariable ::GX::PlotDatasetAPIv2::axisConfigEditor($key,${prefix}_$field) -values {auto linear log} -state readonly -width 17
        } else {
            ttk::entry $frame.e$field -textvariable ::GX::PlotDatasetAPIv2::axisConfigEditor($key,${prefix}_$field) -width 21
        }
        grid $frame.l$field -row $row -column 0 -sticky w -padx 3 -pady 2
        grid $frame.e$field -row $row -column 1 -sticky ew -padx 3 -pady 2
    }
}

proc ::GX::PlotDatasetAPIv2::_axisConfigBuildGui {context} {
    variable axisConfigEditor
    set parent [dict get $context parent]; set key $parent; set ref [_axisConfigRef $context]
    set pids [panelIds $ref]
    set axisConfigEditor($key,panel_id) [lindex $pids 0]
    set axisConfigEditor($key,panel_title) ""
    set axisConfigEditor($key,x_scale) [_sharedXAxisScale $ref]
    lassign [_sharedXAxisGrid $ref] axisConfigEditor($key,x_major_step) axisConfigEditor($key,x_minor_grid)
    _axisConfigClearValues $key yl; _axisConfigClearValues $key yr

    ttk::label $parent.psl -text "Panel"
    ttk::combobox $parent.panel -textvariable ::GX::PlotDatasetAPIv2::axisConfigEditor($key,panel_id) -values $pids -state readonly -width 20
    bind $parent.panel <<ComboboxSelected>> [list ::GX::PlotDatasetAPIv2::_axisConfigPanelSelect $context]
    ttk::label $parent.tl -text "Panel title"
    ttk::entry $parent.title -textvariable ::GX::PlotDatasetAPIv2::axisConfigEditor($key,panel_title) -width 42
    grid $parent.psl -row 0 -column 0 -sticky e -padx 3 -pady 3
    grid $parent.panel -row 0 -column 1 -sticky w -padx 3 -pady 3
    grid $parent.tl -row 0 -column 2 -sticky e -padx 8 -pady 3
    grid $parent.title -row 0 -column 3 -sticky ew -padx 3 -pady 3

    ttk::frame $parent.axes
    _axisConfigAxisFrame $parent.axes.left "Y Left presentation" $key yl
    _axisConfigAxisFrame $parent.axes.right "Y Right presentation" $key yr
    pack $parent.axes.left $parent.axes.right -side left -fill both -expand 1 -padx 4 -pady 3
    grid $parent.axes -row 3 -column 0 -columnspan 4 -sticky ew
    ttk::button $parent.apply -text "Apply plot.dataset panel presentation" -command [list ::GX::PlotDatasetAPIv2::_axisConfigApply $context]
    grid $parent.apply -row 4 -column 0 -columnspan 4 -sticky e -padx 3 -pady 4
    ttk::label $parent.note -text "These are PlotSpec presentation fields. CORE Multi-panel axes above remain authoritative for Y/Y2 numeric range, tick format and grid overrides." -wraplength 880 -justify left -foreground #555555
    grid $parent.note -row 4 -column 0 -columnspan 4 -sticky ew -padx 3 -pady {2 4}
    grid columnconfigure $parent 3 -weight 1
    _axisConfigLoadPanel $context
    return $parent
}

proc ::GX::PlotDatasetAPIv2::_axisConfigCloseGui {context} {
    variable axisConfigEditor
    set key [dict get $context parent]
    foreach name [array names axisConfigEditor "$key,*"] {unset axisConfigEditor($name)}
    return 1
}

# -----------------------------------------------------------------------------
# Standalone PlotSpec v2 editor
# -----------------------------------------------------------------------------
proc ::GX::PlotDatasetAPIv2::_openEditorGui {plotRef} {
    _requireFramework
    if {![llength [info commands toplevel]]} {_error "Tk is unavailable"}
    set ref [_normalizePlotRef $plotRef]
    set w .plotdatasetv2series
    catch {destroy $w}; toplevel $w
    wm title $w "PlotSpec v2 Series — [dict get $ref graph_id][expr {[dict get $ref variant_id] eq "" ? "" : "/[dict get $ref variant_id]"}]"
    ttk::button $w.close -text Close -command [list destroy $w]
    pack $w.close -side bottom -anchor e -padx 8 -pady 8
    ttk::frame $w.viewport
    pack $w.viewport -fill both -expand 1 -padx 8 -pady 8
    canvas $w.viewport.canvas -highlightthickness 0
    ttk::scrollbar $w.viewport.vscroll -orient vertical -command [list $w.viewport.canvas yview]
    ttk::scrollbar $w.viewport.hscroll -orient horizontal -command [list $w.viewport.canvas xview]
    $w.viewport.canvas configure -yscrollcommand [list $w.viewport.vscroll set] -xscrollcommand [list $w.viewport.hscroll set]
    grid $w.viewport.canvas -row 0 -column 0 -sticky nsew
    grid $w.viewport.vscroll -row 0 -column 1 -sticky ns
    grid $w.viewport.hscroll -row 1 -column 0 -sticky ew
    grid rowconfigure $w.viewport 0 -weight 1
    grid columnconfigure $w.viewport 0 -weight 1
    ttk::frame $w.viewport.canvas.body
    $w.viewport.canvas create window 0 0 -anchor nw -window $w.viewport.canvas.body
    bind $w.viewport.canvas.body <Configure> [list $w.viewport.canvas configure -scrollregion [list 0 0 %w %h]]
    _editorBuild $w.viewport.canvas.body $ref
    update idletasks
    set width [expr {min([winfo reqwidth $w.viewport.canvas.body] + 55, [winfo screenwidth $w] - 80)}]
    set height [expr {min([winfo reqheight $w.viewport.canvas.body] + 75, [winfo screenheight $w] - 80)}]
    wm geometry $w ${width}x${height}
    return $w
}


proc ::GX::PlotDatasetAPIv2::_editorBuild {f ref} {
    variable supportedKinds
    variable editor

    set editor($f,panel_id) ""

    ttk::treeview $f.tree -columns {panel id enabled dataset x y axis kind label} -show headings -height 8
    foreach c {panel id enabled dataset x y axis kind label} {$f.tree heading $c -text [string totitle $c]; $f.tree column $c -width [expr {$c eq "label" ? 130 : 82}]}
    ttk::scrollbar $f.treeY -orient vertical -command [list $f.tree yview]
    $f.tree configure -yscrollcommand [list $f.treeY set]
    grid $f.tree -row 0 -column 0 -columnspan 6 -sticky nsew -pady 4
    grid $f.treeY -row 0 -column 6 -sticky ns -pady 4
    grid columnconfigure $f 1 -weight 1; grid rowconfigure $f 0 -weight 1

    foreach {field label} {panel_id Panel id ID dataset_id Dataset x_variable_id X y_variable_id Y axis Axis kind Kind label Label} {
        ttk::label $f.l$field -text $label
        if {$field eq "panel_id"} {ttk::combobox $f.e$field -textvariable ::GX::PlotDatasetAPIv2::editor($f,$field) -values {} -state readonly -width 25
        } elseif {$field eq "dataset_id"} {ttk::combobox $f.e$field -textvariable ::GX::PlotDatasetAPIv2::editor($f,$field) -values [::GX::datasetRegistryIds] -state readonly -width 42
        } elseif {$field in {x_variable_id y_variable_id}} {ttk::combobox $f.e$field -textvariable ::GX::PlotDatasetAPIv2::editor($f,$field) -values {} -state readonly -width 25
        } elseif {$field eq "axis"} {ttk::combobox $f.e$field -textvariable ::GX::PlotDatasetAPIv2::editor($f,$field) -values {left right} -state readonly -width 25
        } elseif {$field eq "kind"} {ttk::combobox $f.e$field -textvariable ::GX::PlotDatasetAPIv2::editor($f,$field) -values $supportedKinds -state readonly -width 25
        } else {ttk::entry $f.e$field -textvariable ::GX::PlotDatasetAPIv2::editor($f,$field) -width 27}
    }
    set r 1; foreach field {panel_id id dataset_id x_variable_id y_variable_id axis kind label} {grid $f.l$field -row $r -column 0 -sticky w -padx 3; grid $f.e$field -row $r -column 1 -sticky ew -padx 3; incr r}
    set editor($f,enabled) 1; ttk::checkbutton $f.enabled -text Enabled -variable ::GX::PlotDatasetAPIv2::editor($f,enabled); grid $f.enabled -row $r -column 0 -columnspan 2 -sticky w; incr r

    _presentationClearValues ::GX::PlotDatasetAPIv2::editor $f
    set editor($f,kind) auto
    _presentationBuildDetails $f.style $f.unc ::GX::PlotDatasetAPIv2::editor $f
    grid $f.style -row 1 -column 2 -rowspan 9 -columnspan 4 -sticky nsew -padx 10
    grid $f.unc -row $r -column 0 -columnspan 6 -sticky ew -pady 8

    set r [expr {$r + 6}]
    ttk::button $f.save -text "Add/update series" -command [list ::GX::PlotDatasetAPIv2::_editorSave $f $ref]
    ttk::button $f.remove -text "Remove selected series" -command [list ::GX::PlotDatasetAPIv2::_editorRemove $f $ref]
    ttk::button $f.up -text Up -command [list ::GX::PlotDatasetAPIv2::_editorMove $f $ref -1]
    ttk::button $f.down -text Down -command [list ::GX::PlotDatasetAPIv2::_editorMove $f $ref 1]
    grid $f.save -row $r -column 0 -sticky w; grid $f.remove -row $r -column 1 -sticky w; grid $f.up -row $r -column 2; grid $f.down -row $r -column 3
    bind $f.edataset_id <<ComboboxSelected>> [list ::GX::PlotDatasetAPIv2::_editorDatasetChanged $f]
    bind $f.tree <<TreeviewSelect>> [list ::GX::PlotDatasetAPIv2::_editorLoad $f $ref]
    _editorRefresh $f $ref
}
proc ::GX::PlotDatasetAPIv2::_editorDatasetChanged {f} {
    variable editor
    set ds [string trim $editor($f,dataset_id)]
    set vals [_presentationVariableIds $ds]
    foreach field {x_variable_id y_variable_id} { catch {$f.e$field configure -values $vals} }
    _presentationSetVariableChoices $f.unc $ds
}


proc ::GX::PlotDatasetAPIv2::_editorRefresh {f ref} {
    variable editor
    foreach x [$f.tree children {}] {$f.tree delete $x}
    set spec [loadSpec $ref 1]
    set pids {}
    foreach p [dict get $spec panels] {
        set pid [dict get $p id]; lappend pids $pid
        foreach s [dict get $p series] {
            set id [dict get $s id]
            $f.tree insert {} end -id $id -values [list $pid $id [expr {[dict exists $s enabled] ? [dict get $s enabled] : 1}] [dict get $s dataset_id] [dict get $s x_variable_id] [dict get $s y_variable_id] [dict get $s axis] [expr {[dict exists $s kind] ? [dict get $s kind] : "auto"}] [expr {[dict exists $s label] ? [dict get $s label] : ""}]]
        }
    }
    catch {$f.epanel_id configure -values $pids}
    if {$editor($f,panel_id) eq "" || [lsearch -exact $pids $editor($f,panel_id)] < 0} {set editor($f,panel_id) [lindex $pids 0]}
    if {[multiPanelEnabled $ref]} {
        catch {grid $f.lpanel_id}; catch {grid $f.epanel_id}
    } else {
        catch {grid remove $f.lpanel_id}; catch {grid remove $f.epanel_id}
    }
}

proc ::GX::PlotDatasetAPIv2::_editorLoad {f ref} {
    variable editor
    set sel [$f.tree selection]; if {[llength $sel] != 1} return; set sid [lindex $sel 0]
    set spec [loadSpec $ref 1]; set s {}; set pid ""
    foreach p [dict get $spec panels] {
        foreach q [dict get $p series] {if {[dict get $q id] eq $sid} {set s $q;set pid [dict get $p id];break}}
        if {$s ne ""} break
    }
    if {$s eq ""} return
    set editor($f,panel_id) $pid
    foreach field {id dataset_id x_variable_id y_variable_id axis label enabled} {set editor($f,$field) [expr {[dict exists $s $field] ? [dict get $s $field] : ""}]}
    _presentationLoadValues ::GX::PlotDatasetAPIv2::editor $f [_presentationFromSeries $s]
    set editor($f,panel_id) $pid
    _editorDatasetChanged $f
}

proc ::GX::PlotDatasetAPIv2::_editorSave {f ref} {
    variable editor
    if {[catch {
        set spec [loadSpec $ref 1]; set panels [dict get $spec panels]
        set sid [string trim $editor($f,id)]; _validId $sid "series ID"
        if {[multiPanelEnabled $ref]} {
            set pid [string trim $editor($f,panel_id)]; if {$pid eq ""} {_error "select a panel"}
        } else {
            set pid [dict get [lindex [dict get $spec panels] 0] id]
        }
        set s [dict create id $sid dataset_id [string trim $editor($f,dataset_id)] x_variable_id [string trim $editor($f,x_variable_id)] y_variable_id [string trim $editor($f,y_variable_id)] axis [string trim $editor($f,axis)] label [string trim $editor($f,label)] enabled $editor($f,enabled)]
        set presentation [_presentationCollectValues ::GX::PlotDatasetAPIv2::editor $f]
        if {[dict exists $presentation __panel_id]} {dict unset presentation __panel_id}
        dict for {field value} $presentation { dict set s $field $value }

        # Remove any previous occurrence, then append to the selected panel.
        set out {}; set target -1; set pi 0
        foreach p $panels {
            set ss {}; foreach q [dict get $p series] {if {[dict get $q id] ne $sid} {lappend ss $q}}
            dict set p series $ss
            if {[dict get $p id] eq $pid} {set target $pi}
            lappend out $p; incr pi
        }
        if {$target < 0} {_error "unknown panel '$pid'"}
        set p [lindex $out $target]; set ss [dict get $p series]; lappend ss $s; dict set p series $ss; lset out $target $p
        dict set spec panels $out; applySpec $ref $spec
    } err]} {tk_messageBox -parent [winfo toplevel $f] -icon error -message $err; return}
    _editorRefresh $f $ref; $f.tree selection set $sid
}

proc ::GX::PlotDatasetAPIv2::_editorRemove {f ref} {
    set sel [$f.tree selection]; if {[llength $sel] != 1} return; set sid [lindex $sel 0]
    set spec [loadSpec $ref 1]; set panels {}; set total 0
    foreach p [dict get $spec panels] {
        set ss {}; foreach s [dict get $p series] {if {[dict get $s id] ne $sid} {lappend ss $s;incr total}}
        dict set p series $ss; lappend panels $p
    }
    if {$total==0} {tk_messageBox -parent [winfo toplevel $f] -icon error -message "PlotSpec requires at least one series"; return}
    dict set spec panels $panels; applySpec $ref $spec; _editorRefresh $f $ref
}

proc ::GX::PlotDatasetAPIv2::_editorMove {f ref delta} {
    set sel [$f.tree selection]; if {[llength $sel] != 1} return; set sid [lindex $sel 0]
    set spec [loadSpec $ref 1]; set panels [dict get $spec panels]; set pi 0; set foundPi -1; set idx -1
    foreach p $panels {
        set i 0; foreach s [dict get $p series] {if {[dict get $s id] eq $sid} {set foundPi $pi;set idx $i;break};incr i}
        if {$foundPi>=0} break
        incr pi
    }
    if {$foundPi<0} return
    set p [lindex $panels $foundPi]; set ss [dict get $p series]; set j [expr {$idx+$delta}]; if {$j < 0 || $j >= [llength $ss]} return
    set a [lindex $ss $idx]; set b [lindex $ss $j]; lset ss $idx $b; lset ss $j $a
    dict set p series $ss; lset panels $foundPi $p; dict set spec panels $panels; applySpec $ref $spec; _editorRefresh $f $ref; $f.tree selection set $sid
}
