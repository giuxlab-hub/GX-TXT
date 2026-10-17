# GX-TXT Curve Digitalizer Dataset Schema API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# Resolve the *semantic meaning* of published columns from a Dataset ID.
# No reliance on variable names, display labels, column positions or viewer state.

namespace eval ::GX::CurveDigitizerDataset {
    variable apiVersion 1
    variable prefix curve_digitizer.
    variable mandatoryRoles {x y curve_key curve_name point_order}
    variable roleSemantics [dict create \
        x {Scientific X coordinate of a digitized point, in the X variable unit.} \
        y {Scientific Y coordinate of a digitized point, in the Y variable unit.} \
        curve_key {Opaque, stable curve membership identifier; group rows by this key, never by display label.} \
        curve_name {Editable human-readable curve name; never use for grouping or identity.} \
        point_order {Zero-based digitization order within each curve_key, not globally sorted by X.} \
        family_parameter {Numeric parameter associated with a true numerical curve family, repeated per point; absent for independent curves.} \
        raster_x {Original source-image raster pixel-center X; independent of scientific axes.} \
        raster_y {Original source-image raster pixel-center Y; independent of scientific axes.} \
        calibration_key {Stable calibration measurement identifier for each row; group jointly with curve_key in combined publications.} \
        calibration_name {Human label of the calibration realization; not a grouping identifier.}]
}

proc ::GX::CurveDigitizerDataset::_context {datasetId session} {
    set datasetId [string trim $datasetId]
    if {$datasetId eq ""} { error "A published Dataset ID is required." }
    set active [::GX::sessionInspectionCurrentSession]
    if {$session eq ""} { set session $active }
    # The public Variable Schema API is bound to the live Session.
    if {[file normalize $session] ne [file normalize $active]} {
        error "The Dataset Schema API can only inspect the current GX-TXT Session."
    }
    set record [::GX::sessionInspectionDataset $datasetId $session]
    set metadata [::GX::datasetMetadataRead $session $datasetId]
    if {![dict exists $metadata curve_digitizer.plugin_id] ||
        [dict get $metadata curve_digitizer.plugin_id] ne "viewer.curve_digitizer"} {
        error "Dataset '$datasetId' was not published by Curve Digitalizer."
    }
    return [dict create dataset_id $datasetId session $session record $record metadata $metadata]
}

proc ::GX::CurveDigitizerDataset::_variable {datasetId variableId role} {
    if {$variableId eq ""} { error "Empty variable ID for semantic role '$role'." }
    # Public V3 lookup validates existence; labels and physical CSV positions are
    # deliberately not used to discover or validate scientific meaning.
    set variable [::GX::datasetVariableV3ById $datasetId $variableId]
    set dtype [dict get $variable dtype]
    if {$role in {x y family_parameter raster_x raster_y} && $dtype ni {float32 float64 int8 int16 int32 int64 uint8 uint16 uint32 uint64}} {
        error "Semantic role '$role' must refer to a numeric variable."
    }
    if {$role in {curve_key curve_name calibration_key calibration_name} && $dtype ni {string text}} {
        error "Semantic role '$role' must refer to a text variable."
    }
    if {$role eq "point_order" && $dtype ni {int8 int16 int32 int64 uint8 uint16 uint32 uint64}} {
        error "Semantic role 'point_order' must refer to an integer variable."
    }
    if {[dict get $variable rank] ne "1"} { error "Semantic role '$role' must refer to a rank-one table variable." }
    return $variable
}

proc ::GX::CurveDigitizerDataset::read {datasetId {session ""}} {
    variable mandatoryRoles
    variable roleSemantics
    set ctx [_context $datasetId $session]
    set md [dict get $ctx metadata]
    set record [dict get $ctx record]
    set dsId [dict get $ctx dataset_id]
    set contract [expr {[dict exists $record contract] ? [dict get $record contract] : [dict get $record kind]}]
    set legacy 0
    if {[dict exists $md curve_digitizer.curve_schema_version]} {
        set v [dict get $md curve_digitizer.curve_schema_version]
        if {$v ne "1"} { error "Unsupported Curve Digitalizer curve schema version '$v'." }
        foreach field {curve_mode curve_grouping curve_row_dimension} {
            if {![dict exists $md curve_digitizer.$field]} { error "Missing curve schema field '$field'." }
        }
        set mode [dict get $md curve_digitizer.curve_mode]
        if {$mode ni {independent numerical_family}} { error "Invalid curve grouping mode '$mode'." }
        set grouping [dict get $md curve_digitizer.curve_grouping]
        if {$grouping ni {curve_key curve_key_and_calibration_key}} {
            error "Unsupported curve grouping strategy."
        }
        if {$grouping eq "curve_key_and_calibration_key" &&
            (![dict exists $md curve_digitizer.curve_column.calibration_key] ||
             ![dict exists $md curve_digitizer.curve_column.calibration_name])} {
            error "Combined publications require calibration-key and calibration-name semantic mappings."
        }
        set dimension [dict get $md curve_digitizer.curve_row_dimension]
    } else {
        # Existing 1.2.7 outputs already published before this manifest existed.
        # Compatibility is limited to the *known historical technical IDs*, and
        # only on actual Curve Digitalizer datasets. Never infer from labels.
        set legacy 1
        set mode [expr {$contract eq "curve_family.table" ? "numerical_family" : "independent"}]
        set dimension row
    }
    set expected [expr {$mode eq "numerical_family" ? "curve_family.table" : "table.generic"}]
    if {$contract ne $expected} { error "Curve schema mode and Dataset contract disagree." }
    if {$dimension eq ""} { error "Missing curve row dimension." }

    set roles $mandatoryRoles
    if {$mode eq "numerical_family"} { lappend roles family_parameter }
    if {!$legacy} {
        set rasterX [dict exists $md curve_digitizer.curve_column.raster_x]
        set rasterY [dict exists $md curve_digitizer.curve_column.raster_y]
        if {$rasterX != $rasterY} {error "Raster X and Y semantic column mappings must both exist."}
        if {$rasterX} { lappend roles raster_x raster_y }
        if {[dict exists $md curve_digitizer.curve_column.calibration_key]} {
            lappend roles calibration_key calibration_name
        }
    }
    set legacyNames [dict create x x y y curve_key curve_id curve_name curve_label point_order point_index family_parameter family_value]
    set columns [dict create]
    set fields [dict create]
    set meanings [dict create]
    set used [dict create]
    foreach role $roles {
        if {$legacy} {
            set variableId [dict get $legacyNames $role]
        } else {
            set k "curve_digitizer.curve_column.$role"
            if {![dict exists $md $k]} { error "Missing semantic column mapping '$role'." }
            set variableId [dict get $md $k]
        }
        if {[dict exists $used $variableId]} { error "Two semantic roles map to variable '$variableId'." }
        set variable [_variable $dsId $variableId $role]
        if {[dict get $variable dimension_ids] ne $dimension} {
            error "Semantic column '$role' is not in row dimension '$dimension'."
        }
        dict set used $variableId 1
        dict set columns $role $variableId
        dict set fields $role $variable
        dict set meanings $role [dict get $roleSemantics $role]
    }
    if {!$legacy && $mode eq "independent" && [dict exists $md curve_digitizer.curve_column.family_parameter]} {
        error "Independent curves must not publish a family parameter mapping."
    }
    return [dict create \
        api_version 1 curve_schema_version [expr {$legacy ? 0 : 1}] \
        dataset_id $dsId contract $contract mode $mode row_dimension $dimension \
        grouping_role curve_key grouping_roles [expr {[dict exists $columns calibration_key] ? {curve_key calibration_key} : {curve_key}}] \
        publication_calibration_mode [expr {[dict exists $columns calibration_key] ? {combined} : {separate}}] \
        columns $columns variables $fields \
        role_meanings $meanings index_origin 0 legacy_inferred $legacy \
        raster_points_available [expr {[dict exists $columns raster_x] && [dict exists $columns raster_y]}]]
}

proc ::GX::CurveDigitizerDataset::column {datasetId semanticRole {session ""}} {
    set manifest [read $datasetId $session]
    if {![dict exists $manifest columns $semanticRole]} {
        error "No '$semanticRole' column exists in this Dataset."
    }
    return [dict get $manifest columns $semanticRole]
}

proc ::GX::CurveDigitizerDataset::hasSchema {datasetId {session ""}} {
    return [expr {![catch {read $datasetId $session}]}]
}

proc ::GX::CurveDigitizerDataset::schema {} {
    variable roleSemantics
    return [dict create api_id CURVE_DIGITIZER_DATASET_SCHEMA_API_v1 \
        api_version 1 schema_version 1 \
        modes {independent numerical_family} grouping_role curve_key \
        mandatory_roles {x y curve_key curve_name point_order} \
        optional_roles {family_parameter raster_x raster_y calibration_key calibration_name} role_meanings $roleSemantics \
        methods {read column hasSchema schema rasterPoints}]
}


# Data-centric, bounded access through CORE Canonical Dataset API v2.
# start/count are row ordinals, not per-curve offsets. Do not open CSV paths.
proc ::GX::CurveDigitizerDataset::rasterPoints {datasetId {curveKey ""} {start 0} {count 10000} {calibrationKey ""}} {
    if {![string is integer -strict $start] || $start<0 ||
        ![string is integer -strict $count] || $count<1 || $count>100000} {
        error "Raster point range requires start>=0 and 1<=count<=100000."
    }
    set manifest [read $datasetId]
    if {![dict get $manifest raster_points_available]} {
        error "Original raster coordinates were not published in this historical Dataset."
    }
    set columns [dict get $manifest columns]
    set roles {curve_key curve_name point_order x y raster_x raster_y}
    if {[dict exists $columns calibration_key]} {lappend roles calibration_key calibration_name}
    set ids {}
    foreach role $roles {lappend ids [dict get $columns $role]}
    set handle [::GX::datasetAccessOpen [::GX::sessionInspectionCurrentSession] $datasetId]
    try {
        set values [::GX::datasetAccessReadRange $handle $ids $start $count]
    } finally {
        ::GX::datasetAccessClose $handle
    }
    set first [dict get $columns curve_key]
    set n [llength [dict get $values $first values]]
    set results {}
    for {set row 0} {$row<$n} {incr row} {
        set item [dict create]
        foreach role $roles {
            set var [dict get $columns $role]
            set valuesAtRole [dict get $values $var values]
            if {$row >= [llength $valuesAtRole]} {
                error "CORE returned uneven curve Dataset columns."
            }
            dict set item $role [lindex $valuesAtRole $row]
        }
        if {$curveKey ne "" && [dict get $item curve_key] ne $curveKey} continue
        if {$calibrationKey ne "" && (![dict exists $item calibration_key] ||
                                      [dict get $item calibration_key] ne $calibrationKey)} continue
        dict set item dataset_row [expr {$start+$row}]
        lappend results $item
    }
    return [dict create dataset_id $datasetId start $start consumed_rows $n points $results \
        coordinate_reference original_source_image_pixel_centers]
}
