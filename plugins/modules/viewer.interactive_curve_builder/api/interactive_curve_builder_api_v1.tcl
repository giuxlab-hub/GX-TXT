# GX-TXT Interactive Curve Builder API v1
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::InteractiveCurveBuilder {
    variable version 1.2.0
    variable windows
    variable ui
}

proc ::GX::InteractiveCurveBuilder::_numeric {} {
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    foreach capability {interpolation linear_regression polynomial_fit} {
        ::GX::NumericAPIv1::requireCapability $capability
    }
}
proc ::GX::InteractiveCurveBuilder::_session {} {
    return [::GX::sessionInspectionCurrentSession]
}
proc ::GX::InteractiveCurveBuilder::_finite {value label} {
    if {![string is double -strict $value] || [catch {set n [expr {double($value)}]}] || $n != $n || abs($n) == Inf} {
        error "$label must be a finite number."
    }
    return $n
}
proc ::GX::InteractiveCurveBuilder::_var {datasetId id} {
    if {$id eq ""} {return [dict create]}
    set v [::GX::datasetVariableById $datasetId $id]
    if {[dict exists $v enabled] && ![dict get $v enabled]} {error "Dataset variable '$id' is disabled."}
    return $v
}
proc ::GX::InteractiveCurveBuilder::datasetIds {} {
    set out {}
    foreach id [::GX::sessionInspectionDatasetIds] {
        if {[catch {set vars [::GX::datasetVariableSchema $id]}]} continue
        set numeric 0
        foreach v $vars {
            if {[dict get $v enabled] && [dict get $v value_kind] eq "number" && (![dict exists $v rank] || [dict get $v rank] == 1)} {incr numeric}
        }
        if {$numeric >= 2} {lappend out $id}
    }
    return [lsort -dictionary $out]
}
proc ::GX::InteractiveCurveBuilder::variables {datasetId} {
    set result [dict create numeric {} family {}]
    foreach v [::GX::datasetVariableSchema $datasetId] {
        if {![dict get $v enabled]} continue
        set id [dict get $v variable_id]
        if {[dict exists $v rank] && [dict get $v rank] != 1} continue
        if {[dict get $v value_kind] eq "number"} {dict lappend result numeric $id}
        dict lappend result family $id
    }
    return $result
}

# Return exact canonical source row ordinals. The family value is an exact
# member key, including text; no numeric conversion or Cartesian expansion.
proc ::GX::InteractiveCurveBuilder::sourceRows {datasetId xId yId {zId ""} {tId ""} {familyId ""} {familyValue ""} {selectionId ""} {options {}}} {
    set session [_session]
    if {$xId eq "" || $yId eq ""} {error "Choose X and Y variables."}
    foreach id [list $xId $yId $zId $tId] {
        if {$id eq ""} continue
        set v [_var $datasetId $id]
        if {[dict get $v value_kind] ne "number"} {error "Variable '$id' must be numeric."}
    }
    if {$familyId ne ""} {_var $datasetId $familyId}
    set memberId [::GX::datasetPublicationV2DictDefault $options member_id {}]
    set memberValue [::GX::datasetPublicationV2DictDefault $options member_value {}]
    set memberEnabled [::GX::datasetPublicationV2DictDefault $options member_enabled 0]
    set familyEnabled [::GX::datasetPublicationV2DictDefault $options family_enabled [expr {$familyId ne {} && $familyValue ne {}}]]
    foreach key [dict keys $options] {if {$key ni {member_id member_value member_enabled family_enabled progress}} {error "Unknown source-row option $key"}}
    if {$memberId ne {}} {_var $datasetId $memberId}
    foreach id [list $familyId $memberId] {if {$id ne {} && [dict get [::GX::datasetVariableV3ById $datasetId $id] rank]!=1} {error {Family/Member variables must have rank one}}}
    if {($memberEnabled && $memberId eq {}) || ($familyEnabled && $familyId eq {})} {error {An enabled exact filter needs its canonical variable}}
    set ids [lsort -unique [concat [list $xId $yId] [expr {$zId eq "" ? {} : [list $zId]}] [expr {$tId eq "" ? {} : [list $tId]}] [expr {$familyId eq "" ? {} : [list $familyId]}] [expr {$memberId eq {} ? {} : [list $memberId]}]]]
    if {$options ne {}} {set identity [::GX::curveSourceDatasetIdentity $session $datasetId];set fingerprint [dict get $identity sha256]}
    set acceptedRows [dict create]
    if {$selectionId ne ""} {
        set selection [::GX::sessionInspectionSelection $selectionId $session]
        if {![dict exists $selection source_dataset_id] || [dict get $selection source_dataset_id] ne $datasetId} {
            error "Selection '$selectionId' belongs to another Dataset."
        }
        if {![dict exists $selection x_variable_id] || [dict get $selection x_variable_id] ne $xId} {
            error "Selection '$selectionId' uses a different canonical X variable."
        }
        set bounds [dict create x_min [dict get $selection x_min] x_max [dict get $selection x_max]]
        if {[dict get $selection type] eq "rectangle"} {
            if {[dict get $selection y_variable_id] ne $yId} {error "Selection '$selectionId' uses a different canonical Y variable."}
            dict set bounds y_min [dict get $selection y_min]
            dict set bounds y_max [dict get $selection y_max]
        } elseif {[dict get $selection type] ne "x_range"} {error "Selection '$selectionId' is not an X range or rectangle."}
        foreach row [::GX::GraphSelectionAPIv1::selectRegionRows $session $datasetId $xId $yId {} $bounds] {dict set acceptedRows $row 1}
    }
    set stream [::GX::tableStreamOpenDataset $session $datasetId $ids 4096]
    set rows {}
    try {
        while {1} {
            set chunk [::GX::tableStreamNext $stream]
            set columns [dict get $chunk values]
            for {set i 0} {$i < [dict get $chunk nrows]} {incr i} {
                set ordinal [expr {[dict get $chunk offset]+$i}]
                if {$selectionId ne "" && ![dict exists $acceptedRows $ordinal]} continue
                set member [expr {$familyId eq "" ? "" : [lindex [dict get $columns $familyId] $i]}]
                if {$familyEnabled && $member ne $familyValue} continue
                set memberKey [expr {$memberId eq {} ? {} : [lindex [dict get $columns $memberId] $i]}]
                if {$memberEnabled && $memberKey ne $memberValue} continue
                set row [dict create dataset_id $datasetId row $ordinal x_id $xId y_id $yId z_id $zId t_id $tId family_id $familyId family_value $member]
                if {$options ne {}} {
                    dict set row member_id $memberId;dict set row member_value $memberKey;dict set row source_sha256 $fingerprint
                    dict set row source_schema_identity [dict get $identity schema_identity]
                    dict set row filter_binding [dict create family_id $familyId family_enabled $familyEnabled family_value $familyValue member_id $memberId member_enabled $memberEnabled member_value $memberValue selection_id $selectionId combination AND]
                }
                set valid 1
                foreach key {x y z t} id [list $xId $yId $zId $tId] {
                    if {$id eq ""} continue
                    set value [lindex [dict get $columns $id] $i]
                    if {[catch {set value [_finite $value "Source $datasetId row [dict get $row row] $key"]}]} {set valid 0; break}
                    dict set row $key $value
                }
                if {$valid} {lappend rows $row}
            }
            if {[::GX::datasetPublicationV2DictDefault $options progress {}] ne {}} {::GX::curveSourceCooperativeBoundary [dict get $options progress] [dict create stage source_rows completed_rows [expr {[dict get $chunk offset]+[dict get $chunk nrows]}] total_rows -1]}
            if {[dict get $chunk eof]} break
        }
    } finally {::GX::tableStreamClose $stream}
    return $rows
}
proc ::GX::InteractiveCurveBuilder::familyValues {datasetId familyId} {
    set stream [::GX::tableStreamOpenDataset [_session] $datasetId [list $familyId] 4096]
    set values [dict create]
    try {
        while {1} {
            set chunk [::GX::tableStreamNext $stream]
            foreach value [dict get [dict get $chunk values] $familyId] {dict set values $value 1}
            if {[dict get $chunk eof]} break
        }
    } finally {::GX::tableStreamClose $stream}
    return [lsort -dictionary [dict keys $values]]
}
proc ::GX::InteractiveCurveBuilder::_byX {a b} {
    set av [dict get $a x]; set bv [dict get $b x]
    return [expr {$av < $bv ? -1 : $av > $bv ? 1 : 0}]
}
proc ::GX::InteractiveCurveBuilder::_byT {a b} {
    set av [dict get $a t]; set bv [dict get $b t]
    return [expr {$av < $bv ? -1 : $av > $bv ? 1 : 0}]
}
proc ::GX::InteractiveCurveBuilder::_units {rows mode parameterMode} {
    set first [lindex $rows 0]
    set units [dict create]
    foreach axis {x y z t} {
        if {$axis eq "z" && $mode ne "3d"} continue
        if {$axis eq "t" && ($mode ne "3d" || $parameterMode ne "variable")} continue
        set id [dict get $first ${axis}_id]
        if {$id eq ""} {error "Missing $axis variable."}
        dict set units $axis [dict get [_var [dict get $first dataset_id] $id] unit]
    }
    foreach row $rows {
        foreach axis [dict keys $units] {
            set id [dict get $row ${axis}_id]
            if {$id eq "" || [dict get [_var [dict get $row dataset_id] $id] unit] ne [dict get $units $axis]} {
                error "Selected source curves have incompatible $axis units. Convert them to common units first."
            }
        }
    }
    if {$mode eq "3d" && $parameterMode eq "arc_length"} {
        if {[dict get $units x] ne [dict get $units y] || [dict get $units x] ne [dict get $units z]} {
            error "Arc length requires X, Y and Z to share one unit."
        }
        dict set units t [dict get $units x]
    }
    return $units
}
proc ::GX::InteractiveCurveBuilder::_grid {nodes count} {
    if {![string is integer -strict $count] || $count < 2 || $count > 100000} {error "Target sample count must be 2–100000."}
    set lo [lindex $nodes 0]; set hi [lindex $nodes end]
    set grid $nodes
    for {set i 0} {$i < $count} {incr i} {
        lappend grid [expr {$lo+($hi-$lo)*double($i)/($count-1)}]
    }
    return [lsort -real -unique $grid]
}
proc ::GX::InteractiveCurveBuilder::_axisEvaluate {nodes values target method degree} {
    _numeric
    if {$method in {nearest linear cubic spline pchip}} {
        return [dict get [::GX::NumericAPIv1::interpolate $nodes $values $target [dict create method $method extrapolation error]] yq]
    }
    if {$method eq "line"} {
        set fit [::GX::NumericAPIv1::linearRegression $nodes $values]
        set polynomial [dict create coefficients [list [dict get $fit slope] [dict get $fit intercept]]]
    } elseif {$method eq "polynomial"} {
        set fit [::GX::NumericAPIv1::polynomialFit $nodes $values $degree]
        set polynomial $fit
    } else {error "Unknown curve method '$method'."}
    set predicted [dict get [::GX::NumericAPIv1::polynomialEvaluate $polynomial $target] yq]
    set observedPredicted [dict get [::GX::NumericAPIv1::polynomialEvaluate $polynomial $nodes] yq]
    set diagnostics [::GX::NumericAPIv1::residualMetrics $values $observedPredicted]
    return [dict create values $predicted fit $fit diagnostics $diagnostics]
}

# The returned preview is immutable input to publish. It records every selected
# canonical row and variable binding in provenance, including multi-Dataset sets.
proc ::GX::InteractiveCurveBuilder::evaluate {rows mode method {degree 2} {samples 101} {parameterMode variable} {options {}}} {
    if {$mode ni {2d 3d}} {error "Curve mode must be 2d or 3d."}
    if {$method ni {nearest linear cubic spline pchip line polynomial}} {error "Unsupported curve method '$method'."}
    if {$mode eq "3d" && $parameterMode ni {variable arc_length}} {error "3-D parameter mode must be variable or arc_length."}
    if {[llength $rows] < 2} {error "Select at least two source points."}
    if {$options ne {}} {
        set identities {}
        foreach row $rows {
            set ds [dict get $row dataset_id]
            if {![dict exists $row source_sha256]} continue
            if {![dict exists $identities $ds]} {dict set identities $ds [::GX::curveSourceDatasetIdentity [_session] $ds]}
            set identity [dict get $identities $ds]
            if {[dict get $row source_sha256] ne [dict get $identity sha256] || ([dict exists $row source_schema_identity] && [dict get $row source_schema_identity] ne [dict get $identity schema_identity])} {error {Builder source or scientific schema changed; reload exact source rows before Preview}}
        }
    }
    if {$method eq "polynomial" && (![string is integer -strict $degree] || $degree < 0 || $degree >= [llength $rows])} {
        error "Polynomial degree must be between 0 and one less than the selected point count."
    }
    set units [_units $rows $mode $parameterMode]
    set orderReceipt {}
    if {[::GX::datasetPublicationV2DictDefault $options auto_order 0]} {
        set orderReceipt [::GX::datasetPublicationV2DictDefault $options ordering_receipt {}]
        if {$orderReceipt eq {}} {set orderReceipt [ordering $rows $mode $parameterMode]}
        if {[dict get $orderReceipt original_rows] ne $rows || [dict get $orderReceipt mode] ne $mode || [dict get $orderReceipt parameter_mode] ne $parameterMode} {error {Ordering receipt is stale; review again}}
        if {[dict get $orderReceipt review_required] && ![::GX::datasetPublicationV2DictDefault $options reviewed 0]} {error {Review original/candidate order before using the proposed sequence}}
        if {[llength [dict get $orderReceipt segment_starts]]>1} {error {Disconnected source segments cannot be interpolated as one curve; choose one segment}}
        set ordered [dict get $orderReceipt ordered_rows]
    } elseif {$mode eq "2d"} {set ordered [lsort -command ::GX::InteractiveCurveBuilder::_byX $rows]} elseif {$parameterMode eq "variable"} {
        set ordered [lsort -command ::GX::InteractiveCurveBuilder::_byT $rows]
    } else {set ordered $rows}
    set planarGeometry [expr {$mode eq "2d" && $orderReceipt ne {} && [dict get $orderReceipt policy] eq "geometry_auto"}]
    if {$planarGeometry} {dict set units t [dict get $units x]}
    set nodes {}; set ys {}; set xs {}; set zs {}; set previous {}
    foreach row $ordered {
        if {$mode eq "2d" && !$planarGeometry} {set p [dict get $row x]} elseif {$parameterMode eq "variable"} {set p [dict get $row t]} else {
            if {$previous eq ""} {set p 0.0} else {
                set sum 0.0
                foreach axis [expr {$mode eq "3d" ? {x y z} : {x y}}] {set delta [expr {[dict get $row $axis]-[dict get $previous $axis]}]; set sum [expr {$sum+$delta*$delta}]}
                set p [expr {[lindex $nodes end]+sqrt($sum)}]
            }
        }
        if {[llength $nodes] && $p <= [lindex $nodes end]} {error "Selected independent coordinates must be strictly increasing; duplicate rows, X, t or zero-length arc segments are not valid."}
        lappend nodes $p; lappend ys [dict get $row y]
        if {$mode eq "3d" || $planarGeometry} {lappend xs [dict get $row x]}
        if {$mode eq "3d"} {lappend zs [dict get $row z]}
        set previous $row
    }
    set target [_grid $nodes $samples]
    set result [dict create mode $mode method $method degree $degree samples $samples parameter_mode $parameterMode target $target units $units source_rows $ordered source_count [llength $ordered]]
    if {$options ne {}} {
        if {$orderReceipt eq {}} {
            set methodOrder [expr {$mode eq "2d" ? "x_ascending" : $parameterMode eq "variable" ? "t_ascending" : "source_sequence"}]
            set orderReceipt [dict create enabled 0 policy legacy_dev095 method_order $methodOrder original_rows $rows ordered_rows $ordered algorithm legacy_dev095 mode $mode parameter_mode $parameterMode]
        }
        dict set result ordering $orderReceipt
    }
    if {$mode eq "2d"} {set axes [expr {$planarGeometry ? {x y} : {y}}]} else {set axes {x y z}}
    foreach axis $axes {
        set values [expr {$axis eq "x" ? $xs : $axis eq "y" ? $ys : $zs}]
        set evaluated [_axisEvaluate $nodes $values $target $method $degree]
        if {[dict exists $evaluated values]} {
            dict set result $axis [dict get $evaluated values]
            dict set result diagnostics $axis [dict get $evaluated diagnostics]
            dict set result fits $axis [dict get $evaluated fit]
        } else {dict set result $axis $evaluated}
    }
    dict set result statistical_results [_interpretStatistics $result]
    return $result
}
proc ::GX::InteractiveCurveBuilder::_interpretStatistics {preview} {
    set method [dict get $preview method]
    if {$method ni {line polynomial}} {return {}}
    set operation [expr {$method eq "line"?"linear_regression":"polynomial_fit"}]
    set model [expr {$method eq "line"?"math.numeric.linear":"math.numeric.polynomial"}]
    set units [dict get $preview units]
    set independent [expr {[dict get $preview mode] eq "2d"&&![dict exists $preview x]?"x":"t"}]
    set sources {};foreach row [dict get $preview source_rows] {set id [dict get $row dataset_id];if {$id ni $sources} {lappend sources $id}}
    set results {}
    dict for {axis raw} [dict get $preview fits] {
        set context [dict create orientation y_of_x x_unit [dict get $units $independent] y_unit [dict get $units $axis] constraints none coefficient_space original_physical noise_model unspecified sample_role training]
        dict set results $axis [::GX::StatisticsV1::fromNumeric $model $operation $raw $context [dict get $preview diagnostics $axis] [dict create producer viewer.interactive_curve_builder method $method independent_axis $independent response_axis $axis source_dataset_ids $sources]]
    }
    return $results
}
proc ::GX::InteractiveCurveBuilder::_statisticsText {preview} {
    set lines {}
    dict for {axis result} [_interpretStatistics $preview] {lappend lines "$axis: [::GX::StatisticsV1::report $result {n rmse r_squared} ]"}
    return [join $lines {; }]
}

proc ::GX::InteractiveCurveBuilder::_variable {writer id unit semanticRole coordinateRole} {
    ::GX::datasetPublicationV2DeclareVariable $writer $id [dict create name $id unit $unit semantic_role $semanticRole dtype float64 rank 1 dimension_ids row coordinate_role $coordinateRole axis_kind explicit]
}
proc ::GX::InteractiveCurveBuilder::publish {preview datasetId {displayName ""}} {
    set session [_session]
    if {![dict exists $preview source_rows] || ![llength [dict get $preview source_rows]]} {error "Build a curve preview first."}
    set statistics [_interpretStatistics $preview]
    if {[dict exists $preview statistical_results]} {
        if {[lsort [dict keys [dict get $preview statistical_results]]] ne [lsort [dict keys $statistics]]} {error {Curve Builder statistical result identities changed; preview again}}
        dict for {axis expected} $statistics {
            set actual [dict get $preview statistical_results $axis]
            ::GX::StatisticsV1::validate $actual
            if {[dict get $actual request] ne [dict get $expected request]} {error {Curve Builder numerical facts and interpreted result differ; preview again}}
        }
    }
    set rows [dict get $preview source_rows]
    set checkedSources {};set checkedSchema {}
    foreach row $rows {
        set ds [dict get $row dataset_id]
        if {![dict exists $checkedSources $ds]} {
            set identity [::GX::curveSourceDatasetIdentity $session $ds]
            dict set checkedSources $ds [dict get $identity sha256];dict set checkedSchema $ds [dict get $identity schema_identity]
        }
        if {[dict exists $row source_sha256] && [dict get $row source_sha256] ne [dict get $checkedSources $ds]} {error {Source Dataset changed after preview; rebuild before publication}}
        if {[dict exists $row source_schema_identity] && [dict get $row source_schema_identity] ne [dict get $checkedSchema $ds]} {error {Source scientific schema changed after preview; rebuild before publication}}
    }
    set sources {}; set bindings {}; set identities {}
    foreach row $rows {
        set ds [dict get $row dataset_id]
        if {$ds ni $sources} {lappend sources $ds}
        foreach axis {x y z t} {
            set id [dict get $row ${axis}_id]
            if {$id ne "" && "$ds:$id" ni $bindings} {lappend bindings "$ds:$id"}
        }
        lappend identities "$ds:[dict get $row row]"
    }
    set mode [dict get $preview mode]
    set provenance "Interactive Curve Builder [dict get $preview method]; mode=$mode; parameter=[dict get $preview parameter_mode]; source_rows=[join $identities ,]"
    set definition [dict create dataset_id $datasetId contract table.generic storage csv producer_version 1.2.0 source "Interactive Curve Builder" provenance $provenance notes $displayName source_dataset_ids $sources source_variable_ids $bindings]
    if {$statistics ne {}} {dict set definition structured_metadata [::GX::StatisticsV1::publicationMetadata $statistics]}
    set plan [::GX::datasetPublicationV2Prepare $session viewer.interactive_curve_builder $definition]
    set writer ""
    try {
        set writer [::GX::datasetPublicationV2OpenWriter $plan]
        ::GX::datasetPublicationV2DeclareDimension $writer row 0 [dict create extendible 1]
        set units [dict get $preview units]
        set first [lindex $rows 0]
        if {$mode eq "2d"} {
            _variable $writer x [dict get $units x] [dict get [_var [dict get $first dataset_id] [dict get $first x_id]] semantic_role] coordinate
            _variable $writer y [dict get $units y] [dict get [_var [dict get $first dataset_id] [dict get $first y_id]] semantic_role] data
            set data [dict create x [::GX::datasetPublicationV2DictDefault $preview x [dict get $preview target]] y [dict get $preview y]]
            if {[dict exists $preview x]} {_variable $writer t [dict get $units t] independent coordinate;dict set data t [dict get $preview target]}
        } else {
            set parameterAxis [expr {[dict get $preview parameter_mode] eq "variable" ? "t" : "x"}]
            _variable $writer t [dict get $units t] [dict get [_var [dict get $first dataset_id] [dict get $first ${parameterAxis}_id]] semantic_role] coordinate
            foreach axis {x y z} {_variable $writer $axis [dict get $units $axis] [dict get [_var [dict get $first dataset_id] [dict get $first ${axis}_id]] semantic_role] data}
            set data [dict create t [dict get $preview target] x [dict get $preview x] y [dict get $preview y] z [dict get $preview z]]
        }
        ::GX::datasetPublicationV2Append $writer row $data
        set published [::GX::datasetPublicationV2Finalize $writer]
    } on error {err options} {
        if {$writer ne ""} {catch {::GX::datasetPublicationV2Abort $writer}}
        return -options $options $err
    }
    set metadata [dict create \
        dataset.display_name $displayName \
        curve_builder.method [dict get $preview method] \
        curve_builder.mode $mode \
        curve_builder.parameter_mode [dict get $preview parameter_mode] \
        curve_builder.degree [dict get $preview degree] \
        curve_builder.samples [dict get $preview samples] \
        curve_builder.source_dataset_ids [join $sources {;}] \
        curve_builder.source_variable_ids [join $bindings {;}] \
        curve_builder.source_rows [join $identities {;}] \
        curve_builder.target_coordinates [join [dict get $preview target] {;}] \
        curve_builder.units $units]
    if {$statistics ne {}} {set metadata [dict merge $metadata [::GX::StatisticsV1::publicationMetadata $statistics]]}
    if {[dict exists $preview diagnostics]} {dict set metadata curve_builder.diagnostics [dict get $preview diagnostics]}
    set filterBindings {};set sourceFingerprints {}
    foreach row $rows {
        if {[dict exists $row filter_binding]} {lappend filterBindings [dict create dataset_id [dict get $row dataset_id] row [dict get $row row] binding [dict get $row filter_binding]]}
        dict set sourceFingerprints [dict get $row dataset_id] [dict get $checkedSources [dict get $row dataset_id]]
    }
    dict set metadata curve_builder.filter_bindings $filterBindings
    dict set metadata curve_builder.source_fingerprints $sourceFingerprints
    dict set metadata curve_builder.source_schema_identities $checkedSchema
    if {[dict exists $preview ordering]} {
        set receipt [dict get $preview ordering]
        set provenance [dict remove $receipt points original_rows ordered_rows]
        foreach {key field} {original_rows input_order ordered_rows output_order} {
            dict set provenance $field [lmap row [dict get $receipt $key] {list [dict get $row dataset_id] [dict get $row row]}]
        }
        dict set metadata curve_builder.ordering $provenance
    }
    ::GX::datasetMetadataWrite $session $datasetId $metadata
    return [dict merge $published [dict create source_dataset_ids $sources source_rows $identities]]
}

# The source is rendered by Plot Dataset, then its public transient renderer
# overlays the unpublished NUMERIC_API result. The temporary source Plot
# Variant is removed after capture; the caller owns the preview directory.
proc ::GX::InteractiveCurveBuilder::renderPreview {preview destinationDir {scope full}} {
    if {[dict get $preview mode] ne "2d"} {error "Plot Dataset transient preview currently supports 2-D curves only."}
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
    ::GX::PlotDatasetAPIv3::requireCapability transient_2d_overlay
    set series [sourcePlotSeries [dict get $preview source_rows] $scope]
    if {![llength $series]} {error "Preview has no canonical source series."}
    set spec [dict create schema PLOT_DATASET_PLOTSPEC_v2 graph_type cartesian_2d graph_id plot.dataset.xy \
        title "Builder preview · [sourcePlotCaption [dict get $preview source_rows] $scope]" defaults [dict create style [dict create]] \
        panels [list [dict create id main title [sourcePlotCaption [dict get $preview source_rows] $scope] \
            axes [dict create x [dict create label X scale linear] y_left [dict create label Y scale linear]] \
            series $series annotations {}]] output [dict create]]
    set ref ""
    try {
        set ref [::GX::PlotDatasetAPIv3::createPlotFromSpec $spec variant]
        set rendered [::GX::PlotDatasetAPIv3::render $ref]
        set artifact [dict get [dict get $rendered artifacts] graph_artifact]
        set overlay [::GX::PlotDatasetAPIv3::renderTransientOverlay $artifact [::GX::datasetPublicationV2DictDefault $preview x [dict get $preview target]] [dict get $preview y] "Built curve" $destinationDir]
        return [dict get $overlay artifact]
    } finally {
        if {$ref ne ""} {catch {::GX::PlotDatasetAPIv3::deletePlot $ref}}
    }
}

proc ::GX::InteractiveCurveBuilder::openPlot {datasetId {sourceRows {}} {scope full}} {
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
    set hasT [expr {![catch {::GX::datasetVariableById $datasetId t}]}]
    if {$hasT && ![catch {::GX::datasetVariableById $datasetId z}]} {
        set spec [dict create schema PLOT_DATASET_PLOTSPEC_v2 graph_type cartesian_3d graph_id plot.dataset.xyz \
            dataset_id $datasetId x_variable_id x y_variable_id y z_variable_id z \
            title "Interactive Curve Builder 3-D: $datasetId" config [dict create plot_type line3]]
        set ref [::GX::PlotDatasetAPIv3::createPlotFromSpec $spec variant]
        ::GX::PlotDatasetAPIv3::render $ref
        ::GX::PlotDatasetAPIv3::openInteractive $ref
        return $ref
    }
    set metadata [::GX::datasetMetadataRead [_session] $datasetId]
    set useT [expr {$hasT && [::GX::datasetPublicationV2DictDefault $metadata curve_builder.mode {}] ne "2d"}]
    set xId [expr {$useT ? "t" : "x"}]
    set series [list [dict create id derived dataset_id $datasetId x_variable_id $xId y_variable_id y axis left kind line label "Built curve" style [dict create line_width 2.0]]]
    lappend series {*}[sourcePlotSeries $sourceRows $scope $useT]
    set spec [dict create schema PLOT_DATASET_PLOTSPEC_v2 graph_type cartesian_2d graph_id plot.dataset.xy title "Built $datasetId · [sourcePlotCaption $sourceRows $scope]" defaults [dict create style [dict create]] panels [list [dict create id main title [sourcePlotCaption $sourceRows $scope] axes [dict create x [dict create label $xId scale linear] y_left [dict create label Y scale linear]] series $series annotations {}]] output [dict create]]
    set ref [::GX::PlotDatasetAPIv3::createPlotFromSpec $spec variant]
    ::GX::PlotDatasetAPIv3::render $ref
    ::GX::PlotDatasetAPIv3::openEditor $ref
    return $ref
}

proc ::GX::InteractiveCurveBuilder::_uiError {w message} {
    # A cooperative source scan may finish unwinding after native window close.
    if {![winfo exists $w]} return
    set ::GX::InteractiveCurveBuilder::ui($w,status) $message
    tk_messageBox -parent $w -icon error -type ok -title "Interactive Curve Builder" -message $message
}
proc ::GX::InteractiveCurveBuilder::_uiSelections {w} {
    variable ui
    set ids [list ""]
    foreach id [::GX::sessionInspectionSelectionIds] {
        set selection [::GX::sessionInspectionSelection $id]
        if {[dict exists $selection source_dataset_id] && [dict get $selection source_dataset_id] eq $ui($w,dataset)} {lappend ids $id}
    }
    $w.source.selection configure -values $ids
    if {$ui($w,selection) ni $ids} {set ui($w,selection) ""}
}
proc ::GX::InteractiveCurveBuilder::_uiDatasets {w} {
    variable ui
    set ids [datasetIds]
    $w.source.dataset configure -values $ids
    if {[llength $ids] && $ui($w,dataset) ni $ids} {set ui($w,dataset) [lindex $ids 0]}
    if {$ui($w,dataset) ne ""} {_uiVariables $w}
}
proc ::GX::InteractiveCurveBuilder::_uiVariables {w} {
    variable ui
    set ds $ui($w,dataset)
    if {$ds eq ""} return
    set vars [variables $ds]
    foreach axis {x y z t} {
        set values [dict get $vars numeric]
        if {$axis in {z t}} {set values [linsert $values 0 ""]}
        $w.source.$axis configure -values $values
        if {$ui($w,$axis) ni $values} {
            set index [expr {$axis eq "x" ? 0 : $axis eq "y" ? 1 : 0}]
            set ui($w,$axis) [lindex $values $index]
        }
    }
    set families [linsert [dict get $vars family] 0 ""]
    $w.source.family configure -values $families
    if {$ui($w,family) ni $families} {set ui($w,family) ""}
    set suggestions [_identitySuggestions $ds]
    if {$ui($w,family) eq {}} {set ui($w,family) [dict get $suggestions family]}
    $w.source.member configure -values $families
    set ui($w,member) [dict get $suggestions member]
    _uiFamilyValues $w
    _uiMemberValues $w
    _uiSelections $w
}
proc ::GX::InteractiveCurveBuilder::_uiFamilyValues {w} {
    _uiFilterValues $w family
}
proc ::GX::InteractiveCurveBuilder::_uiAddSource {w} {
    variable ui
    if {[catch {
        _uiScope $w
        set mode $ui($w,mode)
        set z [expr {$mode eq "3d" ? $ui($w,z) : ""}]
        set t [expr {$mode eq "3d" && $ui($w,parameter_mode) eq "variable" ? $ui($w,t) : ""}]
        if {$mode eq "3d" && $z eq ""} {error "Choose Z for a 3-D curve."}
        if {$mode eq "3d" && $ui($w,parameter_mode) eq "variable" && $t eq ""} {error "Choose a monotonic t variable, or choose cumulative arc length."}
        set rows [sourceRows $ui($w,dataset) $ui($w,x) $ui($w,y) $z $t $ui($w,family) $ui($w,family_value) $ui($w,selection) [dict create family_enabled $ui($w,family_enabled) member_id $ui($w,member) member_value $ui($w,member_value) member_enabled $ui($w,member_enabled) progress [list ::GX::InteractiveCurveBuilder::_uiProgress $w $ui($w,epoch)]]]
        if {![llength $rows]} {_uiClearSelection $w;error "The exact Family AND Member AND Plot Selection intersection contains no finite points."}
        _uiInvalidate $w
        set tree $w.points.tree
        foreach row $rows {
            set id "point_[incr ui($w,next)]"
            dict set ui($w,rows) $id $row
            $tree insert {} end -id $id -values [_uiRowValues $row]
        }
        _uiClosePreview $w
        set ui($w,status) "Added [llength $rows] canonical rows. Select whole curve, a range, or highlighted points."
        set ui($w,preview) ""
    } err]} {_uiError $w $err}
}
proc ::GX::InteractiveCurveBuilder::_uiMark {w ids} {
    variable ui
    _uiInvalidate $w
    _uiClosePreview $w
    set tree $w.points.tree
    foreach id $ids {
        if {![dict exists $ui($w,rows) $id]} continue
        dict set ui($w,selected) $id 1
        set values [$tree item $id -values]
        lset values 0 "●"
        $tree item $id -values $values
    }
    set ui($w,preview) ""
    set ui($w,status) "[dict size $ui($w,selected)] points selected."
}
proc ::GX::InteractiveCurveBuilder::_uiSelectWhole {w} {
    _uiMark $w [$w.points.tree children {}]
}
proc ::GX::InteractiveCurveBuilder::_uiSelectHighlighted {w} {
    _uiMark $w [$w.points.tree selection]
}
proc ::GX::InteractiveCurveBuilder::_uiSelectRange {w} {
    variable ui
    if {[catch {
        set lo [_finite $ui($w,range_min) "Range minimum"]
        set hi [_finite $ui($w,range_max) "Range maximum"]
        if {$lo > $hi} {error "Range minimum exceeds maximum."}
        set ids {}
        dict for {id row} $ui($w,rows) {
            set axis [expr {$ui($w,mode) eq "3d" && $ui($w,parameter_mode) eq "variable" ? "t" : "x"}]
            if {![dict exists $row $axis]} continue
            set value [dict get $row $axis]
            if {$value >= $lo && $value <= $hi} {lappend ids $id}
        }
        _uiMark $w $ids
    } err]} {_uiError $w $err}
}
proc ::GX::InteractiveCurveBuilder::_uiClearSelection {w} {
    variable ui
    set ui($w,ordering) {};set ui($w,reviewed) 0
    _uiClosePreview $w
    set ui($w,selected) [dict create]
    set ui($w,preview) ""
    set tree $w.points.tree
    foreach id [$tree children {}] {
        set values [$tree item $id -values]
        lset values 0 ""
        $tree item $id -values $values
    }
    set ui($w,status) "Selection cleared."
}
proc ::GX::InteractiveCurveBuilder::_uiRestart {w} {
    variable ui
    _uiInvalidate $w
    _uiClosePreview $w
    $w.points.tree delete [$w.points.tree children {}]
    set ui($w,rows) [dict create]
    set ui($w,selected) [dict create]
    set ui($w,preview) ""
    $w.preview.table delete [$w.preview.table children {}]
    set ui($w,status) "Source list cleared."
}
proc ::GX::InteractiveCurveBuilder::_uiSelectedRows {w} {
    variable ui
    set rows {}
    foreach id [$w.points.tree children {}] {
        if {[dict exists $ui($w,selected) $id]} {lappend rows [dict get $ui($w,rows) $id]}
    }
    return $rows
}
proc ::GX::InteractiveCurveBuilder::renderPreview3D {preview destinationDir} {
    if {[dict get $preview mode] ne "3d"} {error "3-D transient preview requires a 3-D parametric curve."}
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
    set rendered [::GX::PlotDatasetAPIv3::renderTransientCurve3D \
        [dict get $preview x] [dict get $preview y] [dict get $preview z] \
        "Built 3-D curve" $destinationDir]
    return [dict get $rendered artifact]
}

proc ::GX::InteractiveCurveBuilder::_uiClosePreview {w} {
    variable ui
    if {[winfo exists .interactive_curve_preview]} {destroy .interactive_curve_preview}
    if {[info exists ui($w,preview_image)] && $ui($w,preview_image) ne ""} {catch {image delete $ui($w,preview_image)}; set ui($w,preview_image) ""}
    if {[info exists ui($w,preview_dir)] && $ui($w,preview_dir) ne ""} {catch {file delete -force -- $ui($w,preview_dir)}; set ui($w,preview_dir) ""}
}
proc ::GX::InteractiveCurveBuilder::_uiClose {w} {
    _uiDispose $w
    _uiClosePreview $w
    if {[winfo exists $w]} {destroy $w}
}
proc ::GX::InteractiveCurveBuilder::_uiGraphPreview {w preview} {
    variable ui
    _uiClosePreview $w
    set channel [file tempfile destination]
    close $channel
    file delete -- $destination
    if {[catch {set artifact [expr {[dict get $preview mode] eq "2d" ? [renderPreview $preview $destination $ui($w,display_scope)] : [renderPreview3D $preview $destination]}]} err options]} {
        catch {file delete -force -- $destination}
        return -options $options $err
    }
    _uiScope $w
    set picture [image create photo -file $artifact]
    set ui($w,preview_dir) $destination
    set ui($w,preview_image) $picture
    set p .interactive_curve_preview
    toplevel $p
    wm title $p "Curve Builder Plot Dataset preview"
    ttk::label $p.image -image $picture
    ttk::button $p.close -text Close -command [list ::GX::InteractiveCurveBuilder::_uiClosePreview $w]
    pack $p.image -padx 8 -pady 8
    pack $p.close -pady 8
    wm protocol $p WM_DELETE_WINDOW [list ::GX::InteractiveCurveBuilder::_uiClosePreview $w]
}
proc ::GX::InteractiveCurveBuilder::_uiPreview {w} {
    variable ui
    _uiClosePreview $w
    if {$ui($w,auto_order) && !$ui($w,reviewed)} {_uiOrderReview $w;return}
    if {[catch {
        _uiScope $w
        set rows [_uiSelectedRows $w]
        set requestEpoch $ui($w,epoch)
        set preview [evaluate $rows $ui($w,mode) $ui($w,method) $ui($w,degree) $ui($w,samples) $ui($w,parameter_mode) [dict create auto_order $ui($w,auto_order) reviewed $ui($w,reviewed) ordering_receipt $ui($w,ordering)]]
        _uiScope $w
        if {$requestEpoch!=$ui($w,epoch) || $rows ne [_uiSelectedRows $w]} {error {Preview request changed; select and preview again}}
        set ui($w,preview) $preview
        set tree $w.preview.table
        $tree delete [$tree children {}]
        set n [llength [dict get $preview target]]
        for {set i 0} {$i < $n && $i < 500} {incr i} {
            $tree insert {} end -values [list [lindex [dict get $preview target] $i] [expr {[dict exists $preview x] ? [lindex [dict get $preview x] $i] : ""}] [lindex [dict get $preview y] $i] [expr {[dict exists $preview z] ? [lindex [dict get $preview z] $i] : ""}]]
        }
        set diagnostic [_statisticsText $preview]
        set ui($w,status) "Preview: $n target points from [dict get $preview source_count] selected source rows. $diagnostic"
        _uiGraphPreview $w $preview
    } err]} {_uiError $w $err}
}
proc ::GX::InteractiveCurveBuilder::_uiPublish {w} {
    variable ui
    if {[catch {
        _uiScope $w
        if {$ui($w,preview) eq ""} {error "Preview the selected curve before publishing."}
        foreach key {mode method degree samples parameter_mode} {
            if {[dict get $ui($w,preview) $key] ne $ui($w,$key)} {error "Curve settings changed; preview again before publishing."}
        }
        if {[dict exists $ui($w,preview) ordering] && [dict get $ui($w,preview) ordering original_rows] ne [_uiSelectedRows $w]} {error {Selected identities changed; preview again before publishing}}
        if {![dict exists $ui($w,preview) ordering] && [dict get $ui($w,preview) source_rows] ne [_uiSelectedRows $w] && $ui($w,mode) eq "3d" && $ui($w,parameter_mode) eq "arc_length"} {
            # Arc-length rows retain the user's order; this exact identity check
            # is meaningful only before the evaluator sorts other modes.
            error "Selected rows changed; preview again before publishing."
        }
        set id [string trim $ui($w,result_id)]
        if {$id eq ""} {error "Enter a Dataset ID for the result."}
        publish $ui($w,preview) $id $ui($w,result_name)
        set ui($w,status) "Published Dataset $id. It is available in Plot Dataset and will survive Session save/reopen."
        if {$ui($w,open_plot)} {openPlot $id [dict get $ui($w,preview) source_rows] $ui($w,display_scope)}
    } err]} {_uiError $w $err}
}
proc ::GX::InteractiveCurveBuilder::open {{context {}}} {
    variable ui
    variable windows
    package require Tk
    _numeric
    set session [_session]
    set w .interactive_curve_builder
    set requested [::GX::datasetPublicationV2DictDefault $context workspace_id {}]
    if {[winfo exists $w] && $requested ne {} && $requested ne $ui($w,document)} {_uiClose $w}
    if {[winfo exists $w]} {raise $w; focus $w; return $w}
    toplevel $w
    wm title $w "Interactive Curve Builder"
    wm minsize $w 1000 680
    set windows($w) $session
    set ui($w,session_token) [::GX::interactiveDocumentSessionToken]
    set ui($w,epoch) [incr ::GX::InteractiveCurveBuilder::epoch]
    set ui($w,document) {};set ui($w,workspace_name) [::GX::datasetPublicationV2DictDefault $context workspace_name {}]
    set ui($w,ordering) {};set ui($w,reviewed) 0
    set prefs [_optionsValidate [dict get [::GX::configurationResolve modules.curve_builder.defaults] effective]]
    dict for {key value} $prefs {set ui($w,$key) $value}
    foreach {key value} {family_value {} member_value {} family_enabled 0 member_enabled 0} {set ui($w,$key) $value}
    foreach {key value} {dataset "" x "" y "" z "" t "" family "" member "" selection "" mode 2d parameter_mode variable method linear degree 2 samples 101 range_min "" range_max "" result_id built_curve result_name "Built curve" open_plot 1 status "Choose a Dataset, then add source rows." preview "" next 0} {set ui($w,$key) $value}
    set ui($w,rows) [dict create]
    set ui($w,selected) [dict create]
    set ui($w,preview_dir) ""
    set ui($w,preview_image) ""
    wm protocol $w WM_DELETE_WINDOW [list ::GX::InteractiveCurveBuilder::_uiClose $w]
    if {[dict exists $context dataset_id]} {set ui($w,dataset) [dict get $context dataset_id]}
    if {[dict exists $context source_dataset_id]} {set ui($w,dataset) [dict get $context source_dataset_id]}
    ttk::frame $w.source -padding 8
    grid $w.source -row 0 -column 0 -sticky ew
    set col 0
    foreach {key label width} {dataset Dataset 24 x X 10 y Y 10 z Z 10 t t 10 selection {Plot Selection} 16} {
        ttk::label $w.source.l_$key -text $label
        ttk::combobox $w.source.$key -textvariable ::GX::InteractiveCurveBuilder::ui($w,$key) -state readonly -width $width
        grid $w.source.l_$key -row 0 -column $col -sticky w -padx 3
        grid $w.source.$key -row 1 -column $col -sticky ew -padx 3
        incr col
    }
    set col 0
    foreach {key label width} {family {Family variable} 18 family_value {Family value (exact)} 24 member {Member variable} 18 member_value {Member value (exact)} 24} {
        ttk::label $w.source.l_$key -text $label
        ttk::combobox $w.source.$key -textvariable ::GX::InteractiveCurveBuilder::ui($w,$key) -state [expr {$key in {family member} ? "readonly" : "normal"}] -width $width
        grid $w.source.l_$key -row 2 -column $col -sticky w -padx 3 -pady {8 0}
        grid $w.source.$key -row 3 -column $col -sticky ew -padx 3
        incr col
        if {$key in {family_value member_value}} {
            set role [string range $key 0 end-6]
            ttk::checkbutton $w.source.${role}_enabled -text {Filter enabled} -variable ::GX::InteractiveCurveBuilder::ui($w,${role}_enabled) -command [list ::GX::InteractiveCurveBuilder::_uiInvalidate $w 1]
            grid $w.source.${role}_enabled -row 3 -column $col -padx 3
            incr col
        }
    }
    bind $w.source.dataset <<ComboboxSelected>> [list ::GX::InteractiveCurveBuilder::_uiVariables $w]
    bind $w.source.family <<ComboboxSelected>> [list ::GX::InteractiveCurveBuilder::_uiFamilyValues $w]
    bind $w.source.member <<ComboboxSelected>> [list ::GX::InteractiveCurveBuilder::_uiMemberValues $w]
    foreach key {family_value member_value} {bind $w.source.$key <<ComboboxSelected>> [list ::GX::InteractiveCurveBuilder::_uiInvalidate $w 1];bind $w.source.$key <KeyRelease> [list ::GX::InteractiveCurveBuilder::_uiInvalidate $w 1]}
    foreach key {x y z t selection} {bind $w.source.$key <<ComboboxSelected>> [list ::GX::InteractiveCurveBuilder::_uiInvalidate $w]}
    ttk::frame $w.settings -padding 8
    grid $w.settings -row 1 -column 0 -sticky ew
    set col 0
    foreach {key label values width} {mode Mode {2d 3d} 5 parameter_mode Parameter {variable arc_length} 11 method Method {nearest linear cubic spline pchip line polynomial} 14} {
        ttk::label $w.settings.l_$key -text $label
        ttk::combobox $w.settings.$key -textvariable ::GX::InteractiveCurveBuilder::ui($w,$key) -values $values -state readonly -width $width
        grid $w.settings.l_$key -row 0 -column $col -sticky w -padx 3
        grid $w.settings.$key -row 1 -column $col -sticky ew -padx 3
        incr col
    }
    foreach {key label width} {degree {Polynomial degree} 8 samples {Target samples} 10 range_min {Range minimum} 12 range_max {Range maximum} 12} {
        ttk::label $w.settings.l_$key -text $label
        ttk::entry $w.settings.$key -textvariable ::GX::InteractiveCurveBuilder::ui($w,$key) -width $width
        grid $w.settings.l_$key -row 0 -column $col -sticky w -padx 3
        grid $w.settings.$key -row 1 -column $col -sticky ew -padx 3
        incr col
    }
    ttk::button $w.settings.add -text "Add source rows" -command [list ::GX::InteractiveCurveBuilder::_uiAddSource $w]
    grid $w.settings.add -row 1 -column $col -padx 8
    ttk::frame $w.points -padding 8
    grid $w.points -row 2 -column 0 -sticky nsew
    ttk::label $w.points.label -text "Canonical source rows (select individual points in this table)"
    grid $w.points.label -row 0 -column 0 -sticky w
    ttk::treeview $w.points.tree -columns {chosen dataset row family member x y z t} -show headings -selectmode extended -height 9
    foreach {key label width} {chosen Selected 60 dataset Dataset 190 row Row 60 family Family 130 member Member 170 x X 110 y Y 110 z Z 110 t t 110} {
        $w.points.tree heading $key -text $label
        $w.points.tree column $key -width $width -stretch 1
    }
    ttk::scrollbar $w.points.scroll -command [list $w.points.tree yview]
    ttk::scrollbar $w.points.horizontal -orient horizontal -command [list $w.points.tree xview]
    $w.points.tree configure -yscrollcommand [list $w.points.scroll set] -xscrollcommand [list $w.points.horizontal set]
    grid $w.points.horizontal -row 2 -column 0 -sticky ew
    grid $w.points.tree -row 1 -column 0 -sticky nsew
    grid $w.points.scroll -row 1 -column 1 -sticky ns
    grid rowconfigure $w.points 1 -weight 1
    grid columnconfigure $w.points 0 -weight 1
    ttk::frame $w.actions -padding 8
    grid $w.actions -row 3 -column 0 -sticky ew
    foreach {key label command} {whole {Whole curve} _uiSelectWhole highlighted {Highlighted points} _uiSelectHighlighted range Range _uiSelectRange clear {Clear selection} _uiClearSelection restart {Restart sources} _uiRestart preview Preview _uiPreview} {
        ttk::button $w.actions.$key -text $label -command [list ::GX::InteractiveCurveBuilder::$command $w]
        pack $w.actions.$key -side left -padx 4
    }
    _uiMiddleMenus $w
    ttk::frame $w.preview -padding 8
    grid $w.preview -row 4 -column 0 -sticky nsew
    ttk::label $w.preview.label -text "NUMERIC_API preview values (first 500 shown)"
    grid $w.preview.label -row 0 -column 0 -sticky w
    ttk::treeview $w.preview.table -columns {parameter x y z} -show headings -height 7
    foreach {key label width} {parameter {X or t} 170 x X 170 y Y 170 z Z 170} {
        $w.preview.table heading $key -text $label
        $w.preview.table column $key -width $width -stretch 1
    }
    ttk::scrollbar $w.preview.scroll -command [list $w.preview.table yview]
    $w.preview.table configure -yscrollcommand [list $w.preview.scroll set]
    grid $w.preview.table -row 1 -column 0 -sticky nsew
    grid $w.preview.scroll -row 1 -column 1 -sticky ns
    grid rowconfigure $w.preview 1 -weight 1
    grid columnconfigure $w.preview 0 -weight 1
    ttk::frame $w.publish -padding 8
    grid $w.publish -row 5 -column 0 -sticky ew
    ttk::label $w.publish.id_label -text "Result Dataset ID"
    ttk::entry $w.publish.id -textvariable ::GX::InteractiveCurveBuilder::ui($w,result_id) -width 24
    ttk::label $w.publish.name_label -text "Display name"
    ttk::entry $w.publish.name -textvariable ::GX::InteractiveCurveBuilder::ui($w,result_name) -width 26
    ttk::checkbutton $w.publish.plot -text "Open Plot Dataset overlay after publication" -variable ::GX::InteractiveCurveBuilder::ui($w,open_plot)
    ttk::button $w.publish.go -text "Publish as Dataset" -command [list ::GX::InteractiveCurveBuilder::_uiPublish $w]
    pack $w.publish.id_label $w.publish.id $w.publish.name_label $w.publish.name $w.publish.plot $w.publish.go -side left -padx 5
    ttk::label $w.status -textvariable ::GX::InteractiveCurveBuilder::ui($w,status) -wraplength 980
    grid $w.status -row 6 -column 0 -sticky ew -padx 8 -pady 5
    grid columnconfigure $w 0 -weight 1
    grid rowconfigure $w 2 -weight 1
    grid rowconfigure $w 4 -weight 1
    _uiDatasets $w
    foreach key {mode parameter_mode method} {bind $w.settings.$key <<ComboboxSelected>> [list ::GX::InteractiveCurveBuilder::_uiInvalidate $w]}
    foreach key {degree samples} {bind $w.settings.$key <KeyRelease> [list ::GX::InteractiveCurveBuilder::_uiInvalidate $w]}
    _uiWorkspaceAttach $w $context
    if {$ui($w,auto_order)} {set ui($w,status) {An explicit saved Auto-order preference is enabled; review each candidate before Preview}}
    return $w
}
proc ::GX::InteractiveCurveBuilder::viewerDispatch {action scene} {
    if {$action ni {open rerender}} {error "Unsupported Curve Builder viewer action '$action'."}
    set context [expr {[dict exists $scene open_context] ? [dict get $scene open_context] : [dict create]}]
    return [open $context]
}
::GX::viewerBackendRegister interactive_curve_builder_tk ::GX::InteractiveCurveBuilder::viewerDispatch

source [file join [file dirname [info script]] curve_builder_options.tcl]
source [file join [file dirname [info script]] curve_builder_workspace.tcl]
