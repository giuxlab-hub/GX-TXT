# SPDX-License-Identifier: GPL-3.0-or-later
# Multi-series consultation uses CORE Curve Source streams and explicit filters.
proc ::GX::scientificDatasetSeriesBuild {w numeric} {
    variable ::GX::DatasetViewer::state
    set p $w.views.plot.series;ttk::frame $p;pack $p -fill x -padx 5
    set state($w,numeric) $numeric;set state($w,series) {};set state($w,queue) {}
    ttk::label $p.label -text {Overlay Y (Ctrl selects):}
    listbox $p.variables -listvariable ::GX::DatasetViewer::state($w,numeric) -selectmode extended -exportselection 0 -height 3 -width 24
    pack $p.label $p.variables -side left -padx 4
    ttk::frame $p.filters;pack $p.filters -side left -padx 4
    scientificDatasetFilterControls $p.filters $state($w,id) ::GX::DatasetViewer::state $w 1
    set state($w,memberVariable) {};set state($w,members) {}
}

proc ::GX::scientificDatasetMembersRead {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]} return
    if {[catch {
        datasetViewerCheck $w
        set chunk [tableStreamNext $state($w,memberStream)]
        foreach member [dict get [lindex [dict get $chunk columns] 0] values] {
            if {$member ni $state($w,members)} {lappend state($w,members) $member}
            if {[llength $state($w,members)]>1024} {error {More than 1024 family members; the canonical table retains access to the complete family.}}
        }
        if {[dict get $chunk eof]} {
            tableStreamClose $state($w,memberStream);unset state($w,memberStream)
            $w.views.plot.series.members selection set 0
            set state($w,status) {Select family members explicitly, then Plot; each member is a separate trace.}
        } else {set state($w,memberScan) [after 1 [list ::GX::scientificDatasetMembersRead $w]]}
    } message]} {
        if {[info exists state($w,memberStream)]} {tableStreamClose $state($w,memberStream);unset state($w,memberStream)}
        if {[info exists state($w,id)]} {set state($w,status) $message}
    }
}
proc ::GX::scientificDatasetViewerSelection {w} {
    variable ::GX::DatasetViewer::state
    if {$state($w,x) eq {}||$state($w,y) eq {}} {error {Choose explicit X and Y variables.}}
    set ys [list $state($w,y)]
    foreach index [$w.views.plot.series.variables curselection] {set id [lindex $state($w,numeric) $index];if {$id ni $ys} {lappend ys $id}}
    set unit [dict get [datasetVariableV3ById $state($w,id) $state($w,y)] unit]
    foreach id $ys {if {[dict get [datasetVariableV3ById $state($w,id) $id] unit] ne $unit} {error {Overlay variables must declare the same unit. Inspect different units separately; no automatic conversion is applied.}}}
    set requests [scientificDatasetFilterRequests $state($w,dimensions) $state($w,filters) $state($w,separate)]
    if {[llength $ys]*[llength $requests]>16} {error {Select up to 16 visible traces at once.}}
    return [list $state($w,x) $ys $requests]
}
proc ::GX::scientificDatasetViewerPlot {w} {
    variable ::GX::DatasetViewer::state
    set epoch {}
    if {[catch {
        datasetViewerCheck $w;scientificDatasetViewerCancel $w
        set epoch $state($w,epoch)
        if {$state($w,source) ne {}} {curveSourceClose $state($w,source);set state($w,source) {}}
        set state($w,plottedRequest) [scientificDatasetViewerSelection $w]
        lassign $state($w,plottedRequest) x ys requests
        set state($w,coordinateContext) [datasetCoordinateRead $::GX::currentSession $state($w,id)]
        scientificDatasetCoordinateOverlay $state($w,coordinateContext) $ys
        set state($w,queue) {};set state($w,series) {}
        foreach filters $requests {foreach y $ys {lappend state($w,queue) [list $y $filters]}}
        scientificDatasetViewerRetain $w {Previous render — loading selected sources}
        scientificDatasetViewerNext $w
    } message]} {if {[info exists state($w,id)] && ($epoch eq {} || $state($w,epoch)==$epoch)} {set state($w,status) $message}}
}
proc ::GX::scientificDatasetViewerNext {w} {
    variable ::GX::DatasetViewer::state
    if {![llength $state($w,queue)]} {scientificDatasetViewerFit $w;return}
    scientificDatasetViewerRetain $w {Previous render — loading selected source}
    set state($w,status) {Loading selected canonical source. Cancel remains available.}
    lassign [lindex $state($w,queue) 0] y filters;set state($w,queue) [lrange $state($w,queue) 1 end]
    set state($w,loading) [list $y $filters]
    set request [dict create dataset_id $state($w,id) x_variable_id [lindex $state($w,plottedRequest) 0] y_variable_id $y display_budget 4096]
    dict set request filters $filters
    if {[info exists state($w,ordering)] && $state($w,ordering) ne {}} {dict set request order_variable_id $state($w,ordering)}
    set epoch $state($w,epoch)
    set state($w,opening) 1
    try {
        set source [curveSourceOpen $::GX::currentSession $request [list ::GX::scientificDatasetOpeningProgress $w $epoch]]
    } finally {
        if {[info exists state($w,id)] && $state($w,epoch)==$epoch} {set state($w,opening) 0}
    }
    # Counting yields to ordinary Cancel, close and replacement requests.
    # A source returned after that boundary belongs to the abandoned request.
    if {![info exists state($w,id)] || $state($w,epoch)!=$epoch} {
        curveSourceClose $source
        return
    }
    set state($w,source) $source
    if {[catch {set state($w,job) [curveSourceDisplayAsync $source [list ::GX::scientificDatasetViewerReady $w] [list ::GX::scientificDatasetViewerProgress $w]]} message options]} {
        catch {curveSourceClose $source}
        if {[info exists state($w,id)] && $state($w,epoch)==$epoch} {set state($w,source) {}}
        return -options $options $message
    }
}
proc ::GX::scientificDatasetViewerReady {w receipt} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]} return
    set epoch $state($w,epoch)
    set state($w,job) {}
    if {[dict get $receipt status] ne {ok}} {
        set state($w,status) [datasetPublicationV2DictDefault $receipt message {Loading cancelled}]
        scientificDatasetViewerRetain $w $state($w,status)
        return
    }
    set source $state($w,source)
    if {[catch {
        datasetViewerCheck $w
        set sourceDescriptor [curveSourceDescribe $source]
        set display [dict get $receipt display]
        if {[datasetCoordinateRead $::GX::currentSession $state($w,id)] ne $state($w,coordinateContext)} {error {Coordinate settings changed during loading; select Plot again}}
        lassign $state($w,loading) y filters
        set display [scientificDatasetCoordinateDisplay $state($w,coordinateContext) [lindex $state($w,plottedRequest) 0] $y $display]
        set member [join $filters {; }]
        set series [concat $state($w,series) [list [dict create y $y member $member filters $filters display $display source_descriptor $sourceDescriptor]]]
        if {![scientificDatasetViewerAdopt $w $series $state($w,coordinateContext)]} {catch {curveSourceClose $source};return}
        set state($w,series) $series
        scientificDatasetViewerCoordinateLegend $w
        set state($w,status) "[scientificDatasetFilterMode $state($w,dimensions) $state($w,filters) $state($w,separate)] — [llength $series] trace(s); last trace: [dict get $display row_count] canonical rows, [llength [dict get $display points]] displayed points. Gaps retained; reduced: [dict get $display reduced]. Drag to Pan; wheel zooms."
        curveSourceClose $source;set state($w,source) {}
        scientificDatasetViewerNext $w
    } message]} {
        catch {curveSourceClose $source}
        if {[info exists state($w,id)] && $state($w,epoch)==$epoch} {
            if {$state($w,source) eq $source} {set state($w,source) {}}
            set state($w,status) $message
            scientificDatasetViewerRetain $w $message
        }
        return
    }
}

proc ::GX::scientificDatasetViewerPoint {w x y} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,plotCurrent)] || !$state($w,plotCurrent)} return
    if {[catch {datasetViewerCheck $w;set hit [::GX::PlotDatasetAPIv4::widgetHit $state($w,plotWidget) $x $y]} reason]} {set state($w,status) $reason;return}
    if {![dict get $hit hit] || [dict get $hit kind] ne {point} || ![dict exists $hit source_row_ordinal]} return
    set index 0
    foreach series $state($w,series) {
        if {[dict get $hit series_id] eq "trace_$index"} {
            set display [dict get $series display]
            set row [dict get $hit source_row_ordinal]
            set ordinal [lsearch -exact [dict get $display source_rows] $row]
            if {$ordinal<0} return
            set identity [dict get [dict get $series source_descriptor] row_identity_kind]
            set label [expr {$identity eq {dataset_row} ? {canonical row} : {transform view row}}]
            set state($w,status) "[dict get $series y] [dict get $series member] · $label [expr {$row+1}] · displayed X/Y: [lindex [dict get $display points] $ordinal] [dict get $display coordinate_presentation display_units] · canonical X/Y: [lindex [dict get $display canonical_points] $ordinal]"
            return
        }
        incr index
    }
}

proc ::GX::scientificDatasetOpeningProgress {w epoch receipt} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]||$state($w,epoch)!=$epoch} {error {Scientific source opening cancelled}}
    datasetViewerCheck $w
    set state($w,status) "Counting canonical rows: [dict get $receipt completed_rows]. Cancel remains available."
}
