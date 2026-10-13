# Additive scoped contracts use the existing scene and document lifetime checks.
proc ::GX::_native2DPartCall {token operation request} {
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native]
    set object [dict get $request object_token];set id [_native2DGeometryObject $scene $object]
    if {$operation eq "composition_parts"} {
        set parts {}
        foreach state [::GX::Native2D::core composition_states $native $id] {
            set definition [::GX::Native2D::core composition_part $native $id [dict get $state ordinal]]
            dict set state effective_direction [expr {[dict get $state direction forward]==[dict get [::GX::Native2D::core direction_marker $native $id] forward]}]
            dict set state topology_epoch [::GX::Native2D::core identity_topology_epoch $native $id]
            dict set state part_ref [dict create object_token $object part_id [dict get $state part_id]]
            lappend parts [dict merge $state $definition]
        }
        return [dict create parts $parts traversal [::GX::Native2D::core composition_traversal $native $id]]
    }
    if {$operation eq "composition_traversal"} {return [dict create traversal [::GX::Native2D::core composition_traversal $native $id]]}
    if {$operation eq "image_calibration_reset"} {
        set state [::GX::Native2D::core image_get $native $id]
        if {$state eq {}} {error {Object is not a reference image}}
        dict set state calibrated 0
        return [dict create image_state [::GX::Native2D::core image_update $native $id $state]]
    }
    if {$operation eq "part_pick"} {set id [::GX::Native2D::core part_pick $native $id [dict get $request device] [datasetPublicationV2DictDefault $request tolerance_px 5]];return [dict create part_id $id]}
    if {$operation eq "part_direction_batch"} {return [dict create parts [::GX::Native2D::core part_direction_batch $native $id [dict get $request updates]]]}
    set part [dict get $request part_id]
    switch -- $operation {
        part_direction {set args {};if {[dict exists $request changes]} {lappend args [dict get $request changes]};return [dict create direction [::GX::Native2D::core part_direction $native $id $part {*}$args]]}
        part_render {return [dict create points [::GX::Native2D::core part_render $native $id $part]]}
        part_marker_geometry {return [dict create geometry [::GX::Native2D::core part_marker_render $native $id $part]]}
        part_marker_hit {return [dict create hit [::GX::Native2D::core part_marker_hit $native $id $part [dict get $request device] [datasetPublicationV2DictDefault $request tolerance_px 5]]]}
        part_marker_place {return [dict create fraction [::GX::Native2D::core part_marker_place $native $id $part [dict get $request device]]]}
    }
    error {Unknown constituent operation}
}
