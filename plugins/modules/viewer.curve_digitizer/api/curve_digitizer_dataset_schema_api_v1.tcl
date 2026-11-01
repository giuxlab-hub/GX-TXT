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
        calibration_name {Human label of the calibration realization; not a grouping identifier.} \
        y_axis_id {Logical Y1 or Y2 binding, independent of left/right placement.}]
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
    if {$role in {curve_key curve_name calibration_key calibration_name y_axis_id} && $dtype ni {string text}} {
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
        if {$v ni {1 2}} { error "Unsupported Curve Digitalizer curve schema version '$v'." }
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
        if {!$legacy && [dict get $md curve_digitizer.curve_schema_version] eq "2"} {lappend roles y_axis_id}
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
        api_version 1 curve_schema_version [expr {$legacy ? 0 : [dict get $md curve_digitizer.curve_schema_version]}] \
        dataset_id $dsId contract $contract mode $mode row_dimension $dimension \
        grouping_role curve_key grouping_roles [expr {[dict exists $columns calibration_key] ? {curve_key calibration_key} : {curve_key}}] \
        publication_calibration_mode [expr {[dict exists $columns calibration_key] ? {combined} : {separate}}] \
        columns $columns variables $fields \
        role_meanings $meanings index_origin 0 legacy_inferred $legacy \
        raster_points_available [expr {[dict exists $columns raster_x] && [dict exists $columns raster_y]}] \
        multi_y_available [expr {[dict exists $columns y_axis_id]}] \
        y_axis_mode [expr {[dict exists $columns y_axis_id] ? [dict get $md curve_digitizer.axis_mode] : "y1"}]]
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
        optional_roles {family_parameter raster_x raster_y calibration_key calibration_name y_axis_id} role_meanings $roleSemantics \
        methods {read column hasSchema schema rasterPoints axes curves describe datasetGroup}]
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
    if {[dict exists $columns y_axis_id]} {lappend roles y_axis_id}
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

# Public, version-adaptive semantic description. Dataset schemas remain
# canonical table.generic / curve_family.table. Internal JSON layouts are
# interpreted only by this producer-owned API, never by external readers.
proc ::GX::CurveDigitizerDataset::_jsonRecords {json label} {
    if {[string bytelength $json]>1000000} {error "$label metadata exceeds 1 MiB"}
    if {[catch {package require json}]} {error {Tcl JSON decoder is unavailable}}
    if {[catch {::json::json2dict $json} records]} {
        error "Invalid $label metadata JSON."
    }
    return $records
}

proc ::GX::CurveDigitizerDataset::axes {datasetId {session ""}} {
    set m [read $datasetId $session]
    set md [dict get [_context $datasetId $session] metadata]
    if {[dict get $m curve_schema_version] eq "2"} {
        foreach k {axis_schema_version axis_model_version axis_mode
                   axis_definitions_json axis_units_y1 axis_units_y2} {
            if {![dict exists $md curve_digitizer.$k]} {error "Missing Y2 axis metadata '$k'."}
        }
        if {[dict get $md curve_digitizer.axis_schema_version] ne "1" ||
            [dict get $md curve_digitizer.axis_model_version] ne "2" ||
            [dict get $md curve_digitizer.axis_mode] ni {y1 y2 mixed}} {
            error {Unsupported scientific Y2 axis schema.}
        }
        set records [_jsonRecords [dict get $md curve_digitizer.axis_definitions_json] axes]
        if {[llength $records]<1 || [llength $records]>200} {
            error {Y2 axes require 1..200 calibration descriptions.}
        }
        set seen {}
        foreach row $records {
            foreach key {measurement_id label x y1 y2} {
                if {![dict exists $row $key]} {error "Missing scientific axis '$key'."}
            }
            set id [dict get $row measurement_id]
            if {![regexp {^meas_[a-f0-9]{32}$} $id] || $id in $seen} {
                error {Invalid or repeated calibration measurement ID.}
            }
            lappend seen $id
            foreach axis {x y1 y2} {
                set config [dict get $row $axis]
                foreach field {minimum maximum scale unit} {
                    if {![dict exists $config $field]} {
                        error "Missing $axis.$field in axis metadata."
                    }
                }
                if {[dict get $config scale] ni {linear log}} {
                    error "Unsupported scientific scale of $axis."
                }
            }
        }
        return [dict create schema_version 1 available_axes {x y1 y2} \
            mode [dict get $md curve_digitizer.axis_mode] \
            measurements $records \
            unit_y1 [dict get $md curve_digitizer.axis_units_y1] \
            unit_y2 [dict get $md curve_digitizer.axis_units_y2]]
    }
    # The historic per-axis min/max were not canonical for every schema 0/1.
    # Never invent physical limits absent from verified published metadata.
    set result [dict create schema_version 0 available_axes {x y1} mode y1]
    foreach {code prefix} {x x y1 y} {
        set details {}
        foreach field {label unit scale} {
            set key "curve_digitizer.$prefix\_$field"
            if {[dict exists $md $key]} {
                dict set details $field [dict get $md $key]
            }
        }
        dict set result $code $details
    }
    return $result
}

proc ::GX::CurveDigitizerDataset::curves {datasetId {session ""}} {
    set m [read $datasetId $session]
    set md [dict get [_context $datasetId $session] metadata]
    if {[dict get $m curve_schema_version] eq "2"} {
        if {![dict exists $md curve_digitizer.curves_json]} {
            error {Missing versioned Y2 curve descriptions.}
        }
        set records [_jsonRecords [dict get $md curve_digitizer.curves_json] curves]
        if {[llength $records]<1 || [llength $records]>10000} {
            error {Y2 curve descriptions must contain 1..10000 entries.}
        }
        set seen {}
        foreach row $records {
            foreach field {curve_id curve_name axis_id point_count_per_calibration} {
                if {![dict exists $row $field]} {error "Y2 curve metadata lacks '$field'."}
            }
            set id [dict get $row curve_id]
            set axis [dict get $row axis_id]
            if {$id in $seen || $axis ni {y1 y2}} {
                error {Duplicate curve ID or invalid Y axis binding.}
            }
            set count [dict get $row point_count_per_calibration]
            if {![string is integer -strict $count] || $count<0} {
                error {Invalid source point count in curve metadata.}
            }
            set binding "curve_digitizer.curve_axis.$id"
            if {![dict exists $md $binding] || [dict get $md $binding] ne $axis} {
                error {Curve/Y axis binding disagrees with published metadata.}
            }
            lappend seen $id
        }
        return [dict create curve_schema_version 2 curves $records]
    }
    # v0/v1 legacy: bounded canonical row scan using the public Dataset API.
    # These outputs do not contain producer-stored per-curve JSON records.
    set columns [dict get $m columns]
    set ids [list [dict get $columns curve_key] [dict get $columns curve_name]]
    set handle [::GX::datasetAccessOpen [dict get [_context $datasetId $session] session] $datasetId]
    try {
        set unique {}
        set order {}
        set start 0
        while {$start<200000} {
            set page [::GX::datasetAccessReadRange $handle $ids $start 1000]
            set keys [dict get $page [lindex $ids 0] values]
            set names [dict get $page [lindex $ids 1] values]
            if {[llength $keys] != [llength $names]} {error {Uneven canonical curve columns.}}
            foreach id $keys label $names {
                if {![dict exists $unique $id]} {
                    dict set unique $id [dict create curve_id $id curve_name $label \
                        axis_id y1 point_count_per_calibration 0]
                    lappend order $id
                }
                set current [dict get $unique $id]
                dict incr current point_count_per_calibration
                dict set unique $id $current
            }
            set n [llength $keys]
            incr start $n
            if {$n<1000} break
        }
        if {$start>=200000} {error {Legacy curve scan exceeded 200000 rows.}}
        set rows {}
        foreach id $order {lappend rows [dict get $unique $id]}
    } finally {
        ::GX::datasetAccessClose $handle
    }
    return [dict create curve_schema_version [dict get $m curve_schema_version] curves $rows]
}

proc ::GX::CurveDigitizerDataset::datasetGroup {datasetId {session ""}} {
    set ctx [_context $datasetId $session]
    if {![llength [info commands ::GX::datasetGroupForDataset]]} {
        return [dict create grouped 0 group_id {}]
    }
    set group [::GX::datasetGroupForDataset [dict get $ctx session] $datasetId]
    if {$group eq {}} {return [dict create grouped 0 group_id {}]}
    set manifest [::GX::datasetGroupGet [dict get $ctx session] $group]
    return [dict create grouped 1 group_id $group \
        primary_dataset_id [dict get $manifest primary_dataset_id] \
        members [dict get $manifest members] \
        status [dict get $manifest status]]
}

proc ::GX::CurveDigitizerDataset::describe {datasetId {session ""}} {
    set m [read $datasetId $session]
    return [dict create api_version 1 dataset_id $datasetId \
        contract [dict get $m contract] \
        curve_schema_version [dict get $m curve_schema_version] \
        columns [dict get $m columns] \
        axes [axes $datasetId $session] \
        curves [curves $datasetId $session] \
        group [datasetGroup $datasetId $session]]
}
