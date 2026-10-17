# Bounded retained residual presentation; no numerical recomputation.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::resultResidualPage {reference start count} {
    set result [dict get [_recipeResultRecord $reference] provenance]
    if {![string is entier -strict $start]||![string is entier -strict $count]||$start<0||$count<1||$count>512} {error {Residual pages require a nonnegative offset and 1..512 rows}}
    if {![dict exists $result residual_resource]||![dict exists $result source_rows_resource]} {error {This historical result has no owned exact residual pages; preserve it or explicitly fit again}}
    set values [::GX::managedResourceNumericPage [dict get $result residual_resource] $start $count]
    set rows [::GX::managedResourceNumericPage [dict get $result source_rows_resource] $start $count]
    if {[dict get $values total_rows]!=[dict get $rows total_rows]||[dict get $values total_rows]!=[dict get $result source_n]||[dict get $values dtype] ne "float64"||[dict get $rows dtype] ne "uint64"||[dict get $values columns] ne [split [dict get $result residual_columns] ,]} {error {Retained residual shape or canonical columns changed}}
    set page [dict create api_id FITTER_RESIDUAL_PAGE_v1 api_version 1 meaning [dict get $result statistical_results evaluation] residuals $values source_rows $rows]
    if {[dict get $result model] eq "complex_response"} {dict set page physical_column_units [_complexResidualUnits $result];dict set page meaning_scope joint_cartesian_covariance_objective;dict set page display_projection [dict get $result options complex_data display]}
    return $page
}
proc ::GX::DatasetCurveFit::_residualRowsPage {w start count} {
    variable state
    set result $state($w,preview)
    if {[dict exists $result residual_resource]} {return [_numericResidualPage $result $start $count]}
    set rows [dict get $result residual];set ids [::GX::datasetPublicationV2DictDefault $result residual_rows $state($w,rows)]
    return [dict create start $start row_count [llength $rows] rows [lrange $rows $start [expr {$start+$count-1}]] source_rows [lrange $ids $start [expr {$start+$count-1}]]]
}
proc ::GX::DatasetCurveFit::_residualAxis {w axis} {
    variable state
    if {$axis ni {source predicted}} {error {Residual axis must be source or predicted}}
    if {$axis eq "predicted"&&$state($w,preview) ne {}&&[dict get $state($w,preview) model] eq "implicit"} {error {Equation residuals have no fitted response at the observed pair; use the source-coordinate axis}}
    if {$axis eq "predicted"&&$state($w,preview) ne {}&&[dict get $state($w,preview) parametric]} {error {A geometric projection has no single predicted response; inspect signed distance against its parameter}}
    set state($w,residualAxis) $axis
    _saveState $w;redraw $w
}
proc ::GX::DatasetCurveFit::_residualPlotRows {w} {
    variable state
    set report $state($w,preview)
    set key [list $state($w,activeSource) [::GX::datasetPublicationV2DictDefault $report residual_native {}] [::GX::datasetPublicationV2DictDefault $report residual_resource {}] [dict get $report residual]]
    if {[info exists state($w,residualPlotCacheKey)]&&$key eq $state($w,residualPlotCacheKey)} {return $state($w,residualPlotCache)}
    set rows {};set offsets {}
    if {[dict exists $report residual_native]&&[dict exists $report residual_resource]} {
        set sample [::GX::Native2D::core object_sample $state($w,scene) [dict get $report residual_native] 4096]
        set offsets [dict get $sample point_indices]
        set width [expr {8*[llength [dict get $report residual_resource metadata columns]]}]
        set ranges [lmap offset $offsets {list [expr {$offset*$width}] $width}]
        foreach bytes [::GX::interactiveDocumentResourceReadRanges [dict get $report residual_resource] $ranges] {binary scan $bytes q* row;lappend rows $row}
    } else {
        set n [llength [dict get $report residual]];set stride [expr {max(1,int(ceil($n/4096.0)))}]
        for {set i 0} {$i<$n} {incr i $stride} {lappend offsets $i;lappend rows [lindex [dict get $report residual] $i]}
    }
    set state($w,residualPlotCacheKey) $key;set state($w,residualPlotCache) [dict create rows $rows offsets $offsets]
    return $state($w,residualPlotCache)
}
proc ::GX::DatasetCurveFit::_residualFocusOffset {w offset {focusTable 1}} {
    variable state
    _assertLoaded $w
    if {$state($w,preview) eq {}||![string is entier -strict $offset]||$offset<0||$offset>=[dict get $state($w,preview) source_n]} {error {Choose an existing retained residual row}}
    set page [_residualRowsPage $w $offset 1];set row [lindex [dict get $page rows] 0];set id [lindex [dict get $page source_rows] 0]
    set review [dict create offset $offset source_row $id point [lrange $row 0 1] values $row]
    if {[info exists state($w,residualReview)]&&$state($w,residualReview) eq $review&&!$focusTable} return
    _residualPlotRows $w
    set state($w,residualReviewKey) $state($w,residualPlotCacheKey)
    set state($w,residualReview) $review
    if {$focusTable} {
        set state($w,residualStart) $offset;_residualPageUi $w 0
        set table $w.right.residuals.table;set item residual_$offset
        if {[$table exists $item]} {$table selection set $item;$table focus $item;$table see $item}
    }
    set state($w,status) "Inspecting exact source row $id. Fitting selection is unchanged."
    redraw $w
    return $review
}
proc ::GX::DatasetCurveFit::_residualTableFocus {w} {
    variable state
    if {![info exists state($w,preview)]||$state($w,preview) eq {}} return
    set selected [$w.right.residuals.table selection]
    if {[llength $selected]!=1||![regexp {^residual_([0-9]+)$} [lindex $selected 0] -> offset]} return
    if {[catch {_residualFocusOffset $w $offset 0} message]} {set state($w,status) $message}
}
proc ::GX::DatasetCurveFit::_residualLocateRow {w row} {
    variable state
    set report $state($w,preview)
    if {$report eq {}} {return -1}
    if {![dict exists $report source_rows_resource]} {return [lsearch -exact [::GX::datasetPublicationV2DictDefault $report residual_rows $state($w,rows)] $row]}
    set reader [::GX::interactiveDocumentResourceOpenReader [dict get $report source_rows_resource]]
    try {
        while 1 {
            set chunk [::GX::interactiveDocumentResourceNext $reader 65536];binary scan [dict get $chunk bytes] wu* ids
            set found [lsearch -exact $ids $row]
            if {$found>=0} {return [expr {[dict get $chunk offset]/8+$found}]}
            if {[dict get $chunk eof]} break
        }
    } finally {::GX::interactiveDocumentResourceCloseReader $reader}
    return -1
}
proc ::GX::DatasetCurveFit::_residualFocusSource {w index} {
    variable state
    if {$state($w,preview) eq {}} return
    set offset [_residualLocateRow $w [lindex $state($w,rows) $index]]
    if {$offset>=0} {_residualFocusOffset $w $offset}
}
proc ::GX::DatasetCurveFit::_residualPick {w x y} {
    variable state
    if {![info exists state($w,residualDevices)]} {return 0}
    set best 8.000001;set chosen -1
    foreach entry $state($w,residualDevices) {
        lassign $entry px py offset
        set distance [expr {hypot($px-$x,$py-$y)}]
        if {$distance<$best} {set best $distance;set chosen $offset}
    }
    if {$chosen<0} {return 0}
    _residualFocusOffset $w $chosen
    return 1
}
proc ::GX::DatasetCurveFit::_residualReviewSelect {w} {
    variable state
    if {![info exists state($w,residualReview)]} {error {Select a residual row to inspect first}}
    _residualPlotRows $w
    if {$state($w,residualReviewKey) ne $state($w,residualPlotCacheKey)} {error {Inspected preview changed; select a residual row again}}
    set offset [dict get $state($w,residualReview) offset]
    set page [_residualRowsPage $w $offset 1]
    return [_diagnosticSelectSourceRow $w [dict merge [_sourceProvenance $w] $state($w,preview)] [lindex [dict get $page source_rows] 0]]
}
proc ::GX::DatasetCurveFit::_drawResidualPanel {w left right height line} {
    variable state
    set state($w,residualDevices) {}
    if {$state($w,preview) eq {}||!$state($w,residualPlotVisible)} return
    set report $state($w,preview);set sample [_residualPlotRows $w];set orientation [dict get $report orientation];set geometric [dict get $report parametric]
    set predicted [expr {$state($w,residualAxis) eq "predicted"&&!$geometric&&[dict get $report model] ne "implicit"}]
    set column [expr {$predicted?2:($geometric||$orientation eq "r_of_theta"?5:($orientation eq "x_of_y"?1:0))}]
    set displayed {};set xvalues {};set maxabs 1e-12
    foreach row [dict get $sample rows] offset [dict get $sample offsets] {
        set x [lindex $row $column];set y [lindex $row 3]
        if {[catch {_finite $x x}]||[catch {_finite $y residual}]} continue
        lappend displayed [list $x $y $offset];lappend xvalues $x;set maxabs [expr {max($maxabs,abs($y))}]
    }
    if {![llength $displayed]} return
    set maxabs [expr {$maxabs*1.12}]
    set unit unspecified;if {[dict exists $report statistical_results evaluation residual unit]} {set unit [dict get $report statistical_results evaluation residual unit]}
    set response [expr {$orientation eq "x_of_y"?"X":($orientation eq "r_of_theta"?"radius":"Y")}]
    if {[dict get $report model] eq "complex_response"} {set unit [dict get $report complex_binding source_identity source_axes y unit]}
    set label [expr {$geometric?"Signed distance vs normalized parameter":"$response residual ($unit) vs [expr {$predicted?"predicted $response ($unit)":"source [expr {$orientation eq "x_of_y"?"Y":"X"}]"}]"}]
    if {[dict get $report model] eq "complex_response"} {set label "Display projection residual ($unit); joint Cartesian diagnostics are reported separately"}
    if {[dict get $report model] eq "implicit"} {set label "Equation residual: zero minus f ($unit) vs source [expr {$orientation eq "x_of_y"?"Y":"X"}]"}
    if {!$predicted&&$orientation eq "r_of_theta"} {set label "Radial residual ($unit) vs theta ([dict get $report angle_unit])"}
    if {$geometric&&$state($w,residualAxis) eq "predicted"} {append label { — no scalar predicted-response axis}}
    set canvas $w.right.plot.canvas;set top $state($w,residualPlotTop);set bottom [expr {$height-12}]
    $canvas create text $left [expr {$top-2*$line-8}] -anchor nw -text $label -width [expr {$right-$left}] -fill #475569 -tags residual_caption
    if {![info exists state($w,residualViewScene)]} {set state($w,residualViewScene) [::GX::Native2D::core scene]}
    # This separate diagnostic scene has response-versus-residual axes, not a
    # geometric metric. The public native authority permits module overrides;
    # keep the main scientific scene's equal-scale policy unchanged.
    ::GX::Native2D::core aspect $state($w,residualViewScene) auto
    set bounds [lindex [::GX::Native2D::core view $state($w,scene)] 6]
    set xmin [lindex $bounds [expr {$orientation eq "x_of_y"?1:0}]];set xmax [lindex $bounds [expr {$orientation eq "x_of_y"?3:2}]]
    if {$geometric} {set xmin 0;set xmax 1} elseif {$orientation eq "r_of_theta"} {set xmin [dict get $report angular_min];set xmax [dict get $report angular_max]}
    if {$predicted} {
        set sorted [lsort -real $xvalues];set xmin [lindex $sorted 0];set xmax [lindex $sorted end]
        set margin [expr {$xmax>$xmin?0.05*($xmax-$xmin):max(1e-12,abs($xmin)*.05,1.0)}]
        set xmin [expr {$xmin-$margin}];set xmax [expr {$xmax+$margin}]
    }
    ::GX::Native2D::core view $state($w,residualViewScene) [list [winfo width $canvas] $height $left $top [expr {[winfo width $canvas]-$right}] [expr {$height-$bottom}] [list $xmin [expr {-$maxabs}] $xmax $maxabs]]
    set zero [expr {($top+$bottom)/2.0}];$canvas create line $left $zero $right $zero -fill #94a3b8 -dash {3 3}
    foreach row $displayed {
        lassign $row x y offset;lassign [::GX::Native2D::core device $state($w,residualViewScene) [list $x $y]] px py
        if {$px<$left||$px>$right||$py<$top||$py>$bottom} continue
        $canvas create oval [expr {$px-2}] [expr {$py-2}] [expr {$px+2}] [expr {$py+2}] -fill #9a3412 -outline {} -tags residual_point
        lappend state($w,residualDevices) [list $px $py $offset]
    }
    if {[info exists state($w,residualReview)]&&[info exists state($w,residualReviewKey)]&&$state($w,residualReviewKey) eq $state($w,residualPlotCacheKey)} {
        set review $state($w,residualReview);set values [dict get $review values]
        lassign [::GX::Native2D::core device $state($w,residualViewScene) [list [lindex $values $column] [lindex $values 3]]] rx ry
        lassign [_screen $w {*}[dict get $review point]] px py
        foreach x [list $px $rx] y [list $py $ry] tag {residual_source_link residual_row_link} {
            $canvas create oval [expr {$x-6}] [expr {$y-6}] [expr {$x+6}] [expr {$y+6}] -outline #b44700 -width 2 -tags $tag
        }
        ::GX::native2DCanvasClipItems $canvas $state($w,scene) [$canvas find withtag residual_source_link]
        ::GX::native2DCanvasClipItems $canvas $state($w,residualViewScene) [$canvas find withtag residual_row_link]
    }
}
