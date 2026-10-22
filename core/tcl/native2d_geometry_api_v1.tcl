# SPDX-License-Identifier: GPL-3.0-or-later
# Document- and Session-scoped retained Native2D geometry. Public callers see
# opaque logical tokens; only this authority maps them to native scene IDs.
namespace eval ::GX::Native2DGeometry {variable scenes {};variable serial 0}
source [file join [file dirname [info script]] native2d_diagram_document_v1.tcl]
proc ::GX::native2DGeometryPathValidate {points topology} {
    if {$topology ni {open closed}} {error {Explicit open/closed topology required}}
    native2DEnsure;set scene [::GX::Native2D::core scene]
    try {return [::GX::Native2D::core path_validate $scene $points [expr {$topology eq "closed"}]]} finally {::GX::Native2D::core destroy $scene}
}
proc ::GX::native2DGeometryPolarBulk {frame encoded} {
    native2DEnsure
    if {[string length $encoded]>1398104} {error "Polar bulk input exceeds65536 XY rows"}
    set bytes [binary decode base64 -strict $encoded]
    set scene [::GX::Native2D::core scene]
    try {
        set frame [::GX::Native2D::core polar $scene $frame]
        set result [::GX::Native2D::core polar_binary $scene $bytes]
        return [dict create format native2d.float64_theta_r_le_v1 row_count [expr {[string length $bytes]/16}] theta_r_base64 [binary encode base64 -maxlen 0 [dict get $result theta_r]] angle_defined_base64 [binary encode base64 -maxlen 0 [dict get $result angle_defined]] frame $frame policy native_cartesian_to_polar origin_angle_policy zero_placeholder_with_explicit_angle_defined0 normalization positive_full_turn]
    } finally {::GX::Native2D::core destroy $scene}
}
proc ::GX::native2DGeometryApiInfo {} {
    return [dict create api_id NATIVE_2D_GEOMETRY_API_v1 api_version 1 operations {path_validate open raster_dataset_bind raster_snapshot raster_save raster_restore raster_roi_set raster_roi_get raster_roi_remove raster_roi_geometry raster_roi_pick raster_roi_propose raster_layer_get raster_layer_update raster_prepare raster_submit raster_freeze axis_presentation composition_parts composition_traversal part_direction part_direction_batch part_render part_marker_geometry part_marker_hit part_marker_place part_pick image_calibration_reset selection_definition spline_line_plan spline_span_to_line composition_create composition_part composition_split composition_explode path_vertices path_split path_join primitive_publish dataset_promote image_attach image_get image_update image_calibrate image_map symmetry_preview symmetry_construct canvas_preview spline_tangent_get spline_tangent_edit fit_all fit_selected fit_bounds zoom pan scene_bounds world_to_device device_to_world pixel_tolerance construct_attached placement_points placement_preview reference_connected sketch_status sketch_component dimension_infer dimension_preview dimension_apply dimension_geometry relationship_state relationship_hit construct construct_preview from_fit controls reference reference_resolve reference_point_index control_definition control_edit constraint_options constraint_apply constraint_location polar_bulk compare_geometry geometry_role series_create series_get series_list series_members series_update series_transform series_bounds series_delete series_explode saved_view_create saved_view_get saved_view_list saved_view_update saved_view_restore saved_view_delete view_state view_state_rescale layer_create layer_get layer_list layer_update layer_delete layer_assign selection_pick selection_region selection_set_apply selection_set_restore selection_set_bounds selection_set_create selection_set_get selection_set_list selection_set_update selection_set_add_member selection_set_remove_member selection_set_delete selection_set_activate identity fragment_create fragment_get fragment_list fragment_update fragment_delete fragment_sample fragment_length fragment_bounds fragment_materialize sketch sketch_update sketch_evaluate sketch_sample sketch_materialize sketch_explode curve from_source describe metrics measure path_point replace_points points_page nearest_vertex rescale_coordinates affine series group group_members group_add group_remove ungroup delete endpoint_frame bridge spline compare selection pivot grid polar view style direction export_resource restore_resource constraint_create constraint_join constraint_get constraint_list constraint_update constraint_enable constraint_delete checkpoint close} host_operations {native2DGeometryViewportAttach native2DGeometryViewportDraw} raw_pointers 0 implicit_dataset_publication 0 point_page_limit 65536]
}
proc ::GX::native2DGeometryOpen {document} {
    variable ::GX::Native2DGeometry::scenes;variable ::GX::Native2DGeometry::serial
    set owner [interactiveDocumentRead $document]
    native2DEnsure
    set token "native2d-scene#[pid]-[incr serial]-[clock clicks]"
    dict set scenes $token [dict create scene_token $token document_id $document generation [dict get $owner generation] revision [dict get $owner revision] session_token [interactiveDocumentSessionToken] native [::GX::Native2D::core scene] objects {} constraints {}]
    return $token
}
proc ::GX::_native2DGeometryRequire {token} {
    variable ::GX::Native2DGeometry::scenes
    if {![dict exists $scenes $token]} {error "Unknown or closed Native2D scene token"}
    set scene [dict get $scenes $token]
    if {[dict get $scene session_token] ne [interactiveDocumentSessionToken]} {error "Native2D scene belongs to another Session lifetime"}
    set owner [interactiveDocumentRead [dict get $scene document_id]]
    if {[dict get $scene generation] ne [dict get $owner generation]} {error "Native2D document owner was replaced"}
    if {[dict get $scene revision] ne [dict get $owner revision]} {error "Native2D document revision changed; reopen and restore authoritative geometry"}
    return $scene
}
proc ::GX::_native2DGeometryObject {scene token} {
    if {![dict exists $scene objects $token]} {error "Object token is not owned by this Native2D scene"}
    set object [dict get $scene objects $token]
    if {[dict get $object native] ni [::GX::Native2D::core ids [dict get $scene native]]} {error "Native2D object was removed; its token is stale"}
    return [dict get $object native]
}
proc ::GX::_native2DGeometryAdopt {token native {metadata {}}} {
    variable ::GX::Native2DGeometry::scenes;variable ::GX::Native2DGeometry::serial
    set id "native2d-object#[pid]-[incr serial]-[clock clicks]"
    dict set scenes $token objects $id [dict create native $native metadata $metadata]
    try {return [native2DGeometryCall $token describe [dict create object_token $id]]} on error {message options} {
        dict unset scenes $token objects $id
        ::GX::Native2D::core delete [dict get $scenes $token native] $native
        return -options $options $message
    }
}
proc ::GX::_native2DGeometryAdoptCopies {token receipt operation parameters} {
    variable ::GX::Native2DGeometry::scenes
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native];set tokens {};set objects {}
    try {
        foreach id [dict get $receipt object_ids] sourceId [dict get $receipt source_ids] {
            set metadata {}
            dict for {old entry} [dict get $scene objects] {if {[dict get $entry native]==$sourceId} {set metadata [dict get $entry metadata];dict set metadata parent_geometry_token $old;break}}
            dict set metadata geometry_operation $operation;dict set metadata geometry_parameters $parameters
            if {$operation eq "affine_copy"} {dict set metadata affine_matrix [dict get $parameters matrix]}
            set item [_native2DGeometryAdopt $token $id $metadata]
            lappend objects $item;lappend tokens [dict get $item object_token]
        }
        return [dict create object_tokens $tokens objects $objects copy 1]
    } on error {message options} {
        foreach object $tokens {dict unset scenes $token objects $object}
        set live [::GX::Native2D::core ids $native]
        foreach id [dict get $receipt object_ids] {if {$id in $live} {::GX::Native2D::core delete $native $id}}
        return -options $options $message
    }
}
proc ::GX::_native2DGeometrySourceInput {token descriptor input} {
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native];set document [dict get $scene document_id]
    set object [native2DLoadNumericRowsWithGaps $native [dict get $input xy_file] [dict get $input break_before_file]]
    try {
        set rows [interactiveDocumentResourceImportNumeric $document [dict get $input source_rows_file] [dict create format native2d.uint64_source_rows_le_v1 point_count [dict get $input row_count]]]
        set gaps [interactiveDocumentResourceImportNumeric $document [dict get $input break_before_file] [dict create format native2d.uint8_break_before_v1 point_count [dict get $input row_count]]]
        _native2DGeometryRequire $token
        return [_native2DGeometryAdopt $token $object [dict create source_kind [dict get $descriptor source_kind] source_id [dict get $descriptor source_id] source_descriptor $descriptor source_rows_resource $rows gap_resource $gaps]]
    } on error {message options} {
        if {$object in [::GX::Native2D::core ids $native]} {::GX::Native2D::core delete $native $object}
        return -options $options $message
    }
}
proc ::GX::native2DGeometryCheckpoint {token payload} {
    variable ::GX::Native2DGeometry::scenes
    set scene [_native2DGeometryRequire $token]
    set result [interactiveDocumentUpdate [dict get $scene document_id] $payload]
    dict set scenes $token revision [dict get $result revision]
    return $result
}
proc ::GX::native2DGeometryClose {token} {
    variable ::GX::Native2DGeometry::scenes
    if {![dict exists $scenes $token]} {error "Unknown or closed Native2D scene token"}
    # Closing is valid after owner/Session expiry, so script cleanup can always
    # release this authority's scene without writing to the current Session.
    dict for {object reader} [datasetPublicationV2DictDefault [dict get $scenes $token] raster_resource_readers {}] {
        catch {interactiveDocumentResourceCloseReader $reader}
    }
    native2DRasterSceneDispose [dict get $scenes $token native]
    ::GX::Native2D::core destroy [dict get $scenes $token native]
    dict unset scenes $token
    return 1
}
proc ::GX::_native2DGeometryConstraintAdopt {token receipt} {
    variable ::GX::Native2DGeometry::scenes;variable ::GX::Native2DGeometry::serial
    set scene [_native2DGeometryRequire $token]
    set constraint "native2d-constraint#[pid]-[incr serial]-[clock clicks]"
    dict set scenes $token constraints $constraint [dict get $receipt id]
    return [_native2DGeometryConstraintReceipt $scene $constraint $receipt]
}
proc ::GX::_native2DGeometryConstraintSpec {scene definition} {
    foreach key [dict keys $definition] {if {$key ni {kind a_token b_token axis_token a_index b_index axis_index value tolerance angular_tolerance disabled anchor solved driven placed annotation branch curvature_tolerance}} {error "Unknown Native2D constraint parameter: $key"}}
    set native [dict remove $definition a_token b_token axis_token]
    set objects {}
    foreach field {a b axis} {
        set key ${field}_token
        if {[dict exists $definition $key]} {lappend objects [dict get $definition $key];dict set native $field [_native2DGeometryObject $scene [dict get $definition $key]]}
    }
    if {![dict exists $native a]} {error "Constraint requires a_token"}
    _native2DGeometryCommonFrame $scene $objects
    return $native
}
proc ::GX::_native2DGeometryConstraintReceipt {scene token receipt} {
    dict unset receipt id
    dict set receipt constraint_token $token
    foreach field {a b axis} {
        set native [dict get $receipt $field];dict unset receipt $field
        if {$native==0} continue
        set found 0
        dict for {object entry} [dict get $scene objects] {if {[dict get $entry native]==$native} {dict set receipt ${field}_token $object;set found 1;break}}
        if {!$found} {error "Constraint references geometry outside its public scene ownership"}
    }
    return $receipt
}
proc ::GX::_native2DGeometryCoordinateUnits {scene object} {
    set metadata [dict get $scene objects $object metadata]
    if {[dict exists $metadata coordinate_units]} {return [dict get $metadata coordinate_units]}
    if {[dict exists $metadata working_unit]} {return [lrepeat 2 [dict get $metadata working_unit]]}
    set units [list {} {}]
    if {[dict exists $metadata source_descriptor variables]} {
        set descriptor [dict get $metadata source_descriptor]
        foreach variable [dict get $descriptor variables] {
            foreach axis {x y} index {0 1} {if {[dict get $variable variable_id] eq [dict get $descriptor request ${axis}_variable_id]} {lset units $index [dict get $variable unit]}}
        }
    }
    return $units
}
proc ::GX::_native2DCoordinateFrame {units {relations {}}} {
    # Resolve immutable numeric-plane meaning, never a physical metric. The
    # Unit Registry remains the owner of relation syntax and conversions.
    if {[llength $units]!=2} {error {Coordinate frame requires ordered X/Y units}}
    foreach axis [dict keys $relations] {if {$axis ni {x y}} {error "Unknown coordinate relation axis '$axis'"}}
    set normalized {}
    foreach axis {x y} unit $units {
        if {[string length $unit]>256||[regexp {[\r\n]} $unit]} {error {Invalid coordinate unit}}
        set definition [unitRegistryDefinition $unit];set nominal {}
        foreach field {canonical_unit to_canonical from_canonical} {dict set nominal $field [dict get $definition $field]}
        set relation [datasetPublicationV2DictDefault $relations $axis {}]
        foreach field [dict keys $relation] {if {$field ni {canonical_unit to_canonical from_canonical}} {error "Unknown coordinate relation field '$field'"}}
        set resolved [dict merge $nominal $relation]
        if {[dict get $resolved canonical_unit] eq {}} {
            if {[dict get $resolved to_canonical] ne {}||[dict get $resolved from_canonical] ne {}} {error {Coordinate formulas require a canonical unit}}
        } else {unitRegistryConversionPlan $unit [dict get $resolved canonical_unit] $resolved}
        if {$resolved ne $nominal} {dict set normalized $axis $resolved}
    }
    set common {};if {[lindex $units 0] eq [lindex $units 1]} {set common [lindex $units 0]}
    return [dict create coordinate_units $units coordinate_relations $normalized working_unit $common]
}
proc ::GX::_native2DGeometryCoordinateFrame {scene object} {
    set metadata [dict get $scene objects $object metadata]
    set relations [datasetPublicationV2DictDefault $metadata coordinate_relations {}]
    if {![dict exists $metadata coordinate_relations]&&![dict exists $metadata coordinate_conversions]&&[dict exists $metadata source_descriptor variables]} {
        set descriptor [dict get $metadata source_descriptor];set request [dict get $descriptor request]
        set relations [native2DSourceCoordinateRelations $descriptor [dict get $request x_variable_id] [dict get $request y_variable_id]]
    }
    return [_native2DCoordinateFrame [_native2DGeometryCoordinateUnits $scene $object] $relations]
}
proc ::GX::_native2DCoordinateVariableSchema {variable} {
    set unit [dict get $variable unit];set definition [unitRegistryDefinition $unit]
    set result [dict create unit $unit]
    foreach field {canonical_unit to_canonical from_canonical} {dict set result $field [dict get $definition $field]}
    if {[datasetPublicationV2DictDefault $variable canonical_unit {}] ne {}} {
        foreach field {canonical_unit to_canonical from_canonical} {dict set result $field [dict get $variable $field]}
    } elseif {[datasetPublicationV2DictDefault $variable to_canonical {}] ne {}||[datasetPublicationV2DictDefault $variable from_canonical {}] ne {}} {error {Coordinate formulas require a canonical unit}}
    return $result
}
proc ::GX::_native2DGeometryCommonFrame {scene objects} {
    if {$objects eq {}} {error {Select at least one geometry object}}
    set frame [_native2DGeometryCoordinateFrame $scene [lindex $objects 0]]
    foreach object [lrange $objects 1 end] {if {[_native2DGeometryCoordinateFrame $scene $object] ne $frame} {error {Geometry requires the same complete X/Y coordinate frame and frozen relations}}}
    return $frame
}
proc ::GX::_native2DMeasurementCoordinateUnit {kind frame} {
    if {[dict get $frame coordinate_relations] ne {}} {error {Normalize variable-specific coordinate relations through Dataset Transform before physical measurement}}
    set units [dict get $frame coordinate_units]
    if {$kind in {horizontal_distance bounding_width}} {return [lindex $units 0]}
    if {$kind in {vertical_distance bounding_height}} {return [lindex $units 1]}
    if {[lindex $units 0] ne [lindex $units 1]} {error {Physical plane measurements require explicitly normalized common X/Y working coordinates; use axis-specific measurements or Dataset Transform}}
    unitRegistryHomogeneousCoordinatePlan [lindex $units 0] [lindex $units 0]
    native2DComparisonFrame path $units $units
    return [lindex $units 0]
}
proc ::GX::_native2DGeometryWorkingUnit {scene object} {
    set units [_native2DGeometryCoordinateUnits $scene $object]
    if {[lindex $units 0] eq [lindex $units 1]} {return [lindex $units 0]}
    return {}
}
proc ::GX::native2DSourceCoordinateRelations {descriptor xVariable yVariable} {
    set relations {}
    foreach axis {x y} selected [list $xVariable $yVariable] {
        foreach variable [dict get $descriptor variables] {
            if {[dict get $variable variable_id] ne $selected} continue
            set nominal [unitRegistryDefinition [dict get $variable unit]]
            foreach field {canonical_unit to_canonical from_canonical} {
                set value [datasetPublicationV2DictDefault $variable $field {}]
                if {$value ne {}&&$value ne [dict get $nominal $field]} {dict set relations $axis $field $value}
            }
        }
    }
    return $relations
}
proc ::GX::_native2DGeometryComparableUnits {scene object} {
    if {[dict get [_native2DGeometryCoordinateFrame $scene $object] coordinate_relations] ne {}} {error {Variable-specific coordinate relations require explicit Dataset Transform normalization before physical comparison or metrics}}
    return [_native2DGeometryCoordinateUnits $scene $object]
}
proc ::GX::native2DComparisonFrame {method referenceUnits targetUnits {options {}}} {
    if {$method ni {x path geometry}} {error {Comparison method must be x, path or geometry}}
    foreach key [dict keys $options] {if {$key ne "output_units"} {error "Unknown comparison frame option '$key'"}}
    if {[llength $referenceUnits]!=2||[llength $targetUnits]!=2} {error {Comparison requires ordered X/Y coordinate units}}
    set output [datasetPublicationV2DictDefault $options output_units [expr {$method eq "x"?$referenceUnits:[lrepeat 2 [lindex $referenceUnits 0]]}]]
    if {[llength $output]!=2} {error {Comparison output_units requires ordered X/Y units}}
    if {$method ne "x"&&[lindex $output 0] ne [lindex $output 1]} {error {Euclidean comparison requires one common physical output unit}}
    # Equal labels alone do not establish a proportional physical plane. Keep
    # the existing wholly unlabelled numeric inspection route; its statistical
    # physical quantities remain unavailable. X-wise matching has separate axes.
    set homogeneous [expr {$method ne "x"&&[lsearch -not -exact [concat $referenceUnits $targetUnits $output] {}]>=0}]
    set frame [dict create schema_version 1 method $method reference_units $referenceUnits target_units $targetUnits output_units $output]
    foreach role {reference target} units [list $referenceUnits $targetUnits] {
        set scales {};set offsets {}
        foreach source $units destination $output {
            if {$homogeneous} {unitRegistryHomogeneousCoordinatePlan $source $destination}
            set plan [unitRegistryAffinePlan $source $destination]
            if {![dict get $plan affine]||[dict get $plan scale]<=0} {error {Comparison requires a positive affine coordinate conversion; explicitly normalize nonlinear source coordinates through Dataset Transform}}
            lappend scales [dict get $plan scale];lappend offsets [dict get $plan offset]
        }
        dict set frame ${role}_matrix [list [lindex $scales 0] 0.0 0.0 [lindex $scales 1] {*}$offsets]
    }
    return $frame
}
proc ::GX::native2DComparisonPoint {receipt role point} {
    # Convert a reported projection back to its original Native object frame.
    # This inverts the recorded evaluation matrix, not a mutable unit definition.
    if {$role ni {reference target}} {error {Comparison point role must be reference or target}}
    if {![dict exists $receipt coordinate_frame]} {return $point}
    if {[llength $point]!=2} {error {Comparison point requires X/Y}}
    lassign [dict get $receipt coordinate_frame ${role}_matrix] sx b c sy tx ty
    if {$b!=0||$c!=0||$sx<=0||$sy<=0} {error {Invalid comparison coordinate frame}}
    set result {}
    foreach value $point scale [list $sx $sy] offset [list $tx $ty] {
        lappend result [uiFieldNormalize {type number} [expr {($value-$offset)/$scale}]]
    }
    return $result
}
proc ::GX::_native2DFrameObject {scene object matrix} {
    lassign $matrix sx b c sy tx ty
    if {$sx==1&&$sy==1&&$tx==0&&$ty==0} {return [dict create object $object temporary {}]}
    set copied [::GX::Native2D::core affine $scene [list $object] $matrix 1]
    set ids [dict get $copied object_ids]
    if {[llength $ids]!=1} {
        foreach id [lreverse $ids] {::GX::Native2D::core delete $scene $id}
        error {Evaluation requires one curve per coordinate frame}
    }
    return [dict create object [lindex $ids 0] temporary $ids]
}
proc ::GX::native2DMetrics {scene object units {options {}}} {
    set frame [native2DComparisonFrame geometry $units $units $options]
    set prepared [_native2DFrameObject $scene $object [dict get $frame reference_matrix]]
    try {set result [::GX::Native2D::core metrics $scene [dict get $prepared object]]} finally {foreach id [dict get $prepared temporary] {::GX::Native2D::core delete $scene $id}}
    dict set result coordinate_frame $frame
    dict set result unit [lindex [dict get $frame output_units] 0]
    return $result
}
proc ::GX::native2DComparison {scene reference target method budget referenceUnits targetUnits provenance {options {}}} {
    # One scientific boundary for both public opaque scenes and Workbench scenes.
    set frame [native2DComparisonFrame $method $referenceUnits $targetUnits $options]
    set temporaries {};set objects {}
    try {
        foreach role {reference target} object [list $reference $target] {
            set prepared [_native2DFrameObject $scene $object [dict get $frame ${role}_matrix]]
            lappend temporaries {*}[dict get $prepared temporary]
            lappend objects [dict get $prepared object]
        }
        if {$method eq "geometry"} {set receipt [::GX::Native2D::core compare_geometry $scene {*}$objects $budget]} else {set receipt [::GX::Native2D::core compare_lod $scene {*}$objects $method $budget]}
    } finally {foreach object [lreverse $temporaries] {::GX::Native2D::core delete $scene $object}}
    lassign [dict get $frame output_units] xUnit yUnit
    dict set receipt coordinate_frame $frame
    dict set provenance coordinate_frame $frame
    dict set receipt statistics [::GX::StatisticsV1::fromNativeComparison $method $receipt [dict create x_unit $xUnit y_unit $yUnit] $provenance]
    dict set receipt unit $yUnit
    if {$method eq "geometry"} {dict set receipt area_unit [expr {$xUnit eq {} ? {} : "$xUnit^2"}]}
    return $receipt
}
proc ::GX::native2DGeometryCall {token operation request} {
    variable ::GX::Native2DGeometry::scenes
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native]
    if {[catch {dict size $request}]} {error "Native2D request must be a public struct"}
    switch -- $operation {
        selection_definition - spline_line_plan - spline_span_to_line {
            set object [_native2DGeometryObject $scene [dict get $request object_token]]
            return [::GX::Native2D::core $operation $native $object [dict get $request index]]
        }
        composition_create {
            set ids {};set sources [dict get $request object_tokens]
            set frame [_native2DGeometryCommonFrame $scene $sources]
            foreach source $sources {lappend ids [_native2DGeometryObject $scene $source]}
            set arrangement [datasetPublicationV2DictDefault $request arrangement compound]
            if {$arrangement ni {compound ordered_path auto_path}} {error {Composition arrangement must be compound, ordered_path or auto_path}}
            set mode [lsearch -exact {compound ordered_path auto_path} $arrangement]
            set id [::GX::Native2D::core composition_create $native $ids [datasetPublicationV2DictDefault $request reversals {}] $mode [datasetPublicationV2DictDefault $request tolerance 0]]
            return [_native2DGeometryAdopt $token $id [dict create {*}$frame parent_geometry_tokens $sources geometry_operation $arrangement {*}[_native2DPathProvenance $scene $sources]]]
        }
        composition_part {
            return [::GX::Native2D::core composition_part $native [_native2DGeometryObject $scene [dict get $request object_token]] [dict get $request part_index]]
        }
        composition_split - composition_explode {
            set source [dict get $request object_token];set id [_native2DGeometryObject $scene $source]
            set args {};if {$operation eq "composition_split"} {lappend args [dict get $request junction_index]}
            set natives [::GX::Native2D::core $operation $native $id {*}$args]
            set result [_native2DGeometryAdoptCopies $token [dict create object_ids $natives source_ids [lrepeat [llength $natives] $id]] $operation [dict remove $request object_token]]
            dict set result source_modified 0
            return $result
        }
        metrics {
            foreach key [dict keys $request] {if {$key ni {object_token output_units}} {error "Unknown metrics parameter '$key'"}}
            set options {};if {[dict exists $request output_units]} {dict set options output_units [dict get $request output_units]}
            return [native2DMetrics $native [_native2DGeometryObject $scene [dict get $request object_token]] [_native2DGeometryComparableUnits $scene [dict get $request object_token]] $options]
        }
        measure {
            foreach key [dict keys $request] {if {$key ni {kind a_token b_token a_index b_index pair_budget}} {error "Unknown Native2D measurement field: $key"}}
            set spec [dict remove $request a_token b_token]
            foreach field {a b} {if {[dict exists $request ${field}_token]} {dict set spec $field [_native2DGeometryObject $scene [dict get $request ${field}_token]]}}
            set objects [list [dict get $request a_token]]
            if {[dict exists $request b_token]} {lappend objects [dict get $request b_token]}
            set frame [_native2DGeometryCommonFrame $scene $objects]
            set unit [_native2DMeasurementCoordinateUnit [dict get $request kind] $frame]
            set result [::GX::Native2D::core measure $native $spec]
            dict set result unit_declared [expr {$unit ne {}}]
            dict set result working_unit $unit
            dict set result unit [expr {[dict get $result angular] ? "rad" : $unit eq {} ? {} : [dict get $result unit_power]==2 ? "${unit}^2" : $unit}]
            dict set result kind [dict get $request kind]
            return $result
        }
        constraint_create {
            set spec [_native2DGeometryConstraintSpec $scene [dict get $request definition]]
            set receipt [::GX::Native2D::core constraint_create $native $spec]
            return [_native2DGeometryConstraintAdopt $token $receipt]
        }
        constraint_join {
            _native2DGeometryCommonFrame $scene [list [dict get $request a_token] [dict get $request b_token]]
            set a [_native2DGeometryObject $scene [dict get $request a_token]];set b [_native2DGeometryObject $scene [dict get $request b_token]]
            set receipt [::GX::Native2D::core constraint_join $native $a [dict get $request a_index] $b [dict get $request b_index] [datasetPublicationV2DictDefault $request merge 1] [datasetPublicationV2DictDefault $request tolerance 1e-8]]
            return [_native2DGeometryConstraintAdopt $token $receipt]
        }
        constraint_list {
            set constraints {}
            foreach receipt [::GX::Native2D::core constraint_list $native] {
                set found 0
                dict for {constraint id} [dict get $scene constraints] {if {$id==[dict get $receipt id]} {lappend constraints [_native2DGeometryConstraintReceipt $scene $constraint $receipt];set found 1;break}}
                if {!$found} {error "Native constraint has no owned logical token"}
            }
            return [dict create constraints $constraints general_solver 0]
        }
        constraint_get - constraint_update - constraint_enable - constraint_delete {
            set constraint [dict get $request constraint_token]
            if {![dict exists $scene constraints $constraint]} {error "Constraint token is not owned by this Native2D scene"}
            set id [dict get $scene constraints $constraint]
            switch -- $operation {
                constraint_update {set receipt [::GX::Native2D::core constraint_update $native $id [_native2DGeometryConstraintSpec $scene [dict get $request definition]]]}
                constraint_enable {set receipt [::GX::Native2D::core constraint_enable $native $id [dict get $request enabled]]}
                constraint_delete {::GX::Native2D::core constraint_delete $native $id;dict unset scenes $token constraints $constraint;return 1}
                default {set receipt [::GX::Native2D::core constraint_get $native $id]}
            }
            return [_native2DGeometryConstraintReceipt $scene $constraint $receipt]
        }

        rescale_coordinates {
            set from [dict get $request source_unit];set to [dict get $request target_unit]
            set factor [lindex [unitRegistryConvertCoordinates $from $to {1}] 0]
            set assume [uiFieldNormalize {type boolean} [datasetPublicationV2DictDefault $request assume_undeclared 0]]
            set prepared $scene
            dict for {object entry} [dict get $scene objects] {
                set metadata [dict get $entry metadata]
                if {[::GX::Native2D::core kind $native [dict get $entry native]] ne "group"} {
                    set frame [_native2DGeometryCoordinateFrame $scene $object]
                    if {[dict get $frame coordinate_relations] ne {}} {error "Geometry $object has variable-specific coordinate calibration; normalize the source through Dataset Transform before proportional frame conversion"}
                    set units [dict get $frame coordinate_units]
                    foreach unit $units {
                        if {$unit eq {}&&!$assume} {error "Geometry $object has undeclared coordinate units; explicitly choose assume_undeclared or annotate its working unit"}
                        if {$unit ne {}&&$unit ne $from} {error "Geometry $object uses $unit, not $from; normalize mixed coordinate units before scene conversion"}
                    }
                }
                dict set metadata working_unit $to
                dict set metadata coordinate_units [lrepeat 2 $to]
                dict set metadata coordinate_relations {}
                dict lappend metadata coordinate_conversions [dict create source_unit $from target_unit $to factor $factor assumed_undeclared $assume physical_scale 0]
                if {[dict exists $metadata affine_matrix]} {
                    set matrix [dict get $metadata affine_matrix]
                    set matrix [lreplace $matrix 4 5 {*}[unitRegistryConvertCoordinates $from $to [lrange $matrix 4 5]]]
                    dict set metadata affine_matrix $matrix
                }
                if {[dict exists $metadata bridge_descriptor]} {
                    set bridge [dict get $metadata bridge_descriptor]
                    foreach key {start_derivative end_derivative} {if {[dict exists $bridge $key]} {dict set bridge $key [unitRegistryConvertCoordinates $from $to [dict get $bridge $key]]}}
                    foreach key {start end} {if {[dict exists $bridge $key]} {foreach component {point derivative} {dict set bridge $key $component [unitRegistryConvertCoordinates $from $to [dict get $bridge $key $component]]}}}
                    set controls {};foreach point [dict get $bridge controls] {lappend controls [unitRegistryConvertCoordinates $from $to $point]};dict set bridge controls $controls
                    if {[dict exists $bridge tolerance]} {dict set bridge tolerance [expr {[dict get $bridge tolerance]*$factor}]}
                    dict set metadata bridge_descriptor $bridge
                }
                dict set prepared objects $object metadata $metadata
            }
            dict set prepared working_unit $to
            if {[dict exists $prepared series_containers]} {dict for {id record} [dict get $prepared series_containers] {dict set prepared series_containers $id [native2DSeriesRescaleRecord $record $factor]}}
            ::GX::Native2D::core rescale_coordinates $native $factor
            dict for {object entry} [dict get $scene objects] {
                set id [dict get $entry native];set image [::GX::Native2D::core image_get $native $id]
                if {$image ne {}} {dict set image length_unit $to;::GX::Native2D::core image_update $native $id $image}
            }
            dict set scenes $token $prepared
            return [dict create source_unit $from target_unit $to factor $factor object_count [dict size [dict get $scene objects]] physical_scale 0]
        }
        nearest_vertex {
            set excluded {};foreach object [datasetPublicationV2DictDefault $request exclude_object_tokens {}] {lappend excluded [_native2DGeometryObject $scene $object]}
            set endpoints [uiFieldNormalize {type boolean} [datasetPublicationV2DictDefault $request endpoints_only 0]]
            set result [::GX::Native2D::core scene_nearest_vertex $native [dict get $request point] [dict get $request radius] $excluded $endpoints]
            if {$result eq {}} {return [dict create found 0]}
            set found [dict get $result object];dict unset result object
            dict for {object entry} [dict get $scene objects] {if {[dict get $entry native]==$found} {dict set result object_token $object;dict set result found 1;return $result}}
            error "Nearest Native geometry has no owned logical token"
        }
        sketch {
            set metadata [dict create geometry_authority retained_sketch]
            set unit [datasetPublicationV2DictDefault $request working_unit [datasetPublicationV2DictDefault $scene working_unit {}]]
            if {$unit ne {}} {unitRegistryConversionPlan $unit $unit;dict set metadata working_unit $unit}
            if {[dict exists $request coordinate_units]} {set metadata [dict merge $metadata [_native2DCoordinateFrame [dict get $request coordinate_units] [datasetPublicationV2DictDefault $request coordinate_relations {}]]]}
            set samples [datasetPublicationV2DictDefault $request display_samples 257]
            return [_native2DGeometryAdopt $token [::GX::Native2D::core sketch_create $native [dict get $request definition] $samples] $metadata]
        }
        curve {
            set kind curve;if {[dict exists $request kind]} {set kind [dict get $request kind]}
            if {$kind ni {curve pointset point}} {error "Geometry kind must be curve, pointset or point"}
            set points [dict get $request points]
            if {[llength $points]>65536} {error "Use a Curve Source or typed geometry resource for more than 65536 points"}
            set command [dict get {curve add pointset pointset point point} $kind]
            set metadata {};set unit [datasetPublicationV2DictDefault $request working_unit [datasetPublicationV2DictDefault $scene working_unit {}]]
            if {$unit ne {}} {unitRegistryConversionPlan $unit $unit;dict set metadata working_unit $unit}
            if {[dict exists $request coordinate_units]} {set metadata [dict merge $metadata [_native2DCoordinateFrame [dict get $request coordinate_units] [datasetPublicationV2DictDefault $request coordinate_relations {}]]]}
            return [_native2DGeometryAdopt $token [::GX::Native2D::core $command $native $points] $metadata]
        }
        from_source {
            set source [dict get $request source_token];set descriptor [curveSourceDescribe $source]
            return [curveSourceWithNumericInput $source [list ::GX::_native2DGeometrySourceInput $token $descriptor]]
        }
        restore_resource {
            set resource [dict get $request resource];set metadata {}
            if {[dict exists $resource metadata geometry_metadata]} {set metadata [dict get $resource metadata geometry_metadata]}
            if {[dict exists $metadata gap_resource]} {
                set id [interactiveDocumentNative2DRestoreWithGaps $resource [dict get $metadata gap_resource] $native]
            } else {
                set kind auto;if {[dict exists $request kind]} {set kind [dict get $request kind]}
                set id [interactiveDocumentNative2DRestore $resource $native $kind]
            }
            return [_native2DGeometryAdopt $token $id $metadata]
        }
        affine {
            set sourceTokens [dict get $request object_tokens];set ids {}
            foreach id $sourceTokens {lappend ids [_native2DGeometryObject $scene $id]}
            set copy 0;if {[dict exists $request copy]} {set copy [uiFieldNormalize {type boolean} [dict get $request copy]]}
            set result [::GX::Native2D::core affine $native $ids [dict get $request matrix] $copy]
            if {!$copy} {return [dict create object_tokens $sourceTokens copy 0]}
            return [_native2DGeometryAdoptCopies $token $result affine_copy [dict create matrix [dict get $request matrix]]]
        }
        series {
            set ids {};foreach id [dict get $request object_tokens] {lappend ids [_native2DGeometryObject $scene $id]}
            set parameters [dict get $request parameters]
            foreach key [dict keys $parameters] {if {$key ni {circular include_origin rotate_geometry rows columns positions spacing_x spacing_y angle_step pivot}} {error "Unknown Native2D series parameter: $key"}}
            set result [::GX::Native2D::core series $native $ids $parameters]
            return [_native2DGeometryAdoptCopies $token $result series_copy $parameters]
        }
        group {
            set ids {};foreach id [dict get $request object_tokens] {lappend ids [_native2DGeometryObject $scene $id]}
            return [_native2DGeometryAdopt $token [::GX::Native2D::core group $native $ids]]
        }
        compare {
            set reference [dict get $request reference];set target [dict get $request derived]
            set options {};if {[dict exists $request output_units]} {dict set options output_units [dict get $request output_units]}
            return [native2DComparison $native [_native2DGeometryObject $scene $reference] [_native2DGeometryObject $scene $target] [dict get $request method] [dict get $request budget] [_native2DGeometryComparableUnits $scene $reference] [_native2DGeometryComparableUnits $scene $target] [dict create producer core.native2d reference $reference target $target] $options]
        }
        bridge {
            set result [::GX::Native2D::core bridge $native [_native2DGeometryObject $scene [dict get $request start]] [_native2DGeometryObject $scene [dict get $request end]] [dict get $request kind] [dict get $request subdivisions] [dict get $request tolerance] [dict get $request start_reverse] [dict get $request end_reverse] [dict get $request start_interpolation] [dict get $request end_interpolation]]
            set id [dict get $result native];dict unset result native
            dict set result bridge_kind [dict get $result kind];dict unset result kind
            return [dict merge [_native2DGeometryAdopt $token $id [dict create bridge_descriptor $result]] $result]
        }
        polar_bulk {
            set result [native2DGeometryPolarBulk [::GX::Native2D::core polar $native] [dict get $request xy_base64]]
            dict set result polar_frame [dict get $result frame];dict unset result frame
            return $result
        }
        pivot - grid - polar - view {
            set args {}
            if {[dict exists $request arguments]} {set args [dict get $request arguments]}
            set result [::GX::Native2D::core $operation $native {*}$args]
            if {$operation eq "view"&&[llength $args]} {return [::GX::Native2D::core view $native]}
            return $result
        }
        default {
            set objectToken [dict get $request object_token];set object [_native2DGeometryObject $scene $objectToken]
            switch -- $operation {
                describe {
                    set kind [::GX::Native2D::core kind $native $object]
                    set result [dict create object_token $objectToken kind $kind metadata [dict get $scene objects $objectToken metadata]]
                    set definition [::GX::Native2D::core sketch_definition $native $object]
                    if {$definition ne {}} {dict set result definition $definition;dict set result geometry_authority retained_sketch}
                    set infinite [expr {$definition ne {}&&[dict get $definition family] eq "construction_line"}]
                    dict set result finite_bounds [expr {!$infinite}]
                    dict set result bounds [expr {$infinite ? {} : [::GX::Native2D::core bounds $native $object]}]
                    dict set result style [::GX::Native2D::core object_style $native $object]
                    if {$kind ne "group"} {dict set result geometry_role [::GX::Native2D::core identity_geometry_role $native $object];dict set result point_count [::GX::Native2D::core count $native $object]}
                    if {$kind eq "curve"&&!$infinite} {dict set result metrics [::GX::Native2D::core metrics $native $object]}
                    return $result
                }
                sketch_update {
                    ::GX::Native2D::core sketch_update $native $object [dict get $request definition] [datasetPublicationV2DictDefault $request display_samples 257]
                    return [native2DGeometryCall $token describe [dict create object_token $objectToken]]
                }
                sketch_evaluate {return [::GX::Native2D::core sketch_evaluate $native $object [dict get $request parameter]]}
                sketch_sample {
                    set points [::GX::Native2D::core sketch_sample $native $object [datasetPublicationV2DictDefault $request first 0] [datasetPublicationV2DictDefault $request last 1] [dict get $request total] [dict get $request start] [dict get $request count]]
                    return [dict create start [dict get $request start] total [dict get $request total] points $points]
                }
                sketch_materialize {
                    set first [dict get $request first];set last [dict get $request last];set total [dict get $request total]
                    set metadata [dict create geometry_operation explicit_sketch_materialization source_geometry_token $objectToken sampling [dict create method uniform_parameter first $first last $last total $total]]
                    set metadata [dict merge $metadata [_native2DPathProvenance $scene [list $objectToken]]]
                    return [_native2DGeometryAdopt $token [::GX::Native2D::core sketch_materialize $native $object $first $last $total] $metadata]
                }
                sketch_explode {
                    set metadata [dict create {*}[_native2DPathProvenance $scene [list $objectToken]] geometry_operation explicit_sketch_explosion source_geometry_token $objectToken]
                    return [_native2DGeometryAdopt $token [::GX::Native2D::core sketch_explode $native $object [dict get $request samples]] $metadata]
                }
                replace_points {
                    set points [dict get $request points]
                    if {[llength $points]>65536} {error "Direct Native point replacement is limited to 65536; use owned geometry resources for larger geometry"}
                    if {[dict exists $scene objects $objectToken metadata source_rows_resource]&&[llength $points]!=[::GX::Native2D::core count $native $object]} {error "Source row identities require a preserved point count; explicitly materialize a new derived range"}
                    ::GX::Native2D::core replace $native $object $points
                    dict set scenes $token objects $objectToken metadata geometry_operation point_replace
                    return [native2DGeometryCall $token describe [dict create object_token $objectToken]]
                }
                path_point {return [::GX::Native2D::core path_point $native $object [dict get $request distance]]}
                points_page {return [dict create start [dict get $request start] points [::GX::Native2D::core points_page $native $object [dict get $request start] [dict get $request count]]]}
                group_members {
                    set tokens {}
                    foreach id [::GX::Native2D::core group_members $native $object] {
                        dict for {member entry} [dict get $scene objects] {if {[dict get $entry native]==$id} {lappend tokens $member;break}}
                    }
                    return [dict create object_tokens $tokens]
                }
                group_add - group_remove {::GX::Native2D::core $operation $native $object [_native2DGeometryObject $scene [dict get $request member]];return 1}
                delete - ungroup {
                    ::GX::Native2D::core $operation $native $object
                    if {[dict exists $scenes $token raster_resource_readers $objectToken]} {
                        catch {interactiveDocumentResourceCloseReader [dict get $scenes $token raster_resource_readers $objectToken]}
                        dict unset scenes $token raster_resource_readers $objectToken
                    }
                    catch {dict unset scenes $token raster_dataset_stamps $objectToken}
                    dict unset scenes $token objects $objectToken
                    return 1
                }
                endpoint_frame {return [::GX::Native2D::core endpoint_frame $native $object [dict get $request end] [dict get $request reverse] [dict get $request interpolation]]}
                spline {return [_native2DGeometryAdopt $token [::GX::Native2D::core spline_object $native $object [dict get $request subdivisions]]]}
                selection {::GX::Native2D::core selection_replace $native $object [dict get $request indices];return [::GX::Native2D::core selection_summary $native $object]}
                style - direction {
                    set command [expr {$operation eq "style" ? "object_style" : "direction_marker"}]
                    set args {};if {[dict exists $request properties]} {set args [list [dict get $request properties]]}
                    if {$operation eq "style"&&[dict exists $request properties layer]&&[dict get $request properties layer]!=0} {error "Use a public layer token API; native layer numbers are not Script geometry references"}
                    return [::GX::Native2D::core $command $native $object {*}$args]
                }
                export_resource {
                    return [interactiveDocumentNative2DStore [dict get $scene document_id] $native $object [dict create geometry_metadata [dict get $scene objects $objectToken metadata]]]
                }
                default {error "Unsupported Native2D geometry operation: $operation"}
            }
        }
    }
}

# Native names/attributes and parent-linked fragments retain scoped ownership.
proc ::GX::_native2DGeometryFragmentReceipt {token fragment} {
    variable ::GX::Native2DGeometry::scenes
    set scene [_native2DGeometryRequire $token]
    if {![dict exists $scene fragments $fragment]} {error "Fragment token is not owned by this Native2D scene"}
    set entry [dict get $scene fragments $fragment]
    set receipt [::GX::Native2D::core fragment_get [dict get $scene native] [dict get $entry native]]
    dict unset receipt id;dict unset receipt parent
    dict set receipt fragment_token $fragment;dict set receipt parent_token [dict get $entry parent_token]
    dict set receipt attributes [::GX::Native2D::core identity_attributes [dict get $scene native] [dict get $entry native]]
    return $receipt
}
rename ::GX::native2DGeometryCall ::GX::native2DGeometryCall_identity_base
proc ::GX::native2DGeometryCall {token operation request} {
    variable ::GX::Native2DGeometry::scenes;variable ::GX::Native2DGeometry::serial
    if {$operation ni {identity fragment_create fragment_get fragment_list fragment_update fragment_delete fragment_sample fragment_length fragment_bounds fragment_materialize}} {return [native2DGeometryCall_identity_base $token $operation $request]}
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native]
    if {[catch {dict size $request}]} {error "Native2D request must be a public struct"}
    if {$operation eq "identity"} {
        foreach key [dict keys $request] {if {$key ni {object_token fragment_token layer_token selection_set_token name key value remove}} {error "Unknown Native2D identity field: $key"}}
        set owner [_native2DGeometryIdentityOwner $scene $request]
        if {[dict exists $request name]} {::GX::Native2D::core identity_name $native $owner [dict get $request name]}
        if {[dict exists $request key]} {
            if {[::GX::datasetPublicationV2DictDefault $request remove 0]} {::GX::Native2D::core identity_attribute_remove $native $owner [dict get $request key]} elseif {[dict exists $request value]} {::GX::Native2D::core identity_attribute $native $owner [dict get $request key] [dict get $request value]} else {return [dict create value [::GX::Native2D::core identity_attribute $native $owner [dict get $request key]]]}
        }
        return [dict create name [::GX::Native2D::core identity_name $native $owner] attributes [::GX::Native2D::core identity_attributes $native $owner]]
    }
    if {$operation eq "fragment_list"} {
        set result {};if {[dict exists $scene fragments]} {foreach fragment [dict keys [dict get $scene fragments]] {lappend result [_native2DGeometryFragmentReceipt $token $fragment]}}
        return [dict create fragments $result]
    }
    if {$operation in {fragment_create fragment_update}} {
        set definition [dict get $request definition]
        foreach key [dict keys $definition] {if {$key ni {parent_token parameter first last}} {error "Unknown fragment definition field: $key"}}
        set parent [dict get $definition parent_token]
        dict set definition parent [_native2DGeometryObject $scene $parent];dict unset definition parent_token
        if {$operation eq "fragment_create"} {
            set receipt [::GX::Native2D::core fragment_create $native $definition]
            set fragment "native2d-fragment#[pid]-[incr serial]-[clock clicks]"
            dict set scenes $token fragments $fragment [dict create native [dict get $receipt id] parent_token $parent]
        } else {
            set fragment [dict get $request fragment_token];_native2DGeometryFragmentReceipt $token $fragment
            ::GX::Native2D::core fragment_update $native [dict get $scene fragments $fragment native] $definition
            dict set scenes $token fragments $fragment parent_token $parent
        }
        return [_native2DGeometryFragmentReceipt $token $fragment]
    }
    set fragment [dict get $request fragment_token];_native2DGeometryFragmentReceipt $token $fragment
    set id [dict get $scene fragments $fragment native]
    switch -- $operation {
        fragment_get {return [_native2DGeometryFragmentReceipt $token $fragment]}
        fragment_delete {::GX::Native2D::core fragment_delete $native $id;dict unset scenes $token fragments $fragment;return 1}
        fragment_sample {
            set total [dict get $request total];set start [::GX::datasetPublicationV2DictDefault $request start 0];set count [::GX::datasetPublicationV2DictDefault $request count [expr {min(65536,$total-$start)}]]
            return [dict create points [::GX::Native2D::core fragment_sample $native $id $total $start $count] start $start count $count total $total]
        }
        fragment_materialize {
            set frame [_native2DGeometryCoordinateFrame $scene [dict get $scene fragments $fragment parent_token]]
            set created [::GX::Native2D::core fragment_materialize $native $id [dict get $request total]]
            set metadata [dict create {*}$frame source_kind native_fragment fragment_descriptor [_native2DGeometryFragmentReceipt $token $fragment] materialization_sampling [dict create method uniform_fragment total [dict get $request total]]]
            return [_native2DGeometryAdopt $token $created $metadata]
        }
        fragment_length {return [dict create length [::GX::Native2D::core fragment_length $native $id]]}
        fragment_bounds {return [dict create bounds [::GX::Native2D::core fragment_bounds $native $id] policy {exact_discrete_or_circle_interval; conservative_parent_for_other_retained_families}]}
    }
}
rename ::GX::native2DGeometryCall ::GX::native2DGeometryCall_identity_transaction_base
proc ::GX::native2DGeometryCall {token operation request} {
    if {$operation ne "identity"||(![dict exists $request name]&&![dict exists $request value]&&![dict exists $request remove])} {return [native2DGeometryCall_identity_transaction_base $token $operation $request]}
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native];set owner [_native2DGeometryIdentityOwner $scene $request]
    set before [::GX::Native2D::core identity_attributes $native $owner]
    try {return [native2DGeometryCall_identity_transaction_base $token $operation $request]} on error {message options} {
        set current [::GX::Native2D::core identity_attributes $native $owner]
        foreach key [dict keys $current] {if {![dict exists $before $key]} {::GX::Native2D::core identity_attribute_remove $native $owner $key}}
        dict for {key value} $before {if {![dict exists $current $key]||[dict get $current $key] ne $value} {::GX::Native2D::core identity_attribute $native $owner $key $value}}
        return -options $options $message
    }
}

proc ::GX::_native2DGeometryCollectionRequire {scene kind token} {
    if {![dict exists $scene $kind $token]} {error "Collection token is not owned by this Native2D scene"}
    return [dict get $scene $kind $token native]
}
proc ::GX::_native2DGeometrySelectionMembers {scene members} {
    set native {}
    foreach member $members {
        set kind [dict get $member kind];set ref [dict create kind $kind]
        if {$kind eq "fragment"} {dict set ref id [_native2DGeometryCollectionRequire $scene fragments [dict get $member fragment_token]]} elseif {$kind in {object point control segment}} {dict set ref id [_native2DGeometryObject $scene [dict get $member object_token]]} else {error "Selection set member kind must be object, point, control, segment or fragment"}
        if {$kind in {point control segment}} {dict set ref index [dict get $member index]}
        lappend native $ref
    }
    return $native
}
proc ::GX::_native2DGeometryCollectionReceipt {token kind id} {
    set scene [_native2DGeometryRequire $token];set native [_native2DGeometryCollectionRequire $scene $kind $id]
    if {$kind eq "layers"} {set receipt [::GX::Native2D::core layer_info [dict get $scene native] $native];dict unset receipt id;dict set receipt layer_token $id} else {
        set raw [::GX::Native2D::core selection_set_get [dict get $scene native] $native];set members {}
        foreach state [dict get $raw members] logical [dict get $scene $kind $id members] {lappend members [dict merge $logical [dict remove $state id index kind]]}
        set receipt [dict create selection_set_token $id members $members count [llength $members]]
    }
    dict set receipt name [::GX::Native2D::core identity_name [dict get $scene native] $native]
    dict set receipt attributes [::GX::Native2D::core identity_attributes [dict get $scene native] $native]
    return $receipt
}
proc ::GX::_native2DGeometryIdentityOwner {scene request} {
    set owner 0;set targets 0
    foreach field {object_token fragment_token layer_token selection_set_token} {
        if {![dict exists $request $field]} continue
        if {[incr targets]>1} {error "Choose one identity owner"}
        set token [dict get $request $field]
        if {$field eq "object_token"} {set owner [_native2DGeometryObject $scene $token]} else {set kind [dict get {fragment_token fragments layer_token layers selection_set_token selection_sets} $field];set owner [_native2DGeometryCollectionRequire $scene $kind $token]}
    }
    return $owner
}
rename ::GX::native2DGeometryCall ::GX::native2DGeometryCall_collections_base
proc ::GX::native2DGeometryCall {token operation request} {
    variable ::GX::Native2DGeometry::scenes;variable ::GX::Native2DGeometry::serial
    if {$operation ni {layer_create layer_get layer_list layer_update layer_delete layer_assign selection_set_create selection_set_get selection_set_list selection_set_update selection_set_add_member selection_set_remove_member selection_set_delete selection_set_activate}} {return [native2DGeometryCall_collections_base $token $operation $request]}
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native]
    set isLayer [string match layer_* $operation];set kind [expr {$isLayer ? "layers" : "selection_sets"}];set field [expr {$isLayer ? "layer_token" : "selection_set_token"}]
    if {$operation in {layer_list selection_set_list}} {
        set result {};if {[dict exists $scene $kind]} {foreach id [dict keys [dict get $scene $kind]] {lappend result [_native2DGeometryCollectionReceipt $token $kind $id]}}
        return [dict create $kind $result]
    }
    if {$operation in {layer_create selection_set_create}} {
        if {$isLayer} {set properties [dict get $request properties];foreach key [dict keys $properties] {if {$key ni {visible selectable locked order opacity}} {error "Unknown layer property: $key"}};set receipt [::GX::Native2D::core layer_create $native $properties]} else {set members [dict get $request members];set receipt [::GX::Native2D::core selection_set_create $native [_native2DGeometrySelectionMembers $scene $members]]}
        set id "native2d-$kind#[pid]-[incr serial]-[clock clicks]";set entry [dict create native [dict get $receipt id]]
        if {!$isLayer} {dict set entry members $members}
        dict set scenes $token $kind $id $entry
        return [_native2DGeometryCollectionReceipt $token $kind $id]
    }
    set id [dict get $request $field];set owner [_native2DGeometryCollectionRequire $scene $kind $id]
    switch -- $operation {
        layer_get - selection_set_get {return [_native2DGeometryCollectionReceipt $token $kind $id]}
        layer_update {set properties [dict get $request properties];foreach key [dict keys $properties] {if {$key ni {visible selectable locked order opacity}} {error "Unknown layer property: $key"}};::GX::Native2D::core layer_update $native $owner $properties}
        selection_set_update {set members [dict get $request members];::GX::Native2D::core selection_set_update $native $owner [_native2DGeometrySelectionMembers $scene $members];dict set scenes $token $kind $id members $members}
        selection_set_add_member {
            set member [dict get $request member]
            ::GX::Native2D::core selection_set_add_member $native $owner [_native2DGeometrySelectionMembers $scene [list $member]]
            dict set scenes $token $kind $id members [concat [dict get $scene $kind $id members] [list $member]]
        }
        selection_set_remove_member {
            set index [dict get $request member_index]
            ::GX::Native2D::core selection_set_remove_member $native $owner $index
            dict set scenes $token $kind $id members [lreplace [dict get $scene $kind $id members] $index $index]
        }
        layer_delete - selection_set_delete {::GX::Native2D::core $operation $native $owner;dict unset scenes $token $kind $id;return 1}
        selection_set_activate {::GX::Native2D::core selection_set_activate $native $owner [::GX::datasetPublicationV2DictDefault $request mode replace];return [_native2DGeometryCollectionReceipt $token $kind $id]}
        layer_assign {
            set old {};foreach object [dict get $request object_tokens] {set objectId [_native2DGeometryObject $scene $object];dict set old $objectId [::GX::Native2D::core object_style $native $objectId]}
            try {dict for {objectId style} $old {::GX::Native2D::core object_style $native $objectId [dict create layer $owner]}} on error {message options} {dict for {objectId style} $old {::GX::Native2D::core object_style $native $objectId $style};return -options $options $message}
        }
    }
    return [_native2DGeometryCollectionReceipt $token $kind $id]
}
proc ::GX::_native2DGeometryAxisPresentationRequest {scene descriptor} {
    dict for {axis settings} $descriptor {
        if {![dict exists $settings context]} continue
        set context [dict get $settings context]
        if {[dict exists $context image_id]} {error {Public axis context requires an owned object_token or stable image_resource_id, not a native object number}}
        if {[dict exists $context object_token]} {
            set native [_native2DGeometryObject $scene [dict get $context object_token]]
            set image [::GX::Native2D::core image_get [dict get $scene native] $native]
            if {$image eq {}} {error {Axis object_token must identify an owned reference image}}
            dict unset context object_token;dict set context image_resource_id [dict get $image resource_id]
            dict set descriptor $axis context $context
        }
    }
    return $descriptor
}
rename ::GX::native2DGeometryCall ::GX::native2DGeometryCall_view_state_base
proc ::GX::native2DGeometryCall {token operation request} {
    if {$operation ni {view_state view_state_rescale axis_presentation}} {return [native2DGeometryCall_view_state_base $token $operation $request]}
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native]
    if {$operation eq "axis_presentation"} {
        set args {};if {[dict exists $request axis_presentation]} {set args [list [_native2DGeometryAxisPresentationRequest $scene [dict get $request axis_presentation]]]}
        return [dict create axis_presentation [::GX::Native2D::core axis_presentation $native {*}$args] geometry_modified 0]
    }
    if {[dict exists $request view_state axis_presentation]} {
        dict set request view_state axis_presentation [_native2DGeometryAxisPresentationRequest $scene [dict get $request view_state axis_presentation]]
    }
    if {$operation eq "view_state_rescale"} {return [dict create view_state [::GX::Native2D::core view_state_rescale $native [dict get $request view_state] [dict get $request factor]] geometry_modified 0]}
    set args {};if {[dict exists $request view_state]} {set args [list [dict get $request view_state]]}
    return [dict create view_state [::GX::Native2D::core view_state $native {*}$args] geometry_modified 0]
}

proc ::GX::_native2DGeometrySavedViewCapture {scene} {
    set native [dict get $scene native];set objects {};set layers {};set live [::GX::Native2D::core ids $native]
    dict for {token record} [dict get $scene objects] {
        if {[dict get $record native] ni $live} continue
        lappend objects [dict create object_token $token visible [dict get [::GX::Native2D::core object_style $native [dict get $record native]] visible] working_unit [_native2DGeometryWorkingUnit $scene $token]]
    }
    if {[dict exists $scene layers]} {dict for {token record} [dict get $scene layers] {lappend layers [dict create layer_token $token visible [dict get [::GX::Native2D::core layer_info $native [dict get $record native]] visible]]}}
    return [dict create view_state [::GX::Native2D::core view_state $native] objects $objects layers $layers]
}
proc ::GX::_native2DGeometrySavedViewRequire {scene token} {
    if {![dict exists $scene saved_views $token]} {error "Saved view token is not owned by this Native2D scene"}
    return [dict get $scene saved_views $token]
}
rename ::GX::native2DGeometryCall ::GX::native2DGeometryCall_saved_views_base
proc ::GX::native2DGeometryCall {token operation request} {
    variable ::GX::Native2DGeometry::scenes;variable ::GX::Native2DGeometry::serial
    if {$operation ni {saved_view_create saved_view_get saved_view_list saved_view_update saved_view_restore saved_view_delete}} {return [native2DGeometryCall_saved_views_base $token $operation $request]}
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native]
    if {$operation eq "saved_view_list"} {return [dict create saved_views [dict values [::GX::datasetPublicationV2DictDefault $scene saved_views {}]]]}
    if {$operation eq "saved_view_create"} {
        if {[dict size [::GX::datasetPublicationV2DictDefault $scene saved_views {}]]>=256} {error "Saved view limit is 256"}
        set name [string trim [dict get $request name]];if {$name eq {}} {error "Enter a saved view name"}
        set id "native2d-view#[pid]-[incr serial]-[clock clicks]"
        set receipt [dict create saved_view_token $id name $name snapshot [_native2DGeometrySavedViewCapture $scene]]
        dict set scenes $token saved_views $id $receipt;return $receipt
    }
    set id [dict get $request saved_view_token];set receipt [_native2DGeometrySavedViewRequire $scene $id]
    switch -- $operation {
        saved_view_get {return $receipt}
        saved_view_delete {dict unset scenes $token saved_views $id;return 1}
        saved_view_update {
            if {[dict exists $request name]} {set name [string trim [dict get $request name]];if {$name eq {}} {error "Enter a saved view name"};dict set receipt name $name}
            if {[::GX::datasetPublicationV2DictDefault $request capture_current 0]} {dict set receipt snapshot [_native2DGeometrySavedViewCapture $scene]}
            dict set scenes $token saved_views $id $receipt;return $receipt
        }
        saved_view_restore {
            set snapshot [dict get $receipt snapshot];set missing {};set objectStyles {};set layerStyles {};set objects {};set layers {}
            foreach item [dict get $snapshot objects] {
                set object [dict get $item object_token]
                if {![dict exists $scene objects $object]} {lappend missing $object;continue}
                set owner [_native2DGeometryObject $scene $object]
                if {[_native2DGeometryWorkingUnit $scene $object] ne [dict get $item working_unit]} {error "Saved view coordinate units changed; explicitly update it from the current frame"}
                dict set objectStyles $owner [::GX::Native2D::core object_style $native $owner];dict set objects $owner [dict get $item visible]
            }
            foreach item [dict get $snapshot layers] {
                set layer [dict get $item layer_token]
                if {![dict exists $scene layers $layer]} {lappend missing $layer;continue}
                set owner [_native2DGeometryCollectionRequire $scene layers $layer]
                dict set layerStyles $owner [dict remove [::GX::Native2D::core layer_info $native $owner] id];dict set layers $owner [dict get $item visible]
            }
            set before [::GX::Native2D::core view_state $native]
            try {
                ::GX::Native2D::core view_state $native [dict get $snapshot view_state]
                dict for {owner visible} $objects {::GX::Native2D::core object_style $native $owner [dict create visible $visible]}
                dict for {owner visible} $layers {::GX::Native2D::core layer_update $native $owner [dict create visible $visible]}
            } on error {message options} {
                ::GX::Native2D::core view_state $native $before
                dict for {owner style} $objectStyles {::GX::Native2D::core object_style $native $owner $style}
                dict for {owner style} $layerStyles {::GX::Native2D::core layer_update $native $owner $style}
                return -options $options $message
            }
            dict set receipt geometry_modified 0;dict set receipt missing_refs $missing;return $receipt
        }
    }
}

source [file join [file dirname [info script]] native2d_series_v1.tcl]
proc ::GX::_native2DSeriesRequire {scene id} {
    if {![dict exists $scene series_containers $id]} {error "Series token is not owned by this Native2D scene"}
    return [dict get $scene series_containers $id]
}
proc ::GX::_native2DSeriesReceipt {token id} {
    set scene [_native2DGeometryRequire $token];set record [_native2DSeriesRequire $scene $id];set missing {}
    foreach object [dict get $record object_tokens] {
        if {![dict exists $scene objects $object]||[dict get $scene objects $object native] ni [::GX::Native2D::core ids [dict get $scene native]]} {lappend missing $object}
    }
    dict set record missing_refs $missing;dict set record valid [expr {$missing eq {}}]
    return $record
}
rename ::GX::native2DGeometryCall ::GX::native2DGeometryCall_series_container_base
proc ::GX::native2DGeometryCall {token operation request} {
    variable ::GX::Native2DGeometry::scenes;variable ::GX::Native2DGeometry::serial
    set operations {series_create series_get series_list series_members series_update series_transform series_bounds series_delete series_explode}
    if {$operation ni $operations} {return [native2DGeometryCall_series_container_base $token $operation $request]}
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native]
    if {$operation eq "series_list"} {
        set result {};foreach id [dict keys [datasetPublicationV2DictDefault $scene series_containers {}]] {lappend result [_native2DSeriesReceipt $token $id]}
        return [dict create series_containers $result]
    }
    if {$operation eq "series_create"} {
        if {[dict size [datasetPublicationV2DictDefault $scene series_containers {}]]>=256} {error "Series container limit is 256"}
        set sources [dict get $request object_tokens];set parameters [dict get $request parameters];set frame {1 0 0 1 0 0};set name [datasetPublicationV2DictDefault $request name series]
        set id "native2d-series#[pid]-[incr serial]-[clock clicks]";set old {}
    } else {
        set id [dict get $request series_token];set record [_native2DSeriesRequire $scene $id]
        switch -- $operation {
            series_get {return [_native2DSeriesReceipt $token $id]}
            series_members {
                set u [dict get $request u];set v [dict get $request v];set p [dict get $record parameters]
                if {![string is integer -strict $u]||![string is integer -strict $v]||$u<0||$v<0||$u>=[dict get $p columns]||$v>=[dict get $p rows]} {error "Series logical index is outside its shape"}
                return [dict create object_tokens [dict get $record cells "$u,$v"]]
            }
            series_explode {dict unset scenes $token series_containers $id;return [dict create object_tokens [dict get $record object_tokens] geometry_modified 0]}
            series_delete {
                if {[::GX::Native2D::core drag_active $native]} {error "Finish the Native2D gesture before deleting a series"}
                foreach object [dict get $record object_tokens] {
                    if {[dict exists $scenes $token objects $object]} {
                        set owner [dict get $scenes $token objects $object native]
                        if {$owner in [::GX::Native2D::core ids $native]} {::GX::Native2D::core delete $native $owner}
                        dict unset scenes $token objects $object
                    }
                }
                dict unset scenes $token series_containers $id;return 1
            }
            series_transform {
                set ids {};foreach object [dict get $record object_tokens] {lappend ids [_native2DGeometryObject $scene $object]}
                set frame [native2DSeriesCompose [dict get $request matrix] [dict get $record frame]]
                if {$ids ne {}} {::GX::Native2D::core affine $native $ids [dict get $request matrix] 0} else {error "An empty series has no transformable geometry"}
                dict set scenes $token series_containers $id frame $frame
                return [_native2DSeriesReceipt $token $id]
            }
            series_bounds {
                set bounds {}
                foreach object [dict get $record object_tokens] {
                    set owner [_native2DGeometryObject $scene $object]
                    set b [::GX::Native2D::core bounds $native $owner]
                    if {$bounds eq {}} {set bounds $b} else {lassign $bounds x0 y0 x1 y1;lassign $b a0 b0 a1 b1;set bounds [list [expr {min($x0,$a0)}] [expr {min($y0,$b0)}] [expr {max($x1,$a1)}] [expr {max($y1,$b1)}]]}
                }
                return [dict create bounds $bounds finite_bounds [expr {$bounds ne {}}]]
            }
        }
        set sources [dict get $record source_tokens];set frame [dict get $record frame];set name [datasetPublicationV2DictDefault $request name [dict get $record name]]
        set parameters [dict merge [dict get $record parameters] [datasetPublicationV2DictDefault $request parameters {}]];set old [dict get $record object_tokens]
    }
    if {[string trim $name] eq {}} {error "Enter a series name"}
    set sourceIds {};foreach source $sources {lappend sourceIds [_native2DGeometryObject $scene $source]}
    set raw [native2DSeriesBuild $native $sourceIds $parameters $frame]
    set adopted [_native2DGeometryAdoptCopies $token $raw rectangular_series [dict get $raw parameters]]
    set cells {};set cursor 0
    dict for {index ids} [dict get $raw cells] {set count [llength $ids];dict set cells $index [lrange [dict get $adopted object_tokens] $cursor [expr {$cursor+$count-1}]];incr cursor $count}
    foreach object $old {
        if {[dict exists $scenes $token objects $object]} {set owner [dict get $scenes $token objects $object native];if {$owner in [::GX::Native2D::core ids $native]} {::GX::Native2D::core delete $native $owner};dict unset scenes $token objects $object}
    }
    dict set scenes $token series_containers $id [dict create series_token $id name $name source_tokens $sources parameters [dict get $raw parameters] frame $frame object_tokens [dict get $adopted object_tokens] cells $cells originals_preserved 1 origin_policy [dict get $raw origin_policy]]
    return [_native2DSeriesReceipt $token $id]
}

rename ::GX::native2DGeometryCall ::GX::native2DGeometryCall_roles_base
proc ::GX::native2DGeometryCall {token operation request} {
    if {$operation ne "geometry_role"} {return [native2DGeometryCall_roles_base $token $operation $request]}
    set scene [_native2DGeometryRequire $token];set native [_native2DGeometryObject $scene [dict get $request object_token]]
    set args {};if {[dict exists $request role]} {set args [list [dict get $request role]]}
    set role [::GX::Native2D::core identity_geometry_role [dict get $scene native] $native {*}$args]
    return [dict create object_token [dict get $request object_token] role $role normal_output [expr {$role eq "regular"}]]
}
rename ::GX::native2DGeometryCall ::GX::native2DGeometryCall_geometric_comparison_base
proc ::GX::native2DGeometryCall {token operation request} {
    if {$operation ne "compare_geometry"} {return [native2DGeometryCall_geometric_comparison_base $token $operation $request]}
    set scene [_native2DGeometryRequire $token];set reference [dict get $request reference];set derived [dict get $request derived]
    set a [_native2DGeometryObject $scene $reference];set b [_native2DGeometryObject $scene $derived]
    set options {};if {[dict exists $request output_units]} {dict set options output_units [dict get $request output_units]}
    return [native2DComparison [dict get $scene native] $a $b geometry [datasetPublicationV2DictDefault $request budget 257] [_native2DGeometryComparableUnits $scene $reference] [_native2DGeometryComparableUnits $scene $derived] [dict create producer core.native2d reference $reference target $derived] $options]
}
# Public explicit representation services. Use Canonical Dataset Publication,
# existing structured metadata and Native2D sampling; no new storage authority.
# Materialization policy is independent of the scene's presentation budget.
# The same policy is replayed when checking exact reconstruction provenance.
proc ::GX::_native2DOrderedCompositionSamples {scene object sampling {historicalReplay 0}} {
    set definition [::GX::Native2D::core sketch_definition $scene $object]
    if {[dict get $definition family] ne "composite_path"} {error {One ordered Path is required; publish Compound constituents separately}}
    set curved [datasetPublicationV2DictDefault $sampling curved_samples 257]
    if {![string is integer -strict $curved]||$curved<2||$curved>65536} {error {Curved constituent samples must be between 2 and 65536}}
    set forward [datasetPublicationV2DictDefault $sampling forward 1]
    ::GX::Native2D::core direction_marker $scene $object [dict create forward $forward]
    if {!$historicalReplay&&[::GX::Native2D::core composition_traversal $scene $object] ne "continuous"} {error {This composition has no continuous chosen traversal. Publish constituents separately; all boundary samples are preserved.}}
    set states [::GX::Native2D::core composition_states $scene $object]
    set indices {};for {set i 0} {$i<[llength [dict get $definition parts]]} {incr i} {lappend indices $i}
    if {!$forward} {set indices [lreverse $indices]}
    set points {}
    foreach i $indices {
        set part [::GX::Native2D::core composition_part $scene $object $i]
        set leaf [dict get $part definition];set family [dict get $leaf family]
        set native [::GX::Native2D::core sketch_create $scene $leaf 2]
        try {
            if {$family eq "path"} {
                # Every closed leaf contributes its closing endpoint here; the
                # root policy removes it once, after orientation and assembly.
                set values [::GX::Native2D::core path_vertices $scene $native 1]
            } else {
                switch -- $family {
                    line {set count 2}
                    polyline {set count [llength [dict get $leaf controls]]}
                    rectangle {set count 5}
                    default {set count $curved}
                }
                set values [::GX::Native2D::core sketch_sample $scene $native 0 1 $count 0 $count]
            }
            if {($historicalReplay&&([dict get $part reversed] != !$forward))||(!$historicalReplay&&[dict get [lindex $states $i] direction forward] != $forward)} {set values [lreverse $values]}
            if {[llength $points]&&($historicalReplay||[lindex $points end] eq [lindex $values 0])} {set values [lrange $values 1 end]}
            lappend points {*}$values
            if {[llength $points]>65536} {error {Ordered publication exceeds 65536 points; reduce curved sampling}}
        } finally {::GX::Native2D::core delete $scene $native}
    }
    if {[dict get $definition closed]&&![datasetPublicationV2DictDefault $sampling repeat_endpoint 0]&&($historicalReplay||[lindex $points 0] eq [lindex $points end])} {set points [lrange $points 0 end-1]}
    return $points
}
proc ::GX::native2DPrimitivePublish {session requested definition unit sampling logicalId {name {Retained primitive}} {moduleId core.native2d}} {
    # Trusted dispatch supplies the actual producer. Preserve the historical
    # CORE default for headless callers without a module activation context.
    if {$::GX::DatasetPrivate::activeContext ne {}} {set moduleId [dict get $::GX::DatasetPrivate::activeContext module_id]}
    set paired [dict exists $sampling coordinate_units]
    if {$paired} {
        set frame [_native2DCoordinateFrame [dict get $sampling coordinate_units] [datasetPublicationV2DictDefault $sampling coordinate_relations {}]]
        set unit [dict get $frame working_unit]
    } else {
        if {[dict exists $sampling coordinate_relations]} {error {Coordinate relations require an explicit X/Y unit pair}}
        unitRegistryConversionPlan $unit $unit
        if {![::GX::unitTclCompatible $unit m]} {error {Retained geometric conversion requires declared compatible length units}}
        set frame [_native2DCoordinateFrame [lrepeat 2 $unit]]
    }
    set variables {};set sourceSchema {}
    foreach axis {x y} axisUnit [dict get $frame coordinate_units] {
        set variable [dict create variable_id $axis name [string toupper $axis] unit $axisUnit]
        set relation [datasetPublicationV2DictDefault [dict get $frame coordinate_relations] $axis {}]
        set variable [dict merge $variable $relation]
        dict set variables $axis $variable
        dict set sourceSchema $axis [_native2DCoordinateVariableSchema $variable]
    }
    native2DEnsure;set scene [::GX::Native2D::core scene]
    try {
        set object [::GX::Native2D::core sketch_create $scene $definition 257]
        set forward [datasetPublicationV2DictDefault $sampling forward 1]
        ::GX::Native2D::core direction_marker $scene $object [dict create forward $forward]
        set definition [::GX::Native2D::core sketch_definition $scene $object]
        set extras {};set indexId {};set sourceDatasets [datasetPublicationV2DictDefault $sampling source_dataset_ids {}]
        if {[dict get $definition family] eq "compound"} {error {A Compound has no global traversal. Review separate constituent Dataset outputs before publication.}}
        if {[dict get $definition family] in {path composite_path}} {
            set repeat [datasetPublicationV2DictDefault $sampling repeat_endpoint 0]
            if {[dict get $definition family] eq "composite_path"} {
                set points [_native2DOrderedCompositionSamples $scene $object $sampling]
            } else {set points [::GX::Native2D::core path_vertices $scene $object $repeat]}
            if {[llength $points]>65536} {error {Publication supports at most 65536 ordered vertices; omit repeated closure for this maximum-size path}}
            set indexId [datasetPublicationV2DictDefault $sampling index_variable_id index]
            if {$indexId ne {}} {
                if {![regexp {^[A-Za-z][A-Za-z0-9_]*$} $indexId]||$indexId in {x y}} {error {Choose a valid distinct ordering Variable ID}}
                set values {};for {set i 0} {$i<[llength $points]} {incr i} {lappend values $i}
                lappend extras [dict create descriptor [dict create variable_id $indexId name $indexId unit {} dtype int64 coordinate_role data axis_kind explicit] values $values]
            }
            set policy [dict create method authoritative_path_vertices total [llength $points] forward $forward repeat_endpoint $repeat index_variable_id $indexId index_start 0 index_step 1 index_meaning global_curve_point_order reversal_anchor [expr {[dict get $definition closed]?"vertex_zero":"direction_endpoint"}]]
            set approximation {Exact authoritative straight-path vertices; shared junctions occur once; closed endpoint repetition is explicit}
            if {[dict get $definition family] eq "composite_path"} {
                dict set policy method ordered_constituents
                dict set policy traversal_contract 2
                dict set policy constituents [::GX::Native2D::core composition_states $scene $object]
                dict set policy curved_samples [datasetPublicationV2DictDefault $sampling curved_samples 257]
                dict set policy reversal_anchor constituent_boundary
                set approximation {Exact straight vertices and explicit uniform-parameter curved samples per constituent; shared junctions occur once; retained definition remains exact}
            }
        } else {
            set total [dict get $sampling total];set first [dict get $sampling first];set last [dict get $sampling last]
            if {!$forward} {set tmp $first;set first $last;set last $tmp}
            set points [::GX::Native2D::core sketch_sample $scene $object $first $last $total 0 $total]
            set policy [dict create method uniform_parameter first $first last $last total $total forward $forward]
            set approximation {Finite uniform-parameter values; retained definition remains exact and unchanged}
        }
        set provenance [dict create api_id NATIVE2D_PRIMITIVE_PUBLICATION_v1 api_version 1 operation retained_primitive_to_dataset framework_version $::GX::version definition $definition working_unit $unit sampling $policy source_logical_identity $logicalId x_variable_id x y_variable_id y producer core.native2d source_dataset_ids $sourceDatasets conversion_provenance [datasetPublicationV2DictDefault $sampling conversion_provenance {}]]
        if {$paired} {
            dict set provenance coordinate_units [dict get $frame coordinate_units]
            dict set provenance coordinate_relations [dict get $frame coordinate_relations]
            dict set provenance original_source_variable_schema $sourceSchema
        }
        dict set provenance publishing_module $moduleId
        set metadata [dict create native2d.primitive_publication $provenance native2d.geometry_authority retained_sketch native2d.approximation_policy $approximation]
        return [datasetPublicationV2PublishSeries $session $moduleId [dict create dataset_id $requested display_name $name producer_version 1.0.0 contract table.generic storage auto x_values [lmap p $points {lindex $p 0}] y_values [lmap p $points {lindex $p 1}] x_variable [dict get $variables x] y_variable [dict get $variables y] extra_variables $extras source_dataset_ids $sourceDatasets structured_metadata $metadata provenance $provenance]]
    } finally {::GX::Native2D::core destroy $scene}
}

proc ::GX::native2DPrimitiveReconstruct {session datasetId xId yId} {
    set metadata [datasetMetadataRead $session $datasetId]
    if {![dict exists $metadata native2d.primitive_publication]} {error "No compatible GX-TXT retained primitive provenance; use Fit to primitive for arbitrary data"}
    set provenance [dict get $metadata native2d.primitive_publication]
    if {[datasetField $datasetId producer_module {}] ne [datasetPublicationV2DictDefault $provenance publishing_module core.native2d]||[datasetField $datasetId provenance {}] ne $provenance} {error "Structured primitive provenance differs from its original Canonical Publication receipt"}
    if {[dict get $provenance api_id] ne "NATIVE2D_PRIMITIVE_PUBLICATION_v1"||[dict get $provenance api_version]!=1||[dict get $provenance producer] ne "core.native2d"||[dict get $provenance operation] ne "retained_primitive_to_dataset"} {error "Unsupported primitive provenance contract"}
    if {$xId ne [dict get $provenance x_variable_id]||$yId ne [dict get $provenance y_variable_id]} {error "Select the original Cartesian publication X/Y variables"}
    set unit [dict get $provenance working_unit]
    if {[dict exists $provenance coordinate_units]} {
        set frame [_native2DCoordinateFrame [dict get $provenance coordinate_units] [dict get $provenance coordinate_relations]]
        if {$unit ne [dict get $frame working_unit]} {error {Published coordinate frame contradicts its common-unit receipt}}
        foreach axis {x y} variable [list $xId $yId] axisUnit [dict get $frame coordinate_units] {
            set actual [_native2DCoordinateVariableSchema [datasetVariableById $datasetId $variable]]
            set captured [dict get $provenance original_source_variable_schema $axis]
            if {[dict get $captured unit] ne $axisUnit} {error {Captured publication schema contradicts its coordinate frame}}
            foreach field {unit canonical_unit to_canonical from_canonical} {
                if {[dict get $actual $field] ne [dict get $captured $field]} {error "Published coordinate schema changed ($axis/$field); exact reconstruction rejected"}
            }
            set expected [_native2DCoordinateVariableSchema [dict merge [dict create unit $axisUnit] [datasetPublicationV2DictDefault [dict get $frame coordinate_relations] $axis {}]]]
            if {$captured ne $expected} {error {Captured publication relation contradicts its coordinate frame}}
        }
    } else {
        foreach variable [list $xId $yId] {
            set actual [datasetVariableById $datasetId $variable]
            if {[dict get $actual unit] ne $unit} {error "Published coordinate units changed; exact reconstruction rejected"}
            if {[_native2DCoordinateVariableSchema $actual] ne [_native2DCoordinateVariableSchema [dict create unit $unit]]} {error {Published coordinate relation changed; exact legacy reconstruction rejected}}
        }
        unitRegistryConversionPlan $unit $unit
        if {![::GX::unitTclCompatible $unit m]} {error "Retained geometric conversion requires declared compatible length units"}
        set frame [_native2DCoordinateFrame [lrepeat 2 $unit]]
    }
    set sampling [dict get $provenance sampling]
    if {[dict get $sampling method] ni {uniform_parameter authoritative_path_vertices ordered_constituents}||[dict get $sampling total]>65536} {error "Unsupported primitive materialization policy"}
    native2DEnsure;set scene [::GX::Native2D::core scene];set stream {}
    try {
        set native [::GX::Native2D::core sketch_create $scene [dict get $provenance definition] 257]
        if {[dict get $sampling method] eq "ordered_constituents"} {
            set expected [_native2DOrderedCompositionSamples $scene $native $sampling [expr {![dict exists $sampling traversal_contract]}]]
        } elseif {[dict get $sampling method] eq "authoritative_path_vertices"} {
            ::GX::Native2D::core direction_marker $scene $native [dict create forward [dict get $sampling forward]]
            set expected [::GX::Native2D::core path_vertices $scene $native [dict get $sampling repeat_endpoint]]
        } else {set expected [::GX::Native2D::core sketch_sample $scene $native [dict get $sampling first] [dict get $sampling last] [dict get $sampling total] 0 [dict get $sampling total]]}
        set indexId [datasetPublicationV2DictDefault $sampling index_variable_id {}]
        set variables [list $xId $yId]
        if {$indexId ne {}} {
            set descriptor [datasetVariableV3ById $datasetId $indexId]
            if {[dict get $descriptor dtype] ne "int64"||[dict get $descriptor unit] ne {}||[dict get $sampling index_start]!=0||[dict get $sampling index_step]!=1} {error {Published global ordering contract changed; exact reconstruction rejected}}
            lappend variables $indexId
        }
        set stream [tableStreamOpenDataset $session $datasetId $variables 4096]
        set rows 0
        while {1} {set chunk [tableStreamNext $stream]
            set localRow 0
            foreach x [dict get $chunk values $xId] y [dict get $chunk values $yId] {
                if {$indexId ne {}} {
                    set index [lindex [dict get $chunk values $indexId] $localRow]
                    if {![string is entier -strict $index]||$index!=$rows} {error {Dataset global ordering values differ from publication provenance}}
                }
                incr localRow
                set row [list $x $y]
                if {$rows>=[llength $expected]} {error "Dataset row count differs from primitive provenance"}
                foreach actual $row value [lindex $expected $rows] {
                    if {![string is double -strict $actual]||abs($actual-$value)>1e-12*max(1,abs($value))} {error "Dataset values differ from retained sampling; use scientific fitting"}
                }
                incr rows
            }
            if {[dict get $chunk eof]} break
        }
        if {$rows!=[llength $expected]} {error "Dataset row count differs from primitive provenance"}
        return [dict create definition [::GX::Native2D::core sketch_definition $scene $native] {*}$frame method exact_provenance_reconstruction source_dataset_id $datasetId provenance $provenance direction [dict create forward [datasetPublicationV2DictDefault $sampling forward 1]] materialization_verified 1 original_dataset_modified 0]
    } finally {if {$stream ne {}} {tableStreamClose $stream};::GX::Native2D::core destroy $scene}
}
proc ::GX::_native2DInteractionNativeReference {scene reference} {
    set native [dict remove $reference object_token]
    dict set native object [_native2DGeometryObject $scene [dict get $reference object_token]]
    return $native
}
proc ::GX::_native2DInteractionPublicReference {scene reference} {
    set id [dict get $reference object];dict unset reference object
    dict for {token entry} [dict get $scene objects] {if {[dict get $entry native]==$id} {dict set reference object_token $token;return $reference}}
    error "Reference is outside the owned Native2D scene"
}
rename ::GX::native2DGeometryCall ::GX::native2DGeometryCall_interaction_base
proc ::GX::native2DGeometryCall {token operation request} {
    if {$operation ni {construct construct_preview from_fit controls reference reference_resolve reference_point_index control_definition control_edit constraint_options constraint_apply constraint_location}} {return [native2DGeometryCall_interaction_base $token $operation $request]}
    variable ::GX::Native2DGeometry::scenes
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native]
    switch -- $operation {
        construct {return [dict create definition [::GX::Native2D::core interaction_construct $native [dict get $request family] [dict get $request points]]]}
        construct_preview {return [dict create definition [::GX::Native2D::core interaction_construct_preview $native [dict get $request family] [dict get $request points]]]}
        from_fit {return [dict create definition [::GX::Native2D::core interaction_from_fit $native [dict get $request family] [dict get $request parameters]]]}
        control_definition {return [dict create definition [::GX::Native2D::core interaction_edit_definition $native [_native2DInteractionNativeReference $scene [dict get $request reference]] [dict get $request point]]]}
        reference_point_index {return [dict create point_index [::GX::Native2D::core interaction_point_index $native [_native2DInteractionNativeReference $scene [dict get $request reference]]]]}
        constraint_location {
            set constraint [dict get $request constraint_token]
            if {![dict exists $scene constraints $constraint]} {error "Constraint token is stale or foreign"}
            return [dict create point [::GX::Native2D::core interaction_constraint_location $native [dict get $scene constraints $constraint]]]
        }
        controls {
            set handles {}
            foreach handle [::GX::Native2D::core interaction_controls $native [_native2DGeometryObject $scene [dict get $request object_token]]] {lappend handles [_native2DInteractionPublicReference $scene $handle]}
            return [dict create handles $handles]
        }
        reference {
            if {[dict exists $request semantic_index]} {return [_native2DInteractionPublicReference $scene [::GX::Native2D::core interaction_reference_index $native [_native2DGeometryObject $scene [dict get $request object_token]] [dict get $request semantic_index]]]}
            return [_native2DInteractionPublicReference $scene [::GX::Native2D::core interaction_reference $native [_native2DGeometryObject $scene [dict get $request object_token]] [dict get $request entity] [datasetPublicationV2DictDefault $request ordinal 0]]]
        }
        reference_resolve {return [dict create point [::GX::Native2D::core interaction_resolve $native [_native2DInteractionNativeReference $scene [dict get $request reference]]]]}
        control_edit {
            set reference [_native2DInteractionNativeReference $scene [dict get $request reference]]
            ::GX::Native2D::core interaction_edit $native $reference [dict get $request point]
            return [dict create geometry_modified 1 object_token [dict get $request reference object_token]]
        }
        constraint_options {
            set refs {};foreach reference [dict get $request references] {lappend refs [_native2DInteractionNativeReference $scene $reference]}
            set result {}
            dict for {kind definition} [::GX::Native2D::core interaction_constraints $native $refs] {
                set definition [dict remove $definition id valid geometry_supported measured_value residual angular_residual enforcement general_solver anchor]
                foreach field {a b axis} {
                    set id [dict get $definition $field];dict unset definition $field
                    if {$id==0} continue
                    dict for {object entry} [dict get $scene objects] {if {[dict get $entry native]==$id} {dict set definition ${field}_token $object;break}}
                }
                lappend result [dict create kind $kind definition $definition]
            }
            return [dict create compatible_constraints $result general_solver 1]
        }
        constraint_apply {
            set existing [datasetPublicationV2DictDefault $request constraint_token {}];set id 0
            if {$existing ne {}} {if {![dict exists $scene constraints $existing]} {error "Constraint token is stale or foreign"};set id [dict get $scene constraints $existing]}
            set definition [dict get $request definition];set spec [_native2DGeometryConstraintSpec $scene $definition]
            set unit [_native2DGeometryWorkingUnit $scene [dict get $definition a_token]]
            foreach field {b_token axis_token} {if {[dict exists $definition $field]&&[_native2DGeometryWorkingUnit $scene [dict get $definition $field]] ne $unit} {error "Constraint geometry requires common working units"}}
            set receipt [::GX::Native2D::core interaction_constraint_apply $native $id $spec]
            if {$existing eq {}} {return [_native2DGeometryConstraintAdopt $token $receipt]}
            return [_native2DGeometryConstraintReceipt $scene $existing $receipt]
        }
    }
}
# dev-054 additive sketch APIs use the same owned object/constraint token maps.
rename ::GX::native2DGeometryCall ::GX::native2DGeometryCall_sketch054_base
proc ::GX::native2DGeometryCall {token operation request} {
    if {$operation ni {sketch_status sketch_component dimension_infer dimension_preview dimension_apply dimension_geometry relationship_state relationship_hit}} {return [native2DGeometryCall_sketch054_base $token $operation $request]}
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native]
    switch -- $operation {
        sketch_status {return [dict merge [::GX::Native2D::core sketch_status $native [_native2DGeometryObject $scene [dict get $request object_token]]] {rank_scope local_component}]}
        sketch_component {
            set ids [::GX::Native2D::core sketch_component $native [_native2DGeometryObject $scene [dict get $request object_token]]];set tokens {}
            dict for {object entry} [dict get $scene objects] {if {[dict get $entry native] in $ids} {lappend tokens $object}}
            return [dict create object_tokens $tokens]
        }
        dimension_infer {
            set refs {};foreach r [dict get $request references] {lappend refs [_native2DInteractionNativeReference $scene $r]}
            set d [::GX::Native2D::core sketch_dimension_infer $native $refs [dict get $request annotation]]
            set public [_native2DGeometryConstraintReceipt $scene {} $d]
            return [dict create definition [dict remove $public constraint_token valid geometry_supported measured_value residual angular_residual enforcement general_solver anchor]]
        }
        dimension_preview {
            return [::GX::Native2D::core sketch_dimension_preview $native [_native2DGeometryConstraintSpec $scene [dict get $request definition]] [dict get $request annotation]]
        }
        dimension_apply {
            set existing [datasetPublicationV2DictDefault $request constraint_token {}];set id 0
            if {$existing ne {}} {if {![dict exists $scene constraints $existing]} {error {Constraint token is stale or foreign}};set id [dict get $scene constraints $existing]}
            set definition [dict get $request definition];set spec [_native2DGeometryConstraintSpec $scene $definition]
            set unit [_native2DGeometryWorkingUnit $scene [dict get $definition a_token]]
            foreach field {b_token axis_token} {if {[dict exists $definition $field]&&[_native2DGeometryWorkingUnit $scene [dict get $definition $field]] ne $unit} {error {Dimension geometry requires common working units}}}
            set receipt [::GX::Native2D::core sketch_dimension_apply $native $id $spec [datasetPublicationV2DictDefault $request driven 0] [dict get $request annotation]]
            if {$existing eq {}} {return [_native2DGeometryConstraintAdopt $token $receipt]}
            return [_native2DGeometryConstraintReceipt $scene $existing $receipt]
        }
        default {
            set constraint [dict get $request constraint_token]
            if {![dict exists $scene constraints $constraint]} {error {Constraint token is stale or foreign}}
            set id [dict get $scene constraints $constraint]
            switch -- $operation {
                dimension_geometry {return [::GX::Native2D::core sketch_dimension_geometry $native $id]}
                relationship_state {
                    set args {};if {[dict exists $request presentation]} {
                        set presentation [dict get $request presentation]
                        foreach key [dict keys $presentation] {if {$key ni {annotation placed driven}} {error "Unknown relationship presentation field: $key"}}
                        lappend args $presentation
                    }
                    return [_native2DGeometryConstraintReceipt $scene $constraint [::GX::Native2D::core sketch_relationship $native $id {*}$args]]
                }
                relationship_hit {return [dict create hit [::GX::Native2D::core sketch_relationship_hit $native $id [dict get $request device] [dict get $request label_bounds]]]}
            }
        }
    }
}

# Additive construction semantics use the same execution-owned geometry/rules.
proc ::GX::_native2DConstructionReference {scene reference frame} {
    if {[_native2DGeometryCoordinateFrame $scene [dict get $reference object_token]] ne $frame} {error {Attached construction requires the same complete coordinate frame}}
    return [_native2DInteractionNativeReference $scene $reference]
}
proc ::GX::_native2DConstructionPlacements {scene placements frame} {
    set result {}
    foreach placement $placements {
        foreach key [dict keys $placement] {if {$key ni {point reference earlier}} {error "Unknown construction placement field '$key'"}}
        if {[dict exists $placement reference]} {
            dict set placement reference [_native2DConstructionReference $scene [dict get $placement reference] $frame]
        }
        lappend result $placement
    }
    return $result
}
rename ::GX::native2DGeometryCall ::GX::native2DGeometryCall_construction055_base
proc ::GX::native2DGeometryCall {token operation request} {
    if {$operation ni {construct_attached placement_points placement_preview reference_connected}} {return [native2DGeometryCall_construction055_base $token $operation $request]}
    variable ::GX::Native2DGeometry::scenes
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native]
    if {$operation eq "reference_connected"} {
        return [dict create connected [::GX::Native2D::core construction_connected $native [_native2DInteractionNativeReference $scene [dict get $request a]] [_native2DInteractionNativeReference $scene [dict get $request b]]]]
    }
    set unit [datasetPublicationV2DictDefault $request working_unit {}]
    if {$unit ne {}} {unitRegistryConversionPlan $unit $unit}
    set frame [_native2DCoordinateFrame [datasetPublicationV2DictDefault $request coordinate_units [lrepeat 2 $unit]] [datasetPublicationV2DictDefault $request coordinate_relations {}]]
    set placements [_native2DConstructionPlacements $scene [dict get $request placements] $frame]
    switch -- $operation {
        placement_points {return [dict create points [::GX::Native2D::core construction_points $native $placements]]}
        placement_preview {return [dict create definition [::GX::Native2D::core construction_preview $native [dict get $request family] $placements]]}
        construct_attached {
            set closure {};foreach ref [datasetPublicationV2DictDefault $request closure_references {}] {lappend closure [_native2DConstructionReference $scene $ref $frame]}
            set receipt [::GX::Native2D::core construction_create $native [dict get $request family] $placements [datasetPublicationV2DictDefault $request display_samples 257] $closure]
            set before $scene
            try {
                set object [_native2DGeometryAdopt $token [dict get $receipt id] [dict create {*}$frame geometry_operation attached_construction]]
                set rules {};foreach relationship [dict get $receipt relationships] {lappend rules [_native2DGeometryConstraintAdopt $token $relationship]}
                set owned [_native2DGeometryRequire $token]
                return [dict merge $object [dict create definition [dict get $receipt definition] tail_reference [_native2DInteractionPublicReference $owned [dict get $receipt tail_reference]] constraints $rules closed [dict get $receipt closed] periodic 0]]
            } on error {message options} {
                dict set scenes $token $before
                if {[dict get $receipt id] in [::GX::Native2D::core ids $native]} {::GX::Native2D::core delete $native [dict get $receipt id]}
                return -options $options $message
            }
        }
    }
}

# Reuse the existing C view authority; these calls do not capture host gestures.
rename ::GX::native2DGeometryCall ::GX::native2DGeometryCall_view056_base
proc ::GX::native2DGeometryCall {token operation request} {
    if {$operation ni {fit_all fit_selected fit_bounds zoom pan scene_bounds world_to_device device_to_world pixel_tolerance}} {return [native2DGeometryCall_view056_base $token $operation $request]}
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native]
    switch -- $operation {
        fit_all {::GX::Native2D::core fit $native}
        fit_selected {::GX::Native2D::core fit_selected $native}
        fit_bounds {::GX::Native2D::core fit_bounds $native [dict get $request bounds]}
        zoom {::GX::Native2D::core zoom $native [dict get $request factor] [dict get $request point]}
        pan {::GX::Native2D::core pan $native {*}[dict get $request delta]}
        scene_bounds {return [dict create bounds [::GX::Native2D::core scene_bounds $native [datasetPublicationV2DictDefault $request selected_only 0]]]}
        world_to_device {return [dict create point [::GX::Native2D::core device $native [dict get $request point]]]}
        device_to_world {return [dict create point [::GX::Native2D::core world $native [dict get $request point]]]}
        pixel_tolerance {return [dict create point [::GX::Native2D::core tolerance $native [dict get $request pixels]]]}
    }
    return [dict create view_state [::GX::Native2D::core view_state $native]]
}

rename ::GX::native2DGeometryCall ::GX::native2DGeometryCall_tangent056_base
proc ::GX::native2DGeometryCall {token operation request} {
    if {$operation ni {spline_tangent_get spline_tangent_edit}} {return [native2DGeometryCall_tangent056_base $token $operation $request]}
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native]
    set args [list $native [_native2DGeometryObject $scene [dict get $request object_token]] [dict get $request knot] [dict get $request incoming]]
    if {$operation eq "spline_tangent_edit"} {lappend args [dict get $request point] [datasetPublicationV2DictDefault $request reset 0]}
    return [::GX::Native2D::core spline_tangent {*}$args]
}

rename ::GX::native2DGeometryCall ::GX::native2DGeometryCall_scene056_base
proc ::GX::native2DGeometryCall {token operation request} {
    if {$operation ni {image_attach image_get image_update image_calibrate image_map symmetry_preview symmetry_construct canvas_preview}} {return [native2DGeometryCall_scene056_base $token $operation $request]}
    variable ::GX::Native2DGeometry::scenes
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native]
    if {$operation eq "canvas_preview"} {return [native2DCanvasPreview $native [dict get $scene document_id] [dict get $request mode] [datasetPublicationV2DictDefault $request options {}]]}
    if {$operation eq "image_attach"} {
        set resource [dict get $request resource];interactiveDocumentResourceInfo $resource
        set path [file join [_documentResourceRoot [dict get $resource document_id] 1] [dict get $resource sha256].blob]
        lassign [_native2DRasterHelper info $path] width height
        set unit [dict get $request working_unit]
        if {$unit eq {px}} {unitRegistryConversionPlan px px} else {unitRegistryConversionPlan $unit m}
        set state [dict merge [dict create width $width height $height length_unit $unit resource_id [dict get $resource sha256] scale 1 translation {0 0} rotation 0 opacity 1 visible 1 locked 0] [datasetPublicationV2DictDefault $request state {}]]
        # Raster identity/dimensions come from the managed resource, never caller
        # claims. Script requests cannot smuggle a host filename into Native.
        dict set state resource_id [dict get $resource sha256];dict set state width $width;dict set state height $height;dict set state length_unit $unit
        set id [::GX::Native2D::core image_create $native $state]
        try {native2DReferenceImageBind $native $id $resource;return [dict merge [_native2DGeometryAdopt $token $id [dict create working_unit $unit image_resource $resource]] [dict create image_state [::GX::Native2D::core image_get $native $id] resource $resource]]} on error {message options} {if {$id in [::GX::Native2D::core ids $native]} {::GX::Native2D::core delete $native $id};return -options $options $message}
    }
    if {$operation in {symmetry_preview symmetry_construct}} {
        set axis [_native2DInteractionNativeReference $scene [dict get $request axis]]
        if {$operation eq "symmetry_preview"} {return [::GX::Native2D::core symmetry_preview $native $axis [dict get $request definition]]}
        if {[dict exists $request coordinate_units]} {
            set frame [_native2DCoordinateFrame [dict get $request coordinate_units] [datasetPublicationV2DictDefault $request coordinate_relations {}]]
        } else {set unit [dict get $request working_unit];unitRegistryConversionPlan $unit m;set frame [_native2DCoordinateFrame [lrepeat 2 $unit]]}
        if {[_native2DGeometryCoordinateFrame $scene [dict get [dict get $request axis] object_token]] ne $frame} {error {Symmetric construction requires the axis complete coordinate frame}}
        set created [::GX::Native2D::core symmetry_construct $native $axis [dict get $request definition] [datasetPublicationV2DictDefault $request display_samples 257]]
        set before $scene
        try {
            set source [_native2DGeometryAdopt $token [dict get $created source] $frame]
            set mirror [_native2DGeometryAdopt $token [dict get $created mirror] $frame]
            set receipt [::GX::Native2D::core constraint_get $native [dict get $created relationship]]
            set relationship [_native2DGeometryConstraintAdopt $token $receipt]
            return [dict create objects [list $source $mirror] constraints [list $relationship]]
        } on error {message options} {
            dict set scenes $token $before
            foreach key {source mirror} {set id [dict get $created $key];if {$id in [::GX::Native2D::core ids $native]} {::GX::Native2D::core delete $native $id}}
            return -options $options $message
        }
    }
    set object [_native2DGeometryObject $scene [dict get $request object_token]]
    _native2DRasterDatasetCheck $scene [dict get $request object_token]
    set state [::GX::Native2D::core image_get $native $object]
    if {$state eq {}} {error {Object is not a reference image}}
    switch $operation {
        image_get {return [dict create image_state $state resource [dict get $scene objects [dict get $request object_token] metadata image_resource]]}
        image_update {
            set changes [dict get $request changes]
            foreach key [dict keys $changes] {if {$key ni {scale rotation translation opacity visible locked}} {error "Unsupported image state change '$key'"}}
            return [dict create image_state [::GX::Native2D::core image_update $native $object [dict merge $state $changes]]]
        }
        image_calibrate {
            set distance [dict get $request distance]
            set unit [datasetPublicationV2DictDefault $request distance_unit [dict get $state length_unit]]
            set distance [lindex [unitRegistryConvertCoordinates $unit [dict get $state length_unit] [list $distance]] 0]
            return [dict create image_state [::GX::Native2D::core image_calibrate $native $object [dict get $request point_a] [dict get $request point_b] $distance]]
        }
        image_map {return [dict create point [::GX::Native2D::core image_map $native $object [dict get $request point] [datasetPublicationV2DictDefault $request inverse 0]]]}
    }
}

# Semantic multi-object operations share Native selection sets and return only
# scoped logical tokens; no host widgets or alternate geometric predicates.
proc ::GX::_native2DSelectionPublicMember {scene member} {
    set native [dict get $member id];set result [dict remove $member id]
    dict for {token entry} [dict get $scene objects] {
        if {[dict get $entry native]==$native} {dict set result object_token $token;return $result}
    }
    error {Selection reference is outside this owned Native2D scene}
}
rename ::GX::native2DGeometryCall ::GX::native2DGeometryCall_selection057_base
proc ::GX::native2DGeometryCall {token operation request} {
    if {$operation ni {selection_pick selection_region selection_set_apply selection_set_restore selection_set_bounds}} {return [native2DGeometryCall_selection057_base $token $operation $request]}
    variable ::GX::Native2DGeometry::scenes;variable ::GX::Native2DGeometry::serial
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native]
    if {$operation eq "selection_set_bounds"} {
        set owner [_native2DGeometryCollectionRequire $scene selection_sets [dict get $request selection_set_token]]
        return [dict create bounds [::GX::Native2D::core selection_set_bounds $native $owner]]
    }
    if {$operation in {selection_pick selection_region}} {
        set ids {};foreach object [dict get $request object_tokens] {lappend ids [_native2DGeometryObject $scene $object]}
        if {$operation eq "selection_pick"} {
            set member [::GX::Native2D::core selection_pick $native $ids [dict get $request device] [datasetPublicationV2DictDefault $request tolerance 9] [datasetPublicationV2DictDefault $request target detail]]
            if {$member eq {}} {return [dict create hit 0]}
            return [dict create hit 1 member [_native2DSelectionPublicMember $scene $member]]
        }
        set members [::GX::Native2D::core selection_region $native $ids [dict get $request polygon] [datasetPublicationV2DictDefault $request maximum 65536] [datasetPublicationV2DictDefault $request target detail]]
        return [dict create members [lmap member $members {_native2DSelectionPublicMember $scene $member}] count [llength $members]]
    }
    set id [datasetPublicationV2DictDefault $request selection_set_token {}]
    set owner [expr {$id eq {}?0:[_native2DGeometryCollectionRequire $scene selection_sets $id]}]
    set owner [::GX::Native2D::core $operation $native $owner [_native2DGeometrySelectionMembers $scene [dict get $request members]] [datasetPublicationV2DictDefault $request mode replace]]
    if {!$owner} {if {$id ne {}} {dict unset scenes $token selection_sets $id};return [dict create selection_set_token {} members {} count 0]}
    if {$id eq {}} {set id "native2d-selection_sets#[pid]-[incr serial]-[clock clicks]"}
    set members {};foreach member [dict get [::GX::Native2D::core selection_set_get $native $owner] members] {lappend members [_native2DSelectionPublicMember $scene [dict remove $member topology_epoch valid missing]]}
    dict set scenes $token selection_sets $id [dict create native $owner members $members]
    return [_native2DGeometryCollectionReceipt $token selection_sets $id]
}

proc ::GX::native2DDatasetPromote {session dataset x y {options {}}} {
    set metadata [datasetMetadataRead $session $dataset]
    set request [dict create dataset_id $dataset x_variable_id $x y_variable_id $y display_budget 65536]
    foreach key {order_variable_id filters} {if {[dict exists $options $key]} {dict set request $key [dict get $options $key]}}
    if {[dict exists $metadata native2d.primitive_publication]&&![dict exists $request filters]&&![dict exists $request order_variable_id]} {return [native2DPrimitiveReconstruct $session $dataset $x $y]}
    set source [curveSourceOpen $session $request]
    try {
        set descriptor [curveSourceDescribe $source];set display [curveSourceDisplay $source]
        set units [list [dict get [datasetVariableById $dataset $x] unit] [dict get [datasetVariableById $dataset $y] unit]]
        set frame [_native2DCoordinateFrame $units [native2DSourceCoordinateRelations $descriptor $x $y]]
        set unit [dict get $frame working_unit]
        if {[dict get $display reduced]} {error {Retained spline promotion supports at most 65536 authoritative knots; choose an explicit source subset}}
        if {[dict get $display breaks] ne {}} {error {Promote disconnected Dataset spans separately; interpolation cannot bridge missing geometry implicitly}}
        set points [dict get $display points];native2DEnsure;set scene [::GX::Native2D::core scene]
        try {
            set definition [::GX::Native2D::core interaction_construct $scene spline $points]
            set object [::GX::Native2D::core sketch_create $scene $definition 257]
            set maximum 0;set axisMaximum {x 0 y 0};set i 0;set n [llength $points]
            foreach p $points {
                set q [dict get [::GX::Native2D::core sketch_evaluate $scene $object [expr {$i/double($n-1)}]] point]
                foreach axis {x y} actual $p interpolated $q {dict set axisMaximum $axis [expr {max([dict get $axisMaximum $axis],abs($actual-$interpolated))}]}
                set maximum [expr {max($maximum,hypot([lindex $p 0]-[lindex $q 0],[lindex $p 1]-[lindex $q 1]))}];incr i
            }
            set metricScope numeric_plane_interpolation_at_authoritative_knots
            if {$unit ne {}&&[dict get $frame coordinate_relations] eq {}} {set metricScope interpolation_at_authoritative_knots}
            return [dict create definition $definition {*}$frame method spline_interpolation source_dataset_id $dataset source_descriptor $descriptor source_request $request source_rows [dict get $display source_rows] parameters {kernel native_interpolating_catmull_rom parameterization uniform_source_order} quality [dict create knot_count $n maximum_knot_error $maximum maximum_knot_error_by_axis $axisMaximum coordinate_units $units unit $unit scope $metricScope] original_dataset_modified 0]
        } finally {::GX::Native2D::core destroy $scene}
    } finally {curveSourceClose $source}
}
# Snapshot source provenance when adopting a new path; later disposal of its
# input actors cannot erase Dataset identity or a reviewed conversion method.
proc ::GX::_native2DPathProvenance {scene objects} {
    set frame [_native2DGeometryCommonFrame $scene $objects]
    set sources {};set conversions {}
    foreach object $objects {
        set metadata [dict get $scene objects $object metadata]
        foreach source [datasetPublicationV2DictDefault $metadata source_dataset_ids {}] {lappend sources $source}
        if {[dict exists $metadata conversion_provenance]} {
            set conversion [dict get $metadata conversion_provenance]
            if {[dict exists $conversion source_dataset_id]} {lappend sources [dict get $conversion source_dataset_id]}
            lappend conversions $conversion
        }
        if {[dict exists $metadata source_descriptor request dataset_id]} {lappend sources [dict get $metadata source_descriptor request dataset_id]}
    }
    return [dict create {*}$frame source_dataset_ids [lsort -unique $sources] conversion_provenance [dict create inputs $conversions]]
}
rename ::GX::native2DGeometryCall ::GX::native2DGeometryCall_path057_base
proc ::GX::native2DGeometryCall {token operation request} {
    if {[string match raster_* $operation]} {return [_native2DRasterCall $token $operation $request]}
    if {$operation in {composition_parts composition_traversal part_direction part_direction_batch part_render part_marker_geometry part_marker_hit part_marker_place part_pick image_calibration_reset}} {return [_native2DPartCall $token $operation $request]}
    if {$operation ni {path_vertices path_split path_join primitive_publish dataset_promote}} {return [native2DGeometryCall_path057_base $token $operation $request]}
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native]
    switch -- $operation {
        path_vertices {return [dict create points [::GX::Native2D::core path_vertices $native [_native2DGeometryObject $scene [dict get $request object_token]] [datasetPublicationV2DictDefault $request repeat_endpoint 0]] method authoritative_path_vertices]}
        path_split {
            set source [dict get $request object_token]
            set metadata [_native2DPathProvenance $scene [list $source]]
            set ids [::GX::Native2D::core path_split $native [_native2DGeometryObject $scene $source] [dict get $request vertex]]
            set objects {};foreach id $ids {lappend objects [_native2DGeometryAdopt $token $id [dict create {*}$metadata parent_geometry_token $source geometry_operation retained_path_split]]}
            return [dict create objects $objects source_modified 0]
        }
        path_join {
            set a [dict get $request a];set b [dict get $request b]
            set metadata [_native2DPathProvenance $scene [list $a $b]]
            set id [::GX::Native2D::core path_join $native [_native2DGeometryObject $scene $a] [_native2DGeometryObject $scene $b] [datasetPublicationV2DictDefault $request reverse_a 0] [datasetPublicationV2DictDefault $request reverse_b 0] [datasetPublicationV2DictDefault $request tolerance 0]]
            return [_native2DGeometryAdopt $token $id [dict create {*}$metadata parent_geometry_tokens [list $a $b] geometry_operation retained_path_join]]
        }
        primitive_publish {
            set object [dict get $request object_token];set id [_native2DGeometryObject $scene $object]
            set sampling [dict merge [dict get $request sampling] [_native2DPathProvenance $scene [list $object]]];dict set sampling forward [dict get [::GX::Native2D::core direction_marker $native $id] forward]
            set definition [::GX::Native2D::core sketch_definition $native $id]
            return [native2DPrimitivePublish [sessionInspectionCurrentSession] [dict get $request dataset_id] $definition [_native2DGeometryWorkingUnit $scene $object] $sampling $object [datasetPublicationV2DictDefault $request name {Retained curve}]]
        }
        dataset_promote {
            set receipt [native2DDatasetPromote [sessionInspectionCurrentSession] [dict get $request dataset_id] [dict get $request x_variable_id] [dict get $request y_variable_id] [datasetPublicationV2DictDefault $request options {}]]
            # Explicit adoption is the caller's requested editable conversion.
            set id [::GX::Native2D::core sketch_create $native [dict get $receipt definition] 257]
            if {[dict exists $receipt direction]} {::GX::Native2D::core direction_marker $native $id [dict get $receipt direction]}
            set frame [_native2DCoordinateFrame [dict get $receipt coordinate_units] [dict get $receipt coordinate_relations]]
            return [dict merge [_native2DGeometryAdopt $token $id [dict create {*}$frame conversion_provenance $receipt]] [dict create conversion $receipt original_dataset_modified 0]]
        }
    }
}

# Only explicit coincidence links grow a construction network. Tangency to an
# external Circle must not swallow that Circle into the newly constructed Path.
proc ::GX::native2DConnectedObjects {scene seeds} {
    set result [lsort -unique $seeds];set changed 1
    set rules [::GX::Native2D::core constraint_list $scene]
    while {$changed} {
        set changed 0
        foreach rule $rules {
            if {[dict get $rule kind] ne "coincident"||[dict get $rule disabled]} continue
            set a [dict get $rule a];set b [dict get $rule b]
            if {$a in $result||$b in $result} {foreach id [list $a $b] {if {$id!=0&&$id ni $result} {lappend result $id;set changed 1}}}
        }
    }
    return $result
}

source [file join [file dirname [info script]] native2d_parts_api_v1.tcl]

source [file join [file dirname [info script]] native2d_raster_api_v1.tcl]

# Compatible discovery extension; original geometry operations keep their owner.
rename ::GX::native2DGeometryApiInfo ::GX::_native2DGeometryApiInfoBeforeDiagrams
proc ::GX::native2DGeometryApiInfo {} {
    set info [_native2DGeometryApiInfoBeforeDiagrams]
    dict set info diagram_commands {native2DGeometryDiagramCatalogRegister native2DGeometryDiagramCatalog native2DGeometryDiagramCreate native2DGeometryDiagramRead native2DGeometryDiagramValidate native2DGeometryDiagramEdit native2DGeometryDiagramEndpoint native2DGeometryDiagramProject}
    dict set info diagram_format gxtxt.native2d.diagram.v1
    dict set info diagram_authority INTERACTIVE_DOCUMENT_API_v1
    dict set info diagram_connectivity explicit_stable_ports_and_junctions
    dict set info diagram_edit_modes {commit preview}
    dict set info diagram_edit_preview_semantics {same_source_and_candidate_validation_without_document_or_id_allocation}
    dict set info diagram_route_fields {id route start end}
    dict set info diagram_route_semantics {same_stable_wire_id_typed_bends_or_existing_terminal_reconnection}
    dict set info diagram_wire_target {kind wire wire_id STABLE_WIRE_ID point {world_x world_y}}
    dict set info diagram_wire_target_semantics {validated_native_segment_projection_atomic_split_explicit_canonical_junction_existing_endpoint_reuse}
    foreach operation {raster_annotation_get raster_annotation_set raster_annotation_remove raster_annotation_project} {dict lappend info operations $operation}
    dict set info raster_annotation_authority {existing Native2D image identity attribute gx.image.annotations; ordinary Resource/Document checkpoint persistence}
    dict set info raster_annotation_coordinates {retained source pixels; Native2D image_map and world_to_device only}
    dict set info raster_annotation_limits {maximum_annotations 512 maximum_attribute_bytes 16384 font_size_min 6 font_size_max 96 font_size_unit device_px}
    dict set info diagram_junction_fields {position target targets}
    dict set info diagram_crossing_semantics {geometric_crossings_disconnected_unless_intentional_junction_targets}
    dict set info diagram_electrical_notation {catalog electrical.basic canonical SI m milli meg mega editable_exact_roundtrip 1}
    dict set info diagram_symbol_variants {attribute declared_choice marks choice_to_paths}
    return $info
}
