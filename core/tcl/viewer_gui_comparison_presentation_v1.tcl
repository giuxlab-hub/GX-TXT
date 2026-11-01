# SPDX-License-Identifier: GPL-3.0-or-later
# Finite presentation of an already admitted Comparison Plot. Existing Plot,
# UI Field, History, Graph variants, Resource and File Publication own the work.
proc ::GX::_viewerComparisonPlotAdmission {window {numerical 0}} {
    # CORE-owned dialogs/cursor callbacks may run after their native event.
    # Reuse its original admitted package and source identities, not the old
    # event generation, before exercising the retained public presentation.
    if {![dict exists $::GX::ViewerDevelopment::windows $window]} {return {}}
    set r [_viewerNativeClientBase $window]
    if {[_viewerDevelopmentSnapshot [dict get $r project]] ne [dict get $r validated_snapshot] ||
        ![dict exists $r native_client_package_snapshot] ||
        [_viewerNativeClientPackageSnapshot [dict get $r runtime_module_root]] ne [dict get $r native_client_package_snapshot]} {error {Comparison package or source admission changed; reopen the Viewer}}
    set grants [dict get $r native_client_grants]
    if {{comparison_command} ni [datasetPublicationV2DictDefault $grants COMPARISON_PLOT_API_v1 {}] ||
        {widgetCreate} ni [datasetPublicationV2DictDefault $grants PLOT_DATASET_API_v4 {}]} {error {Comparison Plot presentation capability is not granted}}
    if {$numerical && {comparison_curves} ni [datasetPublicationV2DictDefault $grants NUMERIC_API_v1 {}]} {error {Comparison re-preparation lacks its exact Numeric capability}}
    return $r
}
proc ::GX::_viewerComparisonPlotBound {window form} {
    _viewerComparisonPlotAdmission $window
    set p [_viewerGuiComparisonForm $window $form]
    set component [dict get $p comparison_target]
    if {![dict exists $::GX::ViewerGui::instances $window bindings $component]} {error {Prepare a comparison before using Plot commands}}
    set binding [dict get $::GX::ViewerGui::instances $window bindings $component]
    if {[dict get $binding kind] ne {plot} || ![dict exists $binding spec comparison]} {error {This form has no prepared Comparison Plot}}
    set widget [dict get $::GX::ViewerGui::instances $window widgets $component].plot
    if {![winfo exists $widget]} {error {The prepared Plot has closed}}
    foreach source [dict get $binding spec comparison sources] {
        if {[dict get $source kind] eq {library_entry} && ![_viewerComparisonLibraryAllowed $window]} {error {Saved Library consultation is not granted}}
    }
    ::GX::PlotDatasetAPIv4::widgetReceipt $widget
    return [dict create component $component widget $widget spec [dict get $binding spec] context [dict get $binding context]]
}
proc ::GX::_viewerComparisonPlotActionEnabled {window action} {
    if {![dict exists $::GX::ViewerGui::instances $window]} {return {}}
    foreach c [dict get $::GX::ViewerGui::instances $window design components] {
        set p [dict get $c properties]
        if {![dict exists $p comparison_commands $action]} continue
        set op [dict get $p comparison_commands $action]
        if {![string match plot_* $op]} {return {}}
        if {[dict exists $::GX::ViewerGui::instances $window design handlers $action available] && ![dict get $::GX::ViewerGui::instances $window design handlers $action available]} {return 0}
        if {![viewerGuiDesignGuard $window]} {return 0}
        if {$op ni {plot_fit plot_zoom_in plot_zoom_out plot_copy plot_export} && [dict exists $::GX::ScientificHistory::viewers $window] && ![scientificHistoryViewerEditable $window]} {return 0}
        if {$op eq {plot_load_variant}} {return [expr {$::GX::currentSession ne {}}]}
        if {$op eq {plot_save_variant} && $::GX::currentSession eq {}} {return 0}
        set target [dict get $p comparison_target]
        return [expr {[dict exists $::GX::ViewerGui::instances $window bindings $target spec comparison] && [winfo exists [dict get $::GX::ViewerGui::instances $window widgets $target].plot]}]
    }
    return {}
}
proc ::GX::_viewerComparisonPlotAttach {window component widget} {
    set c [viewerGuiDesignComponent $window $component]
    if {![dict exists $c properties comparison_form]} return
    bind $widget <ButtonRelease-1> +[list ::GX::_viewerComparisonPlotPick $window [dict get $c properties comparison_form] %x %y]
    bind $widget <Escape> +[list catch [list ::GX::_viewerComparisonPlotCommand $window [dict get $c properties comparison_form] plot_clear_cursor]]
}
proc ::GX::_viewerComparisonPlotApply {window form spec {retainView 1} {description {Edit Comparison Plot}}} {
    _viewerComparisonPlotAdmission $window 1
    if {[dict exists $::GX::ScientificHistory::viewers $window] && ![scientificHistoryViewerEditable $window]} {error {History browsing is read-only; return to latest before editing the Plot}}
    set bound [_viewerComparisonPlotBound $window $form]
    comparisonPlotValidate [dict get $spec comparison]
    set widget [dict get $bound widget]
    set corrected {}
    # A loaded variant replaces the view explicitly. Its hidden target may not
    # have drawn yet, and therefore legitimately has no native axes receipt.
    if {$retainView} {
        set axes [dict get [::GX::PlotDatasetAPIv4::widgetReceipt $widget] axes]
        set view [_viewerGuiPlotViewState $axes]
        # A direction change keeps the visible physical interval, but must not be
        # undone by restoring the old native receipt's direction.
        foreach item $view {
            if {[dict get $item axis] eq {x}} {
                foreach panel [dict get $spec panels] {
                    if {[dict get $panel id] eq [dict get $item panel_id] && [dict exists $panel axes x direction] && [dict get $panel axes x direction] ne {auto}} {dict set item direction [dict get $panel axes x direction]}
                }
            }
            lappend corrected $item
        }
    }
    set restoring [dict get $::GX::ViewerGui::instances $window restoring]
    if {!$restoring && [dict exists $::GX::ScientificHistory::viewers $window] && ![scientificHistoryViewerPrepareEdit $window]} {error {Plot edit cancelled before changing the valid frame}}
    dict set ::GX::ViewerGui::instances $window restoring 1
    try {
        viewerGuiDesignPlotSet $window [dict get $bound component] $spec [dict get $bound context]
        if {$retainView} {::GX::PlotDatasetAPIv4::widgetView $widget restore $corrected}
    } finally {
        if {[dict exists $::GX::ViewerGui::instances $window]} {dict set ::GX::ViewerGui::instances $window restoring $restoring}
    }
    if {!$restoring && [dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerRecordOperation $window $description}
    return $widget
}
proc ::GX::_viewerComparisonPlotDialogContext {window form dialog kind} {
    set bound [_viewerComparisonPlotBound $window $form]
    dict set ::GX::ViewerGui::instances $window comparison_dialogs $dialog [dict create kind $kind form $form window_id [winfo id $window] widget_id [winfo id [dict get $bound widget]] spec [dict get $bound spec]]
    return $bound
}
proc ::GX::_viewerComparisonPlotDialogApply {window dialog values} {
    if {![viewerGuiDesignGuard $window] || ![dict exists $::GX::ViewerGui::instances $window comparison_dialogs $dialog]} {error {Plot dialog belongs to a closed or previous Viewer}}
    set saved [dict get $::GX::ViewerGui::instances $window comparison_dialogs $dialog]
    set form [dict get $saved form];set bound [_viewerComparisonPlotBound $window $form]
    if {[winfo id $window] ne [dict get $saved window_id] || [winfo id [dict get $bound widget]] ne [dict get $saved widget_id] || [dict get $bound spec] ne [dict get $saved spec]} {error {The prepared Plot changed while this dialog was open; reopen its properties}}
    set spec [dict get $bound spec];set kind [dict get $saved kind];set retainView 1
    switch $kind {
        properties {
            set target [dict get $values panel];set panels {};set found 0
            foreach panel [dict get $spec panels] {
                # One shared X presentation, with independently edited Y.
                foreach key {label scale direction min max major_step minor_grid tick_positions tick_labels} {
                    set value [dict get $values x_$key]
                    if {$value ne {}} {dict set panel axes x $key $value} elseif {[dict exists $panel axes x $key]} {dict unset panel axes x $key}
                }
                if {[dict get $panel id] eq $target} {
                    set found 1;dict set panel title [dict get $values panel_title]
                    foreach key {label scale min max} {
                        set value [dict get $values y_$key]
                        if {$value ne {}} {dict set panel axes y_left $key $value} elseif {[dict exists $panel axes y_left $key]} {dict unset panel axes y_left $key}
                    }
                }
                lappend panels $panel
            }
            if {!$found} {error {Selected Plot panel is unavailable}}
            dict set spec panels $panels;set retainView 0
            dict set spec native_presentation schema GXTXT_NATIVE_GRAPH_PRESENTATION_v1
            foreach field {font_size axis_label_font_size title_font_size} {dict set spec native_presentation graphics $field [dict get $values $field]}
            # Existing Graph presentation owns its font unit; changing axes
            # must not silently reinterpret stored point sizes as pixels.
            if {![dict exists $spec native_presentation graphics font_unit]} {dict set spec native_presentation graphics font_unit px}
        }
        legend {
            dict set spec native_presentation schema GXTXT_NATIVE_GRAPH_PRESENTATION_v1
            set background [string trim [dict get $values background]]
            if {$background ne {none} && $background ne {}} {set background [uiFieldColor $background]}
            foreach key {placement layout columns font_size border} {dict set spec native_presentation legend $key [dict get $values $key]}
            dict set spec native_presentation legend background $background
            if {![dict exists $spec native_presentation legend font_unit]} {dict set spec native_presentation legend font_unit px}
        }
        style {
            set id [dict get $values series]
            set allowed [_viewerComparisonPlotSeriesIds $spec]
            if {$id ni $allowed} {error {The selected display series is no longer available}}
            set style {};foreach field {color line_width line_style marker marker_size opacity} {dict set style $field [dict get $values $field]}
            ::GX::PlotDatasetAPIv2::_validateStyle $style {Comparison display}
            dict set spec native_presentation schema GXTXT_NATIVE_GRAPH_PRESENTATION_v1
            dict set spec native_presentation plot_config comparison_style_version 1
            dict for {field value} $style {dict set spec native_presentation plot_config comparison_style:$id:$field $value}
        }
        save_variant {
            set name [string trim [dict get $values name]]
            if {$name eq {} || [string length $name]>200} {error {Enter a Plot variant name of 1..200 characters}}
            dict set spec title $name
            set ref [::GX::PlotDatasetAPIv4::createPlotFromSpec $spec variant]
            _viewerGuiComparisonRefresh $window $form "Saved Plot variant [dict get $ref variant_id]: $name. Canonical sources are unchanged."
            destroy $dialog
            return
        }
        default {error {Unknown Plot presentation dialog}}
    }
    _viewerComparisonPlotApply $window $form $spec $retainView "Comparison Plot: $kind"
    dict set ::GX::ViewerGui::instances $window comparison_dialogs $dialog spec [dict get $::GX::ViewerGui::instances $window bindings [dict get $bound component] spec]
}
proc ::GX::_viewerComparisonPlotSeriesIds {spec} {
    set n [expr {[dict get $spec comparison mode] in {difference ratio}?1:[llength [dict get $spec comparison sources]]}]
    set ids {};for {set i 0} {$i<$n} {incr i} {lappend ids comparison_$i};return $ids
}
proc ::GX::_viewerComparisonPlotDialog {window form kind} {
    set dialog $window.comparisonPlotDialog
    set bound [_viewerComparisonPlotDialogContext $window $form $dialog $kind]
    set spec [dict get $bound spec];set fields {};set values {};set title {Plot properties}
    switch $kind {
        properties {
            set ids {};foreach panel [dict get $spec panels] {lappend ids [dict get $panel id]}
            set panel [lindex [dict get $spec panels] 0]
            dict set fields panel [dict create type choice label {Y panel / panel title} values $ids]
            dict set values panel [lindex $ids 0]
            dict set fields panel_title {type string label {Panel title (source identity stays in Sources)}}
            dict set values panel_title [datasetPublicationV2DictDefault $panel title {}]
            foreach axis {x y} label {{Shared X} {Selected Y}} {
                set key [expr {$axis eq {x}?{x}:{y_left}}]
                foreach {field type caption default} {label string title {} scale choice scale linear min string minimum auto max string maximum auto} {
                    set d [dict create type $type label "$label $caption"]
                    if {$field eq {scale}} {dict set d values {auto linear log}}
                    dict set fields ${axis}_$field $d
                    dict set values ${axis}_$field [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $panel axes {}] $key {}] $field $default]
                }
            }
            dict set fields x_direction {type choice label {Shared X direction} values {auto normal reverse}}
            dict set values x_direction [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $panel axes {}] x {}] direction normal]
            foreach {field label default} {
                major_step {Shared X major tick step (blank: automatic)} {}
                minor_grid {Shared X minor grid} off
                tick_positions {Explicit X tick values (semicolon-separated; blank: automatic)} {}
                tick_labels {Explicit X tick labels (semicolon-separated; paired with values)} {}
            } {
                set d [dict create type string label $label]
                if {$field eq {minor_grid}} {dict set d type choice;dict set d values {off auto}}
                dict set fields x_$field $d
                dict set values x_$field [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $panel axes {}] x {}] $field $default]
            }
            set fontUnit [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $spec native_presentation {}] graphics {}] font_unit px]
            set fontLabel [expr {$fontUnit in {pt points}?{points}:{pixels}}]
            foreach {field label default} {font_size {Tick font} 12 axis_label_font_size {Axis-label font} 14 title_font_size {Title font} 18} {
                dict set fields $field [dict create type number label "$label ($fontLabel; blank inherits)" allow_inherit 1 min 6 max 72]
                dict set values $field [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $spec native_presentation {}] graphics {}] $field $default]
            }
        }
        legend {
            set title {Comparison Plot legend}
            set legend [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $spec native_presentation {}] legend {}]
            foreach {key type label default extra} {
                placement choice Placement inside {values {inside above below left right none manual}}
                layout choice {Entry layout} stacked {values {auto stacked row wrapped}}
                columns integer Columns 1 {min 1 max 8}
                font_size number {Font size} 12 {allow_inherit 1 min 6 max 72}
                background string {Background (none or #RRGGBB)} none {}
                border boolean Border off {}
            } {dict set fields $key [dict merge [dict create type $type label $label] $extra];dict set values $key [datasetPublicationV2DictDefault $legend $key $default]}
            if {[dict get $values border] eq {none}} {dict set values border 0}
            dict set values border [uiFieldNormalize {type boolean} [dict get $values border]]
            set fontUnit [datasetPublicationV2DictDefault $legend font_unit px]
            if {$fontUnit eq {inherit}} {set fontUnit [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $spec native_presentation {}] graphics {}] font_unit px]}
            dict set fields font_size label "Font size ([expr {$fontUnit in {pt points}?{points}:{pixels}}]; blank inherits)"
        }
        style {
            set title {Comparison display series style}
            set ids [_viewerComparisonPlotSeriesIds $spec]
            dict set fields series [dict create type choice label {Display series (source order)} values $ids];dict set values series [lindex $ids 0]
            foreach {key type label default extra} {
                color string {Color: auto or #RRGGBB} auto {}
                line_width number {Line width} 1.5 {min 0.1 max 30}
                line_style choice {Line style} solid {values {solid dashed dotted dashdot none}}
                marker choice Marker none {values {none circle square diamond triangle_up triangle_down plus x star}}
                marker_size number {Marker size} 4 {min 0.1 max 50}
                opacity number Opacity 1 {min 0 max 1}
            } {dict set fields $key [dict merge [dict create type $type label $label] $extra];dict set values $key $default}
        }
        save_variant {
            set title {Save current Comparison as a Plot variant}
            set fields {name {type string label {Variant name}}};set values {name {Scientific comparison}}
        }
        default {error {Unknown Plot properties group}}
    }
    uiFieldFormCreate $dialog $title $fields $values [list ::GX::_viewerComparisonPlotDialogApply $window $dialog] $window
    if {$kind eq {properties}} {
        dict set ::GX::ViewerGui::instances $window comparison_dialogs $dialog selected_panel [dict get $values panel]
        trace add variable ::GX::UiField::formValues($dialog,panel) write [list ::GX::_viewerComparisonPlotPanelChanged $window $dialog]
    }
    if {$kind eq {style}} {trace add variable ::GX::UiField::formValues($dialog,series) write [list ::GX::_viewerComparisonPlotStyleChanged $window $dialog];_viewerComparisonPlotStyleChanged $window $dialog}
    return [dict create status dialog_opened canonical_values_modified 0]
}
proc ::GX::_viewerComparisonPlotPanelChanged {window dialog args} {
    if {![viewerGuiDesignGuard $window] || ![dict exists $::GX::ViewerGui::instances $window comparison_dialogs $dialog]} return
    set saved [dict get $::GX::ViewerGui::instances $window comparison_dialogs $dialog]
    set selected $::GX::UiField::formValues($dialog,panel)
    if {[dict exists $saved selected_panel] && [dict get $saved selected_panel] eq $selected} return
    dict set ::GX::ViewerGui::instances $window comparison_dialogs $dialog selected_panel $selected
    foreach panel [dict get $saved spec panels] {
        if {[dict get $panel id] ne $selected} continue
        set ::GX::UiField::formValues($dialog,panel_title) [datasetPublicationV2DictDefault $panel title {}]
        foreach {field default} {label {} scale linear min auto max auto} {set ::GX::UiField::formValues($dialog,y_$field) [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $panel axes {}] y_left {}] $field $default]}
    }
}
proc ::GX::_viewerComparisonPlotStyleChanged {window dialog args} {
    if {![viewerGuiDesignGuard $window] || ![dict exists $::GX::ViewerGui::instances $window comparison_dialogs $dialog]} return
    set saved [dict get $::GX::ViewerGui::instances $window comparison_dialogs $dialog]
    set id $::GX::UiField::formValues($dialog,series)
    if {[dict exists $saved selected_series] && [dict get $saved selected_series] eq $id} return
    dict set ::GX::ViewerGui::instances $window comparison_dialogs $dialog selected_series $id
    set config [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault [dict get $saved spec] native_presentation {}] plot_config {}]
    foreach {field default} {color auto line_width 1.5 line_style solid marker none marker_size 4 opacity 1} {set ::GX::UiField::formValues($dialog,$field) [datasetPublicationV2DictDefault $config comparison_style:$id:$field $default]}
}
proc ::GX::_viewerComparisonPlotPick {window form x y} {
    if {![viewerGuiDesignGuard $window] || ![datasetPublicationV2DictDefault [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] comparison_cursors {}] $form 0]} return
    if {[catch {
        set bound [_viewerComparisonPlotBound $window $form]
        set hit [::GX::PlotDatasetAPIv4::widgetHit [dict get $bound widget] $x $y]
        foreach key {panel_id series_id x y} {if {![dict exists $hit $key]} {return}}
        set spec [dict get $bound spec];set panelIds {}
        foreach panel [dict get $spec panels] {lappend panelIds [dict get $panel id]}
        if {[dict get $hit panel_id] ni $panelIds} {error {The picked display panel changed}}
        dict set spec native_presentation schema GXTXT_NATIVE_GRAPH_PRESENTATION_v1
        dict set spec native_presentation plot_config comparison_cursor_version 1
        dict set spec native_presentation plot_config comparison_cursor_panel [dict get $hit panel_id]
        foreach field {x y} {dict set spec native_presentation plot_config comparison_cursor_$field [dict get $hit $field]}
        _viewerComparisonPlotApply $window $form $spec 1 {Comparison display cursor}
        set config [dict get $spec comparison];set first [lindex [dict get $config sources] 0]
        set unit [dict get $first y_unit]
        if {[dict get $config mode] eq {ratio} || [dict get $config normalization] eq {minmax}} {set unit 1} elseif {[dict get $config mode] eq {top_bottom} && [regexp {^source_([0-7])$} [dict get $hit panel_id] -> index]} {set unit [dict get [lindex [dict get $config sources] $index] y_unit]}
        _viewerGuiComparisonRefresh $window $form "Display cursor: X=[dict get $hit x] [dict get $first x_unit], Y=[dict get $hit y] $unit; series [dict get $hit series_id]. These are plotted values after the declared display transform, not an asserted canonical row."
    } reason]} {catch {_viewerGuiComparisonRefresh $window $form "Cursor unavailable: $reason. Previous valid Plot retained."}}
}
proc ::GX::_viewerComparisonPlotVariantLoad {window form expected values} {
    if {![viewerGuiDesignGuard $window] || [winfo id $window] ne [dict get $expected window_id] || [interactiveDocumentSessionToken] ne [dict get $expected token]} {error {Variant dialog belongs to a previous Session or Viewer}}
    _viewerComparisonPlotAdmission $window 1
    set selected [dict get $values variant]
    if {![dict exists $expected choices $selected]} {error {Select an offered Plot variant}}
    set id [dict get $expected choices $selected]
    set ref [::GX::PlotDatasetAPIv4::openPlot [dict get $expected graph] $id]
    set spec [::GX::PlotDatasetAPIv4::loadSpec $ref]
    if {![dict exists $spec comparison]} {error {Selected variant is not a Comparison Plot}}
    foreach source [dict get $spec comparison sources] {if {[dict get $source kind] eq {library_entry} && ![_viewerComparisonLibraryAllowed $window]} {error {Saved Library consultation is not granted}}}
    set p [_viewerGuiComparisonForm $window $form]
    comparisonPlotValidate [dict get $spec comparison]
    set restoring [dict get $::GX::ViewerGui::instances $window restoring]
    if {!$restoring && [dict exists $::GX::ScientificHistory::viewers $window] && ![scientificHistoryViewerPrepareEdit $window]} {error {Variant load cancelled before changing the valid Plot}}
    dict set ::GX::ViewerGui::instances $window restoring 1
    try {
        if {[dict exists $::GX::ViewerGui::instances $window bindings [dict get $p comparison_target]]} {_viewerComparisonPlotApply $window $form $spec 0 {Load Comparison Plot variant}} else {viewerGuiDesignPlotSet $window [dict get $p comparison_target] $spec}
        dict set ::GX::ViewerGui::instances $window comparison_sources $form [dict get $spec comparison sources]
        foreach {property key} {comparison_mode mode comparison_normalization normalization comparison_offset offset comparison_floor denominator_floor} {viewerGuiDesignValueSet $window [dict get $p $property] [dict get $spec comparison $key]}
        _viewerGuiComparisonCapture $window
    } finally {if {[dict exists $::GX::ViewerGui::instances $window]} {dict set ::GX::ViewerGui::instances $window restoring $restoring}}
    if {!$restoring && [dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerRecordOperation $window {Load Comparison Plot variant}}
    _viewerGuiComparisonRefresh $window $form "Loaded exact Plot variant $id; source pins verified."
}
proc ::GX::_viewerComparisonPlotCommand {window form operation} {
    _viewerComparisonPlotAdmission $window
    set p [_viewerGuiComparisonForm $window $form]
    modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
    if {$operation eq {plot_load_variant}} {
        set graph [dict get [::GX::PlotDatasetAPIv4::newSpec] graph_id];set choices {}
        foreach id [plotVariantIds plot.dataset $graph] {
            if {![catch {set spec [::GX::PlotDatasetAPIv4::loadSpec [::GX::PlotDatasetAPIv4::openPlot $graph $id]]}] && [dict exists $spec comparison]} {dict set choices "[dict get $spec title] — $id" $id}
        }
        if {![dict size $choices]} {_viewerGuiComparisonRefresh $window $form {No saved Comparison Plot variants are available. Prepare a Plot, then choose Plot > Save Plot Variant.};return [dict create status empty]}
        set labels [dict keys $choices]
        uiFieldFormCreate $window.comparisonVariant {Load Comparison Plot variant} [dict create variant [dict create type choice label {Saved variant} values $labels]] [dict create variant [lindex $labels 0]] [list ::GX::_viewerComparisonPlotVariantLoad $window $form [dict create graph $graph choices $choices token [interactiveDocumentSessionToken] window_id [winfo id $window]]] $window
        return [dict create status dialog_opened]
    }
    set bound [_viewerComparisonPlotBound $window $form];set widget [dict get $bound widget];set spec [dict get $bound spec]
    switch $operation {
        plot_fit {::GX::PlotDatasetAPIv4::widgetView $widget fit}
        plot_zoom_in - plot_zoom_out {
            set factor [expr {$operation eq {plot_zoom_in}?1.25:0.8}]
            set receipt [::GX::PlotDatasetAPIv4::widgetReceipt $widget]
            foreach axis [dict get $receipt axes] {if {[dict get $axis axis] eq {x}} {::GX::PlotDatasetAPIv4::widgetView $widget zoom [dict get $axis panel_id] $factor .5 .5;break}}
        }
        plot_cursor {dict set ::GX::ViewerGui::instances $window comparison_cursors $form 1;_viewerGuiComparisonRefresh $window $form {Click a displayed point to place its X/Y reference cursor. Values are display coordinates, not an inferred canonical source row.}}
        plot_clear_cursor {
            dict set ::GX::ViewerGui::instances $window comparison_cursors $form 0
            foreach key {comparison_cursor_version comparison_cursor_panel comparison_cursor_x comparison_cursor_y} {
                if {[dict exists $spec native_presentation plot_config $key]} {dict unset spec native_presentation plot_config $key}
            }
            _viewerComparisonPlotApply $window $form $spec 1 {Clear Comparison cursor}
        }
        plot_reverse_x {
            set panels {};set old [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault [lindex [dict get $spec panels] 0] axes {}] x {}] direction normal]
            foreach panel [dict get $spec panels] {dict set panel axes x direction [expr {$old eq {reverse}?{normal}:{reverse}}];lappend panels $panel};dict set spec panels $panels
            _viewerComparisonPlotApply $window $form $spec 1 {Reverse Comparison X direction}
        }
        plot_properties - plot_legend - plot_style - plot_save_variant {return [_viewerComparisonPlotDialog $window $form [string range $operation 5 end]]}
        plot_copy - plot_export {
            set destination {}
            if {$operation eq {plot_export}} {set destination [tk_getSaveFile -parent $window -title {Export current Comparison Plot as PNG} -defaultextension .png -filetypes {{{PNG image} {.png}}}];if {$destination eq {}} {return [dict create status cancelled]};set bound [_viewerComparisonPlotBound $window $form];set widget [dict get $bound widget]}
            set allocation [resourceManagementAllocate comparison_plot [dict create kind directory lifetime operation session $::GX::currentSession retention_seconds 0]]
            try {
                set png [file join [dict get $allocation path] comparison.png]
                ::GX::PlotDatasetAPIv4::widgetExport $widget $png [expr {max(200,[winfo width $widget])}] [expr {max(160,[winfo height $widget])}]
                if {$operation eq {plot_copy}} {graphFullClipboardX11 $png} else {filePublicationCopy $png $destination [sha256File $png] replace}
            } finally {resourceManagementRelease [dict get $allocation id] verified_orphan}
            _viewerGuiComparisonRefresh $window $form [expr {$operation eq {plot_copy}?{Copied displayed Plot image to the image clipboard; canonical samples are unchanged.}:"Exported displayed Plot PNG: $destination"}]
        }
        default {error {Unknown finite Plot presentation operation}}
    }
    return [dict create status completed source_count [llength [dict get $spec comparison sources]] canonical_values_modified 0]
}
