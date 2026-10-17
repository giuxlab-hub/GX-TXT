# SPDX-License-Identifier: GPL-3.0-or-later
# Interactive section/profile viewer. All scientific transforms go through the
# public NUMERIC_API geometry family; no private mesh cutting is performed here.
namespace eval ::GX::SectionProfile {
    variable version 1.0.0
    variable state
    array set state {}
}

proc ::GX::SectionProfile::_get {key {default ""}} {
    variable state
    expr {[info exists state($key)] ? $state($key) : $default}
}
proc ::GX::SectionProfile::_set {key value} {
    variable state
    set state($key) $value
    return $value
}
proc ::GX::SectionProfile::_array {value} {
    if {![llength [info commands ::GX::ScientificTransportv1::array]]} {
        ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    }
    if {![llength $value]} {return [::GX::ScientificTransportv1::empty]}
    if {[llength [lindex $value 0]] == 1 && [llength $value] == 3} {
        return [::GX::ScientificTransportv1::array {1 3} $value]
    }
    set rows [llength $value]
    set columns [llength [lindex $value 0]]
    if {$columns == 0} {return [::GX::ScientificTransportv1::empty]}
    foreach row $value {if {[llength $row] != $columns} {error "Geometry matrix rows have different lengths"}}
    # ScientificTransport reshapes in Octave column-major order.
    set flat {}
    for {set column 0} {$column < $columns} {incr column} {
        foreach row $value {lappend flat [lindex $row $column]}
    }
    return [::GX::ScientificTransportv1::array [list $rows $columns] $flat]
}
proc ::GX::SectionProfile::_vec {value} {
    if {[llength $value] != 3} {error "3-D coordinate needs three values"}
    foreach x $value {
        if {![string is double -strict $x] || ![expr {abs(double($x)) < Inf}]} {error "3-D coordinate must be finite"}
    }
    return $value
}
proc ::GX::SectionProfile::_parseVec {value} {
    if {[string trim $value] eq ""} {return {}}
    set items [split [string map {, " " ; " "} [string trim $value]]]
    set out {}
    foreach item $items {if {$item ne ""} {lappend out $item}}
    return [_vec $out]
}
proc ::GX::SectionProfile::_formatVec {value} {join $value {, }}
proc ::GX::SectionProfile::_syncOriginControls {} {
    set frame [_get frame ""]
    if {$frame eq ""} return
    _set coordinate_syncing 1
    try {
        set w [_get window ""]
        foreach axis {x y z} index {0 1 2} {
            set value [lindex [dict get $frame origin] $index]
            if {$w ne "" && [winfo exists $w.plane.position.$axis]} {
                $w.plane.position.$axis configure -from [expr {min(-100.0,$value-10.0)}] -to [expr {max(100.0,$value+10.0)}]
            }
            _set origin_$axis [format %.8g $value]
        }
    } finally {_set coordinate_syncing 0}
}
proc ::GX::SectionProfile::_moveAxis {axis} {
    if {$axis ni {x y z}} {error "Unknown plane translation axis $axis"}
    set value [_get origin_$axis]
    if {![string is double -strict $value] || ![expr {abs(double($value)) < Inf}]} {error "Plane $axis coordinate must be finite"}
    set frame [_get frame ""]
    if {$frame eq ""} {set frame [_applyPlane]}
    set origin [dict get $frame origin]
    lset origin [lsearch -exact {x y z} $axis] $value
    set frame [_frame $origin [dict get $frame normal] [dict get $frame u_axis]]
    _set frame $frame
    _set origin [_formatVec [dict get $frame origin]]
    _set plane_interaction_source controls
    _syncOriginControls
    _syncNativePlane
    _status "Plane moved along [string toupper $axis] to $value"
    return $frame
}
proc ::GX::SectionProfile::_scheduleAxis {axis args} {
    if {[_get coordinate_syncing 0]} return
    set pending [_get axis_after_$axis ""]
    if {$pending ne ""} {after cancel $pending}
    _set axis_after_$axis [after 80 [list ::GX::SectionProfile::_invoke [list ::GX::SectionProfile::_moveAxis $axis]]]
}
proc ::GX::SectionProfile::_scheduleOrientation {args} {
    set pending [_get orientation_after ""]
    if {$pending ne ""} {after cancel $pending}
    _set orientation_after [after 80 [list ::GX::SectionProfile::_invoke ::GX::SectionProfile::_orientPlane]]
}
proc ::GX::SectionProfile::_geometry {action a b c {options ""}} {
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    if {$options eq ""} {set options [::GX::ScientificTransportv1::struct [dict create]]}
    return [::GX::NumericAPIv1::foundation geometry $action $a $b $c $options]
}
proc ::GX::SectionProfile::_frame {origin normal {hint {}}} {
    set a [_array [_vec $origin]]
    set b [_array [_vec $normal]]
    set c [_array $hint]
    set result [_geometry plane_frame $a $b $c]
    foreach key {origin normal u_axis v_axis} {
        if {![dict exists $result $key]} {error "NUMERIC geometry plane_frame omitted $key"}
    }
    return $result
}
proc ::GX::SectionProfile::_local {points frame} {
    set basis {}
    for {set i 0} {$i < 3} {incr i} {
        lappend basis [list [lindex [dict get $frame u_axis] $i] [lindex [dict get $frame v_axis] $i] [lindex [dict get $frame normal] $i]]
    }
    set result [_geometry frame_transform [_array $points] [_array [dict get $frame origin]] [_array $basis]]
    if {![dict exists $result value_real]} {error "NUMERIC geometry frame_transform omitted coordinates"}
    return [dict get $result value_real]
}
proc ::GX::SectionProfile::_datasetIds {} {
    set out {}
    foreach id [::GX::sessionInspectionDatasetIds] {
        set record [::GX::sessionInspectionDataset $id]
        set format [string tolower [expr {[dict exists $record format] ? [dict get $record format] : ""}]]
        if {$format in {csv hdf5 h5 obj stl vtp vtu vti step stp ply}} {lappend out $id}
    }
    return [lsort -dictionary $out]
}
proc ::GX::SectionProfile::_source {datasetId} {
    set record [::GX::sessionInspectionDataset $datasetId]
    if {[catch {set payload [::GX::sessionInspectionDatasetPayload $datasetId]}]} {
        # Older imported geometry records lack canonical_sha256. Resolve the
        # Session-relative resource through the public safe resource API and
        # retain its measured digest in publication provenance.
        if {![dict exists $record path]} {error "Dataset $datasetId has no source payload"}
        set payload [::GX::sessionInspectionResolveResource [dict get $record path]]
        dict set payload format [dict get $record format]
    }
    set format [string tolower [dict get $payload format]]
    set type [expr {$format in {csv hdf5 h5} ? "table" : ($format eq "vti" ? "volume" : "mesh")}]
    return [dict create id $datasetId record $record payload $payload type $type]
}
proc ::GX::SectionProfile::_variables {datasetId} {
    set out {}
    foreach variable [::GX::datasetVariableSchemaV3 $datasetId] {
        if {![dict get $variable enabled]} continue
        if {[dict get $variable rank] > 1} continue
        set dtype [string tolower [dict get $variable dtype]]
        if {$dtype ni {float32 float64 int8 int16 int32 int64 uint8 uint16 uint32 uint64}} continue
        lappend out [dict get $variable variable_id]
    }
    return $out
}
proc ::GX::SectionProfile::_readPoints {datasetId xId yId zId} {
    set session [::GX::sessionInspectionCurrentSession]
    set handle [::GX::datasetAccessOpen $session $datasetId]
    try {
        set data [::GX::datasetAccessReadVariables $handle [list $xId $yId $zId]]
    } finally {::GX::datasetAccessClose $handle}
    foreach id [list $xId $yId $zId] {
        if {![dict exists $data $id values]} {error "Dataset variable $id has no readable values"}
    }
    set xs [dict get $data $xId values]
    set ys [dict get $data $yId values]
    set zs [dict get $data $zId values]
    if {[llength $xs] != [llength $ys] || [llength $xs] != [llength $zs]} {error "X/Y/Z variables have different lengths"}
    set points {}; set rows {}
    for {set i 0} {$i < [llength $xs]} {incr i} {
        set p [list [lindex $xs $i] [lindex $ys $i] [lindex $zs $i]]
        if {[catch {_vec $p}]} continue
        lappend points $p
        lappend rows $i
    }
    if {![llength $points]} {error "No finite 3-D source points are available"}
    return [dict create points $points rows $rows]
}
proc ::GX::SectionProfile::_principal {mode} {
    switch -- $mode {
        XY {return [list {0 0 0} {0 0 1}]}
        XZ {return [list {0 0 0} {0 1 0}]}
        YZ {return [list {0 0 0} {1 0 0}]}
        default {error "Unknown principal plane $mode"}
    }
}
proc ::GX::SectionProfile::_selectedPoints {} {
    set w [_get window]
    if {$w eq "" || ![winfo exists $w.points_frame.points]} {return {}}
    if {[winfo exists $w.picks.points] && [llength [$w.picks.points selection]]} {
        set picks [_get native_picks {}]
        set out {}
        foreach item [$w.picks.points selection] {
            set index [lindex [$w.picks.points item $item -values] 0]
            if {[string is integer -strict $index] && $index >= 0 && $index < [llength $picks]} {
                lappend out [dict get [lindex $picks $index] position]
            }
        }
        return $out
    }
    set data [_get source_points [dict create]]
    if {![dict exists $data points]} {return {}}
    set points [dict get $data points]
    set out {}
    foreach item [$w.points_frame.points selection] {
        set index [lindex [$w.points_frame.points item $item -values] 0]
        if {[string is integer -strict $index] && $index >= 0 && $index < [llength $points]} {lappend out [lindex $points $index]}
    }
    return $out
}
proc ::GX::SectionProfile::_selectedPickNormal {} {
    set w [_get window]
    if {$w eq "" || ![winfo exists $w.picks.points]} {return ""}
    set selection [$w.picks.points selection]
    if {[llength $selection] != 1} {return ""}
    set index [lindex [$w.picks.points item [lindex $selection 0] -values] 0]
    set picks [_get native_picks {}]
    if {![string is integer -strict $index] || $index < 0 || $index >= [llength $picks]} {return ""}
    set pick [lindex $picks $index]
    expr {[dict exists $pick normal] ? [dict get $pick normal] : ""}
}
proc ::GX::SectionProfile::_clearPicks {} {
    _set native_picks {}
    _set picked_normal ""
    set w [_get window]
    if {$w ne "" && [winfo exists $w.picks.points]} {$w.picks.points delete [$w.picks.points children {}]}
    _status "Native 3D picked points cleared"
}
proc ::GX::SectionProfile::_selectionChanged {which} {
    if {[_get selection_updating 0]} return
    set w [_get window]
    if {$w eq ""} return
    _set selection_updating 1
    try {
        if {$which eq "native" && [winfo exists $w.points_frame.points]} {
            $w.points_frame.points selection remove [$w.points_frame.points selection]
        } elseif {$which eq "table" && [winfo exists $w.picks.points]} {
            $w.picks.points selection remove [$w.picks.points selection]
        }
    } finally {_set selection_updating 0}
}
proc ::GX::SectionProfile::nativeInteraction {event} {
    if {[catch {dict size $event}]} {error "Native 3D interaction event must be a dictionary"}
    set w [_get window]
    if {$w eq "" || ![winfo exists $w]} {return}
    if {![dict exists $event event]} {error "Native 3D interaction event has no type"}
    switch -- [dict get $event event] {
        plane {
            foreach key {origin normal u_axis} {if {![dict exists $event $key]} {error "Native plane event omitted $key"}}
            set frame [_frame [_vec [dict get $event origin]] [_vec [dict get $event normal]] [_vec [dict get $event u_axis]]]
            _set frame $frame
            _set plane_mode arbitrary
            _set plane_interaction_source native_mouse
            _set origin [_formatVec [dict get $frame origin]]
            _set normal [_formatVec [dict get $frame normal]]
            _set u_hint [_formatVec [dict get $frame u_axis]]
            _syncOriginControls
            _status "Working plane moved/oriented in Native 3D"
        }
        pick {
            if {![dict exists $event position]} {error "Native pick event omitted position"}
            set position [_vec [dict get $event position]]
            set pick [dict create position $position]
            if {[dict exists $event normal] && [dict get $event normal] ne ""} {
                set candidate [_vec [dict get $event normal]]
                if {[expr {abs([lindex $candidate 0])+abs([lindex $candidate 1])+abs([lindex $candidate 2]) > 1e-12}]} {
                    dict set pick normal $candidate
                    _set picked_normal $candidate
                }
            }
            foreach key {cell_id point_id} {if {[dict exists $event $key]} {dict set pick $key [dict get $event $key]}}
            set picks [_get native_picks {}]
            set index [llength $picks]
            lappend picks $pick
            _set native_picks $picks
            set normal [expr {[dict exists $pick normal] ? [_formatVec [dict get $pick normal]] : ""}]
            set cell [expr {[dict exists $pick cell_id] ? [dict get $pick cell_id] : ""}]
            set point [expr {[dict exists $pick point_id] ? [dict get $pick point_id] : ""}]
            set item [$w.picks.points insert {} end -values [list $index {*}$position $normal $cell $point]]
            $w.picks.points selection add $item
            $w.picks.points see $item
            _selectionChanged native
            _status "Picked 3-D point [expr {$index+1}] in Native 3D"
        }
        default {error "Unknown Native 3D interaction event [dict get $event event]"}
    }
}
proc ::GX::SectionProfile::_subscribeNative {} {
    if {[_get native_subscribed 0]} return
    ::GX::modulePublicApiActivate viewer.native_3d NATIVE_3D_VIEWER_API_v1
    if {![llength [info commands ::GX::Native3D::subscribeInteraction]]} {
        _status "Native 3D mouse interaction API is unavailable"
        return
    }
    ::GX::Native3D::subscribeInteraction ::GX::SectionProfile::nativeInteraction
    _set native_subscribed 1
}
proc ::GX::SectionProfile::_unsubscribeNative {} {
    if {![_get native_subscribed 0]} return
    if {[llength [info commands ::GX::Native3D::unsubscribeInteraction]]} {
        ::GX::Native3D::unsubscribeInteraction ::GX::SectionProfile::nativeInteraction
    }
    _set native_subscribed 0
}
proc ::GX::SectionProfile::_planeFromMode {mode} {
    set points [_selectedPoints]
    switch -- $mode {
        XY - XZ - YZ {lassign [_principal $mode] origin normal; return [_frame $origin $normal]}
        arbitrary {return [_frame [_parseVec [_get origin]] [_parseVec [_get normal]] ]}
        three_points {
            if {[llength $points] != 3} {error "Select exactly three source points"}
            set result [_geometry plane_three_points [_array [lindex $points 0]] [_array [lindex $points 1]] [_array [lindex $points 2]]]
            return [_frame [dict get $result origin] [dict get $result normal]]
        }
        best_fit {
            if {[llength $points] < 3} {error "Select at least three source points"}
            set result [_geometry plane_fit [_array $points] [::GX::ScientificTransportv1::empty] [::GX::ScientificTransportv1::empty]]
            return [_frame [dict get $result origin] [dict get $result normal]]
        }
        curve_normal - curve_tangent_roll {
            set source [_get source_points [dict create]]
            if {[llength $points] != 1 || ![dict exists $source points]} {error "Select exactly one trajectory point"}
            set all [dict get $source points]
            set index -1
            for {set i 0} {$i < [llength $all]} {incr i} {if {[lindex $all $i] eq [lindex $points 0]} {set index $i; break}}
            if {$index < 0} {
                # Native picks are world coordinates; resolve their associated
                # canonical trajectory sample through public geometry search.
                set nearest [_geometry nearest [_array $all] [_array [list [lindex $points 0]]] [::GX::ScientificTransportv1::empty]]
                set index [expr {int([lindex [dict get $nearest index] 0])-1}]
            }
            if {$index < 0 || $index >= [llength $all]} {error "Picked trajectory point could not be resolved"}
            set point [lindex $all $index]
            set tangent [_geometry trajectory_tangent [_array $all] [_array [list [expr {$index+1}]]] [::GX::ScientificTransportv1::empty]]
            set direction [dict get $tangent tangent]
            if {$mode eq "curve_normal"} {return [_frame $point $direction]}
            set radians [expr {double([_get roll 0])*acos(-1)/180.0}]
            set result [_geometry plane_containing_tangent [_array $point] [_array $direction] [_array [list $radians]]]
            return [_frame [dict get $result origin] [dict get $result normal] [dict get $result u_axis]]
        }
        surface_tangent {
            set normal [_selectedPickNormal]
            if {[llength $points] != 1 || $normal eq ""} {error "Select one surface point with a reliable picked normal"}
            return [_frame [lindex $points 0] $normal]
        }
        dataset_plane {
            set md [_get source_metadata [dict create]]
            foreach key {section.origin section.normal} {if {![dict exists $md $key]} {error "Source Dataset has no saved plane frame"}}
            set hint [expr {[dict exists $md section.u_axis] ? [dict get $md section.u_axis] : {}}]
            return [_frame [_parseVec [dict get $md section.origin]] [_parseVec [dict get $md section.normal]] [_parseVec $hint]]
        }
        default {error "Unknown plane mode $mode"}
    }
}
proc ::GX::SectionProfile::_applyPlane {{mode ""}} {
    if {$mode eq ""} {set mode [_get plane_mode XY]}
    set frame [_planeFromMode $mode]
    _set frame $frame
    _set plane_mode $mode
    _set plane_interaction_source controls
    _set origin [_formatVec [dict get $frame origin]]
    _set normal [_formatVec [dict get $frame normal]]
    _set u_hint [_formatVec [dict get $frame u_axis]]
    _syncOriginControls
    _syncNativePlane
    _status "Plane set: $mode"
    return $frame
}
proc ::GX::SectionProfile::_offsetPlane {distance} {
    set frame [_get frame ""]
    if {$frame eq ""} {set frame [_applyPlane]}
    set result [_geometry plane_offset [_array [dict get $frame origin]] [_array [dict get $frame normal]] [_array [list $distance]]]
    set frame [_frame [dict get $result origin] [dict get $frame normal] [dict get $frame u_axis]]
    _set frame $frame
    _set origin [_formatVec [dict get $frame origin]]
    _syncOriginControls
    _syncNativePlane
    return $frame
}
proc ::GX::SectionProfile::_orientPlane {} {
    set frame [_get frame ""]
    if {$frame eq ""} {set frame [_applyPlane]}
    set degrees [list [_get azimuth 0] [_get elevation 0] [_get roll 0]]
    set radians {}
    foreach degree $degrees {lappend radians [expr {double($degree)*acos(-1)/180.0}]}
    set result [_geometry plane_orient [_array [dict get $frame origin]] [_array $radians] [::GX::ScientificTransportv1::empty]]
    set frame [_frame [dict get $frame origin] [dict get $result normal] [dict get $result u_axis]]
    _set frame $frame
    _set normal [_formatVec [dict get $frame normal]]
    _set u_hint [_formatVec [dict get $frame u_axis]]
    _syncNativePlane
    return $frame
}
proc ::GX::SectionProfile::_flipPlane {} {
    set frame [_get frame ""]
    if {$frame eq ""} {set frame [_applyPlane]}
    set result [_geometry plane_flip [_array [dict get $frame origin]] [_array [dict get $frame normal]] [_array [dict get $frame u_axis]]]
    set frame [_frame [dict get $frame origin] [dict get $result normal] [dict get $frame u_axis]]
    _set frame $frame
    _set normal [_formatVec [dict get $frame normal]]
    _syncNativePlane
    return $frame
}
proc ::GX::SectionProfile::_centerPlane {} {
    set points [_selectedPoints]
    if {![llength $points]} {error "Select source points first"}
    set result [_geometry centroid [_array $points] [::GX::ScientificTransportv1::empty] [::GX::ScientificTransportv1::empty]]
    set frame [_get frame ""]
    if {$frame eq ""} {set frame [_applyPlane]}
    set frame [_frame [dict get $result centroid] [dict get $frame normal] [dict get $frame u_axis]]
    _set frame $frame
    _set origin [_formatVec [dict get $frame origin]]
    _syncOriginControls
    _syncNativePlane
    return $frame
}
proc ::GX::SectionProfile::_syncNativePlane {} {
    set frame [_get frame ""]
    if {$frame eq ""} return
    if {[llength [info commands ::GX::Native3D::setWorkingPlane]]} {
        ::GX::Native3D::setWorkingPlane [dict get $frame origin] [dict get $frame normal] [dict get $frame u_axis] 1
    }
}
proc ::GX::SectionProfile::_openNative {} {
    set source [_get source ""]
    if {$source eq ""} {error "Choose a source Dataset"}
    _subscribeNative
    ::GX::viewerOpen viewer.native_3d native_3d [dict create dataset_id [dict get $source id]]
    _syncNativePlane
}
proc ::GX::SectionProfile::_sourceChanged {} {
    set datasetId [_get dataset_id]
    if {$datasetId eq ""} return
    set source [_source $datasetId]
    _set source $source
    _clearPicks
    set session [::GX::sessionInspectionCurrentSession]
    _set source_metadata [::GX::datasetMetadataRead $session $datasetId]
    if {[dict get $source type] eq "table"} {
        set variables [_variables $datasetId]
        foreach axis {x y z} {
            set w [_get window]
            $w.vars.$axis configure -values $variables
            set candidate [_get ${axis}_variable_id]
            if {$candidate ni $variables} {
                set index [expr {$axis eq "x" ? 0 : ($axis eq "y" ? 1 : 2)}]
                _set ${axis}_variable_id [lindex $variables $index]
            }
        }
        _loadPointList
    } else {
        _set source_points [dict create]
        foreach axis {x y z} {_set ${axis}_variable_id ""}
        set w [_get window]
        if {$w ne "" && [winfo exists $w.points_frame.points]} {$w.points_frame.points delete [$w.points_frame.points children {}]}
    }
    _status "Source: $datasetId ([dict get $source type])"
}
proc ::GX::SectionProfile::_loadPointList {} {
    set source [_get source ""]
    if {$source eq "" || [dict get $source type] ne "table"} return
    set data [_readPoints [dict get $source id] [_get x_variable_id] [_get y_variable_id] [_get z_variable_id]]
    _set source_points $data
    set w [_get window]
    $w.points_frame.points delete [$w.points_frame.points children {}]
    set points [dict get $data points]
    set rows [dict get $data rows]
    for {set i 0} {$i < [llength $points]} {incr i} {
        $w.points_frame.points insert {} end -values [list $i [lindex $rows $i] {*}[lindex $points $i]]
    }
    _status "Loaded [llength $points] finite 3-D rows"
}
proc ::GX::SectionProfile::_extract {} {
    set source [_get source ""]
    if {$source eq ""} {error "Choose a source Dataset"}
    set frame [_get frame ""]
    if {$frame eq ""} {set frame [_applyPlane]}
    set type [dict get $source type]
    set mode [_get extraction_mode intersection]
    set rows {}
    set triples {}
    set segments {}
    set original {}
    set extraColumns [dict create]
    if {$type eq "table"} {
        set data [_get source_points ""]
        if {$data eq ""} {error "Choose X/Y/Z variables"}
        set points [dict get $data points]
        set local [_local $points $frame]
        set sourceRows [dict get $data rows]
        if {$mode eq "slab_projection"} {
            set tolerance [_get slab_tolerance]
            if {![string is double -strict $tolerance] || $tolerance < 0} {error "Slab tolerance must be nonnegative"}
            for {set i 0} {$i < [llength $local]} {incr i} {
                set q [lindex $local $i]
                if {abs([lindex $q 2]) > $tolerance} continue
                lappend rows [lindex $sourceRows $i]
                lappend triples [list [lindex $q 0] [lindex $q 1]]
                lappend original [lindex $points $i]
                lappend segments 0
            }
        } elseif {$mode eq "trajectory_projection"} {
            for {set i 0} {$i < [llength $local]} {incr i} {
                set q [lindex $local $i]
                lappend rows [lindex $sourceRows $i]
                lappend triples [list [lindex $q 0] [lindex $q 1]]
                lappend original [lindex $points $i]
                lappend segments 0
            }
        } elseif {$mode eq "trajectory_intersection"} {
            set result [_geometry trajectory_plane_intersections [_array $points] [_array [dict get $frame origin]] [_array [dict get $frame normal]]]
            foreach key {points source_row_pairs} {if {![dict exists $result $key]} {error "Trajectory intersection omitted $key"}}
            set original [dict get $result points]
            set local [_local $original $frame]
            foreach q $local {lappend triples [list [lindex $q 0] [lindex $q 1]]}
            set rowEnds {}
            foreach pair [dict get $result source_row_pairs] {
                lappend rows [lindex $sourceRows [expr {[lindex $pair 0]-1}]]
                lappend rowEnds [lindex $sourceRows [expr {[lindex $pair 1]-1}]]
            }
            for {set i 0} {$i < [llength $triples]} {incr i} {lappend segments $i}
            dict set extraColumns source_row_end $rowEnds
            if {[dict exists $result fraction]} {dict set extraColumns crossing_fraction [dict get $result fraction]}
        } else {error "Choose a point-cloud slab projection or trajectory operation"}
    } elseif {$type eq "mesh"} {
        if {$mode ne "intersection"} {error "Meshes use actual plane intersection"}
        set payload [dict get $source payload]
        set options [::GX::ScientificTransportv1::struct [dict create \
            sha256 [::GX::ScientificTransportv1::text [dict get $payload sha256]] \
            format [::GX::ScientificTransportv1::text [dict get $payload format]]]]
        set result [_geometry mesh_section [::GX::ScientificTransportv1::text [dict get $payload path]] [_array [dict get $frame origin]] [_array [dict get $frame normal]] $options]
        foreach key {points segment_id} {if {![dict exists $result $key]} {error "Mesh section omitted $key"}}
        set original [dict get $result points]
        set segments [dict get $result segment_id]
        if {![llength $original]} {
            error "Plane does not intersect mesh Dataset '[dict get $source id]'. Move the plane into the mesh and retry."
        }
        if {[dict exists $result source_cell_id]} {dict set extraColumns source_cell_id [dict get $result source_cell_id]}
        set local [_local $original $frame]
        foreach q $local {lappend triples [list [lindex $q 0] [lindex $q 1]]}
        set rows [lrepeat [llength $triples] -1]
    } else {
        if {$mode ne "intersection"} {error "Scalar grids use a true plane slice"}
        set payload [dict get $source payload]
        set options [::GX::ScientificTransportv1::struct [dict create \
            sha256 [::GX::ScientificTransportv1::text [dict get $payload sha256]] \
            format [::GX::ScientificTransportv1::text [dict get $payload format]]]]
        set result [_geometry volume_slice [::GX::ScientificTransportv1::text [dict get $payload path]] [_array [dict get $frame origin]] [_array [dict get $frame normal]] $options]
        foreach key {points scalar} {if {![dict exists $result $key]} {error "Volume slice omitted $key"}}
        set original [dict get $result points]
        if {![llength $original]} {
            error "Plane does not intersect scalar grid Dataset '[dict get $source id]'. Move the plane into the grid and retry."
        }
        set local [_local $original $frame]
        foreach q $local {lappend triples [list [lindex $q 0] [lindex $q 1]]}
        set rows [lrepeat [llength $triples] -1]
        set segments [lrepeat [llength $triples] 0]
        _set slice_scalar [dict get $result scalar]
        _set slice_scalar_name [expr {[dict exists $result field_name] ? [dict get $result field_name] : "scalar"}]
    }
    if {![llength $triples]} {error "The chosen plane/mode produced no output points"}
    if {[llength $triples] != [llength $original] || [llength $triples] != [llength $segments]} {error "Section point/identity lengths differ"}
    set output [dict create source $source frame $frame mode $mode uv $triples xyz $original source_rows $rows segment_id $segments \
        extra_columns $extraColumns output_kind [expr {$type eq "volume" ? "scalar_field_2d" : "profile_points_2d"}]]
    if {$type eq "volume"} {
        if {[llength [_get slice_scalar]] != [llength $triples]} {error "Volume slice scalar/point lengths differ"}
        dict set output scalar [_get slice_scalar]
        dict set output scalar_name [_get slice_scalar_name]
    }
    _set output $output
    _preview $output
    _status "Extracted [llength $triples] $mode points"
    return $output
}
proc ::GX::SectionProfile::_preview {output} {
    set w [_get window]
    if {$w eq "" || ![winfo exists $w.preview]} return
    set canvas $w.preview
    $canvas delete all
    set points [dict get $output uv]
    set us {}; set vs {}
    foreach q $points {lappend us [lindex $q 0]; lappend vs [lindex $q 1]}
    set u0 [tcl::mathfunc::min {*}$us]; set u1 [tcl::mathfunc::max {*}$us]
    set v0 [tcl::mathfunc::min {*}$vs]; set v1 [tcl::mathfunc::max {*}$vs]
    if {$u0 == $u1} {set u1 [expr {$u0+1.0}]}
    if {$v0 == $v1} {set v1 [expr {$v0+1.0}]}
    set width [winfo width $canvas]; if {$width < 100} {set width 480}
    set height [winfo height $canvas]; if {$height < 100} {set height 260}
    $canvas create line 20 [expr {$height-20}] [expr {$width-10}] [expr {$height-20}] -fill #789
    $canvas create line 20 [expr {$height-20}] 20 10 -fill #789
    $canvas create text [expr {$width-25}] [expr {$height-28}] -text U -fill #def
    $canvas create text 30 20 -text V -fill #def
    foreach q $points {
        set x [expr {20.0+($width-40)*([lindex $q 0]-$u0)/($u1-$u0)}]
        set y [expr {$height-20.0-($height-40)*([lindex $q 1]-$v0)/($v1-$v0)}]
        $canvas create oval [expr {$x-2}] [expr {$y-2}] [expr {$x+2}] [expr {$y+2}] -fill #4bd4ba -outline {}
    }
}
proc ::GX::SectionProfile::_publish {} {
    set output [_get output ""]
    if {$output eq ""} {error "Extract a section or projection before publication"}
    set id [string trim [_get output_id]]
    if {$id eq ""} {error "Output Dataset ID is required"}
    set source [dict get $output source]
    set sourceId [dict get $source id]
    set frame [dict get $output frame]
    set mode [dict get $output mode]
    set payload [dict get $source payload]
    set session [::GX::sessionInspectionCurrentSession]
    set definition [dict create dataset_id $id contract table.generic storage csv replace_owned 1 \
        producer_version 1.0.0 source "3D Section/Profile Viewer" \
        source_dataset_ids [list $sourceId] \
        provenance "Source Dataset $sourceId SHA-256 [dict get $payload sha256]; $mode; plane mode [_get plane_mode]"]
    set plan [::GX::datasetPublicationV2Prepare $session viewer.section_profile $definition]
    set writer ""
    try {
        set writer [::GX::datasetPublicationV2OpenWriter $plan]
        ::GX::datasetPublicationV2DeclareDimension $writer row 0 [dict create extendible 1]
        set specs {{u float64 coordinate} {v float64 coordinate} {source_x float64 auxiliary} {source_y float64 auxiliary} {source_z float64 auxiliary} {source_row int64 auxiliary} {segment_id int64 auxiliary}}
        if {[dict get $output output_kind] eq "scalar_field_2d"} {lappend specs {scalar float64 data}}
        dict for {column values} [dict get $output extra_columns] {
            if {[llength $values] != [llength [dict get $output uv]]} {error "Section $column length differs from U/V"}
            set dtype [expr {$column eq "crossing_fraction" ? "float64" : "int64"}]
            lappend specs [list $column $dtype auxiliary]
        }
        foreach spec $specs {
            lassign $spec name dtype role
            ::GX::datasetPublicationV2DeclareVariable $writer $name [dict create name $name unit "" semantic_role "" dtype $dtype rank 1 dimension_ids row coordinate_role $role axis_kind explicit]
        }
        set data [dict create u {} v {} source_x {} source_y {} source_z {} source_row [dict get $output source_rows] segment_id [dict get $output segment_id]]
        foreach q [dict get $output uv] {dict lappend data u [lindex $q 0]; dict lappend data v [lindex $q 1]}
        foreach p [dict get $output xyz] {
            dict lappend data source_x [lindex $p 0]
            dict lappend data source_y [lindex $p 1]
            dict lappend data source_z [lindex $p 2]
        }
        if {[dict get $output output_kind] eq "scalar_field_2d"} {dict set data scalar [dict get $output scalar]}
        dict for {column values} [dict get $output extra_columns] {dict set data $column $values}
        ::GX::datasetPublicationV2Append $writer row $data
        set result [::GX::datasetPublicationV2Finalize $writer]
    } on error {error options} {
        if {$writer ne ""} {catch {::GX::datasetPublicationV2Abort $writer}}
        return -options $options $error
    }
    set metadata [dict create \
        section.source_dataset_id $sourceId \
        section.source_sha256 [dict get $payload sha256] \
        section.source_format [dict get $payload format] \
        section.x_variable_id [_get x_variable_id] \
        section.y_variable_id [_get y_variable_id] \
        section.z_variable_id [_get z_variable_id] \
        section.plane_mode [_get plane_mode] \
        section.plane_interaction_source [_get plane_interaction_source controls] \
        section.origin [_formatVec [dict get $frame origin]] \
        section.normal [_formatVec [dict get $frame normal]] \
        section.u_axis [_formatVec [dict get $frame u_axis]] \
        section.v_axis [_formatVec [dict get $frame v_axis]] \
        section.offset [_get offset 0] \
        section.azimuth [_get azimuth 0] \
        section.elevation [_get elevation 0] \
        section.roll [_get roll 0] \
        section.slab_tolerance [_get slab_tolerance 0] \
        section.extraction_mode $mode]
    dict set metadata section.output_kind [dict get $output output_kind]
    if {[dict get $output output_kind] eq "scalar_field_2d"} {dict set metadata section.scalar_name [dict get $output scalar_name]}
    ::GX::datasetMetadataWrite $session $id $metadata
    _status "Published Dataset $id"
    return $result
}
proc ::GX::SectionProfile::_status {message} {_set status $message}
proc ::GX::SectionProfile::_invoke {command} {
    if {[catch {uplevel #0 [list {*}$command]} error options]} {
        _status $error
        set detail [expr {[dict exists $options -errorinfo] ? [dict get $options -errorinfo] : $error}]
        tk_messageBox -parent [_get window] -icon error -title "Section/Profile Viewer" \
            -message $error -detail $detail
        return -options $options $error
    }
}
proc ::GX::SectionProfile::_widget {} {
    package require Tk
    set w .gxtxt_section_profile
    if {[winfo exists $w]} {raise $w; focus $w; return $w}
    toplevel $w
    wm title $w "3D Section / Profile Viewer"
    wm geometry $w 1100x850
    _set window $w
    foreach {key value} {plane_mode XY origin {0, 0, 0} normal {0, 0, 1} u_hint {1, 0, 0} extraction_mode intersection slab_tolerance 0.01 offset 0 azimuth 0 elevation 0 roll 0 output_id section_profile status Ready} {
        if {[_get $key ""] eq ""} {_set $key $value}
    }
    ttk::frame $w.source
    ttk::label $w.source.label -text "Source Dataset"
    ttk::combobox $w.source.dataset -textvariable ::GX::SectionProfile::state(dataset_id) -values [_datasetIds] -state readonly -width 40
    bind $w.source.dataset <<ComboboxSelected>> {::GX::SectionProfile::_invoke ::GX::SectionProfile::_sourceChanged}
    ttk::button $w.source.refresh -text Refresh -command {::GX::SectionProfile::_invoke ::GX::SectionProfile::_sourceChanged}
    ttk::button $w.source.native -text "Open in Native 3D" -command {::GX::SectionProfile::_invoke ::GX::SectionProfile::_openNative}
    pack $w.source.label $w.source.dataset $w.source.refresh $w.source.native -side left -padx 5
    pack $w.source -fill x -padx 8 -pady 8
    ttk::frame $w.vars
    foreach axis {x y z} {
        ttk::label $w.vars.${axis}label -text "[string toupper $axis] variable"
        ttk::combobox $w.vars.$axis -textvariable ::GX::SectionProfile::state(${axis}_variable_id) -state readonly -width 19
        pack $w.vars.${axis}label $w.vars.$axis -side left -padx 4
        bind $w.vars.$axis <<ComboboxSelected>> {::GX::SectionProfile::_invoke ::GX::SectionProfile::_loadPointList}
    }
    pack $w.vars -fill x -padx 8 -pady 3
    ttk::labelframe $w.plane -text "Working plane"
    ttk::label $w.plane.mode_label -text "Definition"
    ttk::combobox $w.plane.mode -textvariable ::GX::SectionProfile::state(plane_mode) -values {XY XZ YZ arbitrary three_points best_fit curve_normal curve_tangent_roll surface_tangent dataset_plane} -state readonly -width 24
    ttk::label $w.plane.origin_label -text "Origin"
    ttk::entry $w.plane.origin -textvariable ::GX::SectionProfile::state(origin) -width 29
    ttk::label $w.plane.normal_label -text "Normal"
    ttk::entry $w.plane.normal -textvariable ::GX::SectionProfile::state(normal) -width 29
    ttk::button $w.plane.apply -text "Set plane" -command {::GX::SectionProfile::_invoke ::GX::SectionProfile::_applyPlane}
    grid $w.plane.mode_label -row 0 -column 0 -padx 4 -pady 4
    grid $w.plane.mode -row 0 -column 1 -padx 4 -pady 4
    grid $w.plane.origin_label -row 0 -column 2 -padx 4
    grid $w.plane.origin -row 0 -column 3 -padx 4
    grid $w.plane.normal_label -row 0 -column 4 -padx 4
    grid $w.plane.normal -row 0 -column 5 -padx 4
    grid $w.plane.apply -row 0 -column 6 -padx 4
    ttk::frame $w.plane.adjust
    foreach {key label from to} {offset Offset -100 100 azimuth Azimuth -180 180 elevation Elevation -90 90 roll Roll -180 180} {
        ttk::label $w.plane.adjust.${key}label -text $label
        ttk::scale $w.plane.adjust.$key -from $from -to $to -variable ::GX::SectionProfile::state($key) -orient horizontal -length 145
        ttk::entry $w.plane.adjust.${key}value -textvariable ::GX::SectionProfile::state($key) -width 7
        pack $w.plane.adjust.${key}label $w.plane.adjust.$key $w.plane.adjust.${key}value -side left -padx 2
    }
    grid $w.plane.adjust -row 1 -column 0 -columnspan 7 -sticky ew -pady 4
    ttk::frame $w.plane.position
    foreach {axis label color} {x {X (red)} #b4232c y {Y (green)} #17803d z {Z (blue)} #275db1} {
        ttk::label $w.plane.position.${axis}label -text $label -foreground $color
        ttk::scale $w.plane.position.$axis -from -100 -to 100 -variable ::GX::SectionProfile::state(origin_$axis) -orient horizontal -length 145 -command [list ::GX::SectionProfile::_scheduleAxis $axis]
        ttk::entry $w.plane.position.${axis}value -textvariable ::GX::SectionProfile::state(origin_$axis) -width 9
        bind $w.plane.position.${axis}value <Return> [list ::GX::SectionProfile::_invoke [list ::GX::SectionProfile::_moveAxis $axis]]
        bind $w.plane.position.${axis}value <FocusOut> [list ::GX::SectionProfile::_invoke [list ::GX::SectionProfile::_moveAxis $axis]]
        pack $w.plane.position.${axis}label $w.plane.position.$axis $w.plane.position.${axis}value -side left -padx 2
    }
    grid $w.plane.position -row 2 -column 0 -columnspan 7 -sticky ew -pady 4
    foreach axis {azimuth elevation roll} {
        $w.plane.adjust.$axis configure -command ::GX::SectionProfile::_scheduleOrientation
        bind $w.plane.adjust.${axis}value <Return> {::GX::SectionProfile::_invoke ::GX::SectionProfile::_orientPlane}
        bind $w.plane.adjust.${axis}value <FocusOut> {::GX::SectionProfile::_invoke ::GX::SectionProfile::_orientPlane}
    }
    ttk::frame $w.plane.actions
    foreach {name label command} {
        reset Reset {::GX::SectionProfile::_applyPlane XY}
        flip {Flip normal} {::GX::SectionProfile::_flipPlane}
        center {Center on selection} {::GX::SectionProfile::_centerPlane}
        offset {Apply offset} {::GX::SectionProfile::_offsetPlane [::GX::SectionProfile::_get offset 0]}
        orient {Apply orientation} {::GX::SectionProfile::_orientPlane}
        dataset {Use Dataset plane} {::GX::SectionProfile::_applyPlane dataset_plane}
    } {
        ttk::button $w.plane.actions.$name -text $label -command [list ::GX::SectionProfile::_invoke $command]
        pack $w.plane.actions.$name -side left -padx 3
    }
    grid $w.plane.actions -row 3 -column 0 -columnspan 7 -sticky w -pady 3
    pack $w.plane -fill x -padx 8 -pady 4
    ttk::labelframe $w.points_frame -text "Source points (select rows for 3-point, best-fit, and curve planes)"
    ttk::treeview $w.points_frame.points -columns {index source_row x y z} -show headings -selectmode extended -height 8
    foreach c {index source_row x y z} {$w.points_frame.points heading $c -text $c; $w.points_frame.points column $c -width 120}
    bind $w.points_frame.points <<TreeviewSelect>> {::GX::SectionProfile::_selectionChanged table}
    ttk::scrollbar $w.points_frame.scroll -orient vertical -command [list $w.points_frame.points yview]
    $w.points_frame.points configure -yscrollcommand [list $w.points_frame.scroll set]
    pack $w.points_frame.points -in $w.points_frame -side left -fill both -expand 1
    pack $w.points_frame.scroll -in $w.points_frame -side right -fill y
    pack $w.points_frame -fill both -expand 1 -padx 8 -pady 4
    ttk::labelframe $w.picks -text "Native 3D mouse picks (select three for a plane, or one for tangent modes)"
    ttk::treeview $w.picks.points -columns {index x y z normal cell_id point_id} -show headings -selectmode extended -height 4
    foreach c {index x y z normal cell_id point_id} {$w.picks.points heading $c -text $c; $w.picks.points column $c -width 110}
    $w.picks.points column normal -width 190
    bind $w.picks.points <<TreeviewSelect>> {::GX::SectionProfile::_selectionChanged native}
    ttk::button $w.picks.clear -text "Clear picks" -command {::GX::SectionProfile::_clearPicks}
    pack $w.picks.clear -side right -padx 4
    pack $w.picks.points -side left -fill both -expand 1
    pack $w.picks -fill both -padx 8 -pady 4
    ttk::frame $w.extract
    ttk::label $w.extract.mode_label -text "Operation"
    ttk::combobox $w.extract.mode -textvariable ::GX::SectionProfile::state(extraction_mode) -values {intersection slab_projection trajectory_intersection trajectory_projection} -state readonly -width 25
    ttk::label $w.extract.tol_label -text "Slab half-thickness"
    ttk::entry $w.extract.tol -textvariable ::GX::SectionProfile::state(slab_tolerance) -width 12
    ttk::button $w.extract.go -text "Extract / Preview" -command {::GX::SectionProfile::_invoke ::GX::SectionProfile::_extract}
    pack $w.extract.mode_label $w.extract.mode $w.extract.tol_label $w.extract.tol $w.extract.go -side left -padx 5
    pack $w.extract -fill x -padx 8 -pady 5
    canvas $w.preview -height 260 -background #17212d -highlightthickness 0
    pack $w.preview -fill both -expand 1 -padx 8 -pady 4
    ttk::frame $w.output
    ttk::label $w.output.idlabel -text "Output Dataset ID"
    ttk::entry $w.output.id -textvariable ::GX::SectionProfile::state(output_id) -width 30
    ttk::button $w.output.publish -text "Publish as 2-D Dataset" -command {::GX::SectionProfile::_invoke ::GX::SectionProfile::_publish}
    ttk::label $w.output.status -textvariable ::GX::SectionProfile::state(status)
    pack $w.output.idlabel $w.output.id $w.output.publish $w.output.status -side left -padx 6
    pack $w.output -fill x -padx 8 -pady 8
    bind $w <Destroy> [list ::GX::SectionProfile::_destroyed $w %W]
    _subscribeNative
    return $w
}
proc ::GX::SectionProfile::viewerDispatch {action scene} {
    if {$action ni {open rerender}} {error "Section/Profile viewer action must be open or rerender"}
    set w [_widget]
    if {[dict exists $scene open_context dataset_id]} {
        set id [dict get $scene open_context dataset_id]
        if {$id in [_datasetIds]} {_set dataset_id $id; _sourceChanged}
    } elseif {[_get dataset_id] eq "" && [llength [_datasetIds]] == 1} {
        _set dataset_id [lindex [_datasetIds] 0]
        _sourceChanged
    }
    return $w
}

::GX::viewerBackendRegister section_profile_tk ::GX::SectionProfile::viewerDispatch

proc ::GX::SectionProfile::_destroyed {owner actual} {
    if {$actual ne $owner} return
    _unsubscribeNative
    _set window {}
}
