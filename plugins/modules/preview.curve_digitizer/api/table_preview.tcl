# SPDX-License-Identifier: GPL-3.0-or-later
# Canonical Data GUI: source-bound, read-only, bounded public Dataset pages.
# No private CSV reader, Dataset write or numeric alteration. CORE Bridge 022
# supplies persistent cache pages and off-UI preparation.
namespace eval ::GX::DigitizerFamilyPreview {
    variable tableState {}
}
proc ::GX::DigitizerFamilyPreview::_tableDesign {} {
    variable root
    return [::GX::viewerGuiDesignRead [file join $root gui table_design.tcldict]]
}
proc ::GX::DigitizerFamilyPreview::_tableMount {host context} {
    variable tableState
    ::GX::viewerGuiDesignPreviewMount [_tableDesign] $host [list ::GX::DigitizerFamilyPreview::dispatch]
    # Passive mounting must NOT read canonical scientific rows.
    dict set tableState $host [dict create start 0 page_size 50 loaded 0 has_next 0]
    ::GX::datasetPreviewGuiControlSet $host information {Two views: Scientific values and Point traceability. Select Load first page.}
}
proc ::GX::DigitizerFamilyPreview::_tableNumber {value precision} {
    if {![string is double -strict $value] || [catch {expr {abs(double($value))<Inf}} finite] || !$finite} {
        return $value
    }
    switch -- $precision {
        {6 digits} {return [format %.6g [expr {double($value)}]]}
        {10 digits} {return [format %.10g [expr {double($value)}]]}
        {Full precision} {return $value}
        default {error {Unknown numeric precision}}
    }
}
# Point ID belongs to the authenticated publication metadata and canonical
# Variable Schema v3, not the narrower Curve Schema v1 semantic-role dictionary.
# Never infer it from column position, a guessed variable name or raw CSV.
proc ::GX::DigitizerFamilyPreview::_tablePointIdColumn {context columns} {
    if {![dict exists $context metadata]} {return {}}
    set metadata [dict get $context metadata]
    set key curve_digitizer.curve_column.point_id
    if {![dict exists $metadata $key]} {return {}}
    set id [dict get $metadata $key]
    if {$id eq {}} {error {Published Point ID mapping is empty}}
    if {[dict exists $columns point_id] && [dict get $columns point_id] ne $id} {
        error {Conflicting Point ID mappings}
    }
    if {$id in [dict values [dict remove $columns point_id]]} {
        error {Point ID aliases a scientific role variable}
    }
    set candidate {}
    foreach variable [dict get $context variables] {
        if {[dict get $variable variable_id] ne $id} continue
        if {$candidate ne {}} {error {Duplicate Point ID variable in canonical schema}}
        set candidate $variable
    }
    if {$candidate eq {}} {error {Published Point ID variable missing from canonical Variable Schema}}
    set xVariableId [dict get $columns x]
    set xDimension {}
    foreach variable [dict get $context variables] {
        if {[dict get $variable variable_id] eq $xVariableId} {
            set xDimension [dict get $variable dimension_ids]
            break
        }
    }
    if {$xDimension eq {} ||
        [dict get $candidate rank]!=1 ||
        [dict get $candidate dtype] ni {string text} ||
        [dict get $candidate dimension_ids] ne $xDimension} {
        error {Published Point ID variable has incompatible canonical schema}
    }
    if {[dict exists $candidate enabled] && ![dict get $candidate enabled]} {
        error {Published Point ID variable is disabled}
    }
    return $id
}

# Optional numerical uncertainty fields are discovered by their validated
# canonical V3 semantic roles, never by physical CSV column number.
proc ::GX::DigitizerFamilyPreview::_tableUncertaintyColumns {context columns} {
    set expected {uncertainty_standard_x uncertainty_standard_y uncertainty_covariance_xy}
    set result {}
    set xUnit {};set yUnit {};set xDim {}
    set reserved [dict values $columns]
    foreach variable [dict get $context variables] {
        set id [dict get $variable variable_id]
        if {$id eq [dict get $columns x]} {
            set xUnit [dict get $variable unit]
            set xDim [dict get $variable dimension_ids]
        }
        if {$id eq [dict get $columns y]} {set yUnit [dict get $variable unit]}
        set role [expr {[dict exists $variable semantic_role] ? [dict get $variable semantic_role] : {}}]
        if {$role ni $expected} continue
        if {[dict exists $result $role] || $id in $reserved ||
            [dict get $variable rank]!=1 ||
            [dict get $variable dimension_ids] ne $xDim && $xDim ne {} ||
            [dict get $variable dtype] ni {float32 float64} ||
            ([dict exists $variable enabled] && ![dict get $variable enabled])} {
            error {Invalid canonical uncertainty Variable Schema}
        }
        dict set result $role [dict create id $id unit [dict get $variable unit] dimension [dict get $variable dimension_ids]]
    }
    if {![dict size $result]} {return {}}
    if {[dict size $result]!=3} {error {Incomplete three-column uncertainty publication}}
    foreach role $expected {
        if {![dict exists $result $role]} {error {Missing canonical uncertainty role}}
    }
    # Validate all roles against the declared scientific dimensions and units.
    if {$xDim eq {}} {error {Missing scientific X dimension}}
    if {[dict get $result uncertainty_standard_x dimension] ne $xDim ||
        [dict get $result uncertainty_standard_y dimension] ne $xDim ||
        [dict get $result uncertainty_covariance_xy dimension] ne $xDim ||
        [dict get $result uncertainty_standard_x unit] ne $xUnit ||
        [dict get $result uncertainty_standard_y unit] ne $yUnit ||
        [dict get $result uncertainty_covariance_xy unit] ne "$xUnit*$yUnit"} {
        error {Incompatible published uncertainty units or dimensions}
    }
    return [dict create sigma_x [dict get $result uncertainty_standard_x id] \
                        sigma_y [dict get $result uncertainty_standard_y id] \
                        covariance_xy [dict get $result uncertainty_covariance_xy id]]
}

# Separate publications do not carry a per-row calibration_key: their
# calibration identity is in authenticated canonical producer metadata.
# Combined publications MUST continue to use the actual per-row key.
proc ::GX::DigitizerFamilyPreview::_tableSeparateCalibration {context schema} {
    if {[dict get $schema publication_calibration_mode] ne {separate}} {return {}}
    if {![dict exists $context metadata]} {return [dict create id {Not published} label {Single calibration}]}
    set md [dict get $context metadata]
    set id [expr {[dict exists $md curve_digitizer.calibration_id] ?
        [dict get $md curve_digitizer.calibration_id] : {}}]
    if {$id eq {}} {
        return [dict create id {Not published} label {Single calibration}]
    }
    if {![regexp {^cal_[a-f0-9]{24}$} $id]} {
        error {Published separate Calibration ID is malformed}
    }
    set label {Single calibration}
    # A separate Dataset may retain one or more source realizations in
    # versioned metadata, but its selected calibration must be unambiguous.
    set active [expr {[dict exists $md curve_digitizer.active_measurement_id] ?
        [dict get $md curve_digitizer.active_measurement_id] : {}}]
    if {[dict exists $md curve_digitizer.measurement.0.calibration_id]} {
        set registered [dict get $md curve_digitizer.measurement.0.calibration_id]
        if {$registered ne $id} {error {Published Calibration ID disagrees with measurement metadata}}
        if {$active ne {} && [dict exists $md curve_digitizer.measurement.0.measurement_id] &&
            [dict get $md curve_digitizer.measurement.0.measurement_id] ne $active} {
            error {Selected Calibration measurement identity is inconsistent}
        }
        if {[dict exists $md curve_digitizer.measurement.0.label]} {
            set label [dict get $md curve_digitizer.measurement.0.label]
        }
    }
    return [dict create id $id label $label]
}

proc ::GX::DigitizerFamilyPreview::_cachedPageReady {host generation requestedStart response} {
    variable tableState
    if {![dict exists $tableState $host]} {return}
    set state [dict get $tableState $host]
    if {![dict exists $state generation] || [dict get $state generation]!=$generation ||
        [dict get $state pending_start] != $requestedStart} {return}
    if {[dict get $response status] ne {ready}} {
        catch {::GX::datasetPreviewGuiControlSet $host table_notice "Cached page loading failed: [dict get $response message]"}
        return
    }
    if {[catch {_tableRead $host $requestedStart [dict get $response page]} reason]} {
        catch {::GX::datasetPreviewGuiControlSet $host table_notice "Cached page display failed: $reason"}
    }
}
proc ::GX::DigitizerFamilyPreview::_tableRead {host requestedStart {providedPage {}}} {
    variable tableState
    if {![dict exists $tableState $host]} {error {Canonical table host is unavailable}}
    set state [dict get $tableState $host]
    set count [dict get $state page_size]
    if {![string is entier -strict $requestedStart] || $requestedStart<0 || $requestedStart%$count!=0} {
        error {Invalid canonical page offset}
    }
    set context [::GX::datasetPreviewGuiContext $host]
    set schema [_schema $context]
    set cols [dict get $schema columns]
    set separateCalibration [_tableSeparateCalibration $context $schema]
    set roles {curve_key curve_name point_order x y y_axis_id calibration_key calibration_name raster_x raster_y point_id}
    set pointId [_tablePointIdColumn $context $cols]
    set uncertainty [_tableUncertaintyColumns $context $cols]
    foreach role {sigma_x sigma_y covariance_xy} {
        if {[dict exists $uncertainty $role]} {lappend roles $role}
    }
    set actualRoles {};set variableIds {}
    foreach role $roles {
        if {$role eq {point_id}} {
            if {$pointId eq {}} continue
            lappend actualRoles $role
            lappend variableIds $pointId
            continue
        }
        if {$role in {sigma_x sigma_y covariance_xy}} {
            lappend actualRoles $role
            lappend variableIds [dict get $uncertainty $role]
            continue
        }
        if {![dict exists $cols $role]} continue
        lappend actualRoles $role
        lappend variableIds [dict get $cols $role]
    }
    # This disposable, source-bound page memo has at most two 50-row pages.
    # It is not CORE's durable Preview/Plot cache; no source authority is copied.
    set identity [list [dict get $context dataset_id] [dict get $context token] \
                       [dict get $context canonical_identity] $variableIds]
    set page $providedPage
    if {$page eq {} && [dict exists $state pages $requestedStart] &&
        [dict exists $state source_identity] &&
        [dict get $state source_identity] eq $identity} {
        set page [dict get $state pages $requestedStart]
    }
    if {$page eq {}} {
        if {[llength [info commands ::GX::datasetPreviewGuiCachedPageRequest]]} {
            set generation [expr {[dict exists $state generation] ? [dict get $state generation]+1 : 1}]
            dict set state generation $generation
            dict set state pending_start $requestedStart
            dict set tableState $host $state
            ::GX::datasetPreviewGuiControlSet $host table_notice "Reading retained canonical page at row [expr {$requestedStart+1}]..."
            return [::GX::datasetPreviewGuiCachedPageRequest $host \
                [dict create start $requestedStart count $count variable_ids $variableIds] \
                [list ::GX::DigitizerFamilyPreview::_cachedPageReady $host $generation $requestedStart]]
        }
        # Only the isolated legacy regression fixtures permit the old
        # direct page path; production must use the CORE verified cache.
        if {![info exists ::env(GXTXT_PREVIEW_TEST_LEGACY)]} {
            error {CORE Preview Cache Bridge 022 is missing: canonical page cannot be synchronously reread}
        }
        set page [::GX::datasetPreviewPage [dict get $context session] [dict get $context dataset_id] \
            [dict create start $requestedStart count $count variable_ids $variableIds]]
    }
    if {![dict get $page available]} {error {Canonical Dataset page is unavailable}}
    set n [dict get $page count]
    if {$n!=[llength [dict get $page rows]] || $n!=[llength [dict get $page source_rows]]} {
        error {Canonical row count or row identity mismatch}
    }
    if {$n==0 && [dict get $page has_next]} {error {Canonical paging made no progress}}
    # The public host must still own this exact Dataset, Session, and source revision.
    set current [::GX::datasetPreviewGuiContext $host]
    foreach key {dataset_id session token canonical_identity} {
        if {[dict get $current $key] ne [dict get $context $key]} {
            error {Canonical Dataset or Session changed while reading}
        }
    }
    set precision [::GX::datasetPreviewGuiControlGet $host precision]
    set numeric {};set technical {}
    foreach raw [dict get $page rows] sourceRow [dict get $page source_rows] {
        if {[llength $raw]!=[llength $actualRoles]} {error {Incomplete canonical row projection}}
        set record {}
        foreach role $actualRoles value $raw {dict set record $role $value}
        set curve [dict get $record curve_name]
        set axis [expr {[dict exists $record y_axis_id] ? [string toupper [dict get $record y_axis_id]] : {Y1}}]
        if {$axis ni {Y1 Y2}} {error {Unknown published logical Y axis}}
        set x [dict get $record x]
        set y [dict get $record y]
        set ordered [dict get $record point_order]
        if {![string is entier -strict $ordered] || $ordered<0 ||
            ![string is double -strict $x] || ![string is double -strict $y]} {
            error {Invalid canonical scientific row}
        }
        if {[dict get $schema publication_calibration_mode] eq {combined}} {
            if {![dict exists $record calibration_key] || ![dict exists $record calibration_name]} {
                error {Combined publication lacks per-row calibration identity}
            }
            set calibrationName [dict get $record calibration_name]
            set calibrationId [dict get $record calibration_key]
        } else {
            set calibrationName [dict get $separateCalibration label]
            set calibrationId [dict get $separateCalibration id]
        }
        set uncertainties {}
        foreach name {sigma_x sigma_y covariance_xy} {
            if {[dict exists $record $name]} {
                lappend uncertainties [_tableNumber [dict get $record $name] $precision]
            } else {
                lappend uncertainties {Not published}
            }
        }
        lappend numeric [list $sourceRow $curve $ordered [_tableNumber $x $precision] [_tableNumber $y $precision] $axis $calibrationName {*}$uncertainties]
        set cx [expr {[dict exists $record raster_x] ? [_tableNumber [dict get $record raster_x] $precision] : {Not published}}]
        set cy [expr {[dict exists $record raster_y] ? [_tableNumber [dict get $record raster_y] $precision] : {Not published}}]
        lappend technical [list $sourceRow [dict get $record curve_key] \
            [expr {[dict exists $record point_id] ? [dict get $record point_id] : {Not published}}] $calibrationId $cx $cy]
    }
    ::GX::datasetPreviewGuiTableSet $host science_table $numeric
    ::GX::datasetPreviewGuiTableSet $host provenance_table $technical
    set xUnit {};set yUnit {}
    if {[dict exists $context variables]} {
        foreach variable [dict get $context variables] {
            if {[dict get $variable variable_id] eq [dict get $cols x]} {set xUnit [dict get $variable unit]}
            if {[dict get $variable variable_id] eq [dict get $cols y]} {set yUnit [dict get $variable unit]}
        }
    }
    set range [expr {$n>0 ? "[lindex [dict get $page source_rows] 0]–[lindex [dict get $page source_rows] end]" : {empty}}]
    set uncertaintyNote {No published uncertainty}
    if {[dict size $uncertainty]} {
        set uncertaintyNote "Sigma X ($xUnit), Sigma Y ($yUnit), Cov XY ($xUnit*$yUnit)"
    }
    ::GX::datasetPreviewGuiControlSet $host information \
        "Canonical rows $range. X: [dict get $cols x] ($xUnit); Y: [dict get $cols y] ($yUnit). $uncertaintyNote. Stored values unchanged."
    ::GX::datasetPreviewGuiControlSet $host table_notice \
        "Rows $n / page $count. Precision: $precision. Next: [expr {[dict get $page has_next] ? {available} : {end}}]. Ctrl+C copies selected table rows."
    dict set state start $requestedStart
    dict set state loaded 1
    dict set state has_next [dict get $page has_next]
    if {![dict exists $state source_identity] ||
        [dict get $state source_identity] ne $identity} {
        dict set state pages {}
    }
    dict set state source_identity $identity
    dict set state pages $requestedStart $page
    # Bounded retention of at most two original canonical pages.
    foreach previous [dict keys [dict get $state pages]] {
        if {$previous!=$requestedStart &&
            [dict size [dict get $state pages]]>2} {
            dict unset state pages $previous
        }
    }
    dict set tableState $host $state
    return [dict create status ready displayed $n start $requestedStart has_next [dict get $page has_next]]
}
proc ::GX::DigitizerFamilyPreview::_tableDispatch {host event} {
    variable tableState
    set action [dict get $event control_id]
    if {![dict exists $tableState $host]} {error {Canonical table host is unavailable}}
    set state [dict get $tableState $host]
    switch -- $action {
        first {return [_tableRead $host 0]}
        previous {
            if {![dict get $state loaded] || [dict get $state start]==0} return
            return [_tableRead $host [expr {[dict get $state start]-[dict get $state page_size]}]]
        }
        next {
            if {![dict get $state loaded] || ![dict get $state has_next]} return
            return [_tableRead $host [expr {[dict get $state start]+[dict get $state page_size]}]]
        }
        precision {
            if {![dict get $state loaded]} return
            return [_tableRead $host [dict get $state start]]
        }
        default {return}
    }
}
