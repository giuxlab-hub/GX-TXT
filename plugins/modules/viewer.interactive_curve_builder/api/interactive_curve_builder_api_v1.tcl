# GX-TXT Interactive Curve Builder API v1
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::InteractiveCurveBuilder {
    variable version 1.0.0
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
proc ::GX::InteractiveCurveBuilder::sourceRows {datasetId xId yId {zId ""} {tId ""} {familyId ""} {familyValue ""} {selectionId ""}} {
    set session [_session]
    if {$xId eq "" || $yId eq ""} {error "Choose X and Y variables."}
    foreach id [list $xId $yId $zId $tId] {
        if {$id eq ""} continue
        set v [_var $datasetId $id]
        if {[dict get $v value_kind] ne "number"} {error "Variable '$id' must be numeric."}
    }
    if {$familyId ne ""} {_var $datasetId $familyId}
    set ids [lsort -unique [concat [list $xId $yId] [expr {$zId eq "" ? {} : [list $zId]}] [expr {$tId eq "" ? {} : [list $tId]}] [expr {$familyId eq "" ? {} : [list $familyId]}]]]
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
                if {$familyId ne "" && $familyValue ne "" && $member ne $familyValue} continue
                set row [dict create dataset_id $datasetId row $ordinal x_id $xId y_id $yId z_id $zId t_id $tId family_id $familyId family_value $member]
                set valid 1
                foreach key {x y z t} id [list $xId $yId $zId $tId] {
                    if {$id eq ""} continue
                    set value [lindex [dict get $columns $id] $i]
                    if {[catch {set value [_finite $value "Source $datasetId row [dict get $row row] $key"]}]} {set valid 0; break}
                    dict set row $key $value
                }
                if {$valid} {lappend rows $row}
            }
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
proc ::GX::InteractiveCurveBuilder::evaluate {rows mode method {degree 2} {samples 101} {parameterMode variable}} {
    if {$mode ni {2d 3d}} {error "Curve mode must be 2d or 3d."}
    if {$method ni {nearest linear cubic spline pchip line polynomial}} {error "Unsupported curve method '$method'."}
    if {$mode eq "3d" && $parameterMode ni {variable arc_length}} {error "3-D parameter mode must be variable or arc_length."}
    if {[llength $rows] < 2} {error "Select at least two source points."}
    if {$method eq "polynomial" && (![string is integer -strict $degree] || $degree < 0 || $degree >= [llength $rows])} {
        error "Polynomial degree must be between 0 and one less than the selected point count."
    }
    set units [_units $rows $mode $parameterMode]
    if {$mode eq "2d"} {set ordered [lsort -command ::GX::InteractiveCurveBuilder::_byX $rows]} elseif {$parameterMode eq "variable"} {
        set ordered [lsort -command ::GX::InteractiveCurveBuilder::_byT $rows]
    } else {set ordered $rows}
    set nodes {}; set ys {}; set xs {}; set zs {}; set previous {}
    foreach row $ordered {
        if {$mode eq "2d"} {set p [dict get $row x]} elseif {$parameterMode eq "variable"} {set p [dict get $row t]} else {
            if {$previous eq ""} {set p 0.0} else {
                set sum 0.0
                foreach axis {x y z} {set delta [expr {[dict get $row $axis]-[dict get $previous $axis]}]; set sum [expr {$sum+$delta*$delta}]}
                set p [expr {[lindex $nodes end]+sqrt($sum)}]
            }
        }
        if {[llength $nodes] && $p <= [lindex $nodes end]} {error "Selected independent coordinates must be strictly increasing; duplicate rows, X, t or zero-length arc segments are not valid."}
        lappend nodes $p; lappend ys [dict get $row y]
        if {$mode eq "3d"} {lappend xs [dict get $row x]; lappend zs [dict get $row z]}
        set previous $row
    }
    set target [_grid $nodes $samples]
    set result [dict create mode $mode method $method degree $degree samples $samples parameter_mode $parameterMode target $target units $units source_rows $ordered source_count [llength $ordered]]
    if {$mode eq "2d"} {set axes {y}} else {set axes {x y z}}
    foreach axis $axes {
        set values [expr {$axis eq "x" ? $xs : $axis eq "y" ? $ys : $zs}]
        set evaluated [_axisEvaluate $nodes $values $target $method $degree]
        if {[dict exists $evaluated values]} {
            dict set result $axis [dict get $evaluated values]
            dict set result diagnostics $axis [dict get $evaluated diagnostics]
            dict set result fits $axis [dict get $evaluated fit]
        } else {dict set result $axis $evaluated}
    }
    return $result
}

proc ::GX::InteractiveCurveBuilder::_variable {writer id unit semanticRole coordinateRole} {
    ::GX::datasetPublicationV2DeclareVariable $writer $id [dict create name $id unit $unit semantic_role $semanticRole dtype float64 rank 1 dimension_ids row coordinate_role $coordinateRole axis_kind explicit]
}
proc ::GX::InteractiveCurveBuilder::publish {preview datasetId {displayName ""}} {
    set session [_session]
    if {![dict exists $preview source_rows] || ![llength [dict get $preview source_rows]]} {error "Build a curve preview first."}
    set rows [dict get $preview source_rows]
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
    set definition [dict create dataset_id $datasetId contract table.generic storage csv producer_version 1.0.0 source "Interactive Curve Builder" provenance $provenance notes $displayName source_dataset_ids $sources source_variable_ids $bindings]
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
            set data [dict create x [dict get $preview target] y [dict get $preview y]]
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
    if {[dict exists $preview diagnostics]} {dict set metadata curve_builder.diagnostics [dict get $preview diagnostics]}
    ::GX::datasetMetadataWrite $session $datasetId $metadata
    return [dict merge $published [dict create source_dataset_ids $sources source_rows $identities]]
}

# The source is rendered by Plot Dataset, then its public transient renderer
# overlays the unpublished NUMERIC_API result. The temporary source Plot
# Variant is removed after capture; the caller owns the preview directory.
proc ::GX::InteractiveCurveBuilder::renderPreview {preview destinationDir} {
    if {[dict get $preview mode] ne "2d"} {error "Plot Dataset transient preview currently supports 2-D curves only."}
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
    ::GX::PlotDatasetAPIv3::requireCapability transient_2d_overlay
    set series {}
    set seen [dict create]
    set index 0
    foreach row [dict get $preview source_rows] {
        set ds [dict get $row dataset_id]
        set xId [dict get $row x_id]
        set yId [dict get $row y_id]
        set key "$ds:$xId:$yId"
        if {[dict exists $seen $key]} continue
        dict set seen $key 1
        incr index
        lappend series [dict create id "source_$index" dataset_id $ds x_variable_id $xId y_variable_id $yId axis left kind line_marker label "Source $ds" style [dict create line_width 1.0 marker_size 3]]
    }
    if {![llength $series]} {error "Preview has no canonical source series."}
    set spec [dict create schema PLOT_DATASET_PLOTSPEC_v2 graph_type cartesian_2d graph_id plot.dataset.xy \
        title "Interactive Curve Builder preview" defaults [dict create style [dict create]] \
        panels [list [dict create id main title "Selected source and built curve" \
            axes [dict create x [dict create label X scale linear] y_left [dict create label Y scale linear]] \
            series $series annotations {}]] output [dict create]]
    set ref ""
    try {
        set ref [::GX::PlotDatasetAPIv3::createPlotFromSpec $spec variant]
        set rendered [::GX::PlotDatasetAPIv3::render $ref]
        set artifact [dict get [dict get $rendered artifacts] graph_artifact]
        set overlay [::GX::PlotDatasetAPIv3::renderTransientOverlay $artifact [dict get $preview target] [dict get $preview y] "Built curve" $destinationDir]
        return [dict get $overlay artifact]
    } finally {
        if {$ref ne ""} {catch {::GX::PlotDatasetAPIv3::deletePlot $ref}}
    }
}

proc ::GX::InteractiveCurveBuilder::openPlot {datasetId {sourceRows {}}} {
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
    set xId [expr {$hasT ? "t" : "x"}]
    set series [list [dict create id derived dataset_id $datasetId x_variable_id $xId y_variable_id y axis left kind line label "Built curve" style [dict create line_width 2.0]]]
    set seen {}
    set index 0
    foreach row $sourceRows {
        set source [dict get $row dataset_id]
        set sx [expr {$hasT ? [dict get $row t_id] : [dict get $row x_id]}]
        if {$sx eq ""} continue
        set sy [dict get $row y_id]
        set key "$source:$sx:$sy"
        if {$key in $seen} continue
        lappend seen $key
        incr index
        lappend series [dict create id "source_$index" dataset_id $source x_variable_id $sx y_variable_id $sy axis left kind scatter label "Source $source" style [dict create marker_size 4]]
    }
    set spec [dict create schema PLOT_DATASET_PLOTSPEC_v2 graph_type cartesian_2d graph_id plot.dataset.xy title "Interactive Curve Builder: $datasetId" defaults [dict create style [dict create]] panels [list [dict create id main title "Curve and sources" axes [dict create x [dict create label $xId scale linear] y_left [dict create label Y scale linear]] series $series annotations {}]] output [dict create]]
    set ref [::GX::PlotDatasetAPIv3::createPlotFromSpec $spec variant]
    ::GX::PlotDatasetAPIv3::render $ref
    ::GX::PlotDatasetAPIv3::openEditor $ref
    return $ref
}

proc ::GX::InteractiveCurveBuilder::_uiError {w message} {
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
    _uiFamilyValues $w
    _uiSelections $w
}
proc ::GX::InteractiveCurveBuilder::_uiFamilyValues {w} {
    variable ui
    set values [list ""]
    if {$ui($w,family) ne ""} {set values [concat $values [familyValues $ui($w,dataset) $ui($w,family)]]}
    $w.source.member configure -values $values
    if {$ui($w,member) ni $values} {set ui($w,member) ""}
}
proc ::GX::InteractiveCurveBuilder::_uiAddSource {w} {
    variable ui
    if {[catch {
        set mode $ui($w,mode)
        set z [expr {$mode eq "3d" ? $ui($w,z) : ""}]
        set t [expr {$mode eq "3d" && $ui($w,parameter_mode) eq "variable" ? $ui($w,t) : ""}]
        if {$mode eq "3d" && $z eq ""} {error "Choose Z for a 3-D curve."}
        if {$mode eq "3d" && $ui($w,parameter_mode) eq "variable" && $t eq ""} {error "Choose a monotonic t variable, or choose cumulative arc length."}
        set rows [sourceRows $ui($w,dataset) $ui($w,x) $ui($w,y) $z $t $ui($w,family) $ui($w,member) $ui($w,selection)]
        if {![llength $rows]} {error "This Dataset and family member contain no finite points."}
        set tree $w.points.tree
        foreach row $rows {
            set id "point_[incr ui($w,next)]"
            dict set ui($w,rows) $id $row
            $tree insert {} end -id $id -values [list "" [dict get $row dataset_id] [dict get $row row] [dict get $row family_value] [dict get $row x] [dict get $row y] [expr {[dict exists $row z] ? [dict get $row z] : ""}] [expr {[dict exists $row t] ? [dict get $row t] : ""}]]
        }
        _uiClosePreview $w
        set ui($w,status) "Added [llength $rows] canonical rows. Select whole curve, a range, or highlighted points."
        set ui($w,preview) ""
    } err]} {_uiError $w $err}
}
proc ::GX::InteractiveCurveBuilder::_uiMark {w ids} {
    variable ui
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
    _uiClosePreview $w
    if {[winfo exists $w]} {destroy $w}
}
proc ::GX::InteractiveCurveBuilder::_uiGraphPreview {w preview} {
    variable ui
    _uiClosePreview $w
    set channel [file tempfile destination]
    close $channel
    file delete -- $destination
    if {[catch {set artifact [expr {[dict get $preview mode] eq "2d" ? [renderPreview $preview $destination] : [renderPreview3D $preview $destination]}]} err options]} {
        catch {file delete -force -- $destination}
        return -options $options $err
    }
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
    if {[catch {
        set rows [_uiSelectedRows $w]
        set preview [evaluate $rows $ui($w,mode) $ui($w,method) $ui($w,degree) $ui($w,samples) $ui($w,parameter_mode)]
        set ui($w,preview) $preview
        set tree $w.preview.table
        $tree delete [$tree children {}]
        set n [llength [dict get $preview target]]
        for {set i 0} {$i < $n && $i < 500} {incr i} {
            $tree insert {} end -values [list [lindex [dict get $preview target] $i] [expr {[dict exists $preview x] ? [lindex [dict get $preview x] $i] : ""}] [lindex [dict get $preview y] $i] [expr {[dict exists $preview z] ? [lindex [dict get $preview z] $i] : ""}]]
        }
        set diagnostic ""
        if {[dict exists $preview diagnostics]} {
            dict for {axis d} [dict get $preview diagnostics] {
                append diagnostic "$axis: RMSE [expr {[dict exists $d rmse] ? [dict get $d rmse] : "n/a"}]  "
            }
        }
        set ui($w,status) "Preview: $n target points from [dict get $preview source_count] selected source rows. $diagnostic"
        _uiGraphPreview $w $preview
    } err]} {_uiError $w $err}
}
proc ::GX::InteractiveCurveBuilder::_uiPublish {w} {
    variable ui
    if {[catch {
        if {$ui($w,preview) eq ""} {error "Preview the selected curve before publishing."}
        foreach key {mode method degree samples parameter_mode} {
            if {[dict get $ui($w,preview) $key] ne $ui($w,$key)} {error "Curve settings changed; preview again before publishing."}
        }
        if {[dict get $ui($w,preview) source_rows] ne [_uiSelectedRows $w] && $ui($w,mode) eq "3d" && $ui($w,parameter_mode) eq "arc_length"} {
            # Arc-length rows retain the user's order; this exact identity check
            # is meaningful only before the evaluator sorts other modes.
            error "Selected rows changed; preview again before publishing."
        }
        set id [string trim $ui($w,result_id)]
        if {$id eq ""} {error "Enter a Dataset ID for the result."}
        publish $ui($w,preview) $id $ui($w,result_name)
        set ui($w,status) "Published Dataset $id. It is available in Plot Dataset and will survive Session save/reopen."
        if {$ui($w,open_plot)} {openPlot $id [dict get $ui($w,preview) source_rows]}
    } err]} {_uiError $w $err}
}
proc ::GX::InteractiveCurveBuilder::open {{context {}}} {
    variable ui
    variable windows
    package require Tk
    _numeric
    set session [_session]
    set w .interactive_curve_builder
    if {[winfo exists $w]} {raise $w; focus $w; return $w}
    toplevel $w
    wm title $w "Interactive Curve Builder"
    wm minsize $w 1000 680
    set windows($w) $session
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
    foreach {key label width} {dataset Dataset 24 x X 12 y Y 12 z Z 12 t t 12 family Family 12 member Member 18 selection {Plot Selection} 14} {
        ttk::label $w.source.l_$key -text $label
        ttk::combobox $w.source.$key -textvariable ::GX::InteractiveCurveBuilder::ui($w,$key) -state readonly -width $width
        grid $w.source.l_$key -row 0 -column $col -sticky w -padx 3
        grid $w.source.$key -row 1 -column $col -sticky ew -padx 3
        incr col
    }
    bind $w.source.dataset <<ComboboxSelected>> [list ::GX::InteractiveCurveBuilder::_uiVariables $w]
    bind $w.source.family <<ComboboxSelected>> [list ::GX::InteractiveCurveBuilder::_uiFamilyValues $w]
    ttk::frame $w.settings -padding 8
    grid $w.settings -row 1 -column 0 -sticky ew
    set col 0
    foreach {key label values width} {mode Mode {2d 3d} 5 parameter_mode {3-D parameter} {variable arc_length} 11 method Method {nearest linear cubic spline pchip line polynomial} 14} {
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
    ttk::treeview $w.points.tree -columns {chosen dataset row family x y z t} -show headings -selectmode extended -height 9
    foreach {key label width} {chosen Selected 60 dataset Dataset 190 row Row 60 family Member 130 x X 110 y Y 110 z Z 110 t t 110} {
        $w.points.tree heading $key -text $label
        $w.points.tree column $key -width $width -stretch 1
    }
    ttk::scrollbar $w.points.scroll -command [list $w.points.tree yview]
    $w.points.tree configure -yscrollcommand [list $w.points.scroll set]
    grid $w.points.tree -row 1 -column 0 -sticky nsew
    grid $w.points.scroll -row 1 -column 1 -sticky ns
    grid rowconfigure $w.points 1 -weight 1
    grid columnconfigure $w.points 0 -weight 1
    ttk::frame $w.actions -padding 8
    grid $w.actions -row 3 -column 0 -sticky ew
    foreach {key label command} {whole {Select whole curve} _uiSelectWhole highlighted {Select highlighted points} _uiSelectHighlighted range {Select range} _uiSelectRange clear {Clear selection} _uiClearSelection restart {Restart sources} _uiRestart preview {Preview curve} _uiPreview} {
        ttk::button $w.actions.$key -text $label -command [list ::GX::InteractiveCurveBuilder::$command $w]
        pack $w.actions.$key -side left -padx 4
    }
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
    return $w
}
proc ::GX::InteractiveCurveBuilder::viewerDispatch {action scene} {
    if {$action ni {open rerender}} {error "Unsupported Curve Builder viewer action '$action'."}
    set context [expr {[dict exists $scene open_context] ? [dict get $scene open_context] : [dict create]}]
    return [open $context]
}
::GX::viewerBackendRegister interactive_curve_builder_tk ::GX::InteractiveCurveBuilder::viewerDispatch
