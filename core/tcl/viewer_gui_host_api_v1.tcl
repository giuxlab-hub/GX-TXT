# SPDX-License-Identifier: GPL-3.0-or-later
# Host-only integration manifest. Existing public owners retain every widget,
# command, renderer, Workspace, History, source and scientific execution state.
proc ::GX::viewerGuiHostApiInfo {} {
    return [dict merge [_viewerGuiHostApiInfoBase] [dict create pcb_source_form_kind eagle_pair_fixed_v1 pcb_source_form_profile document_view_v1 pcb_source_form_capability pcb_source_form pcb_source_form_commands {import_pair refresh inspect cancel} pcb_source_form_entrypoint viewerGuiDesignAction pcb_source_form_implicit_import 0 pcb_source_form_scope import_only_completed_canonical_snapshots pcb_source_form_native_projection 0]]
}
proc ::GX::_viewerGuiHostApiInfoBase {} {
    return [dict create api_id VIEWER_GUI_HOST_API_v1 api_version 1 host_only 1 schema gxtxt.viewer_gui_manifest.v1 operations {viewerGuiManifestValidate viewerGuiCompose viewerGuiActionsMount viewerGuiMenuMount viewerGuiContextMount viewerGuiSelectionAttach viewerGuiActionsRefresh} design_schema gxtxt.viewer_design.v1 diagram_tool_property {target_native2d_component tool} diagram_tool_presentation authoritative_viewport_checked scientific_probe_optional_context {hit_kind wire wire_id ID point {x y}} scientific_probe_analyses {op tran dc ac} scientific_probe_ac_policy {declared_complex_projection_form_with_explicit_evaluate_and_publish} design_operations {viewerGuiComponentCapabilities viewerGuiDesignNew viewerGuiDesignValidate viewerGuiDesignRead viewerGuiDesignSave viewerGuiDesignModelCreate viewerGuiDesignModelEdit viewerGuiDesignModelNavigate viewerGuiDesignCompose viewerGuiDesignImport viewerGuiManifestDescribe viewerGuiDesignHandlerBindings viewerGuiDesignGenerate viewerGuiDesignHandlerSource viewerGuiDesignValues viewerGuiIconCatalog viewerGuiIconImport viewerGuiIconsValidate viewerGuiIconEdit viewerGuiDesignValueSet viewerGuiDesignComponentVisible viewerGuiDesignComponentVisibleGet viewerGuiDesignVisibilityCommands viewerGuiDesignTableSet viewerGuiDesignSourceSet viewerGuiDesignRasterBind viewerGuiDesignRasterDescribe viewerGuiDesignRasterTool viewerGuiDesignRasterCommand viewerGuiDesignRasterToolBindings viewerGuiDesignRasterToolChecked viewerGuiDocumentCompatible viewerGuiDesignDocumentBind viewerGuiDesignDocumentInspect viewerGuiDesignTeXCommand viewerGuiDesignEMCommand viewerGuiDesignWorkbenchCommand viewerGuiDesignTransform viewerGuiDesignPlotSet viewerGuiDesignNative3DSet viewerGuiDesignTemporarySceneSet viewerGuiDesignDiagramSet viewerGuiDesignDiagramCommand viewerGuiDesignDiagramToolBindings viewerGuiDesignDiagramToolChecked viewerGuiDesignScientificDiscover viewerGuiDesignScientificPrepare viewerGuiDesignScientificSubmit viewerGuiDesignScientificStatus viewerGuiDesignScientificCancel viewerGuiDesignScientificReconnect viewerGuiDesignScientificLog viewerGuiDesignScientificImport viewerGuiDesignScientificProbe viewerGuiDesignScientificNetlist viewerGuiDesignPlotDiscover viewerGuiDesignPlotBind viewerGuiDesignPlotSeries viewerGuiDesignPlotProbe viewerGuiDesignPlotCursor viewerGuiDesignPlotCursorClear viewerGuiDesignNumericDiscover viewerGuiDesignNumericEvaluate viewerGuiDesignNumericStatistics viewerGuiDesignNumericCompare viewerGuiDesignNumericPublish viewerGuiDesignCatalogRefresh viewerGuiDesignCatalogInspect viewerGuiDesignCatalogAction viewerGuiDesignCatalogDescribe viewerGuiRuntimeInspect viewerGuiDesignPublish viewerGuiPublishedWindows viewerGuiCompare viewerGuiScientificBindingSummary} transform_form_kind baseline_correct transform_form_profile scientific_view_v1 transform_form_commands {discover create_corrected cancel inspect} transform_form_entrypoint viewerGuiDesignTransform transform_form_arguments {window form operation} transform_form_implicit_execution 0 laboratory_operations {viewerGuiMonitorStart viewerGuiMonitorCancel viewerGuiTraceSubscribe viewerGuiTraceUnsubscribe viewerGuiRecordingStart viewerGuiRecordingStop viewerGuiScenarioValidate viewerGuiReplayStart viewerGuiReplayCancel viewerGuiTestPlan viewerGuiTestsStart viewerGuiDiagnosticExport viewerGuiTestFixtureValidate} owners [dict create regions UI_FIELD_API_v1 actions CONFIGURATION_API_v1 workspace SESSION_WORKSPACE_API_v1 history SCIENTIFIC_RECIPE_API_v1 help DOCUMENTATION_BROWSER_API_v1 canvas {NATIVE2D_VIEWPORT_HOST_v1 NATIVE_3D_GUI_HOST_API_v1 NATIVE_3D_GUI_HOST_API_v2 PLOT_DATASET_API_v4}]]
}
proc ::GX::viewerGuiManifestValidate {manifest} {
    foreach field {schema viewer_id provider_id window title handlers} {if {![dict exists $manifest $field]} {error "Viewer GUI manifest requires '$field'"}}
    if {[dict get $manifest schema] ne "gxtxt.viewer_gui_manifest.v1"} {error {Unsupported Viewer GUI manifest version}}
    foreach field [dict keys $manifest] {if {$field ni {schema viewer_id provider_id window title handlers guard workspace history history_record canvas canvas_mount geometry inspector_width toolbar_actions toolbar_mode help menus context_actions command_catalog}} {error "Unknown Viewer GUI manifest field '$field'"}}
    if {[datasetPublicationV2DictDefault $manifest toolbar_mode actions] ni {actions declarative}} {error {Unknown Viewer toolbar mode.}}
    if {![string is boolean -strict [datasetPublicationV2DictDefault $manifest help 1]]} {error {Viewer Help policy must be boolean.}}
    set module [dict get $manifest viewer_id]
    if {[moduleField $module descriptor {}] eq {} || [moduleField $module kind {}] ne "viewer"} {error {Manifest must refer to a registered Viewer module}}
    viewerProviderDefinition $module [dict get $manifest provider_id]
    set commandCatalog [datasetPublicationV2DictDefault $manifest command_catalog $module]
    set catalog [viewerCommandCatalog $commandCatalog]
    if {[dict get $::GX::ViewerCommands::catalogs $commandCatalog owner_module] ne $module} {error {Viewer command catalog has a different module owner.}}
    dict for {id handler} [dict get $manifest handlers] {
        if {![dict exists $catalog $id] || ![dict exists $handler command]} {error "Unregistered Viewer command '$id'"}
    }
    set actions [datasetPublicationV2DictDefault $manifest toolbar_actions {}]
    lappend actions {*}[datasetPublicationV2DictDefault $manifest context_actions {}]
    foreach menu [datasetPublicationV2DictDefault $manifest menus {}] {
        if {![dict exists $menu label] || ![dict exists $menu actions]} {error {A Viewer menu requires label and actions}}
        lappend actions {*}[dict get $menu actions]
    }
    foreach id $actions {if {$id ne "-" && ![dict exists $manifest handlers $id]} {error "No handler for Viewer action '$id'"}}
    set width [datasetPublicationV2DictDefault $manifest inspector_width 320]
    if {![string is integer -strict $width] || $width<200 || $width>600} {error {Inspector width must be between 200 and 600}}
    if {[dict exists $manifest canvas]} {
        set canvas [dict get $manifest canvas]
        if {[dict get $canvas api_id] ni {NATIVE2D_VIEWPORT_HOST_v1 NATIVE_3D_GUI_HOST_API_v1 NATIVE_3D_GUI_HOST_API_v2 PLOT_DATASET_API_v4}} {error {Select an existing public Native2D, Native3D or Plot canvas owner}}
    }
    return $manifest
}
proc ::GX::viewerGuiActionsMount {window frame {commandIds {}}} {return [viewerCommandToolbarCreate $window $frame $commandIds]}
proc ::GX::viewerGuiCompose {manifest} {
    set manifest [viewerGuiManifestValidate $manifest]
    set window [dict get $manifest window];set module [dict get $manifest viewer_id];set provider [dict get $manifest provider_id]
    set slots [uiFieldViewerShellCreate $window [dict get $manifest title] [datasetPublicationV2DictDefault $manifest geometry 1100x720] [datasetPublicationV2DictDefault $manifest inspector_width 320]]
    try {
        viewerCommandsAttach $window [datasetPublicationV2DictDefault $manifest command_catalog $module] [dict get $manifest handlers] [datasetPublicationV2DictDefault $manifest guard {}]
        if {[datasetPublicationV2DictDefault $manifest toolbar_mode actions] eq {actions}} {viewerGuiActionsMount $window [dict get $slots toolbar] [datasetPublicationV2DictDefault $manifest toolbar_actions {}]}
        set index 0
        foreach descriptor [datasetPublicationV2DictDefault $manifest menus {}] {
            set menu $window.menus.actions[incr index]
            viewerGuiMenuMount $window $menu [dict get $descriptor actions]
            $window.menus add cascade -label [dict get $descriptor label] -menu $menu
        }
        if {[dict exists $manifest context_actions]} {
            set menu [viewerGuiMenuMount $window $window.context [dict get $manifest context_actions]]
            dict set slots context_menu $menu
            viewerGuiContextMount $window [dict get $slots canvas]
        }
        if {[dict exists $manifest workspace]} {
            menu $window.menus.workspace -tearoff 0
            sessionWorkspaceViewerMenu $window.menus.workspace $provider [dict get $manifest workspace] $window
            $window.menus add cascade -label Workspace -menu $window.menus.workspace
        }
        if {[dict exists $manifest history]} {
            scientificHistoryViewerAttach $window $module [dict get $manifest history] [datasetPublicationV2DictDefault $manifest history_record {}]
            scientificHistoryViewerStrip $window [dict get $slots footer] [dict get $slots status]
        }
        if {[datasetPublicationV2DictDefault $manifest help 1]} {documentationBrowserAttachViewerHelp $module $provider $window}
        if {[dict exists $manifest canvas]} {
            set api [dict get $manifest canvas api_id]
            if {$api eq "PLOT_DATASET_API_v4"} {modulePublicApiActivate plot.dataset $api}
            dict set slots canvas_api $api
        }
        if {[dict exists $manifest canvas_mount]} {uplevel #0 [list {*}[dict get $manifest canvas_mount] [dict get $slots canvas]]}
        dict set ::GX::ViewerGui::manifests [list $module $provider] [dict remove $manifest history_record]
        dict set ::GX::ViewerGui::shells $window [dict create manifest [dict remove $manifest history_record] slots $slots]
        bind $window <Destroy> +[list ::GX::_viewerGuiHostDisposed $window %W]
    } on error {message options} {destroy $window;return -options $options $message}
    return $slots
}

proc ::GX::viewerGuiMenuMount {window menu actions} {
    menu $menu -tearoff 0 -postcommand [list ::GX::viewerCommandMenusRefresh $window]
    foreach id $actions {
        if {$id eq "-"} {$menu add separator} else {viewerCommandMenuAdd $window $menu $id}
    }
    return $menu
}
proc ::GX::viewerGuiContextMount {window widget} {
    if {![winfo exists $window.context] || ![winfo exists $widget]} {error {Viewer context host is not mounted}}
    bind $widget <Button-3> [list ::GX::uiMenuPopup $window.context %X %Y]
}
proc ::GX::viewerGuiSelectionAttach {window widget {event <<ListboxSelect>>}} {
    if {![winfo exists $widget] || [winfo toplevel $widget] ne $window} {error {Selection must belong to its Viewer}}
    bind $widget $event +[list ::GX::viewerGuiActionsRefresh $window]
}
proc ::GX::viewerGuiActionsRefresh {window} {
    _viewerGuiEMRefreshAvailability $window
    viewerCommandWidgetsRefresh $window
    viewerCommandToolbarStatesRefresh $window
    viewerCommandToolbarRefresh $window
    viewerCommandMenusRefresh $window
}

source [file join [file dirname [info script]] viewer_gui_design_v1.tcl]
source [file join [file dirname [info script]] viewer_gui_laboratory_v1.tcl]
