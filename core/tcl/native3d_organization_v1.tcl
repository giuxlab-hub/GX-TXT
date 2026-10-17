# SPDX-License-Identifier: GPL-3.0-or-later
# Scoped organization belongs to CORE; opaque members are verified by Native3D.
proc ::GX::native3DOrganizationOperations {} {return {selection_set_create selection_set_get selection_set_list selection_set_update selection_set_delete selection_set_activate layer_create layer_get layer_list layer_update layer_delete layer_assign saved_view_create saved_view_get saved_view_list saved_view_update saved_view_delete saved_view_restore}}
proc ::GX::_native3DOrganizationMembers {token members} {
    if {[llength $members]>65536} {error "Native3D organization member limit is 65536"}
    set result {};foreach member $members {
        set object [dict get $member object_token];set info [native3DGeometryCall $token describe [dict create object_token $object]]
        if {[dict exists $member anchor]} {native3DGeometryCall $token anchor_describe [dict create object_token $object anchor [dict get $member anchor]]}
        dict set member geometry_sha256 [dict get $info geometry_sha256]
        dict set member world_transform [dict get $info world_transform];lappend result $member
    };return $result
}
proc ::GX::_native3DOrganizationMemberState {token member} {
    if {[catch {native3DGeometryCall $token describe [dict create object_token [dict get $member object_token]]} info]} {return missing}
    if {[dict get $info geometry_sha256] ne [dict get $member geometry_sha256]||[dict get $info world_transform] ne [dict get $member world_transform]} {return stale}
    return current
}
proc ::GX::native3DOrganizationCall {token action request} {
    variable ::GX::Native3DGeometry::scenes;variable ::GX::Native3DGeometry::serial
    set scope [_native3DGeometryRequire $token];set organization [datasetPublicationV2DictDefault $scope organization {}]
    set prefix [lindex [split $action _] 0];if {$prefix eq "selection"} {set prefix selection_set} elseif {$prefix eq "saved"} {set prefix saved_view}
    set operation [string range $action [expr {[string length $prefix]+1}] end]
    set collection [datasetPublicationV2DictDefault $organization $prefix {}]
    if {$operation eq "list"} {return [dict values $collection]}
    if {$operation eq "create"} {
        if {[dict size $collection]>=256} {error "Native3D $prefix limit is 256"}
        set id "native3d-$prefix#[pid]-[incr serial]";set value [dict create id $id name [dict get $request name]]
    } else {
        set id [dict get $request id];if {![dict exists $collection $id]} {error "Unknown or stale Native3D $prefix token"};set value [dict get $collection $id]
    }
    if {$operation in {create update}} {
        set fields [dict remove $request id]
        if {$prefix eq "selection_set"} {
            foreach key [dict keys $fields] {if {$key ni {name members}} {error "Unknown Selection Set field $key"}}
            if {[dict exists $fields members]} {dict set fields members [_native3DOrganizationMembers $token [dict get $fields members]]}
            set value [dict merge [dict create members {}] $value $fields]
        } elseif {$prefix eq "layer"} {
            foreach key [dict keys $fields] {if {$key ni {name visible selectable locked opacity color}} {error "Unknown Layer field $key"}}
            set value [dict merge [dict create visible 1 selectable 1 locked 0 opacity 1 color {0.78 0.82 0.9} members {}] $value $fields]
            foreach key {visible selectable locked} {dict set value $key [uiFieldNormalize {type boolean} [dict get $value $key]]}
            dict set value opacity [uiFieldNormalize {type number min 0 max 1} [dict get $value opacity]]
            if {[llength [dict get $value color]]!=3} {error "Layer color requires three components"}
            foreach component [dict get $value color] {uiFieldNormalize {type number min 0 max 1} $component}
        } else {
            foreach key [dict keys $fields] {if {$key ni {name view visibility working_unit}} {error "Unknown saved-view field $key"}}
            set value [dict merge $value $fields]
            unitRegistryConversionPlan [dict get $value working_unit] mm
            dict set value view [viewerSceneValidate viewer.3d_workbench workbench_3d [dict get $value view]]
            dict for {object visible} [dict get $value visibility] {native3DGeometryCall $token describe [dict create object_token $object];uiFieldNormalize {type boolean} $visible}
        }
        if {[string trim [dict get $value name]] eq {}} {error "Organization name must not be empty"}
        dict set collection $id $value
    } elseif {$operation eq "delete"} {dict unset collection $id} elseif {$operation eq "assign"&&$prefix eq "layer"} {
        dict set value members [_native3DOrganizationMembers $token [dict get $request members]];dict set collection $id $value
    } elseif {$operation in {get activate}} {
        if {$prefix eq "selection_set"} {
            set statuses {};foreach member [dict get $value members] {lappend statuses [_native3DOrganizationMemberState $token $member]};dict set value member_states $statuses
            if {$operation eq "activate"} {
                if {[lsearch -not -exact $statuses current]>=0} {error "Selection Set has stale/missing members; explicitly update its references"}
                dict for {layerId layer} [datasetPublicationV2DictDefault $organization layer {}] {if {[dict get $layer selectable]} continue;foreach member [dict get $value members] {foreach assigned [dict get $layer members] {if {[dict get $assigned object_token] eq [dict get $member object_token]} {error "Selection Set member is not selectable in Layer '[dict get $layer name]'"}}}}
                set mode [datasetPublicationV2DictDefault $request mode replace];if {$mode ni {replace add subtract}} {error "Selection mode must be replace, add or subtract"}
                set chosen [datasetPublicationV2DictDefault $organization selected_members {}]
                if {$mode eq "replace"} {set chosen [dict get $value members]} else {foreach member [dict get $value members] {set index [lsearch -exact $chosen $member];if {$mode eq "add"&&$index<0} {lappend chosen $member} elseif {$mode eq "subtract"&&$index>=0} {set chosen [lreplace $chosen $index $index]}}}
                dict set organization selected_members $chosen;dict set value selected_members $chosen
            }
        }
    } elseif {$operation eq "restore"&&$prefix eq "saved_view"} {
        if {[dict get $request working_unit] ne [dict get $value working_unit]} {error "Saved view has a different working unit; recapture it explicitly"}
        dict for {object visible} [dict get $value visibility] {native3DGeometryCall $token describe [dict create object_token $object]}
    } else {error "Unknown Native3D organization operation $action"}
    dict set organization $prefix $collection;dict set scenes $token organization $organization
    return $value
}
rename ::GX::native3DGeometryCall ::GX::native3DGeometryCall_organization_base
proc ::GX::native3DGeometryCall {token action request} {
    if {$action eq "compare_sections"} {tailcall native3DGeometryCompareSections $token $request}
    if {$action in [native3DOrganizationOperations]} {tailcall native3DOrganizationCall $token $action $request}
    if {$action eq "compare_geometry"} {
        if {![dict exists $request working_unit]} {error "Scientific geometry comparison requires an explicit working_unit"}
        unitRegistryConversionPlan [dict get $request working_unit] mm
        set result [native3DGeometryCall_organization_base $token $action $request]
        dict set result working_unit [dict get $request working_unit]
        set unit [dict get $request working_unit]
        dict set result statistics [::GX::StatisticsV1::fromNativeComparison surface $result [dict create x_unit $unit y_unit $unit z_unit $unit] [dict create producer core.native3d reference [dict get $request base] target [dict get $request tool]]]
        dict set result area_unit "[dict get $request working_unit]^2";dict set result volume_unit "[dict get $request working_unit]^3"
        return $result
    }
    if {$action in {translate rotate scale transform reset_transform delete clean weld orient heal mesh_heal_seam mesh_lod clip clip_cap align_three_points constraint_solve boolean mesh_append mesh_merge mesh_stitch mesh_bridge group_copy}} {
        set scope [_native3DGeometryRequire $token];set layers [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $scope organization {}] layer {}]
        set targets [datasetPublicationV2DictDefault $request object_tokens {}]
        foreach field {object_token base tool} {if {[dict exists $request $field]} {lappend targets [dict get $request $field]}}
        dict for {id layer} $layers {if {![dict get $layer locked]} continue;foreach member [dict get $layer members] {if {[dict get $member object_token] in $targets} {error "Geometry is locked by Native3D Layer '[dict get $layer name]'"}}}
    }
    tailcall native3DGeometryCall_organization_base $token $action $request
}
rename ::GX::native3DGeometryApiInfo ::GX::native3DGeometryApiInfo_organization_base
proc ::GX::native3DGeometryApiInfo {} {set info [native3DGeometryApiInfo_organization_base];dict set info geometry_operations [concat [dict get $info geometry_operations] {geometry_role compare_geometry compare_sections} [native3DOrganizationOperations]];return $info}
