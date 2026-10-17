# SPDX-License-Identifier: GPL-3.0-or-later
# Host-only integration manifest. Existing public owners retain every widget,
# command, renderer, Workspace, History, source and scientific execution state.
proc ::GX::viewerGuiHostApiInfo {} {
    return [dict create api_id VIEWER_GUI_HOST_API_v1 api_version 1 host_only 1 schema gxtxt.viewer_gui_manifest.v1 operations {viewerGuiManifestValidate viewerGuiCompose viewerGuiActionsMount} owners [dict create regions UI_FIELD_API_v1 actions CONFIGURATION_API_v1 workspace SESSION_WORKSPACE_API_v1 history SCIENTIFIC_RECIPE_API_v1 help DOCUMENTATION_BROWSER_API_v1 canvas {NATIVE2D_VIEWPORT_HOST_v1 NATIVE_3D_GUI_HOST_API_v1 PLOT_DATASET_API_v4}]]
}
proc ::GX::viewerGuiManifestValidate {manifest} {
    foreach field {schema viewer_id provider_id window title handlers} {if {![dict exists $manifest $field]} {error "Viewer GUI manifest requires '$field'"}}
    if {[dict get $manifest schema] ne "gxtxt.viewer_gui_manifest.v1"} {error {Unsupported Viewer GUI manifest version}}
    foreach field [dict keys $manifest] {if {$field ni {schema viewer_id provider_id window title handlers guard workspace history history_record canvas canvas_mount geometry}} {error "Unknown Viewer GUI manifest field '$field'"}}
    set module [dict get $manifest viewer_id]
    if {[moduleField $module descriptor {}] eq {} || [moduleField $module kind {}] ne "viewer"} {error {Manifest must refer to a registered Viewer module}}
    viewerProviderDefinition $module [dict get $manifest provider_id]
    set catalog [viewerCommandCatalog $module]
    dict for {id handler} [dict get $manifest handlers] {
        if {![dict exists $catalog $id] || ![dict exists $handler command]} {error "Unregistered Viewer command '$id'"}
    }
    if {[dict exists $manifest canvas]} {
        set canvas [dict get $manifest canvas]
        if {[dict get $canvas api_id] ni {NATIVE2D_VIEWPORT_HOST_v1 NATIVE_3D_GUI_HOST_API_v1 PLOT_DATASET_API_v4}} {error {Select an existing public Native2D, Native3D or Plot canvas owner}}
    }
    return $manifest
}
proc ::GX::viewerGuiActionsMount {window frame {commandIds {}}} {return [viewerCommandToolbarCreate $window $frame $commandIds]}
proc ::GX::viewerGuiCompose {manifest} {
    set manifest [viewerGuiManifestValidate $manifest]
    set window [dict get $manifest window];set module [dict get $manifest viewer_id];set provider [dict get $manifest provider_id]
    set slots [uiFieldViewerShellCreate $window [dict get $manifest title] [datasetPublicationV2DictDefault $manifest geometry 1100x720]]
    try {
        viewerCommandsAttach $window $module [dict get $manifest handlers] [datasetPublicationV2DictDefault $manifest guard {}]
        viewerGuiActionsMount $window [dict get $slots toolbar]
        if {[dict exists $manifest workspace]} {
            menu $window.menus.workspace -tearoff 0
            sessionWorkspaceViewerMenu $window.menus.workspace $provider [dict get $manifest workspace] $window
            $window.menus add cascade -label Workspace -menu $window.menus.workspace
        }
        if {[dict exists $manifest history]} {
            scientificHistoryViewerAttach $window $module [dict get $manifest history] [datasetPublicationV2DictDefault $manifest history_record {}]
            scientificHistoryViewerStrip $window [dict get $slots footer] [dict get $slots status]
        }
        documentationBrowserAttachViewerHelp $module $provider $window
        if {[dict exists $manifest canvas]} {
            set api [dict get $manifest canvas api_id]
            if {$api eq "PLOT_DATASET_API_v4"} {modulePublicApiActivate plot.dataset $api}
            dict set slots canvas_api $api
        }
        if {[dict exists $manifest canvas_mount]} {uplevel #0 [list {*}[dict get $manifest canvas_mount] [dict get $slots canvas]]}
    } on error {message options} {destroy $window;return -options $options $message}
    return $slots
}
