# GX-TXT Temporal Set API v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Public, runtime-independent temporal views over canonical time-series data.
# A Temporal Segment Set stores a small ordered list of user-authored intervals.
# A Temporal Window Set stores a compact regular generator definition. Neither
# resource copies, concatenates, or modifies source Dataset values.

namespace eval ::GX {
    variable temporalSetApiVersion 1
    variable temporalSet
    variable temporalSetCounter 0
    variable temporalSegment
    variable temporalSetWidgetDisplay
    variable temporalSetWidgetPath
    array set temporalSet {}
    array set temporalSegment {}
    array set temporalSetWidgetDisplay {}
    array set temporalSetWidgetPath {}
}

proc ::GX::temporalSetClear {} {
    variable temporalSet
    variable temporalSetCounter
    variable temporalSegment
    array unset temporalSet *
    array unset temporalSegment *
    set temporalSetCounter 0
}

proc ::GX::temporalSetValidId {id} {
    return [regexp {^tset_([0-9]+)$} $id]
}

proc ::GX::temporalSegmentValidId {id} {
    return [regexp {^seg_([0-9]+)$} $id]
}

proc ::GX::temporalSetIds {} {
    variable temporalSet
    set ids {}
    foreach name [array names temporalSet "*,id"] {
        set id [string range $name 0 end-3]
        if {$id ni $ids} { lappend ids $id }
    }
    return [lsort -dictionary $ids]
}

proc ::GX::temporalSetField {id field {default ""}} {
    variable temporalSet
    if {[info exists temporalSet($id,$field)]} { return $temporalSet($id,$field) }
    return $default
}

proc ::GX::temporalSegmentField {setId segmentId field {default ""}} {
    variable temporalSegment
    if {[info exists temporalSegment($setId,$segmentId,$field)]} { return $temporalSegment($setId,$segmentId,$field) }
    return $default
}

proc ::GX::temporalSetNextId {} {
    variable temporalSetCounter
    while 1 {
        incr temporalSetCounter
        set id [format "tset_%03d" $temporalSetCounter]
        if {[temporalSetField $id id ""] eq ""} { return $id }
    }
}

proc ::GX::temporalSetRegistryPath {session} {
    return [file join $session metadata temporal_sets.ini]
}

proc ::GX::temporalSetDefinitionFields {} {
    return {api_version id type source_dataset_id temporal_variable_id temporal_variable temporal_unit parent_selection_id boundary_policy generator_basis window_size step duration_unit partial_policy label created_at updated_at}
}

proc ::GX::temporalSetRegisterRaw {id fields} {
    variable temporalSet
    variable temporalSetCounter
    if {![regexp {^tset_([0-9]+)$} $id -> number]} { error "Invalid Temporal Set ID '$id'." }
    scan $number %d number
    foreach {field value} $fields { set temporalSet($id,$field) $value }
    set temporalSet($id,id) $id
    set temporalSet($id,api_version) 1
    if {$number > $temporalSetCounter} { set temporalSetCounter $number }
    return $id
}

proc ::GX::temporalSetRemoveSegments {id} {
    variable temporalSegment
    array unset temporalSegment "$id,*"
}

proc ::GX::temporalSetNormalizeSegments {id segments} {
    set out {}
    set used {}
    set next 0
    foreach segment $segments {
        if {[catch {dict size $segment}]} { error "Temporal Segment definitions must be dictionaries." }
        set segmentId [expr {[dict exists $segment id] ? [string trim [dict get $segment id]] : ""}]
        if {$segmentId eq ""} {
            while 1 {
                incr next
                set candidate [format "seg_%03d" $next]
                if {$candidate ni $used} { set segmentId $candidate; break }
            }
        }
        if {![regexp {^seg_([0-9]+)$} $segmentId -> n]} { error "Invalid Temporal Segment ID '$segmentId'." }
        scan $n %d n
        if {$segmentId in $used} { error "Duplicate Temporal Segment ID '$segmentId'." }
        if {$n > $next} { set next $n }
        set start [expr {[dict exists $segment start] ? [dict get $segment start] : ""}]
        set end [expr {[dict exists $segment end] ? [dict get $segment end] : ""}]
        if {![string is double -strict $start] || ![string is double -strict $end]} {
            error "Temporal Segment '$segmentId' requires numeric start and end values."
        }
        if {double($end) <= double($start)} { error "Temporal Segment '$segmentId' end must be greater than start." }
        set label [expr {[dict exists $segment label] ? [dict get $segment label] : ""}]
        if {[regexp {[\r\n]} $label]} { error "Temporal Segment labels must be single-line strings." }
        lappend used $segmentId
        lappend out [dict create id $segmentId order [llength $out] label $label start [format %.17g $start] end [format %.17g $end]]
    }
    return $out
}

proc ::GX::temporalSetStoreSegments {id segments} {
    variable temporalSegment
    temporalSetRemoveSegments $id
    set order 0
    foreach segment $segments {
        incr order
        set segmentId [dict get $segment id]
        set temporalSegment($id,$segmentId,id) $segmentId
        set temporalSegment($id,$segmentId,order) $order
        set temporalSegment($id,$segmentId,label) [dict get $segment label]
        set temporalSegment($id,$segmentId,start) [dict get $segment start]
        set temporalSegment($id,$segmentId,end) [dict get $segment end]
    }
}


# Return segment dictionaries in persistent order. The wrapper above uses an
# order tuple to avoid relying on array enumeration order.
proc ::GX::temporalSetOrderedSegments {id} {
    variable temporalSegment
    set rows {}
    foreach name [array names temporalSegment "$id,*,id"] {
        set segmentId [lindex [split $name ,] 1]
        lappend rows [list [temporalSegmentField $id $segmentId order 0] [dict create id $segmentId order [temporalSegmentField $id $segmentId order 0] label [temporalSegmentField $id $segmentId label ""] start [temporalSegmentField $id $segmentId start ""] end [temporalSegmentField $id $segmentId end ""]]]
    }
    set out {}
    foreach row [lsort -integer -index 0 $rows] { lappend out [lindex $row 1] }
    return $out
}

proc ::GX::temporalSetRead {id} {
    if {[temporalSetField $id id ""] eq ""} { error "Unknown Temporal Set '$id'." }
    set out [dict create]
    foreach field [temporalSetDefinitionFields] { dict set out $field [temporalSetField $id $field ""] }
    if {[dict get $out type] eq "segment_set"} { dict set out segments [temporalSetOrderedSegments $id] }
    return $out
}

proc ::GX::temporalSetNumericUnitForVariable {variable} {
    # value_kind=elapsed_time/value_format=hms has one public numeric base unit:
    # seconds. Temporal Set must use that numeric unit rather than the original
    # source declaration, otherwise equal durations would resolve differently.
    if {[dict get $variable value_kind] eq "elapsed_time" && [dict get $variable value_format] eq "hms"} { return s }
    return [dict get $variable unit]
}

proc ::GX::temporalUnitConvertLinear {value fromUnit toUnit} {
    if {![string is double -strict $value]} { error "Temporal value '$value' is not numeric." }
    if {$fromUnit eq $toUnit} { return [expr {double($value)}] }
    if {![unitTclCompatible $fromUnit $toUnit]} { error "Incompatible temporal units '$fromUnit' and '$toUnit'." }

    # Temporal durations use the public elapsed-time requested-unit path whenever
    # both units are compatible with seconds.  This keeps intrinsic units and
    # Unit Registry scale resources (for example Julian year, ka and Ma) under
    # one authoritative conversion model instead of duplicating a duration table.
    if {[llength [info commands ::GX::elapsedTimeConvert]] &&
        [unitTclCompatible $fromUnit s] && [unitTclCompatible $toUnit s]} {
        set oneSecondInFrom [lindex [elapsedTimeConvert 1 $fromUnit] 0]
        if {$oneSecondInFrom == 0.0} { error "Invalid temporal conversion scale for '$fromUnit'." }
        set seconds [expr {double($value) / double($oneSecondInFrom)}]
        return [lindex [elapsedTimeConvert $seconds $toUnit] 0]
    }

    # Fallback for compatible intrinsic linear units outside the elapsed-time
    # semantic path. Affine and nonlinear relations remain invalid for widths.
    if {[catch {lassign [unitTclSingle $fromUnit] fromScale _ _} err]} { error "Unsupported temporal unit '$fromUnit': $err" }
    if {[catch {lassign [unitTclSingle $toUnit] toScale _ _} err]} { error "Unsupported temporal unit '$toUnit': $err" }
    return [expr {double($value)*double($fromScale)/double($toScale)}]
}

proc ::GX::temporalSetAxisInfo {id} {
    variable currentSession
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { error "Temporal Set '$id' requires an open session." }
    loadDatasetRegistry $currentSession
    set datasetId [temporalSetField $id source_dataset_id ""]
    if {$datasetId eq "" || [datasetField $datasetId id ""] eq ""} { error "Temporal Set '$id' refers to missing Dataset '$datasetId'." }
    set variableId [temporalSetField $id temporal_variable_id ""]
    if {$variableId eq ""} { error "Temporal Set '$id' has no temporal variable identity." }
    if {[catch {set variable [datasetVariableV3ById $datasetId $variableId]} err]} { error "Temporal Set '$id' refers to missing temporal variable '$variableId' in Dataset '$datasetId'." }
    if {![dict get $variable enabled]} { error "Temporal Set '$id' temporal variable '$variableId' is disabled." }
    if {[dict get $variable value_kind] eq "text"} { error "Temporal Set '$id' temporal variable '$variableId' is textual." }
    if {[dict get $variable rank] != 1} { error "Temporal Set '$id' temporal variable '$variableId' must be one-dimensional." }
    set numericUnit [temporalSetNumericUnitForVariable $variable]
    if {$numericUnit eq "" || ![unitTclCompatible $numericUnit s]} { error "Temporal Set '$id' variable '$variableId' does not have a temporal unit." }
    set axisKind [dict get $variable axis_kind]
    set count ""
    if {$axisKind eq "uniform"} {
        set count [dict get $variable axis_count]
        if {![string is integer -strict $count] || $count < 0} { error "Temporal Set '$id' uniform temporal axis has invalid axis_count." }
        if {![string is double -strict [dict get $variable axis_origin]] || ![string is double -strict [dict get $variable axis_step]] || [dict get $variable axis_step] <= 0} {
            error "Temporal Set '$id' requires a positive uniform temporal axis step."
        }
    } else {
        set shape [datasetSchemaV3SplitIds [dict get $variable shape]]
        if {[llength $shape] == 1 && [string is integer -strict [lindex $shape 0]]} { set count [lindex $shape 0] }
        if {$count eq ""} { set count [datasetField $datasetId row_count ""] }
        if {![string is integer -strict $count] || $count < 0} { error "Temporal Set '$id' cannot determine the temporal axis row count." }
    }
    return [dict create dataset_id $datasetId variable_id $variableId variable $variable variable_name [dict get $variable canonical] source_unit [dict get $variable unit] numeric_unit $numericUnit axis_kind $axisKind count $count]
}

proc ::GX::temporalSetValidateParentSelection {id axisInfo} {
    variable currentSession
    set selectionId [temporalSetField $id parent_selection_id ""]
    if {$selectionId eq ""} { return [dict create id ""] }
    datasetSelectionLoadRegistry $currentSession
    if {[datasetSelectionField $selectionId id ""] eq ""} { error "Temporal Set '$id' refers to missing parent Dataset Selection '$selectionId'." }
    if {[datasetSelectionField $selectionId type ""] ne "x_range"} { error "Temporal Set '$id' parent Dataset Selection '$selectionId' must be type x_range." }
    if {[datasetSelectionField $selectionId x_coordinate_space "source"] ne "source"} { error "Temporal Set '$id' parent Dataset Selection '$selectionId' must use one canonical source coordinate space." }
    set datasetId [dict get $axisInfo dataset_id]
    if {[datasetSelectionField $selectionId source_dataset_id ""] ne $datasetId} { error "Temporal Set '$id' parent Dataset Selection '$selectionId' refers to a different Dataset." }
    set variableId [dict get $axisInfo variable_id]
    set selectionVariableId [datasetSelectionField $selectionId x_variable_id ""]
    if {$selectionVariableId ne ""} {
        if {$selectionVariableId ne $variableId} { error "Temporal Set '$id' parent Dataset Selection '$selectionId' refers to a different temporal variable." }
    } elseif {[datasetSelectionField $selectionId x_variable ""] ne [dict get $axisInfo variable_name]} {
        error "Temporal Set '$id' parent Dataset Selection '$selectionId' refers to a different temporal variable."
    }
    set xmin [datasetSelectionField $selectionId x_min ""]
    set xmax [datasetSelectionField $selectionId x_max ""]
    if {![string is double -strict $xmin] || ![string is double -strict $xmax]} { error "Temporal Set '$id' parent Dataset Selection '$selectionId' has invalid X bounds." }
    if {$xmin > $xmax} { set q $xmin; set xmin $xmax; set xmax $q }
    set selectionUnit [datasetSelectionField $selectionId x_unit [dict get $axisInfo numeric_unit]]
    set axisUnit [dict get $axisInfo numeric_unit]
    if {$selectionUnit ne $axisUnit} {
        set xmin [temporalUnitConvertLinear $xmin $selectionUnit $axisUnit]
        set xmax [temporalUnitConvertLinear $xmax $selectionUnit $axisUnit]
    }
    return [dict create id $selectionId x_min [format %.17g $xmin] x_max [format %.17g $xmax]]
}

proc ::GX::temporalSetValidateDefinition {id} {
    set type [temporalSetField $id type ""]
    if {$type ni {segment_set window_set}} { error "Temporal Set '$id' has unsupported type '$type'." }
    set axisInfo [temporalSetAxisInfo $id]
    temporalSetValidateParentSelection $id $axisInfo
    if {$type eq "segment_set"} {
        set segments [temporalSetOrderedSegments $id]
        if {![llength $segments]} { error "Temporal Segment Set '$id' must contain at least one segment." }
        # Re-normalization validates stored numeric bounds and unique IDs.
        temporalSetNormalizeSegments $id $segments
    } else {
        set basis [temporalSetField $id generator_basis ""]
        if {$basis ni {samples duration}} { error "Temporal Window Set '$id' generator_basis must be samples or duration." }
        set windowSize [temporalSetField $id window_size ""]
        set step [temporalSetField $id step ""]
        if {$basis eq "samples"} {
            if {![string is integer -strict $windowSize] || $windowSize <= 0 || ![string is integer -strict $step] || $step <= 0} { error "Temporal Window Set '$id' sample window_size and step must be positive integers." }
        } else {
            if {![string is double -strict $windowSize] || $windowSize <= 0 || ![string is double -strict $step] || $step <= 0} { error "Temporal Window Set '$id' duration window_size and step must be positive numbers." }
            if {[dict get $axisInfo axis_kind] ne "uniform"} { error "Temporal Window Set '$id' duration-based generation currently requires a canonical uniform temporal axis." }
            set durationUnit [temporalSetField $id duration_unit ""]
            # An omitted duration unit means the temporal variable's current
            # numeric unit. This is a definition default, not the later public
            # requested-unit conversion API.
            if {$durationUnit eq ""} { set durationUnit [dict get $axisInfo numeric_unit] }
            temporalUnitConvertLinear 1 $durationUnit [dict get $axisInfo numeric_unit]
        }
        if {[temporalSetField $id partial_policy drop] ni {drop include}} { error "Temporal Window Set '$id' partial_policy must be drop or include." }
    }
    return $axisInfo
}

proc ::GX::temporalSetSaveRegistry {{session ""}} {
    variable currentSession
    if {$session eq ""} { set session $currentSession }
    if {$session eq "" || ![file isdirectory $session]} { return "" }
    file mkdir [file join $session metadata]
    set path [temporalSetRegistryPath $session]
    set tmp "${path}.tmp.[pid]"
    set fd [open $tmp w]
    fconfigure $fd -encoding utf-8 -translation lf
    try {
        puts $fd "; GX-TXT Temporal Set API v1 registry"
        puts $fd "; Persistent definitions only. Resolved regular windows are derived runtime state."
        puts $fd "\[temporal_set_api\]"; putKV $fd api_version 1; putKV $fd ids [join [temporalSetIds] ";"]
        foreach id [temporalSetIds] {
            puts $fd "\n\[temporal_set.$id\]"
            foreach field [temporalSetDefinitionFields] { putKV $fd $field [temporalSetField $id $field ""] }
            if {[temporalSetField $id type ""] eq "segment_set"} {
                set segments [temporalSetOrderedSegments $id]
                putKV $fd segment_count [llength $segments]
                set index 0
                foreach segment $segments {
                    incr index
                    puts $fd "\n\[temporal_set.$id.segment.$index\]"
                    foreach field {id order label start end} { putKV $fd $field [dict get $segment $field] }
                }
            }
        }
    } finally {
        close $fd
    }
    file rename -force -- $tmp $path
    return $path
}

proc ::GX::temporalSetLoadRegistry {{session ""}} {
    variable currentSession
    if {$session eq ""} { set session $currentSession }
    temporalSetClear
    if {$session eq ""} { return {} }
    set path [temporalSetRegistryPath $session]
    if {![file isfile $path]} { return {} }
    set data [parseIni $path]
    set ids [expr {[dict exists $data temporal_set_api.ids] ? [splitList [dict get $data temporal_set_api.ids]] : {}}]
    if {![llength $ids]} {
        foreach key [dict keys $data] {
            if {[regexp {^temporal_set\.(tset_[0-9]+)\.id$} $key -> id]} { lappend ids $id }
        }
        set ids [lsort -unique $ids]
    }
    foreach id $ids {
        set fields {}
        foreach field [temporalSetDefinitionFields] {
            set key "temporal_set.$id.$field"
            if {[dict exists $data $key]} { lappend fields $field [dict get $data $key] }
        }
        temporalSetRegisterRaw $id $fields
        if {[temporalSetField $id type ""] eq "segment_set"} {
            set count [expr {[dict exists $data temporal_set.$id.segment_count] ? [dict get $data temporal_set.$id.segment_count] : 0}]
            set segments {}
            for {set index 1} {$index <= $count} {incr index} {
                set prefix "temporal_set.$id.segment.$index."
                if {![dict exists $data ${prefix}id]} continue
                set segment [dict create]
                foreach field {id order label start end} { dict set segment $field [expr {[dict exists $data ${prefix}$field] ? [dict get $data ${prefix}$field] : ""}] }
                lappend segments $segment
            }
            temporalSetStoreSegments $id [temporalSetNormalizeSegments $id $segments]
        }
    }
    return [temporalSetIds]
}

proc ::GX::temporalSetCreate {definition} {
    variable currentSession
    variable temporalSet
    variable temporalSegment
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { error "Creating a Temporal Set requires an open session." }
    if {[catch {dict size $definition}]} { error "Temporal Set definition must be a dictionary." }
    temporalSetLoadRegistry $currentSession
    set id [expr {[dict exists $definition id] ? [string trim [dict get $definition id]] : [temporalSetNextId]}]
    if {![temporalSetValidId $id]} { error "Invalid Temporal Set ID '$id'." }
    if {[temporalSetField $id id ""] ne ""} { error "Temporal Set '$id' already exists." }
    set type [expr {[dict exists $definition type] ? [string tolower [string trim [dict get $definition type]]] : ""}]
    set datasetId [expr {[dict exists $definition source_dataset_id] ? [string trim [dict get $definition source_dataset_id]] : ""}]
    set variableId [expr {[dict exists $definition temporal_variable_id] ? [string trim [dict get $definition temporal_variable_id]] : ""}]
    set parent [expr {[dict exists $definition parent_selection_id] ? [string trim [dict get $definition parent_selection_id]] : ""}]
    set now [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"]
    set fields [list type $type source_dataset_id $datasetId temporal_variable_id $variableId parent_selection_id $parent boundary_policy start_inclusive_end_exclusive created_at $now updated_at $now]
    foreach field {generator_basis window_size step duration_unit partial_policy label} {
        set default [expr {$field eq "partial_policy" ? "drop" : ""}]
        lappend fields $field [expr {[dict exists $definition $field] ? [dict get $definition $field] : $default}]
    }
    temporalSetRegisterRaw $id $fields
    if {$type eq "segment_set"} {
        set segments [expr {[dict exists $definition segments] ? [dict get $definition segments] : {}}]
        temporalSetStoreSegments $id [temporalSetNormalizeSegments $id $segments]
    }
    if {[catch {
        set axisInfo [temporalSetValidateDefinition $id]
        set temporalSet($id,temporal_variable) [dict get $axisInfo variable_name]
        set temporalSet($id,temporal_unit) [dict get $axisInfo numeric_unit]
        if {$type eq "window_set" && [temporalSetField $id generator_basis ""] eq "duration" && [temporalSetField $id duration_unit ""] eq ""} { set temporalSet($id,duration_unit) [dict get $axisInfo numeric_unit] }
        temporalSetSaveRegistry $currentSession
    } err opts]} {
        foreach name [array names temporalSet "$id,*"] { unset temporalSet($name) }
        temporalSetRemoveSegments $id
        return -options $opts $err
    }
    return $id
}

proc ::GX::temporalSetUpdate {id changes} {
    variable currentSession
    variable temporalSet
    variable temporalSegment
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { error "Updating a Temporal Set requires an open session." }
    temporalSetLoadRegistry $currentSession
    if {[temporalSetField $id id ""] eq ""} { error "Unknown Temporal Set '$id'." }
    if {[catch {dict size $changes}]} { error "Temporal Set changes must be a dictionary." }
    set beforeSet [array get temporalSet "$id,*"]
    set beforeSegments [array get temporalSegment "$id,*"]
    set immutable {id api_version created_at boundary_policy}
    set allowed {type source_dataset_id temporal_variable_id parent_selection_id generator_basis window_size step duration_unit partial_policy label segments}
    if {[catch {
        dict for {field value} $changes {
            if {$field in $immutable || $field ni $allowed} { error "Temporal Set field '$field' is not mutable through API v1." }
            if {$field eq "segments"} continue
            set temporalSet($id,$field) $value
        }
        if {[dict exists $changes segments]} {
            if {[temporalSetField $id type ""] ne "segment_set"} { error "segments are valid only for Temporal Segment Sets." }
            temporalSetStoreSegments $id [temporalSetNormalizeSegments $id [dict get $changes segments]]
        } elseif {[temporalSetField $id type ""] ne "segment_set"} {
            temporalSetRemoveSegments $id
        }
        set axisInfo [temporalSetValidateDefinition $id]
        set temporalSet($id,temporal_variable) [dict get $axisInfo variable_name]
        set temporalSet($id,temporal_unit) [dict get $axisInfo numeric_unit]
        if {[temporalSetField $id type ""] eq "window_set" && [temporalSetField $id generator_basis ""] eq "duration" && [temporalSetField $id duration_unit ""] eq ""} {
            set temporalSet($id,duration_unit) [dict get $axisInfo numeric_unit]
        }
        set temporalSet($id,updated_at) [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"]
        temporalSetSaveRegistry $currentSession
    } err opts]} {
        array unset temporalSet "$id,*"; array set temporalSet $beforeSet
        array unset temporalSegment "$id,*"; array set temporalSegment $beforeSegments
        return -options $opts $err
    }
    return [temporalSetRead $id]
}

proc ::GX::temporalSetDelete {id} {
    variable currentSession
    variable temporalSet
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { error "Deleting a Temporal Set requires an open session." }
    temporalSetLoadRegistry $currentSession
    if {[temporalSetField $id id ""] eq ""} { error "Unknown Temporal Set '$id'." }
    foreach name [array names temporalSet "$id,*"] { unset temporalSet($name) }
    temporalSetRemoveSegments $id
    temporalSetSaveRegistry $currentSession
    return $id
}

proc ::GX::temporalSetList {{datasetId ""}} {
    set out {}
    foreach id [temporalSetIds] {
        if {$datasetId ne "" && [temporalSetField $id source_dataset_id ""] ne $datasetId} continue
        lappend out [temporalSetRead $id]
    }
    return $out
}

proc ::GX::_temporalCeilIndex {value origin step} {
    set raw [expr {(double($value)-double($origin))/double($step)}]
    set nearest [expr {round($raw)}]
    if {abs($raw-$nearest) <= 1e-10*max(1.0,abs($raw))} { return [expr {int($nearest)}] }
    return [expr {int(ceil($raw))}]
}

proc ::GX::_temporalFloorIndex {value origin step} {
    set raw [expr {(double($value)-double($origin))/double($step)}]
    set nearest [expr {round($raw)}]
    if {abs($raw-$nearest) <= 1e-10*max(1.0,abs($raw))} { return [expr {int($nearest)}] }
    return [expr {int(floor($raw))}]
}

proc ::GX::temporalSetUniformParentRows {axisInfo parent} {
    set variable [dict get $axisInfo variable]
    set total [dict get $axisInfo count]
    if {[dict get $parent id] eq ""} { return [dict create row_start 0 row_count $total time_min "" time_max ""] }
    set origin [dict get $variable axis_origin]
    set step [dict get $variable axis_step]
    set first [_temporalCeilIndex [dict get $parent x_min] $origin $step]
    set last [_temporalFloorIndex [dict get $parent x_max] $origin $step]
    set first [expr {max(0,min($total,$first))}]
    set end [expr {max(0,min($total,$last+1))}]
    if {$end < $first} { set end $first }
    return [dict create row_start $first row_count [expr {$end-$first}] time_min [dict get $parent x_min] time_max [dict get $parent x_max]]
}

proc ::GX::_temporalBoundaryCompare {a b} {
    set av [dict get $a value]; set bv [dict get $b value]
    if {double($av) < double($bv)} { return -1 }
    if {double($av) > double($bv)} { return 1 }
    # At one coordinate, >= must be resolved before > so an equal sample can
    # satisfy the inclusive lower boundary without blocking the strict upper.
    set ar [expr {[dict get $a op] eq "ge" ? 0 : 1}]
    set br [expr {[dict get $b op] eq "ge" ? 0 : 1}]
    return [expr {$ar < $br ? -1 : ($ar > $br ? 1 : 0)}]
}

proc ::GX::temporalSetScanExplicitBoundaries {axisInfo boundaries} {
    variable currentSession
    set datasetId [dict get $axisInfo dataset_id]
    set variableId [dict get $axisInfo variable_id]
    set total [dict get $axisInfo count]
    set sorted [lsort -command ::GX::_temporalBoundaryCompare $boundaries]
    set results [dict create]
    if {![llength $sorted]} { return $results }
    set handle ""
    try {
        set handle [datasetAccessOpen $currentSession $datasetId]
        set chunkSize 65536
        set offset 0
        set next 0
        set previous ""
        while {$offset < $total && $next < [llength $sorted]} {
            set request [expr {min($chunkSize,$total-$offset)}]
            set block [datasetAccessReadRange $handle [list $variableId] $offset $request]
            set item [dict get $block $variableId]
            set values [dict get $item values]
            set local 0
            foreach raw $values {
                set lower [string tolower [string trim $raw]]
                if {![string is double -strict $raw] || $lower in {nan +nan -nan inf +inf -inf infinity +infinity -infinity}} { error "Temporal Set explicit axis contains a non-finite value at row [expr {$offset+$local}]." }
                set value [expr {double($raw)}]
                if {$previous ne "" && $value < $previous} { error "Temporal Set explicit axis must be monotonically non-decreasing." }
                set previous $value
                while {$next < [llength $sorted]} {
                    set boundaryItem [lindex $sorted $next]
                    set boundary [dict get $boundaryItem value]; set key [dict get $boundaryItem key]; set op [dict get $boundaryItem op]
                    set hit [expr {$op eq "gt" ? $value > double($boundary) : $value >= double($boundary)}]
                    if {!$hit} break
                    dict set results $key [expr {$offset+$local}]
                    incr next
                }
                incr local
            }
            incr offset [llength $values]
            if {![llength $values]} break
        }
        while {$next < [llength $sorted]} {
            set key [dict get [lindex $sorted $next] key]
            dict set results $key $total
            incr next
        }
    } finally {
        if {$handle ne ""} { datasetAccessClose $handle }
    }
    return $results
}

proc ::GX::temporalSetExplicitParentRows {axisInfo parent} {
    set total [dict get $axisInfo count]
    if {[dict get $parent id] eq ""} { return [dict create row_start 0 row_count $total time_min "" time_max ""] }
    set bounds [list [dict create key parent_start value [dict get $parent x_min] op ge] [dict create key parent_end value [dict get $parent x_max] op gt]]
    set mapped [temporalSetScanExplicitBoundaries $axisInfo $bounds]
    set first [dict get $mapped parent_start]
    set end [dict get $mapped parent_end]
    if {$end < $first} { set end $first }
    return [dict create row_start $first row_count [expr {$end-$first}] time_min [dict get $parent x_min] time_max [dict get $parent x_max]]
}

proc ::GX::temporalSetWindowRowParameters {id axisInfo} {
    set basis [temporalSetField $id generator_basis ""]
    if {$basis eq "samples"} { return [dict create window_rows [temporalSetField $id window_size] step_rows [temporalSetField $id step]] }
    set variable [dict get $axisInfo variable]
    set axisStep [dict get $variable axis_step]
    set axisUnit [dict get $axisInfo numeric_unit]
    set durationUnit [temporalSetField $id duration_unit ""]
    if {$durationUnit eq ""} { set durationUnit $axisUnit }
    set width [temporalUnitConvertLinear [temporalSetField $id window_size] $durationUnit $axisUnit]
    set step [temporalUnitConvertLinear [temporalSetField $id step] $durationUnit $axisUnit]
    set widthRows [expr {double($width)/double($axisStep)}]
    set stepRows [expr {double($step)/double($axisStep)}]
    foreach {label raw} [list window_size $widthRows step $stepRows] {
        set rounded [expr {round($raw)}]
        if {abs($raw-$rounded) > 1e-10*max(1.0,abs($raw)) || $rounded < 1} { error "Temporal Window Set '$id' duration $label does not map to an exact positive number of uniform samples." }
        if {$label eq "window_size"} { set widthRows [expr {int($rounded)}] } else { set stepRows [expr {int($rounded)}] }
    }
    return [dict create window_rows $widthRows step_rows $stepRows]
}

proc ::GX::temporalSetWindowCount {parentCount windowRows stepRows partialPolicy} {
    if {$parentCount <= 0} { return 0 }
    if {$partialPolicy eq "include"} { return [expr {int(floor(double($parentCount-1)/$stepRows))+1}] }
    if {$parentCount < $windowRows} { return 0 }
    return [expr {int(floor(double($parentCount-$windowRows)/$stepRows))+1}]
}

proc ::GX::temporalSetResolveInfo {id} {
    variable currentSession
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { error "Resolving a Temporal Set requires an open session." }
    temporalSetLoadRegistry $currentSession
    if {[temporalSetField $id id ""] eq ""} { error "Unknown Temporal Set '$id'." }
    set axisInfo [temporalSetValidateDefinition $id]
    set parent [temporalSetValidateParentSelection $id $axisInfo]
    set parentRows [expr {[dict get $axisInfo axis_kind] eq "uniform" ? [temporalSetUniformParentRows $axisInfo $parent] : [temporalSetExplicitParentRows $axisInfo $parent]}]
    set out [dict create api_version 1 id $id type [temporalSetField $id type] source_dataset_id [dict get $axisInfo dataset_id] temporal_variable_id [dict get $axisInfo variable_id] temporal_variable [dict get $axisInfo variable_name] temporal_unit [dict get $axisInfo numeric_unit] parent_selection_id [dict get $parent id] boundary_policy start_inclusive_end_exclusive axis_kind [dict get $axisInfo axis_kind] axis_origin "" axis_step "" axis_count [dict get $axisInfo count] effective_row_start [dict get $parentRows row_start] effective_row_count [dict get $parentRows row_count] member_count 0]
    if {[dict get $axisInfo axis_kind] eq "uniform"} {
        dict set out axis_origin [dict get [dict get $axisInfo variable] axis_origin]
        dict set out axis_step [dict get [dict get $axisInfo variable] axis_step]
    }
    if {[temporalSetField $id type] eq "window_set"} {
        set params [temporalSetWindowRowParameters $id $axisInfo]
        set windowRows [dict get $params window_rows]
        set stepRows [dict get $params step_rows]
        set partial [temporalSetField $id partial_policy drop]
        dict set out generator_basis [temporalSetField $id generator_basis]
        dict set out window_size [temporalSetField $id window_size]
        dict set out step [temporalSetField $id step]
        dict set out duration_unit [temporalSetField $id duration_unit ""]
        dict set out partial_policy $partial
        dict set out resolved_window_rows $windowRows
        dict set out resolved_step_rows $stepRows
        dict set out member_count [temporalSetWindowCount [dict get $parentRows row_count] $windowRows $stepRows $partial]
        return $out
    }

    set segments [temporalSetOrderedSegments $id]
    set bounds {}
    set index 0
    foreach segment $segments {
        incr index
        lappend bounds [dict create key "segment_${index}_start" value [dict get $segment start] op ge]
        lappend bounds [dict create key "segment_${index}_end" value [dict get $segment end] op ge]
    }
    if {[dict get $axisInfo axis_kind] eq "explicit"} { set mapped [temporalSetScanExplicitBoundaries $axisInfo $bounds] } else { set mapped [dict create] }
    set parentStart [dict get $parentRows row_start]
    set parentEnd [expr {$parentStart+[dict get $parentRows row_count]}]
    set members {}
    set index 0
    foreach segment $segments {
        incr index
        set startValue [dict get $segment start]
        set endValue [dict get $segment end]
        if {[dict get $axisInfo axis_kind] eq "uniform"} {
            set variable [dict get $axisInfo variable]
            set startRow [_temporalCeilIndex $startValue [dict get $variable axis_origin] [dict get $variable axis_step]]
            set endRow [_temporalCeilIndex $endValue [dict get $variable axis_origin] [dict get $variable axis_step]]
        } else {
            set startRow [dict get $mapped segment_${index}_start]
            set endRow [dict get $mapped segment_${index}_end]
        }
        set startRow [expr {max($parentStart,min($parentEnd,$startRow))}]
        set endRow [expr {max($parentStart,min($parentEnd,$endRow))}]
        if {$endRow < $startRow} { set endRow $startRow }
        set effectiveStart $startValue
        set effectiveEnd $endValue
        if {[dict get $axisInfo axis_kind] eq "uniform"} {
            set variable [dict get $axisInfo variable]
            set effectiveStart [expr {double([dict get $variable axis_origin])+$startRow*double([dict get $variable axis_step])}]
            set effectiveEnd [expr {double([dict get $variable axis_origin])+$endRow*double([dict get $variable axis_step])}]
        } elseif {[dict get $parent id] ne ""} {
            # For explicit axes the row mapping is authoritative. Clip the
            # reported effective interval too, so consumers never see bounds
            # outside the parent Selection while requested_* keeps user intent.
            set effectiveStart [expr {max(double($startValue),double([dict get $parent x_min]))}]
            set effectiveEnd [expr {min(double($endValue),double([dict get $parent x_max]))}]
            if {$effectiveEnd < $effectiveStart} { set effectiveEnd $effectiveStart }
        }
        lappend members [dict create index $index member_id [dict get $segment id] label [dict get $segment label] requested_time_start $startValue requested_time_end $endValue time_start [format %.17g $effectiveStart] time_end [format %.17g $effectiveEnd] row_start $startRow row_count [expr {$endRow-$startRow}]]
    }
    dict set out members $members
    dict set out member_count [llength $members]
    return $out
}

proc ::GX::_temporalSetMemberFromInfo {info index} {
    if {![string is integer -strict $index] || $index < 1} { error "Temporal Set member index must be an integer >= 1." }
    set count [dict get $info member_count]
    if {$index > $count} { error "Temporal Set '[dict get $info id]' has no member $index (count=$count)." }
    if {[dict get $info type] eq "segment_set"} { return [lindex [dict get $info members] [expr {$index-1}]] }
    set rowStart [expr {[dict get $info effective_row_start]+($index-1)*[dict get $info resolved_step_rows]}]
    set parentEnd [expr {[dict get $info effective_row_start]+[dict get $info effective_row_count]}]
    set rowCount [dict get $info resolved_window_rows]
    if {$rowStart+$rowCount > $parentEnd} { set rowCount [expr {$parentEnd-$rowStart}] }
    set timeStart ""; set timeEnd ""
    if {[dict get $info axis_kind] eq "uniform"} {
        set timeStart [expr {double([dict get $info axis_origin])+$rowStart*double([dict get $info axis_step])}]
        set timeEnd [expr {double([dict get $info axis_origin])+($rowStart+$rowCount)*double([dict get $info axis_step])}]
        set timeStart [format %.17g $timeStart]; set timeEnd [format %.17g $timeEnd]
    }
    return [dict create index $index member_id [format "win_%06d" $index] label "" requested_time_start $timeStart requested_time_end $timeEnd time_start $timeStart time_end $timeEnd row_start $rowStart row_count $rowCount]
}

proc ::GX::temporalSetResolveMember {id index} {
    return [_temporalSetMemberFromInfo [temporalSetResolveInfo $id] $index]
}

proc ::GX::temporalSetIterate {id commandPrefix} {
    set info [temporalSetResolveInfo $id]
    set count [dict get $info member_count]
    for {set index 1} {$index <= $count} {incr index} {
        uplevel #0 [list {*}$commandPrefix $id [_temporalSetMemberFromInfo $info $index]]
    }
    return $count
}

proc ::GX::temporalSetResolve {id} {
    set info [temporalSetResolveInfo $id]
    set members {}
    for {set index 1} {$index <= [dict get $info member_count]} {incr index} { lappend members [_temporalSetMemberFromInfo $info $index] }
    dict set info members $members
    return $info
}

proc ::GX::temporalSetCompatibleIds {moduleId configKey} {
    variable currentSession
    if {$currentSession ne "" && [file isdirectory $currentSession]} { temporalSetLoadRegistry $currentSession }
    set sourceRole [string trim [moduleConfigField $moduleId $configKey source_role primary]]
    if {$sourceRole eq ""} { set sourceRole primary }
    set target [datasetSelectionSourceDataset $moduleId $sourceRole]
    set types [splitList [moduleConfigField $moduleId $configKey temporal_types "segment_set;window_set"]]
    set out {}
    foreach id [temporalSetIds] {
        if {$target ne "" && [temporalSetField $id source_dataset_id ""] ne $target} continue
        if {[temporalSetField $id type ""] ni $types} continue
        lappend out $id
    }
    return $out
}

proc ::GX::temporalSetValidateConfig {moduleId configKey} {
    variable moduleCfg
    set value [expr {[info exists moduleCfg($moduleId,$configKey)] ? [string trim $moduleCfg($moduleId,$configKey)] : ""}]
    set required [expr {[moduleConfigField $moduleId $configKey required 0] ? 1 : 0}]
    if {$value eq "" || $value eq "None"} {
        if {$required} { error "$moduleId: configuration '$configKey' requires a Temporal Set." }
        return ""
    }
    if {[temporalSetField $value id ""] eq ""} { error "$moduleId: unknown Temporal Set '$value'." }
    if {[lsearch -exact [temporalSetCompatibleIds $moduleId $configKey] $value] < 0} { error "$moduleId: Temporal Set '$value' is incompatible with the configured source for '$configKey'." }
    temporalSetValidateDefinition $value
    return $value
}

proc ::GX::temporalSetDescription {id} {
    set type [temporalSetField $id type ""]
    set label [temporalSetField $id label ""]
    set out "$id — $type — [temporalSetField $id source_dataset_id] / [temporalSetField $id temporal_variable]"
    if {$label ne ""} { append out " — $label" }
    return $out
}

proc ::GX::temporalSetWidgetRefresh {moduleId configKey widget} {
    variable moduleCfg
    variable temporalSetWidgetDisplay
    variable temporalSetWidgetPath
    set temporalSetWidgetPath($moduleId,$configKey) $widget
    if {![winfo exists $widget]} return
    set values {None}
    foreach id [temporalSetCompatibleIds $moduleId $configKey] { lappend values [temporalSetDescription $id] }
    $widget configure -values $values
    set current [expr {[info exists moduleCfg($moduleId,$configKey)] ? [string trim $moduleCfg($moduleId,$configKey)] : ""}]
    if {$current eq "" || $current ni [temporalSetCompatibleIds $moduleId $configKey]} { set temporalSetWidgetDisplay($moduleId,$configKey) None } else { set temporalSetWidgetDisplay($moduleId,$configKey) [temporalSetDescription $current] }
}


proc ::GX::temporalSetWidgetRefreshAll {} {
    variable temporalSetWidgetPath
    foreach key [array names temporalSetWidgetPath] {
        set widget $temporalSetWidgetPath($key)
        if {![winfo exists $widget]} {
            unset temporalSetWidgetPath($key)
            continue
        }
        lassign [split $key ,] moduleId configKey
        temporalSetWidgetRefresh $moduleId $configKey $widget
    }
}

proc ::GX::temporalSetWidgetChanged {moduleId configKey} {
    variable moduleCfg
    variable temporalSetWidgetDisplay
    if {[info exists temporalSetWidgetDisplay($moduleId,$configKey)]} {
        set value $temporalSetWidgetDisplay($moduleId,$configKey)
    } else {
        set value "None"
    }
    if {$value eq "None"} {
        set moduleCfg($moduleId,$configKey) ""
    } else {
        set moduleCfg($moduleId,$configKey) [lindex $value 0]
    }
    catch {refreshManifestPreview}
}

# Descriptor type=temporal_set is only a GUI selector. The semantic API above
# contains no Tk dependency and remains usable by batch/headless callers.
proc ::GX::standardConfigWidgetTemporalSet {parent moduleId configKey row} {
    variable temporalSetWidgetDisplay
    set type [string tolower [moduleConfigField $moduleId $configKey type string]]
    if {$type ne "temporal_set"} { return [::GX::standardConfigWidget_before_temporal_set_v1 $parent $moduleId $configKey $row] }
    ttk::label $parent.l$row -text [moduleConfigField $moduleId $configKey label $configKey]
    ttk::combobox $parent.w$row -textvariable ::GX::temporalSetWidgetDisplay($moduleId,$configKey) -state readonly -width 68 -postcommand [list ::GX::temporalSetWidgetRefresh $moduleId $configKey $parent.w$row]
    bind $parent.w$row <<ComboboxSelected>> [list ::GX::temporalSetWidgetChanged $moduleId $configKey]
    grid $parent.l$row -row $row -column 0 -sticky e -padx 4 -pady 2
    grid $parent.w$row -row $row -column 1 -sticky ew -padx 4 -pady 2
    temporalSetWidgetRefresh $moduleId $configKey $parent.w$row
}

proc ::GX::temporalSetRuntimeWriteMember {fd prefix member} {
    foreach field {index member_id label requested_time_start requested_time_end time_start time_end row_start row_count} { putKV $fd $field [dict get $member $field] }
}

# Standard runtime transports the authoritative definition plus compact derived
# resolution. Regular windows are intentionally not expanded into thousands of
# INI sections; consumers reconstruct each deterministic member by index.
proc ::GX::writeStandardRuntimeConfig_before_parallel_octave_binding_v1 {moduleId} {
    variable moduleCfg
    variable currentSession
    set path [::GX::writeStandardRuntimeConfig_before_temporal_set_v1 $moduleId]
    if {$currentSession eq "" || ![file isdirectory $currentSession] || ![file isfile $path]} { return $path }
    temporalSetLoadRegistry $currentSession
    set keys {}
    foreach key [moduleConfigKeys $moduleId] { if {[string tolower [moduleConfigField $moduleId $key type string]] eq "temporal_set"} { lappend keys $key } }
    if {![llength $keys]} { return $path }
    set fd [open $path a]; fconfigure $fd -encoding utf-8 -translation lf
    try {
        puts $fd "\n\[temporal_set_api\]"; putKV $fd api_version 1
        foreach key $keys {
            set setId [temporalSetValidateConfig $moduleId $key]
            puts $fd "\n\[temporal_set.$key\]"; putKV $fd api_version 1; putKV $fd id $setId
            if {$setId eq ""} { putKV $fd enabled 0; continue }
            putKV $fd enabled 1
            set info [temporalSetResolveInfo $setId]
            foreach field {type source_dataset_id temporal_variable_id temporal_variable temporal_unit parent_selection_id boundary_policy axis_kind axis_origin axis_step axis_count effective_row_start effective_row_count member_count generator_basis window_size step duration_unit partial_policy resolved_window_rows resolved_step_rows} {
                putKV $fd $field [expr {[dict exists $info $field] ? [dict get $info $field] : [temporalSetField $setId $field ""]}]
            }
            if {[dict get $info type] eq "segment_set"} {
                set index 0
                foreach member [dict get $info members] {
                    incr index
                    puts $fd "\n\[temporal_set.$key.member.$index\]"
                    temporalSetRuntimeWriteMember $fd "temporal_set.$key.member.$index" $member
                }
            }
        }
    } finally { close $fd }
    return $path
}

# Keep a manifest snapshot for session portability. The dedicated registry is
# authoritative once present in a session.
proc ::GX::manifestStringV2_before_project_api_v1 {} {
    set out [::GX::manifestStringV2_before_temporal_set_v1]
    append out "\n\[temporal_set_api\]\n"; appendKV out version 1; appendKV out ids [join [temporalSetIds] ";"]
    foreach id [temporalSetIds] {
        append out "\n\[temporal_set.$id\]\n"
        foreach field [temporalSetDefinitionFields] { appendKV out $field [temporalSetField $id $field ""] }
        if {[temporalSetField $id type ""] eq "segment_set"} {
            set segments [temporalSetOrderedSegments $id]; appendKV out segment_count [llength $segments]
            set index 0
            foreach segment $segments {
                incr index; append out "\n\[temporal_set.$id.segment.$index\]\n"
                foreach field {id order label start end} { appendKV out $field [dict get $segment $field] }
            }
        }
    }
    return $out
}

proc ::GX::loadManifestV2_before_project_api_v1 {path} {
    variable currentSession
    ::GX::loadManifestV2_before_temporal_set_v1 $path
    if {$currentSession ne "" && [file isfile [temporalSetRegistryPath $currentSession]]} { temporalSetLoadRegistry $currentSession; return }
    temporalSetClear
    set data [parseIni $path]
    set ids [expr {[dict exists $data temporal_set_api.ids] ? [splitList [dict get $data temporal_set_api.ids]] : {}}]
    foreach id $ids {
        set fields {}
        foreach field [temporalSetDefinitionFields] {
            set key "temporal_set.$id.$field"
            if {[dict exists $data $key]} { lappend fields $field [dict get $data $key] }
        }
        temporalSetRegisterRaw $id $fields
        if {[temporalSetField $id type ""] eq "segment_set"} {
            set count [expr {[dict exists $data temporal_set.$id.segment_count] ? [dict get $data temporal_set.$id.segment_count] : 0}]
            set segments {}
            for {set index 1} {$index <= $count} {incr index} {
                set prefix "temporal_set.$id.segment.$index."
                if {![dict exists $data ${prefix}id]} continue
                set segment [dict create]
                foreach field {id order label start end} { dict set segment $field [expr {[dict exists $data ${prefix}$field] ? [dict get $data ${prefix}$field] : ""}] }
                lappend segments $segment
            }
            temporalSetStoreSegments $id [temporalSetNormalizeSegments $id $segments]
        }
    }
    if {$currentSession ne "" && [file isdirectory $currentSession] && [llength [temporalSetIds]]} { temporalSetSaveRegistry $currentSession }
}

# A Dataset referenced by an authoritative Temporal Set cannot be deleted while
# the reference exists. Preventing the inconsistency is safer than leaving a
# persistent resource that only fails much later at analysis time.
proc ::GX::datasetDelete {session datasetId} {
    if {$::GX::DatasetPrivate::activeContext ne {}} {_datasetNamespaceRequireModuleWrite $session [dict get $::GX::DatasetPrivate::activeContext module_id] $datasetId}
    if {$session ne "" && [file isdirectory $session]} {
        temporalSetLoadRegistry $session
        set refs {}
        foreach id [temporalSetIds] { if {[temporalSetField $id source_dataset_id ""] eq $datasetId} { lappend refs $id } }
        if {[llength $refs]} { error "Dataset '$datasetId' is referenced by Temporal Set(s) [join $refs {, }]. Delete those Temporal Sets explicitly before deleting the Dataset." }
    }
    return [::GX::datasetDelete_before_temporal_set_v1 $session $datasetId]
}

proc ::GX::defaults_before_temporal_set_gui_v1 {} {
    variable temporalSetWidgetDisplay
    variable temporalSetWidgetPath
    ::GX::defaults_before_temporal_set_v1
    temporalSetClear
    array unset temporalSetWidgetDisplay *
    array unset temporalSetWidgetPath *
}
