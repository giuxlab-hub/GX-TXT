# CORE Graphs control for selecting plotted source rows and publishing Datasets.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::GraphSelectionGui {
    variable path ""
    variable graph ""
    variable variant ""
    variable pointRows {}
    variable seriesRows {}
    variable selectedRows {}
    variable selectedMembers {}
    variable mode point
    variable operation exclude
    variable outputId ""
    variable status ""
    variable picking 0
    variable priorClickBinding ""
    variable priorRightBinding ""
    variable priorDoubleBinding ""
}

proc ::GX::GraphSelectionGui::cancelPick {} {
    variable picking
    variable priorClickBinding
    variable priorRightBinding
    variable priorDoubleBinding
    set wasPicking $picking
    set picking 0
    if {![info exists ::GX::ui(graphPreview)]} return
    set canvas $::GX::ui(graphPreview)
    if {![winfo exists $canvas]} return
    if {$wasPicking} {
        # Point picking temporarily owns these gestures; restore the graph's
        # bindings so later legend and region edits keep their normal behavior.
        bind $canvas <Button-1> $priorClickBinding
        bind $canvas <Button-3> $priorRightBinding
        bind $canvas <Double-ButtonPress-1> $priorDoubleBinding
    }
    $canvas configure -cursor {}
}

proc ::GX::GraphSelectionGui::currentSeriesIds {} {
    variable seriesRows
    if {![winfo exists .graphselection.series]} { return {} }
    set out {}
    foreach index [.graphselection.series curselection] {
        lappend out [dict get [lindex $seriesRows $index] series_id]
    }
    return $out
}

proc ::GX::GraphSelectionGui::readPointIndex {artifact} {
    if {$::GX::currentSession eq "" || ![file isdirectory [file join $::GX::currentSession metadata]]} {
        error "Open a Session before selecting graph points."
    }
    set temporary [file join $::GX::currentSession metadata ".gxtxt_points_[pid]_[clock clicks].tsv"]
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
    set rows {}
    try {
        ::GX::PlotDatasetAPIv3::writePointIndex $artifact $temporary
        set input [::open $temporary r]
        fconfigure $input -encoding utf-8
        try {
            set header [gets $input]
            if {$header ne "series_id\tdataset_id\tsource_row\tx\ty\taxis\tpanel_id"} {
                error "Plot Dataset returned an unsupported point index."
            }
            while {[gets $input line] >= 0} {
                set fields [split $line "\t"]
                if {[llength $fields] != 7} { error "Plot Dataset returned an invalid point index row." }
                lappend rows [dict create series_id [lindex $fields 0] dataset_id [lindex $fields 1] \
                    source_row [lindex $fields 2] x [lindex $fields 3] y [lindex $fields 4] \
                    axis [lindex $fields 5] panel_id [lindex $fields 6]]
            }
        } finally { close $input }
    } finally { catch {file delete -- $temporary} }
    return $rows
}

proc ::GX::GraphSelectionGui::hasSelectableSeries {ref} {
    set spec [::GX::PlotDatasetAPIv2::loadSpec $ref]
    # Histograms and box plots display aggregate statistics, so a click on
    # their rendered mark cannot identify one original Dataset row.
    foreach panel [dict get $spec panels] {
        foreach series [dict get $panel series] {
            if {![dict exists $series enabled] || [dict get $series enabled]} {
                set kind [expr {[dict exists $series kind] ? [dict get $series kind] : "auto"}]
                set axis [expr {[dict exists $series axis] ? [dict get $series axis] : "left"}]
                if {$kind ni {histogram box_whisker} && $axis eq "left"} { return 1 }
            }
        }
    }
    return 0
}

proc ::GX::GraphSelectionGui::leftYUnitCompatible {geom unit seriesRows} {
    set declared [dict get $geom axis.1.y_source_unit]
    if {$declared ne ""} { return [expr {$declared eq $unit}] }
    # A multi-series graph can leave the shared Y source unit unspecified.
    # Its raw Y values are selectable only when the display transform is the
    # identity and every left-axis series uses the same canonical unit.
    if {[dict get $geom axis.1.y_display_unit] ne "" ||
        [dict get $geom axis.1.y_transform] ne "affine" ||
        abs(double([dict get $geom axis.1.y_display_to_source_scale])-1) > 1e-12 ||
        abs(double([dict get $geom axis.1.y_display_to_source_offset])) > 1e-12} {
        return 0
    }
    set units {}
    foreach series $seriesRows {
        if {[dict get $series axis] eq "left"} { lappend units [dict get $series y_unit] }
    }
    set units [lsort -unique $units]
    return [expr {[llength $units] == 1 && [lindex $units 0] eq $unit}]
}

proc ::GX::GraphSelectionGui::sourceNumericUnit {dataset variable} {
    set unit [::GX::datasetVariableUnit $dataset [dict get $variable canonical]]
    # The Dataset reader decodes elapsed_time/hms values to seconds. The
    # declared display unit (often h) does not describe these numeric rows.
    if {[dict exists $variable value_kind] && [dict exists $variable value_format] &&
        [dict get $variable value_kind] eq "elapsed_time" &&
        [dict get $variable value_format] eq "hms"} { return s }
    return $unit
}

proc ::GX::GraphSelectionGui::open {} {
    variable path
    variable graph
    variable variant
    variable pointRows
    variable seriesRows
    variable selectedRows
    variable selectedMembers
    variable mode
    variable operation
    variable outputId
    variable status
    set artifact [::GX::currentGraphPath]
    if {$artifact eq ""} { tk_messageBox -message "Select a graph first."; return }
    if {[catch {
        ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v2
        set ref [::GX::PlotDatasetAPIv2::plotRefForArtifact $artifact]
        if {$ref eq "" || [dict get $ref graph_id] eq "plot.dataset.xyz"} {
            error "Graphical Dataset selection requires a 2D Plot Dataset graph."
        }
        if {![hasSelectableSeries $ref]} {
            error "Aggregate distribution plots do not expose individual plotted source points."
        }
        ::GX::plotRegionCanvasFrame $artifact
        set newRows [readPointIndex $artifact]
        set newSeries [::GX::graphSeriesList plot.dataset [dict get $ref graph_id] [dict get $ref variant_id]]
        if {![llength $newRows] || ![llength $newSeries]} {
            error "This graph has no selectable canonical source points."
        }
    } failure]} {
        tk_messageBox -icon error -title "Select graph data" -message $failure
        return
    }
    set path $artifact
    set graph [dict get $ref graph_id]
    set variant [dict get $ref variant_id]
    set pointRows $newRows
    set seriesRows $newSeries
    set selectedRows [dict create]
    set selectedMembers [dict create]
    set mode point
    set operation exclude
    set outputId "graph.selection.[clock seconds]"
    set status "Choose one or more series, then click a plotted point or draw an area."
    catch {destroy .graphselection}
    set w .graphselection
    toplevel $w
    wm title $w "Select graph data"
    wm transient $w .
    wm protocol $w WM_DELETE_WINDOW {::GX::GraphSelectionGui::cancelPick; destroy .graphselection}
    ttk::label $w.intro -text "Publish selected or remaining source rows as a new Session Dataset. Point clicks use the exact source row; area selection scans the complete source Dataset." -wraplength 640
    pack $w.intro -fill x -padx 10 -pady 8
    ttk::label $w.seriesLabel -text "Series (Ctrl/Shift to select several)"
    pack $w.seriesLabel -anchor w -padx 10
    listbox $w.series -selectmode extended -height [expr {min(8,max(2,[llength $seriesRows]))}] -exportselection 0 -width 75
    pack $w.series -fill x -padx 10 -pady {2 8}
    foreach row $seriesRows {
        set label [dict get $row label]
        if {$label eq ""} { set label [dict get $row series_id] }
        $w.series insert end "$label - [dict get $row dataset_id]"
    }
    $w.series selection set 0 end
    ttk::frame $w.mode
    ttk::radiobutton $w.mode.point -text "Individual points" -value point -variable ::GX::GraphSelectionGui::mode
    ttk::radiobutton $w.mode.area -text "Graphical area" -value area -variable ::GX::GraphSelectionGui::mode
    ttk::button $w.mode.pick -text "Click point in graph" -command ::GX::GraphSelectionGui::beginPointPick
    ttk::button $w.mode.draw -text "Draw area in graph" -command {::GX::GraphSelectionGui::cancelPick; set ::GX::GraphSelectionGui::mode area; ::GX::plotRegionBegin}
    pack $w.mode.point $w.mode.area $w.mode.pick $w.mode.draw -side left -padx 4
    pack $w.mode -anchor w -padx 10 -pady 5
    ttk::frame $w.action
    ttk::radiobutton $w.action.keep -text "Keep selected" -value keep -variable ::GX::GraphSelectionGui::operation
    ttk::radiobutton $w.action.exclude -text "Exclude selected" -value exclude -variable ::GX::GraphSelectionGui::operation
    pack $w.action.keep $w.action.exclude -side left -padx 4
    pack $w.action -anchor w -padx 10 -pady 5
    ttk::frame $w.output
    ttk::label $w.output.label -text "New Dataset ID"
    ttk::entry $w.output.id -textvariable ::GX::GraphSelectionGui::outputId -width 42
    pack $w.output.label $w.output.id -side left -padx 4
    pack $w.output -anchor w -padx 10 -pady 5
    ttk::label $w.status -textvariable ::GX::GraphSelectionGui::status -wraplength 640
    pack $w.status -fill x -padx 10 -pady 8
    ttk::frame $w.buttons
    ttk::button $w.buttons.publish -text "Create Dataset" -command ::GX::GraphSelectionGui::publish
    ttk::button $w.buttons.save -text "Save Selection" -command {::GX::GraphSelectionGui::publish selection}
    ttk::button $w.buttons.clear -text "Clear picked points" -command ::GX::GraphSelectionGui::clearPoints
    ttk::button $w.buttons.close -text "Close" -command {::GX::GraphSelectionGui::cancelPick; destroy .graphselection}
    pack $w.buttons.publish $w.buttons.save $w.buttons.clear $w.buttons.close -side left -padx 4
    pack $w.buttons -anchor e -padx 10 -pady 10
}
proc ::GX::GraphSelectionGui::clearPoints {} {
    variable selectedRows;variable selectedMembers;variable status
    set selectedRows [dict create];set selectedMembers [dict create];set status "Point selection cleared."
}

proc ::GX::GraphSelectionGui::beginPointPick {} {
    variable path
    variable picking
    variable priorClickBinding
    variable priorRightBinding
    variable priorDoubleBinding
    variable mode
    variable status
    if {![winfo exists .graphselection] || [::GX::currentGraphPath] ne $path} {
        tk_messageBox -icon error -message "Return to the graph used to open this selection."
        return
    }
    if {![llength [currentSeriesIds]]} { tk_messageBox -message "Choose at least one series."; return }
    if {$picking} { cancelPick }
    set mode point
    catch {::GX::plotRegionCancelPick}
    catch {::GX::cancelLegendPick}
    set picking 1
    set canvas $::GX::ui(graphPreview)
    set priorClickBinding [bind $canvas <Button-1>]
    set priorRightBinding [bind $canvas <Button-3>]
    set priorDoubleBinding [bind $canvas <Double-ButtonPress-1>]
    bind $canvas <Button-1> {::GX::GraphSelectionGui::pickClick %x %y}
    bind $canvas <Double-ButtonPress-1> {::GX::GraphSelectionGui::pickClick %x %y}
    bind $canvas <Button-3> {::GX::GraphSelectionGui::cancelPick}
    $canvas configure -cursor crosshair
    set status "Click a point in the graph; repeat to select several. Right click ends picking."
}

proc ::GX::GraphSelectionGui::pickClick {x y} {
    variable path
    variable pointRows
    variable seriesRows
    variable selectedRows
    variable selectedMembers
    variable status
    variable picking
    if {!$picking || [::GX::currentGraphPath] ne $path} { cancelPick; return }
    set selected [currentSeriesIds]
    if {[catch {set geom [::GX::plotRegionGeometry $path]} failure]} {
        cancelPick; tk_messageBox -icon error -message $failure; return
    }
    set best {}
    set bestDistance 145.0
    set compatible [dict create]
    foreach series $seriesRows {
        set ds [dict get $series dataset_id]
        set xVariable [::GX::datasetVariableById $ds [dict get $series x_variable_id]]
        set yVariable [::GX::datasetVariableById $ds [dict get $series y_variable_id]]
        set xUnit [sourceNumericUnit $ds $xVariable]
        set yUnit [sourceNumericUnit $ds $yVariable]
        if {$xUnit eq [dict get $geom axis.1.x_source_unit] &&
            [leftYUnitCompatible $geom $yUnit $seriesRows] &&
            [dict get $geom axis.1.y_transform] eq "affine"} {
            dict set compatible [dict get $series series_id] 1
        }
    }
    foreach row $pointRows {
        if {[dict get $row series_id] ni $selected} continue
        if {![dict exists $compatible [dict get $row series_id]]} continue
        # Calibrated geometry already guarantees one primary 2D axes. Its
        # panel may have a domain-specific ID (for example, minimization).
        if {[dict get $row axis] ne "left"} continue
        if {[catch {
            set dx [::GX::datasetSelectionSourceToDisplay $geom x [dict get $row x]]
            set dy [::GX::datasetSelectionSourceToDisplay $geom y [dict get $row y]]
            lassign [::GX::plotRegionDataToCanvas $path $dx $dy] px py
        }]} continue
        set distance [expr {($px-$x)*($px-$x)+($py-$y)*($py-$y)}]
        if {$distance < $bestDistance} { set best $row; set bestDistance $distance }
    }
    if {$best eq ""} { set status "No compatible selected-series point lies within 12 preview pixels. Point picking needs a left-axis series with the calibrated source units."; return }
    set dataset [dict get $best dataset_id]
    set sourceRow [dict get $best source_row]
    dict set selectedRows $dataset $sourceRow 1
    dict set selectedMembers [dict get $best series_id] $sourceRow 1
    set total 0
    dict for {member rows} $selectedMembers { incr total [dict size $rows] }
    set status "Selected $total source point(s). Latest: [dict get $best series_id], source row $sourceRow."
}

proc ::GX::GraphSelectionGui::areaRows {} {
    variable path
    variable graph
    variable variant
    variable seriesRows
    variable status
    variable selectedMembers
    set info [::GX::plotRegionCurrentInfo]
    if {[llength $info] != 3 || [lindex $info 2] ne $path} { error "Return to the source graph and draw an area." }
    lassign $info mid graphKey _
    ::GX::plotRegionEnsure $mid $graphKey
    if {!$::GX::plotRegion($mid,$graphKey,enabled)} { error "Draw an area with Select area first." }
    set chosen [currentSeriesIds]
    if {![llength $chosen]} { error "Choose at least one series." }
    set geom [::GX::plotRegionGeometry $path]
    set bounds [dict create \
        x_min [::GX::datasetSelectionDisplayToSource $geom x $::GX::plotRegion($mid,$graphKey,x_min)] \
        x_max [::GX::datasetSelectionDisplayToSource $geom x $::GX::plotRegion($mid,$graphKey,x_max)]]
    if {[::GX::plotRegionType $mid $graphKey] eq "rectangle"} {
        dict set bounds y_min [::GX::datasetSelectionDisplayToSource $geom y $::GX::plotRegion($mid,$graphKey,y_min)]
        dict set bounds y_max [::GX::datasetSelectionDisplayToSource $geom y $::GX::plotRegion($mid,$graphKey,y_max)]
    }
    set result [dict create]
    set selectedMembers [dict create]
    foreach row $seriesRows {
        if {[dict get $row series_id] ni $chosen} continue
        set ds [dict get $row dataset_id]
        set xId [dict get $row x_variable_id]
        set yId [dict get $row y_variable_id]
        set xUnit [sourceNumericUnit $ds [::GX::datasetVariableById $ds $xId]]
        if {$xUnit ne [dict get $geom axis.1.x_source_unit]} {
            error "Series [dict get $row series_id] uses a different X source unit; this area needs a series-specific coordinate conversion."
        }
        if {[dict exists $bounds y_min]} {
            if {[dict get $row axis] ne "left"} { error "Rectangle selection is available on the left Y axis only." }
            set yUnit [sourceNumericUnit $ds [::GX::datasetVariableById $ds $yId]]
            if {![leftYUnitCompatible $geom $yUnit $seriesRows]} {
                error "Series [dict get $row series_id] uses a different Y source unit."
            }
        }
        set rows [::GX::GraphSelectionAPIv1::selectRegionRows $::GX::currentSession $ds $xId $yId [dict get $row row_filters] $bounds]
        set numbers [dict create]
        foreach number $rows {dict set numbers $number 1}
        dict set selectedMembers [dict get $row series_id] $numbers
        foreach number $rows { dict set result $ds $number 1 }
    }
    return $result
}

proc ::GX::GraphSelectionGui::publish {{target dataset}} {
    variable path
    variable graph
    variable variant
    variable selectedRows
    variable selectedMembers;variable seriesRows
    variable mode
    variable operation
    variable outputId
    variable status
    if {[::GX::currentGraphPath] ne $path} { tk_messageBox -icon error -message "Return to the source graph before publishing."; return }
    if {[catch {
        if {$mode eq "area"} { set rows [areaRows] } else { set rows $selectedRows }
        if {![dict size $rows]} { error "Select at least one point or draw an area containing source data." }
        set stem [string trim $outputId]
        if {$target eq "dataset" && $stem eq ""} { error "Enter an output Dataset ID." }
        set members {}
        set chosen [currentSeriesIds]
        foreach series $seriesRows {
            set member [dict get $series series_id]
            if {$member ni $chosen} continue
            set numbers [expr {[dict exists $selectedMembers $member] ? [dict get $selectedMembers $member] : {}}]
            lappend members [dict create member_id $member dataset_id [dict get $series dataset_id] x_variable_id [dict get $series x_variable_id] y_variable_id [dict get $series y_variable_id] rows [lsort -integer [dict keys $numbers]] row_operation $operation row_filters [dict get $series row_filters]]
        }
        set metadata [dict create selection.producer core.graph_selection selection.graph_id $graph selection.variant_id $variant selection.mode $mode selection.operation $operation]
        if {$target eq "selection"} {
            set id [::GX::datasetSelectionCreateMembers $::GX::currentSession $members [dict create producer_module plot.dataset producer_graph $graph producer_variant $variant]]
            ::GX::writeManifest [file join $::GX::currentSession metadata manifest.ini]
            set status "Saved $id ([llength $members] source members) for Dataset Extract."
        } else {
        set result [::GX::GraphSelectionAPIv1::publishMembers $::GX::currentSession $members $stem $metadata]
        set status "Created [dict get $result dataset_id] ([dict get $result row_count] rows) from [llength $members] selected member(s)."
        }
        catch {::GX::refreshManifestPreview}
    } failure]} {
        tk_messageBox -icon error -title "Create selection Dataset" -message $failure
    }
}

proc ::GX::launchGui_before_core_ui_surfaces {} {
    ::GX::launchGui_before_graph_selection
    set actions .top.nb.graphs.actions
    if {[winfo exists $actions] && ![winfo exists $actions.selectdata]} {
        ttk::button $actions.selectdata -text "Select data..." -command ::GX::GraphSelectionGui::open
        pack $actions.selectdata -side left -padx 3 -before $actions.sep2
        $actions.selectdata state disabled
    }
}

proc ::GX::GraphSelectionGui::updateButton {} {
    set button .top.nb.graphs.actions.selectdata
    if {![winfo exists $button]} return
    set artifact [::GX::currentGraphPath]
    set available 0
    if {$artifact ne ""} {
        if {![catch {
            ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v2
            set ref [::GX::PlotDatasetAPIv2::plotRefForArtifact $artifact]
            if {$ref ne "" && [dict get $ref graph_id] ne "plot.dataset.xyz" &&
                [hasSelectableSeries $ref]} {
                ::GX::plotRegionGeometry $artifact
                set available 1
            }
        }]} {}
    }
    if {$available} { $button state !disabled } else { $button state disabled }
}

proc ::GX::previewGraph {} {
    ::GX::previewGraph_before_graph_selection
    catch {::GX::GraphSelectionGui::updateButton}
    if {[llength [info commands ::GX::native3DPreviewPlotSelection]]} {::GX::native3DPreviewPlotSelection}
}
