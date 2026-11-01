# SPDX-License-Identifier: GPL-3.0-or-later
# Coordinate-frame conversion uses Native2D for complete geometry and the
# public Unit Registry for dimensional semantics. Source identities are frozen.
proc ::GX::CurveWorkbench::_coordinateUnits {record} {
    if {[dict exists $record coordinate_units]} {return [dict get $record coordinate_units]}
    if {[dict exists $record sketch_units]&&![dict exists $record working_unit]} {return [dict get $record sketch_units]}
    if {[dict exists $record working_unit]} {return [lrepeat 2 [dict get $record working_unit]]}
    set result {}
    foreach axis {x y} {
        set unit "";set variable [dict get $record $axis]
        if {[dict exists $record source_descriptor]} {
            foreach descriptor [dict get $record source_descriptor variables] {
                if {[dict get $descriptor variable_id] eq $variable} {set unit [dict get $descriptor unit];break}
            }
        } elseif {[dict get $record source] ne ""} {
            set unit [dict get [::GX::datasetVariableById [dict get $record source] $variable] unit]
        }
        lappend result $unit
    }
    return $result
}
rename ::GX::CurveWorkbench::_newRecord ::GX::CurveWorkbench::_newRecord_units_base
proc ::GX::CurveWorkbench::_newRecord {w name samples source x y filter value family order parents operations {representation linear}} {
    variable st
    set record [_newRecord_units_base $w $name $samples $source $x $y $filter $value $family $order $parents $operations $representation]
    if {$parents ne {}} {
        set units [_coordinateUnits [_record $w [lindex $parents 0]]]
        foreach parent $parents {if {[_coordinateUnits [_record $w $parent]] ne $units} {error "Derived geometry requires common coordinate units across its parents"}}
        dict set record coordinate_units $units
        if {[lindex $units 0] ne ""&&[lindex $units 0] eq [lindex $units 1]} {dict set record working_unit [lindex $units 0]}
        set record [_coordinateRetainFrame $w $record $parents]
    }
    return $record
}
rename ::GX::CurveWorkbench::_pointList ::GX::CurveWorkbench::_pointList_units_base
proc ::GX::CurveWorkbench::_pointList {w} {
    variable st
    _pointList_units_base $w
    if {$st($w,active) ne ""&&[winfo exists $w.leftScroll.viewport.content.numeric.leditX]} {
        foreach axis {x y} {
            set key [string toupper $axis]
            set unit [dict get [_coordinateAxis $w $st($w,active) $axis] display_unit]
            $w.leftScroll.viewport.content.numeric.ledit$key configure -text "$key ($unit)"
            $w.leftScroll.viewport.content.points heading $axis -text "$key ($unit)"
        }
        foreach column [$w.leftScroll.viewport.content.points cget -columns] {
            set minimum [expr {[font measure TkHeadingFont [$w.leftScroll.viewport.content.points heading $column -text]]+24}]
            $w.leftScroll.viewport.content.points column $column -minwidth $minimum
            if {[$w.leftScroll.viewport.content.points column $column -width]<$minimum} {$w.leftScroll.viewport.content.points column $column -width $minimum}
        }
        $w.leftScroll.viewport.content.interval.label configure -text "Select X interval ([dict get [_coordinateAxis $w $st($w,active) x] display_unit])"
    }
}
rename ::GX::CurveWorkbench::_restoreSnapshot ::GX::CurveWorkbench::_restoreSnapshot_units_base
proc ::GX::CurveWorkbench::_restoreSnapshot {w snapshot} {
    _restoreSnapshot_units_base $w $snapshot
    if {[dict exists $snapshot @cad point_selection]&&![dict exists $snapshot @cad semantic_selection]} {_restorePointSelectionDescriptor $w [dict get $snapshot @cad point_selection]}
}
proc ::GX::CurveWorkbench::_unitsOpen {w} {
    variable st
    set ids [dict keys $st($w,curves)];if {$ids eq {}} {error "Load or create geometry first"}
    set units [_coordinateUnits [_record $w [lindex $ids 0]]]
    set from [lindex $units 0];if {$from eq ""} {set from mm}
    foreach id $ids {
        foreach unit [_coordinateUnits [_record $w $id]] {if {$unit ne {}} {::GX::unitRegistryHomogeneousCoordinatePlan $unit $from}}
    }
    set fields [dict create source_unit {type string required 1 label {Current coordinate unit}} target_unit {type string required 1 label {New common working unit}} assume_undeclared [dict create type boolean label {Explicitly assume the current unit for undeclared coordinates}]]
    ::GX::uiFieldFormCreate $w.units "Convert whole workspace coordinates — scientific extent preserved" $fields [dict create source_unit $from target_unit $from assume_undeclared 0] [list ::GX::CurveWorkbench::_unitsApply $w $st($w,token) $ids] $w
}
proc ::GX::CurveWorkbench::_workingUnitCandidates {{source {}}} {
    set result {}
    foreach unit [lsort -unique [concat [::GX::unitSelectorCandidates] [list $source]]] {
        if {$unit eq {}} continue
        if {![catch {::GX::unitRegistryHomogeneousCoordinatePlan $unit [expr {$source eq {}?$unit:$source}]}]} {lappend result $unit}
    }
    return $result
}
proc ::GX::CurveWorkbench::_unitsApply {w token ids values} {
    variable st
    if {$token ne [::GX::interactiveDocumentSessionToken]||$token ne $st($w,token)} {error "Session lifetime changed; reopen the unit form"}
    if {$ids ne [dict keys $st($w,curves)]} {error "Workspace geometry changed; reopen the unit form"}
    _cancelGesture $w;_pointSyncApply $w
    set from [dict get $values source_unit];set to [dict get $values target_unit]
    set assume [::GX::uiFieldNormalize {type boolean} [dict get $values assume_undeclared]]
    set factor [dict get [::GX::unitRegistryHomogeneousCoordinatePlan $from $to] scale]
    set unknown {};set assumptionUpdates {}
    foreach id $ids {
        set record [_record $w $id];set undeclared 0
        if {[_coordinateSourceRelations $record] ne {}} {error {Normalize variable-specific coordinate relations through Dataset Transform before a proportional whole-frame conversion}}
        foreach unit [_coordinateUnits $record] {
            if {$unit eq ""} {
                if {!$assume} {error "[dict get $record name] has undeclared units; choose an explicit current-unit assumption"}
                set undeclared 1
            } elseif {$unit ne $from} {error "[dict get $record name] uses '$unit', not '$from'; normalize mixed source units explicitly before whole-workspace conversion"}
        }
        dict set unknown $id $undeclared
        if {$undeclared&&([dict get $record source] ne {}||[dict exists $record coordinate_snapshot])} {
            set assumptions [::GX::datasetPublicationV2DictDefault $record source_assumed_units {}]
            foreach axis {x y} unit [_coordinateUnits $record] {
                if {$unit ne {}} continue
                set variable [_coordinateSnapshotVariable $record $axis]
                if {[dict exists $assumptions $variable]&&[dict get $assumptions $variable] ne $from} {error {A prior explicit source-unit assumption must be preserved; normalize that frame explicitly}}
                dict set assumptions $variable $from
            }
            dict set assumptionUpdates $id $assumptions
        }
        if {[dict exists $record source_descriptor]} {
            foreach variable [dict get $record source_descriptor variables] {
                if {[dict get $variable variable_id] ni [list [dict get $record x] [dict get $record y]]} continue
                set nominal [::GX::unitRegistryDefinition [dict get $variable unit]]
                foreach field {canonical_unit to_canonical from_canonical} {
                    if {[dict exists $variable $field]&&[dict get $variable $field] ne ""&&[dict get $variable $field] ne [dict get $nominal $field]} {error "[dict get $record name] has variable-specific coordinate calibration; normalize it with Dataset Transform before a proportional whole-frame unit conversion"}
                }
            }
        }
    }
    set before [_snapshotIds $w $ids];
    set descriptor [_pointSelectionDescriptor $w]
    set changed 0
    try {
        dict for {image record} $st($w,images) {if {[dict get [::GX::Native2D::core image_get $st($w,scene) [dict get $record native]] length_unit] ne $from} {error {Reference images require the same declared workspace unit before conversion}}}
        if {[info exists st($w,coordinateFrameKey)]} {
            dict set st($w,coordinateFrameViews) $st($w,coordinateFrameKey) [dict create view [::GX::Native2D::core view_requested $st($w,scene)] presentation [::GX::Native2D::core presentation $st($w,scene)] coordinate_view $st($w,coordinateView)]
        }
        ::GX::Native2D::core rescale_coordinates $st($w,scene) $factor;set changed 1
        dict for {image record} $st($w,images) {set native [dict get $record native];set state [::GX::Native2D::core image_get $st($w,scene) $native];dict set state length_unit $to;::GX::Native2D::core image_update $st($w,scene) $native $state}
        set st($w,bridgeTolerance) [expr {$st($w,bridgeTolerance)*$factor}]
        foreach id $ids {
            set record [_record $w $id]
            if {[_bulkRecord $record]} {
                dict set record geometry_resource [::GX::interactiveDocumentNative2DStore $st($w,document) $st($w,scene) [dict get $record native]]
            } else {
                set edited [dict get $record edited]
                _syncSamples $w $id;set record [_record $w $id]
                dict set record edited $edited
            }
            dict set record working_unit $to
            dict unset record coordinate_units
            dict set record coordinate_relations {}
            if {[dict exists $assumptionUpdates $id]} {dict set record source_assumed_units [dict get $assumptionUpdates $id]}
            if {[dict exists $record bridge_descriptors]} {
                set bridges {}
                foreach bridge [dict get $record bridge_descriptors] {
                    foreach key {point start_derivative end_derivative} {if {[dict exists $bridge $key]} {dict set bridge $key [::GX::unitRegistryConvertValues $from $to [dict get $bridge $key]]}}
                    foreach key {start end} {if {[dict exists $bridge $key]} {foreach component {point derivative} {if {[dict exists $bridge $key $component]} {dict set bridge $key $component [::GX::unitRegistryConvertValues $from $to [dict get $bridge $key $component]]}}}}
                    if {[dict exists $bridge controls]} {set controls {};foreach point [dict get $bridge controls] {lappend controls [::GX::unitRegistryConvertValues $from $to $point]};dict set bridge controls $controls}
                    if {[dict exists $bridge tolerance]} {dict set bridge tolerance [expr {[dict get $bridge tolerance]*$factor}]}
                    lappend bridges $bridge
                }
                dict set record bridge_descriptors $bridges
            }
            dict lappend record coordinate_conversions [dict create source_unit $from target_unit $to factor $factor assumed_undeclared [dict get $unknown $id] physical_scale 0]
            dict set st($w,curves) $id $record
        }
        if {[info exists st($w,seriesContainers)]} {dict for {container record} $st($w,seriesContainers) {dict set st($w,seriesContainers) $container [::GX::native2DSeriesRescaleRecord $record $factor]}}
        set regions {}
        foreach region [dict get $descriptor regions] {dict set region bounds [::GX::unitRegistryConvertValues $from $to [dict get $region bounds]];lappend regions $region}
        dict set descriptor regions $regions
        _coordinateRescaleView $w $factor
        dict set st($w,coordinateConfiguration) x_unit $to
        dict set st($w,coordinateConfiguration) y_unit $to
        set st($w,sketchUnit) $to
        set st($w,coordinateFrameKey) [_coordinateFrameKey [_record $w $st($w,active)]]
        _selectionScene $w;_restorePointSelectionDescriptor $w $descriptor
        _history $w $before $ids
    } on error {message options} {

        if {$changed} {
            if {[catch {_restoreSnapshot $w $before;_curveList $w;_pointList $w;_draw $w} rollback]} {append message "; workspace rollback failed: $rollback"}
        }
        return -options $options $message
    }
    set st($w,status) "Converted whole workspace from $from to $to; scientific extent and original source identities preserved. One Undo restores the prior coordinate frame."
    return [dict create source_unit $from target_unit $to factor $factor object_count [llength $ids] physical_scale 0]
}
proc ::GX::CurveWorkbench::_buildUnits {w} {
    ttk::button $w.cad.declareaxes -text "Declare axes…" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_coordinateDeclareOpen $w]]
    pack $w.cad.declareaxes -side left -padx 3
    ttk::button $w.cad.axisunits -text "Axis display units…" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_coordinateOpen $w]]
    ttk::button $w.cad.datasetcoordinates -text "Dataset coordinates…" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_coordinateDatasetOpen $w]]
    pack $w.cad.axisunits $w.cad.datasetcoordinates -side left -padx 3
    ttk::button $w.cad.units -text "Working units…" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_unitsOpen $w]]
    pack $w.cad.units -side left -padx 3
}
