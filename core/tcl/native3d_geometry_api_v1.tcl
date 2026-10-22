# SPDX-License-Identifier: GPL-3.0-or-later
# Scoped retained geometry on the shared Native3D isolated worker.
namespace eval ::GX::Native3DGeometry {variable scenes {};variable serial 0}
proc ::GX::native3DGeometryApiInfo {} {
    return [dict create api_id NATIVE_3D_GEOMETRY_API_v1 api_version 1 operations {open scene_info convert_axes planar_api_info planar_create planar_list planar_show planar_edit_begin planar_edit_accept planar_edit_cancel call import_dataset profile_from_sources profile_resources profile_view_resource export_resource checkpoint close} geometry_operations {logical_id projection_profile plane_frame indexed_mesh polydata masked_surface sweep load_scientific project profile profile_delete profile_rescale section_profile extrude box cylinder boolean duplicate mesh describe anchor_describe measure delete transform translate rotate scale rescale_coordinates reset_transform align_three_points constraint_solve clean weld orient heal clip clip_cap self_intersections mesh_append mesh_merge mesh_stitch mesh_bridge mesh_heal_seam mesh_lod mesh_boundaries mesh_intersection_pairs group_copy group_duplicate group_delete export export_local load_step restore_step load_mesh} raw_pointers 0 implicit_dataset_publication 0 numerical_point_limit 1000000 numerical_cell_limit 1000000 numerical_request_bytes 67108864 logical_id_max 9007199254740991 projection_policy orthogonal_full_geometry editable_projection source_boundary reference_renderer modern_native3d]
}
proc ::GX::native3DGeometryImportDataset {token datasetId workingUnit {assumedInputUnit {}}} {
    set scope [_native3DGeometryRequire $token]
    unitRegistryConversionPlan $workingUnit mm
    set workingScale [expr {[unitRegistryIntrinsicScale $workingUnit]/[unitRegistryIntrinsicScale mm]}]
    set payload [sessionInspectionDatasetPayload $datasetId]
    set format [string tolower [dict get $payload format]]
    if {$format eq "stp"} {set format step}
    if {$format ni {step stl obj vtp}} {error "Native3D Dataset intake supports exact STEP and complete STL, OBJ or VTP surfaces"}
    set metadata [datasetMetadataRead $::GX::currentSession $datasetId]
    set declaredUnit [datasetPublicationV2DictDefault $metadata geometry.working_unit {}]
    set inputUnit $declaredUnit
    set assumed 0
    if {$format ne "step"} {
        if {$inputUnit eq {}} {set inputUnit $assumedInputUnit;set assumed 1}
        if {$inputUnit eq {}} {error "Dataset '$datasetId' has no mesh coordinate unit; explicitly choose its input unit"}
        unitRegistryConversionPlan $inputUnit $workingUnit
        set factor [expr {[unitRegistryIntrinsicScale $inputUnit]/[unitRegistryIntrinsicScale $workingUnit]}]
    } else {set factor 1;set inputUnit {}}
    set unitPolicy [expr {$format eq "step" ? "step_embedded_units" : "explicit_mesh_coordinate_unit"}]
    set reference [interactiveDocumentResourceImportNumeric [dict get $scope document_id] [dict get $payload path] [dict create format native3d.$format.v1 millimeters_per_working_unit $workingScale source_dataset_id $datasetId source_sha256 [dict get $payload sha256] input_unit $inputUnit assumed_input_unit $assumed]]
    set owned {}
    try {
        if {[sessionInspectionDatasetPayload $datasetId] ne $payload} {error "Dataset changed during Native3D intake; reload it explicitly"}
        set result [native3DGeometryCall $token [expr {$format eq "step" ? "load_step" : "load_mesh"}] [dict create resource $reference]]
        lappend owned [dict get $result object_token]
        if {$factor!=1} {
            set converted [native3DGeometryCall $token rescale_coordinates [dict create object_token [dict get $result object_token] factor $factor]]
            lappend owned [dict get $converted object_token]
            native3DGeometryCall $token delete [dict create object_token [dict get $result object_token]]
            set owned [list [dict get $converted object_token]];set result $converted
        }
        if {[sessionInspectionDatasetPayload $datasetId] ne $payload} {error "Dataset changed during Native3D intake; reload it explicitly"}
        dict set result dataset_binding [dict create source_kind dataset source_dataset_id $datasetId source_sha256 [dict get $payload sha256] source_format $format source_resource $reference input_unit $inputUnit dataset_declared_unit $declaredUnit unit_policy $unitPolicy assumed_input_unit $assumed working_unit $workingUnit coordinate_factor $factor]
        set owned {};return $result
    } on error {message options} {
        foreach object $owned {if {[catch {native3DGeometryCall $token delete [dict create object_token $object]} cleanup]} {append message "; intake cleanup failed: $cleanup"}}
        return -options $options $message
    }
}
proc ::GX::native3DGeometryOpen {document} {
    variable ::GX::Native3DGeometry::scenes;variable ::GX::Native3DGeometry::serial
    set owner [interactiveDocumentRead $document]
    set sessionToken [interactiveDocumentSessionToken]
    ::GX::Engine3D::loadNative
    set token "native3d-scene#[pid]-[incr serial]-[clock clicks]"
    ::GX::Engine3D::rpc [list cad $token open {}]
    try {
        if {$sessionToken ne [interactiveDocumentSessionToken]||[dict get [interactiveDocumentRead $document] generation] ne [dict get $owner generation]} {error "Document or Session lifetime changed while opening Native3D"}
    } on error {message options} {
        if {[catch {::GX::Engine3D::rpc [list cad $token close {}]} cleanup]} {append message "; Native3D cleanup failed: $cleanup"}
        return -options $options $message
    }
    dict set scenes $token [dict create document_id $document generation [dict get $owner generation] revision [dict get $owner revision] session_token $sessionToken worker_generation $::GX::Engine3D::workerGeneration]
    return $token
}
proc ::GX::_native3DGeometryRequire {token} {
    variable ::GX::Native3DGeometry::scenes
    if {![dict exists $scenes $token]} {error "Unknown or closed Native3D scene token"}
    set scene [dict get $scenes $token]
    if {[dict get $scene session_token] ne [interactiveDocumentSessionToken]} {error "Native3D scene belongs to another Session lifetime"}
    set owner [interactiveDocumentRead [dict get $scene document_id]]
    if {[dict get $scene generation] ne [dict get $owner generation]} {error "Native3D document owner was replaced"}
    if {[dict get $scene revision] ne [dict get $owner revision]} {error "Native3D document revision changed; reopen and restore its authoritative geometry"}
    if {$::GX::Engine3D::worker eq ""||[dict get $scene worker_generation]!=$::GX::Engine3D::workerGeneration} {error "Native3D worker lifetime changed; restore its document geometry"}
    return $scene
}
proc ::GX::native3DGeometryCheckpoint {token payload} {
    variable ::GX::Native3DGeometry::scenes
    set scene [_native3DGeometryRequire $token]
    set result [interactiveDocumentUpdate [dict get $scene document_id] $payload]
    dict set scenes $token revision [dict get $result revision]
    return $result
}
proc ::GX::native3DGeometrySceneInfo {token} {
    set scene [_native3DGeometryRequire $token]
    return [dict create api_id NATIVE_3D_GEOMETRY_SCENE_INFO_v1 document_id [dict get $scene document_id] generation [dict get $scene generation] revision [dict get $scene revision] session_token [dict get $scene session_token] worker_generation [dict get $scene worker_generation]]
}
proc ::GX::_native3DGeometryImportSource {document descriptor input} {
    set count [dict get $input row_count]
    set xy [interactiveDocumentResourceImportNumeric $document [dict get $input xy_file] [dict create format native2d.float64_xy_le_v1 point_count $count source_id [dict get $descriptor source_id]]]
    set gap [interactiveDocumentResourceImportNumeric $document [dict get $input break_before_file] [dict create format native2d.uint8_break_before_v1 point_count $count source_id [dict get $descriptor source_id]]]
    set rows [interactiveDocumentResourceImportNumeric $document [dict get $input source_rows_file] [dict create format native2d.uint64_source_rows_le_v1 point_count $count]]
    return [dict create xy_resource $xy gap_resource $gap source_rows_resource $rows source_descriptor $descriptor]
}
proc ::GX::native3DGeometryProfileFromSources {token sources plane tolerance} {
    set scene [_native3DGeometryRequire $token];set document [dict get $scene document_id]
    if {[llength $sources]<1||[llength $sources]>4096} {error "Profile needs 1–4096 explicit curve sources"}
    set contours {};set descriptors {};set bindings {}
    foreach source $sources {
        foreach field {source_token closed} {if {![dict exists $source $field]} {error "Native3D source profile needs $field"}}
        set sourceToken [dict get $source source_token];set descriptor [curveSourceDescribe $sourceToken]
        set variables [dict get $descriptor variables]
        if {[dict get [lindex $variables 0] unit] ne [dict get [lindex $variables 1] unit]} {error "Profile X/Y require the same unit; use an explicit Dataset Transform conversion"}
        set imported [curveSourceWithNumericInput $sourceToken [list ::GX::_native3DGeometryImportSource $document $descriptor]]
        dict set imported closed [uiFieldNormalize {type boolean} [dict get $source closed]]
        lappend contours [dict remove $imported source_rows_resource source_descriptor]
        lappend descriptors $imported;lappend bindings [list $sourceToken $descriptor]
    }
    foreach binding $bindings {lassign $binding source descriptor;if {[curveSourceDescribe $source] ne $descriptor} {error "Source changed while constructing profile; reload it explicitly"}}
    set result [native3DGeometryCall $token profile [dict create contours $contours plane $plane tolerance $tolerance]]
    dict set result source_bindings $descriptors;dict set result captured_plane $plane
    return $result
}
proc ::GX::_native3DGeometryStageResource {reference pathsName} {
    upvar 1 $pathsName paths
    set reader [interactiveDocumentResourceOpenReader $reference]
    set f [file tempfile path];lappend paths $path
    try {
        fconfigure $f -encoding binary -translation binary
        while {1} {set chunk [interactiveDocumentResourceNext $reader];puts -nonewline $f [dict get $chunk bytes];if {[dict get $chunk eof]} break}
    } finally {close $f;interactiveDocumentResourceCloseReader $reader}
    return $path
}
proc ::GX::native3DGeometryExportResource {token object format millimetersPerUnit {placement world}} {
    set scene [_native3DGeometryRequire $token]
    if {$format ni {step stl vtp}} {error "Choose STEP, STL or VTP for a complete geometry resource"}
    if {$placement ni {local world}} {error "Geometry resource placement must be local or world"}
    set info [native3DGeometryCall $token describe [dict create object_token $object]]
    set f [file tempfile path];close $f;file delete -- $path
    try {
        native3DGeometryCall $token [expr {$placement eq "local" ? "export_local" : "export"}] [dict create object_token $object format $format path $path millimeters_per_working_unit $millimetersPerUnit]
        set metadata [dict create format native3d.$format.v1 millimeters_per_working_unit $millimetersPerUnit geometry_sha256 [dict get $info geometry_sha256] bounds_min [dict get $info bounds_min] bounds_max [dict get $info bounds_max]]
        dict set metadata geometry_placement $placement
        dict set metadata geometry_role [dict get $info geometry_role]
        dict set metadata origin [_scientificResourceOrigin [dict get $scene document_id] derived_geometry_resource]
        if {$placement eq "local"} {dict set metadata transform [dict get $info world_transform]}
        set resource [interactiveDocumentResourceImportNumeric [dict get $scene document_id] $path $metadata]
        _native3DGeometryRequire $token
        return $resource
    } finally {file delete -force -- $path}
}
proc ::GX::native3DGeometryProfileResources {token profile} {
    set scene [_native3DGeometryRequire $token]
    set f [file tempfile directory];close $f;file delete -- $directory;file mkdir $directory
    try {
        set staged [::GX::Engine3D::rpc [list cad $token profile_export [dict create profile_token $profile directory $directory]]]
        _native3DGeometryRequire $token
        set contours {}
        foreach contour [dict get $staged contours] {
            set reference [interactiveDocumentResourceImportNumeric [dict get $scene document_id] [dict get $contour xy_file] [dict create format native2d.float64_xy_le_v1 point_count [dict get $contour point_count] source_kind native3d_profile origin [_scientificResourceOrigin [dict get $scene document_id] derived_profile_resource]]]
            lappend contours [dict create xy_resource $reference closed [dict get $contour closed]]
        }
        dict set staged contours $contours
        _native3DGeometryRequire $token
        return $staged
    } finally {file delete -force -- $directory}
}
proc ::GX::native3DGeometryProfileViewResource {token profile} {
    set scene [_native3DGeometryRequire $token]
    set f [file tempfile path];close $f;file delete -- $path
    try {
        ::GX::Engine3D::rpc [list cad $token profile_view_export [dict create profile_token $profile path $path]]
        _native3DGeometryRequire $token
        set result [interactiveDocumentResourceImportNumeric [dict get $scene document_id] $path [dict create format native3d.vtp.v1 source_kind native3d_profile geometry_placement world origin [_scientificResourceOrigin [dict get $scene document_id] derived_profile_resource]]]
        _native3DGeometryRequire $token
        return $result
    } finally {file delete -force -- $path}
}
proc ::GX::native3DGeometryCall {token action request} {
    set scene [_native3DGeometryRequire $token]
    if {$action ni [dict get [native3DGeometryApiInfo] geometry_operations]} {error "Unknown Native3D geometry operation '$action'"}
    if {[catch {dict size $request}]} {error "Native3D request must be a dictionary"}
    if {$action in {indexed_mesh polydata masked_surface sweep}} {
        unitRegistryConversionPlan [dict get $request working_unit] m
        if {[string bytelength $request]>67108864} {error "Numerical geometry request exceeds 64 MiB; use resource intake"}
    }
    set document [dict get $scene document_id];set revision [dict get [interactiveDocumentRead $document] revision]
    set paths {};set result {}
    try {
        if {$action eq "profile"} {
            set contours {};set total 0
            if {![dict exists $request contours]||[llength [dict get $request contours]]<1||[llength [dict get $request contours]]>4096} {error "Profile needs 1–4096 resource contours"}
            foreach contour [dict get $request contours] {
                foreach field {xy_resource closed} {if {![dict exists $contour $field]} {error "Profile contour needs $field"}}
                set xy [dict get $contour xy_resource];interactiveDocumentResourceInfo $xy
                if {[dict get $xy metadata format] ne "native2d.float64_xy_le_v1"||![dict exists $xy metadata point_count]} {error "Profile needs a complete typed XY resource"}
                set count [dict get $xy metadata point_count]
                if {![string is entier -strict $count]||$count<2||[dict get $xy size_bytes]!=16*$count||$total+$count>1000000} {error "Profile resource shape or complete-point budget is invalid"}
                incr total $count
                set item [dict create xy_file [_native3DGeometryStageResource $xy paths] point_count $count closed [uiFieldNormalize {type boolean} [dict get $contour closed]]]
                if {[dict exists $contour gap_resource]} {
                    set gap [dict get $contour gap_resource];interactiveDocumentResourceInfo $gap
                    if {[dict get $gap metadata format] ne "native2d.uint8_break_before_v1"||[dict get $gap size_bytes]!=$count} {error "Profile gap resource shape is invalid"}
                    dict set item gap_file [_native3DGeometryStageResource $gap paths]
                }
                lappend contours $item
            }
            dict set request contours $contours
        }
        if {$action in {load_step restore_step load_mesh load_scientific}} {
            if {![dict exists $request resource]} {error "Geometry restore requires an owned document resource"}
            set reference [dict get $request resource];interactiveDocumentResourceInfo $reference
            set format [dict get $reference metadata format]
            if {$action in {load_step restore_step}} {
                if {$format ne "native3d.step.v1"} {error "B-Rep restore requires an exact STEP resource"}
                dict set request millimeters_per_working_unit [dict get $reference metadata millimeters_per_working_unit]
            } else {
                if {$format ni {native3d.stl.v1 native3d.obj.v1 native3d.vtp.v1}} {error "Mesh restore requires STL, OBJ or VTP resource metadata"}
                dict set request format [lindex [split $format .] 1]
            }
            set path [_native3DGeometryStageResource $reference paths]
            # Scientific readers validate their explicit declared suffix. The
            # staged filename is an owned temporary, never a provider path.
            set typedPath "$path.[lindex [split $format .] 1]"
            file rename -- $path $typedPath;lappend paths $typedPath
            dict set request path $typedPath
            if {[dict exists $reference metadata geometry_placement]&&[dict get $reference metadata geometry_placement] eq "local"} {dict set request matrix [dict get $reference metadata transform]}
            dict unset request resource
        }
        if {$action eq "mesh"} {
            foreach {field ceiling} {max_triangles 10000000 max_output_bytes 536870912} {
                if {![dict exists $request $field]||![string is entier -strict [dict get $request $field]]||[dict get $request $field]<1||[dict get $request $field]>$ceiling} {error "Native3D $field must be a positive integer at most $ceiling"}
            }
        }
        set result [::GX::Engine3D::rpc [list cad $token $action $request]]
        if {$action in {load_step restore_step load_mesh load_scientific}&&[dict exists $reference metadata geometry_role]} {
            set result [::GX::Engine3D::rpc [list cad $token geometry_role [dict create object_token [dict get $result object_token] role [dict get $reference metadata geometry_role]]]]
        }
        _native3DGeometryRequire $token
        if {[dict get [interactiveDocumentRead $document] revision]!=$revision} {
            error "Native3D document changed while the operation was running; repeat it on the current revision"
        }
        return $result
    } on error {message options} {
        if {$::GX::Engine3D::worker ne ""&&[dict get $scene worker_generation]==$::GX::Engine3D::workerGeneration} {
            foreach {field disposal} {group_token group_delete object_token delete profile_token profile_delete} {
                if {$action ni {describe geometry_role}&&[dict exists $result $field]&&[catch {::GX::Engine3D::rpc [list cad $token $disposal [dict create $field [dict get $result $field]]]} cleanup]} {append message "; Native3D result cleanup failed: $cleanup"}
            }
        }
        return -options $options $message
    } finally {foreach path $paths {file delete -- $path}}
}
proc ::GX::native3DGeometryClose {token} {
    variable ::GX::Native3DGeometry::scenes
    if {![dict exists $scenes $token]} {error "Unknown or closed Native3D scene token"}
    set scene [dict get $scenes $token]
    if {$::GX::Engine3D::worker ne ""&&[dict get $scene worker_generation]==$::GX::Engine3D::workerGeneration} {::GX::Engine3D::rpc [list cad $token close {}]}
    dict unset scenes $token
}

# Explicit per-axis physical normalization; no unit guessing and no Dataset mutation.
proc ::GX::native3DGeometryConvertAxes {scene object sourceUnits targetUnit} {
    if {[llength $sourceUnits]!=3} {error {Declare three source coordinate units}}
    unitRegistryConversionPlan $targetUnit m
    set factors {};foreach unit $sourceUnits {lappend factors [lindex [unitRegistryConvertCoordinates $unit $targetUnit {1}] 0]}
    set result [native3DGeometryCall $scene scale [dict create object_token $object factors $factors pivot {0 0 0}]]
    dict set result coordinate_conversion [dict create source_units $sourceUnits target_unit $targetUnit factors $factors]
    return $result
}
