# SPDX-License-Identifier: GPL-3.0-or-later
# Declarative design-time facade of Viewer GUI Host. Rendering, command,
# field, Dataset, native and scientific state retain their public owners.
namespace eval ::GX::ViewerGui {variable manifests {};variable shells {};variable instances {};variable values;variable serial 0;variable traces {}}
proc ::GX::_viewerGuiGeometryObserved window {
    if {![dict exists $::GX::ViewerGui::instances $window] || ![winfo exists $window]} return
    catch {dict unset ::GX::ViewerGui::instances $window resize_timer}
    set geometry [lindex [split [wm geometry $window] +] 0]
    if {[dict exists $::GX::ViewerGui::instances $window last_geometry] && [dict get $::GX::ViewerGui::instances $window last_geometry] eq $geometry} return
    dict set ::GX::ViewerGui::instances $window last_geometry $geometry
    viewerGuiTraceEmit $window window resized [dict create status settled geometry $geometry]
}
proc ::GX::_viewerGuiGeometrySchedule {window actual} {
    if {$window ne $actual || ![dict exists $::GX::ViewerGui::instances $window]} return
    if {[dict exists $::GX::ViewerGui::instances $window resize_timer]} {after cancel [dict get $::GX::ViewerGui::instances $window resize_timer]}
    dict set ::GX::ViewerGui::instances $window resize_timer [after 120 [list ::GX::_viewerGuiGeometryObserved $window]]
}
proc ::GX::_viewerGuiHostDisposed {window actual} {if {$window eq $actual && [dict exists $::GX::ViewerGui::shells $window]} {dict unset ::GX::ViewerGui::shells $window}}
proc ::GX::viewerGuiCompare {original rebuilt {tolerance 4}} {
    if {![string is integer -strict $tolerance] || $tolerance<0 || $tolerance>40} {error {Comparison tolerance must be 0–40 pixels.}}
    set id comparison-[incr ::GX::ViewerGui::serial];set cases {};set boundaries {}
    foreach w [list $original $rebuilt] {
        if {![dict exists $::GX::ViewerGui::instances $w]} {
            return [dict create schema gxtxt.viewer_gui_comparison.v1 id $id status CORE_GAP cases {} original [viewerGuiHostInspect $original] rebuilt [viewerGuiHostInspect $rebuilt] boundaries [list [dict create classification coverage_limitation owner VIEWER_GUI_HOST_API_v1 reason {A complete declarative component model is unavailable for one side; shell geometry does not establish full parity.}]]]
        }
    }
    set a [viewerGuiRuntimeInspect $original];set b [viewerGuiRuntimeInspect $rebuilt]
    set ea [viewerGuiEnvironment $original];set eb [viewerGuiEnvironment $rebuilt]
    set valid 1
    foreach field {platform tk theme scaling font} {
        set equal [expr {[dict get $ea $field] eq [dict get $eb $field]}]
        if {!$equal} {set valid 0}
        lappend cases [dict create id environment:$field status [expr {$equal ? {PASS} : {INVALID COMPARISON}}] owner UI_FIELD_API_v1 expected [dict get $ea $field] observed [dict get $eb $field]]
    }
    set sizeA [list [winfo width $original] [winfo height $original]];set sizeB [list [winfo width $rebuilt] [winfo height $rebuilt]]
    if {$sizeA ne $sizeB} {set valid 0}
    lappend cases [dict create id environment:client_size status [expr {$sizeA eq $sizeB ? {PASS} : {INVALID COMPARISON}}] owner UI_FIELD_API_v1 expected $sizeA observed $sizeB]
    set da [dict get $::GX::ViewerGui::instances $original design];set db [dict get $::GX::ViewerGui::instances $rebuilt design]
    foreach field {components handlers requirements} {
        set equal [expr {[dict get $da $field] eq [dict get $db $field]}]
        lappend cases [dict create id declaration:$field status [expr {$equal ? {PASS} : {FAIL}}] owner VIEWER_GUI_HOST_API_v1 expected [dict get $da $field] observed [dict get $db $field]]
    }
    dict for {component row} [dict get $a components] {
        set status PASS;set observed {}
        if {![dict exists $b components $component]} {set status FAIL;set observed {Component missing from reconstruction}} else {
            set other [dict get $b components $component];set observed $other
            foreach field {type class mapped effective_text menu_entries scientific_binding readiness} {if {[dict exists $row $field] && (![dict exists $other $field] || [dict get $row $field] ne [dict get $other $field])} {set status FAIL}}
            if {$valid && [dict get $row mapped] && [dict get $other mapped] && [dict exists $row rectangle] && [dict exists $other rectangle]} {
                foreach x [dict get $row rectangle] y [dict get $other rectangle] {if {abs($x-$y)>$tolerance} {set status FAIL}}
            }
        }
        lappend cases [dict create id component:$component status $status owner [dict get $row api_id] expected $row observed $observed]
        if {[dict get $row type] in {field toggle choice dataset_selector entry combobox checkbutton list log progress} && [dict exists $b components $component]} {
            set valueStatus PASS;set detail {Values compared privately; contents excluded from this report.}
            if {[catch {
                set left [uiFieldComponentRead [dict get $row widget] [dict get $row type]]
                set right [uiFieldComponentRead [dict get $b components $component widget] [dict get $row type]]
                if {$left ne $right} {set valueStatus FAIL}
            } problem]} {set valueStatus {NOT RUN};set detail $problem}
            lappend cases [dict create id value:$component status $valueStatus owner UI_FIELD_API_v1 expected {Equivalent current UI value} observed $detail]
        }
    }
    set eventsA {};set eventsB {}
    foreach inspection [list $a $b] listName {eventsA eventsB} {
        foreach event [dict get $inspection trace] {if {[dict get $event event] eq {result}} {lappend $listName [list [dict get $event component] [dict get $event detail status]]}}
    }
    set behavior [expr {$eventsA eq {} || $eventsB eq {} ? {NOT RUN} : ($eventsA eq $eventsB ? {PASS} : {FAIL})}]
    lappend cases [dict create id behavior:observed_commands status $behavior owner CONFIGURATION_API_v1 expected $eventsA observed $eventsB scope {Only these actual command/result sequences; no unexecuted handler or scientific correctness claim.}]
    set status [expr {$valid ? {PASS} : {INVALID COMPARISON}}]
    foreach row $cases {if {[dict get $row status] eq {FAIL}} {set status FAIL;break};if {[dict get $row status] eq {NOT RUN} && $status eq {PASS}} {set status {NOT RUN}}}
    return [dict create schema gxtxt.viewer_gui_comparison.v1 id $id status $status environment $ea tolerance_px $tolerance cases $cases boundaries $boundaries behavior_scope {Observed commands only; full round-trip acceptance also requires persistence, package, handler-source and private scientific fixture receipts.}]
}
proc ::GX::viewerGuiComponentCapabilities {} {
    set result [uiFieldComponentCapabilities]
    foreach {type label api properties} {
        command_toolbar {Responsive command toolbar} CONFIGURATION_API_v1 {actions list}
        native2d {Native2D scientific viewport} NATIVE2D_VIEWPORT_HOST_v1 {title string diagram_catalog choice document_slot identifier source_kind choice}
        plot {Native Plot Dataset v4 host} PLOT_DATASET_API_v4 {title string spec dictionary empty_style choice}
        document {Canonical document consultation or declared TeX source} VIEWER_GUI_HOST_API_v1 {kind choice title string mode choice}
        context_menu {Viewer contextual command menu} CONFIGURATION_API_v1 {actions list}
        menu {Viewer command menu} CONFIGURATION_API_v1 {label string actions list}
        help {Current module Manual and About} DOCUMENTATION_BROWSER_API_v1 {}
        workspace {Session Workspace lifecycle} SESSION_WORKSPACE_API_v1 {}
        history {Description / History and Undo / Redo} SCIENTIFIC_RECIPE_API_v1 {}
    } {dict set result $type [dict create label $label api_id $api api_version [expr {$type eq {plot} ? 4 : 1}] owner core/tcl/viewer_gui_host_api_v1.tcl properties $properties events [expr {$type in {native2d plot} ? {selection view_changed} : {invoke}}] status AVAILABLE]}
    dict set result checkbutton properties plot_visibility dictionary
    foreach type {toggle checkbutton action} {dict set result $type properties component_visibility identifier}
    foreach type {menu context_menu command_toolbar} {dict set result $type properties visibility_commands dictionary}
    foreach {key datatype} {scientific_provider string scientific_parameters dictionary scientific_destination identifier scientific_status identifier scientific_log identifier} {dict set result section properties $key $datatype}
    foreach {key datatype} {scientific_sweep_axes dictionary scientific_sweep_enabled identifier scientific_sweep_case identifier scientific_sweep_workers identifier scientific_sweep_fail_fast identifier} {dict set result section properties $key $datatype}
    foreach key {scientific_probe_diagram scientific_probe_plot scientific_probe_mode scientific_probe_ac_form} {dict set result section properties $key identifier}
    foreach key {scientific_netlist scientific_netlist_diagram scientific_netlist_action} {dict set result section properties $key identifier}
    foreach key {plot_dataset plot_x plot_y plot_probe plot_x_scale plot_y_scale} {dict set result section properties $key identifier}
    foreach key {plot_series plot_series_label plot_series_axis plot_series_enabled plot_panel plot_panel_title plot_series_target plot_series_status} {dict set result section properties $key identifier}
    dict set result section properties plot_series_commands dictionary
    foreach key {numeric_dataset numeric_expression numeric_start numeric_count numeric_output_unit numeric_x numeric_status numeric_report numeric_source numeric_statistic numeric_observed numeric_relative_floor} {dict set result section properties $key identifier}
    foreach key {numeric_variables numeric_parameters} {dict set result section properties $key dictionary}
    dict set result section properties numeric_kind choice
    dict set result section properties catalog_owner choice
    foreach key {catalog_records catalog_mode catalog_filter catalog_info catalog_capabilities catalog_entries catalog_log catalog_status catalog_count catalog_extra_action catalog_page} {dict set result section properties $key identifier}
    dict set result section properties catalog_actions dictionary
    foreach key {numeric_y numeric_query_dataset numeric_query_x numeric_query_start numeric_query_count numeric_method numeric_extrapolation numeric_real numeric_imaginary numeric_projection} {dict set result section properties $key identifier}
    foreach key {tex_source tex_pdf tex_projects tex_assets tex_diagnostics tex_log tex_status tex_info tex_source_status tex_pdf_status} {dict set result section properties $key identifier}
    dict set result section properties em_parameters dictionary
    dict set result section properties em_actions dictionary
    dict set result section properties workbench_parameters dictionary
    foreach key {workbench_viewport workbench_documents workbench_objects workbench_selection workbench_selection_mode workbench_unit workbench_status} {dict set result section properties $key identifier}
    foreach key {em_models em_jobs em_status em_log em_report em_output_id em_dataset em_field_plot em_profile_plot em_field_native3d} {dict set result section properties $key identifier}
    dict set result plot properties plot_form identifier
    foreach type {action label status checkbutton toggle} {
        foreach {key datatype} {icon string icon_disabled string icon_hover string icon_selected string presentation choice icon_position choice icon_size number icon_spacing number} {dict set result $type properties $key $datatype}
    }
    dict set result action properties diagram_tool list
    dict set result action properties raster_tool list
    dict set result action properties raster_command list
    dict set result section properties viewport_anchor dictionary
    dict set result section properties annotation_fields dictionary
    foreach type {command_toolbar menu context_menu} {dict set result $type properties command_icons dictionary}
    dict set result context_menu properties semantic_viewport identifier
    dict set result context_menu properties semantic_rules dictionary
    foreach type {field toggle choice dataset_selector entry combobox checkbutton list} {dict set result $type properties change_action identifier}
    dict set result native3d [dict create label {Native3D embedded viewport} api_id NATIVE_3D_GUI_HOST_API_v2 api_version 2 owner core/tcl/native3d_gui_host_v2.tcl properties {title string width number height number projection choice camera_position string camera_target string camera_up string axes_world boolean navigation_cube_visible boolean demo boolean} events {ready view_changed selected error source_changed released} status AVAILABLE]
    dict set result editable3d [dict create label {Native3D canonical geometry editor} api_id WORKBENCH_3D_API_v1 api_version 1 owner plugins/modules/viewer.3d_workbench/api/workbench_3d_api_v1.tcl properties {title string} events {ready selected view_changed error released} status AVAILABLE]
    foreach {type owner} {native2d core/tcl/native2d_viewport_curve_source.tcl plot plugins/modules/plot.dataset/api/plot_dataset_api_v4.tcl menu core/tcl/configuration_viewer_commands.tcl help app/gui/documentation_module_window.tcl workspace core/tcl/session_workspace_api_v1.tcl history core/tcl/scientific_recipe_history.tcl} {dict set result $type owner $owner}
    dict for {type descriptor} $result {
        dict set descriptor supported_parents [expr {$type eq {menu} ? {menubar} : ($type eq {context_menu} ? {canvas} : ($type eq {command_toolbar} ? {toolbar} : ($type in {workspace history help} ? {footer} : ($type eq {tab} ? {tabs} : {toolbar inspector canvas footer panel section splitter tab}))))}]
        dict set descriptor construction [expr {[dict exists [uiFieldComponentCapabilities] $type] ? {::GX::uiFieldComponentCreate} : {::GX::viewerGuiDesignCompose}}]
        dict set descriptor callback_signature [expr {$type eq {action} ? {window action -> status} : {CORE event -> component ID and redacted detail}}]
        dict set descriptor limitations [expr {$type in {native2d plot} ? {Empty until an explicit public scientific source binding; display is not scientific authority.} : ($type in {history workspace} ? {Requires a current Session; saved state uses existing Workspace/History owners.} : ($type eq {table} ? {Read-only bounded pages; no Worksheet formulas or editing.} : {Only declared properties and events are supported.}))}]
        if {[info exists ::GX::ComponentDemo::specs]&&[dict exists $::GX::ComponentDemo::specs $type]} {dict set descriptor demo [dict create api_id VIEWER_COMPONENT_DEMO_API_v1 fixture_version 1 provenance demo_fixture]}
        dict set result $type $descriptor
    }
    return $result
}
proc ::GX::viewerGuiDesignAction {window id} {
    if {![viewerGuiDesignGuard $window]} {return [dict create status rejected message {Viewer belongs to a previous Session.}]}
    set instance [dict get $::GX::ViewerGui::instances $window]
    if {[dict get $instance mode] eq {demo}} {return [viewerGuiDemoAction $window $id]}
    set correlation [viewerGuiTraceEmit $window $id invoke [dict create status started]]
    set started [clock microseconds]
    set status not_connected
    set statusMessage {}
    set navigate 0
    if {$id in {undo redo} && [dict exists $::GX::ScientificHistory::viewers $window]} {
        set record [scientificHistoryViewerRecord $window]
        set navigate [expr {$id eq {undo} ? [dict get $record cursor]>0 : [dict get $record cursor]<[llength [dict get $record steps]]}]
    }
    try {
        if {[dict exists [viewerGuiDesignDiagramToolBindings [dict get $instance design]] $id]} {
            lassign [dict get [viewerGuiDesignDiagramToolBindings [dict get $instance design]] $id] target tool
            viewerGuiDesignDiagramCommand $window $target tool $tool
            set status completed
        } elseif {[dict exists [viewerGuiDesignRasterToolBindings [dict get $instance design]] $id]} {
            viewerGuiDesignRasterTool $window {*}[dict get [viewerGuiDesignRasterToolBindings [dict get $instance design]] $id]
            set status completed
        } elseif {[dict exists [viewerGuiDesignRasterCommandBindings [dict get $instance design]] $id]} {
            viewerGuiDesignRasterCommand $window {*}[dict get [viewerGuiDesignRasterCommandBindings [dict get $instance design]] $id]
            set status completed
        } elseif {$navigate} {scientificHistoryViewerNavigate $window $id;set status completed} elseif {[set seriesAction [_viewerGuiPlotSeriesAction $window $id]] ne {}} {
            viewerGuiDesignPlotSeries $window {*}$seriesAction;set status completed
        } elseif {[set netlistForm [_viewerGuiScientificNetlistAction $window $id]] ne {}} {
            viewerGuiDesignScientificNetlist $window $netlistForm;set status completed
        } elseif {[dict exists [viewerGuiDesignVisibilityCommands [dict get $instance design]] $id]} {
            set target [dict get [viewerGuiDesignVisibilityCommands [dict get $instance design]] $id]
            viewerGuiDesignComponentVisible $window $target [expr {![viewerGuiDesignComponentVisibleGet $window $target]}]
            if {[dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerChanged $window "Toggle pane $target"}
            set status completed
        } elseif {$id in {fit zoom_in zoom_out}} {
            dict for {component widget} [dict get $instance widgets] {
                if {[winfo exists $widget.curve] && ![catch {native2DViewportCurveDescribe $widget.curve}]} {
                    set op [expr {$id eq {fit} ? {fit} : {zoom}}]
                    if {$op eq {fit}} {native2DViewportCurveNavigate $widget.curve fit} else {native2DViewportCurveNavigate $widget.curve zoom [expr {$id eq {zoom_in} ? 1.25 : 0.8}] [expr {[winfo width $widget.curve]/2}] [expr {[winfo height $widget.curve]/2}]}
                    set status completed
                }
                if {[dict exists $instance demo_bindings $component]} {
                    set fixture [dict get $instance demo_bindings $component fixture]
                    set temporary [dict get $instance demo_bindings $component widget]
                    if {$fixture eq {native2d}} {
                        if {$id eq {fit}} {native2DTemporaryDisplayNavigate $temporary fit} else {native2DTemporaryDisplayNavigate $temporary zoom [expr {$id eq {zoom_in}?1.25:0.8}] [expr {[winfo width $temporary]/2}] [expr {[winfo height $temporary]/2}]}
                    } elseif {$fixture eq {plot}} {nativePlotDisplayView $widget.plot [expr {$id eq {fit}?{fit}:{zoom}}] [expr {$id eq {zoom_in}?1.25:0.8}]}
                    set status completed
                }
                if {[dict exists $instance native3d $component]} {
                    set h [dict get $instance native3d $component]
                    if {$id eq {fit}} {native3DViewportCommand $h preset fit_scene} else {native3DViewportNavigate $h zoom [expr {$id eq {zoom_in}?-1:1}] 0}
                    set status completed
                }
                if {[winfo exists $widget.plot]&&![dict exists $instance demo_bindings $component]} {
                    if {$id eq {fit}} {::GX::PlotDatasetAPIv4::widgetView $widget.plot fit} else {
                        foreach panel [dict get $instance bindings $component spec panels] {::GX::PlotDatasetAPIv4::widgetView $widget.plot zoom [dict get $panel id] [expr {$id eq {zoom_in} ? 1.25 : 0.8}] .5 .5}
                    }
                    set status completed
                }
            }
        } elseif {[dict get $instance mode] eq {runtime} && [dict exists $instance handlers $id]} {
            set command [dict get $instance handlers $id]
            if {![catch {dict get $command command} prefix]} {set command $prefix}
            if {![llength [info commands [lindex $command 0]]]} {error "Handler '$id' is not connected."}
            set result [uplevel #0 [list {*}$command $window $id]]
            set status [datasetPublicationV2DictDefault $result status completed]
            set statusMessage [datasetPublicationV2DictDefault $result message {}]
        }
    } on error {message options} {
        viewerGuiTraceEmit $window $id result [dict create status failed message $message elapsed_us [expr {[clock microseconds]-$started}]] $correlation
        dict get $instance slots status
        [dict get $instance slots status] configure -text $message
        return [dict create status failed message $message]
    }
    set display [expr {$status eq {not_connected} ? "Action '$id': not connected" : "Action '$id': $status"}]
    if {$statusMessage ne {}} {append display ": $statusMessage"}
    [dict get $instance slots status] configure -text $display
    set receipt [dict create status $status]
    if {$statusMessage ne {}} {dict set receipt message $statusMessage}
    viewerGuiTraceEmit $window $id result [dict merge $receipt [dict create elapsed_us [expr {[clock microseconds]-$started}]]] $correlation
    return $receipt
}
proc ::GX::viewerGuiDesignActionEnabled {window id} {
    if {![viewerGuiDesignGuard $window]} {return 0}
    set instance [dict get $::GX::ViewerGui::instances $window]
    set anchored [_viewerGuiAnchoredActionEnabled $window $id]
    if {$anchored ne {}} {
        if {[dict exists $instance design handlers $id available] && ![dict get $instance design handlers $id available]} {return 0}
        return $anchored
    }
    set catalog [_viewerGuiCatalogActionEnabled $window $id]
    if {$catalog ne {}} {
        if {[dict exists $instance design handlers $id available] && ![dict get $instance design handlers $id available]} {return 0}
        return $catalog
    }
    set electromagnetic [_viewerGuiEMActionEnabled $window $id]
    if {$electromagnetic ne {}} {
        if {[dict exists $instance design handlers $id available] && ![dict get $instance design handlers $id available]} {return 0}
        return $electromagnetic
    }
    if {[dict exists $instance design handlers $id available]} {return [dict get $instance design handlers $id available]}
    if {$id in {undo redo}} {
        if {![dict exists $::GX::ScientificHistory::viewers $window]} {return 0}
        set record [scientificHistoryViewerRecord $window]
        return [expr {$id eq {undo} ? [dict get $record cursor]>0 : [dict get $record cursor]<[llength [dict get $record steps]]}]
    }
    if {$id in {fit zoom_in zoom_out}} {
        if {[dict exists $instance demo_bindings]&&[dict size [dict get $instance demo_bindings]]} {return 1}
        if {[dict exists $instance native3d]} {dict for {component h} [dict get $instance native3d] {if {[dict get [native3DViewportInspect $h] status] eq {ready}} {return 1}}}
        dict for {component binding} [dict get $instance bindings] {
            set widget [dict get $instance widgets $component]
            if {[dict get $binding kind] eq {native2d} && [winfo exists $widget.curve] && ![catch {native2DViewportCurveDescribe $widget.curve} state] && [dict get $state status] eq {ready}} {return 1}
            if {[dict get $binding kind] eq {plot} && [winfo exists $widget.plot]} {return 1}
        }
        return 0
    }
    if {[dict get $instance mode] eq {runtime} && [dict exists $instance handlers $id]} {
        set handler [dict get $instance handlers $id]
        if {![catch {dict get $handler enabled} callback]} {return [uplevel #0 [list {*}$callback $window $id]]}
    }
    return 1
}
proc ::GX::_viewerGuiPlotViewState axes {
    # Native receipts also contain pixel rectangles and device tick positions.
    # Those depend on tab visibility/window size, not the saved scientific view.
    set view {}
    foreach axis $axes {
        set item {}
        foreach key {panel_id axis limits scale direction} {dict set item $key [dict get $axis $key]}
        lappend view $item
    }
    return $view
}
proc ::GX::viewerGuiDesignCapture window {
    set bindings [dict get $::GX::ViewerGui::instances $window bindings]
    dict for {id binding} $bindings {
        if {[dict get $binding kind] eq {raster}} {dict set bindings $id [_viewerGuiRasterCapture $window $id $binding]}
        if {[dict get $binding kind] eq {diagram}} {
            set widget [dict get $::GX::ViewerGui::instances $window widgets $id].diagram
            if {[dict exists $::GX::Native2DDiagram::viewports $widget]} {
                set token [dict get $::GX::Native2DDiagram::viewports $widget projection scene_token]
                dict set bindings $id view_state [dict get [native2DGeometryCall $token view_state {}] view_state]
            }
        }
        if {[dict get $binding kind] eq {plot}} {
            # A restored, not-yet-mapped widget may still have no live axes.
            # Normalize its retained view too: pixels/tick positions are never
            # a durable scientific view, including during this first frame.
            if {[dict exists $binding view_axes]} {dict set bindings $id view_axes [_viewerGuiPlotViewState [dict get $binding view_axes]]}
            set widget [dict get $::GX::ViewerGui::instances $window widgets $id].plot
            if {[winfo exists $widget]} {
                set receipt [::GX::PlotDatasetAPIv4::widgetReceipt $widget]
                if {[dict exists $receipt axes]} {dict set bindings $id view_axes [_viewerGuiPlotViewState [dict get $receipt axes]]}
            }
        }
    }
    set choices [_viewerGuiEMCapturedChoices $window [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] choice_options {}]]
    return [dict create schema gxtxt.viewer_interface_state.v1 values [_viewerGuiAnchoredCaptureValues $window] bindings $bindings choices $choices visibility [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] component_visibility {}] domain_state [viewerGuiDesignContextGet $window]]
}
proc ::GX::viewerGuiDesignComponent {window id} {
    foreach component [dict get $::GX::ViewerGui::instances $window design components] {if {[dict get $component id] eq $id} {return $component}}
    error "Unknown Viewer component '$id'."
}
# Shared constructor for normal and semantic-panel component mounting. A panel
# changes the disposable parent, never the declared field's owner or contract.
proc ::GX::_viewerGuiDesignUIFieldMount {window component widget mode context {callback {}}} {
    set id [dict get $component id];set type [dict get $component type];set p [dict get $component properties]
    if {$callback eq {}} {
        set callback [list ::GX::viewerGuiDesignFieldChanged $window $id]
        if {$type eq {action}} {set callback [list ::GX::viewerCommandInvoke $window [dict get $p action]]}
    }
    set componentContext {}
    if {$mode eq {demo} && $type eq {dataset_selector}} {set componentContext {demo_choices {{Synthetic sensor A} {Synthetic sensor B} {Synthetic calibration}}}}
    uiFieldComponentCreate $widget $type $p ::GX::ViewerGui::values($window,$id) $callback $componentContext
    if {$type eq {dataset_selector} && [dict exists $context dataset_id] && [dict get $context dataset_id] in [$widget.entry cget -values]} {set ::GX::ViewerGui::values($window,$id) [dict get $context dataset_id]}
    return $widget
}
proc ::GX::_viewerGuiDesignTraceMount {window id widget} {
    set tag GXGuiComponent$window.$id
    bind $tag <Button-1> [list ::GX::viewerGuiTraceEmit $window $id selected {status selected}]
    bind $tag <FocusIn> [list ::GX::viewerGuiTraceEmit $window $id selected {status selected}]
    foreach target [list $widget $widget.entry $widget.caption $widget.reset $widget.swatch] {
        if {[winfo exists $target]} {bindtags $target [linsert [bindtags $target] 0 $tag]}
    }
}
proc ::GX::viewerGuiDesignCompose {design window module provider {mode preview} {handlers {}} {context {}}} {
    set design [viewerGuiDesignValidate $design]
    if {$mode ni {preview runtime demo}} {error {Choose preview, demo or runtime mode.}}
    if {$mode eq {demo} && $handlers ne {}} {error {Synthetic demonstrations cannot connect domain handlers}}
    set workspaceName {}
    if {[dict exists $context workspace_name]} {
        if {[datasetPublicationV2DictDefault $context workspace_id {}] ne {new}} {error {A Workspace name belongs only to a new Workspace}}
        set workspaceName [_workspaceName [dict get $context workspace_name]]
    }
    set catalog [dict create gui_inspect [dict create label {Inspect interface}]]
    set commands [dict create gui_inspect [dict create command [list ::GX::viewerGuiRuntimeInspect $window]]]
    set menus {};set history 0;set workspace 0;set help 0;set regions {canvas}
    dict for {id contract} [dict get $design handlers] {
        dict set catalog $id [dict create label [datasetPublicationV2DictDefault $contract label [string totitle [string map {_ { }} $id]]] default [datasetPublicationV2DictDefault $contract default {}]]
        dict set commands $id [dict create command [list ::GX::viewerGuiDesignAction $window $id] enabled [list ::GX::viewerGuiDesignActionEnabled $window $id]]
        if {[dict exists [viewerGuiDesignVisibilityCommands $design] $id]} {dict set commands $id checked [list ::GX::viewerGuiDesignVisibilityChecked $window $id]}
    }
    dict for {id pair} [viewerGuiDesignDiagramToolBindings $design] {
        dict set commands $id checked [list ::GX::viewerGuiDesignDiagramToolChecked $window {*}$pair]
    }
    dict for {id pair} [viewerGuiDesignRasterToolBindings $design] {
        dict set commands $id checked [list ::GX::viewerGuiDesignRasterToolChecked $window {*}$pair]
    }
    foreach component [dict get $design components] {
        set properties [dict get $component properties];set type [dict get $component type]
        if {$type eq {action}} {
            set id [dict get $properties action]
            dict set catalog $id [dict create label [dict get $properties label] default [datasetPublicationV2DictDefault $properties shortcut {}]]
        } elseif {$type eq {menu}} {lappend menus $properties} elseif {$type eq {history}} {set history 1} elseif {$type eq {workspace}} {set workspace 1} elseif {$type eq {help}} {set help 1}
        set parent [dict get $component parent];if {$parent in {toolbar inspector footer} && ($type ni {menu context_menu workspace help}||$mode eq {demo})} {lappend regions $parent}
    }
    set commandCatalog [datasetPublicationV2DictDefault $context command_catalog $module.$provider.design_commands]
    set shortcutKey design_shortcuts_[format %08x [zlib crc32 [list [dict get $design module_id] [dict get $design provider_id]]]]
    viewerCommandCatalogRegister $commandCatalog $catalog {} $shortcutKey $module
    set manifest [dict create schema gxtxt.viewer_gui_manifest.v1 viewer_id $module provider_id $provider command_catalog $commandCatalog window $window title [dict get $design title] handlers $commands menus $menus geometry [dict get $design geometry] toolbar_mode declarative help $help]
    foreach component [dict get $design components] {if {[dict get $component type] eq {context_menu}} {dict set manifest context_actions [dict get $component properties actions]}}
    if {[dict exists $design shell inspector_width]} {dict set manifest inspector_width [dict get $design shell inspector_width]}
    if {$mode eq {demo}} {set history 0;set workspace 0;set help 0;lappend regions footer}
    if {[dict exists $design shell status]} {lappend regions footer}
    set token {};if {$mode ne {demo}} {catch {set token [interactiveDocumentSessionToken]}}
    set slots [viewerGuiCompose $manifest]
    set payload {};set workspaceId [datasetPublicationV2DictDefault $context workspace_id {}]
    set stamp {}
    if {$workspaceId ni {{} new}} {set item [sessionWorkspaceGet $workspaceId];set payload [dict get $item payload];set stamp [list [dict get $item generation] [dict get $item revision] [dict get $item sha256]]} else {set workspaceId {}}
    dict set ::GX::ViewerGui::instances $window [dict create design $design module [dict get $design module_id] provider [dict get $design provider_id] mode $mode handlers $handlers slots $slots widgets {} token $token opened_us [clock microseconds] traces {} subscriptions {} workspace_id $workspaceId workspace_name $workspaceName workspace_stamp $stamp bindings {} restoring 0 help $help]
    _viewerGuiAnchoredInitialize $window
    bind $window <Destroy> +[list ::GX::viewerGuiDesignDispose $window %W]
    bind $window <Configure> +[list ::GX::_viewerGuiGeometrySchedule $window %W]
    try {
        set index 0;set widgets {};set actionWidgets {};set policies {}
        foreach component [_viewerGuiDesignParentOrder [dict get $design components]] {
            set id [dict get $component id];set type [dict get $component type];set parent [dict get $component parent];set p [dict get $component properties]
            if {$type in {menu context_menu}||($type in {workspace history help}&&$mode ne {demo})} continue
            if {[dict exists $slots $parent]} {set host [dict get $slots $parent]} else {set host [dict get $widgets $parent]}
            if {$parent eq {footer}} {
                if {![winfo exists $window.footer.designed]} {ttk::frame $window.footer.designed;pack $window.footer.designed -fill x -before [dict get $slots status]}
                set host $window.footer.designed
            }
            set widget $host.$id
            set ::GX::ViewerGui::values($window,$id) [datasetPublicationV2DictDefault $p default [expr {$type in {toggle checkbutton progress} ? 0 : {}}]]
            if {$mode eq {demo}&&$type in {workspace history help}} {
                viewerGuiLifecycleDemoCreate $widget $type [list ::GX::viewerGuiDemoLifecycleEvent $window $id]
            } elseif {$mode eq {demo}&&$type eq {native2d}} {
                native2DTemporaryDisplayCreate $widget [list ::GX::viewerGuiDemoNativeEvent $window $id]
                dict set ::GX::ViewerGui::instances $window demo_bindings $id [dict create fixture native2d widget $widget provenance display_only_RAM scientific_source {}]
            } elseif {$mode eq {demo}&&$type eq {plot}} {
                ttk::frame $widget
                nativePlotDisplayCreate $widget.plot [viewerGuiDemoPlotModel] [list ::GX::viewerGuiDemoNativeEvent $window $id]
                pack $widget.plot -fill both -expand 1
                dict set ::GX::ViewerGui::instances $window demo_bindings $id [dict create fixture plot widget $widget.plot provenance display_only_RAM scientific_source {}]
            } elseif {$type eq {command_toolbar}} {
                set widget $host
                viewerGuiActionsMount $window $widget [dict get $p actions]
            } elseif {$type eq {editable3d}} {
                ttk::frame $widget
                ttk::label $widget.empty -text {Open or create a canonical 3D Document.} -wraplength 400
                pack $widget.empty -fill both -expand 1 -padx 12 -pady 12
            } elseif {$type eq {native3d}} {
                set options $p;dict unset options title;dict unset options demo
                set handle [native3DViewportCreate $widget $options]
                dict set ::GX::ViewerGui::instances $window native3d $id $handle
                foreach event {ready view_changed selected error source_changed} {native3DViewportSubscribe $handle $event [list ::GX::_viewerGuiNative3DEvent $window $id]}
                if {[datasetPublicationV2DictDefault $p demo 0]} {native3DViewportBind $handle {kind demo};dict set ::GX::ViewerGui::instances $window demo_bindings $id [dict create fixture native3d widget $widget provenance display_only_RAM scientific_source {}]}
            } elseif {$type eq {document}} {
                if {[datasetPublicationV2DictDefault $p kind {}] ni {html pdf code table tex}} {error {Document kind must be html, pdf, code, table or declared tex source}}
                ttk::frame $widget
                ttk::label $widget.empty -text {Select a compatible canonical Dataset, then Open.} -wraplength 500
                pack $widget.empty -fill both -expand 1 -padx 12 -pady 12
            } elseif {$type in {native2d plot}} {
                ttk::frame $widget
                # Empty is genuinely empty. Scientific sources are loaded only
                # through an explicit source/Plot binding operation below.
                if {$type ne {plot} || [datasetPublicationV2DictDefault $p empty_style canvas] ne {blank}} {canvas $widget.empty -background white -highlightthickness 0 -width 500 -height 350;pack $widget.empty -fill both -expand 1}
            } else {
                _viewerGuiDesignUIFieldMount $window $component $widget $mode $context
            }
            if {[dict exists $p icon]&&[dict get $p icon] ne {}} {uiFieldIconApply $widget $p [dict get $design icons [dict get $p icon]] [dict get $design icons]}
            dict set widgets $id $widget
            if {$type eq {action}} {dict lappend actionWidgets [dict get $p action] $widget}
            set parentType {};foreach ancestor [dict get $design components] {if {[dict get $ancestor id] eq $parent} {set parentType [dict get $ancestor type];break}}
            set layout [dict get $component layout]
            if {$type eq {command_toolbar}} {
                # Mount in the existing shell toolbar, preserving its layout.
            } elseif {$parentType eq {splitter}} {$host add $widget -weight [datasetPublicationV2DictDefault $layout weight 1]} elseif {$parentType eq {tabs}} {$host add $widget -text [datasetPublicationV2DictDefault $p title $id]} elseif {[datasetPublicationV2DictDefault $layout manager grid] eq {pack}} {uiFieldComponentLayout $widget $host $layout} else {
                set row [datasetPublicationV2DictDefault $layout row 0];set col [datasetPublicationV2DictDefault $layout column 0]
                grid $widget -row $row -column $col -rowspan [datasetPublicationV2DictDefault $layout rowspan 1] -columnspan [datasetPublicationV2DictDefault $layout columnspan 1] -sticky [datasetPublicationV2DictDefault $layout sticky ew] -padx [datasetPublicationV2DictDefault $layout padding 3] -pady [datasetPublicationV2DictDefault $layout padding 3]
                foreach {axis index minimum} [list column $col minimum_width row $row minimum_height] {
                    set policy [datasetPublicationV2DictDefault $policies [list $host $axis $index] {weight 0 minsize 0}]
                    dict set policy weight [expr {max([dict get $policy weight],[datasetPublicationV2DictDefault $layout weight [expr {$axis eq {column} ? 1 : 0}]])}]
                    dict set policy minsize [expr {max([dict get $policy minsize],[datasetPublicationV2DictDefault $layout $minimum 0])}]
                    dict set policies [list $host $axis $index] $policy
                }
            }
            _viewerGuiDesignTraceMount $window $id $widget

        }
        dict for {key policy} $policies {lassign $key host axis index;grid ${axis}configure $host $index -weight [dict get $policy weight] -minsize [dict get $policy minsize]}
        dict set ::GX::ViewerGui::instances $window widgets $widgets
        viewerCommandWidgetsAttach $window $actionWidgets
        dict for {id spec} [_viewerGuiAnchoredDefinitions $design] {
            set placeholder [dict get $widgets $id]
            if {[winfo manager $placeholder] eq {grid}} {grid remove $placeholder} elseif {[winfo manager $placeholder] eq {pack}} {pack forget $placeholder}
        }
        _viewerGuiVisibilityInitialize $window
        _viewerGuiTeXInitialize $window $context
        _viewerGuiEMInitialize $window $context
        _viewerGuiWorkbenchInitialize $window
        if {$payload ne {}} {viewerGuiDesignRestore $window $payload}
        dict set ::GX::ViewerGui::instances $window committed_values [viewerGuiDesignValues $window]
        dict set ::GX::ViewerGui::instances $window saved [viewerGuiDesignCapture $window]
        if {$history && $token ne {}} {
            scientificRecipeHostRegister $module [dict create capture [list ::GX::viewerGuiDesignCapture $window] validate ::GX::viewerGuiDesignHistoryValidate replay ::GX::scientificHistoryState]
            scientificHistoryViewerAttach $window $module [dict create capture [list ::GX::viewerGuiDesignCapture $window] restore [list ::GX::viewerGuiDesignRestore $window] commit [list ::GX::viewerGuiDesignHistoryCommit $window] guard [list ::GX::viewerGuiDesignGuard $window]] [datasetPublicationV2DictDefault $payload history {}]
            dict set ::GX::ViewerGui::instances $window saved_history [scientificHistoryViewerRecord $window]
            scientificHistoryViewerStrip $window [dict get $slots footer] [dict get $slots status]
        }
        if {$workspace && $token ne {}} {
            set wp [datasetPublicationV2DictDefault $context workspace_provider [string map {. _ - _} $module]_${provider}_interface_state]
            set open [datasetPublicationV2DictDefault $context workspace_open [list ::GX::viewerGuiDesignWorkspaceOpen $module $provider $design $mode $handlers]]
            sessionWorkspaceProviderRegister $wp [dict create module_id $module viewer_provider $provider type {Designed Viewer state} schema gxtxt.viewer_interface_state.v1 version 1 validate ::GX::viewerGuiDesignStateValidate open $open]
            set callbacks [dict create current [list ::GX::viewerGuiDesignCurrent $window] save [list ::GX::viewerGuiDesignWorkspaceSave $window] dirty [list ::GX::viewerGuiDesignDirty $window] close [list ::GX::viewerGuiDesignWorkspaceClose $window] open $open discard [list destroy $window]]
            dict set ::GX::ViewerGui::instances $window workspace_provider $wp
            dict set ::GX::ViewerGui::instances $window workspace_callbacks $callbacks
            menu $window.menus.workspace -tearoff 0
            sessionWorkspaceViewerMenu $window.menus.workspace $wp $callbacks $window
            $window.menus add cascade -label Workspace -menu $window.menus.workspace
            if {$help} {documentationBrowserAttachViewerHelp $module $provider $window}
            wm protocol $window WM_DELETE_WINDOW [list ::GX::viewerGuiDesignWorkspaceClose $window]
        } elseif {($workspace || $history) && $token eq {}} {[dict get $slots status] configure -text {Open a Session to enable Workspace and History.}}
        # Restore can replace scientific hosts and relocate their declared
        # children (for example anchored raster controls). Preserve that
        # committed map when specializing the shell-owned menu components.
        set widgets [dict get $::GX::ViewerGui::instances $window widgets]
        set menuIndex 0
        foreach component [dict get $design components] {
            set id [dict get $component id]
            if {$mode eq {demo}&&[dict get $component type] in {workspace history help}} continue
            switch [dict get $component type] {
                menu {dict set widgets $id $window.menus.actions[incr menuIndex]}
                context_menu {dict set widgets $id $window.context}
                help {dict set widgets $id $window.menus}
                workspace {dict set widgets $id $window.menus.workspace}
                history {dict set widgets $id $window.footer.historyStrip}
            }
        }
        dict set ::GX::ViewerGui::instances $window widgets $widgets
        uiFieldViewerRegionsSet $window [lsort -unique $regions]
        _viewerGuiCommandIconsMount $window
        if {[dict exists $design shell status]} {[dict get $slots status] configure -text [dict get $design shell status]}
        if {$mode eq {runtime} && [dict exists $design initial_action]} {viewerGuiDesignAction $window [dict get $design initial_action]}
        if {$workspaceId eq {}} {dict set ::GX::ViewerGui::instances $window saved [viewerGuiDesignCapture $window]}
        return $slots
    } on error {message options} {destroy $window;return -options $options $message}
}
proc ::GX::viewerGuiDesignCurrent window {return [dict get $::GX::ViewerGui::instances $window workspace_id]}
proc ::GX::viewerGuiDesignDirty window {
    foreach form [dict keys [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] tex_forms {}]] {if {[_viewerGuiTeXDirty $window $form]} {return 1}}
    foreach form [dict keys [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] em_forms {}]] {if {[_viewerGuiEMDirty $window $form]} {return 1}}
    foreach form [dict keys [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] workbench_forms {}]] {if {[_viewerGuiWorkbenchDirty $window $form]} {return 1}}
    # A return to the saved visible state can still append meaningful History.
    # Browsing is transient; compare the durable record, including its cursor.
    if {[dict exists $::GX::ScientificHistory::viewers $window] && [scientificHistoryViewerRecord $window] ne [dict get $::GX::ViewerGui::instances $window saved_history]} {return 1}
    return [expr {[viewerGuiDesignCapture $window] ne [dict get $::GX::ViewerGui::instances $window saved]}]
}
proc ::GX::viewerGuiDesignDispose {window actual} {
    if {$window ne $actual} return
    _viewerGuiCatalogDispose $window
    _viewerGuiTeXDispose $window
    if {[dict exists $::GX::ViewerGui::instances $window em_availability_timer]} {after cancel [dict get $::GX::ViewerGui::instances $window em_availability_timer]}
    if {[llength [info commands ::GX::viewerGuiLaboratoryDispose]]} {viewerGuiLaboratoryDispose $window}
    if {[dict exists $::GX::ViewerGui::instances $window resize_timer]} {after cancel [dict get $::GX::ViewerGui::instances $window resize_timer]}
    if {[dict exists $::GX::ViewerGui::instances $window document_watch]} {after cancel [dict get $::GX::ViewerGui::instances $window document_watch]}
    if {[dict exists $::GX::ViewerGui::instances $window]} {
        if {[dict exists $::GX::ViewerGui::instances $window document_readers]} {
            foreach component [dict keys [dict get $::GX::ViewerGui::instances $window document_readers]] {viewerGuiDocumentRelease $window $component}
        }
        if {[dict exists $::GX::ViewerGui::instances $window scientific_preparations]} {
            dict for {form receipt} [dict get $::GX::ViewerGui::instances $window scientific_preparations] {_viewerGuiScientificPreparationDiscard $receipt}
        }
        if {[dict exists $::GX::ViewerGui::instances $window scientific_retained_preparations]} {dict for {form receipt} [dict get $::GX::ViewerGui::instances $window scientific_retained_preparations] {_viewerGuiScientificPreparationDiscard $receipt}}
        foreach component [dict get $::GX::ViewerGui::instances $window design components] {
            set tag GXGuiComponent$window.[dict get $component id]
            foreach sequence [bind $tag] {bind $tag $sequence {}}
        }
        dict unset ::GX::ViewerGui::instances $window
    }
    array unset ::GX::ViewerGui::values $window,*
    dict for {id observer} $::GX::ViewerGui::traces {if {[dict get $observer window] eq $window} {dict unset ::GX::ViewerGui::traces $id}}
}
proc ::GX::viewerGuiDesignFieldChanged {window id args} {
    if {![viewerGuiDesignGuard $window] || [dict get $::GX::ViewerGui::instances $window restoring]} return
    set component [viewerGuiDesignComponent $window $id]
    if {[_viewerGuiAnchoredMember $window $id] ne {}} {return}
    if {[dict get $component type] eq {list}} {set widget [dict get $::GX::ViewerGui::instances $window widgets $id];set ::GX::ViewerGui::values($window,$id) [$widget curselection]}
    set value $::GX::ViewerGui::values($window,$id)
    # Explicitly choosing the already displayed singleton still replaces local
    # multiple candidates. Do this projection before the scalar no-op guard;
    # only the existing Select command changes authoritative geometry selection.
    _viewerGuiWorkbenchSelectionFieldChanged $window $id
    if {[dict exists $::GX::ViewerGui::instances $window committed_values $id] && [dict get $::GX::ViewerGui::instances $window committed_values $id] eq $value} {return}
    dict set ::GX::ViewerGui::instances $window committed_values $id $value
    if {[dict exists $component properties component_visibility] && [dict get $component type] in {toggle checkbutton}} {viewerGuiDesignComponentVisible $window [dict get $component properties component_visibility] $value}
    if {[dict exists $component properties plot_visibility]} {
        set target [dict get $component properties plot_visibility]
        set plot [dict get $::GX::ViewerGui::instances $window widgets [dict get $target component]].plot
        if {[winfo exists $plot]} {
            set visible $::GX::ViewerGui::values($window,$id)
            ::GX::PlotDatasetAPIv4::widgetVisibility $plot [dict get $target panel] [dict get $target series] $visible
            dict set ::GX::ViewerGui::instances $window bindings [dict get $target component] visibility [dict get $target panel] [dict get $target series] $visible
        }
    }
    viewerGuiTraceEmit $window $id changed [dict create status accepted value redacted]
    if {[dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerChanged $window "Change $id"}
    if {[dict exists $component properties change_action]} {viewerCommandInvoke $window [dict get $component properties change_action]}
    viewerGuiActionsRefresh $window
}
proc ::GX::viewerGuiDesignHandlerSource {module provider} {
    set descriptor [viewerProviderDefinition $module $provider 1]
    if {{gui_roundtrip} ni [split [datasetPublicationV2DictDefault $descriptor capabilities {}] {;}] || [datasetPublicationV2DictDefault $descriptor gui_design {}] eq {}} {error {This Viewer does not declare regenerable handler source.}}
    set directory [file normalize [file dirname [moduleField $module descriptor]]]
    set path [file join $directory handlers.tcl]
    if {![file isfile $path] || [file type $path] eq {link} || [file size $path]>4194304} {error {Declared handler source is unavailable or exceeds 4 MiB.}}
    set channel [open $path rb];try {return [read $channel]} finally {close $channel}
}
proc ::GX::viewerGuiDesignGenerate {project sourceDirectory outputDirectory callback} {
    viewerGuiDesignRead $project
    set command [list [runtimeToolRequired python] -B [file join $::GX::scriptDir core python viewer_gui_request.py]]
    return [scriptJobAsync $command [dict create operation generate project [file normalize $project] source_directory [file normalize $sourceDirectory] output_directory [file normalize $outputDirectory]] $callback {timeout_ms 60000 max_bytes 1048576 process_group 1 ui_lifetime 1 label {Viewer module generation}}]
}
proc ::GX::viewerGuiDesignGuard window {
    if {![dict exists $::GX::ViewerGui::instances $window] || ![winfo exists $window]} {return 0}
    set token [dict get $::GX::ViewerGui::instances $window token]
    return [expr {$token eq {} || (![catch {interactiveDocumentSessionToken} current] && $token eq $current)}]
}
proc ::GX::viewerGuiDesignHandlerBindings {module provider} {
    set descriptor [viewerProviderDefinition $module $provider]
    if {$descriptor eq {} || ![dict exists $descriptor gui_handler_command] || [dict get $descriptor gui_handler_command] eq {}} {error {This Viewer does not publish a GUI handler binding factory.}}
    set command [dict get $descriptor gui_handler_command]
    if {[llength $command]!=1 || ![regexp {^::[a-zA-Z_][a-zA-Z0-9_:]*$} $command]} {error {Invalid public Viewer handler factory.}}
    modulePublicApiActivate $module [dict get $descriptor activation_api]
    if {![llength [info commands $command]]} {error {Declared GUI handler factory is unavailable.}}
    set handlers [{*}$command]
    dict for {id binding} $handlers {if {![dict exists $binding command]} {error {Published GUI bindings require a command prefix.}}}
    return $handlers
}
proc ::GX::viewerGuiDesignHistoryCommit {window record} {dict set ::GX::ViewerGui::instances $window history $record}
proc ::GX::viewerGuiDesignHistoryValidate record {return [viewerGuiDesignStateValidate [dict get $record base]]}
proc ::GX::viewerGuiDesignImport {module provider} {
    set descriptor [viewerProviderDefinition $module $provider 1]
    set query [datasetPublicationV2DictDefault $descriptor gui_design_command {}]
    if {$query ne {}} {
        if {[llength $query]!=1 || ![regexp {^::[a-zA-Z_][a-zA-Z0-9_:]*$} $query]} {error {Invalid public GUI design query.}}
        modulePublicApiActivate $module [dict get $descriptor activation_api]
        set report [{*}$query]
        if {[dict exists $report design]} {dict set report design [viewerGuiDesignValidate [dict get $report design]]}
        return $report
    }
    set path [datasetPublicationV2DictDefault $descriptor gui_design {}]
    if {$path ne {}} {
        set root [file normalize [file dirname [moduleField $module descriptor]]]
        set file [file normalize [file join $root $path]]
        if {![string match $root/* $file]} {error {Viewer GUI design path escapes its module.}}
        set report [dict create status FULL_DECLARATIVE design [viewerGuiDesignRead $file] boundaries {}]
        foreach window [viewerGuiPublishedWindows $module $provider] {
            if {[viewerGuiDesignGuard $window]} {dict set report state [viewerGuiDesignCapture $window];break}
        }
        return $report
    }
    set source [viewerGuiManifestDescribe $module $provider]
    if {[dict exists $source status]} {return $source}
    set design [viewerGuiDesignNew [dict get $source title]];set components {};set handlers {}
    set i 0;set row 0
    dict for {id handler} [dict get $source handlers] {dict set handlers $id [dict create arguments {window action} effect unbound]}
    foreach id [datasetPublicationV2DictDefault $source toolbar_actions {}] {
        if {$id eq {-}} continue
        lappend components [dict create id action_[incr i] type action parent toolbar properties [dict create action $id label [datasetPublicationV2DictDefault [dict get [viewerCommandCatalog $module] $id] label $id]] layout [dict create row 0 column $row]];incr row
    }
    foreach menu [datasetPublicationV2DictDefault $source menus {}] {lappend components [dict create id menu_[incr i] type menu parent menubar properties $menu layout {}]}
    if {[dict exists $source canvas]} {lappend components [dict create id scientific_view type [expr {[dict get $source canvas api_id] eq {PLOT_DATASET_API_v4} ? {plot} : {native2d}}] parent canvas properties {} layout {row 0 column 0 weight 1 sticky nsew}]}
    foreach kind {workspace history} {if {[dict exists $source $kind]} {lappend components [dict create id $kind type $kind parent footer properties {} layout {}]}}
    dict set design components $components;dict set design handlers $handlers
    foreach component $components {set cap [dict get [viewerGuiComponentCapabilities] [dict get $component type]];dict set design requirements [dict get $cap api_id] [dict get $cap api_version]}
    dict set design origin [dict create module $module provider $provider source_schema [dict get $source schema]]
    return [dict create status DECLARED_HOST_ONLY design [viewerGuiDesignValidate $design] boundaries [list [dict create classification coverage_limitation owner $module behavior {Custom inspector construction, scientific canvas binding and domain callbacks outside the published manifest are not represented.}]]]
}
proc ::GX::viewerGuiDesignModelCreate design {return [dict create schema gxtxt.viewer_design_model.v1 design [viewerGuiDesignValidate $design] saved $design past {} future {} revision 0]}
proc ::GX::_viewerGuiDesignRelocateLayout {layout components parent {excluded {}}} {
    set row 0;set manager [datasetPublicationV2DictDefault $layout manager grid]
    foreach item $components {
        if {[dict get $item parent] ne $parent || [dict get $item id] in $excluded || [dict get $item type] in {menu help history workspace context_menu command_toolbar}} continue
        set sibling [dict get $item layout];set manager [datasetPublicationV2DictDefault $sibling manager grid]
        set row [expr {max($row,[datasetPublicationV2DictDefault $sibling row 0]+[datasetPublicationV2DictDefault $sibling rowspan 1])}]
    }
    dict set layout manager $manager
    if {$manager eq {pack}} {
        foreach key {row column rowspan columnspan sticky} {dict unset layout $key}
        if {![dict exists $layout fill]} {dict set layout fill x}
    } else {
        foreach key {side fill expand anchor padx pady} {dict unset layout $key}
        dict set layout row $row;dict set layout column 0
    }
    return $layout
}
proc ::GX::_viewerGuiDesignParentOrder {components} {
    set known {toolbar inspector canvas footer menubar};set ordered {}
    while {[llength $components]} {
        set pending {};set count 0
        foreach item $components {
            if {[dict get $item parent] in $known} {lappend ordered $item;lappend known [dict get $item id];incr count} else {lappend pending $item}
        }
        if {!$count} {error {The design has a missing or cyclic container.}}
        set components $pending
    }
    return $ordered
}
proc ::GX::viewerGuiDesignModelEdit {model operation args} {
    set design [dict get $model design];set components [dict get $design components]
    set index -1;set id [lindex $args 0]
    for {set i 0} {$i<[llength $components]} {incr i} {if {[dict get [lindex $components $i] id] eq $id} {set index $i;break}}
    set prior $design
    switch $operation {
        icon {set design [viewerGuiIconEdit $design {*}$args];set components [dict get $design components]}
        add {
            set item [lindex $args 0];set actions {}
            set capability [dict get [viewerGuiComponentCapabilities] [dict get $item type]]
            dict set design requirements [dict get $capability api_id] [dict get $capability api_version]
            if {[dict get $item type] eq {action}} {set actions [list [dict get $item properties action]]} elseif {[dict get $item type] in {menu context_menu command_toolbar}} {set actions [dict get $item properties actions]}
            if {[dict exists $item properties change_action]} {lappend actions [dict get $item properties change_action]}
            foreach action $actions {if {$action ne {-} && ![dict exists $design handlers $action]} {dict set design handlers $action [dict create arguments {window action} effect unbound]}}
            lappend components $item
        }
        properties {
            if {$index<0} {error {Select a component}}
            set item [lindex $components $index];dict set item properties [dict merge [dict get $item properties] [lindex $args 1]]
            lset components $index $item
        }
        property - layout - constraints {
            if {$index<0} {error {Select a component.}}
            set item [lindex $components $index]
            set field [expr {$operation eq {property} ? {properties} : {layout}}]
            if {$operation eq {constraints}} {dict set item layout [dict merge [dict get $item layout] [lindex $args 1]]} else {dict set item $field [lindex $args 1] [lindex $args 2]}
            lset components $index $item
        }
        bind {
            if {$index<0} {error {Select an action, menu or input component.}}
            lassign $args id action effect
            dict set design handlers $action [dict create arguments {window action} effect $effect]
            set item [lindex $components $index];set type [dict get $item type]
            if {$type eq {action}} {dict set item properties action $action} elseif {$type in {menu context_menu command_toolbar}} {
                if {$action ni [dict get $item properties actions]} {set actions [dict get $item properties actions];lappend actions $action;dict set item properties actions $actions}
            } elseif {$type in {field toggle choice dataset_selector entry combobox checkbutton list}} {dict set item properties change_action $action} else {error {This component emits no bindable action/change event.}}
            lset components $index $item
        }
        reparent {
            if {$index<0} {error {Select a component.}}
            set subtree [list $id]
            foreach item [_viewerGuiDesignParentOrder $components] {if {[dict get $item parent] in $subtree} {lappend subtree [dict get $item id]}}
            set parent [lindex $args 1]
            if {$parent in $subtree} {error {A container cannot be placed inside itself.}}
            set item [lindex $components $index]
            dict set item parent $parent
            dict set item layout [_viewerGuiDesignRelocateLayout [dict get $item layout] $components $parent $subtree]
            # Declaration positions are the restricted SDK identities.
            # Construction order is derived separately, never persisted.
            lset components $index $item
        }
        remove - duplicate {
            if {$index<0} {error {Select a component.}}
            set subtree [list $id]
            foreach item [_viewerGuiDesignParentOrder $components] {if {[dict get $item parent] in $subtree} {lappend subtree [dict get $item id]}}
            if {$operation eq {remove}} {set kept {};foreach item $components {if {[dict get $item id] ni $subtree} {lappend kept $item}};set components $kept} else {
                set parent [dict get [lindex $components $index] parent]
                if {$operation eq {reparent}} {set parent [lindex $args 1];if {$parent in $subtree} {error {A container cannot be placed inside itself.}}}
                set existing {};foreach item $components {lappend existing [dict get $item id]}
                set additions {};set kept {};set mapping {}
                foreach old $subtree {set fresh $old;set n 1;while {$fresh in $existing} {set fresh ${old}_copy[incr n]};dict set mapping $old $fresh;lappend existing $fresh}
                foreach item $components {
                    set old [dict get $item id]
                    if {$old ni $subtree || $operation eq {duplicate}} {lappend kept $item}
                    if {$old ni $subtree} continue
                    set fresh $old
                    if {$operation eq {duplicate}} {set fresh [dict get $mapping $old];dict set item id $fresh}
                    if {$old eq $id} {
                        dict set item parent $parent
                        set excluded [expr {$operation eq {reparent} ? $subtree : {}}]
                        dict set item layout [_viewerGuiDesignRelocateLayout [dict get $item layout] $components $parent $excluded]
                    } elseif {[dict exists $mapping [dict get $item parent]]} {dict set item parent [dict get $mapping [dict get $item parent]]}
                    lappend additions $item
                }
                set components [concat $kept $additions]
            }
        }
        reorder {
            if {$index<0} {error {Select a component.}}
            set item [lindex $components $index];set parent [dict get $item parent];set candidates {}
            for {set j 0} {$j<[llength $components]} {incr j} {set c [lindex $components $j];if {[dict get $c parent] eq $parent} {lappend candidates [list [datasetPublicationV2DictDefault [dict get $c layout] row 0] [datasetPublicationV2DictDefault [dict get $c layout] column 0] $j]}}
            set candidates [lsort -integer -index 0 $candidates];set at -1
            for {set j 0} {$j<[llength $candidates]} {incr j} {if {[lindex [lindex $candidates $j] 2]==$index} {set at $j;break}}
            set other [expr {$at+[lindex $args 1]}]
            if {$other<0 || $other>=[llength $candidates]} {return $model}
            set j [lindex [lindex $candidates $other] 2];set second [lindex $components $j]
            if {[dict get $item type] eq {menu} || [datasetPublicationV2DictDefault [dict get $item layout] manager grid] eq {pack}} {set swap $item;set item $second;set second $swap} else {set layout [dict get $item layout];dict set item layout [dict get $second layout];dict set second layout $layout}
            lset components $index $item;lset components $j $second
        }
        swap {
            if {$index<0} {error {Select a component.}}
            set target [lindex $args 1];set other -1
            for {set j 0} {$j<[llength $components]} {incr j} {if {[dict get [lindex $components $j] id] eq $target} {set other $j;break}}
            if {$other<0} {error {Select a declared sibling target.}}
            set item [lindex $components $index];set second [lindex $components $other]
            if {[dict get $item parent] ne [dict get $second parent]} {error {Direct grid swap requires siblings.}}
            if {[datasetPublicationV2DictDefault [dict get $item layout] manager grid] ne {grid}} {error {Packed components use Move up / Move down to reorder.}}
            set layout [dict get $item layout];dict set item layout [dict get $second layout];dict set second layout $layout
            lset components $index $item;lset components $other $second
        }
        paste {
            lassign $args subtree parent
            dict for {action contract} [lindex $args 2] {
                if {[dict exists $design handlers $action] && [dict get $design handlers $action] ne $contract} {error "Pasted action '$action' has a conflicting contract."}
                dict set design handlers $action $contract
            }
            set ids {};foreach item $components {lappend ids [dict get $item id]}
            set mapping {};set rootId [dict get [lindex $subtree 0] id]
            foreach item $subtree {
                set old [dict get $item id];set fresh $old;set n 1
                while {$fresh in $ids} {set fresh ${old}_copy[incr n]}
                dict set mapping $old $fresh;lappend ids $fresh;dict set item id $fresh
                if {$old eq $rootId} {dict set item parent $parent;dict set item layout [_viewerGuiDesignRelocateLayout [dict get $item layout] $components $parent]} else {dict set item parent [dict get $mapping [dict get $item parent]]}
                set cap [dict get [viewerGuiComponentCapabilities] [dict get $item type]]
                dict set design requirements [dict get $cap api_id] [dict get $cap api_version]
                lappend components $item
            }
        }
        metadata {if {[lindex $args 0] eq {inspector_width}} {dict set design shell inspector_width [lindex $args 1]} else {dict set design [lindex $args 0] [lindex $args 1]}}
        default {error {Unknown Viewer design edit operation.}}
    }
    dict set design components $components;set design [viewerGuiDesignValidate $design]
    if {$design eq $prior} {return $model}
    set past [dict get $model past];lappend past $prior
    dict set model past [lrange $past end-49 end];dict set model future {};dict set model design $design;dict incr model revision
    return $model
}
proc ::GX::viewerGuiDesignModelNavigate {model direction} {
    if {$direction ni {undo redo}} {error {Choose Undo or Redo.}}
    set from [expr {$direction eq {undo} ? {past} : {future}}];set to [expr {$direction eq {undo} ? {future} : {past}}]
    set stack [dict get $model $from];if {![llength $stack]} {return $model}
    dict lappend model $to [dict get $model design];dict set model design [lindex $stack end];dict set model $from [lrange $stack 0 end-1];dict incr model revision
    return $model
}
proc ::GX::viewerGuiDesignNew {{title {Untitled Viewer}}} {
    return [dict create schema gxtxt.viewer_design.v1 title $title module_id viewer.generated_interface provider_id generated_interface version 1.0.0 geometry 1100x720 requirements {VIEWER_GUI_HOST_API_v1 1 UI_FIELD_API_v1 1} components {} handlers {} origin {}]
}
proc ::GX::viewerGuiDesignPlotSet {window component spec {context {}}} {
    if {![viewerGuiDesignGuard $window]} {error {Plot belongs to a previous Session.}}
    set definition [viewerGuiDesignComponent $window $component]
    if {[dict get $definition type] ne {plot}} {error {Select a Plot Dataset v4 slot.}}
    if {[dict exists $definition properties title]} {dict set spec title [dict get $definition properties title]}
    modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
    set widget [dict get $::GX::ViewerGui::instances $window widgets $component]
    if {[winfo exists $widget.plot]} {
        # The existing Plot owner validates/model-builds before configure, so
        # domain/source errors retain the prior native frame and binding.
        set plot [::GX::PlotDatasetAPIv4::widgetConfigure $widget.plot $spec $context]
    } else {
        set plot [::GX::PlotDatasetAPIv4::widgetCreate $widget.plot $spec $context]
        foreach child [winfo children $widget] {if {$child ne $plot} {destroy $child}}
        pack $plot -fill both -expand 1
        _viewerGuiPlotAttach $window $component $plot
        viewerGuiSourceScopeAttach $window $component $plot
        if {[dict exists $::GX::ViewerGui::instances $window slots context_menu]} {viewerGuiContextMount $window $plot}
    }
    if {[dict exists $::GX::ViewerGui::instances $window demo_bindings $component]} {dict unset ::GX::ViewerGui::instances $window demo_bindings $component}
    dict set ::GX::ViewerGui::instances $window bindings $component [dict create kind plot spec $spec context $context]
    _viewerGuiPlotBindingChanged $window $component
    if {![dict get $::GX::ViewerGui::instances $window restoring] && [dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerChanged $window "Bind Plot $component"}
    viewerGuiActionsRefresh $window
    return $plot
}
proc ::GX::viewerGuiDesignPublish {window design widgets values bindings {boundaries {}}} {
    set design [viewerGuiDesignValidate $design]
    if {![dict exists $::GX::ViewerGui::shells $window]} {error {Publish requires the existing CORE Viewer GUI shell.}}
    foreach component [dict get $design components] {
        set id [dict get $component id]
        if {![dict exists $widgets $id] || ![winfo exists [dict get $widgets $id]]} {error "Published component '$id' has no actual owner widget."}
    }
    set old [datasetPublicationV2DictDefault $::GX::ViewerGui::instances $window {}]
    set instance [dict create design $design mode observed handlers {} slots [dict get $::GX::ViewerGui::shells $window slots] widgets $widgets token [interactiveDocumentSessionToken] opened_us [datasetPublicationV2DictDefault $old opened_us [clock microseconds]] traces [datasetPublicationV2DictDefault $old traces {}] subscriptions {} workspace_id {} workspace_stamp {} bindings $bindings restoring 0 help 1 boundaries $boundaries]
    dict set ::GX::ViewerGui::instances $window $instance
    dict for {id value} $values {set ::GX::ViewerGui::values($window,$id) $value}
    foreach component [dict get $design components] {
        set id [dict get $component id];set widget [dict get $widgets $id];set tag GXGuiComponent$window.$id
        bind $tag <Button-1> [list ::GX::viewerGuiTraceEmit $window $id selected {status selected}]
        if {$tag ni [bindtags $widget]} {bindtags $widget [linsert [bindtags $widget] 0 $tag]}
    }
    if {$old eq {}} {
        bind $window <Destroy> +[list ::GX::viewerGuiDesignDispose $window %W]
        bind $window <Configure> +[list ::GX::_viewerGuiGeometrySchedule $window %W]
    }
    return [dict create design $design state [viewerGuiDesignCapture $window] boundaries $boundaries]
}
proc ::GX::viewerGuiDesignRead path {
    if {![file isfile $path] || [file size $path]>4194304} {error {Viewer project is unavailable or exceeds 4 MiB.}}
    set f [open $path r];fconfigure $f -encoding utf-8
    try {set design [read $f 4194305]} finally {close $f}
    return [viewerGuiDesignValidate $design]
}
proc ::GX::viewerGuiDesignRestore {window state} {
    viewerGuiDesignStateValidate $state
    _viewerGuiTeXRestoreCheck $window [datasetPublicationV2DictDefault $state domain_state {}]
    _viewerGuiEMRestoreCheck $window [datasetPublicationV2DictDefault $state domain_state {}]
    _viewerGuiWorkbenchRestoreCheck $window [datasetPublicationV2DictDefault $state domain_state {}]
    dict for {id binding} [datasetPublicationV2DictDefault $state bindings {}] {
        if {[dict get $binding kind] eq {document}} {_viewerGuiDocumentRestoreCheck $window $id $binding}
        if {[dict get $binding kind] eq {raster}} {_viewerGuiRasterRestoreCheck $window $id $binding}
    }
    dict set ::GX::ViewerGui::instances $window restoring 1
    try {
        viewerGuiDesignContextSet $window [datasetPublicationV2DictDefault $state domain_state {}]
        _viewerGuiTeXRestore $window
        _viewerGuiEMRestore $window [dict get $state values]
        dict for {id choices} [datasetPublicationV2DictDefault $state choices {}] {if {[dict exists $::GX::ViewerGui::instances $window widgets $id]} {viewerGuiDesignChoicesSet $window $id $choices}}
        _viewerGuiVisibilityRestore $window [datasetPublicationV2DictDefault $state visibility {}]
        dict for {id value} [dict get $state values] {
            if {![info exists ::GX::ViewerGui::values($window,$id)]} continue
            set definition [viewerGuiDesignComponent $window $id]
            if {[dict get $definition type] eq {tabs} && $value ne {}} {
                set page [viewerGuiDesignComponent $window $value]
                if {[dict get $page type] ne {tab} || [dict get $page parent] ne $id} {error {Saved notebook selection must name its own declared tab}}
                set widgets [dict get $::GX::ViewerGui::instances $window widgets]
                if {[viewerGuiDesignComponentVisibleGet $window $value]} {[dict get $widgets $id] select [dict get $widgets $value]}
            } elseif {[dict get $definition type] in {field toggle choice dataset_selector progress entry combobox checkbutton list}} {viewerGuiDesignValueSet $window $id $value} else {set ::GX::ViewerGui::values($window,$id) $value}
        }
        set desired [datasetPublicationV2DictDefault $state bindings {}]
        set prior [dict get $::GX::ViewerGui::instances $window bindings]
        dict for {id binding} $prior {
            if {![dict exists $desired $id]} {
                set widget [dict get $::GX::ViewerGui::instances $window widgets $id]
                foreach child [winfo children $widget] {destroy $child}
                canvas $widget.empty -background white -highlightthickness 0;pack $widget.empty -fill both -expand 1
                dict unset ::GX::ViewerGui::instances $window bindings $id
            }
        }
        dict for {id binding} $desired {
            if {[dict exists $prior $id] && [dict get $prior $id] eq $binding} continue
            if {[dict get $binding kind] eq {diagram}} {viewerGuiDesignDiagramSet $window $id [dict get $binding document_id] [dict get $binding payload] [datasetPublicationV2DictDefault $binding view_state {}]
            } elseif {[dict get $binding kind] eq {document}} {
                _viewerGuiDocumentBindDataset $window $id [dict get $binding dataset_id]
            } elseif {[dict get $binding kind] eq {raster}} {
                _viewerGuiRasterBindDataset $window $id [dict get $binding source dataset_id] $binding
            } elseif {[dict get $binding kind] eq {native2d}} {viewerGuiDesignSourceSet $window $id [dict get $binding request] [dict get $binding source_id]} elseif {[dict get $binding kind] eq {plot}} {
                set plot [viewerGuiDesignPlotSet $window $id [dict get $binding spec] [datasetPublicationV2DictDefault $binding context {}]]
                dict for {panel seriesStates} [datasetPublicationV2DictDefault $binding visibility {}] {dict for {series visible} $seriesStates {::GX::PlotDatasetAPIv4::widgetVisibility $plot $panel $series $visible}}
                if {[dict exists $binding view_axes]} {::GX::PlotDatasetAPIv4::widgetView $plot restore [dict get $binding view_axes]}
                dict set ::GX::ViewerGui::instances $window bindings $id $binding
            }
        }
        _viewerGuiNumericRestore $window
        _viewerGuiScientificRestore $window
        _viewerGuiWorkbenchRestore $window
        _viewerGuiVisibilitySync $window
    } finally {dict set ::GX::ViewerGui::instances $window restoring 0}
    viewerGuiActionsRefresh $window
}
proc ::GX::viewerGuiDesignSave {path design} {set design [viewerGuiDesignValidate $design];resourceLifecycleWriteBytes $path [encoding convertto utf-8 $design];return $path}
proc ::GX::viewerGuiDesignSourceReady {window component canvas receipt} {
    if {![dict exists $::GX::ViewerGui::instances $window] || ![winfo exists $canvas]} return
    viewerGuiTraceEmit $window $component source_ready [dict create status [dict get $receipt status]]
    viewerGuiActionsRefresh $window
}
proc ::GX::viewerGuiDesignSourceSelected {window component canvas receipt} {
    set detail [dict create status selected hit [dict get $receipt hit]]
    foreach key {source_id source_row_ordinal row_identity_kind} {if {[dict exists $receipt $key]} {dict set detail $key [dict get $receipt $key]}}
    viewerGuiTraceEmit $window $component selected $detail
}
proc ::GX::viewerGuiDesignSourceSet {window component request {expectedSource {}}} {
    if {![viewerGuiDesignGuard $window]} {error {Viewer source binding belongs to a previous Session.}}
    set definition [viewerGuiDesignComponent $window $component]
    if {[dict get $::GX::ViewerGui::instances $window token] eq {}} {dict set ::GX::ViewerGui::instances $window token [interactiveDocumentSessionToken]}
    if {[dict get $definition type] ne {native2d}} {error {Select a Native2D source slot.}}
    set token [curveSourceOpen $::GX::currentSession $request]
    try {
        set descriptor [curveSourceDescribe $token]
        if {$expectedSource ne {} && [dict get $descriptor source_id] ne $expectedSource} {error {Scientific source changed; rebind it explicitly.}}
    } finally {curveSourceClose $token}
    set widget [dict get $::GX::ViewerGui::instances $window widgets $component]
    foreach child [winfo children $widget] {destroy $child}
    set title [datasetPublicationV2DictDefault [dict get $definition properties] title [dict get $::GX::ViewerGui::instances $window design title]]
    set canvas [native2DViewportCurveCreate $widget $::GX::currentSession $request [dict create title $title selected [list ::GX::viewerGuiDesignSourceSelected $window $component] completed [list ::GX::viewerGuiDesignSourceReady $window $component] view_changed [list ::GX::viewerGuiDesignSourceView $window $component]]]
    pack $canvas -fill both -expand 1
    viewerGuiSourceScopeAttach $window $component $canvas
    if {[dict exists $::GX::ViewerGui::instances $window slots context_menu]} {viewerGuiContextMount $window $canvas}
    if {[dict exists $::GX::ViewerGui::instances $window demo_bindings $component]} {dict unset ::GX::ViewerGui::instances $window demo_bindings $component}
    dict set ::GX::ViewerGui::instances $window bindings $component [dict create kind native2d request $request source_id [dict get $descriptor source_id]]
    if {![dict get $::GX::ViewerGui::instances $window restoring] && [dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerChanged $window "Bind scientific source $component"}
    viewerGuiTraceEmit $window $component source_bound [dict create status loading source_identity [dict get [native2DViewportCurveDescribe $canvas] source]]
    viewerGuiActionsRefresh $window
    return $canvas
}
proc ::GX::viewerGuiDesignSourceView {window component canvas receipt} {
    if {![dict exists $::GX::ViewerGui::instances $window] || ![winfo exists $canvas]} return
    viewerGuiTraceEmit $window $component view_changed [dict merge {status presentation_only} $receipt]
}
proc ::GX::viewerGuiDesignStateValidate payload {
    if {[dict get $payload schema] ne {gxtxt.viewer_interface_state.v1} || [catch {dict size [dict get $payload values]}]} {error {Invalid declarative Viewer state.}}
    return 1
}
proc ::GX::viewerGuiDesignTableSet {window id rows} {
    set component [viewerGuiDesignComponent $window $id]
    if {[dict get $component type] ne {table} || [llength $rows]>1000 || [string bytelength $rows]>4194304} {error {Use a declared table and a bounded page of at most 1000 rows / 4 MiB.}}
    set widget [dict get $::GX::ViewerGui::instances $window widgets $id]
    set table [uiFieldComponentTableWidget $widget]
    $table delete [$table children {}];foreach row $rows {$table insert {} end -values $row}
    if {[datasetPublicationV2DictDefault [dict get $component properties] scrollbars none] in {horizontal both}} {uiFieldInspectionColumnsSchedule $table}
}
proc ::GX::viewerGuiDesignValidate design {
    foreach field {schema title module_id provider_id version geometry requirements components handlers origin} {if {![dict exists $design $field]} {error "Viewer design requires '$field'."}}
    foreach field [dict keys $design] {if {$field ni {schema title module_id provider_id version geometry requirements components handlers origin shell initial_action icons catalog}} {error "Unknown Viewer design field '$field'."}}
    if {[dict exists $design initial_action] && ![dict exists $design handlers [dict get $design initial_action]]} {error {Initial action must name a declared public handler}}
    if {[dict exists $design shell]} {
        foreach key [dict keys [dict get $design shell]] {if {$key ni {inspector_width status}} {error {Unknown Viewer shell property.}}}
        set width [datasetPublicationV2DictDefault [dict get $design shell] inspector_width 320]
        if {![string is integer -strict $width] || $width<200 || $width>600} {error {Inspector width must be 200–600 pixels.}}
    }
    if {[dict get $design schema] ne {gxtxt.viewer_design.v1}} {error {Unsupported Viewer design schema.}}
    if {[string trim [dict get $design title]] eq {} || [string length [dict get $design title]]>200 || [regexp {[\r\n]} [dict get $design title]]} {error {Use a single-line Viewer title of 1–200 characters.}}
    if {![regexp {^viewer\.[a-z][a-z0-9_]*$} [dict get $design module_id]] || ![regexp {^[a-z][a-z0-9_]*$} [dict get $design provider_id]] || ![regexp {^[0-9]+\.[0-9]+\.[0-9]+$} [dict get $design version]]} {error {Use a stable viewer.lowercase_id, provider ID and semantic version.}}
    if {![regexp {^[0-9]{3,4}x[0-9]{3,4}$} [dict get $design geometry]]} {error {Runtime geometry must be WIDTHxHEIGHT.}}
    if {[string bytelength $design]>4194304 || [llength [dict get $design components]]>1000} {error {Viewer design exceeds its 4 MiB / 1000-component bound.}}
    set icons [viewerGuiIconsValidate [datasetPublicationV2DictDefault $design icons {}]]
    if {[dict exists $design catalog]} {
        dict for {key value} [dict get $design catalog] {
            if {$key ni {semantic_group group_title short_title icon}} {error {Unknown Viewer catalog field}}
            if {[string length $value]>200 || [regexp {[\r\n\x00]} $value]} {error {Viewer catalog values must be bounded single-line text}}
            if {$key eq {semantic_group} && ![regexp {^[a-z][a-z0-9_]{0,63}$} $value]} {error {Viewer semantic group must be a stable identifier}}
            if {$key eq {icon} && ![dict exists $icons $value]} {error {Viewer catalog icon must name an admitted project icon}}
        }
    }
    set capabilities [viewerGuiComponentCapabilities];set ids {};set cells {};set singletons {}
    set versions {VIEWER_GUI_HOST_API_v1 1}
    dict for {type capability} $capabilities {if {[dict get $capability status] eq {AVAILABLE}} {dict set versions [dict get $capability api_id] [dict get $capability api_version]}}
    foreach {api command} {SCIENTIFIC_EXECUTION_API_v1 ::GX::scientificExecutionApiInfo SCRIPT_JOB_API_v1 ::GX::scriptJobApiInfo PARALLEL_EXECUTION_API_v1 ::GX::parallelExecutionApiInfo SCIENTIFIC_LIBRARY_MANAGER_API_v1 ::GX::ScientificLibraryManagerAPIv1::apiInfo FILE_PUBLICATION_API_v1 ::GX::filePublicationApiInfo} {
        if {[llength [info commands $command]]} {dict set versions $api [dict get [$command] api_version]}
    }
    if {[dict exists $design requirements NUMERIC_API_v1]} {
        modulePublicApiActivate math.numeric NUMERIC_API_v1
        dict set versions NUMERIC_API_v1 [dict get [::GX::NumericAPIv1::apiInfo] api_version]
    }
    if {[dict exists $design requirements ELECTROMAGNETIC_SIMULATION_API_v1]} {
        modulePublicApiActivate math.electromagnetic_simulation ELECTROMAGNETIC_SIMULATION_API_v1
        dict set versions ELECTROMAGNETIC_SIMULATION_API_v1 [dict get [::GX::ElectromagneticSimulation::apiInfo] api_version]
    }
    dict for {api version} [dict get $design requirements] {if {![dict exists $versions $api] || ![string is integer -strict $version] || [dict get $versions $api]!=$version} {error "Unavailable CORE API/version: $api @ $version"}}
    # Index every declaration first: a parent may follow its child without
    # changing either one's public one-based SDK component number.
    foreach component [dict get $design components] {
        foreach key {id type parent properties layout} {if {![dict exists $component $key]} {error "Component requires '$key'."}}
        set id [dict get $component id]
        if {![regexp {^[a-z][a-z0-9_]*$} $id] || [dict exists $ids $id] || $id in {toolbar inspector canvas footer menubar}} {error "Duplicate or invalid component ID '$id'."}
        dict set ids $id [dict get $component type]
    }
    _viewerGuiVisibilityDesignValidate $design
    _viewerGuiDesignParentOrder [dict get $design components]
    foreach component [dict get $design components] {
        foreach key {id type parent properties layout} {if {![dict exists $component $key]} {error "Component requires '$key'."}}
        foreach key [dict keys $component] {if {$key ni {id type parent properties layout}} {error "Unknown component field '$key'."}}
        set id [dict get $component id];set type [dict get $component type];set parent [dict get $component parent]
        if {![dict exists $capabilities $type] || [dict get $capabilities $type status] ne {AVAILABLE}} {error "Unavailable CORE component '$type'."}
        set api [dict get $capabilities $type api_id]
        if {![dict exists $design requirements $api]} {error "Component '$id' needs a declared $api capability requirement."}
        if {$parent ni {toolbar inspector canvas footer menubar} && ![dict exists $ids $parent]} {error "Parent '$parent' must be a declared container."}
        if {$type in {command_toolbar context_menu history workspace help}} {
            if {$type in $singletons} {error "Only one '$type' host belongs to a Viewer shell."}
            lappend singletons $type
        }
        if {$type eq {context_menu} && $parent ne {canvas}} {error {The main contextual menu belongs to the canvas slot.}}
        if {$type in {workspace history help} && $parent ne {footer}} {error {Workspace, History and Help use the shell footer declaration.}}
        if {$type eq {command_toolbar} && $parent ne {toolbar}} {error {The responsive command toolbar requires the shell toolbar slot.}}
        if {$parent eq {menubar} && $type ne {menu}} {error {Only menu components belong to the menubar.}}
        if {$type eq {menu} && $parent ne {menubar}} {error {Menus require the menubar slot.}}
        if {[dict exists $ids $parent]} {
            set parentType [dict get $ids $parent]
            if {$parentType ni {panel section splitter tabs tab}} {error "Component '$parent' is not a container."}
            if {($parentType eq {tabs}) != ($type eq {tab})} {error {A tab must be inside tabs, and tabs contain only tab pages.}}
        } elseif {$type eq {tab}} {error {A tab requires a tabs parent.}}
        set properties [dict get $component properties]
        if {[dict exists $properties alpha] && ($type ne {field} || [datasetPublicationV2DictDefault $properties datatype string] ne {color})} {error {Alpha is an option of an existing color field only}}
        set allowed [dict get $capabilities $type properties]
        if {$type eq {document}} {
            if {[datasetPublicationV2DictDefault $properties kind {}] ni {html pdf code table tex}} {error {Document kind must be html, pdf, code, table or declared tex source}}
            if {[datasetPublicationV2DictDefault $properties mode read_only] ni {read_only editable} || ([datasetPublicationV2DictDefault $properties mode read_only] eq {editable} && [dict get $properties kind] ne {tex})} {error {Only a declared TeX source form is editable}}
        }
        if {$type eq {table} && [datasetPublicationV2DictDefault $properties scrollbars none] ni {none vertical horizontal both}} {error {Table scrollbars must be none, vertical, horizontal or both.}}
        if {$type eq {tabs} && [datasetPublicationV2DictDefault $properties tab_position north] ni {north west}} {error {Tab position must be north or west}}
        if {$type eq {dataset_selector} && [datasetPublicationV2DictDefault $properties content_kind {}] ni {{} html pdf code table raster}} {error {Unsupported canonical Dataset content_kind}}
        dict for {key value} $properties {
            if {![dict exists $allowed $key]} {error "Unsupported $type property '$key'."}
            set datatype [dict get $allowed $key]
            if {$datatype eq {boolean} && ![string is boolean -strict $value]} {error "Invalid boolean '$key'."}
            if {$datatype eq {number} && (![string is double -strict $value] || [catch {expr {abs(double($value))<Inf}} finite] || !$finite)} {error "Invalid finite number '$key'."}
            if {$datatype eq {identifier} && ![regexp {^[a-z][a-z0-9_]*$} $value]} {error "Invalid action identifier '$value'."}
            if {$datatype eq {dictionary} && [catch {dict size $value}]} {error "Property '$key' requires a dictionary."}
            if {$datatype eq {list} && [catch {llength $value}]} {error "Property '$key' requires a valid list."}
            if {$key in {width height wraplength padding} && (![string is integer -strict $value] || $value<0 || $value>2000)} {error "Property '$key' requires an integer from 0 to 2000."}
        }
        _viewerGuiCommandIconsValidate $type $properties $icons
        if {[dict exists $properties icon]&&[dict get $properties icon] ne {}} {
            if {![dict exists $icons [dict get $properties icon]]} {error "Missing project icon: [dict get $properties icon]"}
            if {[datasetPublicationV2DictDefault $properties presentation icon_text] eq {icon_only} && [string trim [datasetPublicationV2DictDefault $properties label [datasetPublicationV2DictDefault $properties text {}]]] eq {} && [string trim [datasetPublicationV2DictDefault $properties tooltip {}]] eq {}} {error {Icon-only controls require an accessible text label or tooltip}}
            if {[datasetPublicationV2DictDefault $properties presentation icon_text] ni {icon_only text_only icon_text}||[datasetPublicationV2DictDefault $properties icon_position left] ni {left right top bottom}||[datasetPublicationV2DictDefault $properties icon_size 24] ni {16 24 32 48}||[datasetPublicationV2DictDefault $properties icon_spacing 4] ni {0 2 4 6 8 12}} {error {Invalid typed icon presentation, placement, size or spacing}}
        }
        foreach key {icon_disabled icon_hover icon_selected} {
            set stateIcon [datasetPublicationV2DictDefault $properties $key {}]
            if {$stateIcon eq {}} continue
            if {[datasetPublicationV2DictDefault $properties icon {}] eq {} || ![dict exists $icons $stateIcon]} {error "Icon state $key requires a normal icon and an existing project resource"}
        }
        if {$type eq {splitter} && [datasetPublicationV2DictDefault $properties orientation horizontal] ni {horizontal vertical}} {error {Splitter orientation must be horizontal or vertical.}}
        if {$type eq {native2d} && [datasetPublicationV2DictDefault $properties diagram_catalog {}] ne {}} {native2DGeometryDiagramCatalog [dict get $properties diagram_catalog]}
        if {$type eq {native2d} && [dict exists $properties source_kind]} {
            if {[dict get $properties source_kind] ne {raster} || [datasetPublicationV2DictDefault $properties diagram_catalog {}] ne {}} {error {Native2D source_kind raster cannot also declare a diagram catalog}}
        }
        if {$type eq {section} && [dict exists $properties scientific_provider]} {
            if {![dict exists $design requirements SCIENTIFIC_EXECUTION_API_v1] || [dict get $design requirements SCIENTIFIC_EXECUTION_API_v1]!=1} {error {Scientific form requires SCIENTIFIC_EXECUTION_API_v1@1}}
            if {[dict get $properties scientific_provider] ne {core.ngspice.circuit}} {error {Unsupported declared scientific source profile}}
        }
        if {$type eq {field} && [datasetPublicationV2DictDefault $properties datatype string] ni {string integer double number boolean choice color}} {error {Unsupported UI Field datatype.}}
        if {$type eq {plot} && [datasetPublicationV2DictDefault $properties empty_style canvas] ni {blank canvas}} {error {Unsupported empty Plot style.}}
        if {$type eq {native3d}} {
            if {[datasetPublicationV2DictDefault $properties projection perspective] ni {perspective orthographic}} {error {Native3D projection must be perspective or orthographic.}}
            foreach key {camera_position camera_target camera_up} {if {[dict exists $properties $key]} {viewerTriple [dict get $properties $key] $key}}
            foreach key {width height} {if {[dict exists $properties $key]&&[dict get $properties $key]<160} {error {Native3D dimensions must be at least 160 pixels.}}}
        }
        if {$type eq {list} && [datasetPublicationV2DictDefault $properties selectmode browse] ni {browse single multiple extended}} {error {Unsupported native list selection mode.}}
        set layout [dict get $component layout]
        foreach key [dict keys $layout] {if {$key ni {row column rowspan columnspan weight padding sticky minimum_width minimum_height manager side fill expand anchor padx pady}} {error "Unsupported layout property '$key'."}}
        set manager [datasetPublicationV2DictDefault $layout manager grid]
        if {$manager ni {grid pack}} {error {Use the public grid or pack container layout.}}
        if {$type ni {menu context_menu workspace history help} && (![dict exists $ids $parent] || [dict get $ids $parent] ni {tabs splitter})} {
            if {[dict exists $cells manager:$parent] && [dict get $cells manager:$parent] ne $manager} {error {A container cannot mix grid and pack children.}}
            dict set cells manager:$parent $manager
        }
        foreach {key choices} {side {top bottom left right} fill {none x y both} anchor {n ne e se s sw w nw center}} {if {[dict exists $layout $key] && [dict get $layout $key] ni $choices} {error "Invalid pack property '$key'."}}
        if {[dict exists $layout expand] && ![string is boolean -strict [dict get $layout expand]]} {error {Pack expand must be boolean.}}
        foreach key {padx pady} {if {[dict exists $layout $key] && (![string is integer -strict [dict get $layout $key]] || [dict get $layout $key]<0 || [dict get $layout $key]>1000)} {error {Pack padding must be 0–1000 pixels.}}}
        foreach key {row column rowspan columnspan weight padding minimum_width minimum_height} {
            if {[dict exists $layout $key] && (![string is integer -strict [dict get $layout $key]] || [dict get $layout $key]<0 || [dict get $layout $key]>[expr {$key in {minimum_width minimum_height} ? 2000 : 1000}])} {error "Invalid grid property '$key'."}
        }
        foreach key {rowspan columnspan} {if {[dict exists $layout $key] && [dict get $layout $key]<1} {error {Grid spans must be positive.}}}
        if {[dict exists $layout sticky] && ![regexp {^[nsew]*$} [dict get $layout sticky]]} {error {Invalid grid alignment.}}
        if {$manager eq {grid} && $type ni {menu context_menu workspace history help} && (![dict exists $ids $parent] || [dict get $ids $parent] ni {tabs splitter})} {
            set r [datasetPublicationV2DictDefault $layout row 0];set c [datasetPublicationV2DictDefault $layout column 0]
            set bottom [expr {$r+[datasetPublicationV2DictDefault $layout rowspan 1]}];set right [expr {$c+[datasetPublicationV2DictDefault $layout columnspan 1]}]
            foreach cell [datasetPublicationV2DictDefault $cells $parent {}] {
                lassign $cell previous pr pc pb pe
                if {$r<$pb && $bottom>$pr && $c<$pe && $right>$pc} {error "Overlapping grid spans: '$id' and '$previous' in '$parent'."}
            }
            dict lappend cells $parent [list $id $r $c $bottom $right]
        }
        dict set ids $id $type
    }
    dict for {id contract} [dict get $design handlers] {
        if {[dict exists $contract available] && ![string is boolean -strict [dict get $contract available]]} {error {Command availability must be boolean.}}
        foreach key {arguments effect} {if {![dict exists $contract $key]} {error "Handler '$id' requires '$key'."}}
        foreach key [dict keys $contract] {if {$key ni {arguments effect label default available}} {error "Unknown handler contract field '$key'."}}
        if {![regexp {^[a-z][a-z0-9_]*$} $id] || [dict get $contract arguments] ne {window action} || [dict get $contract effect] ni {unbound presentation mutating}} {error "Invalid callback contract '$id'; expected (window, action) and an explicit effect."}
    }
    foreach component [dict get $design components] {
        set p [dict get $component properties]
        if {[dict exists $p plot_visibility]} {
            set target [dict get $p plot_visibility]
            if {[lsort [dict keys $target]] ne {component panel series} || ![dict exists $ids [dict get $target component]] || [dict get $ids [dict get $target component]] ne {plot}} {error {Visibility binding requires a declared Plot component, panel and series.}}
        }
        if {[dict get $component type] eq {action}} {set actions [list [dict get $p action]]} elseif {[dict get $component type] in {menu command_toolbar context_menu}} {set actions [dict get $p actions]} else {set actions {}}
        if {[dict exists $p change_action]} {lappend actions [dict get $p change_action]}
        if {{command_toolbar} in $singletons && [dict get $component parent] eq {toolbar} && [dict get $component type] ne {command_toolbar}} {error {Use either the responsive command toolbar or custom toolbar components.}}
        foreach id $actions {if {$id ne {-} && ![dict exists $design handlers $id]} {error "Missing handler contract '$id'."}}
    }
    _viewerGuiScientificDesignValidate $design
    _viewerGuiPlotDesignValidate $design
    _viewerGuiNumericDesignValidate $design
    _viewerGuiCatalogDesignValidate $design
    _viewerGuiTeXDesignValidate $design
    _viewerGuiEMDesignValidate $design
    _viewerGuiWorkbenchDesignValidate $design
    _viewerGuiSemanticContextDesignValidate $design
    viewerGuiDesignDiagramToolBindings $design
    viewerGuiDesignRasterToolBindings $design
    viewerGuiDesignRasterCommandBindings $design
    _viewerGuiAnchoredDefinitions $design
    return [dict create {*}$design]
}
proc ::GX::viewerGuiDesignValueSet {window id value} {
    if {[dict get $::GX::ViewerGui::instances $window mode] eq {observed}} {error {An observed original Viewer is read-only through the design API.}}
    set component [viewerGuiDesignComponent $window $id];set type [dict get $component type];set p [dict get $component properties]
    set widget [dict get $::GX::ViewerGui::instances $window widgets $id]
    if {$type in {status label}} {$widget configure -text $value;return $value}
    if {$type ni {field toggle choice dataset_selector progress entry combobox checkbutton list}} {error {This component has no public value binding.}}
    if {$type in {field toggle choice combobox checkbutton}} {
        set datatype [datasetPublicationV2DictDefault $p datatype [dict get {field string toggle boolean choice choice combobox choice checkbutton boolean} $type]]
        set descriptor [dict create type $datatype]
        if {$datatype eq {choice}} {dict set descriptor values [dict get $p choices];if {[dict exists $::GX::ViewerGui::instances $window choice_options $id]} {dict set descriptor values [dict get $::GX::ViewerGui::instances $window choice_options $id]}}
        foreach key {min max alpha} {if {[dict exists $p $key]} {dict set descriptor $key [dict get $p $key]}}
        # The typed C++ numeric transport carries finite doubles. Preserve an
        # exact integral value such as 1.0 for an integer destination; never
        # round a fractional value or relax the interactive field validator.
        if {$datatype eq {integer} && ![string is entier -strict $value]} {
            set numeric [uiFieldNormalize {type number} $value]
            if {$numeric!=floor($numeric)} {error {Enter an integer}}
            set value [expr {entier($numeric)}]
        }
        set value [uiFieldNormalize $descriptor $value]
    }
    if {$type eq {list}} {
        foreach index $value {if {![string is integer -strict $index] || $index<0 || $index>=[$widget size]} {error {List selection index is outside the declared items.}}}
        $widget selection clear 0 end;foreach index $value {$widget selection set $index}
    }
    set ::GX::ViewerGui::values($window,$id) $value
    dict set ::GX::ViewerGui::instances $window committed_values $id $value
    # Keep the shared field owner's baseline coherent with programmatic values.
    # The Design baseline above suppresses a duplicate authored change event.
    if {$type in {field toggle choice}} {
        if {$datatype eq {color}} {uiFieldRefreshColor $widget}
        uiFieldCommit $widget
    }
    viewerGuiActionsRefresh $window;return $value
}
proc ::GX::viewerGuiDesignValues window {
    set result {};set design [dict get $::GX::ViewerGui::instances $window design]
    foreach component [dict get $design components] {
        set id [dict get $component id]
        if {[dict get $component type] eq {tabs} && [dict exists $::GX::ViewerGui::instances $window widgets $id]} {
            set widget [dict get $::GX::ViewerGui::instances $window widgets $id]
            if {[winfo exists $widget]} {dict set result $id [file tail [string map {. /} [$widget select]]];continue}
        }
        if {[info exists ::GX::ViewerGui::values($window,$id)]} {dict set result $id $::GX::ViewerGui::values($window,$id)}
    }
    return $result
}
proc ::GX::viewerGuiDesignWorkspaceClose window {
    set instance [dict get $::GX::ViewerGui::instances $window]
    sessionWorkspaceViewerAction [dict get $instance workspace_provider] [dict get $instance workspace_callbacks] $window close
}
proc ::GX::viewerGuiDesignWorkspaceOpen {module provider design mode handlers context} {
    if {$context ne {} && ![catch {sessionWorkspaceGet $context} item]} {set context [dict create workspace_id [dict get $item workspace_id]]}
    set descriptor [viewerProviderDefinition $module $provider]
    if {{restricted_cpp} in [split [datasetPublicationV2DictDefault $descriptor capabilities {}] {;}] && {RESTRICTED_VIEWER_CLIENT_API_v1} in [modulePublicApiIds $module]} {
        return [viewerDevelopmentInstalledOpen $module $provider [file dirname [moduleField $module descriptor]] $context]
    }
    set id [datasetPublicationV2DictDefault $context workspace_id {}]
    if {$id ni {{} new}} {set item [sessionWorkspaceGet $id];set payload [dict get $item payload];viewerGuiDesignStateValidate $payload;set design [dict get $payload design]}
    set window .designed_[incr ::GX::ViewerGui::serial]
    viewerGuiDesignCompose $design $window $module $provider $mode $handlers $context
    return $window
}
proc ::GX::viewerGuiDesignWorkspaceSave window {
    if {![viewerGuiDesignGuard $window]} {error {Session changed; reopen this Viewer.}}
    foreach form [dict keys [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] tex_forms {}]] {if {[_viewerGuiTeXDirty $window $form]} {_viewerGuiTeXSave $window $form}}
    foreach form [dict keys [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] em_forms {}]] {if {[_viewerGuiEMDirty $window $form]} {_viewerGuiEMSave $window $form}}
    foreach form [dict keys [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] workbench_forms {}]] {if {[_viewerGuiWorkbenchDirty $window $form]} {_viewerGuiWorkbenchSave $window $form}}
    set instance [dict get $::GX::ViewerGui::instances $window]
    set payload [viewerGuiDesignCapture $window];dict set payload design [dict get $instance design]
    if {[dict exists $::GX::ScientificHistory::viewers $window]} {dict set payload history [scientificHistoryViewerRecord $window]}
    set id [dict get $instance workspace_id]
    if {$id eq {}} {
        set name [datasetPublicationV2DictDefault $instance workspace_name {}]
        if {$name eq {}} {set name [sessionWorkspaceAvailableName [dict get $instance design title]]}
        set item [sessionWorkspaceCreate [dict get $instance workspace_provider] $name $payload]
    } else {
        set current [sessionWorkspaceGet $id]
        if {[dict get $instance workspace_stamp] ne [list [dict get $current generation] [dict get $current revision] [dict get $current sha256]]} {error {Workspace changed in another window; reopen it before saving.}}
        set item [sessionWorkspaceUpdate $id $payload]
    }
    dict set ::GX::ViewerGui::instances $window workspace_id [dict get $item workspace_id]
    dict set ::GX::ViewerGui::instances $window workspace_stamp [list [dict get $item generation] [dict get $item revision] [dict get $item sha256]]
    dict set ::GX::ViewerGui::instances $window saved [viewerGuiDesignCapture $window]
    if {[dict exists $::GX::ScientificHistory::viewers $window]} {dict set ::GX::ViewerGui::instances $window saved_history [scientificHistoryViewerRecord $window]}
    return [dict get $item workspace_id]
}
proc ::GX::viewerGuiHostInspect window {
    if {![winfo exists $window] || ![dict exists $::GX::ViewerGui::shells $window]} {return [dict create status CORE_GAP window $window reason {No live public GUI Host declaration.}]}
    set shell [dict get $::GX::ViewerGui::shells $window];set rows {}
    dict for {slot widget} [dict get $shell slots] {
        if {![winfo exists $widget]} continue
        dict set rows $slot [dict create widget $widget class [winfo class $widget] mapped [winfo ismapped $widget] rectangle [list [expr {[winfo rootx $widget]-[winfo rootx $window]}] [expr {[winfo rooty $widget]-[winfo rooty $window]}] [winfo width $widget] [winfo height $widget]]]
    }
    return [dict create status DECLARED_HOST_ONLY window $window manifest [dict get $shell manifest] slots $rows environment [viewerGuiEnvironment $window] boundary {Private construction outside these declared slots is not introspected or reconstructed.}]
}
proc ::GX::viewerGuiManifestDescribe {module provider} {
    set key [list $module $provider]
    if {![dict exists $::GX::ViewerGui::manifests $key]} {return [dict create status CORE_GAP reason {This Viewer has not published a GUI manifest through Viewer GUI Host. No private widget reconstruction was attempted.}]}
    return [dict get $::GX::ViewerGui::manifests $key]
}
proc ::GX::viewerGuiRuntimeInspect window {
    if {![dict exists $::GX::ViewerGui::instances $window] || ![winfo exists $window]} {return [dict create status CLOSED window $window]}
    set instance [dict get $::GX::ViewerGui::instances $window];set rows {};set capabilities [viewerGuiComponentCapabilities]
    foreach component [dict get $instance design components] {
        set id [dict get $component id];set type [dict get $component type]
        set widget [datasetPublicationV2DictDefault [dict get $instance widgets] $id {}]
        set status MOUNTED
        if {$widget eq {} || ![winfo exists $widget]} {set status [expr {$type in {history workspace} && [dict get $instance token] eq {} ? {SESSION_REQUIRED} : {MISSING}}]}
        set row [dict create component $id type $type api_id [dict get $capabilities $type api_id] api_version [dict get $capabilities $type api_version] owner [dict get $capabilities $type owner] widget $widget status $status declared_properties [dict get $component properties]]
        if {$status eq {MOUNTED}} {
            dict set row class [winfo class $widget]
            dict set row mapped [winfo ismapped $widget]
            dict set row rectangle [list [expr {[winfo rootx $widget]-[winfo rootx $window]}] [expr {[winfo rooty $widget]-[winfo rooty $window]}] [winfo width $widget] [winfo height $widget]]
            if {$type eq {native3d}} {dict set row native_state [native3DViewportInspect [dict get $instance native3d $id]]}
            if {$type eq {editable3d}} {
                dict set row native_state [dict create status unbound owner viewer.3d_workbench/workbench_3d]
                foreach form [dict keys [datasetPublicationV2DictDefault $instance workbench_forms {}]] {
                    if {[dict get [viewerGuiDesignComponent $window $form] properties workbench_viewport] eq $id && [_viewerGuiWorkbenchOwned $window $form]} {dict set row native_state [::GX::Workbench3D::guiInspect]}
                }
            }
            if {[dict exists $instance demo_bindings $id]} {
                dict set row status DEMO_BOUND
                dict set row demo_binding [dict get $instance demo_bindings $id]
                if {$type eq {native2d}} {dict set row native_state [native2DTemporaryDisplayInspect [dict get $instance demo_bindings $id widget]]}
                if {$type eq {plot}} {dict set row native_state [nativePlotDisplayInspect $widget.plot]}
            } elseif {$type in {native2d plot}} {
                if {[dict exists $instance bindings $id]} {dict set row scientific_binding [viewerGuiScientificBindingSummary [dict get $instance bindings $id]];dict set row status SOURCE_BOUND} else {dict set row status UNBOUND_SOURCE_SLOT}
                if {$type eq {native2d} && [winfo exists $widget.curve] && ![catch {native2DViewportCurveDescribe $widget.curve} native]} {dict set row native_metrics [dict get $native metrics];dict set row readiness [dict get $native status]}
                if {$type eq {native2d} && [dict exists $instance bindings $id] && [dict get $instance bindings $id kind] eq {raster}} {
                    if {[catch {viewerGuiDesignRasterDescribe $window $id} raster]} {dict set row readiness STALE_SOURCE;dict set row diagnostic $raster} else {dict set row readiness [dict get $raster status];dict set row native_state $raster}
                }
                if {$type eq {plot} && [winfo exists $widget.plot]} {
                    if {[catch {::GX::PlotDatasetAPIv4::widgetReceipt $widget.plot} receipt]} {dict set row readiness STALE_SOURCE;dict set row diagnostic $receipt} else {dict set row readiness [expr {[dict exists $receipt axes] ? {ready} : {waiting_first_paint}}]}
                }
            }
            if {$type in {action label status}} {dict set row effective_text [$widget cget -text]}
            if {[winfo class $widget] eq {Menu}} {
                set entries {};set end [$widget index end]
                if {$end ne {none}} {for {set i 0} {$i<=$end} {incr i} {
                    set entry [dict create type [$widget type $i]]
                    foreach key {label state accelerator} {if {![catch {$widget entrycget $i -$key} value]} {dict set entry $key $value}}
                    lappend entries $entry
                }}
                dict set row menu_entries $entries
            }
        }
        dict set rows $id $row
    }
    set pending {};foreach timer [after info] {set data [after info $timer];if {[string first $window [lindex $data 0]]>=0} {lappend pending [list $timer $data]}}
    set commands {};set adapter [dict get $::GX::ViewerCommands::windows $window]
    dict for {id handler} [dict get $adapter handlers] {
        dict set commands $id [dict create enabled [viewerCommandEnabled $window $id] applicable [viewerCommandApplicable $window $id] shortcut [dict get $adapter bindings $id] handler [dict get $handler command]]
    }
    set correlations {};set anomalies {};set active {};set commandTimings {}
    foreach trace [dict get $instance traces] {
        set correlation [dict get $trace correlation_id];set event [dict get $trace event]
        if {$event in {invoke result}} {
            if {[dict exists $correlations $correlation $event]} {lappend anomalies [dict create correlation_id $correlation status DUPLICATE event $event owner VIEWER_GUI_HOST_API_v1]}
            dict set correlations $correlation $event 1
            if {$event eq {invoke}} {
                foreach activeCommand [dict values $active] {if {[dict get $activeCommand component] eq [dict get $trace component]} {lappend anomalies [dict create correlation_id $correlation status REENTRANT component [dict get $trace component] owner CONFIGURATION_API_v1]}}
                dict set active $correlation $trace
            } elseif {[dict exists $active $correlation]} {
                set started [dict get $active $correlation];dict unset active $correlation
                lappend commandTimings [dict create correlation_id $correlation component [dict get $trace component] command_callback_ms [expr {([dict get $trace monotonic_us]-[dict get $started monotonic_us])/1000.0}] scope {Synchronous command callback, excluding subsequent asynchronous scientific Job/paint time.}]
            }
        }
    }
    set subscriptions {};dict for {id observer} $::GX::ViewerGui::traces {if {[dict get $observer window] eq $window} {lappend subscriptions $id}}
    return [dict create schema gxtxt.viewer_gui_inspection.v1 status INSPECTED window $window mapped [winfo ismapped $window] viewable [winfo viewable $window] geometry [wm geometry $window] theme [ttk::style theme use] tk_scaling [tk scaling] font [font actual TkDefaultFont] focus [focus] grab [grab current] components $rows commands $commands anomalies $anomalies command_timings $commandTimings incomplete_commands [dict keys $active] subscriptions $subscriptions scoped_timers $pending trace [dict get $instance traces] managed_requests_observed [dict size $::GX::scriptJobRequests] managed_requests_attribution {Global count; not proof of per-Viewer scientific execution.}]
}
proc ::GX::viewerGuiTraceClear window {if {[dict exists $::GX::ViewerGui::instances $window]} {dict set ::GX::ViewerGui::instances $window traces {}}}
proc ::GX::viewerGuiTraceEmit {window component event detail {correlation {}}} {
    if {![dict exists $::GX::ViewerGui::instances $window]} return
    if {$correlation eq {}} {set correlation gui-[incr ::GX::ViewerGui::serial]}
    set record [dict create correlation_id $correlation monotonic_us [clock microseconds] window $window component $component event $event detail $detail]
    set traces [dict get $::GX::ViewerGui::instances $window traces]
    lappend traces $record;dict set ::GX::ViewerGui::instances $window traces [lrange $traces end-1999 end]
    dict for {id observer} $::GX::ViewerGui::traces {if {[dict get $observer window] eq $window} {catch {uplevel #0 [list {*}[dict get $observer callback] $record]}}}
    return $correlation
}
proc ::GX::viewerGuiTraceSubscribe {window callback} {set id observer-[incr ::GX::ViewerGui::serial];dict set ::GX::ViewerGui::traces $id [dict create window $window callback $callback];return $id}
proc ::GX::viewerGuiTraceUnsubscribe id {if {[dict exists $::GX::ViewerGui::traces $id]} {dict unset ::GX::ViewerGui::traces $id}}
proc ::GX::viewerGuiWindowHelpRequested window {
    if {[dict exists $::GX::ViewerGui::instances $window help]} {return [dict get $::GX::ViewerGui::instances $window help]}
    return 1
}

proc ::GX::viewerGuiPublishedWindows {module provider} {
    set result {}
    dict for {window record} $::GX::ViewerGui::shells {
        if {[winfo exists $window] && [dict get $record manifest viewer_id] eq $module && [dict get $record manifest provider_id] eq $provider} {lappend result $window}
    }
    return $result
}

proc ::GX::viewerGuiScientificBindingSummary {binding} {
    set kind [dict get $binding kind]
    if {$kind eq {raster}} {return [dict create kind raster document_id [dict get $binding document_id] source [dict get $binding source] authority NATIVE_2D_GEOMETRY_API_v1]}
    if {$kind eq {diagram}} {
        set owner [dict get $binding document_receipt]
        return [dict create kind diagram document_id [dict get $owner id] generation [dict get $owner generation] revision [dict get $owner revision] sha256 [dict get $owner sha256] catalog [dict get $binding payload catalog] component_count [dict size [dict get $binding payload components]] wire_count [dict size [dict get $binding payload wires]] authority INTERACTIVE_DOCUMENT_API_v1 payload redacted]
    }
    if {$kind eq {native2d}} {
        set request [dict get $binding request]
        set result [dict create kind $kind source_id [dict get $binding source_id]]
        foreach key {dataset_id x_variable_id y_variable_id} {if {[dict exists $request $key]} {dict set result $key [dict get $request $key]}}
        return $result
    }
    set spec [dict get $binding spec];set datasets {};set seriesCount 0
    if {[dict exists $spec dataset_id]} {lappend datasets [dict get $spec dataset_id]}
    foreach panel [datasetPublicationV2DictDefault $spec panels {}] {
        foreach series [dict get $panel series] {incr seriesCount;if {[dict exists $series dataset_id]} {lappend datasets [dict get $series dataset_id]}}
    }
    set identities {};foreach id [lsort -unique $datasets] {dict set identities $id [datasetField $id canonical_sha256 [datasetField $id sha256 {}]]}
    return [dict create kind plot prepared_model [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $binding context {}] prepared_model 0] panels [llength [datasetPublicationV2DictDefault $spec panels {}]] series $seriesCount dataset_sha256 $identities model_crc32 [zlib crc32 $spec] fingerprint_scope {Noncryptographic equality of the retained model; fixture scientific SHA is verified separately.} payload redacted]
}

proc ::GX::viewerGuiSourceScopeAttach {window component widget} {
    set tag GXGuiSourceScope$window.$component
    foreach event {<ButtonPress> <ButtonRelease> <Motion> <MouseWheel> <KeyPress>} {
        bind $tag $event [format {if {![::GX::viewerGuiSourceScopeAllowed %s %s]} {break}} [list $window] [list $component]]
    }
    if {$tag ni [bindtags $widget]} {bindtags $widget [linsert [bindtags $widget] 0 $tag]}
    bind $widget <Destroy> +[list ::GX::_viewerGuiSourceScopeDispose $tag $widget %W]
}
proc ::GX::viewerGuiSourceScopeAllowed {window component} {
    if {[viewerGuiDesignGuard $window]} {return 1}
    if {[dict exists $::GX::ViewerGui::instances $window] && [winfo exists $window]} {
        [dict get $::GX::ViewerGui::instances $window slots status] configure -text {Session changed; reopen this scientific source before interacting.}
    }
    return 0
}
proc ::GX::_viewerGuiSourceScopeDispose {tag expected actual} {
    if {$expected ne $actual} return
    foreach event [bind $tag] {bind $tag $event {}}
}

proc ::GX::viewerGuiDesignChoicesSet {window component choices} {
    if {[llength $choices]>4096} {error {Choice projection exceeds 4096 entries}}
    set definition [viewerGuiDesignComponent $window $component]
    set widget [dict get $::GX::ViewerGui::instances $window widgets $component]
    if {[dict get $definition type] eq {list}} {
        # Lists project their owning provider's current records. Changed rows
        # invalidate old positional UI selection; the owner restores its actual
        # logical identities explicitly after projecting the new records.
        if {[$widget get 0 end] ne $choices} {
            $widget delete 0 end
            foreach value $choices {$widget insert end $value}
            viewerGuiDesignValueSet $window $component {}
        }
        dict set ::GX::ViewerGui::instances $window choice_options $component $choices
        return $choices
    }
    if {[dict get $definition type] eq {choice} || ([dict get $definition type] eq {field} && [datasetPublicationV2DictDefault [dict get $definition properties] datatype string] eq {choice})} {uiFieldChoicesSet $widget $choices;set widget $widget.entry}
    if {[winfo class $widget] ne {TCombobox}} {error {The component is not a public choice control}}
    $widget configure -values $choices
    dict set ::GX::ViewerGui::instances $window choice_options $component $choices
}
proc ::GX::viewerGuiDesignComponentVisible {window component visible} {
    return [_viewerGuiComponentVisibilityApply $window $component $visible]
}
proc ::GX::viewerGuiDesignTextSet {window component content} {
    set definition [viewerGuiDesignComponent $window $component]
    if {[string bytelength $content]>1048576} {error {Presentation text exceeds 1 MiB; use bounded consultation}}
    set widget [dict get $::GX::ViewerGui::instances $window widgets $component]
    switch [dict get $definition type] {
        log {$widget configure -state normal;$widget delete 1.0 end;$widget insert 1.0 $content;$widget configure -state disabled}
        label - status {$widget configure -text $content}
        default {error {Select an existing public read-only text component}}
    }
}

proc ::GX::viewerGuiDesignContextSet {window value} {
    if {[catch {dict size $value}] || [string bytelength $value]>65536} {error {Viewer domain state requires a bounded inert dictionary of at most 64 KiB}}
    dict set ::GX::ViewerGui::instances $window domain_state $value
}
proc ::GX::viewerGuiDesignContextGet {window} {return [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] domain_state {}]}

proc ::GX::_viewerGuiNative3DEvent {window id handle event detail} {
    if {![viewerGuiDesignGuard $window]} return
    viewerGuiTraceEmit $window $id $event $detail
    viewerGuiActionsRefresh $window
}
proc ::GX::viewerGuiDesignNative3DSet {window component source} {
    if {![viewerGuiDesignGuard $window]} {error {Viewer belongs to a previous Session}}
    set definition [viewerGuiDesignComponent $window $component]
    if {[dict get $definition type] ne {native3d}} {error {Select a Native3D component}}
    set result [native3DViewportBind [dict get $::GX::ViewerGui::instances $window native3d $component] $source]
    if {[dict exists $::GX::ViewerGui::instances $window demo_bindings $component]} {dict unset ::GX::ViewerGui::instances $window demo_bindings $component}
    viewerGuiActionsRefresh $window
    return $result
}
proc ::GX::viewerGuiDesignTemporarySceneSet {window component fixture {callback {}}} {
    if {![viewerGuiDesignGuard $window]} {error {Viewer belongs to a previous lifetime}}
    set definition [viewerGuiDesignComponent $window $component]
    set type [dict get $definition type]
    if {$fixture ni {native2d plot native3d}||$type ne $fixture} {error {Temporary fixture must match the declared native component}}
    set widget [dict get $::GX::ViewerGui::instances $window widgets $component]
    if {$type eq {native3d}} {set result [native3DViewportBind [dict get $::GX::ViewerGui::instances $window native3d $component] {kind demo}]} else {
        foreach child [winfo children $widget] {destroy $child}
        if {$type eq {native2d}} {set result [native2DTemporaryDisplayCreate $widget.demo $callback]} else {set result [nativePlotDisplayCreate $widget.plot [viewerGuiDemoPlotModel] $callback]}
        pack $result -fill both -expand 1
    }
    if {[dict exists $::GX::ViewerGui::instances $window bindings $component]} {dict unset ::GX::ViewerGui::instances $window bindings $component}
    dict set ::GX::ViewerGui::instances $window demo_bindings $component [dict create fixture $fixture widget [expr {$type eq {native3d}?$widget:$result}] provenance display_only_RAM scientific_source {}]
    viewerGuiActionsRefresh $window
    return $result
}

source [file join [file dirname [info script]] viewer_gui_icons_v1.tcl]
source [file join [file dirname [info script]] viewer_gui_visibility_v1.tcl]
source [file join [file dirname [info script]] viewer_gui_diagrams_v1.tcl]
source [file join [file dirname [info script]] viewer_gui_scientific_v1.tcl]
source [file join [file dirname [info script]] viewer_gui_plot_bindings_v1.tcl]
source [file join [file dirname [info script]] viewer_gui_numeric_v1.tcl]
source [file join [file dirname [info script]] viewer_gui_document_v1.tcl]
source [file join [file dirname [info script]] viewer_gui_raster_v1.tcl]
source [file join [file dirname [info script]] viewer_gui_semantic_context_v1.tcl]
source [file join [file dirname [info script]] viewer_gui_anchored_panels_v1.tcl]
source [file join [file dirname [info script]] viewer_gui_catalog_v1.tcl]
source [file join [file dirname [info script]] viewer_gui_tex_v1.tcl]
source [file join [file dirname [info script]] viewer_gui_em_v1.tcl]
source [file join [file dirname [info script]] viewer_gui_workbench_v1.tcl]
