# GX-TXT Plot Region Selection API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# Optional rectangle selection in primary 2D data coordinates.

namespace eval ::GX {
    variable plotRegionApiVersion 1
    variable plotRegion
    variable regionPickActive 0
    variable regionPickStartX 0
    variable regionPickStartY 0
    variable regionPickModule ""
    variable regionPickGraph ""
    variable regionPickPng ""
    variable regionPickPressed 0
    variable regionPickMode create
    variable regionPickHandle ""
    variable regionPickSelectionId ""
    variable regionPickOriginalRect {}
    variable regionPickPriorDoubleBinding ""
    variable regionPickDatasetBinding 1
}

proc ::GX::plotRegionType_before_plot_variant {moduleId graphId} {
    set typ [string tolower [string trim [moduleGraphField $moduleId $graphId region_selection rectangle]]]
    if {$typ eq ""} { set typ rectangle }
    return $typ
}

proc ::GX::plotRegionSupports_before_plot_variant {moduleId graphId} {
    if {$moduleId eq "" || $graphId eq ""} { return 0 }
    set on [string tolower [string trim [moduleGraphField $moduleId $graphId supports_region_selection 0]]]
    if {$on ni {1 true yes on}} { return 0 }
    set typ [plotRegionType $moduleId $graphId]
    return [expr {$typ in {rectangle x_range}}]
}

proc ::GX::plotRegionEnsure {moduleId graphId} {
    variable plotRegion
    foreach {f d} {enabled 0 space data axis primary x_min "" x_max "" y_min "" y_max ""} {
        if {![info exists plotRegion($moduleId,$graphId,$f)]} { set plotRegion($moduleId,$graphId,$f) $d }
    }
}

proc ::GX::plotRegionMetadataPath {png} {
    set d [file dirname $png]; set n [file rootname [file tail $png]]
    return [file join $d .gxtxt_plotmeta "${n}.ini"]
}

proc ::GX::plotRegionCurrentInfo {} {
    set p [currentGraphPath]; if {$p eq ""} { return {} }
    set q [nativeGraphInfoForPath $p]
    if {[llength $q] != 2} { return {} }
    return [list [lindex $q 0] [graphKeyForPath $p] $p]
}

proc ::GX::plotRegionGeometry {png} {
    set fn [plotRegionMetadataPath $png]
    if {![file isfile $fn]} { error "Plot geometry metadata is missing. Rerender this plot once with GX-TXT v0.9.1 or later." }
    set d [parseIni $fn]
    if {![dict exists $d plot_metadata.selection_supported] || ![dict get $d plot_metadata.selection_supported]} {
        # A shared-X Plot Dataset stack has genuine multi-panel topology in
        # its main sidecar. Its established X-range selection calibration is
        # stored separately so it cannot disguise the primary axes count.
        set native [nativeGraphInfoForPath $png]
        if {[llength $native] == 2 && [plotRegionType [lindex $native 0] [graphKeyForPath $png]] eq "x_range"} {
            set special [file join [file dirname $fn] "[file rootname [file tail $png]].xrange.ini"]
            if {[file isfile $special]} {
                set xdata [parseIni $special]
                if {[dict exists $xdata plot_metadata.selection_supported] && [dict get $xdata plot_metadata.selection_supported]} {
                    set d $xdata
                }
            }
        }
    }
    if {![dict exists $d plot_metadata.selection_supported] || ![dict get $d plot_metadata.selection_supported]} {
        if {[dict exists $d plot_metadata.selection_topology_supported]} {
            if {![dict get $d plot_metadata.selection_topology_supported]} {
                error "Region Selection API v1 requires one primary 2D data axes. This plot has unsupported multi-panel or 3D topology."
            }
            if {![dict exists $d plot_metadata.selection_calibration_valid] ||
                ![dict get $d plot_metadata.selection_calibration_valid]} {
                error "Region Selection calibration is unavailable for this valid 2D plot. Rerender the plot to regenerate its raster geometry."
            }
        }
        error "Region Selection API v1 supports only one primary 2D data axes. This plot is multi-panel, 3D, or lacks calibrated legacy metadata."
    }
    foreach k {axis.1.position axis.1.xlim axis.1.ylim axis.1.xscale axis.1.yscale axis.1.xdir axis.1.ydir} {
        if {![dict exists $d $k]} { error "Incomplete plot geometry metadata: $k" }
    }
    return $d
}

proc ::GX::plotRegionCanvasFrame {png} {
    set geom [previewImageGeometry]; if {[llength $geom] != 4} { error "Plot preview geometry is unavailable." }
    lassign $geom ox oy iw ih
    set d [plotRegionGeometry $png]
    if {![dict exists $d axis.1.pixel_rect] || ![dict exists $d plot_metadata.image_width] || ![dict exists $d plot_metadata.image_height]} {
        error "The plot lacks calibrated raster geometry. Rerender it before selecting an area."
    }
    set rect [splitList [dict get $d axis.1.pixel_rect]]
    if {[llength $rect] != 4} { error "Invalid calibrated data rectangle." }
    lassign $rect px0 py0 px1 py1
    set pw [dict get $d plot_metadata.image_width]
    set ph [dict get $d plot_metadata.image_height]
    foreach v [list $px0 $py0 $px1 $py1 $pw $ph] {
        if {![string is double -strict $v]} { error "Invalid calibrated raster geometry." }
    }
    if {$pw <= 0 || $ph <= 0 || $px0 < 0 || $py0 < 0 || $px1 >= $pw || $py1 >= $ph || $px1 <= $px0 || $py1 <= $py0} {
        error "Calibrated data rectangle is outside the PNG."
    }
    set x0 [expr {$ox + double($px0)*$iw/$pw}]; set x1 [expr {$ox + double($px1)*$iw/$pw}]
    set y0 [expr {$oy + double($py0)*$ih/$ph}]; set y1 [expr {$oy + double($py1)*$ih/$ph}]
    return [list $x0 $y0 $x1 $y1 $d]
}

proc ::GX::plotRegionMapFraction {f lim scale dir} {
    lassign $lim a b
    if {$dir eq "reverse"} { set f [expr {1.0-$f}] }
    if {$scale eq "log"} {
        if {$a <= 0 || $b <= 0} { error "Invalid logarithmic plot limits." }
        return [expr {exp(log(double($a)) + $f*(log(double($b))-log(double($a))))}]
    }
    return [expr {double($a) + $f*(double($b)-double($a))}]
}

proc ::GX::plotRegionDataFraction {v lim scale dir} {
    lassign $lim a b
    if {$scale eq "log"} {
        if {$v <= 0 || $a <= 0 || $b <= 0} { return 0.0 }
        set f [expr {(log(double($v))-log(double($a)))/(log(double($b))-log(double($a)))}]
    } else {
        set f [expr {(double($v)-double($a))/(double($b)-double($a))}]
    }
    if {$dir eq "reverse"} { set f [expr {1.0-$f}] }
    return $f
}

proc ::GX::plotRegionCanvasToData {png x y} {
    lassign [plotRegionCanvasFrame $png] x0 y0 x1 y1 d
    # A mouse event is rounded to an integer canvas pixel. Accept only the
    # half-pixel uncertainty at the measured raster border, then clamp it.
    if {$x < $x0-0.5 || $x > $x1+0.5 || $y < $y0-0.5 || $y > $y1+0.5} { return {} }
    set x [expr {min($x1,max($x0,$x))}]; set y [expr {min($y1,max($y0,$y))}]
    set u [expr {($x-$x0)/double($x1-$x0)}]; set v [expr {1.0-($y-$y0)/double($y1-$y0)}]
    set xl [splitList [dict get $d axis.1.xlim]]; set yl [splitList [dict get $d axis.1.ylim]]
    set xd [string tolower [dict get $d axis.1.xdir]]; set yd [string tolower [dict get $d axis.1.ydir]]
    set xs [string tolower [dict get $d axis.1.xscale]]; set ys [string tolower [dict get $d axis.1.yscale]]
    set xv [plotRegionMapFraction $u $xl $xs $xd]; set yv [plotRegionMapFraction $v $yl $ys $yd]
    return [list $xv $yv]
}

proc ::GX::plotRegionDataToCanvas {png x y} {
    lassign [plotRegionCanvasFrame $png] x0 y0 x1 y1 d
    set xl [splitList [dict get $d axis.1.xlim]]; set yl [splitList [dict get $d axis.1.ylim]]
    set xd [string tolower [dict get $d axis.1.xdir]]; set yd [string tolower [dict get $d axis.1.ydir]]
    set xs [string tolower [dict get $d axis.1.xscale]]; set ys [string tolower [dict get $d axis.1.yscale]]
    set u [plotRegionDataFraction $x $xl $xs $xd]; set v [plotRegionDataFraction $y $yl $ys $yd]
    return [list [expr {$x0+$u*($x1-$x0)}] [expr {$y0+(1.0-$v)*($y1-$y0)}]]
}

proc ::GX::plotRegionSyncFromSelection {mid gid png} {
    variable plotRegion
    if {![llength [info commands ::GX::datasetSelectionForPlot]]} { return "" }
    set sid [datasetSelectionForPlot $mid $gid]
    if {$sid eq ""} { return "" }
    set geom [plotRegionGeometry $png]
    plotRegionEnsure $mid $gid
    foreach axis {x y} {
        foreach edge {min max} {
            set value [datasetSelectionField $sid "${axis}_${edge}" ""]
            if {$value eq ""} continue
            set plotRegion($mid,$gid,${axis}_${edge}) [datasetSelectionSourceToDisplay $geom $axis $value]
        }
    }
    return $sid
}

proc ::GX::plotRegionVisibleSelection {mid gid png} {
    set sid [plotRegionSyncFromSelection $mid $gid $png]
    if {$sid ne ""} { return $sid }
    if {![llength [info commands ::GX::datasetSelectionIds]]} { return "" }
    set decoded [plotVariantDecodeKey $mid $gid]
    set base $gid; set variant ""
    if {[llength $decoded] == 2} { lassign $decoded base variant }
    foreach id [datasetSelectionIds] {
        if {[datasetSelectionField $id producer_module ""] eq $mid &&
            [datasetSelectionField $id producer_graph ""] eq $base &&
            [datasetSelectionField $id producer_variant ""] eq $variant} { return "__other_binding__" }
    }
    return ""
}

proc ::GX::plotRegionVisualRect {mid gid png} {
    variable plotRegion
    set typ [plotRegionType $mid $gid]
    if {$typ eq "x_range"} {
        lassign [plotRegionCanvasFrame $png] _ y0 _ y1 geom
        set yl [splitList [dict get $geom axis.1.ylim]]
        lassign [plotRegionDataToCanvas $png $plotRegion($mid,$gid,x_min) [lindex $yl 0]] x0 _
        lassign [plotRegionDataToCanvas $png $plotRegion($mid,$gid,x_max) [lindex $yl 1]] x1 _
    } else {
        lassign [plotRegionDataToCanvas $png $plotRegion($mid,$gid,x_min) $plotRegion($mid,$gid,y_min)] ax ay
        lassign [plotRegionDataToCanvas $png $plotRegion($mid,$gid,x_max) $plotRegion($mid,$gid,y_max)] bx by
        set x0 [expr {min($ax,$bx)}]; set x1 [expr {max($ax,$bx)}]
        set y0 [expr {min($ay,$by)}]; set y1 [expr {max($ay,$by)}]
    }
    return [list [expr {min($x0,$x1)}] [expr {min($y0,$y1)}] [expr {max($x0,$x1)}] [expr {max($y0,$y1)}]]
}

proc ::GX::plotRegionHitHandle {typ rect x y} {
    lassign $rect x0 y0 x1 y1
    set tol 8.0
    if {$x < $x0-$tol || $x > $x1+$tol || $y < $y0-$tol || $y > $y1+$tol} { return "" }
    set left [expr {abs($x-$x0)<=$tol}]
    set right [expr {abs($x-$x1)<=$tol}]
    if {$typ eq "x_range"} {
        if {$left} { return left }
        if {$right} { return right }
        if {$x >= $x0 && $x <= $x1 && $y >= $y0 && $y <= $y1} { return move }
        return ""
    }
    set top [expr {abs($y-$y0)<=$tol}]
    set bottom [expr {abs($y-$y1)<=$tol}]
    if {$left && $top} { return left_top }
    if {$right && $top} { return right_top }
    if {$left && $bottom} { return left_bottom }
    if {$right && $bottom} { return right_bottom }
    if {$left && $y >= $y0 && $y <= $y1} { return left }
    if {$right && $y >= $y0 && $y <= $y1} { return right }
    if {$top && $x >= $x0 && $x <= $x1} { return top }
    if {$bottom && $x >= $x0 && $x <= $x1} { return bottom }
    if {$x >= $x0 && $x <= $x1 && $y >= $y0 && $y <= $y1} { return move }
    return ""
}

proc ::GX::plotRegionDragRect {rect handle dx dy frame typ} {
    lassign $rect x0 y0 x1 y1
    lassign $frame fx0 fy0 fx1 fy1 _
    if {$handle eq "move"} {
        set dx [expr {min($fx1-$x1,max($fx0-$x0,$dx))}]
        set x0 [expr {$x0+$dx}]; set x1 [expr {$x1+$dx}]
        if {$typ eq "rectangle"} {
            set dy [expr {min($fy1-$y1,max($fy0-$y0,$dy))}]
            set y0 [expr {$y0+$dy}]; set y1 [expr {$y1+$dy}]
        }
    } else {
        if {[string first left $handle] >= 0} { set x0 [expr {min($x1-1,max($fx0,$x0+$dx))}] }
        if {[string first right $handle] >= 0} { set x1 [expr {max($x0+1,min($fx1,$x1+$dx))}] }
        if {$typ eq "rectangle"} {
            if {[string first top $handle] >= 0} { set y0 [expr {min($y1-1,max($fy0,$y0+$dy))}] }
            if {[string first bottom $handle] >= 0} { set y1 [expr {max($y0+1,min($fy1,$y1+$dy))}] }
        }
    }
    return [list $x0 $y0 $x1 $y1]
}

proc ::GX::plotRegionSetFromRect {mid gid png rect} {
    variable plotRegion
    lassign $rect x0 y0 x1 y1
    set a [plotRegionCanvasToData $png $x0 $y1]
    set b [plotRegionCanvasToData $png $x1 $y0]
    if {[llength $a]!=2 || [llength $b]!=2} { error "Selection is outside the data rectangle." }
    lassign $a xa ya; lassign $b xb yb
    plotRegionEnsure $mid $gid
    set plotRegion($mid,$gid,enabled) 1
    set plotRegion($mid,$gid,x_min) [expr {min($xa,$xb)}]
    set plotRegion($mid,$gid,x_max) [expr {max($xa,$xb)}]
    if {[plotRegionType $mid $gid] eq "x_range"} {
        set geom [plotRegionGeometry $png]
        set yl [splitList [dict get $geom axis.1.ylim]]
        set plotRegion($mid,$gid,y_min) [lindex $yl 0]
        set plotRegion($mid,$gid,y_max) [lindex $yl 1]
    } else {
        set plotRegion($mid,$gid,y_min) [expr {min($ya,$yb)}]
        set plotRegion($mid,$gid,y_max) [expr {max($ya,$yb)}]
    }
}

proc ::GX::plotRegionDrawPersistent {} {
    variable ui; variable plotRegion; variable regionPickActive
    if {$regionPickActive} { return }
    if {![info exists ui(graphPreview)] || ![winfo exists $ui(graphPreview)]} { return }
    set c $ui(graphPreview); $c delete regionSelectionOverlay
    set info [plotRegionCurrentInfo]; if {[llength $info] != 3} { return }
    lassign $info mid gid png
    if {![plotRegionSupports $mid $gid]} { return }
    plotRegionEnsure $mid $gid
    if {!$plotRegion($mid,$gid,enabled)} { return }
    if {[catch {set sid [plotRegionVisibleSelection $mid $gid $png]}]} { return }
    if {$sid eq "__other_binding__"} { return }
    if {[catch {set rect [plotRegionVisualRect $mid $gid $png]}]} { return }
    lassign $rect x0 y0 x1 y1
    $c create rectangle $x0 $y0 $x1 $y1 -outline #0066CC -width 2 -dash {6 3} -tags regionSelectionOverlay
    set label [expr {[plotRegionType $mid $gid] eq "x_range" ? "selected X range" : "selected area"}]
    $c create text [expr {$x0+5}] [expr {$y0+5}] -anchor nw -text $label -fill #003366 -tags regionSelectionOverlay
}

proc ::GX::plotRegionCancelPick {} {
    variable regionPickActive; variable regionPickPressed; variable ui
    variable regionPickPriorDoubleBinding
    set wasActive $regionPickActive
    set regionPickActive 0; set regionPickPressed 0
    if {[info exists ui(graphPreview)] && [winfo exists $ui(graphPreview)]} {
        set c $ui(graphPreview)
        bind $c <ButtonPress-1> {}; bind $c <B1-Motion> {}; bind $c <ButtonRelease-1> {}; bind $c <Button-3> {}
        if {$wasActive} { bind $c <Double-ButtonPress-1> $regionPickPriorDoubleBinding }
        $c configure -cursor {}; $c delete regionPickOverlay
    }
    catch {plotRegionDrawPersistent}
}

proc ::GX::plotRegionBegin {} {
    variable regionPickActive; variable regionPickPressed
    variable regionPickModule; variable regionPickGraph; variable regionPickPng; variable ui
    variable regionPickPriorDoubleBinding
    variable regionPickDatasetBinding
    set info [plotRegionCurrentInfo]
    if {[llength $info] != 3} { tk_messageBox -message "Select a descriptor-defined plot first."; return }
    lassign $info mid gid png
    if {![plotRegionSupports $mid $gid]} { tk_messageBox -message "This plot does not opt in to Plot Region Selection API v1."; return }
    if {[catch {plotRegionCanvasFrame $png} err]} { tk_messageBox -icon error -message $err; return }
    # The older Dataset Selection API models one canonical axis binding.
    # Keep the graphical area usable for multi-series plots; Select data...
    # applies it to the chosen series through the CORE Graph Selection API.
    set regionPickDatasetBinding 1
    if {[llength [info commands ::GX::datasetSelectionForPlot]] &&
        [catch {datasetSelectionForPlot $mid $gid}]} { set regionPickDatasetBinding 0 }
    if {$regionPickActive} { plotRegionCancelPick }
    catch {cancelLegendPick}
    set regionPickActive 1; set regionPickPressed 0
    set regionPickModule $mid; set regionPickGraph $gid; set regionPickPng $png
    set c $ui(graphPreview); $c delete regionSelectionOverlay; $c configure -cursor crosshair
    set regionPickPriorDoubleBinding [bind $c <Double-ButtonPress-1>]
    bind $c <ButtonPress-1> {::GX::plotRegionPress %x %y}
    # Tk classifies two nearby clicks on successive Variants as a double
    # click, suppressing the single-press binding used to start the drag.
    bind $c <Double-ButtonPress-1> {::GX::plotRegionPress %x %y}
    bind $c <B1-Motion> {::GX::plotRegionMotion %x %y}
    bind $c <ButtonRelease-1> {::GX::plotRegionRelease %x %y}
    bind $c <Button-3> {::GX::plotRegionCancelPick}
    set ui(graphInfo) "Drag in the data area to create a selection. Drag an existing edge, corner, or interior to edit it. Right-click cancels."
}

proc ::GX::plotRegionPress {x y} {
    variable regionPickStartX; variable regionPickStartY
    variable regionPickPressed; variable regionPickMode; variable regionPickHandle
    variable regionPickSelectionId; variable regionPickOriginalRect
    variable regionPickModule; variable regionPickGraph; variable regionPickPng; variable plotRegion; variable ui
    variable regionPickDatasetBinding
    set regionPickPressed 0
    set info [plotRegionCurrentInfo]
    if {[llength $info]!=3 || [lindex $info 0] ne $regionPickModule ||
        [lindex $info 1] ne $regionPickGraph || [lindex $info 2] ne $regionPickPng} { plotRegionCancelPick; return }
    if {[llength [plotRegionCanvasToData $regionPickPng $x $y]] != 2} { return }
    set regionPickStartX $x; set regionPickStartY $y
    set regionPickMode create; set regionPickHandle ""; set regionPickSelectionId ""
    if {[info exists plotRegion($regionPickModule,$regionPickGraph,enabled)] &&
        $plotRegion($regionPickModule,$regionPickGraph,enabled) &&
        $regionPickDatasetBinding && [llength [info commands ::GX::datasetSelectionForPlot]]} {
        if {[catch {set sid [datasetSelectionForPlot $regionPickModule $regionPickGraph]} err]} {
            plotRegionCancelPick
            tk_messageBox -icon error -message $err
            return
        }
        if {$sid ne ""} {
            plotRegionSyncFromSelection $regionPickModule $regionPickGraph $regionPickPng
            set rect [plotRegionVisualRect $regionPickModule $regionPickGraph $regionPickPng]
            set handle [plotRegionHitHandle [plotRegionType $regionPickModule $regionPickGraph] $rect $x $y]
            if {$handle ne ""} {
                set regionPickMode edit; set regionPickHandle $handle
                set regionPickSelectionId $sid; set regionPickOriginalRect $rect
            }
        }
    }
    set regionPickPressed 1
    $ui(graphPreview) delete regionPickOverlay
}

proc ::GX::plotRegionMotion {x y} {
    variable regionPickActive; variable regionPickPressed
    variable regionPickStartX; variable regionPickStartY
    variable regionPickModule; variable regionPickGraph; variable regionPickPng
    variable regionPickMode; variable regionPickHandle; variable regionPickOriginalRect; variable ui
    if {!$regionPickActive || !$regionPickPressed} { return }
    if {[catch {set frame [plotRegionCanvasFrame $regionPickPng]}]} { return }
    lassign $frame x0 y0 x1 y1 _
    set x [expr {min($x1,max($x0,$x))}]; set y [expr {min($y1,max($y0,$y))}]
    set typ [plotRegionType $regionPickModule $regionPickGraph]
    if {$regionPickMode eq "edit"} {
        set rect [plotRegionDragRect $regionPickOriginalRect $regionPickHandle [expr {$x-$regionPickStartX}] [expr {$y-$regionPickStartY}] $frame $typ]
    } elseif {$typ eq "x_range"} {
        set rect [list [expr {min($regionPickStartX,$x)}] $y0 [expr {max($regionPickStartX,$x)}] $y1]
    } else {
        set rect [list [expr {min($regionPickStartX,$x)}] [expr {min($regionPickStartY,$y)}] [expr {max($regionPickStartX,$x)}] [expr {max($regionPickStartY,$y)}]]
    }
    set c $ui(graphPreview); $c delete regionPickOverlay
    $c create rectangle {*}$rect -outline #CC5500 -width 2 -dash {4 2} -tags regionPickOverlay
}

proc ::GX::plotRegionRelease {x y} {
    variable regionPickActive; variable regionPickPressed
    variable regionPickStartX; variable regionPickStartY
    variable regionPickModule; variable regionPickGraph; variable regionPickPng
    variable regionPickMode; variable regionPickHandle; variable regionPickSelectionId; variable regionPickOriginalRect
    variable regionPickDatasetBinding
    variable plotRegion; variable ui
    if {!$regionPickActive || !$regionPickPressed} { return }
    set info [plotRegionCurrentInfo]
    if {[llength $info]!=3 || [lindex $info 0] ne $regionPickModule ||
        [lindex $info 1] ne $regionPickGraph || [lindex $info 2] ne $regionPickPng} { plotRegionCancelPick; return }
    set frame [plotRegionCanvasFrame $regionPickPng]
    lassign $frame x0 y0 x1 y1 _
    set x [expr {min($x1,max($x0,$x))}]; set y [expr {min($y1,max($y0,$y))}]
    set typ [plotRegionType $regionPickModule $regionPickGraph]
    if {$regionPickMode eq "edit"} {
        set rect [plotRegionDragRect $regionPickOriginalRect $regionPickHandle [expr {$x-$regionPickStartX}] [expr {$y-$regionPickStartY}] $frame $typ]
    } elseif {$typ eq "x_range"} {
        set rect [list [expr {min($regionPickStartX,$x)}] $y0 [expr {max($regionPickStartX,$x)}] $y1]
    } else {
        set rect [list [expr {min($regionPickStartX,$x)}] [expr {min($regionPickStartY,$y)}] [expr {max($regionPickStartX,$x)}] [expr {max($regionPickStartY,$y)}]]
    }
    lassign $rect rx0 ry0 rx1 ry1
    if {$rx1-$rx0<1 || ($typ eq "rectangle" && $ry1-$ry0<1)} { plotRegionCancelPick; return }
    set prior [array get plotRegion "$regionPickModule,$regionPickGraph,*"]
    if {[catch {
        plotRegionSetFromRect $regionPickModule $regionPickGraph $regionPickPng $rect
        if {$regionPickDatasetBinding && [llength [info commands ::GX::datasetSelectionFromPlotRegion]]} {
            datasetSelectionFromPlotRegion $regionPickModule $regionPickGraph $regionPickPng $regionPickSelectionId
        }
    } err]} {
        foreach key [array names plotRegion "$regionPickModule,$regionPickGraph,*"] { unset plotRegion($key) }
        array set plotRegion $prior
        plotRegionCancelPick
        tk_messageBox -icon error -message $err
        return
    }
    plotRegionCancelPick
    catch {refreshManifestPreview}
    catch {plotRegionUpdateButtons}
    if {$typ eq "x_range"} {
        set ui(graphInfo) [format "Selected X range: %.9g .. %.9g" $plotRegion($regionPickModule,$regionPickGraph,x_min) $plotRegion($regionPickModule,$regionPickGraph,x_max)]
    } else {
        set ui(graphInfo) [format "Selected data region: X %.9g .. %.9g | Y %.9g .. %.9g" $plotRegion($regionPickModule,$regionPickGraph,x_min) $plotRegion($regionPickModule,$regionPickGraph,x_max) $plotRegion($regionPickModule,$regionPickGraph,y_min) $plotRegion($regionPickModule,$regionPickGraph,y_max)]
    }
}

proc ::GX::plotRegionClearCurrent {} {
    variable plotRegion
    set info [plotRegionCurrentInfo];if {[llength $info]!=3} return;lassign $info mid gid _
    plotRegionEnsure $mid $gid;set plotRegion($mid,$gid,enabled) 0
    catch {refreshManifestPreview};catch {drawGraphPreview}
    catch {plotRegionUpdateButtons}
}

# Persist only plots that opt in. Missing sections remain fully compatible.
proc ::GX::manifestStringV2_v091_before_dataset_selection {} {
    variable moduleOrder;variable plotRegion
    set out [::GX::manifestStringV2_v090_before_plot_region]
    append out "\n\[plot_region_selection_api\]\n";appendKV out version $::GX::plotRegionApiVersion
    foreach mid $moduleOrder { foreach gid [moduleGraphIds $mid] {
        if {![plotRegionSupports $mid $gid]} continue
        plotRegionEnsure $mid $gid
        append out "\n\[module_plot_region.$mid.$gid\]\n"
        foreach f {enabled space axis x_min x_max y_min y_max} { appendKV out $f $plotRegion($mid,$gid,$f) }
    }}
    return $out
}

proc ::GX::loadManifestV2_v091_before_dataset_selection {path} {
    variable moduleOrder;variable plotRegion
    ::GX::loadManifestV2_v090_before_plot_region $path
    array unset plotRegion *;set d [parseIni $path]
    foreach mid $moduleOrder { foreach gid [moduleGraphIds $mid] {
        if {![plotRegionSupports $mid $gid]} continue
        plotRegionEnsure $mid $gid
        foreach f {enabled space axis x_min x_max y_min y_max} { set k "module_plot_region.$mid.$gid.$f";if {[dict exists $d $k]} { set plotRegion($mid,$gid,$f) [dict get $d $k] } }
    }}
}

proc ::GX::writeStandardRuntimeConfig_v091_before_dataset_selection {id} {
    variable plotRegion
    set path [::GX::writeStandardRuntimeConfig_v090_before_plot_region $id]
    set gids [moduleGraphIds $id];if {![llength $gids]} { return $path }
    set fd [open $path a];fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "\n\[plot_region_selection_api\]";putKV $fd api_version $::GX::plotRegionApiVersion
    foreach gid $gids {
        if {![plotRegionSupports $id $gid]} continue
        plotRegionEnsure $id $gid
        puts $fd "\n\[plot.region.$gid\]";putKV $fd api_version 1
        foreach f {enabled space axis x_min x_max y_min y_max} { putKV $fd $f $plotRegion($id,$gid,$f) }
    }
    close $fd;return $path
}

# Keep the selected region visible in the ordinary preview.
proc ::GX::drawGraphPreview {} { ::GX::drawGraphPreview_v090_before_plot_region;catch {::GX::plotRegionDrawPersistent} }

# Add generic controls to the existing Plots toolbar; no plugin-specific GUI.
proc ::GX::launchGui_v091_before_dataset_notes {} {
    ::GX::launchGui_v090_before_plot_region
    set f .top.nb.graphs.actions
    if {[winfo exists $f] && ![winfo exists $f.region]} {
        ttk::button $f.region -text "Select area" -command ::GX::plotRegionBegin
        ttk::button $f.clearregion -text "Clear area" -command ::GX::plotRegionClearCurrent
        if {[winfo exists $f.sep2]} { pack $f.region $f.clearregion -side left -padx 3 -before $f.sep2 } else { pack $f.region $f.clearregion -side left -padx 3 }
    }
}

proc ::GX::plotRegionUpdateButtons {} {
    variable plotRegion
    set r .top.nb.graphs.actions.region; set c .top.nb.graphs.actions.clearregion
    if {![winfo exists $r]} { return }
    set info [plotRegionCurrentInfo]
    if {[llength $info] != 3} { $r state disabled; if {[winfo exists $c]} {$c state disabled}; return }
    lassign $info mid gid _
    if {![plotRegionSupports $mid $gid]} { $r state disabled; if {[winfo exists $c]} {$c state disabled}; return }
    $r state !disabled; plotRegionEnsure $mid $gid
    if {[winfo exists $c]} { if {$plotRegion($mid,$gid,enabled)} {$c state !disabled} else {$c state disabled} }
}

proc ::GX::previewGraph_before_clones {} { ::GX::previewGraph_v090_before_plot_region; catch {::GX::plotRegionUpdateButtons} }
