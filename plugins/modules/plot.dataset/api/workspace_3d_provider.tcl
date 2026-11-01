# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::PlotWorkspace3D {variable receipts {};variable token {}}
::GX::nativeWorkspaceShapeRegister plot_representation3d {record {
    source_module_id text source_graph_id text source_variant_id text source_plot_reference {record {api_id text api_version int module_id text graph_id text variant_id text plot_id text kind text}}
    source_fingerprint text last_successful_sync_fingerprint text source_dataset_id text source_dataset_sha256 text
    viewer_scene {named scene3d} layers {map {named layer3d}} scientific_figure {named figure3d}
    presentation {record {plot_type text source_owner text}} caption text renderer_owner text
}}
proc ::GX::PlotWorkspace3D::encode {payload} {return [::GX::nativeWorkspaceEncode {named plot_representation3d} [dict remove $payload workspace_metadata]]}
proc ::GX::PlotWorkspace3D::validate {payload} {encode $payload}
proc ::GX::PlotWorkspace3D::remember {item} {
    variable receipts;variable token
    set current [::GX::interactiveDocumentSessionToken]
    if {$current ne $token} {set receipts {};set token $current}
    dict set receipts [dict get $item id] [dict create id [dict get $item id] generation [dict get $item generation] revision [dict get $item revision]]
    return $item
}
proc ::GX::PlotWorkspace3D::read {id} {
    set item [::GX::sessionWorkspaceGet $id]
    if {[dict get $item module_id] ne {plot.dataset} || [dict get $item provider_id] ni {plot_dataset_3d plot_dataset_3d_v4}} {error {Foreign Plot Dataset 3D Workspace}}
    return [remember $item]
}
proc ::GX::PlotWorkspace3D::save {id payload} {
    variable receipts;variable token
    if {$token ne [::GX::interactiveDocumentSessionToken] || ![dict exists $receipts $id]} {error {Open the Plot3D representation before saving}}
    return [remember [::GX::sessionWorkspaceUpdate $id $payload [dict get $receipts $id]]]
}
proc ::GX::PlotWorkspace3D::create {provider payload} {
    set name [::GX::sessionWorkspaceAvailableName "Plot3D [dict get $payload source_plot_reference variant_id]"]
    return [remember [::GX::sessionWorkspaceCreate $provider $name $payload]]
}
proc ::GX::PlotWorkspace3D::open {id} {
    set item [read $id]
    if {[dict get $item provider_id] eq {plot_dataset_3d_v4}} {
        ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
        ::GX::PlotDatasetAPIv4::activateInteractive $id
    } else {
        ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_3D_API_v1
        ::GX::PlotDataset3DAPIv1::activateRepresentation $id
    }
    return [::GX::viewerOpen viewer.native_3d native_3d [dict create scene_only 1]]
}

proc ::GX::PlotWorkspace3D::active {} {
    if {[info exists ::GX::PlotWorkspace3D::activeReceipt] && [lindex $::GX::PlotWorkspace3D::activeReceipt 0] eq [::GX::interactiveDocumentSessionToken]} {return [lindex $::GX::PlotWorkspace3D::activeReceipt 1]}
    return {}
}
proc ::GX::PlotWorkspace3D::activate {id} {set ::GX::PlotWorkspace3D::activeReceipt [list [::GX::interactiveDocumentSessionToken] $id]}
proc ::GX::PlotWorkspace3D::saveActive {} {
    set id [active];if {$id eq {}} {return {}}
    set metadata [::GX::nativeWorkspaceMetadata $id]
    if {[dict get $metadata provider_id] eq {plot_dataset_3d_v4}} {::GX::PlotDatasetAPIv4::_saveActiveNativeRepresentation} else {::GX::PlotDataset3DAPIv1::_saveActiveRepresentation}
    return [::GX::nativeWorkspaceFlush $id]
}
proc ::GX::PlotWorkspace3D::dirtyActive {} {
    set id [active];if {$id eq {}} {return 0}
    set item [read $id];set state [dict get $item payload]
    set current {};foreach layer [::GX::viewerLayerIds viewer.native_3d native_3d] {dict set current $layer [::GX::viewerLayerGet viewer.native_3d native_3d $layer]}
    if {[lsort [dict keys $current]] ne [lsort [dict keys [dict get $state layers]]]} {return 0}
    set saved {};dict for {key layer} [dict get $state layers] {dict set saved $key [dict remove $layer absolute_path attributes]}
    set normalized {};dict for {key layer} $current {dict set normalized $key [dict remove $layer absolute_path attributes]}
    return [expr {$normalized ne $saved || [::GX::viewerSceneGet viewer.native_3d native_3d] ne [dict get $state viewer_scene]}]
}
