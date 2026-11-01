# SPDX-License-Identifier: GPL-3.0-or-later
# Presentation/source-binding persistence only; original scientific owners stay separate.
namespace eval ::GX::Native3D {variable workspaceReceipts {};variable workspaceToken {}}
proc ::GX::Native3D::_workspaceCamera {value} {
    if {$value eq {}} {return {text {}}}
    return [::GX::nativeWorkspaceEncode {tuple {real real real}} $value]
}
::GX::nativeWorkspaceShapeRegister native3d_viewer {record {
    viewer_id text source_mode text source_dataset_id text source_path_hint text source_resource text source_sha256 text source_format text
    source_size int cache_key text cache_format_version int requested_lod text automatic_interaction_lod bool
    camera_position {codec ::GX::Native3D::_workspaceCamera} camera_target {codec ::GX::Native3D::_workspaceCamera} camera_up {codec ::GX::Native3D::_workspaceCamera}
    projection text parallel_scale {number_or_symbol {{}}} view_angle_deg {number_or_symbol {{}}} display_mode text visible bool opacity real
    lighting text background_rgb text clipping_enabled bool clipping_axis text clipping_fraction real notes text imported_at text
    vtu_layers {map {record {resource_path text sha256 text scalar_array text vector_array text visible bool opacity real}}}
    dataset_layers {map {record {dataset_id text sha256 text scalar_variable text coordinates {array text} vector_variables {array text} visible bool opacity real}}}
    object_visibility {map bool}
    pattern_regions {map {record {source_cell int radius real count_x int count_y int step_x real step_y real layout text visible bool opacity real placement_path text placement_sha256 text}}}
    repeat_component {record {source_cell int instances int prototype_triangles int}}
}}
proc ::GX::Native3D::workspaceEncode {payload} {return [::GX::nativeWorkspaceEncode {named native3d_viewer} [dict remove $payload workspace_metadata]]}
proc ::GX::Native3D::workspaceValidate {payload} {workspaceEncode $payload}
proc ::GX::Native3D::workspaceOpen {id} {
    ::GX::sessionWorkspaceValidate $id
    ::GX::modulePublicApiActivate viewer.native_3d NATIVE_3D_VIEWER_API_v1
    return [::GX::viewerOpen viewer.native_3d native_3d [dict create workspace_id $id]]
}
proc ::GX::Native3D::_workspaceRemember {full} {
    variable workspaceReceipts;variable workspaceToken
    set token [::GX::interactiveDocumentSessionToken]
    if {$token ne $workspaceToken} {set workspaceReceipts {};set workspaceToken $token}
    set expected [dict create id [dict get $full id] generation [dict get $full generation] revision [dict get $full revision]]
    dict set workspaceReceipts [dict get $full id] $expected
    return $full
}
proc ::GX::Native3D::_workspaceRead {id} {
    set full [::GX::sessionWorkspaceGet $id]
    if {[dict get $full module_id] ne {viewer.native_3d} || [dict get $full provider_id] ne {native_3d}} {error {Foreign Native3D Workspace owner}}
    return [_workspaceRemember $full]
}
proc ::GX::Native3D::_workspaceUpdate {id state} {
    variable workspaceReceipts;variable workspaceToken
    if {$workspaceToken ne [::GX::interactiveDocumentSessionToken] || ![dict exists $workspaceReceipts $id]} {error {Open this Native3D Workspace before saving}}
    return [_workspaceRemember [::GX::sessionWorkspaceUpdate $id $state [dict get $workspaceReceipts $id]]]
}
proc ::GX::Native3D::_workspaceCreate {state} {
    set name [::GX::sessionWorkspaceAvailableName "Native 3D [file tail [dict get $state source_path_hint]]"]
    return [_workspaceRemember [::GX::sessionWorkspaceCreate native_3d $name $state]]
}
proc ::GX::Native3D::_workspaceCurrent {} {
    if {$::GX::Native3D::documentId ne {}} {return $::GX::Native3D::documentId}
    if {[llength [info commands ::GX::PlotWorkspace3D::active]]} {return [::GX::PlotWorkspace3D::active]}
    return {}
}
proc ::GX::Native3D::_workspaceDirty {} {
    if {$::GX::Native3D::documentId eq {} && [llength [info commands ::GX::PlotWorkspace3D::dirtyActive]]} {return [::GX::PlotWorkspace3D::dirtyActive]}
    return 0
}
proc ::GX::Native3D::_workspaceSave {} {
    set id [_workspaceCurrent]
    if {$id eq {}} {error {Open a Native3D source before saving}}
    if {$::GX::Native3D::documentId eq {}} {return [::GX::PlotWorkspace3D::saveActive]}
    return [::GX::nativeWorkspaceFlush $id]
}
proc ::GX::Native3D::_workspacePrepare {action} {
    if {$::GX::Native3D::worker ne {}} {error {Finish or cancel Native3D preprocessing before changing Session}}
    if {[dict size $::GX::Native3D::patternPending] || [dict size $::GX::Native3D::repeatPending]} {error {Wait for the pending Native3D operation before changing Workspace}}
}
proc ::GX::Native3D::_workspaceDispose {} {
    _workspaceSaveIfPresent
    rootShutdown .
    set ::GX::Native3D::documentId {};set ::GX::Native3D::session {};set ::GX::Native3D::sceneOnly 0
    if {[winfo exists .gxNative3D]} {destroy .gxNative3D}
}
proc ::GX::Native3D::_workspaceSaveIfPresent {} {if {[_workspaceCurrent] ne {} && ($::GX::Native3D::documentId eq {} || $::GX::Native3D::workspaceToken eq [::GX::interactiveDocumentSessionToken])} {::GX::nativeWorkspaceFlush [_workspaceCurrent]}}
proc ::GX::Native3D::_workspaceMetadata {before after} {
    variable workspaceReceipts
    set id [dict get $before id]
    if {[dict exists $workspaceReceipts $id]} {
        set expected [dict get $workspaceReceipts $id]
        if {[dict get $expected generation] eq [dict get $before generation] && [dict get $expected revision] eq [dict get $before revision]} {dict set expected revision [dict get $after revision];dict set workspaceReceipts $id $expected}
    }
}
proc ::GX::Native3D::_workspaceMenuAttach {w} {
    menu $w.workspaceMenu -tearoff 0
    menu $w.workspaceMenu.files -tearoff 0
    $w.workspaceMenu add cascade -label Workspace -menu $w.workspaceMenu.files
    $w configure -menu $w.workspaceMenu
    set callbacks [dict create current ::GX::Native3D::_workspaceCurrent save ::GX::Native3D::_workspaceSave open ::GX::Native3D::_workspaceOpenAction dirty ::GX::Native3D::_workspaceDirty close ::GX::Native3D::_workspaceDispose discard ::GX::Native3D::_workspaceDispose prepare ::GX::Native3D::_workspacePrepare metadata_advanced ::GX::Native3D::_workspaceMetadata]
    ::GX::sessionWorkspaceViewerMenu $w.workspaceMenu.files native_3d $callbacks $w
}
proc ::GX::Native3D::_workspaceOpenAction {context} {
    set id [dict get $context workspace_id]
    if {$id eq {new}} {return [choose]}
    return [::GX::sessionWorkspaceOpen $id]
}
