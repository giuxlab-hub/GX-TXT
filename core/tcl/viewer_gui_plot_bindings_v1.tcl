# SPDX-License-Identifier: GPL-3.0-or-later
# Canonical Dataset selection delegates all rendering and units to Plot v4.
source [file join [file dirname [info script]] viewer_gui_plot_series_v1.tcl]
proc ::GX::_viewerGuiPlotForm {window form} {
    if {![viewerGuiDesignGuard $window]} {error {Plot form belongs to a previous Session lifetime}}
    set definition [viewerGuiDesignComponent $window $form]
    if {[dict get $definition type] ne {section}} {error {Select a declared Plot form section}}
    set p [dict get $definition properties]
    foreach key {plot_dataset plot_x plot_y} {if {![dict exists $p $key]} {error "Plot form requires $key"}}
    return $p
}
proc ::GX::viewerGuiDesignPlotDiscover {window form} {
    set p [_viewerGuiPlotForm $window $form]
    set values [viewerGuiDesignValues $window];set dataset [dict get $values [dict get $p plot_dataset]]
    set variables [datasetVariableSchemaV3 $dataset];set choices {}
    foreach variable $variables {if {[dict get $variable dtype] in {float64 float32 int64 int32 uint64 uint32 int16 uint16 int8 uint8}} {lappend choices [dict get $variable variable_id]}}
    if {$choices eq {} || [llength $choices]>4096} {error {Dataset has no bounded numeric variable choices}}
    foreach key {plot_x plot_y} {
        set component [dict get $p $key]
        viewerGuiDesignChoicesSet $window $component $choices
        if {[dict get $values $component] ni $choices} {viewerGuiDesignValueSet $window $component [lindex $choices 0]}
    }
    return [dict create dataset_id $dataset variables $variables]
}
proc ::GX::viewerGuiDesignPlotBind {window component form {selection {}}} {
    try {
    set p [_viewerGuiPlotForm $window $form];set values [viewerGuiDesignValues $window]
    foreach key [dict keys $selection] {if {$key ni {y_variable_id}} {error {Plot selection supports only an explicit canonical Y variable}}}
    if {[dict exists $selection y_variable_id]} {
        set target [dict get $p plot_y];set wanted [dict get $selection y_variable_id]
        set choices [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] choice_options {}]
        set declared [viewerGuiDesignComponent $window $target]
        set allowed [datasetPublicationV2DictDefault $choices $target [datasetPublicationV2DictDefault [dict get $declared properties] choices {}]]
        if {$wanted ni $allowed} {error {Discover the actual Dataset variables before selecting this waveform}}
        dict set values $target $wanted
    }
    set dataset [dict get $values [dict get $p plot_dataset]]
    set x [dict get $values [dict get $p plot_x]];set y [dict get $values [dict get $p plot_y]]
    datasetVariableV3ById $dataset $x;set yVariable [datasetVariableV3ById $dataset $y]
    modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
    set spec [::GX::PlotDatasetAPIv4::newSpec -title {Canonical Dataset waveform}]
    set panel [lindex [dict get $spec panels] 0]
    set series [dict create id selected_source dataset_id $dataset x_variable_id $x y_variable_id $y axis left kind line label $y]
    # A one-row operating-point/measurement source has no line segment. Keep
    # its actual canonical observation visible using the existing Plot kind.
    if {[dict exists $yVariable shape] && [llength [dict get $yVariable shape]]==1 && [lindex [dict get $yVariable shape] 0]==1} {dict set series kind line_marker;dict set series style marker circle}
    dict set panel series [list $series]
    foreach {key axis} {plot_x_scale x plot_y_scale y_left} {
        if {[dict exists $p $key]} {
            set scale [dict get $values [dict get $p $key]]
            if {$scale ni {linear log}} {error {Choose the public Plot axis scale linear or log}}
            dict set panel axes $axis scale $scale
        }
    }
    dict set spec panels [list $panel]
    # Record History only after both the accepted native binding and its typed
    # selection agree. The original shared restoring guard suppresses the
    # intermediate History snapshot; it never changes Dataset authority.
    if {[dict exists $selection y_variable_id]} {
        set restoring [dict get $::GX::ViewerGui::instances $window restoring]
        dict set ::GX::ViewerGui::instances $window restoring 1
        try {
            set result [viewerGuiDesignPlotSet $window $component $spec]
            viewerGuiDesignValueSet $window [dict get $p plot_y] $y
        } finally {dict set ::GX::ViewerGui::instances $window restoring $restoring}
        if {!$restoring && [dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerChanged $window "Select canonical waveform $y"}
    } else {set result [viewerGuiDesignPlotSet $window $component $spec]}
    if {[dict exists $p plot_probe]} {viewerGuiDesignTextSet $window [dict get $p plot_probe] "Dataset: $dataset\nX: $x; Y: $y\nRelease the pointer on an actual source point to inspect its canonical row and units."}
    return $result
    } on error {message options} {
        if {[info exists p] && [dict exists $p plot_probe]} {catch {viewerGuiDesignTextSet $window [dict get $p plot_probe] "Plot binding failed: $message\nThe previous valid frame and canonical binding are retained. Correct the Dataset/variables/axis scales and Bind again."}}
        return -options $options $message
    }
}
proc ::GX::_viewerGuiPlotAttach {window component plot} {
    set definition [viewerGuiDesignComponent $window $component]
    set form [datasetPublicationV2DictDefault [dict get $definition properties] plot_form {}]
    if {$form eq {}} return
    _viewerGuiPlotForm $window $form
    bind $plot <ButtonPress-1> +[list focus $plot]
    bind $plot <ButtonRelease-1> +[list ::GX::_viewerGuiPlotSelected $window $component $form $plot %x %y]
    bind $plot <Escape> +[list catch [list ::GX::viewerGuiDesignPlotCursorClear $window $component]]
}
proc ::GX::_viewerGuiPlotBindingChanged {window component} {
    set definition [viewerGuiDesignComponent $window $component]
    set form [datasetPublicationV2DictDefault [dict get $definition properties] plot_form {}]
    if {$form eq {}} return
    set p [_viewerGuiPlotForm $window $form]
    if {[dict exists $p plot_probe]} {
        set cursor 0
        if {[dict exists $::GX::ViewerGui::instances $window bindings $component spec panels]} {
            foreach panel [dict get $::GX::ViewerGui::instances $window bindings $component spec panels] {
                foreach annotation [datasetPublicationV2DictDefault $panel annotations {}] {if {[datasetPublicationV2DictDefault $annotation id {}] in {__gx_source_cursor_x __gx_source_cursor_y}} {set cursor 1}}
            }
        }
        set message [expr {$cursor ? {Saved source cursor is displayed as reference lines. No canonical row has been reselected for this frame. Release the pointer on a computed point to inspect its exact source values and units.} : {Waveform binding updated. No source point is selected for this frame. Release the pointer on a computed point to inspect its exact canonical row and units.}}]
        viewerGuiDesignTextSet $window [dict get $p plot_probe] $message
    }
}
proc ::GX::_viewerGuiPlotSelected {window component form plot x y} {
    if {![viewerGuiDesignGuard $window]} return
    if {[catch {viewerGuiDesignPlotCursor $window $component $x $y} receipt]} {return}
    set p [_viewerGuiPlotForm $window $form]
    set text $receipt
    if {[dict exists $receipt source_values]} {
        set text "Dataset: [dict get $receipt dataset_id]\nSource row (zero-based): [dict get $receipt source_row_ordinal]"
        dict for {id value} [dict get $receipt source_values] {append text "\n$id = $value [dict get $receipt source_units $id]"}
    }
    if {[dict exists $p plot_probe]} {viewerGuiDesignTextSet $window [dict get $p plot_probe] [string range $text 0 4095]}
    viewerGuiTraceEmit $window $component selection [dict create status selected native_hit $receipt authority PLOT_DATASET_API_v4]
}
proc ::GX::_viewerGuiPlotCursorAnnotations {window component receipt} {
    if {![viewerGuiDesignGuard $window]} {error {Plot belongs to a previous Session lifetime}}
    set binding [dict get $::GX::ViewerGui::instances $window bindings $component]
    if {[dict get $binding kind] ne {plot}} {error {Bind a canonical Plot before selecting a source cursor}}
    set spec [dict get $binding spec];set panels {};set selected 0
    foreach panel [dict get $spec panels] {
        set annotations {}
        foreach annotation [datasetPublicationV2DictDefault $panel annotations {}] {
            if {[datasetPublicationV2DictDefault $annotation id {}] ni {__gx_source_cursor_x __gx_source_cursor_y}} {lappend annotations $annotation}
        }
        if {$receipt ne {} && [dict get $panel id] eq [dict get $receipt panel_id]} {
            set axis {}
            foreach series [dict get $panel series] {if {[dict get $series id] eq [dict get $receipt series_id]} {set axis [datasetPublicationV2DictDefault $series axis left];break}}
            if {$axis ni {left right}} {error {Source cursor no longer matches its canonical series}}
            lappend annotations [dict create id __gx_source_cursor_x type reference_line axis x value [dict get $receipt x] color #7b3fa0 line_style dashed line_width 1]
            lappend annotations [dict create id __gx_source_cursor_y type reference_line axis $axis value [dict get $receipt y] color #7b3fa0 line_style dashed line_width 1]
            set selected 1
        }
        dict set panel annotations $annotations;lappend panels $panel
    }
    if {$receipt ne {} && !$selected} {error {Source cursor panel no longer exists}}
    dict set spec panels $panels
    if {$spec eq [dict get $binding spec]} {return}
    set plot [dict get $::GX::ViewerGui::instances $window widgets $component].plot
    set axes [dict get [::GX::PlotDatasetAPIv4::widgetReceipt $plot] axes]
    set restoring [dict get $::GX::ViewerGui::instances $window restoring]
    dict set ::GX::ViewerGui::instances $window restoring 1
    try {
        viewerGuiDesignPlotSet $window $component $spec [datasetPublicationV2DictDefault $binding context {}]
        ::GX::PlotDatasetAPIv4::widgetView $plot restore $axes
    } finally {dict set ::GX::ViewerGui::instances $window restoring $restoring}
    if {!$restoring && [dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerChanged $window [expr {$receipt eq {}?{Clear source cursor}:{Select source cursor}}]}
}
proc ::GX::viewerGuiDesignPlotCursor {window component x y} {
    # Display coordinates are supplied by the existing native Plot hit owner;
    # exact scientific values/units still come from its canonical source row.
    set receipt [viewerGuiDesignPlotProbe $window $component $x $y]
    if {[dict exists $receipt source_row_ordinal]} {_viewerGuiPlotCursorAnnotations $window $component $receipt}
    return $receipt
}
proc ::GX::viewerGuiDesignPlotCursorClear {window component} {
    _viewerGuiPlotCursorAnnotations $window $component {}
    return [dict create status cleared owner PLOT_DATASET_API_v4 representation canonical_reference_line_annotations]
}
proc ::GX::viewerGuiDesignPlotProbe {window component x y} {
    if {![viewerGuiDesignGuard $window]} {error {Plot belongs to a previous Session lifetime}}
    set widget [dict get $::GX::ViewerGui::instances $window widgets $component].plot
    set receipt [::GX::PlotDatasetAPIv4::widgetHit $widget $x $y]
    if {![dict exists $receipt source_row_ordinal]} {return $receipt}
    set spec [dict get $::GX::ViewerGui::instances $window bindings $component spec]
    foreach panel [dict get $spec panels] {
        if {[dict get $panel id] ne [dict get $receipt panel_id]} continue
        foreach series [dict get $panel series] {
            if {[dict get $series id] ne [dict get $receipt series_id]} continue
            set dataset [dict get $series dataset_id]
            set ids [lsort -unique [list [dict get $series x_variable_id] [dict get $series y_variable_id]]]
            set stream [tableStreamOpenDataset $::GX::currentSession $dataset $ids 1 [dict create start [dict get $receipt source_row_ordinal] count 1 numeric_transport values]]
            try {set chunk [tableStreamNext $stream]} finally {tableStreamClose $stream}
            if {[dict get $chunk nrows]!=1} {error {Exact Plot source row is no longer available}}
            set values {};set units {}
            foreach id $ids {dict set values $id [lindex [dict get $chunk values $id] 0];dict set units $id [dict get [datasetVariableV3ById $dataset $id] unit]}
            return [dict merge $receipt [dict create dataset_id $dataset x_variable_id [dict get $series x_variable_id] y_variable_id [dict get $series y_variable_id] source_values $values source_units $units]]
        }
    }
    error {Native hit no longer matches its canonical series binding}
}
proc ::GX::viewerGuiDesignPlotReceipt {window component} {
    if {![viewerGuiDesignGuard $window]} {error {Plot belongs to a previous Session lifetime}}
    if {[dict get [viewerGuiDesignComponent $window $component] type] ne {plot}} {error {Select a declared canonical Plot}}
    set widget [dict get $::GX::ViewerGui::instances $window widgets $component].plot
    if {![winfo exists $widget]} {error {Bind the declared Plot first}}
    set receipt [::GX::PlotDatasetAPIv4::widgetReceipt $widget]
    if {[string bytelength $receipt]>65536} {error {Native Plot receipt exceeds the bounded inspection contract}}
    return [dict create width [winfo width $widget] height [winfo height $widget] mapped [winfo ismapped $widget] native_receipt $receipt]
}
proc ::GX::_viewerGuiPlotDesignValidate {design} {
    _viewerGuiPlotSeriesDesignValidate $design
    set definitions {};foreach component [dict get $design components] {dict set definitions [dict get $component id] $component}
    foreach component [dict get $design components] {
        set p [dict get $component properties]
        if {[dict get $component type] eq {plot} && [dict exists $p plot_form]} {
            set target [dict get $p plot_form]
            if {![dict exists $definitions $target properties plot_dataset]} {error {Plot needs a declared complete Plot form}}
        }
        if {[dict get $component type] ne {section} || ![dict exists $p plot_dataset]} continue
        if {![dict exists $design requirements PLOT_DATASET_API_v4] || [dict get $design requirements PLOT_DATASET_API_v4]!=4} {error {Plot form requires PLOT_DATASET_API_v4@4}}
        foreach {key types} {plot_dataset {dataset_selector} plot_x {choice combobox} plot_y {choice combobox}} {
            if {![dict exists $p $key] || ![dict exists $definitions [dict get $p $key]] || [dict get $definitions [dict get $p $key] type] ni $types} {error "Invalid canonical Plot form field $key"}
        }
        if {[dict exists $p plot_probe] && (![dict exists $definitions [dict get $p plot_probe]] || [dict get $definitions [dict get $p plot_probe] type] ni {label status log})} {error {Plot probe needs an existing read-only text control}}
        foreach key {plot_x_scale plot_y_scale} {
            if {[dict exists $p $key] && (![dict exists $definitions [dict get $p $key]] || [dict get $definitions [dict get $p $key] type] ni {choice combobox})} {error {Plot scale needs a declared typed choice control}}
        }
    }
}
